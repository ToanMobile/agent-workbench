#!/usr/bin/env bash
# Regression test: worktree_sandbox.py creation, .worktreeinclude CoW copy, and cleanup
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$DEVKIT_DIR/scripts/git/worktree_sandbox.py"
[ -f "$SCRIPT" ] || SCRIPT="$DEVKIT_DIR/scripts/worktree_sandbox.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Test 1: Script help command runs cleanly
python3 "$SCRIPT" --help >/dev/null 2>&1
if [ $? -eq 0 ]; then
  ok "worktree_sandbox.py --help returns exit 0"
else
  fail "worktree_sandbox.py --help failed"
fi

# Test 2: Lifecycle in a mock repo
P="$TMP/mock-repo"
mkdir -p "$P" && cd "$P"
git init -q -b main . && git config user.email t@t && git config user.name t   # -b: các ca checkout tách rời cần nhánh trunk
echo "hello world" > README.md
echo -e ".env\nlocal.properties" > .worktreeinclude
echo "SECRET_KEY=12345" > .env
echo "sdk.dir=/dummy/sdk" > local.properties
git add README.md .worktreeinclude
git commit -q -m "initial commit"

# Create sandbox test_sb
python3 "$SCRIPT" create test_sb --port-offset 20 >/dev/null 2>&1
if [ -d "$P/.sandboxes/test_sb" ]; then
  ok "Sandbox directory created successfully"
else
  fail "Sandbox directory not created"
fi

if [ -f "$P/.sandboxes/test_sb/.env" ] && [ -f "$P/.sandboxes/test_sb/local.properties" ]; then
  ok ".worktreeinclude files copied via CoW"
else
  fail ".worktreeinclude files missing in sandbox"
fi

if [ -f "$P/.sandboxes/test_sb/.sandbox-env.sh" ]; then
  ok ".sandbox-env.sh envelope generated"
else
  fail ".sandbox-env.sh missing"
fi

# List sandboxes
LIST_OUT=$(python3 "$SCRIPT" list)
if echo "$LIST_OUT" | grep -q "test_sb"; then
  ok "Sandbox listed in active sandboxes"
else
  fail "Sandbox not found in list output"
fi

# Cleanup sandbox
python3 "$SCRIPT" cleanup --name test_sb >/dev/null 2>&1
if [ ! -d "$P/.sandboxes/test_sb" ]; then
  ok "Sandbox cleaned up and removed cleanly"
else
  fail "Sandbox directory still exists after cleanup"
fi

# Test 3: merge-winner with automatic cleanup
python3 "$SCRIPT" create winner_sb >/dev/null 2>&1
cd "$P/.sandboxes/winner_sb"
echo "winner feature implemented" > winner.txt
git add winner.txt
git commit -q -m "feat: winner commit"
cd "$P"

# Merge winner into main
MERGE_OUT=$(python3 "$SCRIPT" merge-winner winner_sb)
if [ -f "$P/winner.txt" ]; then
  ok "Winner commit merged into main branch"
else
  fail "Winner feature not found in main branch"
fi

if [ ! -d "$P/.sandboxes/winner_sb" ]; then
  ok "Winner sandbox automatically deleted after merge"
else
  fail "Winner sandbox directory was not auto-cleared"
fi

if git branch --list | grep -q "sandbox/winner_sb"; then
  fail "Winner branch sandbox/winner_sb still exists"
else
  ok "Winner branch automatically deleted"
fi

# Test 4: merge-winner must NOT delete other sandboxes unless --clean-others is given
python3 "$SCRIPT" create keep_a >/dev/null 2>&1
python3 "$SCRIPT" create win_b >/dev/null 2>&1
( cd "$P/.sandboxes/win_b" && echo "b" > b.txt && git add b.txt && git commit -q -m "feat: b" )
python3 "$SCRIPT" merge-winner win_b >/dev/null 2>&1
if [ -d "$P/.sandboxes/keep_a" ]; then
  ok "merge-winner keeps the other sandboxes by default"
else
  fail "merge-winner deleted another sandbox by default"
fi
python3 "$SCRIPT" create win_c >/dev/null 2>&1
( cd "$P/.sandboxes/win_c" && echo "c" > c.txt && git add c.txt && git commit -q -m "feat: c" )
python3 "$SCRIPT" merge-winner win_c --clean-others >/dev/null 2>&1
if [ ! -d "$P/.sandboxes/keep_a" ]; then
  ok "--clean-others removes the losing sandboxes on request"
