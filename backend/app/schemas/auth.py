from pydantic import BaseModel

from app.schemas.user import UserRead


class SignInRequest(BaseModel):
    # Present when the client came through the Sign Up screen; absent for
    # Sign In. Only ever used if this turns out to be a genuinely new
    # user — see authenticate_token's docstring for why an existing
    # user's name is never touched regardless of what's sent here.
    display_name: str | None = None


class SignInResponse(BaseModel):
    user: UserRead
    # True only when this call is what provisioned the user row. The
    # client uses this to decide whether a name still needs capturing
    # (new user, no display_name supplied) or whether to show "you
    # already have an account" (existing user, but the caller came from
    # the Sign Up screen and did supply one).
    is_new: bool


class PhoneExistsResponse(BaseModel):
    exists: bool
