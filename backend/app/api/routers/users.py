import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.group import Group
from app.models.membership import Membership
from app.models.user import User
from app.schemas.user import UserRead, UserUpdate
from app.services import firebase_auth_admin_service
from app.services.membership_service import rebalance_admin_before_departure
from app.services.status_service import clear_status, group_channel

logger = get_logger(__name__)
router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserRead)
async def read_current_user(current_user: User = Depends(get_current_user)) -> User:
    """Fetch-or-create: the caller is resolved (and provisioned on first
    sight) entirely inside get_current_user from the verified token.
    """
    return current_user


@router.patch("/me", response_model=UserRead)
async def update_current_user(
    payload: UserUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> User:
    """The only field a user can self-edit today: their display name. It
    starts out defaulted to their phone number (see get_current_user's
    first-sight provisioning) until they set a real one here, from
    onboarding or the profile screen.
    """
    current_user.display_name = payload.display_name
    await db.commit()
    await db.refresh(current_user)
    logger.info("user.display_name_updated", user_id=str(current_user.id))
    return current_user


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_current_user(
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> None:
    """Deletes the caller's account from both Firebase Auth and Postgres.

    Firebase first, since it's the external, less-reliable side — if it
    raises, nothing here has been committed yet (see below) so nothing
    ends up half-deleted and the caller can just retry.
    `delete_firebase_user` returning False (credentials unconfigured,
    e.g. local dev without the runtime service account) is not an error
    and doesn't block the Postgres deletion — only a genuine failure
    does.

    Every child row keyed off the User (memberships, reservations,
    chores, device tokens) is `ON DELETE CASCADE` at the database level
    (see the data model in README), so deleting the User row handles all
    of that automatically. What cascade can't do is the group-side
    business rule this locked client decision requires: a house is never
    left without an admin, and never left as an orphaned, member-less
    row either. That has to run *before* the cascade removes this user's
    own Membership rows, since it needs to inspect their role — see
    rebalance_admin_before_departure.
    """
    # Captured before anything is deleted, not derived from it: once the
    # Membership rows cascade-delete along with the User row, there's no
    # way to ask Postgres afterward which groups this person was in — the
    # whole point of publishing member_left is telling those exact
    # groups' already-open sessions to refetch their member list, same as
    # member_joined does for the opposite direction (see groups.py's
    # join_group).
    result = await db.execute(
        select(Membership.group_id).where(Membership.user_id == current_user.id)
    )
    group_ids = [row[0] for row in result.all()]

    groups_to_delete: list[uuid.UUID] = []
    for group_id in group_ids:
        should_delete_group, _promoted_user_id = await rebalance_admin_before_departure(
            db, group_id=group_id, departing_user_id=current_user.id
        )
        if should_delete_group:
            groups_to_delete.append(group_id)

    for group_id in groups_to_delete:
        group = await db.get(Group, group_id)
        if group is not None:
            await db.delete(group)

    try:
        await firebase_auth_admin_service.delete_firebase_user(current_user.firebase_uid)
    except Exception as exc:
        await db.rollback()
        logger.error("user.delete.firebase_failed", user_id=str(current_user.id), error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not delete your account. Try again.",
        ) from exc

    user_id = current_user.id
    await db.delete(current_user)
    await db.commit()

    # Redis never sees the cascade delete above — a departed member's
    # live status (Open to Chat especially, which has no TTL at all)
    # would otherwise sit there and keep showing up for the group's
    # remaining members indefinitely. Only relevant for a group that's
    # still around; a deleted group's statuses are simply never read
    # again by anyone.
    still_active_group_ids = [gid for gid in group_ids if gid not in groups_to_delete]
    for group_id in still_active_group_ids:
        await clear_status(redis, group_id, user_id)

    for group_id in group_ids:
        payload = {"event": "member_left", "group_id": str(group_id), "user_id": str(user_id)}
        await redis.publish(group_channel(group_id), json.dumps(payload))

    logger.info(
        "user.deleted",
        user_id=str(user_id),
        group_count=len(group_ids),
        groups_deleted=len(groups_to_delete),
    )


@router.get("/{user_id}", response_model=UserRead)
async def get_user(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: User = Depends(get_current_user),
) -> User:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    return user
