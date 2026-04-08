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
- but `pull -> export -> commit -> push` must be serialized per machine

## Scripts

- `scripts/export-node-memory.sh <machine-slug>`
- `scripts/promote-import.sh <machine-slug>`
- `scripts/pull-and-promote.sh <local-machine-slug>`
- `scripts/rebuild-indexes.sh`
- `scripts/normalize-lessons.sh`
- `scripts/normalize-recent-dailies.sh`
- `scripts/audit-wiki-metadata.sh`
- `scripts/bootstrap-from-bridge.sh`

## Template warning

This repo demonstrates the workflow. It is not a live shared-memory canon yet.
This repo is a stripped example derived from a live shared-memory system. It preserves the working model and scripts, but ships only sample data.

