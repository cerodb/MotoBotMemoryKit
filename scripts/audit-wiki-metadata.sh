#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STRICT="${STRICT:-0}"
SCOPE="${SCOPE:-all}"
RECENT_DAILY_COUNT="${RECENT_DAILY_COUNT:-10}"

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
  local file_path="$1"
  local first_line

  first_line="$(sed -n '1p' "$file_path")"
  [ "$first_line" = "---" ]
}

missing_frontmatter=0
missing_lesson_id=0
duplicate_lesson_ids=0

tmp_ids="$(mktemp)"

daily_recent_files() {
  find "${REPO_ROOT}/daily" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' | sort | tail -n "${RECENT_DAILY_COUNT}"
}

printf '# Wiki Metadata Audit\n\n'
printf '> Generated on %s\n\n' "$(date '+%Y-%m-%d %H:%M %Z')"

for section in lessons projects daily; do
  if [ "$SCOPE" = "lessons" ] && [ "$section" != "lessons" ]; then
    continue
  fi
  if [ "$SCOPE" = "daily-recent" ] && [ "$section" != "daily" ]; then
    continue
  fi
  printf '## %s missing frontmatter\n' "$section"
  if [ "$section" = "daily" ] && [ "$SCOPE" = "daily-recent" ]; then
    daily_recent_files | while IFS= read -r file_path; do
      if ! has_frontmatter "$file_path"; then
        printf -- '- %s\n' "$(basename "$file_path")"
      fi
    done
  else
    find "${REPO_ROOT}/${section}" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' | sort | while IFS= read -r file_path; do
      if ! has_frontmatter "$file_path"; then
        printf -- '- %s\n' "$(basename "$file_path")"
      fi
    done
  fi
  printf '\n'
done

printf '## Lessons missing lesson_id\n'
for file_path in "${REPO_ROOT}"/lessons/*.md; do
  [ "$(basename "$file_path")" = "index.md" ] && continue
  if has_frontmatter "$file_path"; then
    lesson_id="$(frontmatter_field "$file_path" "lesson_id")"
    if [ -z "$lesson_id" ]; then
      printf -- '- %s\n' "$(basename "$file_path")"
      missing_lesson_id=$((missing_lesson_id + 1))
    else
      printf '%s\t%s\n' "$lesson_id" "$(basename "$file_path")" >> "$tmp_ids"
    fi
  else
    printf -- '- %s (no frontmatter yet)\n' "$(basename "$file_path")"
    missing_lesson_id=$((missing_lesson_id + 1))
  fi
done
printf '\n'

printf '## Duplicate lesson_id values\n'
dups="$(cut -f1 "$tmp_ids" | sort | uniq -d || true)"
if [ -n "$dups" ]; then
  duplicate_lesson_ids=1
  printf '%s\n' "$dups"
else
  printf 'none\n'
fi
printf '\n'

for section in lessons projects daily; do
  if [ "$SCOPE" = "lessons" ] && [ "$section" != "lessons" ]; then
    continue
  fi
  if [ "$SCOPE" = "daily-recent" ] && [ "$section" != "daily" ]; then
    continue
  fi
  section_missing=0
  if [ "$section" = "daily" ] && [ "$SCOPE" = "daily-recent" ]; then
    while IFS= read -r file_path; do
      [ -n "$file_path" ] || continue
      if ! has_frontmatter "$file_path"; then
        section_missing=$((section_missing + 1))
      fi
    done < <(daily_recent_files)
  else
    while IFS= read -r file_path; do
      if ! has_frontmatter "$file_path"; then
        section_missing=$((section_missing + 1))
      fi
    done < <(find "${REPO_ROOT}/${section}" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' | sort)
  fi
  missing_frontmatter=$((missing_frontmatter + section_missing))
done

printf '## Summary\n'
printf -- '- missing_frontmatter: %s\n' "$missing_frontmatter"
printf -- '- missing_lesson_id: %s\n' "$missing_lesson_id"
printf -- '- duplicate_lesson_ids: %s\n' "$duplicate_lesson_ids"

rm -f "$tmp_ids"

if [ "$STRICT" = "1" ]; then
  if [ "$missing_frontmatter" -gt 0 ] || [ "$missing_lesson_id" -gt 0 ] || [ "$duplicate_lesson_ids" -gt 0 ]; then
    exit 1
  fi
fi
