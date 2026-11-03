#!/usr/bin/env bash
# Regression test (gate wave 2, item 8, 03/11): hooks/worktree_merge_gate.sh held the Stop (exit 2, text on stderr) and let it go
# (exit 0) without one line in a log file — a wrong hold in one of the 5 app repos left nothing to diagnose afterwards.
# Now each hold and each of the three releases after a pending set was found writes ONE line to
# .claude/audit-gate/worktree_merge_gate.log (same folder as its state):
#   hold                       → `BLOCK hold N/3 …` with the pending worktree paths
#   stop_hook_active           → `release: stop_hook_active …`
#   cap (4th Stop, same set)   → `release: cap …`
#   state not saved            → `release: state not saved …`
# Behaviour stays: the same exit code, the same stderr / stdout text, and the log text never goes to them.
# Case 6 (recheck H1): a state file that is a FIFO or deep JSON reads as no state (the ordinary hold), never the fail-open exit 0.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export WORKTREE_AUTO_MERGE=0   # the HOLD logic; the automatic merge has its own tests
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/proj"; mkdir -p "$P" && G "$P" init -q -b main . && echo a > "$P/a.txt" && G "$P" add a.txt && G "$P" commit -qm init
LOG="$P/.claude/audit-gate/worktree_merge_gate.log"
sleep 1.2
TR="$TMP/tr.jsonl"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"go"}}))' > "$TR"
sleep 1.2
python3 -c 'import json,sys;print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":sys.argv[1]}}]}}))' \
  "git worktree add -b feat $TMP/wt-new" >> "$TR"
G "$P" worktree add -q -b feat "$TMP/wt-new" && echo n > "$TMP/wt-new/n.txt" && G "$TMP/wt-new" add n.txt && G "$TMP/wt-new" commit -qm new
stop() {   # stop <session> [stop_hook_active true|false]
  printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s","stop_hook_active":%s}' "$1" "$TR" "${2:-false}" \
    | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
nlines() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }
clean_streams() { ! grep -q "BLOCK hold\|release: " "$TMP/out" "$TMP/err"; }

# ── 1. hold: exit 2, stderr text as before, one BLOCK line naming the worktree ──
stop s1; rc=$?
[ "$rc" = 2 ] && grep -q "WORKTREE-MERGE GATE" "$TMP/err" && grep -q "Lần giữ 1/3" "$TMP/err" && [ ! -s "$TMP/out" ] && clean_streams \
  && ok "hold unchanged: exit 2, 'Lần giữ 1/3' on stderr, stdout empty, no log text in the streams" \
  || fail "hold changed: rc=$rc out=$(cat "$TMP/out") err=$(head -2 "$TMP/err")"
last="$(tail -1 "$LOG" 2>/dev/null)"
printf '%s' "$last" | grep -Eq '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}\] BLOCK hold 1/3 ' && printf '%s' "$last" | grep -q "wt-new" \
  && ok "the hold is logged: '[ts] BLOCK hold 1/3 …' with the pending worktree" || fail "no BLOCK line in the log: '${last}'"

# ── 2. stop_hook_active: exit 0 with the systemMessage, one release line ─────
n0="$(nlines)"
stop s1 true; rc=$?
last="$(tail -1 "$LOG" 2>/dev/null)"
[ "$rc" = 0 ] && grep -q "systemMessage" "$TMP/out" && grep -q "stop_hook_active" "$TMP/out" && [ ! -s "$TMP/err" ] && clean_streams \
  && ok "stop_hook_active unchanged: exit 0, systemMessage on stdout, stderr empty" || fail "stop_hook_active changed: rc=$rc out=$(cat "$TMP/out")"
[ "$(nlines)" = $((n0 + 1)) ] && printf '%s' "$last" | grep -q "release: stop_hook_active" \
  && ok "the stop_hook_active release is logged in one line" || fail "stop_hook_active release not logged: '${last}'"

# ── 3. cap: the 4th Stop on the same set passes, one release line ───────────
stop s2; stop s2; stop s2; n0="$(nlines)"; stop s2; rc=$?
last="$(tail -1 "$LOG" 2>/dev/null)"
[ "$rc" = 0 ] && grep -q "systemMessage" "$TMP/out" && grep -q "CHƯA về trunk" "$TMP/out" && [ ! -s "$TMP/err" ] && clean_streams \
  && ok "cap unchanged: the 4th Stop exits 0 with the systemMessage" || fail "cap changed: rc=$rc out=$(cat "$TMP/out")"
[ "$(nlines)" = $((n0 + 1)) ] && printf '%s' "$last" | grep -q "release: cap" \
  && ok "the cap release is logged in one line" || fail "cap release not logged: '${last}'"
[ "$(grep -c "BLOCK hold" "$LOG" 2>/dev/null)" = 4 ] && grep -q "BLOCK hold 3/3" "$LOG" \
  && ok "every hold before the cap is logged (s1 1/3, s2 1/3..3/3)" || fail "hold lines: $(grep "BLOCK hold" "$LOG" 2>/dev/null)"

# ── 4. state not saved: exit 0 silently as before, one release line ──────────
rm -f "$P/.claude/audit-gate/worktree_merge_gate.state" && mkdir "$P/.claude/audit-gate/worktree_merge_gate.state"   # os.replace onto a folder fails
n0="$(nlines)"
stop s3; rc=$?
last="$(tail -1 "$LOG" 2>/dev/null)"
[ "$rc" = 0 ] && [ ! -s "$TMP/out" ] && [ ! -s "$TMP/err" ] \
  && ok "state not saved unchanged: exit 0, nothing on stdout / stderr" || fail "state-not-saved changed: rc=$rc out=$(cat "$TMP/out") err=$(cat "$TMP/err")"
