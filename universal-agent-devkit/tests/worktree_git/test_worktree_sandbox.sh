#!/usr/bin/env bash
# Regression test: worktree_sandbox.py creation, .worktreeinclude CoW copy, and cleanup
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$DEVKIT_DIR/scripts/git/worktree_sandbox.py"
[ -f "$SCRIPT" ] || SCRIPT="$DEVKIT_DIR/scripts/worktree_sandbox.py"
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
INC=$(python3 -c "import sys; sys.path.extend(['$DEVKIT_DIR/scripts/git', '$DEVKIT_DIR/scripts']); import worktree_sandbox as w; from pathlib import Path; print(w.parse_worktree_include(Path('$P')))")
if [ "$INC" = "['.env']" ]; then
  ok ".worktreeinclude '.' / './' lines are ignored"
else
  fail ".worktreeinclude accepted a repo-root path: $INC"
fi

# Test 6: cleanup never discards work unless --force is given
python3 "$SCRIPT" create dirty_sb >/dev/null 2>&1
echo "uncommitted work" >> "$P/.sandboxes/dirty_sb/README.md"
python3 "$SCRIPT" cleanup --name dirty_sb >/dev/null 2>&1
if [ -d "$P/.sandboxes/dirty_sb" ] && grep -q "uncommitted work" "$P/.sandboxes/dirty_sb/README.md"; then
  ok "cleanup keeps a sandbox that has uncommitted changes"
else
  fail "cleanup destroyed uncommitted work without --force"
fi
python3 "$SCRIPT" create ahead_sb >/dev/null 2>&1
( cd "$P/.sandboxes/ahead_sb" && echo x > ahead.txt && git add ahead.txt && git commit -q -m "feat: unmerged" )
python3 "$SCRIPT" cleanup --name ahead_sb >/dev/null 2>&1
if git -C "$P" rev-parse --verify -q "sandbox/ahead_sb" >/dev/null; then
  ok "cleanup keeps the branch that holds unmerged commits"
else
  fail "cleanup deleted a branch with unmerged commits without --force"
fi
python3 "$SCRIPT" cleanup --name dirty_sb --force >/dev/null 2>&1
python3 "$SCRIPT" cleanup --name ahead_sb --force >/dev/null 2>&1
if [ ! -d "$P/.sandboxes/dirty_sb" ] && [ ! -d "$P/.sandboxes/ahead_sb" ] && ! git -C "$P" rev-parse --verify -q "sandbox/ahead_sb" >/dev/null; then
  ok "--force removes the sandbox and the unmerged branch on explicit request"
else
  fail "--force did not remove the sandboxes and branch"
fi

# Test 7: a new file that was never `git add`ed is work too (not a disposable leftover)
python3 "$SCRIPT" create untracked_sb >/dev/null 2>&1
echo "print('feature')" > "$P/.sandboxes/untracked_sb/feature.py"
python3 "$SCRIPT" cleanup --name untracked_sb >/dev/null 2>&1
if [ -f "$P/.sandboxes/untracked_sb/feature.py" ]; then
  ok "cleanup keeps a sandbox holding a new untracked file"
else
  fail "cleanup deleted an untracked new file without --force"
fi
if python3 "$SCRIPT" merge-winner untracked_sb >/dev/null 2>&1; then
  fail "merge-winner accepted a sandbox holding an untracked new file"
else
  ok "merge-winner refuses a sandbox holding an untracked new file"
fi
[ -f "$P/.sandboxes/untracked_sb/feature.py" ] && ok "  … and the file is still there" || fail "merge-winner lost the untracked file"
python3 "$SCRIPT" cleanup --name untracked_sb --force >/dev/null 2>&1

# Test 8: an unreadable worktree (admin dir gone) must not look clean
python3 "$SCRIPT" create broken_sb >/dev/null 2>&1
echo "tracked edit" >> "$P/.sandboxes/broken_sb/README.md"
GCD="$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)"
mv "$GCD/worktrees/broken_sb" "$TMP/broken_sb_admin"
python3 "$SCRIPT" cleanup --name broken_sb >/dev/null 2>&1
if [ -f "$P/.sandboxes/broken_sb/README.md" ] && grep -q "tracked edit" "$P/.sandboxes/broken_sb/README.md"; then
  ok "cleanup keeps a sandbox whose git status cannot be read"
else
  fail "cleanup deleted a sandbox whose status was unreadable"
fi
mv "$TMP/broken_sb_admin" "$GCD/worktrees/broken_sb"
python3 "$SCRIPT" cleanup --name broken_sb --force >/dev/null 2>&1

# Test 9: .worktreeinclude may name a DIRECTORY; a new file inside it is still work, an unchanged copy is not
mkdir -p "$P/config" && echo "base" > "$P/config/base.txt"
printf 'config\n.env\n' > "$P/.worktreeinclude"
python3 "$SCRIPT" create dir_sb >/dev/null 2>&1
echo "print('mine')" > "$P/.sandboxes/dir_sb/config/new_work.py"
python3 "$SCRIPT" cleanup --name dir_sb >/dev/null 2>&1
if [ -f "$P/.sandboxes/dir_sb/config/new_work.py" ]; then
  ok "cleanup keeps a new file inside an included directory"
else
  fail "cleanup deleted a new file inside an included directory"
fi
rm -f "$P/.sandboxes/dir_sb/config/new_work.py"
python3 "$SCRIPT" cleanup --name dir_sb >/dev/null 2>&1
if [ ! -d "$P/.sandboxes/dir_sb" ]; then
  ok "a sandbox holding only unchanged copies of included files is cleaned up"
else
  fail "a sandbox with only unchanged included copies was kept"
fi

if [ $FAILS -gt 0 ]; then
  echo "FAILED: $FAILS errors"
  exit 1
fi
echo "ALL TESTS PASSED"
exit 0
