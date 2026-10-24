#!/usr/bin/env bash
# Regression test (issue #181): red_proof.py --pending marks a matrix suite (kind=test) and an
# orphan test row red_proof = N/A with a reason — a RED proof only exists for a bug/REQ — and never
# touches a bug row's proof or removes a row.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROOF="$DEVKIT_DIR/scripts/testing/red_proof.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
  printf 'def add(a, b):\n    return a + b\n' > src/calc.py
  python3 -c 'import json; json.dump({"adopted": True, "rules": [{"component": "Calc", "watch_files": ["src/*.py"],
    "mandatory_regression_tests": [{"id": "REG-CALC", "name": "calc", "command": "true"}]}]},
    open(".agents/regression_matrix.active.json", "w"))'
  printf 'tmp/\n' > .gitignore
  git add -A && git commit -qm init )
cd "$P"
CLAUDE_PROJECT_DIR="$P" python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null 2>&1
# an orphan row and a REPORTED bug with no test, written straight into the checklist
python3 - <<'PY'
import json
f = ".agents/regression_status.json"
d = json.load(open(f))
d["items"]["ORPHAN-X"] = {"id": "ORPHAN-X", "kind": "orphan", "title": "tests/x.py"}
d["items"]["BUG-NOTEST"] = {"id": "BUG-NOTEST", "kind": "bug", "state": "reported", "title": "no test"}
json.dump(d, open(f, "w"))
PY
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
field() { python3 -c "import json;print((json.load(open('$P/.agents/regression_status.json'))['items'].get('$1',{}).get('red_proof') or {}).get('$2','-'))"; }
[ "$(field REG-CALC status)" = "N/A" ] && ok "a matrix suite (kind=test) gets red_proof N/A" || fail "REG-CALC: $(field REG-CALC status)"
[ "$(field ORPHAN-X status)" = "N/A" ] && ok "an orphan row gets red_proof N/A" || fail "ORPHAN-X: $(field ORPHAN-X status)"
[ "$(field REG-CALC reason)" != "-" ] && [ -n "$(field REG-CALC reason)" ] && ok "N/A carries a reason" || fail "N/A without a reason"
[ "$(field BUG-NOTEST status)" = "-" ] && ok "a bug row is left alone (no proof written)" || fail "BUG-NOTEST: $(field BUG-NOTEST status)"
python3 -c "import json,sys;sys.exit(0 if 'BUG-NOTEST' in json.load(open('$P/.agents/regression_status.json'))['items'] else 1)" \
  && ok "no row is dropped" || fail "a row vanished"
[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
