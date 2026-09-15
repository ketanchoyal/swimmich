"""Immich API stub for the "On this device" scenario (`LocalLibraryUITests`).

Thin on purpose: the OAuth handshake, the server configuration, `/api/users/me`,
the server's own statistics, one day of timeline and real PNG thumbnails all come
from `immich_stub_base`. This file adds the two routes the feature owns — both
under `/api/assets`, and both deceptively close to the shell's own asset routes:

    python3 UITests/stubs/immich_stub_local_library.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/local-library.uitest.log \\
        UITests/stubs/immich_stub_local_library.py LocalLibraryUITests/test_localLibrary \\
        --media /tmp/ll-a.png --media /tmp/ll-b.png --media /tmp/ll-c.png --erase

    `POST /api/assets/bulk-upload-check` — the feature's only question to the
    server: "which of the files I picked do you already hold?" (`reject` = already
    there, `accept` = send it). The stub answers `reject` for exactly ONE item of
    the batch, so the scenario can prove the screen marks "not on the server" for
    the accepted ones and ONLY those. WHICH item is arbitrary — a real server
    decides on the checksum, and this stub has no way to know the bytes Photos
    handed the app — so the rule is the LAST id of the batch: arbitrary but
    stable, and `req.note(rejected=…, accepted=…)` publishes the answer on
    `/__requests`, which is what lets the scenario name the asset from the WIRE
    instead of guessing which tile got the chip.

    `POST /api/assets` — the upload, as `AssetMediaCreateDto` multipart: the file
    under `assetData`, its name, `deviceAssetId` (the PHAsset localIdentifier) and
    the timestamps. Declaring it exactly is not optional: the shell answers an
    unrouted write with `{"successful": true}`, which does not decode as
    `AssetMediaResponseDto`, so the screen would show an error badge and the
    scenario would read a failure that looks like an app bug. The stub parses the
    two fields the scenario asserts on (`deviceAssetId`, the file name), notes
    them, and answers 201 `{"id", "status": "created"}` like the server does.

    Deliberately NOT here: a memory of what was uploaded (that would be a ledger,
    and dedup by checksum is the real server's job), any persistence of the
    verdict, and any route for the local library itself — the device library is
    PhotoKit's, not the API's.
"""
import re

from immich_stub_base import Response, STATE, main, router

CHECK = "/api/assets/bulk-upload-check"
UPLOAD = "/api/assets"

# `MultipartBody.writeStreamed` writes CRLF-terminated parts. Both fields the
# scenario reads are plain ASCII values, so they survive the stub's text decoding
# of the raw body (the file bytes do not, and are not asserted on).
DEVICE_ASSET_ID = re.compile(r'name="deviceAssetId"\r\n\r\n([^\r\n]+)')
FILE_CREATED_AT = re.compile(r'name="fileCreatedAt"\r\n\r\n([^\r\n]+)')
FILENAME = re.compile(r'name="assetData"; filename="([^"]*)"')


@router.reset
def initial():
    STATE["checks"] = []
    STATE["uploads"] = []


# `/__reset` is not the only way in: a by-hand run (or a first request before the
# scenario's reset) has to find the state, not a KeyError.
initial()


@router.post(CHECK)
def bulk_upload_check(req):
    """One verdict per item: the last one is already on the server."""
    items = req.body.get("assets") or []
    ids = [item.get("id") for item in items]
    # Never `None` in the note: an empty checksum has to be readable as empty
    # (it would mean the app asked the server to dedup on nothing).
    checksums = [item.get("checksum") or "" for item in items]
    rejected = ids[-1:]
    accepted = ids[:-1]

    results = []
    for aid in ids:
        if aid in rejected:
            results.append({"id": aid, "action": "reject", "reason": "duplicate",
                            "assetId": "server-holding-%s" % aid[-4:]})
        else:
            results.append({"id": aid, "action": "accept"})
    req.note(checked=ids, checksums=checksums, rejected=rejected, accepted=accepted)
    STATE["checks"].append({"ids": ids, "rejected": rejected, "accepted": accepted})
    return Response({"results": results})


@router.post(UPLOAD)
def upload(req):
    """One asset, streamed as multipart. What the scenario asserts on is the
    `deviceAssetId` field: it is the PHAsset the bytes came from, so the wire
    says exactly which local assets left the device."""
    raw = req.body.get("raw", "") if isinstance(req.body, dict) else ""
    device = DEVICE_ASSET_ID.search(raw)
    created = FILE_CREATED_AT.search(raw)
    name = FILENAME.search(raw)
    fields = {
        "deviceAssetId": device.group(1) if device else None,
        # The asset's creation date: the ONE field that identifies a media the run
        # seeded, because `simctl addmedia` renames the files on import (a seeded
        # `ll-a.png` lands in DCIM as `IMG_0007.PNG`) and the device's own sample
        # photos — present even on an erased device — are dated years back.
        "fileCreatedAt": created.group(1) if created else None,
        "filename": name.group(1) if name else None,
        "bytes": len(raw),
    }
    req.note(**fields)
    STATE["uploads"].append(fields)
    return Response({"id": "uploaded-%d" % len(STATE["uploads"]), "status": "created"},
                    status=201)


if __name__ == "__main__":
    main(label="local-library")
