#!/usr/bin/env bash
# Regression tests using temporary bridges and local Git remotes only.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Test GIT_COMMITTER_NAME=Test
export GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_EMAIL=test@example.invalid

fail() { echo "FAIL: $*" >&2; exit 1; }

# Exercise both export branches across New Year, including pruning and repeat runs.
repo="$WORK/export"
bridge="$WORK/bridge"
mkdir -p "$repo/scripts" "$repo/.git" "$repo/lessons" \
  "$bridge/lessons" "$bridge/projects" "$bridge/memories/daily"
cp "$ROOT/scripts/export-node-memory.sh" "$repo/scripts/"
for day in 2025-12-31 2026-12-31 2027-01-01; do
  printf '# %s\n\nA recorded event.\n' "$day" > "$bridge/memories/daily/$day.md"
done
printf 'Not a daily\n' > "$bridge/memories/daily/2027-notes.md"
run_export() {
  MOTOBOT_MEMORY_ROOT="$bridge" DAILY_LIMIT="$1" bash "$repo/scripts/export-node-memory.sh" testnode > "$WORK/export.log"
}
run_export all
for day in 2025-12-31 2026-12-31 2027-01-01; do
  cmp "$bridge/memories/daily/$day.md" "$repo/imports/testnode/daily/$day.md"
done
[[ ! -e "$repo/imports/testnode/daily/2027-notes.md" ]] || fail 'non-date file exported'
run_export all
grep -q 'Changed files: 0' "$WORK/export.log"
run_export 1
[[ -f "$repo/imports/testnode/daily/2027-01-01.md" ]] || fail 'latest daily missing'
[[ ! -e "$repo/imports/testnode/daily/2026-12-31.md" ]] || fail 'old daily not pruned'
[[ ! -e "$repo/imports/testnode/daily/2025-12-31.md" ]] || fail 'old daily not pruned'
run_export 0
[[ -f "$repo/imports/testnode/daily/2026-12-31.md" ]] || fail 'zero did not restore full window'
# An empty bridge must prune previously staged files without nounset failures.
rm "$bridge/memories/daily/"*.md
printf 'Old project\n' > "$repo/imports/testnode/projects/old.md"
run_export all
[[ -z "$(find "$repo/imports/testnode/daily" "$repo/imports/testnode/projects" -type f)" ]] || fail 'empty bridge failed to prune stale files'
echo 'PASS: export across years, full/limited/zero windows, pruning and idempotence'

# A real fetch/merge against a local bare remote, with the real promoter.
for scenario in collision success additions empty single-node; do
  repo="$WORK/$scenario"
  git init -q --initial-branch=main "$repo"
  mkdir -p "$repo/scripts" "$repo/machines" "$repo/lessons" "$repo/daily" "$repo/projects"
  cp "$ROOT/scripts/"{pull-and-promote,promote-import}.sh "$repo/scripts/"
  printf '### local\n### first\n### second\n' > "$repo/machines/registry.md"
  if [[ "$scenario" == single-node ]]; then
    printf '### local\n' > "$repo/machines/registry.md"
  fi
  for node in local first second; do
    mkdir -p "$repo/imports/$node/"{lessons,daily,projects}
  done
  printf 'Must be skipped\n' > "$repo/imports/local/lessons/local.md"
  if [[ "$scenario" != empty && "$scenario" != single-node ]]; then
    printf 'New lesson\n' > "$repo/imports/first/lessons/first.md"
    printf 'Later node\n' > "$repo/imports/second/lessons/second.md"
  fi
  if [[ "$scenario" == success ]]; then
    printf 'New lesson\n' > "$repo/lessons/first.md"
    printf 'New lesson\nAdditional fact\n' > "$repo/imports/first/lessons/first.md"
  fi
  if [[ "$scenario" == collision ]]; then
    printf 'Protected canonical content\n' > "$repo/lessons/shared.md"
    printf 'Conflicting replacement\n' > "$repo/imports/first/lessons/shared.md"
  fi
  git -C "$repo" add .
  git -C "$repo" commit -qm fixture
  git clone -q --bare "$repo" "$WORK/$scenario.git"
  git -C "$repo" remote add origin "$WORK/$scenario.git"
  before="$(git -C "$repo" rev-parse HEAD)"
  rc=0
  COMMIT_PROMOTIONS=1 PUSH_PROMOTIONS=1 bash "$repo/scripts/pull-and-promote.sh" local > "$WORK/$scenario.log" 2>&1 || rc=$?
  [[ ! -e "$repo/lessons/local.md" ]] || fail 'local node was promoted'
  if [[ "$scenario" == collision ]]; then
    [[ "$rc" == 1 ]] || fail 'collision must return 1'
    [[ -f "$repo/lessons/second.md" ]] || fail 'later node was skipped'
    [[ -f "$repo/lessons/first.md" ]] || fail 'valid file from failed node missing'
    grep -qx 'Protected canonical content' "$repo/lessons/shared.md"
    grep -q 'Promotion failed for first (exit 1)' "$WORK/$scenario.log"
    grep -q 'Failed promotion passes: 1' "$WORK/$scenario.log"
    [[ "$(git -C "$repo" rev-parse HEAD)" == "$before" ]] || fail 'partial result committed'
    [[ "$(git --git-dir="$WORK/$scenario.git" rev-parse main)" == "$before" ]] || fail 'partial result pushed'
  else
    [[ "$rc" == 0 ]] || fail "$scenario returned $rc"
    grep -q 'Failed promotion passes: 0' "$WORK/$scenario.log"
    if [[ "$scenario" == success || "$scenario" == additions ]]; then
      [[ -f "$repo/lessons/first.md" && -f "$repo/lessons/second.md" ]] || fail 'successful promotion missing'
      [[ "$(git -C "$repo" rev-parse HEAD)" != "$before" ]] || fail 'successful result not committed'
      [[ "$(git --git-dir="$WORK/$scenario.git" rev-parse main)" == "$(git -C "$repo" rev-parse HEAD)" ]] || fail 'successful result not pushed to fixture'
    else
      [[ "$(git -C "$repo" rev-parse HEAD)" == "$before" ]] || fail 'empty run committed'
    fi
  fi
  if [[ "$scenario" == success || "$scenario" == additions ]]; then
    committed="$(git -C "$repo" rev-parse HEAD)"
    COMMIT_PROMOTIONS=1 PUSH_PROMOTIONS=1 bash "$repo/scripts/pull-and-promote.sh" local > "$WORK/repeat.log" 2>&1
    [[ "$(git -C "$repo" rev-parse HEAD)" == "$committed" ]] || fail 'repeat run made an empty commit'
    [[ -z "$(git -C "$repo" status --porcelain)" ]] || fail 'successful run left changes uncommitted'
  fi
  echo "PASS: cross-node promotion ($scenario)"
done
