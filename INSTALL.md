# Install

This file explains the zero-to-first-smoke-test setup for `MotoBotMemoryKit`.

The intended outcome is not to work directly inside the kit forever.

The intended outcome is:

- use the kit as a starting point
- create your own private repo
- run your first smoke test there
- then treat that new repo as your live shared-memory system

## Goal

End with:

- a local Git repo
- a connected remote
- one initial commit
- one successful smoke export from a fake or real bridge

## Option A — Start from a new private remote

1. Create an empty private Git repo named `MotoBotMemoryKit`
2. Clone it locally:

```bash
git clone <your-private-repo-url>
cd MotoBotMemoryKit
```

3. Copy this template content into that working tree
4. Make the initial commit:

```bash
git add .
git commit -m "feat: initialize MotoBotMemoryKit template"
git push origin main
```

## Option B — Start locally first

If you do not have the remote yet:

```bash
mkdir MotoBotMemoryKit
cd MotoBotMemoryKit
git init
```

Then copy the template files into the repo and create the first commit:

```bash
git add .
git commit -m "feat: initialize MotoBotMemoryKit template"
```

Later, when the remote exists:

```bash
git remote add origin <your-private-repo-url>
git branch -M main
git push -u origin main
```

## First smoke test

Create a fake or real bridge root:

```bash
mkdir -p /path/to/.motobot-memory/lessons
mkdir -p /path/to/.motobot-memory/memories/daily
mkdir -p /path/to/.motobot-memory/projects
```

Run:

```bash
MOTOBOT_MEMORY_ROOT=/path/to/.motobot-memory \
DAILY_LIMIT=2 \
bash scripts/export-node-memory.sh temp-node-smoke
```

Inspect:

```bash
find imports/temp-node-smoke -maxdepth 3 -type f | sort
git status --short
```

Expected result:

- one or more staged lesson files
- one or more staged daily files
- one staged `active-db-snapshot.md`

## Before treating the repo as operational

Read:

1. `README.md`
2. `ONBOARDING.md`
3. `machines/registry.md`

Then decide whether the node should keep using a temporary slug or adopt a permanent one.
