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
git init -q . && git symbolic-ref HEAD refs/heads/main && git config user.email t@t && git config user.name t   # nhánh tên main cố định: các ca checkout tách rời cần nhánh trunk
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
print("kept:", w.cleanup_sandbox(name="race_sb"))
PYEOF
)
if git -C "$P" rev-parse --verify -q "sandbox/race_sb" >/dev/null && [ "$(git -C "$P" log -1 --format=%s sandbox/race_sb 2>/dev/null)" = "race" ] \
   && echo "$RACE_OUT" | grep -q "kept: \['race_sb'\]" && ! echo "$RACE_OUT" | grep -q "✅"; then
  ok "cleanup keeps the branch when a commit lands on it after the merge check"
else
  fail "cleanup deleted a branch that gained a commit after the merge check: $RACE_OUT"
fi
git -C "$P" branch -q -D sandbox/race_sb 2>/dev/null
# OCR rebuild 2: một worktree khác đang checkout nhánh sandbox (attached) → không xoá nhánh dưới chân nó (HEAD thành unborn)
python3 "$SCRIPT" create co_sb >/dev/null 2>&1
git -C "$P" worktree add -q -f "$TMP/co-wt" sandbox/co_sb
CO_OUT=$(python3 "$SCRIPT" cleanup --name co_sb 2>&1)
if git -C "$P" rev-parse --verify -q "sandbox/co_sb" >/dev/null && git -C "$TMP/co-wt" rev-parse --verify -q HEAD >/dev/null \
   && [ -d "$P/.sandboxes/co_sb" ]; then   # từ chối TRƯỚC rmtree: không để thư mục mất mà nhánh còn (review)
  ok "cleanup keeps a sandbox branch another worktree has checked out"
else
  fail "cleanup deleted a branch another worktree had checked out: $CO_OUT"
fi
git -C "$P" worktree remove --force "$TMP/co-wt"
python3 "$SCRIPT" cleanup --name co_sb --force >/dev/null 2>&1
# review: checkout chạy lệnh đứng trên chính nhánh sandbox → mốc "đã merge" là chính nhánh đó, phép kiểm luôn đúng → giữ, trước rmtree
python3 "$SCRIPT" create self_sb >/dev/null 2>&1
( cd "$P/.sandboxes/self_sb" && echo s > self.txt && git add self.txt && git commit -q -m "feat: self" )
git -C "$P" checkout -q --ignore-other-worktrees sandbox/self_sb
SELF_OUT=$(python3 "$SCRIPT" cleanup --name self_sb 2>&1)
git -C "$P" checkout -q "$MAIN_BR"
if [ -f "$P/.sandboxes/self_sb/self.txt" ] && git -C "$P" rev-parse --verify -q "sandbox/self_sb" >/dev/null && echo "$SELF_OUT" | grep -q "chính nhánh sandbox/self_sb"; then
  ok "cleanup refuses when the checkout running it stands on the sandbox branch itself"
else
  fail "cleanup judged a sandbox against its own branch: $SELF_OUT"
fi
python3 "$SCRIPT" cleanup --name self_sb --force >/dev/null 2>&1
# review: refs/heads/sandbox/<x> là symref trỏ main → xoá đúng symref, không xoá main qua nó
MAIN_SHA=$(git -C "$P" rev-parse "refs/heads/$MAIN_BR")
git -C "$P" symbolic-ref refs/heads/sandbox/sym_sb "refs/heads/$MAIN_BR"
SYM_OUT=$(python3 "$SCRIPT" cleanup --name sym_sb 2>&1)
if git -C "$P" show-ref --verify -q "refs/heads/$MAIN_BR" && ! git -C "$P" show-ref --verify -q "refs/heads/sandbox/sym_sb" \
   && ! git -C "$P" symbolic-ref -q refs/heads/sandbox/sym_sb >/dev/null 2>&1; then
  ok "cleanup deletes a symref sandbox branch itself, never the branch it points to"
else
  fail "cleanup followed a sandbox symref (main gone?): $SYM_OUT"
