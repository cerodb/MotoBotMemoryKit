#!/usr/bin/env bash
set -euo pipefail

if ! command -v flock >/dev/null 2>&1; then
  echo "error: required dependency 'flock' is unavailable; use a node-specific serialized wrapper or install flock" >&2
  exit 127
fi

LOCK_FILE="${MOTOBOT_SYNC_LOCK:-/tmp/motobotsharedmemory-sync.lock}"
LOG_FILE="${MOTOBOT_SYNC_LOG:-${HOME}/.motobot-bridge-sync.log}"
ROOT="${MOTOBOT_SHARED_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BRIDGE="${MOTOBOT_MEMORY_ROOT:-${HOME}/.motobot-memory}"
SLUG="${MOTOBOT_NODE_SLUG:?Set MOTOBOT_NODE_SLUG to your registered node slug}"
BRANCH="${MOTOBOT_SYNC_BRANCH:-main}"
DAILY_LIMIT="${DAILY_LIMIT:-3}"

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "$LOG_FILE" 2>/dev/null || true; }

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "skip: lock busy"
  exit 0
fi

[[ -d "$BRIDGE" ]] || exit 0
[[ -d "$ROOT/.git" ]] || exit 0
[[ -x "$ROOT/scripts/export-node-memory.sh" || -f "$ROOT/scripts/export-node-memory.sh" ]] || exit 0
[[ -f "$ROOT/scripts/pull-and-promote.sh" ]] || exit 0
[[ -f "$ROOT/scripts/rebuild-indexes.sh" ]] || exit 0

cd "$ROOT" || exit 0

if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  log "abort: shared repo dirty before hook sync"
  git status --short >> "$LOG_FILE" 2>/dev/null || true
  exit 0
fi

# Cheap local export first. This avoids network in the common no-change case.
MOTOBOT_MEMORY_ROOT="$BRIDGE" DAILY_LIMIT="$DAILY_LIMIT" \
  bash "$ROOT/scripts/export-node-memory.sh" "$SLUG" >/dev/null 2>>"$LOG_FILE" || {
    log "export failed"
    exit 0
  }

if [[ -z "$(git status --porcelain -- "imports/$SLUG")" ]]; then
  # No local bridge export changes. Still allow already-pulled remote imports to be promoted only
  # during the scheduled cron or explicit manual runs; Stop hooks should stay cheap when idle.
  exit 0
fi

log "new local bridge export detected — syncing $SLUG"

# Network path only when there is something to publish.
git pull --ff-only --quiet origin "$BRANCH" 2>>"$LOG_FILE" || {
  log "pull failed; leaving changes uncommitted for next cron/manual sync"
  exit 0
}

# Re-run export after pull in case imports changed during fast-forward.
MOTOBOT_MEMORY_ROOT="$BRIDGE" DAILY_LIMIT="$DAILY_LIMIT" \
  bash "$ROOT/scripts/export-node-memory.sh" "$SLUG" >/dev/null 2>>"$LOG_FILE" || {
    log "export after pull failed"
    exit 0
  }

if [[ -n "$(git status --porcelain -- "imports/$SLUG")" ]]; then
  git add "imports/$SLUG" 2>>"$LOG_FILE"
  git commit --quiet -m "feat: sync node memory export for $SLUG" 2>>"$LOG_FILE" || true
  git push --quiet origin "$BRANCH" 2>>"$LOG_FILE" && log "pushed export for $SLUG" || log "push export failed"
fi

# Promote other nodes' staged imports, not this node's own backlog. This mirrors the existing cron
# and avoids bulk-promoting uncurated local import-only lessons.
bash "$ROOT/scripts/pull-and-promote.sh" "$SLUG" >/dev/null 2>>"$LOG_FILE" || {
  log "pull-and-promote failed"
  exit 0
}

if [[ -n "$(git status --porcelain -- lessons daily projects)" ]]; then
  bash "$ROOT/scripts/rebuild-indexes.sh" >/dev/null 2>>"$LOG_FILE" || true
  git add lessons daily projects 2>>"$LOG_FILE"
  # The rebuild also writes this derived index when transcriptions exist.
  if [[ -f knowledge/transcriptions/index.md ]]; then
    git add knowledge/transcriptions/index.md 2>>"$LOG_FILE"
  fi
  git commit --quiet -m "feat: promote shared-memory imports for $SLUG" 2>>"$LOG_FILE" || true
  git push --quiet origin "$BRANCH" 2>>"$LOG_FILE" && log "pushed promoted imports" || log "push promotions failed"
fi

log "done"
