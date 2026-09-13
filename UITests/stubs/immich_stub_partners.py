"""Immich API stub for the partner end-to-end scenario (UITests).

Committed on purpose: the stacks stub lives in /tmp, so a `rm -rf /tmp/*` (or a
reboot) silently destroys the harness and only the test comments remember it
existed. This one is self-contained — no sibling module to import — and is run
by hand before the XCUITest:

    python3 UITests/stubs/immich_stub_partners.py 8421
    xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI \\
        -destination 'platform=iOS Simulator,name=iPhone 17' \\
        -only-testing:ImmichSwiftUIUITests/ImmichRenderScreenshots/test_06_partners

It serves the OAuth handshake the app needs to reach the authenticated shell
(same shape as the throwaway base stub) plus the partner routes. Two behaviours
matter beyond "returns data":

* `GET /api/partners` **requires** `direction` and answers **400** without it.
  The app shipped a direction-less call for months (`getPartners()`), which this
  stub reproduces as a hard failure rather than a silently empty list — a grep
  on the source could never catch that.
* the response of a direction is the *other* user of the pair, and `PUT`
  (`sharedById = id, sharedWithId = me`) and `DELETE` (`sharedById = me,
  sharedWithId = id`) each only match one direction. The stub enforces it, so a
  mutation sent on the wrong collection is a 400 here, not a silent no-op.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8421
BASE = f"http://127.0.0.1:{PORT}"

ME = "11111111-1111-4111-8111-111111111111"
# Shares their library with me → appears under "Shared with me".
INCOMING = "aaaaaaaa-1111-4111-8111-111111111111"
# I share my library with them → appears under "Sharing".
OUTGOING = "bbbbbbbb-2222-4222-8222-000000000002"
# Nobody has invited them yet → offered by the invite sheet.
INVITABLE = "cccccccc-3333-4333-8333-000000000003"


def user(uid, name, email):
    return {
        "id": uid, "name": name, "email": email, "profileImagePath": "",
        "avatarColor": "primary", "profileChangedAt": "2026-01-01T00:00:00.000Z",
    }


ME_USER = {
    **user(ME, "Stub User", "stub@example.com"),
    "isAdmin": False, "shouldChangePassword": False,
    "createdAt": "2026-01-01T00:00:00.000Z", "updatedAt": "2026-01-01T00:00:00.000Z",
    "deletedAt": None, "status": "active",
    "quotaSizeInBytes": 107374182400, "quotaUsageInBytes": 21474836480,
    "storageLabel": None, "oauthId": "",
}

CONFIG = {
    "oauthButtonText": "Continue with Immich SSO",
    "loginPageMessage": "Stub server for UI verification",
    "trashDays": 30, "userDeleteDelay": 7,
    "isInitialized": True, "isOnboarded": True,
    "externalDomain": "", "publicUsers": True,
    "mapDarkStyleUrl": "", "mapLightStyleUrl": "",
    "maintenanceMode": False, "minFaces": 0,
}

PROVIDER_HTML = """<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Stub Identity Provider</title>
<style>
 body{font:16px -apple-system,sans-serif;margin:0;display:flex;align-items:center;
      justify-content:center;height:100vh;background:#f2f2f7;}
 .card{background:#fff;border-radius:18px;padding:28px;text-align:center;
       box-shadow:0 10px 40px rgba(0,0,0,.12);max-width:320px;}
 h1{font-size:20px;margin:0 0 6px;}p{color:#6b7280;margin:0 0 20px;font-size:14px;}
 a{display:block;background:#4250af;color:#fff;text-decoration:none;
   padding:14px;border-radius:12px;font-weight:600;}
</style></head>
<body><div class="card">
  <h1>Stub Identity Provider</h1>
  <p>Signing in as stub@example.com</p>
  <a id="authorize" href="app.immich:///oauth-callback?code=stub-code&amp;state=stub-state">Authorize</a>
</div></body></html>
"""

AUTO_HTML = """<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Stub Identity Provider</title></head>
<body style="font:16px -apple-system,sans-serif;text-align:center;padding-top:120px">
<p>Signing in as stub@example.com…</p>
<script>window.location = "app.immich:///oauth-callback?code=stub-code&state=stub-state";</script>
</body></html>
"""


def partner(uid, name, email, in_timeline):
    return {**user(uid, name, email), "inTimeline": in_timeline}


def initial_state():
    return {
        # direction=shared-by rows: people I added.
        "shared_by": [partner(OUTGOING, "Outgoing Olive", "olive@example.com", False)],
        # direction=shared-with rows: people who share with me.
        "shared_with": [partner(INCOMING, "Incoming Ivan", "ivan@example.com", True)],
        "provider": "manual",
        "requests": [],
    }


STATE = initial_state()
DIRECTIONS = {
    "shared-by": "shared_by",
    "shared-with": "shared_with",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("stub %s\n" % (fmt % args))

    def _send(self, payload, status=200, ctype="application/json"):
        body = payload if isinstance(payload, bytes) else (
            payload.encode() if ctype.startswith("text/") else json.dumps(payload).encode()
        )
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}") if length else {}

    def _log(self, entry):
        STATE["requests"].append(entry)

    # MARK: - GET

    def do_GET(self):
        path = self.path.split("?")[0]
        query = self.path.split("?")[1] if "?" in self.path else ""

        if path == "/__reset":
            STATE.update(initial_state())
            return self._send({"reset": True})
        if path == "/__provider":
            STATE["provider"] = "auto" if "auto" in query else "manual"
            return self._send({"provider": STATE["provider"]})
        if path == "/__requests":
            return self._send(STATE["requests"])
        if path == "/provider-manual":
            return self._send(PROVIDER_HTML, ctype="text/html; charset=utf-8")
        if path == "/provider-auto":
            return self._send(AUTO_HTML, ctype="text/html; charset=utf-8")

        if path == "/api/partners":
            params = dict(
                pair.split("=", 1) for pair in query.split("&") if "=" in pair
            )
            direction = params.get("direction")
            self._log({"method": "GET", "path": path, "direction": direction})
            if direction not in DIRECTIONS:
                # Exactly what the real server does (ZodValidationPipe on a
                # required enum). No silent empty list.
                return self._send(
                    {"error": "Bad Request", "message": ["direction must be one of: shared-by, shared-with"]},
                    status=400,
                )
            return self._send(STATE[DIRECTIONS[direction]])

        if path == "/api/users":
            return self._send([
                user(ME, "Stub User", "stub@example.com"),
                user(INCOMING, "Incoming Ivan", "ivan@example.com"),
                user(OUTGOING, "Outgoing Olive", "olive@example.com"),
                user(INVITABLE, "Invitable Iris", "iris@example.com"),
            ])

        routes = {
            "/api/server/ping": {"res": "pong"},
            "/api/server/version": {"major": 1, "minor": 119, "patch": 0, "prerelease": None},
            "/api/server/config": CONFIG,
            "/api/users/me": ME_USER,
            "/api/timeline/buckets": [],
            "/api/memories": [],
            "/api/albums": [],
            "/api/activities": [],
            "/api/notifications": [],
            "/api/stacks": [],
        }
        if path in routes:
            return self._send(routes[path])
        if path.startswith("/api/"):
            return self._send([])
        self._send({"error": "not found", "path": path}, status=404)

    # MARK: - POST

    def do_POST(self):
        path = self.path.split("?")[0]
        body = self._body()

        if path == "/api/oauth/authorize":
            return self._send({"url": f"{BASE}/provider-manual" if STATE["provider"] == "manual"
                               else f"{BASE}/provider-auto"})
        if path == "/api/oauth/callback":
            return self._send({
                "accessToken": "stub-access-token", "userId": ME, "userEmail": ME_USER["email"],
                "name": ME_USER["name"], "isAdmin": False, "profileImagePath": "",
                "shouldChangePassword": False, "isOnboarded": True,
            })
        if path == "/api/auth/logout":
            return self._send({"successful": True})
        if path == "/api/partners":
            shared_with_id = body.get("sharedWithId")
            self._log({"method": "POST", "path": path, "sharedWithId": shared_with_id})
            if not shared_with_id:
                return self._send({"error": "Bad Request", "message": ["sharedWithId must be a uuid"]}, status=400)
            if any(p["id"] == shared_with_id for p in STATE["shared_by"]):
                return self._send({"error": "Bad Request", "message": "Partner already exists"}, status=400)
            created = partner(shared_with_id, f"User {shared_with_id[:4]}", f"{shared_with_id[:4]}@example.com", False)
            STATE["shared_by"].append(created)
            return self._send(created, status=201)
        if path.startswith("/api/"):
            return self._send({"successful": True})
        self._send({"error": "not found", "path": path}, status=404)

    # MARK: - PUT

    def do_PUT(self):
        path = self.path.split("?")[0]
        body = self._body()
        if path.startswith("/api/partners/"):
            partner_id = path.rsplit("/", 1)[-1]
            self._log({"method": "PUT", "path": path, "inTimeline": body.get("inTimeline")})
            # The server pairs {sharedById: id, sharedWithId: me}: only a row
            # from `direction=shared-with` can be updated.
            for row in STATE["shared_with"]:
                if row["id"] == partner_id:
                    row["inTimeline"] = bool(body.get("inTimeline"))
                    return self._send(row)
            return self._send({"error": "Bad Request", "message": "Partner not found"}, status=400)
        self._send({"error": "not found", "path": path}, status=404)

    # MARK: - DELETE

    def do_DELETE(self):
        path = self.path.split("?")[0]
        if path.startswith("/api/partners/"):
            partner_id = path.rsplit("/", 1)[-1]
            self._log({"method": "DELETE", "path": path})
            # The server pairs {sharedById: me, sharedWithId: id}: only a row
            # from `direction=shared-by` can be removed.
            before = len(STATE["shared_by"])
            STATE["shared_by"] = [p for p in STATE["shared_by"] if p["id"] != partner_id]
            if len(STATE["shared_by"]) == before:
                return self._send({"error": "Bad Request", "message": "Partner not found"}, status=400)
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()
            return
        self._send({"error": "not found", "path": path}, status=404)


if __name__ == "__main__":
    print(json.dumps({
        "port": PORT,
        "endpoints": ["/api/partners?direction=", "/api/partners", "/api/users", "/__reset", "/__requests"],
    }))
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
