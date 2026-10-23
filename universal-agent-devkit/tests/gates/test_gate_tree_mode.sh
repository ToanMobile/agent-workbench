#!/usr/bin/env bash
# Test hồi quy #307 (23/10): không có cách xác nhận một cây sạch. `--full` trên worktree sạch tại HEAD = exit 3 (không có thay đổi để
# kiểm); `--diff <ref cũ>` qua một merge sửa ma trận không chỉ-nối-cuối = exit 2 (ma trận không tin được) dù 63/63 suite xanh.
# Chế độ `--tree HEAD`: chạy đủ suite trên cây sạch ở HEAD, tin ma trận ĐÃ COMMIT của chính cây đó, ghi biên nhận theo cây cho proof_gate.
# Mỗi ca chặn chỉ khác ca cho qua đúng một biến (cây bẩn, suite đỏ).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"; TR="$TMP/transcript.jsonl"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src templates .agents
  printf '[ -z "$FAIL_SUITE" ]\n' > result.sh && echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: không cần ảnh, chỉ xét cổng
  printf '.claude/audit-gate/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
BASE="$(git -C "$REPO" rev-parse HEAD)"

# Một commit sửa ma trận KHÔNG chỉ-nối-cuối (chèn rule mới lên đầu): --diff <BASE> không tin được ma trận (exit 2), cây sạch ở HEAD thì có.
( cd "$REPO" && cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Head","watch_files":["result.sh"],
 "mandatory_regression_tests":[{"id":"REG-0","name":"head","command":"true"}]},
 {"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git commit -qam "ma trận sửa không chỉ nối cuối" && git push -q origin main ) || exit 1

gate() { local d="$1"; shift; CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --no-checklist --run-tests "$@" >"$TMP/gate" 2>&1; }

# A0. Triệu chứng của issue: --full trên cây sạch, không --diff, không upstream phía trước: exit 3.
gate "$REPO" --full; rc=$?
[ "$rc" = 3 ] && ok "A0 --full on a clean tree: exit 3 (nothing to audit), the symptom" || fail "A0 expected exit 3, got $rc"
# A1. Triệu chứng 2: --diff qua commit sửa ma trận không chỉ-nối-cuối: exit 2.
gate "$REPO" --full --diff "$BASE"; rc=$?
[ "$rc" = 2 ] && ok "A1 --diff across a non-additive matrix edit: exit 2 (matrix untrusted), the symptom" || fail "A1 expected exit 2, got $rc"

# T1. Cây sạch ở HEAD, ma trận đã commit, suite xanh: --tree HEAD exit 0 và suite chạy thật.
gate "$REPO" --full --tree HEAD; rc=$?
[ "$rc" = 0 ] && grep -q "REG-1" "$TMP/gate" && ok "T1 --tree HEAD on a clean tree: exit 0 and REG-1 ran" \
  || fail "T1 expected exit 0 with REG-1 run, got $rc ($(tail -3 "$TMP/gate" | tr '\n' ' '))"
# T1b. Chạy cả suite của rule không khớp file nào (REG-0 theo rule chèn đầu): --tree chạy MỌI suite, không chọn theo file đổi.
grep -q "REG-0" "$TMP/gate" && ok "T1b --tree ran the suite of a rule no changed file selects (REG-0)" || fail "T1b REG-0 did not run"
# T1c. Không cần --full kèm theo: --tree tự bắt buộc full.
gate "$REPO" --tree HEAD; rc=$?
[ "$rc" = 0 ] && grep -q "REG-0" "$TMP/gate" && ok "T1c --tree alone implies the full run" || fail "T1c got $rc"

# T2. Suite đỏ: --tree HEAD exit 1 (chứng minh chế độ này chạy suite thật, không phải đi tắt).
FAIL_SUITE=1 gate "$REPO" --full --tree HEAD --no-cache; rc=$?   # --no-cache: T1 left a PASS receipt of this very tree
[ "$rc" = 1 ] && ok "T2 a failing suite under --tree: exit 1" || fail "T2 expected exit 1, got $rc"

# N1. Cây bẩn (file code sửa chưa commit): --tree không được xác nhận — exit 2 với lý do riêng, không bao giờ 0.
echo "def ok(): return 2" > "$REPO/src/core.py"
gate "$REPO" --full --tree HEAD; rc=$?
[ "$rc" = 2 ] && grep -q -- "--tree: " "$TMP/gate" && ! grep -q "unrecognized" "$TMP/gate" \
  && ok "N1 dirty code file under --tree: exit 2, never 0" || fail "N1 expected exit 2 by the dirty-tree rule, got $rc"
git -C "$REPO" checkout -q -- src/core.py
# N2. Ma trận sửa chưa commit: cùng chặn (bắt tay vào "tin ma trận" không được nới cho thay đổi chưa commit).
printf '{"project":"t","rules":[]}\n' > "$REPO/templates/regression_matrix.json"
gate "$REPO" --full --tree HEAD; rc=$?
[ "$rc" = 2 ] && grep -q -- "--tree: " "$TMP/gate" && ! grep -q "unrecognized" "$TMP/gate" \
  && ok "N2 uncommitted matrix edit under --tree: exit 2" || fail "N2 expected exit 2 by the dirty-tree rule, got $rc"
git -C "$REPO" checkout -q -- templates/regression_matrix.json
# N3. File chưa track cũng là cây bẩn.
echo x > "$REPO/src/new.py"
gate "$REPO" --full --tree HEAD; rc=$?
[ "$rc" = 2 ] && grep -q -- "--tree: " "$TMP/gate" && ok "N3 untracked file under --tree: exit 2" || fail "N3 expected exit 2, got $rc"
rm -f "$REPO/src/new.py"
# N4. Ref không phải HEAD: suite chạy trên cây làm việc, không trên ref — từ chối.
gate "$REPO" --full --tree "$BASE"; rc=$?
[ "$rc" = 2 ] && grep -q -- "--tree: " "$TMP/gate" && ok "N4 --tree <ref other than HEAD>: exit 2" || fail "N4 expected exit 2, got $rc"
# N5. --tree kèm --diff: bị từ chối.
gate "$REPO" --full --tree HEAD --diff "$BASE"; rc=$?
[ "$rc" = 2 ] && grep -q -- "--tree: " "$TMP/gate" && ok "N5 --tree with --diff: exit 2" || fail "N5 expected exit 2, got $rc"

# R1. proof_gate nhận biên nhận theo cây: worktree sạch ở HEAD, gate --tree HEAD exit 0, worktree gỡ, XONG ở main được qua.
WT="$TMP/wt"; git -C "$REPO" worktree add -q --detach "$WT" HEAD
python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"xác nhận main sạch"}}))' > "$TR"; sleep 1
gate "$WT" --full --tree HEAD || fail "R1 setup: gate exit $?"
git -C "$REPO" worktree remove --force "$WT"
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
rm -f "$REPO/.claude/audit-gate/proof_gate.state"
python3 -c 'import json,sys; print(json.dumps({"session_id":"s-t","hook_event_name":"Stop","transcript_path":sys.argv[1],
  "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã giao. Gate exit 0, ảnh: không cần — backend
$REPORT" | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && ok "R1 proof_gate accepts the receipt of --tree HEAD (by tree, worktree gone)" \
  || fail "R1 proof_gate refused ($(grep -m1 'Cổng:' "$TMP/err" || head -2 "$TMP/err" | tr '\n' ' '))"

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
