"""Immich API stub for the "sync badge" scenario (`SyncBadgeUITests`).

WHAT THIS ADDS, AND WHY IT IS NOT DECORATION
    A cloud badge on a timeline tile is a claim about a REAL backup run: the
    ledger only knows an asset is on the server because a run asked the server
    and was told so. The shell (`immich_stub_base`) answers neither route such a
    run uses, so this file adds exactly the two of them:

    * `POST /api/assets/bulk-upload-check` — the dedup question. A checksum this
      process has never stored is `accept` (the app then uploads it); a checksum
      it HAS stored (it learned every one of them through the upload route) is
      `reject` with `assetId` = the server UUID it holds it under, exactly like
      the real server. A blanket `reject` would never exercise the upload, and a
      blanket `accept` would make the server forget what it just received.
    * `POST /api/assets` — the multipart upload. Answers `{id, status}`; the id
      is what the app writes into its ledger as `serverAssetId`.

WHY THE UPLOAD ANSWERS WITH THE SHELL'S FIRST TIMELINE UUID
    The badge is drawn on a TIMELINE tile, and a tile is only known by its
    SERVER uuid — the same uuid the shell already serves for the first photo of
    its day. So every upload answers `UPSTREAM`, and the ledger's proof lands on
    exactly one of the six tiles. That is the whole point of the scenario: the
    assertion is "this tile, and no other", which a stub answering a fresh
    random uuid could not support (nothing on screen would carry it).

    EVERY upload, not just the first: an erased simulator already carries six
    sample photos, so a run stages several assets and the stub would otherwise
    have to guess which one the scenario's badge is about. Answering them all
    with `UPSTREAM` keeps the claim observable — one server uuid, one badged
    tile — and the scenario's wire assertions compare the SETS (every uploaded
    asset was asked about first, with the same checksum), never a count.

    python3 UITests/stubs/immich_stub_sync_badge.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/sync-badge.uitest.log \\
        UITests/stubs/immich_stub_sync_badge.py SyncBadgeUITests/test_syncBadge \\
        --media /tmp/sync-badge-media.png --erase

`--media` seeds the Photos library the run reads (a badge with an empty ledger
is unfalsifiable), and `--erase` is what makes the run reproducible: the ledger
lives in the app container, so a leftover entry from a previous run would leave
the second run's timeline badged before anything was backed up.
"""
import re

from immich_stub_base import Response, STATE, TIMELINE_ASSETS, main, router

# The server UUID the upload answers with: the first photo of the shell's own
# day, so a proven upload is visible as a badge on a tile the scenario can name.
UPSTREAM = TIMELINE_ASSETS[0]

# `name="field"\r\n\r\n value` — the textual half of a multipart part. The file
# part carries a `filename=` and a `Content-Type` line before its bytes, so it
# cannot match this and is read by `_filename` instead.
_FIELD = re.compile(r'name="([^"]+)"\r\n\r\n([^\r\n]*)')
_FILENAME = re.compile(r'name="assetData"; filename="([^"]*)"')


def _multipart(req):
    """The textual fields of a multipart body, as a dict.

    The shell decodes every request body as JSON, so a multipart one arrives as
    `{"raw": "<whole body>"}`: the image bytes are mangled by the utf-8 decode,
    but the field NAMES and their (ASCII) values survive — which is what this
    route is asked about. Returning them is not a convenience for the test: it
    is the only way the scenario can assert what the app actually SENT.
    """
    raw = req.body.get("raw", "") if isinstance(req.body, dict) else ""
    return dict(_FIELD.findall(raw))


def _stored():
    """`checksum -> server uuid` of everything this stub has accepted.

    `setdefault` rather than `STATE[...]`: `/__reset` wipes `STATE` back to the
    shell's own keys, and a route must not depend on the hook below having run.
    """
    return STATE.setdefault("stored", {})


@router.post("/api/assets/bulk-upload-check")
def bulk_upload_check(req):
    """One result per asked checksum: `reject` if the server already holds it."""
    stored = _stored()
    items = req.body.get("assets", []) if isinstance(req.body, dict) else []
    results = []
    for item in items:
        checksum = item.get("checksum", "")
        known = stored.get(checksum)
        if known:
            results.append({
                "id": item.get("id"), "action": "reject", "reason": "duplicate",
                "assetId": known, "isTrashed": False,
            })
        else:
            results.append({"id": item.get("id"), "action": "accept"})
    # Noted flat (not as the JSON body) so the scenario's decoder stays a plain
    # `[String: String]`-shaped struct: what it asserts is which assets were
    # asked about and with which checksum, not the shape of a DTO. Every id,
    # not just the first: an erased device already carries sample photos, so a
    # run stages several assets and the scenario has to compare SETS.
    req.note(
        checked=len(items),
        ids=",".join(item.get("id", "") for item in items),
        checksums=",".join(item.get("checksum", "") for item in items),
    )
    return Response({"results": results})


@router.post("/api/assets")
def upload(req):
    """The multipart upload: remembers the checksum, answers a timeline uuid."""
    fields = _multipart(req)
    checksum = req.headers.get("x-immich-checksum") or ""
    if checksum:
        _stored()[checksum] = UPSTREAM
    req.note(
        deviceAssetId=fields.get("deviceAssetId", ""),
        visibility=fields.get("visibility", ""),
        filename=_FILENAME.search(req.body.get("raw", "") if isinstance(req.body, dict) else "").group(1)
        if _FILENAME.search(req.body.get("raw", "") if isinstance(req.body, dict) else "") else "",
        checksum=checksum,
    )
    return Response({"id": UPSTREAM, "status": "created"}, status=201)


@router.reset
def fresh():
    """No run may be served by the previous one's dedup memory."""
    STATE["stored"] = {}


if __name__ == "__main__":
    main(label="sync-badge")
