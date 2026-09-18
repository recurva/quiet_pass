from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "QuietPass API"
    environment: str = "local"
    debug: bool = True
    log_level: str = "INFO"

    database_url: str = "postgresql+asyncpg://quietpass:quietpass@localhost:5433/quietpass"
    redis_url: str = "redis://localhost:6379/0"

    cors_origins: list[str] = ["http://localhost:3000"]

    # Firebase project id: used to verify the `aud`/`iss` claims on phone-auth
    # ID tokens. Not a secret (it's the same id baked into the Flutter app's
    # firebase_options.dart).
    firebase_project_id: str = "quietpass-app"

    # Quiet-pulse spam limits (presets are unlimited by design — they're
    # one-off factual events, not something a housemate would spam).
    quiet_pulse_cooldown_seconds: int = 900  # 15 min between one sender's pulses
    quiet_pulse_daily_cap: int = 6  # pulses per group per UTC day

    # FCM push send credentials. Unlike token verification (credential-free,
    # see core/firebase.py), *sending* push requires a real service account
    # — there's no public-cert workaround for this direction. Tried in this
    # order; if none are set, push sending no-ops with a warning log rather
    # than failing nudge creation:
    #   1. A downloaded key (FIREBASE_SERVICE_ACCOUNT_JSON / _PATH) — never
    #      commit the key itself.
    #   2. Impersonating FCM_IMPERSONATE_SERVICE_ACCOUNT via Application
    #      Default Credentials (see push_service.py) — no key file needed,
    #      just `gcloud auth application-default login` plus Service
    #      Account Token Creator on the target. Fine for local dev; in
    #      production the backend should run *as* that service account
    #      directly (Cloud Run/GCE/GKE workload identity) instead of
    #      impersonating from a developer's own login.
    firebase_service_account_path: str | None = None
    firebase_service_account_json: str | None = None
    fcm_impersonate_service_account: str | None = None

    # Production path (Cloud Run/GCE/GKE workload identity): the process is
    # already *running as* the target service account, so Application
    # Default Credentials resolve to it directly — no key file, no
    # impersonation hop. Explicit opt-in flag rather than an automatic
    # fallback, so a local dev machine with `gcloud auth application-default
    # login` (which yields *user* credentials, not a service account) never
    # silently takes this path and fails in a confusing way.
    fcm_use_runtime_service_account: bool = False

    # Reservations: booking rules for the base layer (no recurring bookings
    # or emergency override yet).
    reservation_buffer_minutes: int = 15  # gap required between bookings on the same space
    reservation_max_advance_days: int = 7  # how far ahead a booking can be made


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
