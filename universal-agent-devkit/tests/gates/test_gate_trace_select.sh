#!/usr/bin/env bash
# #667 AC2: DEVKIT_TRACE_MAP_SELECT=1 makes the impacted run skip suites the test→source map proves unaffected
# (same map as the #476 shadow). Default off: the old selection runs unchanged. A suite whose inputs changed always runs.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL CI DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE DEVKIT_PER_TEST_CACHE DEVKIT_SHADOW_MAP
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$HOME" "$SB_HEAVY_SLOT_DIR"
FAILS=0
R="$TMP/work"
mkdir -p "$R/src" "$R/tests" && git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo 'x = 1' > "$R/src/a.py"; echo 'y = 1' > "$R/src/b.py"
printf '# reads src/a.py\nimport sys\nsys.exit(1 if "x = 3" in open("src/a.py").read() else 0)\n' > "$R/tests/t1.py"
cat > "$R/matrix.json" <<'JSON'
{"project":"t","rules":[
 {"component":"A","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"python3 tests/t1.py"}]},
 {"component":"B","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-B","name":"b","command":"true"}]}
]}
JSON
git -C "$R" add -A && git -C "$R" commit -qm init
ran() {  # $1 = flag value ("" = unset), $2 = label, $3 = extra gate flag (e.g. --scoped)
  ( cd "$R" && env ${1:+DEVKIT_TRACE_MAP_SELECT=$1} FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --no-checklist --no-cache ${3:-} --task "$2" >"$TMP/out.$2" 2>&1 ); echo "rc=$?" >"$TMP/rc.$2"
  python3 -I -c "import json,sys;r=json.loads(open(sys.argv[1]).read().splitlines()[-1]);print(','.join(sorted(r.get('ran_suites') or [])))" "$R/.git/postfix-gate/runs.jsonl"
}
chk() { if [ "$2" = "$3" ]; then echo "✔ $1 ($2)"; else echo "✖ $1: got '$2' want '$3'"; FAILS=$((FAILS+1)); fi; }
echo 'y = 2' > "$R/src/b.py"
chk "1. flag off: old selection runs both" "$(ran "" T1)" "REG-A,REG-B"
chk "2. flag on, only src/b.py changed: map skips both" "$(ran 1 T2)" ""
chk "2b. exit code still 0" "$(cat "$TMP/rc.T2")" "rc=0"
echo 'x = 2' > "$R/src/a.py"
chk "3. flag on, src/a.py changed: REG-A runs, REG-B skipped" "$(ran 1 T3)" "REG-A"
echo 'x = 3' > "$R/src/a.py"
chk "4. flag on, failing REG-A still runs and fails the gate" "$(ran 1 T4)" "REG-A"
chk "4b. gate not green" "$([ "$(cat "$TMP/rc.T4")" != "rc=0" ] && echo notgreen)" "notgreen"
# R1 (review #1194): a --scoped receipt lists scoped_tests as covered, so the map may not drop suites there.
git -C "$R" checkout -q -- src; echo 'x = 4' > "$R/src/a.py"; echo 'y = 4' > "$R/src/b.py"
chk "5. flag on + --scoped: nothing skipped (receipt would claim unrun tests)" "$(ran 1 T5 --scoped)" "REG-A,REG-B"
# R2: a deleted file is not in the current-tree map, so a dependent suite must not be skipped.
git -C "$R" checkout -q -- src; rm "$R/src/a.py"
W6="$(ran "" T6off)"; echo "(flag-off baseline for delete: $W6)"
chk "6. flag on, src/a.py deleted: same suites as flag off (no map skip)" "$(ran 1 T6)" "$W6"
# R2: a renamed file's old path is not in the map either.
git -C "$R" checkout -q -- src; git -C "$R" mv src/a.py src/a2.py
W7="$(ran "" T7off)"; echo "(flag-off baseline for rename: $W7)"
chk "7. flag on, src/a.py renamed: same suites as flag off (no map skip)" "$(ran 1 T7)" "$W7"
[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
