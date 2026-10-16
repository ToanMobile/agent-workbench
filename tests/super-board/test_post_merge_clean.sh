#!/usr/bin/env bash
# Test hồi quy cho .claude/bin/super-board-post-merge-clean.sh, bước dọn sau merge của merge gate.
# 2026-10-16: bản đầu xoá --force MỌI worktree issue-*-qa / issue-*-review sau bất kỳ lần merge nào, nên merge
# thẻ A xoá luôn thư mục mà Tester hoặc Reviewer của thẻ B đang làm. Chỉ worktree sạch của chính thẻ vừa merge
# (và nhánh local của nó, khi vẫn trỏ đúng commit đã merge) được xoá.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEAN="$ROOT/.claude/bin/super-board-post-merge-clean.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-postmerge-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
echo a > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm init
mkdir -p "$W"
git -C "$R" branch issue-7-fix-thing
MERGED="$(git -C "$R" rev-parse issue-7-fix-thing)"
git -C "$R" branch issue-8-other
git -C "$R" branch issue-70-similar
git -C "$R" worktree add -q "$W/issue-7-build" issue-7-fix-thing
git -C "$R" worktree add -q --detach "$W/issue-7-qa" main
git -C "$R" worktree add -q --detach "$W/issue-7-review" main
git -C "$R" worktree add -q --detach "$W/issue-7-spike" main          # thẻ 7, nhưng không ở nhánh đã merge
git -C "$R" worktree add -q "$W/issue-8-build" issue-8-other
git -C "$R" worktree add -q --detach "$W/issue-8-qa" main
git -C "$R" worktree add -q --detach "$W/issue-8-review" main
git -C "$R" worktree add -q "$W/issue-70-build" issue-70-similar      # 'issue-7' là tiền tố của nó
echo wip > "$W/issue-8-qa/a"   # Tester của thẻ #8 đang sửa dở

# Merge gate do chính Reviewer của thẻ #7 chạy, từ worktree của nó, với repo.path "." (config của mọi board):
# vẫn phải tìm ra main checkout, và thư mục của Reviewer phải còn sau merge để nó làm nốt
# (kiểm merge, đóng issue, chuyển thẻ sang Done — run.md).
( cd "$W/issue-7-review" && bash "$CLEAN" . issue-7-fix-thing "$MERGED" >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || fail "exit $rc"
for w in issue-7-build issue-7-qa; do
  [ ! -d "$W/$w" ] && ok "merged card's $w removed (repo.path '.' from the review worktree)" || fail "merged card's $w kept"
done
[ -d "$W/issue-7-review" ] && ok "the calling Reviewer's own issue-7-review kept" \
  || fail "the calling Reviewer's own issue-7-review REMOVED under it (its post-merge steps lose their cwd)"
[ -d "$W/issue-7-spike" ] && ok "card 7 worktree on another commit kept" || fail "card 7 worktree not on the merged branch removed"
for w in issue-8-build issue-8-qa issue-8-review issue-70-build; do
  [ -d "$W/$w" ] && ok "other card's $w kept" || fail "other card's $w REMOVED (another worker's folder)"
done
[ "$(cat "$W/issue-8-qa/a" 2>/dev/null)" = wip ] && ok "other card's uncommitted edit intact" || fail "other card's uncommitted edit lost"
git -C "$R" rev-parse --verify -q refs/heads/issue-7-fix-thing >/dev/null && fail "merged branch kept" || ok "merged branch deleted"
for b in issue-8-other issue-70-similar; do
  git -C "$R" rev-parse --verify -q "refs/heads/$b" >/dev/null && ok "other card's branch $b kept" || fail "other card's branch $b deleted"
done

# Thẻ 9: Builder để lại sửa đổi chưa commit, và commit thêm một lần sau head đã merge.
git -C "$R" branch issue-9-late
MERGED9="$(git -C "$R" rev-parse issue-9-late)"
git -C "$R" worktree add -q "$W/issue-9-build" issue-9-late
git -C "$R" worktree add -q --detach "$W/issue-9-qa" main
echo late > "$W/issue-9-build/b"; git -C "$W/issue-9-build" add b; git -C "$W/issue-9-build" commit -qm late
echo dirty > "$W/issue-9-qa/a"
bash "$CLEAN" "$R" issue-9-late "$MERGED9" >/dev/null 2>&1
[ -d "$W/issue-9-qa" ] && [ "$(cat "$W/issue-9-qa/a")" = dirty ] && ok "worktree with uncommitted edits kept" \
  || fail "worktree with uncommitted edits removed (edit lost)"
git -C "$R" rev-parse --verify -q refs/heads/issue-9-late >/dev/null && ok "branch with commits after the merged head kept" \
  || fail "branch with commits after the merged head deleted (commit lost)"
[ ! -d "$W/issue-9-build" ] && ok "clean Builder worktree removed while its ahead branch is kept" \
  || fail "clean Builder worktree of card 9 kept"

# Thẻ 12: Tester commit trên HEAD detached (repro chưa push), worktree sạch; Builder còn sửa dở trên nhánh đã merge.
git -C "$R" branch issue-12-y
MERGED12="$(git -C "$R" rev-parse issue-12-y)"
git -C "$R" worktree add -q "$W/issue-12-build" issue-12-y
git -C "$R" worktree add -q --detach "$W/issue-12-qa" main
echo repro > "$W/issue-12-qa/t"; git -C "$W/issue-12-qa" add t; git -C "$W/issue-12-qa" commit -qm repro
echo wip > "$W/issue-12-build/a"
bash "$CLEAN" "$R" issue-12-y "$MERGED12" >/dev/null 2>&1
[ -d "$W/issue-12-qa" ] && ok "qa worktree with a commit outside the merge kept" || fail "qa worktree with an unpushed detached commit removed (commit only in reflog)"
[ -d "$W/issue-12-build" ] && ok "dirty Builder worktree on the merged branch kept" || fail "dirty Builder worktree on the merged branch removed"
git -C "$R" rev-parse --verify -q refs/heads/issue-12-y >/dev/null && ok "branch still checked out by a kept worktree stays" || fail "branch of a kept worktree deleted"

# Không có SHA đã merge (đối số 3 trống): không biết nhánh có gì ngoài merge, nên giữ nhánh.
git -C "$R" branch issue-13-z
bash "$CLEAN" "$R" issue-13-z >/dev/null 2>&1
git -C "$R" rev-parse --verify -q refs/heads/issue-13-z >/dev/null && ok "no merged SHA given: branch kept" || fail "no merged SHA given: branch deleted"

# Chạy từ trong worktree qa của thẻ vừa merge: thư mục đó là cwd của lệnh gọi nên được giữ.
git -C "$R" branch issue-11-x
MERGED11="$(git -C "$R" rev-parse issue-11-x)"
git -C "$R" worktree add -q --detach "$W/issue-11-qa" main
( cd "$W/issue-11-qa" && bash "$CLEAN" "$R" issue-11-x "$MERGED11" >/dev/null 2>&1 )
[ -d "$W/issue-11-qa" ] && ok "worktree holding the caller's cwd kept" || fail "worktree holding the caller's cwd removed"

# Head ref không phải của thẻ nào (không dạng issue-<N>-…) thì không đụng gì.
bash "$CLEAN" "$R" feature-x "$MERGED" >/dev/null 2>&1
[ -d "$W/issue-8-qa" ] && ok "non-card head ref: nothing removed" || fail "non-card head ref removed a worktree"

[ "$FAILS" -eq 0 ] && echo "✅ test_post_merge_clean: all passed" || { echo "❌ test_post_merge_clean: $FAILS failed"; exit 1; }
