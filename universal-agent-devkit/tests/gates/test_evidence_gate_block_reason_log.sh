#!/usr/bin/env bash
# Regression test (gate wave 2, item 8, 03/11): hooks/test_evidence_gate.sh held the Stop with its once-per-session
# reminder (exit 2) and its log said only `reminder (once per session): 1` — which reminder, nobody could tell
# afterwards, so a wrong hold in one of the 5 app repos could not be diagnosed from the log.
# Now the same log line carries the reason (the fixed first line of each reminder, one line, no bug titles).
# Behaviour stays: exit 2, stdout empty, the reminder text on stderr; on a re-Stop past the cap the reason is
# still logged first, then the release (exit 0) as before.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
STOP_GATE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

P="$TMP/p"; mkdir -p "$P/src" "$P/tests"
( cd "$P" && git init -q . && git config user.email t@t && git config user.name t \
  && echo "def total(): return 1" > src/cart.py && echo "def test_total(): pass" > tests/test_cart.py \
  && git add -A && git commit -qm init )
LOG="$P/.claude/audit-gate/test_evidence_gate.log"
# A proven fix: pytest RED, a source edit, pytest GREEN.
python3 - "$P/tr.jsonl" "$P/src/cart.py" <<'PY'
import json, sys
out, src = sys.argv[1], sys.argv[2]
steps = [("Bash", {"command": "python3 -m pytest tests"}, "FAILED tests/test_cart.py::test_total\n1 failed", True),
         ("Edit", {"file_path": src, "old_string": "1", "new_string": "2"}, "ok", False),
         ("Bash", {"command": "python3 -m pytest tests"}, "1 passed in 0.01s", False)]
lines = []
for i, (name, inp, res, err) in enumerate(steps):
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": name, "input": inp}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": res, "is_error": err}]}}))
open(out, "w").write("\n".join(lines) + "\n")
PY
stop() {   # stop <session> <stop_hook_active true|false> [extra env...]
  local sid="$1" active="$2"; shift 2
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "transcript_path": sys.argv[2], "stop_hook_active": sys.argv[3] == "true",
    "last_assistant_message": "Đã fix lỗi tổng giỏ hàng, test RED→GREEN."}))' "$sid" "$P/tr.jsonl" "$active" \
    | env CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER=1 BUG_LINK_REMINDER=0 RED_PROOF=0 "$@" bash "$STOP_GATE" >"$TMP/out" 2>"$TMP/err"
}

# ── 1. the reminder hold: the log line names the reminder ────────────────────
stop s1 false; rc=$?
line="$(grep "reminder (once per session)" "$LOG" 2>/dev/null | tail -1)"
[ "$rc" = 2 ] && [ ! -s "$TMP/out" ] && grep -q "BÀI HỌC" "$TMP/err" \
  && ok "reminder hold unchanged: exit 2, stdout empty, the lesson reminder on stderr" \
  || fail "reminder hold changed: rc=$rc out=$(cat "$TMP/out") err=$(head -3 "$TMP/err")"
printf '%s' "$line" | grep -q "BÀI HỌC" \
  && ok "the log line of the hold carries its reason (the reminder's first line)" \
  || fail "no reason in the log line: '${line}'"
[ "$(grep -c "reminder (once per session)" "$LOG" 2>/dev/null)" = 1 ] && [ "$(printf '%s' "$line" | wc -l | tr -d ' ')" = 0 ] \
  && ok "one log line per hold (nightly / devkit_metrics count lines with 'reminder'): no second line" \
  || fail "the hold wrote more than one counted line: $(grep -c "reminder" "$LOG")"
grep -q "nhắc này không lặp lại" "$LOG" && fail "the whole reminder text went into the log" || ok "only the first line of the reminder is logged, not the whole text"

# ── 2. re-Stop past the cap: reason logged BEFORE the release, exit still 0 ──
stop s2 true TEST_EVIDENCE_GATE_MAX_RESTOPS=0; rc=$?
tail2="$(grep -A1 "reminder (once per session)" "$LOG" | tail -2)"
[ "$rc" = 0 ] && grep -q "THẢ Stop" "$TMP/err" \
  && ok "re-Stop past the cap: still released (exit 0, release notice on stderr)" \
  || fail "release changed: rc=$rc err=$(head -3 "$TMP/err")"
printf '%s\n' "$tail2" | head -1 | grep -q "BÀI HỌC" && printf '%s\n' "$tail2" | tail -1 | grep -q "RELEASED on re-Stop" \
  && ok "the reason line is written before the RELEASED line (logged before _guarded_exit)" \
  || fail "reason/release order in the log: ${tail2}"

[ "$FAILS" = 0 ] && { echo "✅ test_evidence_gate_block_reason_log: all checks passed"; exit 0; }
echo "❌ test_evidence_gate_block_reason_log: $FAILS check(s) failed"; exit 1
