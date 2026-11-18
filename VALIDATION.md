# Validation scope

The public source starts from Beeb 0.8.2. The initial public edition preserved playback code apart from the app/Keychain namespace changing to the public template identifier; subsequent changes are recorded below. No credentials or signing account are supplied. Public changes add install documentation, portable setup configuration discovery/validation, release checking and source packaging. Artwork selection now uses plain homepage banners and episode-specific standard stills; the discovery cache namespace is refreshed for this policy.

Original development tests covered native 3840×2160 HLG stream decoding, sustained playback/seeking, native BBC captions on UHD/Full HD, subtitle clock mapping, stream policy, history, discovery, DASH parsing and fragment normalisation. The stream tests used macOS AVPlayer; simulator tests covered native subtitle rendering and app interfaces. A user separately confirmed temporary subtitles after skipping back on Apple TV. These are historical results, not a new test of the public edition on another person's account/device.

The setup helper's --check validates local configuration shape, matching certificate/key and validity period without starting a server. It cannot confirm BBC authorisation. Unit tests use synthetic temporary identities and never a maintainer's credentials.

Current public-edition verification results are recorded in RELEASE-CHECKS.md. No fresh personal-account provisioning, physical Apple TV installation, TwinVine credential transfer or live BBC playback is implied by an unsigned build or offline test pass. Those steps must be verified by each installer on their own setup.

## 0.9.0 catalogue and playback changes

Added tests for complete A–Z pagination, replacement UHD versions, expired/future/accessibility variants, accent-insensitive search, bundled snapshot decoding, daily cache suppression, interrupted-queue persistence, failed-request retention and removal after a successful negative availability check. Playback policy now labels all received 2160p pictures as 4K, regardless of HDR metadata. Native keyboard/dictation availability still depends on the Apple TV system settings.

The catalogue, playback-policy and playback-extras test scripts pass, as do Debug simulator and signed Release device builds. Simulator checks confirmed the native search keyboard, cached UHD results and a decoded local 1080p video with its actual Full HD badge beside the subtitle (14-point horizontal gap and vertical centres within one point). The bundled snapshot decodes 3,643 programme entries and 95 UHD programme groups; it is an initial partial snapshot, not proof of a completed availability scan. A live catalogue test from macOS timed out, so automated live BBC refresh and Siri Remote dictation have not been verified end to end for this update. The maintainer's configured Apple TV installation launched successfully; each installer still supplies their own signing and UHD setup.

## 0.9.1 interface changes

Search now shows only the native search field and matching results, without a heading, help text or catalogue status controls. UHD-category programme pages keep every season and episode visible, retaining individual 4K badges; they initially select a season containing UHD when available. Received 1080p video is labelled FHD, while 720p remains HD. The playback-policy checks cover both labels.

## 0.9.2 playback spacing

Raised the metadata block and constrained its bottom at least 32 points above AVKit's public unobscured-content boundary, allowing the layout to follow changes in the native playback controls rather than relying only on a fixed screen inset.

Debug simulator and signed Release builds passed. A simulator playback-layout capture confirmed the raised title above the transport area; the recorded metadata bottom was 821 points against AVKit's 930-point boundary on a 1080-point display. The 0.9.2 update was installed on the configured Apple TV.

## 0.9.3 metadata contrast

Moved the non-interactive metadata into a containing view above the native player, rather than AVKit's content overlay beneath its controls. This prevents the native controls' dimming layer from darkening the labels. Title, subtitle and badge now use opaque white; the playback-control clearance and transport visibility delegate remain in place.

Debug simulator and signed Release builds passed. A simulator capture confirmed white metadata, and a local 1080p video decoded with the FHD badge. Recorded geometry preserved the metadata bottom at 821 points against AVKit's 930-point boundary.

## 0.9.4 native playback metadata

Removed the custom metadata overlay and containing player controller. AVKit's standard transport title view now handles title/subtitle position, typography, contrast and progress-bar spacing. The received quality label is appended to the native episode metadata line; it no longer uses a separate outlined overlay badge. Native skip actions remain unchanged.

Debug simulator and signed Release builds passed. A simulator capture confirmed the standard title and episode line above the native progress bar, and local playback decoded at 1080p without an error.

## 0.9.5 outlined quality mark

Restored the outlined received-quality mark as a non-interactive overlay alongside the native episode line. AVKit still renders and positions the programme title and episode text. The badge follows transport visibility and is placed above AVKit's dimming layer. Its position uses the public unobscured-content boundary at the native episode line and the measured episode text width.

Debug simulator and signed Release builds passed. A local playback capture confirmed the outlined FHD mark beside the native episode text, with its centre at the 775-point guide boundary and its left edge at 327 points on a 1920×1080 display. The native title and progress bar retained their standard positions.

## 0.9.6 live metadata

