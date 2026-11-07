#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 7): guard của điểm gộp. Mục [merge-guard] của .agents/gate-core.txt (∪ mục của base) tiêm vào lượt --scoped
# CHỈ ở thư mục scratch điểm gộp (.merge-scratch-*), sau cap, chạy thật mỗi lượt.
#   a  diff chỉ tài liệu ở .merge-scratch-*: guard vẫn chạy, exit 0
#   b  lượt thứ hai trên đúng cây đó: guard chạy lại (không rerun-skip, không biên nhận, không khoá cùng cây)
#   c  không phải điểm gộp: guard không chạy
#   d  id có trong [merge-guard] mà ma trận không có: exit 1, dòng đỏ mang id
#   e  PR xoá id khỏi [merge-guard] (base vẫn có): guard vẫn chạy
#   f  guard là suite kit bị cap hoãn: chạy đúng một lần, không nằm trong deferred_to_heavy của biên nhận
#   g  merge_guard_ids: hợp cây này với base, thứ tự cây trước
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI FLAKY_RETRY DEVKIT_GATE_PARALLEL DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE \
      DEVKIT_IMPACTED_DIRS DEVKIT_SCOPED_TESTS DEVKIT_SCOPED_NO_CONSISTENCY DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_PER_TEST_CACHE \
      POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1; mkdir -p "$SB_HEAVY_SLOT_DIR"
export DEVKIT_MERGE_POINT=1   # at_merge_point cần dấu này (merge gate / train / integrate đặt) cùng đường dẫn .merge-scratch-*
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_repo() {   # $1 = thư mục repo; $2 = danh sách id [merge-guard]
  local R="$1" KIT="$1/universal-agent-devkit"
  mkdir -p "$KIT/tests/gates" "$KIT/tests/verification" "$KIT/tests/lib" "$KIT/lib" "$R/.agents" "$R/docs"
  git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; echo '# trống' > "$KIT/tests/impact_map.txt"
  cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
  ln -s "$DEVKIT_DIR/bin" "$KIT/bin"
  echo true > "$KIT/tests/verification/test_repo_consistency.sh"
  printf 'echo x >> %s/ran.guard\n' "$TMP" > "$KIT/tests/gates/test_guard.sh"
  echo v1 > "$KIT/lib/shared.txt"
  echo '# docs' > "$R/docs/a.md"
  printf '.claude/audit-gate/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n' > "$R/.gitignore"
  echo '{"profile":"backend"}' > "$R/.agents/active-profile.json"
  printf '[core]\n.agents/gate-core.txt\n\n[merge-guard]\n# guard\n' > "$R/.agents/gate-core.txt"
  for g in $2; do echo "$g" >> "$R/.agents/gate-core.txt"; done
  python3 - "$R/.agents/regression_matrix.active.json" <<'PY'
import json, sys
json.dump({"project": "t", "rules": [
    {"component": "guard", "watch_files": ["universal-agent-devkit/lib/*"],
     "mandatory_regression_tests": [{"id": "REG-G1", "name": "guard", "command": "bash universal-agent-devkit/tests/gates/test_guard.sh", "parallel_safe": True}]},
    {"component": "kit", "watch_files": ["universal-agent-devkit/tests/run_impacted.sh"],
     "mandatory_regression_tests": [{"id": "REG-DK-ALL-KIT-01", "name": "kit", "command": "bash universal-agent-devkit/tests/run_impacted.sh", "parallel_safe": True}]}]},
    open(sys.argv[1], "w"))
PY
  git -C "$R" add -A && git -C "$R" commit -qm init && git -C "$R" checkout -q -b f
}
gate() { local R="$1"; ( cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --no-checklist --json --scoped --diff main >"$TMP/out" 2>&1 ); RC=$?; }
nguard() { if [ -f "$TMP/ran.guard" ]; then wc -l < "$TMP/ran.guard" | tr -d ' '; else echo 0; fi; }
receipt() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1/.git/postfix-gate/scoped_pass.json" "$2" 2>&1; }

