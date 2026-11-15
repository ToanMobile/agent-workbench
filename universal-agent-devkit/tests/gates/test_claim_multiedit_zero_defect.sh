#!/usr/bin/env bash
# Zero-Defect commitments C1 / C2, the holes Antigravity's audit T0479 reproduced on the kit at 5db81236 (2026-11-14) in three hooks
# next to test_evidence_gate.sh (its own cases: tests/gates/test_evidence_zero_defect_c1.sh):
#  A. hooks/claim_check.sh (Stop), check C: any Bash tool_use that NAMES a test runner backed "đã chạy test", also when its result says
#     the runner never started (exit 127 "command not found", exit 126, a call a hook refused, a missing script). Two-way: a run that
#     passed, a run whose tests FAILED (it ran) and a call with no result in the transcript back the claim as before.
#  B. hooks/comment_claim_guard.sh (PostToolUse): a MultiEdit carries its text in `edits[].new_string`, the guard read only
#     `new_string` / `content`, so a claim comment written by MultiEdit was never read.
#  C. hooks/churn_guard.sh (PostToolUse): MultiEdit calls were no edits, so three in a row with no evidence call never warned.
#  D. the PostToolUse matcher that starts B and C held no MultiEdit (hooks/hooks.json, templates/claude_settings.json). A project's
#     installed .claude/settings.json gets it from the template at the next install; it is live session configuration, not a kit file.
# Run: bash tests/gates/test_claim_multiedit_zero_defect.sh   (CC_HOOK / CCG_HOOK / CG_HOOK=<path> test another copy of a hook)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CC="${CC_HOOK:-$DEVKIT_DIR/hooks/claim_check.sh}"
CCG="${CCG_HOOK:-$DEVKIT_DIR/hooks/comment_claim_guard.sh}"
CG="${CG_HOOK:-$DEVKIT_DIR/hooks/churn_guard.sh}"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
R="$TMP/repo"; mkdir -p "$R/app" "$R/scripts"
git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
N=0

echo "-- A. claim_check.sh: a runner call that never started is no evidence for 'đã chạy test'"
# bash_tr <file> <cmd> <result text | -> <is_error: true|false>: one Bash call; "-" = the transcript holds no result for it
bash_tr() {
  python3 - "$@" <<'PY'
import json, sys
out, cmd, res, err = sys.argv[1:5]
with open(out, "w") as fh:
    fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": "chạy test giúp tôi"}}) + "\n")
    fh.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
    if res != "-":
        fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": [
            {"type": "tool_result", "tool_use_id": "t1", "content": res, "is_error": err == "true"}]}}) + "\n")
