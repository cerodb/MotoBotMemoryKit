#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRIDGE_ROOT="${MOTOBOT_MEMORY_ROOT:-$HOME/.motobot-memory}"
MACHINE_SLUG="${1:-sample-node-a}"
DAILY_LIMIT="${DAILY_LIMIT:-3}"
STAGE_DIR="$ROOT/imports/$MACHINE_SLUG"

if [[ ! -d "$ROOT/.git" ]]; then
  echo "missing git repo at $ROOT" >&2
  exit 1
fi

if [[ ! -d "$BRIDGE_ROOT" ]]; then
  echo "missing bridge source at $BRIDGE_ROOT" >&2
  exit 1
fi

mkdir -p "$STAGE_DIR/lessons" "$STAGE_DIR/daily" "$STAGE_DIR/projects"

changed=0

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

strip_frontmatter() {
  local file_path="$1"

  awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { in_frontmatter = 0; next }
    in_frontmatter { next }
    { print }
  ' "$file_path"
}

next_lesson_id() {
  local max_id=0
  local raw

  for file_path in "$ROOT"/lessons/*.md; do
    [ "$(basename "$file_path")" = "index.md" ] && continue
    raw="$(frontmatter_field "$file_path" "lesson_id")"
    if [[ "$raw" =~ ^L([0-9]+)$ ]]; then
      num="${BASH_REMATCH[1]}"
      num=$((10#$num))
      if [ "$num" -gt "$max_id" ]; then
        max_id="$num"
      fi
    fi
  done

  printf 'L%03d' $((max_id + 1))
}

derive_lesson_name() {
  local file_path="$1"
  printf '%s\n' "$(basename "$file_path" .md)"
}

derive_lesson_description() {
  local file_path="$1"
  local heading

  heading="$(awk '/^#/{ sub(/^#+[[:space:]]*/, "", $0); print; exit }' "$file_path")"
  if [ -n "$heading" ]; then
    printf '%s\n' "$heading"
  else
    printf 'TODO add description\n'
  fi
}

