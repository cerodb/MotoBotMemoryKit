# MotoBotMemoryKit

Template repo for a file-based shared-memory workflow.

New agent or new node?

- start with `START-HERE.md`
- for first setup, also read `INSTALL.md`

## What This Is

`MotoBotMemoryKit` is a starter kit for building a private shared-memory repo for one user, team, or set of machines.

It gives you:

- the folder structure
- the operating model
- the export/promote scripts
- onboarding and smoke-test docs
- a small fake dataset so the workflow is understandable from day one
- a linked sample cluster in canon plus a staged sample import payload

## What This Is Not

This repo is not meant to become your live shared-memory canon by itself.

Instead:

- you use this kit as the starting point
- you create your own private repo from it
- your machines and agents operate inside that new repo

In other words:

- `MotoBotMemoryKit` = template
- your future repo = live memory system

## Purpose

Teach and bootstrap a shared-memory workflow that is:

- file-based
- Git-backed
- local-first
- safe for multiple nodes and multiple agents

## Included

- `MEMORY.md`
- sample `lessons/*.md`
- sample `daily/*.md`
- sample `projects/*.md`
- sample `imports/<machine-slug>/`
- reusable scripts
- onboarding and smoke-test docs

## Excluded

- real project databases
- auth/session state
- runtime queues
- credentials
- private historical memory

## Typical Usage

1. create a new private repo of your own
2. initialize it from this kit
3. run a smoke test with a temporary node slug
4. confirm the exports look sane
5. only then start treating it as your real shared-memory repo

If you are starting from zero, read `INSTALL.md`.

## Canonical naming

- canonical daily files:
  - `daily/YYYY-MM-DD-<machine-slug>.md`
- canonical active snapshots:
  - `projects/active-db-snapshot-<machine-slug>.md`
- staged node exports:
  - `imports/<machine-slug>/...`

Collisions should fail rather than overwrite canon silently.

## Multiple agents on one node

Claude, Codex, and any other agent on the same machine are still one node.

That means:

- they may all write into the same local bridge
- they export into the same `imports/<machine-slug>/`
- bridge-only memory is not visible to other nodes yet
- `pull -> export -> commit -> push` must be serialized per machine

## Scripts

- `scripts/export-node-memory.sh <machine-slug>` — stages bridge memory into `imports/<machine-slug>/`; exports date-named daily files (`YYYY-MM-DD.md`) across all years by default (`DAILY_LIMIT=all`), use `DAILY_LIMIT=N` only for smoke tests/diagnostics
- `scripts/promote-import.sh <machine-slug>`
- `scripts/pull-and-promote.sh <local-machine-slug>` — processes remaining nodes after a promotion failure, then exits non-zero; partial results stay local and automatic commit/push is skipped. On success, `COMMIT_PROMOTIONS=1` includes newly added canonical files as well as tracked changes.
- `scripts/rebuild-indexes.sh`
- `scripts/normalize-lessons.sh`
- `scripts/normalize-recent-dailies.sh`
- `scripts/audit-wiki-metadata.sh`
- `scripts/audit-case-collisions.sh` — fails before commit/push if tracked or staged paths would collide on default macOS/case-insensitive filesystems
- `scripts/motobotsharedmemory-stop-sync.sh` — optional close-time hook; see [setup and dependencies](scripts/STOP-SYNC.md). It does not replace scheduled synchronization.
- `scripts/bootstrap-from-bridge.sh`

`scripts/bootstrap-from-bridge.sh` is disabled by default.
Use it only with explicit opt-in in a private derived repo, because it can copy raw local bridge content into the Git tree.

## Tests

- `tests/promote-import.test.sh` — run it from the repo root (`bash tests/promote-import.test.sh`) to check the promotion rules before you trust a change to `scripts/promote-import.sh`.

- `tests/export-and-pull.test.sh` — run with Bash to check year-independent export and cross-node promotion using temporary bridges and local Git remotes only. Includes additions-only commits, repeat runs, empty-bridge pruning and a single-node registry.

To exercise an alternate Bash, put it first on `PATH` before running the suites so child scripts use the same interpreter. Testing Bash 3.2 on Linux does not verify macOS utilities or the optional sync hook.

## Template warning

This repo demonstrates the workflow. It is not a live shared-memory canon yet.
This repo is a stripped example derived from a live shared-memory system. It preserves the working model and scripts, but ships only sample data.

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

The close-time hook already ships in `scripts/`, but a complete scheduled wrapper and its installation remain node-local. The hook skips networking when there is no local export change, so it cannot be the only mechanism for receiving other nodes' updates.
