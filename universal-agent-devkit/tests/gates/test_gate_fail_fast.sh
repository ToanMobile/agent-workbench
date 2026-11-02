#!/usr/bin/env bash
# #647: mặc định dừng khi một suite FAIL. Suite sau thành UNTESTED, đuôi "Không chạy",
# và dòng Log của suite FAIL. --no-fail-fast chạy tiếp, kể cả suite covered_by của suite đỏ.
# gate_full và merge-train gắn cờ này vào post-fix-gate. super-board-verify-flags.sh không gắn.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
TRAIN="$ROOT/.claude/bin/super-board-merge-train.sh"
FLAGS="$ROOT/.claude/bin/super-board-verify-flags.sh"
FULL="$DEVKIT_DIR/bin/gate_full.py"
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
 "mandatory_regression_tests":[
  {"id":"REG-A","name":"first","command":"exit 1"},
  {"id":"REG-B","name":"later","command":"echo later >> ran"},
  {"id":"REG-C","name":"covered","command":"echo covered >> ran","covered_by":"REG-A"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1

gate() { CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --no-checklist --run-tests --tree HEAD --no-cache "$@" >"$TMP/gate" 2>&1; }
show() { tail -c 600 "$TMP/gate" | tr '\n' ' '; }
reset_tree() {
  git -C "$REPO" checkout -q -- .
  git -C "$REPO" clean -qfd
  rm -rf "$REPO/.agents/evidence" "$REPO/ran"
}

reset_tree
gate; rc=$?
[ "$rc" = 1 ] && ok "default fail-fast: exit 1" || fail "default: rc $rc (want 1) $(show)"
grep -q "Không chạy" "$TMP/gate" && ok "default: later suites say Không chạy" || fail "default: missing Không chạy $(show)"
grep -q "Log:" "$TMP/gate" && grep -q ".agents/evidence" "$TMP/gate" \
  && ok "default: FAIL line names the evidence log" || fail "default: missing Log path $(show)"
if [ -e "$REPO/ran" ] && grep -E -q "later|covered" "$REPO/ran"; then
  fail "default: ran has later output ($(cat "$REPO/ran"))"
else
  ok "default: later suites did not append ran"
fi

reset_tree
gate --no-fail-fast; rc=$?
[ "$rc" = 1 ] && ok "--no-fail-fast: exit 1" || fail "--no-fail-fast: rc $rc (want 1) $(show)"
grep -q "later" "$REPO/ran" && grep -q "covered" "$REPO/ran" \
  && ok "--no-fail-fast: later and covered both ran" \
  || fail "--no-fail-fast: ran=$(cat "$REPO/ran" 2>/dev/null) $(show)"

if python3 - "$TRAIN" "$FLAGS" "$FULL" <<'PY'
import sys
train, flags, full = sys.argv[1:]
src = open(train, encoding="utf-8").read()
i = src.find("# #647:")
chunk = src[i:i + 900] if i >= 0 else ""
gf = open(full, encoding="utf-8").read()
fl = open(flags, encoding="utf-8").read()
sys.exit(0 if ("*post-fix-gate*" in chunk and "--no-fail-fast" in chunk
               and '"--no-fail-fast"' in gf and "--no-fail-fast" not in fl) else 1)
PY
then
  ok "merge-train and gate_full pass --no-fail-fast; verify-flags does not"
else
  fail "flag call sites: train/gate_full/verify-flags"
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_fail_fast: PASS"; exit 0; }
echo "test_gate_fail_fast: FAIL ($FAILS)"
exit 1
