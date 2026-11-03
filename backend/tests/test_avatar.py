"""Avatar upload: setting and clearing the URL, owner-only access, and
that it actually shows up in the housemates payload for free (via
UserRead, which every "look up a user" path already returns).
"""

import io

from PIL import Image

from app.core.config import settings
from tests.conftest import auth_headers


async def _sign_in(client, uid: str, phone: str, name: str) -> dict:
    response = await client.post(
        "/api/v1/auth/sign-in", headers=auth_headers(uid, phone), json={"display_name": name}
    )
    return response.json()["user"]


async def _create_group(client, uid: str, phone: str) -> dict:
    response = await client.post(
        "/api/v1/groups", headers=auth_headers(uid, phone), json={"name": "Avatar Test House"}
    )
    return response.json()


def _fake_jpeg_bytes(size: tuple[int, int] = (800, 600)) -> bytes:
    image = Image.new("RGB", size, color=(120, 160, 200))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG")
    return buffer.getvalue()


def _fake_png_with_alpha_bytes(size: tuple[int, int] = (300, 300)) -> bytes:
    image = Image.new("RGBA", size, color=(10, 200, 100, 128))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


async def test_uploading_an_avatar_sets_the_url(client, _fake_avatar_storage):
    user = await _sign_in(client, "uid-av-1", "+919000000001", "A")

    response = await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-1", "+919000000001"),
        files={"file": ("photo.jpg", _fake_jpeg_bytes(), "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["avatar_url"] is not None
    # Not .endswith(...) — the URL carries a cache-busting `?v=` query
    # param after the object path (see test_reuploading_gets_a_different_
    # cache_busted_url below for why).
    assert f"avatars/{user['id']}.jpg?v=" in body["avatar_url"]

    # The actual processed bytes genuinely landed in storage, not just a
    # URL string being returned.
    stored = _fake_avatar_storage.uploaded[f"avatars/{user['id']}.jpg"]
    assert stored[1] == "image/jpeg"
    assert len(stored[0]) > 0


async def test_an_oversized_image_is_downsized_to_the_max_dimension(client, _fake_avatar_storage):
    user = await _sign_in(client, "uid-av-2", "+919000000002", "A")

    response = await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-2", "+919000000002"),
        files={"file": ("big.jpg", _fake_jpeg_bytes(size=(2000, 1500)), "image/jpeg")},
    )
    assert response.status_code == 200

    stored_bytes, _ = _fake_avatar_storage.uploaded[f"avatars/{user['id']}.jpg"]
    resized = Image.open(io.BytesIO(stored_bytes))
    assert max(resized.size) <= 512


async def test_a_png_with_alpha_is_flattened_to_rgb_jpeg(client, _fake_avatar_storage):
    """Confirms the RGBA→RGB flattening path specifically (not just "any
    image works") — a JPEG has no alpha channel, so this has to actually
    run, not just pass an RGB image through unchanged.
    """
    user = await _sign_in(client, "uid-av-3", "+919000000003", "A")

    response = await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-3", "+919000000003"),
        files={"file": ("transparent.png", _fake_png_with_alpha_bytes(), "image/png")},
    )
    assert response.status_code == 200

    stored_bytes, content_type = _fake_avatar_storage.uploaded[f"avatars/{user['id']}.jpg"]
    assert content_type == "image/jpeg"
    decoded = Image.open(io.BytesIO(stored_bytes))
    assert decoded.mode == "RGB"


async def test_removing_an_avatar_clears_the_url(client, _fake_avatar_storage):
    user = await _sign_in(client, "uid-av-4", "+919000000004", "A")
    await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-4", "+919000000004"),
        files={"file": ("photo.jpg", _fake_jpeg_bytes(), "image/jpeg")},
    )
    assert f"avatars/{user['id']}.jpg" in _fake_avatar_storage.uploaded

    response = await client.delete(
        "/api/v1/users/me/avatar", headers=auth_headers("uid-av-4", "+919000000004")
    )
    assert response.status_code == 200
    assert response.json()["avatar_url"] is None
    assert f"avatars/{user['id']}.jpg" not in _fake_avatar_storage.uploaded

    me = await client.get("/api/v1/users/me", headers=auth_headers("uid-av-4", "+919000000004"))
    assert me.json()["avatar_url"] is None


