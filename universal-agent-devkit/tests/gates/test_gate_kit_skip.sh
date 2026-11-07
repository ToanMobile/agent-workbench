#!/usr/bin/env bash
# Test hồi quy (gate speed v16, mục 4 và [smoke] của 5b): [smoke] rời lượt --scoped; diff không chạm file kit thì run_impacted.sh không ép test consistency,
# hàng KIT chỉ ở lại khi còn test; lượt thu hẹp hết thì exit 0.
#   a  diff code app có luật riêng: chỉ suite app; biên nhận không ghi smoke
#   b  decide chọn test kit cho file app: hàng KIT giữ, chạy đúng test đó, không test consistency, không smoke
#   c  diff chỉ tài liệu: 0 suite, exit 0, in "0 test liên quan", biên nhận scoped vẫn ghi (không exit 2 no_match)
#   d  .claude/settings.json bẩn cục bộ không làm diff thành "chạm kit" (nhìn theo HEAD như decide)
#   e  diff chạm kit: test trực tiếp và consistency chạy, smoke không
#   f  is_kit_path nhận đúng danh sách
#   g  run_impacted.sh: cờ bỏ test consistency, đọc một lần; không cờ vẫn thêm; suite khác không thấy cờ
#   h  [core-smoke] thêm sau cap (test py không chạy được) trùng test cap đã hoãn: chạy, và không còn trong deferred_to_heavy
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
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_repo() {   # kit giả + app/: test_app_reader.sh chạy app/reader.py; app/solo.py chỉ có luật ma trận riêng
  local R="$1" KIT="$1/universal-agent-devkit"
  mkdir -p "$KIT/tests/gates" "$KIT/tests/verification" "$KIT/tests/lib" "$KIT/lib" "$R/.agents" "$R/app" "$R/docs" "$R/.claude"
  git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; echo '# trống' > "$KIT/tests/impact_map.txt"
  cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
  ln -s "$DEVKIT_DIR/bin" "$KIT/bin"
  printf 'echo x >> %s/ran.consistency\n' "$TMP" > "$KIT/tests/verification/test_repo_consistency.sh"
  printf 'echo x >> %s/ran.smoke\n' "$TMP" > "$KIT/tests/gates/test_smoke.sh"
  echo v1 > "$KIT/lib/shared.txt"
  printf 'grep -q v "$(dirname "$0")/../../lib/shared.txt"\necho x >> %s/ran.kit\n' "$TMP" > "$KIT/tests/gates/test_kit.sh"
  printf 'python3 "$(dirname "$0")/../../../app/reader.py"\necho x >> %s/ran.reader\n' "$TMP" > "$KIT/tests/gates/test_app_reader.sh"
  printf 'print(1)\n' > "$R/app/reader.py"; printf 'print(1)\n' > "$R/app/solo.py"
  printf 'echo x >> %s/ran.app\n' "$TMP" > "$R/app/check.sh"
  echo '# docs' > "$R/docs/a.md"
  echo '{}' > "$R/.claude/settings.json"
  printf '.claude/audit-gate/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n' > "$R/.gitignore"
  echo '{"profile":"backend"}' > "$R/.agents/active-profile.json"
  printf '[core]\n.agents/gate-core.txt\n\n[smoke]\nuniversal-agent-devkit/tests/verification/test_repo_consistency.sh\nuniversal-agent-devkit/tests/gates/test_smoke.sh\n' > "$R/.agents/gate-core.txt"
  python3 - "$R/.agents/regression_matrix.active.json" <<'PY'
import json, sys
json.dump({"project": "t", "rules": [
    {"component": "app", "watch_files": ["app/solo.py"], "mandatory_regression_tests": [{"id": "REG-APP", "name": "app", "command": "bash app/check.sh", "parallel_safe": True}]},
    {"component": "reader", "watch_files": ["app/reader.py"], "mandatory_regression_tests": [{"id": "REG-READER", "name": "reader", "command": "true"}]},
    {"component": "cfg", "watch_files": ["universal-agent-devkit/*", ".agents/gate-core.txt"], "mandatory_regression_tests": [{"id": "REG-KIT-CFG", "name": "cfg", "command": "true"}]},
    {"component": "kit", "watch_files": ["universal-agent-devkit/tests/run_impacted.sh"],
     "mandatory_regression_tests": [{"id": "REG-DK-ALL-KIT-01", "name": "kit", "command": "bash universal-agent-devkit/tests/run_impacted.sh", "parallel_safe": True}]}]},
    open(sys.argv[1], "w"))
PY
  git -C "$R" add -A && git -C "$R" commit -qm init && git -C "$R" checkout -q -b f
}
gate() { local R="$1"; rm -f "$TMP"/ran.*; ( cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --no-checklist --json --scoped --diff main >"$TMP/out" 2>&1 ); RC=$?
  LC_ALL=C grep -a '^{.*"exit_code"' "$TMP/out" | tail -1 > "$TMP/j"; }
