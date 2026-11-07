#!/usr/bin/env bash
# Gate speed v26 (lane D2): Stop hook không còn chạy gate nên không còn truyền DEVKIT_LEDGER_ROOT. post-fix-gate.py chạy trong linked
# worktree với --session/--transcript phải tự đọc bash_write_ledger.tsv của main (hooks/bash_write_ledger.sh ghi ở CLAUDE_PROJECT_DIR = main).
#   l1. (tiền đề) có DEVKIT_LEDGER_ROOT=main: test cũ bị sửa trong cửa sổ Bash của phiên KHÁC ⇒ chỉ cảnh báo, exit 0.
#   l2. không có biến: kết quả như l1 (trước bản sửa: gate đọc ledger của worktree, không thấy cửa sổ nào ⇒ chặn).
#   l3. không có biến, ledger main không có cửa sổ nào quanh thay đổi ⇒ vẫn chặn (fail closed giữ nguyên).
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_CACHE DEVKIT_SCOPED_TESTS DEVKIT_GATE_MERGE_CHECK POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL CI \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID DEVKIT_LEDGER_ROOT DEVKIT_AUTO_APPROVE_TESTS
export DEVKIT_SUITE_CACHE=0 DEVKIT_GATE_CACHE=0

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

M="$TMP/main"; W="$M/.claude/worktrees/s1"
mkdir -p "$M/src/test" "$M/.agents" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t || exit 1
printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$M/.gitignore"
echo "fun ok() = 1" > "$M/src/Core.kt"; echo "assert(true)" > "$M/src/test/CoreTest.kt"
printf '{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt","src/test/*.kt"],"mandatory_regression_tests":[{"id":"REG-X","name":"core","command":"true"}]}]}\n' \
  > "$M/.agents/regression_matrix.active.json"
git -C "$M" add -A && git -C "$M" commit -qm i || exit 1
git -C "$M" worktree add -q --detach "$W" HEAD || exit 1

# Thay đổi trong worktree: Core.kt do phiên s63 sửa (transcript), CoreTest.kt (test cũ) sửa lúc now-300 bởi ai đó khác.
echo "fun ok() = 2" > "$W/src/Core.kt"; echo "// weakened" > "$W/src/test/CoreTest.kt"
python3 -I - "$W" "$TMP/t.jsonl" <<'PY'
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
ledger_main() {   # ledger_main <session> <start offset s> <end offset s> [...]: cửa sổ Bash, ghi ở main như bash_write_ledger.sh
  mkdir -p "$M/.claude/audit-gate"
  python3 -I - "$M/.claude/audit-gate/bash_write_ledger.tsv" "$@" <<'PY'
import sys, time
now, a = time.time(), sys.argv[2:]
with open(sys.argv[1], "w") as fh:
    for i in range(0, len(a), 3):
        fh.write("%s\tstart\t%.3f\tw%d\n%s\tend\t%.3f\tw%d\n" % (a[i], now + float(a[i + 1]), i, a[i], now + float(a[i + 2]), i))
PY
}
gate() { ( cd "$W" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$W" python3 "$GATE" --run-tests --no-checklist \
  --session s63 --transcript "$TMP/t.jsonl" >"$TMP/out" 2>&1 ); RC=$?; }
show() { grep -E "CoreTest|KẾT LUẬN|VERDICT" "$TMP/out" | head -4 | tr '\n' ' ' | cut -c1-400; }

ledger_main s-x -305 -295 s63 -590 -589
DEVKIT_LEDGER_ROOT="$M" gate
[ "$RC" = 0 ] && grep -q "src/test/CoreTest.kt" "$TMP/out" \
  && ok "l1. (tiền đề) DEVKIT_LEDGER_ROOT=main: test sửa trong cửa sổ phiên khác chỉ cảnh báo, exit 0" \
  || fail "l1. rc=$RC (mong 0 kèm cảnh báo CoreTest.kt) $(show)"

gate
[ "$RC" = 0 ] && grep -q "src/test/CoreTest.kt" "$TMP/out" \
  && ok "l2. không có DEVKIT_LEDGER_ROOT, chạy trong worktree: gate tự đọc ledger của main, exit 0 kèm cảnh báo" \
  || fail "l2. rc=$RC (mong 0 như l1: gate phải tự tìm ledger của main) $(show)"

ledger_main s63 -590 -589
gate
[ "$RC" != 0 ] && grep -q "src/test/CoreTest.kt" "$TMP/out" \
  && ok "l3. ledger main không có cửa sổ quanh thay đổi: vẫn chặn (rc=$RC)" \
  || fail "l3. rc=$RC (mong ≠0: không ai nhận thay đổi thì chặn) $(show)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_ledger_main_from_worktree: PASS"; exit 0; }
echo "test_gate_ledger_main_from_worktree: FAIL ($FAILS)"
exit 1
