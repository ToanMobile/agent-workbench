#!/usr/bin/env bash
# Regression test (fresh-context audit 2026-10-10, Goods) for scripts/testing/red_proof.py --patch: the tool copies the patch into
# .agents/local/red-patches/<ID>.patch, a TRACKED folder, with no size limit. Goods kept two patches of ~53 MB (a diff of MainGameScene.unity)
# and its .git grew to 241 MB. A bug-back patch holds production code only; above DEVKIT_RED_PATCH_MAX_MB (default 5) the tool now refuses to
# keep it (exit 2, nothing copied, no proof run) and says how to shrink it. A small patch still proves and is kept, as before.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROOF="${RED_PROOF_UNDER_TEST:-$DEVKIT_DIR/scripts/testing/red_proof.py}"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TEST_ADD='import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
import calc
class TestAdd(unittest.TestCase):
    def test_add(self):
        self.assertEqual(calc.add(2, 2), 4)
'
UT="python3 -m unittest discover -s tests"
P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
  printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
  python3 -c 'import json,sys; json.dump({"adopted": True, "rules": [{"component": "Calc", "watch_files": ["src/*.py", "tests/*.py"],
    "mandatory_regression_tests": [{"id": "REG-CALC", "name": "calc", "command": sys.argv[1]}]}]}, open(".agents/regression_matrix.active.json", "w"))' "$UT"
  printf '.env\n' > .gitignore; git add -A && git commit -qm "fix + test" )
bid() { printf '%s' "$1" | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1; }
proof() { python3 -c "import json;print((json.load(open('$P/.agents/regression_status.json'))['items']['$1'].get('red_proof') or {}).get('status','-'))"; }
cd "$P"
printf 'def add(a, b):\n    return a - b\n' > src/calc.py; git diff > "$TMP/small.patch"; git checkout -q src/calc.py
# the same bug-back hunk plus a ~1.3 MB new production file (stands in for a big scene diff)
python3 - "$TMP/small.patch" "$TMP/big.patch" <<'PY'
import sys
small = open(sys.argv[1]).read()
rows = ["+" + "x" * 78 for _ in range(16000)]
open(sys.argv[2], "w").write(small + "diff --git a/src/pad.dat b/src/pad.dat\nnew file mode 100644\n--- /dev/null\n+++ b/src/pad.dat\n@@ -0,0 +1,%d @@\n" % len(rows) + "\n".join(rows) + "\n")
PY
B1="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (patch nhỏ)" --fixed --test tests/test_calc.py 2>&1)")"
B2="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (patch lớn)" --fixed --test tests/test_calc.py 2>&1)")"

out="$(DEVKIT_RED_PATCH_MAX_MB=1 python3 "$PROOF" "$P" --bug "$B2" --patch "$TMP/big.patch" --wait 2>&1)"; rc=$?
[ "$rc" = 2 ] && ok "a patch over the cap is refused (exit 2)" || fail "big patch: exit $rc, want 2: $out"
echo "$out" | grep -qi 'DEVKIT_RED_PATCH_MAX_MB' && ok "the refusal names the knob and how to shrink the patch" || fail "refusal without the knob: $out"
[ ! -e "$P/.agents/local/red-patches/$B2.patch" ] && ok "the big patch was not copied into the tracked folder" || fail "big patch kept in .agents/local/red-patches"
[ "$(proof "$B2")" = - ] && ok "no proof was run for the refused patch" || fail "a proof ran: $(proof "$B2")"

DEVKIT_RED_PATCH_MAX_MB=1 python3 "$PROOF" "$P" --bug "$B1" --patch "$TMP/small.patch" --wait >/dev/null 2>&1
[ "$(proof "$B1")" = PROVEN ] && ok "a patch under the cap still proves" || fail "small patch: $(proof "$B1")"
[ -f "$P/.agents/local/red-patches/$B1.patch" ] && ok "a patch under the cap is kept, as before" || fail "small patch not kept"

# review 2026-10-10: the knob is user input. "inf" is the natural way to say "no limit"; inf / 1e400 / nan / words must not crash the tool
for v in inf 1e400; do
  rm -f "$P/.agents/local/red-patches/$B2.patch"
  out="$(DEVKIT_RED_PATCH_MAX_MB=$v python3 "$PROOF" "$P" --bug "$B2" --patch "$TMP/big.patch" --wait 2>&1)"; rc=$?
  { [ "$rc" = 0 ] && ! echo "$out" | grep -q Traceback; } && ok "DEVKIT_RED_PATCH_MAX_MB=$v: no limit, no crash" || fail "MAX_MB=$v: exit $rc: $(echo "$out" | tail -3 | tr '\n' ' ')"
done
for v in nan abc ""; do
  out="$(DEVKIT_RED_PATCH_MAX_MB=$v python3 "$PROOF" "$P" --bug "$B1" --patch "$TMP/small.patch" --wait 2>&1)"; rc=$?
  { [ "$rc" = 0 ] && ! echo "$out" | grep -q Traceback; } && ok "DEVKIT_RED_PATCH_MAX_MB='$v': falls back to the default cap, no crash" || fail "MAX_MB='$v': exit $rc: $(echo "$out" | tail -3 | tr '\n' ' ')"
done

[ "$FAILS" -eq 0 ] && echo "✅ test_red_proof_patch_cap: all passed" || { echo "❌ test_red_proof_patch_cap: $FAILS failed"; exit 1; }
