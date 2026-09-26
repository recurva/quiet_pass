"""Groups and admin succession: the integrity rules a house's admin
status is built on. These are exactly the cases hand-tracing couldn't
fully confirm before — a real test either holds them or it doesn't.
"""

import asyncio

from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str, name: str = "Test House") -> dict:
    response = await client.post("/api/v1/groups", headers=auth_headers(uid, phone), json={"name": name})
    return response.json()


async def _join_group(client, uid: str, phone: str, invite_code: str) -> dict:
    response = await client.post(
        "/api/v1/groups/join", headers=auth_headers(uid, phone), json={"invite_code": invite_code}
    )
    return response.json()


async def _members(client, uid: str, phone: str, group_id: str) -> list[dict]:
    response = await client.get(f"/api/v1/groups/{group_id}/members", headers=auth_headers(uid, phone))
    return response.json()


def _role_of(members: list[dict], user_id: str) -> str | None:
    return next((m["role"] for m in members if m["user_id"] == user_id), None)


def _membership_id_of(members: list[dict], user_id: str) -> str | None:
    return next((m["id"] for m in members if m["user_id"] == user_id), None)


async def test_creator_is_admin_and_joiner_is_member(client):
    a = await _sign_in(client, "uid-ga-1", "+912222220001", "Admin A")
    group = await _create_group(client, "uid-ga-1", "+912222220001")

    b = await _sign_in(client, "uid-ga-2", "+912222220002", "Member B")
    await _join_group(client, "uid-ga-2", "+912222220002", group["invite_code"])

    members = await _members(client, "uid-ga-1", "+912222220001", group["id"])
    assert _role_of(members, a["id"]) == "admin"
    assert _role_of(members, b["id"]) == "member"


async def test_promote_gives_two_admins_then_either_can_demote_the_other(client):
    a = await _sign_in(client, "uid-ga-3", "+912222220003", "A")
    group = await _create_group(client, "uid-ga-3", "+912222220003")
    b = await _sign_in(client, "uid-ga-4", "+912222220004", "B")
    await _join_group(client, "uid-ga-4", "+912222220004", group["invite_code"])

    members = await _members(client, "uid-ga-3", "+912222220003", group["id"])
    b_membership_id = _membership_id_of(members, b["id"])

    promote = await client.patch(
        f"/api/v1/memberships/{b_membership_id}/role?role=admin",
        headers=auth_headers("uid-ga-3", "+912222220003"),
    )
    assert promote.status_code == 200

    members = await _members(client, "uid-ga-3", "+912222220003", group["id"])
    assert _role_of(members, b["id"]) == "admin"

    # Two admins now — demoting one is safe, the other remains.
    a_membership_id = _membership_id_of(members, a["id"])
    demote = await client.patch(
        f"/api/v1/memberships/{a_membership_id}/role?role=member",
        headers=auth_headers("uid-ga-4", "+912222220004"),  # B (now admin) demotes A
    )
    assert demote.status_code == 200

    members = await _members(client, "uid-ga-4", "+912222220004", group["id"])
    assert _role_of(members, a["id"]) == "member"
    assert _role_of(members, b["id"]) == "admin"


async def test_sole_admin_cannot_self_demote_and_orphan_the_house(client):
    a = await _sign_in(client, "uid-ga-5", "+912222220005", "Sole Admin")
    group = await _create_group(client, "uid-ga-5", "+912222220005")
    members = await _members(client, "uid-ga-5", "+912222220005", group["id"])
    a_membership_id = _membership_id_of(members, a["id"])

    response = await client.patch(
        f"/api/v1/memberships/{a_membership_id}/role?role=member",
        headers=auth_headers("uid-ga-5", "+912222220005"),
    )
    assert response.status_code == 409

    # And the house is provably still admin-led afterward, not just "the
    # request failed" — the role must be unchanged.
    members_after = await _members(client, "uid-ga-5", "+912222220005", group["id"])
    assert _role_of(members_after, a["id"]) == "admin"


async def test_last_admin_deleting_account_promotes_longest_standing_member(client):
    a = await _sign_in(client, "uid-ga-6", "+912222220006", "Admin")
    group = await _create_group(client, "uid-ga-6", "+912222220006")
    b = await _sign_in(client, "uid-ga-7", "+912222220007", "First Joiner")
    await _join_group(client, "uid-ga-7", "+912222220007", group["invite_code"])
    c = await _sign_in(client, "uid-ga-8", "+912222220008", "Second Joiner")
    await _join_group(client, "uid-ga-8", "+912222220008", group["invite_code"])

    delete_response = await client.delete(
        "/api/v1/users/me", headers=auth_headers("uid-ga-6", "+912222220006")
    )
    assert delete_response.status_code == 204

    members = await _members(client, "uid-ga-7", "+912222220007", group["id"])
    # B joined before C — B is the one who must inherit admin, not C.
    assert _role_of(members, b["id"]) == "admin"
    assert _role_of(members, c["id"]) == "member"
    assert _role_of(members, a["id"]) is None  # a is gone entirely


