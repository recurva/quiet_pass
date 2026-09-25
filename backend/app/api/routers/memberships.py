import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_admin
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.device_token import DeviceToken
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.user import User
from app.schemas.membership import MembershipRead
from app.services import push_service
from app.services.membership_service import rebalance_admin_before_departure
from app.services.status_service import clear_status, publish_group_event

logger = get_logger(__name__)
router = APIRouter(prefix="/memberships", tags=["memberships"])


@router.patch("/{membership_id}/role", response_model=MembershipRead)
async def update_membership_role(
    membership_id: uuid.UUID,
    role: MembershipRole,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> Membership:
    """Promote or demote a member. Only an admin of the same group may do
    this. A group supports multiple admins, so this only ever changes one
    row's role — except demoting the group's *last* admin, which is
    rejected outright (see below): the same "never left without an
    admin" rule rebalance_admin_before_departure enforces on departure
    applies here too, since a self-demotion is otherwise a single,
    unguarded request that bypasses it entirely.
    """
    membership = await db.get(Membership, membership_id)
    if membership is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Membership not found."
        )

    await require_admin(db, group_id=membership.group_id, user_id=current_user.id)

    if membership.role == MembershipRole.ADMIN and role != MembershipRole.ADMIN:
        # Locks the group's membership rows so two concurrent demotions
        # (or a demotion racing a departure) can't both see "someone else
        # is still admin" and both proceed — same reasoning as
        # rebalance_admin_before_departure's own lock.
        other_admins_result = await db.execute(
            select(Membership.id)
            .where(
                Membership.group_id == membership.group_id,
                Membership.role == MembershipRole.ADMIN,
                Membership.id != membership.id,
            )
            .with_for_update()
        )
        if other_admins_result.first() is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Promote another member to admin first — a house can't be left without one.",
            )

    membership.role = role
    await db.commit()
    await db.refresh(membership)

    # Same refetch-the-member-list mechanism as member_joined/member_left
    # (see groups.py's join_group) — a role change is exactly the kind of
    # thing an already-open session on another member's device has no
    # other way to learn about.
    payload = {
        "event": "member_role_changed",
        "group_id": str(membership.group_id),
        "user_id": str(membership.user_id),
    }
    await publish_group_event(redis, membership.group_id, payload)
    logger.info("membership.role_updated", membership_id=str(membership_id), role=role.value)
    return membership


@router.delete("/{membership_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_membership(
    membership_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> None:
    """A member may remove themselves (leave); removing someone else
    requires being an admin of the same group.

    Same locked client decision as account deletion (see
    rebalance_admin_before_departure): a house is never left without an
    admin, and never left orphaned with no members at all either.
    """
    membership = await db.get(Membership, membership_id)
    if membership is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Membership not found."
        )

    was_kicked = membership.user_id != current_user.id
    if was_kicked:
        await require_admin(db, group_id=membership.group_id, user_id=current_user.id)

    group_id = membership.group_id
    departed_user_id = membership.user_id

    # Only needed for the kicked-push body below, and the group row is
    # never touched in that branch (removing someone else always leaves
    # at least the admin who did the removing) — safe to read now,
    # before anything here is deleted.
    group = await db.get(Group, group_id) if was_kicked else None
    group_name = group.name if group is not None else None

    should_delete_group, _promoted_user_id = await rebalance_admin_before_departure(
        db, group_id=group_id, departing_user_id=departed_user_id
    )

    await db.delete(membership)

    if should_delete_group:
        group_to_delete = await db.get(Group, group_id)
        if group_to_delete is not None:
            await db.delete(group_to_delete)

    await db.commit()

    if not should_delete_group:
        await clear_status(redis, group_id, departed_user_id)

    # "kicked" distinguishes this from a voluntary leave for whichever
    # client happens to be the departed user's own — see
    # group_status_client.dart's handling. Every *other* member's client
    # only ever cares that the member list changed either way.
    payload = {
        "event": "member_left",
        "group_id": str(group_id),
        "user_id": str(departed_user_id),
        "kicked": was_kicked,
    }
    await publish_group_event(redis, group_id, payload)
    logger.info(
        "group.member_left",
        group_id=str(group_id),
        user_id=str(departed_user_id),
        group_deleted=should_delete_group,
        kicked=was_kicked,
    )

    # Best-effort, same as every other push send in this app (nudges) —
    # a failure here must never fail the removal itself, which has
    # already committed by this point regardless.
    if was_kicked and group_name is not None:
        tokens_result = await db.execute(
            select(DeviceToken.token).where(DeviceToken.user_id == departed_user_id)
        )
        tokens = [row[0] for row in tokens_result.all()]
        if tokens:
            await push_service.send_to_tokens(
                tokens,
                title="QuietPass",
                body=f"You've been removed from {group_name}.",
                data={"event": "member_removed", "group_id": str(group_id)},
            )
