"""Immich API stub for the "person birthday" scenario (`PersonBirthdayUITests`).

Thin on purpose: booting, signing in and drawing the timeline come from
`immich_stub_base` (the OAuth handshake, the server config, `/api/users/me`, a
day of timeline, real PNG thumbnails). This file adds what the feature owns —
a two-person library and the ONE write route the card is about:

    python3 UITests/stubs/immich_stub_person_birthday.py 8423

    .omp/orchestration/uitest.sh <worktree> /tmp/person-birthday.uitest.log \\
        UITests/stubs/immich_stub_person_birthday.py \\
        PersonBirthdayUITests/test_personBirthday --erase

WHAT MAKES IT LOAD-BEARING. `PUT /api/people/{id}` is the single route the whole
feature writes through (`setBirthday` and `clearPersonBirthday` differ only by
body), so this stub is where the two facts a green screen could hide are pinned:

* It records the request BODY (the shell logs it; a scenario reads it back from
  `/__requests`), so "one field only" is checkable — a body carrying `name` or
  `featureFaceAssetId` is caught even though the screen looks identical.
* It answers a DIFFERENT day than the one it received (`ANSWERED_DAY`). The
  drill-down header must therefore show the server's answer, not the draft the
  picker held: a screen painted from the local value shows the day that was sent
  and fails the scenario.

TWO OTHER FACTS, DELIBERATELY MODELLED RATHER THAN PAPERED OVER:

* A body with NO `birthDate` key changes nothing and answers 200 — exactly what
  the real server does, and the reason the card exists: `PersonUpdateDto(birthDate:
  nil)` omits the key (synthesized `encodeIfPresent`), so the erase silently does
  nothing. A stub that treated a missing key as an erase would hide that bug.
* `GET /control/birthday?fail=1` puts the write route in a refusing mode that
  answers 400 — the scenario's negative control. It does NOT live under `/__`:
  the shell answers every `/__…` path before the router is consulted (measured),
  so a feature control route has to sit elsewhere.
"""
from immich_stub_base import STATE, TIMELINE_ASSETS, Response, asset, main, png, router

# The library: one person WITH a birthday (the erase has something to erase, and
# the editor opens pre-filled) and one WITHOUT (the sheet must then offer no
# "Clear Birthday" at all). Names are not localized, so a scenario can find the
# rows by them in any language.
ADA = "dddddddd-1111-4111-8111-000000000001"
ALAN = "dddddddd-1111-4111-8111-000000000002"
SEEDED_DAY = "1990-05-12"

# What the server answers after a successful write — never the day it was sent:
# see the docstring. Its YEAR is what the scenario asserts on screen, because a
# localized label ("December 31, 2001" / "31 décembre 2001") reads the same in
# digits everywhere.
ANSWERED_DAY = "2001-12-31"

# `GET /api/people/{id}/statistics` — the count under each name.
ASSETS_PER_PERSON = 3


def person(pid, name, birth_date):
    """One `PersonResponseDto` — every non-optional field the app decodes."""
    return {
        "id": pid,
        "name": name,
        "birthDate": birth_date,
        "thumbnailPath": "",
        "isHidden": False,
        "color": "#4a5aef",
        "isFavorite": False,
        "updatedAt": "2026-09-01T10:00:00.000Z",
    }


def seed():
    """(Re)install the fixture — run at import and on every `/__reset`, so no
    assertion can be satisfied by a previous run's leftovers."""
    STATE["people"] = [person(ADA, "Ada Lovelace", SEEDED_DAY),
                       person(ALAN, "Alan Turing", None)]
    STATE["birthday_fail"] = False


router.reset(seed)
seed()


def _find(pid):
    return next((p for p in STATE["people"] if p["id"] == pid), None)


# MARK: - Routes


@router.get("/api/people")
def people(req):
    """The list, `birthDate` included — the field the feature reads and writes."""
    return Response({
        "people": STATE["people"],
        "hidden": 0,
        "total": len(STATE["people"]),
        "hasNextPage": False,
    })


@router.prefix("GET", "/api/people/")
def one_person(req):
    """The drill-down's own reads: the asset count behind each row and the face
    avatar. `None` for anything else, which falls through to the shell."""
    pid, _, tail = req.rest.partition("/")
    if _find(pid) is None:
        return None
    if tail == "statistics":
        return Response({"assets": ASSETS_PER_PERSON})
    if tail == "thumbnail":
        # A real PNG: this URL answering the shell's `[]` paints a broken avatar
        # in every screenshot of the drill-down (measured elsewhere in this
        # harness). `no-store` for the same reason the shell's asset routes use it.
        return Response(png(pid), ctype="image/png", headers={"Cache-Control": "no-store"})
    return None


@router.post("/api/search/metadata")
def person_faces(req):
    """The faces grid of the drill-down (`searchMetadata(personIds:)`).

    Not decoration: the shell acknowledges an unrouted POST with
    `{"successful": true}`, which fails to decode into `SearchResponseDto` and
    paints a red banner over the card this scenario is about. The three ids are
    the shell's own timeline assets, so their thumbnails resolve through
    `/api/assets/{id}/thumbnail` and the grid shows real pixels.
    """
    items = [asset(aid) for aid in TIMELINE_ASSETS[:3]]
    return Response({"assets": {"count": len(items), "items": items, "nextPage": None}})


@router.get("/control/birthday")
def birthday_mode(req):
    """`/control/birthday?fail=1` — make the write route answer 400.

    A feature control route cannot be called `/__…`: `_dispatch` intercepts that
    prefix before the router, so `/control/…` is where it goes (it will show up
    in `/__requests` like any other route, which is harmless).
    """
    STATE["birthday_fail"] = req.params.get("fail") == "1"
    return Response({"fail": STATE["birthday_fail"]})


@router.prefix("PUT", "/api/people/")
def update_person(req):
    """`PUT /api/people/{id}` — the ONE route of this feature.

    The scenario reads the recorded body back from `/__requests`: its KEY SET is
    what proves "this single field and nothing else", and for the erase it must
    be exactly `{"birthDate": null}` — a key that is simply absent is the trap
    this card was raised for, and is reproduced here (nothing is updated).
    """
    target = _find(req.rest)
    if target is None:
        return None

    if STATE["birthday_fail"]:
        # The negative control. A real 400 body: the client turns the whole body
        # into "Server error 400: {…}", which the app renders verbatim.
        return Response({"message": "birthday write refused by the stub",
                         "error": "Bad Request",
                         "statusCode": 400}, status=400)

    if "birthDate" not in req.body:
        return Response(target)
    target["birthDate"] = None if req.body["birthDate"] is None else ANSWERED_DAY
    return Response(target)


if __name__ == "__main__":
    main(label="person-birthday")
