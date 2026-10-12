"""Urgent access request (emergency override): the request flow, the
per-(holder, requester) cooldown, and the permission/validity checks —
must be a member, must not be the holder, and the booking must be
currently active.
"""

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import func

from app.models.reservation import Reservation
from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Urgent Access Test House"}
    )
    return response.json()


async def _join(client, uid: str, phone: str, name: str, invite_code: str) -> None:
    await _sign_in(client, uid, phone, name)
    await client.post(
        "/api/v1/groups/join", headers=auth_headers(uid, phone), json={"invite_code": invite_code}
    )


async def _first_space_id(client, uid: str, phone: str, group_id: str) -> str:
    response = await client.get(f"/api/v1/groups/{group_id}/spaces", headers=auth_headers(uid, phone))
    return response.json()[0]["id"]


def _iso(dt: datetime) -> str:
    return dt.isoformat()


async def _insert_active_reservation(db_session, group_id: str, space_id: str, holder_user_id: str) -> str:
    """Inserts a reservation that's already in progress right now —
    directly via the session, bypassing the single-booking HTTP endpoint
    (which rejects a start_time in the past) — the same "insert directly,
    bypassing the API" approach test_dinner.py uses for setting up state
    the API itself has no way to produce. A real booking could only ever
    become "active" by waiting for wall-clock time to pass, which this
    sidesteps entirely.
    """
    start_time = datetime.now(timezone.utc) - timedelta(minutes=5)
    end_time = datetime.now(timezone.utc) + timedelta(minutes=25)
    reservation = Reservation(
        id=uuid.uuid4(),
        group_id=uuid.UUID(group_id),
        space_id=uuid.UUID(space_id),
        user_id=uuid.UUID(holder_user_id),
        start_time=start_time,
        end_time=end_time,
    )
    reservation.during = func.tstzrange(start_time, end_time, "[)")
    db_session.add(reservation)
    await db_session.flush()
    await db_session.commit()
    return str(reservation.id)


async def test_member_can_request_urgent_access_to_a_currently_held_space(client, db_session):
    holder = await _sign_in(client, "uid-ua-1", "+910000000001", "Holder")
    group = await _create_group(client, "uid-ua-1", "+910000000001")
    space_id = await _first_space_id(client, "uid-ua-1", "+910000000001", group["id"])
    reservation_id = await _insert_active_reservation(db_session, group["id"], space_id, holder["id"])
    await _join(client, "uid-ua-2", "+910000000002", "Requester", group["invite_code"])

    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations/{reservation_id}/urgent-access-request",
        headers=auth_headers("uid-ua-2", "+910000000002"),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["holder_id"] != body["requester_id"]


async def test_second_request_within_the_cooldown_is_rate_limited(client, db_session):
    holder = await _sign_in(client, "uid-ua-3", "+910000000003", "Holder")
    group = await _create_group(client, "uid-ua-3", "+910000000003")
    space_id = await _first_space_id(client, "uid-ua-3", "+910000000003", group["id"])
    reservation_id = await _insert_active_reservation(db_session, group["id"], space_id, holder["id"])
    await _join(client, "uid-ua-4", "+910000000004", "Requester", group["invite_code"])

    first = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations/{reservation_id}/urgent-access-request",
        headers=auth_headers("uid-ua-4", "+910000000004"),
    )
    assert first.status_code == 200

    second = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations/{reservation_id}/urgent-access-request",
        headers=auth_headers("uid-ua-4", "+910000000004"),
    )
    assert second.status_code == 429
    assert "Retry-After" in second.headers


async def test_cannot_request_urgent_access_to_your_own_booking(client, db_session):
    holder = await _sign_in(client, "uid-ua-5", "+910000000005", "A")
    group = await _create_group(client, "uid-ua-5", "+910000000005")
    space_id = await _first_space_id(client, "uid-ua-5", "+910000000005", group["id"])
    reservation_id = await _insert_active_reservation(db_session, group["id"], space_id, holder["id"])

    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations/{reservation_id}/urgent-access-request",
        headers=auth_headers("uid-ua-5", "+910000000005"),
    )
    assert response.status_code == 400


async def test_cannot_request_urgent_access_to_a_future_not_yet_active_booking(client):
    await _sign_in(client, "uid-ua-6", "+910000000006", "Holder")
    group = await _create_group(client, "uid-ua-6", "+910000000006")
    space_id = await _first_space_id(client, "uid-ua-6", "+910000000006", group["id"])

    future_start = datetime.now(timezone.utc) + timedelta(hours=3)
    booking = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-ua-6", "+910000000006"),
        json={"start_time": _iso(future_start), "duration_minutes": 60},
    )
    reservation_id = booking.json()["reservation"]["id"]
    await _join(client, "uid-ua-7", "+910000000007", "Requester", group["invite_code"])

    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations/{reservation_id}/urgent-access-request",
        headers=auth_headers("uid-ua-7", "+910000000007"),
    )
    assert response.status_code == 400


async def test_non_member_cannot_send_an_urgent_access_request(client, db_session):
    holder = await _sign_in(client, "uid-ua-8", "+910000000008", "Holder")
    group = await _create_group(client, "uid-ua-8", "+910000000008")
    space_id = await _first_space_id(client, "uid-ua-8", "+910000000008", group["id"])
    reservation_id = await _insert_active_reservation(db_session, group["id"], space_id, holder["id"])
    await _sign_in(client, "uid-ua-9", "+910000000009", "Outsider")

    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations/{reservation_id}/urgent-access-request",
        headers=auth_headers("uid-ua-9", "+910000000009"),
    )
    assert response.status_code == 403


async def test_requesting_against_a_nonexistent_reservation_is_404(client):
    await _sign_in(client, "uid-ua-10", "+910000000010", "A")
    group = await _create_group(client, "uid-ua-10", "+910000000010")
    space_id = await _first_space_id(client, "uid-ua-10", "+910000000010", group["id"])
    fake_id = "00000000-0000-0000-0000-000000000000"

    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations/{fake_id}/urgent-access-request",
        headers=auth_headers("uid-ua-10", "+910000000010"),
    )
    assert response.status_code == 404


async def test_cooldown_is_scoped_per_requester_not_shared_across_requesters(client, db_session):
    """A cooldown one requester triggers must not block a *different*
    requester from also asking — it's "don't let one person spam the
    holder," not "only one urgent request per booking, ever."
    """
    holder = await _sign_in(client, "uid-ua-11", "+910000000011", "Holder")
    group = await _create_group(client, "uid-ua-11", "+910000000011")
    space_id = await _first_space_id(client, "uid-ua-11", "+910000000011", group["id"])
    reservation_id = await _insert_active_reservation(db_session, group["id"], space_id, holder["id"])
    await _join(client, "uid-ua-12", "+910000000012", "Requester A", group["invite_code"])
    await _join(client, "uid-ua-13", "+910000000013", "Requester B", group["invite_code"])

    from_a = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations/{reservation_id}/urgent-access-request",
        headers=auth_headers("uid-ua-12", "+910000000012"),
    )
    assert from_a.status_code == 200

    from_b = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations/{reservation_id}/urgent-access-request",
        headers=auth_headers("uid-ua-13", "+910000000013"),
    )
    assert from_b.status_code == 200
