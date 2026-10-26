#!/usr/bin/env bash
# Test hồi quy Pha 1 (T0061, bước 2): lượt CLI `post-fix-gate --run-tests` (không --full) exit 0 trong worktree / nhánh không phải nhánh
# đích ghi "biên nhận task" cách ly: <git dir của worktree>/postfix-gate/task_pass.json + <git common dir>/postfix-gate/task_receipts/<fp>.json
# với {"scope":"task","fp","tested_at","diff_base","session"}; không bao giờ ghi full_pass.json hay tree_receipts/.
# Ca: W1 impacted exit 0 → có (đúng fp, diff_base = merge-base(origin/main, HEAD)); W2 --since → không; W3 DEVKIT_GATE_MERGE_CHECK=1 → không;
# W4 BUSY → không, và không xoá biên nhận đã có; W5 lượt sau cùng fp exit 1 → xoá cả hai file; W6 cây sạch đã push trên nhánh → không
# exit 3, có biên nhận; W7 --full → không; W8 checkout trên nhánh đích → không; W9 --diff hẹp hơn merge-base → không (chưa kiểm trọn).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID DEVKIT_GATE_MERGE_CHECK CI

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
HOLDER=""
trap '[ -n "$HOLDER" ] && kill "$HOLDER" 2>/dev/null; rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # hàng đợi gate riêng: không tranh slot với máy thật
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src .agents
  printf '[ -z "$FAIL_SUITE" ]\n' > result.sh && echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.claude/audit-gate/\n' > .gitignore
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
git -C "$REPO" remote set-head origin main >/dev/null 2>&1
STORE="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/postfix-gate/task_receipts"
TREE_STORE="$(dirname "$STORE")/tree_receipts"

