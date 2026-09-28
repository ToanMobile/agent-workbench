#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test_proof_gate_turn.sh — which Bash calls of the turn proof_gate.sh (Stop hook) reads as a push.
#
# A push is a real `git push` command, not the words in a quoted heredoc body that writes a
# file, a quoted string, or a multi-line commit message (2026-09-28: a turn that wrote a test
# containing `git push -q -u origin main` was asked for the 4-item handover report). One
# classifier (devkit_harness.git_writes) serves proof_gate and work_in_progress (regression_gate,
# review_gate), so both hooks read the same turn the same way.
#
# Usage: bash hooks/tests/test_proof_gate_turn.sh   Exit 0 = all hold. bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/proof_gate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/proofturn.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

REPO="$TMP/repo"; mkdir -p "$REPO/src" "$REPO/.agents" "$REPO/reports"
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt && echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.claude/audit-gate/\n' > .gitignore
  git add -A && git commit -qm init )
TR="$TMP/transcript.jsonl"
N=0
# A new turn: the user's prompt 1 s ago. Tool calls of the turn are appended after it.
turn_start() { sleep 1; N=$((N + 1)); python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X"}}))' > "$TR"; }
tool() { # Bash <command>
  python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":sys.argv[1],"input":{"command":sys.argv[2]}}]}}))' "$1" "$2" >> "$TR"; }
stop() { # <reply>   (one session per turn)
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "$1" "pt-$N" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

# ── 1a. proof_gate: only a real `git push` makes the turn a handover ─────────────
echo "proof_gate.sh — push detection"
NL='
'
for cmd in "cat > tests/t.sh <<'SH'${NL}#!/bin/sh${NL}git push -q -u origin main${NL}SH" \
           "cat > notes.txt <<EOF${NL}  git push origin main${NL}EOF${NL}ls" \
           "echo 'a; git push'" \
           "grep -n \"git push\" hooks/proof_gate.sh" \
           "git commit -qm \"fix: hook${NL}${NL}git push is now read as a command only\"" \
           "python3 -c 'import sys${NL}git push = 1'"; do
  turn_start; tool Bash "$cmd"
  stop "CHƯA XONG
Còn phần B."; rc=$?
  [ "$rc" = 0 ] && ok "not a push: $(printf '%s' "$cmd" | head -1)" \
    || fail "false push (rc=$rc): $(printf '%s' "$cmd" | tr '\n' '~')"
done
for cmd in "git push origin main" "cd /x/repo && git push" "git -C /x/repo push" "git push 2>&1 | tail -2" \
           "git fetch -q; git push -q origin HEAD" "(cd /x && git push)" \
           "cat > f <<'SH'${NL}git push${NL}SH${NL}git push origin main" "bash <<'SH'${NL}git push origin main${NL}SH"; do
  turn_start; tool Bash "$cmd"
  stop "CHƯA XONG
Còn phần B."; rc=$?
  [ "$rc" = 2 ] && grep -q "4 mục" "$TMP/err" && ok "real push needs the report: $(printf '%s' "$cmd" | tr '\n' '~')" \
    || fail "real push missed (rc=$rc): $(printf '%s' "$cmd" | tr '\n' '~')"
done

# ── 1b. work_in_progress reads pushes the same way (one shared classifier) ───────
echo "work_in_progress (regression_gate, review_gate)"
wip() { # <want True|False> <label>
  got="$(python3 - "$HOOKS" "$TR" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import devkit_harness
print(devkit_harness.work_in_progress({"transcript_path": sys.argv[2],
                                       "last_assistant_message": "CHƯA XONG\nCòn phần B."}, env={}))
PY
)"
  [ "$got" = "$1" ] && ok "wip $2 -> $got" || fail "wip $2: want $1, got $got"
}
turn_start; tool Bash "cat > tests/t.sh <<'SH'${NL}git push -q -u origin main${NL}SH"; wip True "heredoc body mentioning git push"
turn_start; tool Bash "git commit -qm \"docs${NL}git push later\""; wip True "commit message line starting git push"
turn_start; tool Bash "cd /x && git push origin main"; wip False "cd && git push"
turn_start; tool Bash "git -C /x push"; wip False "git -C dir push"

echo ""
echo "proof_gate turn: ${PASS} ok, ${FAIL} failed"
[ "$FAIL" = 0 ]
