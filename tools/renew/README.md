# Keeping Beeb signed (free Apple account)

With a free Apple developer account, apps you install yourself stop opening after **7 days**. These scripts
rebuild Beeb with your account and reinstall it on your Apple TVs — on demand, or automatically from a Mac
that's always on. Your watch history, Saved list and settings survive a reinstall.

## One-time setup

1. Do the normal first install from [INSTALL.md](../../INSTALL.md): add your Apple account to Xcode, pair each
   Apple TV (**Settings › Remotes and Devices › Remote App and Devices** on the TV, then Xcode's device window),
   and run Beeb once from Xcode with your team selected.
2. `cp renew.conf.example renew.conf` and fill in your bundle id and team id. The team id is shown in Xcode
   under the target's **Signing & Capabilities** (a 10-character code), or in the Apple Developer account page.
3. `cp devices.txt.example devices.txt` and list your Apple TVs. Get the identifiers with
   `xcrun devicectl list devices` (the long `00008110-…` value for each physical Apple TV).
4. Run `./renew.sh` once to check it builds and installs.

`renew.conf`, `devices.txt`, `state/`, `build/` and `renew.log` are git-ignored.

## Renewing automatically

`renew-if-needed.sh` renews an Apple TV only when its signature has less than 3 days left, and only installs to
boxes that respond (installing never wakes the screen, so it won't switch your TV on). Run it every 2 hours:

1. Keep the repository **outside** `~/Documents`, `~/Desktop` and `~/Downloads` — macOS blocks background jobs
   from reading those folders. `~/Developer` works well.
2. `sed "s#/PATH/TO/beeb#$(cd ../.. && pwd)#" com.example.beeb-renew.plist.template > ~/Library/LaunchAgents/com.example.beeb-renew.plist`
3. `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.beeb-renew.plist`

You'll get a Mac notification after a renewal, or if renewing keeps failing close to expiry; details are in
`renew.log`. To stop: `launchctl bootout gui/$(id -u)/com.example.beeb-renew`.

## Notes

- If Xcode reports *Unable to log in with account* (error -1001), it's a temporary Apple sign-in timeout: run again.
- A paid Apple developer account gives one-year signatures, so renewing becomes a yearly job.
- Keep the same bundle id and team for every renewal, or the Apple TV treats it as a different app (and its data).
