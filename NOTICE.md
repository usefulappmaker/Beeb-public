# Attribution and licence

Beeb is an independent, unofficial tvOS client. It is not produced or endorsed by the BBC.

The stream-discovery implementation is adapted from get_iplayer 3.36, copyright (C) 2008–2010 Phil Lewis and 2010– get_iplayer contributors:
https://github.com/get-iplayer/get_iplayer/tree/v3.36

In particular, the media-selector requests, same-host playlist query propagation, and Full HD candidate selection are based on that implementation. Beeb is distributed under GPL-3.0-or-later; the full licence is in LICENSE.txt. The original Perl runtime is not embedded. BBC programme images and video are retrieved from BBC services at runtime and are not bundled.

The client-certificate selector flow follows TwinVine and its iP service (service version 1.0.3, author stabbedbybrick) from the upstream service configuration. The native Swift DASH-to-HLS bridge and native one-time setup are implemented in this project. TwinVine source is distributed under GPL; Beeb remains GPL-3.0-or-later.

No client certificate, private key, DRM key, BBC account credential or signed stream URL is bundled. At the user's request, one-time setup downloads the upstream service configuration, validates its identity and BBC UHD access, and imports it into the app's device-only Keychain. No upstream executable code is downloaded or run. The import package and metadata are retained in device-only Keychain storage; compatibility preference keys also retain the fingerprint and configured User-Agent. Stream URLs and media fragments are used transiently in memory for playback. BBC service changes can affect this unofficial client.

Continue Watching records are stored locally in app preferences. They contain programme/episode metadata and playback positions, not media files or signed stream URLs.
