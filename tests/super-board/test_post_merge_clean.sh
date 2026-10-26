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
mkdir -p "$W/issue-9-build/.agents/local"; echo "lane note 9" > "$W/issue-9-build/.agents/local/note.md"   # KEEP_RE: tidy would salvage it
bash "$CLEAN" "$R" issue-9-late "$MERGED9" >/dev/null 2>"$TMP/k9late.err"
[ -d "$W/issue-9-qa" ] && [ "$(cat "$W/issue-9-qa/a")" = dirty ] && ok "worktree with uncommitted edits kept" \
  || fail "worktree with uncommitted edits removed (edit lost)"
git -C "$R" rev-parse --verify -q refs/heads/issue-9-late >/dev/null && ok "branch with commits after the merged head kept" \
  || fail "branch with commits after the merged head deleted (commit lost)"
# U2 (audit 25/10): một worktree mang commit trunk chưa có (commit sau head đã merge: việc tiếp sau merge) không bao giờ bị bộ dọn
# gỡ, kể cả khi nhánh còn giữ commit đó (sweep đã giữ đúng ca này: "not the head of a merged PR"). Trước đây post mode gỡ nó.
[ -d "$W/issue-9-build" ] && ok "Builder worktree with a commit after the merged head kept (work the trunk lacks)" \
  || fail "Builder worktree with a commit after the merged head REMOVED (work the trunk lacks)"
# F5 (review U2, 26/10): integration is decided read-only (kit `held --merged=<sha>`) BEFORE tidy moves a file: a worktree the kit then
# keeps as "not integrated" was salvaged / reverted first and put back by untidy. Nothing is moved, no salvage record is written.
! grep -q "salvaged .*/issue-9-build" "$TMP/k9late.err" && [ -z "$(ls "$R/.git/super-board/salvage" 2>/dev/null | grep '^issue-9-build')" ] \
  && grep -q "kept .*/issue-9-build: \(not integrated\|chưa tích hợp\)" "$TMP/k9late.err" && [ "$(cat "$W/issue-9-build/.agents/local/note.md" 2>/dev/null)" = "lane note 9" ] \
  && ok "F5 a worktree that is not integrated is kept before tidy touches a file (no salvage, note untouched, reason given)" \
  || { fail "F5 tidy moved files of a worktree the kit then kept as not integrated"; cat "$TMP/k9late.err"; }

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
# k2b (review U2 P3, 26/10): như k2, nhưng worktree do hook WorktreeCreate dựng (`add --session`: state ghi phiên chủ, bản ghi
#     session_worktree mang pid của phiên). `held` nay hỏi cả _live_holder; phiên chủ là CHÍNH phiên gọi (pid tổ tiên) thì không phải
#     "đang giữ" — như khoá devkit-kept của chính nó. Phiên chủ KHÁC còn sống: vẫn giữ.
mkdir -p "$R/.claude/audit-gate/session_worktree"
git -C "$R" branch feat-own2; MERGEDF2="$(git -C "$R" rev-parse feat-own2)"
git -C "$R" worktree add -q "$W/feat-own2" feat-own2
git -C "$R" worktree lock --reason "devkit-kept session=sess-me pid=$$" "$W/feat-own2"
printf '{"session":"sess-me","branch":"feat-own2","baseline":{},"fp":2}\n' > "$(git -C "$W/feat-own2" rev-parse --absolute-git-dir)/devkit-worktree.json"
printf '%s\npid %s\n' "$W/feat-own2" "$$" > "$R/.claude/audit-gate/session_worktree/sess-me"
bash "$CLEAN" "$R" feat-own2 "$MERGEDF2" >/dev/null 2>"$TMP/k2b.err"
[ ! -d "$W/feat-own2" ] && ok "k2b the caller's own session (its state owner) does not hold its merged worktree: removed" \
  || { fail "k2b the caller's own hook-made worktree is kept as held by its own session"; cat "$TMP/k2b.err"; }
