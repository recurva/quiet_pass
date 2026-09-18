import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_admin
from app.api.deps import get_current_user, get_db
from app.core.logging import get_logger
from app.models.membership import Membership, MembershipRole
from app.models.user import User
from app.schemas.membership import MembershipRead

logger = get_logger(__name__)
router = APIRouter(prefix="/memberships", tags=["memberships"])


@router.patch("/{membership_id}/role", response_model=MembershipRead)
async def update_membership_role(
    membership_id: uuid.UUID,
    role: MembershipRole,
    db: AsyncSession = Depends(get_db),
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
    logger.info("membership.role_updated", membership_id=str(membership_id), role=role.value)
    return membership


@router.delete("/{membership_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_membership(
    membership_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """A member may remove themselves (leave); removing someone else
    requires being an admin of the same group.
    """
    membership = await db.get(Membership, membership_id)
    if membership is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Membership not found."
        )

    if membership.user_id != current_user.id:
        await require_admin(db, group_id=membership.group_id, user_id=current_user.id)

    await db.delete(membership)
    await db.commit()
