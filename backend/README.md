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

Key: `status:{group_id}:{user_id}` → status value. Statuses: Open to Chat,
Deep Focus, In Call, Sleeping Early, Away. On every write, the change is
published on `status:group:{group_id}`.

**Duration policy (the Time Limits spec).** Open to Chat is the one
indefinite, uncapped status — `PUT .../status` with
`{"status": "open_to_chat"}` sets the Redis key with no `EX` at all, rather
than skipping the write. The other four statuses (In Call, Deep Focus,
Sleeping Early, Away) all share one uniform rule — the client simplified
this from an earlier per-status preset design: `duration_minutes` must be
a multiple of 30 from 30 up to 480 (8h), defaulting to 30 if omitted, hard
capped at 8h server-side regardless of what the client sends. See
`STATUS_DURATION_RULES` in `app/schemas/status.py`.

A `duration_minutes` outside that set is a clean `400`
(`InvalidStatusDurationError`), not a silent clamp or a UI-only
restriction — the cap is enforced here, not just hidden from the picker.

**No "no status" state.** An expired or never-set status resolves to Open
to Chat, not null — `StatusRead.status` is never `None` on the wire. Two
places implement this the same way: `status_service.get_status` returns
`HouseStatus.OPEN_TO_CHAT` for a missing Redis key, and
`get_group_statuses` simply omits members with no key at all, relying on
callers to render that absence identically (open to chat) rather than
needing the group's full membership list to fill gaps itself. Nothing
server-side fires when a TTL naturally lapses — Redis just lets the key
expire silently; a client holding a stale status has to notice the
crossover itself by comparing the broadcast `expires_at` to now (see
`MemberStatus.effectiveStatus` in the Flutter app).

**`expires_at` is the top-priority field for display.** Both `set_status`'s
publish payload and every `StatusRead` include an absolute UTC
`expires_at` (null for Open to Chat), computed from the TTL at write/read
time — not just the relative `ttl_seconds`, which drifts the moment a
client caches it. The Flutter status badge renders it as "until 6:30 PM"
in the viewer's own local time.

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

## Account deletion (Firebase Auth + Postgres)

`DELETE /api/v1/users/me` removes the caller entirely: from Firebase
Authentication first, then the Postgres `users` row (whose `ON DELETE
CASCADE` on `memberships`, `reservations`, `chores`, and `device_tokens`
handles every child row — see the data model above). Firebase goes first
deliberately: it's the external, less-reliable side, so if it fails the
Postgres row is left untouched rather than risking the two ending up out
of sync.

**Needs its own credential, separate from push's.** Deleting a Firebase
Auth user requires the `identitytoolkit` scope, which push's FCM-scoped
credential (`app/services/push_service.py`) can't be reused for — a
single named `firebase_admin` app can't hold two scopes. See
`app/services/firebase_auth_admin_service.py`, which follows the exact
same credential-resolution pattern as push (impersonation for local dev,
runtime service account in production) but as its own separately-scoped
app. Gated on `FIREBASE_ADMIN_USE_RUNTIME_SERVICE_ACCOUNT` (production)
or `FCM_IMPERSONATE_SERVICE_ACCOUNT` (local dev, reusing the same target
principal as push's impersonation — just a different requested scope).

**The runtime service account needs an additional IAM grant** beyond the
`roles/firebasecloudmessaging.admin` already covering push:

```bash
gcloud projects add-iam-policy-binding quietpass-app \
  --member="serviceAccount:quietpass-runtime@quietpass-app.iam.gserviceaccount.com" \
  --role="roles/firebaseauth.admin"
```

**Fans out over the same WebSocket/Redis infrastructure as everything
else** (status, nudges, reservations — see Live status stream, above),
with its own `"event": "member_left"` payload, published to every group
the deleted user belonged to — captured *before* the delete, since once
the `Membership` rows cascade away there's no way to ask Postgres
afterward which groups they were in. This is the exact mirror of
`"event": "member_joined"` (published from `groups.py`'s `join_group`):
without it, an already-open session on another member's device has no
way to learn someone's account was deleted except by being fully
restarted — the member just silently stays in the list.

If neither credential path is configured, `delete_firebase_user` returns
`False` rather than raising — the Postgres deletion still proceeds (the
account becomes unusable locally either way), just without the matching
Firebase Auth cleanup. Only a genuine failure (credentials configured but
the call itself errors) stops the Postgres deletion, logged as
`user.delete.firebase_failed`.

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

## Deploying (Cloud Run) — the WebSocket timeout gotcha

Cloud Run's **default request timeout is 300 seconds, and it applies to
WebSocket connections** — not just plain HTTP requests. Every open
`/ws` connection gets forcibly severed at the platform level every 5
minutes, invisible to this app's own code (no `WebSocketDisconnect`, no
exception — the infrastructure just cuts the connection, so nothing here
gets a chance to log it). The client's own reconnect logic papers over
this most of the time, but a nudge (or any event) published during one of
those dead windows is silently lost, since nothing was listening.

Always set the service's timeout to Cloud Run's max on deploy:

```bash
gcloud run deploy quietpass-backend \
  --image=... \
  --timeout=3600 \
  ...
```

`gcloud run services update ... --timeout=3600` fixes an already-deployed
service without a rebuild. A later `gcloud run deploy` that doesn't pass
`--timeout` keeps the previous revision's value (Cloud Run only changes
what you explicitly pass), but it's still worth including explicitly
every time this command appears in a runbook — a copy-pasted command
missing it is exactly how this regressed once already.

## Auth

Every endpoint except `/health` and `/docs` requires
`Authorization: Bearer <firebase-id-token>`. `get_current_user`
(`app/api/deps.py`) verifies the token, then resolves the matching `User` by
`firebase_uid` — provisioning one on first sight if none exists, with
`display_name` defaulted to the phone number. There's no separate "create
user" endpoint; signing in via Firebase phone auth and calling any
protected route is what creates the row.

**New-vs-returning is a backend decision, not a client one.** Flutter has
two entry screens — `SignInPage` (number only) and `SignUpPage` (name and
number) — but Firebase phone auth ties the account to the number
regardless of which one was used, so the client can't actually know
whether a given number is new. `POST /api/v1/auth/sign-in`
(`app/api/routers/auth.py`) is the one call made right after OTP
verification succeeds, from *either* screen: it wraps `authenticate_token`
(now returning `(user, is_new)` instead of just `user`) and responds with
both. `is_new` is true only when this exact call is what provisioned the
row — never when an existing user was resolved.

**An existing user's `display_name` is never touched by sign-in, under
any circumstances** — not by `get_current_user`'s auto-provisioning, and
not by `/auth/sign-in` even when the caller supplies one. This is what
makes a returning user's sign-in immune to a stray name arriving with it
(the concrete case: someone opens `SignUpPage` — maybe out of habit, or
not realizing they already have an account — for a number that's already
registered; the entered name is silently ignored, their real name comes
back unchanged, and the client shows a brief "you already have an
account" notice rather than an error or a duplicate). The name is only
ever used on the provisioning path, the same "first sight" moment
`get_current_user` has always had.

`GET /users/me` and `PATCH /users/me` are unchanged and still exist for
their own purposes (fetch the current profile; edit the name later from
the profile screen) — `/auth/sign-in` is additive, specifically for the
post-OTP moment, not a replacement for either.

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
