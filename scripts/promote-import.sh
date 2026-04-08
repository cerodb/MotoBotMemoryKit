#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: promote-import.sh <machine-slug>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT/imports/$1"
SOURCE_SLUG="$1"

if [[ ! -d "$ROOT/.git" ]]; then
  echo "missing repo root at $ROOT" >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "missing import dir: $SOURCE_DIR" >&2
  exit 1
fi

shopt -s nullglob

has_frontmatter() {
  [ "$(sed -n '1p' "$1")" = "---" ]
}

strip_frontmatter() {
  local file_path="$1"

  awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { in_frontmatter = 0; next }
    in_frontmatter { next }
    { print }
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

safe_copy() {
  local src="$1"
  local dst="$2"

  if [[ -f "$dst" ]]; then
    if cmp -s "$src" "$dst"; then
      return 0
    fi
    if has_frontmatter "$src" && has_frontmatter "$dst" && same_body "$src" "$dst"; then
      return 0
    fi
    echo "collision: $dst already exists with different content" >&2
    exit 1
  fi

  cp "$src" "$dst"
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
  safe_copy "$file" "$ROOT/lessons/$(basename "$file")"
done

for file in "$SOURCE_DIR"/daily/*.md; do
  safe_copy "$file" "$ROOT/daily/$(canonical_daily_name "$file")"
done

for file in "$SOURCE_DIR"/projects/*.md; do
  safe_copy "$file" "$ROOT/projects/$(canonical_project_name "$file")"
done

echo "Promoted staged files from $SOURCE_DIR"
