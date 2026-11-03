"""Status: per-status duration validation, the 8-hour cap boundary,
expiry resolving to Open to Chat, and the "never set anything" default.
"""

import asyncio

from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Status Test House"}
    )
    return response.json()


async def test_open_to_chat_has_no_ttl_or_expiry(client):
    await _sign_in(client, "uid-st-1", "+914444440001", "A")
    group = await _create_group(client, "uid-st-1", "+914444440001")

    response = await client.put(
        f"/api/v1/groups/{group['id']}/status",
        headers=auth_headers("uid-st-1", "+914444440001"),
        json={"status": "open_to_chat"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["ttl_seconds"] is None
    assert body["expires_at"] is None


async def test_default_duration_is_used_when_omitted(client):
    await _sign_in(client, "uid-st-2", "+914444440002", "A")
    group = await _create_group(client, "uid-st-2", "+914444440002")

    response = await client.put(
        f"/api/v1/groups/{group['id']}/status",
        headers=auth_headers("uid-st-2", "+914444440002"),
        json={"status": "deep_focus"},  # no duration_minutes at all
    )
    assert response.status_code == 200
    assert response.json()["ttl_seconds"] == 30 * 60  # this status's default


async def test_a_duration_outside_the_30_minute_steps_is_rejected(client):
    await _sign_in(client, "uid-st-3", "+914444440003", "A")
    group = await _create_group(client, "uid-st-3", "+914444440003")

    response = await client.put(
        f"/api/v1/groups/{group['id']}/status",
        headers=auth_headers("uid-st-3", "+914444440003"),
        json={"status": "in_call", "duration_minutes": 45},  # not a 30-min step
    )
    assert response.status_code == 400


async def test_exactly_8_hours_is_allowed_and_over_is_rejected(client):
    await _sign_in(client, "uid-st-4", "+914444440004", "A")
    group = await _create_group(client, "uid-st-4", "+914444440004")

    at_cap = await client.put(
        f"/api/v1/groups/{group['id']}/status",
        headers=auth_headers("uid-st-4", "+914444440004"),
        json={"status": "away", "duration_minutes": 8 * 60},
    )
    assert at_cap.status_code == 200
    assert at_cap.json()["ttl_seconds"] == 8 * 60 * 60

    over_cap = await client.put(
        f"/api/v1/groups/{group['id']}/status",
        headers=auth_headers("uid-st-4", "+914444440004"),
        json={"status": "sleeping_early", "duration_minutes": 8 * 60 + 30},
    )
    assert over_cap.status_code == 400


async def test_a_member_who_never_set_a_status_defaults_to_open_to_chat(client):
    await _sign_in(client, "uid-st-5", "+914444440005", "A")
    group = await _create_group(client, "uid-st-5", "+914444440005")
    b = await _sign_in(client, "uid-st-6", "+914444440006", "B")
    await client.post(
        "/api/v1/groups/join",
        headers=auth_headers("uid-st-6", "+914444440006"),
        json={"invite_code": group["invite_code"]},
    )

    # A never set anything for B — reading B's status must still resolve
    # cleanly to Open to Chat, not 404 or null.
    response = await client.get(
        f"/api/v1/groups/{group['id']}/status/{b['id']}", headers=auth_headers("uid-st-5", "+914444440005")
    )
    assert response.status_code == 200
    assert response.json()["status"] == "open_to_chat"


async def test_an_expired_status_resolves_back_to_open_to_chat(client, redis_client):
    a = await _sign_in(client, "uid-st-7", "+914444440007", "A")
    group = await _create_group(client, "uid-st-7", "+914444440007")

    await client.put(
        f"/api/v1/groups/{group['id']}/status",
        headers=auth_headers("uid-st-7", "+914444440007"),
        json={"status": "deep_focus", "duration_minutes": 30},
    )

    # Simulates the TTL having already lapsed (Redis expires it silently,
    # with nothing server-side needed to notice) rather than sleeping 30
    # real minutes in a test — the key is gone either way, which is the
    # only thing _read_result actually branches on.
    keys = [key async for key in redis_client.scan_iter(match="status:*")]
    assert keys, "expected the status key to exist before deleting it"
    await redis_client.delete(*keys)

    response = await client.get(
        f"/api/v1/groups/{group['id']}/status/{a['id']}",
        headers=auth_headers("uid-st-7", "+914444440007"),
    )
    assert response.status_code == 200
    assert response.json()["status"] == "open_to_chat"


async def test_status_persists_across_independent_rereads_within_ttl(client):
    """Regression for the client bug where returning to the group screen
    showed Open to Chat even though the real TTL hadn't expired: the
    client-side fix (groups_providers.dart's groupStatusesProvider) relies
    entirely on the *backend* still reporting the true status on any
    independent re-fetch — a simulated reconnect's fresh WS `snapshot`, or
    a plain GET, must both reflect the exact same live value, repeatedly,
    not just immediately after the write. Nothing here should ever revert
    to open_to_chat early: the TTL is 2 hours, comfortably longer than
    this test takes to run.
    """
    a = await _sign_in(client, "uid-st-8", "+914444440008", "A")
    group = await _create_group(client, "uid-st-8", "+914444440008")

    set_response = await client.put(
        f"/api/v1/groups/{group['id']}/status",
        headers=auth_headers("uid-st-8", "+914444440008"),
        json={"status": "sleeping_early", "duration_minutes": 120},
    )
    assert set_response.status_code == 200

    # Three independent reads, standing in for: a GET refetch, a second
    # member's own status snapshot of the group, and a simulated WebSocket
    # reconnect's fresh snapshot (get_group_statuses is exactly what the
    # ws route calls on every accept()) — none of these should see
    # anything other than the status actually set above.
    for _ in range(3):
        single = await client.get(
            f"/api/v1/groups/{group['id']}/status/{a['id']}",
            headers=auth_headers("uid-st-8", "+914444440008"),
        )
        assert single.status_code == 200
        assert single.json()["status"] == "sleeping_early"
        assert single.json()["ttl_seconds"] is not None
        assert single.json()["ttl_seconds"] > 0

        snapshot = await client.get(
            f"/api/v1/groups/{group['id']}/status",
            headers=auth_headers("uid-st-8", "+914444440008"),
        )
        assert snapshot.status_code == 200
        entries = {row["user_id"]: row for row in snapshot.json()}
        assert entries[a["id"]]["status"] == "sleeping_early"


async def test_status_reverts_to_open_to_chat_only_after_real_expiry(client, redis_client):
    """A genuine real-time TTL expiry (not the "delete the key to simulate
    lapsed TTL" shortcut the other expiry test uses) — written directly
    against Redis with a short TTL, since the API itself enforces a
    30-minute floor on every timed status and a real test can't wait that
    long. Confirms both halves: still correct status while time remains,
    reverted only once the clock has actually run out.
    """
    a = await _sign_in(client, "uid-st-9", "+914444440009", "A")
    group = await _create_group(client, "uid-st-9", "+914444440009")

    key = f"status:{group['id']}:{a['id']}"
    await redis_client.set(key, "deep_focus", ex=1)

    still_active = await client.get(
        f"/api/v1/groups/{group['id']}/status/{a['id']}",
        headers=auth_headers("uid-st-9", "+914444440009"),
    )
    assert still_active.status_code == 200
    assert still_active.json()["status"] == "deep_focus"

    await asyncio.sleep(1.5)

    expired = await client.get(
        f"/api/v1/groups/{group['id']}/status/{a['id']}",
        headers=auth_headers("uid-st-9", "+914444440009"),
    )
    assert expired.status_code == 200
    assert expired.json()["status"] == "open_to_chat"
    assert expired.json()["ttl_seconds"] is None
    assert expired.json()["expires_at"] is None
