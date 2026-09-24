import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_membership
from app.api.deps import get_current_user, get_db
from app.core.logging import get_logger
from app.models.chore import Chore
from app.models.reservation import Reservation
from app.models.user import User
from app.schemas.chore import ChoreRead

logger = get_logger(__name__)
router = APIRouter(tags=["chores"])


@router.get("/groups/{group_id}/chores", response_model=list[ChoreRead])
async def list_group_chores(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[Chore]:
    """Every chore in the group, whoever it's assigned to — like
    reservations, chores aren't anonymous.
    """
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    result = await db.execute(
        select(Chore)
        .join(Reservation, Reservation.id == Chore.reservation_id)
        .where(Reservation.group_id == group_id)
        .order_by(Chore.due_at)
        .limit(1000)
    )
    return list(result.scalars().all())


@router.patch("/chores/{chore_id}/done", response_model=ChoreRead)
async def mark_chore_done(
    chore_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Chore:
    chore = await db.get(Chore, chore_id)
    if chore is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chore not found.")
    if chore.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Only the assignee can complete this."
        )

    # The assignee check above isn't enough on its own: the user row
    # itself isn't touched by DELETE /memberships/{id} (only account
    # deletion removes it), so someone removed from this group after
    # being assigned a chore would otherwise still be able to complete
    # it — matching every other endpoint's require_membership gate.
    reservation = await db.get(Reservation, chore.reservation_id)
    if reservation is not None:
        await require_membership(db, group_id=reservation.group_id, user_id=current_user.id)

    chore.done = True
    await db.commit()
    await db.refresh(chore)
    logger.info("chore.completed", chore_id=str(chore_id), user_id=str(current_user.id))
    return chore
