# Install the unsigned IPA

The prebuilt **Beeb-0.10.9-public-unsigned.ipa** is for physical Apple TV devices running tvOS 17+. It contains no developer signature or provisioning profile. **You must sign it with your own Apple account before installation.** It is not a one-click Apple TV download or an App Store/TestFlight build.

Download the IPA from **[GitHub Releases](https://github.com/usefulappmaker/Beeb-public/releases/latest)** alongside the matching public source ZIP. Source ZIPs intentionally exclude binaries. Both routes install the same public app functionality; [INSTALL.md](INSTALL.md) remains the recommended fully source-based route.

## Requirements

- A Mac with full Xcode and compatible tvOS platform support.
- Your own signing certificate/private key available in your Mac's Keychain and a **tvOS** development or ad hoc provisioning profile covering your Apple TV and chosen app identifier.
- A paired Apple TV HD or Apple TV 4K running tvOS 17+.
- A signing tool that supports tvOS IPA input, such as [iOS App Signer](https://github.com/DanTheMan827/ios-app-signer). The name includes iOS, but its upstream instructions cover tvOS too.

## 1. Download and check the release

Download the unsigned IPA and its SHA-256 file from the same release as the public source. Verify the checksum in Terminal from that download folder:

```sh
shasum -a 256 -c Beeb-0.10.9-public-unsigned.sha256
```

For an additional structural check, with the source folder available:

```sh
python3 scripts/check-unsigned-ipa.py /path/to/Beeb-0.10.9-public-unsigned.ipa
```

Replace the example path. The checker verifies a public-template arm64 tvOS app without a code signature/profile and scans for common personal-path/key markers. It is not a complete secret scanner or a signing tool.

## Top Shelf extension signing

This release includes `PlugIns/BeebTopShelf.appex`. Your signing tool must sign both the app and this extension, preserving distinct identifiers: for example `com.youralias.Beeb` and `com.youralias.Beeb.TopShelf`. Each bundle needs provisioning that permits its own identifier and your Apple TV. One explicit app-only profile does not automatically cover the extension. If your third-party signer cannot handle nested tvOS extensions, use the Xcode source-install route, which manages both targets.

Keep the extension in the IPA to retain the one-click live channel cards. This release uses no App Group. After installation, move Beeb to the top row of the Apple TV home screen, select its icon and press Up to reach the channel cards.

## 2. Prepare signing for your device

If you already have a valid tvOS profile and its matching certificate/private key for your device, use them. Otherwise:

1. Add your own account under **Xcode → Settings → Accounts**.
2. Create a small temporary **tvOS App** project in Xcode. Select your team and automatic signing. Choose a unique identifier you will use for Beeb, for example `com.youralias.Beeb`, replacing `youralias`.
3. Pair your Apple TV using the network-pairing instructions in [INSTALL.md](INSTALL.md). Select that physical TV as the destination.
4. Let Xcode generate its signing profile; Run the temporary project if necessary to finish device provisioning. For Top Shelf, also create/provision a tvOS Top Shelf extension target with the matching `.TopShelf` identifier. Alternatively open the supplied Beeb project and let Xcode manage both targets, as described in INSTALL.md. This prepares the app and extension signing setup. Keep the selected team and identifier for the next step.

Use a tvOS profile, not an iPhone profile. Free Personal Team profiles are short-lived and require renewal. Never send your Apple password, signing private key or device profile to the project maintainer.

## 3. Sign a local copy

In iOS App Signer, choose the downloaded unsigned IPA as the input, your own signing certificate and matching tvOS provisioning profile. Set **New Application ID** to the exact identifier in that profile. Export a separately named signed IPA so the public unsigned download remains intact.

The signing tool must use entitlements allowed by your profile, including an app-specific Keychain access group under **your** team prefix and bundle ID. If installation reports invalid entitlements or UHD setup later reports Keychain errors, use the Xcode source-install route instead of guessing entitlement values.

Refer to the tool's [upstream instructions](https://dantheman827.github.io/ios-app-signer/). Its older cable-pairing screenshots do not describe modern Apple TV 4K network pairing; use Beeb's current Xcode pairing guide. The third-party signing workflow is documented from upstream and has not been exercised end to end for this release on a new user's account.

## 4. Install the signed app

Use Xcode's device manager to install the **signed** IPA on your paired Apple TV. Older Xcode exposes an **Installed Apps → +** control in **Window → Devices and Simulators**; current Xcode uses **Device Hub**. Choose the install-app action available for the selected device.

For a command-line alternative, extract your signed IPA into a temporary folder, then install its app bundle with Xcode's device tools:

```sh
unzip Beeb-signed.ipa -d Beeb-signed
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl list devices
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app --device "YOUR_DEVICE_IDENTIFIER" Beeb-signed/Payload/BeebHD.app
```

Replace the filenames, device identifier and Xcode location if necessary. Use the device identifier printed for your physical Apple TV. The app folder may have a different name if your signing tool changes it. The unsigned file itself will fail normal installation signature validation.

Wake the Apple TV and open **Beeb**. Confirm HD playback first. For optional UHD, follow [SETUP-UHD.md](SETUP-UHD.md) using **Settings → Enable BBC UHD** directly on Apple TV. No UHD identity is included in the IPA.

## Updates and privacy

Keep your own signing team and app identifier unchanged when signing updates. Re-sign and reinstall when provisioning expires. Your resulting signed IPA may contain your name, signing identifiers and registered-device information: keep that personal output private and distribute only the original audited unsigned release.
