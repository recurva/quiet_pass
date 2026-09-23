"""Shared FastAPI dependencies: DB session, Redis client, and the
Firebase-token-authenticated caller.
"""

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError, NoResultFound
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
        # Two different races land here, and only one of them means "the
        # row we want already exists":
        #
        # 1. Lost a race with another request provisioning the exact same
        #    firebase_uid — re-querying by firebase_uid finds it, still
        #    "new" from this call's perspective (the row didn't exist when
        #    we looked).
        # 2. This token's phone_number has since been claimed by a
        #    *different* firebase_uid. This happens for a token minted
        #    before an account was deleted and then re-signed-up with the
        #    same number: the JWT itself is still cryptographically valid
        #    (Firebase ID tokens don't self-invalidate on account
        #    deletion, and this hand-rolled verification never calls out
        #    to check revocation), so it decodes fine here, but the
        #    account it names is gone and its phone number now belongs to
        #    someone else. Re-querying by firebase_uid finds *nothing* in
        #    this case — there's no row to return, so this has to be
        #    treated as what it actually is: a token for an account that
        #    no longer exists, not a successful "new user" race.
        await db.rollback()
        result = await db.execute(select(User).where(User.firebase_uid == firebase_uid))
        try:
            user = result.scalar_one()
        except NoResultFound as exc:
            # Self-healing, not just error reporting: as long as this
            # firebase_uid's Firebase Auth account still exists, Firebase
            # phone-auth will keep re-authenticating this same phone
            # number to it forever — it never mints a new uid for a
            # number that already has a live Firebase user, even though
            # that user is a dead end on the Postgres side. Without
            # deleting it here, this phone number would be permanently
            # stuck: every future sign-in attempt hits this exact branch
            # again. Best-effort — if this fails too, at least the
            # current request still reports the real problem instead of
            # masking it with a secondary error.
            logger.warning("auth.token_for_deleted_account", firebase_uid=firebase_uid)
            try:
                from app.services import firebase_auth_admin_service

                await firebase_auth_admin_service.delete_firebase_user(firebase_uid)
            except Exception as cleanup_exc:
                logger.error(
                    "auth.ghost_firebase_user_cleanup_failed",
                    firebase_uid=firebase_uid,
                    error=str(cleanup_exc),
                )
            raise TokenInvalidError(
                "This account no longer exists. Please sign in again."
            ) from exc
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