PY
}
# cc <want rc> <label> <transcript> <reply>
cc() {
  local want="$1" label="$2" tr="$3" text="$4" rc
  N=$((N + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":"zd-cc-"+sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' \
    "$tr" "$text" "$N" > "$TMP/in.json"
  ( cd "$R" && CLAUDE_PROJECT_DIR="$R" bash "$CC" < "$TMP/in.json" > /dev/null 2> "$TMP/err" ); rc=$?
  grep -q Traceback "$TMP/err" && rc=99
  [ "$rc" = "$want" ] && ok "rc $rc: $label" || fail "rc $rc (want $want): $label — $(head -c 160 "$TMP/err" | tr '\n' ' ')"
}
RAN='Tôi đã chạy test cho dự án.'
T="$TMP/cc.jsonl"
bash_tr "$T" 'ls' 'README.md' false
cc 2 "control: no runner call at all" "$T" "$RAN"
bash_tr "$T" 'pytest -q' $'Exit code 127\n/bin/zsh:1: command not found: pytest' true
cc 2 "pytest: exit 127, command not found" "$T" "$RAN"
cc 2 "the same in English ('I ran the tests.')" "$T" 'I ran the tests.'
bash_tr "$T" 'npm test' $'Exit code 127\nbash: npm: command not found' true
cc 2 "npm test: exit 127 (bash wording)" "$T" "$RAN"
bash_tr "$T" './gradlew test' $'Exit code 126\n/bin/zsh:1: permission denied: ./gradlew' true
cc 2 "./gradlew test: exit 126, permission denied" "$T" "$RAN"
bash_tr "$T" 'bash tests/test_x.sh' $'Exit code 127\nbash: tests/test_x.sh: No such file or directory' true
cc 2 "bash tests/test_x.sh: no such file" "$T" "$RAN"
bash_tr "$T" 'python3 -m pytest -q' 'PreToolUse:Bash hook error: [bash .claude/hooks/session_lock.sh]: ⛔ blocked' true
cc 2 "a call a hook refused" "$T" "$RAN"
bash_tr "$T" 'python3 -m pytest -q' $'Exit code 1\n/usr/bin/python3: No module named pytest' true
cc 2 "python3 -m pytest: No module named pytest" "$T" "$RAN"
bash_tr "$T" 'python3 -m pytest -q' '5 passed in 0.03s' false
cc 0 "control: the run passed" "$T" "$RAN"
bash_tr "$T" 'python3 -m pytest -q' $'Exit code 1\nFAILED tests/test_a.py::test_x - assert 1 == 2\n1 failed, 4 passed in 0.05s' true
cc 0 "control: the tests ran and FAILED (the claim is 'ran', and it did)" "$T" "$RAN"
bash_tr "$T" 'python3 -m pytest -q' - false
cc 0 "control: a call with no result in the transcript (as before)" "$T" "$RAN"

echo "-- B. comment_claim_guard.sh: a claim comment written by MultiEdit is read"
# ccg <want rc> <label> <file> <tool: Edit|MultiEdit> <text, \n = newline> [second MultiEdit text]
ccg() {
  local want="$1" label="$2" file="$3" tool="$4" text="$5" more="${6:-}" rc
  : > "$TMP/empty.jsonl"
  python3 -I -c '
import json, sys
tool, f, text, more = sys.argv[1], sys.argv[2], sys.argv[3].replace("\\n", "\n"), sys.argv[4].replace("\\n", "\n")
if tool == "MultiEdit":
    inp = {"file_path": f, "edits": [{"old_string": "pass", "new_string": text}] + ([{"old_string": "x", "new_string": more}] if more else [])}
else:
    inp = {"file_path": f, "old_string": "pass", "new_string": text}
print(json.dumps({"session_id": "s", "transcript_path": sys.argv[5], "cwd": sys.argv[6], "hook_event_name": "PostToolUse",
                  "tool_name": tool, "tool_input": inp, "tool_response": {"filePath": f}}))' "$tool" "$R/$file" "$text" "$more" "$TMP/empty.jsonl" "$R" \
    > "$TMP/in.json"
  ( cd "$R" && CLAUDE_PROJECT_DIR="$R" bash "$CCG" < "$TMP/in.json" > /dev/null 2> "$TMP/err" ); rc=$?
  grep -q Traceback "$TMP/err" && rc=99
  [ "$rc" = "$want" ] && ok "rc $rc: $label" || fail "rc $rc (want $want): $label — $(head -c 160 "$TMP/err" | tr '\n' ' ')"
}
ccg 2 "control: Edit, '# already tested on macOS' in a .sh"      scripts/run.sh Edit      '# already tested on macOS\necho hi'
ccg 2 "MultiEdit, the same comment in a .sh"                     scripts/run.sh MultiEdit '# already tested on macOS\necho hi'
ccg 2 "MultiEdit, '# đã được test ở module khác' in a .py"       app/util.py    MultiEdit '# đã được test ở module khác\nX = 1'
ccg 2 "MultiEdit, the claim is in its SECOND edit"               scripts/run.sh MultiEdit 'echo hi' '# never called anywhere else\necho bye'
ccg 0 "control: MultiEdit, a plain comment"                      scripts/run.sh MultiEdit '# Build the bundle, then sign it.\necho ok'
ccg 0 "control: MultiEdit, claim words in a string, no comment"  app/msg.py     MultiEdit 'MSG = "covered by test_orders"'
ccg 0 "control: MultiEdit of a .md"                              notes.md       MultiEdit '# covered by test_orders'

echo "-- C. churn_guard.sh: MultiEdit calls count as edits of the file"
# churn_tr <file> <spec…>: one assistant line per spec: e<name> = Edit of /p/<name>, m<name> = MultiEdit of it, b = a Bash call (evidence)
churn_tr() {
  local f="$1"; shift; : > "$f"; local i=0 s
  for s in "$@"; do
    i=$((i + 1))
    case "$s" in
      e*) printf '{"type":"assistant","message":{"id":"m%s","content":[{"type":"tool_use","id":"t%s","name":"Edit","input":{"file_path":"/p/%s","old_string":"a","new_string":"b"}}]}}\n' "$i" "$i" "${s#e}" >> "$f" ;;
      m*) printf '{"type":"assistant","message":{"id":"m%s","content":[{"type":"tool_use","id":"t%s","name":"MultiEdit","input":{"file_path":"/p/%s","edits":[{"old_string":"a","new_string":"b"}]}}]}}\n' "$i" "$i" "${s#m}" >> "$f" ;;
      b)  printf '{"type":"assistant","message":{"id":"m%s","content":[{"type":"tool_use","id":"t%s","name":"Bash","input":{"command":"ls"}}]}}\n' "$i" "$i" >> "$f" ;;
    esac
  done
}
# cg <want rc> <label> <tool of the triggering call> <spec…>
cg() {
  local want="$1" label="$2" tool="$3" rc; shift 3
  churn_tr "$TMP/churn.jsonl" "$@"
  printf '{"session_id":"s","transcript_path":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"file_path":"/p/Foo.kt"}}' \
    "$TMP/churn.jsonl" "$R" "$tool" > "$TMP/in.json"
  ( cd "$R" && CLAUDE_PROJECT_DIR="$R" bash "$CG" < "$TMP/in.json" > /dev/null 2> "$TMP/err" ); rc=$?
  grep -q Traceback "$TMP/err" && rc=99
  [ "$rc" = "$want" ] && ok "rc $rc: $label" || fail "rc $rc (want $want): $label — $(head -c 160 "$TMP/err" | tr '\n' ' ')"
}
cg 2 "control: the 3rd Edit in a row warns"                       Edit      eFoo.kt eFoo.kt eFoo.kt
cg 2 "the 3rd MultiEdit in a row warns"                           MultiEdit mFoo.kt mFoo.kt mFoo.kt
cg 2 "Edit, MultiEdit, Edit of one file: the 3rd warns"           Edit      eFoo.kt mFoo.kt eFoo.kt
cg 0 "control: the 2nd MultiEdit does not"                        MultiEdit mFoo.kt mFoo.kt
cg 0 "control: evidence between the MultiEdits resets the count"  MultiEdit mFoo.kt mFoo.kt b mFoo.kt
cg 0 "control: MultiEdits of another file do not count"           MultiEdit mBar.kt mBar.kt mFoo.kt

