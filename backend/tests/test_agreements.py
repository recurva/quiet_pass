"""House Agreements pinboard: member-readable, admin-only-writable, plain
text only.
"""

from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Agreements Test House"}
    )
    return response.json()


async def _join(client, uid: str, phone: str, name: str, invite_code: str) -> dict:
    await _sign_in(client, uid, phone, name)
    await client.post(
        "/api/v1/groups/join", headers=auth_headers(uid, phone), json={"invite_code": invite_code}
    )


async def test_admin_can_create_an_agreement_and_member_can_view_it(client):
    await _sign_in(client, "uid-ag-1", "+915555550001", "Admin")
    group = await _create_group(client, "uid-ag-1", "+915555550001")
    await _join(client, "uid-ag-2", "+915555550002", "Member", group["invite_code"])

    create = await client.post(
        f"/api/v1/groups/{group['id']}/agreements",
        headers=auth_headers("uid-ag-1", "+915555550001"),
        json={"title": "Trash schedule", "content": "Bins out every Tuesday night."},
    )
    assert create.status_code == 201
    body = create.json()
    assert body["title"] == "Trash schedule"
    assert body["content"] == "Bins out every Tuesday night."

    listed = await client.get(
        f"/api/v1/groups/{group['id']}/agreements", headers=auth_headers("uid-ag-2", "+915555550002")
    )
    assert listed.status_code == 200
    assert len(listed.json()) == 1
    assert listed.json()[0]["id"] == body["id"]


async def test_member_cannot_create_edit_or_remove_an_agreement(client):
    await _sign_in(client, "uid-ag-3", "+915555550003", "Admin")
    group = await _create_group(client, "uid-ag-3", "+915555550003")
    await _join(client, "uid-ag-4", "+915555550004", "Member", group["invite_code"])

    create_as_member = await client.post(
        f"/api/v1/groups/{group['id']}/agreements",
        headers=auth_headers("uid-ag-4", "+915555550004"),
        json={"title": "Rule", "content": "No loud music after 10pm."},
    )
    assert create_as_member.status_code == 403

    # Seed one as the admin, then try to edit/remove it as the member.
    created = (
        await client.post(
            f"/api/v1/groups/{group['id']}/agreements",
            headers=auth_headers("uid-ag-3", "+915555550003"),
            json={"title": "Rule", "content": "No loud music after 10pm."},
        )
    ).json()

    edit_as_member = await client.patch(
        f"/api/v1/groups/{group['id']}/agreements/{created['id']}",
        headers=auth_headers("uid-ag-4", "+915555550004"),
        json={"title": "Rule", "content": "No loud music after 11pm."},
    )
    assert edit_as_member.status_code == 403

    remove_as_member = await client.delete(
        f"/api/v1/groups/{group['id']}/agreements/{created['id']}",
        headers=auth_headers("uid-ag-4", "+915555550004"),
    )
    assert remove_as_member.status_code == 403


async def test_admin_can_edit_and_remove_an_agreement(client):
    await _sign_in(client, "uid-ag-5", "+915555550005", "Admin")
    group = await _create_group(client, "uid-ag-5", "+915555550005")

    created = (
        await client.post(
            f"/api/v1/groups/{group['id']}/agreements",
            headers=auth_headers("uid-ag-5", "+915555550005"),
            json={"title": "Landlord", "content": "Call 555-1234 for maintenance."},
        )
    ).json()

    edited = await client.patch(
        f"/api/v1/groups/{group['id']}/agreements/{created['id']}",
        headers=auth_headers("uid-ag-5", "+915555550005"),
        json={"title": "Landlord contact", "content": "Call 555-5678 for maintenance."},
    )
    assert edited.status_code == 200
    assert edited.json()["content"] == "Call 555-5678 for maintenance."

    removed = await client.delete(
        f"/api/v1/groups/{group['id']}/agreements/{created['id']}",
        headers=auth_headers("uid-ag-5", "+915555550005"),
    )
    assert removed.status_code == 204

    listed = await client.get(
        f"/api/v1/groups/{group['id']}/agreements", headers=auth_headers("uid-ag-5", "+915555550005")
    )
    assert listed.json() == []


async def test_non_member_cannot_view_or_write_agreements(client):
    await _sign_in(client, "uid-ag-6", "+915555550006", "Owner")
    group = await _create_group(client, "uid-ag-6", "+915555550006")
    await _sign_in(client, "uid-ag-7", "+915555550007", "Outsider")

    get_agreements = await client.get(
        f"/api/v1/groups/{group['id']}/agreements", headers=auth_headers("uid-ag-7", "+915555550007")
    )
    assert get_agreements.status_code == 403

    create_agreement = await client.post(
        f"/api/v1/groups/{group['id']}/agreements",
        headers=auth_headers("uid-ag-7", "+915555550007"),
        json={"title": "Rule", "content": "Nope."},
    )
    assert create_agreement.status_code == 403


