#!/usr/bin/env bash
# Regression test: worktree_sandbox.py creation, .worktreeinclude CoW copy, and cleanup
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$DEVKIT_DIR/scripts/worktree_sandbox.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Test 1: Script help command runs cleanly
python3 "$SCRIPT" --help >/dev/null 2>&1
if [ $? -eq 0 ]; then
  ok "worktree_sandbox.py --help returns exit 0"
else
  fail "worktree_sandbox.py --help failed"
fi

# Test 2: Lifecycle in a mock repo
P="$TMP/mock-repo"
mkdir -p "$P" && cd "$P"
git init -q . && git config user.email t@t && git config user.name t
echo "hello world" > README.md
echo -e ".env\nlocal.properties" > .worktreeinclude
echo "SECRET_KEY=12345" > .env
echo "sdk.dir=/dummy/sdk" > local.properties
git add README.md .worktreeinclude
git commit -q -m "initial commit"

# Create sandbox test_sb
python3 "$SCRIPT" create test_sb --port-offset 20 >/dev/null 2>&1
if [ -d "$P/.sandboxes/test_sb" ]; then
  ok "Sandbox directory created successfully"
else
  fail "Sandbox directory not created"
fi

if [ -f "$P/.sandboxes/test_sb/.env" ] && [ -f "$P/.sandboxes/test_sb/local.properties" ]; then
  ok ".worktreeinclude files copied via CoW"
else
  fail ".worktreeinclude files missing in sandbox"
fi

if [ -f "$P/.sandboxes/test_sb/.sandbox-env.sh" ]; then
  ok ".sandbox-env.sh envelope generated"
else
  fail ".sandbox-env.sh missing"
fi

# List sandboxes
LIST_OUT=$(python3 "$SCRIPT" list)
if echo "$LIST_OUT" | grep -q "test_sb"; then
  ok "Sandbox listed in active sandboxes"
else
  fail "Sandbox not found in list output"
fi

# Cleanup sandbox
python3 "$SCRIPT" cleanup --name test_sb >/dev/null 2>&1
if [ ! -d "$P/.sandboxes/test_sb" ]; then
  ok "Sandbox cleaned up and removed cleanly"
else
  fail "Sandbox directory still exists after cleanup"
fi

# Test 3: merge-winner with automatic cleanup
python3 "$SCRIPT" create winner_sb >/dev/null 2>&1
cd "$P/.sandboxes/winner_sb"
echo "winner feature implemented" > winner.txt
git add winner.txt
git commit -q -m "feat: winner commit"
cd "$P"

# Merge winner into main
MERGE_OUT=$(python3 "$SCRIPT" merge-winner winner_sb)
if [ -f "$P/winner.txt" ]; then
  ok "Winner commit merged into main branch"
else
  fail "Winner feature not found in main branch"
fi

if [ ! -d "$P/.sandboxes/winner_sb" ]; then
  ok "Winner sandbox automatically deleted after merge"
else
  fail "Winner sandbox directory was not auto-cleared"
fi

if git branch --list | grep -q "sandbox/winner_sb"; then
  fail "Winner branch sandbox/winner_sb still exists"
else
  ok "Winner branch automatically deleted"
fi

# Test 4: merge-winner must NOT delete other sandboxes unless --clean-others is given
python3 "$SCRIPT" create keep_a >/dev/null 2>&1
python3 "$SCRIPT" create win_b >/dev/null 2>&1
( cd "$P/.sandboxes/win_b" && echo "b" > b.txt && git add b.txt && git commit -q -m "feat: b" )
python3 "$SCRIPT" merge-winner win_b >/dev/null 2>&1
if [ -d "$P/.sandboxes/keep_a" ]; then
  ok "merge-winner keeps the other sandboxes by default"
else
  fail "merge-winner deleted another sandbox by default"
fi
python3 "$SCRIPT" create win_c >/dev/null 2>&1
( cd "$P/.sandboxes/win_c" && echo "c" > c.txt && git add c.txt && git commit -q -m "feat: c" )
python3 "$SCRIPT" merge-winner win_c --clean-others >/dev/null 2>&1
if [ ! -d "$P/.sandboxes/keep_a" ]; then
  ok "--clean-others removes the losing sandboxes on request"
else
  fail "--clean-others did not remove the losing sandbox"
fi

# Test 5: a '.' line in .worktreeinclude must never select the repo root
printf '.\n./\n.env\n' > "$P/.worktreeinclude"
INC=$(python3 -c "import sys; sys.path.insert(0, '$DEVKIT_DIR/scripts'); import worktree_sandbox as w; from pathlib import Path; print(w.parse_worktree_include(Path('$P')))")
if [ "$INC" = "['.env']" ]; then
  ok ".worktreeinclude '.' / './' lines are ignored"
else
  fail ".worktreeinclude accepted a repo-root path: $INC"
fi

if [ $FAILS -gt 0 ]; then
  echo "FAILED: $FAILS errors"
  exit 1
fi
echo "ALL TESTS PASSED"
exit 0
