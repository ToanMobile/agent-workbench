#!/usr/bin/env bash
# Owner order 16/11: the default disk floor of `worktree add` is 5 GiB (was 15). The env knob still overrides it.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$ROOT/scripts/git/worktree.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
d="$(env -u WORKTREE_DISK_MIN_GIB python3 -c "import sys; sys.path.insert(0, '$ROOT/scripts/git'); import worktree; print(worktree.DISK_MIN_GIB)" 2>&1)"
[ "$d" = "5.0" ] && ok "default floor is 5 GiB" || fail "default floor=$d, want 5.0"
o="$(WORKTREE_DISK_MIN_GIB=7 python3 -c "import sys; sys.path.insert(0, '$ROOT/scripts/git'); import worktree; print(worktree.DISK_MIN_GIB)" 2>&1)"
[ "$o" = "7.0" ] && ok "WORKTREE_DISK_MIN_GIB still overrides" || fail "override=$o, want 7.0"
[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_disk_floor_default: all passed" || { echo "❌ $FAILS failed"; exit 1; }
