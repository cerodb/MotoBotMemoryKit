#!/usr/bin/env bash
# Shared by export and normalization. Callers provide frontmatter_field().
# Scan persisted IDs instead of caching in a command-substitution subshell.
next_lesson_id() {
  local node="$1"
  shift
  local prefix="${MOTOBOT_LESSON_ID_PREFIX:-L-${node}-}"
  local dir file_path raw suffix num max_id=0
  if [[ ! "$node" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
     [[ ! "$prefix" =~ ^L-[a-zA-Z][a-zA-Z0-9_-]*$ ]] ||
     [[ "$prefix" =~ [0-9]$ ]]; then
    echo "Invalid lesson node/prefix: use a unique L- prefix ending in a letter or separator" >&2
    return 1
  fi
  for dir in "$@"; do
    for file_path in "$dir"/*.md; do
      [[ -f "$file_path" && "${file_path##*/}" != index.md ]] || continue
      raw="$(frontmatter_field "$file_path" lesson_id)"
      [[ "$raw" == "$prefix"* ]] || continue
      suffix="${raw#"$prefix"}"
      [[ "$suffix" =~ ^[0-9]+$ ]] || continue
      num=$((10#$suffix))
      if [[ "$num" -gt "$max_id" ]]; then max_id="$num"; fi
    done
  done
  printf '%s%03d' "$prefix" "$((max_id + 1))"
}

# Fill missing/empty IDs while retaining all other metadata and body text.
insert_lesson_id() {
  local file_path="$1" lesson_id="$2" tmp_file
  tmp_file="$(mktemp)"
  awk -v lesson_id="$lesson_id" '
    NR == 1 && $0 == "---" { print; print "lesson_id: " lesson_id; in_header=1; next }
    in_header && $0 == "---" { in_header=0 }
    in_header && /^lesson_id:/ { next }
    { print }
  ' "$file_path" > "$tmp_file"
  mv "$tmp_file" "$file_path"
}
