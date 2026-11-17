#!/usr/bin/env bash
# #1267: the antigravity worker launch must not pass `--effort` together with a `--model` whose name already carries the effort level
# (gemini-4-argon-high/medium/low). The real `agy` rejects that pair at argument parsing ("--model gemini-4-argon-high conflicts with
# --effort=xhigh", exit 1, 5 s), so every build/QA/review worker died at once and the card was blocked after 3 deaths.
set -u
cd "$(dirname "$0")/../.." || exit 1
RUN=.claude/bin/super-board-run.sh
fails=0
ok()   { echo "ok   $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

n=0
# The launch line(s): every line that execs the agy binary with --model (bash 3.2 safe: no mapfile).
while IFS= read -r l; do
  n=$((n + 1))
  model=$(printf '%s' "$l" | grep -oE -- '--model +[A-Za-z0-9._-]+' | head -1 | awk '{print $2}')
  case "$model" in
    *-high|*-medium|*-low)
      if printf '%s' "$l" | grep -qE -- '--effort'; then
        fail "B1: launch passes --effort with model $model whose name already encodes the level (agy rejects it): line ${l%%:*}"
      else ok "B1: model $model launched without --effort"; fi ;;
    *) ok "B1: model '$model' has no level suffix, --effort cannot conflict" ;;
  esac
  printf '%s' "$l" | grep -qE -- '--dangerously-skip-permissions' \
    && ok "C1: launch keeps --dangerously-skip-permissions" || fail "C1: launch lost --dangerously-skip-permissions"
  printf '%s' "$l" | grep -qE -- '-p +"\$prompt"' \
    && ok "C2: launch keeps -p \"\$prompt\"" || fail "C2: launch lost -p \"\$prompt\""
done < <(grep -nE '\.local/bin/agy"? +--model' "$RUN" 2>/dev/null)

[ "$n" -ge 1 ] && ok "A1: found $n agy worker launch line(s) in $RUN" || fail "A1: no agy launch line found in $RUN"

[ "$fails" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAILED: $fails"; exit 1; }
