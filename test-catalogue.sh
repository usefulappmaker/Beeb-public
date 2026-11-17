#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_dir="${BEEB_TEST_DIR:-$PWD/build/tests}"
mkdir -p "$test_dir"
common=(-module-cache-path "$test_dir/ModuleCache" Shared/LiveChannels.swift BeebHD/BBCService.swift BeebHD/Catalogue.swift BeebHD/Discovery.swift)
xcrun swiftc "${common[@]}" Tests/CatalogueTests.swift -o "$test_dir/catalogue-tests"
"$test_dir/catalogue-tests" "$@"
xcrun swiftc "${common[@]}" BeebHD/CatalogueStore.swift Tests/CatalogueLifecycleTests.swift -o "$test_dir/catalogue-lifecycle-tests"
"$test_dir/catalogue-lifecycle-tests"
xcrun swiftc "${common[@]}" BeebHD/Library.swift Tests/LibraryTests.swift -o "$test_dir/library-tests"
"$test_dir/library-tests"

xcrun swiftc "${common[@]}" BeebHD/CatalogueIndex.swift BeebHD/CatalogueIndexStore.swift Tests/CatalogueIndexTests.swift -o "$test_dir/catalogue-index-tests"
"$test_dir/catalogue-index-tests" BeebHD/CatalogueSeed.plist "$@"
