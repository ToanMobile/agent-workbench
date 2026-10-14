#!/usr/bin/env bash
# hooks/review_gate.sh counts code changed through Bash (issue #13, 13/10): the gate only saw the Edit/Write/NotebookEdit tools, so
# code rewritten by a script (`python3 - <<'EOF'`, `sed -i`, a heredoc) logged "none edited this session — pass" and no review was
# asked (session d352c03b, W1 step 1: every change to worktree.py went through Python, review_gate.log had no BLOCK). Now a file
# of the diff counts as edited at the latest Bash command of the session that names it and was running when the file last changed
# (start to result, 2 s slack; a run in the background: up to 2 h); a deleted file at the latest command that names it as a write
# target. Not this session's edit (OpenCodeReview and principal-code-reviewer, 14/10): a command that named the file only before or
# after the change (a `cat`, then an IDE save), another file of the same name (other/app.py, app.py.bak, another checkout's absolute
# path), a read naming a deleted file. A 72 KB command stays well inside the hook's 20 s.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P/scripts"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo "def f(): return 1" > scripts/app.py && echo "def g(): return 1" > scripts/other.py && git add -A && git commit -qm i)
P="$(cd "$P" && pwd -P)"

TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys, time, datetime
kind, tr, at = sys.argv[1], sys.argv[2], float(sys.argv[3])   # at: seconds from now (the record's timestamp)
a = sys.argv[4:]
stamp = datetime.datetime.fromtimestamp(time.time() + at, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
if kind == "bash":
    rec = {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": a[0], "name": "Bash", "input": {"command": a[1]}}]}}
elif kind == "result":
    rec = {"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": a[0], "content": a[1] if len(a) > 1 else "ok"}]}}
