#!/usr/bin/env bash
# Regression test: an OPEN Bash window (a `start` row with no `end`) of a session that is gone must not
# cover later changes (W1-i, 2026-10-05).
#
# hooks/bash_write_ledger.sh writes `start` before every Bash call and `end` after it, but a command that
# FAILED (the harness fires PostToolUseFailure, not PostToolUse), one run in the background (no `end` by
# design), an interrupted one or a killed session leaves a `start` with no `end`. bin/session_authorship.py
# used to stretch such a window to "now": a window of a dead session 3 days old covered every later change,
# so post-fix-gate read a person's edit of an EXISTING test as "another session's" and only warned (exit 0)
# instead of blocking (exit 2). Live ledgers: 4.6-6.7 % of the starts are open, the oldest 121 h.
# Rule now (session_authorship.open_windows): the judged session's own windows stay open until now; another
# session's open window reaches now only while that session is LIVE (a session_lock registry entry in
# <git common dir>/devkit-sessions with a live pid and a sign of life, heartbeat or ledger row, <= 10 min old),
# and then at most 2 h after its start; a dead session's window ended at its last sign of life.
#
# Round 2 (review rv-i): cutting a window only NARROWS it, and the narrowest window wins, so the cut must not change who owns
# a file in the LENIENT-for-the-other-session direction (post-fix-gate, ran_here: block_owner says "another session" only when the
# old rule and the cut rule both do) nor in the CREDIT direction (ran_in_my_window, own and foreign ledger: the old rule). A pid
# in the registry past the OS range (or any garbage the agent writes there) is "not live", never a crash of the gate.
#
# Each case builds a fake repo with an existing test changed by a person at a known time and runs
# post-fix-gate --run-tests --session s-me; the exit code is the decision (2 = blocked, 0 = a warning only).
# Cases marked [CHANGE] are the ONLY decisions that differ from the kit before the fix (they are red there).
#   LSW_KIT=<devkit dir>   run the same cases against another copy of the kit (e.g. the unpatched one: RED).
# bash 3.2 compatible wrapper; stdlib python3 only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${LSW_KIT:-$DEVKIT_DIR}"
GATE="$KIT/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
sleep 600 & LIVE_PID=$!; disown "$LIVE_PID" 2>/dev/null
sh -c 'exit 0' & DEAD_PID=$!; wait "$DEAD_PID" 2>/dev/null
trap 'kill "$LIVE_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; N=0

# --- fixtures -----------------------------------------------------------------------------------------
new_repo() {   # an existing test changed in the working tree, nothing committed
  rm -rf "$TMP/repo" && mkdir -p "$TMP/repo/src/test"; cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt; echo "assert(true)" > src/test/CoreTest.kt
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt && echo "// weakened" > src/test/CoreTest.kt
}
# row <sid> <start|end> <offset seconds from now> <tool_use_id>
row() { mkdir -p .claude/audit-gate; python3 -I -c 'import sys,time; print("%s\t%s\t%.3f\t%s" % (sys.argv[1], sys.argv[2], time.time()+float(sys.argv[3]), sys.argv[4]))' "$@" >> .claude/audit-gate/bash_write_ledger.tsv; }
# reg <sid> <pid|none> <heartbeat offset> — a session_lock registry entry (the git common dir is .git here)
reg() { mkdir -p .git/devkit-sessions; python3 -I -c '
import json, sys, time
sid, pid, off = sys.argv[1], sys.argv[2], float(sys.argv[3])
d = {"session_id": sid, "agent": "claude", "started": time.time() - 7200, "heartbeat": time.time() + off, "status": "working"}
if pid != "none":
    d["pid"] = int(pid)
json.dump(d, open(".git/devkit-sessions/%s.json" % sid, "w"))' "$@"; }
set_mtime() { python3 -I -c 'import os,sys,time; t=time.time()+float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$2"; }
me_session() { python3 -I - "$TMP/me.jsonl" <<'PY'
import json, sys, time
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))
now = time.time()
recs = [{"type": "user", "sessionId": "s-me", "timestamp": iso(now - 600), "message": {"role": "user", "content": "fix it"}},
        {"type": "assistant", "sessionId": "s-me", "timestamp": iso(now - 590), "message": {"content": [
            {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "git status"}}]}}]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in recs))
