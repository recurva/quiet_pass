"""Nudges: anonymity by construction, the quiet-pulse cooldown and daily
cap, and custom-nudge validation/permissions.

Note on "custom nudge create/remove permissions" from the test plan:
there is no delete/remove endpoint for a nudge at all (a nudge is a
fire-and-forget broadcast, never stored for later deletion) — only
*sending* one is gated. This file tests send permissions (member vs.
non-member) and the CUSTOM type's own validation; "remove" isn't a
real code path to test and isn't invented here. Flagged again in the
final report rather than silently skipped.
"""

from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Nudge Test House"}
    )
    return response.json()


async def test_nudge_payload_never_identifies_the_sender(client):
    await _sign_in(client, "uid-nu-1", "+915555550001", "Sender")
    group = await _create_group(client, "uid-nu-1", "+915555550001")

    response = await client.post(
        f"/api/v1/groups/{group['id']}/nudges",
        headers=auth_headers("uid-nu-1", "+915555550001"),
        json={"type": "package_arrived"},
    )
    assert response.status_code == 201
    body = response.json()
    assert set(body.keys()) == {"id", "group_id", "type", "message", "duration_minutes", "created_at"}
    assert "sender_id" not in body
    assert "user_id" not in body


async def test_non_member_cannot_send_a_nudge(client):
    await _sign_in(client, "uid-nu-2", "+915555550002", "Owner")
    group = await _create_group(client, "uid-nu-2", "+915555550002")
    await _sign_in(client, "uid-nu-3", "+915555550003", "Outsider")

    response = await client.post(
        f"/api/v1/groups/{group['id']}/nudges",
        headers=auth_headers("uid-nu-3", "+915555550003"),
        json={"type": "sink_full"},
    )
    assert response.status_code == 403


async def test_quiet_pulse_cooldown_blocks_the_same_sender(client):
    await _sign_in(client, "uid-nu-4", "+915555550004", "A")
    group = await _create_group(client, "uid-nu-4", "+915555550004")

    first = await client.post(
        f"/api/v1/groups/{group['id']}/nudges",
        headers=auth_headers("uid-nu-4", "+915555550004"),
        json={"type": "quiet_pulse", "duration_minutes": 15},
    )
    assert first.status_code == 201

    second = await client.post(
        f"/api/v1/groups/{group['id']}/nudges",
        headers=auth_headers("uid-nu-4", "+915555550004"),
        json={"type": "quiet_pulse", "duration_minutes": 15},
    )
    assert second.status_code == 429


async def test_quiet_pulse_daily_cap_blocks_the_group_regardless_of_sender(client):
    """The cap is per-group, not per-sender — 6 different members each
    sending once (so none of them is individually cooldown-blocked)
    exhausts it, and a 7th distinct member still gets capped.
    """
    await _sign_in(client, "uid-nu-cap-0", "+915555551000", "Creator")
    group = await _create_group(client, "uid-nu-cap-0", "+915555551000")

    # Names must be letters-and-spaces only (see app/schemas/user.py's own
    # validator) — a digit here would 422 the sign-in itself, which is
    # exactly what caught this on the first draft of this test.
    member_names = ["Member One", "Member Two", "Member Three", "Member Four", "Member Five", "Member Six"]
    member_count = 7  # creator + 6 joiners = matches settings.quiet_pulse_daily_cap
    for i in range(1, member_count):
        uid = f"uid-nu-cap-{i}"
        phone = f"+91555555100{i}"
        await _sign_in(client, uid, phone, member_names[i - 1])
        await client.post(
            "/api/v1/groups/join", headers=auth_headers(uid, phone), json={"invite_code": group["invite_code"]}
        )

    senders = [("uid-nu-cap-0", "+915555551000")] + [
        (f"uid-nu-cap-{i}", f"+91555555100{i}") for i in range(1, member_count)
    ]

    statuses = []
    for uid, phone in senders:
        response = await client.post(
            f"/api/v1/groups/{group['id']}/nudges",
            headers=auth_headers(uid, phone),
            json={"type": "quiet_pulse", "duration_minutes": 15},
        )
        statuses.append(response.status_code)

    assert statuses[:6] == [201] * 6
    assert statuses[6] == 429


async def test_custom_nudge_requires_a_message_and_carries_it_verbatim(client):
    await _sign_in(client, "uid-nu-5", "+915555550005", "A")
    group = await _create_group(client, "uid-nu-5", "+915555550005")

    missing_message = await client.post(
        f"/api/v1/groups/{group['id']}/nudges",
        headers=auth_headers("uid-nu-5", "+915555550005"),
        json={"type": "custom"},
    )
    assert missing_message.status_code == 422

    with_message = await client.post(
        f"/api/v1/groups/{group['id']}/nudges",
        headers=auth_headers("uid-nu-5", "+915555550005"),
        json={"type": "custom", "message": "  Running the vacuum in 10 minutes  "},
    )
    assert with_message.status_code == 201
    assert with_message.json()["message"] == "Running the vacuum in 10 minutes"  # stripped


async def test_message_is_rejected_on_a_non_custom_type(client):
    await _sign_in(client, "uid-nu-6", "+915555550006", "A")
    group = await _create_group(client, "uid-nu-6", "+915555550006")

    response = await client.post(
        f"/api/v1/groups/{group['id']}/nudges",
        headers=auth_headers("uid-nu-6", "+915555550006"),
        json={"type": "sink_full", "message": "not allowed here"},
    )
    assert response.status_code == 422
