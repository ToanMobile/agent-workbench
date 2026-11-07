#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 1): Stop hook regression_gate.sh KHÔNG chạy suite nào; nó cho dừng theo biên nhận / kết luận mà lượt
# gate của agent (post-fix-gate --run-tests --scoped) đã ghi, và chặn khi không có.
#   a  thay đổi chưa có biên nhận ⇒ chặn, KHÔNG suite nào chạy (lệnh ma trận ghi marker), lời chặn nêu lệnh gate --scoped
#   b  chạy gate (exit 0) ⇒ Stop cho dừng, verified_head = HEAD
#   c  sửa tiếp sau gate ⇒ chặn lại; MAX_ATTEMPTS=2 rồi cho dừng kèm cảnh báo
#   d  nhánh đích không origin: hai commit sau verified_head, biên nhận từ --diff HEAD~ ⇒ chưa phủ, chặn, lệnh nêu --diff <vh>;
#      gate --diff <vh> ⇒ cho dừng
#   e  nhánh feature: biên nhận task (base = merge-base với origin/main) ⇒ cho dừng
#   f  outcome test có sẵn bị sửa ⇒ chặn một lần, lần sau chỉ nhắc
#   g  outcome exit 3 trên base phủ dải ⇒ cho dừng; outcome exit 3 base không phủ ⇒ chặn
#   h  chỉ đổi README.md (không luật ma trận theo dõi) ⇒ cho dừng không cần biên nhận
#   i  repo PR (super-board), nhánh đã push, cây sạch ⇒ cho dừng; bẩn ⇒ lệnh là commit rồi `git push`
#   j  gate đỏ (exit 1) ⇒ không biên nhận ⇒ chặn
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID DEVKIT_SLOT_PRIORITY DEVKIT_GATE_CACHE_MAX_S REGRESSION_GATE \
      DEVKIT_GATE_EVERY_STOP SB_BOARD_WORKER CLAUDE_PROJECT_DIR
export WORKTREE_TRUNK_MODE=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
MARK="$TMP/suite-ran"

new_repo() {   # new_repo <dir> [origin]: ma trận đã commit, suite REG-1 ghi marker rồi chạy result.sh
  local d="$1"
  if [ "${2:-}" = origin ]; then git init -q --bare -b main "$d.git" && git clone -q "$d.git" "$d" 2>/dev/null || exit 1
  else mkdir -p "$d" && git -C "$d" init -q -b main || exit 1; fi
  ( cd "$d" && git config user.email t@t && git config user.name t && mkdir -p src .agents tests
    echo "def ok(): return 1" > src/core.py
    echo 'exit 0' > tests/result.sh
    echo '{"profile":"backend"}' > .agents/active-profile.json
    printf '.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n' > .gitignore
    printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> %s; sh tests/result.sh"}]}]}\n' "$MARK" \
      > .agents/regression_matrix.active.json
    git add -A && git commit -qm init
    if [ "${2:-}" = origin ]; then git push -q -u origin main 2>/dev/null; fi ) || exit 1
}
stop() {   # stop <repo>: Stop hook, rc vào RC
  printf '{"session_id":"s-1","hook_event_name":"Stop","last_assistant_message":"XONG"}' \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; RC=$?
}
gate() { ( cd "$1" && shift && python3 "$GATE" --run-tests --scoped --brief "$@" ) >"$TMP/gout" 2>&1; GRC=$?; }
vh_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verified_head",""))' "$1/.claude/audit-gate/regression_gate.state.json" 2>/dev/null; }

# a
R="$TMP/a"; new_repo "$R"
stop "$R"; [ "$RC" -eq 0 ] && ok "a0. cây sạch: cho dừng" || fail "a0. cây sạch rc=$RC $(cat "$TMP/err")"
echo "def ok(): return 2" > "$R/src/core.py"
rm -f "$MARK"
stop "$R"
[ "$RC" -eq 2 ] && ok "a. chưa có biên nhận ⇒ chặn" || fail "a. rc=$RC out=$(cat "$TMP/out") err=$(cat "$TMP/err")"
[ ! -e "$MARK" ] && ok "a. Stop không chạy suite nào" || fail "a. Stop đã chạy suite (marker có)"
grep -q -- "--run-tests --scoped --brief" "$TMP/err" && ! grep -q -- "--session" "$TMP/err" && ok "a. lời chặn nêu lệnh gate --scoped, không --session" \
  || fail "a. lệnh: $(cat "$TMP/err")"