else
  fail "--clean-others did not remove the losing sandbox"
fi

# Test 5: a '.' line in .worktreeinclude must never select the repo root
printf '.\n./\n.env\n' > "$P/.worktreeinclude"
INC=$(python3 -c "import sys; sys.path.extend(['$DEVKIT_DIR/scripts/git', '$DEVKIT_DIR/scripts']); import worktree_sandbox as w; from pathlib import Path; print(w.parse_worktree_include(Path('$P')))")
if [ "$INC" = "['.env']" ]; then
  ok ".worktreeinclude '.' / './' lines are ignored"
else
  fail ".worktreeinclude accepted a repo-root path: $INC"
fi

# Test 6: cleanup never discards work unless --force is given
python3 "$SCRIPT" create dirty_sb >/dev/null 2>&1
echo "uncommitted work" >> "$P/.sandboxes/dirty_sb/README.md"
python3 "$SCRIPT" cleanup --name dirty_sb >/dev/null 2>&1
if [ -d "$P/.sandboxes/dirty_sb" ] && grep -q "uncommitted work" "$P/.sandboxes/dirty_sb/README.md"; then
  ok "cleanup keeps a sandbox that has uncommitted changes"
else
  fail "cleanup destroyed uncommitted work without --force"
fi
python3 "$SCRIPT" create ahead_sb >/dev/null 2>&1
( cd "$P/.sandboxes/ahead_sb" && echo x > ahead.txt && git add ahead.txt && git commit -q -m "feat: unmerged" )
AHEAD_OUT=$(python3 "$SCRIPT" cleanup --name ahead_sb 2>&1)
if git -C "$P" rev-parse --verify -q "sandbox/ahead_sb" >/dev/null; then
  ok "cleanup keeps the branch that holds unmerged commits"
else
  fail "cleanup deleted a branch with unmerged commits without --force"
fi
# issue #12: the FOLDER of a sandbox with unmerged commits is kept too (refused before rmtree), and the user is told why
if [ -f "$P/.sandboxes/ahead_sb/ahead.txt" ] && echo "$AHEAD_OUT" | grep -q "chưa merge"; then
  ok "cleanup refuses a sandbox with unmerged commits: folder kept, warning printed"
else
  fail "cleanup deleted the folder of a sandbox with unmerged commits: $AHEAD_OUT"
fi
# issue #12 review R2: cleanup vừa từ chối thì không được chốt "✅ Đã dọn dẹp hoàn tất", phải nêu tên sandbox chưa dọn
if ! echo "$AHEAD_OUT" | grep -q "✅" && echo "$AHEAD_OUT" | grep -q "chưa dọn.*ahead_sb"; then
  ok "cleanup that refused a sandbox names it as not cleaned, never 'done'"
else
  fail "cleanup claimed it was done after refusing a sandbox: $AHEAD_OUT"
fi
# a commit on the sandbox's own detached HEAD (its branch is merged): only that worktree's reflog names it, so it is unmerged work too
python3 "$SCRIPT" create det_sb >/dev/null 2>&1
( cd "$P/.sandboxes/det_sb" && git checkout -q --detach && echo d > det.txt && git add det.txt && git commit -q -m "feat: detached" )
DET_OUT=$(python3 "$SCRIPT" cleanup --name det_sb 2>&1)
if [ -f "$P/.sandboxes/det_sb/det.txt" ] && echo "$DET_OUT" | grep -q "chưa merge"; then
  ok "cleanup refuses a sandbox whose detached HEAD holds an unmerged commit"
else
  fail "cleanup deleted a sandbox whose detached HEAD held an unmerged commit: $DET_OUT"
fi
# issue #12 QA F2: commit trên HEAD tách rời rồi quay lại nhánh sandbox (đã merge): chỉ reflog HEAD của sandbox còn giữ commit đó
python3 "$SCRIPT" create f2_sb >/dev/null 2>&1
( cd "$P/.sandboxes/f2_sb" && git checkout -q --detach && echo f2 > f2.txt && git add f2.txt && git commit -q -m "feat: f2" && git checkout -q sandbox/f2_sb )
F2_OUT=$(python3 "$SCRIPT" cleanup --name f2_sb 2>&1)
if [ -d "$P/.sandboxes/f2_sb" ] && git -C "$P" rev-parse --verify -q "sandbox/f2_sb" >/dev/null && echo "$F2_OUT" | grep -q "chưa merge"; then
  ok "cleanup keeps a sandbox whose reflog-only commit is unmerged"
