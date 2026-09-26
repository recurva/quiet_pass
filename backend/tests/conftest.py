"""Test infrastructure: a real Postgres database (migrated with the exact
same Alembic revisions production runs, not just Base.metadata.create_all —
the EXCLUDE constraint's btree_gist extension only exists because a
migration creates it), a real local Redis (a dedicated DB index, flushed
per test), and a FastAPI app wired to both through dependency_overrides,
with Firebase token verification faked out so nothing here ever makes a
real network call.

DATABASE_URL/REDIS_URL are overridden via os.environ *before* anything
under app/ is imported — app.core.config.settings is instantiated once,
at import time, so this has to happen first or the real dev database
would get used by accident.
"""

import os
import subprocess
import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_TEST_DB_NAME = "quietpass_test"
_MAINTENANCE_DATABASE_URL = "postgresql+asyncpg://quietpass:quietpass@localhost:5433/quietpass"
_TEST_DATABASE_URL = f"postgresql+asyncpg://quietpass:quietpass@localhost:5433/{_TEST_DB_NAME}"
_TEST_REDIS_URL = "redis://localhost:6379/15"  # a dedicated index, never the dev DB's (0)

os.environ["DATABASE_URL"] = _TEST_DATABASE_URL
os.environ["REDIS_URL"] = _TEST_REDIS_URL
os.environ["FIREBASE_ADMIN_USE_RUNTIME_SERVICE_ACCOUNT"] = "false"
os.environ["FCM_USE_RUNTIME_SERVICE_ACCOUNT"] = "false"

import asyncio  # noqa: E402
import json  # noqa: E402
from collections.abc import AsyncIterator  # noqa: E402
from unittest.mock import AsyncMock  # noqa: E402

import asyncpg  # noqa: E402
import pytest  # noqa: E402
import pytest_asyncio  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from redis.asyncio import Redis as AsyncRedis  # noqa: E402
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine  # noqa: E402

import app.api.deps as deps_module  # noqa: E402
from app.core.firebase import TokenExpiredError, TokenInvalidError  # noqa: E402
from app.db.session import get_db  # noqa: E402
from app.db.redis import get_redis  # noqa: E402
from app.main import app  # noqa: E402
from app.services import firebase_auth_admin_service, push_service  # noqa: E402


def _run_alembic_upgrade() -> None:
    """Runs migrations as a subprocess, not in-process — alembic/env.py
    reads app.core.config.settings directly (see its own comment on why:
    configparser chokes on a literal "%" in a password), and settings is
    a module-level singleton already constructed by the time this fixture
    runs. A subprocess with DATABASE_URL in its own environment sidesteps
    that entirely rather than fighting the singleton.
    """
    env = os.environ.copy()
    env["DATABASE_URL"] = _TEST_DATABASE_URL
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=str(_BACKEND_ROOT),
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"alembic upgrade head failed (exit {result.returncode}):\n"
            f"--- stdout ---\n{result.stdout}\n--- stderr ---\n{result.stderr}"
        )


async def _recreate_test_database() -> None:
    conn = await asyncpg.connect(
        "postgresql://quietpass:quietpass@localhost:5433/quietpass"
    )
    try:
        await conn.execute(
            f"""
            SELECT pg_terminate_backend(pid)
            FROM pg_stat_activity
            WHERE datname = '{_TEST_DB_NAME}' AND pid <> pg_backend_pid()
            """
        )
        await conn.execute(f'DROP DATABASE IF EXISTS "{_TEST_DB_NAME}"')
        await conn.execute(f'CREATE DATABASE "{_TEST_DB_NAME}" OWNER quietpass')
    finally:
        await conn.close()


@pytest.fixture(scope="session")
def event_loop():
    """Session-scoped, deliberately, not the pytest-asyncio default of one
    fresh loop per test: the engine and its connection pool below are
    session-scoped too, and asyncpg connections are permanently bound to
    the loop that created them — a fresh per-test loop would make every
    test after the first fail cross-loop ("attached to a different
    loop"). pytest-asyncio deprecated overriding this fixture in favor of
    its own ini-based loop-scope config, but that config only governs
    *fixture* loop scope, not the test function's own — it didn't
    actually keep tests on one loop in this version, and this does.
    """
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest_asyncio.fixture(scope="session", autouse=True)
async def _test_database():
    """Fresh database for the whole run, migrated with the real Alembic
    chain. Dropped and recreated every run — deliberately, not left
    around: a leftover row from a crashed previous run must never be
    able to make today's run pass or fail for the wrong reason.
    """
    await _recreate_test_database()
    _run_alembic_upgrade()
    yield


@pytest.fixture(scope="session")
def engine(_test_database):
    eng = create_async_engine(_TEST_DATABASE_URL, pool_size=5, max_overflow=5)
    yield eng


