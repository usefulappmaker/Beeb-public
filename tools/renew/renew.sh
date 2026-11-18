#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build Beeb signed with YOUR Apple account and (re)install it on your Apple TVs.
# A free Apple account's signature lasts 7 days; run this (or let renew-if-needed.sh run it) before then.
#
# Setup (once): see tools/renew/README.md — renew.conf (bundle id + team) and devices.txt (your Apple TVs).
# Usage:  tools/renew/renew.sh               every Apple TV in devices.txt
#         tools/renew/renew.sh <device id>   just that one
# A sleeping Apple TV is updated without waking its screen; one that doesn't answer is skipped.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$HERE"
[ -f renew.conf ] || { echo "Create tools/renew/renew.conf first (copy renew.conf.example)."; exit 1; }
# shellcheck disable=SC1091
source ./renew.conf
: "${BEEB_BUNDLE_ID:?set BEEB_BUNDLE_ID in renew.conf}" "${APPLE_TEAM_ID:?set APPLE_TEAM_ID in renew.conf}"
[ -f devices.txt ] || { echo "Create tools/renew/devices.txt first (copy devices.txt.example)."; exit 1; }
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD="$HERE/build"
APP="$BUILD/Build/Products/Release-appletvos/BeebHD.app"
mkdir -p state

devices=("$@")
if [ ${#devices[@]} -eq 0 ]; then
  while read -r id name; do [[ -z "$id" || "$id" == \#* ]] && continue; devices+=("$id"); done < devices.txt
fi

# One generic build: the team's development profile covers every Apple TV registered to the account.
xcodebuild -project "$ROOT/BeebHD.xcodeproj" -scheme BeebHD -configuration Release \
  -destination 'generic/platform=tvOS' -derivedDataPath "$BUILD" \
  BEEB_APP_BUNDLE_IDENTIFIER="$BEEB_BUNDLE_ID" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  -allowProvisioningUpdates build | grep -E "error:|BUILD"
exp=$(security cms -D -i "$APP/embedded.mobileprovision" | plutil -extract ExpirationDate raw -)

fails=0
for id in "${devices[@]}"; do
  name=$(awk -v id="$id" '$1==id {$1=""; sub(/^ /,""); print}' devices.txt)
  if out=$(timeout 180 xcrun devicectl device install app --device "$id" "$APP" 2>&1) && grep -q "bundleID" <<<"$out"; then
    echo "$exp" > "state/$id.exp"
    echo "installed on ${name:-$id}, signed until $exp"
  else
    echo "skipped ${name:-$id}: not reachable"
    fails=$((fails + 1))
  fi
done
[ "$fails" -eq 0 ]