PY
}
decide() {   # decide <name> <want exit> — run the gate on the fake repo as session s-me
  local name="$1" want="$2" rc
  N=$((N + 1)); me_session
  CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --session s-me --transcript "$TMP/me.jsonl" >"$TMP/out.txt" 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then echo "✔ $name: exit $rc"; else echo "✖ $name: exit $rc, expected $want"; FAILS=$((FAILS + 1)); fi
}
TESTF=src/test/CoreTest.kt

# --- decisions that must NOT change (green before and after the fix) -------------------------------------
new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1
decide "S0 person edit, only my own closed window -> blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-dead start -400 d1; row s-dead end -390 d1
decide "S2 other session's CLOSED window that ended before the edit -> blocked" 2

new_repo; set_mtime $TESTF -60; row s-me start -70 m1
decide "S3 my own OPEN window holds the edit -> mine, blocked (no registry entry for me: my window is never cut)" 2

new_repo; set_mtime $TESTF -60; row s-me start -70 m1; row s-me end -50 m1
decide "S4 my own closed window holds the edit -> blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; reg s-live $LIVE_PID -300; row s-live start -400 l1
decide "LIVE other session (pid alive, heartbeat 5 min old, last sign of life BEFORE the edit) keeps its open window until now: warning only" 0

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; reg s-live $LIVE_PID -900; row s-live start -400 l1; row s-live start -250 l2; row s-live end -249 l2
decide "LIVE session, heartbeat 15 min old but a ledger row 4 min old -> still live, keeps the window" 0

new_repo; set_mtime $TESTF -20; row s-me start -590 m1; row s-me end -589 m1; reg s-live none -100; row s-live start -400 l1
decide "LIVE session registered without a pid, heartbeat 100 s old (limit 180 s) -> live, keeps the window" 0

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-dead start -400 d1; row s-dead start -100 d2
decide "dead session, its last sign of life (-100) is after the edit (-120): its window reached it -> warning only" 0

new_repo
decide "no ledger at all -> a person's edit blocks" 2
new_repo; mkdir -p .claude/audit-gate; : > .claude/audit-gate/bash_write_ledger.tsv; set_mtime $TESTF -120
decide "empty ledger -> blocked" 2

# --- the decisions the fix changes: an open window of a session that is gone no longer covers later edits ---
new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-dead start -400 d1
decide "S1 [CHANGE] dead session, open window, no registry entry -> blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; reg s-dead $DEAD_PID -300; row s-dead start -400 d1
decide "S1b [CHANGE] registry entry whose pid is gone -> dead, blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; reg s-idle $LIVE_PID -1800; row s-idle start -2000 i1
decide "S1c [CHANGE] pid alive but no sign of life for 30 min -> not live, blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-dead start -400 d1; row s-dead start -300 d2; row s-dead end -200 d2
decide "S1h [CHANGE] dead session, its last sign of life (-200) is before the edit (-120): the window ended there -> blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; reg s-live $LIVE_PID -5; row s-live start -10800 l1
decide "S1d [CHANGE] live session, open window 3 h old: reaches at most 2 h after its start -> blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-dead start -400 d1; row s-dead start 3600 d2
decide "S1e [CHANGE] future-dated row of a dead session is no sign of life -> blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-dead start -400 d1
printf 'garbage line\ns-x\tstart\tnot-a-number\tz\ns-dead\tstart\t17911' >> .claude/audit-gate/bash_write_ledger.tsv
decide "S1f [CHANGE] corrupt and truncated ledger lines are skipped, the dead window is still cut -> blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row ../decoy start -400 d1; mkdir -p .git/devkit-sessions
python3 -I -c 'import json,sys,time; json.dump({"session_id": "../decoy", "pid": int(sys.argv[1]), "heartbeat": time.time()}, open(".git/decoy.json", "w"))' "$LIVE_PID"
decide "S1g [CHANGE] a session id that points outside the registry directory is never read as live -> blocked" 2

