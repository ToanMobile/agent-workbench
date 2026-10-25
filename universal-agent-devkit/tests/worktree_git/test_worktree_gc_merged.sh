#!/usr/bin/env bash
# `agent-kit worktree gc --merged` (audit 25/10 U2): ba bộ dọn worktree đã gộp (worktree.py gc, .claude/hooks/cleanup-wt.py chưa track,
# super-board-post-merge-clean.sh) gộp về MỘT nơi quyết định: worktree.py. cleanup-wt --auto ở SessionStart gỡ worktree đã ĐĂNG KÝ mà
# git coi là "merged" chỉ bằng merged_state (tổ tiên / cherry / squash probe) + `git worktree remove` + `git branch -D`: không xét
# commit chỉ reflog giữ, file bí mật bị ignore, submodule, phiên còn sống không khoá git (25/10 nó gỡ worktree dropped-card-sweep giữa
# lúc gate --full chạy trong đó). `gc --merged` thay nó: chỉ worktree dưới <main>/.claude/worktrees/ (không phải của super-board), chỉ
# khi nội dung HEAD đã trong trunk, không phiên / khoá nào giữ, không mới tạo (< WORKTREE_GC_FRESH_S, chưa commit gì sau khi tạo),
# nhánh không có PR mở, và removal_blockers() (luật của `worktree remove`) trống. Nhánh local không worktree: xoá khi trunk đã có nội
# dung và không còn ref remote (commit chỉ reflog nhánh giữ được cất ở refs/devkit/discarded). Kèm `held <path>` (câu hỏi chỉ-đọc
# board dùng trước khi đụng worktree) và `remove --merged[=<sha>]` (gỡ chỉ khi đã tích hợp: trunk có nội dung, hoặc HEAD là / là tổ
# tiên của head PR vừa gộp).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
SL=""
trap '[ -n "$SL" ] && kill "$SL" 2>/dev/null; chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
has_branch() { G "$R" show-ref --verify --quiet "refs/heads/$1"; }
export WORKTREE_GC_MIN_AGE_S=0

O="$TMP/origin.git"; git init -q --bare -b main "$O"
R="$TMP/repo"; mkdir -p "$R" && G "$R" init -q -b main .
printf '.env\n' > "$R/.gitignore"; echo base > "$R/a.txt"; G "$R" add -A && G "$R" commit -qm init
G "$R" remote add origin "$O" && G "$R" push -q -u origin main 2>/dev/null
H="$R/.claude/worktrees"; mkdir -p "$H"
add_det() { G "$R" worktree add -q --detach "$H/$1" main; }
add_br() { G "$R" worktree add -q -b "$2" "$H/$1" main; }

# gh giả: `pr list --state open` đọc $FAKE_DIR/open.json; FAKE_GH_DOWN=1: gh hỏng. Lệnh khác: lỗi.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/gh.calls"
[ -z "${FAKE_GH_DOWN:-}" ] || exit 1
case " $* " in
  *" pr list "*"--state open"*) cat "$FAKE_DIR/open.json" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
echo '[{"number":5,"headRefName":"feat-open","baseRefName":"main"},{"number":6,"headRefName":"stack-top","baseRefName":"feat-base"}]' > "$TMP/open.json"

