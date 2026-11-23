# Household sync

Beeb keeps profiles, each person's **Continue Watching** and **Saved** list, and the kids PIN on the Apple TV.
With household sync, every Apple TV in your home shares them through a small server **that you run** — for
example on Home Assistant. Start something in one room and resume it in another; add a profile once and it
appears everywhere.

Sync is **off** until you enter a server in **Settings › Household sync**. Nothing is sent anywhere else.

There are two ready-made servers. They behave identically; pick one.

| | Needs | Address to enter in Beeb |
|---|---|---|
| [Home Assistant (AppDaemon)](#option-1-home-assistant-appdaemon) | Home Assistant OS/Supervised with the AppDaemon add-on | `http://<home-assistant>:5050/api/appdaemon/beeb_history` |
| [Standalone (Python or Docker)](#option-2-standalone-python-or-docker) | Any always-on machine (NAS, Raspberry Pi, Mac, PC) | `http://<machine>:8765/beeb_history` |

You'll also need a **key**: a long random password shared by the server and your Apple TVs. Make one with
`python3 -c "import secrets; print(secrets.token_urlsafe(24))"` or any password manager (16+ characters).

---

## Option 1: Home Assistant (AppDaemon)

1. **Install AppDaemon.** In Home Assistant: **Settings › Add-ons › Add-on Store**, search **AppDaemon**,
   **Install**, then **Start**. Turn on **Start on boot**.
2. **Copy the app.** Put [`sync-server/appdaemon/beeb_sync.py`](../sync-server/appdaemon/beeb_sync.py) into
   AppDaemon's `apps` folder. With the **File editor**, **Studio Code Server** or **Samba** add-on this is
   `/addon_configs/a0d7b954_appdaemon/apps/` (shown as `addon_configs/a0d7b954_appdaemon/apps` over Samba).
3. **Configure it.** Add this to `apps.yaml` in the same folder, with your own key
   (see [`apps.yaml.example`](../sync-server/appdaemon/apps.yaml.example)):

   ```yaml
   beeb_sync:
     module: beeb_sync
     class: BeebSync
     key: "your-long-random-key"
   ```
4. **Check the log.** AppDaemon reloads apps automatically. Its log (**Settings › Add-ons › AppDaemon › Log**)
   should show `Beeb sync ready`.
5. **Connect each Apple TV.** In Beeb, **Settings › Household sync**: enter
   `http://<your-home-assistant-address>:5050/api/appdaemon/beeb_history` and the key, then **Test connection**.
   Use Home Assistant's IP address if `homeassistant.local` doesn't resolve on your network.

Port 5050 is AppDaemon's own web server (the add-on exposes it on your network by default). The data lives in
`beeb_history.json` next to the app, so it's included in Home Assistant backups that include add-on configs.

## Option 2: Standalone (Python or Docker)

**Python** (3.9+, nothing to install):

```sh
cd sync-server
BEEB_SYNC_KEY="your-long-random-key" python3 standalone/beeb_sync_server.py
```

Optional: `BEEB_SYNC_PORT` (default `8765`), `BEEB_SYNC_DATA` (default `./beeb_sync.json`). Run it as a service
(launchd, systemd, a NAS task) so it starts on boot.

**Docker:**

```sh
cd sync-server
# edit standalone/docker-compose.yml and set BEEB_SYNC_KEY
docker compose -f standalone/docker-compose.yml up -d --build
```

Data is kept in `sync-server/standalone/data/`. Then in Beeb enter `http://<machine>:8765/beeb_history` and the key.

---

## How it behaves

- **Profiles** (names, kids flag) are shared by every Apple TV using the server. Removing a profile deletes its
  data on the server and on every Apple TV.
- Which profile is **current**, and the **On launch** choice, stay per Apple TV.
- Beeb syncs when it opens or comes back to the front, a few seconds after a change, about every 30 seconds
  during playback, and once a minute while it's on screen — so another room catches up within about a minute.
- If the server can't be reached, Beeb carries on with what's on the Apple TV and catches up later.
- Conflicts: for each programme the most recent change wins; removing something wins over older progress.

## Security

The server is meant for a **home network**. Requests carry the key in a header over plain HTTP, so anyone on
your network who can see the traffic could read it. Don't forward the port to the internet; if you need access
from elsewhere, put the server behind HTTPS (for example a reverse proxy) or a VPN.

## Protocol (for writing your own server)

`POST` JSON to the URL with header `X-Beeb-Key: <key>`:

```json
{"profile": "main", "kind": "history", "records": [{"id": "…", "updatedAt": 816640984.6, "...": "..."}], "removed": {"<id>": 816641000.0}}
```

- `kind`: `history` (Continue Watching), `saved`, `profiles` (sent with `profile: "household"`), `settings`, `channels` (favourite channels: `id`, `position`), `episodes` (per-episode progress: `id`, `position`, `duration`, `completed`)
  (household settings such as the kids PIN, also `profile: "household"`).
- Records are opaque objects with an `id` and `updatedAt` (seconds since 2001-01-01).
- Merge per `(profile, kind)`: newest `updatedAt` per id wins; a removal beats records that aren't newer than it;
  a newer record clears the removal. Reply with the merged `{"records": [...], "removed": {...}}`.
- `{"profile": "<id>", "purge": true}` deletes everything for that profile.
- Wrong key: `403`. Bad input: `400`.

[`sync-server/beeb_sync_core.py`](../sync-server/beeb_sync_core.py) is a reference implementation.
