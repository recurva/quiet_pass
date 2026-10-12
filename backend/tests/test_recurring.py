"""Recurring weekly bookings: the per-user weekly cap, partial-conflict
handling (book what's free, report what's skipped), that every generated
occurrence is governed by the same exclusion constraint and buffer as an
ad-hoc booking (including under genuine concurrency), and series/occurrence
cancellation.
"""

import asyncio
from datetime import datetime, timedelta, timezone

from app.services.recurring_service import _candidate_occurrences
from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Recurring Test House"}
    )
    return response.json()


async def _first_space_id(client, uid: str, phone: str, group_id: str) -> str:
    response = await client.get(f"/api/v1/groups/{group_id}/spaces", headers=auth_headers(uid, phone))
    return response.json()[0]["id"]


async def _join(client, uid: str, phone: str, name: str, invite_code: str) -> None:
    await _sign_in(client, uid, phone, name)
    await client.post(
        "/api/v1/groups/join", headers=auth_headers(uid, phone), json={"invite_code": invite_code}
    )


def _iso(dt: datetime) -> str:
    return dt.isoformat()


# A fixed hour unlikely to collide with "now" regardless of when the test
# suite runs, and always safely within the recurring horizon.
_SAFE_HOUR = 22
_SAFE_MINUTE = 0


async def _create_series(client, uid, phone, group_id, space_id, weekdays, duration_minutes=60):
    return await client.post(
        f"/api/v1/groups/{group_id}/spaces/{space_id}/recurring-series",
        headers=auth_headers(uid, phone),
        json={
            "weekdays": weekdays,
            "start_hour_utc": _SAFE_HOUR,
            "start_minute_utc": _SAFE_MINUTE,
            "duration_minutes": duration_minutes,
        },
    )


async def test_creating_a_series_books_every_free_occurrence_in_the_horizon(client):
    await _sign_in(client, "uid-rec-1", "+911111110001", "A")
    group = await _create_group(client, "uid-rec-1", "+911111110001")
    space_id = await _first_space_id(client, "uid-rec-1", "+911111110001", group["id"])

    response = await _create_series(client, "uid-rec-1", "+911111110001", group["id"], space_id, [1, 3])
    assert response.status_code == 201
    body = response.json()

    expected = _candidate_occurrences([1, 3], _SAFE_HOUR, _SAFE_MINUTE, 60)
    assert len(body["created"]) + len(body["skipped"]) == len(expected)
    assert len(body["skipped"]) == 0  # nothing pre-existing to conflict with
    assert body["series"]["weekdays"] == [1, 3]


async def test_weekly_cap_of_three_slots_per_user_is_enforced(client):
    await _sign_in(client, "uid-rec-2", "+911111110002", "A")
    group = await _create_group(client, "uid-rec-2", "+911111110002")
    space_id = await _first_space_id(client, "uid-rec-2", "+911111110002", group["id"])

    # 2 + 1 = 3, exactly at the cap — allowed.
    first = await _create_series(client, "uid-rec-2", "+911111110002", group["id"], space_id, [0, 1])
    assert first.status_code == 201
    second = await _create_series(client, "uid-rec-2", "+911111110002", group["id"], space_id, [2])
    assert second.status_code == 201

    # One more weekday would make 4 — rejected.
    third = await _create_series(client, "uid-rec-2", "+911111110002", group["id"], space_id, [3])
    assert third.status_code == 409

    # A single series requesting more than the cap outright is also rejected.
    await _sign_in(client, "uid-rec-3", "+911111110003", "B")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-rec-3", "+911111110003"), json={"invite_code": group["invite_code"]}
    )
    too_many_at_once = await _create_series(
        client, "uid-rec-3", "+911111110003", group["id"], space_id, [0, 1, 2, 3]
    )
    assert too_many_at_once.status_code == 409