ids() { python3 -c 'import json,sys; print(",".join(sorted(t["id"] for t in json.load(open(sys.argv[1]))["regression_tests"] if t.get("command"))))' "$TMP/j"; }
receipt() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1/.git/postfix-gate/scoped_pass.json" "$2" 2>&1; }
ran() { [ -s "$TMP/ran.$1" ]; }

# a
R="$TMP/a"; new_repo "$R"; echo 'print(2)' > "$R/app/solo.py"; git -C "$R" commit -qam e
gate "$R"
[ "$RC" -eq 0 ] && [ "$(ids)" = REG-APP ] && ok "a. chỉ suite app" || { fail "a. rc=$RC suite=$(ids)"; tail -15 "$TMP/out"; }
ran smoke && fail "a. smoke vẫn chạy" || ok "a. không smoke"
ran consistency && fail "a. consistency vẫn chạy" || ok "a. không consistency"
[ "$(receipt "$R" 'd["smoke"]')" = "[]" ] && ok "a. biên nhận không ghi smoke" || fail "a. biên nhận smoke: $(receipt "$R" 'd.get("smoke")')"

# b
R="$TMP/b"; new_repo "$R"; echo 'print(2)' > "$R/app/reader.py"; git -C "$R" commit -qam e
gate "$R"
[ "$RC" -eq 0 ] && [ "$(ids)" = "REG-DK-ALL-KIT-01,REG-READER" ] && ok "b. hàng KIT giữ" || { fail "b. rc=$RC suite=$(ids)"; tail -15 "$TMP/out"; }
ran reader && ok "b. test của decide chạy" || fail "b. test_app_reader không chạy"
ran consistency && fail "b. consistency vẫn chạy" || ok "b. cờ bỏ consistency"
ran smoke && fail "b. smoke vẫn chạy" || ok "b. không smoke"

# c
R="$TMP/c"; new_repo "$R"; echo '# đổi' >> "$R/docs/a.md"; git -C "$R" commit -qam e
gate "$R"
[ "$RC" -eq 0 ] && ok "c. chỉ tài liệu: exit 0" || { fail "c. rc=$RC"; tail -15 "$TMP/out"; }
[ -z "$(ids)" ] && ok "c. 0 suite" || fail "c. suite: $(ids)"
LC_ALL=C grep -aq "0 test liên quan\|0 related tests" "$TMP/out" && ok "c. in 0 test liên quan" || fail "c. thiếu dòng 0 test liên quan"
[ "$(receipt "$R" 'd["exit"]')" = 0 ] && ok "c. biên nhận scoped exit 0" || fail "c. biên nhận: $(receipt "$R" 'd.get("exit")')"

# d
R="$TMP/d"; new_repo "$R"; echo 'print(2)' > "$R/app/solo.py"; git -C "$R" commit -qam e; echo '{"x":1}' > "$R/.claude/settings.json"
gate "$R"
ran smoke && fail "d. settings.json bẩn kéo smoke" || ok "d. settings.json bẩn không tính là chạm kit"

# e
R="$TMP/e"; new_repo "$R"; echo v2 > "$R/universal-agent-devkit/lib/shared.txt"; git -C "$R" commit -qam e
gate "$R"
ran consistency && ran kit && ok "e. diff chạm kit: consistency, test kit chạy" || { fail "e. rc=$RC suite=$(ids)"; tail -15 "$TMP/out"; }
ran smoke && fail "e. smoke vẫn chạy" || ok "e. [smoke] rời lượt --scoped"