[ "$(nlines)" = $((n0 + 1)) ] && printf '%s' "$last" | grep -q "release: state not saved" \
  && ok "the state-not-saved release is logged in one line" || fail "state-not-saved release not logged: '${last}'"

# ── 5. G5 (review 03/11): the log path is a FIFO (an agent can write .claude/audit-gate/) ─────────────────────────────────────
# a plain open() waited for a reader until the 13 s alarm, whose fail-open exits 0: the hold was lost. Now the log opens without
# waiting, only as a regular file; anything else drops the line and the hold keeps its exit 2.
rm -rf "$P/.claude/audit-gate/worktree_merge_gate.state" "$LOG" && mkfifo "$LOG"
t0="$(python3 -c 'import time; print(time.time())')"
printf '{"session_id":"s4","hook_event_name":"Stop","transcript_path":"%s","stop_hook_active":false}' "$TR" \
  | CLAUDE_PROJECT_DIR="$P" perl -e 'alarm shift; exec @ARGV' 25 bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rc=$?
el="$(python3 -c 'import sys,time; print(round(time.time() - float(sys.argv[1]), 1))' "$t0")"
[ "$rc" = 2 ] && grep -q "WORKTREE-MERGE GATE" "$TMP/err" && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 5 else 1)' "$el" \
  && ok "FIFO log: the hold keeps exit 2 and ends in ${el}s (< 5 s), the log line is dropped" \
  || fail "FIFO log: rc=$rc after ${el}s (want 2 in < 5 s)"
[ -p "$LOG" ] && ok "  … the FIFO is left as it is (not replaced by a file)" || fail "  … the FIFO was replaced"
rm -f "$LOG"; ln -s "$TMP/elsewhere.log" "$LOG"; rm -rf "$P/.claude/audit-gate/worktree_merge_gate.state"
stop s5; rc=$?
[ "$rc" = 2 ] && [ ! -e "$TMP/elsewhere.log" ] && ok "symlinked log: the hold keeps exit 2, nothing written through the link" \
  || fail "symlinked log: rc=$rc, target written: $([ -e "$TMP/elsewhere.log" ] && echo yes || echo no)"

# ── 6. H1 (recheck 03/11): the STATE file is a FIFO / deep JSON (the same agent-writable folder) ───────────────────────────────
# A plain open() of a FIFO waited for a writer until the 13 s alarm (fail-open exit 0); json.load of '[' * 2000000 raised RecursionError (Python 3.15: a stack-size limit),
# a traceback the shell turned into exit 0. Both dropped the hold. Now an unreadable state is no state: the ordinary hold 1/3.
rm -f "$LOG"; rm -rf "$P/.claude/audit-gate/worktree_merge_gate.state"; mkfifo "$P/.claude/audit-gate/worktree_merge_gate.state"
t0="$(python3 -c 'import time; print(time.time())')"
printf '{"session_id":"s6","hook_event_name":"Stop","transcript_path":"%s","stop_hook_active":false}' "$TR" \
  | CLAUDE_PROJECT_DIR="$P" perl -e 'alarm shift; exec @ARGV' 25 bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rc=$?
el="$(python3 -c 'import sys,time; print(round(time.time() - float(sys.argv[1]), 1))' "$t0")"
[ "$rc" = 2 ] && grep -q "Lần giữ 1/3" "$TMP/err" && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 5 else 1)' "$el" \
  && ok "FIFO state: read as no state, the hold 1/3 keeps exit 2 in ${el}s (< 5 s)" \
  || fail "FIFO state: rc=$rc after ${el}s (want 2 with 'Lần giữ 1/3' in < 5 s); err: $(head -1 "$TMP/err")"
rm -rf "$P/.claude/audit-gate/worktree_merge_gate.state"
python3 -c 'import sys; open(sys.argv[1], "w").write("[" * 2000000)' "$P/.claude/audit-gate/worktree_merge_gate.state"
stop s7; rc=$?
[ "$rc" = 2 ] && grep -q "Lần giữ 1/3" "$TMP/err" && ! grep -q "Traceback" "$TMP/err" \
  && ok "deep-JSON state: read as no state (no RecursionError traceback), the hold 1/3 keeps exit 2" \
  || fail "deep-JSON state: rc=$rc (want 2 with 'Lần giữ 1/3'); err: $(grep -m1 -E 'Error|Lần giữ' "$TMP/err")"

# ── 7. H1 (review FX4 03/11): an oversized STATE file (> 1 MiB; the real one holds at most 50 sessions) is no state ─────────────
# Read whole, a GB file outran the 13 s alarm or raised MemoryError (exit 1 → shell exit 0): the hold dropped. A padded copy of a
# state already at 3/3 shows it: read, the 4th Stop is released by the cap (exit 0); ignored, it is the ordinary hold 1/3 (exit 2).
rm -rf "$P/.claude/audit-gate/worktree_merge_gate.state"
stop s8; stop s8; stop s8
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["pad"]="x"*(1<<21); json.dump(d, open(p, "w"))' \
  "$P/.claude/audit-gate/worktree_merge_gate.state"
stop s8; rc=$?
[ "$rc" = 2 ] && grep -q "Lần giữ 1/3" "$TMP/err" \
  && ok "oversized state (> 1 MiB): read as no state, the hold 1/3 keeps exit 2 (not the cap release)" \
  || fail "oversized state: rc=$rc (want 2 with 'Lần giữ 1/3'); err: $(head -1 "$TMP/err") out: $(head -c 120 "$TMP/out")"

[ "$FAILS" = 0 ] && { echo "✅ test_worktree_merge_gate_block_reason_log: all checks passed"; exit 0; }
echo "❌ test_worktree_merge_gate_block_reason_log: $FAILS check(s) failed"; exit 1
