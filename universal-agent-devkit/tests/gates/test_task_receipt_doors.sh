#!/usr/bin/env bash
# Test hồi quy Pha 1 (T0061, bước 1): biên nhận task (`"scope":"task"`, lượt --run-tests không --full) KHÔNG BAO GIỜ thay được biên nhận
# --full. Sáu cửa ĐỌC biên nhận --full phải từ chối một biên nhận mang scope task, kể cả khi mọi trường khác hợp lệ:
#   1 cached_full_pass (post-fix-gate.py; cả biên nhận của chính git dir lẫn mục tree_receipts/ của store)
#   2 push_gate.receipt_problem
#   3 worktree._carry_gate_receipt (cô lập: push_gate.check bị thay bằng hàm luôn đồng ý, chỉ còn chốt của chính carry)
#   4 proof_gate full_gate_problem   5 proof_gate tree_store_evidence   6 proof_gate merged_evidence (a)
# Cách làm: một lượt gate --full THẬT trong worktree, rồi chỉ thêm `"scope":"task"` vào đúng biên nhận mà cửa đó đọc. Mỗi cửa có ca đối
# chứng (cùng biên nhận, không scope) phải được nhận, nên một ca ĐỎ chỉ có thể do chốt scope. Các đường cứu khác của proof_gate bị đóng
# trong từng ca (trunk mode tắt, store bị dời, worktree bị gỡ).
# Ca 7: mark_merge_gate_receipt (post-fix-gate.py, hàm GHI, gọi ở nhánh `not partial`) được kiểm bằng đầu dò: lượt task (không --full)
# phải để đầu dò trống; đối chứng --full --diff origin/main phải ghi vào nó.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID DEVKIT_GATE_MERGE_CHECK

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # hàng đợi gate riêng: không tranh slot với máy thật
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"; WT="$TMP/wt"; TR="$TMP/transcript.jsonl"; MARK="$TMP/mark"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src .agents .claude/bin .claude/super-board/configs
  echo 'exit 0' > result.sh && echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: XONG không cần ảnh, chỉ xét cổng
  printf '.claude/audit-gate/\n' > .gitignore
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  # đầu dò của mark_merge_gate_receipt: script verify của board chỉ ghi một dòng vào $MARK
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$MARK" > .claude/bin/super-board-verify-cmd.sh
  echo '{"base_branch":"main","verify_commands":["python3 post-fix-gate.py --run-tests --full"]}' > .claude/super-board/configs/t.json
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
git -C "$REPO" remote set-head origin main >/dev/null 2>&1

