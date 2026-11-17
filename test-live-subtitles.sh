#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_dir="${BEEB_TEST_DIR:-$PWD/build/tests}"
mkdir -p "$test_dir"
xcrun swiftc -module-cache-path "$test_dir/ModuleCache" Shared/LiveChannels.swift BeebHD/BBCService.swift BeebHD/Catalogue.swift BeebHD/Discovery.swift BeebHD/PlaybackExtras.swift BeebHD/FMP4Normalizer.swift BeebHD/LocalHLSServer.swift BeebHD/LiveSubtitles.swift Tests/LiveSubtitleTests.swift -o "$test_dir/live-subtitle-tests"
"$test_dir/live-subtitle-tests" "$@"