else
  fail "cleanup lost a reflog-only commit: $F2_OUT"
fi
# commit trên nhánh sandbox rồi `reset --hard HEAD~1`: reflog của nhánh không cứu được vì cleanup xoá luôn nhánh đó
python3 "$SCRIPT" create reset_sb >/dev/null 2>&1
( cd "$P/.sandboxes/reset_sb" && echo r > r.txt && git add r.txt && git commit -q -m "feat: reset away" && git reset -q --hard HEAD~1 )
RESET_OUT=$(python3 "$SCRIPT" cleanup --name reset_sb 2>&1)
if [ -d "$P/.sandboxes/reset_sb" ] && echo "$RESET_OUT" | grep -q "chưa merge"; then
  ok "cleanup keeps a sandbox whose reset-away commit only reflogs name"
else
  fail "cleanup lost a commit named only by the reflogs it deletes: $RESET_OUT"
fi
# issue #12 QA SW6: checkout chính tách rời ở đúng nhánh sandbox: HEAD của nó chứa commit, nhưng nhánh chính thì chưa
MAIN_BR=$(git -C "$P" symbolic-ref --short HEAD)
python3 "$SCRIPT" create sw6_sb >/dev/null 2>&1
( cd "$P/.sandboxes/sw6_sb" && echo s > s.txt && git add s.txt && git commit -q -m "feat: sw6" )
git -C "$P" checkout -q --detach sandbox/sw6_sb
SW6_OUT=$(python3 "$SCRIPT" cleanup --name sw6_sb 2>&1)
git -C "$P" checkout -q "$MAIN_BR"
if [ -d "$P/.sandboxes/sw6_sb" ] && git -C "$P" rev-parse --verify -q "sandbox/sw6_sb" >/dev/null && echo "$SW6_OUT" | grep -q "chưa merge"; then
  ok "cleanup judges 'merged' by the main branch, not a detached main checkout"
else
  fail "cleanup deleted a sandbox merged only into a detached main checkout: $SW6_OUT"
fi
# issue #12 review R1: checkout chính tách rời (`git checkout --detach`, witness của reviewer): "đã merge" xét theo nhánh trunk,
# sandbox chưa đụng vẫn dọn được (SW6 ở trên vẫn giữ: commit của nó chưa vào trunk)
git -C "$P" checkout -q --detach
python3 "$SCRIPT" create r1_main >/dev/null 2>&1
R1M_OUT=$(python3 "$SCRIPT" cleanup --name r1_main 2>&1)
git -C "$P" checkout -q "$MAIN_BR"
if [ ! -d "$P/.sandboxes/r1_main" ] && ! git -C "$P" rev-parse --verify -q "sandbox/r1_main" >/dev/null; then
  ok "cleanup from a detached main checkout removes an untouched sandbox"
else
  fail "cleanup from a detached main checkout kept an untouched sandbox: $R1M_OUT"
fi
# OCR: checkout chính tách rời ở commit CŨ hơn trunk: sandbox chưa đụng (tạo từ trunk) dọn cả thư mục lẫn nhánh, không nửa vời
python3 "$SCRIPT" create r1_old >/dev/null 2>&1
git -C "$P" checkout -q --detach HEAD~1
R1O_OUT=$(python3 "$SCRIPT" cleanup --name r1_old 2>&1)
git -C "$P" checkout -q "$MAIN_BR"
if [ ! -d "$P/.sandboxes/r1_old" ] && ! git -C "$P" rev-parse --verify -q "sandbox/r1_old" >/dev/null && echo "$R1O_OUT" | grep -q "✅"; then
  ok "cleanup from a main checkout detached behind trunk removes folder and branch together"
else
  fail "cleanup from a main checkout detached behind trunk left a half-cleaned sandbox: $R1O_OUT"
