#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="${MOTOBOT_MEMORY_ROOT:-$HOME/.motobot-memory}"
BOOTSTRAP_MACHINE_SLUG="${BOOTSTRAP_MACHINE_SLUG:-sample-node-a}"

if [[ ! -d "$ROOT/.git" ]]; then
  echo "missing repo root at $ROOT" >&2
  exit 1
fi

if [[ ! -d "$SRC" ]]; then
  echo "missing bridge source at $SRC" >&2
  exit 1
fi

mkdir -p "$ROOT/lessons" "$ROOT/daily" "$ROOT/projects"

cp "$SRC/projects/active-db-snapshot.md" "$ROOT/projects/active-db-snapshot-${BOOTSTRAP_MACHINE_SLUG}.md"

for file in "$SRC"/lessons/*.md; do
  [ -f "$file" ] || continue
  cp "$file" "$ROOT/lessons/$(basename "$file")"
done

for file in "$SRC"/memories/daily/2026-*.md; do
  [ -f "$file" ] || continue
  cp "$file" "$ROOT/daily/$(basename "$file")"
done

echo "Bootstrapped template memory repo from $SRC"
