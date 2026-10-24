# Public edition verification

## Release: 0.10.9 hotfix (40)

- Based on public 0.10.8 and the approved TEST build 39 navigation/setup changes. Standard Beeb icon, public app/extension identifiers, URL scheme and device-only Keychain namespace are retained.
- Enable BBC UHD is the visible one-step setup name. No manual helper URL entry, downloader or computer is required for UHD setup. Upstream attribution remains in NOTICE.md and SETUP-UHD.md.
- Existing Display 4K UHD category preference remains available across Classic/Modern navigation and Browse.
- Clean physical-device tvOS Release build and Debug simulator build passed. Unsigned app and Top Shelf have matching 0.10.9 (40), arm64 device executables, with no signing profiles or code-signature load commands.
- Four source-boundary tests and three unsigned-payload structural tests passed. Source and final unsigned IPA scans passed, including known private installer/account/team/device and TEST-namespace checks.
- The unchanged native identity packaging/validation logic inherits synthetic encryption, certificate matching, import and rejection coverage from TEST setup validation. The maintainer confirmed one-step setup on their physical Apple TV in TEST. The public signing/install path has not been repeated under another user's account.
- All eight public-app simulator UI tests passed: one-step setup naming/manual removal, UHD category hidden in navigation and Browse, sidebar boundary/return and scroll retention, pushed-page isolation, topbar Up/Down and Saved from all first-row episode columns. The unsigned public IPA requires each installer's own signing; the matching TEST features were installed separately on the maintainer's Apple TV.
- The maintainer approved the hotfix banner on 24 October 2026. It is prepared as a separate release image outside the source tree. Source, IPA and banner are packaged as release assets.

## Historical release: 0.10.8 (36)

- Public app is derived from the approved TEST feature set, with the original public Beeb icon, app/extension identities, live URL scheme and Keychain namespace.
- Added a persisted Display 4K UHD category toggle, default on, shared by all navigation layouts and Browse. Hiding an active UHD tab returns Home and removes hidden focus targets. TwinVine setup is independent.
- Modern/Classic, Topbar/Sidebar, readable categories, continuous listings, episode discovery updates, live captions and Back/Cancel changes are included.
- Prior build 35 native simulator checks on the matching TEST/prototype logic passed for all three layouts, Settings selection/retention, Topbar Down, programme Back, sidebar Back, Settings Back and Additional Streams cancellation.
- Live captions are confirmed working on Apple TV by the maintainer. Automated timing/bridge/rewind checks also cover the live caption conversion. Compatible BBC live UHD event playback remains availability-dependent and is not claimed validated by off-air fixtures.
- Clean-source physical tvOS Release build passed with signing disabled. App and Top Shelf are 0.10.8 (36), arm64, with standard public identifiers and no code-signature load commands or provisioning profiles.
- Build 36: clean unsigned tvOS Release build, three release-boundary tests, three nested unsigned-IPA tests, source boundary scan and unsigned payload scan passed. No new simulator or physical-device UI check was performed for this settings-only change.
- Inherited build 35 validation: resolver, catalogue/lifecycle/index/library, live-caption HTTP/timing/rewind, live UHD rolling/loopback, public live-channel routes and playback policy suites passed. Release-boundary and nested-extension unsigned checks passed.
- Public source and payload scans found no known private installer/account/team/TEST namespace markers. New native screenshot ancillary metadata was removed without changing compressed pixel data.
- IPA ZIP integrity and neutral owner/timestamp metadata checks passed; source packaging runs the release boundary checker and excludes Git history, builds, identities and binaries. SHA-256 files accompany both release assets.
- This unsigned public IPA has not been installed as-is, because it needs the recipient's signing. Matching TEST features were installed separately; the maintainer confirms live captions work. No GitHub upload or public-device installation is part of this preparation.

## Earlier prepared 0.10.8 (29)

- RED is a native live-player action opening the two curated additional streams. On-demand controls retain their previous configuration.
- Live DASH fixtures cover rolling windows, stable sequence/resource mapping, bounded resources, timeline addressing, invalid timing, off-air/protected rejection and an advancing loopback playlist.
- DASH, catalogue, live channel and public source/privacy checks passed. Release and Debug simulator builds passed.
- Integrated simulator UI automation is incomplete because installation/launch stalled. Physical Apple TV remote/menu verification and BBC UHD event playback remain outstanding.
- A fresh unsigned physical-device IPA and matching source archive are prepared locally; no GitHub publication or device installation is performed by this update.

## Historical release: 0.10.7 (28)