# b
gate "$R"
[ "$GRC" -eq 0 ] && [ -e "$MARK" ] && ok "b. gate của agent chạy suite, exit 0" || { fail "b. gate rc=$GRC"; tail -20 "$TMP/gout"; }
rm -f "$MARK"
stop "$R"
[ "$RC" -eq 0 ] && [ ! -e "$MARK" ] && ok "b. biên nhận ⇒ cho dừng, không suite" || fail "b. rc=$RC err=$(cat "$TMP/err")"
[ "$(vh_of "$R")" = "$(git -C "$R" rev-parse HEAD)" ] && ok "b. verified_head = HEAD" || fail "b. vh=$(vh_of "$R")"

# c
echo "# more" >> "$R/src/core.py"
stop "$R"; r1=$RC; stop "$R"; r2=$RC; stop "$R"; r3=$RC
[ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$r3" = 0 ] && grep -q systemMessage "$TMP/out" && ok "c. sửa sau gate ⇒ chặn 2 lần rồi cho dừng có cảnh báo" \
  || fail "c. r1=$r1 r2=$r2 r3=$r3 out=$(cat "$TMP/out")"
[ ! -e "$MARK" ] && ok "c. vẫn không suite nào chạy ở Stop" || fail "c. marker có"

# d
R="$TMP/d"; new_repo "$R"
stop "$R"
V0="$(git -C "$R" rev-parse HEAD)"
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam c1 && echo "def ok(): return 3" > src/core.py && git commit -qam c2 )
gate "$R" --diff HEAD~
[ "$GRC" -eq 0 ] || { fail "d. gate --diff HEAD~ rc=$GRC"; tail -20 "$TMP/gout"; }
stop "$R"
[ "$RC" -eq 2 ] && grep -q -- "--diff $V0 --force" "$TMP/err" && ok "d. biên nhận không phủ c1 ⇒ chặn, lệnh nêu --diff <vh> --force" || fail "d. rc=$RC err=$(cat "$TMP/err")"
gate "$R" --diff "$V0" --force
stop "$R"
[ "$RC" -eq 0 ] && [ "$(vh_of "$R")" = "$(git -C "$R" rev-parse HEAD)" ] && ok "d. gate --diff <vh> ⇒ cho dừng, vh = HEAD" || fail "d2. rc=$RC err=$(cat "$TMP/err") vh=$(vh_of "$R")"

# e
R="$TMP/e"; new_repo "$R" origin
stop "$R"
( cd "$R" && git checkout -q -b feature && echo "def ok(): return 2" > src/core.py && git commit -qam f1 && echo "def ok(): return 3" > src/core.py && git commit -qam f2 )
stop "$R"; [ "$RC" -eq 2 ] && ok "e0. nhánh feature chưa gate ⇒ chặn" || fail "e0. rc=$RC"
gate "$R"
stop "$R"
[ "$RC" -eq 0 ] && ok "e. biên nhận task trên nhánh feature ⇒ cho dừng" || { fail "e. rc=$RC err=$(cat "$TMP/err") gate=$GRC"; tail -10 "$TMP/gout"; }

# f
R="$TMP/f"; new_repo "$R"
stop "$R"
echo 'echo changed; exit 0' > "$R/tests/result.sh"
gate "$R"
stop "$R"; r1=$RC; e1="$(cat "$TMP/err")"
stop "$R"; r2=$RC
[ "$GRC" -eq 2 ] && [ "$r1" = 2 ] && [ "$r2" = 0 ] && grep -q "Vẫn chờ người duyệt" "$TMP/out" && ok "f. test sửa ⇒ chặn một lần, sau đó nhắc" \
  || fail "f. gate=$GRC r1=$r1 r2=$r2 err1=$e1 out=$(cat "$TMP/out")"