elif kind == "agent":
    rec = {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": a[0], "name": "Agent", "input": {"subagent_type": a[1], "prompt": "review"}}]}}
rec["timestamp"] = stamp
with open(tr, "a") as f:
    f.write(json.dumps(rec) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
setmtime() { python3 -c 'import os, sys, time; t = time.time() + float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$2"; }
stop() { printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" \
  | REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0 CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; }
reset() { : > "$TR"; rm -rf "$P/.claude/audit-gate"; rm -f "$P/.git/devkit-session.lock"; git -C "$P" reset -q --hard; }
change() { echo "def f(): return $1" > "$P/scripts/app.py"; setmtime "$P/scripts/app.py" "$2"; }
lock() {   # lock <session id> <started, seconds from now>
  python3 -c 'import json,sys,time; json.dump({"session_id":sys.argv[1],"started":time.time()+float(sys.argv[2]),"heartbeat":time.time()-1,
"cwd":sys.argv[3],"pid":int(sys.argv[4]),"gitdir":sys.argv[3]+"/.git"},open(sys.argv[3]+"/.git/devkit-session.lock","w"))' "$1" "$2" "$P" $$
}
expect() {   # expect <rc> <label>
  stop; local rc=$?
  [ "$rc" = "$1" ] && ok "$2" || fail "$2: rc $rc (want $1), log: $(tail -1 "$P/.claude/audit-gate/review_gate.log" 2>/dev/null)"
}

# 1. a heredoc script rewrote the file: blocked until a review runs after it
reset
ev bash -120 b1 "python3 - <<'EOF'
p = 'scripts/app.py'
open(p, 'w').write('def f(): return 2\n')
EOF"
change 2 -119; ev result -118 b1
expect 2 "code rewritten by a Bash heredoc: blocked until reviewed"
ev agent -60 a1 principal-code-reviewer
expect 0 "a review after the Bash edit: passes"

# 2. sed -i through a variable path after the review: blocked again
ev bash -30 b2 "sed -i '' 's/2/3/' \"\$W/scripts/app.py\""
change 3 -29; ev result -28 b2
expect 2 "a sed -i (\$W/scripts/app.py) after the review re-arms the gate"

# 3. a command that names the file only AFTER it changed (a cat, a grep) is not the edit
reset
change 4 -200; ev bash -100 b3 "cat scripts/app.py"; ev result -99 b3
expect 0 "a read after the change is not this session's edit"

# 4. a change no Bash command of this session names (another session's dirty file) is not this session's edit
reset
ev bash -100 b4 "python3 - <<'EOF'
open('scripts/other.py').read()
EOF"
ev result -99 b4; change 5 -50
expect 0 "a file no command of the session names: not counted"

# 5. a read that ENDED before the change (an IDE save later) is not the edit
reset
ev bash -100 b5 "grep -n f scripts/app.py"; ev result -99 b5; change 6 -50
expect 0 "a grep that ended before the file changed: not counted"

# 6. a run moved to the background has no end: a change after its result line is still its own
reset
ev bash -100 b6 "python3 tools/regen.py scripts/app.py"; ev result -99 b6 "Command running in background with ID: x1. Output is being written to: /tmp/x"
change 7 -50
expect 2 "a background run that names the file: its later change counts"

# 7. another file of the same name: other/app.py, app.py.bak, myapp.py, another checkout's absolute path
for c in "sed -i '' s/1/2/ other/app.py" "cp /tmp/x scripts/app.py.bak" "python3 scripts/myapp.py" \
         "sed -i '' s/1/2/ /elsewhere/checkout/scripts/app.py" "sed -i '' s/1/2/ ../other/scripts/app.py" \
         "sed -i '' s/1/2/ /elsewhere/./scripts/app.py"; do
  reset; ev bash -100 b7 "$c"; change 8 -99; ev result -98 b7
  expect 0 "not the same file: $c"
done
# ... while this repo's own absolute path and a ../ path are
for c in "sed -i '' s/1/2/ $P/scripts/app.py" "cd tools && sed -i '' s/1/2/ ../scripts/app.py"; do
  reset; ev bash -100 b8 "$c"; change 9 -99; ev result -98 b8
  expect 2 "the same file: $c"
done

# 8. a file deleted through Bash
reset
ev bash -50 b9 "rm scripts/app.py"; rm -f "$P/scripts/app.py"; ev result -49 b9
expect 2 "a code file deleted with rm: blocked until reviewed"

# ... a deleted file that only a read names (another session's `git rm`, then this session's grep) is not this session's edit
reset
git -C "$P" rm -q scripts/other.py; ev bash -50 b10 "grep -rn 'other.py' ."; ev result -49 b10
expect 0 "a deleted file a grep names: not counted (only a write-shaped command counts)"

# 9. the checkout held by another live session does not make this session's own Bash edit disappear (review 14/10: session_lock
#    does not stop a python heredoc, issue #13's own case)
reset
ev bash -100 b11 "python3 - <<'EOF'
open('scripts/app.py', 'w').write('x')
EOF"
change 11 -99; ev result -98 b11
lock other-session -300
expect 2 "held by another live session: this session's heredoc edit still counts"

# 10. paths above the repo root and in an f-string; the other background variants
for c in "sed -i '' s/1/2/ \$HOME/work/p/scripts/app.py" "python3 - <<'EOF'
open(f\"{ROOT}/scripts/app.py\", 'w').write('x')
EOF"; do
  reset; ev bash -100 b12 "$c"; change 12 -99; ev result -98 b12
  expect 2 "named through a prefix: $(printf '%s' "$c" | head -2 | tr '\n' ' ')"
done
reset
ev bash -100 b13 "python3 tools/regen.py scripts/app.py"
ev result -99 b13 "Command was moved to the background (ID: x2) so that a message could be sent"; change 13 -50
expect 2 "a run moved to the background (other wording): its later change counts"
reset
python3 - "$TR" <<'PY'
import json, sys, time, datetime
st = lambda at: datetime.datetime.fromtimestamp(time.time() + at, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
with open(sys.argv[1], "a") as f:
    f.write(json.dumps({"type": "assistant", "timestamp": st(-100), "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "b14", "name": "Bash", "input": {"command": "python3 tools/regen.py scripts/app.py", "run_in_background": True}}]}}) + "\n")
    f.write(json.dumps({"type": "user", "timestamp": st(-99), "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "b14", "content": "started"}]}}) + "\n")
PY
change 14 -50
expect 2 "run_in_background: its later change counts whatever its result says"
# ... and a review that STARTED before that change did not see it (OpenCodeReview 14/10: crediting the run's own index let it pass)
ev agent -70 a14 principal-code-reviewer
expect 2 "a background run changing the file after a review: still blocked"
ev agent -10 a15 principal-code-reviewer
expect 0 "a review after the background change: passes"

# 11. a 72 KB token before the name (a base64 blob in a heredoc) stays fast: the hook has 20 s (review 14/10: 120 s)
reset
python3 - "$TR" <<'PY'
import json, sys, time, datetime
st = lambda at: datetime.datetime.fromtimestamp(time.time() + at, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
cmd = "python3 - <<'EOF'\nb = '" + "QUJD" * 18000 + "'\nopen('scripts/app.py', 'w').write(b)\nEOF"
with open(sys.argv[1], "a") as f:
    f.write(json.dumps({"type": "assistant", "timestamp": st(-100), "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "b15", "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
    f.write(json.dumps({"type": "user", "timestamp": st(-98), "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "b15", "content": "ok"}]}}) + "\n")
PY
change 15 -99
t0=$(date +%s); expect 2 "a 72 KB heredoc that writes the file: counted"; t1=$(date +%s)
[ $((t1 - t0)) -lt 5 ] && ok "... in $((t1 - t0)) s (< 5 s)" || fail "a 72 KB command took $((t1 - t0)) s"

if [ "$FAILS" -ne 0 ]; then echo "review gate bash edit: $FAILS FAILED"; exit 1; fi
echo "review gate bash edit: all checks passed"
