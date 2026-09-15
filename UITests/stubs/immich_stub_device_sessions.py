"""Immich API stub for the connected-devices scenario (`DeviceSessionsUITests`).

    python3 UITests/stubs/immich_stub_device_sessions.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/device-sessions.uitest.log \\
        UITests/stubs/immich_stub_device_sessions.py DeviceSessionsUITests/test_deviceSessions

The shell (`immich_stub_base`) brings the app from onboarding to the
authenticated shell; this file adds the five routes the feature under test
owns, and every one of them is one claim of the card:

* `GET /api/sessions` — the list, and its ONLY source. It answers from the live
  state, so a deletion the screen does not re-read is visible as a row that
  stays: the stub stops serving it, nothing else.
* `DELETE /api/sessions/{id}` and `DELETE /api/sessions` — both 204, both really
  applied. The bulk one keeps the calling session, exactly like the server
  (`invalidateAll({ userId, excludeId: currentSessionId })`): the route is not a
  self-logout, which is why the app's copy says "other devices".
* `GET /api/auth/status` — the elevation. No field of `SessionResponseDto`
  carries it, so this route is the only place the screen can read it from.
  `AuthStatusResponseDto` requires all five fields: a partial body decodes to
  nothing and the probe fails silently, so the whole shape is served.
* `POST /api/auth/session/unlock` — the PIN is checked for real (401 otherwise,
  so a scenario that mistyped it cannot pass on a lenient stub), and a correct
  one answers 204. It deliberately does **not** raise `elevated`: the scenario
  needs a server whose status route contradicts the mutation it just accepted,
  which is the one case that tells a screen reading the server apart from a
  screen trusting its own successful call.
* `GET /control/elevation?isElevated=0|1` — the scenario's pen on the server's
  own elevation state, so both directions are provable: the screen must follow
  it up (nothing local elevated anything) and down (a 204 unlock did not).
  Not under `/__`: the shell answers every `/__*` path itself and never
  consults the router, so a feature control route there is answered 404.

A 204 is `Response(b"", status=204)`: the shell's `_send` streams `bytes`
verbatim, so the reply really has no body and the client's `validate()` takes
its explicit 204 branch.
"""
from immich_stub_base import Response, STATE, router, main

# MARK: - Fixtures

# The session in your hand opens the list; the two others are what the screen
# exists to get rid of. The ids are readable in a screenshot and in an assertion
# ("dddd…", the fourth block of the harness's fixtures).
SELF = "dddddddd-1111-4111-8111-000000000001"
IPHONE = "dddddddd-1111-4111-8111-000000000002"
CHROME = "dddddddd-1111-4111-8111-000000000003"

# The account PIN, and the only one this stub elevates. `SessionUnlockDto` only
# ever carries `pinCode` (the server reads nothing else, whatever the field's
# description says).
PIN = "246813"

NO_CONTENT = Response(b"", status=204)


def session(sid, current, device_os, device_type, version, updated):
    """One `SessionResponseDto`. `expiresAt` and `appVersion` are the only two
    optional fields of the OpenAPI schema — `appVersion: None` is what a session
    whose client never reported one looks like, and it also exercises the
    version segment being dropped from the row's first line."""
    return {
        "id": sid,
        "createdAt": "2026-09-01T08:00:00.000Z",
        "updatedAt": updated,
        "expiresAt": None,
        "current": current,
        "deviceType": device_type,
        "deviceOS": device_os,
        "appVersion": version,
        "isPendingSyncReset": False,
    }


def initial_sessions():
    """Current first, then the others by last activity descending — the order
    the screen must end up showing, so a wrong sort is legible in a screenshot."""
    return [
        session(SELF, True, "iOS", "iPhone", "2.1.0", "2026-09-15T09:00:00.000Z"),
        session(IPHONE, False, "iOS", "iPhone", None, "2026-09-14T18:30:00.000Z"),
        session(CHROME, False, "Chrome OS", "Chrome", "1.119.0", "2026-09-12T07:15:00.000Z"),
    ]


# MARK: - Routes


@router.get("/api/sessions")
def list_sessions(req):
    """The list, live. Nothing about it is derived: a scenario reads the same
    state the assertions below are written against."""
    return Response(STATE["sessions"])


@router.delete("/api/sessions")
def delete_others(req):
    """`DELETE /api/sessions` — every session but the caller's own."""
    gone = [s["id"] for s in STATE["sessions"] if not s["current"]]
    req.note(sessions=",".join(gone))
    STATE["sessions"] = [s for s in STATE["sessions"] if s["current"]]
    return NO_CONTENT


@router.prefix("DELETE", "/api/sessions/")
def delete_one(req):
    """`DELETE /api/sessions/{id}` — one device. An id this stub does not know
    is a 404 and not a silent success: the scenario asserts the exact id it
    swiped, and a route that answered 204 for anything would let a wrong path
    through."""
    sid = req.rest.split("/")[0]
    req.note(session=sid)
    before = len(STATE["sessions"])
    STATE["sessions"] = [s for s in STATE["sessions"] if s["id"] != sid]
    if len(STATE["sessions"]) == before:
        return Response({"error": "Not Found", "message": "Session not found", "statusCode": 404},
                        status=404)
    return NO_CONTENT


@router.get("/api/auth/status")
def auth_status(req):
    """The elevation's only source. `elevated` belongs to the scenario (see
    `/control/elevation`); the rest of the payload is the account's setup, which
    the locked folder also reads."""
    return Response({
        "expiresAt": None,
        "isElevated": STATE["elevated"],
        "password": True,
        "pinCode": True,
        "pinExpiresAt": "2026-09-15T12:00:00.000Z" if STATE["elevated"] else None,
    })


@router.post("/api/auth/session/unlock")
def unlock(req):
    """Elevates the session with the account PIN — and then leaves `elevated`
    exactly where the scenario put it. See the module docstring: an unlock that
    also flipped the status would make the two implementations under test (read
    the server / trust the call) indistinguishable."""
    pin = req.body.get("pinCode")
    accepted = pin == PIN
    req.note(pinCode=str(pin), accepted="yes" if accepted else "no")
    if not accepted:
        return Response({"error": "Unauthorized", "message": "Invalid PIN code", "statusCode": 401},
                        status=401)
    return NO_CONTENT


@router.get("/control/elevation")
def set_elevation(req):
    """The scenario's pen on the server's elevation. Logged like any other
    request — harmless, every assertion filters on `/api/…`."""
    STATE["elevated"] = req.params.get("isElevated") in ("1", "true", "yes")
    return Response({"isElevated": STATE["elevated"]})


@router.reset
def fresh():
    STATE["sessions"] = initial_sessions()
    STATE["elevated"] = False


# Both the boot state and the reset state: `STATE` starts as the shell's own
# dict, so a route that read `STATE["sessions"]` before any `/__reset` would
# raise a `KeyError` inside the handler — which reaches the client as a dropped
# connection and an empty body, not as a 500 (measured on this stub).
fresh()


if __name__ == "__main__":
    main(label="device-sessions")
