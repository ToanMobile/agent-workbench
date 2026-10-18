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
SL=""
trap '[ -n "$SL" ] && kill "$SL" 2>/dev/null; rm -rf "$TMP"' EXIT
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

# 18/10 (NFH PR #38, #45, Geely PR #59): phiên rời worktree của PR bằng ExitWorktree "keep" (khoá devkit-kept với pid của phiên) rồi tự
# chạy merge gate. `git worktree remove` trần từ chối worktree bị khoá, nên phiên phải unlock tay. Bước dọn dùng `agent-kit worktree remove`
# (tự mở khoá của chính phiên hoặc của pid đã chết, luật không-mất-việc giữ nguyên).
# k1. thẻ: issue-14-build khoá keep bởi chính tiến trình gọi (pid của shell test là tổ tiên của bước dọn)
git -C "$R" branch issue-14-k
MERGED14="$(git -C "$R" rev-parse issue-14-k)"
git -C "$R" worktree add -q "$W/issue-14-build" issue-14-k
git -C "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$W/issue-14-build"
bash "$CLEAN" "$R" issue-14-k "$MERGED14" >/dev/null 2>&1
[ ! -d "$W/issue-14-build" ] && ok "k1 card worktree locked by the caller's own ExitWorktree keep is removed" \
  || fail "k1 card worktree locked by the caller's own keep kept (the session has to unlock by hand)"
# k2. nhánh PR thường (không dạng issue-<N>-…): worktree của phiên ở đúng nhánh vừa merge, khoá keep của chính phiên
git -C "$R" branch feat-own
MERGEDF="$(git -C "$R" rev-parse feat-own)"
git -C "$R" worktree add -q "$W/feat-own" feat-own
git -C "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$W/feat-own"
bash "$CLEAN" "$R" feat-own "$MERGEDF" >/dev/null 2>&1
[ ! -d "$W/feat-own" ] && ok "k2 the session's own worktree on a merged non-card branch is removed" \
  || fail "k2 the session's own worktree on a merged non-card branch kept"
git -C "$R" rev-parse --verify -q refs/heads/feat-own >/dev/null && fail "k2 merged non-card branch kept" || ok "k2 merged non-card branch deleted"
# k3. khoá keep của một phiên KHÁC còn sống: giữ (không bao giờ gỡ worktree từ dưới chân phiên khác)
sleep 300 & SL=$!; disown "$SL" 2>/dev/null
git -C "$R" branch issue-15-o
MERGED15="$(git -C "$R" rev-parse issue-15-o)"
git -C "$R" worktree add -q "$W/issue-15-build" issue-15-o
git -C "$R" worktree lock --reason "devkit-kept session=other pid=$SL" "$W/issue-15-build"
bash "$CLEAN" "$R" issue-15-o "$MERGED15" >/dev/null 2>&1
[ -d "$W/issue-15-build" ] && ok "k3 worktree another live session keeps is left alone" || fail "k3 worktree another live session keeps REMOVED"
kill "$SL" 2>/dev/null
# k4. (OCR 18/10) worktree người dùng tự dựng NGOÀI .claude/worktrees ở đúng nhánh PR thường vừa merge: không phải của phiên, giữ
git -C "$R" branch feat-hand
MERGEDH="$(git -C "$R" rev-parse feat-hand)"
git -C "$R" worktree add -q "$TMP/repo-feat-hand" feat-hand
bash "$CLEAN" "$R" feat-hand "$MERGEDH" >/dev/null 2>&1
[ -d "$TMP/repo-feat-hand" ] && ok "k4 a hand-made worktree outside .claude/worktrees on the merged branch is left alone" \
  || fail "k4 a hand-made worktree outside .claude/worktrees REMOVED"
# k5. (OCR 18/10) không có python3 (hay kit không chạy được): đường git như cũ — worktree sạch không khoá vẫn được gỡ, worktree khoá giữ
#     và nói rõ lý do. PATH chỉ còn các lệnh script cần, trừ python3.
NOPY="$TMP/nopy"; mkdir -p "$NOPY"
for b in git sed dirname cut tail head grep bash sh env; do p=$(command -v "$b") && ln -s "$p" "$NOPY/$b"; done
git -C "$R" branch issue-16-np
MERGED16="$(git -C "$R" rev-parse issue-16-np)"
git -C "$R" worktree add -q "$W/issue-16-build" issue-16-np
git -C "$R" worktree add -q --detach "$W/issue-16-qa" main
git -C "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$W/issue-16-qa"
PATH="$NOPY" bash "$CLEAN" "$R" issue-16-np "$MERGED16" >/dev/null 2>"$TMP/k5.err"
[ ! -d "$W/issue-16-build" ] && [ -d "$W/issue-16-qa" ] && grep -q "/issue-16-qa: git worktree remove failed" "$TMP/k5.err" \
  && ok "k5 without python3: plain git removes the unlocked worktree and keeps the locked one, saying why" \
  || { fail "k5 no-python3 fallback"; cat "$TMP/k5.err"; }
