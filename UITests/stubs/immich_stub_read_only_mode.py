"""Immich API stub for the read-only-mode scenario (`ReadOnlyModeUITests`).

Thin on purpose: onboarding, the OAuth handshake, the server config, the user,
the ordinary timeline and the real PNG thumbnails all come from
`immich_stub_base`. This file adds the TWO routes the feature under test needs
to be judged on — and they exist so that the *absence* of traffic means
something:

    python3 UITests/stubs/immich_stub_read_only_mode.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/read-only-mode.uitest.log \\
        UITests/stubs/immich_stub_read_only_mode.py ReadOnlyModeUITests/test_readOnlyMode

WHAT THE SCENARIO READS OFF THIS STUB
    `/__requests`, which the shell logs for every non-`/__*` request. This stub
    deliberately does NOT register `DELETE /api/assets`: the shell already
    answers an unrouted write with `{"successful": true}`, so a delete that is
    *allowed* (read-only mode off) reaches the wire and is logged, and one that
    is *refused* by `ReadOnlyGuardClient.assertWritable()` never leaves the app —
    the log is the whole proof, and it must not be polluted by a route of mine.

    The two routes below are the backup run's traffic, and they are what makes
    "one refusal, not N per-asset failures" measurable: with the mode off the
    app sends one `bulk-upload-check` and one `POST /api/assets` per new photo;
    with the mode on it sends neither.

WHY `bulkUploadCheck` ACCEPTS EVERYTHING
    The engine confronts the server before uploading (a photo already stored
    under the same checksum is skipped). Accepting every candidate is what lets
    at least one upload follow — a stub that rejected would leave the wire with
    no `POST /api/assets` at all, and the mode-off control run would prove
    nothing.
"""
from immich_stub_base import STATE, Response, main, router


@router.post("/api/assets/bulk-upload-check")
def bulk_upload_check(req):
    """Every candidate is new: answer `accept` so the uploads follow."""
    items = req.body.get("assets") or []
    req.note(checked=len(items))
    return Response({"results": [{"id": item.get("id"), "action": "accept"} for item in items]})


@router.post("/api/assets")
def upload_asset(req):
    """One upload = one entry in `/__requests`, `POST /api/assets`.

    The body is multipart, so `_body()` hands it back as `{"raw": …}` — what the
    scenario counts is the request. The checksum header is noted because it is
    the one field of a multipart upload the harness can read back as a
    structured value.
    """
    STATE["uploads"] += 1
    req.note(checksum=req.headers.get("x-immich-checksum"), upload=STATE["uploads"])
    return Response(
        {"id": "dddddddd-1111-4111-8111-%012d" % STATE["uploads"], "status": "created"},
        status=201,
    )


@router.reset
def fresh():
    """`/__reset` runs this after wiping `STATE`: a run never inherits a count."""
    STATE["uploads"] = 0


if __name__ == "__main__":
    main(label="read-only-mode")