echo "-- D. the PostToolUse matcher that starts churn_guard.sh and comment_claim_guard.sh names MultiEdit"
# matcher <label> <settings file>: every PostToolUse entry that runs one of the two hooks matches MultiEdit (and still Edit, Write, NotebookEdit)
matcher() {
  local out
  out="$(python3 -I - "$2" <<'PY'
import json, sys
bad, seen = [], 0
for e in (json.load(open(sys.argv[1])).get("hooks") or {}).get("PostToolUse") or []:
    cmds = " ".join(str(h.get("command", "")) for h in e.get("hooks") or [])
    if "churn_guard.sh" in cmds or "comment_claim_guard.sh" in cmds:
        seen += 1
        names = str(e.get("matcher", "")).split("|")
        missing = [t for t in ("Edit", "Write", "MultiEdit", "NotebookEdit") if t not in names]
        if missing:
            bad.append("matcher %r lacks %s" % (e.get("matcher"), ", ".join(missing)))
print("; ".join(bad) if bad else ("" if seen else "no PostToolUse entry runs the two hooks"))
PY
)"
  [ -z "$out" ] && ok "$1" || fail "$1: $out"
}
matcher "hooks/hooks.json" "$DEVKIT_DIR/hooks/hooks.json"
matcher "templates/claude_settings.json" "$DEVKIT_DIR/templates/claude_settings.json"

echo "-- E. claim_check.sh: a tool id that is no string (a list, an object, null, a number) neither crashes the hook nor frees the claim"
# OCR review of 2193a36a: `tool_use_id in test_calls` with a list id raised TypeError (unhashable), the hook left with rc 0 and every claim passed.
# id_tr <file> <cmd> <result text> <is_error> <id as JSON>: one Bash call and its result, both carrying that id
id_tr() {
  python3 - "$@" <<'PY'
import json, sys
out, cmd, res, err = sys.argv[1:5]
tid = json.loads(sys.argv[5])
with open(out, "w") as fh:
    fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": "chạy test giúp tôi"}}) + "\n")
    fh.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
    fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": tid, "content": res, "is_error": err == "true"}]}}) + "\n")
PY
}
for id in '["a","b"]' '{"k":1}' 'null' '7'; do
  id_tr "$T" 'ls' 'README.md' false "$id"
  cc 2 "id $id: no runner call, the claim is still blocked" "$T" "$RAN"
  id_tr "$T" 'pytest -q' $'Exit code 127\n/bin/zsh:1: command not found: pytest' true "$id"
  cc 2 "id $id: a runner that never started is still no evidence" "$T" "$RAN"
  id_tr "$T" 'python3 -m pytest -q' '5 passed in 0.03s' false "$id"
  cc 0 "id $id: control, the run passed" "$T" "$RAN"