async def test_cap_is_scoped_per_user_not_shared_across_the_house(client):
    await _sign_in(client, "uid-rec-4", "+911111110004", "A")
    group = await _create_group(client, "uid-rec-4", "+911111110004")
    space_id = await _first_space_id(client, "uid-rec-4", "+911111110004", group["id"])
    await _sign_in(client, "uid-rec-5", "+911111110005", "B")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-rec-5", "+911111110005"), json={"invite_code": group["invite_code"]}
    )

    # Different weekdays so these two users' series don't conflict with
    # each other — this test is purely about the cap being per-user.
    a = await _create_series(client, "uid-rec-4", "+911111110004", group["id"], space_id, [0, 1, 2])
    assert a.status_code == 201
    b = await _create_series(client, "uid-rec-5", "+911111110005", group["id"], space_id, [3, 4, 5])
    assert b.status_code == 201  # B's own cap is untouched by A's series


async def test_a_partially_conflicting_series_books_the_free_weeks_and_reports_the_rest(client):
    """My call on the "fail whole series vs. book-and-report" decision:
    book everything free, report the rest as skipped. A single contested
    week shouldn't cost every other free week in the horizon.
    """
    await _sign_in(client, "uid-rec-6", "+911111110006", "Owner")
    group = await _create_group(client, "uid-rec-6", "+911111110006")
    space_id = await _first_space_id(client, "uid-rec-6", "+911111110006", group["id"])

    weekday = 2  # Wednesday
    expected = _candidate_occurrences([weekday], _SAFE_HOUR, _SAFE_MINUTE, 60)
    assert len(expected) >= 2  # needs at least 2 occurrences in the horizon to prove partial behavior
    first_start, first_end = expected[0]

    # A second member books the exact first occurrence ad-hoc, ahead of
    # the series being created.
    await _sign_in(client, "uid-rec-7", "+911111110007", "Other")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-rec-7", "+911111110007"), json={"invite_code": group["invite_code"]}
    )
    blocker = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-rec-7", "+911111110007"),
        json={"start_time": _iso(first_start), "duration_minutes": 60},
    )
    assert blocker.status_code == 201

    response = await _create_series(client, "uid-rec-6", "+911111110006", group["id"], space_id, [weekday])
    assert response.status_code == 201
    body = response.json()

    assert len(body["skipped"]) == 1
    assert body["skipped"][0]["reason"] == "conflict"
    assert len(body["created"]) == len(expected) - 1
    # The series itself still exists even though its first week lost.
    assert body["series"]["weekdays"] == [weekday]


async def test_every_occurrence_respects_the_booking_buffer(client):
    """Not just "no exact overlap" — a generated occurrence must also
    honor the 15-minute buffer against an adjacent existing booking, the
    same EXCLUDE-constraint check an ad-hoc booking gets.
    """
    await _sign_in(client, "uid-rec-8", "+911111110008", "A")
    group = await _create_group(client, "uid-rec-8", "+911111110008")
    space_id = await _first_space_id(client, "uid-rec-8", "+911111110008", group["id"])

    weekday = 4  # Friday
    expected = _candidate_occurrences([weekday], _SAFE_HOUR, _SAFE_MINUTE, 60)
    first_start, first_end = expected[0]

    # A booking that ends only 10 minutes before the series' first
    # occurrence starts — inside the 15-minute buffer, so it must also
    # be reported as skipped, not just an exact-overlap conflict.
    buffered_conflict_start = first_start - timedelta(minutes=70)
    buffered_conflict_end = first_start - timedelta(minutes=10)
    duration = int((buffered_conflict_end - buffered_conflict_start).total_seconds() / 60)
    await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-rec-8", "+911111110008"),
        json={"start_time": _iso(buffered_conflict_start), "duration_minutes": duration},
    )

    response = await _create_series(client, "uid-rec-8", "+911111110008", group["id"], space_id, [weekday])
    body = response.json()
    assert len(body["skipped"]) == 1  # the buffer-violating first occurrence
    assert len(body["created"]) == len(expected) - 1


