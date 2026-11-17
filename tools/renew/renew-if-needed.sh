#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Run every couple of hours by launchd (see README.md). Renews only Apple TVs whose Beeb signature expires within
# RENEW_DAYS; never wakes a sleeping screen; retries unreachable boxes next run. Log: tools/renew/renew.log
set -uo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
RENEW_DAYS=3
log() { echo "$(date '+%F %T') $*" >> renew.log; }

due=()
while read -r id name; do
  [[ -z "$id" || "$id" == \#* ]] && continue
  exp=$(cat "state/$id.exp" 2>/dev/null)
  left=0
  [[ -n "$exp" ]] && left=$(( $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$exp" +%s) - $(date +%s) ))
  (( left > RENEW_DAYS * 86400 )) && continue
  due+=("$id"); log "renewing ${name:-$id} ($(( left / 3600 )) h left)"
done < devices.txt
[ ${#due[@]} -eq 0 ] && exit 0

out=$(timeout 1500 ./renew.sh "${due[@]}" 2>&1); rc=$?
log "$(echo "$out" | tr '\n' ' ' | sed 's/  */ /g')"
if [ $rc -eq 0 ]; then
  osascript -e 'display notification "Beeb renewed on your Apple TVs" with title "Beeb"' 2>/dev/null || true
elif ! grep -q "installed on" <<<"$out"; then
  for id in "${due[@]}"; do      # only alert when an Apple TV is under a day from expiring
    exp=$(cat "state/$id.exp" 2>/dev/null); [[ -z "$exp" ]] && continue
    if (( $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$exp" +%s) - $(date +%s) < 86400 )); then
      osascript -e 'display notification "Beeb renew keeps failing - see renew.log" with title "Beeb"' 2>/dev/null || true
      break
    fi
  done
fi
