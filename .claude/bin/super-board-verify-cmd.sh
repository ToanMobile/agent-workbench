#!/usr/bin/env bash
# super-board-verify-cmd.sh --config <cfg> — in từng lệnh verify (một dòng mỗi lệnh) đúng như merge gate sẽ chạy, kể cả
# ` --diff origin/<base> --force-full`. QA chạy các lệnh này trên cây gộp base hiện tại để bắt cùng lỗi merge gate sẽ bắt (#251).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG=""; RECORD=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    --record) RECORD=1; shift ;;
    *) echo "usage: super-board-verify-cmd.sh --config <cfg> [--record]" >&2; exit 64 ;;
  esac
done
[ -f "$CONFIG" ] || { echo "super-board-verify-cmd: --config <file> required" >&2; exit 64; }
. "$HERE/super-board-verify-flags.sh"
BASE=$(jq -r '.base_branch // "main"' "$CONFIG")
jq -r '.verify_commands[] | select(test("\\S"))' "$CONFIG" | while IFS= read -r c; do
  sb_verify_inject_flags "$c" "$BASE"; echo
done
# --record (#226 gap 7): chạy chính các lệnh trên trên cây gộp sạch, và chỉ khi TẤT CẢ exit 0 mới ghi biên nhận cùng khoá với merge gate
# (OCR 24/10: bản cũ tin lời người gọi, không ai kiểm lệnh đã chạy/đạt). Base đổi thì khoá khác.
if [ "$RECORD" -eq 1 ]; then
  [ -z "$(git status --porcelain 2>/dev/null)" ] || { echo "super-board-verify-cmd: --record needs a clean merged tree" >&2; exit 65; }
  # Cây phải chứa origin/<base> hiện tại: khoá theo tree, nhưng QA chưa gộp base mới thì cây này không phải cây merge gate sẽ dựng.
  git merge-base --is-ancestor "origin/$BASE" HEAD 2>/dev/null || { echo "super-board-verify-cmd: --record needs origin/$BASE merged into this tree" >&2; exit 65; }
  CMDS=(); while IFS= read -r c; do CMDS+=("$c"); done < <(jq -r '.verify_commands[] | select(test("\\S"))' "$CONFIG")
  [ "${#CMDS[@]}" -gt 0 ] || { echo "super-board-verify-cmd: no verify commands; no receipt" >&2; exit 0; }   # bash 3.2: "${CMDS[@]}" rỗng lỗi unbound
  RECEIPT=$(sb_verified_tree_receipt "$(git rev-parse 'HEAD^{tree}')" "$BASE" "." "${CMDS[@]}")
  [ -n "$RECEIPT" ] || { echo "super-board-verify-cmd: no git common dir or sha256 tool; no receipt" >&2; exit 66; }
  for c in "${CMDS[@]}"; do
    RUN=$(sb_verify_inject_flags "$c" "$BASE")
    bash -c "$RUN" >&2 || { echo "super-board-verify-cmd: verify command failed (exit $?); no receipt: $RUN" >&2; exit 11; }
  done
  mkdir -p "${RECEIPT%/*}" && : > "$RECEIPT" && echo "recorded verified tree receipt ${RECEIPT##*/}" >&2
fi
