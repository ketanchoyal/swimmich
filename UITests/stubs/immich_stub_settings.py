"""Immich API stub for the "settings-parity" scenario (`SettingsParityUITests`).

Everything the app needs to boot, sign in, draw a day of timeline and open the
photo viewer comes from `immich_stub_base` — the OAuth handshake, the server
config, `/api/users/me`, the bucket payload, real PNG thumbnails, `/__requests`,
`/__reset`. This file adds the ONE route the feature under test is judged on:

    GET /api/assets/{id}/original

`Preferences → Viewer → Load Full Quality` decides which of the two media URLs
the zoomable page asks for: the transcoded preview
(`/api/assets/{id}/thumbnail?size=fullsize`, what the app asks for by default) or
the original file. Serving the SAME picture on both would let the scenario pass
with the setting wired to nothing — the bytes, and therefore the screen, would be
identical either way. So the original is deliberately a DIFFERENT colour: the
palette `png()` picks is keyed on the fingerprint, and `original_fingerprint`
below searches for a fingerprint that lands three palette entries away from the
preview's own. The screenshot taken with "Load Full Quality" on is thus a
different photo from the one taken before it, on top of the wire assertion that
names the route.

    python3 UITests/stubs/immich_stub_settings.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/settings-parity.uitest.log \\
        UITests/stubs/immich_stub_settings.py SettingsParityUITests/test_settingsParity

Nothing else here is feature-local, and that is the point of the card: a
preference is a device-local choice, so the scenario asserts that the whole
interaction — change, relaunch, reset — puts NO writing request on this wire.
A stub that grew a `/api/users/me/preferences` route for the scenario to
observe would have invented the very endpoint the feature says does not exist.
"""
from immich_stub_base import PALETTE, Response, main, png, router


def original_fingerprint(asset_id):
    """A fingerprint whose PNG colour differs from the preview's own.

    `png()` maps `sum(fingerprint.encode()) % len(PALETTE)` onto a six-colour
    palette, so "the same picture in a bigger file" is exactly what two
    fingerprints in the same slot would look like — a green that proved nothing
    about which URL was fetched. This walks a counter until the fingerprint
    lands three entries away, which is stable for a given asset id.
    """
    preview = sum(asset_id.encode()) % len(PALETTE)
    wanted = (preview + 3) % len(PALETTE)
    for attempt in range(1, 64):
        candidate = f"original-{asset_id}-{attempt}"
        if sum(candidate.encode()) % len(PALETTE) == wanted:
            return candidate
    return f"original-{asset_id}"


@router.prefix("GET", "/api/assets/")
def original_file(req):
    """The original file — the payload "Load Full Quality" switches to.

    `None` for every other `/api/assets/…` path (the `AssetResponseDto` of
    `{id}`, the `thumbnail` a grid tile asks for): the shell keeps answering
    those, and this stub stays additive. `note()` puts the quality axis on the
    request log itself, so `/__requests` says which rendition was asked for
    without the scenario having to read image bytes.
    """
    parts = req.rest.split("/")
    if len(parts) != 2 or parts[1] != "original":
        return None
    asset_id = parts[0]
    req.note(quality="original")
    return Response(png(original_fingerprint(asset_id), size=64),
                    ctype="application/octet-stream",
                    headers={"Cache-Control": "no-store"})


if __name__ == "__main__":
    main(label="settings")
