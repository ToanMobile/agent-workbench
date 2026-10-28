#!/bin/bash
# #488: tests/lib/tlimit.py runs its command in its own process group; a SIGTERM/SIGINT sent to tlimit itself (Ctrl-C, run_impacted killing a
# suite past its time) must stop that whole group, not leave the child (a post-fix-gate holding a lock/slot) running orphaned.
# Rows: SIGTERM -> grandchild gone, exit 143 · SIGINT -> grandchild gone, exit 130 · a normal exit code passes through · a timeout is still 124.
# TLIMIT=<path> tests another copy of the helper (the pre-fix one must go red).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TL="${TLIMIT:-$HERE/lib/tlimit.py}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed)" >&2; exit 1; fi
cleanup() {
  local f
  for f in "$TMP"/gc.*; do [ -f "$f" ] && kill -9 "$(cat "$f")" 2>/dev/null; done
  rm -r "$TMP" 2>/dev/null
}
trap cleanup EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

sig_row() { # <signal name> <want rc> <label>
  local sig="$1" want="$2" label="$3" f="$TMP/gc.$1" pid gc rc i
  python3 -I "$TL" 60 sh -c "sleep 300 & echo \$! > '$f'; wait" >/dev/null 2>&1 &
  pid=$!
  for i in $(seq 1 50); do [ -s "$f" ] && break; sleep 0.1; done
  if [ ! -s "$f" ]; then bad "$label: grandchild never started"; kill -9 "$pid" 2>/dev/null; return; fi
  gc="$(cat "$f")"
  kill -"$sig" "$pid"
  wait "$pid"; rc=$?
  for i in $(seq 1 60); do kill -0 "$gc" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$gc" 2>/dev/null; then bad "$label: grandchild $gc still running after tlimit got SIG$sig (orphaned)"; kill -9 "$gc" 2>/dev/null
  else ok "$label: grandchild stopped"; fi
  if [ "$rc" = "$want" ]; then ok "$label: exit $rc"; else bad "$label: exit $rc, want $want"; fi
}
sig_row TERM 143 "SIGTERM"
sig_row INT 130 "SIGINT"

python3 -I "$TL" 60 sh -c 'exit 7' >/dev/null 2>&1; rc=$?
if [ "$rc" = 7 ]; then ok "rc passthrough"; else bad "rc passthrough: $rc"; fi
python3 -I "$TL" 1 sleep 30 >/dev/null 2>&1; rc=$?
if [ "$rc" = 124 ]; then ok "timeout 124"; else bad "timeout: $rc"; fi

if [ "$FAILS" = 0 ]; then echo "PASS"; exit 0; fi
echo "FAIL ($FAILS)"; exit 1