fi
git -C "$P" show-ref --verify -q "refs/heads/$MAIN_BR" || git -C "$P" update-ref "refs/heads/$MAIN_BR" "$MAIN_SHA"   # lỗi thì dựng lại main cho các ca sau
# review: nhánh sandbox bị xoá đồng thời giữa bước kiểm và bước xoá → đã sạch, không liệt kê "chưa dọn"
python3 "$SCRIPT" create gone_sb >/dev/null 2>&1
GONE_OUT=$(python3 - "$DEVKIT_DIR/scripts/git" "$P" 2>&1 <<'PYEOF'
import subprocess, sys
sys.path.insert(0, sys.argv[1])
import worktree_sandbox as w
orig = w.sandbox_unmerged_commits
def gone(*a, **k):
    r = orig(*a, **k)
    subprocess.run(["git", "-C", sys.argv[2], "update-ref", "-d", "refs/heads/sandbox/gone_sb"], check=True)
    return r
w.sandbox_unmerged_commits = gone
w.cleanup_sandbox(name="gone_sb")
PYEOF
)
if [ ! -d "$P/.sandboxes/gone_sb" ] && echo "$GONE_OUT" | grep -q "✅" && ! echo "$GONE_OUT" | grep -q "chưa dọn"; then
  ok "cleanup counts a sandbox whose branch vanished meanwhile as cleaned"
else
  fail "cleanup listed a sandbox whose branch is already gone as not cleaned: $GONE_OUT"
fi
# review: git không trả lời được nhánh còn hay mất sau khi xoá lỗi (rev-parse rc 128) → giữ trong danh sách, không báo ✓
python3 "$SCRIPT" create err_sb >/dev/null 2>&1
ERR_OUT=$(python3 - "$DEVKIT_DIR/scripts/git" 2>&1 <<'PYEOF'
import subprocess, sys
sys.path.insert(0, sys.argv[1])
import worktree_sandbox as w
orig = w.run_cmd
def broken(cmd, *a, **k):
    if cmd[:2] == ["git", "update-ref"]:
        return subprocess.CompletedProcess(cmd, 1, "", "fatal: simulated")
    if cmd[:2] == ["git", "rev-parse"] and cmd[-1] == "refs/heads/sandbox/err_sb":
        return subprocess.CompletedProcess(cmd, 128, "", "fatal: simulated")
    return orig(cmd, *a, **k)
w.run_cmd = broken
print("kept:", w.cleanup_sandbox(name="err_sb"))
PYEOF
)
if echo "$ERR_OUT" | grep -q "kept: \['err_sb'\]"; then
  ok "cleanup keeps a sandbox in the not-cleaned list when git cannot say whether its branch survived"
else
  fail "cleanup read a git error as 'branch gone': $ERR_OUT"
fi
python3 "$SCRIPT" cleanup --name err_sb --force >/dev/null 2>&1
# review: đăng ký worktree của chính sandbox bị `git worktree lock` → từ chối trước rmtree (như `git worktree remove`), không để đăng ký ma + ✅
python3 "$SCRIPT" create lock_sb >/dev/null 2>&1
git -C "$P" worktree lock "$P/.sandboxes/lock_sb"
LOCK_OUT=$(python3 "$SCRIPT" cleanup --name lock_sb 2>&1)
if [ -d "$P/.sandboxes/lock_sb" ] && git -C "$P" rev-parse --verify -q "sandbox/lock_sb" >/dev/null && echo "$LOCK_OUT" | grep -q "khoá"; then
  ok "cleanup refuses a sandbox whose worktree registration is locked"
else
  fail "cleanup removed a locked sandbox registration's folder/branch: $LOCK_OUT"
fi
git -C "$P" worktree unlock "$P/.sandboxes/lock_sb"
python3 "$SCRIPT" cleanup --name lock_sb --force >/dev/null 2>&1
# OCR: cùng ca khoá nhưng nhánh sandbox đã mất (sandbox đứng HEAD tách rời) → vẫn từ chối, không cần nhánh mới kiểm khoá
python3 "$SCRIPT" create lock_nb >/dev/null 2>&1
git -C "$P/.sandboxes/lock_nb" checkout -q --detach
git -C "$P" branch -q -D sandbox/lock_nb
git -C "$P" worktree lock "$P/.sandboxes/lock_nb"
LNB_OUT=$(python3 "$SCRIPT" cleanup --name lock_nb 2>&1)
if [ -d "$P/.sandboxes/lock_nb" ] && echo "$LNB_OUT" | grep -q "khoá"; then
  ok "cleanup refuses a locked sandbox registration even when its branch is gone"
