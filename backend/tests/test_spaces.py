"""Custom spaces: admin-only create/remove, and that removing a space
actually cancels its bookings rather than orphaning them.
"""

from datetime import datetime, timedelta, timezone

from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Spaces Test House"}
    )
    return response.json()


def _iso(dt: datetime) -> str:
    return dt.isoformat()


async def test_admin_can_create_a_custom_space(client):
    await _sign_in(client, "uid-sp-1", "+915555550001", "Admin")
    group = await _create_group(client, "uid-sp-1", "+915555550001")

    before = await client.get(
        f"/api/v1/groups/{group['id']}/spaces", headers=auth_headers("uid-sp-1", "+915555550001")
    )
    seeded_count = len(before.json())

    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces",
        headers=auth_headers("uid-sp-1", "+915555550001"),
        json={"name": "Rooftop"},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Rooftop"
    assert body["group_id"] == group["id"]

    after = await client.get(
        f"/api/v1/groups/{group['id']}/spaces", headers=auth_headers("uid-sp-1", "+915555550001")
    )
    assert len(after.json()) == seeded_count + 1
    assert any(s["name"] == "Rooftop" for s in after.json())


async def test_non_admin_cannot_create_a_space(client):
    await _sign_in(client, "uid-sp-2", "+915555550002", "Admin")
    group = await _create_group(client, "uid-sp-2", "+915555550002")
    await _sign_in(client, "uid-sp-3", "+915555550003", "Member")
    await client.post(
        "/api/v1/groups/join",
        headers=auth_headers("uid-sp-3", "+915555550003"),
        json={"invite_code": group["invite_code"]},
    )

    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces",
        headers=auth_headers("uid-sp-3", "+915555550003"),
        json={"name": "Garage"},
    )
    assert response.status_code == 403


async def test_a_custom_space_name_must_be_non_empty(client):
    await _sign_in(client, "uid-sp-4", "+915555550004", "Admin")
    group = await _create_group(client, "uid-sp-4", "+915555550004")

    response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces",
        headers=auth_headers("uid-sp-4", "+915555550004"),
        json={"name": ""},
    )
    assert response.status_code == 422


async def test_admin_can_remove_a_space_with_no_bookings(client):
    await _sign_in(client, "uid-sp-5", "+915555550005", "Admin")
    group = await _create_group(client, "uid-sp-5", "+915555550005")

    created = await client.post(
        f"/api/v1/groups/{group['id']}/spaces",
        headers=auth_headers("uid-sp-5", "+915555550005"),
        json={"name": "Garage"},
    )
    space_id = created.json()["id"]

    response = await client.delete(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}",
        headers=auth_headers("uid-sp-5", "+915555550005"),
    )
    assert response.status_code == 204

    after = await client.get(
        f"/api/v1/groups/{group['id']}/spaces", headers=auth_headers("uid-sp-5", "+915555550005")
    )
    assert all(s["id"] != space_id for s in after.json())


async def test_non_admin_cannot_remove_a_space(client):
    await _sign_in(client, "uid-sp-6", "+915555550006", "Admin")
    group = await _create_group(client, "uid-sp-6", "+915555550006")
    await _sign_in(client, "uid-sp-7", "+915555550007", "Member")
    await client.post(
        "/api/v1/groups/join",
        headers=auth_headers("uid-sp-7", "+915555550007"),
        json={"invite_code": group["invite_code"]},
    )

    created = await client.post(
        f"/api/v1/groups/{group['id']}/spaces",
        headers=auth_headers("uid-sp-6", "+915555550006"),
        json={"name": "Garage"},
    )
    space_id = created.json()["id"]

    response = await client.delete(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}",
        headers=auth_headers("uid-sp-7", "+915555550007"),
    )
    assert response.status_code == 403


async def test_removing_a_space_cancels_its_bookings_not_orphans_them(client):
    """The core correctness requirement: a reservation (ad-hoc) and a
    recurring series on a custom space must both actually be cancelled
    by the removal, not just left dangling with their space gone out from
    under them.
    """
    await _sign_in(client, "uid-sp-8", "+915555550008", "Booker")
    group = await _create_group(client, "uid-sp-8", "+915555550008")
    await client.post(
        "/api/v1/groups/join",
        headers=auth_headers("uid-sp-8", "+915555550008"),
        json={"invite_code": group["invite_code"]},
    )
    admin_headers = auth_headers("uid-sp-8", "+915555550008")

    created = await client.post(
        f"/api/v1/groups/{group['id']}/spaces", headers=admin_headers, json={"name": "Garage"}
    )
    space_id = created.json()["id"]

    # An ad-hoc booking on the custom space.
    start = datetime.now(timezone.utc) + timedelta(hours=2)
    booking = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/reservations",
        headers=admin_headers,
        json={"start_time": _iso(start), "duration_minutes": 30},
    )
    assert booking.status_code == 201
    chore_id = booking.json()["chore"]["id"]

    # A recurring series on the same space, a different weekday/time so it
    # can't possibly collide with the ad-hoc booking above (a different
    # calendar day's occurrence, regardless of hour).
    # Python's date.weekday() convention (0=Monday..6=Sunday), matching
    # the schema's own field_validator comment.
    other_weekday = (start.weekday() + 3) % 7
    series_response = await client.post(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}/recurring-series",
        headers=admin_headers,
        json={
            "weekdays": [other_weekday],
            "start_hour_utc": 5,
            "start_minute_utc": 0,
            "duration_minutes": 30,
        },
    )
    assert series_response.status_code == 201
    series_body = series_response.json()
    series_id = series_body["series"]["id"]
    assert series_body["created"], "expected at least one materialized occurrence"

    remove_response = await client.delete(
        f"/api/v1/groups/{group['id']}/spaces/{space_id}", headers=admin_headers
    )
    assert remove_response.status_code == 204

    # The ad-hoc reservation and its chore are both gone (chore cascades
    # off the reservation's own deletion).
    chore_check = await client.patch(f"/api/v1/chores/{chore_id}/done", headers=admin_headers)
    assert chore_check.status_code == 404

    # The whole series is gone too.
    my_series = await client.get(
        f"/api/v1/groups/{group['id']}/recurring-series", headers=admin_headers
    )
    assert all(s["id"] != series_id for s in my_series.json())

    # The space itself is gone.
    spaces_after = await client.get(f"/api/v1/groups/{group['id']}/spaces", headers=admin_headers)
    assert all(s["id"] != space_id for s in spaces_after.json())

    # Nothing on the removed space shows up in the group's reservation
    # list either (it would if cancellation had merely detached the space
    # instead of deleting the bookings).
    reservations_after = await client.get(
        f"/api/v1/groups/{group['id']}/reservations", headers=admin_headers
    )
    assert all(r["space_id"] != space_id for r in reservations_after.json())
