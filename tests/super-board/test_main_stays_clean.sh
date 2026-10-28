#!/usr/bin/env bash
# Test hồi quy (#461 AC5): file runtime của board (log run hằng ngày, dup-noted) bị git ignore, nên một lượt board không để untracked ở main.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
for f in docs/super-board/runs/2099-01-01-agent-workbench.md .claude/super-board/dup-noted; do
  if git -C "$ROOT" check-ignore -q -- "$f"; then echo "✔ ignored: $f"; else echo "✖ not ignored: $f"; FAILS=$((FAILS + 1)); fi
done
exit "$FAILS"