else
  fail "cleanup removed a locked sandbox whose branch was gone: $LNB_OUT"
fi
git -C "$P" worktree unlock "$P/.sandboxes/lock_nb"
python3 "$SCRIPT" cleanup --name lock_nb --force >/dev/null 2>&1
# review: worktree khác từng checkout nhánh sandbox nhưng thư mục đã mất (prunable) → không chặn dọn
python3 "$SCRIPT" create prn_sb >/dev/null 2>&1
git -C "$P" worktree add -q -f "$TMP/prn-wt" sandbox/prn_sb
rm -rf "$TMP/prn-wt"
PRN_OUT=$(python3 "$SCRIPT" cleanup --name prn_sb 2>&1)
if [ ! -d "$P/.sandboxes/prn_sb" ] && ! git -C "$P" rev-parse --verify -q "sandbox/prn_sb" >/dev/null; then
  ok "a prunable registration whose folder is gone does not block cleanup"
else
  fail "a prunable registration blocked cleanup: $PRN_OUT"
fi
# review: merge-winner khi checkout đứng trên chính nhánh sandbox → merge vào chính nó, không vào nhánh chính → từ chối
python3 "$SCRIPT" create g_sb >/dev/null 2>&1
( cd "$P/.sandboxes/g_sb" && echo g > g.txt && git add g.txt && git commit -q -m "feat: g" )
git -C "$P" checkout -q --ignore-other-worktrees sandbox/g_sb
if G_OUT=$(python3 "$SCRIPT" merge-winner g_sb 2>&1); then G_RC=0; else G_RC=1; fi
git -C "$P" checkout -q "$MAIN_BR"
if [ "$G_RC" -ne 0 ] && echo "$G_OUT" | grep -q "chính nhánh sandbox/g_sb" && [ -d "$P/.sandboxes/g_sb" ]; then
  ok "merge-winner refuses when the checkout stands on the sandbox branch itself"
else
  fail "merge-winner merged a sandbox into its own branch (rc=$G_RC): $G_OUT"
fi
python3 "$SCRIPT" cleanup --name g_sb --force >/dev/null 2>&1
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
R1V_OUT=$(python3 "$SCRIPT" cleanup --name r1_view 2>&1)
if [ ! -d "$W/.sandboxes/r1_view" ] && git -C "$W" merge-base --is-ancestor "$R1V_SHA" HEAD; then
  ok "a detached linked worktree viewing a sandbox: sandbox cleaned, its commits stay on that worktree's HEAD"
else
  fail "linked-worktree view trade-off changed (sandbox kept, or its commits left HEAD) — update the docstring of merged_into: $R1V_OUT"
fi
cd "$P"
git -C "$P" worktree remove --force "$W"

# issue #12 (#38): thư mục sandbox bị xoá tay khi commit của nó chỉ còn reflog HEAD trong admin dir giữ — cleanup không bao giờ
# `git worktree prune` toàn repo: chỉ gỡ đúng đăng ký của sandbox vừa kiểm
CD="$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)"
python3 "$SCRIPT" create gx >/dev/null 2>&1   # biến thể B: commit trên HEAD tách rời rồi quay lại nhánh (đã merge): chỉ reflog giữ
( cd "$P/.sandboxes/gx" && git checkout -q --detach && echo g > g.txt && git add g.txt && git commit -q -m "feat: gx detached" \
  && git checkout -q sandbox/gx )
