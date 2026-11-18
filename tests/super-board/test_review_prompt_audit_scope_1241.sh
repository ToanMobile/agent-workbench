#!/usr/bin/env bash
# #1241 (bổ sung #1235): hai nơi quyết định cách worker Review audit PR sửa test đã có vẫn dặn `project = config repo.path` (checkout chính) và
# không cấm `message`, nên server PM trả `Khong ghi pham vi` và merge gate bỏ qua audit. Lượt Review của #1003 (17/11) đọc SKILL.md mới mà vẫn
# làm theo prompt trực tiếp của runner. Ghim:
#  A  prompt Review trong super-board-run.sh: project = worktree review, WITHOUT a message parameter, có `Pham vi:`; không còn `config repo.path`
#  B  worker-preamble.md: cùng ý; không còn `project = config `repo.path``
# Tương thích bash 3.2. Đọc file từ cây này; đặt TEST_REF=<git ref> để kiểm bản cũ (đỏ trên origin/main trước sửa).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
RUN=".claude/bin/super-board-run.sh"
PRE=".claude/skills/super-build/references/worker-preamble.md"
get() { if [ -n "${TEST_REF:-}" ]; then git -C "$ROOT" show "$TEST_REF:$1" 2>/dev/null; else cat "$ROOT/$1"; fi; }

# dòng prompt Review: dòng có `Run super-review on issue`
rp="$(get "$RUN" | grep -F 'Run super-review on issue' | head -1)"
[ -n "$rp" ] || fail "A0: review prompt line not found in $RUN"
case "$rp" in *"project = the config repo.path"*) fail "A1: review prompt still says project = the config repo.path" ;; *) ok "A1: review prompt no longer points the audit at the main checkout" ;; esac
case "$rp" in *"review worktree"*) ok "A2: review prompt names the card's review worktree" ;; *) fail "A2: review prompt does not name the review worktree" ;; esac
case "$rp" in *"WITHOUT a message parameter"*) ok "A3: review prompt forbids the message parameter" ;; *) fail "A3: review prompt does not forbid message" ;; esac
case "$rp" in *"Pham vi:"*) ok "A4: review prompt asks for the Pham vi: line" ;; *) fail "A4: review prompt does not mention Pham vi:" ;; esac

pl="$(get "$PRE" | grep -F 'pm_task_create' | head -1)"
[ -n "$pl" ] || fail "B0: pm_task_create line not found in $PRE"
case "$pl" in *'project = config `repo.path`'*) fail "B1: worker-preamble still says project = config repo.path" ;; *) ok "B1: worker-preamble no longer points the audit at the main checkout" ;; esac
case "$pl" in *"review worktree"*) ok "B2: worker-preamble names the review worktree" ;; *) fail "B2: worker-preamble does not name the review worktree" ;; esac
case "$pl" in *"WITHOUT"*"message"*) ok "B3: worker-preamble forbids message" ;; *) fail "B3: worker-preamble does not forbid message" ;; esac

[ "$FAILS" = 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
