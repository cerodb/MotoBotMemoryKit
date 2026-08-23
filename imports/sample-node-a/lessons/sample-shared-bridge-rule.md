---
lesson_id: L001
name: sample-shared-bridge-rule
description: Agents on one machine share a local staging bridge and one node namespace.
type: lesson
scope: shared
date: 2026-01-15
origin_node: sample-node-a
applies_to:
  - all-nodes
related_projects:
  - P100
related_lessons:
  - L002
tags:
  - lesson
  - memory
---

# Shared bridge rule

If multiple agents work on the same machine, they may all write durable memory to the same local bridge/staging root.

That bridge is not the final shared truth. Other nodes can consume the memory only after it has been exported, promoted into the repo's canonical directories, committed, and pushed.

The Git sync cycle must still be serialized per machine.
