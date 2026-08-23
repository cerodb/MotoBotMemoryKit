#!/usr/bin/env bash
# promote-import.sh <machine-slug>
#
# Promotes staged files from imports/<machine-slug>/ into the canonical
# lessons/, daily/ and projects/ directories.
#
# Two write policies, decided by whether the canonical name is node-namespaced:
#
#   write-once (contended names) — lessons/*.md, projects/*.md
#     Any node can produce these names, so the canonical file may have been
#     written by a different node. A content difference is a real collision:
#     report it and leave the canonical file untouched.
#
#   update (node-owned names) — daily/YYYY-MM-DD-<slug>.md,
#                               projects/active-db-snapshot-<slug>.md
#     The slug in the name means the promoting node is the only authoritative
#     writer, so no other node can ever contend for it. These are living
#     documents (a daily grows as sessions close; a snapshot is re-taken), so a
#     content difference is an update. Dailies additionally assert the update is
#     non-destructive (nothing already published is removed or replaced);
#     a destructive rewrite is refused and reported, never silent.
#
# One bad file never blocks the rest: collisions are recorded and the run
# continues, so unrelated lessons/dailies/projects still land. The exit code is
# non-zero only if something genuinely could not be promoted.
#
# Tests: bash tests/promote-import.test.sh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: promote-import.sh <machine-slug>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT/imports/$1"
SOURCE_SLUG="$1"

if [[ ! -e "$ROOT/.git" ]]; then
  echo "missing repo root at $ROOT" >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "missing import dir: $SOURCE_DIR" >&2
  exit 1
fi

shopt -s nullglob

ADDED=0
UPDATED=0
COLLISIONS=0
REWRITES=0
DIVERGED=0

has_frontmatter() {
  [ "$(sed -n '1p' "$1")" = "---" ]
}

strip_frontmatter() {
  local file_path="$1"

  awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; had_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { in_frontmatter = 0; skip_one_leading_blank = 1; next }
    in_frontmatter { next }
    had_frontmatter && skip_one_leading_blank && $0 == "" { skip_one_leading_blank = 0; next }
    { skip_one_leading_blank = 0; print }
  ' "$file_path"
}

same_body() {
  local src="$1"
  local dst="$2"
  local src_body
  local dst_body

  src_body="$(mktemp)"
  dst_body="$(mktemp)"
  strip_frontmatter "$src" > "$src_body"
  strip_frontmatter "$dst" > "$dst_body"

  if cmp -s "$src_body" "$dst_body"; then
    rm -f "$src_body" "$dst_body"
    return 0
  fi

  rm -f "$src_body" "$dst_body"
  return 1
}

# Equivalent for promotion purposes: byte-identical, or same body after
# ignoring optional frontmatter on either side. This prevents full-history daily
# churn when exported bridge files gain canonical metadata but old canonical
# dailies intentionally remain body-identical.
equivalent() {
  local src="$1"
  local dst="$2"

  if cmp -s "$src" "$dst"; then
    return 0
  fi
  if same_body "$src" "$dst"; then
    return 0
  fi
  return 1
}

# Body lines that carry actual memory: no frontmatter, no blank lines, no
# headings. Blockquotes DO count — the decision-log daily template writes every
# entry as "> [DECISION ...]", so excluding them reads a full day as empty.
meaningful_line_count() {
  [ -f "$1" ] || { printf '0'; return; }
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    { n++ }
    END { print n + 0 }
  ' "$1"
}

# A file whose body is only headings: created by a template, never written to.
is_skeleton() {
  [ "$(meaningful_line_count "$1")" -eq 0 ]
}

# True when the update destroys nothing: every non-blank line of the current
# canonical body survives in the incoming body.
#
# This deliberately does NOT require the canonical body to be a byte prefix of
# the incoming one. A daily grows by inserting entries under existing section
# headings ("## Completado"), not only by appending at the end, so a prefix test
# rejects every real same-day update — which is how a canonical daily gets stuck
# as an empty skeleton while the real memory stays in the bridge.
# A replaced or deleted line still counts as destructive and is refused.
body_is_nondestructive() {
  local src="$1"
  local dst="$2"
  local src_body
  local dst_body
  local rc

  # An empty skeleton holds nothing to destroy, so replacing it is always safe —
  # even when the incoming file uses a different set of headings. Three cron jobs
  # write the same daily filename with three different templates, and the empty
  # one is what gets published first (created 00:00, published 01:30, filled with
  # the real summary only at midnight). Comparing line-by-line then reads the
  # heading swap as deletions and refuses the real memory forever.
  if is_skeleton "$dst" && ! is_skeleton "$src"; then
    return 0
  fi

  src_body="$(mktemp)"
  dst_body="$(mktemp)"
  strip_frontmatter "$src" | grep -v '^[[:space:]]*$' > "$src_body" || true
  strip_frontmatter "$dst" | grep -v '^[[:space:]]*$' > "$dst_body" || true

  # Multiset containment, not position. `diff` aligns by longest common
  # subsequence, so it answers "are the published lines still in the same
  # relative order?" when the question that matters is "is every published line
  # still there, as many times as before?". Merged dailies put the agent block
  # first, which reorders the published sections against each other; diff then
  # counts lines as deleted while they are present a few lines away, and the
  # real memory is refused forever. Content merely added above a
  # contiguous published block was already accepted, which is why this only ever
  # bit the reordered files.
  #
  # Order is irrelevant, but count is not: a line published twice and delivered
  # once has lost an occurrence, and that is destruction.
  #
  # Markdown headings are the one exception, and only headings — not `---`, not
  # anything else. A heading is structure, not memory: canonical dailies grew a
  # second copy of `# <date>` when a stub was concatenated onto the real entry,
  # and a merge that renders the day once collapses those two copies into one
  # without losing a word. Losing the *last* copy of a heading is still
  # destruction and is refused.
  local missing
  missing="$(awk '
    function is_heading(line,   n) {
      n = 0
      while (substr(line, n + 1, 1) == "#") n++
      return (n >= 1 && n <= 6 && substr(line, n + 1, 1) ~ /[[:space:]]/)
    }
    NR == FNR { incoming[$0]++; next }
    { published[$0]++ }
    END {
      n = 0
      for (l in published) {
        if (is_heading(l)) {
          if (incoming[l] + 0 == 0) n++
        } else if (published[l] > incoming[l] + 0) {
          n++
        }
      }
      print n + 0
    }
  ' "$src_body" "$dst_body")"
  if [ "${missing:-0}" -gt 0 ]; then
    rc=1
  else
    rc=0
  fi

  rm -f "$src_body" "$dst_body"
  return "$rc"
}

