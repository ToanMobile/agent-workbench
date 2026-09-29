#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# session_lock.sh — SessionStart / PreToolUse / SessionEnd hook: ONE agent session per checkout.
# Logic and rationale: bin/session_lock.py (owner request, GeelyEx2 2026-09-29: two sessions in one checkout voided
# full-gate receipts and blocked a push). Exit 2 on PreToolUse = blocked; SessionStart never blocks.
# ─────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0")")" && pwd)"
exec python3 "$HERE/../bin/session_lock.py"
