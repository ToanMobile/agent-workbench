#!/usr/bin/env bash
# Regression test: what the pre-commit gate believes about a suite's length (bin/post-fix-gate.py
# _recorded_seconds) must not depend on which run happened to be the LAST one.
# 2026-10-03/04: REG-DK-ALL-01 (run_impacted.sh, whose length follows the diff) recorded 165.6 s, 164.6 s, 23.4 s,
# 17.6 s ...; pre-commit skips a suite over 30 s, so the same commit ran it or skipped it depending on the previous
# gate run, and the suite_env identity leak only surfaced when it finally ran. The belief is now the longest
# PASS/FAIL run in the history (untested / busy / cached runs carry no real length).
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DEVKIT_DIR/tests/lib/clean_git_env.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/p/.agents"
python3 - "$TMP/p/.agents/regression_status.json" <<'PY'
import json, sys
def run(status, dur): return {"status": status, "duration": dur}
items = {
  # newest first, as the gate writes it: the last run was a short one
  "REG-VARIABLE": {"last": run("PASS", "17.59s"), "history": [run("PASS", "17.59s"), run("PASS", "165.61s"), run("PASS", "164.59s"), run("FAIL", "50.64s"), run("PASS", "23.38s")]},
  "REG-NOHISTORY": {"last": run("PASS", "9.5s")},
  "REG-UNREAL": {"last": run("PASS", "3s"), "history": [run("UNTESTED", "-"), run("UNTESTED", "0s"), run("PASS", "3s"), run("PASS", "cached")]},
  "REG-ONLYUNTESTED": {"last": run("UNTESTED", "0s"), "history": [run("UNTESTED", "0s")]},
}
json.dump({"items": items}, open(sys.argv[1], "w"))
PY
out="$(CLAUDE_PROJECT_DIR="$TMP/p" python3 - "$GATE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("post_fix_gate", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
r = mod._recorded_seconds()
for k in ("REG-VARIABLE", "REG-NOHISTORY", "REG-UNREAL", "REG-ONLYUNTESTED"):
    print(k, r.get(k, "none"))
PY
)" || { echo "✖ could not import $GATE"; exit 1; }
val() { printf '%s\n' "$out" | awk -v k="$1" '$1 == k { print $2 }'; }
[ "$(val REG-VARIABLE)" = "165.61" ] && ok "a suite whose runs vary: the longest PASS/FAIL run counts (165.61, not the last 17.59)" || fail "REG-VARIABLE → '$(val REG-VARIABLE)' (want 165.61)"
[ "$(val REG-NOHISTORY)" = "9.5" ] && ok "no history: the last run is used" || fail "REG-NOHISTORY → '$(val REG-NOHISTORY)' (want 9.5)"
[ "$(val REG-UNREAL)" = "3.0" ] && ok "untested / cached runs carry no length and are ignored" || fail "REG-UNREAL → '$(val REG-UNREAL)' (want 3.0)"
[ "$(val REG-ONLYUNTESTED)" = "none" ] && ok "only untested runs: no belief (the suite is not skipped for a length it never had)" || fail "REG-ONLYUNTESTED → '$(val REG-ONLYUNTESTED)' (want none)"

[ "$FAILS" -eq 0 ] && echo "✅ test_precommit_duration: all passed" || { echo "❌ test_precommit_duration: $FAILS failed"; exit 1; }
