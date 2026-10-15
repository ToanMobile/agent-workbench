#!/usr/bin/env bash
# issues-bugs.md A.4 (14/10) / W1 v6 item 2: after EnterWorktree, CLAUDE_PROJECT_DIR still names the main checkout (code.claude.com docs),
# so regression_gate, proof_gate, test_evidence_gate, precode_gate and read_ledger judged a clean main and let the session's work in its
# worktree through. They now ask hooks/session_worktree.py: the worktree the session entered (its PostToolUse record), or the one the
# harness started a subagent in (its meta worktreePath). Shown on the two that are observable without a whole session:
#   - regression_gate's probe reads the matrix of the tree it would gate: main has none, the worktree has one;
#   - read_ledger writes its ledger in the tree it judges.
# A session without a record, and a forged record (another repo), keep the old answer: main.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M="$TMP/main"; W="$M/.claude/worktrees/s1"; O="$TMP/other"
for r in "$M" "$O"; do
  mkdir -p "$r/src" && git -C "$r" init -q -b main && git -C "$r" config user.email t@t && git -C "$r" config user.name t \
    && git -C "$r" config devkit.trunkMode false \
    && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$r/.gitignore" && echo 'x = 1' > "$r/src/a.py" && git -C "$r" add -A && git -C "$r" commit -qm i
done
git -C "$M" worktree add -q --detach "$W" HEAD && git -C "$O" worktree add -q --detach "$TMP/other-wt" HEAD
mkdir -p "$W/.agents" && printf '{"project":"t","rules":[{"component":"App","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-T-01","name":"t","command":"true"}]}]}\n' \
  > "$W/.agents/regression_matrix.active.json" && git -C "$W" add -A && git -C "$W" commit -qm "matrix in the worktree only"
mkdir -p "$M/.claude/audit-gate/session_worktree" && printf '%s\n' "$W" > "$M/.claude/audit-gate/session_worktree/s1"
TP="$TMP/proj/s1.jsonl"; mkdir -p "$TMP/proj/s1/subagents" && : > "$TP"
printf '{"worktreePath": "%s"}\n' "$W" > "$TMP/proj/s1/subagents/agent-a1.meta.json"

probe() {   # probe <session> <cwd>: regression_gate's state for a Stop of that session
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3]}))' "$1" "$2" "$TP" \
    | CLAUDE_PROJECT_DIR="$M" REGRESSION_GATE_PROBE=1 bash "$DEVKIT_DIR/hooks/regression_gate.sh" 2>/dev/null | tail -1
}
state() { python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("state"))' "$1" 2>/dev/null; }
s1="$(state "$(probe s1 "$W")")"; s2="$(state "$(probe s2 "$M")")"
[ "$s1" != none ] && [ -n "$s1" ] && [ "$s2" = none ] && ok "regression_gate: the session in its worktree is gated there (matrix: $s1); a session in main: main (none)" \
  || fail "regression_gate probe: entered=$s1 other=$s2"

ledger_read() {   # ledger_read <session> <cwd> <file> [agent_id]: read_ledger for one Read
  python3 -c 'import json,sys; s,cwd,f,a,tp=sys.argv[1:6]; d={"hook_event_name":"PostToolUse","session_id":s,"cwd":cwd,"transcript_path":tp,"tool_name":"Read","tool_input":{"file_path":f}}; a and d.update(agent_id=a); print(json.dumps(d))' "$1" "$2" "$3" "${4:-}" "$TP" \
    | CLAUDE_PROJECT_DIR="$M" bash "$DEVKIT_DIR/hooks/read_ledger.sh" >/dev/null 2>&1
}
ledger_read s1 "$W" "$W/src/a.py"
grep -q "$W/src/a.py" "$W/.claude/audit-gate/read_ledger.tsv" 2>/dev/null && ! grep -q "$W/src/a.py" "$M/.claude/audit-gate/read_ledger.tsv" 2>/dev/null \
  && ok "read_ledger: the entered session's read lands in its worktree's ledger (precode_gate reads the same one)" || fail "read_ledger with a record: not in the worktree's ledger"
