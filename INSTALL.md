# Install Beeb on your Apple TV

This guide installs a build signed by **you** on **your** Apple TV. There is no shared signing account, certificate or ready-to-install public IPA. Start with HD; optional UHD setup comes later.

To use the prebuilt unsigned IPA instead of compiling Beeb, see [INSTALL-IPA.md](INSTALL-IPA.md). It still needs your own certificate/profile and a Mac for the documented signing workflow.

## 1. What you need

- A Mac that supports a version of Xcode compatible with your Apple TV's tvOS version.
- Full Xcode from the Mac App Store or [Apple Developer Downloads](https://developer.apple.com/download/all/). Command Line Tools alone are insufficient.
- Xcode's tvOS platform support. In Xcode Settings → Components/Platforms, install tvOS support if missing; names vary by Xcode release.
- An Apple account that you can add to Xcode. A Personal Team can be used for personal testing subject to Apple's limits. Paid membership is optional for this source-install route, not a promise of permanent signing.
- An Apple TV HD or Apple TV 4K running tvOS 17+. UHD requires Apple TV 4K and an HLG-compatible display path.
- Mac and Apple TV on the same local network, with device discovery permitted.

Apple documents [Personal Team restrictions](https://developer.apple.com/help/account/basics/about-your-developer-account): free provisioning requires periodic reprovisioning and has seven-day limits. Expect to reconnect to Xcode and Run again when the provisioning expires. Paid-account profiles also expire; retain access to your signing account and Mac.

## 2. Download the project

On its GitHub page choose **Code → Download ZIP**, then double-click the download to extract it. Open the extracted folder containing `BeebHD.xcodeproj`, `README.md` and this guide. If using Git instead, clone the actual repository URL shown on that page; no maintainer account URL is baked into these instructions.

Open `BeebHD.xcodeproj` in Xcode. Allow Xcode to finish any first-launch setup and accept any Apple agreements yourself. No Swift package downloads are needed.

## 3. Add your Apple account and configure signing

1. Open **Xcode → Settings → Accounts** and add your own Apple account. Never send credentials or verification codes to a project maintainer.
2. Select the blue project icon in the navigator, then the **BeebHD target** (not just the project).
3. Open **Signing & Capabilities**. Enable **Automatically manage signing**.
4. Choose your own **Team** for both the **BeebHD** and **BeebTopShelf** targets. The public source intentionally leaves this blank.
5. In the project’s **Build Settings**, change **BEEB_APP_BUNDLE_IDENTIFIER** from `org.beebplayer.Beeb` to a unique value such as `com.youralias.Beeb` for Debug and Release. This updates both the app identifier and its `.TopShelf` extension identifier. Do not give the extension the same identifier as the main app.
6. Leave the existing app-specific Keychain entitlement in place. It uses the signing prefix and bundle identifier of your build, not a maintainer's team.

If Xcode says an identifier is unavailable, choose another unique identifier. If your account cannot provision a capability, read the exact signing error and account limitations; no maintainer's profile can fix provisioning for your own device.

## 4. Pair the Apple TV

1. Keep the Mac and Apple TV on the same home network. Avoid guest networks/client isolation. Ethernet is fine if both devices can discover each other.
2. On Apple TV open **Settings → Remotes and Devices → Remote App and Devices** and leave that screen visible.
3. In newer Xcode, open **Xcode → Open Developer Tool → Device Hub**, add a device and select **Pair Nearby Device → Apple TV**. In older Xcode, use **Window → Devices and Simulators → Devices**, select the discovered Apple TV and choose Pair.
4. Select your Apple TV and enter the verification code shown on its screen into Xcode. Complete any trust/development prompts that Xcode presents. Follow the device-specific prompts rather than looking for an iPhone-only Developer Mode menu.
5. Wait for pairing and device preparation to finish. Select the physical Apple TV as the run destination. A Simulator or “Any tvOS Device” destination will not install on your TV.

See Apple's current [Device Hub pairing guide](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac) and [older Devices and Simulators instructions](https://help.apple.com/xcode/mac/current/en.lproj/devbc48d1bad.html). On current tvOS/Xcode, Apple specifies IPv6-enabled local networking for pairing. Allow Xcode local-network discovery if macOS asks.

## 5. Build and install

Choose the **BeebHD** scheme and your paired **physical Apple TV**, then press the Run triangle or **Command-R**. Xcode builds, signs, installs and launches the app. The home-screen name is **Beeb**. The first build may take a few minutes.

If signing fails, return to step 3. If the Apple TV OS is newer than your Xcode supports, install compatible Xcode/platform support. If it installs but will not launch, check the provisioning status and device preparation messages in Xcode.

## 6. Confirm HD works first

Browse to an available episode and press the pink logo Play button. With no UHD identity configured, the app selects the best available HD/SD stream. Try Live separately. BBC availability/network restrictions still apply; the app does not provide a universal access service.

Show the playback controls to see the received-quality badge. Use the native subtitle control to choose English when available. On a supported tvOS release, **Settings → Video and Audio → Automatic Subtitles → Show on Skip Back** enables temporary subtitles after skipping back. Style captions through Apple's accessibility/subtitle settings.

Then, if desired, follow [SETUP-UHD.md](SETUP-UHD.md). The optional Enable BBC UHD step runs directly on Apple TV; ordinary HD/live playback needs no UHD setup.

## 7. Update and renew signing

Keep your selected **bundle identifier and signing team** unchanged for future updates. Download new source, set those same values, choose the same Apple TV and Run again. Installing over the existing app normally preserves local history, bookmarks and Keychain setup. Deleting the app, changing its identifier or changing team can affect data/Keychain access; do not rely on automatic migration between different app identities.

When free provisioning expires, repeat Xcode Run with your account. This does not require somebody else's signed IPA. Keep your own configuration values privately; never commit generated profiles or certificates to a public repository.

## Without a Mac

This release does not include a supported Windows/Linux-only signing and installation workflow. An unsigned IPA cannot simply be opened on Apple TV. Use a Mac with Xcode for this guide. No App Store or TestFlight distribution has been established for this project.