async def test_genuinely_concurrent_series_creation_on_the_same_slot_only_one_wins(concurrent_client):
    """Two different members both try to claim the exact same weekly slot
    at the same instant — this only proves the exclusion constraint holds
    under genuine concurrency (not two sequential calls) if both requests
    are in flight at once over independent connections.
    """
    client = concurrent_client
    await _sign_in(client, "uid-rec-9", "+911111110009", "A")
    group = await _create_group(client, "uid-rec-9", "+911111110009")
    space_id = await _first_space_id(client, "uid-rec-9", "+911111110009", group["id"])
    await _sign_in(client, "uid-rec-10", "+911111110010", "B")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-rec-10", "+911111110010"), json={"invite_code": group["invite_code"]}
    )

    weekday = 5  # Saturday

    results = await asyncio.gather(
        _create_series(client, "uid-rec-9", "+911111110009", group["id"], space_id, [weekday]),
        _create_series(client, "uid-rec-10", "+911111110010", group["id"], space_id, [weekday]),
        return_exceptions=True,
    )
    bodies = [r.json() for r in results if not isinstance(r, Exception) and r.status_code == 201]
    assert len(bodies) == 2  # both series are created; the *occurrences* are what contend

    total_created = sum(len(b["created"]) for b in bodies)
    total_skipped = sum(len(b["skipped"]) for b in bodies)
    expected_occurrences = len(_candidate_occurrences([weekday], _SAFE_HOUR, _SAFE_MINUTE, 60))

    # Exactly one side wins each contested week — never both (that would
    # mean the EXCLUDE constraint let an overlap through), never neither
    # (every occurrence must land in created or skipped on one side).
    assert total_created == expected_occurrences
    assert total_skipped == expected_occurrences


async def test_cancelling_a_single_occurrence_leaves_the_series_and_other_occurrences_intact(client):
    await _sign_in(client, "uid-rec-11", "+911111110011", "A")
    group = await _create_group(client, "uid-rec-11", "+911111110011")
    space_id = await _first_space_id(client, "uid-rec-11", "+911111110011", group["id"])

    created_response = await _create_series(client, "uid-rec-11", "+911111110011", group["id"], space_id, [6])
    occurrences = created_response.json()["created"]
    assert len(occurrences) >= 2
    first_reservation_id = occurrences[0]["reservation"]["id"]

    cancel = await client.delete(
        f"/api/v1/groups/{group['id']}/reservations/{first_reservation_id}",
        headers=auth_headers("uid-rec-11", "+911111110011"),
    )
    assert cancel.status_code == 204

    remaining = await client.get(
        f"/api/v1/groups/{group['id']}/reservations", headers=auth_headers("uid-rec-11", "+911111110011")
    )
    remaining_ids = [r["id"] for r in remaining.json()]
    assert first_reservation_id not in remaining_ids
    assert len(remaining_ids) == len(occurrences) - 1

    # The series itself is untouched.
    series_list = await client.get(
        f"/api/v1/groups/{group['id']}/recurring-series", headers=auth_headers("uid-rec-11", "+911111110011")
    )
    assert len(series_list.json()) == 1


async def test_cancelling_the_whole_series_removes_every_future_occurrence(client):
    await _sign_in(client, "uid-rec-12", "+911111110012", "A")
    group = await _create_group(client, "uid-rec-12", "+911111110012")
    space_id = await _first_space_id(client, "uid-rec-12", "+911111110012", group["id"])

    created_response = await _create_series(client, "uid-rec-12", "+911111110012", group["id"], space_id, [0])
    series_id = created_response.json()["series"]["id"]
    occurrence_count = len(created_response.json()["created"])
    assert occurrence_count >= 1

    cancel = await client.delete(
        f"/api/v1/groups/{group['id']}/recurring-series/{series_id}",
        headers=auth_headers("uid-rec-12", "+911111110012"),
    )
    assert cancel.status_code == 200
    assert len(cancel.json()["cancelled_occurrence_ids"]) == occurrence_count

    remaining = await client.get(
        f"/api/v1/groups/{group['id']}/reservations", headers=auth_headers("uid-rec-12", "+911111110012")
    )
    assert remaining.json() == []

    series_list = await client.get(
        f"/api/v1/groups/{group['id']}/recurring-series", headers=auth_headers("uid-rec-12", "+911111110012")
    )
    assert series_list.json() == []


