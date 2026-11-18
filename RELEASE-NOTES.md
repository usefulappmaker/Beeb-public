# Beeb 0.10.9 hotfix: one-step BBC UHD setup and navigation fixes

Changes since **0.10.8**:

- **One-step UHD setup:** open **Settings → Enable BBC UHD** and select **Enable BBC UHD**. Setup runs entirely on Apple TV; no separate computer, downloader, Python installation, helper or copied setup URL is needed.
- **Check before connecting:** Beeb validates the downloaded configuration and checks for a compatible BBC 4K HLG stream before saving the identity securely in the device-only Keychain. Cancelling or a failed check keeps your existing setup.
- **Modern Topbar focus fixed:** pressing Down from any Home topbar heading goes directly to **Watch now**, without first jumping through a programme card. Returning Up to navigation is more reliable across pages.
- **Sidebar shortcuts:** press Left at the left edge of a row or control to open the sidebar. Close it with Right, Back or the current section to return to the same item and scroll position.
- **Saved is easier to reach:** pressing Up from any episode in the first row reaches the programme's bookmark, including programmes with several series.
- **More reliable controls:** Browse and homescreen-layout options use native SwiftUI buttons with individual focus targets. Move between choices with Left/Right and click to select.
- **Cleaner Live page:** removed the explanatory quality line below the heading.
- **Simpler setup screen:** removed manual helper setup and setup-URL entry. Updated installation and UHD instructions for the new flow.

## Downloads

- **Beeb-0.10.9-public-unsigned.ipa** — Apple TV, tvOS 17+. Sign the app and included Top Shelf extension yourself before installation.
- **Beeb-0.10.9-public-source.zip** — matching GPL source, Xcode project and instructions.
- SHA-256 checksums for both downloads.

Keep the same signing team and bundle identifier when updating. The app uses the normal Beeb icon and public identifiers. The existing **Display 4K UHD category** setting is retained.

UHD setup no longer requires a computer; signing and installing the app remain separate steps. UHD needs an Apple TV 4K, compatible content/display connection and configuration currently accepted by BBC. Beeb downloads that configuration from the upstream service at setup time; no identity is embedded in these downloads. Service or identity changes can affect availability. Beeb remains independent and unofficial.
