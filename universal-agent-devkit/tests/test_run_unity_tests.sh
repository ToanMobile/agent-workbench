#!/usr/bin/env bash
# scripts/run_unity_tests.py: wraps profiles/game/scripts/unity-batch.sh and maps the result
# to 0 = every test passed, 1 = a test failed, 2 = compile error / no results / no Editor.
# No Unity: a fake Editor (UNITY_PATH) writes the log and an NUnit 3 result file.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$DEVKIT_DIR/scripts/run_unity_tests.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

UNITY="$TMP/Unity"
cat > "$UNITY" <<'SH'
#!/usr/bin/env bash
echo "$*" > "$FAKE_DIR/args"
log="" xml=""
while [ $# -gt 0 ]; do
  case "$1" in -logFile) log="$2"; shift ;; -testResults) xml="$2"; shift ;; esac; shift
done
echo "fake unity" > "$log"
case "${FAKE_MODE:-pass}" in
  compile) echo "Assets/Game/Board.cs(12,5): error CS1002: ; expected" >> "$log"; exit 1 ;;
  noxml) exit 0 ;;
  fail) r2=Failed ;;
  *) r2=Passed ;;
esac
cat > "$xml" <<XML
<test-run>
 <test-case fullname="Game.Tests.BoardTests.Spawns" result="Passed"/>
 <test-case fullname="Game.Tests.BoardTests.Clears" result="$r2"><failure><message>Expected: 3
  But was:  2</message></failure></test-case>
 <test-case fullname="Game.Tests.BoardTests.Later" result="Skipped"/>
</test-run>
XML
[ "$r2" = Failed ] && exit 2
exit 0
SH
chmod +x "$UNITY"

PROJ="$TMP/proj"
mkdir -p "$PROJ/Assets" "$PROJ/ProjectSettings"
printf 'm_EditorVersion: 6000.6.0f1\n' > "$PROJ/ProjectSettings/ProjectVersion.txt"

run() {  # run <mode> [args…] → RC, $TMP/out
  local mode="$1"; shift
  (cd "$TMP" && env FAKE_DIR="$TMP" FAKE_MODE="$mode" UNITY_PATH="$UNITY" UNITY_KEEP_PREFS=1 \
    python3 "$CMD" --project "$PROJ" "$@") >"$TMP/out" 2>&1
  RC=$?
}

run pass
[ "$RC" = 0 ] && grep -q 'total 3, passed 2, failed 0' "$TMP/out" \
  && [ -s "$TMP/reports/unity-test-results.xml" ] && [ -s "$TMP/reports/unity_test.log" ] \
  && grep -q -- '-batchmode' "$TMP/args" && grep -q -- '-nographics' "$TMP/args" \
  && grep -q -- '-testPlatform EditMode' "$TMP/args" \
  && ok "all passed: exit 0, XML at reports/unity-test-results.xml, log at reports/unity_test.log" \
  || fail "pass: rc=$RC $(cat "$TMP/out")"

run fail
[ "$RC" = 1 ] && grep -q 'failed 1' "$TMP/out" && grep -q 'Game.Tests.BoardTests.Clears' "$TMP/out" \
  && grep -q 'Expected: 3' "$TMP/out" \
  && ok "failed test: exit 1 with the test name and assertion message" || fail "fail: rc=$RC $(cat "$TMP/out")"

run compile
[ "$RC" = 2 ] && grep -q 'error CS1002' "$TMP/out" \
  && ok "compile error: exit 2 with the compiler line" || fail "compile: rc=$RC $(cat "$TMP/out")"

run noxml
[ "$RC" = 2 ] && ok "no result file: exit 2" || fail "noxml: rc=$RC $(cat "$TMP/out")"

run pass --platform playmode --output "$TMP/custom/r.xml"
[ "$RC" = 0 ] && grep -q -- '-testPlatform PlayMode' "$TMP/args" && grep -q -- '-nographics' "$TMP/args" \
  && [ -s "$TMP/custom/r.xml" ] && [ -s "$TMP/custom/unity_test.log" ] \
  && ok "--platform playmode runs headless and --output is honoured" || fail "playmode: rc=$RC $(cat "$TMP/out")"

# Pinned version not installed: exit 2, names the version (never opens the project with another Editor).
printf 'm_EditorVersion: 1999.1.0f1\n' > "$PROJ/ProjectSettings/ProjectVersion.txt"
(cd "$TMP" && env -u UNITY_PATH FAKE_DIR="$TMP" python3 "$CMD" --project "$PROJ") >"$TMP/out" 2>&1; RC=$?
[ "$RC" = 2 ] && grep -q '1999.1.0f1' "$TMP/out" \
  && ok "pinned Editor missing: exit 2 naming the version" || fail "missing editor: rc=$RC $(cat "$TMP/out")"

# A stale unity_test.log from an earlier run does not survive a run that never opened the Editor.
echo "old log" > "$TMP/reports/unity_test.log"
(cd "$TMP" && env -u UNITY_PATH FAKE_DIR="$TMP" python3 "$CMD" --project "$PROJ") >"$TMP/out" 2>&1; RC=$?
[ "$RC" = 2 ] && [ ! -e "$TMP/reports/unity_test.log" ] \
  && ok "stale unity_test.log removed when the run wrote none" || fail "stale log: rc=$RC $(cat "$TMP/reports/unity_test.log" 2>&1)"

# Hub scan: versions installed under a Hub folder, matched to ProjectVersion.txt.
HUB="$TMP/hub"
for v in 2022.3.1f1 6000.6.0f1; do
  mkdir -p "$HUB/$v/Unity.app/Contents/MacOS"; cp "$UNITY" "$HUB/$v/Unity.app/Contents/MacOS/Unity"
done
got="$(python3 - "$CMD" "$HUB" "$PROJ" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("rut", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
hub, proj = Path(sys.argv[2]), Path(sys.argv[3])
(proj / "ProjectSettings/ProjectVersion.txt").write_text("m_EditorVersion: 6000.6.0f1\n")
print(sorted(m.installed_editors(hub)), m.find_editor(proj, hub, {}), m.find_editor(proj, hub, {"UNITY_PATH": "/x/Unity"}))
PY
)"
case "$got" in
  *"['2022.3.1f1', '6000.6.0f1']"*"6000.6.0f1/Unity.app/Contents/MacOS/Unity /x/Unity") ok "Hub scan picks the project's version; UNITY_PATH wins" ;;
  *) fail "hub scan: $got" ;;
esac

[ "$FAILS" = 0 ] && echo "ok" || { echo "$FAILS failed"; exit 1; }