async def test_only_the_owner_or_an_admin_can_cancel_a_series_or_occurrence(client):
    await _sign_in(client, "uid-rec-13", "+911111110013", "Owner")
    group = await _create_group(client, "uid-rec-13", "+911111110013")
    space_id = await _first_space_id(client, "uid-rec-13", "+911111110013", group["id"])
    await _sign_in(client, "uid-rec-14", "+911111110014", "Other")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-rec-14", "+911111110014"), json={"invite_code": group["invite_code"]}
    )

    created_response = await _create_series(client, "uid-rec-13", "+911111110013", group["id"], space_id, [0])
    series_id = created_response.json()["series"]["id"]
    reservation_id = created_response.json()["created"][0]["reservation"]["id"]

    cancel_series = await client.delete(
        f"/api/v1/groups/{group['id']}/recurring-series/{series_id}",
        headers=auth_headers("uid-rec-14", "+911111110014"),
    )
    assert cancel_series.status_code == 403

    cancel_occurrence = await client.delete(
        f"/api/v1/groups/{group['id']}/reservations/{reservation_id}",
        headers=auth_headers("uid-rec-14", "+911111110014"),
    )
    assert cancel_occurrence.status_code == 403


async def test_invalid_weekdays_are_rejected(client):
    await _sign_in(client, "uid-rec-15", "+911111110015", "A")
    group = await _create_group(client, "uid-rec-15", "+911111110015")
    space_id = await _first_space_id(client, "uid-rec-15", "+911111110015", group["id"])

    empty = await _create_series(client, "uid-rec-15", "+911111110015", group["id"], space_id, [])
    assert empty.status_code == 422

    out_of_range = await _create_series(client, "uid-rec-15", "+911111110015", group["id"], space_id, [7])
    assert out_of_range.status_code == 422

    duplicates = await _create_series(client, "uid-rec-15", "+911111110015", group["id"], space_id, [1, 1])
    assert duplicates.status_code == 422


async def test_cancelling_an_ad_hoc_reservation_still_works_through_the_shared_endpoint(client):
    """DELETE /reservations/{id} is shared by ad-hoc bookings and
    recurring occurrences — this confirms the ad-hoc path specifically,
    not just the recurring one every other cancellation test here covers.
    """
    await _sign_in(client, "uid-rec-18", "+911111110018", "A")
    group = await _create_group(client, "uid-rec-18", "+911111110018")
    space_id = await _first_space_id(client, "uid-rec-18", "+911111110018", group["id"])

    start = datetime.now(timezone.utc) + timedelta(hours=2)
    booking = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-rec-18", "+911111110018"),
        json={"start_time": _iso(start), "duration_minutes": 30},
    )
    reservation_id = booking.json()["reservation"]["id"]

    cancel = await client.delete(
        f"/api/v1/groups/{group['id']}/reservations/{reservation_id}",
        headers=auth_headers("uid-rec-18", "+911111110018"),
    )
    assert cancel.status_code == 204

    remaining = await client.get(
        f"/api/v1/groups/{group['id']}/reservations", headers=auth_headers("uid-rec-18", "+911111110018")
    )
    assert remaining.json() == []


async def test_reservation_list_reports_recurring_series_id_correctly(client):
    """An occurrence's reservation carries its series id; an ad-hoc
    booking's is null — this is what the Flutter client uses to show the
    "weekly" tag and to decide which cancel action to offer.
    """
    await _sign_in(client, "uid-rec-19", "+911111110019", "A")
    group = await _create_group(client, "uid-rec-19", "+911111110019")
    space_id = await _first_space_id(client, "uid-rec-19", "+911111110019", group["id"])

    series_response = await _create_series(client, "uid-rec-19", "+911111110019", group["id"], space_id, [1])
    series_id = series_response.json()["series"]["id"]

    ad_hoc_start = datetime.now(timezone.utc) + timedelta(hours=1)
    await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-rec-19", "+911111110019"),
        json={"start_time": _iso(ad_hoc_start), "duration_minutes": 15},
    )

    listed = (
        await client.get(
            f"/api/v1/groups/{group['id']}/reservations", headers=auth_headers("uid-rec-19", "+911111110019")
        )
    ).json()
    series_tagged = [r for r in listed if r["recurring_series_id"] == series_id]
    ad_hoc_tagged = [r for r in listed if r["recurring_series_id"] is None]
    assert len(series_tagged) >= 1
    assert len(ad_hoc_tagged) == 1


