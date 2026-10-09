#!/usr/bin/env bash
# hooks/review_timing_guard.sh handed the hook payload to its python through an environment variable (RT_INPUT="${INPUT}"). An
# Edit of a big file puts the whole new text in the payload; past the exec limit for arguments + environment (1 MiB on macOS,
# 128 KiB for one string on Linux) the shell could not start `date` or `python3` at all: "Argument list too long", the guard never
# ran and every such Edit printed two shell errors (2026-10-09 follow-up, plan docs/plans/audit-2026-10-09-followup.md step 3 item 3).
# The payload now reaches python on a file descriptor, like worktree_merge_gate.sh. A 1.3 MB payload: no shell error, and the
# guard actually reads it (it logs that the transcript it names is not there — a line only python writes).
# Only the hook runs here.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${RT_HOOK:-$DEVKIT_DIR/hooks/review_timing_guard.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

P="$TMP/proj"; mkdir -p "$P" && git -C "$P" init -q .
LOG="$P/.claude/audit-gate/review_timing_guard.log"

# payload <bytes of new_string>
payload() {
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":sys.argv[3]+"/none.jsonl","cwd":sys.argv[3],
    "hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":sys.argv[3]+"/A.kt","old_string":"a","new_string":"x"*int(sys.argv[1])}}))' "$1" "" "$P" > "$TMP/in.json"
}
run() { ( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > "$TMP/out" 2> "$TMP/err" ); RC=$?; }

# small payload: the guard reads it (control — also proves the log line this test relies on)
rm -f "$LOG"; payload 100; run
[ "$RC" = 0 ] && grep -q "transcript unreadable" "$LOG" 2>/dev/null && ok "control: a small payload is read (rc $RC, logged)" || fail "control: small payload (rc $RC): $(cat "$TMP/err") $(cat "$LOG" 2>/dev/null)"

# big payload: well past the 1 MiB exec limit of macOS and the 128 KiB single-string limit of Linux
for n in 300000 1300000; do
  rm -f "$LOG"; payload "$n"; run
  grep -qi "too long" "$TMP/err" && fail "$n bytes: shell error: $(head -c 200 "$TMP/err")" || ok "$n bytes: no 'Argument list too long'"
  [ "$RC" = 0 ] && grep -q "transcript unreadable" "$LOG" 2>/dev/null && ok "  … and the guard read the payload (rc $RC, logged)" || fail "$n bytes: the guard did not run (rc $RC); log: $(cat "$LOG" 2>/dev/null)"
done

[ "$FAILS" -eq 0 ] && echo "✅ test_review_timing_guard_big_payload: all passed" || { echo "❌ test_review_timing_guard_big_payload: $FAILS failed"; exit 1; }