@pytest_asyncio.fixture
async def db_session(engine) -> AsyncIterator[AsyncSession]:
    """The default session for most tests: one connection, one outer
    transaction, rolled back after the test — isolated and fast, and
    every test starts from an identical empty schema regardless of
    execution order. NOT used by the genuine-concurrency reservation
    test, which needs two independent connections that actually commit
    against each other; that test takes `engine` directly instead.
    """
    async with engine.connect() as conn:
        trans = await conn.begin()
        session = AsyncSession(bind=conn, expire_on_commit=False, join_transaction_mode="create_savepoint")
        try:
            yield session
        finally:
            await session.close()
            await trans.rollback()


@pytest_asyncio.fixture
async def redis_client() -> AsyncIterator[AsyncRedis]:
    client = AsyncRedis.from_url(_TEST_REDIS_URL, decode_responses=True)
    await client.flushdb()
    try:
        yield client
    finally:
        await client.flushdb()
        await client.aclose()


# --- Fake Firebase token verification -------------------------------------
#
# make_token(uid, phone) below is the one and only thing every test uses
# instead of a real Firebase ID token. This fixture patches the exact name
# authenticate_token calls (app.api.deps.verify_id_token — the module-level
# binding from `from app.core.firebase import verify_id_token`, not the
# original module it came from) so nothing in the whole suite ever makes a
# real network call to Google's cert endpoint.

def make_token(uid: str, phone_number: str | None) -> str:
    return json.dumps({"uid": uid, "phone_number": phone_number})


async def _fake_verify_id_token(token: str) -> dict:
    if token == "EXPIRED":
        raise TokenExpiredError("Token expired.")
    if token == "INVALID":
        raise TokenInvalidError("Malformed token.")
    decoded = json.loads(token)
    decoded.setdefault("uid", decoded.get("uid"))
    return decoded


@pytest.fixture(autouse=True)
def _fake_auth(monkeypatch):
    monkeypatch.setattr(deps_module, "verify_id_token", _fake_verify_id_token)


@pytest.fixture(autouse=True)
def _fake_firebase_admin_delete(monkeypatch):
    """Default: every account deletion in a test is treated as Firebase
    confirming the uid is genuinely gone (mirrors production's normal
    path) — this is what lets delete_current_user actually write a
    tombstone row during tests. An individual test can override this
    same mock's return_value to False to exercise the
    unconfigured-credentials branch instead.
    """
    mock = AsyncMock(return_value=True)
    monkeypatch.setattr(firebase_auth_admin_service, "delete_firebase_user", mock)
    return mock


@pytest.fixture(autouse=True)
def _fake_push(monkeypatch):
    """No real FCM send ever happens in tests — this is a spy, not just a
    no-op, so a test that cares can assert on how it was called (e.g. the
    member-removal push).
    """
    from app.services.push_service import PushSendResult

    mock = AsyncMock(return_value=PushSendResult())
    monkeypatch.setattr(push_service, "send_to_tokens", mock)
    return mock


@pytest_asyncio.fixture
async def client(db_session, redis_client) -> AsyncIterator[AsyncClient]:
    async def _get_db_override():
        yield db_session

    async def _get_redis_override():
        yield redis_client

    app.dependency_overrides[get_db] = _get_db_override
    app.dependency_overrides[get_redis] = _get_redis_override
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


def auth_headers(uid: str, phone_number: str | None) -> dict[str, str]:
    return {"Authorization": f"Bearer {make_token(uid, phone_number)}"}


@pytest_asyncio.fixture
async def concurrent_client(engine, redis_client) -> AsyncIterator[AsyncClient]:
    """For the two tests that specifically need genuine concurrency (the
    reservation EXCLUDE constraint, the two-departures-at-once race) —
    NOT the default `client` fixture, which binds every request in a test
    to the same single session/connection wrapped in one outer
    transaction. Two requests sharing one session can't actually
    contend with each other the way two real, independent production
    requests would (a `SELECT ... FOR UPDATE` from one won't block a
    second command on the very same connection the way it blocks a
    second *connection*), which would make a "concurrency" test pass or
    fail for the wrong reason regardless of whether the code being
    tested is actually race-safe.

    A fresh session per request, each pulling its own connection from the
    shared pool and committing for real, is what makes asyncio.gather-ed
    requests through this client behave like real concurrent traffic.
    Not wrapped in a rollback — rows created through this client outlive
    the test, which is fine: the whole database is recreated fresh at
    the start of every run regardless (see _test_database), and every
    test that uses this fixture is expected to use phone numbers/data
    unique to itself so leftover rows can't collide with a later test.
    """

    async def _get_db_override():
        async with AsyncSession(bind=engine, expire_on_commit=False) as session:
            yield session

    async def _get_redis_override():
        yield redis_client

    app.dependency_overrides[get_db] = _get_db_override
    app.dependency_overrides[get_redis] = _get_redis_override
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()