# g
R="$TMP/g"; new_repo "$R"
stop "$R"
gate "$R"
[ "$GRC" -eq 3 ] || fail "g. mong exit 3, được $GRC"
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam g1 )
stop "$R"
[ "$RC" -eq 2 ] && ok "g. outcome exit 3 của cây cũ không dùng cho cây mới" || fail "g. rc=$RC"
python3 - "$DEVKIT_DIR/bin" "$R" "$(git -C "$R" rev-parse HEAD)" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1]); import tree_fp
p = os.path.join(os.path.dirname(tree_fp.receipt_path(sys.argv[2])), "outcomes", tree_fp.tree_fingerprint(sys.argv[2]) + ".json")
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump({"exit": 3, "reason": "nothing", "lines": ["nothing"], "base": sys.argv[3], "at": 0}, open(p, "w"))
PY
stop "$R"
[ "$RC" -eq 2 ] && ok "g. outcome exit 3 với base = HEAD không phủ commit g1 ⇒ chặn" || fail "g2. rc=$RC"
python3 - "$DEVKIT_DIR/bin" "$R" "$(git -C "$R" rev-parse HEAD~)" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1]); import tree_fp
p = os.path.join(os.path.dirname(tree_fp.receipt_path(sys.argv[2])), "outcomes", tree_fp.tree_fingerprint(sys.argv[2]) + ".json")
json.dump({"exit": 3, "reason": "nothing", "lines": ["nothing"], "base": sys.argv[3], "at": 0}, open(p, "w"))
PY
stop "$R"
[ "$RC" -eq 0 ] && ok "g. outcome exit 3 với base phủ dải ⇒ cho dừng" || fail "g3. rc=$RC err=$(cat "$TMP/err")"

# h
R="$TMP/h"; new_repo "$R"
stop "$R"
echo "# notes" > "$R/README.md"
stop "$R"
[ "$RC" -eq 0 ] && ok "h. chỉ README.md đổi ⇒ cho dừng không biên nhận" || fail "h. rc=$RC err=$(cat "$TMP/err")"

# i
R="$TMP/i"; new_repo "$R" origin
( cd "$R" && mkdir -p .claude/super-board/configs && echo '{"base_branch":"main"}' > .claude/super-board/configs/t.json \
  && git add -f .claude/super-board/configs/t.json && git commit -qm board && git push -q 2>/dev/null )
stop "$R"
( cd "$R" && git checkout -q -b issue-1 && echo "def ok(): return 2" > src/core.py && git commit -qam i1 )
stop "$R"
[ "$RC" -eq 2 ] && grep -q "git push" "$TMP/err" && ! grep -q -- "--run-tests" "$TMP/err" && ok "i. repo PR chưa push ⇒ chặn, lệnh là git push" \
  || fail "i. rc=$RC err=$(cat "$TMP/err")"
git -C "$R" push -q -u origin issue-1 2>/dev/null
stop "$R"
[ "$RC" -eq 0 ] && ok "i. repo PR, nhánh đã push, cây sạch ⇒ cho dừng" || fail "i2. rc=$RC err=$(cat "$TMP/err")"
echo "# x" >> "$R/src/core.py"
stop "$R"
[ "$RC" -eq 2 ] && grep -q "commit" "$TMP/err" && grep -q "git push" "$TMP/err" && ok "i. repo PR bẩn ⇒ lệnh commit rồi git push" || fail "i3. rc=$RC err=$(cat "$TMP/err")"

# j
R="$TMP/j"; new_repo "$R"
stop "$R"
echo 'exit 1' > "$R/tests/result.sh"; git -C "$R" commit -qam red
echo "def ok(): return 2" > "$R/src/core.py"
gate "$R"
stop "$R"
[ "$GRC" -eq 1 ] && [ "$RC" -eq 2 ] && ok "j. gate đỏ ⇒ không biên nhận ⇒ chặn" || fail "j. gate=$GRC rc=$RC"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
