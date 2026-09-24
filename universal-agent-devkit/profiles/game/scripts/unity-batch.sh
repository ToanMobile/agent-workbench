#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# unity-batch.sh — generic Unity batchmode gate for any Unity project (Unity 2021+ / Unity 6)
#
#   unity-batch.sh compile                 # import + compile every assembly, then quit
#   unity-batch.sh editmode [options]      # Unity Test Framework, EditMode
#   unity-batch.sh playmode [options]      # Unity Test Framework, PlayMode
#   unity-batch.sh execute <Ns.Class.Method> [editor args…]
#                                          # -executeMethod WITHOUT -quit: the method must end
#                                          # with EditorApplication.Exit(code) (needed for
#                                          # anything that enters Play Mode, e.g. a bot run)
#
# Options (tests only):
#   --filter <names|regex>   passed to -testFilter   (semicolon-separated)
#   --category <names>       passed to -testCategory (semicolon-separated)
#   --assembly <names>       passed to -assemblyNames (semicolon-separated)
# Environment:
#   UNITY_PATH          Editor binary (default: Unity Hub location of the version pinned in
#                       ProjectSettings/ProjectVersion.txt, incl. Hub's secondary install path)
#   UNITY_PROJECT       project root (default: current directory)
#   UNITY_TIMEOUT       seconds before the Editor is killed (default 900)
#   UNITY_BATCH_OUT     log / results folder (default: <project>/Logs/agent-kit — Logs/ is
#                       in the standard Unity .gitignore)
#   UNITY_NOGRAPHICS=1  add -nographics to PlayMode runs (off by default: pixel reads,
#                       screenshots and some rendering tests need a graphics device)
#   UNITY_EXTRA_ARGS    extra Editor arguments (word-split)
#   UNITY_KEEP_PREFS=1  keep the PlayerPrefs the run wrote (macOS). By default the Editor's
#                       defaults domain unity.<company>.<product> is snapshotted and restored
#
# Exit: 0 = PASS · 1 = FAIL (compile error, failed test, zero tests executed, timeout)
#       2 = UNTESTED (no Editor, project already open in an Editor, bad usage)
#
# Pitfalls this script exists for (see profiles/game/rules/game-rules.md §8):
#   • Unity can exit 0 while the log contains `error CS…` → the log is always scanned.
#   • `-runTests` exits by itself; adding `-quit` ends the run before the tests start.
#   • A run that executes 0 tests exits 0 → "no <test-case> in the results" is a FAIL.
#   • The results file is NUnit 3 XML, not JUnit — parsed here with the NUnit schema.
#   • Only one Editor may open a project: Temp/UnityLockfile + a live Unity process on
#     the same path = UNTESTED (never kill someone else's Editor session).
#   • A killed run can leave a stale Temp/UnityLockfile. If the PID in the file is dead
#     and no Editor has this project path, the file is removed and the run continues.
# bash 3.2 compatible (macOS default shell).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

MODE="${1:-}"
[ $# -gt 0 ] && shift
FILTER="" CATEGORY="" ASSEMBLY="" METHOD=""
if [ "$MODE" = "execute" ]; then
  METHOD="${1:-}"
  [ -n "$METHOD" ] || { echo "usage: unity-batch.sh execute <Namespace.Class.Method> [editor args…]" >&2; exit 2; }
  shift
  EXEC_ARGS=("$@")
  set --
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --filter) FILTER="${2:-}"; shift 2 ;;
    --filter=*) FILTER="${1#*=}"; shift ;;
    --category) CATEGORY="${2:-}"; shift 2 ;;
    --category=*) CATEGORY="${1#*=}"; shift ;;
    --assembly) ASSEMBLY="${2:-}"; shift 2 ;;
    --assembly=*) ASSEMBLY="${1#*=}"; shift ;;
    *) echo "unity-batch: unknown option '$1'" >&2; exit 2 ;;
  esac
