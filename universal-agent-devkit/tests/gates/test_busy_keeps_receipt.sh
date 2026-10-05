#!/usr/bin/env bash
# Regression (DevKit speed, review of 0a/0b): a gate run that could not take the test-run lock ends BUSY
# (UNTESTED, exit 4: no suite ran). It still called write_full_pass_receipt(exit 4, untested=None), which
# deletes .git/postfix-gate/full_pass.json — also a VALID one (fingerprint of the current tree). The Stop hook
# (no --full) hits this whenever the lock wait runs out, so XONG / the push gate were refused and a full run was
# demanded for no reason. "Could not lock" means nothing ran: nothing to write and nothing to delete.
#   BUSY, partial or --full, valid or stale receipt -> exit 4, receipt byte-identical; no receipt -> still none
#   a REAL --full receipt that survives BUSY still serves the same code (proof_gate XONG passes) and still refuses code edited
#   after it (proof_gate: "code đã đổi sau lần exit 0"; push_gate: "khác bản gate đã test"): surviving never means accepting
#   controls (old behaviour unchanged): lock free + PASS keeps (partial) / rewrites (--full) the receipt;
#   a real FAIL deletes it; UNTESTED for another reason (untested_exit suite) keeps (partial) / records exit 4 (--full).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export VACUITY_REVERT=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'touch "$TMP/release" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
make_repo() { # $1 = exit code of the suite, $2 = "car" adds a suite that exits 2 (untested_exit)
  rm -rf "$R" && mkdir -p "$R/src" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf 'exit %s\n' "$1" > ok.sh; printf 'exit 2\n' > car.sh
  extra=""
  [ "${2:-}" = car ] && extra=',{"id":"REG-CAR","name":"real car","command":"sh car.sh","untested_exit":2}'
  cat > matrix.json <<JSON
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-OK","name":"core","command":"sh ok.sh"}$extra]}]}
JSON
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt
}
run_gate() { CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en "$@" 2>&1; }
RCPT() { echo "$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"; }
# plant a receipt: $1 = valid (fingerprint of the CURRENT tree) | stale (another fingerprint)
plant() {
  mkdir -p "$(dirname "$(RCPT)")"
  python3 - "$DEVKIT_DIR/bin" "$R" "$1" "$(RCPT)" <<'PY'
import json, sys, time
sys.path.insert(0, sys.argv[1])
import tree_fp
fp = tree_fp.tree_fingerprint(sys.argv[2]) if sys.argv[3] == "valid" else "0" * 24
json.dump({"exit": 0, "time": time.time() - 100, "fingerprint": fp, "tested_at": time.time() - 100}, open(sys.argv[4], "w"))
PY
}
# the planted receipt still names the current tree (usable by proof_gate / push_gate)
still_valid() {
  [ -f "$(RCPT)" ] || return 1
  python3 - "$DEVKIT_DIR/bin" "$R" "$(RCPT)" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import tree_fp
sys.exit(0 if json.load(open(sys.argv[3])).get("fingerprint") == tree_fp.tree_fingerprint(sys.argv[2]) else 1)
PY
}
field() { python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r.get(sys.argv[2]), end="")' "$(RCPT)" "$1" 2>/dev/null; }