# --- phải bị GỠ (đã tích hợp, sạch, không ai giữ) ---
add_br done-branch done-1                       # m1 nhánh ở đúng main, chưa publish
add_det done-detached                           # m2 detached ở main
add_br done-squash sq-1                         # m2b gộp kiểu squash: commit của nhánh không là tổ tiên, main có đúng nội dung
echo sq > "$H/done-squash/sq.txt"; G "$H/done-squash" add sq.txt && G "$H/done-squash" commit -qm sq
SQ_C=$(G "$H/done-squash" rev-parse HEAD)
echo sq > "$R/sq.txt"; G "$R" add sq.txt && G "$R" commit -qm "sq (squash)"
add_br pr-merged feat-closed                    # m7c đã publish, PR không còn mở: gỡ worktree, nhánh giữ (remote còn ref)
G "$R" push -q origin feat-closed 2>/dev/null
add_det here                                    # m10 lệnh chạy từ đây: giữ
# --- phải được GIỮ ---
add_br ahead ahead-1                            # m3 commit main chưa có (nhánh giữ commit: remove thường vẫn gỡ được, gc --merged thì không)
echo ahead > "$H/ahead/ahead.txt"; G "$H/ahead" add ahead.txt && G "$H/ahead" commit -qm ahead
add_det dirty; echo "only here" > "$H/dirty/new.txt"            # m4 chỉ có file chưa commit
add_det reflog                                  # m5 commit chỉ reflog của worktree giữ
echo lost > "$H/reflog/lost.txt"; G "$H/reflog" add lost.txt && G "$H/reflog" commit -qm lost
LOST=$(G "$H/reflog" rev-parse HEAD); G "$H/reflog" checkout -q --detach main
sleep 300 & SL=$!; disown "$SL" 2>/dev/null
add_det held-session                            # m6 khoá checkout (devkit-session.lock) của một phiên còn sống
GD6=$(G "$H/held-session" rev-parse --absolute-git-dir)
printf '{"session_id":"live","pid":%s,"gitdir":"%s"}\n' "$SL" "$GD6" > "$GD6/devkit-session.lock"
add_det held-kept; G "$R" worktree lock --reason "devkit-kept session=other pid=$SL" "$H/held-kept"   # m6b keep của phiên khác còn sống
add_det held-user; G "$R" worktree lock --reason "user is working here" "$H/held-user"               # m6c khoá của người dùng
add_br open-pr feat-open; G "$R" push -q origin feat-open 2>/dev/null     # m7 PR mở (head)
add_br open-base feat-base; G "$R" push -q origin feat-base 2>/dev/null   # m7d nhánh là BASE của một PR mở (PR chồng)
add_det secret; echo "TOKEN=only-here" > "$H/secret/.env"                 # m8 bí mật bị ignore chỉ worktree có
add_br issue-5-build issue-5-x                  # m11 worktree của super-board: sweep của board xét, gc thì không
G "$R" worktree add -q -b hand-1 "$TMP/repo-hand" main                    # m12 worktree người tự dựng ngoài .claude/worktrees
# nhánh local không worktree (m13)
G "$R" branch merged-local main                                           # đã trong trunk, chưa publish: xoá
G "$R" branch merged-reflog main                                          # như trên, reflog nhánh còn một commit riêng: xoá, commit được cất
G "$R" switch -q merged-reflog && echo y > "$R/y.txt" && G "$R" add y.txt && G "$R" commit -qm y
REFLOG_Y=$(G "$R" rev-parse HEAD); G "$R" reset -q --hard main; G "$R" switch -q main
G "$R" branch unmerged-local ahead-1                                      # commit main chưa có: giữ
G "$R" branch pushed-merged main; G "$R" push -q origin pushed-merged 2>/dev/null   # đã publish: giữ
G "$R" branch issue-6-y main                                              # nhánh của board: giữ

gone() { [ ! -e "$H/$1" ]; }
kept() { [ -d "$H/$1" ]; }

# A. `gc` thường (không --merged): worktree đã đăng ký không bao giờ là việc của nó (hợp đồng cũ, test_worktree_gc.sh #1)
(cd "$R" && python3 "$WT" gc >/dev/null 2>&1)
kept done-branch && kept done-detached && ok "A plain gc leaves registered worktrees alone" || fail "A plain gc removed a registered worktree"

# B. mới tạo (< WORKTREE_GC_FRESH_S, chưa commit gì sau khi tạo): giữ — worktree của subagent trước commit đầu
(cd "$R" && WORKTREE_GC_FRESH_S=86400 python3 "$WT" gc --merged >"$TMP/b.out" 2>&1)
kept done-branch && kept done-detached && ok "B a worktree made minutes ago with no commit since is kept (fresh)" \
  || { fail "B a fresh worktree was reaped"; cat "$TMP/b.out"; }

# C. --dry-run: không xoá gì, nói sẽ gỡ cái nào
(cd "$R" && WORKTREE_GC_FRESH_S=0 python3 "$WT" gc --merged --dry-run >"$TMP/c.out" 2>&1)
kept done-branch && grep -q "would remove $H/done-branch" "$TMP/c.out" && has_branch done-1 \
  && ok "C --dry-run removes nothing and names what it would remove" || { fail "C dry-run"; cat "$TMP/c.out"; }

