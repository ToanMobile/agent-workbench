#!/usr/bin/env bash
# Regression test: the two command words and the RED-proof of past bugs.
#  - "làm backlog": the prompt hook puts the bugs no regression test guards into the context,
#    most severe first (critical/P0 → P1 → P2 → unclassified), at most 10, each with the next
#    command; a bug whose evidence names its fix commit gets the revert RED-proof command
#  - "làm inbox": the inbox items not done yet (seen before or new), to do them all
#  - red_proof.py --pending proves an old bug by reverting the fix commit its evidence names
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"; PROMPT_HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"; PROOF="$DEVKIT_DIR/scripts/red_proof.py"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset PROMPT_CONTEXT BUG_CAPTURE INBOX_WATCH

P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
printf 'def add(a, b):\n    return a - b\n' > src/calc.py
cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[{"component":"Calc","watch_files":["src/*.py","tests/*.py"],
 "mandatory_regression_tests":[{"id":"REG-CALC","name":"calc","command":"python3 -m unittest discover -s tests"}]}]}
JSON
git add -A && git commit -qm init
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; git commit -qam "fix add"; FIX="$(git rev-parse --short HEAD)"
export CLAUDE_PROJECT_DIR="$P"
hook() { python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": "sb"}))' "$1" 2>/dev/null \
         | CLAUDE_PROJECT_DIR="$P" bash "$PROMPT_HOOK" 2>&1; }

{ printf 'bug_id\ttitle\tseverity\tfixed?\tmodule\ttest_id_or_NONE\tevidence\n'
  printf 'L1\tLỗi nhỏ giao diện\t-\tyes\tui\tNONE\t-\n'
  printf 'C1\tCrash khi cộng số\tcritical\tyes\tcalc\tNONE\tfix %s\n' "$FIX"
  printf 'P1\tSai định dạng ngày\tP1\tyes\tdate\tNONE\t-\n'
  printf 'O1\tChưa sửa\tP0\tno\tx\tNONE\t-\n'
  for i in 01 02 03 04 05 06 07 08 09 10 11; do printf 'M%s\tBug phụ %s\tP2\tyes\tm\tNONE\t-\n' "$i" "$i"; done; } > "$TMP/bugs.tsv"
bash "$KIT" bugs import "$TMP/bugs.tsv" >/dev/null 2>&1

out="$(hook "làm backlog")"
first="$(printf '%s' "$out" | grep -o 'BUG-[A-Za-z0-9]*' | head -1)"
[ "$first" = BUG-C1 ] && ok "làm backlog: the critical bug comes first" || fail "order: first=$first — $out"
printf '%s' "$out" | grep -q "BUG-C1.*" && printf '%s' "$out" | grep -q -- "--fix-commit $FIX" && ok "bug with a fix commit in its evidence → revert RED-proof command" || fail "fix-commit: $out"
p1="$(printf '%s' "$out" | grep -n 'BUG-P1' | head -1 | cut -d: -f1)"; l1="$(printf '%s' "$out" | grep -n 'BUG-L1' | head -1 | cut -d: -f1)"
[ -n "$p1" ] && { [ -z "$l1" ] || [ "$p1" -lt "$l1" ]; } && ok "P1 before unclassified" || fail "P1/L1 order: $p1 $l1"
[ "$(printf '%s' "$out" | grep -c 'BUG-')" -le 11 ] && printf '%s' "$out" | grep -q "14 bug" && ok "at most 10 listed, the total said" || fail "limit: $(printf '%s' "$out" | grep -c 'BUG-') — $out"
printf '%s' "$out" | grep -q "BUG-O1" && fail "an unfixed bug is not backlog of tests" || ok "unfixed bugs are not in the test backlog"

printf '# Hộp thư\n- [ ] Xuất PDF\n- [ ] Đổi màu nút @làm\n' > .agents/INBOX.md
hook "xem giúp tình hình" >/dev/null           # seen once
out="$(hook "làm inbox")"
printf '%s' "$out" | grep -q "Xuất PDF" && printf '%s' "$out" | grep -q "Đổi màu nút" && ok "làm inbox: every item not done yet, even seen ones" || fail "inbox: $out"

# past bug proven by reverting the fix commit named in its evidence
printf 'import os, sys, unittest\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))\nimport calc\nclass TestAdd(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(calc.add(2, 2), 4)\n' > tests/test_calc.py
git add tests/test_calc.py && git commit -qm "test for C1"
bash "$KIT" bugs link BUG-C1 tests/test_calc.py >/dev/null 2>&1
echo "# touch" >> tests/test_calc.py; python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1; git checkout -q tests/test_calc.py
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
proof="$(python3 -c "import json;print(json.load(open('.agents/regression_status.json'))['items']['BUG-C1'].get('red_proof',{}).get('status'))")"
mode="$(python3 -c "import json;print(json.load(open('.agents/regression_status.json'))['items']['BUG-C1'].get('red_proof',{}).get('mode'))")"
[ "$proof" = PROVEN ] && [ "$mode" = revert ] && ok "--pending: fix commit from the evidence reverted in a sandbox → PROVEN" || fail "pending revert: $proof $mode"

[ "$FAILS" -eq 0 ] && echo "✅ test_backlog: all passed" || { echo "❌ test_backlog: $FAILS failed"; exit 1; }