fi
# review rebuild 2: merge-winner từ checkout chính tách rời chỉ merge vào HEAD tách rời (`git checkout main` là bỏ rơi) → từ chối
# trước khi đổi gì: HEAD không nhích, sandbox + nhánh giữ nguyên
python3 "$SCRIPT" create r1_mwd >/dev/null 2>&1
( cd "$P/.sandboxes/r1_mwd" && echo m > mwd.txt && git add mwd.txt && git commit -q -m "feat: mwd" )
git -C "$P" checkout -q --detach
MWD_BEFORE=$(git -C "$P" rev-parse HEAD)
if MWD_OUT=$(python3 "$SCRIPT" merge-winner r1_mwd 2>&1); then MWD_RC=0; else MWD_RC=1; fi
MWD_AFTER=$(git -C "$P" rev-parse HEAD)
git -C "$P" checkout -q "$MAIN_BR"
if [ "$MWD_RC" -ne 0 ] && [ "$MWD_BEFORE" = "$MWD_AFTER" ] && [ -d "$P/.sandboxes/r1_mwd" ] \
   && git -C "$P" rev-parse --verify -q "sandbox/r1_mwd" >/dev/null && echo "$MWD_OUT" | grep -q "HEAD tách rời"; then
  ok "merge-winner refuses to merge into a detached main checkout"
else
  fail "merge-winner merged into a detached main checkout (rc=$MWD_RC): $MWD_OUT"
fi
python3 "$SCRIPT" cleanup --name r1_mwd --force >/dev/null 2>&1
# review rebuild 2: origin/HEAD trỏ nhánh trunk không có bản local → giữ (fail closed) và nói rõ vì sao
git -C "$P" update-ref refs/remotes/origin/develop HEAD
git -C "$P" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
python3 "$SCRIPT" create r1_dev >/dev/null 2>&1
git -C "$P" checkout -q --detach
DEV_OUT=$(python3 "$SCRIPT" cleanup --name r1_dev 2>&1)
git -C "$P" checkout -q "$MAIN_BR"
git -C "$P" symbolic-ref --delete refs/remotes/origin/HEAD
git -C "$P" update-ref -d refs/remotes/origin/develop
if [ -d "$P/.sandboxes/r1_dev" ] && echo "$DEV_OUT" | grep -q "develop.*không có bản local"; then
  ok "cleanup keeps a sandbox when origin/HEAD names a trunk with no local branch, and says why"
else
  fail "cleanup misjudged a trunk with no local branch: $DEV_OUT"
fi
python3 "$SCRIPT" cleanup --name r1_dev --force >/dev/null 2>&1
# review rebuild 2 P1: agent khác commit vào nhánh sandbox SAU bước kiểm, trước khi xoá nhánh → nhánh phải được giữ (xoá đúng SHA đã kiểm)
python3 "$SCRIPT" create race_sb >/dev/null 2>&1
RACE_OUT=$(python3 - "$DEVKIT_DIR/scripts/git" "$P/.sandboxes/race_sb" 2>&1 <<'PYEOF'
import subprocess, sys
sys.path.insert(0, sys.argv[1])
import worktree_sandbox as w
orig = w.sandbox_unmerged_commits
def racy(*a, **k):
    r = orig(*a, **k)
    subprocess.run(["git", "-C", sys.argv[2], "commit", "-q", "--allow-empty", "-m", "race"], check=True)
    return r
w.sandbox_unmerged_commits = racy
w.cleanup_sandbox(name="race_sb")
PYEOF
)
if git -C "$P" rev-parse --verify -q "sandbox/race_sb" >/dev/null && [ "$(git -C "$P" log -1 --format=%s sandbox/race_sb 2>/dev/null)" = "race" ]; then
  ok "cleanup keeps the branch when a commit lands on it after the merge check"
else
  fail "cleanup deleted a branch that gained a commit after the merge check: $RACE_OUT"
fi
git -C "$P" branch -q -D sandbox/race_sb 2>/dev/null
# OCR rebuild 2: một worktree khác đang checkout nhánh sandbox (attached) → không xoá nhánh dưới chân nó (HEAD thành unborn)
python3 "$SCRIPT" create co_sb >/dev/null 2>&1
git -C "$P" worktree add -q -f "$TMP/co-wt" sandbox/co_sb
CO_OUT=$(python3 "$SCRIPT" cleanup --name co_sb 2>&1)
if git -C "$P" rev-parse --verify -q "sandbox/co_sb" >/dev/null && git -C "$TMP/co-wt" rev-parse --verify -q HEAD >/dev/null; then
  ok "cleanup keeps a sandbox branch another worktree has checked out"
else
  fail "cleanup deleted a branch another worktree had checked out: $CO_OUT"
