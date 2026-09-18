"""Sends FCM push notifications. Unlike app/core/firebase.py (which verifies
ID tokens with no credentials at all), sending push has no credential-free
path — it needs a real service account with the firebase.messaging scope.

Three ways to get there, tried in order (see Settings.fcm_impersonate_service_account
et al. in core/config.py for the full precedence/rationale):
  1. A downloaded key file/JSON.
  2. Impersonating a service account via Application Default Credentials —
     no key file at all, just `gcloud auth application-default login` plus
     Service Account Token Creator on the target.
  3. Neither configured: every send below no-ops with a warning log instead
     of raising — a nudge still reaches everyone over the WebSocket; it
     just won't reach a backgrounded/locked device until push credentials
     exist.
"""

import asyncio
import json
from dataclasses import dataclass, field

import firebase_admin
import google.auth
from firebase_admin import credentials, messaging
from google.auth import impersonated_credentials

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)

_app: firebase_admin.App | None = None
_unconfigured = False

_FCM_SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]


@dataclass
class PushSendResult:
    sent: int = 0
    failed: int = 0
    invalid_tokens: list[str] = field(default_factory=list)


class _GoogleAuthCredential(credentials.Base):
    """Adapts a plain google-auth Credentials object (e.g. impersonated
    credentials, which have no key file at all) to what
    firebase_admin.initialize_app expects. firebase_admin.credentials only
    ships a Certificate (key file) and ApplicationDefault (unimpersonated)
    wrapper; neither fits "ADC, but impersonating someone else."
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
        target_scopes=_FCM_SCOPES,
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
        _app = firebase_admin.get_app("fcm")
        return _app
    except ValueError:
        pass  # not yet initialized

    try:
        if settings.firebase_service_account_json:
            cred = credentials.Certificate(json.loads(settings.firebase_service_account_json))
        elif settings.firebase_service_account_path:
            cred = credentials.Certificate(settings.firebase_service_account_path)
        elif settings.fcm_use_runtime_service_account:
            # Cloud Run (and GCE/GKE workload identity): ADC resolves to the
            # revision's own runtime service account via the metadata
            # server, so this needs no key and no impersonation hop — just
            # that service account holding roles/firebasecloudmessaging.admin
            # (see README's Push section for the exact grant command).
            cred = credentials.ApplicationDefault()
            logger.info("push.using_runtime_service_account")
        elif settings.fcm_impersonate_service_account:
            cred = _build_impersonated_credential()
            logger.info(
                "push.using_impersonated_credentials",
                target=settings.fcm_impersonate_service_account,
            )
        else:
            _unconfigured = True
            logger.warning("push.not_configured")
            return None
    except Exception as exc:
        # ADC missing, impersonation target unreachable, malformed key JSON,
        # etc. — fail closed to the same no-op path, not a crash.
        _unconfigured = True
        logger.error("push.credential_init_failed", error=str(exc))
        return None

    # A service-account JSON file carries its own project id; bare
    # impersonated credentials don't, so firebase_admin can't infer it and
    # needs it passed explicitly.
    _app = firebase_admin.initialize_app(
        cred, options={"projectId": settings.firebase_project_id}, name="fcm"
    )
    return _app


async def send_to_tokens(
    tokens: list[str], title: str, body: str, data: dict[str, str]
) -> PushSendResult:
    """Send one notification to many device tokens. Never raises — a push
    failure (missing credentials, an individual dead token, a full outage)
    is logged and returned, never blocks the caller (nudge creation still
    succeeds over the WebSocket regardless).
    """
    if not tokens:
        return PushSendResult()

    app = _get_app()
    if app is None:
        return PushSendResult(failed=len(tokens))

    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data=data,
        tokens=tokens,
    )

    try:
        # firebase_admin's messaging client is synchronous; keep it off the
        # event loop.
        response = await asyncio.to_thread(
            messaging.send_each_for_multicast, message, app=app
        )
    except Exception as exc:
        logger.error("push.send_failed", error=str(exc), token_count=len(tokens))
        return PushSendResult(failed=len(tokens))

    invalid_tokens: list[str] = []
    for token, individual in zip(tokens, response.responses):
        if individual.success:
            continue
        code = getattr(individual.exception, "code", None)
        if code in ("NOT_FOUND", "UNREGISTERED", "INVALID_ARGUMENT"):
            invalid_tokens.append(token)
        logger.warning(
            "push.token_failed",
            token_suffix=token[-8:],
            error=str(individual.exception),
        )

    logger.info(
        "push.sent",
        requested=len(tokens),
        success=response.success_count,
        failure=response.failure_count,
    )
    return PushSendResult(
        sent=response.success_count,
        failed=response.failure_count,
        invalid_tokens=invalid_tokens,
    )
