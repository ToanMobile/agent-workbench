#!/usr/bin/env bash
# #106: prompt lane của super-board-wave.js (merge gate exit 7 và exit 8) chỉ nói "label needs-you", nên lane chạy qua workflow
# backend không đăng comment 🙋 Cần bạn lên thẻ. Test này khẳng định cả hai chuỗi gọi đúng `super-board-needs-you.py mark`
# với --repo --issue --action --next (block-template.md → "A person must act").
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WAVE="$ROOT/.claude/workflows/super-board-wave.js"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

for n in 7 8; do
  line="$(grep -F "Exit $n = " "$WAVE" | head -1)"
  [ -n "$line" ] || { fail "exit $n: không có chuỗi prompt"; continue; }
  for needle in "super-board-needs-you.py mark" "--repo" "--issue" "--action" "--next"; do
    case "$line" in *"$needle"*) ok "exit $n chứa '$needle'" ;; *) fail "exit $n thiếu '$needle'" ;; esac
  done
done
line7="$(grep -F "Exit 7 = " "$WAVE" | head -1)"
case "$line7" in *"comment đúng một chữ done"*) ok "exit 7 --next nêu comment done" ;; *) fail "exit 7 --next thiếu 'comment đúng một chữ done'" ;; esac
line8="$(grep -F "Exit 8 = " "$WAVE" | head -1)"
case "$line8" in *"comment đúng một chữ done"*) ok "exit 8 --next nêu comment done" ;; *) fail "exit 8 --next thiếu 'comment đúng một chữ done'" ;; esac

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