fi
git -C "$P" worktree remove --force "$TMP/co-wt"
git -C "$P" branch -q -D sandbox/co_sb 2>/dev/null
# merge-winner merge được nhánh nhưng cleanup giữ sandbox (commit chỉ reflog còn giữ): không được báo "đã dọn" sau cảnh báo
python3 "$SCRIPT" create mw_sb >/dev/null 2>&1
( cd "$P/.sandboxes/mw_sb" && echo x > mw.txt && git add mw.txt && git commit -q -m "feat: mw" && git checkout -q --detach \
  && echo y > mwy.txt && git add mwy.txt && git commit -q -m "feat: mw detached" && git checkout -q sandbox/mw_sb )
MW_OUT=$(python3 "$SCRIPT" merge-winner mw_sb 2>&1)
if [ -d "$P/.sandboxes/mw_sb" ] && echo "$MW_OUT" | grep -q "chưa dọn" && ! echo "$MW_OUT" | grep -q "🎉"; then
  ok "merge-winner says the winner was merged but kept, never 'cleaned'"
else
  fail "merge-winner claimed a kept winner sandbox was cleaned: $MW_OUT"
fi
python3 "$SCRIPT" cleanup --name dirty_sb --force >/dev/null 2>&1
python3 "$SCRIPT" cleanup --name ahead_sb --force >/dev/null 2>&1
python3 "$SCRIPT" cleanup --name det_sb --force >/dev/null 2>&1
python3 "$SCRIPT" cleanup --name f2_sb --force >/dev/null 2>&1
python3 "$SCRIPT" cleanup --name reset_sb --force >/dev/null 2>&1
python3 "$SCRIPT" cleanup --name sw6_sb --force >/dev/null 2>&1
python3 "$SCRIPT" cleanup --name mw_sb --force >/dev/null 2>&1
if [ ! -d "$P/.sandboxes/dirty_sb" ] && [ ! -d "$P/.sandboxes/ahead_sb" ] && [ ! -d "$P/.sandboxes/det_sb" ] \
   && [ ! -d "$P/.sandboxes/f2_sb" ] && [ ! -d "$P/.sandboxes/reset_sb" ] && [ ! -d "$P/.sandboxes/sw6_sb" ] && [ ! -d "$P/.sandboxes/mw_sb" ] \
   && ! git -C "$P" rev-parse --verify -q "sandbox/ahead_sb" >/dev/null && ! git -C "$P" rev-parse --verify -q "sandbox/sw6_sb" >/dev/null; then
  ok "--force removes the sandbox and the unmerged branch on explicit request"
else
  fail "--force did not remove the sandboxes and branch"
fi
# issue #12 QA v2: merge-winner --clean-others chạy cleanup --all lên sandbox thua; sandbox thua có commit chỉ reflog HEAD của nó giữ (dạng F2) phải được giữ
python3 "$SCRIPT" create mwl_lose >/dev/null 2>&1
python3 "$SCRIPT" create mwl_win >/dev/null 2>&1
( cd "$P/.sandboxes/mwl_lose" && git checkout -q --detach && echo l > lose.txt && git add lose.txt && git commit -q -m "feat: loser detached" \
  && git checkout -q sandbox/mwl_lose )
( cd "$P/.sandboxes/mwl_win" && echo w > win.txt && git add win.txt && git commit -q -m "feat: win" )
MWL_OUT=$(python3 "$SCRIPT" merge-winner mwl_win --clean-others 2>&1)
if [ -d "$P/.sandboxes/mwl_lose" ] && git -C "$P" rev-parse --verify -q "sandbox/mwl_lose" >/dev/null && echo "$MWL_OUT" | grep -q "chưa merge"; then
  ok "merge-winner --clean-others keeps a losing sandbox whose reflog-only commit is unmerged"
else
  fail "merge-winner --clean-others lost a losing sandbox's reflog-only commit: $MWL_OUT"
fi
# reflog HEAD của sandbox có dòng git không đọc được: không biết commit nào chỉ nó giữ → giữ (fail closed), không hiểu thành "sạch"
python3 "$SCRIPT" create rlg_sb >/dev/null 2>&1
( cd "$P/.sandboxes/rlg_sb" && git checkout -q --detach && echo g > rlg.txt && git add rlg.txt && git commit -q -m "feat: rlg detached" \
  && git checkout -q sandbox/rlg_sb && echo "not a reflog line" >> "$(git rev-parse --git-dir)/logs/HEAD" )
