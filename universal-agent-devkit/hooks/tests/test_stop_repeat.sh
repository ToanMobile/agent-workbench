#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test_stop_repeat.sh — repeated Stops cost nothing new and say what is missing briefly.
#
# Measured (GeelyEx2, 5 days): hooks/regression_gate.sh blocked 214 times on 92 distinct
# trees; 100 blocks were a repeat on the same content and each re-ran the suites at Stop
# (median wait 34 s, p90 181 s). hooks/proof_gate.sh blocked 45 times with long prose; 20 were
# "pushed, 4-item report missing".
#   (a) A Claude session whose previous Stop blocked on the same tree: the next Stop blocks
#       again (exit 2) without the advice, and runs nothing (v26 mục 1: no Stop runs a suite).
#   (b) Any content change (tracked edit, new or edited untracked file) is judged again: the
#       receipt of the old content does not allow it.
#   (c) proof_gate block messages: ≤ 400 characters besides the 4-line report skeleton, and
#       the skeleton itself whenever the report is missing.
#
# Usage: bash hooks/tests/test_stop_repeat.sh   Exit 0 = all hold. bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export WORKTREE_TRUNK_MODE=0   # K12 (18/10): các ca ở đây là phiên sửa thẳng main (không trunk mode); ở trunk mode Stop tại main không gate (test_regression_gate_trunk_main.sh)

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
DEVKIT_DIR="$(dirname "$HOOKS")"
RGATE="$HOOKS/regression_gate.sh"
PGATE="$HOOKS/proof_gate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/stoprepeat.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

# ── (a)/(b) regression_gate.sh: same red content → no re-run ─────────────────
# v26 mục 1: the Stop runs no suite at all; the agent's gate run (the command the block prints) writes a receipt, and the Stop reads it.
# (a) a repeat Stop on the same content costs no run and does not repeat the advice; (b) a content change is judged again: the receipt
# of the old content does not allow it.
echo "hooks/regression_gate.sh — repeat Stop on the same content"
R="$TMP/rg"; mkdir -p "$R/src" "$R/.agents"
( cd "$R" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf 'echo x >> "%s"\nexit "$(cat "%s")"\n' "$TMP/runs" "$TMP/exit" > result.sh
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-R","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init ) >/dev/null
: > "$TMP/runs"; echo 1 > "$TMP/exit"
# A Claude Code transcript: not degraded, so the per-session reuse of degraded mode never applied.
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"c-r"}' > "$TMP/claude.jsonl"
runs() { grep -c x "$TMP/runs" | tr -d ' '; }
rstop() { printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "${1:-c-r}" "$TMP/claude.jsonl" \
  | CLAUDE_PROJECT_DIR="$R" bash "$RGATE" >"$TMP/out" 2>"$TMP/err"; }
grun() { ( cd "$R" && CLAUDE_PROJECT_DIR="$R" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --scoped --brief ) >"$TMP/gate.out" 2>&1; GRC=$?; }
CURE="Không sửa test cũ để lách"

echo "fun ok() = 2" > "$R/src/Core.kt"
grun; n0="$(runs)"; rstop; rc1=$?; n1="$(runs)"; e1="$(wc -c < "$TMP/err" | tr -d ' ')"
[ "$GRC" = 1 ] && grep -q "REG-R" "$TMP/gate.out" && [ "$rc1" = 2 ] && [ "$n1" = "$n0" ] && grep -q "$CURE" "$TMP/err" \
  && ok "first Stop on red content (the gate run failed REG-R): blocks (exit 2) with the advice, runs nothing" || fail "first stop (gate=$GRC rc=$rc1 runs $n0 -> $n1 err=$(head -2 "$TMP/err"))"
rstop; rc2=$?; n2="$(runs)"; e2="$(wc -c < "$TMP/err" | tr -d ' ')"
[ "$rc2" = 2 ] && [ "$n2" = "$n1" ] && ! grep -q "$CURE" "$TMP/err" && [ "$e2" -lt "$e1" ] \
  && ok "(a) second Stop, same content: no run, still exit 2, the advice not repeated ($e1 -> $e2 bytes)" \
  || fail "(a) same content re-ran or repeated the advice (rc=$rc2 runs $n1 -> $n2 bytes $e1 -> $e2 err=$(tr '\n' '~' < "$TMP/err" | head -c 300))"
rstop; rc3=$?; n3="$(runs)"
[ "$rc3" = 0 ] && [ "$n3" = "$n1" ] && grep -q systemMessage "$TMP/out" \
  && ok "existing loop guard unchanged: 3rd Stop on one change released with a warning, no re-run" \
  || fail "loop guard changed (rc=$rc3 runs=$n3)"

