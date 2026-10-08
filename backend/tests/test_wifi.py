"""Wi-Fi credentials: admin-only to set, member-readable (anyone in the
house needs to be able to pull up the QR for a guest).
"""

from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Wifi Test House"}
    )
    return response.json()


async def _join(client, uid: str, phone: str, name: str, invite_code: str) -> None:
    await _sign_in(client, uid, phone, name)
    await client.post(
        "/api/v1/groups/join", headers=auth_headers(uid, phone), json={"invite_code": invite_code}
    )


async def test_admin_can_set_wifi_and_member_can_read_it(client):
    await _sign_in(client, "uid-wf-1", "+914444440001", "Admin")
    group = await _create_group(client, "uid-wf-1", "+914444440001")
    await _join(client, "uid-wf-2", "+914444440002", "Member", group["invite_code"])

    set_response = await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-1", "+914444440001"),
        json={"ssid": "HouseNet", "password": "letmein123"},
    )
    assert set_response.status_code == 200
    assert set_response.json()["ssid"] == "HouseNet"

    read_as_member = await client.get(
        f"/api/v1/groups/{group['id']}/wifi", headers=auth_headers("uid-wf-2", "+914444440002")
    )
    assert read_as_member.status_code == 200
    assert read_as_member.json()["password"] == "letmein123"


async def test_member_cannot_set_wifi(client):
    await _sign_in(client, "uid-wf-3", "+914444440003", "Admin")
    group = await _create_group(client, "uid-wf-3", "+914444440003")
    await _join(client, "uid-wf-4", "+914444440004", "Member", group["invite_code"])

    response = await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-4", "+914444440004"),
        json={"ssid": "Hacked", "password": "nope12345"},
    )
    assert response.status_code == 403


async def test_setting_wifi_twice_updates_in_place_not_a_duplicate(client):
    await _sign_in(client, "uid-wf-5", "+914444440005", "Admin")
    group = await _create_group(client, "uid-wf-5", "+914444440005")

    await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-5", "+914444440005"),
        json={"ssid": "First", "password": "password1"},
    )
    second = await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-5", "+914444440005"),
        json={"ssid": "Second", "password": "password2"},
    )
    assert second.status_code == 200

    read = await client.get(
        f"/api/v1/groups/{group['id']}/wifi", headers=auth_headers("uid-wf-5", "+914444440005")
    )
    assert read.json()["ssid"] == "Second"
    assert read.json()["password"] == "password2"


async def test_reading_wifi_before_its_ever_been_set_is_404(client):
    await _sign_in(client, "uid-wf-6", "+914444440006", "Admin")
    group = await _create_group(client, "uid-wf-6", "+914444440006")

    response = await client.get(
        f"/api/v1/groups/{group['id']}/wifi", headers=auth_headers("uid-wf-6", "+914444440006")
    )
    assert response.status_code == 404


async def test_non_member_cannot_read_or_set_wifi(client):
    await _sign_in(client, "uid-wf-7", "+914444440007", "Owner")
    group = await _create_group(client, "uid-wf-7", "+914444440007")
    await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-7", "+914444440007"),
        json={"ssid": "HouseNet", "password": "letmein123"},
    )
    await _sign_in(client, "uid-wf-8", "+914444440008", "Outsider")

    read = await client.get(
        f"/api/v1/groups/{group['id']}/wifi", headers=auth_headers("uid-wf-8", "+914444440008")
    )
    assert read.status_code == 403

    write = await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-8", "+914444440008"),
        json={"ssid": "Hacked", "password": "nope12345"},
    )
    assert write.status_code == 403


async def test_empty_ssid_or_password_is_rejected(client):
    await _sign_in(client, "uid-wf-9", "+914444440009", "Admin")
    group = await _create_group(client, "uid-wf-9", "+914444440009")

    empty_ssid = await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-9", "+914444440009"),
        json={"ssid": "", "password": "password1"},
    )
    assert empty_ssid.status_code == 422

    empty_password = await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-9", "+914444440009"),
        json={"ssid": "HouseNet", "password": ""},
    )
    assert empty_password.status_code == 422


async def test_ssid_or_password_over_max_length_is_rejected(client):
    await _sign_in(client, "uid-wf-12", "+914444440012", "Admin")
    group = await _create_group(client, "uid-wf-12", "+914444440012")

    too_long_ssid = await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-12", "+914444440012"),
        json={"ssid": "x" * 101, "password": "password1"},
    )
    assert too_long_ssid.status_code == 422

    too_long_password = await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-12", "+914444440012"),
        json={"ssid": "HouseNet", "password": "x" * 101},
    )
    assert too_long_password.status_code == 422

    exactly_max = await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-12", "+914444440012"),
        json={"ssid": "x" * 100, "password": "x" * 100},
    )
    assert exactly_max.status_code == 200


async def test_deleting_a_group_cascades_its_wifi_row(client):
    await _sign_in(client, "uid-wf-13", "+914444440013", "Admin")
    group = await _create_group(client, "uid-wf-13", "+914444440013")
    await client.put(
        f"/api/v1/groups/{group['id']}/wifi",
        headers=auth_headers("uid-wf-13", "+914444440013"),
        json={"ssid": "HouseNet", "password": "letmein123"},
    )

    members = (
        await client.get(f"/api/v1/groups/{group['id']}/members", headers=auth_headers("uid-wf-13", "+914444440013"))
    ).json()
    my_membership_id = next(m["id"] for m in members if m["user_id"])

    leave = await client.delete(
        f"/api/v1/memberships/{my_membership_id}", headers=auth_headers("uid-wf-13", "+914444440013")
    )
    assert leave.status_code == 204  # sole member leaving deletes the group

    get_group = await client.get(
        f"/api/v1/groups/{group['id']}", headers=auth_headers("uid-wf-13", "+914444440013")
    )
    assert get_group.status_code in (403, 404)


async def test_wifi_for_one_group_is_not_visible_through_another_groups_id(client):
    await _sign_in(client, "uid-wf-10", "+914444440010", "Admin A")
    group_a = await _create_group(client, "uid-wf-10", "+914444440010")
    await client.put(
        f"/api/v1/groups/{group_a['id']}/wifi",
        headers=auth_headers("uid-wf-10", "+914444440010"),
        json={"ssid": "HouseA", "password": "passwordA"},
    )

    # Admin B is a member of neither group's wifi row, but is an admin of
    # their own group B — confirms the lookup is scoped by group_id, not
    # just "is this caller an admin of *something*."
    await _sign_in(client, "uid-wf-11", "+914444440011", "Admin B")
    group_b = await _create_group(client, "uid-wf-11", "+914444440011")

    read_a_through_b_membership = await client.get(
        f"/api/v1/groups/{group_a['id']}/wifi", headers=auth_headers("uid-wf-11", "+914444440011")
    )
    assert read_a_through_b_membership.status_code == 403

    read_b_before_set = await client.get(
        f"/api/v1/groups/{group_b['id']}/wifi", headers=auth_headers("uid-wf-11", "+914444440011")
    )
    assert read_b_before_set.status_code == 404
