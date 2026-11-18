#!/usr/bin/env bash
# Regression (#1296): in trunk mode CLAUDE_PROJECT_DIR points at the main checkout while the session
# runs in a linked worktree. `agent-kit learn` and post-fix-gate record_lesson must write the lesson
# into the worktree's .agents/instincts.md, never into the main checkout's tracked file.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset TARGET_DIR
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/main/.agents" && cd "$TMP/main" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf '# instincts\n' > .agents/instincts.md
git add -A && git commit -qm init
git worktree add -q "$TMP/wt" -b wt-branch
main_before="$(cat .agents/instincts.md)"

export CLAUDE_PROJECT_DIR="$TMP/main"
cd "$TMP/wt" || exit 1
bash "$KIT" learn "Worktree lesson one" --cause c --rule r >/dev/null 2>&1
grep -q 'Worktree lesson one' "$TMP/wt/.agents/instincts.md" && ok "learn writes into the worktree" || fail "learn did not write into the worktree"
[ "$(cat "$TMP/main/.agents/instincts.md")" = "$main_before" ] && ok "learn leaves main's instincts.md untouched" || fail "learn dirtied main"

python3 - "$DEVKIT_DIR" "$TMP/main" <<'PY'
import importlib.util, sys
from pathlib import Path
devkit, main = sys.argv[1], Path(sys.argv[2])
sys.path.insert(0, f"{devkit}/bin")
spec = importlib.util.spec_from_file_location("pfg", f"{devkit}/bin/post-fix-gate.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.record_lesson(main, "Worktree lesson two", "c", "p")
PY
grep -q 'Worktree lesson two' "$TMP/wt/.agents/instincts.md" && ok "record_lesson writes into the worktree" || fail "record_lesson did not write into the worktree"
[ "$(cat "$TMP/main/.agents/instincts.md")" = "$main_before" ] && ok "record_lesson leaves main untouched" || fail "record_lesson dirtied main"

# A plain main-checkout session still writes to main.
cd "$TMP/main" && bash "$KIT" learn "Main lesson" >/dev/null 2>&1
grep -q 'Main lesson' "$TMP/main/.agents/instincts.md" && ok "main checkout session still writes to main" || fail "main session regressed"
[ "$FAILS" -eq 0 ]