# hold the project test-run lock (what a running gate of another session does) until $TMP/release exists
HOLDER=""
hold_lock() {
  rm -f "$TMP/held" "$TMP/release"
  python3 - "$R" "$TMP/held" "$TMP/release" <<'PY' &
import fcntl, os, sys, time
d = sys.argv[1] + "/.claude/audit-gate"
os.makedirs(d, exist_ok=True)
with open(d + "/test_run.lock", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    for _ in range(600):
        if os.path.exists(sys.argv[3]):
            break
        time.sleep(0.1)
PY
  HOLDER=$!
  i=0; while [ ! -f "$TMP/held" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ -f "$TMP/held" ] || { bad "setup: the lock holder did not start"; exit 1; }
}
release_lock() { touch "$TMP/release"; wait "$HOLDER" 2>/dev/null; HOLDER=""; }

# ── BUSY: the lock is held by another run ───────────────────────────────────────────────────────────────
for mode in valid stale; do
  for flag in "" "--full"; do
    label="${flag:-partial (the Stop hook)}"
    make_repo 0; plant "$mode"; before="$(cat "$(RCPT)")"
    hold_lock
    out="$(TEST_RUN_LOCK_WAIT_S=1 run_gate --run-tests $flag)"; rc=$?
    release_lock
    printf '%s' "$out" | grep -q "another test run holds the project lock" && [ "$rc" = 4 ] \
      && ok "BUSY $label, $mode receipt: exit 4, no suite ran" || bad "BUSY $label, $mode receipt: exit $rc, $(printf '%s' "$out" | grep -i verdict | head -1)"
    [ -f "$(RCPT)" ] && [ "$(cat "$(RCPT)")" = "$before" ] \
      && ok "BUSY $label: the $mode receipt is still there, byte for byte" || bad "BUSY $label: the $mode receipt was deleted or rewritten"
    [ "$mode" = valid ] && { still_valid && ok "BUSY $label: its fingerprint still matches the tree" || bad "BUSY $label: the receipt fingerprint no longer matches the tree"; }
  done
done
make_repo 0; hold_lock
out="$(TEST_RUN_LOCK_WAIT_S=1 run_gate --run-tests --full)"; rc=$?; release_lock
[ "$rc" = 4 ] && [ ! -e "$(RCPT)" ] && ok "BUSY with no receipt: exit 4 and none is written" || bad "BUSY with no receipt: exit $rc, receipt $([ -e "$(RCPT)" ] && echo written || echo none)"

# ── controls: the same runs with the lock free behave as before ───────────────────────────────────────
make_repo 0; plant valid; before="$(cat "$(RCPT)")"
out="$(run_gate --run-tests)"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$(RCPT)")" = "$before" ] && ok "control: a partial PASS leaves the receipt as it was" || bad "control: partial PASS (exit $rc)"
make_repo 0; plant valid; before="$(cat "$(RCPT)")"
out="$(run_gate --run-tests --full)"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$(RCPT)")" != "$before" ] && [ "$(field exit)" = 0 ] && still_valid \
  && ok "control: a --full PASS rewrites the receipt for the current tree" || bad "control: --full PASS (exit $rc, receipt exit '$(field exit)')"
make_repo 1; plant valid
out="$(run_gate --run-tests)"; rc=$?
[ "$rc" = 1 ] && [ ! -e "$(RCPT)" ] && ok "control: a real FAIL (partial run) deletes the receipt" || bad "control: FAIL (exit $rc, receipt $([ -e "$(RCPT)" ] && echo kept || echo deleted))"
make_repo 0 car; plant valid; before="$(cat "$(RCPT)")"
out="$(run_gate --run-tests)"; rc=$?
[ "$rc" = 4 ] && [ "$(cat "$(RCPT)")" = "$before" ] && ok "control: partial run UNTESTED for another reason (untested_exit) keeps the receipt" || bad "control: partial UNTESTED (exit $rc)"
make_repo 0 car; plant valid
out="$(run_gate --run-tests --full)"; rc=$?
[ "$rc" = 4 ] && [ "$(field exit)" = 4 ] && [ "$(field untested)" = "['REG-CAR']" ] \
  && ok "control: --full UNTESTED for another reason records {exit 4, untested [REG-CAR]}" || bad "control: --full UNTESTED (exit $rc, exit '$(field exit)', untested '$(field untested)')"

