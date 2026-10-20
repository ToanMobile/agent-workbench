#!/usr/bin/env bash
# Regression test (issue #20 via #19) for scripts/testing/red_proof.py hardening:
#  1. narrowed() filled the pytest/jest placeholder with a bare " ".join(tests) (no shlex.quote) and refused any command that
#     still held `{`…`}` — so a literal ${ENV_VAR} in the suite command made it fall back to running the whole suite.
#  2. SIGTERM / SIGINT left the red-proof-* worktree and the test's process group behind (only SIGKILL on timeout).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROOF="${RED_PROOF_UNDER_TEST:-$DEVKIT_DIR/scripts/testing/red_proof.py}"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── 1. narrowed(): shlex.quote on the tests, ${VAR} survives
out="$(python3 - "$PROOF" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("rp", sys.argv[1]); rp = importlib.util.module_from_spec(spec); spec.loader.exec_module(rp)
p = Path("/nonexistent")
print(rp.narrowed(p, "FOO=${HOME} python3 -m pytest {pytest_nodes} -q", ["tests/test_a.py"]))
print(rp.narrowed(p, "python3 -m pytest {pytest_nodes}", ["tests/my test.py", "tests/a;b.py"]))
print(rp.narrowed(p, "python3 -m pytest {unknown_placeholder}", ["tests/test_a.py"]))
PY
)"
l1="$(echo "$out" | sed -n 1p)"; l2="$(echo "$out" | sed -n 2p)"; l3="$(echo "$out" | sed -n 3p)"
[ "$l1" = 'FOO=${HOME} python3 -m pytest tests/test_a.py -q' ] && ok 'narrowed keeps a literal ${VAR} in the command' || fail "narrowed with \${VAR}: $l1"
[ "$l2" = "python3 -m pytest 'tests/my test.py' 'tests/a;b.py'" ] && ok 'narrowed shell-quotes test paths' || fail "narrowed quoting: $l2"
[ "$l3" = None ] && ok 'narrowed still refuses an unfilled placeholder' || fail "unfilled placeholder: $l3"

# ── 2. SIGTERM cleans the sandbox worktree and kills the test's process group
SLOW='import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
import calc
class TestAdd(unittest.TestCase):
    def test_add(self):
        os.system("sleep 47.123")
        self.assertEqual(calc.add(2, 2), 4)
'
P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents" "$TMP/tmpdir"
( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
  printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$SLOW" > tests/test_calc.py
  python3 -c 'import json; json.dump({"adopted": True, "rules": [{"component": "Calc", "watch_files": ["src/*.py", "tests/*.py"],
    "mandatory_regression_tests": [{"id": "REG-CALC", "name": "calc", "command": "python3 -m unittest discover -s tests"}]}]}, open(".agents/regression_matrix.active.json", "w"))'
  git add -A && git commit -qm "fix + test" )
B="$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai" --fixed --test tests/test_calc.py 2>&1 | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1)"
( cd "$P" && printf 'def add(a, b):\n    return a - b\n' > src/calc.py && git diff > "$TMP/bug.patch"; git checkout -q src/calc.py )
TMPDIR="$TMP/tmpdir" python3 "$PROOF" "$P" --bug "$B" --patch "$TMP/bug.patch" --wait >"$TMP/proof.out" 2>&1 &
PID=$!
for _ in $(seq 1 60); do pgrep -f 'sleep 47.123' >/dev/null && break; sleep 0.5; done
[ -s "$TMP/proof.out" ] && cat "$TMP/proof.out"
pgrep -f 'sleep 47.123' >/dev/null && ok "the proof is running its test" || fail "the proof never reached the slow test"
ls -d "$TMP"/tmpdir/red-proof-* >/dev/null 2>&1 && ok "a sandbox worktree exists while it runs" || fail "no red-proof-* sandbox while running"
kill -TERM "$PID"; wait "$PID" 2>/dev/null
sleep 1
ls -d "$TMP"/tmpdir/red-proof-* >/dev/null 2>&1 && fail "SIGTERM left a red-proof-* directory" || ok "SIGTERM removes the red-proof-* sandbox"
pgrep -f 'sleep 47.123' >/dev/null && { fail "SIGTERM left the test's process group running"; pkill -f 'sleep 47.123'; } || ok "SIGTERM kills the test's process group"
git -C "$P" worktree list | grep -q red-proof && fail "SIGTERM left a registered worktree" || ok "no registered sandbox worktree remains"

[ "$FAILS" -eq 0 ] && echo "✅ test_red_proof_hardening: all passed" || { echo "❌ test_red_proof_hardening: $FAILS failed"; exit 1; }
