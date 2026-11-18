#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
build_dir="${BEEB_BUILD_DIR:-$PWD/build}"
mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd)"
args=(-project BeebHD.xcodeproj -scheme BeebHD -configuration Release -destination 'generic/platform=tvOS' -derivedDataPath "$build_dir/DerivedData")
if [[ -n "${BEEB_BUNDLE_ID:-}" ]]; then
    args+=("BEEB_APP_BUNDLE_IDENTIFIER=$BEEB_BUNDLE_ID")
fi
if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    if [[ -z "${BEEB_BUNDLE_ID:-}" ]]; then
        echo 'For a signed archive, set BEEB_BUNDLE_ID to your own unique app identifier. See INSTALL.md.' >&2
        exit 1
    fi
    xcodebuild "${args[@]}" -archivePath "$build_dir/BeebHD.xcarchive" "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" -allowProvisioningUpdates archive
    echo "Signed archive: $build_dir/BeebHD.xcarchive"
    echo 'Use Xcode Organizer to export for your registered Apple TV.'
else
    xcodebuild "${args[@]}" CODE_SIGNING_ALLOWED=NO build
    stage="$(mktemp -d)"
    trap 'rm -rf "$stage"' EXIT
    mkdir -p "$stage/Payload"
    cp -R "$build_dir/DerivedData/Build/Products/Release-appletvos/BeebHD.app" "$stage/Payload/"
    rm -f "$build_dir/BeebHD-unsigned.ipa"
    (cd "$stage" && COPYFILE_DISABLE=1 /usr/bin/zip -Xqry "$build_dir/BeebHD-unsigned.ipa" Payload -x '*/._*' '*/.DS_Store' '__MACOSX/*')
    echo "Unsigned build (must be signed before installation): $build_dir/BeebHD-unsigned.ipa"
fi