async def test_last_admin_leaving_voluntarily_also_promotes_a_successor(client):
    """Same rule, the other entry point (DELETE /memberships/{id} — a
    voluntary leave, not account deletion) — both must enforce it
    identically, not just the account-deletion path.
    """
    a = await _sign_in(client, "uid-ga-9", "+912222220009", "Admin")
    group = await _create_group(client, "uid-ga-9", "+912222220009")
    b = await _sign_in(client, "uid-ga-10", "+912222220010", "Member")
    await _join_group(client, "uid-ga-10", "+912222220010", group["invite_code"])

    members = await _members(client, "uid-ga-9", "+912222220009", group["id"])
    a_membership_id = _membership_id_of(members, a["id"])

    leave_response = await client.delete(
        f"/api/v1/memberships/{a_membership_id}", headers=auth_headers("uid-ga-9", "+912222220009")
    )
    assert leave_response.status_code == 204

    members_after = await _members(client, "uid-ga-10", "+912222220010", group["id"])
    assert _role_of(members_after, b["id"]) == "admin"


async def test_sole_member_deleting_account_deletes_the_house(client):
    await _sign_in(client, "uid-ga-11", "+912222220011", "Solo")
    group = await _create_group(client, "uid-ga-11", "+912222220011")

    delete_response = await client.delete(
        "/api/v1/users/me", headers=auth_headers("uid-ga-11", "+912222220011")
    )
    assert delete_response.status_code == 204

    # Provably gone, not just "no longer visible to the deleted user" —
    # the invite code must not resolve for anyone.
    await _sign_in(client, "uid-ga-12", "+912222220012", "Someone Else")
    join_response = await client.post(
        "/api/v1/groups/join",
        headers=auth_headers("uid-ga-12", "+912222220012"),
        json={"invite_code": group["invite_code"]},
    )
    assert join_response.status_code == 404


async def test_member_removal_cascades_their_membership_only(client):
    """Removing B must not touch A's own membership, and B must lose
    access immediately (403 on a group-scoped endpoint), not just
    disappear from the member list.
    """
    a = await _sign_in(client, "uid-ga-13", "+912222220013", "Admin")
    group = await _create_group(client, "uid-ga-13", "+912222220013")
    b = await _sign_in(client, "uid-ga-14", "+912222220014", "Member")
    await _join_group(client, "uid-ga-14", "+912222220014", group["invite_code"])

    members = await _members(client, "uid-ga-13", "+912222220013", group["id"])
    b_membership_id = _membership_id_of(members, b["id"])

    remove_response = await client.delete(
        f"/api/v1/memberships/{b_membership_id}", headers=auth_headers("uid-ga-13", "+912222220013")
    )
    assert remove_response.status_code == 204

    members_after = await _members(client, "uid-ga-13", "+912222220013", group["id"])
    assert _role_of(members_after, a["id"]) == "admin"  # A untouched
    assert _role_of(members_after, b["id"]) is None  # B gone

    denied = await client.get(
        f"/api/v1/groups/{group['id']}/members", headers=auth_headers("uid-ga-14", "+912222220014")
    )
    assert denied.status_code == 403


async def test_two_concurrent_departures_never_leave_zero_admins(concurrent_client):
    """The race the audit found: two members leaving the same group at
    the same instant, each computing "who's left" from a snapshot taken
    before the other's change was visible. Runs both DELETE calls via
    asyncio.gather over `concurrent_client` — each request gets its own
    real connection (see that fixture's docstring), so this is genuinely
    concurrent traffic hitting the row lock in rebalance_admin_before_departure,
    not two sequential calls dressed up as a concurrency test.
    """
    client = concurrent_client
    a = await _sign_in(client, "uid-race-1", "+912222229001", "A")
    group = await _create_group(client, "uid-race-1", "+912222229001")
    b = await _sign_in(client, "uid-race-2", "+912222229002", "B")
    await _join_group(client, "uid-race-2", "+912222229002", group["invite_code"])
    c = await _sign_in(client, "uid-race-3", "+912222229003", "C")
    await _join_group(client, "uid-race-3", "+912222229003", group["invite_code"])

    members = await _members(client, "uid-race-1", "+912222229001", group["id"])
    a_membership_id = _membership_id_of(members, a["id"])
    b_membership_id = _membership_id_of(members, b["id"])

    # A (the only admin) and B leave at the same instant; C is the only
    # one left standing afterward and must end up admin regardless of
    # which of the two concurrent requests "wins" the race.
    results = await asyncio.gather(
        client.delete(f"/api/v1/memberships/{a_membership_id}", headers=auth_headers("uid-race-1", "+912222229001")),
        client.delete(f"/api/v1/memberships/{b_membership_id}", headers=auth_headers("uid-race-2", "+912222229002")),
    )
    assert all(r.status_code == 204 for r in results)

    members_after = await _members(client, "uid-race-3", "+912222229003", group["id"])
    assert len(members_after) == 1
    assert _role_of(members_after, c["id"]) == "admin"
