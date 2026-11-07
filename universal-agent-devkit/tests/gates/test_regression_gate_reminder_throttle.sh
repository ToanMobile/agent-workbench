#!/usr/bin/env bash
# Regression test: hooks/regression_gate.sh must not block every Stop while the only thing left is "an existing test was edited, another
# agent has to review the diff". Measured 2026-10-08 on OfficeReader (10 sessions in one checkout): 70 of 71 Stop-hook gate runs in 17 h
# ended exit 2 with that reminder. Gate speed v26 mục 1: the Stop runs no gate; the agent's gate run writes the "edited_test" outcome
# (<git dir>/postfix-gate/outcomes/<fp>.json) and the Stop "blocks once with the cure, later stops only remind" for that content.
# What this file keeps: the first Stop of a content blocks naming the file; repeats remind (no block, not a PASS); a new content (tracked,
# untracked bytes, a new commit) is judged again; a gate run that sees a failing suite writes no outcome, so the old reminder can never
# hide that failure.
# Gone with the Stop gate call (plan v26 mục 1, "Remove the gate call RG:833 and result branches RG:855-1096"): the per-session stored
# reminder that skipped the gate run, its REGRESSION_GATE_TOUCHED_RECHECK_S / DEVKIT_GATE_CACHE_MAX_S window and the approval digest
# (tests/gates/test_regression_gate_reminder_approval_key.sh, deleted): the gate run the agent makes judges the approval sources itself.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export WORKTREE_TRUNK_MODE=0   # K12 (18/10): các ca ở đây là phiên sửa thẳng main (không trunk mode); ở trunk mode Stop tại main không gate (test_regression_gate_trunk_main.sh)
export DEVKIT_GATE_CACHE=0

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

X="$TMP/repo"; mkdir -p "$X/src/test" "$X/.agents" && cd "$X" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo "assert(true)" > src/test/CoreTest.kt
RUNS="$TMP/runs"; : > "$RUNS"
cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt","src/test/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-X","name":"core","command":"printf x >> $RUNS; [ ! -f $TMP/failnow ]"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt && echo "// weakened" > src/test/CoreTest.kt
runs() { wc -c < "$RUNS" | tr -d ' '; }
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"s-y2"}' > "$TMP/s.jsonl"
stop() { printf '{"session_id":"s-y2","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/s.jsonl" \
  | env "$@" CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
# gaterun [ENV=VAL …]: the agent's gate run, the command a block prints (--diff <verified_head> on this trunk branch once one is recorded)
gaterun() {
  local vh; vh="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verified_head") or "")' "$X/.claude/audit-gate/regression_gate.state.json" 2>/dev/null)"
  git -C "$X" cat-file -e "${vh:-none}^{commit}" 2>/dev/null || vh=""
  ( cd "$X" && env "$@" CLAUDE_PROJECT_DIR="$X" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --scoped --brief ${vh:+--diff "$vh"} ) >"$TMP/gate.out" 2>&1; GRC=$?; }

# 1. first Stop of the change: blocks, naming the edited test (the gate run said exit 2)
gaterun X=1; n0="$(runs)"; stop X=1; rc=$?
[ "$GRC" = 2 ] && [ "$rc" = 2 ] && grep -q "src/test/CoreTest.kt" "$TMP/err" && [ "$(runs)" = "$n0" ] \
  && ok "first stop: blocked once, naming the edited test; the Stop ran no suite" \
  || fail "first stop: gate=$GRC rc=$rc runs $n0 -> $(runs) err='$(head -3 "$TMP/err")'"

# 2. same content: a reminder, no block, no run, not a PASS
stop X=1; rc=$?
[ "$rc" = 0 ] && grep -q "src/test/CoreTest.kt" "$TMP/out" && grep -q "Vẫn chờ người duyệt" "$TMP/out" && grep -q "KHÔNG phải PASS" "$TMP/out" \
  && [ "$(runs)" = "$n0" ] && ok "repeat stop: allowed with the reminder naming the file, no run" \
  || fail "repeat stop: rc=$rc runs=$(runs) out='$(head -c 300 "$TMP/out")' err='$(head -2 "$TMP/err")'"
