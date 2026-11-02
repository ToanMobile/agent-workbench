#!/usr/bin/env bash
# #486: `worktree finish` fast-forwards main only on gate exit 0, exit 3 (nothing to audit),
# or exit 4 that is only a suite this machine cannot run (no device). Exit 2 with tests_touched
# (an edited test nobody approved), exit 1 while every suite is PASS, and exit 4 label SLOT
# leave main where it was and name the reason.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null
export DEVKIT_LANG=en

repo() {
  local p="$TMP/$1"; mkdir -p "$p/.agents" && G "$p" init -q -b main . && G "$p" config user.email t@t && G "$p" config user.name t
  printf 'greet() { echo ok; }\n' > "$p/lib.sh"
  printf '. ./lib.sh\ngreet\n' > "$p/app.sh"
  printf 'echo "all apps ok"\n' > "$p/check.sh"
  printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"every app prints ok","command":"bash check.sh"}]}]}\n' \
    > "$p/.agents/regression_matrix.active.json"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.claude/\n' > "$p/.gitignore"
  G "$p" add -A && G "$p" commit -qm base
}
wtadd() { (cd "$TMP/$1" && python3 "$WT" add "$TMP/$1-$2" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1-$2"; }
ahead() { printf '. ./lib.sh\ngreet\n' > "$TMP/$1-$2/app2.sh" && G "$TMP/$1-$2" add app2.sh && G "$TMP/$1-$2" commit -qm "app2 calls greet"; }

FK="$TMP/kit"; mkdir -p "$FK/bin" "$FK/profiles" && ln -s "$DEVKIT_DIR/scripts" "$FK/scripts"
printf '%s\n' 'import os, sys' 'if __name__ == "__main__":' '    print("some output")' \
  '    print(os.environ.get("FAKE_GATE_JSON", "null"))' '    sys.exit(int(os.environ.get("FAKE_GATE_CODE", "0")))' \
  > "$FK/bin/post-fix-gate.py"

fin() { # fin <repo> ; FAKE_GATE_CODE and FAKE_GATE_JSON from the caller
  (cd "$TMP/$1" && python3 "$FK/scripts/git/worktree.py" finish "$TMP/$1-w" > "$TMP/out" 2>&1)
}

# one fresh repo per case: a passing finish removes the worktree
prepare() { repo "$1"; wtadd "$1" w; ahead "$1" w; }

PASS_JSON='{"regression_tests":[{"id":"REG-APP-01","status":"PASS"}]}'

# 1 exit 2, suites PASS, an existing test edited and not approved: main stays, the file is named
prepare a; before="$(G "$TMP/a" rev-parse HEAD)"
FAKE_GATE_CODE=2 FAKE_GATE_JSON='{"regression_tests":[{"id":"REG-APP-01","status":"PASS"}],"tests_touched":["tests/t.sh"]}' fin a; rc=$?
if [ "$rc" = 1 ] && [ "$(G "$TMP/a" rev-parse HEAD)" = "$before" ] && [ ! -f "$TMP/a/app2.sh" ] && [ -d "$TMP/a-w" ] \
    && grep -q "tests/t.sh" "$TMP/out" && grep -q "approved_tests.json" "$TMP/out"; then
  ok "exit 2 edited test: refused, main unmoved, the file and the approval path are named"
else
  fail "exit 2 edited test: rc=$rc main_same=$([ "$(G "$TMP/a" rev-parse HEAD)" = "$before" ] && echo yes || echo no) $(tail -3 "$TMP/out")"
fi

# 2 exit 1, every suite PASS (static findings): main stays
prepare b; before="$(G "$TMP/b" rev-parse HEAD)"
FAKE_GATE_CODE=1 FAKE_GATE_JSON="$PASS_JSON" fin b; rc=$?
if [ "$rc" = 1 ] && [ "$(G "$TMP/b" rev-parse HEAD)" = "$before" ] && [ ! -f "$TMP/b/app2.sh" ] && grep -q "exit 1" "$TMP/out"; then
  ok "exit 1 with suites PASS: refused, main unmoved"
else
  fail "exit 1: rc=$rc main_same=$([ "$(G "$TMP/b" rev-parse HEAD)" = "$before" ] && echo yes || echo no) $(tail -3 "$TMP/out")"
fi

# 3 exit 4 label SLOT: main stays
prepare c; before="$(G "$TMP/c" rev-parse HEAD)"
FAKE_GATE_CODE=4 FAKE_GATE_JSON='{"regression_tests":[{"id":"REG-APP-01","status":"UNTESTED","label":"SLOT"}]}' fin c; rc=$?
if [ "$rc" = 1 ] && [ "$(G "$TMP/c" rev-parse HEAD)" = "$before" ] && [ ! -f "$TMP/c/app2.sh" ] && grep -q "SLOT" "$TMP/out"; then
  ok "exit 4 SLOT: refused, main unmoved"
else
  fail "exit 4 SLOT: rc=$rc main_same=$([ "$(G "$TMP/c" rev-parse HEAD)" = "$before" ] && echo yes || echo no) $(tail -3 "$TMP/out")"
fi

# 4 exit 0, including an already-approved edited test: main moves
prepare d
FAKE_GATE_CODE=0 FAKE_GATE_JSON='{"regression_tests":[{"id":"REG-APP-01","status":"PASS"}],"tests_approved":["tests/t.sh"]}' fin d; rc=$?
if [ "$rc" = 0 ] && [ -f "$TMP/d/app2.sh" ] && [ ! -d "$TMP/d-w" ]; then
  ok "exit 0 with tests_approved: merged"
else
  fail "exit 0: rc=$rc $(tail -3 "$TMP/out")"
fi

# 5 exit 4 that is only a missing device (UNTESTED, label not SLOT/BUSY/BUDGET): main moves
prepare e
FAKE_GATE_CODE=4 FAKE_GATE_JSON='{"regression_tests":[{"id":"REG-DEV-01","status":"UNTESTED","label":"missing_tool"}]}' fin e; rc=$?
if [ "$rc" = 0 ] && [ -f "$TMP/e/app2.sh" ] && [ ! -d "$TMP/e-w" ]; then
  ok "exit 4 missing device: merged"
else
  fail "exit 4 missing device: rc=$rc $(tail -3 "$TMP/out")"
fi

# 6 exit 3: nothing to audit, main moves (the JSON is never read)
prepare f
FAKE_GATE_CODE=3 FAKE_GATE_JSON='not-json' fin f; rc=$?
if [ "$rc" = 0 ] && [ -f "$TMP/f/app2.sh" ] && [ ! -d "$TMP/f-w" ]; then
  ok "exit 3 nothing to audit: merged"
else
  fail "exit 3: rc=$rc $(tail -3 "$TMP/out")"
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_merge_gate_edited_test: PASS"; exit 0; }
echo "test_worktree_merge_gate_edited_test: FAIL ($FAILS)"; exit 1
