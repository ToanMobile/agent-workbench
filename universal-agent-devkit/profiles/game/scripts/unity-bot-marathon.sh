#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# unity-bot-marathon.sh — Bot Gameplay Simulation Oracle (Unity batchmode)
#
# Plays N levels with the project's own bot (a static Editor method) and checks the
# result line it prints. Proves generator/solver output is actually winnable end to end,
# which unit tests of the solver alone do not.
#
#   unity-bot-marathon.sh [levels]            # levels: "100", "1-100" or "3,7,12" (default 1-100)
#
# 1. If the project has its own scripts/unity-bot-marathon.sh, that one runs (it knows
#    its bot); this file is only the generic fallback.
# 2. Otherwise BOT_METHOD must name the project's static Editor method, e.g.
#    BOT_METHOD=MyGame.Editor.BotRunner.RunMarathon. The levels are passed as
#    `-botLevels <levels>` and in $BOT_LEVELS.
#
# Contract for the bot method: print exactly one line
#   [BOT-SUMMARY] won=<W>/<T> deadlocks=<D>
# and exit the Editor (EditorApplication.Exit(0|1)). PASS only when W == T and D == 0.
#
# Exit: 0 PASS · 1 FAIL (lost level, deadlock, no summary line, timeout, Unity error)
#       2 UNTESTED (no Editor / no bot method / project open in an Editor) — never a PASS.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

LEVELS="${1:-1-100}"
ROOT="$(cd "${UNITY_PROJECT:-$PWD}" 2>/dev/null && pwd -P)" || { echo "UNTESTED: project dir not found"; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [ -x "$ROOT/scripts/unity-bot-marathon.sh" ] && [ "$(cd "$ROOT/scripts" && pwd -P)" != "$HERE" ]; then
  exec "$ROOT/scripts/unity-bot-marathon.sh" "$@"
fi

if [ -z "${BOT_METHOD:-}" ]; then
  echo "UNTESTED: set BOT_METHOD=<Namespace.Class.StaticMethod> (the project's bot entry point)"
  echo "          or add scripts/unity-bot-marathon.sh to the project. No bot ran — this is not a PASS."
  exit 2
fi

case "$LEVELS" in
  *-*) COUNT=$(( ${LEVELS#*-} - ${LEVELS%-*} + 1 )) ;;
  *,*) COUNT=$(printf '%s' "$LEVELS" | tr ',' '\n' | grep -c .) ;;
  *)   COUNT="$LEVELS" ;;
esac
# ~2 minutes per level + Editor start-up, unless the caller sets UNITY_TIMEOUT.
export UNITY_TIMEOUT="${UNITY_TIMEOUT:-$(( COUNT * 120 + 180 ))}"
export BOT_LEVELS="$LEVELS"

OUT="${UNITY_BATCH_OUT:-$ROOT/Logs/agent-kit}"
LOG="$OUT/bot_marathon.log"
mkdir -p "$OUT"

# Editor lookup, one-Editor-per-project check, watchdog and `error CS` scan come from
# unity-batch.sh; `execute` runs without -quit (the bot enters Play Mode and calls
# EditorApplication.Exit itself).
UNITY_BATCH_OUT="$OUT" UNITY_PROJECT="$ROOT" \
  bash "$HERE/unity-batch.sh" execute "$BOT_METHOD" -botLevels "$LEVELS" >"$OUT/bot_marathon.stdout" 2>&1
rc=$?
cp "$OUT/execute.log" "$LOG" 2>/dev/null || true
if [ "$rc" -eq 2 ]; then
  cat "$OUT/bot_marathon.stdout"
  exit 2
fi

SUMMARY="$(grep -a "\[BOT-SUMMARY\]" "$LOG" | tail -n 1)"
grep -aE "\[BOT\]|\[FAIL\]" "$LOG" | tail -n 40
if [ -z "$SUMMARY" ]; then
  echo "FAIL: no [BOT-SUMMARY] line in $LOG (Unity exit $rc) — the bot did not finish"
  exit 1
fi
echo "$SUMMARY"
WON="$(printf '%s' "$SUMMARY" | sed -n 's/.*won=\([0-9]*\)\/\([0-9]*\).*/\1/p')"
TOTAL="$(printf '%s' "$SUMMARY" | sed -n 's/.*won=\([0-9]*\)\/\([0-9]*\).*/\2/p')"
DEAD="$(printf '%s' "$SUMMARY" | sed -n 's/.*deadlocks=\([0-9]*\).*/\1/p')"
if [ -z "$WON" ] || [ -z "$TOTAL" ] || [ "$WON" != "$TOTAL" ] || [ "${DEAD:-0}" != "0" ] || [ "$rc" -ne 0 ]; then
  echo "FAIL: bot won ${WON:-?}/${TOTAL:-?}, deadlocks=${DEAD:-?}, Unity exit $rc — log: $LOG"
  exit 1
fi
echo "PASS: bot won $WON/$TOTAL levels, 0 deadlocks — log: $LOG"
