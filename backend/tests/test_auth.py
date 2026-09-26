"""Auth edge cases: new-vs-returning detection, name-preservation on
return, the deleted-account tombstone, and the phone-exists pre-check.
"""

from urllib.parse import quote

from tests.conftest import auth_headers, make_token


async def test_new_user_is_provisioned_as_new(client):
    response = await client.post(
        "/api/v1/auth/sign-in",
        headers=auth_headers("uid-new-1", "+911111111101"),
        json={"display_name": "Alice"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["is_new"] is True
    assert body["user"]["display_name"] == "Alice"


async def test_returning_user_is_not_new_and_keeps_their_name(client):
    await client.post(
        "/api/v1/auth/sign-in",
        headers=auth_headers("uid-return-1", "+911111111102"),
        json={"display_name": "Bob"},
    )

    # Same uid signs in again, this time via the Sign In screen's path
    # (no display_name at all) — must not touch the name, and must not
    # report is_new a second time.
    response = await client.post(
        "/api/v1/auth/sign-in",
        headers=auth_headers("uid-return-1", "+911111111102"),
        json={},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["is_new"] is False
    assert body["user"]["display_name"] == "Bob"


async def test_signup_on_existing_number_ignores_the_new_name(client):
    await client.post(
        "/api/v1/auth/sign-in",
        headers=auth_headers("uid-existing-1", "+911111111103"),
        json={"display_name": "Carol"},
    )

    # Same phone number, would-be *different* uid in a real client only if
    # Firebase minted a new one — but a genuinely already-registered
    # number always resolves back to the same uid Firebase already has on
    # file, so this is what "signed up again with an existing number"
    # actually looks like at this layer: same uid, a name attached that
    # should be discarded because the account already has one.
    response = await client.post(
        "/api/v1/auth/sign-in",
        headers=auth_headers("uid-existing-1", "+911111111103"),
        json={"display_name": "Someone Else"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["is_new"] is False
    assert body["user"]["display_name"] == "Carol"


async def test_phone_exists_reflects_real_state(client):
    # A literal "+" in a query string means a space once decoded (standard
    # application/x-www-form-urlencoded semantics) — the real Flutter
    # client already percent-encodes this (Uri.encodeQueryComponent, see
    # groups_repository.dart's checkPhoneExists), so the test has to as
    # well or it isn't exercising the same request shape production sends.
    phone = "+911111111104"
    encoded_phone = quote(phone, safe="")

    before = await client.get(f"/api/v1/auth/phone-exists?phone_number={encoded_phone}")
    assert before.json() == {"exists": False}

    await client.post("/api/v1/auth/sign-in", headers=auth_headers("uid-pe-1", phone), json={})

    after = await client.get(f"/api/v1/auth/phone-exists?phone_number={encoded_phone}")
    assert after.json() == {"exists": True}


async def test_deleted_account_tombstone_blocks_a_reused_token(client):
    uid = "uid-tombstone-1"
    phone = "+911111111105"
    token = make_token(uid, phone)

    await client.post("/api/v1/auth/sign-in", headers={"Authorization": f"Bearer {token}"}, json={})

    delete_response = await client.delete(
        "/api/v1/users/me", headers={"Authorization": f"Bearer {token}"}
    )
    assert delete_response.status_code == 204

    # The exact bug this closes: Firebase ID tokens stay cryptographically
    # valid well after the account they name is deleted (nothing here
    # checks revocation) — the same, now-stale token must be rejected,
    # not silently provision a brand-new blank account under the same uid.
    reuse_response = await client.get(
        "/api/v1/users/me", headers={"Authorization": f"Bearer {token}"}
    )
    assert reuse_response.status_code == 401


async def test_a_genuinely_new_uid_for_a_freed_number_still_works(client):
    """The tombstone must be scoped to the *uid*, not the phone number —
    a real resignup after a real deletion gets a different Firebase uid
    for the same number and must provision cleanly.
    """
    phone = "+911111111106"
    old_uid = "uid-freed-old"
    new_uid = "uid-freed-new"

    old_token = make_token(old_uid, phone)
    await client.post("/api/v1/auth/sign-in", headers={"Authorization": f"Bearer {old_token}"}, json={})
    await client.delete("/api/v1/users/me", headers={"Authorization": f"Bearer {old_token}"})

    response = await client.post(
        "/api/v1/auth/sign-in",
        headers=auth_headers(new_uid, phone),
        json={"display_name": "Fresh Start"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["is_new"] is True
    assert body["user"]["display_name"] == "Fresh Start"


async def test_expired_and_invalid_tokens_are_rejected(client):
    expired = await client.get("/api/v1/users/me", headers={"Authorization": "Bearer EXPIRED"})
    assert expired.status_code == 401

    invalid = await client.get("/api/v1/users/me", headers={"Authorization": "Bearer INVALID"})
    assert invalid.status_code == 401

    missing = await client.get("/api/v1/users/me")
    assert missing.status_code == 401