Removed the redundant “• Live” suffix from all live-channel subtitles. Playback now tracks live-channel state explicitly, including resetting it before on-demand playback. The outlined quality mark reserves additional space for AVKit's red LIVE indicator before measuring the channel name. On-demand badge placement is unchanged.

Debug simulator and signed Release builds passed. A local HLS live fixture produced AVKit's actual red LIVE indicator followed by BBC Two and the outlined FHD mark, with no trailing “• Live” or overlap. The captured badge was at x=294 with its vertical centre aligned to the 774-point metadata boundary.

## 0.9.7 homepage banner

Removed the arrow buttons and numeric carousel counter. The banner now uses a taller 2.35:1 frame instead of a fixed 530-point height, reducing vertical artwork cropping. Left/right move commands on the focused banner cycle through the cards and wrap at either end; up/down retain normal focus navigation and Select opens the programme. VoiceOver adjustment also changes cards. Automatic rotation continues to pause while the banner has focus. Settings now reads the installed version from the app bundle.

Debug simulator and signed Release builds passed. A simulator capture using offline artwork confirmed the taller focused banner, no arrow/counter row and the next programme row below it. The focus record confirmed the banner retained focus. Physical remote navigation has not been automated in this validation.

## 0.9.8 homepage section spacing

Added the same 30-point bottom focus space beneath the banner that programme rows already reserve. Combined with the homepage's 34-point section spacing, the gap before Continue Watching now matches the gap before subsequent sections such as Most Popular Today. The padding belongs to the banner, so an empty Continue Watching row introduces no extra space.

## 0.10.0 lightweight UHD index

Replaced background episode scanning with one daily download of BBC's UHD help article, merged with cached discoveries. Old full-scan queue fields are no longer decoded or resumed. Search retains a separate daily A–Z summary refresh, without programme episode requests. Opened programme details update UHD discoveries without extra requests; unknown episode links resolve their actual programme parent lazily. The category reports the webpage refresh time rather than claiming a complete availability scan.

Catalogue tests pass for one-request refresh, old-cache migration, daily freshness, manual refresh, failed-request backoff, cancellation, retained discoveries and learned parent aliases. The actual downloaded BBC article parsed 93 distinct links. Lifecycle tests confirmed an episode link opens its full parent programme with both UHD and non-UHD episodes. Debug simulator and signed Release device builds passed. This editorial list plus cached discoveries does not guarantee exhaustive current UHD availability.

Installed and launched on the configured Apple TV. Reading only the public-metadata cache confirmed a successful UHD webpage refresh, 96 retained UHD programme groups, no retry errors and no legacy scan queue/progress keys. The 3,643-title Search index remains separate from UHD discovery.

## 0.10.1 card consistency

Removed the extra UHD episode-count line so every UHD category entry uses the same ShowCard layout. Standalone titles no longer show an episode count; their fixed metadata-line space remains reserved to keep card heights consistent. Series with one available episode use the singular “1 episode”. Replacement film metadata has not been selected yet.

## 0.10.2 minimal UHD category

Removed the descriptive paragraph, last-updated timestamp and saved-list explanation from the UHD category. Update activity is indicated within the existing update button. Error text appears only when an update fails. Catalogue caching and daily refresh behaviour are unchanged.

## 0.10.3 · Native programme Info and Back behaviour

The native player receives description, runtime, original broadcast date, guidance and optional JPEG artwork in addition to title/subtitle. Original-date fields come from the selected BBC version’s `first_broadcast` and `first_broadcast_date_time`, not catalogue re-release dates. Episode parsing prefers the full synopsis. Existing cached Programme values remain decodable. The selected episode metadata request also supplies version-matched skip markers; optional artwork failure does not stop playback, and cancelled/stale requests cannot update a replacement item.

Removed the outer SwiftUI Back interceptor. AVKit now handles Info/control dismissal and requests closure of the embedded player through `playerViewControllerShouldDismiss`. Native title placement and the outlined quality badge remain in place.

Fixture suites cover native metadata values/artwork, legacy decoding, original broadcast versus re-release, full synopsis, skip markers, catalogue lifecycle and cached UHD/search behaviour. The simulator playback fixture confirms the active AVPlayerItem retains synopsis, runtime, first broadcast and guidance while playing, with an FHD quality badge and no error. Hardware remote navigation still needs verification on Apple TV. The signed 0.10.3 (build 24) archive was installed successfully over Beeb Public on the paired Apple TV. The updated app launched successfully. No GitHub publication was performed.

## 0.10.4 · Remove duplicate date and runtime text

The expanded synopsis contains the synopsis and guidance, without appended Length or First broadcast lines. The original release date remains available to the native Info footer alongside AVKit’s actual media duration. Simulator checks established that both release-date and creation-date metadata cause AVKit to prefix the year in its transport subtitle. The native transport title is therefore disabled; white title/subtitle labels share Beeb’s existing noninteractive quality overlay, omit the year, and follow native control visibility. Native Info, artwork, footer date, duration, MORE and Back handling remain managed by AVKit.