turn_start() { python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X rồi giao"}}))' > "$TR"; sleep 1; }
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
stop() {   # stop DIR: hook Stop với XONG, xét cây DIR
  rm -f "$1/.claude/audit-gate/proof_gate.state"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-d","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã giao. Gate exit 0, ảnh: không cần — backend
$REPORT" | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
why() { echo "rc=$1 err=$(grep -m1 'Cổng:' "$TMP/err" || head -2 "$TMP/err" | tr '\n' ' ')"; }
setscope() { python3 -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); r["scope"]="task"; json.dump(r,open(p,"w"))' "$1"; }

# Một lượt gate --full thật trong worktree, trên cây sạch đã commit (merged_evidence (a) và push_gate cần cây sạch).
turn_start
git -C "$REPO" worktree add -q --detach "$WT" HEAD || exit 1
echo "def ok(): return 2" > "$WT/src/core.py" && git -C "$WT" commit -qam "edit 2"
CLAUDE_PROJECT_DIR="$WT" python3 "$GATE" --run-tests --full --no-checklist --diff HEAD~1 >"$TMP/gate" 2>&1 \
  || { echo "setup: gate --full exit $?"; tail -20 "$TMP/gate"; exit 1; }
WRC="$(git -C "$WT" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
STORE="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/postfix-gate/tree_receipts"
MRC="$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
SENTRY="$(ls "$STORE"/*.json 2>/dev/null | head -1)"
[ -f "$WRC" ] && [ -n "$SENTRY" ] || { echo "setup: thiếu biên nhận worktree hoặc mục store"; exit 1; }
cp "$WRC" "$TMP/wrc.bak"; cp "$SENTRY" "$TMP/store.bak"
restore() { cp "$TMP/wrc.bak" "$WRC"; mkdir -p "$STORE"; cp "$TMP/store.bak" "$SENTRY"; }

# ── 1. cached_full_pass: biên nhận của chính git dir và mục store ──
cfp() { CLAUDE_PROJECT_DIR="$WT" python3 - "$GATE" "$WT" "$@" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg_doors", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
r = m.cached_full_pass(sys.argv[2], None, path=sys.argv[3] if len(sys.argv) > 3 else None)
print("HIT" if r else "MISS")
PY
}
[ "$(cfp)" = HIT ] || fail "1 đối chứng: cached_full_pass không nhận biên nhận --full thật"
setscope "$WRC"; got="$(cfp)"; restore
[ "$got" = MISS ] && ok "1 cached_full_pass từ chối biên nhận của chính git dir có scope task" || fail "1 cached_full_pass nhận biên nhận scope task ($got)"
[ "$(cfp "$SENTRY")" = HIT ] || fail "1 đối chứng: cached_full_pass không nhận mục store thật"
setscope "$SENTRY"; got="$(cfp "$SENTRY")"; restore
[ "$got" = MISS ] && ok "1 cached_full_pass từ chối mục tree_receipts/ có scope task" || fail "1 cached_full_pass nhận mục store scope task ($got)"

# ── 2. push_gate.receipt_problem ──
rp() { python3 - "$DEVKIT_DIR/bin" "$WT" "$WRC" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1]); import push_gate
print(push_gate.receipt_problem(sys.argv[2], sys.argv[3], json.load(open(sys.argv[3])), "HEAD") or "OK")
PY
}
got="$(rp)"; [ "$got" = OK ] || fail "2 đối chứng: receipt_problem từ chối biên nhận --full thật ($got)"
setscope "$WRC"; got="$(rp)"; restore
[ "$got" != OK ] && ok "2 push_gate.receipt_problem từ chối scope task ($got)" || fail "2 receipt_problem nhận biên nhận scope task"

# ── 3. worktree._carry_gate_receipt, push_gate.check bị thay bằng hàm luôn đồng ý ──
carry() { rm -f "$MRC"; python3 - "$DEVKIT_DIR" "$REPO" "$WT" "$MRC" <<'PY'
import os, sys
kit, main, wt, dst = sys.argv[1:]
sys.path.insert(0, os.path.join(kit, "bin")); sys.path.insert(0, os.path.join(kit, "scripts", "git"))
import push_gate
push_gate.check = lambda *a, **k: (True, "stub")   # chỉ còn chốt của chính _carry_gate_receipt
import worktree as w
w._carry_gate_receipt(main, wt)
print("CARRIED" if os.path.isfile(dst) else "NOT")
PY
}
[ "$(carry)" = CARRIED ] || fail "3 đối chứng: _carry_gate_receipt không chép biên nhận --full thật"
setscope "$WRC"; got="$(carry)"; restore; rm -f "$MRC"
[ "$got" = NOT ] && ok "3 _carry_gate_receipt không chép biên nhận scope task sang main" || fail "3 _carry_gate_receipt chép biên nhận scope task"

# ── 4. proof_gate full_gate_problem (xét worktree; trunk mode tắt: tree_store / merged không cứu) ──
git -C "$REPO" config devkit.trunkMode false
stop "$WT"; rc=$?
[ "$rc" = 0 ] || fail "4 đối chứng: XONG với biên nhận --full thật bị chặn ($(why $rc))"
setscope "$WRC"; stop "$WT"; rc=$?; restore
[ "$rc" = 2 ] && ok "4 full_gate_problem từ chối biên nhận scope task" || fail "4 full_gate_problem nhận biên nhận scope task ($(why $rc))"
git -C "$REPO" config --unset devkit.trunkMode

