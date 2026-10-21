#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/tests
xcrun swiftc -O -module-cache-path build/tests/ModuleCache BeebHD/BBCService.swift BeebHD/Catalogue.swift BeebHD/CatalogueIndex.swift Tests/SearchPerformanceTests.swift -o build/tests/search-performance
build/tests/search-performance "$@"
