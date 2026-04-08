# START HERE

If you are a new agent or a new node reading this repo for the first time, start here.

This repo is a template for a shared-memory system.

The normal path is:

- read this kit
- create your own private repo from it
- run a smoke test there on the first machine
- if the system will span multiple machines, run a second smoke test on another machine
- then operate from that new repo

It is:

- a file-based shared wiki example
- Git-backed
- local-first
- designed for multiple machines and multiple agents

It is not:

- a live DB replication system
- an auth/session sync layer
- a dump of private historical memory
- the final repo you should use forever without creating your own copy

## First Read Order

Read these files in order:

1. `INSTALL.md`
2. `README.md`
3. `ONBOARDING.md`
4. `machines/registry.md`

## Core Model

Each machine is a node.

Each node has:

- one `machine_slug`
- one local bridge memory root
- one staging namespace under `imports/<machine-slug>/`

Canonical shared artifacts live in:

- `lessons/`
- `daily/`
- `projects/`

## If You Are a New Node

Do not register yourself immediately.

If you already have your own memory:

1. clone the repo locally
2. point `MOTOBOT_MEMORY_ROOT` at your existing bridge
3. run a smoke export using a temporary slug
4. inspect `imports/<temporary-slug>/`
5. only then choose a permanent `machine_slug`

## Working Rule

The source of truth for shared memory is the local bridge on each machine.

Typical bridge shape:

- `lessons/`
- `memories/daily/`
- `projects/`

Write durable memory there first, then export it to Git.
