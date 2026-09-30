#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
# No executable is available on this PATH: dependency validation must happen first.
for script in motobotsharedmemory-stop-sync.sh; do
  rc=0
  PATH="$TMP/bin" MOTOBOT_NODE_SLUG=testnode MOTOBOT_SHARED_ROOT="$TMP/repo" \
    MOTOBOT_SYNC_LOCK="$TMP/lock" MOTOBOT_SYNC_LOG="$TMP/log" \
    "$BASH" "$ROOT/scripts/$script" > "$TMP/out" 2> "$TMP/err" || rc=$?
  [[ "$rc" == 127 ]]
  grep -q "required dependency 'flock' is unavailable" "$TMP/err"
  ! grep -q 'lock busy' "$TMP/err"
  [[ ! -e "$TMP/lock" && ! -e "$TMP/log" && ! -e "$TMP/repo" ]]
  echo "PASS: $script reports missing flock without side effects"
done

if command -v flock >/dev/null 2>&1; then
  exec 9>"$TMP/held.lock"
  flock -n 9
  for script in motobotsharedmemory-stop-sync.sh; do
    MOTOBOT_NODE_SLUG=testnode MOTOBOT_SYNC_LOCK="$TMP/held.lock" \
      MOTOBOT_SYNC_LOG="$TMP/$script.log" \
      "$BASH" "$ROOT/scripts/$script"
    grep -q 'lock busy' "$TMP/$script.log"
    echo "PASS: $script retains successful skip for a genuinely held lock"
  done
  flock -u 9
else
  echo 'SKIP: held-lock checks require flock; missing-dependency checks passed'
fi
