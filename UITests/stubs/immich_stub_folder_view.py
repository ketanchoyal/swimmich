"""Immich API stub for the folder view (gap G11, `.omp/folder-view/`).

Thin on purpose: everything the app needs to boot, sign in and draw a grid comes
from `immich_stub_base` (the OAuth handshake, the server config, `/api/users/me`,
a day of timeline, real PNG thumbnails, `/__requests`, `/__reset`). This file
adds the TWO routes the feature owns, plus the control route that empties the
library:

    python3 UITests/stubs/immich_stub_folder_view.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/folder-view.uitest.log \\
        UITests/stubs/immich_stub_folder_view.py FolderViewUITests/test_folderView

TWO ROOTS, TWO LEVELS, ONE EMPTY FOLDER — so the SCREEN says *which* folder was
opened, not merely that a folder was:

* `unique-paths` → `/Photos`, `/Videos` (the two roots the top level shows) and
  `/Videos/2026`. The nested path is load-bearing: `/view/folder` answers
  ASSETS, never folders, so the ONLY source of a folder row is this list.
* `/view/folder?path=/Photos`      → four assets (`dddd…`),
* `/view/folder?path=/Videos`      → two assets (`eeee…`),
* `/view/folder?path=/Videos/2026` → nothing: the server filters that route on
  `visibility = timeline` and `deletedAt is null`, so a folder whose assets were
  all archived since the tree was read comes back empty. That is the
  "empty folder" state — a level that still prints its path bar and holds no row
  and no tile — which must not be confused with the top level of a library that
  has no folder at all (`/control/tree?mode=empty` empties the tree; the folder
  view caches the tree for the life of its ViewModel, so only a fresh launch
  observes it).

The per-folder asset ids are what make "the path was honoured" provable: a grid
that answered `/Photos`' photos for every request would look perfectly healthy,
and a scenario asserting only "some tile appeared" would pass. `COLOUR`-wise the
thumbnails also differ (the shell derives the PNG colour from the asset id), so
a screenshot shows it too.

`/control/tree` is NOT a `/__` route on purpose: the shell answers every `/__…`
itself before consulting a feature router, so a feature control route lives on
its own path and is therefore logged in `/__requests` like any other request.
"""
from immich_stub_base import Response, STATE, asset, main, router

# The two ABSOLUTE roots of the library — both must show on the top level — and
# one nested path, which is what puts a sub-folder row inside `/Videos`.
PATHS = ["/Photos", "/Videos", "/Videos/2026"]

# Per-folder asset ids: distinct so the grid itself says which folder answered.
PHOTOS = [f"dddddddd-1111-4111-8111-{i:012d}" for i in range(1, 5)]
VIDEOS = [f"eeeeeeee-1111-4111-8111-{i:012d}" for i in range(1, 3)]

DAY = "2025-04-01"

# path → [(asset id, file name, minute of the capture stamp)]. The minutes make
# the client-side date order (newest first) deterministic.
FOLDERS = {
    "/Photos": [(PHOTOS[i], f"photos-{i + 1}.jpg", 10 + i) for i in range(len(PHOTOS))],
    "/Videos": [(VIDEOS[i], f"clip-{i + 1}.jpg", 20 + i) for i in range(len(VIDEOS))],
    "/Videos/2026": [],
}


def folder_asset(aid, path, name, minute):
    """One `AssetResponseDto` laid directly in `path`.

    `originalPath` and `originalFileName` are the fields the server's own
    pattern matches on, so they are spelled the way it would spell them: left at
    `asset()`'s placeholder they describe a folder that does not exist.
    """
    dto = asset(aid)
    stamp = f"{DAY}T10:{minute:02d}:00.000Z"
    dto.update({
        "originalPath": f"{path}/{name}",
        "originalFileName": name,
        "localDateTime": stamp,
        "createdAt": stamp,
        "fileCreatedAt": stamp,
        "fileModifiedAt": stamp,
        "updatedAt": stamp,
    })
    dto["exifInfo"] = {**dto["exifInfo"], "dateTimeOriginal": stamp, "modifyDate": stamp}
    return dto


@router.reset
def fresh():
    """`/__reset` puts the library back to a full tree, never an empty one."""
    STATE["tree"] = "full"


@router.get("/api/view/folder/unique-paths")
def unique_paths(req):
    """Every distinct directory holding a timeline asset — no parameter, no
    pagination."""
    return Response([] if STATE.get("tree") == "empty" else PATHS)


@router.get("/api/view/folder")
def folder_assets(req):
    """The assets laid DIRECTLY in `path` — never a recursive listing. An
    unknown path answers an empty folder, exactly as the server does for a
    directory whose assets were archived since `unique-paths` was read."""
    path = req.params.get("path", "")
    return Response([folder_asset(aid, path, name, minute)
                     for aid, name, minute in FOLDERS.get(path, [])])


@router.get("/control/tree")
def switch_tree(req):
    """Empties or refills the library (`?mode=empty|full`)."""
    mode = req.params.get("mode")
    STATE["tree"] = mode if mode in ("full", "empty") else "full"
    return Response({"tree": STATE["tree"]})


if __name__ == "__main__":
    main(label="folder-view")
