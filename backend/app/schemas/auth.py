from pydantic import BaseModel, Field, field_validator

from app.schemas.user import DISPLAY_NAME_MAX_LENGTH, _LETTERS_AND_SPACES_ONLY, UserRead


class SignInRequest(BaseModel):
    # Present when the client came through the Sign Up screen; absent for
    # Sign In. Only ever used if this turns out to be a genuinely new
    # user — see authenticate_token's docstring for why an existing
    # user's name is never touched regardless of what's sent here.
    display_name: str | None = Field(default=None, max_length=DISPLAY_NAME_MAX_LENGTH)

    @field_validator("display_name")
    @classmethod
    def _strip_and_reject_blank(cls, value: str | None) -> str | None:
        # None (Sign In, no name entered) passes straight through — only
        # a *supplied* name is validated. A whitespace-only string is
        # normalized to None rather than rejected outright: authenticate_token
        # already treats a missing name as "let the phone number stand in
        # until the profile screen sets a real one," which is exactly the
        # right fallback for this case too. A non-blank name still has to
        # pass the same letters-and-spaces rule as UserUpdate — the
        # client already enforces this before ever calling sendCode, this
        # is only the defense-in-depth backstop for a bypassed client.
        if value is None:
            return None
        stripped = value.strip()
        if not stripped:
            return None
        if not _LETTERS_AND_SPACES_ONLY.match(stripped):
            raise ValueError("Name can only contain letters and spaces.")
        return stripped


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
