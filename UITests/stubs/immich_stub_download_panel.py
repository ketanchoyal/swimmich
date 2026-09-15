"""Immich API stub for the download-panel scenario (`DownloadPanelUITests`).

Thin on purpose: everything the app needs to boot, sign in, draw a grid and
open the viewer comes from `immich_stub_base` (the OAuth handshake, the server
config, `/api/users/me`, a day of timeline, real PNG thumbnails). This file
answers ONE route the feature under test owns, in the two shapes the queue
needs to see it:

* `GET /api/assets/{id}`      — the asset itself, with the size the ORIGINAL
  really has (see WHY THE SIZE MATCHES);
* `GET /api/assets/{id}/original` — that original, paced over ~24 s.

Everything else under `/api/assets/` (the thumbnails, any other asset) falls
through to the shell, which already serves it.

WHY THE DELAY
    The download queue is only observable WHILE a transfer runs: the floating
    panel exists exactly as long as a row is queued or running, and the info
    screen offers a `Cancel` on that row for the same window. The shell answers
    `/original` in one shot, so a scenario driven against it would see the panel
    appear and vanish inside a single frame and could assert nothing about a
    transfer in progress. 16 chunks, 1.5 s apart, give the scenario ~24 s to
    walk from the viewer to the panel to the info screen and back out.

    `Connection: close` and an explicit `Content-Length` are what make that
    legible to the app: without the length, `URLSession` reports
    `totalBytesExpectedToWrite == 0` and the row has no fraction to show.

WHY THE SIZE MATCHES
    `DownloadItem.expectedBytes` starts at the asset's
    `exifInfo.fileSizeInByte` and is only ever corrected from the transport's
    `Content-Length`. A stub that served 77 KiB while advertising the shell's
    2 KiB would make the row's displayed size and its fraction disagree with
    the file on disk — a fixture artefact that reads exactly like an app bug.
    So this stub owns the DTO too, and `fileSizeInByte` is `len(original)`.

WHY THE BODY IS NOISE
    A real, decodable PNG is served — the app writes it to
    `Documents/Downloads/`, and a fixture that did not decode would put a
    broken file in the user's folder. But it cannot come from
    `immich_stub_base.png()`: that draws ONE flat colour, which zlib squeezes
    to about 90 bytes, and 90 bytes over 16 chunks is not a stream. This builds
    the same PNG structure over pseudo-random pixels instead, which compress to
    nothing. The pixels are seeded by the asset id, so the DTO and the body
    agree on a length byte for byte.

THE NEGATIVE CONTROL
    `ORIGINAL_STATUS` is the lever. Set it to 500 and the same slow body goes
    out on an error status; the app checks the status after streaming (a 404
    writes its error page to disk like any other response), deletes the temp
    file and must park the row at `failed` — never at `completed`. That is the
    point of the scenario's completion assertion, and how it is proven to
    discriminate.

    python3 UITests/stubs/immich_stub_download_panel.py 8421

    .omp/orchestration/uitest.sh <worktree> /tmp/download-panel.uitest.log \\
        UITests/stubs/immich_stub_download_panel.py DownloadPanelUITests/test_downloadPanel
"""
import random
import time
import zlib

import immich_stub_base as base
from immich_stub_base import Response, router

# The tile the scenario downloads: the first photo of the shell's own day, so
# the request the queue sends is `GET /api/assets/aaaa…0001/original`.
TARGET = base.TIMELINE_ASSETS[0]

# See THE NEGATIVE CONTROL above: 200 is the scenario's green, 500 its failure.
ORIGINAL_STATUS = 200

SIDE = 160              # 160×160 RGB → ~77 KiB of pixels
CHUNK_BYTES = 5 * 1024  # → 16 chunks
CHUNK_SECONDS = 1.5     # → ~24 s per original


def original(aid, side=SIDE):
    """The asset's original: a real, decodable PNG of a size worth streaming.

    Same chunk layout as `immich_stub_base.png()` — signature, `IHDR`, one
    `IDAT`, `IEND` — but the pixels come from a PRNG seeded by the asset id, so
    (a) the deflate stream cannot shrink them away and (b) two calls return the
    same length, which is what lets the DTO announce it.
    """
    rng = random.Random(aid)
    raw = b"".join(b"\x00" + rng.randbytes(side * 3) for _ in range(side))

    def chunk(kind, data):
        payload = kind + data
        return (len(data).to_bytes(4, "big") + payload
                + (zlib.crc32(payload) & 0xFFFFFFFF).to_bytes(4, "big"))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", side.to_bytes(4, "big") + side.to_bytes(4, "big")
                    + bytes((8, 2, 0, 0, 0)))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


class Paced(Response):
    """A `Response` the stub writes one chunk at a time, `seconds` apart.

    A subclass rather than a parallel type, so it keeps `Response`'s payload /
    status / ctype / headers contract and only adds the pacing the base's
    `_send` has no place for (it writes a body in a single call).
    """

    __slots__ = ("seconds",)

    def __init__(self, payload, status=200, ctype="application/octet-stream", seconds=CHUNK_SECONDS):
        super().__init__(payload, status=status, ctype=ctype,
                         headers={"Cache-Control": "no-store"})
        self.seconds = seconds


class PacedHandler(base.StubHandler):
    """`StubHandler` that paces a `Paced` body — everything else unchanged."""

    def _send(self, response):
        if not isinstance(response, Paced):
            return super()._send(response)
        body = response.payload
        self.send_response(response.status)
        self.send_header("Content-Type", response.ctype)
        self.send_header("Content-Length", str(len(body)))
        for name, value in response.headers.items():
            self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        for start in range(0, len(body), CHUNK_BYTES):
            self.wfile.write(body[start:start + CHUNK_BYTES])
            self.wfile.flush()
            time.sleep(response.seconds)


@router.prefix("GET", "/api/assets/")
def one_asset(req):
    """The asset and its original — the two shapes this feature reads.

    `None` for everything else under the prefix (`/thumbnail`, and any id the
    shell already knows how to answer): the shell's own routes stay in charge
    of those, which is what keeps this stub additive.
    """
    parts = req.rest.split("/")
    aid = parts[0]

    if len(parts) == 1:
        dto = base.asset(aid)
        dto["exifInfo"]["fileSizeInByte"] = len(original(aid))
        return Response(dto)

    if len(parts) == 2 and parts[1] == "original":
        return Paced(original(aid), status=ORIGINAL_STATUS)

    return None


if __name__ == "__main__":
    # `immich_stub_base.main()` builds its server with the module's own
    # `StubHandler`; installing the pacing variant by name is the one seam that
    # avoids re-implementing the bind and the startup banner here.
    base.StubHandler = PacedHandler
    base.main(label="download-panel")