sleep 300 & SL2=$!; disown "$SL2" 2>/dev/null
git -C "$R" branch feat-other2; MERGEDO2="$(git -C "$R" rev-parse feat-other2)"
git -C "$R" worktree add -q "$W/feat-other2" feat-other2
printf '{"session":"sess-other","branch":"feat-other2","baseline":{},"fp":2}\n' > "$(git -C "$W/feat-other2" rev-parse --absolute-git-dir)/devkit-worktree.json"
printf '%s\npid %s\n' "$W/feat-other2" "$SL2" > "$R/.claude/audit-gate/session_worktree/sess-other"
bash "$CLEAN" "$R" feat-other2 "$MERGEDO2" >/dev/null 2>"$TMP/k2c.err"
[ -d "$W/feat-other2" ] && grep -q "sess-other" "$TMP/k2c.err" && ok "k2b … a worktree another live session owns is kept, naming it" \
  || { fail "k2b a worktree another live session owns was removed"; cat "$TMP/k2c.err"; }
kill "$SL2" 2>/dev/null
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
# k5. không có python3 (hay kit không chạy được): không còn đường git trần (U2, audit 25/10). `git worktree remove` trần xoá im lặng
#     file bị ignore chỉ worktree có (bí mật), commit chỉ reflog giữ… — chỉ kit chứng minh được là không mất gì; không có kit thì giữ
#     mọi worktree và nói lý do. PATH chỉ còn các lệnh script cần, trừ python3.
NOPY="$TMP/nopy"; mkdir -p "$NOPY"
for b in git sed dirname cut tail head grep bash sh env; do p=$(command -v "$b") && ln -s "$p" "$NOPY/$b"; done
git -C "$R" branch issue-16-np
MERGED16="$(git -C "$R" rev-parse issue-16-np)"
git -C "$R" worktree add -q "$W/issue-16-build" issue-16-np
git -C "$R" worktree add -q --detach "$W/issue-16-qa" main
git -C "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$W/issue-16-qa"
echo "k5.secret" >> "$R/.git/info/exclude"; echo "TOKEN=only-here" > "$W/issue-16-build/k5.secret"   # bí mật bị ignore chỉ nó có
PATH="$NOPY" bash "$CLEAN" "$R" issue-16-np "$MERGED16" >/dev/null 2>"$TMP/k5.err"
[ -f "$W/issue-16-build/k5.secret" ] && [ -d "$W/issue-16-qa" ] && grep -q "issue-16-build: no DevKit" "$TMP/k5.err" \
  && ok "k5 without python3 nothing is removed (no DevKit to prove it safe), saying why: the ignored secret stays" \
  || { fail "k5 without python3 a worktree was removed by plain git (its ignored secret is gone)"; cat "$TMP/k5.err"; }
# k6. DevKit của repo có mặt nhưng không chạy được (cú pháp hỏng / python quá cũ): như không có kit — giữ, nói lý do (U2 25/10)
#     Chạy BẢN CHÉP của script ở thư mục tạm: không còn kit nào cạnh nó, chỉ còn kit hỏng của repo (OCR: không thì kit của repo này đỡ thay)
mkdir -p "$R/.agents/devkit/scripts/git" && printf 'def broken(:\n' > "$R/.agents/devkit/scripts/git/worktree.py"
mkdir -p "$TMP/sb/.claude/bin" && cp "$CLEAN" "$TMP/sb/.claude/bin/clean.sh"
git -C "$R" branch issue-17-bk
MERGED17="$(git -C "$R" rev-parse issue-17-bk)"
git -C "$R" worktree add -q "$W/issue-17-build" issue-17-bk
git -C "$R" worktree add -q --detach "$W/issue-17-qa" main
git -C "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$W/issue-17-qa"
bash "$TMP/sb/.claude/bin/clean.sh" "$R" issue-17-bk "$MERGED17" >/dev/null 2>"$TMP/k6.err"
[ -d "$W/issue-17-build" ] && [ -d "$W/issue-17-qa" ] && grep -q "issue-17-build: no DevKit" "$TMP/k6.err" \
  && ok "k6 a DevKit that cannot start removes nothing (no plain-git fallback), saying why" \
  || { fail "k6 broken DevKit: plain git removed a worktree"; cat "$TMP/k6.err"; }
