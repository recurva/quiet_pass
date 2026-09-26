"""Cross-user authorization: endpoints that should reject a caller who
doesn't share a group with the target (or isn't a member of the group
at all), tested directly rather than assumed from the endpoints that
happen to exercise them in other files.
"""

from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Authz Test House"}
    )
    return response.json()


async def test_get_user_rejects_a_caller_with_no_shared_group(client):
    a = await _sign_in(client, "uid-az-1", "+916666660001", "A")
    await _sign_in(client, "uid-az-2", "+916666660002", "B")  # no group in common with A

    response = await client.get(f"/api/v1/users/{a['id']}", headers=auth_headers("uid-az-2", "+916666660002"))
    assert response.status_code == 403


async def test_get_user_allows_a_caller_who_shares_a_group(client):
    a = await _sign_in(client, "uid-az-3", "+916666660003", "A")
    group = await _create_group(client, "uid-az-3", "+916666660003")
    await _sign_in(client, "uid-az-4", "+916666660004", "B")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-az-4", "+916666660004"), json={"invite_code": group["invite_code"]}
    )

    response = await client.get(f"/api/v1/users/{a['id']}", headers=auth_headers("uid-az-4", "+916666660004"))
    assert response.status_code == 200


async def test_get_user_always_allows_viewing_yourself(client):
    a = await _sign_in(client, "uid-az-5", "+916666660005", "A")
    response = await client.get(f"/api/v1/users/{a['id']}", headers=auth_headers("uid-az-5", "+916666660005"))
    assert response.status_code == 200


async def test_non_member_cannot_view_group_or_its_members(client):
    await _sign_in(client, "uid-az-6", "+916666660006", "Owner")
    group = await _create_group(client, "uid-az-6", "+916666660006")
    await _sign_in(client, "uid-az-7", "+916666660007", "Outsider")

    get_group = await client.get(f"/api/v1/groups/{group['id']}", headers=auth_headers("uid-az-7", "+916666660007"))
    assert get_group.status_code == 403

    get_members = await client.get(
        f"/api/v1/groups/{group['id']}/members", headers=auth_headers("uid-az-7", "+916666660007")
    )
    assert get_members.status_code == 403


async def test_non_member_cannot_view_or_set_status(client):
    await _sign_in(client, "uid-az-8", "+916666660008", "Owner")
    group = await _create_group(client, "uid-az-8", "+916666660008")
    await _sign_in(client, "uid-az-9", "+916666660009", "Outsider")

    get_status = await client.get(
        f"/api/v1/groups/{group['id']}/status", headers=auth_headers("uid-az-9", "+916666660009")
    )
    assert get_status.status_code == 403

    set_status = await client.put(
        f"/api/v1/groups/{group['id']}/status",
        headers=auth_headers("uid-az-9", "+916666660009"),
        json={"status": "open_to_chat"},
    )
    assert set_status.status_code == 403


async def test_only_an_admin_can_change_a_role_or_remove_someone_else(client):
    await _sign_in(client, "uid-az-10", "+916666660010", "Admin")
    group = await _create_group(client, "uid-az-10", "+916666660010")
    b = await _sign_in(client, "uid-az-11", "+916666660011", "Member")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-az-11", "+916666660011"), json={"invite_code": group["invite_code"]}
    )
    c = await _sign_in(client, "uid-az-12", "+916666660012", "Another Member")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-az-12", "+916666660012"), json={"invite_code": group["invite_code"]}
    )

    members = (
        await client.get(f"/api/v1/groups/{group['id']}/members", headers=auth_headers("uid-az-10", "+916666660010"))
    ).json()
    c_membership_id = next(m["id"] for m in members if m["user_id"] == c["id"])

    # B (a plain member, not admin) tries to promote themselves and to
    # remove C — both must be rejected.
    b_membership_id = next(m["id"] for m in members if m["user_id"] == b["id"])
    promote_self = await client.patch(
        f"/api/v1/memberships/{b_membership_id}/role?role=admin", headers=auth_headers("uid-az-11", "+916666660011")
    )
    assert promote_self.status_code == 403

    remove_other = await client.delete(
        f"/api/v1/memberships/{c_membership_id}", headers=auth_headers("uid-az-11", "+916666660011")
    )
    assert remove_other.status_code == 403
