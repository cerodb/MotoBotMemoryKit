# Install

This file explains the zero-to-first-smoke-test setup for `MotoBotMemoryKit`.

The intended outcome is not to work directly inside the kit forever.

The intended outcome is:

- use the kit as a starting point
- create your own private repo
- run your first smoke test there
- run a second smoke test on another machine if the system is meant to be multi-node
- then treat that new repo as your live shared-memory system

## Goal

End with:

- a local Git repo
- a connected remote
- one initial commit
- one successful smoke export from a fake or real bridge

## Option A — Start from a new private remote

1. Create an empty private Git repo of your own.
   It may be named `MotoBotMemoryKit`, but it does not have to be.
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

- the command should complete without crashing
- `imports/temp-node-smoke/` should exist
- if the bridge is empty, staged folders may remain empty and that is acceptable for a first smoke test
- if the bridge already has exportable content, staged lessons/dailies/projects should appear there

If the bridge is empty, add a minimal sample and rerun, for example:

```bash
cat > /path/to/.motobot-memory/lessons/first-lesson.md <<'EOF'
# First lesson

This is a smoke-test lesson.
EOF
```

## Before treating the repo as operational

Read:

1. `README.md`
2. `ONBOARDING.md`
3. `machines/registry.md`

Then decide whether the node should keep using a temporary slug or adopt a permanent one.

## Multi-node go-live rule

If the goal is a shared-memory system across more than one machine, do not declare the new repo "live" after only one smoke test.

Recommended sequence:

1. run the first smoke test on machine A
2. fix any onboarding/script/documentation issues
3. run the same smoke test on machine B
4. only after both smoke tests pass, create or bless the derived repo as the live shared-memory repo
5. then assign permanent `machine_slug` values and update `machines/registry.md`

This avoids turning a one-machine success into a premature multi-node commitment.

## Sample data included in the kit

The kit already ships with:

- a tiny linked canonical sample cluster in `lessons/`, `projects/`, and `daily/`
- a matching staged sample payload in `imports/sample-node-a/`

Those samples are for understanding the structure only.
Your first smoke test should still use your own fake or real bridge root.

## Recommended production safety-net

Once a derived repo is live on a real node, add a node-local wrapper script plus cron so export/pull/promote also happens as a safety net.

Suggested cadence for active nodes:

- `30 1,13 * * * <path-to-node-wrapper>`

Suggested wrapper shape:

1. fail if repo is dirty
2. `git pull --ff-only`
3. run `scripts/export-node-memory.sh <machine-slug>`
4. commit + push node export changes
5. run `scripts/pull-and-promote.sh <machine-slug>`
6. rebuild indexes if canonical dirs changed
7. commit + push promotions
8. guard with a lock file

This should be shipped as template guidance or helper script in a later refinement pass.
