# Close-time memory publication

Run the versioned hook using Bash and your registered node slug:

```sh
MOTOBOT_NODE_SLUG=my-node bash /path/to/shared-memory/scripts/motobotsharedmemory-stop-sync.sh
```

The repository defaults to the script's parent directory and the bridge to
`$HOME/.motobot-memory`. Overrides: `MOTOBOT_SHARED_ROOT`, `MOTOBOT_MEMORY_ROOT`,
`MOTOBOT_SYNC_LOCK`, `MOTOBOT_SYNC_LOG`, `MOTOBOT_SYNC_BRANCH`.
Use the same lock as the scheduled sync. Requires Bash, flock and Git.

This preserves the existing close-time behavior: a three-daily export window
(override with `DAILY_LIMIT`), no network when the export is unchanged, and
failures logged without blocking session shutdown. Scheduled sync remains the
full-window backstop. This hook does not replace it.

The promotion commit includes the transcription index when present because
`rebuild-indexes.sh` can update it alongside the other indexes. Leaving it
uncommitted would block the next sync's clean-worktree check.

If `flock` is unavailable, the hook reports the missing dependency to stderr and
exits 127 before touching the lock or repository. This configuration error is not
a busy-lock skip. On macOS, use a node-specific wrapper with verified serialization
or provide `flock`; no automatic lock fallback is selected.
