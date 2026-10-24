#!/usr/bin/env bash
# #299 (b)(c): text inside a heredoc is data, not a command. Reported 22-23/10 as blocks of harmless commands; both guards are
# checked here in BOTH directions, so "does not reproduce" is evidence and a later regression shows up on either side:
#  (b) hardware_safety_gate: a python heredoc whose body holds `rm -rf "$TMP"` is allowed; a real `rm -rf /` is still refused;
#  (c) worktree_guard, worker that entered a worktree: a python heredoc whose body holds the word git (and `git push origin main`)
#      is allowed from the worktree; a real write into the MAIN checkout (cp) is still refused.
# Only the hooks run here — never the command text.
#   HW_HOOK=<path> / WG_HOOK=<path>  run the same checks against another copy of a hook.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
WG="${WG_HOOK:-$DEVKIT_DIR/hooks/worktree_guard.sh}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

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
# guard <hook> <cwd> <command> -> the hook's exit code
guard() {
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":sys.argv[1],"cwd":sys.argv[2],
"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[3]}}))' "$TR" "$2" "$3" \
  | ( cd "$2" && env -u WORKTREE_GUARD HOME="$TMP" CLAUDE_PROJECT_DIR="$M" bash "$1" >/dev/null 2>"$TMP/err" )
}
want() { # want <rc> <hook> <cwd> <label> <command>
  guard "$2" "$3" "$5"; local rc=$?
  [ "$rc" = "$1" ] && ok "$4: rc $rc" || fail "$4: rc $rc (want $1) — $(head -c 200 "$TMP/err" | tr '\n' ' ')"
}

PY_RM=$'python3 - <<\'PY\'\nopen("t.sh","w").write("rm -rf \\"$TMP\\"")\nPY'
want 0 "$HW" "$W" "(b) python heredoc holding rm -rf \"\$TMP\" text" "$PY_RM"
want 2 "$HW" "$W" "(b) a real rm -rf /" "rm -rf /"

PY_GIT=$'python3 - <<\'PY\'\nprint("git push origin main")\nPY'
want 0 "$WG" "$W" "(c) python heredoc holding the word git, from the worktree" "$PY_GIT"
want 2 "$WG" "$M" "(c) a real write (cp) into the main checkout" "cp /tmp/x src/b.kt"

[ "$FAILS" = 0 ] && echo "ALL PASS" && exit 0
echo "FAILS: $FAILS"; exit 1
