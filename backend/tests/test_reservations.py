"""Reservations: the EXCLUDE constraint under genuine concurrent
connections (not sequential calls), the exact buffer boundary, and the
chore that comes out of a booking.
"""

import asyncio
from datetime import datetime, timedelta, timezone

from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Reservation Test House"}
    )
    return response.json()


async def _first_space_id(client, uid: str, phone: str, group_id: str) -> str:
    response = await client.get(f"/api/v1/groups/{group_id}/spaces", headers=auth_headers(uid, phone))
    return response.json()[0]["id"]


def _iso(dt: datetime) -> str:
    return dt.isoformat()


async def test_booking_in_the_past_is_rejected(client):
    await _sign_in(client, "uid-res-1", "+913333330001", "A")
    group = await _create_group(client, "uid-res-1", "+913333330001")
    space_id = await _first_space_id(client, "uid-res-1", "+913333330001", group["id"])

    past = datetime.now(timezone.utc) - timedelta(hours=1)
    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-res-1", "+913333330001"),
        json={"start_time": _iso(past), "duration_minutes": 30},
    )
    assert response.status_code == 400


async def test_booking_beyond_max_advance_is_rejected(client):
    await _sign_in(client, "uid-res-2", "+913333330002", "A")
    group = await _create_group(client, "uid-res-2", "+913333330002")
    space_id = await _first_space_id(client, "uid-res-2", "+913333330002", group["id"])

    too_far = datetime.now(timezone.utc) + timedelta(days=8)  # max is 7
    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-res-2", "+913333330002"),
        json={"start_time": _iso(too_far), "duration_minutes": 30},
    )
    assert response.status_code == 400


async def test_booking_creates_a_chore_assigned_to_the_booker(client):
    a = await _sign_in(client, "uid-res-3", "+913333330003", "Booker")
    group = await _create_group(client, "uid-res-3", "+913333330003")
    space_id = await _first_space_id(client, "uid-res-3", "+913333330003", group["id"])

    start = datetime.now(timezone.utc) + timedelta(hours=2)
    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-res-3", "+913333330003"),
        json={"start_time": _iso(start), "duration_minutes": 30},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["chore"]["user_id"] == a["id"]
    assert body["chore"]["done"] is False


async def test_mark_done_is_assignee_only_and_membership_gated(client):
    a = await _sign_in(client, "uid-res-4", "+913333330004", "Booker")
    group = await _create_group(client, "uid-res-4", "+913333330004")
    b = await _sign_in(client, "uid-res-5", "+913333330005", "Housemate")
    await client.post(
        "/api/v1/groups/join",
        headers=auth_headers("uid-res-5", "+913333330005"),
        json={"invite_code": group["invite_code"]},
    )
    outsider = await _sign_in(client, "uid-res-6", "+913333330006", "Outsider")

    space_id = await _first_space_id(client, "uid-res-4", "+913333330004", group["id"])
    start = datetime.now(timezone.utc) + timedelta(hours=3)
    booking = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-res-4", "+913333330004"),
        json={"start_time": _iso(start), "duration_minutes": 30},
    )
    chore_id = booking.json()["chore"]["id"]

    # A housemate who isn't the assignee: rejected.
    denied = await client.patch(
        f"/api/v1/chores/{chore_id}/done", headers=auth_headers("uid-res-5", "+913333330005")
    )
    assert denied.status_code == 403

    # An outsider (not even a member): also rejected, and for the right
    # reason — assignee-only is checked before membership, so this could
    # otherwise pass by accident if it happened to also be a non-member.
    outsider_denied = await client.patch(
        f"/api/v1/chores/{chore_id}/done", headers=auth_headers("uid-res-6", "+913333330006")
    )
    assert outsider_denied.status_code == 403

    # The actual assignee: allowed.
    allowed = await client.patch(
        f"/api/v1/chores/{chore_id}/done", headers=auth_headers("uid-res-4", "+913333330004")
    )
    assert allowed.status_code == 200
    assert allowed.json()["done"] is True


async def test_buffer_boundary_exactly_15_minutes_passes_14_fails(client):
    """The buffer is a half-open range [start, end + buffer) — a second
    booking starting exactly at that upper bound doesn't overlap it, one
    starting even a minute earlier does. This is the exact boundary the
    EXCLUDE constraint enforces at the database level.
    """
    await _sign_in(client, "uid-res-7", "+913333330007", "A")
    group = await _create_group(client, "uid-res-7", "+913333330007")
    space_id = await _first_space_id(client, "uid-res-7", "+913333330007", group["id"])

    first_start = datetime.now(timezone.utc) + timedelta(hours=4)
    first_end = first_start + timedelta(minutes=30)
    first = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-res-7", "+913333330007"),
        json={"start_time": _iso(first_start), "duration_minutes": 30},
    )
    assert first.status_code == 201

    # 14 minutes after the first booking ends: still inside its buffer — rejected.
    too_soon_start = first_end + timedelta(minutes=14)
    too_soon = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-res-7", "+913333330007"),
        json={"start_time": _iso(too_soon_start), "duration_minutes": 30},
    )
    assert too_soon.status_code == 409

    # Exactly 15 minutes after: right at the buffer's own boundary — allowed.
    exactly_buffer_start = first_end + timedelta(minutes=15)
    exactly_buffer = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-res-7", "+913333330007"),
        json={"start_time": _iso(exactly_buffer_start), "duration_minutes": 30},
    )
    assert exactly_buffer.status_code == 201


async def test_genuinely_concurrent_overlapping_bookings_only_one_wins(concurrent_client):
    """The one place in the codebase that deliberately avoids an
    app-level TOCTOU check in favor of a database EXCLUDE constraint —
    this only actually proves anything if both inserts are attempted at
    the same time over independent connections (see concurrent_client's
    docstring), not two sequential calls where the second trivially sees
    the first's already-committed row.
    """
    client = concurrent_client
    await _sign_in(client, "uid-res-8", "+913333330008", "A")
    group = await _create_group(client, "uid-res-8", "+913333330008")
    space_id = await _first_space_id(client, "uid-res-8", "+913333330008", group["id"])

    start = datetime.now(timezone.utc) + timedelta(hours=5)
    payload = {"start_time": _iso(start), "duration_minutes": 30}

    results = await asyncio.gather(
        client.post(
            f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
            headers=auth_headers("uid-res-8", "+913333330008"),
            json=payload,
        ),
        client.post(
            f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
            headers=auth_headers("uid-res-8", "+913333330008"),
            json=payload,
        ),
        return_exceptions=True,
    )

    statuses = sorted(r.status_code for r in results if not isinstance(r, Exception))
    assert statuses == [201, 409], (
        f"expected exactly one success and one conflict, got {statuses} "
        f"(exceptions: {[r for r in results if isinstance(r, Exception)]})"
    )