python3 "$SCRIPT" create gd >/dev/null 2>&1   # biến thể A: còn đứng HEAD tách rời ở commit chưa merge
( cd "$P/.sandboxes/gd" && git checkout -q --detach && echo d > d.txt && git add d.txt && git commit -q -m "feat: gd detached" )
python3 "$SCRIPT" create ge >/dev/null 2>&1   # biến thể e: nhánh còn commit chưa merge (cleanup từ chối) + commit chỉ reflog giữ
( cd "$P/.sandboxes/ge" && echo e > e.txt && git add e.txt && git commit -q -m "feat: ge branch" && git checkout -q --detach \
  && echo e2 > e2.txt && git add e2.txt && git commit -q -m "feat: ge detached" && git checkout -q sandbox/ge )
rm -rf "$P/.sandboxes/gx" "$P/.sandboxes/gd" "$P/.sandboxes/ge"
python3 "$SCRIPT" create gy >/dev/null 2>&1
GY_OUT=$(python3 "$SCRIPT" cleanup --name gy 2>&1)
if [ ! -d "$P/.sandboxes/gy" ] && [ -d "$CD/worktrees/gx" ] && [ -d "$CD/worktrees/gd" ] && [ -d "$CD/worktrees/ge" ]; then
  ok "cleanup of another sandbox keeps the admin dirs of sandboxes whose folder is gone (#38)"
else
  fail "cleanup --name gy pruned other sandboxes' admin dirs: $GY_OUT"
fi
for s in gx gd; do
  S_OUT=$(python3 "$SCRIPT" cleanup --name "$s" 2>&1)
  if [ -d "$CD/worktrees/$s" ] && echo "$S_OUT" | grep -q "chưa merge" && echo "$S_OUT" | grep -q "chưa dọn.*$s"; then
    ok "cleanup keeps a folder-gone sandbox whose admin reflog/HEAD holds an unmerged commit, and says so ($s, #38)"
  else
    fail "cleanup lost the admin dir of folder-gone sandbox $s or did not warn: $S_OUT"
  fi
done
git -C "$P" rev-parse --verify -q refs/heads/sandbox/gx >/dev/null && ok "  … and keeps its branch" || fail "cleanup deleted sandbox/gx"
GE_OUT=$(python3 "$SCRIPT" cleanup --name ge 2>&1)
if [ -d "$CD/worktrees/ge" ] && git -C "$P" rev-parse --verify -q refs/heads/sandbox/ge >/dev/null && echo "$GE_OUT" | grep -q "chưa merge"; then
  ok "a refused sandbox is never pruned afterwards: its admin reflog survives (#38)"
else
  fail "cleanup refused ge then pruned its admin dir: $GE_OUT"
fi
python3 "$SCRIPT" create gz >/dev/null 2>&1; rm -rf "$P/.sandboxes/gz"   # thư mục mất, không còn gì chưa merge: dọn cả đăng ký lẫn nhánh
GZ_OUT=$(python3 "$SCRIPT" cleanup --name gz 2>&1)
if [ ! -d "$CD/worktrees/gz" ] && ! git -C "$P" rev-parse --verify -q refs/heads/sandbox/gz >/dev/null && echo "$GZ_OUT" | grep -q "✓"; then
  ok "cleanup of a clean folder-gone sandbox removes its own registration and branch"
else
  fail "cleanup left a clean folder-gone sandbox registered: $GZ_OUT"
fi
for s in gx gd ge; do python3 "$SCRIPT" cleanup --name "$s" --force >/dev/null 2>&1; done
if [ ! -d "$CD/worktrees/gx" ] && [ ! -d "$CD/worktrees/gd" ] && [ ! -d "$CD/worktrees/ge" ]; then
  ok "cleanup --force removes a folder-gone sandbox's own registration"
else
  fail "cleanup --force left a folder-gone sandbox registered"
