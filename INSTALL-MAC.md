# Install Beeb for Mac (preview)

Beeb 0.11.0 adds a first preview of Beeb for **macOS 14 or later**, built from the same sources as the Apple TV app. It has a sidebar with Home, Search, Browse, Live, 4K UHD, Saved and Settings, programme pages, Continue Watching, the channel guide and an AVKit player with subtitles, audio choices, playback speeds and Picture in Picture.

This is a preview. Report problems on [GitHub Issues](https://github.com/usefulappmaker/Beeb-public/issues).

## Option 1: the unsigned download

Download **Beeb-0.11.0-mac-unsigned.zip** from [GitHub Releases](https://github.com/usefulappmaker/Beeb-public/releases/latest), check it against its SHA-256 file, then unzip it and move **Beeb.app** to Applications:

```sh
shasum -a 256 -c Beeb-0.11.0-mac-unsigned.sha256
```

The app is not notarised, so macOS blocks it the first time. Open it once, then go to **System Settings → Privacy & Security** and choose **Open Anyway** for Beeb.

Browsing, the guide and HD playback work in this build. **Enable BBC UHD does not:** it stores its identity in the macOS data protection Keychain, which only a signed app can use, and the unsigned app reports Keychain error -34018. For 4K, use option 2.

## Option 2: build and sign it yourself (needed for UHD)

You need a Mac with the full Xcode app and an Apple account added under **Xcode → Settings → Accounts**. A free Personal Team works.

1. Download the source ZIP from the same release, or clone this repository.
2. Open `BeebMac.xcodeproj`, select the **BeebMac** target and open **Signing & Capabilities**.
3. Tick **Automatically manage signing**, choose your team and change the bundle identifier to your own unique value, for example `com.youralias.BeebMac`.
4. Press **Run** (⌘R).

Or from Terminal, using your own team ID and identifier:

```sh
xcodebuild -project BeebMac.xcodeproj -scheme BeebMac -configuration Release \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID BEEB_APP_BUNDLE_IDENTIFIER=com.youralias.BeebMac \
  -allowProvisioningUpdates build
```

Then open **Settings → Enable BBC UHD** in Beeb. UHD still needs compatible content and a display that supports HLG HDR.

## Known limits

- No notarised or App Store build.
- BBC UHD setup and 4K playback need a development-signed build, as above.
- Profiles, kids mode, household sync and Top Shelf are Apple TV features for now. The Mac app uses a single default profile.

Beeb is independent and unofficial, and is not produced or endorsed by the BBC.
