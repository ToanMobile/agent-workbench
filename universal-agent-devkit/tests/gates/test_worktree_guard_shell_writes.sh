#!/usr/bin/env bash
# hooks/worktree_guard.sh now takes its Bash write targets from hooks/shell_writes.py (issues-bugs.md A.1 #3, 14/10: the scanner it had
# inline, shared with bin/session_lock.py). For a worker that entered a worktree (EnterWorktree in its transcript):
#  - a Bash write into the MAIN checkout is still blocked (cp, chmod -w whose mode starts with -, env -C <main> rm from the worktree);
#  - the same write inside its worktree is not;
#  - with shell_writes.py missing next to the hook (a partial install), the Bash call is BLOCKED with the reason: the inline scanner
#    always ran, so a missing module must not switch the check off without a word (OpenCodeReview 14/10).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M="$TMP/main"; W="$TMP/wt"
mkdir -p "$M/src" && git -C "$M" init -q && git -C "$M" config user.email t@t && git -C "$M" config user.name t \
  && echo x > "$M/src/a.kt" && git -C "$M" add -A && git -C "$M" commit -qm i && git -C "$M" worktree add -q --detach "$W" HEAD
TR="$TMP/t.jsonl"
python3 - "$TR" "$M" "$W" <<'PY'
import json, sys
tr, main, wt = sys.argv[1:4]
rec = lambda **kw: json.dumps(kw, separators=(",", ":"))
with open(tr, "w") as f:
    f.write(rec(type="user", cwd=main, message={"role": "user", "content": "hi"}) + "\n")
    f.write(rec(type="assistant", cwd=main, message={"role": "assistant", "content": [
        {"type": "tool_use", "id": "toolu_1", "name": "EnterWorktree", "input": {"path": wt}}]}) + "\n")
    f.write(rec(type="user", cwd=main, message={"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "toolu_1", "content": "Switched to worktree " + wt}]}) + "\n")
PY
guard() {   # guard <hook> <cwd> <command>: the hook's exit code; stderr in $TMP/err
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":sys.argv[1],"cwd":sys.argv[2],
"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[3]}}))' "$TR" "$2" "$3" \
  | env -u WORKTREE_GUARD CLAUDE_PROJECT_DIR="$M" bash "$1" >/dev/null 2>"$TMP/err"
}
H="$DEVKIT_DIR/hooks/worktree_guard.sh"
guard "$H" "$M" "cp /tmp/x src/b.kt"; rc=$?
[ "$rc" = 2 ] && grep -q "WORKTREE GUARD" "$TMP/err" && ok "cp into the main checkout: blocked" || fail "cp into main: rc $rc"
guard "$H" "$M" "chmod -w src/a.kt"; rc=$?
[ "$rc" = 2 ] && ok "chmod -w (a mode starting with -) in the main checkout: blocked" || fail "chmod -w in main: rc $rc"
guard "$H" "$W" "env -C $M rm src/a.kt"; rc=$?
[ "$rc" = 2 ] && ok "env -C <main> rm from the worktree: blocked" || fail "env -C main: rc $rc"
guard "$H" "$W" "rm src/a.kt"; rc=$?
[ "$rc" = 0 ] && ok "rm inside its own worktree: allowed" || fail "rm in the worktree: rc $rc $(cat "$TMP/err")"
# env -S / --split-string holds a whole command line: env splits it into words, puts them first and runs them with the words after it
# appended. It was dropped as the option's value, so its writes were never seen (OpenCodeReview 14/10, issues-bugs.md A.4 (b)).
guard "$H" "$M" "env -S 'rm src/a.kt'"; rc=$?
[ "$rc" = 2 ] && ok "env -S '<rm …>' in the main checkout: blocked" || fail "env -S '<rm …>' in main: rc $rc"
guard "$H" "$M" "env -S'rm -f' src/a.kt"; rc=$?
[ "$rc" = 2 ] && ok "env -S'rm -f' src/a.kt (attached, the operand after it): blocked" || fail "env -S'rm -f' + operand in main: rc $rc"
guard "$H" "$M" "env --split-string 'FOO=1 rm src/a.kt'"; rc=$?
[ "$rc" = 2 ] && ok "env --split-string '<VAR=… rm …>' in the main checkout: blocked" || fail "env --split-string <line> in main: rc $rc"
guard "$H" "$M" "env -i --split-string='rm src/a.kt'"; rc=$?
[ "$rc" = 2 ] && ok "env -i --split-string='<rm …>' in the main checkout: blocked" || fail "env --split-string=<line> in main: rc $rc"
guard "$H" "$W" "env -S 'rm src/a.kt'"; rc=$?
[ "$rc" = 0 ] && ok "env -S '<rm …>' inside its own worktree: allowed" || fail "env -S in the worktree: rc $rc $(cat "$TMP/err")"

mkdir -p "$TMP/partial" && cp "$H" "$TMP/partial/worktree_guard.sh"   # a partial install: no shell_writes.py beside it
guard "$TMP/partial/worktree_guard.sh" "$M" "cp /tmp/x src/b.kt"; rc=$?
[ "$rc" = 2 ] && grep -q "shell_writes.py could not be loaded" "$TMP/err" && ok "shell_writes.py missing: the Bash call is blocked with the reason" \
  || fail "missing module: rc $rc $(cat "$TMP/err")"

if [ "$FAILS" -ne 0 ]; then echo "worktree_guard shell_writes: $FAILS FAILED"; exit 1; fi
echo "worktree_guard shell_writes: all checks passed"
