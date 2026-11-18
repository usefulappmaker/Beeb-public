# Beeb 0.11.0: profiles, kids mode, TV guide, Top Shelf choices and Beeb for Mac

Changes since **0.10.9**:

- **Profiles:** each person gets their own Continue Watching and Saved list. Switch with the profile button in the top bar and choose what happens on launch.
- **Kids mode:** CBeebies and CBBC only, no programmes with BBC guidance warnings, no Search, Browse, 4K or Settings, and an optional PIN to leave the kids profile.
- **Household sync (optional):** share profiles, Continue Watching, Saved and the kids PIN between Apple TVs through a server you run. Off until you enter one in Settings → Household sync.
- **Channels page:** Live is now Channels, with a channel wordmark strip, an ON NOW card and each channel's featured programmes.
- **TV guide:** switch to Guide for a timeline of every channel, up to eight hours back. Pink plays live; teal is already on iPlayer.
- **Watch from start:** Watch from start and Live buttons in the live player, plus an optional "from the start or live?" prompt.
- **Choose your Top Shelf:** Live TV, Continue Watching, Saved or a Mix, in Settings → Top Shelf.
- **Faster search:** typing and dictation no longer stall while results update.
- **Better programme pages:** newest series first, series tabs, Start watching/Resume, and Up from the first episode row now reaches the series tabs.
- **Beeb for Mac (preview):** a new macOS 14 app built from the same sources.

Thanks to community contributors lewisburgess, threepeakschallenge, videojedi and ChristopherJohnDillon. Full details in [CHANGELOG.md](CHANGELOG.md).

## Downloads

- **Beeb-0.11.0-public-unsigned.ipa**: Apple TV, tvOS 17+. Sign the app and included Top Shelf extension yourself before installation. See [INSTALL-IPA.md](INSTALL-IPA.md).
- **Beeb-0.11.0-mac-unsigned.zip**: Beeb for Mac preview, macOS 14+. See [INSTALL-MAC.md](INSTALL-MAC.md).
- **Beeb-0.11.0-public-source.zip**: matching GPL source, Xcode projects and instructions.
- SHA-256 checksums for each download.

Keep the same signing team and bundle identifier when updating, so profiles, Saved, Continue Watching and UHD setup are retained. The Top Shelf choices need the new App Group in your signing; without it, Top Shelf shows Live TV.

UHD needs an Apple TV 4K, compatible content and display connection, and configuration currently accepted by BBC. Beeb downloads that configuration at setup time; no identity is embedded in these downloads. Beeb remains independent and unofficial.
