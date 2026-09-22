"""Deletes a user from Firebase Authentication (account deletion, part of
DELETE /users/me). This is a *different* capability from both token
verification (app/core/firebase.py — credential-free, hand-rolled JWT
check) and FCM send (push_service.py — scoped to firebase.messaging only):
deleting an Auth user needs the identitytoolkit scope, which push's
narrowly-scoped credential doesn't carry and can't be reused for.

Same three-tier credential resolution as push_service.py, deliberately
kept as its own separately-scoped `firebase_admin` app rather than reusing
push_service's — a single named app can't hold two different scopes, and
keeping the capabilities apart means a bug or credential problem in one
never has any way to affect the other.
"""

import firebase_admin
import google.auth
from firebase_admin import auth as firebase_auth, credentials
from google.auth import impersonated_credentials

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)

_app: firebase_admin.App | None = None
_unconfigured = False

_IDENTITY_TOOLKIT_SCOPES = ["https://www.googleapis.com/auth/identitytoolkit"]


class _GoogleAuthCredential(credentials.Base):
    """See push_service.py's identical adapter — same reason: firebase_admin
    only ships Certificate/ApplicationDefault wrappers, neither of which
    fits "ADC, but a specific scope or impersonating someone else."
    """

    def __init__(self, google_credential: google.auth.credentials.Credentials):
        self._google_credential = google_credential

    def get_credential(self) -> google.auth.credentials.Credentials:
        return self._google_credential


def _build_impersonated_credential() -> credentials.Base:
    source_credentials, _ = google.auth.default()
    target_credentials = impersonated_credentials.Credentials(
        source_credentials=source_credentials,
        target_principal=settings.fcm_impersonate_service_account,
        target_scopes=_IDENTITY_TOOLKIT_SCOPES,
        lifetime=3600,
    )
    return _GoogleAuthCredential(target_credentials)


def _get_app() -> firebase_admin.App | None:
    global _app, _unconfigured
    if _app is not None:
        return _app
    if _unconfigured:
        return None

    try:
        _app = firebase_admin.get_app("auth_admin")
        return _app
    except ValueError:
        pass  # not yet initialized

    try:
        if settings.firebase_admin_use_runtime_service_account:
            # Cloud Run/GCE/GKE workload identity: ADC resolves to the
            # revision's own runtime service account directly — needs
            # roles/firebaseauth.admin granted to it (see README).
            cred = credentials.ApplicationDefault()
            logger.info("firebase_auth_admin.using_runtime_service_account")
        elif settings.fcm_impersonate_service_account:
            # Local-dev convenience, reusing the same target principal as
            # push's impersonation path — just requesting a different scope.
            cred = _build_impersonated_credential()
            logger.info(
                "firebase_auth_admin.using_impersonated_credentials",
                target=settings.fcm_impersonate_service_account,
            )
        else:
            _unconfigured = True
            logger.warning("firebase_auth_admin.not_configured")
            return None
    except Exception as exc:
        _unconfigured = True
        logger.error("firebase_auth_admin.credential_init_failed", error=str(exc))
        return None

    _app = firebase_admin.initialize_app(
        cred, options={"projectId": settings.firebase_project_id}, name="auth_admin"
    )
    return _app


async def delete_firebase_user(firebase_uid: str) -> bool:
    """Deletes the Firebase Auth account for `firebase_uid`. Returns True if
    the account is gone afterward (deleted now, or already didn't exist —
    both leave Firebase in the desired end state), False if credentials
    aren't configured. Raises on any other failure, since — unlike push,
    where a failure just means one notification doesn't arrive — a failed
    account deletion here should stop DELETE /users/me from also deleting
    the Postgres row, not fail silently and leave the two out of sync.
    """
    app = _get_app()
    if app is None:
        return False

    try:
        firebase_auth.delete_user(firebase_uid, app=app)
        logger.info("firebase_auth_admin.user_deleted", firebase_uid=firebase_uid)
    except firebase_auth.UserNotFoundError:
        logger.info("firebase_auth_admin.user_already_absent", firebase_uid=firebase_uid)

    return True
