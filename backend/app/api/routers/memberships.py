import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_admin
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.user import User
from app.schemas.membership import MembershipRead
from app.services.membership_service import rebalance_admin_before_departure
from app.services.status_service import clear_status, group_channel

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
    row's role.
    """
    membership = await db.get(Membership, membership_id)
    if membership is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Membership not found."
        )

    await require_admin(db, group_id=membership.group_id, user_id=current_user.id)

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
    await redis.publish(group_channel(membership.group_id), json.dumps(payload))
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

    if membership.user_id != current_user.id:
        await require_admin(db, group_id=membership.group_id, user_id=current_user.id)

    group_id = membership.group_id
    departed_user_id = membership.user_id

    should_delete_group, _promoted_user_id = await rebalance_admin_before_departure(
        db, group_id=group_id, departing_user_id=departed_user_id
    )

    await db.delete(membership)

    if should_delete_group:
        group = await db.get(Group, group_id)
        if group is not None:
            await db.delete(group)

    await db.commit()

    if not should_delete_group:
        await clear_status(redis, group_id, departed_user_id)

    payload = {
        "event": "member_left",
        "group_id": str(group_id),
        "user_id": str(departed_user_id),
    }
    await redis.publish(group_channel(group_id), json.dumps(payload))
    logger.info(
        "group.member_left",
        group_id=str(group_id),
        user_id=str(departed_user_id),
        group_deleted=should_delete_group,
    )