Native simulator screenshots confirmed no year beside the quality badge and retained year/duration in Info. Title spacing was adjusted to preserve clearance above the scrubber. Native metadata fixtures pass with unchanged original-date/artwork values and no duplicate runtime/date in the description. No GitHub publication.

Final 0.10.4 verification: simulator remote navigation passed with rendered transport/Info captures; signed archive succeeded and the update installed successfully on the paired Apple TV.

## 0.10.5 · Info dismissal and layout isolation

User reports video continuing while the Info overlay becomes stuck. No matching local device crash report was available; the exact physical-device freeze was not independently reproduced. Removed cross-hierarchy constraints between the title labels and AVKit’s animated unobscured-content guide, and stopped changing constraints/transforms inside the overlay layout pass. The overlay now observes native geometry, uses isolated frame layout only when values change, and stops its geometry sampling while controls are hidden. Identical configure calls no longer invalidate layout.

Restored an explicit SwiftUI Back handler that closes active native Info/controls through AVKit’s public playback-controls API, without pausing/stopping the player. Once controls are closed, Back can dismiss the player. Native embedded-player dismissal remains supported. Artwork uses ImageIO downsampling to a maximum of 960 pixels off the main actor; invalid images are rejected and cancelled/stale loads cannot update a replacement item.

Simulator UI automation repeatedly opened Info and dismissed it with Back four times with JPEG artwork, a long synopsis and the native date/duration footer. All four opening/dismissal assertions passed. The main-actor heartbeat reached 44 seconds with video at 47.35 seconds, no playback error and 14 overlay layout passes; no uncontrolled layout loop occurred. Fixture tests verify bounded artwork decoding, invalid-image rejection and existing metadata/subtitle behaviour. The remaining hardware check is the user’s reported programme/remote path on Apple TV. No GitHub publication.

The signed 0.10.5 (build 26) archive succeeded and installed successfully over Beeb Public on the paired Apple TV.

## 0.10.6 · Safe Info, immediate Back exit and live Top Shelf

Retrieved physical-device crash reports for 0.10.4 and 0.10.5. Both show a watchdog termination while AVKit's expanding summary repeatedly measures text through TextKit. Replaced that description path with an app-owned Info card opened by a transport-bar Info action. It uses bounded UILabel layout and a scroll view, programme artwork, synopsis, original broadcast date, runtime and quality. Native audio/subtitle settings remain enabled. The first Back hides Info/controls; the next Back immediately stops playback and dismisses the enclosing playback screen. Non-Back navigation resets that exit state.

The final simulator UI suite passed all three tests: three repeated openings from the actual Continue Watching row using a short cached synopsis without MORE, immediate two-Back return to the row each time, native English subtitle menu availability, and the actual Top Shelf provider returning 11 landscape channel cards with matching display/play actions and images. A local video fixture isolates these UI checks from BBC stream availability. Direct URL routing also started BBC News and switched the running player to BBC Two; test instrumentation confirmed live playback state for both.

Added an embedded TVServices Top Shelf extension with live-channel landscape cards, public current-programme imagery and cached channel artwork fallback. Both Select and Play route directly into live playback. Content refresh uses a ten-minute extension cache; no account credentials or stream URLs are shared. Move Beeb to the Apple TV home screen's top row to use the shelf.

The source privacy check passed for 104 files. The unsigned device Release archive succeeded, with matching app/extension version 0.10.6 (27) and distinct bundle identifiers. After signing into Xcode, automatic provisioning created the Top Shelf extension profile. The signed Release archive succeeded, full app/extension signature verification passed, and devicectl confirmed installation of 0.10.6 (27) on the paired Apple TV. The updated app launched successfully. No GitHub publication was performed.

Packaged Beeb-0.10.6-public-unsigned.ipa from a fresh public-identifier Release device build. Both app and embedded Top Shelf extension are arm64, version 0.10.6 (27), with no executable code signatures or provisioning profiles. Removed debug symbol paths; the unsigned IPA privacy/structure check passes. Archive integrity and SHA-256 checks pass. Sideloadly signing/installation has not been exercised with this IPA.

IPA packaging correction: ditto had added AppleDouble metadata including PlugIns/._BeebTopShelf.appex, which the device installer treated as an invalid extension. Regenerated the unsigned IPA without AppleDouble, Finder or __MACOSX entries, retaining the actual Top Shelf extension. The strengthened release checker rejects the original defective archive and accepts the clean archive. Packaging now uses zip -X with metadata exclusions and replaces stale ZIP output. Previously signed copies must be signed again from the clean input because their resource seals can include metadata. The original unsigned filename and checksum have also been replaced with the corrected data.

