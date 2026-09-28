#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_MACHINE_SLUG="${1:-}"
COMMIT_PROMOTIONS="${COMMIT_PROMOTIONS:-0}"
PUSH_PROMOTIONS="${PUSH_PROMOTIONS:-0}"
REGISTRY_FILE="$ROOT/machines/registry.md"

if [[ -z "$LOCAL_MACHINE_SLUG" ]]; then
  echo "usage: pull-and-promote.sh <local-machine-slug>" >&2
  exit 2
fi

if [[ ! -e "$ROOT/.git" ]]; then
  echo "missing repo root at $ROOT" >&2
  exit 1
fi

if [[ ! -f "$REGISTRY_FILE" ]]; then
  echo "missing machine registry at $REGISTRY_FILE" >&2
  exit 1
fi

cd "$ROOT"

current_branch="$(git rev-parse --abbrev-ref HEAD)"
git fetch origin "$current_branch"
git merge --ff-only FETCH_HEAD

machine_slugs=()
while IFS= read -r line; do
  machine_slugs+=("$line")
done < <(
  grep -E '^### ' "$REGISTRY_FILE" \
    | sed 's/^### //' \
    | sed '/^'"$LOCAL_MACHINE_SLUG"'$/d'
)

promoted=0
failed=0

has_md_files() {
  local dir="$1"
  find \
    "$dir/lessons" \
    "$dir/daily" \
    "$dir/projects" \
    -type f -name '*.md' -print -quit 2>/dev/null | grep -q .
}

# The alternate expansion skips empty arrays under nounset on Bash 3.2.
for slug in ${machine_slugs[@]+"${machine_slugs[@]}"}; do
  import_dir="$ROOT/imports/$slug"

  if [[ ! -d "$import_dir" ]]; then
    continue
  fi

  if ! has_md_files "$import_dir"; then
    continue
  fi

  before="$(git status --porcelain)"
  if bash "$SCRIPT_DIR/promote-import.sh" "$slug"; then
    :
  else
    rc=$?
    failed=$((failed + 1))
    echo "Promotion failed for $slug (exit $rc); continuing with remaining nodes" >&2
  fi
  after="$(git status --porcelain)"

  if [[ "$before" != "$after" ]]; then
    promoted=$((promoted + 1))
    echo "Promoted imports from $slug"
  else
    echo "No canonical changes from $slug"
  fi
done

echo "Promotion passes with canonical changes: $promoted"
echo "Failed promotion passes: $failed"

if [[ "$failed" -gt 0 ]]; then
  echo "Partial promotion: changes remain local; automatic commit/push skipped" >&2
  exit 1
fi

if [[ "$COMMIT_PROMOTIONS" == "1" ]] && [[ -n "$(git status --porcelain --untracked-files=all -- lessons daily projects)" ]]; then
  git add lessons daily projects
  git commit -m "feat: promote shared-memory imports for $LOCAL_MACHINE_SLUG"

  if [[ "$PUSH_PROMOTIONS" == "1" ]]; then
    git push origin main
  fi
fi