echo 0 > "$TMP/exit"; echo "fun ok() = 3" > "$R/src/Core.kt"
rstop; rc=$?
[ "$rc" = 2 ] && ok "(b) tracked file edited: judged again (a new change gets its own blocks)" || fail "(b) tracked edit released by the old change's guard (rc=$rc)"
grun; rstop; rc5=$?
echo "fun t() = 1" > "$R/src/NewTest.kt"; rstop; rc=$?
[ "$GRC" = 0 ] && [ "$rc5" = 0 ] && [ "$rc" = 2 ] && ok "(b) new untracked file: the receipt of the tree before does not allow it" || fail "(b) new untracked file not judged (gate=$GRC rcs $rc5 $rc)"
grun; rstop; rc6=$?
echo "fun t() = 2" > "$R/src/NewTest.kt"; rstop; rc=$?
[ "$GRC" = 0 ] && [ "$rc6" = 0 ] && [ "$rc" = 2 ] && ok "(b) untracked file content edited: the receipt of the old content does not allow it" \
  || fail "(b) untracked content edit kept the old receipt (gate=$GRC rcs $rc6 $rc)"
rm -f "$R/src/NewTest.kt"; echo 1 > "$TMP/exit"; echo "fun ok() = 4" > "$R/src/Core.kt"
grun; n8="$(runs)"; rstop c-r; rstop c-other; rc=$?; n9="$(runs)"
[ "$rc" = 2 ] && [ "$n9" = "$n8" ] && ok "another session on the same red content: blocked too, no run" \
  || fail "another session (rc=$rc runs $n8 -> $n9)"
# ── (c) hooks/proof_gate.sh: short, actionable block messages ────────────────
echo "hooks/proof_gate.sh — block message size and report skeleton"
SKEL="1. Đã fix gì: …
2. Chặn bug cũ: …
3. Nguy cơ bug mới: …
4. An toàn mã nguồn: …"
mkrepo() { # <dir> <profile>
  mkdir -p "$1/src" "$1/.agents" "$1/reports"
  ( cd "$1" && git init -q . && git config user.email t@t && git config user.name t
    echo "fun ok() = 1" > src/Core.kt && echo "{\"profile\":\"$2\"}" > .agents/active-profile.json
    printf '.claude/audit-gate/\n' > .gitignore
    git add -A && git commit -qm init && echo "fun ok() = 2" > src/Core.kt ) >/dev/null; }
mkrepo "$TMP/pa" android; mkrepo "$TMP/pb" backend
TR="$TMP/turn.jsonl"
sleep 1
python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X"}}))' > "$TR"
REPORT="1. Đã fix: lỗi X.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
N=0
pstop() { # <repo> <reply>
  N=$((N + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "$2" "ps-$N" \
  | CLAUDE_PROJECT_DIR="$1" bash "$PGATE" >"$TMP/out" 2>"$TMP/err"; }
# measure <label>: prints "<chars without the skeleton> <skeleton present 0|1>" (characters, not bytes)
measure() { python3 - "$TMP/err" "$SKEL" <<'PY'
import sys
msg = open(sys.argv[1], encoding="utf-8").read().strip("\n")
skel = sys.argv[2]
has = skel in msg
print(len(msg.replace(skel, "")) if has else len(msg), int(has))
PY
}
check() { # <label> <want skeleton 0|1> <rc>
  set -- "$1" "$2" "$3" $(measure)
  [ "$3" = 2 ] && [ "$4" -le 400 ] && [ "$5" = "$2" ] \
    && ok "(c) $1: exit 2, $4 chars + skeleton=$5" \
    || fail "(c) $1: rc=$3 chars=$4 skeleton=$5 (want ≤400, skeleton=$2): $(head -c 600 "$TMP/err" | tr '\n' '~')"
}
pstop "$TMP/pa" "XONG
Đã sửa."; rc=$?
check "android XONG, no report/gate/image" 1 "$rc"
grep -q "4 mục" "$TMP/err" && grep -q -- "--full" "$TMP/err" && grep -q "proof-" "$TMP/err" && grep -q "ẢNH" "$TMP/err" \
  && ok "(c) android: names the report, the --full gate and the proof-….png" || fail "(c) android: a condition is not named"
pstop "$TMP/pb" "XONG
Đã sửa.
$REPORT"; rc=$?
check "backend XONG with report, gate missing" 0 "$rc"
! grep -q "proof-capture" "$TMP/err" && grep -q -- "--full" "$TMP/err" \
  && ok "(c) backend gate-only: the gate command, no screenshot instruction" || fail "(c) backend told to capture or gate unnamed"
python3 -c 'import datetime,json
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"git push origin main"}}]}}))' >> "$TR"
pstop "$TMP/pb" "Đã push lên origin/main."; rc=$?
check "push turn without the report" 1 "$rc"
grep -q "4 mục" "$TMP/err" && ok "(c) push turn: names the 4-item report" || fail "(c) push turn: '4 mục' missing"

echo ""
echo "stop repeat: ${PASS} ok, ${FAIL} failed"
[ "$FAIL" = 0 ]
