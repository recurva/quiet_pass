import secrets
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_membership
from app.api.deps import get_current_user, get_db
from app.core.logging import get_logger
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.user import User
from app.schemas.group import GroupCreate, GroupJoin, GroupRead
from app.schemas.membership import MembershipRead
from app.services.reservation_service import seed_default_spaces

logger = get_logger(__name__)
router = APIRouter(prefix="/groups", tags=["groups"])


def _generate_invite_code() -> str:
    return secrets.token_urlsafe(6)


@router.post("", response_model=GroupRead, status_code=status.HTTP_201_CREATED)
async def create_group(
    payload: GroupCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Group:
    """Create a group and make the caller its first admin."""
    group = Group(name=payload.name, invite_code=_generate_invite_code())
    db.add(group)
    try:
        await db.flush()
        db.add(
            Membership(user_id=current_user.id, group_id=group.id, role=MembershipRole.ADMIN)
        )
        await seed_default_spaces(db, group.id)
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        logger.warning("group.create.conflict", name=payload.name)
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Could not create group."
        ) from exc

    await db.refresh(group)
    return group


@router.get("/mine", response_model=list[GroupRead])
async def list_my_groups(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[Group]:
    result = await db.execute(
        select(Group)
        .join(Membership, Membership.group_id == Group.id)
        .where(Membership.user_id == current_user.id)
    )
    return list(result.scalars().all())


@router.post("/join", response_model=MembershipRead, status_code=status.HTTP_201_CREATED)
async def join_group(
    payload: GroupJoin,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Membership:
    """Join a group as a plain member via its invite code."""
    result = await db.execute(select(Group).where(Group.invite_code == payload.invite_code))
    group = result.scalar_one_or_none()
    if group is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid invite code.")

    membership = Membership(user_id=current_user.id, group_id=group.id, role=MembershipRole.MEMBER)
    db.add(membership)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Already a member of this group."
        ) from exc

    await db.refresh(membership)
    return membership


@router.get("/{group_id}", response_model=GroupRead)
async def get_group(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Group:
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    group = await db.get(Group, group_id)
    if group is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found.")
    return group


@router.get("/{group_id}/members", response_model=list[MembershipRead])
async def list_group_members(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[Membership]:
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    result = await db.execute(select(Membership).where(Membership.group_id == group_id))
    return list(result.scalars().all())
