#!/usr/bin/env bash
# Test hồi quy (gate speed v14, mục 5a): lượt --scoped chạy test kit qua MỘT suite REG-DK-ALL-KIT-01, không qua ba shard.
#   a  diff chạm kit: có KIT, không shard; KIT chạy đúng test đã chọn
#   b  ma trận chưa có hàng KIT (app, fixture cũ): shard giữ như cũ
#   c  --tree: shard chạy, hàng KIT không chạy (không chạy hai lần), kể cả khi run_impacted.sh đổi ở --full
#   d  SUITE_TIMEOUT_FACTOR của KIT = của shard GATES; SCOPED-EXTRA parallel_safe
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI FLAKY_RETRY DEVKIT_GATE_PARALLEL DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE \
      DEVKIT_IMPACTED_DIRS DEVKIT_SCOPED_TESTS DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_PER_TEST_CACHE \
      POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1; mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_repo() {   # new_repo <dir> <with_kit_row 0|1>
  local R="$1" KIT="$1/universal-agent-devkit"
  mkdir -p "$KIT/tests/gates" "$KIT/tests/verification" "$KIT/tests/lib" "$KIT/lib" "$R/.agents"
  git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; echo '# trống' > "$KIT/tests/impact_map.txt"
  cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
  ln -s "$DEVKIT_DIR/bin" "$KIT/bin"
  printf 'echo x >> %s/ran.consistency\n' "$TMP" > "$KIT/tests/verification/test_repo_consistency.sh"
  echo v1 > "$KIT/lib/shared.txt"
  printf 'grep -q v "$(dirname "$0")/../../lib/shared.txt"\necho x >> %s/ran.a\n' "$TMP" > "$KIT/tests/gates/test_a.sh"
  printf '.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n' > "$R/.gitignore"
  echo '{"profile":"backend"}' > "$R/.agents/active-profile.json"
  python3 - "$R/.agents/regression_matrix.active.json" "$2" <<'PY'
import json, sys
RUN = "bash universal-agent-devkit/tests/run_impacted.sh"
shard = lambda i, d: {"component": i, "watch_files": ["universal-agent-devkit/*"],
                      "mandatory_regression_tests": [{"id": i, "name": i, "command": "DEVKIT_IMPACTED_DIRS=%s %s" % (d, RUN), "parallel_safe": True}]}
rules = [shard("REG-DK-ALL-GATES-01", "gates"), shard("REG-DK-ALL-WORKTREE-01", "worktree_git"), shard("REG-DK-ALL-REST-01", "!gates,!worktree_git")]
if sys.argv[2] == "1":
    rules.append({"component": "kit", "watch_files": ["universal-agent-devkit/tests/run_impacted.sh"],
                  "mandatory_regression_tests": [{"id": "REG-DK-ALL-KIT-01", "name": "kit", "command": RUN, "parallel_safe": True}]})
json.dump({"project": "t", "rules": rules}, open(sys.argv[1], "w"))
PY
  git -C "$R" add -A && git -C "$R" commit -qm init
}
# gate <repo> [args]: JSON cuối vào $TMP/j, in "<rc>"; ids() đọc id suite
gate() { local R="$1"; shift; rm -f "$TMP"/ran.*; ( cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --no-checklist --json "$@" >"$TMP/out" 2>&1 ); RC=$?
  LC_ALL=C grep -a '^{.*"exit_code"' "$TMP/out" | tail -1 > "$TMP/j"; }
ids() { python3 -c 'import json,sys; print(",".join(sorted(t["id"] for t in json.load(open(sys.argv[1]))["regression_tests"] if t.get("command"))))' "$TMP/j"; }

# a
R="$TMP/a"; new_repo "$R" 1; git -C "$R" checkout -q -b f; echo v2 > "$R/universal-agent-devkit/lib/shared.txt"; git -C "$R" commit -qam e
gate "$R" --scoped --diff main
[ "$(ids)" = "REG-DK-ALL-KIT-01" ] && ok "a. có KIT, không shard" || { fail "a. suite: $(ids) rc=$RC"; tail -20 "$TMP/out"; }
[ -s "$TMP/ran.a" ] && ok "a. KIT chạy test đã chọn" || fail "a. test_a không chạy"
[ "$(wc -l < "$TMP/ran.a" 2>/dev/null | tr -d ' ')" = 1 ] && ok "a. test chạy đúng một lần" || fail "a. test_a chạy $(wc -l < "$TMP/ran.a" 2>/dev/null) lần"

# b
R="$TMP/b"; new_repo "$R" 0; git -C "$R" checkout -q -b f; echo v2 > "$R/universal-agent-devkit/lib/shared.txt"; git -C "$R" commit -qam e
gate "$R" --scoped --diff main
[ "$(ids)" = "REG-DK-ALL-GATES-01,REG-DK-ALL-REST-01,REG-DK-ALL-WORKTREE-01" ] && ok "b. không có hàng KIT: shard giữ nguyên" || fail "b. suite: $(ids) rc=$RC"

# c
R="$TMP/c"; new_repo "$R" 1
git init -q --bare -b main "$TMP/c.git" && git -C "$R" remote add origin "$TMP/c.git" && git -C "$R" push -q -u origin main 2>/dev/null   # --tree chỉ nhận cây đã có trên origin
gate "$R" --tree HEAD --no-cache
case ",$(ids)," in *,REG-DK-ALL-KIT-01,*) fail "c. --tree chạy hàng KIT: $(ids)" ;; *,REG-DK-ALL-GATES-01,*) ok "c. --tree: shard chạy, không hàng KIT" ;; *) fail "c. --tree: $(ids) rc=$RC"; tail -20 "$TMP/out" ;; esac
git -C "$R" checkout -q -b f; echo '# đổi' >> "$R/universal-agent-devkit/tests/run_impacted.sh"; git -C "$R" commit -qam e
gate "$R" --full --diff main --no-cache
case ",$(ids)," in *,REG-DK-ALL-KIT-01,*) fail "c. --full chạy hàng KIT: $(ids)" ;; *) ok "c. --full (run_impacted.sh đổi): không hàng KIT" ;; esac

# d
D="$(python3 - "$GATE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg_kit", sys.argv[1]); m = importlib.util.module_from_spec(spec)
sys.modules["pfg_kit"] = m; spec.loader.exec_module(m)
print("factor", m.SUITE_TIMEOUT_FACTOR.get("REG-DK-ALL-KIT-01") == m.SUITE_TIMEOUT_FACTOR.get("REG-DK-ALL-GATES-01") == 2)
added, _, _ = m.scoped_suites({"tests": ["other/test_o.sh"], "smoke": []}, [], [])
print("extra", [t.get("parallel_safe") for _, t in added])
PY
)"
case "$D" in *"factor True"*) ok "d. trần thời gian KIT như shard GATES" ;; *) fail "d. $D" ;; esac
case "$D" in *"extra [True]"*) ok "d. SCOPED-EXTRA parallel_safe" ;; *) fail "d. $D" ;; esac

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