# --- round 2: a cut window must never take a file from a WIDER window of mine (decisions that must NOT change) --------
new_repo; set_mtime $TESTF -120; row s-me start -180 m1; row s-me end -30 m1; row s-dead start -200 d1; row s-dead start -105 d2; row s-dead end -100 d2
decide "D1 my closed window [-180,-30] holds the edit; a gone session's open window cut to [-200,-100] is narrower -> still mine, blocked" 2

new_repo; set_mtime $TESTF -120; row s-me start -180 m1; row s-me end -30 m1; reg s-dead $DEAD_PID -100; row s-dead start -200 d1; row s-dead start -105 d2; row s-dead end -100 d2
decide "D2 same, the gone session has a registry entry with a dead pid -> still mine, blocked" 2

new_repo; set_mtime $TESTF -1000; row s-me start -1700 m1; row s-me end -30 m1; reg s-idle $LIVE_PID -900; row s-idle start -1800 i1; row s-idle start -905 i2; row s-idle end -900 i2
decide "D3 same, a silent session (live pid, 15 min without a sign of life) -> still mine, blocked" 2

new_repo; set_mtime $TESTF -120; row s-dead start -400 d1; row s-me start -300 m1; row s-dead start -105 d2; row s-dead end -100 d2
decide "D4 my own OPEN window [-300,now] holds the edit; the gone session's open window cut narrower -> still mine, blocked" 2

# --- round 2: a registry the agent can write must not crash the gate (exit 1 + traceback was read as a pass by regression_gate) ---
new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-x start -400 x1; mkdir -p .git/devkit-sessions
python3 -I -c 'import json,time; json.dump({"session_id": "s-x", "pid": 2147483648, "heartbeat": time.time()}, open(".git/devkit-sessions/s-x.json", "w"))'
decide "OVF registry pid 2147483648 (past the OS range) is no live session, no crash -> blocked" 2
new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-x start 3600 x1; mkdir -p .git/devkit-sessions
python3 -I -c 'import json,time; json.dump({"session_id": "s-x", "pid": 2147483648, "heartbeat": time.time()}, open(".git/devkit-sessions/s-x.json", "w"))'
decide "OVF2 the same with a future-dated window -> blocked" 2

# --- round 3: bytes that are not UTF-8 in the ledger (anyone can append them) must neither crash the gate nor change a decision ---
# A crash exits 1; regression_gate.sh reads a crash as "no verdict" and lets the turn through.
badbytes() {   # badbytes <label> <printf format appended to the ledger, no trailing newline added>
  new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-dead start -400 d1
  printf "$2" >> .claude/audit-gate/bash_write_ledger.tsv
  decide "BYTES $1 in the ledger: no crash, the gone session's open window is still cut -> blocked" 2
}
badbytes "\\xff\\xfe line" 'x\xff\xfe\tstart\t1.0\tz\n'
badbytes "a lone \\x80" '\x80\n'
badbytes "NUL bytes" 'a\0b\tstart\t1.0\tz\n\0\0\n'
badbytes "a line cut inside a multi-byte character" 's-dead\tstart\t1.0\tcaf\xc3'
new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1
decide "BYTES none, same scenario: blocked (control)" 2
# the cut-windows rule failing for ANY reason falls back to the old rule, never to a crash (a kit copy whose
# bash_windows raises when it is given a session; the old call, with no session, is untouched)
KITX="$TMP/kitx"; rm -rf "$KITX"; cp -R "$KIT" "$KITX"
printf '\n_orig_bash_windows = bash_windows\ndef bash_windows(project, me=None):\n    if me is not None:\n        raise RuntimeError("boom")\n    return _orig_bash_windows(project)\n' >> "$KITX/bin/session_authorship.py"
GATE_SAVE="$GATE"; GATE="$KITX/bin/post-fix-gate.py"
new_repo; set_mtime $TESTF -120; row s-me start -590 m1; row s-me end -589 m1; row s-dead start -400 d1
decide "FALLBACK the cut rule raises inside post-fix-gate -> the old rule decides: no crash, blocked/warned as before (no live window of mine: other = exit 0)" 0
new_repo; set_mtime $TESTF -120; row s-me start -180 m1; row s-me end -30 m1; row s-dead start -200 d1
decide "FALLBACK the same, a wider window of mine holds the edit -> mine, blocked" 2
GATE="$GATE_SAVE"