async def test_concurrent_series_creation_cannot_race_past_the_weekly_cap(concurrent_client):
    """The weekly cap is an app-level read-then-check
    (_active_weekday_count), not a database constraint like the
    exclusion constraint every occurrence gets — without serialization,
    two genuinely concurrent series-creation calls from the same user
    could each read the cap as not-yet-reached and both land, exceeding
    the limit (this was confirmed empirically before
    create_recurring_series's pg_advisory_xact_lock was added — both
    requests used to return 201). The lock makes the second call block
    until the first's transaction has committed, so exactly one of these
    two must be rejected.
    """
    client = concurrent_client
    await _sign_in(client, "uid-rec-20", "+911111110020", "A")
    group = await _create_group(client, "uid-rec-20", "+911111110020")
    space_id = await _first_space_id(client, "uid-rec-20", "+911111110020", group["id"])

    # Two series of 2 weekdays each — 2+2=4, over the cap of 3 — attempted
    # at the same instant over independent connections.
    results = await asyncio.gather(
        _create_series(client, "uid-rec-20", "+911111110020", group["id"], space_id, [0, 1]),
        _create_series(client, "uid-rec-20", "+911111110020", group["id"], space_id, [2, 3]),
        return_exceptions=True,
    )
    statuses = sorted(r.status_code for r in results if not isinstance(r, Exception))
    assert statuses == [201, 409], (
        f"expected exactly one to land and one rejected by the cap, got {statuses} "
        f"(exceptions: {[r for r in results if isinstance(r, Exception)]})"
    )


async def test_leaving_a_group_cancels_future_reservations_and_recurring_occurrences_there_only(client):
    """A departed member's future bookings in the house they left —
    ad-hoc and every future occurrence of a recurring series — must be
    cancelled, freeing those slots; but their bookings in a *different*
    house they're still a member of must be completely untouched. This
    is the fix for the gap where a departed member's weekly series would
    otherwise hold a space indefinitely with no one able to clear it.
    """
    member = await _sign_in(client, "uid-rec-21", "+911111110021", "Leaving Member")
    house_a = await _create_group(client, "uid-rec-21", "+911111110021")
    space_a_id = await _first_space_id(client, "uid-rec-21", "+911111110021", house_a["id"])

    # A second member in house A, so the departure promotes them to admin
    # instead of deleting the house (leaving_member created the house and
    # is its only admin until this join).
    await _join(client, "uid-rec-22", "+911111110022", "Staying Member", house_a["invite_code"])

    series_response = await _create_series(client, "uid-rec-21", "+911111110021", house_a["id"], space_a_id, [0, 2])
    series_id = series_response.json()["series"]["id"]
    occurrence_count = len(series_response.json()["created"])
    assert occurrence_count > 0

    ad_hoc_start = datetime.now(timezone.utc) + timedelta(hours=2)
    ad_hoc = await client.post(
        f"/api/v1/groups/{house_a['id']}/spaces/{space_a_id}/reservations",
        headers=auth_headers("uid-rec-21", "+911111110021"),
        json={"start_time": _iso(ad_hoc_start), "duration_minutes": 15},
    )
    assert ad_hoc.status_code == 201

    # The same member also has a booking in a second, unrelated house —
    # this one must survive the departure from house A untouched.
    house_b = await _create_group(client, "uid-rec-21", "+911111110021")
    space_b_id = await _first_space_id(client, "uid-rec-21", "+911111110021", house_b["id"])
    house_b_start = datetime.now(timezone.utc) + timedelta(hours=3)
    house_b_booking = await client.post(
        f"/api/v1/groups/{house_b['id']}/spaces/{space_b_id}/reservations",
        headers=auth_headers("uid-rec-21", "+911111110021"),
        json={"start_time": _iso(house_b_start), "duration_minutes": 15},
    )
    assert house_b_booking.status_code == 201

    members = (
        await client.get(f"/api/v1/groups/{house_a['id']}/members", headers=auth_headers("uid-rec-21", "+911111110021"))
    ).json()
    my_membership_id = next(m["id"] for m in members if m["user_id"] == member["id"])

    leave = await client.delete(
        f"/api/v1/memberships/{my_membership_id}", headers=auth_headers("uid-rec-21", "+911111110021")
    )
    assert leave.status_code == 204

    # House A: nothing of theirs remains — the series's occurrences and
    # the ad-hoc booking are both gone, and the orphaned series row itself
    # is cleaned up (zero remaining occurrences, previous owner gone).
    house_a_reservations = (
        await client.get(f"/api/v1/groups/{house_a['id']}/reservations", headers=auth_headers("uid-rec-22", "+911111110022"))
    ).json()
    assert house_a_reservations == []

    house_a_series = (
        await client.get(f"/api/v1/groups/{house_a['id']}/recurring-series", headers=auth_headers("uid-rec-22", "+911111110022"))
    ).json()
    assert all(s["id"] != series_id for s in house_a_series)

    # The freed slot is actually bookable again, not just marked gone —
    # the exact behavior that makes this fix worth doing.
    rebook = await client.post(
        f"/api/v1/groups/{house_a['id']}/spaces/{space_a_id}/reservations",
        headers=auth_headers("uid-rec-22", "+911111110022"),
        json={"start_time": _iso(ad_hoc_start), "duration_minutes": 15},
    )
    assert rebook.status_code == 201

    # House B: completely untouched by the house A departure.
    house_b_reservations = (
        await client.get(f"/api/v1/groups/{house_b['id']}/reservations", headers=auth_headers("uid-rec-21", "+911111110021"))
    ).json()
    assert len(house_b_reservations) == 1
    assert house_b_reservations[0]["id"] == house_b_booking.json()["reservation"]["id"]