fi
# issue #12 (#41): một worktree khác đăng ký LỒNG trong sandbox dưới đường dẫn bị ignore — git status của sandbox không thấy nó
echo ".nest-wt/" >> "$CD/info/exclude"
python3 "$SCRIPT" create nest_sb >/dev/null 2>&1
git -C "$P" worktree add -q --detach "$P/.sandboxes/nest_sb/.nest-wt/inner" HEAD
echo "work in inner" >> "$P/.sandboxes/nest_sb/.nest-wt/inner/README.md"
NEST_OUT=$(python3 "$SCRIPT" cleanup --name nest_sb 2>&1)
if grep -q "work in inner" "$P/.sandboxes/nest_sb/.nest-wt/inner/README.md" 2>/dev/null && echo "$NEST_OUT" | grep -q "inner" \
   && echo "$NEST_OUT" | grep -q "chưa dọn.*nest_sb"; then
  ok "cleanup keeps a sandbox holding a registered nested worktree (under an ignored path) and names it (#41)"
else
  fail "cleanup deleted a nested worktree's uncommitted work: $NEST_OUT"
fi
git -C "$P" worktree remove --force "$P/.sandboxes/nest_sb/.nest-wt/inner" 2>/dev/null
python3 "$SCRIPT" cleanup --name nest_sb --force >/dev/null 2>&1
# issue #12 (#41): nhánh sandbox là symref treo (đích đã mất): xoá lỗi thì nằm trong "chưa dọn", không in "xoá nhánh"
git -C "$P" symbolic-ref refs/heads/sandbox/dsym_sb refs/heads/no-such-target
if [ -d "$CD/refs/heads/sandbox" ]; then
  : > "$CD/refs/heads/sandbox/dsym_sb.lock"   # khoá ref: xoá symref sẽ lỗi
  DS_OUT=$(python3 "$SCRIPT" cleanup --name dsym_sb 2>&1)
  if git -C "$P" symbolic-ref -q refs/heads/sandbox/dsym_sb >/dev/null && ! echo "$DS_OUT" | grep -q "✓" \
     && echo "$DS_OUT" | grep -q "chưa dọn.*dsym_sb"; then
    ok "a dangling sandbox symref that cannot be deleted is listed as not cleaned, never '✓ … xoá nhánh' (#41)"
  else
    fail "cleanup claimed it deleted a dangling symref it could not delete: $DS_OUT"
  fi
  rm -f "$CD/refs/heads/sandbox/dsym_sb.lock"
fi
DS2_OUT=$(python3 "$SCRIPT" cleanup --name dsym_sb 2>&1)
if ! git -C "$P" symbolic-ref -q refs/heads/sandbox/dsym_sb >/dev/null 2>&1 && echo "$DS2_OUT" | grep -q "✓"; then
  ok "a dangling sandbox symref is deleted itself (its target untouched) and then reported done (#41)"
else
  fail "cleanup left a dangling sandbox symref: $DS2_OUT"
fi
# issue #12 (review): file bị git ignore không hiện ở `git status`: file .worktreeinclude hay file bí mật khác bản ở main là bản duy nhất
printf 'app.db\n*.jks\n' >> "$CD/info/exclude"
echo "main db" > "$P/app.db"
cp "$P/.worktreeinclude" "$TMP/worktreeinclude.bak" && printf 'app.db\n' >> "$P/.worktreeinclude"
python3 "$SCRIPT" create db_sb >/dev/null 2>&1; echo "changed in sandbox" > "$P/.sandboxes/db_sb/app.db"
python3 "$SCRIPT" create jks_sb >/dev/null 2>&1; echo "key" > "$P/.sandboxes/jks_sb/release.jks"
python3 "$SCRIPT" create db_ok >/dev/null 2>&1   # app.db chép từ main, không đổi: dọn được
DB_OUT=$(python3 "$SCRIPT" cleanup --name db_sb 2>&1); JKS_OUT=$(python3 "$SCRIPT" cleanup --name jks_sb 2>&1)
OK_OUT=$(python3 "$SCRIPT" cleanup --name db_ok 2>&1)
if grep -q "changed in sandbox" "$P/.sandboxes/db_sb/app.db" 2>/dev/null && echo "$DB_OUT" | grep -q "app.db"; then
  ok "cleanup keeps a sandbox whose ignored .worktreeinclude file differs from main's, and names it"
else
  fail "cleanup deleted an ignored include file that differed from main: $DB_OUT"
