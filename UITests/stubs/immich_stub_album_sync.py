"""Immich API stub for the album-mirror scenario (`AlbumSyncUITests`).

Thin on purpose: everything the app needs to boot, sign in, reach the Backup
screen and draw the timeline comes from `immich_stub_base` (the OAuth handshake,
the server config, `/api/users/me`, a day of timeline, real PNG thumbnails). This
file adds the two routes a BACKUP RUN needs, and nothing else:

    python3 UITests/stubs/immich_stub_album_sync.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/immich-orchestration/album-sync.uitest.log \\
        UITests/stubs/immich_stub_album_sync.py AlbumSyncUITests/test_albumMirror

WHY THE RUN'S OWN ROUTES LIVE IN AN "ALBUM" STUB
    The mirror is driven by the backup run: `BackupEngine.run()` resolves the
    device→server map before scanning, stages each uploaded asset, and flushes at
    the end. So the scenario that proves the mirror stays SILENT while no album
    is selected has to run a real backup, and a run that cannot finish proves
    nothing — every asset would land in `failures` and the run would end before
    the flush that the assertion is about. Hence the two routes below, which are
    the run's, not the mirror's:

    * `POST /api/assets/bulk-upload-check` — the dedup pass before uploading.
      "accept" for everything: the server has nothing, so the run uploads and
      the ledger records an entry. A non-zero "Tracked photos" is the OTHER half
      of the `canReorganize` guard, and the scenario needs it non-zero to show
      that the guard's album half is what keeps the button disabled.
    * `POST /api/assets` — the upload itself (multipart), answered with a real
      `AssetMediaResponseDto` (`{id, status}`). Left unrouted, this POST falls to
      the shell's generic write acknowledgement (`{"successful": true}`), which
      does not decode: the run would end in a failure per asset.

WHAT IT DELIBERATELY DOES NOT ROUTE
    `/api/albums` (list, create) and `/api/albums/{id}/assets` (the write) stay
    unrouted — and that is the point. The mirror's only visible effect is a
    request to one of those, so the scenario asserts their ABSENCE from
    `/__requests`; a stub that answered them would also be a place to hide the
    call it must not make. The album routes are also the reason this file exists
    at all rather than reusing another feature's stub: the run needs a server
    that says "I hold nothing", which is the shape a mirror-less run must leave
    untouched.
"""
from immich_stub_base import Response, main, router

# The id every upload answers with. The ledger stores it (`serverAssetId`), and
# nothing else reads it: with no album selected there is no album write to
# correlate it with, which is exactly the state this scenario pins down.
UPLOAD_ID = "dddddddd-1111-4111-8111-000000000001"


@router.post("/api/assets/bulk-upload-check")
def bulk_upload_check(req):
    """The run's dedup pass — one `accept` per candidate, so every asset is
    uploaded and the ledger ends up non-empty."""
    items = req.body.get("assets") or []
    # The device ids, so a failure is legible in the request log: a run that
    # checked nothing is a scan bug, not a network bug.
    req.note(ids=[item.get("id") for item in items])
    return Response({"results": [{"id": item["id"], "action": "accept"} for item in items]})


@router.post("/api/assets")
def upload(req):
    """The upload (multipart — which the shell keeps as `{"raw": ...}`), answered
    with the `AssetMediaResponseDto` the client decodes."""
    req.note(uploaded=True)
    return Response({"id": UPLOAD_ID, "status": "created"}, status=201)


if __name__ == "__main__":
    main(label="album-sync")