done

echo "-- F. review_gate.sh / security_gate.sh (Stop): a file edited by MultiEdit is seen like one edited by Edit"
RG="${RG_HOOK:-$DEVKIT_DIR/hooks/review_gate.sh}"
SG="${SG_HOOK:-$DEVKIT_DIR/hooks/security_gate.sh}"
mkdir -p "$R/app/src/main"
printf 'def f():\n    return 1\n' > "$R/app/util.py"; echo '<manifest/>' > "$R/app/src/main/AndroidManifest.xml"; echo 'notes' > "$R/notes.md"
git -C "$R" add -A && git -C "$R" commit -qm init
printf 'def f():\n    return 2\n' > "$R/app/util.py"      # the edit of the transcript is real: an uncommitted diff
# edit_tr <file> <tool: Edit|MultiEdit> <path> <new text>: one edit call that ran
edit_tr() {
  python3 - "$@" <<'PY'
import json, sys
out, tool, path, text = sys.argv[1:5]
inp = {"file_path": path, "old_string": "a", "new_string": text}
if tool == "MultiEdit":
    inp = {"file_path": path, "edits": [{"old_string": "a", "new_string": "x = 1"}, {"old_string": "b", "new_string": text}]}
with open(out, "w") as fh:
    fh.write(json.dumps({"type": "user", "timestamp": "2026-11-15T00:00:00Z", "message": {"role": "user", "content": "go"}}) + "\n")
    fh.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": tool, "input": inp}]}}) + "\n")
    fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "t1", "content": "The file has been updated successfully.", "is_error": False}]}}) + "\n")
PY
}
# stopgate <want rc> <label> <hook> <transcript>
stopgate() {
  local want="$1" label="$2" hook="$3" tr="$4" rc
  N=$((N + 1))
  printf '{"session_id":"zd-sg-%s","transcript_path":"%s","hook_event_name":"Stop","last_assistant_message":"xong"}' "$N" "$tr" > "$TMP/in.json"
  ( cd "$R" && env -u SECURITY_GATE -u REVIEW_GATE CLAUDE_PROJECT_DIR="$R" bash "$hook" < "$TMP/in.json" > /dev/null 2> "$TMP/err" ); rc=$?
  grep -q Traceback "$TMP/err" && rc=99
  [ "$rc" = "$want" ] && ok "rc $rc: $label" || fail "rc $rc (want $want): $label — $(head -c 160 "$TMP/err" | tr '\n' ' ')"
}
E="$TMP/edit.jsonl"
edit_tr "$E" Edit "$R/app/util.py" 'y = 2';       stopgate 2 "review_gate, control: Edit of an uncommitted code file asks for a review" "$RG" "$E"
edit_tr "$E" MultiEdit "$R/app/util.py" 'y = 2';  stopgate 2 "review_gate: MultiEdit of the same file asks for it too" "$RG" "$E"
edit_tr "$E" MultiEdit "$R/notes.md" 'y = 2';     stopgate 0 "review_gate, control: MultiEdit of a .md asks for none" "$RG" "$E"
PERM='<uses-permission android:name="android.permission.CAMERA"/>'
edit_tr "$E" Edit "$R/app/src/main/AndroidManifest.xml" "$PERM";      stopgate 2 "security_gate, control: Edit of AndroidManifest.xml asks for a security review" "$SG" "$E"
edit_tr "$E" MultiEdit "$R/app/src/main/AndroidManifest.xml" "$PERM"; stopgate 2 "security_gate: MultiEdit of it asks for one too" "$SG" "$E"
edit_tr "$E" Edit "$R/app/util.py" 'webView.addJavascriptInterface(bridge, "app")';      stopgate 2 "security_gate, control: Edit whose TEXT is an attack surface" "$SG" "$E"
edit_tr "$E" MultiEdit "$R/app/util.py" 'webView.addJavascriptInterface(bridge, "app")'; stopgate 2 "security_gate: the same text in the SECOND edit of a MultiEdit" "$SG" "$E"
edit_tr "$E" MultiEdit "$R/app/util.py" 'y = 2';  stopgate 0 "security_gate, control: MultiEdit with no attack surface" "$SG" "$E"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
