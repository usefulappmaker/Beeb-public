# Enable BBC UHD

This is Beeb's optional one-time setup for compatible BBC catch-up UHD playback. It runs directly on Apple TV after the app has been installed.

## Requirements

- An installed and signed Beeb 0.10.9 or later.
- Apple TV 4K with a suitable HLG-capable display/HDMI connection.
- Internet access to the upstream configuration and BBC services.
- A currently available, compatible BBC UHD episode and an upstream identity BBC currently accepts.

No separate computer, downloader, Python environment, helper, browser pairing or copied setup URL is needed. Installing/signing the app is a separate process: [INSTALL-IPA.md](INSTALL-IPA.md) or [INSTALL.md](INSTALL.md).

## Connect

1. Open **Beeb → Settings → Enable BBC UHD**.
2. Select **Enable BBC UHD**.
3. Wait while Beeb downloads and validates the configuration, then checks BBC access using a compatible 4K HLG stream.
4. Look for **UHD identity connected**. Open a UHD-listed episode and press Play.
5. Show the player controls. The outlined **4K** badge reports received 2160p video. A catalogue badge describes listed availability and is not proof of the stream actually playing. Your display's HLG/HDR information can help check the output connection.

You can cancel setup. Cancellation or a failed check leaves any previous working setup in place. HD remains available if UHD cannot be used.

## What happens behind the button

Beeb fetches the configuration over HTTPS from the upstream iP service:

[Upstream configuration](https://git.gay/Vinefeeder/twinvine-services/raw/branch/main/iP/config.yaml)

The access flow follows TwinVine's iP service; the visible Beeb setting is called **Enable BBC UHD**. Upstream attribution is retained in [NOTICE.md](NOTICE.md).

Only the certificate and User-Agent configuration fields are read; no upstream scripts are run. Beeb validates the certificate, matching private key and validity period, creates an encrypted import package natively on Apple TV, and checks for a compatible BBC UHD stream before replacing the saved setup. The identity/import package are kept in the device-only Keychain, not bundled in the app or exported to another installer.

Streams travel directly from BBC to Apple TV. Beeb's on-device DASH-to-HLS bridge prepares supported streams for Apple's player without video transcoding. No computer or third-party playback backend is needed.

## Updates, removal and problems

- Updating with the same signing team and app identifier normally retains the existing setup. A different app identity/team can require reconnecting.
- **Forget UHD identity** removes Beeb's local setup; it does not revoke the upstream certificate.
- If the configuration is temporarily unavailable, an already-connected installation uses its saved identity. A new connection needs the upstream download. An identity can also expire or stop being accepted independently of that download.
- If setup reports a download or validation error, check connectivity and try again later. If BBC returns no compatible stream, check episode availability and try another UHD programme.
- The existing **Display 4K UHD category** setting only shows/hides the navigation category; it does not connect UHD or change playback quality.
- Red Button UHD is an event-dependent live feed, separate from catch-up UHD setup.

Never post certificates, private keys, import packages, signing profiles or unredacted device logs in an issue. Beeb is independent and is not produced or endorsed by BBC.
