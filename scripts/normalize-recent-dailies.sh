#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAILY_DIR="${REPO_ROOT}/daily"
RECENT_DAILY_COUNT="${RECENT_DAILY_COUNT:-10}"
DEFAULT_ORIGIN_NODE="${DEFAULT_ORIGIN_NODE:-sample-node-a}"

frontmatter_field() {
  local file_path="$1"
  local field_name="$2"

  awk -v field_name="$field_name" '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && index($0, field_name ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "", $0)
      print
      exit
    }
  ' "$file_path"
}

has_frontmatter() {
  [ "$(sed -n '1p' "$1")" = "---" ]
}

derive_name() {
  local file_path="$1"
  local existing_name
  existing_name="$(frontmatter_field "$file_path" "name")"
  if [ -n "$existing_name" ]; then
    printf '%s\n' "$existing_name"
    return 0
  fi
  printf 'daily-%s\n' "$(basename "$file_path" .md)"
}

derive_description() {
  local file_path="$1"
  local current
  local candidate

  current="$(frontmatter_field "$file_path" "description")"
  if [ -n "$current" ]; then
    printf '%s\n' "$current"
    return 0
  fi

  candidate="$(awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { in_frontmatter = 0; next }
    in_frontmatter { next }
    /^#/ {
      sub(/^#+[[:space:]]*/, "", $0)
      if (length($0) > 0) {
        print
        exit
      }
    }
    /^- / {
      sub(/^- /, "", $0)
      if (length($0) > 0) {
        print
        exit
      }
    }
  ' "$file_path")"

  if [ -n "$candidate" ]; then
    printf '%s\n' "$candidate"
  else
    printf 'Recent shared-memory daily entry\n'
  fi
}

derive_date() {
  local file_path="$1"
  local base
  local found
  base="$(basename "$file_path")"
  if [[ "$base" =~ (20[0-9]{2}-[0-9]{2}-[0-9]{2}) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  found="$(grep -E -m1 -o '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$file_path" || true)"
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
  else
    date '+%Y-%m-%d'
  fi
}

derive_origin_node() {
  printf '%s\n' "$DEFAULT_ORIGIN_NODE"
}

print_related_projects() {
  local file_path="$1"
  local count=0

  grep -E -o '\bP[0-9]{3}\b|\bPM[0-9]{2}\b|\bPG[0-9]{2}\b' "$file_path" | sort -u | while IFS= read -r project_id; do
    [ -n "$project_id" ] || continue
    printf '  - %s\n' "$project_id"
    count=1
  done
}

prepend_frontmatter() {
  local file_path="$1"
  local name="$2"
  local description="$3"
  local date_value="$4"
  local origin_node="$5"
  local tmp_file

  tmp_file="$(mktemp)"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    printf 'type: daily\n'
    printf 'date: %s\n' "$date_value"
    printf 'origin_node: %s\n' "$origin_node"
    printf 'related_projects:\n'
    print_related_projects "$file_path"
    printf 'tags:\n'
    printf '  - daily\n'
    printf '  - %s\n' "$origin_node"
    printf -- '---\n\n'
    cat "$file_path"
  } > "$tmp_file"
  mv "$tmp_file" "$file_path"
}

daily_files="$(find "${DAILY_DIR}" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' | sort | tail -n "${RECENT_DAILY_COUNT}")"

printf '%s\n' "$daily_files" | while IFS= read -r file_path; do
  [ -n "$file_path" ] || continue
  if ! has_frontmatter "$file_path"; then
    prepend_frontmatter \
      "$file_path" \
      "$(derive_name "$file_path")" \
      "$(derive_description "$file_path")" \
      "$(derive_date "$file_path")" \
      "$(derive_origin_node "$file_path")"
  fi
done