- Unsigned physical-device tvOS Release build passed; the app and Top Shelf extension both use version 0.10.7 (28), with distinct public bundle identifiers.
- Both executables are arm64 and contain no code-signature load command. The IPA contains no provisioning profiles, AppleDouble entries or detected private account paths/key markers. Archive integrity and SHA-256 verification passed.
- Original sectioned Top Shelf provider restored; purple-background prototype excluded. Regional feed preferences remain active when a channel starts.
- Latest simulator checks cover Info dismissal and immediate second-Back exit, speed selection, regional settings, and Reduce Loud Sounds selection persistence. Enhance Dialogue was not available in that simulator and is not claimed as a new feature.
- Source privacy/release checks and matching-source packaging are required before publication. No new physical-device installation of 0.10.7 is claimed.

## Historical 0.8.2 preparation checks

- Known private-installer names, account/team/certificate identifiers, original bundle namespace and absolute account paths absent from the public source tree in the preparation audit.
- Source-only release checker: no selected signing team, prohibited artefact types, local account paths, detected key/token patterns, symlinks or unreviewed PNG metadata.
- Xcode project property-list syntax and shell syntax.
- All 12 shipped PNG pixel streams match the original runtime assets; only ancillary metadata was removed. Asset catalogue image references resolve.
- Swift playback sources match 0.8.2 apart from replacing the private app/Keychain namespace with the public template namespace. Catalogue/discovery artwork selection is updated separately: plain homepage banners, episode-specific stills, and a fresh discovery cache namespace.
- Resolver parsing, URL handling, quality selection and selector filtering.
- History persistence, completion/Up next, ordering, removal and corruption recovery.
- Automatic UHD priority, HD fallback, cancellation/error handling and quality badges.
- Version-specific skip markers, HDR/duration metadata, caption parsing/timing, subtitle discovery fixtures and live schedule boundaries.
- Catalogue pagination, ordering, lightweight launch/cache and saved-programme migration.
- Artwork regression checks: distinct episode stills override a shared show logo; missing stills fall back gracefully; homepage banners use plain promotional/default images at the large recipe and never a logo-only fallback. Catalogue/lifecycle/saved-programme and playback-extras suites passed again after the artwork change.
- UHD metadata, codec/range validation, protected-source rejection and unavailable-service handling.
- Offline DASH parser, HLG signalling, protection rejection, range parsing and fragment-padding normalisation subset.
- Three provisioning-helper tests: config discovery/ambiguity, malformed inputs/header injection, and synthetic valid/expired/mismatched certificate-key pairs with no secret output or server startup.
- Three release-boundary tests: reject profiles/selected teams/local paths; exclude builds/Git/environments; reject symlinks.

## Additional installation verification

- A full signed Release archive of the updated public source built successfully after the earlier environment restrictions were removed. Signing team, unique bundle identifier and a separate home-screen display name were supplied as local build overrides; they are not stored in this public project or source archive.
- Installation on a paired physical Apple TV succeeded, and the installed-app list confirmed the separate app alongside the existing installation. Foreground launch was denied because the Apple TV was asleep, so launch and physical playback remain unverified in this installation check.
- Full DASH HTTP loopback/range and padded-fragment regression tests passed after local socket access became available.
- Local signed archives, profiles, build logs and device identifiers remain outside the public source tree. No personally signed IPA is supplied for distribution.

## Unsigned prebuilt release

- Release build from a clean temporary source directory succeeded with code signing disabled, using the public template bundle identifier.
- The initial 0.8.2 unsigned IPA contained the main tvOS app without a Top Shelf extension. The current release also includes the unsigned Top Shelf extension described above. No provisioning profile, code signature, signing certificate or bundled UHD identity is supplied.
- codesign confirmed the app is not signed; executable load commands contain no code signature. The app targets physical arm64 Apple TV devices, with tvOS 17 minimum deployment.
- All payload files were scanned for the original installer's known personal names, account/team/certificate identifiers, original private bundle ID and personal account paths: no matches found. ZIP metadata uses neutral timestamps and no owner extras.
- SHA-256 accompanies the IPA. Matching source is supplied separately under the project licence. The unsigned IPA has not been installed directly, because normal Apple TV installation requires signing first.
- Third-party re-signing instructions are based on upstream documentation. That workflow has not been tested end to end on a new user's account. Xcode source installation remains the documented fallback.

## Not performed

- Signing/provisioning with an unrelated new installer's Apple account.
- Installation on an unrelated user's Apple TV.
- A fresh TwinVine installation, real credential transfer, or live BBC UHD authorisation on a new user's setup.

These require the installer's own account/device and, for UHD, their own accepted identity. Follow INSTALL.md and SETUP-UHD.md. See VALIDATION.md for historical playback evidence; do not describe those earlier results as new public-edition device testing.
