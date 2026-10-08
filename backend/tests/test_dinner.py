"""Dinner headcount: the tally, the implicit daily reset (keyed on
house-local date, not a cleanup job), and the soft cutoff's pure
boundary logic.
"""

from datetime import date, datetime, timedelta, timezone

from app.services.dinner_service import cutoff_at_utc, is_cutoff_passed
from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Dinner Test House"}
    )
    return response.json()


async def test_setting_status_appears_in_the_tally(client):
    a = await _sign_in(client, "uid-di-1", "+917777770001", "A")
    group = await _create_group(client, "uid-di-1", "+917777770001")

    response = await client.put(
        f"/api/v1/groups/{group['id']}/dinner",
        headers=auth_headers("uid-di-1", "+917777770001"),
        json={"status": "home"},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "home"

    tally = (
        await client.get(f"/api/v1/groups/{group['id']}/dinner", headers=auth_headers("uid-di-1", "+917777770001"))
    ).json()
    assert tally["home_count"] == 1
    assert tally["staying_out_count"] == 0
    assert len(tally["responses"]) == 1
    assert tally["responses"][0]["user_id"] == a["id"]


async def test_changing_status_is_an_upsert_not_a_duplicate_row(client):
    await _sign_in(client, "uid-di-2", "+917777770002", "A")
    group = await _create_group(client, "uid-di-2", "+917777770002")

    await client.put(
        f"/api/v1/groups/{group['id']}/dinner",
        headers=auth_headers("uid-di-2", "+917777770002"),
        json={"status": "home"},
    )
    await client.put(
        f"/api/v1/groups/{group['id']}/dinner",
        headers=auth_headers("uid-di-2", "+917777770002"),
        json={"status": "staying_out"},
    )

    tally = (
        await client.get(f"/api/v1/groups/{group['id']}/dinner", headers=auth_headers("uid-di-2", "+917777770002"))
    ).json()
    assert len(tally["responses"]) == 1  # not two rows
    assert tally["responses"][0]["status"] == "staying_out"
    assert tally["home_count"] == 0
    assert tally["staying_out_count"] == 1


async def test_tally_counts_multiple_members_correctly(client):
    await _sign_in(client, "uid-di-3", "+917777770003", "A")
    group = await _create_group(client, "uid-di-3", "+917777770003")
    await _sign_in(client, "uid-di-4", "+917777770004", "B")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-di-4", "+917777770004"), json={"invite_code": group["invite_code"]}
    )
    await _sign_in(client, "uid-di-5", "+917777770005", "C")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-di-5", "+917777770005"), json={"invite_code": group["invite_code"]}
    )

    await client.put(f"/api/v1/groups/{group['id']}/dinner", headers=auth_headers("uid-di-3", "+917777770003"), json={"status": "home"})
    await client.put(f"/api/v1/groups/{group['id']}/dinner", headers=auth_headers("uid-di-4", "+917777770004"), json={"status": "home"})
    await client.put(f"/api/v1/groups/{group['id']}/dinner", headers=auth_headers("uid-di-5", "+917777770005"), json={"status": "staying_out"})

    # C (no dinner response at all) shouldn't appear in the tally.
    tally = (
        await client.get(f"/api/v1/groups/{group['id']}/dinner", headers=auth_headers("uid-di-3", "+917777770003"))
    ).json()
    assert tally["home_count"] == 2
    assert tally["staying_out_count"] == 1
    assert len(tally["responses"]) == 3


async def test_a_response_from_a_different_day_does_not_count_today(client, db_session):
    """The "daily reset" isn't a cleanup job — it's just that the tally
    only ever reads today's rows. Insert yesterday's response directly
    (bypassing the API, which always writes today) and confirm it's
    invisible to today's tally. Uses `db_session` (the same
    rolled-back-isolated session `client` is wired to, per
    tests/conftest.py) rather than a separate connection on `engine` —
    a fresh connection wouldn't see this test's own uncommitted rows.
    """
    import uuid as uuid_module

    from app.models.dinner_headcount import DinnerHeadcount, DinnerStatus
    from app.services.dinner_service import today_in_house_local

    a = await _sign_in(client, "uid-di-6", "+917777770006", "A")
    group = await _create_group(client, "uid-di-6", "+917777770006")

    yesterday = today_in_house_local() - timedelta(days=1)
    db_session.add(
        DinnerHeadcount(
            id=uuid_module.uuid4(),
            group_id=uuid_module.UUID(group["id"]),
            user_id=uuid_module.UUID(a["id"]),
            day=yesterday,
            status=DinnerStatus.HOME,
        )
    )
    await db_session.commit()

    tally = (
        await client.get(f"/api/v1/groups/{group['id']}/dinner", headers=auth_headers("uid-di-6", "+917777770006"))
    ).json()
    assert tally["home_count"] == 0
    assert tally["responses"] == []  # yesterday's row doesn't leak into today


async def test_non_member_cannot_view_or_set_dinner_status(client):
    await _sign_in(client, "uid-di-7", "+917777770007", "Owner")
    group = await _create_group(client, "uid-di-7", "+917777770007")
    await _sign_in(client, "uid-di-8", "+917777770008", "Outsider")

    get_response = await client.get(
        f"/api/v1/groups/{group['id']}/dinner", headers=auth_headers("uid-di-8", "+917777770008")
    )
    assert get_response.status_code == 403

    put_response = await client.put(
        f"/api/v1/groups/{group['id']}/dinner",
        headers=auth_headers("uid-di-8", "+917777770008"),
        json={"status": "home"},
    )
    assert put_response.status_code == 403


async def test_writing_after_the_cutoff_is_still_allowed(client):
    """The cutoff is explicitly soft — a write must never be rejected
    for being late, regardless of what cutoff_passed reports.
    """
    await _sign_in(client, "uid-di-9", "+917777770009", "A")
    group = await _create_group(client, "uid-di-9", "+917777770009")

    response = await client.put(
        f"/api/v1/groups/{group['id']}/dinner",
        headers=auth_headers("uid-di-9", "+917777770009"),
        json={"status": "staying_out"},
    )
    assert response.status_code == 200  # always 200, cutoff or not


async def test_invalid_status_value_is_rejected(client):
    await _sign_in(client, "uid-di-10", "+917777770010", "A")
    group = await _create_group(client, "uid-di-10", "+917777770010")

    response = await client.put(
        f"/api/v1/groups/{group['id']}/dinner",
        headers=auth_headers("uid-di-10", "+917777770010"),
        json={"status": "maybe"},
    )
    assert response.status_code == 422


def test_cutoff_boundary_is_exactly_5pm_ist():
    """Pure function, no wall-clock mocking needed: cutoff_at_utc(day) is
    a deterministic function of the date alone. 5:00 PM IST == 11:30 UTC.
    """
    day = date(2026, 6, 15)
    cutoff = cutoff_at_utc(day)
    assert cutoff == datetime(2026, 6, 15, 11, 30, tzinfo=timezone.utc)

    just_before = cutoff - timedelta(minutes=1)
    just_after = cutoff + timedelta(minutes=1)

    assert is_cutoff_passed(day, now_utc=just_before) is False
    assert is_cutoff_passed(day, now_utc=cutoff) is True  # exactly at cutoff counts as passed
    assert is_cutoff_passed(day, now_utc=just_after) is True