# --- round 2, CREDIT direction: another session's GREEN XML in ANOTHER project must not back my pass claim ---------------
# The foreign project F holds a green XML written 5 s ago; its ledger has one open window of a session `fo` (a failed or
# backgrounded test run, nothing after it: gone, or silent past 10 min). My transcript cat-s the XML and I have a window that
# holds its mtime (A: my own open window; B: a closed 10-minute one; C: A with the gone session's window in MY ledger). The narrower window of `fo` owns the XML under the old
# rule, so the claim is not backed (exit 2); cutting `fo`'s window handed the XML to me (exit 0).
credit() {   # credit <name> <A|B> <want exit>
  local name="$1" v="$2" want="$3" rc d="$TMP/credit_$2"
  N=$((N + 1)); rm -rf "$d"; mkdir -p "$d/p" "$d/f/app/build/test-results/testDebugUnitTest" "$d/f/app/src/main/java"
  : > "$d/p/gradlew"; : > "$d/f/gradlew"; printf 'class A\n' > "$d/f/app/src/main/java/A.kt"
  local x="$d/f/app/build/test-results/testDebugUnitTest/TEST-GreenSuite.xml"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="com.example.GreenSuite" tests="13" failures="0" errors="0" skipped="0">\n  <testcase classname="com.example.GreenSuite" name="doesSomething"/>\n</testsuite>\n' > "$x"
  python3 -I - "$d" "$x" "$v" <<'PY'
import json, os, sys, time
d, x, v = sys.argv[1:4]
now = time.time()
os.utime(x, (now - 5, now - 5))
os.makedirs(d + "/p/.claude/audit-gate"); os.makedirs(d + "/f/.claude/audit-gate")
mine = "s-me\tstart\t%.3f\tm1\n" % (now - 600) if v != "B" else "s-me\tstart\t%.3f\tm1\ns-me\tend\t%.3f\tm1\n" % (now - 600, now - 1)
if v == "C":   # the gone session's open window is in MY ledger, the foreign project has none
    mine += "s-fo\tstart\t%.3f\tf1\n" % (now - 60)
else:
    open(d + "/f/.claude/audit-gate/bash_write_ledger.tsv", "w").write("s-fo\tstart\t%.3f\tf1\n" % (now - 60))
open(d + "/p/.claude/audit-gate/bash_write_ledger.tsv", "w").write(mine)
start = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now - 900))
with open(d + "/tr.jsonl", "w") as fh:
    fh.write(json.dumps({"timestamp": start, "message": {"content": [{"type": "tool_use", "id": "b1", "name": "Bash", "input": {"command": "cat " + x}}]}}) + "\n")
    fh.write(json.dumps({"timestamp": start, "message": {"content": [{"type": "tool_result", "tool_use_id": "b1", "content": "ok"}]}}) + "\n")
PY
  python3 -I -c 'import json,sys; print(json.dumps({"session_id": "s-me", "transcript_path": sys.argv[1], "last_assistant_message": "JUnit XML in the other project shows 13/13 tests passed, 0 failures."}))' "$d/tr.jsonl" \
    | CLAUDE_PROJECT_DIR="$d/p" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 RED_PROOF=0 bash "$KIT/hooks/test_evidence_gate.sh" >"$d/out.txt" 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then echo "✔ $name: exit $rc"; else echo "✖ $name: exit $rc, expected $want"; FAILS=$((FAILS + 1)); fi
}
credit "CREDIT-A foreign green XML, my own open window vs a gone session's open window there -> not my run, claim NOT backed" A 2
credit "CREDIT-B foreign green XML, my closed 10-minute window vs a gone session's open window there -> claim NOT backed" B 2
credit "CREDIT-C the gone session's open window is in MY own ledger (my open window is wider) -> not my run, claim NOT backed" C 2