async def test_admin_cancelling_someone_elses_booking_sends_them_a_push(client, _fake_push):
    """A self-cancel needs no notification; an admin cancelling someone
    else's booking does, since otherwise they'd only find out by
    checking the app or showing up to a space that's no longer theirs.
    """
    await _sign_in(client, "uid-rec-23", "+911111110023", "Admin")
    group = await _create_group(client, "uid-rec-23", "+911111110023")
    space_id = await _first_space_id(client, "uid-rec-23", "+911111110023", group["id"])
    await _join(client, "uid-rec-24", "+911111110024", "Member", group["invite_code"])
    await client.post(
        "/api/v1/device-tokens",
        headers=auth_headers("uid-rec-24", "+911111110024"),
        json={"token": "fake-device-token-rec-24", "platform": "android"},
    )

    start = datetime.now(timezone.utc) + timedelta(hours=1)
    booking = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-rec-24", "+911111110024"),
        json={"start_time": _iso(start), "duration_minutes": 15},
    )
    reservation_id = booking.json()["reservation"]["id"]
    _fake_push.reset_mock()

    cancel = await client.delete(
        f"/api/v1/groups/{group['id']}/reservations/{reservation_id}",
        headers=auth_headers("uid-rec-23", "+911111110023"),
    )
    assert cancel.status_code == 204
    _fake_push.assert_called_once()
    call_kwargs = _fake_push.call_args.kwargs
    assert "cancelled" in call_kwargs["body"].lower()


async def test_self_cancelling_your_own_booking_sends_no_push(client, _fake_push):
    await _sign_in(client, "uid-rec-25", "+911111110025", "A")
    group = await _create_group(client, "uid-rec-25", "+911111110025")
    space_id = await _first_space_id(client, "uid-rec-25", "+911111110025", group["id"])

    start = datetime.now(timezone.utc) + timedelta(hours=1)
    booking = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=auth_headers("uid-rec-25", "+911111110025"),
        json={"start_time": _iso(start), "duration_minutes": 15},
    )
    reservation_id = booking.json()["reservation"]["id"]
    _fake_push.reset_mock()

    await client.delete(
        f"/api/v1/groups/{group['id']}/reservations/{reservation_id}",
        headers=auth_headers("uid-rec-25", "+911111110025"),
    )
    _fake_push.assert_not_called()


async def test_non_member_cannot_create_or_view_recurring_series(client):
    await _sign_in(client, "uid-rec-16", "+911111110016", "Owner")
    group = await _create_group(client, "uid-rec-16", "+911111110016")
    space_id = await _first_space_id(client, "uid-rec-16", "+911111110016", group["id"])
    await _sign_in(client, "uid-rec-17", "+911111110017", "Outsider")

    create = await _create_series(client, "uid-rec-17", "+911111110017", group["id"], space_id, [0])
    assert create.status_code == 403

    listing = await client.get(
        f"/api/v1/groups/{group['id']}/recurring-series", headers=auth_headers("uid-rec-17", "+911111110017")
    )
    assert listing.status_code == 403