# h: [core-smoke] thêm SAU cap (test py không luật nào chạy được) mà trùng một test cap đã hoãn: nó chạy, nên không còn trong deferred_to_heavy
R="$TMP/h"; new_repo "$R"
printf 'python3 "$(dirname "$0")/../../../app/reader.py"\necho x >> %s/ran.second\n' "$TMP" > "$R/universal-agent-devkit/tests/gates/test_second_runner.sh"
mkdir -p "$R/tests"; printf 'from app import reader\n\ndef test_x():\n    assert True\n' > "$R/tests/test_reader.py"
printf '\n[core-smoke]\nuniversal-agent-devkit/tests/gates/test_second_runner.sh\n' >> "$R/.agents/gate-core.txt"
git -C "$R" add -A; git -C "$R" commit -qm h0; git -C "$R" branch -qf main HEAD
echo 'print(3)' > "$R/app/reader.py"; git -C "$R" commit -qam e
gate "$R"
D="$(receipt "$R" 'd["deferred_to_heavy"]["tests"]')"; NR="$(receipt "$R" 'd["not_run"]')"
case "$NR" in *test_reader.py*) ok "h. test py không chạy được ⇒ [core-smoke] sau cap" ;; *) fail "h. dựng ca hỏng: not_run=$NR rc=$RC"; tail -15 "$TMP/out" ;; esac
ran second && ok "h. test [core-smoke] chạy" || fail "h. test [core-smoke] không chạy"
case "$D" in *test_second_runner.sh*) fail "h. test [core-smoke] đã chạy vẫn nằm trong deferred_to_heavy: $D" ;; *) ok "h. deferred_to_heavy không ghi test đã chạy ($D)" ;; esac

# f
F="$(python3 - "$DEVKIT_DIR/bin" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import scoped_gate as g
kit = ["universal-agent-devkit/x", ".agents/devkit/x", ".claude/hooks/x", ".claude/settings.json", ".claude/settings.local.json", ".claude/bin/x", ".claude/workflows/x",
       ".claude/skills/x", ".claude/super-board/x", ".claude/commands/x", ".githooks/x", "tests/super-board/x", "AGENTS.md", "CLAUDE.md", ".agents/context/x", ".agents/gate-core.txt",
       ".agents/regression_matrix.active.json"]
print("iskit", all(g.is_kit_path(p) for p in kit))
print("notkit", any(g.is_kit_path(p) for p in ["src/a.py", ".gitignore", ".github/scripts/x.py", "mcp-servers/a.js", "docs/AGENTS.md", ".claude/other"]))
PY
)"
case "$F" in *"iskit True"*"notkit False"*) ok "f. đường dẫn kit đúng danh sách" ;; *) fail "f. $F" ;; esac

# g
K="$TMP/g"; mkdir -p "$K/tests/gates" "$K/tests/verification" "$K/tests/lib"; git -C "$K" init -q -b main . && git -C "$K" config user.email t@t && git -C "$K" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K/tests/run_impacted.sh"; echo '# trống' > "$K/tests/impact_map.txt"
echo true > "$K/tests/verification/test_repo_consistency.sh"; echo true > "$K/tests/gates/test_a.sh"
git -C "$K" add -A && git -C "$K" commit -qm init
L1="$(DEVKIT_SCOPED_TESTS=tests/gates/test_a.sh DEVKIT_SCOPED_NO_CONSISTENCY=1 bash "$K/tests/run_impacted.sh" --list | tr '\n' ' ')"
L2="$(DEVKIT_SCOPED_TESTS=tests/gates/test_a.sh bash "$K/tests/run_impacted.sh" --list | tr '\n' ' ')"
L3="$(DEVKIT_SCOPED_TESTS= DEVKIT_SCOPED_NO_CONSISTENCY=1 bash "$K/tests/run_impacted.sh" --list | tr '\n' ' ')"
[ "$L1" = "tests/gates/test_a.sh " ] && ok "g. cờ bỏ consistency" || fail "g. có cờ: $L1"
[ "$L2" = "tests/gates/test_a.sh tests/verification/test_repo_consistency.sh " ] && ok "g. không cờ vẫn thêm consistency" || fail "g. không cờ: $L2"
[ -z "$L3" ] && ok "g. danh sách rỗng + cờ: không test nào" || fail "g. rỗng: $L3"
G="$(python3 - "$GATE" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("pfg_skip", sys.argv[1]); m = importlib.util.module_from_spec(spec)
sys.modules["pfg_skip"] = m; spec.loader.exec_module(m)
os.environ["DEVKIT_SCOPED_NO_CONSISTENCY"] = "1"
print("env_dropped", "DEVKIT_SCOPED_NO_CONSISTENCY" not in m.suite_env())
print("in_key", "DEVKIT_SCOPED_NO_CONSISTENCY" in m.SELECTION_ENV)
PY
)"
case "$G" in *"env_dropped True"*"in_key True"*) ok "g. cờ không lọt xuống suite khác, có trong khoá chọn test" ;; *) fail "g. $G" ;; esac

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