# k9. kit chạy được `list` nhưng chết (traceback, exit 1 không có dòng ✖): không nói được là an toàn = giữ (U2 25/10; trước đây rơi về
#     `git worktree remove` trần, xoá luôn bí mật bị ignore chỉ worktree có — k9b)
printf 'import sys\nif sys.argv[1:2] != ["list"]:\n    raise RuntimeError("boom")\n' > "$R/.agents/devkit/scripts/git/worktree.py"
git -C "$R" branch issue-19-cr
MERGED19="$(git -C "$R" rev-parse issue-19-cr)"
git -C "$R" worktree add -q "$W/issue-19-build" issue-19-cr
echo "k9.secret" >> "$R/.git/info/exclude"; echo "TOKEN=only-here" > "$W/issue-19-build/k9.secret"
bash "$TMP/sb/.claude/bin/clean.sh" "$R" issue-19-cr "$MERGED19" >/dev/null 2>"$TMP/k9.err"
[ -d "$W/issue-19-build" ] && grep -q "issue-19-build" "$TMP/k9.err" && ok "k9 a kit that crashes keeps the worktree, saying why (no plain-git fallback)" \
  || { fail "k9 a crashing kit fell back to plain git"; cat "$TMP/k9.err"; }
[ -f "$W/issue-19-build/k9.secret" ] && ok "k9b … so the ignored secret only that worktree holds is not lost" || fail "k9b the ignored secret is gone"
# k11. (OCR 18/10) kit từ chối bằng exit 2 kèm dòng ✖ (die(): git lỗi khi dò bí mật, state không đọc được…): vẫn là từ chối, giữ
printf 'import sys\nif sys.argv[1:2] != ["list"]:\n    print("\\u2716 worktree: cannot list ignored files", file=sys.stderr); sys.exit(2)\n' > "$R/.agents/devkit/scripts/git/worktree.py"
git -C "$R" branch issue-21-r2
MERGED21="$(git -C "$R" rev-parse issue-21-r2)"
git -C "$R" worktree add -q "$W/issue-21-build" issue-21-r2
bash "$TMP/sb/.claude/bin/clean.sh" "$R" issue-21-r2 "$MERGED21" >/dev/null 2>"$TMP/k11.err"
[ -d "$W/issue-21-build" ] && grep -q "issue-21-build: .*✖ worktree: cannot list" "$TMP/k11.err" \
  && ok "k11 a kit refusal with exit 2 and a ✖ line keeps the worktree, no git fallback" \
  || { fail "k11 kit exit-2 refusal fell through to git"; cat "$TMP/k11.err"; }
rm -rf "$R/.agents"
# k10. (OCR 18/10) hợp đồng chính: kit TỪ CHỐI có lý do (exit 1 kèm ✖) thì giữ worktree, KHÔNG rơi về `git worktree remove` — git trần
#      xoá im lặng file bị ignore chỉ worktree có (khoá, .env). Worktree sạch theo `git status`, chỉ giữ một .env bị ignore mà main không có.
echo ".env" >> "$R/.git/info/exclude"
git -C "$R" branch issue-20-sec
MERGED20="$(git -C "$R" rev-parse issue-20-sec)"
git -C "$R" worktree add -q "$W/issue-20-build" issue-20-sec
echo "TOKEN=only-here" > "$W/issue-20-build/.env"
bash "$CLEAN" "$R" issue-20-sec "$MERGED20" >/dev/null 2>"$TMP/k10.err"
[ -f "$W/issue-20-build/.env" ] && grep -q "issue-20-build: agent-kit worktree remove refused" "$TMP/k10.err" \
  && ok "k10 a kit refusal (an ignored secret only the worktree holds) keeps the worktree, no git fallback" \
  || { fail "k10 kit refusal fell through to git: the ignored secret is gone"; cat "$TMP/k10.err"; }
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

