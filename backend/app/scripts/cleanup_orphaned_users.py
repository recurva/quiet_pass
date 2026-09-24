"""Finds every Postgres User row whose Firebase Auth account no longer
exists — a ghost, left over from testing before account deletion was
fully robust (see app/api/deps.py's authenticate_token, whose
auth.repaired_orphaned_account self-heal fixes one of these the moment
its phone number is reused, but does nothing for a ghost that never
signs in again) — and removes it the exact same way a real account
deletion does: admin succession rebalanced first (see
membership_service.rebalance_admin_before_departure), any group left
with no members deleted outright, live Redis status cleared, and
member_left published to any group that's still around.

Safe to re-run any time: a clean database (no ghosts) just reports zero
found and does nothing. This is the actual fix for "make sure deletion
never leaves anything behind, no matter how much testing happens" — the
account-deletion endpoints themselves were already correct going
forward (see users.py's delete_current_user); this is for cleaning up
what existing bad state is already there, and for catching anything
that slips through in the future without needing a code change to do
it again.

Run as a one-off Cloud Run Job using the backend's own image (same
credentials, same VPC connector — no separate setup needed):

    gcloud run jobs create cleanup-orphaned-users \
      --image=$REGION-docker.pkg.dev/$PROJECT_ID/quietpass/backend:latest \
      --region=$REGION \
      --service-account=quietpass-runtime@$PROJECT_ID.iam.gserviceaccount.com \
      --set-cloudsql-instances=$PROJECT_ID:$REGION:quietpass-pg \
      --vpc-connector=quietpass-connector \
      --command=python \
      --args=-m,app.scripts.cleanup_orphaned_users
    gcloud run jobs execute cleanup-orphaned-users --wait
    gcloud run jobs delete cleanup-orphaned-users --quiet
"""

import asyncio
import json
import uuid

from firebase_admin import auth as firebase_auth
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.db.redis import get_redis_client
from app.db.session import AsyncSessionLocal
from app.models.group import Group
from app.models.membership import Membership
from app.models.user import User
from app.services import firebase_auth_admin_service
from app.services.membership_service import rebalance_admin_before_departure
from app.services.status_service import clear_status, group_channel

logger = get_logger(__name__)


def _is_ghost(firebase_uid: str) -> bool:
    app = firebase_auth_admin_service._get_app()
    if app is None:
        raise RuntimeError(
            "Firebase Auth admin credentials aren't configured in this "
            "environment — refusing to guess. This script needs to "
            "positively confirm a user is gone from Firebase before "
            "deleting its Postgres row, the same way delete_current_user "
            "does for a live account deletion."
        )
    try:
        firebase_auth.get_user(firebase_uid, app=app)
        return False
    except firebase_auth.UserNotFoundError:
        return True


async def _delete_orphan(db: AsyncSession, redis: Redis, user: User) -> None:
    result = await db.execute(select(Membership.group_id).where(Membership.user_id == user.id))
    group_ids = [row[0] for row in result.all()]

    groups_to_delete: list[uuid.UUID] = []
    for group_id in group_ids:
        should_delete_group, _promoted = await rebalance_admin_before_departure(
            db, group_id=group_id, departing_user_id=user.id
        )
        if should_delete_group:
            groups_to_delete.append(group_id)

    for group_id in groups_to_delete:
        group = await db.get(Group, group_id)
        if group is not None:
            await db.delete(group)

    user_id = user.id
    firebase_uid = user.firebase_uid
    await db.delete(user)
    await db.commit()

    still_active_group_ids = [gid for gid in group_ids if gid not in groups_to_delete]
    for group_id in still_active_group_ids:
        await clear_status(redis, group_id, user_id)

    for group_id in group_ids:
        payload = {"event": "member_left", "group_id": str(group_id), "user_id": str(user_id)}
        await redis.publish(group_channel(group_id), json.dumps(payload))

    logger.info(
        "cleanup.orphan_deleted",
        user_id=str(user_id),
        firebase_uid=firebase_uid,
        group_count=len(group_ids),
        groups_deleted=len(groups_to_delete),
    )


async def main() -> None:
    redis = get_redis_client()
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User))
        users = list(result.scalars().all())
        logger.info("cleanup.scan_started", total_users=len(users))

        orphans = [user for user in users if _is_ghost(user.firebase_uid)]
        logger.info(
            "cleanup.scan_complete", total_users=len(users), orphan_count=len(orphans)
        )

        for user in orphans:
            await _delete_orphan(db, redis, user)

    await redis.aclose()
    logger.info("cleanup.done", deleted=len(orphans))


if __name__ == "__main__":
    asyncio.run(main())