ledger_read s2 "$M" "$M/src/a.py"
grep -q "$M/src/a.py" "$M/.claude/audit-gate/read_ledger.tsv" 2>/dev/null && ok "  … a session without a record: main's ledger, as before" || fail "read_ledger without a record"
ledger_read s9 "$W" "$W/src/a.py" a1   # a harness subagent runs in its worktree: its hook cwd is that worktree
grep -q "^s9"$'\t'"$W/src/a.py\$" "$W/.claude/audit-gate/read_ledger.tsv" 2>/dev/null && ok "  … a harness subagent in the worktree: the worktree's ledger" || fail "subagent meta not followed"   # (the session field, not any "s9" in a path: OCR2 15)
s4="$(state "$(probe s1 "$M")")"
[ "$s4" = none ] && ok "trunk mode off, the session in main: its record does not move the gates (main)" || fail "record followed from main without trunk mode: $s4"
git -C "$M" config devkit.trunkMode true; s5="$(state "$(probe s1 "$M")")"; git -C "$M" config devkit.trunkMode false
[ "$s5" != none ] && [ -n "$s5" ] && ok "  … trunk mode on: the record alone (cwd main, no worktree in the payload) moves the gates ($s5)" || fail "record-only trigger: $s5"
mkdir -p "$TMP/lone" && cp "$DEVKIT_DIR/hooks/regression_gate.sh" "$TMP/lone/"   # a gate with no session_worktree.py beside it
lone="$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":"s1","cwd":sys.argv[1],"transcript_path":sys.argv[2]}))' "$W" "$TP" \
  | CLAUDE_PROJECT_DIR="$M" REGRESSION_GATE_PROBE=1 bash "$TMP/lone/regression_gate.sh" 2>"$TMP/lone.err" | tail -1)"
grep -q "could not be resolved" "$TMP/lone.err" && [ "$(state "$lone")" = none ] && ok "a gate whose session_worktree.py is missing says so on stderr (never silent) and falls back to CLAUDE_PROJECT_DIR (main: none), although the record and cwd name the worktree" \
  || fail "missing module (state '$(state "$lone")'): $(head -c 200 "$TMP/lone.err")"   # (the fallback result is asserted too: OCR2 12)
printf '%s\n' "$TMP/other-wt" > "$M/.claude/audit-gate/session_worktree/s3"; s3="$(state "$(probe s3 "$TMP/other-wt")")"
[ "$s3" = none ] && ok "a forged record naming another repo's worktree: main, as before" || fail "forged record followed: $s3"

# R3 review P2-3 (14/10): security_gate and testsourceset_gate still judged CLAUDE_PROJECT_DIR (a clean main). security_gate's excluded() also
# drops every path holding "/.claude/", i.e. every file of a worktree under <main>/.claude/worktrees/<n>. Their state stays under main.
for n in 11 12 13 14 21 22; do printf '%s\n' "$W" > "$M/.claude/audit-gate/session_worktree/s$n"; done
mk_tp() {   # mk_tp <file> <tool> <input-json>: a one-call transcript, dated now
  python3 -c 'import json,sys,datetime; ts=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"); print(json.dumps({"type":"assistant","timestamp":ts,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":sys.argv[2],"input":json.loads(sys.argv[3])}]}}))' "$@" > "$1"
}
stop_hook() {   # stop_hook <gate> <session> <cwd> <transcript>: rc of that Stop in the session's worktree; stderr in $TMP/gate.err
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3]}))' "$2" "$3" "$4" \
    | CLAUDE_PROJECT_DIR="$M" bash "$DEVKIT_DIR/hooks/$1" >/dev/null 2>"$TMP/gate.err"
}
mk_tp "$TMP/sg1.jsonl" Write "{\"file_path\":\"$W/app/src/main/AndroidManifest.xml\",\"content\":\"<uses-permission android:name=\\\"x\\\"/>\"}"
stop_hook security_gate.sh s11 "$W" "$TMP/sg1.jsonl"; rc=$?
[ "$rc" = 2 ] && grep -q AndroidManifest "$TMP/gate.err" && ok "security_gate: a Write into the session's worktree (its path holds /.claude/) is judged, no review ran: blocks" \
  || fail "security_gate Write in the worktree: rc=$rc $(head -c 200 "$TMP/gate.err")"