RLG_OUT=$(python3 "$SCRIPT" cleanup --name rlg_sb 2>&1)
if [ -d "$P/.sandboxes/rlg_sb" ] && echo "$RLG_OUT" | grep -q "không đọc được reflog HEAD"; then
  ok "cleanup keeps a sandbox whose HEAD reflog cannot be read"
else
  fail "cleanup treated an unreadable sandbox reflog as clean: $RLG_OUT"
fi
# HEAD của sandbox không đọc được (nhánh orphan chưa có commit): không biết commit nào chỉ reflog giữ → giữ
python3 "$SCRIPT" create unb_sb >/dev/null 2>&1
( cd "$P/.sandboxes/unb_sb" && git checkout -q --detach && echo u > unb.txt && git add unb.txt && git commit -q -m "feat: unb detached" \
  && git checkout -q sandbox/unb_sb && git switch -q --orphan unb_unborn )
UNB_OUT=$(python3 "$SCRIPT" cleanup --name unb_sb 2>&1)
if [ -d "$P/.sandboxes/unb_sb" ] && echo "$UNB_OUT" | grep -q "không đọc được HEAD của sandbox"; then
  ok "cleanup keeps a sandbox whose HEAD cannot be read"
else
  fail "cleanup treated a sandbox with an unreadable HEAD as clean: $UNB_OUT"
fi
python3 "$SCRIPT" cleanup --name mwl_lose --force >/dev/null 2>&1
python3 "$SCRIPT" cleanup --name rlg_sb --force >/dev/null 2>&1
python3 "$SCRIPT" cleanup --name unb_sb --force >/dev/null 2>&1

# Test 7: a new file that was never `git add`ed is work too (not a disposable leftover)
python3 "$SCRIPT" create untracked_sb >/dev/null 2>&1
echo "print('feature')" > "$P/.sandboxes/untracked_sb/feature.py"
python3 "$SCRIPT" cleanup --name untracked_sb >/dev/null 2>&1
if [ -f "$P/.sandboxes/untracked_sb/feature.py" ]; then
  ok "cleanup keeps a sandbox holding a new untracked file"
else
  fail "cleanup deleted an untracked new file without --force"
fi
if python3 "$SCRIPT" merge-winner untracked_sb >/dev/null 2>&1; then
  fail "merge-winner accepted a sandbox holding an untracked new file"
else
  ok "merge-winner refuses a sandbox holding an untracked new file"
fi
[ -f "$P/.sandboxes/untracked_sb/feature.py" ] && ok "  … and the file is still there" || fail "merge-winner lost the untracked file"
python3 "$SCRIPT" cleanup --name untracked_sb --force >/dev/null 2>&1

# Test 8: an unreadable worktree (admin dir gone) must not look clean
python3 "$SCRIPT" create broken_sb >/dev/null 2>&1
echo "tracked edit" >> "$P/.sandboxes/broken_sb/README.md"
GCD="$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)"
mv "$GCD/worktrees/broken_sb" "$TMP/broken_sb_admin"
python3 "$SCRIPT" cleanup --name broken_sb >/dev/null 2>&1
if [ -f "$P/.sandboxes/broken_sb/README.md" ] && grep -q "tracked edit" "$P/.sandboxes/broken_sb/README.md"; then
  ok "cleanup keeps a sandbox whose git status cannot be read"
else
  fail "cleanup deleted a sandbox whose status was unreadable"
fi
mv "$TMP/broken_sb_admin" "$GCD/worktrees/broken_sb"
python3 "$SCRIPT" cleanup --name broken_sb --force >/dev/null 2>&1

# Test 9: .worktreeinclude may name a DIRECTORY; a new file inside it is still work, an unchanged copy is not
mkdir -p "$P/config" && echo "base" > "$P/config/base.txt"
printf 'config\n.env\n' > "$P/.worktreeinclude"
python3 "$SCRIPT" create dir_sb >/dev/null 2>&1
echo "print('mine')" > "$P/.sandboxes/dir_sb/config/new_work.py"
python3 "$SCRIPT" cleanup --name dir_sb >/dev/null 2>&1
if [ -f "$P/.sandboxes/dir_sb/config/new_work.py" ]; then
  ok "cleanup keeps a new file inside an included directory"
else
  fail "cleanup deleted a new file inside an included directory"
