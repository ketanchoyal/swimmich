"""Immich API stub for the AirPlay scenario (`ChromecastUITests`).

    python3 UITests/stubs/immich_stub_chromecast.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/immich-orchestration/chromecast.uitest.log \\
        UITests/stubs/immich_stub_chromecast.py ChromecastUITests/test_chromecast

ONE ROUTE, AND THE APP MUST NEVER CALL IT.

The cast feature has no traffic of its own: over AirPlay the phone stays the
HTTP client of the Immich server — the viewer keeps streaming the photo with its
own bearer token — so demanding a request from it would be demanding the wrong
architecture. What is left to prove on the wire is the opposite, and it is the
wire that carries the card's central assumption: sending a video to a *receiver
that downloads the media itself* (Google Cast) requires a server session
(`POST /api/sessions`: `SessionCreateDto{deviceOS, deviceType, duration}` →
`SessionCreateResponseDto{token, expiresAt}`, present in Immich's published
OpenAPI), and that path is out of scope here.

Serving that route is what makes the scenario's absence assertion falsifiable
rather than vacuous: the route exists and answers, the app still never asks for
a session. A stub that did not serve it could not tell "the app does not create
sessions" from "the app asks silently and reads a 404 as nothing".

Everything else — the OAuth handshake, the server config, the user, the
timeline, the real PNG thumbnails the viewer pulls at `size=fullsize` — is the
shell's, in `immich_stub_base`.
"""
from immich_stub_base import Response, main, router


@router.post("/api/sessions")
def create_session(req):
    """The cast-receiver session this app must never create (see the docstring).

    `req.note` records what was asked for, so a violation is legible in
    `/__requests` and the scenario's failure message names the device the app
    claimed to be — not just that a request appeared.
    """
    req.note(deviceOS=req.body.get("deviceOS"), deviceType=req.body.get("deviceType"))
    return Response(
        {"token": "stub-cast-session-token", "expiresAt": "2026-12-31T00:00:00.000Z"},
        status=201,
    )


if __name__ == "__main__":
    main(label="chromecast")