mk_tp "$TMP/sg2.jsonl" Bash "{\"command\":\"sed -i s/a/b/ $W/app/src/main/AndroidManifest.xml\"}"
stop_hook security_gate.sh s12 "$W" "$TMP/sg2.jsonl"; rc=$?
[ "$rc" = 2 ] && ok "  … a shell write naming a worktree path: blocks" || fail "security_gate Bash in the worktree: rc=$rc $(head -c 200 "$TMP/gate.err")"
mk_tp "$TMP/sg3.jsonl" Write "{\"file_path\":\"$W/.claude/hooks/x.sh\",\"content\":\"apiKey = 1\"}"
stop_hook security_gate.sh s13 "$W" "$TMP/sg3.jsonl"; rc=$?
[ "$rc" = 0 ] && ok "  … the worktree's OWN .claude/ stays out of scope" || fail "security_gate judged the worktree's .claude/: rc=$rc"
mk_tp "$TMP/sg4.jsonl" Bash '{"command":"echo done"}'
mkdir -p "$W/app"; : > "$W/app/google-services.json"   # after the transcript's first timestamp: only a shell command could have written it
stop_hook security_gate.sh s14 "$W" "$TMP/sg4.jsonl"; rc=$?
[ "$rc" = 2 ] && grep -q "google-services.json (git diff" "$TMP/gate.err" && ok "  … the git-diff source reads the worktree (a file only a shell command could have written)" \
  || fail "security_gate git-diff source: rc=$rc $(head -c 200 "$TMP/gate.err")"
rm -f "$W/app/google-services.json"
[ -s "$M/.claude/audit-gate/security_gate.log" ] && [ ! -e "$W/.claude/audit-gate/security_gate.log" ] \
  && ok "  … its log stays under main's .claude/audit-gate" || fail "security_gate log is not under main only"

printf '#!/bin/sh\npwd >> "%s/compiled"\nexit 0\n' "$TMP" > "$W/gradlew"; chmod +x "$W/gradlew"
mkdir -p "$W/app/src/main/java"; echo 'fun a() = 1' > "$W/app/src/main/java/Core.kt"; printf "plugins { id 'x' }\n" > "$W/app/build.gradle"
git -C "$W" add -A && git -C "$W" commit -qm "a gradle module in the worktree only"
echo 'fun a() = 2' > "$W/app/src/main/java/Core.kt"   # dirty in the worktree; main is clean and has no gradlew
mk_tp "$TMP/ts1.jsonl" Write "{\"file_path\":\"$W/app/src/main/java/Core.kt\",\"content\":\"fun a() = 2\"}"
stop_hook testsourceset_gate.sh s21 "$W" "$TMP/ts1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ "$(head -1 "$TMP/compiled" 2>/dev/null)" = "$W" ] && ok "testsourceset_gate: compiles the worktree's test source set (its dirty Kotlin), not a clean main's" \
  || fail "testsourceset_gate in the worktree: rc=$rc compiled=$(head -1 "$TMP/compiled" 2>/dev/null)"
grep -q "PASS" "$M/.claude/audit-gate/testsourceset_gate.log" 2>/dev/null && [ ! -e "$W/.claude/audit-gate/testsourceset_gate.log" ] \
  && ok "  … its state stays under main's .claude/audit-gate" || fail "testsourceset_gate state is not under main only"
[ -e "$W/.claude/audit-gate/test_run.lock" ] && ok "  … and it takes the lock of the tree it compiles (the one the regression gate holds there)" || fail "testsourceset_gate lock is not the worktree's"
git -C "$W" add -A && git -C "$W" commit -qm "Core.kt"
: > "$TMP/compiled"; echo 'fun b() = 1' > "$W/app/src/main/java/Core2.kt"; echo 'fun c() = 1' > "$W/app/src/main/java/Other.kt"; touch -t 202001010000 "$W/app/src/main/java/Other.kt"
python3 -c 'import time; n=time.time(); print("s22\tstart\t%.3f\tw1\ns22\tend\t%.3f\tw1" % (n-30, n+30))' > "$M/.claude/audit-gate/bash_write_ledger.tsv"   # written by the hooks, under main
mk_tp "$TMP/ts2.jsonl" Bash '{"command":"./codegen.sh"}'
stop_hook testsourceset_gate.sh s22 "$W" "$TMP/ts2.jsonl"; rc=$?
grep -q "SCOPE — 2 dirty file(s) → 1 written by this session: app/src/main/java/Core2.kt" "$M/.claude/audit-gate/testsourceset_gate.log" \
  && ok "  … the Bash ledger the hooks write under main scopes the files the session wrote in the worktree" \
  || fail "testsourceset_gate ledger scope: rc=$rc $(tail -2 "$M/.claude/audit-gate/testsourceset_gate.log" 2>/dev/null)"