done
case "$MODE" in
  compile|editmode|playmode|EditMode|PlayMode|execute) ;;
  *) echo "usage: unity-batch.sh <compile|editmode|playmode|execute> [--filter X] [--category X] [--assembly X]" >&2; exit 2 ;;
esac

ROOT="$(cd "${UNITY_PROJECT:-$PWD}" 2>/dev/null && pwd -P)" || { echo "UNTESTED: project dir not found" >&2; exit 2; }
if [ ! -f "$ROOT/ProjectSettings/ProjectVersion.txt" ] || [ ! -d "$ROOT/Assets" ]; then
  echo "UNTESTED: $ROOT is not a Unity project (no Assets/ + ProjectSettings/ProjectVersion.txt)" >&2
  exit 2
fi
VERSION="$(sed -n 's/^m_EditorVersion: *//p' "$ROOT/ProjectSettings/ProjectVersion.txt" | tr -d '\r' | head -n 1)"

# ---------- locate the Editor ----------
find_editor() {
  local v="$1" c hub_json secondary
  if [ -n "${UNITY_PATH:-}" ]; then printf '%s' "$UNITY_PATH"; return; fi
  for hub_json in "$HOME/Library/Application Support/UnityHub/secondaryInstallPath.json" \
                  "$HOME/.config/UnityHub/secondaryInstallPath.json"; do
    [ -f "$hub_json" ] || continue
    secondary="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])) or "")' "$hub_json" 2>/dev/null || true)"
    [ -n "$secondary" ] || continue
    for c in "$secondary/$v/Unity.app/Contents/MacOS/Unity" "$secondary/$v/Editor/Unity" "$secondary/$v/Editor/Unity.exe"; do
      [ -x "$c" ] && { printf '%s' "$c"; return; }
    done
  done
  for c in "/Applications/Unity/Hub/Editor/$v/Unity.app/Contents/MacOS/Unity" \
           "$HOME/Unity/Hub/Editor/$v/Editor/Unity" \
           "/c/Program Files/Unity/Hub/Editor/$v/Editor/Unity.exe"; do
    [ -x "$c" ] && { printf '%s' "$c"; return; }
  done
  printf ''
}
UNITY="$(find_editor "$VERSION")"
if [ -z "$UNITY" ] || [ ! -x "$UNITY" ]; then
  echo "UNTESTED: Unity Editor $VERSION not found (set UNITY_PATH to the Editor binary)" >&2
  exit 2
fi

# ---------- one Editor per project ----------
# Unity writes the Editor PID into Temp/UnityLockfile. A killed batch run leaves the
# file behind. A live PID, or any Unity whose command line has this project path, is
# someone else's session: stop. A dead PID (or no PID and no such process) is stale.
if [ -f "$ROOT/Temp/UnityLockfile" ]; then
  if pgrep -fi -- "projectpath[= ]*$ROOT" >/dev/null 2>&1; then
    echo "UNTESTED: an Editor already has $ROOT open (Temp/UnityLockfile + live process). Close it, then re-run." >&2
    exit 2
  fi
  lock_pid="$(head -n 1 "$ROOT/Temp/UnityLockfile" | tr -cd '0-9' | cut -c1-12)"
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "UNTESTED: Temp/UnityLockfile belongs to live pid $lock_pid. Close that Editor, then re-run." >&2
    exit 2
  fi
  echo "Stale Temp/UnityLockfile (pid ${lock_pid:-none} is not running). Removing it and continuing." >&2
  rm -f "$ROOT/Temp/UnityLockfile"
fi

OUT="${UNITY_BATCH_OUT:-$ROOT/Logs/agent-kit}"
mkdir -p "$OUT" || { echo "UNTESTED: cannot create $OUT" >&2; exit 2; }
LIMIT="${UNITY_TIMEOUT:-900}"