# --- library level: who may be cut, and what the old callers still get ---------------------------------------
N=$((N + 1))
python3 -I - "$KIT" "$TMP/repo" "$LIVE_PID" <<'PY' && echo "✔ library table (me exempt, me=None keeps the old rule, overlap, session ids)" || { echo "✖ library table"; FAILS=$((FAILS + 1)); }
import json, os, subprocess, sys, time
kit, repo, live = sys.argv[1], sys.argv[2], int(sys.argv[3])
sys.path.insert(0, os.path.join(kit, "bin"))
import session_authorship as sa
os.chdir(repo)
now = time.time()
def led(*rows):
    os.makedirs(".claude/audit-gate", exist_ok=True)
    open(".claude/audit-gate/bash_write_ledger.tsv", "w").write("".join("%s\t%s\t%.3f\t%s\n" % (s, k, now + o, t) for s, k, o, t in rows))
def reg(sid, pid, hb):
    os.makedirs(".git/devkit-sessions", exist_ok=True)
    json.dump({"session_id": sid, "pid": pid, "heartbeat": now + hb}, open(".git/devkit-sessions/%s.json" % sid, "w"))
for f in os.listdir(".git/devkit-sessions") if os.path.isdir(".git/devkit-sessions") else []:
    os.remove(os.path.join(".git/devkit-sessions", f))
bad = []
def check(name, ok):
    if not ok:
        bad.append(name)
        print("   FAIL", name)
near = lambda a, b: abs(a - b) < 5
# 1. the judged session's own open window is never cut, with or without a registry entry
led(("me", "start", -500, "m1"), ("dead", "start", -400, "d1"))
w = {s: (a, b) for a, b, s in sa.bash_windows(repo, "me")}
check("me: own open window reaches now", near(w["me"][1], time.time()))
check("dead: ends at its start (no later sign of life)", near(w["dead"][1], now - 400))
# 2. me=None is the old rule for every caller that does not pass a session (testsourceset_gate, wrote_any)
w = {s: (a, b) for a, b, s in sa.bash_windows(repo)}
check("me=None: every open window reaches now", near(w["me"][1], time.time()) and near(w["dead"][1], time.time()))
# 3. a live session reaches now, capped at start + 2 h
led(("live", "start", -400, "l1"), ("old", "start", -10800, "o1"))
reg("live", live, -5); reg("old", live, -5)
w = {s: (a, b) for a, b, s in sa.bash_windows(repo, "me")}
check("live: reaches now", near(w["live"][1], time.time()))
check("live but 3 h old: ends 2 h after its start", near(w["old"][1], now - 10800 + sa.OPEN_MAX_AGE_S))
# 4. narrowest wins as before: a dead session's cut window does not beat a narrower closed one, and ties stay ties
led(("dead", "start", -100, "d1"), ("dead", "start", -50, "d2"), ("dead", "end", -20, "d2"), ("me", "start", -90, "m1"), ("me", "end", -60, "m1"))
wins = sa.bash_windows(repo, "me")
check("dead window ends at its last sign of life (-20)", any(s == "dead" and near(b, now - 20) and near(a, now - 100) for a, b, s in wins))
check("mtime -70: my 30 s window is narrower than the dead one's 80 s", sa.window_owner(now - 70, wins) == "me")
check("mtime -10: after the dead session's last sign of life, nobody", sa.window_owner(now - 10, wins) is None)
# 5. empty / odd session ids and a missing ledger
led(("", "start", -300, "e1"))
check("empty session id: dead, ends at start", all(near(b, now - 300) for a, b, s in sa.bash_windows(repo, "me") if s == ""))
os.remove(".claude/audit-gate/bash_write_ledger.tsv")
check("missing ledger: no windows", sa.bash_windows(repo, "me") == [])
# 6. registry directory missing altogether (not a git repo): everybody else is dead, I am not
import tempfile
nogit = tempfile.mkdtemp()
os.makedirs(nogit + "/.claude/audit-gate")
open(nogit + "/.claude/audit-gate/bash_write_ledger.tsv", "w").write("me\tstart\t%.3f\tm1\nx\tstart\t%.3f\tx1\n" % (now - 50, now - 40))
w = {s: b for a, b, s in sa.bash_windows(nogit, "me")}
check("no git dir: me open until now, other cut at its start", near(w["me"], time.time()) and near(w["x"], now - 40))
# 7. block_owner: "another session" only when the old rule and the cut rule both say it (rv-i D1-D4, S1, S1h, A3)
def owner(rows, mt=-120):
    led(*rows)
    return sa.block_owner(now + mt, sa.bash_windows(repo), sa.bash_windows(repo, "me"), "me")
