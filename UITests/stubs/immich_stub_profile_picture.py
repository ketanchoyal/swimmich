"""Immich API stub for the profile-picture scenario (`ProfilePictureUITests`).

Thin on purpose: everything the app needs to boot, sign in, draw the "Me" hub and
reach a pushed screen comes from `immich_stub_base` (the OAuth handshake, the
server config, `/api/users/me`, the timeline, real PNG thumbnails). This file
adds the three routes the feature under test owns:

    python3 UITests/stubs/immich_stub_profile_picture.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/profile-picture.uitest.log \\
        UITests/stubs/immich_stub_profile_picture.py ProfilePictureUITests/test_profilePicture \\
        --erase --media /tmp/profile-picture-640x480.png

WHAT EACH ROUTE HAS TO PROVE (the screen alone proves nothing):

* `POST /api/users/profile-image` — the app must send a MULTIPART body whose one
  part is a real JPEG carried by the field `file` (never `assetData`, which is the
  asset upload's field). The part is parsed here, not just counted: field name,
  filename, part content type, the JPEG/JFIF marker inside the payload and the
  payload's own byte length (the multipart framing is subtracted from
  `Content-Length`). All of it rides back on `/__requests` via `req.note(...)`.

  Only the FIRST upload succeeds. The second one answers `500` when the scenario
  has armed the refusal (see the control route below), which is how a scenario
  proves "a server failure leaves the previous photo in place": the avatar must
  still be requesting the first stamp's URL and no second stamp may ever appear.

* `DELETE /api/users/profile-image` — `204` with an EMPTY body (the real
  contract; a stub that answered `{"successful": true}` would not exercise the
  no-body path the app has to survive) and clears the published path, so the
  avatar has nothing left to fetch.

* `GET /api/users/{id}/profile-image` — the READ route, `application/octet-stream`
  in production, a real PNG here whose colour derives from `profileChangedAt`: the
  scenario asserts the avatar asked for `?v=<stamp just published>`, which is the
  cache-buster that stops `ImageCache` from reserving the previous photo.

* `GET /api/stub/fail-upload?on=1|0` — the one control route. `/__*` belongs to
  the shell, so a feature switch has to live under `/api/` (it is logged like any
  other request); one-shot on purpose: the armed refusal is consumed by the next
  POST, so a stale flag cannot outlive the step that set it.
"""
import re
import zlib

import immich_stub_base as base
from immich_stub_base import ME, Response, main, router

# MARK: - Fixtures

# The signed-in user's own row, mutated in place: `profilePictureRow` and the
# pushed screen both read `GET /api/users/me`, so the photo the app publishes has
# to exist on the server too - a scenario that only patched the client's copy
# would look identical and prove nothing about the read path.
INITIAL_STAMP = base.ME_USER["profileChangedAt"]

# What each SUCCESSFUL upload publishes. Two distinct values so the wire can tell
# "the new photo is on screen" from "the old one is still there": every
# profile-image GET must carry the first stamp after a refused second upload.
STAMPS = ["2026-09-15T10:00:00.000Z", "2026-09-15T11:00:00.000Z"]

UPLOADED_PATH = "/upload/profile/stub-avatar.jpg"

# One binary field named `file` - `CreateProfileImageDto` has no other member.
FIELD = "file"

FLAGS = {}


def _initial_flags():
    return {"uploads": 0, "succeeded": 0, "deletes": 0, "failUpload": False}


FLAGS.update(_initial_flags())


@router.reset
def _restore():
    """`/__reset`: the server-side photo and every counter go back to nothing.

    Without this hook a second run on the same stub would find a photo already
    published (`ME_USER` is module state, not part of the shell's `STATE`) and
    "the avatar starts on its initials" would pass for the wrong reason.
    """
    base.ME_USER["profileImagePath"] = ""
    base.ME_USER["profileChangedAt"] = INITIAL_STAMP
    base.LOGIN["profileImagePath"] = ""
    FLAGS.clear()
    FLAGS.update(_initial_flags())


# MARK: - Multipart


def _part_names(raw):
    """The `name=` of every part of the body, in order.

    Attached to the log even when the field this stub expects is absent: the
    failure has to NAME the field the app did send (`assetData` is the bug this
    feature exists to avoid), not just say "missing".
    """
    return re.findall(r'(?<![A-Za-z])name="([^"]*)"', raw)


def _multipart_part(req, field):
    """The first part carrying `field`, decoded from the request body.

    The shell hands a non-JSON body over as `{"raw": <utf-8, errors replaced>}`:
    the multipart FRAMING (boundary, `Content-Disposition`, `Content-Type`) is
    ASCII and survives that decoding verbatim, which is what this parses. The
    payload is binary and does not - except for the `JFIF` identifier a JPEG
    carries right after its APP0 marker, which is ASCII and therefore searchable
    here: that is the byte-level proof the part holds a real JPEG.
    """
    raw = req.body.get("raw") or ""
    head, separator, payload = raw.partition("\r\n\r\n")
    if not separator:
        return None
    lines = head.split("\r\n")
    if len(lines) < 2 or not lines[0].startswith("--"):
        return None
    disposition = lines[1]
    if _part_names(disposition) != [field]:
        return None
    boundary = lines[0][2:]
    part_type = ""
    for line in lines[2:]:
        if line.lower().startswith("content-type:"):
            part_type = line.split(":", 1)[1].strip()
    filename = re.search(r'filename="([^"]*)"', disposition)
    total = int(req.headers.get("Content-Length") or 0)
    # `--B\r\n<headers>\r\n\r\n<payload>\r\n--B--\r\n`: everything but the
    # payload is measured, so the payload's own size comes out of the difference.
    framing = len(head) + 4 + len(boundary) + 8
    return {
        "field": field,
        "filename": filename.group(1) if filename else "",
        "partType": part_type,
        "bytes": max(total - framing, 0),
        "jfif": "JFIF" in payload,
        "closed": raw.rstrip().endswith("--%s--" % boundary),
    }