# ---------- keep the Editor's PlayerPrefs (macOS) ----------
# Tests and -executeMethod runs write real PlayerPrefs. On macOS the Editor keeps them in the
# defaults domain unity.<companyName>.<productName>, which is the developer's play state, so
# a Stop-time run would change it. Snapshot the domain now and give it back on exit, whether
# the run passes, fails, times out or is interrupted. The player build's com.* domain is never
# touched. `defaults import` only merges keys, so the domain is deleted first.
# A domain that did not exist before the run is deleted again. If the snapshot fails, nothing
# is deleted afterwards. UNITY_KEEP_PREFS=1 keeps whatever the run wrote.
PREFS_DOMAIN="" PREFS_SNAP="" PREFS_ABSENT=0 UNITY_PID=""
if [ "${UNITY_KEEP_PREFS:-0}" != "1" ] && [ "$(uname -s)" = "Darwin" ] && command -v defaults >/dev/null 2>&1; then
  company="$(sed -n 's/^  companyName: //p' "$ROOT/ProjectSettings/ProjectSettings.asset" 2>/dev/null | head -n 1 | tr -d '\r')"
  product="$(sed -n 's/^  productName: //p' "$ROOT/ProjectSettings/ProjectSettings.asset" 2>/dev/null | head -n 1 | tr -d '\r')"
  if [ -n "$company" ] && [ -n "$product" ]; then
    PREFS_DOMAIN="unity.$company.$product"
    if ! defaults read "$PREFS_DOMAIN" >/dev/null 2>&1; then
      PREFS_ABSENT=1
    else
      PREFS_SNAP="$OUT/editor-prefs-$$.plist"
      if ! { defaults export "$PREFS_DOMAIN" "$PREFS_SNAP" 2>/dev/null && plutil -lint -s "$PREFS_SNAP" >/dev/null 2>&1; }; then
        echo "WARN: could not snapshot Editor PlayerPrefs ($PREFS_DOMAIN); this run may change them" >&2
        rm -f "$PREFS_SNAP"; PREFS_DOMAIN="" PREFS_SNAP=""
      fi
    fi
  fi
fi
restore_editor_prefs() {
  if [ -n "$UNITY_PID" ] && kill -0 "$UNITY_PID" 2>/dev/null; then  # interrupted: stop the Editor first
    kill "$UNITY_PID" 2>/dev/null; sleep 1; kill -9 "$UNITY_PID" 2>/dev/null
  fi
  [ -n "$PREFS_DOMAIN" ] || return 0
  if [ "$PREFS_ABSENT" = "1" ]; then
    defaults delete "$PREFS_DOMAIN" >/dev/null 2>&1
    return 0
  fi
  [ -s "$PREFS_SNAP" ] || return 0
  defaults delete "$PREFS_DOMAIN" >/dev/null 2>&1
  if defaults import "$PREFS_DOMAIN" "$PREFS_SNAP"; then
    rm -f "$PREFS_SNAP"
  else
    echo "WARN: restoring Editor PlayerPrefs failed. Snapshot kept: defaults import $PREFS_DOMAIN $PREFS_SNAP" >&2
  fi
}
trap restore_editor_prefs EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_editor() {  # $1 = log file, rest = Editor args. Returns Editor exit code, 124 on timeout.
  local log="$1" pid waited=0; shift
  : > "$log"
  # shellcheck disable=SC2086
  "$UNITY" "$@" ${UNITY_EXTRA_ARGS:-} -logFile "$log" &
  pid=$!
  UNITY_PID=$pid
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$LIMIT" ]; then
      echo "TIMEOUT after ${LIMIT}s — killing Unity (pid $pid); Temp/UnityLockfile may be left behind" >&2
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 5; waited=$((waited + 5))
  done
  wait "$pid"
}

compile_errors() {  # $1 = log file → prints the compiler errors, returns 0 when there are some
  grep -nE "error CS[0-9]+|Scripts have compiler errors|Shader error in" "$1" 2>/dev/null | head -n 40 | grep -q . || return 1
  echo "===== C# compile errors ($1) ====="
  grep -nE "error CS[0-9]+|Scripts have compiler errors|Shader error in" "$1" | head -n 40
  return 0
}