derive_lesson_date() {
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

prepend_lesson_frontmatter() {
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

derive_daily_name() {
  local file_path="$1"
  local base

  base="$(basename "$file_path" .md)"
  printf 'daily-%s-%s\n' "$base" "$MACHINE_SLUG"
}

derive_daily_description() {
  local file_path="$1"
  local heading

  heading="$(awk '/^#/{ sub(/^#+[[:space:]]*/, "", $0); print; exit }' "$file_path")"
  if [ -n "$heading" ]; then
    printf '%s\n' "$heading"
  else
    printf 'Daily note for %s on %s\n' "$MACHINE_SLUG" "$(basename "$file_path" .md)"
  fi
}

derive_daily_date() {
  local file_path="$1"
  local base

  base="$(basename "$file_path")"
  if [[ "$base" =~ (20[0-9]{2}-[0-9]{2}-[0-9]{2}) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    date '+%Y-%m-%d'
  fi
}

prepend_daily_frontmatter() {
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
    printf 'tags:\n'
    printf '  - daily\n'
    printf -- '---\n\n'
    cat "$file_path"
  } > "$tmp_file"
  mv "$tmp_file" "$file_path"
}

derive_project_name() {
  local file_path="$1"
  printf '%s\n' "$(basename "$file_path" .md)"
}

derive_project_description() {
  local file_path="$1"
  local heading

  heading="$(awk '/^#/{ sub(/^#+[[:space:]]*/, "", $0); print; exit }' "$file_path")"
  if [ -n "$heading" ]; then
    printf '%s\n' "$heading"
  else
    printf 'Project summary for %s\n' "$(basename "$file_path" .md)"
  fi
}

derive_project_date() {
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

prepend_project_frontmatter() {
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
    printf 'type: project\n'
    printf 'date: %s\n' "$date_value"
    printf 'origin_node: %s\n' "$origin_node"
    printf 'tags:\n'
    printf '  - project\n'
    printf -- '---\n\n'
    cat "$file_path"
  } > "$tmp_file"
  mv "$tmp_file" "$file_path"
}

prepare_bridge_lesson() {
  local bridge_file="$1"
  local canonical_file="$ROOT/lessons/$(basename "$bridge_file")"
  local bridge_body
  local canonical_body

  if [[ -f "$canonical_file" ]] && has_frontmatter "$canonical_file"; then
    bridge_body="$(strip_frontmatter "$bridge_file")"
    canonical_body="$(strip_frontmatter "$canonical_file")"
    if [[ "$bridge_body" == "$canonical_body" ]]; then
      cp "$canonical_file" "$bridge_file"
      return 0
    fi
  fi

  if has_frontmatter "$bridge_file"; then
    return 0
  fi

  prepend_lesson_frontmatter \
    "$bridge_file" \
    "$(next_lesson_id)" \
    "$(derive_lesson_name "$bridge_file")" \
    "$(derive_lesson_description "$bridge_file")" \
    "$(derive_lesson_date "$bridge_file")" \
    "$MACHINE_SLUG"
}

prepare_bridge_daily() {
  local bridge_file="$1"
  local daily_base
  local canonical_file
  local bridge_body
  local canonical_body

  daily_base="$(basename "$bridge_file" .md)"
  canonical_file="$ROOT/daily/${daily_base}-${MACHINE_SLUG}.md"

  if [[ -f "$canonical_file" ]] && has_frontmatter "$canonical_file"; then
    bridge_body="$(strip_frontmatter "$bridge_file")"
    canonical_body="$(strip_frontmatter "$canonical_file")"
    if [[ "$bridge_body" == "$canonical_body" ]]; then
      cp "$canonical_file" "$bridge_file"
      return 0
    fi
  fi

  if has_frontmatter "$bridge_file"; then
    return 0
  fi

  prepend_daily_frontmatter \
    "$bridge_file" \
    "$(derive_daily_name "$bridge_file")" \
    "$(derive_daily_description "$bridge_file")" \
    "$(derive_daily_date "$bridge_file")" \
    "$MACHINE_SLUG"
}

prepare_bridge_project() {
  local bridge_file="$1"
  local base
  local canonical_file
  local bridge_body
  local canonical_body

  base="$(basename "$bridge_file")"
  if [[ "$base" == "active-db-snapshot.md" ]]; then
    canonical_file="$ROOT/projects/active-db-snapshot-${MACHINE_SLUG}.md"
  else
    canonical_file="$ROOT/projects/$base"
  fi

  if [[ -f "$canonical_file" ]] && has_frontmatter "$canonical_file"; then
    bridge_body="$(strip_frontmatter "$bridge_file")"
    canonical_body="$(strip_frontmatter "$canonical_file")"
    if [[ "$bridge_body" == "$canonical_body" ]]; then
      cp "$canonical_file" "$bridge_file"
      return 0
    fi
  fi

  if has_frontmatter "$bridge_file"; then
    return 0
  fi

  prepend_project_frontmatter \
    "$bridge_file" \
    "$(derive_project_name "$bridge_file")" \
    "$(derive_project_description "$bridge_file")" \
    "$(derive_project_date "$bridge_file")" \
    "$MACHINE_SLUG"
}

sync_copy() {
  local src="$1"
  local dst="$2"

  if [[ ! -f "$src" ]]; then
    return 0
  fi

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi

  cp "$src" "$dst"
  changed=$((changed + 1))
}

remove_if_present() {
  local file_path="$1"

  if [[ -f "$file_path" ]]; then
    rm -f "$file_path"
    changed=$((changed + 1))
  fi
}

shopt -s nullglob

for file in "$BRIDGE_ROOT"/lessons/*.md; do
  prepare_bridge_lesson "$file"
  sync_copy "$file" "$STAGE_DIR/lessons/$(basename "$file")"
done

recent_dailies=()
while IFS= read -r line; do
  recent_dailies+=("$line")
done < <(
  find "$BRIDGE_ROOT/memories/daily" -maxdepth 1 -type f -name '2026-*.md' -exec basename {} \; \
    | sort \
    | tail -n "$DAILY_LIMIT"
)

for staged_daily in "$STAGE_DIR"/daily/*.md; do
  [ -e "$staged_daily" ] || continue
  keep_file=0
  staged_name="$(basename "$staged_daily")"
  for recent_name in "${recent_dailies[@]}"; do
    if [[ "$staged_name" == "$recent_name" ]]; then
      keep_file=1
      break
    fi
  done
  if [[ "$keep_file" -eq 0 ]]; then
    remove_if_present "$staged_daily"
  fi
done

if [[ "${#recent_dailies[@]}" -gt 0 ]]; then
  for name in "${recent_dailies[@]}"; do
    prepare_bridge_daily "$BRIDGE_ROOT/memories/daily/$name"
    sync_copy "$BRIDGE_ROOT/memories/daily/$name" "$STAGE_DIR/daily/$name"
  done
fi

bridge_projects=()
while IFS= read -r line; do
  bridge_projects+=("$line")
done < <(
  find "$BRIDGE_ROOT/projects" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' -exec basename {} \; | sort
)

for staged_project in "$STAGE_DIR"/projects/*.md; do
  [ -e "$staged_project" ] || continue
  keep_file=0
  staged_name="$(basename "$staged_project")"
  for project_name in "${bridge_projects[@]}"; do
    if [[ "$staged_name" == "$project_name" ]]; then
      keep_file=1
      break
    fi
  done
  if [[ "$keep_file" -eq 0 ]]; then
    remove_if_present "$staged_project"
  fi
done

if [[ "${#bridge_projects[@]}" -gt 0 ]]; then
  for name in "${bridge_projects[@]}"; do
    prepare_bridge_project "$BRIDGE_ROOT/projects/$name"
    sync_copy "$BRIDGE_ROOT/projects/$name" "$STAGE_DIR/projects/$name"
  done
fi

echo "Exported node memory for $MACHINE_SLUG into $STAGE_DIR"
echo "Changed files: $changed"
echo "Daily window: last $DAILY_LIMIT files"
