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


---

# Changes

## 0.10.8 (build 36)

- Added Settings → Display 4K UHD category, enabled by default. Turn it off to hide 4K UHD in Classic/Modern Topbar, Modern Sidebar and Browse categories; the preference is saved independently of TwinVine setup.
- Added Settings → Homescreen Layout: Classic or Modern; Modern offers Topbar or Sidebar and retains the navigation preference across layout changes. Default: Modern Sidebar.
- Added cinematic modern homescreens with large artwork, scrolling navigation/banner, a glowing Beeb mark and plain white Beeb text. Classic retains the public release's compact topbar and framed banner.
- Reworked Browse with readable, icon-led category tiles and the native Categories/A–Z selector.
- Categories and A–Z append pages as you scroll; all indexed UHD programme cards appear in one lazy grid. Removed Previous/Next controls for these listings; episode and Search pagination are unchanged.
- Added native live subtitles by discovering BBC live TTML fragments and exposing timed WebVTT. Uses programme dates and video timestamps, with discontinuity and rewind handling. Maintainer confirms live captions work on Apple TV.
- Added explicit previous-screen Back handling for programme, category, episode-detail and region screens; section roots return Home. Back closes the sidebar. Additional Streams includes native Cancel so Back returns to the current channel without a selection.
- Replaced the obsolete programme playlist endpoint with the current BBC episode API; match episode IDs, filter unavailable/signed/described variants and prioritise UHD versions when appropriate.
- Restored standard public Beeb icons, names, links and Keychain namespace; app and Top Shelf extension share version 0.10.8 (36). Unsigned IPA contains no development identity or device provisioning.

### Additional streams introduced in this release


- Added a native RED action to every live player, alongside Info, subtitles and audio. The approved icon is larger white text on the existing control background, with no inner circle. On-demand controls remain unchanged.
- Added the Additional streams menu with Red Button (`red_button_one`) and Red Button UHD (`uk_bbc_stream_041`). The new feed is resolved before replacing the working channel, so an off-air/error response leaves the current stream playing. Back dismisses the Additional Streams menu without switching channels.
- Added a bounded rolling live DASH-to-HLS adapter for the curated 4K HLG event feed, preserving encoded HEVC/AAC media without transcoding. Checks HLG initialization signalling and playable fragments before switching, refreshes the live window and manifest, and rejects stale/off-air, protected and unsupported multi-period feeds.
- The live UHD entry is event-dependent; it is not a permanent BBC One/Two UHD simulcast. Actual BBC live UHD playback still requires validation during an active compatible event. No live UHD device-playback result is claimed by fixture tests.

## 0.10.7 (build 28), compared with public release 0.8.2

### Browse and discover

- Added a minimal Search tab covering the cached BBC A–Z programme catalogue, matching titles and synopses. Uses the native Apple TV keyboard, with dictation and the iPhone keyboard where supported.
- Added a 4K UHD category backed by a bundled snapshot, cached discoveries and a daily refresh of BBC's UHD webpage. Replaces the earlier full-catalogue episode scan. The BBC editorial list is not guaranteed to include every currently available UHD programme.
- Programme pages opened from 4K UHD retain all seasons and episodes; individual UHD episodes are tagged rather than hiding the HD episodes.
- Larger homepage banner with less image cropping, left/right remote navigation, no arrow buttons or page counter, and consistent spacing before Continue Watching.
- Larger homepage programme cards without redundant “Explore programme” text or episode-count lines. Stream Every Episode uses clickable portrait-only posters.
- Removed extra UHD episode counts, explanatory text and refresh timestamps from the UHD listing.

### Watch

- Added an Info button showing programme/episode title, thumbnail, full synopsis, original broadcast date, runtime, quality and guidance where provided by the BBC.
- Replaced the native expanding-summary path that caused Info freezes/watchdog crashes with a bounded, scrollable description card. Removed redundant date/runtime text, the duplicate year above the title and the Close Info button.
- Back hides Info or playback controls; a second immediate Back exits playback.
- Added native on-demand playback speeds: 0.5×, 0.75×, 1×, 1.25×, 1.5× and 2×.
- Received-quality badges now read 4K, FHD (1080p), HD (720p) or SD. Kept the outlined style, improved contrast and spacing beside episode metadata, and removed the redundant live-text suffix. The 4K badge reports resolution, not HDR status; compatible HLG HDR playback remains supported.

### Live TV and installation

- Added landscape live-channel cards to Apple TV Top Shelf: place Beeb in the top row, press Up, then select a channel to start playback. Includes current programme artwork with channel fallback cards.
- Added Settings choices for 16 BBC One regions and three BBC Two feeds, applied when starting channels from Live or Top Shelf. Top Shelf artwork still uses the default channel schedule.
- Included the Top Shelf extension in the unsigned IPA, with matching version/build and separate bundle identifier.
- Removed AppleDouble/Finder ZIP metadata that could cause an extension installation error. Updated public release checks and signing guidance.

### Existing features retained

4K HLG HDR using your own TwinVine UHD setup; automatic HD fallback; native English subtitles including Show on Skip Back where supported; skip intro/recap where BBC timings exist; Continue Watching, Up next, bookmarks and live TV.

Native audio menus remain in use. Reduce Loud Sounds selection was checked in the simulator; Enhance Dialogue was not available there and is not advertised as a new Beeb capability. Availability depends on tvOS and the supported audio setup.

## 0.8.2

Initial public GitHub release, with matching source and an unsigned tvOS IPA. Included UHD playback, native subtitles, intro/recap skipping, local viewing history, saved programmes, live channels, logo-free banners and individual episode artwork where available.