fi
if [ -f "$P/.sandboxes/jks_sb/release.jks" ] && echo "$JKS_OUT" | grep -q "release.jks"; then
  ok "cleanup keeps a sandbox holding an ignored secret only it has, and names it"
else
  fail "cleanup deleted an ignored secret only the sandbox had: $JKS_OUT"
fi
[ ! -d "$P/.sandboxes/db_ok" ] && echo "$OK_OUT" | grep -q "✓" && ok "  … an unchanged ignored include copy is still cleaned" \
  || fail "cleanup kept a sandbox whose ignored include file equals main's: $OK_OUT"
for s in db_sb jks_sb; do python3 "$SCRIPT" cleanup --name "$s" --force >/dev/null 2>&1; done
cp "$TMP/worktreeinclude.bak" "$P/.worktreeinclude"; rm -f "$P/app.db"
# issue #12 (review): agent khác ghi file / commit tách rời trong sandbox TRONG LÚC cleanup chạy các phép kiểm chậm → kiểm lại ngay trước
# rmtree, sandbox được giữ. Seam: bọc sandbox_unmerged_commits để mô phỏng thao tác chen giữa
race_cleanup() {   # race_cleanup <sandbox> <python thao tác trên p = thư mục sandbox>
  (cd "$P" && python3 - "$SCRIPT" "$1" "$2" <<'PY' 2>&1
import importlib.util, pathlib, subprocess, sys
spec = importlib.util.spec_from_file_location("wsb", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
orig = m.sandbox_unmerged_commits
def slow(s_path, *a, **k):
    r = orig(s_path, *a, **k)
    p = pathlib.Path(s_path)
    exec(sys.argv[3], {"p": p, "subprocess": subprocess})
    return r
m.sandbox_unmerged_commits = slow
m.cleanup_sandbox(name=sys.argv[2])
PY
  )
}
python3 "$SCRIPT" create rf_sb >/dev/null 2>&1
RF_OUT=$(race_cleanup rf_sb '(p / "late.txt").write_text("written during the check\n")')
if [ -f "$P/.sandboxes/rf_sb/late.txt" ] && echo "$RF_OUT" | grep -q "chưa dọn.*rf_sb"; then
  ok "a file written in the sandbox while cleanup checks is kept (re-checked right before rmtree)"
else
  fail "cleanup deleted a file written during its checks: $RF_OUT"
fi
python3 "$SCRIPT" create rc_sb >/dev/null 2>&1
RC_OUT=$(race_cleanup rc_sb 'g = lambda *a: subprocess.run(["git", *a], cwd=p, check=True, capture_output=True)
g("checkout", "-q", "--detach"); (p / "late.txt").write_text("c\n"); g("add", "late.txt"); g("commit", "-qm", "late detached"); g("checkout", "-q", "sandbox/rc_sb")')
RC_SHA=$(git -C "$P/.sandboxes/rc_sb" rev-parse 'HEAD@{1}' 2>/dev/null)
if [ -d "$P/.sandboxes/rc_sb" ] && [ -n "$RC_SHA" ] && echo "$RC_OUT" | grep -q "chưa dọn.*rc_sb"; then
  ok "a detached commit made in the sandbox while cleanup checks is kept (HEAD reflog re-checked)"
else
  fail "cleanup lost a commit made during its checks: $RC_OUT"
fi
for s in rf_sb rc_sb; do python3 "$SCRIPT" cleanup --name "$s" --force >/dev/null 2>&1; done

# Test U1 (audit 2026-10-25 D/U1): in trunk mode main moves only through `agent-kit worktree finish` (its merge gate, then a fast-forward).
# merge-winner run from the MAIN checkout merged the sandbox branch straight into main: no gate, the one door trunk mode forbids. It now
# hands the sandbox to `worktree.py finish` (the setup files create_sandbox wrote are put aside for that run). Run from a session worktree
# (Test 10) it merges into that worktree's HEAD as before; with trunk mode off the old direct merge stays.
Q="$TMP/u1-repo"; mkdir -p "$Q/.agents" && cd "$Q" || exit 1
git init -q . && git symbolic-ref HEAD refs/heads/main && git config user.email t@t && git config user.name t
echo "hello" > README.md; printf '.env\n' > .worktreeinclude; echo "K=1" > .env
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Red","watch_files":["red.txt"],
 "mandatory_regression_tests":[{"id":"REG-RED","name":"red on red.txt","command":"exit 1"}]}]}
