#!/usr/bin/env bash
# #997 (review P2 PR #996): essentials bước 3 nói repo đi PR không chạy gate scoped local, nhưng còn câu nói ngược: bước 5 ("exit 0
# from step 3 (its task receipt)" — repo PR không có task receipt), mục Git non-negotiable ("re-run the step 3 gate after any pull,
# merge or conflict fix" không trừ repo PR) và core-rules §19 ("On a PR branch re-run post-fix-gate.py --run-tests --scoped after any
# pull, merge or conflict fix"). Không câu nào trong essentials/core-rules còn bảo repo đi PR chạy gate scoped local; merge gate là gate.
# ESSENTIALS_FILE / CORE_RULES_FILE: đọc file khác (chạy ĐỎ trên bản cũ). Tương thích bash 3.2.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ESS="${ESSENTIALS_FILE:-$DK/rules/essentials.md}"
CORE="${CORE_RULES_FILE:-$DK/rules/core-rules.md}"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$ESS" ] || { echo "✖ missing $ESS"; exit 1; }
[ -f "$CORE" ] || { echo "✖ missing $CORE"; exit 1; }
join() { tr '\n' ' ' | tr -s ' '; }
step5="$(awk '/^## Every prompt/{e=1} e && /^5\. /{f=1} e && /^## Engineering/{f=0} f' "$ESS" | join)"
git_ess="$(awk '/^- \*\*Git — /{f=1; print; next} f && /^- /{f=0} f' "$ESS" | join)"
git_core="$(awk '/^- \*\*Git\*\*:/{f=1; print; next} f && /^- /{f=0} f' "$CORE" | join)"
[ -n "$step5" ] && [ -n "$git_ess" ] && [ -n "$git_core" ] || { echo "✖ step 5 / Git bullet (essentials) / Git bullet (core-rules §19) not found"; exit 1; }
in_() { case "$2" in *"$1"*) return 0 ;; esac; return 1; }

in_ "PR repo: merge receipt" "$step5" && ok "bước 5: repo đi PR nghiệm thu bằng merge receipt" \
  || fail "bước 5 chỉ nói 'exit 0 from step 3 (its task receipt)' — repo đi PR không có task receipt"
in_ "re-run the step 3 gate after any pull, merge or conflict fix (not in a PR repo)" "$git_ess" \
  && ok "Git (essentials): chạy lại gate sau pull/merge/conflict trừ repo đi PR" \
  || fail "Git (essentials): còn bảo chạy lại gate step 3 sau mọi pull/merge/conflict, kể cả repo đi PR"
in_ "On a PR branch re-run \`post-fix-gate.py --run-tests --scoped\`" "$git_core" \
  && fail "core-rules §19 Git: còn bảo nhánh PR chạy lại gate scoped local" || ok "core-rules §19 Git: không còn bảo nhánh PR chạy gate scoped local"
in_ "PR repo" "$git_core" && in_ "re-runs no local gate" "$git_core" && in_ "the merge gate is the gate" "$git_core" \
  && ok "core-rules §19 Git: repo đi PR không chạy lại gate local, merge gate là gate" \
  || fail "core-rules §19 Git: không nói repo đi PR không chạy lại gate local / merge gate là gate"
in_ "merge receipt" "$git_core" && ok "core-rules §19 Git: task xong ở repo đi PR = merge receipt" \
  || fail "core-rules §19 Git: task xong vẫn chỉ là task receipt của step 3"
# hai câu tiếng Việt của core-rules (mục Git đầu file, §2 nghiệm thu) cũng đòi `--scoped` exit 0 trong lượt: phải trừ repo đi PR
bad=0
while IFS= read -r l; do
  case "$l" in *"--run-tests --scoped\` exit 0"*) case "$l" in *"repo đi PR: biên nhận merge gate"*) ;; *) bad=$((bad + 1)) ;; esac ;; esac
done < "$CORE"
[ "$bad" = 0 ] && ok "core-rules: mọi câu đòi '--scoped exit 0' trong lượt đều trừ repo đi PR (biên nhận merge gate)" \
  || fail "core-rules: $bad câu đòi '--run-tests --scoped exit 0' mà không trừ repo đi PR"
# trunk-push repo giữ gate trước integrate (không nới cho repo push thẳng)
in_ "agent-kit integrate" "$git_core" && ok "core-rules §19 Git: repo push thẳng trunk vẫn qua agent-kit integrate" \
  || fail "core-rules §19 Git: mất câu agent-kit integrate của repo push thẳng trunk"

[ "$FAILS" = 0 ] && echo "✅ test_essentials_pr_repo_no_local_regate: all checks passed" || { echo "❌ $FAILS failed"; exit 1; }
