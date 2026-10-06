"""Immich API stub for the video-duration scenario (`VideoDurationUITests`).

Thin on purpose: the OAuth handshake, the server config, `/api/users/me`, a day
of timeline and real PNG thumbnails come from `immich_stub_base`. This file adds
the ONE thing the defect owns — the `duration` cells of `GET /api/timeline/bucket`,
which Immich v3 sends in MILLISECONDS:

    python3 UITests/stubs/immich_stub_video_duration.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/video-duration.uitest.log \\
        UITests/stubs/immich_stub_video_duration.py VideoDurationUITests/test_videoDuration \\
        --erase

Four tiles, two of them videos:

* `7173` ms   → "0:07" (the reported clip — read as seconds it read "119:33"),
* `300000` ms → "5:00" (a 5-minute clip — read as seconds it read "3000:00"),

and two photos carrying `duration: None`, which must draw no badge at all. The
badge is the whole point: a surface that keeps the raw cell renders an absurdly
long duration while looking perfectly healthy.

Additive like every feature stub: any other day returns `None` and falls through
to `immich_stub_base`'s own timeline.
"""
from immich_stub_base import Response, bucket_payload, main, router

# The shell's own day (`TIMELINE_DAY` in immich_stub_base): the timeline opens
# on it, so the scenario needs no extra navigation to reach the grid.
DAY = "2026-09-01"

# The shell's asset ids, same shape — the tiles keep the addresses every other
# scenario already knows how to look up.
IDS = [f"aaaaaaaa-1111-4111-8111-{i:012d}" for i in range(1, 5)]

# What the server sends, per tile — the two durations are the values under test.
# The payload is built by `bucket_payload` and these two columns are REPLACED
# wholesale: `isImage` and `duration` are parallel to `id`, and a length mismatch
# shifts the client's index zip (a short day, not a visible error).
DURATIONS = [7173, None, 300_000, None]
IS_IMAGE = [duration is None for duration in DURATIONS]


@router.get("/api/timeline/bucket")
def one_day(req):
    """The shell's day, carrying the two video durations the scenario asserts."""
    if req.params.get("timeBucket") != DAY:
        return None
    payload = bucket_payload(IDS, day=DAY)
    payload["isImage"] = IS_IMAGE
    payload["duration"] = DURATIONS
    return Response(payload)


if __name__ == "__main__":
    main(label="video-duration")
