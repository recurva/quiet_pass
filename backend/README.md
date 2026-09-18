# QuietPass backend

Step 2 of the build: FastAPI backend and data model. Postgres holds users,
groups, and memberships (durable). Redis holds live per-member status
(ephemeral, TTL-expiring, pub/sub on change).

## Layout

```
app/
  main.py              FastAPI app, middleware, error handlers, router wiring
  core/
    config.py          Settings from environment (.env)
    logging.py         structlog setup
  db/
    base.py            Shared SQLAlchemy declarative base
    session.py         Async engine + session factory
    redis.py           Async Redis client
  models/               SQLAlchemy models: User, Group, Membership, Space, Reservation, Chore
  schemas/              Pydantic request/response models
  api/
    deps.py            Shared dependencies: DB session, Redis client, get_current_user, authenticate_token
    authz.py           Group-scoped authorization (require_membership / require_admin)
    routers/           users, groups, memberships, status, nudges, device_tokens, spaces, chores, ws
  services/
    status_service.py      set_status / get_status / get_group_statuses (Redis)
    nudge_service.py       Neutral wording, cooldown/cap limits, publish (Redis) + push
    push_service.py        FCM send (needs a service account; no-ops without one)
    reservation_service.py Booking + the atomic conflict/buffer check (see Reservations, below)
    connection_manager.py  Per-worker bookkeeping for live WebSocket connections
alembic/                Migrations (async env.py)
docker-compose.yml      Local Postgres + Redis
```

## Data model

- **User**: id (UUID), firebase_uid (unique), phone_number (unique), display_name, created_at.
- **Group**: id (UUID), name, invite_code (unique), created_at.
- **Membership**: user_id + group_id (unique together) + role
  (`admin`/`member`) + joined_at. Proper many-to-many: a user can belong to
  several groups, and a group can have several admins.
- **DeviceToken**: id, user_id (FK), token (unique across the whole table,
  not per-user), platform, created_at, last_seen_at. Registering a token
  that already exists reassigns it to the caller rather than erroring —
  covers both "refreshed token, same user" and "reused device, new
  account."
- **Space**: id, group_id (FK), name, created_at. A group's bookable
  spaces; seeded automatically (Living Room, Kitchen, Main Desk) when the
  group is created (`reservation_service.seed_default_spaces`).
- **Reservation**: id, group_id, space_id, user_id (the booker — this is
  the one visible-identity feature in the app; unlike a nudge, who booked
  a space is shown to the group), start_time, end_time, plus an internal
  `during` column purely for the conflict check (see Reservations, below).
- **Chore**: id, reservation_id (unique — one per reservation), user_id
  (the booker), template, due_at, done. Created immediately alongside its
  reservation, not by anything that fires later; see Reservations.

No status-history table exists yet. Membership/User/Group are independent of
it, so an append-only history table can be added later (e.g. written
alongside the Redis write in `status_service.set_status`) without touching
the live path.

## Live status (Redis, not Postgres)

Key: `status:{group_id}:{user_id}` → status value, `EX` TTL of 2h / 4h / 8h
(`StatusTtl` enum). On every write, the change is published on
`status:group:{group_id}`. Statuses: Open to Chat, Deep Focus, In Call,
Sleeping Early, Away.

## Live status stream (WebSocket)

