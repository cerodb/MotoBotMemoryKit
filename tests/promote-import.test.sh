#!/usr/bin/env bash
# Tests for scripts/promote-import.sh
#
# Self-contained: every case builds a throwaway fixture repo under $TMPDIR and
# runs the real script against it. No network, no writes outside the fixture.
#
# Usage: bash tests/promote-import.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMOTE="$REPO_ROOT/scripts/promote-import.sh"
SLUG="testnode"

PASS=0
FAIL=0
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fixture() {
  # fixture <name> -> echoes the fixture root
  local root="$WORKDIR/$1"
  mkdir -p "$root/.git" "$root/lessons" "$root/daily" "$root/projects" "$root/scripts" \
           "$root/imports/$SLUG/lessons" "$root/imports/$SLUG/daily" "$root/imports/$SLUG/projects"
  cp "$PROMOTE" "$root/scripts/promote-import.sh"
  echo "$root"
}

run_promote() {
  # run_promote <root> ; sets RC, OUT, ERR
  local root="$1"
  OUT="$(bash "$root/scripts/promote-import.sh" "$SLUG" 2>"$WORKDIR/stderr")"
  RC=$?
  ERR="$(cat "$WORKDIR/stderr")"
  return 0
}

ok() { PASS=$((PASS + 1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

check() {
  # check <description> <condition-string>
  if eval "$2"; then ok "$1"; else no "$1 — [$2]"; fi
}

same() {
  # same <description> <fileA> <fileB>
  if cmp -s "$2" "$3"; then ok "$1"; else no "$1 (files differ: $2 vs $3)"; fi
}

case_header() { printf '\n%s\n' "$1"; }

# ---------------------------------------------------------------------------
case_header "1. fresh promote — everything new lands, exit 0"
R="$(fixture fresh)"
printf 'lesson body\n' > "$R/imports/$SLUG/lessons/l1.md"
printf 'day one\n'     > "$R/imports/$SLUG/daily/2026-07-27.md"
printf 'proj\n'        > "$R/imports/$SLUG/projects/p1.md"
printf 'snap v1\n'     > "$R/imports/$SLUG/projects/active-db-snapshot.md"
run_promote "$R"
check "exit 0"                     '[[ "$RC" == 0 ]]'
check "reports added=4"            '[[ "$OUT" == *"added=4"* ]]'
check "no collisions"              '[[ "$OUT" == *"collisions=0"* ]]'
check "no divergence"              '[[ "$OUT" == *"diverged=0"* ]]'
check "lesson landed"              '[[ -f "$R/lessons/l1.md" ]]'
check "daily node-qualified"       '[[ -f "$R/daily/2026-07-27-testnode.md" ]]'
check "project landed"             '[[ -f "$R/projects/p1.md" ]]'
check "snapshot node-qualified"    '[[ -f "$R/projects/active-db-snapshot-testnode.md" ]]'
check "stderr quiet"               '[[ -z "$ERR" ]]'

# ---------------------------------------------------------------------------
case_header "2. re-promote unchanged — idempotent no-op"
run_promote "$R"
check "exit 0"                     '[[ "$RC" == 0 ]]'
check "added=0 updated=0"          '[[ "$OUT" == *"added=0 updated=0"* ]]'
check "stderr quiet"               '[[ -z "$ERR" ]]'

# ---------------------------------------------------------------------------
case_header "3. same-day daily append — the issue #3 regression"
R="$(fixture append)"
printf 'line1\nline2\n' > "$R/daily/2026-07-27-testnode.md"
printf 'line1\nline2\nline3 appended\n' > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "exit 0 (was exit 1)"        '[[ "$RC" == 0 ]]'
check "counted as update"          '[[ "$OUT" == *"updated=1"* ]]'
check "no collision"               '[[ "$OUT" == *"collisions=0"* ]]'
check "no rewrite warning"         '[[ "$OUT" == *"rewrites=0"* ]]'
check "stderr quiet"               '[[ -z "$ERR" ]]'
same  "canonical now matches import" "$R/daily/2026-07-27-testnode.md" "$R/imports/$SLUG/daily/2026-07-27.md"

# ---------------------------------------------------------------------------
case_header "4. same-day daily rewrite (not an append) — skipped and reported"
R="$(fixture rewrite)"
printf 'original line\nsecond\n' > "$R/daily/2026-07-27-testnode.md"
printf 'REPLACED line\nsecond\n' > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "exit 0"                     '[[ "$RC" == 0 ]]'
check "not counted as update"      '[[ "$OUT" == *"updated=0"* ]]'
check "rewrite counted"            '[[ "$OUT" == *"rewrites=1"* ]]'
check "divergence counted"         '[[ "$OUT" == *"diverged=1"* ]]'
check "warning on stderr"          '[[ "$ERR" == *"not an append; leaving canonical unchanged"* ]]'
check "canonical NOT overwritten"  'grep -q "original line" "$R/daily/2026-07-27-testnode.md"'

# ---------------------------------------------------------------------------
case_header "4b. same-day daily grows under an existing heading — promoted"
# The canonical daily is created as a skeleton of empty sections and entries are
# inserted under them, so the skeleton is not a byte prefix of the final daily.
# A prefix-only test refuses this forever and the canonical stays a skeleton
# while the real memory sits unpublished in the bridge.
R="$(fixture insert)"
printf '# 2026-07-27\n\n## Completado\n\n## Notas\n' > "$R/daily/2026-07-27-testnode.md"
printf '# 2026-07-27\n\n## Completado\n- shipped a real thing\n\n## Notas\n' \
  > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "exit 0"                      '[[ "$RC" == 0 ]]'
check "counted as update"           '[[ "$OUT" == *"updated=1"* ]]'
check "no rewrite warning"          '[[ "$OUT" == *"rewrites=0"* ]]'
check "stderr quiet"                '[[ -z "$ERR" ]]'
check "entry reached canonical"     'grep -q "shipped a real thing" "$R/daily/2026-07-27-testnode.md"'

# ---------------------------------------------------------------------------
case_header "4c. same-day daily drops a published entry — refused"
R="$(fixture shrink)"
printf '# 2026-07-27\n\n## Completado\n- entry one\n- entry two\n' > "$R/daily/2026-07-27-testnode.md"
printf '# 2026-07-27\n\n## Completado\n- entry two\n'              > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "not counted as update"       '[[ "$OUT" == *"updated=0"* ]]'
check "rewrite counted"             '[[ "$OUT" == *"rewrites=1"* ]]'
check "published entry survives"    'grep -q "entry one" "$R/daily/2026-07-27-testnode.md"'

# ---------------------------------------------------------------------------
case_header "4d. contended lesson extended, nothing lost — promoted"
# Strict write-once refused every edit to an already-published lesson or project
# note, reporting it only on stderr, so the edit was dropped silently forever.
R="$(fixture extend)"
printf 'original insight\n'                    > "$R/lessons/l1.md"
printf 'original insight\nfollow-up insight\n' > "$R/imports/$SLUG/lessons/l1.md"
printf 'proj base\n'                           > "$R/projects/p1.md"
printf 'proj base\nproj addendum\n'            > "$R/imports/$SLUG/projects/p1.md"
run_promote "$R"
check "exit 0"                      '[[ "$RC" == 0 ]]'
check "no collision"                '[[ "$OUT" == *"collisions=0"* ]]'
check "stderr quiet"                '[[ -z "$ERR" ]]'
check "lesson edit landed"          'grep -q "follow-up insight" "$R/lessons/l1.md"'
check "project edit landed"         'grep -q "proj addendum" "$R/projects/p1.md"'
check "original line kept"          'grep -q "original insight" "$R/lessons/l1.md"'

# ---------------------------------------------------------------------------
case_header "4e. contended lesson would lose a published line — still a collision"
R="$(fixture lose)"
printf 'line kept\nline that would be lost\n' > "$R/lessons/l1.md"
printf 'line kept\nsomething else\n'          > "$R/imports/$SLUG/lessons/l1.md"
run_promote "$R"
check "exit 1"                      '[[ "$RC" == 1 ]]'
check "collision reported"          '[[ "$ERR" == *"collision: "*"lessons/l1.md"* ]]'
check "published line survives"     'grep -q "line that would be lost" "$R/lessons/l1.md"'

# ---------------------------------------------------------------------------
case_header "4f. skeleton canonical, incoming uses other headings — promoted"
# Three cron jobs write the same daily filename with three different templates.
# The empty one is published first, so the real summary arrives with a different
# heading set and a line-by-line comparison reads the swap as deletions. The
# skeleton holds nothing to lose, so it must be replaced anyway.
R="$(fixture skeleton)"
printf '# 2026-07-27\n\n## Completado\n\n## En Progreso\n\n## Notas\n' \
  > "$R/daily/2026-07-27-testnode.md"
printf '# 2026-07-27 — lunes\n\n## Commits\n- [repo] real work\n\n## Insights\n- 0 new\n' \
  > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "exit 0"                      '[[ "$RC" == 0 ]]'
check "counted as update"           '[[ "$OUT" == *"updated=1"* ]]'
check "no rewrite warning"          '[[ "$OUT" == *"rewrites=0"* ]]'
check "real summary published"      'grep -q "real work" "$R/daily/2026-07-27-testnode.md"'
check "skeleton headings gone"      '! grep -q "En Progreso" "$R/daily/2026-07-27-testnode.md"'

# ---------------------------------------------------------------------------
case_header "4g. blockquote-only daily counts as content, not skeleton"
# The decision-log template writes every entry as "> [DECISION ...]". Treating
# blockquotes as decoration reads a full day of decisions as an empty file.
R="$(fixture quoted)"
printf '# 2026-07-27\n\n## Decisions\n> [DECISION] P404 — approved\n' \
  > "$R/daily/2026-07-27-testnode.md"
printf '# 2026-07-27 — lunes\n\n## Commits\n- unrelated\n' \
  > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "not counted as update"       '[[ "$OUT" == *"updated=0"* ]]'
check "rewrite counted"             '[[ "$OUT" == *"rewrites=1"* ]]'
check "decision survives"           'grep -q "P404 — approved" "$R/daily/2026-07-27-testnode.md"'

# ---------------------------------------------------------------------------
case_header "4h. incoming skeleton never downgrades a written daily"
R="$(fixture downgrade)"
printf '# 2026-07-27\n\n## Completado\n- a real entry\n' > "$R/daily/2026-07-27-testnode.md"
printf '# 2026-07-27\n\n## Completado\n\n## Notas\n'     > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "not counted as update"       '[[ "$OUT" == *"updated=0"* ]]'
check "rewrite counted"             '[[ "$OUT" == *"rewrites=1"* ]]'
check "entry survives"              'grep -q "a real entry" "$R/daily/2026-07-27-testnode.md"'

# ---------------------------------------------------------------------------
case_header "5. contended lesson collision — reported, run continues, exit 1"
R="$(fixture collide)"
printf 'canonical version, written by another node\n' > "$R/lessons/shared.md"
printf 'my different version\n'                       > "$R/imports/$SLUG/lessons/shared.md"
printf 'unrelated lesson\n'                           > "$R/imports/$SLUG/lessons/zz-other.md"
printf 'day\n'                                        > "$R/imports/$SLUG/daily/2026-07-27.md"
printf 'proj\n'                                       > "$R/imports/$SLUG/projects/p1.md"
run_promote "$R"
check "exit 1"                     '[[ "$RC" == 1 ]]'
check "collision reported"         '[[ "$ERR" == *"collision: "*"lessons/shared.md"* ]]'
check "collisions=1"               '[[ "$OUT" == *"collisions=1"* ]]'
check "incomplete note on stderr"  '[[ "$ERR" == *"promote incomplete"* ]]'
check "canonical NOT overwritten"  'grep -q "another node" "$R/lessons/shared.md"'
check "other lesson still landed"  '[[ -f "$R/lessons/zz-other.md" ]]'
check "daily still landed"         '[[ -f "$R/daily/2026-07-27-testnode.md" ]]'
check "project still landed"       '[[ -f "$R/projects/p1.md" ]]'
check "divergence flagged"         '[[ "$ERR" == *"diverged: "*"lessons/shared.md"* ]]'

# ---------------------------------------------------------------------------
case_header "6. frontmatter-only difference — still equivalent (07d02a8)"
R="$(fixture frontmatter)"
printf -- '---\nlesson_id: L001\ndate: 2026-01-01\n---\n\nsame body\n' > "$R/lessons/fm.md"
printf -- '---\nlesson_id: L001\n---\n\nsame body\n'                   > "$R/imports/$SLUG/lessons/fm.md"
run_promote "$R"
check "exit 0"                     '[[ "$RC" == 0 ]]'
check "no collision"               '[[ "$OUT" == *"collisions=0"* ]]'
check "no divergence"              '[[ "$OUT" == *"diverged=0"* ]]'
check "canonical untouched"        'grep -q "date: 2026-01-01" "$R/lessons/fm.md"'

# ---------------------------------------------------------------------------
case_header "7. non-dated daily filename — stays write-once (not node-owned)"
R="$(fixture nondated)"
printf 'canonical\n' > "$R/daily/notes.md"
printf 'mine\n'      > "$R/imports/$SLUG/daily/notes.md"
run_promote "$R"
check "exit 1"                     '[[ "$RC" == 1 ]]'
check "collision reported"         '[[ "$ERR" == *"collision: "*"daily/notes.md"* ]]'
check "canonical untouched"        'grep -q "canonical" "$R/daily/notes.md"'

# ---------------------------------------------------------------------------
case_header "8. active-db-snapshot — node-owned, updates freely"
R="$(fixture snapshot)"
printf 'snapshot as of monday\n'  > "$R/projects/active-db-snapshot-testnode.md"
printf 'snapshot as of friday\n'  > "$R/imports/$SLUG/projects/active-db-snapshot.md"
printf 'other node snapshot\n'    > "$R/projects/active-db-snapshot-othernode.md"
run_promote "$R"
check "exit 0"                     '[[ "$RC" == 0 ]]'
check "counted as update"          '[[ "$OUT" == *"updated=1"* ]]'
check "no rewrite warning"         '[[ "$OUT" == *"rewrites=0"* ]]'
check "own snapshot updated"       'grep -q "friday" "$R/projects/active-db-snapshot-testnode.md"'
check "other node untouched"       'grep -q "other node snapshot" "$R/projects/active-db-snapshot-othernode.md"'

# ---------------------------------------------------------------------------
case_header "9. pre-existing divergence with nothing to promote — reported"
R="$(fixture diverged)"
printf 'canonical stale\n'         > "$R/daily/2026-07-26-testnode.md"
printf 'canonical stale\nnew\n'    > "$R/imports/$SLUG/daily/2026-07-26.md"
printf 'other-node lesson\n'       > "$R/lessons/x.md"
printf 'mine\n'                    > "$R/imports/$SLUG/lessons/x.md"
run_promote "$R"
check "daily reconciled"           'cmp -s "$R/daily/2026-07-26-testnode.md" "$R/imports/$SLUG/daily/2026-07-26.md"'
check "lesson divergence flagged"  '[[ "$ERR" == *"diverged: "*"lessons/x.md"* ]]'
check "diverged=1"                 '[[ "$OUT" == *"diverged=1"* ]]'

# ---------------------------------------------------------------------------
case_header "10. empty import dirs — clean no-op"
R="$(fixture empty)"
run_promote "$R"
check "exit 0"                     '[[ "$RC" == 0 ]]'
check "all counters zero"          '[[ "$OUT" == *"added=0 updated=0 collisions=0 rewrites=0 diverged=0"* ]]'
check "stderr quiet"               '[[ -z "$ERR" ]]'

# ---------------------------------------------------------------------------
case_header "11. guards — bad usage and unknown node"
R="$(fixture guards)"
bash "$R/scripts/promote-import.sh" >/dev/null 2>&1
rc_noargs=$?
bash "$R/scripts/promote-import.sh" nosuchnode >/dev/null 2>&1
rc_unknown=$?
check "no args -> exit 2"          '[[ "$rc_noargs" == 2 ]]'
check "unknown node -> exit 1"     '[[ "$rc_unknown" == 1 ]]'

# ---------------------------------------------------------------------------
case_header "12. non-destructive is multiset containment, not line order"

# Merged bridge dailies carry both the agent block and the cron block, which
# reorders the published sections against each other. The old positional test
# counted those lines as deletions while they were present a few lines away, so
# real memory was refused indefinitely. Order must not matter; occurrence
# counts must.
R="$(fixture reordered)"
printf '# 2026-07-27\n\n## Completado\n- published one\n- published two\n\n## Notas\n- published note\n' \
  > "$R/daily/2026-07-27-testnode.md"
printf '# Memory Log — 2026-07-27\n\n## Antfarm Steps\n> [DECISION] agent content\n\n---\n\n# 2026-07-27\n\n## Notas\n- published note\n\n## Completado\n- published one\n- published two\n' \
  > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "reordered-but-complete is promoted" \
  '[[ "$OUT" == *"updated=1"* && "$OUT" == *"rewrites=0"* && "$OUT" == *"diverged=0"* ]]'
same  "canonical took the reordered import" \
  "$R/daily/2026-07-27-testnode.md" "$R/imports/$SLUG/daily/2026-07-27.md"

# A line published twice and delivered once has lost an occurrence.
R="$(fixture duplicate_loss)"
printf '# 2026-07-27\n\n- repeated entry\n- other entry\n- repeated entry\n' \
  > "$R/daily/2026-07-27-testnode.md"
before_hash="$(sha256sum "$R/daily/2026-07-27-testnode.md" | cut -d' ' -f1)"
printf '# 2026-07-27\n\n- repeated entry\n- other entry\n' \
  > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "losing one of two occurrences is refused" \
  '[[ "$OUT" == *"rewrites=1"* ]]'
check "canonical left untouched when an occurrence would be lost" \
  '[[ "$(sha256sum "$R/daily/2026-07-27-testnode.md" | cut -d" " -f1)" == "$before_hash" ]]'

# Headings are structure, not memory: two identical copies may collapse to one.
R="$(fixture heading_collapse)"
printf '# 2026-07-27\n\n## Completado\n- published one\n\n# 2026-07-27\n\n_stub appended by an old QA run_\n' \
  > "$R/daily/2026-07-27-testnode.md"
printf '# 2026-07-27\n\n## Completado\n- published one\n\n_stub appended by an old QA run_\n' \
  > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "duplicate heading collapsed to one is accepted" \
  '[[ "$OUT" == *"updated=1"* && "$OUT" == *"rewrites=0"* ]]'

# Losing the last copy of a heading is still destruction.
R="$(fixture heading_loss)"
printf '# 2026-07-27\n\n## Completado\n- published one\n\n## Notas\n- a note\n' \
  > "$R/daily/2026-07-27-testnode.md"
before_hash="$(sha256sum "$R/daily/2026-07-27-testnode.md" | cut -d' ' -f1)"
printf '# 2026-07-27\n\n## Completado\n- published one\n\n- a note\n' \
  > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "removing a heading entirely is refused" '[[ "$OUT" == *"rewrites=1"* ]]'
check "canonical left untouched when a heading would vanish" \
  '[[ "$(sha256sum "$R/daily/2026-07-27-testnode.md" | cut -d" " -f1)" == "$before_hash" ]]'

# The heading exception must not leak to other repeated structural lines.
R="$(fixture separator_loss)"
printf '# 2026-07-27\n\n- one\n\n---\n\n- two\n\n---\n\n- three\n' \
  > "$R/daily/2026-07-27-testnode.md"
before_hash="$(sha256sum "$R/daily/2026-07-27-testnode.md" | cut -d' ' -f1)"
printf '# 2026-07-27\n\n- one\n\n---\n\n- two\n\n- three\n' \
  > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "losing a repeated --- separator is still refused" '[[ "$OUT" == *"rewrites=1"* ]]'
check "canonical left untouched when a separator would be lost" \
  '[[ "$(sha256sum "$R/daily/2026-07-27-testnode.md" | cut -d" " -f1)" == "$before_hash" ]]'

# Dropping a distinct line entirely is still destruction.
R="$(fixture distinct_loss)"
printf '# 2026-07-27\n\n- keep me\n- delete me\n' > "$R/daily/2026-07-27-testnode.md"
before_hash="$(sha256sum "$R/daily/2026-07-27-testnode.md" | cut -d' ' -f1)"
printf '# 2026-07-27\n\n> [DECISION] added above\n\n- keep me\n' \
  > "$R/imports/$SLUG/daily/2026-07-27.md"
run_promote "$R"
check "dropping a published line is refused" '[[ "$OUT" == *"rewrites=1"* ]]'
check "canonical left untouched when a line would be dropped" \
  '[[ "$(sha256sum "$R/daily/2026-07-27-testnode.md" | cut -d" " -f1)" == "$before_hash" ]]'

# ---------------------------------------------------------------------------
printf '\n%s\n' "-----------------------------------------"
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]] || exit 1