# k12. (U2 25/10) nhánh vừa merge mà reflog còn nêu một commit riêng (commit rồi reset về head đã merge): `git branch -D` trần xoá
#      reflog và commit đó mất ở lần git gc. Kit (prune-branch) xoá nhánh nhưng cất commit đó vào refs/devkit/discarded trước.
git -C "$R" switch -q -c issue-22-r
echo z > "$R/z22"; git -C "$R" add z22; git -C "$R" commit -qm z22; Z22=$(git -C "$R" rev-parse HEAD)
git -C "$R" reset -q --hard main; git -C "$R" switch -q main
MERGED22="$(git -C "$R" rev-parse issue-22-r)"
bash "$CLEAN" "$R" issue-22-r "$MERGED22" >/dev/null 2>"$TMP/k12.err"
! git -C "$R" rev-parse --verify -q refs/heads/issue-22-r >/dev/null && [ -n "$(git -C "$R" for-each-ref --contains "$Z22" 2>/dev/null)" ] \
  && ok "k12 the merged branch is deleted, the commit only its reflog named is kept on a ref" \
  || { fail "k12 merged branch kept, or deleted with its reflog-only commit lost"; cat "$TMP/k12.err"; }
# k13. (U2 25/10) worktree issue-<N>-qa của thẻ vừa merge nhưng ở NHÁNH KHÁC mang việc trunk chưa có (PR thứ hai của thẻ, còn mở):
#      không phải phần đã merge — giữ.
git -C "$R" branch issue-23-a
MERGED23="$(git -C "$R" rev-parse issue-23-a)"
git -C "$R" worktree add -q -b issue-23-next "$W/issue-23-qa" main
echo next > "$W/issue-23-qa/n23"; git -C "$W/issue-23-qa" add n23; git -C "$W/issue-23-qa" commit -qm next
bash "$CLEAN" "$R" issue-23-a "$MERGED23" >/dev/null 2>"$TMP/k13.err"
[ -d "$W/issue-23-qa" ] && ok "k13 a card worktree on another branch with work the trunk lacks (its open PR) is kept" \
  || { fail "k13 card worktree on another branch with unmerged work REMOVED"; cat "$TMP/k13.err"; }

# k14 (#427, lane C): bản cất của tidy là `git diff --cached --binary`, mà diff porcelain chạy diff.<drv>.textconv và diff ngoài
#      (diff.<drv>.command) theo attribute của repo. Textconv lossy (asset → text, ở đây mọi bản đọc ra "same") bỏ hẳn sửa nhị phân
#      khỏi patch, diff ngoài in ra thứ không phải patch: bước kiểm t1 == t2 hỏng và worktree chỉ còn sửa loại CẤT bị giữ mãi
#      ("salvage could not be verified"). Nay patch tạo với --no-textconv --no-ext-diff: cất đúng byte (áp lên head đã merge dựng lại
#      đúng file), rồi mới gỡ. Pattern attribute riêng tên file của ca này: các ca trên không thấy hai driver.
printf '\000\001base' > "$R/tc.asset"; git -C "$R" add tc.asset; git -C "$R" commit -qm tc
printf 'tc.asset diff=lossy\ntc.note diff=ext\n' >> "$R/.git/info/attributes"
git -C "$R" config diff.lossy.textconv "sh -c 'echo same'"
git -C "$R" config diff.ext.command "sh -c 'echo not-a-patch'"
git -C "$R" branch issue-24-tc
MERGED24="$(git -C "$R" rev-parse issue-24-tc)"
git -C "$R" worktree add -q "$W/issue-24-build" issue-24-tc
printf '\000\001EDIT' > "$W/issue-24-build/tc.asset"                                    # sửa nhị phân trên file đã track (loại CẤT: *.asset)
mkdir -p "$W/issue-24-build/.agents/local"; printf 'note only here\n' > "$W/issue-24-build/.agents/local/tc.note"   # file mới (loại CẤT)
mkdir -p "$TMP/k14-orig"; cp "$W/issue-24-build/tc.asset" "$W/issue-24-build/.agents/local/tc.note" "$TMP/k14-orig/"
bash "$CLEAN" "$R" issue-24-tc "$MERGED24" >/dev/null 2>"$TMP/k14.err"
P14="$(ls "$R"/.git/super-board/salvage/issue-24-build-*.patch 2>/dev/null | head -1)"
git -C "$R" worktree add -q --detach "$TMP/k14-check" "$MERGED24"
[ ! -d "$W/issue-24-build" ] && grep -q "salvaged .*/issue-24-build" "$TMP/k14.err" && [ -n "$P14" ] && grep -q "GIT binary patch" "$P14" \
  && git -C "$TMP/k14-check" apply --binary "$P14" 2>/dev/null && cmp -s "$TMP/k14-check/tc.asset" "$TMP/k14-orig/tc.asset" \
  && cmp -s "$TMP/k14-check/.agents/local/tc.note" "$TMP/k14-orig/tc.note" \
  && ok "k14 a lossy textconv / external diff driver does not spoil the salvage: the patch rebuilds the exact bytes, then the worktree goes" \
  || { fail "k14 salvage under a textconv / external diff driver: worktree $([ -d "$W/issue-24-build" ] && echo kept || echo removed), patch ${P14:-<none>}"; cat "$TMP/k14.err"; }