fi
rm -f "$P/.sandboxes/dir_sb/config/new_work.py"
python3 "$SCRIPT" cleanup --name dir_sb >/dev/null 2>&1
if [ ! -d "$P/.sandboxes/dir_sb" ]; then
  ok "a sandbox holding only unchanged copies of included files is cleaned up"
else
  fail "a sandbox with only unchanged included copies was kept"
fi

# Test 10 (issue #12 review R1): chạy từ linked worktree tách rời (worktree phiên, trunk mode): "đã merge" xét theo HEAD của
# worktree đó (GC root, được gộp về main) — sandbox chưa đụng được dọn, merge-winner dọn + 🎉, commit chưa merge vẫn giữ
W="$TMP/session-wt"
git -C "$P" worktree add -q --detach "$W" HEAD
cd "$W"
python3 "$SCRIPT" create r1_clean >/dev/null 2>&1
R1C_OUT=$(python3 "$SCRIPT" cleanup --name r1_clean 2>&1)
if [ ! -d "$W/.sandboxes/r1_clean" ] && ! git -C "$W" rev-parse --verify -q "sandbox/r1_clean" >/dev/null && echo "$R1C_OUT" | grep -q "✅"; then
  ok "cleanup from a detached linked worktree removes an untouched sandbox"
else
  fail "cleanup from a detached linked worktree kept an untouched sandbox: $R1C_OUT"
fi
python3 "$SCRIPT" create r1_win >/dev/null 2>&1
( cd "$W/.sandboxes/r1_win" && echo w > r1w.txt && git add r1w.txt && git commit -q -m "feat: r1 win" )
R1W_OUT=$(python3 "$SCRIPT" merge-winner r1_win 2>&1)
if [ -f "$W/r1w.txt" ] && [ ! -d "$W/.sandboxes/r1_win" ] && ! git -C "$W" rev-parse --verify -q "sandbox/r1_win" >/dev/null \
   && echo "$R1W_OUT" | grep -q "🎉"; then
  ok "merge-winner from a detached linked worktree merges, cleans the winner and says so"
else
  fail "merge-winner from a detached linked worktree did not clean the winner: $R1W_OUT"
fi
python3 "$SCRIPT" create r1_ahead >/dev/null 2>&1
( cd "$W/.sandboxes/r1_ahead" && echo a > r1a.txt && git add r1a.txt && git commit -q -m "feat: r1 unmerged" )
R1A_OUT=$(python3 "$SCRIPT" cleanup --name r1_ahead 2>&1)
if [ -f "$W/.sandboxes/r1_ahead/r1a.txt" ] && git -C "$W" rev-parse --verify -q "sandbox/r1_ahead" >/dev/null \
   && echo "$R1A_OUT" | grep -q "chưa merge vào HEAD của worktree này"; then
  ok "cleanup from a detached linked worktree still keeps a sandbox with unmerged commits"
else
  fail "cleanup from a detached linked worktree lost unmerged commits: $R1A_OUT"
fi
python3 "$SCRIPT" cleanup --name r1_ahead --force >/dev/null 2>&1
# Trade-off có chủ ý (review rebuild 2): linked worktree `checkout --detach sandbox/<x>` để xem thì sandbox được dọn — cùng hình
# dạng với merge-winner fast-forward ở trên, không phân biệt được — nhưng commit vẫn nằm trên HEAD của worktree đó (không mất lúc dọn)
python3 "$SCRIPT" create r1_view >/dev/null 2>&1
( cd "$W/.sandboxes/r1_view" && echo v > r1v.txt && git add r1v.txt && git commit -q -m "feat: r1 view" )
R1V_SHA=$(git -C "$W" rev-parse "sandbox/r1_view")
git -C "$W" checkout -q --detach "sandbox/r1_view"
python3 "$SCRIPT" cleanup --name r1_view >/dev/null 2>&1
if [ ! -d "$W/.sandboxes/r1_view" ] && git -C "$W" merge-base --is-ancestor "$R1V_SHA" HEAD; then
  ok "a detached linked worktree viewing a sandbox: sandbox cleaned, its commits stay on that worktree's HEAD"
else
  fail "linked-worktree view trade-off changed (sandbox kept, or its commits left HEAD) — update the docstring of merged_into"
fi
cd "$P"
git -C "$P" worktree remove --force "$W"

if [ $FAILS -gt 0 ]; then
  echo "FAILED: $FAILS errors"
  exit 1
fi
echo "ALL TESTS PASSED"
exit 0
