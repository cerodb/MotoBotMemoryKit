---
lesson_id: L002
name: sample-promote-after-pull
description: Promotion should happen only after pulling the latest canon and inspecting staged imports.
type: lesson
scope: shared
date: 2026-01-15
origin_node: sample-node-a
applies_to:
  - all-nodes
related_projects:
  - P100
related_lessons:
  - L001
tags:
  - lesson
  - sync
  - promotion
---

# Promote after pull

Before promoting imported files into canonical directories, a node should pull the latest shared repo state.

This reduces avoidable collisions and makes the promotion step easier to reason about.