# R3 review P3 (14/10): the hooks that write turn_class_<sid>.json (prompt_context) and bash_write_ledger.tsv still write under CLAUDE_PROJECT_DIR
# (main), but precode_gate and proof_gate judged the worktree and read them there: a file the session made with a shell command was a "blind
# edit", and the before-evidence a UI bug fix owes went unasked. They read both from main; the read ledger stays the worktree's (read_ledger).
for n in 31 32 41; do printf '%s\n' "$W" > "$M/.claude/audit-gate/session_worktree/s$n"; done
mk_tp "$TMP/pc.jsonl" Bash '{"command":"./gen.sh"}'
pre_hook() {   # pre_hook <session> <file>: rc of precode_gate for an Edit of <file> by that session in its worktree
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3],"tool_name":"Edit","tool_input":{"file_path":sys.argv[4],"old_string":"a","new_string":"b"}}))' "$1" "$W" "$TMP/pc.jsonl" "$2" \
    | CLAUDE_PROJECT_DIR="$M" bash "$DEVKIT_DIR/hooks/precode_gate.sh" >/dev/null 2>"$TMP/gate.err"
}
echo 'x = 1' > "$W/src/born.py"; echo 'x = 1' > "$W/src/lone.py"
python3 -c 'import time; n=time.time(); print("s31\tstart\t%.3f\tb1\ns31\tend\t%.3f\tb1\ns32\tstart\t%.3f\tb2\ns32\tend\t%.3f\tb2" % (n-5, n+5, n-100, n-90))' > "$M/.claude/audit-gate/bash_write_ledger.tsv"
pre_hook s31 "$W/src/born.py"; r1=$?; pre_hook s32 "$W/src/lone.py"; r2=$?
[ "$r1" = 0 ] && [ "$r2" = 2 ] && ok "precode_gate: a file born in the session's Bash window (main's ledger) is no blind edit; one born in nobody's window is" \
  || fail "precode_gate ledger: born-in-window rc=$r1 (want 0), other rc=$r2 (want 2) $(head -c 200 "$TMP/gate.err")"

