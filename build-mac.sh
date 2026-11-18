#!/bin/bash
# Builds the unsigned Beeb for Mac preview and packages it as a ZIP for a GitHub Release.
# For your own signed build (needed for BBC UHD setup), see INSTALL-MAC.md.
set -euo pipefail
cd "$(dirname "$0")"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
build_dir="${BEEB_BUILD_DIR:-$PWD/build}"
mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd)"
version="$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);.*/\1/p' BeebMac.xcodeproj/project.pbxproj | sort -u)"
[[ "$(wc -l <<<"$version")" -eq 1 ]] || { echo 'BeebMac targets must share one MARKETING_VERSION.' >&2; exit 1; }
xcodebuild -project BeebMac.xcodeproj -scheme BeebMac -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$build_dir/MacDerivedData" \
    CODE_SIGNING_ALLOWED=NO build
app="$build_dir/MacDerivedData/Build/Products/Release/Beeb.app"
zip="$build_dir/Beeb-$version-mac-unsigned.zip"
rm -f "$zip"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --keepParent "$app" "$zip"
echo "Unsigned Mac preview: $zip"
