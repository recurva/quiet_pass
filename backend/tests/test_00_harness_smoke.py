"""Sanity-checks the test harness itself (DB migration ran, fake auth
works, redis is isolated) before anything else relies on it.
"""

import pytest

from tests.conftest import auth_headers


@pytest.mark.asyncio
async def test_health(client):
    response = await client.get("/health")
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_fake_auth_provisions_a_user(client):
    response = await client.get("/api/v1/users/me", headers=auth_headers("uid-smoke-1", "+910000000001"))
    assert response.status_code == 200
    body = response.json()
    assert body["phone_number"] == "+910000000001"
    assert body["display_name"] == "+910000000001"  # defaulted, no name supplied


@pytest.mark.asyncio
async def test_redis_is_isolated_per_test(redis_client):
    assert await redis_client.get("some_key") is None
    await redis_client.set("some_key", "value")
    assert await redis_client.get("some_key") == "value"


@pytest.mark.asyncio
async def test_db_session_rolls_back_between_tests(client):
    # If this number already existed (leaked from test_fake_auth above),
    # the harness's per-test rollback isolation is broken.
    response = await client.get(
        "/api/v1/auth/phone-exists?phone_number=%2B910000000001"
    )
    assert response.json() == {"exists": False}
