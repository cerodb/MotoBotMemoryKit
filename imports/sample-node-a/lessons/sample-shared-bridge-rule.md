---
lesson_id: L001
name: sample-shared-bridge-rule
description: All agents on one machine share one bridge and one node namespace.
type: lesson
scope: shared
date: 2026-01-15
origin_node: sample-node-a
applies_to:
  - all-nodes
tags:
  - lesson
  - memory
---

# Shared bridge rule

If multiple agents work on the same machine, they should all write durable memory to the same local bridge.

The Git sync cycle must still be serialized per machine.
