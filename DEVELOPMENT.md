# Build and test

Use full Xcode with tvOS support. The project uses no external Swift packages. The build respects DEVELOPER_DIR. Users should follow INSTALL.md for signing and physical installation.

If the scripts are not executable after downloading from GitHub, run this once from the project folder:

```sh
chmod +x ./*.sh ./*.command scripts/*.py
```

## Unsigned device build

```sh
./build.sh
```

Creates build/BeebHD-unsigned.ipa. It still requires signing for an intended Apple TV; it is not a universal installer.

For public distribution, build in a neutral path outside your personal account directory, audit the entire IPA and verify that codesign reports no signature. The 0.10.7 release was built with signing disabled and public bundle identifiers, stripped of debug symbols and executable signatures, then packaged without Finder/AppleDouble metadata. Check future binaries independently:

```sh
python3 scripts/check-unsigned-ipa.py build/BeebHD-unsigned.ipa
```

The prebuilt release asset is named Beeb-0.10.8-public-unsigned.ipa and is distributed separately from the source ZIP with a SHA-256 checksum. The structural check cannot detect every possible identifying string; perform an additional private-identifier audit before publishing.

## Signed archive

Supply your own values, never a maintainer's identity:

```sh
APPLE_TEAM_ID=YOUR_TEAM_ID BEEB_BUNDLE_ID=com.youralias.Beeb ./build.sh
```

Keep generated archives and signing profiles out of the public repository.

## Tests

```sh
./test.sh
./test-history.sh
./test-playback-policy.sh
./test-playback-extras.sh
./test-catalogue.sh
./test-uhd.sh
./test-dash.sh
./test-live-channels.sh
./test-live-uhd.sh
python3 Tests/test_public_release.py
.venv-setup/bin/python Tests/test_setup_helper.py
```

The final helper test requires the optional Python environment from SETUP-UHD.md. Tests use fixtures except explicit live modes. The DASH suite opens loopback sockets; it cannot run fully in a sandbox that denies local listeners. See VALIDATION.md and RELEASE-CHECKS.md for completed checks and limitations.

## Check and package public source

```sh
python3 scripts/check-public-release.py
python3 scripts/make-public-archive.py
```

The source ZIP is created under dist/. No upload is performed. See PUBLIC-RELEASE.md for Git identity and publication checks.

## Bundled catalogue snapshot

`BeebHD/CatalogueSeed.plist` is a Codable property-list snapshot of public BBC programme metadata, included as an app resource. It contains a complete A–Z title index and verified UHD candidates as an initial offline cache, not credentials or signed stream URLs. Encode it with `PropertyListEncoder` so Foundation URL and Date values retain their Codable representation. The catalogue tests decode the actual bundled resource. On-device refreshes update a separate cache from the BBC UHD help article; a separate A–Z summary refresh supports Search. Neither refresh enumerates programme episode lists. Old scan queues are ignored when decoding existing caches. Episode-parent aliases avoid duplicate programme cards; unknown episode links resolve their parent lazily when opened. Freshly opened programme details update saved UHD discoveries without additional requests. Refresh work waits during video playback.

## Live Top Shelf

`BeebTopShelf` is embedded in BeebHD. Set `BEEB_APP_BUNDLE_IDENTIFIER` when overriding signing identifiers, rather than overriding `PRODUCT_BUNDLE_IDENTIFIER` for every target. The main app and extension must have distinct identifiers sharing the main app prefix. `build.sh` handles this through the existing `BEEB_BUNDLE_ID` option. The extension refreshes its public BBC channel/schedule snapshot at most every ten minutes when tvOS requests content. It stores no credentials or stream URLs and uses no App Group. `test-live-channels.sh` checks routing and artwork parsing. Select and Play/Pause use the same `beeb://live/<channel-id>` route.

## UHD setup in 0.10.9

The UI uses native on-device configuration download, validation and identity packaging. No additional Python dependency is required by app users. The older scripts/setup-uhd.py protocol implementation and its tests remain for source/history compatibility; the app no longer offers manual helper URL entry. setup-uhd.command directs users to Settings → Enable BBC UHD.
