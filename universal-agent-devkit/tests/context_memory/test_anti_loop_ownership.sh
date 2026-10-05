#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh ANTI-LOOP counts only the test runs THIS
# session made (audit G5, ported from OfficeReader's hook). build/ is shared: a red suite from
# another agent's run landed in the same tree and was counted as one of our failed fixes.
# A run sits inside the Bash window of the session that ran it (.claude/audit-gate/
# bash_write_ledger.tsv: session \t start|end \t <ts> \t <tool_use_id>); the narrowest window
# containing the XML's mtime wins. Fail-closed: no ledger, no containing window, or a tie
# between sessions → counted as ours. A background command's open window lasts until Stop.
# W1-i (2026-10-05): ANOTHER session's open window (a start with no end: a failed, backgrounded, interrupted
# command) reaches 'now' only while that session is live in the session_lock registry (live pid, a sign of life
# <= 10 min old), at most 2 h after its start; a dead one ended at its last sign of life: it no longer
# hides our red run (bin/session_authorship.open_windows).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh (the ratchet test_git_env_isolation requires it before the first git)
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${AL_KIT:-$DEVKIT_DIR}/hooks/test_evidence_gate.sh"   # AL_KIT=<devkit dir>: run the same cases against another copy (e.g. the unpatched one: RED)
TMP="$(mktemp -d)"
sleep 600 & LIVE_PID=$!; disown "$LIVE_PID" 2>/dev/null
sh -c 'exit 0' & DEAD_PID=$!; wait "$DEAD_PID" 2>/dev/null
trap 'kill "$LIVE_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

N=0
# case_ <want-exit> <name> <ledger rows: "sid kind offset uid" relative to the XML mtime, ';'-separated>
#        [registry entry: "sid live|dead|nopid <heartbeat offset from now, s>" — a session_lock registry file]
case_() {
  local want="$1" name="$2" ledger="$3" registry="${4:-}" rawfmt="${5:-}"
  N=$((N + 1)); local P="$TMP/p$N" sid="me"
  mkdir -p "$P/app/build/test-results/testDebugUnitTest" "$P/.claude/audit-gate"
  touch "$P/build.gradle"
  local X="$P/app/build/test-results/testDebugUnitTest/TEST-com.x.PaySuite.xml"
  printf '<?xml version="1.0"?>\n<testsuite name="com.x.PaySuite" tests="1" failures="1" errors="0" skipped="0">\n<testcase classname="com.x.PaySuite" name="pays"><failure message="boom">x</failure></testcase>\n</testsuite>\n' > "$X"
  python3 - "$P" "$X" "$ledger" <<'PY'
import json, os, sys, time
P, X, ledger = sys.argv[1:4]
t = time.time() - 30
os.utime(X, (t, t))
json.dump({"last_run": 0.0, "streak": {"com.x.PaySuite#pays": 1}}, open(f"{P}/.claude/audit-gate/failcycle_me.json", "w"))
if ledger != "none":
    rows = []
    for spec in filter(None, ledger.split(";")):
        sid, kind, off, uid = spec.split()
        rows.append(f"{sid}\t{kind}\t{t + float(off):.3f}\t{uid}\n")
    open(f"{P}/.claude/audit-gate/bash_write_ledger.tsv", "w").write("".join(rows))
PY
  [ -n "$rawfmt" ] && printf "$rawfmt" >> "$P/.claude/audit-gate/bash_write_ledger.tsv"   # raw bytes appended to the ledger
  if [ -n "$registry" ]; then
    git init -q "$P" 2>/dev/null; mkdir -p "$P/.git/devkit-sessions"
    python3 -I - "$P/.git/devkit-sessions" $registry "$LIVE_PID" "$DEAD_PID" <<'PY'
import json, sys, time
d, sid, kind, hb, live, dead = sys.argv[1:7]
rec = {"session_id": sid, "agent": "claude", "heartbeat": time.time() + float(hb)}
if kind != "nopid":
    rec["pid"] = int(live if kind == "live" else dead)
json.dump(rec, open(f"{d}/{sid}.json", "w"))
PY
  fi
  : > "$P/tr.jsonl"
  local rc
  python3 -c 'import json,sys; print(json.dumps({"session_id": "me", "transcript_path": sys.argv[1], "last_assistant_message": "PaySuite vẫn đỏ, tôi thử cách khác."}))' "$P/tr.jsonl" \
    | CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 RED_PROOF=0 bash "$GATE" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then ok "$name (exit $rc)"; else fail "$name: want $want, got $rc"; fi
}

