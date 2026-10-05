#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# session_lock.sh — SessionStart / PreToolUse / SessionEnd hook: ONE agent session per checkout.
# Logic and rationale: bin/session_lock.py (owner request, GeelyEx2 2026-09-29: two sessions in one checkout voided
# full-gate receipts and blocked a push). Exit 2 on PreToolUse = blocked; SessionStart never blocks.
# ─────────────────────────────────────────────────────────────────────────────
# HERE = the directory this file really lives in (symlinks followed): `$HERE/../bin` is the kit. This runs on EVERY PreToolUse and is the
# slowest hook of the PreBash group, so it is resolved in bash (a python start for it cost ~18 ms): follow the symlink chain of $0 (absolute
# or relative targets, at most 32 hops), then `cd -P` (the kernel resolves directory symlinks and `..` physically, as os.path.realpath
# does). Anything unexpected — a loop or a chain over the bound, a readlink that is missing or fails or has no -n, a target or directory name
# with a newline, a directory that cannot be entered — falls through to the OLD python line below, so those cases behave exactly as before.
# `$(...)` strips trailing newlines, so a target `s.sh<newline>` would be followed as the file `s.sh`: readlink -n + a sentinel keeps it exact.
# Equivalence proof: tests/gates/test_session_lock_resolve.sh.
_sl_nl='
'
_sl_self="$0"
_sl_n=0
while [ -L "$_sl_self" ] && [ "$_sl_n" -lt 32 ]; do
  _sl_n=$((_sl_n + 1))
  _sl_link="$(readlink -n "$_sl_self" 2>/dev/null && printf x)" || _sl_link=""
  _sl_link="${_sl_link%x}"
  case "$_sl_link" in
    ""|*"$_sl_nl"*) _sl_n=99 ;;
    /*) _sl_self="$_sl_link" ;;
    *) case "$_sl_self" in */*) _sl_self="${_sl_self%/*}/$_sl_link" ;; *) _sl_self="./$_sl_link" ;; esac ;;
  esac
done
HERE=""
if [ -n "$0" ] && [ "$_sl_n" -lt 32 ]; then
  case "$_sl_self" in */*) _sl_dir="${_sl_self%/*}"; [ -n "$_sl_dir" ] || _sl_dir="/" ;; *) _sl_dir="." ;; esac
  case "$_sl_dir" in *"$_sl_nl"*) ;; *) HERE="$(unset CDPATH; cd -P -- "$_sl_dir" 2>/dev/null && pwd -P)" || HERE="" ;; esac
fi
[ -n "$HERE" ] || HERE="$(cd "$(dirname "$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0")")" && pwd)"
exec python3 "$HERE/../bin/session_lock.py"
