"""Immich API stub for the share-extension scenario (`ShareExtensionUITests`).

The stub of the app's half is the shell: `immich_stub_base` serves the OAuth
handshake that signs the app in, and it is that sign-in which mirrors the
session into the shared keychain the extension reads. This file adds the three
routes the EXTENSION owns, and nothing else:

    GET  /api/albums             → the album picker's menu
    POST /api/assets             → the multipart upload of one shared file
    PUT  /api/albums/{id}/assets → the filing that follows a chosen album

    python3 UITests/stubs/immich_stub_share_extension.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/share-extension.uitest.log \\
        UITests/stubs/immich_stub_share_extension.py \\
        ShareExtensionUITests/test_shareExtension

WHY THE UPLOAD IS PARSED, NOT JUST ACCEPTED
    Accepting a multipart body and answering 201 would let a sheet that sent a
    body of the wrong shape look perfectly healthy: the row would turn green on
    an upload the server could never have stored. So the handler reads the real
    `Content-Type` boundary, lists the part names it actually received, and puts
    them in `/__requests` — `assetData` is the file, the four date/device fields
    are the metadata, and `/__requests` is where the scenario proves both.

WHY THE ALBUM IS SERVED
    The picker degrades to "None" when `/api/albums` fails, and a sheet with no
    album still uploads: without an album in this stub the filing half of the
    feature could never be reached by a scenario at all.
"""
import re

from immich_stub_base import Response, main, router

ALBUM_ID = "11111111-2222-4333-8444-555555555555"
ALBUM_NAME = "Stub Album"
# Recognisable on purpose: the scenario asserts the id the sheet filed, and a
# wrong id in the same log is legible at a glance.
UPLOAD_ID = "dddddddd-1111-4111-8111-000000000001"


def _part_names(raw):
    """The `name="…"` of every part of a multipart body, in order.

    Read off the decoded body rather than a real parser: the boundary and the
    part headers are ASCII, and the only bytes that get mangled are the file's
    own payload, which this function never looks at.
    """
    return re.findall(r'(?<!file)name="([^"]+)"', raw)


def _value(raw, name):
    """The text value of a multipart part (`fileCreatedAt`, `deviceId`, …)."""
    match = re.search(r'name="%s"\r\n\r\n(.*?)\r\n' % re.escape(name), raw, re.S)
    return match.group(1) if match else None


@router.get("/api/albums")
def albums(req):
    """One album: enough for a menu, and the only one the scenario files into."""
    req.note(authorization=req.headers.get("Authorization"))
    return Response([{
        "id": ALBUM_ID,
        "albumName": ALBUM_NAME,
        "ownerId": "11111111-1111-4111-8111-111111111111",
        "assetCount": 3,
        "createdAt": "2026-01-01T00:00:00.000Z",
        "updatedAt": "2026-01-01T00:00:00.000Z",
        "shared": False,
        "hasSharedLink": False,
        "isActivityEnabled": True,
        "order": "desc",
        "owner": None,
        "albumThumbnailAssetId": None,
    }])


@router.post("/api/assets")
def upload(req):
    """The extension's multipart upload — parsed, so a wrong body is visible.

    `status: created` (not `duplicate`): a fresh share is a fresh asset, and the
    sheet renders the two the same way, so a stub that always answered
    `duplicate` would hide nothing and prove less.
    """
    raw = req.body.get("raw", "")
    names = _part_names(raw)
    filename = (re.search(r'filename="([^"]*)"', raw) or [None, None])[1]
    req.note(
        parts=names,
        filename=filename,
        asset_data=("assetData" in names),
        file_created_at=_value(raw, "fileCreatedAt"),
        device_asset_id=_value(raw, "deviceAssetId"),
        device_id=_value(raw, "deviceId"),
        checksum=req.headers.get("x-immich-checksum"),
        authorization=req.headers.get("Authorization"),
        content_type=(req.headers.get("Content-Type") or "").split(";")[0],
    )
    return Response({"id": UPLOAD_ID, "status": "created"}, status=201)


@router.prefix("PUT", "/api/albums/")
def add_assets(req):
    """`PUT /api/albums/{id}/assets` with `{"ids": […]}` — the filing step."""
    parts = req.rest.split("/")
    if len(parts) < 2 or parts[1] != "assets":
        return None
    ids = req.body.get("ids") if isinstance(req.body, dict) else None
    req.note(album_id=parts[0], ids=ids)
    return Response([{"id": aid, "success": True, "error": None, "errorMessage": None}
                     for aid in (ids or [])])


if __name__ == "__main__":
    main(label="share-extension")