mkdir -p "$W/.agents"; echo '{"profile":"android"}' > "$W/.agents/active-profile.json"
echo 'fun ok() = 1' > "$W/src/Core.kt"; git -C "$W" add -A && git -C "$W" commit -qm "a screen profile and an app source"
python3 - "$TMP/pg.jsonl" "$W" <<'PY'
import datetime, json, sys
iso = lambda s: (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=s)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
rows = [{"type": "user", "timestamp": iso(2), "message": {"role": "user", "content": "sửa lỗi UI"}},
        {"type": "assistant", "timestamp": iso(0), "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "Edit", "input": {"file_path": sys.argv[2] + "/src/Core.kt"}}]}}]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
echo "// edit" >> "$W/src/Core.kt"
python3 -c 'import json,sys,time; print(json.dumps({"ts":time.time(),"intents":["BUG_FIX","UI_INTERACTION"]}))' > "$M/.claude/audit-gate/turn_class_s41.json"   # where prompt_context writes it
python3 -I - "$DEVKIT_DIR/bin" "$W" <<'PY'
import json, os, sys, time
sys.path.insert(0, sys.argv[1])
import tree_fp
rp = tree_fp.receipt_path(sys.argv[2])
os.makedirs(os.path.dirname(rp), exist_ok=True)
json.dump({"exit": 0, "time": time.time() + 3600, "fingerprint": tree_fp.tree_fingerprint(sys.argv[2])}, open(rp, "w"))
PY
mkdir -p "$W/reports"; P="reports/proof-$(date +%Y%m%d-%H%M%S).png"
python3 -c 'import os,struct,sys,zlib
c=lambda t,d: struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
open(sys.argv[1],"wb").write(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",1,1,8,2,0,0,0))+c(b"IDAT",os.urandom(20000))+c(b"IEND",b""))' "$W/$P"
python3 -c 'import json,sys; print(json.dumps({"session_id":"s41","hook_event_name":"Stop","cwd":sys.argv[1],"transcript_path":sys.argv[2],"last_assistant_message":sys.argv[3],"stop_hook_active":False}))' "$W" "$TMP/pg.jsonl" "XONG
Đã fix lỗi.
Gate exit 0
Ảnh $P
1. Đã fix gì: abc
2. Chặn bug cũ: abc
3. Nguy cơ bug mới: abc
4. An toàn mã nguồn: abc" | CLAUDE_PROJECT_DIR="$M" bash "$DEVKIT_DIR/hooks/proof_gate.sh" >/dev/null 2>"$TMP/gate.err"; rc=$?
[ "$rc" = 2 ] && grep -q "before-" "$TMP/gate.err" && ok "proof_gate: the turn class prompt_context wrote under main is read - a UI bug fix in the worktree owes its before-evidence" \
  || fail "proof_gate turn_class: rc=$rc (want 2, before-evidence asked) $(head -c 300 "$TMP/gate.err")"

# OCR 11 / 15 (14/10): test_evidence_gate and post-fix-gate (through regression_gate) read bash_write_ledger.tsv under the tree they judge, but
# bash_write_ledger.sh writes it under CLAUDE_PROJECT_DIR (main). A session in its worktree saw no window at all: another session's red XML
# was counted as its failed fix (ANTI-LOOP), and an existing test it never touched blocked it. Fail closed, not a bypass. Both read the
# ledger from main now, as precode_gate and testsourceset_gate already did.
M2="$TMP/main2"; W2="$M2/.claude/worktrees/s61"
mkdir -p "$M2/src/test" "$M2/.agents" && git -C "$M2" init -q -b main && git -C "$M2" config user.email t@t && git -C "$M2" config user.name t \
  && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$M2/.gitignore" && echo "fun ok() = 1" > "$M2/src/Core.kt" && echo "assert(true)" > "$M2/src/test/CoreTest.kt" \
  && printf '{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt","src/test/*.kt"],"mandatory_regression_tests":[{"id":"REG-X","name":"core","command":"env | grep -c ^DEVKIT_LEDGER_ROOT= > %s/suite_env_leak; true"}]}]}\n' "$TMP" \
    > "$M2/.agents/regression_matrix.active.json" && git -C "$M2" add -A && git -C "$M2" commit -qm i
git -C "$M2" worktree add -q --detach "$W2" HEAD
mkdir -p "$M2/.claude/audit-gate/session_worktree"; for n in 61 62 63 64; do printf '%s\n' "$W2" > "$M2/.claude/audit-gate/session_worktree/s$n"; done
ledger_main() {   # ledger_main <session> <start offset s> <end offset s> [<session> <start> <end>]...: Bash windows, written where bash_write_ledger.sh writes them (main)
  python3 -I - "$M2/.claude/audit-gate/bash_write_ledger.tsv" "$@" <<'PY'
import sys, time
now, a = time.time(), sys.argv[2:]
with open(sys.argv[1], "w") as fh:
    for i in range(0, len(a), 3):
        fh.write("%s\tstart\t%.3f\tw%d\n%s\tend\t%.3f\tw%d\n" % (a[i], now + float(a[i + 1]), i, a[i], now + float(a[i + 2]), i))
PY
}

# 11: a red suite run inside ANOTHER session's window is not this session's failed fix; one inside its own window still is.
XML="$W2/app/build/test-results/testDebugUnitTest/TEST-com.x.PaySuite.xml"; mkdir -p "$(dirname "$XML")"; : > "$W2/build.gradle"
printf '<?xml version="1.0"?>\n<testsuite name="com.x.PaySuite" tests="1" failures="1" errors="0" skipped="0">\n<testcase classname="com.x.PaySuite" name="pays"><failure message="boom">x</failure></testcase>\n</testsuite>\n' > "$XML"
python3 -I -c 'import os,sys,time; t=time.time()-30; os.utime(sys.argv[1], (t, t))' "$XML"
evidence_hook() {   # evidence_hook <session>: rc of test_evidence_gate for that session's Stop in its worktree, one failed fix of the suite already counted
  for d in "$W2" "$M2"; do mkdir -p "$d/.claude/audit-gate"; printf '{"last_run": 0.0, "streak": {"com.x.PaySuite#pays": 1}}\n' > "$d/.claude/audit-gate/failcycle_$1.json"; done
  : > "$TMP/te.jsonl"
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3],"last_assistant_message":"PaySuite vẫn đỏ, tôi thử cách khác."}))' "$1" "$W2" "$TMP/te.jsonl" \
    | CLAUDE_PROJECT_DIR="$M2" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 RED_PROOF=0 bash "$DEVKIT_DIR/hooks/test_evidence_gate.sh" >/dev/null 2>"$TMP/gate.err"
}
ledger_main s-other -35 -25; evidence_hook s61; rc=$?
[ "$rc" = 0 ] && ok "test_evidence_gate: a red XML in the worktree inside another session's window (main's ledger) is not this session's failed fix" \
  || fail "test_evidence_gate ledger: another session's window, rc=$rc (want 0) $(head -c 300 "$TMP/gate.err")"