# D. lượt thật, chạy từ worktree "here"
(cd "$H/here" && WORKTREE_GC_FRESH_S=0 python3 "$WT" gc --merged --log="$TMP/gc.log" >"$TMP/d.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "D exit 0" || { fail "D exit $rc"; cat "$TMP/d.out"; }
for w in done-branch done-detached done-squash pr-merged; do
  gone "$w" && ok "D integrated, clean, unheld $w is removed" || { fail "D integrated $w kept"; grep -a "$w" "$TMP/d.out"; }
done
grep -q "$H/done-branch" "$TMP/gc.log" 2>/dev/null && ok "D the removal is recorded in the gc log" || fail "D no gc log record: $(cat "$TMP/gc.log" 2>&1)"
! has_branch done-1 && ok "D its merged, unpublished branch goes with it" || fail "D merged branch done-1 kept"
! has_branch sq-1 && [ -n "$(G "$R" for-each-ref --contains "$SQ_C" refs/devkit/discarded)" ] \
  && ok "D the squash-merged branch is deleted, its commit kept in refs/devkit/discarded" || fail "D squash branch: deleted without a fallback copy, or kept"
has_branch feat-closed && ok "D a published branch is kept (the remote holds it)" || fail "D published branch feat-closed deleted"
kept here && ok "D the worktree the command runs in is kept" || fail "D the caller's own worktree removed"
kept ahead && has_branch ahead-1 && ok "D a worktree with a commit not in main is kept" || fail "D worktree with an unmerged commit removed"
kept dirty && [ "$(cat "$H/dirty/new.txt" 2>/dev/null)" = "only here" ] && ok "D a worktree with only uncommitted files is kept" || fail "D uncommitted file lost"
kept reflog && [ "$(G "$R" cat-file -t "$LOST" 2>/dev/null)" = commit ] && ok "D a worktree holding a reflog-only commit is kept" || fail "D reflog-only commit's worktree removed"
kept held-session && ok "D a worktree a live session's checkout lock holds is kept" || fail "D live session's worktree removed"
kept held-kept && ok "D a worktree another live session keeps (devkit-kept) is kept" || fail "D devkit-kept worktree of a live session removed"
kept held-user && ok "D a worktree a person locked is kept" || fail "D user-locked worktree removed"
kept open-pr && has_branch feat-open && ok "D a worktree whose branch has an open PR is kept" || fail "D open-PR worktree or branch removed"
kept open-base && has_branch feat-base && ok "D a worktree whose branch is the base of an open PR is kept" || fail "D stacked-PR base worktree removed"
kept secret && [ -f "$H/secret/.env" ] && ok "D a worktree holding an ignored secret only it has is kept" || fail "D ignored secret lost"
kept issue-5-build && has_branch issue-5-x && ok "D a super-board worktree is left to the board's sweep" || fail "D board worktree reaped"
[ -d "$TMP/repo-hand" ] && has_branch hand-1 && ok "D a hand-made worktree outside .claude/worktrees is left alone" || fail "D hand-made worktree removed"
! has_branch merged-local && ok "D a merged local branch with no worktree and no remote is deleted" || fail "D merged-local kept"
! has_branch merged-reflog && [ -n "$(G "$R" for-each-ref --contains "$REFLOG_Y" refs/devkit/discarded)" ] \
  && ok "D a merged branch whose reflog names its own commit is deleted, that commit kept in refs/devkit/discarded" \
  || fail "D merged-reflog: kept, or deleted without keeping its reflog-only commit"
has_branch unmerged-local && ok "D a local branch with a commit not in main is kept" || fail "D unmerged branch deleted"
has_branch pushed-merged && ok "D a merged branch that is published is kept" || fail "D published merged branch deleted"
has_branch issue-6-y && ok "D a super-board branch is left to the board" || fail "D board branch deleted"
has_branch main && ok "D the trunk is never touched" || fail "D trunk deleted"

# E. gh không đọc được: nhánh có ref remote có thể có PR mở → giữ; khi gh đọc lại được và không còn PR mở → gỡ
add_br gh-down feat-unknown; G "$R" push -q origin feat-unknown 2>/dev/null
(cd "$R" && FAKE_GH_DOWN=1 WORKTREE_GC_FRESH_S=0 python3 "$WT" gc --merged >"$TMP/e.out" 2>&1)
kept gh-down && ok "E gh down: a published branch's worktree is kept (an open PR cannot be ruled out)" || { fail "E gh down: removed"; cat "$TMP/e.out"; }
(cd "$R" && WORKTREE_GC_FRESH_S=0 python3 "$WT" gc --merged >"$TMP/e2.out" 2>&1)
gone gh-down && ok "E gh back, no open PR: removed" || { fail "E gh back: still kept"; grep -a gh-down "$TMP/e2.out"; }

# F. `held <path>`: 3 + lý do khi bị giữ, 0 khi không ai giữ; mã khác (kit hỏng): người gọi coi là bị giữ
(cd "$R" && python3 "$WT" held "$H/held-kept" >"$TMP/f.out" 2>&1); rc=$?
[ "$rc" -eq 3 ] && grep -q "pid $SL" "$TMP/f.out" && ok "F held: a live devkit-kept lock is reported (exit 3)" || { fail "F held kept-lock rc=$rc"; cat "$TMP/f.out"; }
(cd "$R" && python3 "$WT" held "$H/held-session" >"$TMP/f2.out" 2>&1); rc=$?
[ "$rc" -eq 3 ] && ok "F held: a live checkout lock is reported" || { fail "F held checkout lock rc=$rc"; cat "$TMP/f2.out"; }
(cd "$R" && python3 "$WT" held "$H/held-user" >"$TMP/f3.out" 2>&1); rc=$?
[ "$rc" -eq 3 ] && grep -q "user is working here" "$TMP/f3.out" && ok "F held: a person's lock is reported" || { fail "F held user lock rc=$rc"; cat "$TMP/f3.out"; }
(cd "$R" && python3 "$WT" held "$H/dirty" >"$TMP/f4.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$TMP/f4.out" ] && ok "F held: a worktree nobody holds -> exit 0, silent" || { fail "F held free rc=$rc"; cat "$TMP/f4.out"; }
mkdir -p "$H/not-registered"
(cd "$R" && python3 "$WT" held "$H/not-registered" >"$TMP/f5.out" 2>&1); rc=$?
[ "$rc" -eq 3 ] && ok "F held: a folder git does not list is reported held (cannot be judged)" || { fail "F held unregistered rc=$rc"; cat "$TMP/f5.out"; }
G "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$H/dirty"
(cd "$R" && python3 "$WT" held "$H/dirty" >"$TMP/f6.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "F held: the caller's own devkit-kept lock does not hold it" || { fail "F held own lock rc=$rc"; cat "$TMP/f6.out"; }
G "$R" worktree unlock "$H/dirty"

# G. `remove --merged[=<sha>]`: gỡ chỉ khi đã tích hợp
(cd "$R" && python3 "$WT" remove --merged "$H/ahead" >"$TMP/g.out" 2>&1); rc=$?
[ "$rc" -eq 1 ] && kept ahead && grep -q "✖" "$TMP/g.out" && ok "G remove --merged refuses a worktree whose HEAD the trunk lacks (✖, exit 1)" \
  || { fail "G remove --merged on an unmerged worktree rc=$rc"; cat "$TMP/g.out"; }
AH=$(G "$H/ahead" rev-parse HEAD)
add_det part-of-pr; G "$H/part-of-pr" checkout -q --detach "$AH~0"
(cd "$R" && python3 "$WT" remove --merged="$AH" "$H/part-of-pr" >"$TMP/g2.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && gone part-of-pr && ok "G remove --merged=<merged head>: HEAD is that head -> removed" || { fail "G remove --merged=<sha> rc=$rc"; cat "$TMP/g2.out"; }
(cd "$R" && python3 "$WT" remove --merged=nothex "$H/ahead" >"$TMP/g3.out" 2>&1); rc=$?
[ "$rc" -ne 0 ] && kept ahead && ok "G remove --merged=<not a sha> refuses" || { fail "G bad sha rc=$rc"; cat "$TMP/g3.out"; }

kill "$SL" 2>/dev/null
[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_gc_merged: all passed" || { echo "❌ test_worktree_gc_merged: $FAILS failed"; exit 1; }
