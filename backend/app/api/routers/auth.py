from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import authenticate_token, get_db
from app.core.firebase import TokenExpiredError, TokenInvalidError
from app.core.logging import get_logger
from app.models.user import User
from app.schemas.auth import PhoneExistsResponse, SignInRequest, SignInResponse
from app.schemas.user import UserRead

logger = get_logger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])

_UNAUTHORIZED_HEADERS = {"WWW-Authenticate": "Bearer"}


@router.get("/phone-exists", response_model=PhoneExistsResponse)
async def phone_exists(
    phone_number: str = Query(...),
    db: AsyncSession = Depends(get_db),
) -> PhoneExistsResponse:
    """Lets the Sign Up screen reject an already-registered number at
    "Send code" time, before spending an OTP on it, rather than silently
    signing the person in after they've gone through verification — see
    SignUpPage's _submit. Unauthenticated by design: it runs before any
    token exists yet. It's a pre-flight nicety only — a number that
    changes hands between this check and OTP completion is still handled
    correctly by POST /auth/sign-in's own is_new logic either way.
    """
    result = await db.execute(select(User.id).where(User.phone_number == phone_number))
    return PhoneExistsResponse(exists=result.scalar_one_or_none() is not None)


@router.post("/sign-in", response_model=SignInResponse)
async def sign_in(
    payload: SignInRequest,
    authorization: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> SignInResponse:
    """The one call the client makes right after Firebase OTP verification
    succeeds, for both the Sign In and Sign Up screens alike — Firebase
    ties the account to the phone number regardless of which screen was
    used, so this is where new-vs-returning is actually decided, not the
    client (see authenticate_token's docstring).

    Doesn't reuse get_current_user as a dependency because that resolves
    (and silently auto-provisions) a user with no way to also pass along
    a caller-supplied display_name or learn whether the row was just
    created — both of which this endpoint needs.
    """
    if authorization is None or not authorization.startswith("Bearer "):
        logger.warning("auth.sign_in.missing_token")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token.",
            headers=_UNAUTHORIZED_HEADERS,
        )

    token = authorization.removeprefix("Bearer ").strip()

    try:
        user, is_new = await authenticate_token(db, token, display_name=payload.display_name)
    except TokenExpiredError as exc:
        logger.warning("auth.sign_in.token_expired")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired.",
            headers=_UNAUTHORIZED_HEADERS,
        ) from exc
    except TokenInvalidError as exc:
        logger.warning("auth.sign_in.token_invalid", error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token.",
            headers=_UNAUTHORIZED_HEADERS,
        ) from exc
    except Exception as exc:
        logger.error("auth.sign_in.verification_failed", error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not verify token.",
            headers=_UNAUTHORIZED_HEADERS,
        ) from exc

    logger.info("auth.sign_in", user_id=str(user.id), is_new=is_new)
    return SignInResponse(user=UserRead.model_validate(user), is_new=is_new)
