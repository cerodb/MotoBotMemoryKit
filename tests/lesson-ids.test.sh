#!/usr/bin/env bash
# Real scripts, isolated bridges; no live memory or network.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unset MOTOBOT_LESSON_ID_PREFIX
fail() { echo "FAIL: $*" >&2; exit 1; }
id() { sed -n 's/^lesson_id: //p' "$1"; }
fixture() {
  mkdir -p "$WORK/$1/repo/"{.git,scripts,lessons,daily,projects} "$WORK/$1/bridge/"{lessons,projects,memories/daily}
  cp "$ROOT/scripts/"{export-node-memory,normalize-lessons,lesson-ids,promote-import,rebuild-indexes}.sh "$WORK/$1/repo/scripts/"
}
export_node() {
  MOTOBOT_MEMORY_ROOT="$WORK/$1/bridge" bash "$WORK/$1/repo/scripts/export-node-memory.sh" "$1" > "$WORK/export.log"
}
for node in node-a node-b; do
  fixture "$node"
  printf '# First\n' > "$WORK/$node/bridge/lessons/$node-first.md"
  printf '# Second\n' > "$WORK/$node/bridge/lessons/$node-second.md"
  printf '%s\n' '---' 'name: Retained title' 'lesson_id: ' 'tags: [fixture]' '---' 'Retained body' > "$WORK/$node/bridge/lessons/$node-third.md"
  export_node "$node"
  ids="$(sed -n 's/^lesson_id: //p' "$WORK/$node/bridge/lessons/"*.md | sort -u)"
  [[ "$(printf '%s\n' "$ids" | wc -l)" -eq 3 ]] || fail 'same-run ID collision'
  [[ "$(id "$WORK/$node/bridge/lessons/$node-first.md")" == "L-$node-001" ]] || fail 'namespace missing'
  grep -q '^tags: \[fixture\]$' "$WORK/$node/bridge/lessons/$node-third.md"
  grep -q '^Retained body$' "$WORK/$node/bridge/lessons/$node-third.md"
  [[ "$(grep -c '^lesson_id:' "$WORK/$node/bridge/lessons/$node-third.md")" -eq 1 ]] || fail 'duplicate metadata key'
  export_node "$node"
  grep -q 'Changed files: 0' "$WORK/export.log"
  # Bridge-only IDs must reserve the sequence even before promotion.
  printf '# Later\n' > "$WORK/$node/bridge/lessons/$node-later.md"
  export_node "$node"
  [[ "$(id "$WORK/$node/bridge/lessons/$node-later.md")" == "L-$node-004" ]] || fail 'restart reused an ID'
done
# Merge independent exports into one fixture canon and verify the real indexer accepts them.
cp -R "$WORK/node-b/repo/imports/node-b" "$WORK/node-a/repo/imports/"
for node in node-a node-b; do
  bash "$WORK/node-a/repo/scripts/promote-import.sh" "$node" > "$WORK/promote.log"
done
bash "$WORK/node-a/repo/scripts/rebuild-indexes.sh" > "$WORK/index.log"
[[ "$(sed -n 's/^lesson_id: //p' "$WORK/node-a/repo/lessons/"*.md | sort -u | wc -l)" -eq 8 ]] || fail 'cross-node IDs collided'
echo 'PASS: batch allocation, missing IDs, metadata preservation, restart, two offline nodes and merged indexes'

fixture prefixed
repo="$WORK/prefixed/repo"
bridge="$WORK/prefixed/bridge"
mkdir -p "$repo/imports/prefixed/lessons"
printf '%s\n' '---' 'lesson_id: L-X009' '---' 'Canonical' > "$repo/lessons/existing.md"
printf '%s\n' '---' 'lesson_id: L-X011' '---' 'Staged' > "$repo/imports/prefixed/lessons/staged.md"
printf '%s\n' '---' 'lesson_id: L007' '---' 'Legacy' > "$bridge/lessons/legacy.md"
cp "$bridge/lessons/legacy.md" "$WORK/legacy-before"
printf '# New\n' > "$bridge/lessons/new.md"
MOTOBOT_LESSON_ID_PREFIX=L-X export_node prefixed
[[ "$(id "$bridge/lessons/new.md")" == L-X012 ]] || fail 'canon/staging maximum ignored'
cmp "$WORK/legacy-before" "$bridge/lessons/legacy.md"
printf '# Invalid config\n' > "$bridge/lessons/invalid.md"
cp "$bridge/lessons/invalid.md" "$WORK/invalid-before"
if MOTOBOT_LESSON_ID_PREFIX=L-X1 export_node prefixed 2> "$WORK/error"; then fail 'numeric-ending prefix accepted'; fi
cmp "$WORK/invalid-before" "$bridge/lessons/invalid.md"
echo 'PASS: configured prefix, canon/staging reservations, legacy preservation and invalid prefix rejection'

fixture normalize
repo="$WORK/normalize/repo"
for name in first second; do printf '# New\n' > "$repo/lessons/$name.md"; done
printf '%s\n' '---' 'name: Existing metadata' '---' 'Body' > "$repo/lessons/third.md"
DEFAULT_ORIGIN_NODE=node-c bash "$repo/scripts/normalize-lessons.sh"
[[ "$(sed -n 's/^lesson_id: //p' "$repo/lessons/"*.md | sort -u | wc -l)" -eq 3 ]] || fail 'normalizer IDs collided'
[[ "$(id "$repo/lessons/first.md")" == L-node-c-001 ]] || fail 'normalizer used global IDs'
cp -R "$repo/lessons" "$WORK/normalized-before"
DEFAULT_ORIGIN_NODE=node-c bash "$repo/scripts/normalize-lessons.sh"
diff -qr "$WORK/normalized-before" "$repo/lessons"
echo 'PASS: normalizer shares allocation policy and is idempotent'
