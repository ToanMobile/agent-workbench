#!/usr/bin/env bash
# #648: lượt gate exit 0 ghi <git-dir>/postfix-gate/rerun_skip.json.
# Lượt sau cùng fp, cùng mode, cùng danh sách suite trả 0 và in đường dẫn file, không chạy lại suite.
# --force, --no-cache và DEVKIT_GATE_CACHE=0 chạy lại. --force giữ mode impacted.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE
export DEVKIT_SUITE_CACHE=0

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  mkdir -p src templates .agents
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf 'ran\n.agents/evidence/\n.agents/regression_checklist.md\n.agents/CHECKLIST.md\n.claude/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> ran"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
echo "def ok(): return 2" > "$REPO/src/core.py"
GD="$(git -C "$REPO" rev-parse --absolute-git-dir)"
SKIP="$GD/postfix-gate/rerun_skip.json"

gate() { CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --no-checklist --run-tests "$@" >"$TMP/gate" 2>&1; }
ran_n() { wc -l < "$REPO/ran" | tr -d ' '; }
show() { tail -c 500 "$TMP/gate" | tr '\n' ' '; }

gate; rc=$?
[ "$rc" = 0 ] && [ "$(ran_n)" = 1 ] && ok "first impacted run: exit 0, ran has 1 line" \
  || fail "first run: rc $rc lines=$(ran_n 2>/dev/null) $(show)"
python3 - "$SKIP" <<'PY' || fail "rerun_skip.json fields"
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
fp = d.get("fp") or ""
ok = (d.get("exit") == 0 and d.get("mode") == "impacted" and d.get("result_format") == 3
      and d.get("suites") == ["REG-1"] and len(fp) == 24 and all(c in "0123456789abcdef" for c in fp)
      and "tested_at" not in d)
sys.exit(0 if ok else 1)
PY
[ "$FAILS" -eq 0 ] && ok "rerun_skip.json: fp, mode impacted, suites, result_format 3, exit 0"

gate --json; rc=$?
last="$(tail -n 1 "$TMP/gate")"
[ "$rc" = 0 ] && [ "$(ran_n)" = 1 ] && printf '%s\n' "$last" | grep -q '"exit_code": 0' \
  && grep -q "$SKIP" "$TMP/gate" \
  && ok "second run skips: exit 0, path printed, ran stays 1" \
  || fail "second run: rc $rc lines=$(ran_n) last=$last $(show)"

python3 - "$SKIP" <<'PY' || exit 1
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["fp"] = "0" * 24
open(p, "w", encoding="utf-8").write(json.dumps(d, sort_keys=True) + "\n")
PY
gate; rc=$?
[ "$rc" = 0 ] && [ "$(ran_n)" = 2 ] && ok "fp mismatch runs the suite again (2 lines)" \
  || fail "fp mismatch: rc $rc lines=$(ran_n) $(show)"

python3 - "$SKIP" <<'PY' || exit 1
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["suites"] = ["NOPE"]
open(p, "w", encoding="utf-8").write(json.dumps(d, sort_keys=True) + "\n")
PY
gate; rc=$?
[ "$rc" = 0 ] && [ "$(ran_n)" = 3 ] && ok "suites mismatch runs the suite again (3 lines)" \
  || fail "suites mismatch: rc $rc lines=$(ran_n) $(show)"

gate --force; rc=$?
mode="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("mode"))' "$SKIP")"
[ "$rc" = 0 ] && [ "$(ran_n)" = 4 ] && [ "$mode" = impacted ] \
  && ok "--force runs again and keeps mode impacted (4 lines)" \
  || fail "--force: rc $rc lines=$(ran_n) mode=$mode $(show)"

gate --no-cache; rc=$?
[ "$rc" = 0 ] && [ "$(ran_n)" = 5 ] && ok "--no-cache runs again (5 lines)" \
  || fail "--no-cache: rc $rc lines=$(ran_n) $(show)"

DEVKIT_GATE_CACHE=0 gate; rc=$?
[ "$rc" = 0 ] && [ "$(ran_n)" = 6 ] && ok "DEVKIT_GATE_CACHE=0 runs again (6 lines)" \
  || fail "DEVKIT_GATE_CACHE=0: rc $rc lines=$(ran_n) $(show)"

gate --full; rc=$?
mode="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("mode"))' "$SKIP")"
[ "$rc" = 0 ] && [ "$(ran_n)" = 7 ] && [ "$mode" = full ] \
  && ok "--full runs again and records mode full (7 lines)" \
  || fail "--full: rc $rc lines=$(ran_n) mode=$mode $(show)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_rerun_skip: PASS"; exit 0; }
echo "test_gate_rerun_skip: FAIL ($FAILS)"
exit 1
