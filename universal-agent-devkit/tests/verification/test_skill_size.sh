#!/usr/bin/env bash
# Regression test: every SKILL.md stays under Claude Code's 20000-character cap
# (UTF-8 characters, not bytes). Above it the tail is cut after context compaction.
# Covers the kit's skills/*/SKILL.md and the project's .claude/skills/*/SKILL.md.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
LIMIT=20000

python3 -I - "$LIMIT" "$DEVKIT_DIR/skills" "$ROOT/.claude/skills" <<'PY'
import glob, os, sys

limit = int(sys.argv[1])
files = sorted(p for d in sys.argv[2:] for p in glob.glob(os.path.join(d, "*", "SKILL.md")))
if not files:
    print("FAIL: no SKILL.md found")
    sys.exit(1)
bad = []
for p in files:
    with open(p, encoding="utf-8") as f:
        n = len(f.read())
    if n >= limit:
        bad.append((n, p))
for n, p in bad:
    print(f"FAIL: {p} has {n} characters (limit < {limit})")
print(f"{len(files)} SKILL.md checked, {len(bad)} over the limit")
sys.exit(1 if bad else 0)
PY
