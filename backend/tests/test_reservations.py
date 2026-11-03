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


async def test_reservation_list_shape_supports_free_reserved_in_use(client):
    """Spaces' three-state availability badge (Free / Reserved · <time> /
    In use) is computed entirely client-side from GET .../reservations —
    there's no separate backend "availability" endpoint or field. This
    confirms the list this endpoint returns actually carries what that
    computation needs for all three cases: a space with nothing booked
    today returns an empty list (Free), a space with only a later-today
    booking returns it with the right start/end so the client can show
    "Reserved · <time>" (not currently active), and a space with a
    booking spanning right now returns it too (In use) -- list_reservations
    excludes only reservations whose end_time has already passed, so an
    active-now booking (which hasn't ended yet) and a future one are both
    still present for the client to classify.
    """
    await _sign_in(client, "uid-res-9", "+913333330009", "A")
    group = await _create_group(client, "uid-res-9", "+913333330009")
    spaces = await client.get(
        f"/api/v1/groups/{group['id']}/spaces", headers=auth_headers("uid-res-9", "+913333330009")
    )
    space_ids = [s["id"] for s in spaces.json()]
    assert len(space_ids) >= 2, "need at least two default spaces for this scenario"
    free_space_id, busy_space_id = space_ids[0], space_ids[1]

    # busy_space_id: booked to start in 2 seconds, long enough to clear
    # the "start time must be in the future" check at creation time; a
    # short real sleep afterwards then puts it in the past relative to
    # "now" at list time, so this becomes the active-right-now booking
    # without the API ever having to accept a start time that's already
    # elapsed (it rejects that outright).
    active_start = datetime.now(timezone.utc) + timedelta(seconds=2)
    active = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{busy_space_id}/reservations",
        headers=auth_headers("uid-res-9", "+913333330009"),
        json={"start_time": _iso(active_start), "duration_minutes": 30},
    )
    assert active.status_code == 201

    # Also give busy_space_id a later-today booking, well clear of the
    # active one's buffer, so one space's list exercises both non-Free
    # states at once.
    later_today_start = active_start + timedelta(hours=1)
    later_today = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{busy_space_id}/reservations",
        headers=auth_headers("uid-res-9", "+913333330009"),
        json={"start_time": _iso(later_today_start), "duration_minutes": 30},
    )
    assert later_today.status_code == 201

    # Let active_start actually elapse so it's genuinely active-now (not
    # merely scheduled) by the time the list is fetched below.
    await asyncio.sleep(2.5)

    response = await client.get(
        f"/api/v1/groups/{group['id']}/reservations", headers=auth_headers("uid-res-9", "+913333330009")
    )
    assert response.status_code == 200
    by_space: dict[str, list[dict]] = {}
    for row in response.json():
        by_space.setdefault(row["space_id"], []).append(row)

    # Free: nothing booked at all for this space today or otherwise.
    assert free_space_id not in by_space

    # Reserved + In use: both this space's reservations are present, with
    # the exact start/end times a client needs to classify one as active
    # now and the other as "reserved later today".
    busy_rows = sorted(by_space[busy_space_id], key=lambda r: r["start_time"])
    assert len(busy_rows) == 2
    now = datetime.now(timezone.utc)
    active_row, reserved_row = busy_rows
    assert datetime.fromisoformat(active_row["start_time"]) <= now < datetime.fromisoformat(
        active_row["end_time"]
    )
    assert datetime.fromisoformat(reserved_row["start_time"]) > now


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