JSON
git add README.md .worktreeinclude .agents && git commit -qm init
python3 "$SCRIPT" create u1_red >/dev/null 2>&1
( cd "$Q/.sandboxes/u1_red" && echo r > red.txt && git add red.txt && git commit -qm "feat: red" )
if U1R_OUT=$(python3 "$SCRIPT" merge-winner u1_red 2>&1); then U1R_RC=0; else U1R_RC=1; fi
if [ "$U1R_RC" -ne 0 ] && [ ! -f "$Q/red.txt" ] && [ -d "$Q/.sandboxes/u1_red" ] && [ -f "$Q/.sandboxes/u1_red/.sandbox-env.sh" ] \
   && [ -f "$Q/.sandboxes/u1_red/.env" ] && git -C "$Q" rev-parse --verify -q sandbox/u1_red >/dev/null; then
  ok "U1 trunk mode: merge-winner from main goes through worktree finish — its merge gate is red, main unchanged, the sandbox kept whole"
else
  fail "U1 trunk mode: merge-winner moved main past the merge gate (rc=$U1R_RC, red.txt in main: $([ -f "$Q/red.txt" ] && echo yes || echo no)): $U1R_OUT"
fi
if U1S_OUT=$(python3 "$SCRIPT" merge-winner u1_red --squash 2>&1); then U1S_RC=0; else U1S_RC=1; fi
[ "$U1S_RC" -ne 0 ] && [ ! -f "$Q/red.txt" ] && [ -z "$(git -C "$Q" diff --cached --name-only)" ] \
  && ok "U1 trunk mode: --squash (finish never squashes) is refused before anything moves" || fail "U1 --squash in trunk mode (rc=$U1S_RC): $U1S_OUT"
python3 "$SCRIPT" create u1_ok >/dev/null 2>&1
( cd "$Q/.sandboxes/u1_ok" && echo ok > ok.txt && git add ok.txt && git commit -qm "feat: ok" )
U1K_OUT=$(python3 "$SCRIPT" merge-winner u1_ok 2>&1)
if [ -f "$Q/ok.txt" ] && [ ! -d "$Q/.sandboxes/u1_ok" ] && ! git -C "$Q" rev-parse --verify -q sandbox/u1_ok >/dev/null \
   && echo "$U1K_OUT" | grep -q "worktree finish" && echo "$U1K_OUT" | grep -q "🎉"; then
  ok "U1 trunk mode: a green winner reaches main through worktree finish, sandbox and branch removed"
else
  fail "U1 trunk mode: green winner not merged/cleaned through finish: $U1K_OUT"
fi
U1O_OUT=$(WORKTREE_TRUNK_MODE=0 python3 "$SCRIPT" merge-winner u1_red 2>&1)
[ -f "$Q/red.txt" ] && [ ! -d "$Q/.sandboxes/u1_red" ] && ok "U1 trunk mode off (WORKTREE_TRUNK_MODE=0): the old direct merge stays" \
  || fail "U1 trunk mode off: direct merge lost: $U1O_OUT"
# Review of U1 (25/10): what matters is the BRANCH merge-winner moves, not the checkout it runs from. (a) The main checkout detached, a
# linked worktree on main: merge-winner from there merged straight into main, past the red gate. (b) The main checkout on `feat` (not the
# trunk): finish refused it, where merge-winner merges into feat as before trunk mode. (c) No trunk branch can be told (no origin/HEAD, no
# main/master/trunk): the main checkout is the trunk, as finish judges it — through finish, as before.
red_matrix() { printf '%s\n' '{"project":"t","adopted":true,"rules":[{"component":"Red","watch_files":["red.txt"],' \
  ' "mandatory_regression_tests":[{"id":"REG-RED","name":"red on red.txt","command":"exit 1"}]}]}' > "$1/.agents/regression_matrix.active.json"; }
