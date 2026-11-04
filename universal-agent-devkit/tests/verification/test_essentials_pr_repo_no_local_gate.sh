#!/usr/bin/env bash
# #984 (05/11, chủ repo duyệt): đo 01–04/11 — 66 % slot-giây pool gate lúc merge gate chờ là gate task --scoped chạy ở worktree.
# Repo đi PR (có .claude/super-board/configs/) không chạy gate scoped đầy đủ ở local: push rồi merge gate --dry-run chạy nền song
# song review; merge gate là gate duy nhất, XONG chờ biên nhận merge. Repo push thẳng trunk giữ gate local (lệnh scoped vẫn còn).
# ESSENTIALS_FILE: đọc file khác (chạy ĐỎ trên bản cũ). Tương thích bash 3.2.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ESS="${ESSENTIALS_FILE:-$DK/rules/essentials.md}"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$ESS" ] || { echo "✖ missing $ESS"; exit 1; }
step3="$(awk '/^## Every prompt/{e=1} e && /^3\. /{f=1} e && /^4\. /{f=0} f' "$ESS" | tr '\n' ' ' | tr -s ' ')"
[ -n "$step3" ] || { echo "✖ step 3 of 'Every prompt' not found"; exit 1; }
has() { case "$step3" in *"$1"*) return 0 ;; esac; return 1; }
has "PR repo (\`.claude/super-board/configs/\`): no local scoped run" \
  && ok "step 3: a PR repo (board config present) runs no local scoped gate" || fail "step 3 still lets a PR repo run the scoped gate locally"
has "merge gate \`--dry-run\` in background" && ok "step 3: push, then the merge gate --dry-run in the background" \
  || fail "step 3 does not send a PR repo to the merge gate --dry-run in the background"
has "post-fix-gate.py --run-tests --scoped --brief" && ok "step 3: the scoped gate stays for a trunk-push repo" \
  || fail "step 3 lost the scoped gate command"
grep -q "Done means verified\*\*: step 3 at exit 0 on the current code" "$ESS" \
  && fail "Done means verified still demands a local step 3 exit 0 from a PR repo" || ok "Done means verified: points at step 3 (PR repo: merge receipt)"
[ "$FAILS" = 0 ] && echo "✅ test_essentials_pr_repo_no_local_gate: all checks passed" || { echo "❌ $FAILS failed"; exit 1; }
