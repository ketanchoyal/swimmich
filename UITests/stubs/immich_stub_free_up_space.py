"""Immich API stub for the "free up space" scenario (`FreeUpSpaceUITests`).

WHAT THE FEATURE NEEDS FROM THE SERVER
    "Free Up Space" never deletes an original the server has not confirmed it
    still holds. The ledger only remembers what this device *uploaded* — it is a
    write cache, not the server's truth — so every tracked entry is replayed
    through `POST /api/assets/bulk-upload-check` before an original may leave the
    device:

      * `reject` — "I already have these exact bytes" — is the proof, and the
        asset becomes a cleanup candidate;
      * `accept` — the server does NOT have it (deleted there since the backup,
        purged, or restored from an older backup) — means the local file is the
        only copy left, and it must never be offered.

    That single answer is the whole fixture, so it has to be controllable:

      1. during the backup phase this stub accepts everything, the app uploads
         both seeded photos and records them in its ledger;
      2. before the cleanup scan, the scenario calls `GET /control/held` with the
         one device asset id this server still holds. The other one stands for
         "gone server-side since the backup" — the exact case the guard exists
         for, and the difference between freeing 6 MB and losing a photo.

    `POST /api/assets/bulk-upload-check` is answered per id, never from the
    request count: a stub that rejected everything would let a scenario pass with
    the per-asset guard removed.

ROUTES
    POST /api/assets/bulk-upload-check    reject what we hold, accept the rest
    POST /api/assets                      the upload, as `AssetMediaResponseDto`
    GET  /control/held?ids=a,b            fixture control (logged like any route)

TWO TRAPS THE SHELL DOES NOT COVER

* `POST /api/assets` is unrouted in `immich_stub_base`, whose fallback answers
  `{"successful": true}`. `AssetMediaResponseDto` has no such shape, so EVERY
  upload would fail to decode: the ledger would never record the asset, the
  backup screen would read "0 uploaded", and Free Up Space would have nothing to
  scan (measured while building this fixture). Hence the shape below.
* A `/__…` path never reaches a feature route — the shell answers every `/__*`
  itself (`_control`). The fixture control therefore lives under `/control/`.

    python3 UITests/stubs/immich_stub_free_up_space.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/free-up-space.uitest.log \\
        UITests/stubs/immich_stub_free_up_space.py FreeUpSpaceUITests/test_freeUpSpace \\
        --erase --media /tmp/media-a.png --media /tmp/media-b.png

    The media must carry an OLD modification date (`touch -t 202001011200`):
    `simctl addmedia` takes the asset's creation date from the file, and the
    cutoff presets on screen are all in the past — photos created "now" can
    never be on or before a cutoff the screen can express.

    That date is also the ONLY way to tell the seeded media apart afterwards:
    `simctl addmedia` renames every file to `IMG_000N` in DCIM, and an erased
    device is not an empty library — it ships sample photos of its own, which the
    run uploads too. Hence `multipart_field` below: the upload's `deviceAssetId`
    and `fileCreatedAt` are lifted into the request log, which is how a scenario
    names what it seeded without ever counting an absolute total.
"""
import re
import uuid

from immich_stub_base import Response, STATE, router, main


def multipart_field(raw, name):
    """One text field of a multipart body, by name.

    The upload carries `deviceAssetId` (the `PHAsset.localIdentifier`) and
    `fileCreatedAt`, and those two are what let a scenario name the media it
    seeded. Nothing else can: `simctl addmedia` renames every file to
    `IMG_000N` in DCIM, and an erased device is NOT an empty library — it ships
    its own sample photos — so neither a file name nor a count says which
    assets the run put there.
    """
    match = re.search(r'name="%s"\r\n\r\n(.*?)\r\n' % re.escape(name), raw, re.S)
    return match.group(1) if match else None


@router.reset
def fresh():
    """`/__reset` — a server that holds nothing until it is told otherwise."""
    STATE["held"] = []


@router.get("/control/held")
def set_held(req):
    """Declare which device asset ids this server still holds.

    `ids` is a comma-separated list of `PHAsset.localIdentifier`s — the same
    strings `bulk-upload-check` carries as `id`, `/` and all. An empty list
    means the server holds nothing (everything comes back `accept`).
    """
    ids = [i for i in req.params.get("ids", "").split(",") if i]
    STATE["held"] = ids
    req.note(held=ids)
    return Response({"held": ids})


@router.post("/api/assets/bulk-upload-check")
def bulk_upload_check(req):
    """The guard's only input: per asset, `reject` iff this server holds it."""
    held = set(STATE.get("held", []))
    items = req.body.get("assets", [])
    results = []
    for item in items:
        asset_id = item.get("id")
        mine = asset_id in held
        results.append({
            "id": asset_id,
            # A `reject` carries the UUID the server holds the bytes under; the
            # ledger keeps it. Nothing in this scenario asserts on it.
            "assetId": str(uuid.uuid4()) if mine else None,
            "action": "reject" if mine else "accept",
            "reason": "duplicate" if mine else None,
            "isTrashed": False,
        })
    req.note(ids=[item.get("id") for item in items],
             actions=[result["action"] for result in results])
    return Response({"results": results})


@router.post("/api/assets")
def upload(req):
    """One uploaded original. The body itself is multipart and stays unparsed,
    but its two identity fields are lifted into the log: they are how a scenario
    names the media it seeded (see `multipart_field`)."""
    fields = req.body.get("raw", "") if isinstance(req.body, dict) else ""
    req.note(uploaded=True,
             deviceAssetId=multipart_field(fields, "deviceAssetId"),
             fileCreatedAt=multipart_field(fields, "fileCreatedAt"))
    return Response({"id": str(uuid.uuid4()), "status": "created"}, status=201)


if __name__ == "__main__":
    main(label="free-up-space")