ledger_main s62 -35 -25; evidence_hook s62; rc=$?
[ "$rc" = 2 ] && ok "  … inside this session's own window it still counts (ANTI-LOOP)" || fail "test_evidence_gate own window: rc=$rc (want 2) $(head -c 300 "$TMP/gate.err")"

# 15: an existing test changed inside ANOTHER session's window is that session's (a warning); outside every window nothing says whose it is (a block).
echo "fun ok() = 2" > "$W2/src/Core.kt"; echo "// weakened" > "$W2/src/test/CoreTest.kt"
python3 -I - "$W2" "$TMP/y63.jsonl" <<'PY'
import json, os, sys, time
repo, tp = sys.argv[1:3]
now = time.time()
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))
os.utime(os.path.join(repo, "src/test/CoreTest.kt"), (now - 300, now - 300))
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in [
    {"type": "user", "timestamp": iso(now - 600), "message": {"role": "user", "content": "fix it"}},
    {"type": "assistant", "timestamp": iso(now - 590), "message": {"content": [
        {"type": "tool_use", "id": "m1", "name": "Bash", "input": {"command": "git status"}},
        {"type": "tool_use", "id": "e0", "name": "Edit", "input": {"file_path": os.path.join(repo, "src/Core.kt"), "old_string": "1", "new_string": "2"}}]}}]))
PY
regression_stop() {   # regression_stop <session>: regression_gate's Stop in the session's worktree; stdout in $TMP/out, stderr in $TMP/err
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3]}))' "$1" "$W2" "$TMP/y63.jsonl" \
    | CLAUDE_PROJECT_DIR="$M2" bash "$DEVKIT_DIR/hooks/regression_gate.sh" >"$TMP/out" 2>"$TMP/err"
}
ledger_main s-x -305 -295 s63 -590 -589; regression_stop s63; rc=$?
[ "$rc" = 0 ] && grep -q systemMessage "$TMP/out" && grep -q "src/test/CoreTest.kt" "$TMP/out" \
  && ok "regression_gate: a test changed in the worktree inside another session's window (main's ledger): stop allowed, the warning names the file" \
  || fail "regression_gate ledger: another session's window, rc=$rc (want 0 and a warning) out='$(head -c 300 "$TMP/out")' err='$(head -c 300 "$TMP/err")'"
[ "$(cat "$TMP/suite_env_leak" 2>/dev/null)" = 0 ] \
  && ok "  … the suite it ran did not inherit the ledger root (a gate nested in a kit test judges its own ledger)" \
  || fail "regression_gate suite env: DEVKIT_LEDGER_ROOT leaked into the suites (count='$(cat "$TMP/suite_env_leak" 2>/dev/null)', want 0)"
echo "fun ok() = 3" > "$W2/src/Core.kt"   # a new tree: the first stop's verdict is not reused
ledger_main s64 -590 -589; regression_stop s64; rc=$?
[ "$rc" = 2 ] && grep -q "src/test/CoreTest.kt" "$TMP/err" && ok "  … with no window around the change it stays blocked (nobody else's)" \
  || fail "regression_gate no window: rc=$rc (want 2) err='$(head -c 300 "$TMP/err")'"

echo
[ "$FAILS" -eq 0 ] && { echo "test_gates_follow_session_worktree: PASS"; exit 0; } || { echo "test_gates_follow_session_worktree: FAIL ($FAILS)"; exit 1; }
