# SPDX-License-Identifier: GPL-3.0-or-later
"""Beeb household sync: storage + merge logic shared by the AppDaemon app and the standalone server.

Protocol (see docs/SYNC.md): the app POSTs JSON
    {"profile": "<id>", "kind": "history" | "saved" | "profiles" | "settings" | "channels" | "episodes", "records": [...], "removed": {"<id>": <time>}}
with header X-Beeb-Key: <shared key>. The server merges and replies with the merged {"records", "removed"}.
    {"profile": "<id>", "purge": true} deletes everything stored for that profile (sent when a profile is removed).
Records are opaque JSON objects with "id" and "updatedAt" (seconds since 2001-01-01, Swift's default date encoding).
Merge: per id the newest updatedAt wins; a removal wins over records that aren't newer than it, and a newer record
clears the removal. Removals older than 90 days are forgotten.
"""
import json
import os
import re
import threading
import time

SWIFT_EPOCH = 978307200  # 2001-01-01 in Unix time
LIMITS = {"history": 60, "saved": 300, "profiles": 50, "settings": 20, "channels": 200, "episodes": 600}
REMOVED_DAYS = 90
SLUG = re.compile(r"^[a-z0-9_]{1,32}$")


class SyncStore:
    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()

    def load(self):
        try:
            with open(self.path) as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = {}
        if not data:
            data = {"profiles": {}}
        elif "profiles" not in data:  # file from a build before profiles: it held the default profile's history
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

    def handle(self, body):
        """Process one POST body. Returns (reply_dict, http_status, log_line_or_None)."""
        if not isinstance(body, dict):
            return {"error": "bad json"}, 400, None
        profile = str(body.get("profile") or "main")
        kind = str(body.get("kind") or "history")
        if not SLUG.match(profile) or kind not in LIMITS:
            return {"error": "bad profile or kind"}, 400, None
        with self.lock:
            data = self.load()
            if body.get("purge"):
                gone = data["profiles"].pop(profile, None) is not None
                if gone:
                    self.save(data)
                return {"profile": profile, "purged": True, "records": [], "removed": {}}, 200, (f"purged {profile}" if gone else None)
            try:
                incoming = {"records": list(body.get("records", [])), "removed": dict(body.get("removed", {}))}
            except (TypeError, ValueError):
                return {"error": "bad json"}, 400, None
            current = data["profiles"].setdefault(profile, {}).get(kind, {"records": [], "removed": {}})
            merged = self.merge(current, incoming, LIMITS[kind])
            line = None
            if merged != current:
                data["profiles"][profile][kind] = merged
                self.save(data)
                line = f"{profile}/{kind}: {len(merged['records'])} records, {len(merged['removed'])} removed"
            return {"profile": profile, "kind": kind, **merged}, 200, line

    def summary(self):
        data = self.load()
        return {p: {k: len(v["records"]) for k, v in kinds.items()} for p, kinds in data["profiles"].items()}
