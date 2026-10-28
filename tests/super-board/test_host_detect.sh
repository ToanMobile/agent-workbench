#!/usr/bin/env bash
# #549: super-board-host.sh names claude, codex and agy explicitly and rejects an unknown host
# instead of answering `claude` for everything that is not Codex.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOST="$ROOT/.claude/bin/super-board-host.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

run() { env -i PATH="$PATH" "$@" bash "$HOST" 2>/dev/null; }
expect() { # <label> <want> <env...>
  local label="$1" want="$2"; shift 2
  local got; got="$(run "$@")"
  [ "$got" = "$want" ] && ok "$label → $want" || fail "$label: want $want, got '$got'"
}

expect "SUPER_BOARD_HOST=claude" claude SUPER_BOARD_HOST=claude
expect "SUPER_BOARD_HOST=codex" codex SUPER_BOARD_HOST=codex
expect "SUPER_BOARD_HOST=agy" agy SUPER_BOARD_HOST=agy
expect "CODEX_THREAD_ID set" codex CODEX_THREAD_ID=t1
expect "ANTIGRAVITY_* set" agy ANTIGRAVITY_SESSION_ID=a1
expect "CODEX id beats ANTIGRAVITY" codex CODEX_THREAD_ID=t1 ANTIGRAVITY_SESSION_ID=a1
expect "forced claude beats CODEX id" claude SUPER_BOARD_HOST=claude CODEX_THREAD_ID=t1
expect "no signal → claude" claude

out="$(env -i PATH="$PATH" SUPER_BOARD_HOST=gemini bash "$HOST" 2>&1)"; rc=$?
if [ "$rc" -eq 64 ] && echo "$out" | grep -q "claude, codex or agy"; then ok "unknown SUPER_BOARD_HOST → exit 64 naming claude, codex or agy"
else fail "unknown SUPER_BOARD_HOST: rc=$rc out='$out'"; fi

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
