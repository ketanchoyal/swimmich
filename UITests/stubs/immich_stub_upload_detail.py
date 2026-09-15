"""Immich API stub for the "upload detail" scenario (`UploadDetailUITests`).

Everything the app needs to boot, sign in and draw a timeline comes from
`immich_stub_base` (the OAuth handshake, the server config, `/api/users/me`, a
day of timeline, real PNG thumbnails). This file adds the two routes a backup
run needs — and the one thing the feature under test owns: a run that fails
EXACTLY ONE asset ON THE WIRE.

    python3 UITests/stubs/immich_stub_upload_detail.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/upload-detail.uitest.log \\
        UITests/stubs/immich_stub_upload_detail.py UploadDetailUITests/test_uploadDetail \\
        --erase --media /tmp/media-a.png --media /tmp/media-b.png

THE FAILURE IS CHOSEN BY IDENTIFIER, NEVER BY ORDER
    `BackupEngine` uploads each candidate straight from the original it already
    exported, so the upload body is a `multipart/form-data` whose `assetData`
    part carries the file and whose text fields carry the Photos
    `deviceAssetId`. The stub parses both out of the body (the base handler
    hands it the raw text as `body["raw"]` — the bytes are not JSON).

    Which asset fails is decided ONCE, from the SET of identifiers the first
    `bulk-upload-check` asked about: the greatest identifier of that set. Photos
    assigns `localIdentifier`s this stub cannot predict and enumerates the
    library in an order that is its own business, so "the first upload fails"
    would make the scenario's verdict depend on Photos' ordering. A set-derived
    choice makes the failing asset stable across the retry — and a scenario can
    name it from `/__requests` alone.

THE SERVER REMEMBERS WHAT IT STORED
    A real Immich answers `reject`/`duplicate` for a checksum it already holds.
    So does this stub, for every identifier it has already accepted: that is
    what makes "the retry re-uploaded only the failed asset" provable even if
    the app ran a second FULL pass for its own reasons — a re-checked asset is
    dedup-rejected instead of being uploaded again, exactly as on a real server.

WHAT IS LOGGED, AND WHY THE ASSERTIONS CAN BE EXACT
    Every route here calls `req.note(...)`, so a `/__requests` entry of an
    upload carries `deviceAssetId`, `filename` and `outcome`
    (`created`/`refused`), and an entry of a check carries `ids` — the wire
    proof the scenario asserts on, instead of re-parsing a multipart body in
    Swift.
"""
import re

from immich_stub_base import Response, STATE, main, router

# `MultipartBody.writeStreamed` writes the file field FIRST (with its filename
# in the disposition) and the text fields after it, so both patterns below see
# an intact value even though the binary part in between decodes to U+FFFD.
FILE_FIELD = re.compile(r'name="assetData"; filename="([^"]*)"')
DEVICE_ASSET_ID_FIELD = re.compile(r'name="deviceAssetId"\r\n\r\n([^\r\n]*)')


def _field(pattern, raw):
    """The first captured value of `pattern` in `raw`, or `""`."""
    match = pattern.search(raw)
    return match.group(1) if match else ""


def _uploaded():
    """`deviceAssetId` → the server id the accepted upload was stored under."""
    return STATE.setdefault("uploaded", {})


def _poison():
    """The one identifier this server refuses to accept (see the docstring)."""
    return STATE.setdefault("poison", "")


@router.post("/api/assets/bulk-upload-check")
def check(req):
    """The dedup question the engine asks before uploading.

    `accept` for anything it does not hold, `reject`/`duplicate` (with the id
    it holds it under) for anything it does — the same answer a real server
    gives, and the reason a second full pass cannot re-upload a healthy asset.
    """
    ids = [item.get("id") for item in ((req.body or {}).get("assets") or [])]
    req.note(ids=ids)
    if not _poison() and ids:
        STATE["poison"] = sorted(ids)[-1]
    uploaded = _uploaded()
    results = []
    for device_id in ids:
        if device_id in uploaded:
            results.append({"action": "reject", "reason": "duplicate", "id": device_id,
                            "assetId": uploaded[device_id], "isTrashed": False})
        else:
            results.append({"action": "accept", "id": device_id})
    return Response({"results": results})


@router.post("/api/assets")
def upload(req):
    """`POST /api/assets` — the upload itself, one asset per request.

    The refused asset answers 500: the engine surfaces `APIError.serverError`
    and the message it read, which is what the per-asset failure row must show.
    """
    raw = (req.body or {}).get("raw", "")
    device_id = _field(DEVICE_ASSET_ID_FIELD, raw)
    refused = device_id != "" and device_id == _poison()
    req.note(filename=_field(FILE_FIELD, raw), deviceAssetId=device_id,
             outcome="refused" if refused else "created")
    if refused:
        return Response({"message": "stub refuses this asset"}, status=500)
    server_id = "5d0cf1a2-1111-4111-8111-%012d" % (len(_uploaded()) + 1)
    _uploaded()[device_id] = server_id
    return Response({"id": server_id, "status": "created"}, status=201)


@router.reset
def fresh():
    """`/__reset` — a scenario must never inherit the previous run's verdicts."""
    STATE["uploaded"] = {}
    STATE["poison"] = ""


if __name__ == "__main__":
    main(label="upload-detail")