# main tiến tới cây đã gate (như finish): xét main, main không có full_pass.json
git -C "$REPO" merge -q --ff-only "$(git -C "$WT" rev-parse HEAD)" || exit 1
rm -f "$MRC"

# ── 6. merged_evidence (a): worktree còn sống, sạch, cùng cây; store bị dời đi để tree_store_evidence không cứu ──
mv "$STORE" "$TMP/store.away"
stop "$REPO"; rc=$?
[ "$rc" = 0 ] && grep -q "worktree-receipt" "$REPO/.claude/audit-gate/proof_gate.log" \
  || fail "6 đối chứng: merged_evidence (a) không nhận biên nhận --full thật của worktree ($(why $rc))"
setscope "$WRC"; stop "$REPO"; rc=$?; cp "$TMP/wrc.bak" "$WRC"
[ "$rc" = 2 ] && ok "6 merged_evidence (a) từ chối biên nhận worktree scope task" || fail "6 merged_evidence (a) nhận biên nhận scope task ($(why $rc))"
mv "$TMP/store.away" "$STORE"

# ── 5. tree_store_evidence: worktree đã gỡ (merged_evidence (a) không còn gì để đọc) ──
git -C "$REPO" worktree remove --force "$WT"
stop "$REPO"; rc=$?
[ "$rc" = 0 ] && grep -q "tree-receipt" "$REPO/.claude/audit-gate/proof_gate.log" \
  || fail "5 đối chứng: tree_store_evidence không nhận mục store thật ($(why $rc))"
setscope "$SENTRY"; stop "$REPO"; rc=$?; cp "$TMP/store.bak" "$SENTRY"
[ "$rc" = 2 ] && ok "5 tree_store_evidence từ chối mục store scope task" || fail "5 tree_store_evidence nhận mục store scope task ($(why $rc))"

# ── 7. đầu dò mark_merge_gate_receipt: kỳ vọng lượt task để trống, đối chứng --full --diff origin/main ghi ──
git -C "$REPO" worktree add -q --detach "$TMP/wt2" origin/main || exit 1
echo "def ok(): return 3" > "$TMP/wt2/src/core.py" && git -C "$TMP/wt2" commit -qam "edit 3"
rm -f "$MARK"
CLAUDE_PROJECT_DIR="$TMP/wt2" python3 "$GATE" --run-tests --no-checklist --diff HEAD~1 >"$TMP/gate" 2>&1; g=$?
[ "$g" = 0 ] || fail "7 tiền đề: lượt task exit $g"
CLAUDE_PROJECT_DIR="$TMP/wt2" python3 "$GATE" --run-tests --no-checklist --diff origin/main >"$TMP/gate" 2>&1; g2=$?
[ "$g2" = 0 ] || fail "7 tiền đề: lượt task --diff origin/main exit $g2"
[ ! -e "$MARK" ] && ok "7 lượt task (không --full) không gọi mark_merge_gate_receipt" || fail "7 lượt task gọi mark_merge_gate_receipt: $(cat "$MARK")"
SB_MARK_VERIFIED_TREE=1 CLAUDE_PROJECT_DIR="$TMP/wt2" python3 "$GATE" --run-tests --full --no-checklist --diff origin/main >"$TMP/gate" 2>&1 \
  || fail "7 tiền đề: --full --diff origin/main exit $?"
grep -q -- "--mark" "$MARK" 2>/dev/null && ok "7 đối chứng: --full --diff origin/main gọi mark_merge_gate_receipt" \
  || fail "7 đối chứng: --full --diff origin/main không gọi mark_merge_gate_receipt (đầu dò hỏng)"

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
