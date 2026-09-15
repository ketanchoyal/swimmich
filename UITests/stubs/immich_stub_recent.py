"""Immich API stub for the "recent" reference scenario (`RecentlyTakenUITests`).

Thin on purpose: everything the app needs to boot, sign in and draw a grid comes
from `immich_stub_base` (the OAuth handshake, the server config, `/api/users/me`,
a day of timeline, real PNG thumbnails). This file adds the ONE thing the feature
under test owns — the two sort axes of `GET /api/timeline/buckets`:

    python3 UITests/stubs/immich_stub_recent.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/recently-taken.uitest.log \\
        UITests/stubs/immich_stub_recent.py RecentlyTakenUITests/test_recentlyTaken

THREE AXES, THREE DAYS — so the SCREEN proves which request produced it:

* no `orderBy` (the Photos tab)      → the shell's own day, 2026-09-01 (`aaaa…`),
* `orderBy=takenAt` ("Recently Taken")  → 2024-07-01, the day the photos were shot
  (`bbbb…`),
* `orderBy=createdAt` ("Recently Added") → 2025-11-20, the day they were uploaded
  (`cccc…`).

That mapping is the whole reason the feature exists: `GET /api/timeline/buckets`
is the ONLY route that can sort by upload date — `POST /api/search/metadata` has
no such order field — so a "recently added" grid cannot be emulated by a search.
A stub that answered the same buckets on all three axes would let the scenario
pass with the sort axis removed; three distinct days make that impossible.

Both routes answer `None` for anything else, which falls through to the shell:
the ordinary timeline keeps its own day and a feature stub stays additive.
"""
from immich_stub_base import Response, bucket_payload, main, router

TAKEN_DAY = "2024-07-01"
ADDED_DAY = "2025-11-20"

# Three photos per day: enough for a row in the grid, and their readable prefix
# tells the two screens apart in a screenshot as well as in an assertion.
TAKEN = [f"bbbbbbbb-1111-4111-8111-{i:012d}" for i in range(1, 4)]
ADDED = [f"cccccccc-1111-4111-8111-{i:012d}" for i in range(1, 4)]

# `orderBy` value → (day, assets). The dict IS the contract: an axis the app
# stops sending simply stops being served.
AXES = {
    "takenAt": (TAKEN_DAY, TAKEN),
    "createdAt": (ADDED_DAY, ADDED),
}
DAYS = {TAKEN_DAY: TAKEN, ADDED_DAY: ADDED}


@router.get("/api/timeline/buckets")
def ordered_buckets(req):
    """One bucket per sort axis — and nothing for the plain timeline."""
    axis = req.params.get("orderBy")
    if axis not in AXES:
        return None
    day, ids = AXES[axis]
    return Response([{"timeBucket": day, "count": len(ids)}])


@router.get("/api/timeline/bucket")
def one_day(req):
    """The day the bucket list just announced, or the shell's own."""
    day = req.params.get("timeBucket")
    if day not in DAYS:
        return None
    return Response(bucket_payload(DAYS[day], day=day))


if __name__ == "__main__":
    main(label="recent")
