"""Immich API stub for the map-settings scenario (`MapSettingsUITests`).

Everything the app needs to boot, sign in and draw the ordinary timeline comes
from `immich_stub_base`. This file adds the two routes the feature under test
owns, and nothing else:

    python3 UITests/stubs/immich_stub_map_settings.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/map-settings.uitest.log \\
        UITests/stubs/immich_stub_map_settings.py MapSettingsUITests/test_mapSettings

`GET /api/map/markers` — ONE payload per filter shape, so the SCREEN tells which
question was asked:

* no filter (the plain map)             → four markers, city `Stubtown`
* `fileCreatedAfter`/`fileCreatedBefore`→ two markers, city `Rangetown`
* `isFavorite=true`                     → one marker, city `Favtown`

A stub that answered the same markers whatever the query would let the scenario
pass with the bounds removed from the request (the map would look right while
asking the wrong question) and with the single-file marker cache: the city in
the photo sheet is what makes "a NEW request was sent and its answer rendered"
observable, not just "the network was hit". The trio also makes a recycled
cache response legible — the favourites pass would keep showing `Rangetown`.

The query itself is the second half of the proof: the shell logs every request's
decoded `params`, so the scenario reads `fileCreatedAfter`/`fileCreatedBefore`
off `/__requests` rather than trusting the screen.

`GET /api/assets/{id}` — for ONE asset only (`GPS_ASSET`), the base fixture
enriched with EXIF coordinates. The viewer's info panel draws its mini-map and
its tappable preview (gap G14b's `locationMapPreviewButton`) from those
coordinates, so without them the "map from the viewer" half of the card has no
surface to drive at all. Every other asset id falls through to the shell
(`None`), and so do `/thumbnail` and `/original` tails.
"""
from immich_stub_base import Response, asset, main, router

# MARK: - Markers

GPS_ASSET = "aaaaaaaa-1111-4111-8111-000000000001"
# The Eiffel Tower: one real spot, so a screenshot of the mini-map reads as a
# place and not as an ocean.
GPS = (48.8584, 2.2945)

# Every variant sits inside the same 0.02° box: the map fits itself to the
# markers once, so a variant placed elsewhere would fall outside the visible
# region and empty the photo sheet instead of painting it.
CENTRE = (48.8584, 2.2945)


def marker(mid, city, offset):
    """A `MapMarkerResponseDto`. `state` stays null and the country is constant:
    `MapPhoto.placeName` joins whatever is present, so the city alone is what a
    scenario reads on screen."""
    return {
        "id": mid, "lat": CENTRE[0] + offset, "lon": CENTRE[1] + offset,
        "city": city, "state": None, "country": "Stubland",
    }


def cluster(prefix, city, count):
    return [marker(f"{prefix}-1111-4111-8111-{i:012d}", city, i * 0.005)
            for i in range(1, count + 1)]


PLAIN = cluster("dddddddd", "Stubtown", 4)
RANGED = cluster("eeeeeeee", "Rangetown", 2)
FAVORITES = cluster("ffffffff", "Favtown", 1)


@router.get("/api/map/markers")
def map_markers(req):
    """One marker set per filter shape. The shape IS the contract: a parameter
    the app stops sending simply stops selecting its payload."""
    if req.params.get("isFavorite") == "true":
        variant, markers = "favorites", FAVORITES
    elif "fileCreatedAfter" in req.params or "fileCreatedBefore" in req.params:
        variant, markers = "ranged", RANGED
    else:
        variant, markers = "plain", PLAIN
    # Lands in `/__requests`: the served variant, next to the query that asked
    # for it, so the log reads on its own.
    req.note(variant=variant, served=len(markers))
    return Response(markers)


# MARK: - One geolocated asset

@router.prefix("GET", "/api/assets/")
def located_asset(req):
    """The one asset the viewer's info panel is meant to find on a map.

    A prefix route catches the shell's `/thumbnail` and `/original` tails too,
    hence the exact-id test: those fall through to the shell, which serves the
    real PNG bytes.
    """
    if req.rest != GPS_ASSET:
        return None
    payload = asset(GPS_ASSET)
    payload["latitude"], payload["longitude"] = GPS
    payload["city"], payload["country"] = "Stubtown", "Stubland"
    payload["exifInfo"]["latitude"], payload["exifInfo"]["longitude"] = GPS
    payload["exifInfo"]["city"], payload["exifInfo"]["country"] = "Stubtown", "Stubland"
    req.note(located=True)
    return Response(payload)


if __name__ == "__main__":
    main(label="map-settings")