# Write-once policy for contended canonical names, with one exception: an
# update that destroys nothing is not a collision.
#
# Strict write-once meant that any edit to an already-published lesson or
# project note was refused forever — reported only on stderr, so the edit was
# silently dropped on every run while the author believed it was published.
# An import that still contains every published line only adds to the record,
# and cannot be clobbering another node's work: if a second node had edited the
# same file, its lines would be missing here and this stays a collision.
safe_copy() {
  local src="$1"
  local dst="$2"

  if [[ -f "$dst" ]]; then
    if equivalent "$src" "$dst"; then
      return 0
    fi
    if body_is_nondestructive "$src" "$dst"; then
      cp "$src" "$dst"
      UPDATED=$((UPDATED + 1))
      return 0
    fi
    echo "collision: $dst already exists with different content" >&2
    return 1
  fi

  cp "$src" "$dst"
  ADDED=$((ADDED + 1))
}

# Update policy for canonical names owned by the promoting node.
# $3=append_only: assert (and report) that the update destroys nothing.
update_copy() {
  local src="$1"
  local dst="$2"
  local append_only="${3:-0}"

  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    ADDED=$((ADDED + 1))
    return 0
  fi

  if equivalent "$src" "$dst"; then
    return 0
  fi

  if [[ "$append_only" == "1" ]] && ! body_is_nondestructive "$src" "$dst"; then
    echo "warning: $dst differs from import but is not an append; leaving canonical unchanged" >&2
    REWRITES=$((REWRITES + 1))
    return 0
  fi

  cp "$src" "$dst"
  UPDATED=$((UPDATED + 1))
}

is_dated_daily() {
  [[ "$(basename "$1")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$ ]]
}

canonical_daily_name() {
  local src="$1"
  local base

  base="$(basename "$src")"

  if [[ "$base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})\.md$ ]]; then
    printf '%s-%s.md\n' "${BASH_REMATCH[1]}" "$SOURCE_SLUG"
  else
    printf '%s\n' "$base"
  fi
}

canonical_project_name() {
  local src="$1"
  local base

  base="$(basename "$src")"

  if [[ "$base" == "active-db-snapshot.md" ]]; then
    printf 'active-db-snapshot-%s.md\n' "$SOURCE_SLUG"
  else
    printf '%s\n' "$base"
  fi
}

for file in "$SOURCE_DIR"/lessons/*.md; do
  safe_copy "$file" "$ROOT/lessons/$(basename "$file")" || COLLISIONS=$((COLLISIONS + 1))
done

for file in "$SOURCE_DIR"/daily/*.md; do
  dst="$ROOT/daily/$(canonical_daily_name "$file")"
  if is_dated_daily "$file"; then
    update_copy "$file" "$dst" 1 || COLLISIONS=$((COLLISIONS + 1))
  else
    safe_copy "$file" "$dst" || COLLISIONS=$((COLLISIONS + 1))
  fi
done

for file in "$SOURCE_DIR"/projects/*.md; do
  dst="$ROOT/projects/$(canonical_project_name "$file")"
  if [[ "$(basename "$file")" == "active-db-snapshot.md" ]]; then
    update_copy "$file" "$dst" || COLLISIONS=$((COLLISIONS + 1))
  else
    safe_copy "$file" "$dst" || COLLISIONS=$((COLLISIONS + 1))
  fi
done

# Divergence check: imports/ and canonical/ can drift apart silently (a promote
# that collided, or a canonical file edited by hand). Report it here instead of
# leaving it to be inferred from a git diff.
report_divergence() {
  local src="$1"
  local dst="$2"

  if [[ ! -f "$dst" ]]; then
    echo "diverged: $dst missing for import $src" >&2
    DIVERGED=$((DIVERGED + 1))
    return 0
  fi
  if ! equivalent "$src" "$dst"; then
    echo "diverged: $dst differs from import $src" >&2
    DIVERGED=$((DIVERGED + 1))
  fi
}

for file in "$SOURCE_DIR"/lessons/*.md; do
  report_divergence "$file" "$ROOT/lessons/$(basename "$file")"
done

for file in "$SOURCE_DIR"/daily/*.md; do
  report_divergence "$file" "$ROOT/daily/$(canonical_daily_name "$file")"
done

for file in "$SOURCE_DIR"/projects/*.md; do
  report_divergence "$file" "$ROOT/projects/$(canonical_project_name "$file")"
done

echo "Promoted staged files from $SOURCE_DIR (added=$ADDED updated=$UPDATED collisions=$COLLISIONS rewrites=$REWRITES diverged=$DIVERGED)"

if [[ "$COLLISIONS" -gt 0 ]]; then
  echo "promote incomplete: $COLLISIONS file(s) could not be promoted" >&2
  exit 1
fi