stop X=1; rc=$?
[ "$rc" = 0 ] && grep -q "Vẫn chờ người duyệt" "$TMP/out" && ok "a third stop: still the reminder (never a block loop)" || fail "third stop: rc=$rc"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(1 if d.get("pass_fp") else 0)' "$X/.claude/audit-gate/regression_gate.state.json" \
  && ok "the reminder never stores a PASS for the content" || fail "reminder stored pass_fp"

# 3. a new content is judged again: tracked edit, then an edit inside an untracked file (same status line), then a new commit
echo "// weakened again" > src/test/CoreTest.kt
stop X=1; rc=$?
[ "$rc" = 2 ] && ok "a new content (tracked edit), no gate run for it yet: blocked" || fail "new content: rc=$rc"
gaterun X=1; stop X=1; rc=$?; stop X=1; rc2=$?
[ "$GRC" = 2 ] && [ "$rc" = 2 ] && [ "$rc2" = 0 ] && grep -q "Vẫn chờ người duyệt" "$TMP/out" \
  && ok "the new content after its gate run: blocked once with the cure, then reminded" \
  || fail "new content outcome: gate=$GRC rc=$rc rc2=$rc2"
echo "scratch v1" > untracked.txt; gaterun X=1; stop X=1; stop X=1
echo "scratch v2 with other bytes" > untracked.txt      # same git status line, other bytes
stop X=1; rc=$?
[ "$rc" = 2 ] && ! grep -q "Vẫn chờ người duyệt" "$TMP/out" && ok "an edit inside an untracked file (same status, other bytes) is a new content: no reminder, blocked" \
  || fail "untracked edit reused the reminder (rc=$rc out='$(head -c 200 "$TMP/out")')"
rm -f untracked.txt; gaterun X=1; stop X=1; stop X=1
echo "other" > other.txt && git add other.txt && git commit -qm "unrelated" -- other.txt
stop X=1; rc=$?
[ "$rc" = 2 ] && ! grep -q "Vẫn chờ người duyệt" "$TMP/out" && ok "a new commit (same dirty files): the old reminder is not reused, blocked" \
  || fail "reminder reused across a new commit (rc=$rc)"

# 4. a reminder, then a change that lets the gate see a failing suite (the test edit undone, REG-X red): blocked, no reminder. While the
#    edit waits, the session-less gate run takes no lock and starts no suite (post-fix-gate #472 B: exit 2, never a PASS, no receipt),
#    so neither BUSY nor a red suite can pass behind the reminder: they show on the first run after the approval or the undo.
echo "fun ok() = 4" > src/Core.kt
gaterun X=1; stop X=1; stop X=1; rc=$?
[ "$GRC" = 2 ] && [ "$rc" = 0 ] && grep -q "Vẫn chờ người duyệt" "$TMP/out" && ok "test edited, suite not run yet: the reminder stands" || fail "touched test: gate=$GRC rc=$rc"
touch "$TMP/failnow"; echo "assert(true)" > src/test/CoreTest.kt
gaterun X=1; stop X=1; rc=$?
[ "$GRC" = 1 ] && grep -q "REG-X" "$TMP/gate.out" && [ "$rc" = 2 ] && ! grep -q "Vẫn chờ người duyệt" "$TMP/out" \
  && ok "the gate run that sees REG-X fail: the stop blocks, the old reminder does not hide it" \
  || fail "stale reminder hid a failure (gate=$GRC rc=$rc out='$(head -c 150 "$TMP/out")')"
rm -f "$TMP/failnow"
cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate reminder throttle: $FAILS FAILED"; exit 1; fi
echo "regression gate reminder throttle: all checks passed"
