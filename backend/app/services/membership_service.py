"""Shared logic for what happens on the group side when a member departs —
either by leaving directly (DELETE /memberships/{id}) or by deleting their
whole account (DELETE /users/me). Both call sites need the exact same
rule, so it lives here once rather than being duplicated.

Locked client decision: a house is never left without an admin. If the
departing member was its last admin, the longest-standing remaining
member (earliest joined_at) is auto-promoted. If the departing member was
the group's only member at all, the house itself is deleted rather than
left as an orphaned, member-less row — ON DELETE CASCADE on spaces/
reservations/chores/memberships (see the data model in README) then
cleans up everything under it.
"""

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.models.membership import Membership, MembershipRole

logger = get_logger(__name__)


async def rebalance_admin_before_departure(
    db: AsyncSession, *, group_id: uuid.UUID, departing_user_id: uuid.UUID
) -> tuple[bool, uuid.UUID | None]:
    """Call this before removing (or letting cascade remove) the departing
    member's own Membership row — it still needs to inspect that row's
    role. Doesn't touch the departing row itself and doesn't commit;
    caller does both as part of whatever else it's doing.

    Returns (group_should_be_deleted, promoted_user_id):
    - group_should_be_deleted is True when nobody else is left in the
      group at all.
    - promoted_user_id is set only when the departing member was the
      group's last admin — the caller doesn't need to do anything else
      with it (the promotion is already applied here); it's returned
      only for logging/event purposes.
    """
    result = await db.execute(
        select(Membership)
        .where(Membership.group_id == group_id, Membership.user_id != departing_user_id)
        .order_by(Membership.joined_at.asc())
    )
    remaining = list(result.scalars().all())

    if not remaining:
        return True, None

    departing_result = await db.execute(
        select(Membership.role).where(
            Membership.group_id == group_id, Membership.user_id == departing_user_id
        )
    )
    departing_role = departing_result.scalar_one_or_none()
    if departing_role != MembershipRole.ADMIN:
        return False, None

    if any(m.role == MembershipRole.ADMIN for m in remaining):
        return False, None

    successor = remaining[0]
    successor.role = MembershipRole.ADMIN
    logger.info(
        "group.admin_promoted",
        group_id=str(group_id),
        promoted_user_id=str(successor.user_id),
        departed_user_id=str(departing_user_id),
    )
    return False, successor.user_id
