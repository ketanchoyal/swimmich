"""Immich API stub for the locked folder (`LockedFolderUITests`, gap G12).

Everything the app needs to boot, sign in and draw a grid comes from
`immich_stub_base` (the OAuth handshake, the server config, `/api/users/me`, the
ordinary day of timeline, real PNG thumbnails). This file adds the one thing the
feature under test owns: the **server-side elevation** that opens the folder.

    python3 UITests/stubs/immich_stub_locked_folder.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/locked-folder.uitest.log \\
        UITests/stubs/immich_stub_locked_folder.py LockedFolderUITests/test_lockedFolder

THE PIN IS THE SERVER'S, NOT THE SCREEN'S — hence four routes, all of them
carrying real state:

* `GET /api/auth/status` is the only judge of the door. `isElevated` false and
  `pinCode` false → the app must show the create door; `isElevated` false and
  `pinCode` true → the PIN door; `isElevated` true → the grid. The stub is the
  only thing that can flip `elevated`, so a screen that opens without a
  successful `POST /api/auth/session/unlock` cannot be explained away.
* `POST /api/auth/pin-code` creates the 6-digit PIN once (a second call is a
  400, like the real server).
* `POST /api/auth/session/unlock` elevates **only** on the right PIN. A wrong
  one is answered `400 Wrong PIN code`, which is what immich-app/immich does
  (`AuthService.validatePinCode` → `BadRequestException`) — deliberately NOT
  401: the app's transport reads a 401 as a dead session and signs the user out
  (`ImmichAPIClient.validate` → `authDelegate`), so a 401 here would test the
  logout path and never the folder's refusal path.
* `POST /api/auth/session/lock` drops it again. The real route takes no body,
  and the request's own headers are recorded (`contentType`, `contentLength`)
  so a scenario can prove what went out was bodyless — an empty JSON `{}` and
  no body at all are indistinguishable in the decoded log otherwise.

THE TWO BUCKET ROUTES ARE FILTERED, AND THE LOCKED DAY IS ITS OWN
    `visibility=locked` answers the folder's day, 2025-03-03 (`dddd…`) — a day
    the ordinary timeline never shows, so a grid that rendered those tiles can
    only have read the locked filter. Without elevation the same read answers an
    EMPTY page rather than a 403: that is exactly why the door is driven by
    `/api/auth/status` and never by the grid's content (an empty folder and an
    unelevated read are indistinguishable). Anything without
    `visibility=locked` returns `None` and falls through to the shell, so a
    feature stub stays additive.
"""
from immich_stub_base import Response, STATE, bucket_payload, main, router

# A day of its own: the shell's ordinary timeline is 2026-09-01 (`aaaa…`), and a
# scenario that saw these tiles has proved which filter answered.
LOCKED_DAY = "2025-03-03"
LOCKED = [f"dddddddd-1111-4111-8111-{i:012d}" for i in range(1, 4)]

# Every mutating route of this feature documents 204, and a 204 carrying
# `json.dumps(None)` would be a body on a status that forbids one.
NO_CONTENT = Response(b"", status=204)


def _bad_request(message):
    """The real server's refusal, `BadRequestException` shape included."""
    return Response({"message": message, "error": "Bad Request", "statusCode": 400}, status=400)


def initial():
    return {"pinCode": None, "elevated": False, "refusals": 0}


@router.reset
def fresh():
    # `/__reset` wipes STATE and calls this: no scenario may be served by a PIN
    # (or an elevation) a previous run left behind.
    STATE.update(initial())


# …and once at import, because the shell's `initial_state()` knows nothing of
# this feature's keys: a stub run by hand (no `/__reset` ever sent) must answer
# its first `/api/auth/status` instead of dying on a missing key.
fresh()


@router.get("/api/auth/status")
def auth_status(req):
    """The account's PIN and the session's elevation — the door's only input."""
    return Response({
        "expiresAt": None,
        "isElevated": STATE["elevated"],
        "password": True,
        "pinCode": STATE["pinCode"] is not None,
        "pinExpiresAt": None,
    })


@router.post("/api/auth/pin-code")
def create_pin(req):
    # Noted before anything else: a REFUSED creation must be as legible in
    # `/__requests` as an accepted one.
    pin = req.body.get("pinCode")
    req.note(submittedPIN=pin)
    if STATE["pinCode"] is not None:
        return _bad_request("User already has a PIN code")
    if not isinstance(pin, str) or len(pin) != 6 or not pin.isdigit():
        return _bad_request("Invalid pin code")
    STATE["pinCode"] = pin
    return NO_CONTENT


@router.post("/api/auth/session/unlock")
def unlock_session(req):
    """Elevates the session, or refuses — the two outcomes the door reads."""
    submitted = req.body.get("pinCode")
    req.note(submittedPIN=submitted)
    if STATE["pinCode"] is None:
        return _bad_request("User does not have a PIN code")
    if submitted != STATE["pinCode"]:
        STATE["refusals"] += 1
        return _bad_request("Wrong PIN code")
    STATE["elevated"] = True
    return NO_CONTENT


@router.post("/api/auth/session/lock")
def lock_session(req):
    """Drops the elevation, bodyless.

    The scenario calls this route too, playing the other client (the 15-minute
    TTL, or a lock from another device) with `{"reason": "expired-elsewhere"}`:
    the app is told nothing, and the two calls are told apart by the headers
    recorded below.
    """
    STATE["elevated"] = False
    req.note(contentType=req.headers.get("Content-Type"),
             contentLength=req.headers.get("Content-Length"))
    return NO_CONTENT


def _locked_payload(ids):
    payload = bucket_payload(ids, day=LOCKED_DAY)
    # The columnar payload advertises each asset's visibility, and these are
    # locked ones (the shell's `bucket_payload` is the timeline's).
    payload["visibility"] = ["locked"] * len(ids)
    return payload


@router.get("/api/timeline/buckets")
def locked_buckets(req):
    if req.params.get("visibility") != "locked":
        return None
    if not STATE["elevated"]:
        return Response([])
    return Response([{"timeBucket": LOCKED_DAY, "count": len(LOCKED)}])


@router.get("/api/timeline/bucket")
def locked_day(req):
    if req.params.get("visibility") != "locked":
        return None
    if not STATE["elevated"]:
        return Response(_locked_payload([]))
    return Response(_locked_payload(LOCKED))


if __name__ == "__main__":
    main(label="locked-folder")
