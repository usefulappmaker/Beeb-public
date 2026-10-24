# Troubleshooting

| Problem | What to check |
| --- | --- |
| “Signing requires a development team” | Choose your own account/team on the BeebHD target. Public source has none selected. |
| Bundle identifier unavailable | Replace the template ID with your own unique value. Apply it consistently to build configurations. |
| Apple TV not discovered | Same LAN, Remote App and Devices screen open, local-network permission, IPv6/device discovery enabled; avoid guest isolation. See INSTALL.md for the two Xcode pairing interfaces. |
| Apple TV unavailable as a destination | Install matching tvOS platform support, finish pairing/device preparation and use compatible Xcode. |
| App stops launching days later | Renew its provisioning by running from Xcode again. Personal Team signing is temporary. Keep the same bundle ID/team. |
| Command line says Xcode is missing | Install full Xcode. For a nonstandard location, set DEVELOPER_DIR to that Xcode app's Contents/Developer folder. |
| No programmes or playback unavailable | Check ordinary BBC availability/network access. Test another episode/channel. BBC service changes can affect this independent client. |
| UHD-labelled episode plays HD | Open Settings → Enable BBC UHD, check connected status and test another currently available UHD episode. Catalogue availability is distinct from received quality. |
| Enable BBC UHD cannot download configuration | Check internet access and retry later. Existing saved setup is kept; a new connection depends on the upstream service. |
| Enable BBC UHD fails validation or stream check | The upstream identity may be expired/not accepted, or a compatible BBC UHD stream may be unavailable. Retry later. Failed setup preserves the old identity. |
| Captions absent | Select English in native controls; check this version has captions. Live captions depend on the feed. |
| Automatic captions on rewind absent | Enable Show on Skip Back in Apple TV's Automatic Subtitles settings on a supported tvOS version; check a subtitle track is available. |
| No Skip intro/recap button | BBC must supply a matching marker for the actual playing version, and playback must be within its interval. |

When reporting a bug, include app version, tvOS/Xcode version, device model, public programme URL and a redacted error description. Remove setup URLs/tokens, certificate/private-key contents, provisioning profiles, device IDs, email addresses, local user paths and signed playback URLs. Never upload your TwinVine configuration or an entire device/Xcode log without inspecting it.
