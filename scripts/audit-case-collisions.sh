#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import collections
import subprocess
import sys


def lines(cmd):
    return subprocess.check_output(cmd, text=True).splitlines()

# Tracked paths in HEAD/index plus paths currently staged for add/rename/copy.
# This catches collisions before they are committed on case-sensitive systems.
tracked = set(lines(['git', 'ls-files']))
staged = set(
    path
    for path in lines(['git', 'diff', '--cached', '--name-only', '--diff-filter=ACMR'])
    if path
)
staged_deleted = set(
    path
    for path in lines(['git', 'diff', '--cached', '--name-only', '--diff-filter=D'])
    if path
)

paths = (tracked - staged_deleted) | staged
by_lower = collections.defaultdict(list)
for path in sorted(paths):
    by_lower[path.lower()].append(path)

collisions = {key: value for key, value in sorted(by_lower.items()) if len(value) > 1}
if collisions:
    print('Case-insensitive path collisions found in tracked/staged paths:', file=sys.stderr)
    for key, paths in collisions.items():
        print(f'- {key}: {paths}', file=sys.stderr)
    print('\nThese break case-insensitive filesystems such as default macOS/APFS.', file=sys.stderr)
    print('Run before commit/push on case-sensitive systems; Linux can create bugs macOS only feels later.', file=sys.stderr)
    sys.exit(1)

print('No case-insensitive path collisions found in tracked/staged paths.')
PY
