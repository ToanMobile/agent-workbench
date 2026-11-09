#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 1): proof_gate.sh nhận biên nhận scoped RỖNG (lượt --scoped không có test liên quan: tests [],
# scoped_tests / smoke / core_smoke rỗng) của một lượt TRƯỚC khi cây không đổi, như tree_fp.receipt_for_tree nhận nó ở Stop.
#   a  đổi docs, gate --scoped exit 0 (tests []), lượt sau XONG cùng cây ⇒ cho qua
#   b  biên nhận scoped tests [] mà scoped_tests không rỗng (ghi tay) ⇒ vẫn chặn
#   c  đối chứng: sửa cây sau lượt gate ⇒ chặn
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_SESSION_ID \
      CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_SLOT_PRIORITY CLAUDE_PROJECT_DIR
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/r"; TR="$TMP/transcript.jsonl"
git init -q --bare -b main "$REPO.git" && git clone -q "$REPO.git" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src .agents docs
  echo "def ok(): return 1" > src/core.py && echo hi > docs/a.md
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n' > .gitignore
  echo '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}' \
    > .agents/regression_matrix.active.json
  git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
  git checkout -q -b feature && echo bye > docs/a.md && git commit -qam docs ) || exit 1
turn_start() { sleep 1; python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X"}}))' > "$TR"; }
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 [x] PASS.
3. Nguy cơ bug mới: đã rà caller, không tác dụng phụ.
4. An toàn mã nguồn: secret 0, placeholder 0."
XR="XONG
Đã sửa lỗi X.
Gate exit 0 · ảnh: không cần (profile backend)
$REPORT"
stop() {
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-p","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "$XR" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; RC=$?
  rm -f "$REPO/.claude/audit-gate/proof_gate.state"
}
SP="$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate/scoped_pass.json"

( cd "$REPO" && python3 "$GATE" --run-tests --scoped --brief ) >"$TMP/gout" 2>&1; G=$?
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("tests") == [] and not d.get("scoped_tests") else 1)' "$SP" \
  && [ "$G" -eq 0 ] && ok "setup. gate --scoped exit 0 ghi biên nhận scoped rỗng" || { fail "setup. gate=$G"; tail -20 "$TMP/gout"; }
sleep 1; turn_start
stop
[ "$RC" -eq 0 ] && ok "a. biên nhận scoped rỗng của lượt trước, cùng cây ⇒ XONG qua" || fail "a. rc=$RC err=$(head -3 "$TMP/err" | tr '\n' ' ')"

cp "$SP" "$TMP/sp.bak"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["scoped_tests"]=["tests/t.sh"]; json.dump(d, open(p, "w"))' "$SP"
stop
[ "$RC" -eq 2 ] && ok "b. tests [] mà scoped_tests không rỗng ⇒ chặn" || fail "b. rc=$RC"
cp "$TMP/sp.bak" "$SP"

echo more >> "$REPO/docs/a.md"
stop
[ "$RC" -eq 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "c. cây đổi sau gate ⇒ chặn" || fail "c. rc=$RC err=$(head -3 "$TMP/err" | tr '\n' ' ')"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