# k15 (#427, lane C): TOCTOU của bộ dọn. Board hỏi `held` (chỉ đọc), rồi tidy cất / trả file về HEAD, rồi `remove --merged`; giữa chừng
#      một phiên có thể nhận worktree. python3 giả (chỉ cho lần chạy này) ghi khoá checkout của một phiên sống ĐÚNG lúc board gọi
#      `remove`: kit phải hỏi lại người giữ ngay trước khi gỡ — giữ worktree, nói tên phiên, untidy trả lại sửa của lane.
git -C "$R" branch issue-25-tt
MERGED25="$(git -C "$R" rev-parse issue-25-tt)"
git -C "$R" worktree add -q "$W/issue-25-build" issue-25-tt
mkdir -p "$W/issue-25-build/.agents/local"; echo "lane note 25" > "$W/issue-25-build/.agents/local/note.md"   # tidy cất nó trước khi gỡ
sleep 300 & SL=$!; disown "$SL" 2>/dev/null   # (trap EXIT giết $SL)
REALPY="$(command -v python3)"; mkdir -p "$TMP/k15bin"
cat > "$TMP/k15bin/python3" <<SH
#!/usr/bin/env bash
if [ "\${2:-}" = remove ]; then   # python3 <worktree.py> remove --merged=<sha> <wt>: một phiên vừa nhận worktree
  for a in "\$@"; do wt="\$a"; done
  gd="\$(git -C "\$wt" rev-parse --absolute-git-dir)" && printf '{"session_id":"late-holder","pid":%s,"gitdir":"%s"}\n' "$SL" "\$gd" > "\$gd/devkit-session.lock"
fi
exec "$REALPY" "\$@"
SH
chmod +x "$TMP/k15bin/python3"
PATH="$TMP/k15bin:$PATH" bash "$CLEAN" "$R" issue-25-tt "$MERGED25" >/dev/null 2>"$TMP/k15.err"
[ -d "$W/issue-25-build" ] && grep -q "salvaged .*/issue-25-build" "$TMP/k15.err" \
  && grep -q "kept .*/issue-25-build: agent-kit worktree remove refused: ✖ .*late-holder" "$TMP/k15.err" \
  && [ "$(cat "$W/issue-25-build/.agents/local/note.md" 2>/dev/null)" = "lane note 25" ] \
  && ok "k15 a session that takes the worktree after held / tidy is seen by remove --merged right before the removal: kept, lane edit put back" \
  || { fail "k15 TOCTOU: worktree $([ -d "$W/issue-25-build" ] && echo kept || echo REMOVED) under a session that took it after the decision"; cat "$TMP/k15.err"; }
kill "$SL" 2>/dev/null

[ "$FAILS" -eq 0 ] && echo "✅ test_post_merge_clean: all passed" || { echo "❌ test_post_merge_clean: $FAILS failed"; exit 1; }
