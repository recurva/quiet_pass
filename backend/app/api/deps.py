"""Shared FastAPI dependencies: DB session, Redis client, and the
Firebase-token-authenticated caller.
"""

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.firebase import TokenExpiredError, TokenInvalidError, verify_id_token
from app.core.logging import get_logger
from app.db.redis import get_redis
from app.db.session import get_db
from app.models.user import User

logger = get_logger(__name__)

_UNAUTHORIZED_HEADERS = {"WWW-Authenticate": "Bearer"}


async def authenticate_token(
    db: AsyncSession, token: str, display_name: str | None = None
) -> tuple[User, bool]:
    """Verify a Firebase ID token and resolve (or, on first sight,
    provision) the matching User row. Shared by the HTTP Bearer-header path
    (`get_current_user`) and the WebSocket query-param path, since browsers
    can't set custom headers on a WebSocket handshake.

    Returns `(user, is_new)` — `is_new` is True only when this call is what
    provisioned the row (the initial lookup found nothing), never when an
    existing user was resolved. This is the actual source of truth for
    new-vs-returning (see `POST /auth/sign-in`), not which screen the
    client happened to use — Firebase ties the account to the phone
    number regardless of whether the person tapped "Sign in" or "Sign up".

    `display_name` is used *only* on the provisioning path, and only if
    the caller supplied one — an existing user's name is never touched
    here under any circumstances, deliberately: this is what makes a
    returning user's sign-in immune to a stray name being sent along with
    it (e.g. someone who typed a name into the Sign Up screen for a
    number that already has an account).

    Raises `TokenExpiredError` / `TokenInvalidError` on failure — callers
    decide how to turn that into a 401 or a close code.
    """
    decoded = await verify_id_token(token)

    firebase_uid = decoded["uid"]
    phone_number = decoded.get("phone_number")
    if not phone_number:
        logger.warning("auth.token_missing_phone", firebase_uid=firebase_uid)
        raise TokenInvalidError("Token has no verified phone number.")

    result = await db.execute(select(User).where(User.firebase_uid == firebase_uid))
    user = result.scalar_one_or_none()

    if user is not None:
        return user, False

    user = User(
        firebase_uid=firebase_uid,
        phone_number=phone_number,
        display_name=display_name or phone_number,
    )
    db.add(user)
    try:
        await db.commit()
    except IntegrityError:
        # Lost a race with another request provisioning the same user —
        # still "new" from this call's perspective (the row didn't exist
        # when we looked), whichever request's insert actually won.
        await db.rollback()
        result = await db.execute(select(User).where(User.firebase_uid == firebase_uid))
        user = result.scalar_one()
    else:
        await db.refresh(user)
        logger.info("auth.user_provisioned", user_id=str(user.id))

    return user, True


async def get_current_user(
    authorization: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Verify the `Authorization: Bearer <firebase-id-token>` header and
    resolve the caller, raising a structured-logged 401 on any failure.
    """
    if authorization is None or not authorization.startswith("Bearer "):
        logger.warning("auth.missing_token")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token.",
            headers=_UNAUTHORIZED_HEADERS,
        )

    token = authorization.removeprefix("Bearer ").strip()

    try:
        user, _ = await authenticate_token(db, token)
        return user
    except TokenExpiredError as exc:
        logger.warning("auth.token_expired")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired.",
            headers=_UNAUTHORIZED_HEADERS,
        ) from exc
    except TokenInvalidError as exc:
        logger.warning("auth.token_invalid", error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token.",
            headers=_UNAUTHORIZED_HEADERS,
        ) from exc
    except Exception as exc:
        # Covers cert-fetch/network failures and any other unexpected
        # verification error.
        logger.error("auth.verification_failed", error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not verify token.",
            headers=_UNAUTHORIZED_HEADERS,
        ) from exc


__all__ = ["get_db", "get_redis", "get_current_user", "authenticate_token"]