# a, b
R="$TMP/.merge-scratch-a"; new_repo "$R" "REG-G1"; echo '# đổi' >> "$R/docs/a.md"; git -C "$R" commit -qam e
rm -f "$TMP/ran.guard"; gate "$R"
[ "$RC" -eq 0 ] && [ "$(nguard)" = 1 ] && ok "a. tài liệu ở điểm gộp: guard chạy, exit 0" || { fail "a. rc=$RC guard=$(nguard)"; tail -15 "$TMP/out"; }
gate "$R"
[ "$RC" -eq 0 ] && [ "$(nguard)" = 2 ] && ok "b. lượt hai cùng cây: guard chạy lại" || { fail "b. rc=$RC guard=$(nguard)"; tail -15 "$TMP/out"; }

# c
R="$TMP/plain-c"; new_repo "$R" "REG-G1"; echo '# đổi' >> "$R/docs/a.md"; git -C "$R" commit -qam e
rm -f "$TMP/ran.guard"; gate "$R"
[ "$RC" -eq 0 ] && [ "$(nguard)" = 0 ] && ok "c. ngoài điểm gộp: guard không chạy" || { fail "c. rc=$RC guard=$(nguard)"; tail -15 "$TMP/out"; }

# d
R="$TMP/.merge-scratch-d"; new_repo "$R" "REG-G1 REG-GONE-01"; echo '# đổi' >> "$R/docs/a.md"; git -C "$R" commit -qam e
rm -f "$TMP/ran.guard"; gate "$R"
[ "$RC" -eq 1 ] && LC_ALL=C grep -aq "REG-GONE-01" "$TMP/out" && ok "d. id thiếu trong ma trận: exit 1, nêu id" || { fail "d. rc=$RC"; tail -15 "$TMP/out"; }

# e
R="$TMP/.merge-scratch-e"; new_repo "$R" "REG-G1"
python3 - "$R/.agents/gate-core.txt" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read().replace("REG-G1\n", ""); open(p, "w").write(s)
PY
echo '# đổi' >> "$R/docs/a.md"; git -C "$R" commit -qam e
rm -f "$TMP/ran.guard"; gate "$R"
[ "$(nguard)" = 1 ] && ok "e. PR xoá id, base còn: guard vẫn chạy" || { fail "e. rc=$RC guard=$(nguard)"; tail -15 "$TMP/out"; }

# f
R="$TMP/.merge-scratch-f"; new_repo "$R" "REG-G1"; echo v2 > "$R/universal-agent-devkit/lib/shared.txt"; git -C "$R" commit -qam e
rm -f "$TMP/ran.guard"; gate "$R"
[ "$RC" -eq 0 ] && [ "$(nguard)" = 1 ] && ok "f. guard kit bị cap hoãn: chạy đúng một lần" || { fail "f. rc=$RC guard=$(nguard)"; tail -15 "$TMP/out"; }
D="$(receipt "$R" 'd["deferred_to_heavy"]["suites"]')"
case "$D" in *REG-G1*) fail "f. guard trong deferred_to_heavy: $D" ;; *) ok "f. guard không nằm trong deferred_to_heavy ($D)" ;; esac

# g
R="$TMP/g"; new_repo "$R" "REG-A REG-B"
printf '[merge-guard]\nREG-C\nREG-A\n' > "$R/.agents/gate-core.txt"
G="$(cd "$R" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import scoped_gate as g; print(g.merge_guard_ids(".", "main"), g.merge_guard_ids("."))' "$DEVKIT_DIR/bin" 2>&1)"
[ "$G" = "['REG-C', 'REG-A', 'REG-B'] ['REG-C', 'REG-A']" ] && ok "g. hợp với base, cây này trước" || fail "g. $G"
# g2: merge_guards (gate_full._scoped_pick dùng chung): dòng ma trận, id thiếu, test lệnh guard nêu tên
G2="$(cd "$R" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import scoped_gate as g
rules = [{"component": "c", "mandatory_regression_tests": [{"id": "REG-A", "command": "bash universal-agent-devkit/tests/gates/test_guard.sh"}]}]
m = g.merge_guards(".", rules, "main"); print(m["ids"], [t["id"] for _, t in m["rows"]], m["missing"], m["tests"])' "$DEVKIT_DIR/bin" 2>&1)"
[ "$G2" = "['REG-C', 'REG-A', 'REG-B'] ['REG-A'] ['REG-C', 'REG-B'] ['universal-agent-devkit/tests/gates/test_guard.sh']" ] \
  && ok "g2. merge_guards: dòng, id thiếu, test" || fail "g2. $G2"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
