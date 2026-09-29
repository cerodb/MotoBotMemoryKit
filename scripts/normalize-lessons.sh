#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LESSONS_DIR="${REPO_ROOT}/lessons"
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

# shellcheck source=lesson-ids.sh
source "$SCRIPT_DIR/lesson-ids.sh"

derive_name() {
  local file_path="$1"
  local existing_name
  existing_name="$(frontmatter_field "$file_path" "name")"
  if [ -n "$existing_name" ]; then
    printf '%s\n' "$existing_name"
    return 0
  fi
  printf '%s\n' "$(basename "$file_path" .md)"
}

derive_description() {
  local file_path="$1"
  local heading
  heading="$(awk '/^#/{ sub(/^#+[[:space:]]*/, "", $0); print; exit }' "$file_path")"
  if [ -n "$heading" ]; then
    printf '%s\n' "$heading"
  else
    printf 'TODO add description\n'
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

prepend_frontmatter() {
  local file_path="$1"
  local lesson_id="$2"
  local name="$3"
  local description="$4"
  local date_value="$5"
  local origin_node="$6"
  local tmp_file

  tmp_file="$(mktemp)"
  {
    printf -- '---\n'
    printf 'lesson_id: %s\n' "$lesson_id"
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    printf 'type: lesson\n'
    printf 'scope: shared\n'
    printf 'date: %s\n' "$date_value"
    printf 'origin_node: %s\n' "$origin_node"
    printf 'applies_to:\n'
    printf '  - all-nodes\n'
    printf 'tags:\n'
    printf '  - lesson\n'
    printf -- '---\n\n'
    cat "$file_path"
  } > "$tmp_file"
  mv "$tmp_file" "$file_path"
}

for file_path in "${LESSONS_DIR}"/*.md; do
  [[ -f "$file_path" && "${file_path##*/}" != index.md ]] || continue
  current_id="$(frontmatter_field "$file_path" "lesson_id")"
  [[ -n "$current_id" ]] && continue
  new_id="$(next_lesson_id "$DEFAULT_ORIGIN_NODE" "$LESSONS_DIR")"
  if has_frontmatter "$file_path"; then
    insert_lesson_id "$file_path" "$new_id"
  else
    prepend_frontmatter \
      "$file_path" \
      "$new_id" \
      "$(derive_name "$file_path")" \
      "$(derive_description "$file_path")" \
      "$(derive_date "$file_path")" \
      "$(derive_origin_node "$file_path")"
  fi
done
