#!/usr/bin/env bash
# Headless Unity proof: run an Editor method in batchmode (NO -nographics: the render needs the GPU),
# copy the PNG it wrote to --out. No Editor window, no GameView, no screencapture.
# Use as a proof provider in .antigravity-pm.json:
#   "unity": {"type": "shell", "timeoutMs": 180000, "command":
#     "bash .agents/devkit/bin/unity-proof.sh --project {{project}} --method Ns.Class.Method --shot .antigravity-pm/proof/x.png --out {{out}}"}
# The method must write the PNG at --shot (relative to --project). Exit: 0 ok, 1 no PNG/Unity failed,
# 2 usage/no Unity/Editor open on this project, 124 timeout.
set -uo pipefail

project="" method="" shot="" out="" limit=170 quit="-quit"
while [ $# -gt 0 ]; do
  case "$1" in
    --project) project="$2"; shift 2;;
    --method) method="$2"; shift 2;;
    --shot) shot="$2"; shift 2;;
    --out) out="$2"; shift 2;;
    --timeout) limit="$2"; shift 2;;
    --no-quit) quit=""; shift;;   # for a method that exits the Editor itself (PlayMode runs)
    *) echo "unity-proof: unknown arg $1" >&2; exit 2;;
  esac
done
[ -n "$project" ] && [ -n "$method" ] && [ -n "$shot" ] && [ -n "$out" ] \
  || { echo "usage: unity-proof.sh --project DIR --method Ns.Class.Method --shot REL_PNG --out PNG [--timeout S] [--no-quit]" >&2; exit 2; }

unity="${UNITY:-}"
if [ -z "$unity" ]; then
  ver="$(sed -n 's/^m_EditorVersion: //p' "$project/ProjectSettings/ProjectVersion.txt" 2>/dev/null | head -n 1)"
  unity="/Applications/Unity/Hub/Editor/$ver/Unity.app/Contents/MacOS/Unity"
fi
[ -x "$unity" ] || { echo "unity-proof: Unity not found at $unity (set UNITY=...)" >&2; exit 2; }
# A leftover Temp/UnityLockfile is normal after a crash; only a live Unity on this project blocks.
if [ -f "$project/Temp/UnityLockfile" ] && pgrep -f "projectPath $project( |$)" >/dev/null 2>&1; then
  echo "unity-proof: a Unity is already running on $project" >&2; exit 2
fi

log="$(mktemp -t unity-proof.XXXXXX)"
trap 'rm -f "$log"' EXIT
case "$shot" in /*) shotpath="$shot";; *) shotpath="$project/$shot";; esac
rm -f "$shotpath"
# shellcheck disable=SC2086
"$unity" -batchmode $quit -projectPath "$project" -executeMethod "$method" -logFile "$log" >/dev/null 2>&1 &
pid=$!
waited=0
while kill -0 "$pid" 2>/dev/null; do
  if [ "$waited" -ge "$limit" ]; then
    pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
    echo "unity-proof: Unity exceeded ${limit}s, killed" >&2; exit 124
  fi
  sleep 1; waited=$((waited + 1))
done
wait "$pid"; rc=$?
if [ ! -s "$shotpath" ]; then
  echo "unity-proof: Unity exit $rc, no PNG at $shotpath" >&2
  tail -n 15 "$log" >&2
  exit 1
fi
mkdir -p "$(dirname "$out")"
mv -f "$shotpath" "$out"
echo "unity-proof: $out ($(wc -c <"$out" | tr -d ' ') bytes, ${waited}s, unity exit $rc)"
