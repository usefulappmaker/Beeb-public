#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Beeb household sync, standalone (no Home Assistant needed). Python 3.9+, standard library only.

    BEEB_SYNC_KEY="a-long-random-key" python3 beeb_sync_server.py
Environment: BEEB_SYNC_KEY (required), BEEB_SYNC_PORT (default 8765), BEEB_SYNC_DATA (default ./beeb_sync.json)
Beeb › Settings › Household sync URL:  http://<this-machine>:8765/beeb_history
See docs/SYNC.md. Intended for a home network; put it behind HTTPS if it's reachable from anywhere else.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from beeb_sync_core import SyncStore  # noqa: E402

KEY = os.environ.get("BEEB_SYNC_KEY", "")
PORT = int(os.environ.get("BEEB_SYNC_PORT", "8765"))
STORE = SyncStore(os.environ.get("BEEB_SYNC_DATA", os.path.join(os.getcwd(), "beeb_sync.json")))
MAX_BODY = 2 * 1024 * 1024


class Handler(BaseHTTPRequestHandler):
    server_version = "BeebSync/1"

    def reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authorised(self):
        return self.path.rstrip("/") == "/beeb_history" and KEY and self.headers.get("X-Beeb-Key") == KEY

    def do_GET(self):
        if not self.authorised():
            return self.reply(403, {"error": "forbidden"})
        self.reply(200, {"ok": True, "profiles": STORE.summary()})

    def do_POST(self):
        if not self.authorised():
            return self.reply(403, {"error": "forbidden"})
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            return self.reply(400, {"error": "bad body"})
        try:
            body = json.loads(self.rfile.read(length))
        except ValueError:
            return self.reply(400, {"error": "bad json"})
        payload, status, line = STORE.handle(body)
        if line:
            self.log_message("%s", line)
        self.reply(status, payload)


if __name__ == "__main__":
    if len(KEY) < 16:
        sys.exit("Set BEEB_SYNC_KEY to a random key of at least 16 characters.")
    print(f"Beeb sync listening on :{PORT} (data: {STORE.path}) {STORE.summary()}", flush=True)
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()