if [ "$MODE" = "compile" ]; then
  LOG="$OUT/compile.log"
  run_editor "$LOG" -batchmode -quit -nographics -projectPath "$ROOT"
  rc=$?
  compile_errors "$LOG" && exit 1
  [ "$rc" -eq 124 ] && exit 1
  if [ "$rc" -ne 0 ]; then echo "===== Unity exited $rc — last 40 log lines ====="; tail -n 40 "$LOG"; exit 1; fi
  echo "PASS: compile clean (0 'error CS'), Unity $VERSION — log: $LOG"
  exit 0
fi

if [ "$MODE" = "execute" ]; then
  LOG="$OUT/execute.log"
  set -- -batchmode -projectPath "$ROOT" -executeMethod "$METHOD"
  [ "${UNITY_NOGRAPHICS:-0}" = "1" ] && set -- "$@" -nographics
  [ ${#EXEC_ARGS[@]} -gt 0 ] && set -- "$@" "${EXEC_ARGS[@]}"
  run_editor "$LOG" "$@"
  rc=$?
  compile_errors "$LOG" && exit 1
  [ "$rc" -eq 124 ] && exit 1
  if [ "$rc" -ne 0 ]; then echo "===== $METHOD: Unity exited $rc — last 40 log lines ====="; tail -n 40 "$LOG"; exit 1; fi
  echo "PASS: $METHOD exited 0 — log: $LOG"
  exit 0
fi

PLATFORM="EditMode"; case "$MODE" in playmode|PlayMode) PLATFORM="PlayMode" ;; esac
LOG="$OUT/tests_${PLATFORM}.log"
XML="$OUT/tests_${PLATFORM}.xml"
rm -f "$XML"
set -- -batchmode -projectPath "$ROOT" -runTests -testPlatform "$PLATFORM" -testResults "$XML"
[ "$PLATFORM" = "EditMode" ] && set -- "$@" -nographics
[ "$PLATFORM" = "PlayMode" ] && [ "${UNITY_NOGRAPHICS:-0}" = "1" ] && set -- "$@" -nographics
[ -n "$FILTER" ] && set -- "$@" -testFilter "$FILTER"
[ -n "$CATEGORY" ] && set -- "$@" -testCategory "$CATEGORY"
[ -n "$ASSEMBLY" ] && set -- "$@" -assemblyNames "$ASSEMBLY"
run_editor "$LOG" "$@"
rc=$?
compile_errors "$LOG" && exit 1
[ "$rc" -eq 124 ] && exit 1
if [ ! -s "$XML" ]; then
  echo "FAIL: Unity exited $rc but wrote no results file ($XML) — last 40 log lines:"
  tail -n 40 "$LOG"
  exit 1
fi
python3 - "$XML" "$PLATFORM" "$rc" <<'PY'
import sys
import xml.etree.ElementTree as ET
path, platform, rc = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    root = ET.parse(path).getroot()
except ET.ParseError as e:
    print(f"FAIL: {path} is not valid NUnit XML: {e}")
    sys.exit(1)
cases = list(root.iter("test-case"))
failed = [c for c in cases if c.get("result") == "Failed"]
skipped = sum(1 for c in cases if c.get("result") == "Skipped")
passed = sum(1 for c in cases if c.get("result") == "Passed")
if not cases:
    print(f"FAIL: {platform}: 0 test cases executed (wrong filter/category, or the test assembly did not compile)")
    sys.exit(1)
for c in failed[:30]:
    msg = (c.findtext("failure/message") or "").strip().splitlines()
    print(f"  [Failed] {c.get('fullname')}: {msg[0] if msg else ''}")
if failed or rc != 0:
    print(f"FAIL: {platform}: {passed} passed, {len(failed)} failed, {skipped} skipped (Unity exit {rc}) — {path}")
    sys.exit(1)
print(f"PASS: {platform}: {passed} passed, 0 failed, {skipped} skipped — {path}")
PY