## Pending update · Screenshot review

Implemented a larger bounded programme Info card with equal thumbnail padding, no Close button and scrollable synopsis; two Back presses still hide Info then stop/exit. Added six native VOD playback speeds using AVKit, with no speed control for live channels. Removed Explore programme and the extra ShowCard metadata line; widened homepage cards. Stream Every Episode uses genuine BBC portrait artwork at a verified supported 640×960 recipe, with a title fallback only when no portrait is available. Existing cached models remain decodable.

BBC's public directory confirmed 16 BBC One regions and three BBC Two versions. Settings select these independently; generic Live/Top Shelf channel actions resolve the saved selection inside the main app, without adding App Group signing requirements. Top Shelf uses channel branding for BBC One/Two to avoid wrong-region programme imagery.

Simulator and unsigned physical-device Release builds passed. Catalogue, legacy-decoding, regional routing and playback metadata checks passed. UI review tests confirmed Info opening, no Close button, immediate two-Back return, native 1.5× selection, BBC Two choices, and the native Reduce Loud Sounds checked state persisting when reopened. Source privacy check passed for 104 files. The player captures use a local test video with genuine downloaded BBC episode metadata and artwork, rather than claiming BBC playback was tested in those captures.

Audio Adjustments is a native menu heading. Reduce Loud Sounds was verified selectable. Enhance Dialogue was not offered by the simulator; the existing AVAudioSession moviePlayback mode is eligible on supported hardware/routes, but no audible enhancement fix is claimed. The sectioned Top Shelf layout has no separate public background property. A full-screen purple carousel was built/captured behind a review-only compilation flag; it changes the channel-row presentation and is not enabled in the default build.

Actual captures and a standalone gallery are in the separate local preview output. Waiting for user review and a Top Shelf layout choice before version bump and unsigned IPA packaging. No physical Apple TV install or GitHub publication was performed for this update.


## 0.10.7 (28) · Final unsigned IPA

Restored TopShelf/ContentProvider.swift byte-for-byte to the original 0.10.6 provider at the user's request: sectioned landscape live channel cards with current programme artwork and one-click playback. The purple background experiment is excluded. All other reviewed changes are retained, including the Info card layout, native playback speed selector, poster cards, larger programme cards without “Explore programme”, and regional BBC One/Two preferences applied when playback begins. Native audio controls remain available; Reduce Loud Sounds was verified in the simulator, while Enhance Dialogue availability depends on Apple’s supported hardware and audio route.

Unsigned physical tvOS Release build succeeded. Main app and Top Shelf extension both use version 0.10.7, build 28. The packaged IPA passed archive integrity, unsigned arm64 executable, public bundle identifier, signing-profile, AppleDouble metadata, and public source/privacy checks. SHA-256 verified. Output: Beeb-0.10.7-public-unsigned.ipa. No physical-device installation or GitHub publication was performed.


## 0.10.8 (29) · RED additional streams

The approved text-only RED icon is a native transport-bar UIAction for live playback. A native Additional streams action sheet offers Red Button and Red Button UHD. On-demand playback keeps Info and the native speed selector. Additional-stream resolution is cancellable, scoped to the current playback generation and performed before replacing the working player item. Failure is reported in a separate alert. Back dismisses the stream menu/error before exiting playback.

Added the single-period live HEVC/AAC DASH subset used by the curated BBC event endpoint. Rolling HLS playlists have stable sequence-based resource names, matching wall-clock dates, bounded retained resources and no VOD/end markers. Initialization must signal HLG; recent video and audio fragments must pass the existing normalization path before adoption. Protected, ended/off-air, malformed and unsupported period transitions are rejected. No credentials or live BBC media are bundled.

Initial Release and Debug simulator builds passed. Existing DASH/fragment/range checks, live channel routing, and live UHD fixture tests passed. The running bridge fixture advances playlists on its original loopback URL. BBC Red Button currently returns an HLS master. Actual live UHD playback during a BBC event is not claimed: this needs an active compatible feed and a physical Apple TV check. The integrated UI automation could not complete: the tvOS 27 simulator repeatedly stalled during installation/launch, including a simulator-only copy without the extension. No integrated remote-navigation or screenshot result is claimed. The approved separate native preview is not presented as an integrated capture. Physical Apple TV validation of menu selection, Back and live event playback remains outstanding.

Final 0.10.8 device Release build passed after the repeated-error alert fix. The unsigned IPA includes the matching 0.10.8 (29) app and Top Shelf extension, both arm64 with no executable signature or provisioning profile. Archive integrity, public identifiers, metadata exclusions, detected personal-path/key-marker checks and SHA-256 verification passed. Live UHD fixtures passed again without warnings. Temporary integration simulator and build outputs were removed after packaging; no physical-device install or GitHub publication.
