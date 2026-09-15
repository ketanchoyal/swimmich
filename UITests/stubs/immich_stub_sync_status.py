"""Immich API stub for the "sync status" scenario (`SyncStatusUITests`).

Thin on purpose: the OAuth handshake, the server config, the user and a day of
timeline all come from `immich_stub_base`. This file adds the TWO routes a real
backup run needs — the dedup gate and the upload — and nothing else:

    python3 UITests/stubs/immich_stub_sync_status.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/immich-orchestration/sync-status.uitest.log \\
        UITests/stubs/immich_stub_sync_status.py SyncStatusUITests/test_syncStatus \\
        --erase --media <png> --media <png>

WHY THE STUB REMEMBERS ITS CHECKSUMS
    `POST /api/assets/bulk-upload-check` is asked twice in one scenario and the
    two answers must DIFFER, exactly like a real server's:

    * during the run, the stub has nothing → every asset is `accept` → the run
      uploads it (and `POST /api/assets` records the checksum it received);
    * during the screen's "Check server" action, the checksums are known → every
      entry comes back `reject` with the UUID the stub holds it under.

    A stub that always answered `accept` would make the reconciliation forget
    the whole ledger (a `reject` is what keeps an entry: `action == "accept"`
    means "the server no longer has it"), so the tracked counter would drop to
    zero and a scenario asserting it stays put would fail — which is the point.
    It also makes the second request load-bearing: the ledger must have KEPT the
    checksum from the first one, or the stub cannot recognise the asset.

WHAT IS LOGGED
    `req.note(...)` on both routes, so a scenario asserts on what the app SAID,
    not on a screenshot: `checkIds` / `checksums` / `verdicts` for the gate,
    `deviceAssetId` / `checksum` / `fileName` / `serverAssetId` for the upload.
    The upload's `body` is replaced by a summary of the same fields — the raw
    multipart body is a few hundred bytes of PNG that no assertion reads, and
    leaving it in `/__requests` would hide the fields that matter.
"""
import re

from immich_stub_base import STATE, Response, main, router

# The UUID the stub hands back for an uploaded asset. Readable on purpose: the
# ledger stores it, so a log line or a screenshot says at once which server
# asset an upload became.
SERVER_ASSET = "eeeeeeee-6666-4666-8666-%012d"


def _forget_everything():
    """The stub starts as a server that holds nothing, and `/__reset` puts it
    back there: a second run must not be served a rejection for a photo this
    process already forgot it received."""
    STATE["uploaded"] = {}   # checksum → the UUID the server keeps the asset under
    STATE["uploads"] = []    # one record per accepted upload, for the log


_forget_everything()


def _field(body, name):
    """One text field of a `multipart/form-data` body (`MultipartBody` writes
    `name="x"\\r\\n\\r\\n<value>\\r\\n`, fields after the file part)."""
    match = re.search(r'name="%s"\r\n\r\n([^\r\n]*)' % re.escape(name), body)
    return match.group(1) if match else None


def _filename(body):
    """The original file name carried by the multipart file part — the seeded
    photo's own name, which is how a scenario proves the real files went up."""
    match = re.search(r'filename="([^"]*)"', body)
    return match.group(1) if match else None


@router.post("/api/assets/bulk-upload-check")
def bulk_upload_check(req):
    """The dedup gate: an unknown checksum may be uploaded, a known one is the
    server's already (answered with the UUID it lives under)."""
    items = req.body.get("assets") or []
    results = []
    verdicts = []
    for item in items:
        checksum = item.get("checksum")
        known = STATE["uploaded"].get(checksum) if checksum else None
        if known:
            results.append({"id": item.get("id"), "action": "reject",
                            "reason": "duplicate", "assetId": known})
            verdicts.append("reject")
        else:
            results.append({"id": item.get("id"), "action": "accept"})
            verdicts.append("accept")
    req.note(checkIds=[item.get("id") for item in items],
             checksums=[item.get("checksum") for item in items],
             verdicts=verdicts)
    return Response({"results": results})


@router.post("/api/assets")
def upload(req):
    """`POST /api/assets` — the multipart upload of one asset's original.

    The checksum travels in `x-immich-checksum` (the header drives the server's
    dedup table), the asset's identity in the body's `deviceAssetId` field.
    Both are remembered: the next `bulk-upload-check` has to recognise them.
    """
    body = req.body.get("raw", "")
    device_id = _field(body, "deviceAssetId")
    checksum = (req.headers.get("x-immich-checksum") or "").strip()
    server_id = SERVER_ASSET % (len(STATE["uploads"]) + 1)
    STATE["uploads"].append({"deviceAssetId": device_id, "checksum": checksum,
                             "serverAssetId": server_id, "fileName": _filename(body)})
    if checksum:
        STATE["uploaded"][checksum] = server_id
    # `fileCreatedAt` is what identifies a SEEDED photo: Photos renames an
    # imported file to its DCIM name, so the file name alone cannot say which
    # files the launcher seeded (measured: `photo-a.png` arrives as
    # `IMG_0007.PNG`). The seeded files are the ones created the day of the run.
    created_at = _field(body, "fileCreatedAt")
    req.note(upload=True, deviceAssetId=device_id, checksum=checksum,
             fileName=_filename(body), fileCreatedAt=created_at,
             serverAssetId=server_id,
             body={"deviceAssetId": device_id, "checksum": checksum,
                   "fileName": _filename(body), "fileCreatedAt": created_at,
                   "bytes": len(body)})
    return Response({"id": server_id, "status": "created"}, status=201)


@router.reset
def fresh():
    _forget_everything()


if __name__ == "__main__":
    main(label="sync-status")