# MARK: - Routes


@router.post("/api/users/profile-image")
def upload_profile_image(req):
    """`POST /api/users/profile-image` - the only write that publishes a photo."""
    FLAGS["uploads"] += 1
    part = _multipart_part(req, FIELD)
    refused = FLAGS["failUpload"]
    # The request-level facts are noted even when the part is not the one this
    # stub wants: a wrong field name then reads as "the request carried
    # ['assetData']" instead of "not a multipart request" (measured - the first
    # version of this note made the negative control's failure message lie).
    req.note(upload=FLAGS["uploads"], refused=refused,
             fields=_part_names(req.body.get("raw") or ""),
             requestType=(req.headers.get("Content-Type") or "").split(";")[0].strip(),
             **(part or {"field": None}))
    if refused:
        # One-shot: consumed here, so a later step cannot inherit the refusal.
        FLAGS["failUpload"] = False
        return Response(
            {"message": "stub refuses profile image", "error": "Internal Server Error",
             "statusCode": 500},
            status=500,
        )
    if part is None or not part["jfif"] or part["bytes"] <= 0:
        return Response(
            {"message": "stub: the profile image part is not a usable JPEG", "error": "Bad Request",
             "statusCode": 400},
            status=400,
        )
    stamp = STAMPS[min(FLAGS["succeeded"], len(STAMPS) - 1)]
    FLAGS["succeeded"] += 1
    base.ME_USER["profileImagePath"] = UPLOADED_PATH
    base.ME_USER["profileChangedAt"] = stamp
    return Response(
        {"userId": ME, "profileImagePath": UPLOADED_PATH, "profileChangedAt": stamp},
        status=201,
    )


@router.delete("/api/users/profile-image")
def delete_profile_image(req):
    """`DELETE /api/users/profile-image` - `204`, no body, no `{id}`."""
    FLAGS["deletes"] += 1
    req.note(deletes=FLAGS["deletes"])
    base.ME_USER["profileImagePath"] = ""
    base.ME_USER["profileChangedAt"] = INITIAL_STAMP
    # An empty BYTES payload, not `""`: a `str` would be JSON-encoded and a 204
    # carrying `""` is not the contract the app's no-body path is written for.
    return Response(b"", status=204)


def avatar_png(seed, size=128):
    """The published photo, as real, decodable PNG bytes that LOOK like a photo.

    Four quadrants and an off-centre disc — the shape of the file the launcher
    seeds — whose palette follows the published stamp, so a replacement would be
    visibly a different picture. The shell's own `png()` paints ONE flat colour,
    and a flat disc leaves the screenshot unable to tell "the avatar draws the
    image the server published" from "the avatar draws an empty placeholder
    circle" (measured: the avatar read as a plain green disc).
    """
    r, g, b = base.PALETTE[sum(seed.encode()) % len(base.PALETTE)]
    rows = []
    for y in range(size):
        row = bytearray(b"\x00")
        for x in range(size):
            if (x - size * 0.68) ** 2 + (y - size * 0.68) ** 2 < (size * 0.2) ** 2:
                row += bytes((20, 20, 25))
            elif y < size // 2:
                row += bytes((r, g, b) if x < size // 2 else (g, b, r))
            else:
                row += bytes((b, r, g) if x < size // 2 else (250, 210, 90))
        rows.append(bytes(row))

    def chunk(kind, data):
        payload = kind + data
        return (len(data).to_bytes(4, "big") + payload
                + (zlib.crc32(payload) & 0xFFFFFFFF).to_bytes(4, "big"))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", size.to_bytes(4, "big") + size.to_bytes(4, "big")
                    + bytes((8, 2, 0, 0, 0)))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 6))
            + chunk(b"IEND", b""))


@router.prefix("GET", "/api/users/")
def profile_image(req):
    """`GET /api/users/{id}/profile-image` - the read route, only for this user.

    `req.rest` is the tail after `/api/users/`; anything that is not the
    profile-image route falls through to the shell (which is what answers
    `/api/users/me` and `/api/users`).
    """
    if not req.rest.endswith("/profile-image"):
        return None
    if req.rest[: -len("/profile-image")] != ME:
        return None
    if not base.ME_USER["profileImagePath"]:
        return Response({"message": "no profile image", "error": "Not Found", "statusCode": 404},
                        status=404)
    # Real, decodable bytes whose colours follow the published stamp; `no-store`
    # for the same reason the thumbnails carry it - the app's image session would
    # otherwise replay a body cached under a URL it was told to forget.
    return Response(avatar_png(base.ME_USER["profileChangedAt"]),
                    ctype="image/png", headers={"Cache-Control": "no-store"})


@router.get("/api/stub/fail-upload")
def arm_failure(req):
    """Control route (see the module docstring): arm or disarm the refusal."""
    FLAGS["failUpload"] = req.params.get("on") == "1"
    return Response({"failUpload": FLAGS["failUpload"]})


if __name__ == "__main__":
    main(label="profile-picture")