`GET /api/v1/groups/{group_id}/ws?token=<firebase-id-token>` — the token is
a query param, not a header, because browsers can't set custom headers on a
WebSocket handshake. Verified the same way as `get_current_user`
(`app/api/deps.py`'s `authenticate_token`, shared by both paths); a missing
member gets closed with code `4403`, an auth failure with `4401`.

On accept, the connection subscribes directly to the group's Redis pub/sub
channel (`status_service.group_channel`) and sends one snapshot message.
After that, the route is a dumb relay: it forwards whatever's published on
that channel verbatim. Every message carries its own `"event"` field, set
by whichever service published it — the route never inspects or rewrites
content:

```json
{"event": "snapshot", "statuses": [{"user_id": "...", "status": "deep_focus", "ttl_seconds": 7200}, ...]}
{"event": "status_update", "group_id": "...", "user_id": "...", "status": "in_call", "ttl_seconds": 7200}
{"event": "nudge", "id": "...", "group_id": "...", "type": "quiet_pulse", "message": "A housemate asked for 15 minutes of quiet.", "duration_minutes": 15, "created_at": "..."}
```

`ConnectionManager` (`app/services/connection_manager.py`) only tracks this
worker's local connections for logging/cleanup — it does *not* fan out
messages. Delivery is entirely through Redis: every connection, on every
worker, subscribes to the same channel independently, so an event
published from any worker reaches every connected client regardless of
which worker they're attached to.

## Nudges

`POST /api/v1/groups/{group_id}/nudges` — caller must be a group member.
Body is `{"type": "quiet_pulse", "duration_minutes": 15}` or, for a preset,
just `{"type": "package_arrived"}` (`front_door_unlocked`, `sink_full`).
The client supplies a *type*, never free text; the server renders the
neutral wording (`nudge_service.render_message`) and publishes it on the
same Redis channel status updates use, so it fans out over the existing
WebSocket to every connected member.

**Anonymity holds structurally, not by convention**: `NudgeRead` (the
response schema, and what gets published) has no sender field at all — it's
not filtered out, it was never on the model. The sender id only exists
inside `nudge_service`, logged internally and used to key the Redis
cooldown; nothing that reaches another member's client, or even the
sender's own HTTP response, can carry it.

Quiet pulses (only — presets are unlimited, being one-off factual events)
are rate-limited two ways, both in Redis:
- **Per-sender cooldown** (`quiet_pulse_cooldown_seconds`, default 15 min):
  a `nudge:cooldown:{group_id}:{sender_id}` key with that TTL; a pulse is
  blocked while it exists.
- **Per-group daily cap** (`quiet_pulse_daily_cap`, default 6): a
  `nudge:quiet_pulse_count:{group_id}:{utc_date}` counter, expiring at UTC
  midnight. A rejected attempt decrements the counter back so it doesn't
  eat into the cap it didn't get to use.

Both return `429` with a clear `detail` message, structured-logged as
`nudge.cooldown_blocked` / `nudge.daily_cap_blocked`.

## Push notifications (FCM)

Every nudge also gets pushed via FCM to every *other* group member's
registered devices (`nudge_service._send_push`), so it reaches a
backgrounded or locked phone, not just an open WebSocket connection. Same
neutral message, same no-sender-identity guarantee as the WebSocket path —
the push `data` payload is `{"event": "nudge", "group_id", "type"}`, nothing
else.

**This needs real FCM credentials that token verification doesn't.**
Verifying a sign-in token has a credential-free path (see Auth, below);
*sending* push has no equivalent — it requires a service account with the
`firebase.messaging` scope. `push_service._get_app` tries, in order:

1. `FIREBASE_SERVICE_ACCOUNT_PATH` / `FIREBASE_SERVICE_ACCOUNT_JSON` — a
   downloaded key file.
2. `FCM_IMPERSONATE_SERVICE_ACCOUNT` — impersonate that service account via
   [Application Default
   Credentials](https://cloud.google.com/docs/authentication/provide-credentials-adc),
   using `google.auth.impersonated_credentials`. No key file at all: your
   own `gcloud auth application-default login` session mints a short-lived
   token *as* the target service account, provided your account holds
   `roles/iam.serviceAccountTokenCreator` on it. This is what makes push
   sendable on a project whose org policy blocks key creation.
3. Neither set: `push_service.send_to_tokens` no-ops with a
   `push.not_configured` warning log instead of failing nudge creation —
   the WebSocket delivery is unaffected either way. A credential that
   fails to initialize (ADC missing, impersonation denied, malformed key)
   fails the same way, logged as `push.credential_init_failed` — never a
   crash.

**Local dev setup for option 2** (no key file, works around the
key-creation policy block):

```bash
gcloud auth application-default login
```

Then confirm your own account can impersonate the target — Firebase's
default Admin SDK service account, `firebase-adminsdk-fbsvc@<project-id>.iam.gserviceaccount.com`
(find the exact address at Firebase console → Project settings → Service
accounts):

```bash
gcloud iam service-accounts get-iam-policy \
  firebase-adminsdk-fbsvc@quietpass-app.iam.gserviceaccount.com \
  --project=quietpass-app
```

Look for a binding with your account under `roles/iam.serviceAccountTokenCreator`.
If it's missing (you'll otherwise see a `PERMISSION_DENIED` /
`iam.serviceAccounts.getAccessToken` error at send time), grant it to
yourself — you can, since you're Owner:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  firebase-adminsdk-fbsvc@quietpass-app.iam.gserviceaccount.com \
  --member="user:YOUR_EMAIL@gmail.com" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project=quietpass-app
```

Then set `FCM_IMPERSONATE_SERVICE_ACCOUNT` in `.env` to that same address.

**Production note**: impersonation is a local-dev convenience, not how
this should run in production — there, run the backend *as* that service
account directly (Cloud Run, GCE, or GKE workload identity all support
this natively) and leave `FCM_IMPERSONATE_SERVICE_ACCOUNT` unset. Chaining
through a developer's personal ADC login for every production send is an
unnecessary extra hop and ties push delivery to that person's account
still existing and being logged in.

Device registration: `POST /api/v1/device-tokens` (body:
`{"token": "...", "platform": "android"}`), `DELETE
/api/v1/device-tokens?token=...` to explicitly unregister (e.g. on sign
out). Stale tokens are also removed automatically: after any FCM send, a
per-token failure with code `NOT_FOUND` / `UNREGISTERED` /
`INVALID_ARGUMENT` deletes that row, logged as `push.stale_tokens_removed`.

**Foreground/background tradeoff, kept simple on purpose**: the backend
pushes to every other member's devices regardless of whether their app is
currently foregrounded — it has no visibility into that. Flutter is what
prevents a double notification: `onMessage` (foreground) receives the push
but doesn't render a system notification for it, relying on the
WebSocket-driven in-app banner instead. A more precise version would
exclude currently-connected members from the push entirely; not worth the
complexity yet.

## Reservations (base layer)

Booking a space, without the recurring-bookings or emergency-override
add-ons. `GET /api/v1/groups/{group_id}/spaces` lists a group's spaces
(seeded automatically on group creation — see Data model, above). `GET
/api/v1/groups/{group_id}/reservations` lists upcoming (and in-progress)
bookings across every space. `POST
/api/v1/groups/{group_id}/spaces/{space_id}/reservations` books one, body
`{"start_time": "<ISO 8601, any offset>", "duration_minutes": 15}` (15, 30,
or 60 only). All times are stored and compared in UTC
(`DateTime(timezone=True)` columns, `datetime.now(timezone.utc)`
throughout reservation_service) — the client converts to/from local time
for display, never the backend.

**Conflict locking is a real Postgres constraint, not an application-level
check.** `reservations.during` is a `tstzrange`, and the table has
`EXCLUDE USING gist (space_id WITH =, during WITH &&)` (needs the
`btree_gist` extension, enabled in this table's migration). Postgres
itself rejects any INSERT that would overlap an existing row for the same
space — enforced atomically by the database's own locking, immune to the
race an app-level "check then insert" would have. `create_reservation`
attempts the insert and translates the resulting `IntegrityError` into a
clean `ReservationConflictError` → `409`.

**The 15-minute buffer rides on the same constraint, not a separate
check.** `during` isn't the reservation's literal `[start_time, end_time)`
— it's `[start_time, end_time + buffer)`, padding only the trailing edge.
Padding *both* edges was the first (wrong) implementation: it silently
required a full buffer on each side of every booking, i.e. `2 × buffer`
between two adjacent ones. Padding just the end is sufficient and correct:
for any two bookings on the same space, whichever comes first has its
padded end pushed out by `buffer`, so the second can't start until that
padded end has passed — a `buffer`-minute gap either way, regardless of
booking order. Verified with a two-sided concurrent test (`asyncio.gather`
against two raw `asyncpg` connections, run six times) plus boundary cases
(a gap just under the buffer rejected, a gap of exactly the buffer
accepted, a different space at the identical time unaffected).

Two more rules, checked before the insert (these don't need transactional
protection — they don't depend on concurrent state, only the overlap
check does): `ReservationInPastError` if `start_time` is before now,
`ReservationTooFarAheadError` if it's more than
`reservation_max_advance_days` (default 7) out. Both `400`.

**The chore pass is created immediately at booking time, not triggered by
anything at the reservation's end.** There's no scheduler, no background
job — `create_reservation` inserts the `Chore` row (template + `due_at =
end_time`, `done = false`) in the same transaction as the reservation
itself. "Due" is purely a comparison the client makes against `now()` when
rendering; this is a deliberate simple choice for the base layer, not an
oversight. `GET /api/v1/groups/{group_id}/chores` lists every chore in the
group (not anonymous, same as reservations); `PATCH /api/v1/chores/{id}/done`
marks one done, only the assignee may call it.

Reservation changes fan out over the same WebSocket/Redis infrastructure
as status and nudges (step five), with their own `"event": "reservation"`
payload — the WS route is a dumb relay (see Live status stream, above), so
no route-level change was needed to add a third event type.

## Auth

Every endpoint except `/health` and `/docs` requires
`Authorization: Bearer <firebase-id-token>`. `get_current_user`
(`app/api/deps.py`) verifies the token, then resolves the matching `User` by
`firebase_uid` — provisioning one on first sight if none exists. There's no
separate "create user" endpoint; signing in via Firebase phone auth and
calling any protected route (`GET /users/me` is the obvious one) is what
creates the row.

Token verification (`app/core/firebase.py`) doesn't use the Firebase Admin
SDK — this project's org policy blocks issuing a service-account key for it.
Instead it verifies the ID token's JWT by hand: RS256 signature against
Google's public certs, `iss`/`aud` against the project id, and expiry. This
is Firebase's own documented fallback for exactly this situation and needs
no credentials at all, only `FIREBASE_PROJECT_ID` (not a secret).

Endpoints that used to take a `user_id` to mean "the caller" (creating a
group, joining one, setting your own status) now derive that identity from
the token instead — there's no `user_id` param left to spoof. `group_id` and
an explicit target `user_id` remain where they legitimately name someone
other than the caller (viewing another member's status, an admin changing
someone else's role), and those are authorized against the caller's
membership/role in that group (`app/api/authz.py`).

Missing, malformed, expired, or invalid tokens all return `401` with a
`WWW-Authenticate: Bearer` header and get structured-logged
(`auth.missing_token` / `auth.token_expired` / `auth.token_invalid` / ...).

## Setup

```bash
cp .env.example .env
python -m venv .venv && .venv\Scripts\activate   # Windows
pip install -r requirements.txt

docker-compose up -d
alembic upgrade head
uvicorn app.main:app --reload
```

Open http://127.0.0.1:8000/docs for the interactive API docs.
