"""Verifies Firebase phone-auth ID tokens without the Admin SDK.

This project's Firebase service account can't be issued a key (blocked by
an org policy on the Workspace-managed project), so the usual
`firebase_admin.auth.verify_id_token` path isn't available. Firebase
documents exactly this situation and an alternative: verify the ID token's
JWT by hand against Google's rotating public certs, checking signature,
issuer, audience, and expiry yourself.
https://firebase.google.com/docs/auth/admin/verify-id-tokens#verify_id_tokens_using_a_third-party_jwt_library

This needs no credentials at all — the certs endpoint is public.
"""

import re
import time
from typing import Any

import httpx
import jwt
from cryptography import x509
from cryptography.hazmat.backends import default_backend

from app.core.config import settings

_CERTS_URL = (
    "https://www.googleapis.com/robot/v1/metadata/x509/"
    "securetoken@system.gserviceaccount.com"
)


class TokenVerificationError(Exception):
    """Base for all ID-token verification failures."""


class TokenExpiredError(TokenVerificationError):
    pass


class TokenInvalidError(TokenVerificationError):
    pass


_cached_certs: dict[str, str] = {}
_cached_certs_expiry: float = 0.0


async def _fetch_google_public_certs() -> dict[str, str]:
    global _cached_certs, _cached_certs_expiry
    if _cached_certs and time.time() < _cached_certs_expiry:
        return _cached_certs

    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(_CERTS_URL)
        response.raise_for_status()

    max_age = 3600
    match = re.search(r"max-age=(\d+)", response.headers.get("cache-control", ""))
    if match:
        max_age = int(match.group(1))

    _cached_certs = response.json()
    _cached_certs_expiry = time.time() + max_age
    return _cached_certs


async def verify_id_token(token: str) -> dict[str, Any]:
    """Verify a Firebase phone-auth ID token's RS256 signature, issuer,
    audience, and expiry. Returns the decoded claims (with `uid` aliased
    from `sub`) on success.
    """
    try:
        header = jwt.get_unverified_header(token)
    except jwt.DecodeError as exc:
        raise TokenInvalidError("Malformed token.") from exc

    kid = header.get("kid")
    if not kid:
        raise TokenInvalidError("Token header missing key id.")

    certs = await _fetch_google_public_certs()
    cert_pem = certs.get(kid)
    if cert_pem is None:
        # Certs may have rotated since we last cached them; refresh once.
        global _cached_certs_expiry
        _cached_certs_expiry = 0.0
        certs = await _fetch_google_public_certs()
        cert_pem = certs.get(kid)
        if cert_pem is None:
            raise TokenInvalidError("Unknown signing key.")

    public_key = x509.load_pem_x509_certificate(
        cert_pem.encode(), default_backend()
    ).public_key()

    project_id = settings.firebase_project_id
    try:
        decoded = jwt.decode(
            token,
            key=public_key,
            algorithms=["RS256"],
            audience=project_id,
            issuer=f"https://securetoken.google.com/{project_id}",
            # A few seconds of clock drift between this server and Google's
            # is normal and expected, not a sign of a forged/replayed token.
            # Without this, a clock even slightly behind rejects every
            # freshly-issued token as "not yet valid" (iat in the future).
            leeway=60,
        )
    except jwt.ExpiredSignatureError as exc:
        raise TokenExpiredError("Token expired.") from exc
    except jwt.InvalidTokenError as exc:
        raise TokenInvalidError(str(exc)) from exc

    subject = decoded.get("sub")
    if not subject or not isinstance(subject, str):
        raise TokenInvalidError("Token has no subject claim.")

    decoded["uid"] = subject
    return decoded
