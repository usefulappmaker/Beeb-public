#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_dir="${BEEB_TEST_DIR:-$PWD/build/tests}"
mkdir -p "$test_dir"
xcrun swiftc -module-cache-path "$test_dir/ModuleCache" Shared/LiveChannels.swift BeebHD/BBCService.swift BeebHD/DASHManifest.swift BeebHD/LocalHLSServer.swift BeebHD/FMP4Normalizer.swift BeebHD/LiveDASH.swift Tests/LiveDASHTests.swift -o "$test_dir/live-uhd-tests"
"$test_dir/live-uhd-tests"
