"""Immich API stub for the change-password scenario (`ChangePasswordUITests`).

Thin on purpose: everything the app needs to boot, sign in and draw a grid comes
from `immich_stub_base` (the OAuth handshake, the server config, the ordinary
timeline, real PNG thumbnails). This file adds the TWO things the feature owns —
`POST /api/auth/change-password`, and a `shouldChangePassword` flag on
`GET /api/users/me` that a successful change actually clears:

    python3 UITests/stubs/immich_stub_change_password.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/change-password.uitest.log \\
        UITests/stubs/immich_stub_change_password.py ChangePasswordUITests/test_changePassword

THE FLAG IS THE FEATURE. The hub's Security section shows its reminder only while
the SERVER answers `shouldChangePassword: true`, and the real server writes
`shouldChangePassword: false` on the user when the change goes through. A stub
that answered `false` everywhere would let the scenario pass with the reminder
never rendered; one that never cleared the flag would let the reminder survive a
successful change. Neither is possible here: the flag is one piece of state, read
by `/api/users/me` and written by `/api/auth/change-password`.

A WRONG CURRENT PASSWORD IS A **400**, NEVER A 401 — that is the real server's
`BadRequestException('Wrong password')`, and the app answers a 401 by dropping the
whole session, so a typo would land as a logout. The scenario asserts on the
difference: the error shows up and the session survives. A 404/500 here would
prove nothing, which is why the refused branch is the one branch the stub owns.
"""
from immich_stub_base import ME_USER, STATE, Response, main, router

# The one secret this stub knows: the scenario sends it for the accepted change,
# and something else for the refused one.
CURRENT = "stub-current-secret"


def _initial():
    """The state `/__reset` restores — a server asking for a new password, and
    no change applied yet."""
    STATE["shouldChangePassword"] = True
    STATE["changes"] = 0


# The process starts in the state a reset restores, so a by-hand run and a
# scenario run behave the same before anyone calls `/__reset`.
_initial()
router.reset(_initial)


@router.get("/api/users/me")
def me(req):
    """The user, carrying the flag the Security section reads (the shell's own
    `/api/users/me` answers the same DTO with `false`)."""
    return Response(dict(ME_USER, shouldChangePassword=STATE["shouldChangePassword"]))


@router.post("/api/auth/change-password")
def change_password(req):
    """The feature, server side: refuse a wrong current password, otherwise
    apply the change and clear the flag the hub reads back."""
    if req.body.get("password") != CURRENT:
        return Response({"message": "Wrong password", "error": "Bad Request",
                         "statusCode": 400, "correlationId": "stub"},
                        status=400)
    STATE["shouldChangePassword"] = False
    STATE["changes"] += 1
    return Response(dict(ME_USER, shouldChangePassword=False))


if __name__ == "__main__":
    main(label="change-password")