async def test_removing_an_avatar_that_was_never_set_is_a_no_op_not_an_error(client):
    await _sign_in(client, "uid-av-5", "+919000000005", "A")
    response = await client.delete(
        "/api/v1/users/me/avatar", headers=auth_headers("uid-av-5", "+919000000005")
    )
    assert response.status_code == 200
    assert response.json()["avatar_url"] is None


async def test_an_invalid_image_is_rejected(client):
    await _sign_in(client, "uid-av-6", "+919000000006", "A")
    response = await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-6", "+919000000006"),
        files={"file": ("notanimage.jpg", b"this is definitely not image data", "image/jpeg")},
    )
    assert response.status_code == 400


async def test_an_oversized_upload_is_rejected_before_processing(client):
    await _sign_in(client, "uid-av-7", "+919000000007", "A")
    too_big = b"x" * (9 * 1024 * 1024)
    response = await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-7", "+919000000007"),
        files={"file": ("huge.jpg", too_big, "image/jpeg")},
    )
    assert response.status_code == 413


async def test_avatar_url_appears_in_the_housemates_payload(client, _fake_avatar_storage):
    """The whole point of adding this to UserRead rather than a bespoke
    field: every "look up a user" path (including the N+1 fetchUser
    behind the housemates list) gets it for free, with no separate
    plumbing.
    """
    a = await _sign_in(client, "uid-av-8", "+919000000008", "A")
    group = await _create_group(client, "uid-av-8", "+919000000008")
    await _sign_in(client, "uid-av-9", "+919000000009", "B")
    await client.post(
        "/api/v1/groups/join", headers=auth_headers("uid-av-9", "+919000000009"), json={"invite_code": group["invite_code"]}
    )

    await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-8", "+919000000008"),
        files={"file": ("photo.jpg", _fake_jpeg_bytes(), "image/jpeg")},
    )

    a_profile = await client.get(f"/api/v1/users/{a['id']}", headers=auth_headers("uid-av-9", "+919000000009"))
    assert a_profile.status_code == 200
    assert a_profile.json()["avatar_url"] is not None
    assert f"avatars/{a['id']}.jpg?v=" in a_profile.json()["avatar_url"]


async def test_reuploading_gets_a_different_cache_busted_url(client, _fake_avatar_storage):
    """The GCS object path (avatars/{user_id}.jpg) never changes between
    uploads -- it's overwritten in place by design (avatar_service's own
    module docstring). Without something that actually changes in the
    URL stored on the user, a replaced photo would show stale bytes
    forever to any client (Flutter's own ImageCache included) that had
    already fetched the old URL, since both the framework-level image
    cache and typical HTTP caching key on the exact URL. This is the
    regression test for that: two uploads for the same user must produce
    two different avatar_url values, even though the underlying object
    name is identical both times.
    """
    user = await _sign_in(client, "uid-av-12", "+919000000012", "A")

    first = await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-12", "+919000000012"),
        files={"file": ("first.jpg", _fake_jpeg_bytes(), "image/jpeg")},
    )
    first_url = first.json()["avatar_url"]

    second = await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-12", "+919000000012"),
        files={"file": ("second.jpg", _fake_jpeg_bytes(size=(400, 400)), "image/jpeg")},
    )
    second_url = second.json()["avatar_url"]

    assert first_url != second_url
    # Same underlying object both times -- confirms it's the query string
    # doing the cache-busting, not a change to the object path itself
    # (which would mean the old object is now orphaned in the bucket).
    object_path = f"avatars/{user['id']}.jpg"
    expected_base = f"https://storage.googleapis.com/{settings.avatar_bucket_name}/{object_path}"
    assert first_url.split("?")[0] == second_url.split("?")[0] == expected_base
    assert object_path in _fake_avatar_storage.uploaded


async def test_a_user_cannot_set_another_users_avatar(client, _fake_avatar_storage):
    """There's no "avatar for a specific user id" endpoint at all — only
    /users/me/avatar, which always resolves to the caller via
    get_current_user. This confirms uploading as one user never touches
    a different user's row.
    """
    a = await _sign_in(client, "uid-av-10", "+919000000010", "A")
    await _sign_in(client, "uid-av-11", "+919000000011", "B")

    await client.put(
        "/api/v1/users/me/avatar",
        headers=auth_headers("uid-av-11", "+919000000011"),
        files={"file": ("photo.jpg", _fake_jpeg_bytes(), "image/jpeg")},
    )

    a_profile = await client.get(f"/api/v1/users/{a['id']}", headers=auth_headers("uid-av-10", "+919000000010"))
    assert a_profile.json()["avatar_url"] is None
