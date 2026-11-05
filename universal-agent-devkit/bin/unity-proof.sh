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

# Một Editor batchmode trên máy: cùng khoá với unity-batch.sh và pool `unity` của heavy_slot (<slot dir>/unity-1.lock, P5 04/11).
# SB_HEAVY_SLOT_HELD=1 (không UNITY_BATCH_LOCK): tiến trình cha đang giữ khoá đó, không xin lại. UNITY_LOCK_WAIT_S (mặc định 3600)
# giới hạn lúc chờ: quá hạn thì exit 2. macOS không có flock(1).
UNITY_LOCK_PATH="${UNITY_BATCH_LOCK:-${SB_HEAVY_SLOT_DIR:-$HOME/.claude/super-board/locks}/unity-1.lock}"
UNITY_LOCK_SKIP=0
[ -z "${UNITY_BATCH_LOCK:-}" ] && [ "${SB_HEAVY_SLOT_HELD:-}" = "1" ] && UNITY_LOCK_SKIP=1
UNITY_LOCK_PY=""
UNITY_LOCK_SENTINEL=""

release_unity_lock() {
  if [ -n "${UNITY_LOCK_SENTINEL:-}" ]; then
    rm -f "$UNITY_LOCK_SENTINEL"
  fi
  if [ -n "${UNITY_LOCK_PY:-}" ]; then
    i=0
    while kill -0 "$UNITY_LOCK_PY" 2>/dev/null && [ "$i" -lt 80 ]; do
      sleep 0.05
      i=$((i + 1))
    done
    kill "$UNITY_LOCK_PY" 2>/dev/null || true
    wait "$UNITY_LOCK_PY" 2>/dev/null || true
    UNITY_LOCK_PY=""
  fi
  if [ -n "${UNITY_LOCK_SENTINEL:-}" ]; then
    rm -f "${UNITY_LOCK_SENTINEL}.held" "$UNITY_LOCK_SENTINEL"
    UNITY_LOCK_SENTINEL=""
  fi
}

acquire_unity_lock() {
  [ "$UNITY_LOCK_SKIP" = "1" ] && return 0
  mkdir -p "$(dirname "$UNITY_LOCK_PATH")" || { echo "unity-proof: cannot create unity lock dir" >&2; exit 2; }
  UNITY_LOCK_SENTINEL="$(mktemp "${TMPDIR:-/tmp}/unity-proof-sentinel.XXXXXX")" || {
    echo "unity-proof: cannot create unity lock sentinel" >&2; exit 2; }
  python3 - "$UNITY_LOCK_PATH" "$UNITY_LOCK_SENTINEL" "${UNITY_LOCK_WAIT_S:-3600}" <<'PY' &
import fcntl, os, sys, time
path, sentinel = sys.argv[1], sys.argv[2]
try:
    wait_s = max(0.0, float(sys.argv[3]))
except ValueError:
    wait_s = 3600.0
os.makedirs(os.path.dirname(path) or ".", mode=0o700, exist_ok=True)
fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
deadline, told = time.monotonic() + wait_s, False
while True:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except OSError:
        try:
            holder = os.pread(fd, 32, 0).decode("ascii", "replace").strip() or "?"
        except OSError:
            holder = "?"
        if time.monotonic() >= deadline:
            with open(sentinel + ".busy", "w") as fh:
                fh.write(holder)
            sys.exit(3)
        if not told:
            print(f"unity-proof: waiting for the Unity lock {path} (held by pid {holder}, up to {wait_s:g}s)", file=sys.stderr, flush=True)
            told = True
        time.sleep(0.2)
open(sentinel + ".held", "w").close()
while os.path.exists(sentinel):
    time.sleep(0.05)
try:
    fcntl.flock(fd, fcntl.LOCK_UN)
except OSError:
    pass
os.close(fd)
PY
  UNITY_LOCK_PY=$!
  while [ ! -f "${UNITY_LOCK_SENTINEL}.held" ]; do
    if ! kill -0 "$UNITY_LOCK_PY" 2>/dev/null; then
      if [ -f "${UNITY_LOCK_SENTINEL}.busy" ]; then
        echo "unity-proof: unity lock busy past UNITY_LOCK_WAIT_S=${UNITY_LOCK_WAIT_S:-3600}s (pid $(cat "${UNITY_LOCK_SENTINEL}.busy")): $UNITY_LOCK_PATH" >&2
        rm -f "${UNITY_LOCK_SENTINEL}.busy"
      else
        echo "unity-proof: unity machine lock failed" >&2
      fi
      exit 2
    fi
    sleep 0.05
  done
}

log="$(mktemp -t unity-proof.XXXXXX)"
trap 'release_unity_lock; rm -f "$log"' EXIT
acquire_unity_lock
case "$shot" in /*) shotpath="$shot";; *) shotpath="$project/$shot";; esac
rm -f "$shotpath"
# shellcheck disable=SC2086
nice -n 15 "$unity" -batchmode -job-worker-count 4 $quit -projectPath "$project" -executeMethod "$method" -logFile "$log" >/dev/null 2>&1 &
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
