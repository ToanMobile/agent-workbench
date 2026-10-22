#!/usr/bin/env bash
# #250: lane reviewer không chạy lại `post-fix-gate.py --run-tests --full` trước merge gate — merge gate --force-full đã verify
# cây gộp, nên lần chạy thứ tư là việc trùng. Test khẳng định prompt lane reviewer, run.md (Reviewer) và super-review/SKILL.md
# đều nói rõ "never rerun post-fix-gate --full" và không còn câu "rerun it yourself".
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WAVE="$ROOT/.claude/workflows/super-board-wave.js"
RUN="$ROOT/.claude/skills/super-board/references/run.md"
SKILL="$ROOT/.claude/skills/super-review/SKILL.md"
MARK="never rerun post-fix-gate --full"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Prompt reviewer = REVIEW_MEMORY; không dòng nào được bảo reviewer chạy gate --full.
review_block="$(awk '/^const REVIEW_MEMORY = \[/{f=1} f{print} f&&/^\]/{exit}' "$WAVE")"
[ -n "$review_block" ] || fail "không tìm thấy REVIEW_MEMORY trong wave.js"
case "$review_block" in *"$MARK"*) ok "prompt reviewer nêu '$MARK'" ;; *) fail "prompt reviewer thiếu '$MARK'" ;; esac
if printf '%s\n' "$review_block" | grep -v -F "$MARK" | grep -q -- 'post-fix-gate.*--full'; then
  fail "prompt reviewer còn lệnh post-fix-gate --full"
else ok "prompt reviewer không chứa lệnh post-fix-gate --full"; fi

case "$(cat "$RUN")" in *"$MARK"*) ok "run.md nêu '$MARK'" ;; *) fail "run.md thiếu '$MARK'" ;; esac
case "$(cat "$SKILL")" in *"$MARK"*) ok "SKILL nêu '$MARK'" ;; *) fail "SKILL thiếu '$MARK'" ;; esac
if grep -q "rerun it" "$SKILL"; then fail "SKILL còn 'rerun it yourself'"; else ok "SKILL hết 'rerun it yourself'"; fi
# Merge gate vẫn thêm --force-full vào lệnh verify.
grep -q -- '--force-full' "$ROOT/.claude/bin/super-board-merge-gate.sh" && ok "merge gate vẫn thêm --force-full" || fail "merge gate mất --force-full"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
