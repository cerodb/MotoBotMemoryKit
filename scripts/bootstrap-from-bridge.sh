#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="${MOTOBOT_MEMORY_ROOT:-$HOME/.motobot-memory}"
BOOTSTRAP_MACHINE_SLUG="${BOOTSTRAP_MACHINE_SLUG:-sample-node-a}"
ALLOW_UNSANITIZED_BOOTSTRAP="${ALLOW_UNSANITIZED_BOOTSTRAP:-0}"

if [[ ! -d "$ROOT/.git" ]]; then
  echo "missing repo root at $ROOT" >&2
  exit 1
fi

if [[ ! -d "$SRC" ]]; then
  echo "missing bridge source at $SRC" >&2
  exit 1
fi

if [[ "$ALLOW_UNSANITIZED_BOOTSTRAP" != "1" ]]; then
  cat >&2 <<'EOF'
bootstrap-from-bridge.sh is disabled by default.

Reason:
- it copies raw local bridge content into the repo
- that can leak private memory or machine-local material if used carelessly

If you really want to bootstrap from a live local bridge, rerun with:
  ALLOW_UNSANITIZED_BOOTSTRAP=1 bash scripts/bootstrap-from-bridge.sh
EOF
  exit 2
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
