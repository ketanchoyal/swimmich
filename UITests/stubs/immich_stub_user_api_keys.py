"""Immich API stub for the "API keys" scenario (`UserApiKeysUITests`).

Thin on purpose: everything the app needs to boot, sign in and draw a grid comes
from `immich_stub_base` (the OAuth handshake, the server config, `/api/users/me`
— answered as a NON administrator — a day of timeline, real PNG thumbnails).
This file adds the five routes gap G20 owns:

    GET    /api/api-keys              the keys of the token's owner (the LIST)
    GET    /api/api-keys/me           the key that carries the request (SINGULAR)
    POST   /api/api-keys              create -> a secret, returned ONCE
    POST   /api/api-keys/{id}/rotate  rotate -> a NEW secret (POST, never a PUT:
                                      `.paths["/api-keys/{id}/rotate"]` keys
                                      `post` only in the published document)
    DELETE /api/api-keys/{id}         revoke

TWO ENDPOINTS, TWO PAYLOADS THAT SHARE NO NAME — that is what makes the scenario
load-bearing. The list answers `stub-laptop` and `stub-ci`; `/me` answers
`stub-phone-session`; no name appears in both. A screen that filled the list
from `/me`, or the "Current session" row from the list, is caught by a name
rather than by a detail.

The mutations keep the stub's own state: a created key is appended to the list
and a deleted one removed, so the LIST the screen shows after an action is
evidence that the action reached the server and not just a re-render of the
fixture.

    python3 UITests/stubs/immich_stub_user_api_keys.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/user-api-keys.uitest.log \\
        UITests/stubs/immich_stub_user_api_keys.py UserApiKeysUITests/test_userApiKeys

`GET /control/rotate?mode=fail` arms a refusal: the next `/rotate` answers 500
with `stub refused the rotation` in its body, which the app renders in its error
badge. That is the scenario's negative control — the rotation IS sent, IS
refused, and the screen must say so instead of pretending the key was rotated.
`/__reset` disarms it. (The route cannot live under `/__`: the shell answers
every `/__*` itself, before the router.)
"""
from immich_stub_base import Response, STATE, main, router

# Distinct from the shell's own fixtures (`1111…` user, `aaaa…` assets) so a
# screenshot or a log entry is never ambiguous about its origin.
LAPTOP = "33333333-3333-4333-8333-000000000001"
PHONE = "33333333-3333-4333-8333-000000000002"
CI = "33333333-3333-4333-8333-000000000003"
CREATED = "33333333-3333-4333-8333-000000000004"

STAMP = "2026-09-01T10:00:00.000Z"

# Recognisable, language-neutral, and never a real secret.
SECRET_CREATED = "stub-key-secret-created"
SECRET_ROTATED = "stub-key-secret-rotated"
REFUSED = "stub refused the rotation"


def _key(kid, name, permissions):
    return {"id": kid, "name": name, "createdAt": STAMP, "updatedAt": STAMP,
            "permissions": permissions}


INITIAL_KEYS = [
    _key(LAPTOP, "stub-laptop", ["asset.read"]),
    _key(CI, "stub-ci", ["all"]),
]

# The key that carries the request. A different object from every listed key on
# purpose (see the module docstring). Upstream: `getMyApiKey` — "Retrieve the
# API key that is used to access this endpoint", `ApiKeyResponseDto` singular.
MY_KEY = _key(PHONE, "stub-phone-session", ["all"])


@router.reset
def _restore():
    """The initial fixture, and the refusal disarmed."""
    STATE["keys"] = [dict(key) for key in INITIAL_KEYS]
    STATE["rotate"] = "ok"


_restore()


@router.get("/api/api-keys")
def list_keys(req):
    """`getApiKeys` — "all API keys of the current user", permission
    `apiKey.read`, NOT an admin permission: that is the gap this scenario
    measures (the shell's `/api/users/me` says `isAdmin: false`)."""
    return Response(STATE["keys"])


@router.get("/api/api-keys/me")
def my_key(req):
    return Response(MY_KEY)


@router.post("/api/api-keys")
def create_key(req):
    """`createApiKey` — `ApiKeyCreateDto` = {name, permissions}."""
    name = req.body.get("name")
    permissions = req.body.get("permissions") or []
    # What the scenario asserts on the wire, spelled out rather than nested in
    # the raw body: a body that is not the documented DTO has to fail loudly.
    req.note(name=name, permissions=permissions)
    created = _key(CREATED, name, permissions)
    STATE["keys"].append(created)
    # `ApiKeyCreateResponseDto` = {secret, apiKey}; the secret is the only copy
    # the server will ever hand out.
    return Response({"secret": SECRET_CREATED, "apiKey": created}, status=201)


@router.prefix("POST", "/api/api-keys/")
def rotate_key(req):
    """`rotateApiKey` — a POST on `/{id}/rotate`. Anything else under this
    prefix falls through to the shell."""
    parts = req.rest.split("/")
    if len(parts) != 2 or parts[1] != "rotate":
        return None
    kid = parts[0]
    req.note(key=kid)
    if STATE["rotate"] == "fail":
        return Response({"message": REFUSED, "error": "Internal Server Error",
                         "statusCode": 500}, status=500)
    target = next((key for key in STATE["keys"] if key["id"] == kid), None)
    if target is None:
        return Response({"message": "API key not found", "statusCode": 404}, status=404)
    return Response({"secret": SECRET_ROTATED, "apiKey": target}, status=201)


@router.prefix("DELETE", "/api/api-keys/")
def delete_key(req):
    """`deleteApiKey` — the key is gone from the next list, which is how the
    screen's own list proves the revocation reached the server."""
    kid = req.rest.lstrip("/")
    req.note(key=kid)
    STATE["keys"] = [key for key in STATE["keys"] if key["id"] != kid]
    return Response({"successful": True})


@router.get("/control/rotate")
def control_rotate(req):
    """The negative control's switch, outside `/api/` so it cannot be mistaken
    for a route the app is supposed to call."""
    STATE["rotate"] = "fail" if req.params.get("mode") == "fail" else "ok"
    return Response({"rotate": STATE["rotate"]})


if __name__ == "__main__":
    main(label="user-api-keys")
