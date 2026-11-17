#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_dir="${BEEB_TEST_DIR:-$PWD/build/tests}"
mkdir -p "$test_dir"
xcrun swiftc -module-cache-path "$test_dir/ModuleCache" BeebHD/BBCService.swift BeebHD/Catalogue.swift BeebHD/WatchHistory.swift Tests/WatchHistoryTests.swift -o "$test_dir/history-tests"
"$test_dir/history-tests"