QB="$TMP/u1b-repo"; mkdir -p "$QB/.agents" && cd "$QB" || exit 1
git init -q . && git symbolic-ref HEAD refs/heads/main && git config user.email t@t && git config user.name t
echo hello > README.md; red_matrix "$QB"; git add -A && git commit -qm init
git checkout -q --detach && git worktree add -q "$TMP/u1b-wt" main && cd "$TMP/u1b-wt" || exit 1
U1B_MAIN="$(git rev-parse main)"
python3 "$SCRIPT" create u1b >/dev/null 2>&1
( cd "$TMP/u1b-wt/.sandboxes/u1b" && echo r > red.txt && git add red.txt && git commit -qm "feat: red" )
if U1B_OUT=$(python3 "$SCRIPT" merge-winner u1b 2>&1); then U1B_RC=0; else U1B_RC=1; fi
if [ "$U1B_RC" -ne 0 ] && [ "$(git rev-parse main)" = "$U1B_MAIN" ] && ! git cat-file -e main:red.txt 2>/dev/null && [ -d "$TMP/u1b-wt/.sandboxes/u1b" ]; then
  ok "U1 (a): merge-winner from a linked worktree on main goes through worktree finish too — main unchanged, sandbox kept"
else
  fail "U1 (a): merge-winner from a linked worktree on main moved main past the gate (rc=$U1B_RC): $U1B_OUT"
fi
QC="$TMP/u1c-repo"; mkdir -p "$QC/.agents" && cd "$QC" || exit 1
git init -q . && git symbolic-ref HEAD refs/heads/main && git config user.email t@t && git config user.name t
echo hello > README.md; printf '%s\n' '{"project":"t","adopted":true,"rules":[]}' > .agents/regression_matrix.active.json; git add -A && git commit -qm init
git checkout -q -b feat && echo f > feat.txt && git add feat.txt && git commit -qm feat
U1C_MAIN="$(git rev-parse main)"
python3 "$SCRIPT" create u1c >/dev/null 2>&1
( cd "$QC/.sandboxes/u1c" && echo ok > ok.txt && git add ok.txt && git commit -qm "feat: ok" )
U1C_OUT=$(python3 "$SCRIPT" merge-winner u1c 2>&1)
if git cat-file -e feat:ok.txt 2>/dev/null && [ "$(git rev-parse main)" = "$U1C_MAIN" ] && [ ! -d "$QC/.sandboxes/u1c" ]; then
  ok "U1 (b): main checkout on feat (not the trunk): merge-winner merges into feat as before, main unchanged"
else
  fail "U1 (b): main checkout on feat: winner not merged into feat (main moved: $([ "$(git rev-parse main)" = "$U1C_MAIN" ] && echo no || echo YES)): $U1C_OUT"
fi
QD="$TMP/u1d-repo"; mkdir -p "$QD/.agents" && cd "$QD" || exit 1
git init -q . && git symbolic-ref HEAD refs/heads/develop && git config user.email t@t && git config user.name t
echo hello > README.md; red_matrix "$QD"; git add -A && git commit -qm init
U1D_DEV="$(git rev-parse develop)"
python3 "$SCRIPT" create u1d >/dev/null 2>&1
( cd "$QD/.sandboxes/u1d" && echo r > red.txt && git add red.txt && git commit -qm "feat: red" )
if U1D_OUT=$(python3 "$SCRIPT" merge-winner u1d 2>&1); then U1D_RC=0; else U1D_RC=1; fi
[ "$U1D_RC" -ne 0 ] && [ "$(git rev-parse develop)" = "$U1D_DEV" ] && [ ! -f "$QD/red.txt" ] \
  && ok "U1 (c): no trunk branch can be told: the main checkout still goes through worktree finish (red gate, develop unchanged)" \
  || fail "U1 (c): no trunk branch: merge-winner merged into develop past the gate (rc=$U1D_RC): $U1D_OUT"
cd "$P"

if [ $FAILS -gt 0 ]; then
  echo "FAILED: $FAILS errors"
  exit 1
fi
echo "ALL TESTS PASSED"
exit 0
