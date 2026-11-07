#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 1): tree_fp.receipt_for_tree, một hàm Stop hook dùng thay cho chạy suite, nhận đúng biên nhận mà
# post-fix-gate.py THẬT ghi (không JSON viết tay: công thức local_sha / matrix_sha / gate_sha phải khớp gate) và từ chối khi cây đổi.
#   a  lượt --scoped exit 0 trên nhánh feature ⇒ có biên nhận cho cây, base là sha commit
#   b  sửa một file sau lượt gate ⇒ không còn biên nhận
#   c  thêm .env (bị git ignore) ⇒ local_sha khác ⇒ không nhận
#   d  sửa ma trận chưa commit ⇒ không nhận; ma trận khác (matrix_sha) ⇒ không nhận
#   e  gate khác (gate_sha) ⇒ không nhận
#   f  lượt chỉ đổi docs (0 test liên quan, tests: []) ⇒ biên nhận scoped rỗng vẫn được nhận
#   g  nhánh đích với --diff HEAD~ ⇒ biên nhận scoped, base = HEAD~
#   h  lượt đỏ (exit 1) ⇒ không có biên nhận
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_SLOT_PRIORITY DEVKIT_GATE_CACHE_MAX_S
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_repo() {   # new_repo <dir> <lệnh suite>: origin + clone, nhánh feature
  local d="$1" cmd="$2"
  git init -q --bare -b main "$d.git" && git clone -q "$d.git" "$d" 2>/dev/null || exit 1
  ( cd "$d" && git config user.email t@t && git config user.name t && mkdir -p src .agents docs
    echo "def ok(): return 1" > src/core.py
    echo hi > docs/a.md
    echo '{"profile":"backend"}' > .agents/active-profile.json
    printf '.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n.env\n' > .gitignore
    printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"%s"}]}]}\n' "$cmd" \
      > .agents/regression_matrix.active.json
    git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
    git checkout -q -b feature ) || exit 1
}
gate() { ( cd "$1" && shift && python3 "$GATE" --run-tests --scoped --brief "$@" ) >"$TMP/out" 2>&1; }
rft() {   # rft <repo> [gate] [matrix]: in "<kind> <base>" hoặc "none <lý do>"
  python3 - "$DEVKIT_DIR/bin" "$1" "${2:-$GATE}" "${3:-}" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import tree_fp
why = []
r = tree_fp.receipt_for_tree(sys.argv[2], gate=sys.argv[3], matrix=sys.argv[4] or None, why=why)
print("%s %s" % (r["_kind"], r["_base"]) if r else "none " + ";".join(w.rsplit("/", 1)[-1] for w in why)[:300])
PY
}

R="$TMP/a"; new_repo "$R" true
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam edit )
gate "$R"; RC=$?
MB="$(git -C "$R" merge-base HEAD origin/main)"
got="$(rft "$R")"
[ "$RC" -eq 0 ] && case "$got" in "scoped $MB"|"task $MB") true ;; *) false ;; esac \
  && ok "a. lượt --scoped exit 0 ⇒ biên nhận của cây ($got)" || { fail "a. rc=$RC got=$got"; tail -20 "$TMP/out"; }

( cd "$R" && echo "# later" >> src/core.py )
case "$(rft "$R")" in none*) ok "b. sửa file sau gate ⇒ không biên nhận" ;; *) fail "b. vẫn nhận: $(rft "$R")" ;; esac
( cd "$R" && git checkout -q -- src/core.py )
case "$(rft "$R")" in none*) fail "b2. khôi phục mà mất biên nhận: $(rft "$R")" ;; *) ok "b2. khôi phục nội dung ⇒ nhận lại" ;; esac

( cd "$R" && echo "KEY=1" > .env )
case "$(rft "$R")" in none*local_sha*) ok "c. .env mới ⇒ local_sha khác, không nhận" ;; *) fail "c. $(rft "$R")" ;; esac
rm -f "$R/.env"

cp "$R/.agents/regression_matrix.active.json" "$TMP/m.bak"
( cd "$R" && sed -i.bak 's/"core"/"core2"/' .agents/regression_matrix.active.json && rm -f .agents/regression_matrix.active.json.bak )
case "$(rft "$R")" in none*) ok "d. ma trận sửa ⇒ không nhận" ;; *) fail "d. $(rft "$R")" ;; esac
cp "$TMP/m.bak" "$R/.agents/regression_matrix.active.json"
echo '{"rules":[]}' > "$TMP/other-matrix.json"
case "$(rft "$R" "$GATE" "$TMP/other-matrix.json")" in none*matrix_sha*) ok "d2. ma trận khác (matrix_sha) ⇒ không nhận" ;; *) fail "d2. $(rft "$R" "$GATE" "$TMP/other-matrix.json")" ;; esac

cp "$GATE" "$TMP/other-gate.py" && echo "# other" >> "$TMP/other-gate.py"
case "$(rft "$R" "$TMP/other-gate.py")" in none*gate_sha*) ok "e. gate khác ⇒ không nhận" ;; *) fail "e. $(rft "$R" "$TMP/other-gate.py")" ;; esac

R="$TMP/f"; new_repo "$R" true
( cd "$R" && echo bye > docs/a.md && git commit -qam docs )
gate "$R"; RC=$?
got="$(rft "$R")"
[ "$RC" -eq 0 ] && case "$got" in none*) false ;; *) true ;; esac && ok "f. lượt 0 test liên quan ⇒ biên nhận rỗng được nhận ($got)" \
  || { fail "f. rc=$RC got=$got"; tail -20 "$TMP/out"; }

R="$TMP/g"; new_repo "$R" true
( cd "$R" && git checkout -q main && echo "def ok(): return 3" > src/core.py && git commit -qam e3 )
gate "$R" --diff HEAD~; RC=$?
got="$(rft "$R")"
[ "$RC" -eq 0 ] && [ "$got" = "scoped $(git -C "$R" rev-parse HEAD~)" ] && ok "g. nhánh đích --diff HEAD~ ⇒ scoped, base HEAD~" || { fail "g. rc=$RC got=$got"; tail -20 "$TMP/out"; }

R="$TMP/h"; new_repo "$R" "exit 7"
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam edit )
gate "$R"; RC=$?
case "$(rft "$R")" in none*) [ "$RC" -eq 1 ] && ok "h. lượt đỏ ⇒ không biên nhận" || fail "h. rc=$RC" ;; *) fail "h. lượt đỏ vẫn có biên nhận: $(rft "$R")" ;; esac

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