for f in os.listdir(".git/devkit-sessions"):
    os.remove(os.path.join(".git/devkit-sessions", f))
check("D1 mine stays mine", owner([("me", "start", -180, "m1"), ("me", "end", -30, "m1"), ("dead", "start", -200, "d1"), ("dead", "start", -105, "d2"), ("dead", "end", -100, "d2")]) == "me")
check("D4 my open window stays mine", owner([("dead", "start", -400, "d1"), ("me", "start", -300, "m1"), ("dead", "start", -105, "d2"), ("dead", "end", -100, "d2")]) == "me")
check("S1 a gone session's open window hides nothing (None)", owner([("me", "start", -590, "m1"), ("me", "end", -589, "m1"), ("dead", "start", -400, "d1")]) is None)
check("S1h its last sign of life before the change (None)", owner([("dead", "start", -400, "d1"), ("dead", "start", -300, "d2"), ("dead", "end", -200, "d2")]) is None)
check("A3 a CLOSED window of another session still owns (narrower than mine)", owner([("me", "start", -200, "m1"), ("me", "end", -50, "m1"), ("o", "start", -130, "o1"), ("o", "end", -110, "o1")]) == "o")
check("a gone session's cut window still owns when no window of mine holds the change", owner([("dead", "start", -400, "d1"), ("dead", "start", -100, "d2")]) == "dead")
check("a tie in the old rule stays a tie", owner([("a", "start", -200, "a1"), ("a", "end", -100, "a1"), ("b", "start", -200, "b1"), ("b", "end", -100, "b1")]) == "")
# 8. a registry pid that is not a pid, and a registry the JSON parser cannot take: not live, never an exception
os.makedirs(".git/devkit-sessions", exist_ok=True)
for pid in [2**31, 2**70, -1, 1, "123", 1.5, True, [1], {"a": 1}, (1 << 22) + 1, None, 0, live]:
    led(("o", "start", -50, "x"))
    json.dump({"session_id": "o", "pid": pid, "heartbeat": now}, open(".git/devkit-sessions/o.json", "w"))
    try:
        end = {s: b for a, b, s in sa.bash_windows(repo, "me")}["o"]
    except Exception as e:                      # the whole point: no crash
        check("pid %r: no exception (%s)" % (pid, type(e).__name__), False)
        continue
    isl = near(end, time.time())
    check("pid %r: %s" % (pid, "live (no pid / a live pid)" if pid in (None, 0, live) else "not live"), isl == (pid in (None, 0, live)))
open(".git/devkit-sessions/o.json", "w").write("[" * 200000)
try:
    end = {s: b for a, b, s in sa.bash_windows(repo, "me")}["o"]
    check("a registry nested 200000 deep: not live", near(end, now - 50))
except Exception as e:
    check("a registry nested 200000 deep: no exception (%s)" % type(e).__name__, False)
sys.exit(1 if bad else 0)
PY

echo
if [ "$FAILS" -eq 0 ]; then echo "✅ test_ledger_stale_window: $N checks passed"; else echo "❌ test_ledger_stale_window: $FAILS of $N failed"; exit 1; fi