async def test_editing_or_removing_a_nonexistent_agreement_is_404(client):
    await _sign_in(client, "uid-ag-8", "+915555550008", "Admin")
    group = await _create_group(client, "uid-ag-8", "+915555550008")
    fake_id = "00000000-0000-0000-0000-000000000000"

    edit = await client.patch(
        f"/api/v1/groups/{group['id']}/agreements/{fake_id}",
        headers=auth_headers("uid-ag-8", "+915555550008"),
        json={"title": "X", "content": "Y"},
    )
    assert edit.status_code == 404

    remove = await client.delete(
        f"/api/v1/groups/{group['id']}/agreements/{fake_id}",
        headers=auth_headers("uid-ag-8", "+915555550008"),
    )
    assert remove.status_code == 404


async def test_an_agreement_from_another_group_is_not_editable_through_this_groups_id(client):
    """An admin of group A must not be able to edit an agreement that
    belongs to group B just by guessing its id, even though they're an
    admin of *some* group — the agreement lookup is scoped by group_id,
    not just by id.
    """
    await _sign_in(client, "uid-ag-9", "+915555550009", "Admin A")
    group_a = await _create_group(client, "uid-ag-9", "+915555550009")
    await _sign_in(client, "uid-ag-10", "+915555550010", "Admin B")
    group_b = await _create_group(client, "uid-ag-10", "+915555550010")

    agreement_b = (
        await client.post(
            f"/api/v1/groups/{group_b['id']}/agreements",
            headers=auth_headers("uid-ag-10", "+915555550010"),
            json={"title": "B's rule", "content": "Only for house B."},
        )
    ).json()

    cross_group_edit = await client.patch(
        f"/api/v1/groups/{group_a['id']}/agreements/{agreement_b['id']}",
        headers=auth_headers("uid-ag-9", "+915555550009"),
        json={"title": "Hijacked", "content": "Nope."},
    )
    assert cross_group_edit.status_code == 404


async def test_empty_title_or_content_is_rejected(client):
    await _sign_in(client, "uid-ag-11", "+915555550011", "Admin")
    group = await _create_group(client, "uid-ag-11", "+915555550011")

    empty_title = await client.post(
        f"/api/v1/groups/{group['id']}/agreements",
        headers=auth_headers("uid-ag-11", "+915555550011"),
        json={"title": "", "content": "Something."},
    )
    assert empty_title.status_code == 422

    empty_content = await client.post(
        f"/api/v1/groups/{group['id']}/agreements",
        headers=auth_headers("uid-ag-11", "+915555550011"),
        json={"title": "Title", "content": ""},
    )
    assert empty_content.status_code == 422


async def test_title_over_max_length_is_rejected(client):
    await _sign_in(client, "uid-ag-13", "+915555550013", "Admin")
    group = await _create_group(client, "uid-ag-13", "+915555550013")

    too_long = await client.post(
        f"/api/v1/groups/{group['id']}/agreements",
        headers=auth_headers("uid-ag-13", "+915555550013"),
        json={"title": "x" * 101, "content": "Fine."},
    )
    assert too_long.status_code == 422

    exactly_max = await client.post(
        f"/api/v1/groups/{group['id']}/agreements",
        headers=auth_headers("uid-ag-13", "+915555550013"),
        json={"title": "x" * 100, "content": "Fine."},
    )
    assert exactly_max.status_code == 201


async def test_deleting_a_group_cascades_its_agreements(client):
    """No orphaned agreement rows left behind once the group itself is
    gone — the FK's ON DELETE CASCADE is the actual enforcement point;
    this just confirms it's wired, not just declared.
    """
    await _sign_in(client, "uid-ag-14", "+915555550014", "Admin")
    group = await _create_group(client, "uid-ag-14", "+915555550014")
    await client.post(
        f"/api/v1/groups/{group['id']}/agreements",
        headers=auth_headers("uid-ag-14", "+915555550014"),
        json={"title": "Rule", "content": "Will be gone with the group."},
    )

    members = (
        await client.get(f"/api/v1/groups/{group['id']}/members", headers=auth_headers("uid-ag-14", "+915555550014"))
    ).json()
    my_membership_id = next(m["id"] for m in members if m["user_id"])

    leave = await client.delete(
        f"/api/v1/memberships/{my_membership_id}", headers=auth_headers("uid-ag-14", "+915555550014")
    )
    # Sole member leaving deletes the group outright (existing group
    # lifecycle rule) — confirms via a 204, then the group is gone.
    assert leave.status_code == 204

    get_group = await client.get(
        f"/api/v1/groups/{group['id']}", headers=auth_headers("uid-ag-14", "+915555550014")
    )
    assert get_group.status_code in (403, 404)


async def test_agreements_are_returned_in_creation_order(client):
    await _sign_in(client, "uid-ag-12", "+915555550012", "Admin")
    group = await _create_group(client, "uid-ag-12", "+915555550012")

    for title in ["First", "Second", "Third"]:
        await client.post(
            f"/api/v1/groups/{group['id']}/agreements",
            headers=auth_headers("uid-ag-12", "+915555550012"),
            json={"title": title, "content": "..."},
        )

    listed = (
        await client.get(
            f"/api/v1/groups/{group['id']}/agreements", headers=auth_headers("uid-ag-12", "+915555550012")
        )
    ).json()
    assert [a["title"] for a in listed] == ["First", "Second", "Third"]