# ── the invariant that matters: a surviving REAL receipt serves the same code and still refuses changed code ──────
# (planted receipts above carry no head/dirty/tests, so push_gate would refuse them at once: this uses a real --full PASS)
RR="$TMP/real"; ORIGIN="$TMP/origin.git"; TR="$TMP/tr.jsonl"
make_real() {
  rm -rf "$RR" "$ORIGIN"; mkdir -p "$RR/src" "$RR/.agents"; cd "$RR" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.claude/\n' > .gitignore
  echo "fun ok() = 1" > src/Core.kt; echo 'exit 0' > ok.sh
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-OK","name":"core","command":"sh ok.sh"}]}]}
JSON
  git add -A && git commit -qm init
  git init -q --bare "$ORIGIN" && git remote add origin "$ORIGIN" && git push -q -u origin HEAD:main 2>/dev/null
  git branch -q -u origin/main 2>/dev/null
  echo "fun ok() = 2" > src/Core.kt
  sleep 1
  python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"x"}}))' > "$TR"
}
gate_rr() { CLAUDE_PROJECT_DIR="$RR" python3 "$GATE" --matrix "$RR/.agents/regression_matrix.active.json" --lang en --no-checklist "$@" 2>&1; }
# the Stop hook for a reply that opens with XONG: rc 0 = lets it through, rc 2 = refuses (reason on stderr)
stop_xong() {
  reply="XONG
done
Gate exit 0 · ảnh: không cần — backend
1. Đã fix: x
2. Chặn bug cũ: x
3. Nguy cơ bug mới: x
4. An toàn mã nguồn: x"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-p","hook_event_name":"Stop","transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "$reply" \
    | CLAUDE_PROJECT_DIR="$RR" bash "$DEVKIT_DIR/hooks/proof_gate.sh" > "$TMP/pg.out" 2> "$TMP/pg.err"
  rc=$?; rm -f "$RR/.claude/audit-gate/proof_gate.state"; return $rc
}
RRCPT() { echo "$(git -C "$RR" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"; }
hold_rr() {  # the same lock holder as hold_lock, for $RR
  rm -f "$TMP/held" "$TMP/release"
  python3 - "$RR" "$TMP/held" "$TMP/release" <<'PY' &
import fcntl, os, sys, time
d = sys.argv[1] + "/.claude/audit-gate"
os.makedirs(d, exist_ok=True)
with open(d + "/test_run.lock", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    for _ in range(600):
        if os.path.exists(sys.argv[3]):
            break
        time.sleep(0.1)
PY
  HOLDER=$!
  i=0; while [ ! -f "$TMP/held" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
}

make_real
out="$(gate_rr --run-tests --full)"; rc=$?
[ "$rc" = 0 ] && [ -f "$(RRCPT)" ] && ok "real: a --full PASS wrote the receipt" || bad "real: --full PASS (exit $rc)"
stop_xong; rc=$?
[ "$rc" = 0 ] && ok "real control: XONG on the gated code is let through (proof_gate rc 0)" || bad "real control: proof_gate rc $rc: $(head -c 200 "$TMP/pg.err")"
# The gate would simply re-use this PASS for the same code (nothing to run, so never BUSY). A receipt it cannot re-use but
# proof_gate still accepts (its local-state hash differs, e.g. after a config change) is the case where BUSY can happen.
python3 - "$(RRCPT)" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
r["local_sha"] = "local state changed"
json.dump(r, open(sys.argv[1], "w"))
PY
before="$(cat "$(RRCPT)")"
for flag in "" "--full"; do
  hold_rr; out="$(TEST_RUN_LOCK_WAIT_S=1 gate_rr --run-tests $flag)"; rc=$?; release_lock
  [ "$rc" = 4 ] && [ "$(cat "$(RRCPT)" 2>/dev/null)" = "$before" ] \
    && ok "real, same code, BUSY ${flag:-partial}: exit 4, the receipt is untouched" || bad "real, same code, BUSY ${flag:-partial}: exit $rc, receipt $([ -f "$(RRCPT)" ] && echo kept || echo deleted)"
  stop_xong; rc=$?
  [ "$rc" = 0 ] && ok "real, same code, BUSY ${flag:-partial}: XONG still passes (no new --full needed)" \
    || bad "real, same code, BUSY ${flag:-partial}: proof_gate rc $rc: $(grep -o 'chưa có exit 0[^;.]*\|code đã đổi[^;.]*' "$TMP/pg.err" | head -1)"
done
echo "fun ok() = 3" > "$RR/src/Core.kt"   # code edited AFTER the receipt
for flag in "" "--full"; do
  hold_rr; out="$(TEST_RUN_LOCK_WAIT_S=1 gate_rr --run-tests $flag)"; rc=$?; release_lock
  [ "$rc" = 4 ] && [ "$(cat "$(RRCPT)" 2>/dev/null)" = "$before" ] \
    && ok "real, code edited after the receipt, BUSY ${flag:-partial}: exit 4, the receipt survives" || bad "real, edited, BUSY ${flag:-partial}: exit $rc, receipt $([ -f "$(RRCPT)" ] && echo kept || echo deleted)"
  stop_xong; rc=$?
  [ "$rc" = 2 ] && grep -q "code đã đổi sau lần exit 0" "$TMP/pg.err" \
    && ok "real, edited, BUSY ${flag:-partial}: XONG is refused because the code changed after the receipt (surviving is not accepting)" \
    || bad "real, edited, BUSY ${flag:-partial}: proof_gate rc $rc: $(head -c 200 "$TMP/pg.err")"
done
git -C "$RR" add src/Core.kt && git -C "$RR" commit -qm edit
out="$(cd "$RR" && PYTHONPATH="$DEVKIT_DIR/bin" python3 "$DEVKIT_DIR/bin/push_gate.py" "$RR" HEAD 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "khác bản gate đã test" \
  && ok "real, edited and committed: push_gate refuses the commit (differs from the gated version)" || bad "real, push_gate rc $rc: $(printf '%s' "$out" | head -c 200)"

echo
[ "$FAILS" -eq 0 ] && echo "busy keeps receipt: all checks passed" || { echo "busy keeps receipt: $FAILS FAILED"; exit 1; }
