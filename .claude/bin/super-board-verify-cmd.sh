#!/usr/bin/env bash
# super-board-verify-cmd.sh --config <cfg> — in từng lệnh verify (một dòng mỗi lệnh) đúng như merge gate sẽ chạy, kể cả
# ` --diff origin/<base> --force-full`. QA chạy các lệnh này trên cây gộp base hiện tại để bắt cùng lỗi merge gate sẽ bắt (#251).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    *) echo "usage: super-board-verify-cmd.sh --config <cfg>" >&2; exit 64 ;;
  esac
done
[ -f "$CONFIG" ] || { echo "super-board-verify-cmd: --config <file> required" >&2; exit 64; }
. "$HERE/super-board-verify-flags.sh"
BASE=$(jq -r '.base_branch // "main"' "$CONFIG")
jq -r '.verify_commands[] | select(test("\\S"))' "$CONFIG" | while IFS= read -r c; do
  sb_verify_inject_flags "$c" "$BASE"; echo
done