case_ 0 "red run inside ANOTHER session's window only → not our failed fix" "other start -5 u1;other end 5 u1"
case_ 2 "red run inside OUR window → ANTI-LOOP" "me start -5 u1;me end 5 u1"
case_ 2 "no ledger → counted as ours (fail-closed)" "none"
case_ 2 "narrowest window wins: ours inside theirs → ours" "other start -50 u1;other end 50 u1;me start -2 u2;me end 2 u2"
case_ 0 "narrowest window wins: theirs inside ours → theirs" "me start -50 u1;me end 50 u1;other start -2 u2;other end 2 u2"
case_ 2 "tie between two sessions → ours (fail-closed)" "other start -5 u1;other end 5 u1;me start -5 u2;me end 5 u2"
case_ 2 "our background command (start, no end) is open until Stop → ours" "me start -5 u1"
case_ 2 "no window contains the run → ours (fail-closed)" "other start -500 u1;other end -400 u1"
case_ 0 "ANOTHER session's open window, session LIVE (pid alive, heartbeat 5 min old) → still not our failed fix" "other start -5 u1" "other live -300"
case_ 2 "[W1-i] another session's open window, session GONE (no registry entry) → ours (ANTI-LOOP)" "other start -500 u1"
case_ 2 "[W1-i] another session's open window, registry entry with a dead pid → ours" "other start -500 u1" "other dead -300"
case_ 2 "[W1-i] another session's open window, live pid but silent for 10+ min (its own ledger row too) → ours" "other start -700 u1" "other live -1800"
case_ 2 "[W1-i] a LIVE session's open window is 3 h old: it reaches at most 2 h after its start → ours" "other start -10800 u1" "other live -5"
# W1-i round 2: cutting a gone session's open window makes it NARROWER, and the narrowest window wins: it must never take the
# run from a wider window of OURS. "another session ran it" needs the old rule and the cut rule to agree.
case_ 2 "[W1-i] our closed 70 s window is wider than a gone session's CUT window but narrower than its open one → still ours (ANTI-LOOP)" "me start -50 m1;me end 20 m1;other start -45 o1;other start 5 o2;other end 10 o2"
case_ 2 "[W1-i] same with a registry entry whose pid is dead → ours" "me start -50 m1;me end 20 m1;other start -45 o1;other start 5 o2;other end 10 o2" "other dead -25"
case_ 0 "[W1-i] a CLOSED narrower window of another session still owns the run (unchanged)" "me start -50 m1;me end 20 m1;other start -10 o1;other end 10 o1"
# W1-i round 3: bytes that are not UTF-8 in the ledger, and a cut-windows rule that raises, must leave the OLD rule in force
# (a crash exits 1 and this hook then exits 0: ANTI-LOOP off). No gone-session window involved: only the old rule decides.
case_ 2 "[W1-i] ledger with \\xff\\xfe bytes -> still ours (ANTI-LOOP)" "me start -5 u1;me end 5 u1" "" 'x\xff\xfe\tstart\t1.0\tz\n'
case_ 2 "[W1-i] ledger with a lone \\x80 -> still ours" "me start -5 u1;me end 5 u1" "" '\x80\n'
case_ 2 "[W1-i] ledger with NUL bytes -> still ours" "me start -5 u1;me end 5 u1" "" 'a\0b\tstart\t1.0\tz\n\0\0\n'
case_ 2 "[W1-i] ledger cut inside a multi-byte character -> still ours" "me start -5 u1;me end 5 u1" "" 'other\tstart\t1.0\tcaf\xc3'
STUB="$TMP/stubkit"; mkdir -p "$STUB/hooks" "$STUB/bin"; cp "${AL_KIT:-$DEVKIT_DIR}/hooks/test_evidence_gate.sh" "$STUB/hooks/"
GATE_SAVE="$GATE"; GATE="$STUB/hooks/test_evidence_gate.sh"
printf 'def bash_windows(*a, **k):\n    raise RuntimeError("boom")\n' > "$STUB/bin/session_authorship.py"
case_ 2 "[W1-i] session_authorship.bash_windows raises -> the old rule decides, ours (ANTI-LOOP)" "me start -5 u1;me end 5 u1"
printf 'def bash_windows(*a, **k):\n    return [("not", "a", "window", "tuple")]\n' > "$STUB/bin/session_authorship.py"
case_ 2 "[W1-i] session_authorship returns malformed windows -> the old rule decides, ours" "me start -5 u1;me end 5 u1"
printf 'raise RuntimeError("import boom")\n' > "$STUB/bin/session_authorship.py"
case_ 2 "[W1-i] session_authorship fails at import (not an ImportError) -> the old rule decides, ours" "me start -5 u1;me end 5 u1"
case_ 0 "[W1-i] …and the old rule still lets ANOTHER session's closed window own the run" "other start -5 u1;other end 5 u1"
GATE="$GATE_SAVE"


[ "$FAILS" -eq 0 ] && echo "✅ test_anti_loop_ownership: all passed" || { echo "❌ test_anti_loop_ownership: $FAILS failed"; exit 1; }
