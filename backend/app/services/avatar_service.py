"""Profile photo upload: resize/compress/strip-EXIF, then store in GCS.

Stored as a single, stable object per user (`avatars/{user_id}.jpg`), not
a new file per upload — a re-upload overwrites the previous one in place,
so there's no orphaned-file cleanup to do and no growing list of old
photos per user. The bucket itself grants public read at the IAM level
(see the one-time `gsutil iam ch allUsers:objectViewer` setup), so no
per-object ACL call or signed URL is needed here — profile photos aren't
sensitive, and every housemate already sees them as normal app UI.

The GCS client resolves credentials via plain Application Default
Credentials: on Cloud Run that's the attached runtime service account
automatically (no impersonation dance like push_service.py needs
specifically for the Firebase Admin SDK); locally it's whatever
`gcloud auth application-default login` set up, which may or may not
have write access to the bucket — same "works in production, may not
work locally without extra setup" shape every other GCP-credentialed
service in this app already has.
"""

import io
import time
import uuid

from google.cloud import storage
from PIL import Image, ImageOps

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)

_client: storage.Client | None = None

# Rejected before ever decoding the image — a cheap guard against someone
# uploading something enormous; the real size reduction happens via the
# resize below, but that still has to load the original into memory first.
MAX_UPLOAD_BYTES = 8 * 1024 * 1024  # 8 MB

_ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}


class AvatarError(Exception):
    """Base for avatar upload failures; routers translate these to HTTP errors."""


class AvatarTooLargeError(AvatarError):
    def __init__(self) -> None:
        super().__init__("Image is too large (max 8 MB).")


class AvatarInvalidImageError(AvatarError):
    def __init__(self) -> None:
        super().__init__("That doesn't look like a valid image.")


def _get_client() -> storage.Client:
    global _client
    if _client is None:
        _client = storage.Client()
    return _client


def _object_name(user_id: uuid.UUID) -> str:
    return f"avatars/{user_id}.jpg"


def _process_image(raw: bytes) -> bytes:
    """Decodes, auto-rotates per EXIF orientation (then the EXIF itself is
    discarded entirely — re-encoding below never carries it forward),
    downsizes to fit within avatar_max_dimension_px on the longer edge
    (never upscales a smaller image), converts to RGB (flattening any
    alpha channel onto white, since the output is a JPEG), and re-encodes
    as JPEG. Raises AvatarInvalidImageError for anything Pillow can't
    decode as an image at all.
    """
    try:
        image = Image.open(io.BytesIO(raw))
        image.load()
    except Exception as exc:
        raise AvatarInvalidImageError() from exc

    image = ImageOps.exif_transpose(image)

    if image.mode in ("RGBA", "LA", "P"):
        background = Image.new("RGB", image.size, (255, 255, 255))
        rgba = image.convert("RGBA")
        background.paste(rgba, mask=rgba.split()[-1])
        image = background
    else:
        image = image.convert("RGB")

    max_dim = settings.avatar_max_dimension_px
    if image.width > max_dim or image.height > max_dim:
        image.thumbnail((max_dim, max_dim), Image.LANCZOS)

    output = io.BytesIO()
    image.save(output, format="JPEG", quality=85, optimize=True)
    return output.getvalue()


def upload_avatar(user_id: uuid.UUID, raw: bytes, content_type: str | None) -> str:
    if len(raw) > MAX_UPLOAD_BYTES:
        raise AvatarTooLargeError()
    if content_type is not None and content_type not in _ALLOWED_CONTENT_TYPES:
        # Not fatal by itself — Pillow's own decode below is the real
        # gate (a mislabeled but genuinely valid image still succeeds) —
        # but an explicitly wrong content type fails fast with a clearer
        # message than whatever Pillow would raise on, say, a PDF.
        raise AvatarInvalidImageError()

    processed = _process_image(raw)

    object_name = _object_name(user_id)
    bucket = _get_client().bucket(settings.avatar_bucket_name)
    blob = bucket.blob(object_name)
    # The object itself is immutable from here on *for this exact URL*:
    # a later re-upload gets a brand new `?v=` below, never this one, so
    # it's safe (and faster for every viewer) to let it be cached
    # essentially forever rather than falling back to GCS's own default.
    blob.cache_control = "public, max-age=31536000, immutable"
    blob.upload_from_string(processed, content_type="image/jpeg")

    # `avatars/{user_id}.jpg` is the same object path on every upload —
    # overwritten in place, by design (see this module's docstring) — so
    # without something that actually changes here, every client's own
    # image cache (Flutter's ImageCache keys purely on URL, decoded
    # bytes and all) and any HTTP-level cache in between keep serving
    # whatever bytes they first saw at this URL, even after the object
    # underneath has genuinely changed. The query string is what breaks
    # that: it has no effect on which GCS object is fetched, but it does
    # change the full URL stored in avatar_url, which is the cache key
    # everywhere that matters client-side. Milliseconds, not seconds, so
    # two uploads within the same second still get distinct URLs.
    version = int(time.time() * 1000)
    url = f"https://storage.googleapis.com/{settings.avatar_bucket_name}/{object_name}?v={version}"
    logger.info("avatar.uploaded", user_id=str(user_id), size_bytes=len(processed))
    return url


def delete_avatar(user_id: uuid.UUID) -> None:
    """Best-effort: a GCS failure here must never block clearing the
    user's own avatar_url, which is the half that actually matters to
    every other client reading this user's profile. Mirrors every other
    best-effort external call in this app (push sends, Redis publishes).
    """
    object_name = _object_name(user_id)
    try:
        bucket = _get_client().bucket(settings.avatar_bucket_name)
        bucket.blob(object_name).delete()
    except Exception as exc:
        logger.warning("avatar.delete_blob_failed", user_id=str(user_id), error=str(exc))
    else:
        logger.info("avatar.deleted", user_id=str(user_id))
