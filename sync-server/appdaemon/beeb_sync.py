# SPDX-License-Identifier: GPL-3.0-or-later
"""Beeb household sync for Home Assistant, as an AppDaemon app (single file; copy into AppDaemon's apps folder).

apps.yaml:
    beeb_sync:
      module: beeb_sync
      class: BeebSync
      key: "a-long-random-key"

Endpoint for Beeb › Settings › Household sync:  http://<home-assistant-address>:5050/api/appdaemon/beeb_history
Data is kept in beeb_history.json next to this file. See docs/SYNC.md.
(The merge logic is the same as sync-server/beeb_sync_core.py, inlined here so this stays one file.)
"""
import json
import os
import re
import threading
import time

import appdaemon.plugins.hass.hassapi as hass

SWIFT_EPOCH = 978307200
LIMITS = {"history": 60, "saved": 300, "profiles": 50, "settings": 20}
REMOVED_DAYS = 90
SLUG = re.compile(r"^[a-z0-9_]{1,32}$")


class BeebSync(hass.Hass):
    def initialize(self):
        self.key = str(self.args["key"])
        if len(self.key) < 16:
            self.log("Beeb sync: please use a key of at least 16 characters", level="WARNING")
        self.path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "beeb_history.json")
        self.lock = threading.Lock()
        self.register_endpoint(self.handle, "beeb_history")
        data = self.load()
        self.log(f"Beeb sync ready: {({p: {k: len(v['records']) for k, v in ks.items()} for p, ks in data['profiles'].items()})}")

    def load(self):
        try:
            with open(self.path) as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = {}
        if not data:
            data = {"profiles": {}}
        elif "profiles" not in data:
            data = {"profiles": {"main": {"history": {"records": data.get("records", []), "removed": data.get("removed", {})}}}}
        return data

    def save(self, data):
        tmp = self.path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, self.path)

    @staticmethod
    def merge(a, b, limit):
        records = {}
        for r in a["records"] + b["records"]:
            if not isinstance(r, dict) or "id" not in r:
                continue
            t = float(r.get("updatedAt", 0) or 0)
            old = records.get(r["id"])
            if old is None or t > float(old.get("updatedAt", 0) or 0):
                records[r["id"]] = r
        removed = {}
        for k, v in list(a["removed"].items()) + list(b["removed"].items()):
            removed[k] = max(float(v), removed.get(k, float("-inf")))
        for k, t in list(removed.items()):
            r = records.get(k)
            if r is not None:
                if float(r.get("updatedAt", 0) or 0) > t:
                    del removed[k]
                else:
                    del records[k]
        cutoff = time.time() - SWIFT_EPOCH - REMOVED_DAYS * 86400
        removed = {k: v for k, v in removed.items() if v >= cutoff}
        ordered = sorted(records.values(), key=lambda r: float(r.get("updatedAt", 0) or 0), reverse=True)[:limit]
        return {"records": ordered, "removed": removed}

    async def handle(self, body, kwargs):
        # AppDaemon 4.5: body = parsed JSON (POST) or query args (GET); the aiohttp request is in kwargs.
        request = kwargs["request"]
        if request.headers.get("X-Beeb-Key") != self.key:
            return {"error": "forbidden"}, 403
        if request.method != "POST":
            return {"ok": True}, 200
        if not isinstance(body, dict):
            return {"error": "bad json"}, 400
        profile = str(body.get("profile") or "main")
        kind = str(body.get("kind") or "history")
        if not SLUG.match(profile) or kind not in LIMITS:
            return {"error": "bad profile or kind"}, 400
        with self.lock:
            data = self.load()
            if body.get("purge"):
                if data["profiles"].pop(profile, None) is not None:
                    self.save(data)
                    self.log(f"purged profile {profile}")
                return {"profile": profile, "purged": True, "records": [], "removed": {}}, 200
            try:
                incoming = {"records": list(body.get("records", [])), "removed": dict(body.get("removed", {}))}
            except (TypeError, ValueError):
                return {"error": "bad json"}, 400
            current = data["profiles"].setdefault(profile, {}).get(kind, {"records": [], "removed": {}})
            merged = self.merge(current, incoming, LIMITS[kind])
            if merged != current:
                data["profiles"][profile][kind] = merged
                self.save(data)
            return {"profile": profile, "kind": kind, **merged}, 200