# k6. (OCR 18/10) DevKit của repo có mặt nhưng không chạy được (cú pháp hỏng / python quá cũ): đường git như cũ, worktree sạch vẫn gỡ
#     Chạy BẢN CHÉP của script ở thư mục tạm: không còn kit nào cạnh nó, chỉ còn kit hỏng của repo (OCR: không thì kit của repo này đỡ thay)
mkdir -p "$R/.agents/devkit/scripts/git" && printf 'def broken(:\n' > "$R/.agents/devkit/scripts/git/worktree.py"
mkdir -p "$TMP/sb/.claude/bin" && cp "$CLEAN" "$TMP/sb/.claude/bin/clean.sh"
git -C "$R" branch issue-17-bk
MERGED17="$(git -C "$R" rev-parse issue-17-bk)"
git -C "$R" worktree add -q "$W/issue-17-build" issue-17-bk
git -C "$R" worktree add -q --detach "$W/issue-17-qa" main
git -C "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$W/issue-17-qa"
bash "$TMP/sb/.claude/bin/clean.sh" "$R" issue-17-bk "$MERGED17" >/dev/null 2>"$TMP/k6.err"
[ ! -d "$W/issue-17-build" ] && [ -d "$W/issue-17-qa" ] && grep -q "/issue-17-qa: git worktree remove failed" "$TMP/k6.err" \
  && ok "k6 a DevKit that cannot start falls back to plain git: the clean worktree is removed, the locked one kept" \
  || { fail "k6 broken DevKit fallback"; cat "$TMP/k6.err"; }
# k9. (OCR 18/10) kit chạy được `list` nhưng chết giữa `remove` (traceback, exit 1 không có dòng ✖): không phải lời từ chối có lý do —
#     đường git như cũ, worktree sạch vẫn gỡ
printf 'import sys\nif sys.argv[1:2] != ["list"]:\n    raise RuntimeError("boom")\n' > "$R/.agents/devkit/scripts/git/worktree.py"
git -C "$R" branch issue-19-cr
MERGED19="$(git -C "$R" rev-parse issue-19-cr)"
git -C "$R" worktree add -q "$W/issue-19-build" issue-19-cr
bash "$TMP/sb/.claude/bin/clean.sh" "$R" issue-19-cr "$MERGED19" >/dev/null 2>"$TMP/k9.err"
[ ! -d "$W/issue-19-build" ] && ok "k9 a kit that crashes in remove falls back to plain git" || { fail "k9 kit crash kept a clean worktree"; cat "$TMP/k9.err"; }
rm -rf "$R/.agents"
# k7. (OCR 18/10) nhánh PR thường không có worktree nào của phiên: nhánh local cùng tên ở đúng commit đã merge là của người dùng — giữ
git -C "$R" branch feat-userown
MERGEDU="$(git -C "$R" rev-parse feat-userown)"
bash "$CLEAN" "$R" feat-userown "$MERGEDU" >/dev/null 2>&1
git -C "$R" rev-parse --verify -q refs/heads/feat-userown >/dev/null && ok "k7 a non-card branch with no session worktree is not deleted" \
  || fail "k7 a non-card branch with no session worktree deleted"
# k8. khoá devkit-kept của một pid đã chết: mở khoá và gỡ
sleep 0 & DEAD=$!; wait "$DEAD" 2>/dev/null
git -C "$R" branch issue-18-d
MERGED18="$(git -C "$R" rev-parse issue-18-d)"
git -C "$R" worktree add -q "$W/issue-18-build" issue-18-d
git -C "$R" worktree lock --reason "devkit-kept session=gone pid=$DEAD" "$W/issue-18-build"
bash "$CLEAN" "$R" issue-18-d "$MERGED18" >/dev/null 2>&1
[ ! -d "$W/issue-18-build" ] && ok "k8 a worktree kept by a dead session's lock is removed" || fail "k8 dead session's kept worktree kept"

[ "$FAILS" -eq 0 ] && echo "✅ test_post_merge_clean: all passed" || { echo "❌ test_post_merge_clean: $FAILS failed"; exit 1; }