wt_new() { WT="$TMP/wt-$1"; git -C "$REPO" worktree add -q --detach "$WT" origin/main || exit 1; }
gate() { local d="$1"; shift; CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --run-tests --no-checklist "$@" >"$TMP/gate" 2>&1; }
task_pass() { echo "$(git -C "$1" rev-parse --absolute-git-dir)/postfix-gate/task_pass.json"; }
full_pass() { echo "$(git -C "$1" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"; }
fp_of() { python3 "$DEVKIT_DIR/bin/tree_fp.py" "$1"; }
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
nstore() { ls "$STORE"/*.json 2>/dev/null | wc -l | tr -d ' '; }
wipe() { rm -rf "$STORE"; }

# W1. Worktree tách từ origin/main, một commit + một sửa chưa commit, lượt CLI --run-tests: exit 0 và biên nhận task đúng cây.
wt_new w1; echo "def ok(): return 2" > "$WT/src/core.py"; git -C "$WT" commit -qam "edit 2"
echo "def ok(): return 3" > "$WT/src/core.py"
gate "$WT"; g=$?
TP="$(task_pass "$WT")"; FP="$(fp_of "$WT")"; MB="$(git -C "$WT" merge-base origin/main HEAD)"
[ "$g" = 0 ] || fail "W1 tiền đề: gate exit $g ($(tail -3 "$TMP/gate" | tr '\n' ' '))"
[ -f "$TP" ] && [ "$(field "$TP" scope)" = task ] && [ "$(field "$TP" fp)" = "$FP" ] && [ "$(field "$TP" diff_base)" = "$MB" ] \
  && [ -f "$STORE/$FP.json" ] && [ "$(field "$STORE/$FP.json" scope)" = task ] \
  && ok "W1 lượt task exit 0: task_pass.json + task_receipts/<fp>.json (scope task, fp cây, diff_base merge-base)" \
  || fail "W1 không có biên nhận task đúng (tp=$(cat "$TP" 2>/dev/null) store=$(ls "$STORE" 2>/dev/null | tr '\n' ' '))"
grep -q "src/core.py" "$TMP/gate" && [ "$(field "$TP" tested_at)" != None ] || fail "W1 biên nhận thiếu tested_at hoặc gate không kiểm src/core.py"
[ ! -e "$(full_pass "$WT")" ] && [ -z "$(ls "$TREE_STORE" 2>/dev/null)" ] \
  && ok "W1 lượt task không ghi full_pass.json hay tree_receipts/" || fail "W1 lượt task ghi biên nhận --full"

# W5. Lượt sau trên cùng cây exit 1 (suite đỏ): xoá task_pass.json và mục store của cây đó.
FAIL_SUITE=1 gate "$WT" --no-cache; g=$?
[ "$g" = 1 ] || fail "W5 tiền đề: lượt đỏ exit $g"
[ ! -e "$TP" ] && [ ! -e "$STORE/$FP.json" ] && ok "W5 lượt sau cùng fp exit 1: biên nhận task bị xoá" \
  || fail "W5 biên nhận task còn sau FAIL (tp=$([ -e "$TP" ] && echo có) store=$([ -e "$STORE/$FP.json" ] && echo có))"

# W4. BUSY (khoá chạy test bị giữ): không ghi; và một biên nhận đã có của cây đó không bị xoá.
gate "$WT" || fail "W4 tiền đề: lượt xanh lại exit $?"
[ -f "$TP" ] || fail "W4 tiền đề: không có biên nhận sau lượt xanh"
mkdir -p "$WT/.claude/audit-gate"
python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(60)' \
  "$WT/.claude/audit-gate/test_run.lock" "$TMP/held" & HOLDER=$!
for _ in $(seq 50); do [ -e "$TMP/held" ] && break; sleep 0.1; done
cp "$TP" "$TMP/tp.before"
TEST_RUN_LOCK_WAIT_S=1 DEVKIT_REUSE_LOCK_WAIT_S=1 gate "$WT" --no-cache; g=$?
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; HOLDER=""
[ "$g" = 4 ] || fail "W4 tiền đề: lượt BUSY exit $g"
cmp -s "$TP" "$TMP/tp.before" && [ -f "$STORE/$FP.json" ] && ok "W4 lượt BUSY không ghi, không xoá biên nhận task" \
  || fail "W4 lượt BUSY đổi biên nhận task"
git -C "$REPO" worktree remove --force "$WT"; wipe

# W2. --since (lượt Stop có commit chưa xác minh): không ghi. --diff origin/main cho phạm vi đủ: chỉ chốt --since chặn được.
wt_new w2; echo "def ok(): return 21" > "$WT/src/core.py"; git -C "$WT" commit -qam "edit 21"
gate "$WT" --diff origin/main --since HEAD~1; g=$?
[ "$g" = 0 ] || fail "W2 tiền đề: gate --since exit $g"
[ ! -e "$(task_pass "$WT")" ] && [ "$(nstore)" = 0 ] && ok "W2 --since: không biên nhận task" || fail "W2 --since ghi biên nhận task"

# W3. DEVKIT_GATE_MERGE_CHECK=1 (merge gate của worktree finish, luôn có --diff): không ghi.
DEVKIT_GATE_MERGE_CHECK=1 gate "$WT" --diff origin/main; g=$?
[ "$g" = 0 ] || fail "W3 tiền đề: gate exit $g"
[ ! -e "$(task_pass "$WT")" ] && [ "$(nstore)" = 0 ] && ok "W3 DEVKIT_GATE_MERGE_CHECK=1: không biên nhận task" || fail "W3 merge check ghi biên nhận task"

# W9. --diff hẹp hơn merge-base(origin/main, HEAD) (chỉ sửa chưa commit, bỏ commit của nhánh): chưa kiểm trọn phạm vi, không ghi.
echo "def ok(): return 22" > "$WT/src/core.py"
gate "$WT" --diff HEAD; g=$?
[ "$g" = 0 ] || fail "W9 tiền đề: gate --diff HEAD exit $g"
[ ! -e "$(task_pass "$WT")" ] && [ "$(nstore)" = 0 ] && ok "W9 --diff HEAD trên nhánh có commit riêng: không biên nhận task" || fail "W9 phạm vi hẹp vẫn ghi"

# W7. --full (phạm vi đủ: --diff origin/main): biên nhận --full, không biên nhận task.
gate "$WT" --full --diff origin/main; g=$?
[ "$g" = 0 ] || fail "W7 tiền đề: gate --full exit $g"
[ ! -e "$(task_pass "$WT")" ] && [ "$(nstore)" = 0 ] && [ -f "$(full_pass "$WT")" ] && ok "W7 --full: không biên nhận task" || fail "W7 --full ghi biên nhận task"
git -C "$REPO" worktree remove --force "$WT"; wipe

# W6. Nhánh đã push, cây sạch, ngang upstream: trước đây exit 3 ("không có gì để kiểm"); nay kiểm merge-base(origin/main, HEAD)..HEAD.
wt_new w6; git -C "$WT" checkout -q -b feat-w6 && echo "def ok(): return 6" > "$WT/src/core.py" && git -C "$WT" commit -qam "edit 6" \
  && git -C "$WT" push -q -u origin feat-w6 2>/dev/null || fail "W6 tiền đề: push nhánh"
gate "$WT"; g=$?
TP="$(task_pass "$WT")"
[ "$g" = 0 ] && [ -f "$TP" ] && [ "$(field "$TP" diff_base)" = "$(git -C "$WT" merge-base origin/main HEAD)" ] \
  && ok "W6 cây sạch đã push trên nhánh: exit 0 (không còn exit 3) và có biên nhận task" \
  || fail "W6 exit $g, biên nhận $([ -f "$TP" ] && echo có || echo không) ($(tail -3 "$TMP/gate" | tr '\n' ' '))"
git -C "$REPO" worktree remove --force "$WT"; wipe

# W8. Checkout đứng trên nhánh đích (main) với sửa chưa commit: không biên nhận task (task chỉ ở worktree / nhánh khác nhánh đích).
echo "def ok(): return 8" > "$REPO/src/core.py"
gate "$REPO"; g=$?
[ "$g" = 0 ] || fail "W8 tiền đề: gate exit $g"
[ ! -e "$(task_pass "$REPO")" ] && [ "$(nstore)" = 0 ] && ok "W8 trên nhánh đích: không biên nhận task" || fail "W8 trên nhánh đích ghi biên nhận task"
git -C "$REPO" checkout -q -- src/core.py

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
