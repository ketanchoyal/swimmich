"""Immich API stub for the "What's New" scenario (`WhatsNewUITests`) — gap G23.

    python3 UITests/stubs/immich_stub_whats_new.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/whats-new.uitest.log \\
        UITests/stubs/immich_stub_whats_new.py WhatsNewUITests/test_whatsNew --erase

THE SHORTEST STUB OF THE HARNESS, AND THAT IS THE FEATURE'S CONTRACT.
    "What's New" is served by no route, because the published Immich API has
    none: `grep -c featureMessage /tmp/immich-openapi-main.json` → 0. The batch is
    a constant in the app (`FeatureHighlightCatalog`, content release "3.0.0"), so
    the sheet is complete offline — that is what the scenario asserts. Everything
    the walk to it needs is the SHELL's, and lives in `immich_stub_base`: the OAuth
    handshake, the server config, `/api/users/me`, one day of timeline (which is
    also how the scenario proves the app is talking to THIS stub) and the storage
    card of the "Me" hub, from which the About row is reached. Declaring a route
    "for completeness" here would invent a contract the server does not have, and
    the scenario would then be asserting against my own invention.

THE ONE ROUTE IS A TRIPWIRE, NOT A FEATURE ROUTE.
    An unrouted `/api/…` GET is answered `[]` by the shell, so an app that had
    started asking a server for its release notes would render an EMPTY sheet and
    the screen assertion would fail with nothing pointing at the cause. This
    declares the shape such a call would take (`/api/feature…`) and answers it 404
    with its own explanation, so the mistake is legible on the screen, in
    `/__requests` and in the endpoint list `main()` prints at startup. It is never
    reached by the scenario itself: that is the point.
"""
from immich_stub_base import Response, main, router

# The prefix a "server-served release notes" implementation would reach for.
EMBEDDED_BATCH_PREFIX = "/api/feature"


@router.prefix("GET", EMBEDDED_BATCH_PREFIX)
def batch_is_embedded(req):
    """Refuse `/api/feature…` loudly instead of answering an empty page.

    It does not exist upstream, so answering it here would make the batch look
    server-backed — and a silent `[]` would hide the regression this stub is
    here to expose.
    """
    req.note(neverServed=req.path)
    return Response({
        "error": "the What's New batch is embedded in the app",
        "hint": "no featureMessage route exists in the Immich API",
        "path": req.path,
    }, status=404)


if __name__ == "__main__":
    main(label="whats-new")
