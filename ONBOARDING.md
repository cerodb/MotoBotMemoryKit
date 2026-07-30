# Onboarding

This repo is a template for a MotoBot-style shared-memory system.

## Sample nodes

- `sample-node-a` — primary example node

## Normal transport

Normal operation is via Git.

Do not use zip exchange except for bootstrap, recovery, or manual fallback.

## New node onboarding with existing memory

If a machine already has its own memory layer, do not register it immediately.

Before the smoke test, determine what "local memory" means for that tool on that machine. Examples:

- Claude may keep project memory under a product-specific folder
- Codex may have a local memory root such as `~/.codex/memories/`
- another agent may not have a populated durable memory folder yet

If the tool-local memory root exists but is empty, that is still a valid first smoke-test input. The first test is allowed to prove that the export path works even before there is real content.

Run a local smoke test first:

```bash
git clone <your-private-repo-url>
cd MotoBotMemoryKit

mkdir -p /path/to/.motobot-memory/lessons
mkdir -p /path/to/.motobot-memory/memories/daily
mkdir -p /path/to/.motobot-memory/projects

MOTOBOT_MEMORY_ROOT=/path/to/.motobot-memory \
DAILY_LIMIT=2 \
bash scripts/export-node-memory.sh temp-node-smoke
```

Verify locally:

- `imports/temp-node-smoke/lessons/`
- `imports/temp-node-smoke/daily/`
- `imports/temp-node-smoke/projects/`

An empty result is acceptable on the first run if the bridge had no exportable content yet. In that case, add one minimal sample artifact and rerun.

Only after that should the node adopt a permanent slug and update `machines/registry.md`.

For a first repository bootstrap, read `INSTALL.md`.

## Go-live rule for multi-machine use

If the intended system will span multiple machines, one successful smoke test is not enough to treat the repo as operational.

Use this order:

1. pass a smoke test on machine A
2. fix any kit gaps discovered there
3. pass a smoke test on machine B
4. only then treat the derived repo as the live shared-memory repo
5. only then assign permanent slugs and finalize `machines/registry.md`

## Multiple agents on the same machine

If Claude, Codex, and/or another agent all operate on the same machine, they still count as one node.

Rule:

- they may all write durable memory into the same local bridge
- they must all export into the same namespace for that machine
- bridge-only memory is not visible to other nodes yet
- the `pull -> export -> commit -> push` cycle must run serially, never in parallel

## Promotion flow

To promote a staged node import:

```bash
bash scripts/promote-import.sh <machine-slug>
```

To fetch and promote imports from other nodes:

```bash
bash scripts/pull-and-promote.sh <local-machine-slug>
```

## Recommended production safety-net

Once a derived repo is live on a real node, add a node-local wrapper script plus cron so export/pull/promote also happens as a safety net.

Suggested cadence for active nodes:

- `30 1,13 * * * <path-to-node-wrapper>`

Suggested wrapper shape:

1. fail if repo is dirty
2. `git pull --ff-only`
3. run `scripts/audit-case-collisions.sh`
4. run `scripts/export-node-memory.sh <machine-slug>`
5. after any `git add`, run `scripts/audit-case-collisions.sh` again before commit
6. commit + push node export changes if `imports/<machine-slug>/` changed
7. run `scripts/pull-and-promote.sh <machine-slug>` or `scripts/promote-import.sh <machine-slug>` as appropriate
8. rebuild indexes if canonical dirs changed
9. after any broad staging of canonical dirs, run `scripts/audit-case-collisions.sh` again before commit
10. commit + push promotions
11. verify `HEAD` matches `origin/main`
12. guard with a lock file

This should be shipped as template guidance or helper script in a later refinement pass.
