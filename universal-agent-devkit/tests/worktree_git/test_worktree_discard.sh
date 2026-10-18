#!/usr/bin/env bash
# Hồi quy (18/10, người dùng duyệt K2/K4 "làm cả 3"): guard git chặn `git worktree remove --force`, `git branch -D` và
# `git checkout <sha> -- <path>` theo dạng lệnh, kể cả khi không mất gì, nên mỗi lần như vậy là một việc tay cho người dùng.
# Ba lệnh kit tự chứng minh "không mất gì" rồi mới làm; dạng git trần vẫn bị guard chặn như cũ:
#   - worktree discard <path>: chỉ còn file đã xoá / rác IDE chưa track, HEAD đã nằm trong trunk, không phiên sống nào giữ nó; một bản
#     phòng hờ vào refs/devkit/discarded/* trước khi gỡ (chế độ "worktree của chính phiên" đã bỏ, review 18/10)
#   - worktree restore <sha> -- <path>…: chỉ khi path không có thay đổi chưa commit, không file ignore nào nằm đường, không ở main của trunk mode
#   - worktree prune-branch [--remote] <nhánh>: chỉ khi tip đã nằm trong trunk (tổ tiên hoặc squash) hoặc PR MERGED vào trunk đúng tip đó
# Kèm: `worktree remove` gỡ được worktree mà khoá devkit-kept là của chính phiên gọi (phiên GeelyEx2 18/10 phải unlock tay), và
# `finish` sau khi PR được squash trên GitHub đồng bộ main về origin thay vì gộp commit gốc (yêu cầu qua phiên GeelyEx2 18/10).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
SLEEPER=""
trap '[ -n "$SLEEPER" ] && kill "$SLEEPER" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

R="$TMP/rd"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
G "$R" config devkit.trunkMode true
printf 'a1\n' > a.txt; printf 'b\n' > b.txt; mkdir -p d && printf 'c\n' > d/c.txt
G "$R" add -A && G "$R" commit -qm init
OLD=$(G "$R" rev-parse HEAD)
printf 'a2\n' > a.txt; G "$R" commit -qam a2
has_branch() { G "$R" show-ref --verify --quiet "refs/heads/$1"; }
registered() { G "$R" worktree list --porcelain | grep -qx "worktree $(cd "$1" 2>/dev/null && pwd -P || echo "$1")"; }
mk() { bash "$KIT" worktree add "../$1" ${2:+"$2"} >/dev/null 2>&1 || fail "add $1"; }
sleep 300 & SLEEPER=$!; disown "$SLEEPER" 2>/dev/null

# --- discard (a) ---------------------------------------------------------------------------------------------------------
# a1. chỉ toàn file đã xoá (` D`, `D `), HEAD là trunk: gỡ được
mk w-del; rm "$TMP/w-del/b.txt"; G "$TMP/w-del" rm -q d/c.txt
bash "$KIT" worktree discard ../w-del >"$TMP/a1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-del" ] && ok "a1 discard: a worktree with only deleted files is removed" \
  || { fail "a1 discard of a deletions-only worktree (rc=$rc)"; cat "$TMP/a1.out"; }

# a13. (review 18/10) *.csproj / *.sln chỉ là rác khi repo là project Unity: repo thường thì đó là file thật, từ chối
mk w-cs; echo x > "$TMP/w-cs/App.csproj"; rm "$TMP/w-cs/b.txt"
bash "$KIT" worktree discard ../w-cs >"$TMP/a13.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -f "$TMP/w-cs/App.csproj" ] && ok "a13 discard refuses a *.csproj outside a Unity project (rc=$rc)" \
  || { fail "a13 discard dropped a *.csproj of a non-Unity repo (rc=$rc)"; cat "$TMP/a13.out"; }
mkdir -p "$R/ProjectSettings" && echo 'm_EditorVersion: 6000.0.1f1' > "$R/ProjectSettings/ProjectVersion.txt"
G "$R" add ProjectSettings && G "$R" commit -qm unity

# a2. rác IDE chưa track (.vscode/, *.slnx, *.sln, *.csproj của project Unity) + một file đã xoá: gỡ được
mk w-ide; mkdir -p "$TMP/w-ide/.vscode"; echo '{}' > "$TMP/w-ide/.vscode/settings.json"
echo x > "$TMP/w-ide/w-ide.slnx"; echo x > "$TMP/w-ide/App.csproj"; rm "$TMP/w-ide/b.txt"
bash "$KIT" worktree discard ../w-ide >"$TMP/a2.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-ide" ] && ok "a2 discard: untracked IDE junk + deletions is removed" \
  || { fail "a2 discard of IDE junk (rc=$rc)"; cat "$TMP/a2.out"; }

# a10. (review 18/10) một repo git lồng chưa track nằm trong thư mục rác IDE (.vscode/x/.git): git chỉ ghi một gitlink, object của nó mất
#      cùng thư mục — không phải rác, từ chối
mk w-nest; mkdir -p "$TMP/w-nest/.vscode/x" && G "$TMP/w-nest/.vscode/x" init -q . && echo n > "$TMP/w-nest/.vscode/x/n.txt" \
  && G "$TMP/w-nest/.vscode/x" add n.txt && G "$TMP/w-nest/.vscode/x" commit -qm n; rm "$TMP/w-nest/b.txt"
bash "$KIT" worktree discard ../w-nest >"$TMP/a10.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -d "$TMP/w-nest/.vscode/x/.git" ] && ok "a10 discard refuses an untracked nested git repo inside IDE junk (rc=$rc)" \
  || { fail "a10 discard dropped a nested git repo (rc=$rc)"; cat "$TMP/a10.out"; }

# a11. (audit T0044) *.csproj mới đã `git add` (index giữ nó, HEAD chưa có): không phải rác chưa track, từ chối
mk w-csadd; echo x > "$TMP/w-csadd/New.csproj"; G "$TMP/w-csadd" add New.csproj; rm "$TMP/w-csadd/b.txt"
bash "$KIT" worktree discard ../w-csadd >"$TMP/a11.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -f "$TMP/w-csadd/New.csproj" ] && ok "a11 discard refuses a staged *.csproj (rc=$rc)" \
  || { fail "a11 discard dropped a staged *.csproj (rc=$rc)"; cat "$TMP/a11.out"; }

# a12. (review 18/10) state của worktree ghi một phiên KHÁC còn sống (registry có pid trả lời): từ chối dù chỉ có file xoá
bash "$KIT" worktree add ../w-owned --session=other-live >/dev/null 2>&1 || fail "add w-owned"
mkdir -p "$R/.git/devkit-sessions"
printf '{"session_id":"other-live","pid":%s,"heartbeat":%s,"status":"working"}\n' "$SLEEPER" "$(date +%s)" > "$R/.git/devkit-sessions/other-live.json"
rm -f "$TMP/w-owned/b.txt"
bash "$KIT" worktree discard ../w-owned >"$TMP/a12.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-owned" ] && ok "a12 discard refuses a worktree whose owner session is alive (rc=$rc)" \
  || { fail "a12 discard took a live session's worktree (rc=$rc)"; cat "$TMP/a12.out"; }
rm -f "$R/.git/devkit-sessions/other-live.json"
# a12b. (review 18/10) phiên chủ không có pid ở đâu cả (chưa đăng ký) và worktree mới dựng: không chứng minh được nó đã dừng — từ chối
bash "$KIT" worktree add ../w-unk --session=other-unknown >/dev/null 2>&1 || fail "add w-unk"
rm -f "$TMP/w-unk/b.txt"
bash "$KIT" worktree discard ../w-unk >"$TMP/a12b.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-unk" ] && ok "a12b discard refuses a young worktree whose owner cannot be proven gone (rc=$rc)" \
  || { fail "a12b discard took a worktree of an owner not proven gone (rc=$rc)"; cat "$TMP/a12b.out"; }
# a12c. (review 18/10) khoá checkout của một phiên đang rảnh ở prompt (idle_since) vẫn là phiên sống — từ chối
mk w-idle; rm -f "$TMP/w-idle/b.txt"; GD=$(G "$TMP/w-idle" rev-parse --absolute-git-dir)
printf '{"session_id":"idle-one","pid":%s,"heartbeat":%s,"idle_since":%s,"gitdir":"%s"}\n' "$SLEEPER" "$(date +%s)" "$(date +%s)" "$GD" > "$GD/devkit-session.lock"
bash "$KIT" worktree discard ../w-idle >"$TMP/a12c.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-idle" ] && ok "a12c discard refuses a worktree whose checkout lock holder is idle but alive (rc=$rc)" \
  || { fail "a12c discard took an idle live session's worktree (rc=$rc)"; cat "$TMP/a12c.out"; }

# a3. file sửa chưa commit: từ chối, file còn nguyên
mk w-mod; echo mine > "$TMP/w-mod/a.txt"
bash "$KIT" worktree discard ../w-mod >"$TMP/a3.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$TMP/w-mod/a.txt" 2>/dev/null)" = mine ] && ok "a3 discard refuses an uncommitted edit (rc=$rc)" \
  || { fail "a3 discard dropped an uncommitted edit (rc=$rc)"; cat "$TMP/a3.out"; }

# a4. file thật chưa track: từ chối
mk w-new; echo note > "$TMP/w-new/notes.txt"
bash "$KIT" worktree discard ../w-new >"$TMP/a4.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -f "$TMP/w-new/notes.txt" ] && ok "a4 discard refuses an untracked real file (rc=$rc)" \
  || { fail "a4 discard dropped an untracked file (rc=$rc)"; cat "$TMP/a4.out"; }

# a5. commit chưa có trong trunk (status chỉ còn file xoá): từ chối, commit không mất
mk w-ahead; echo e > "$TMP/w-ahead/e.txt"; G "$TMP/w-ahead" add e.txt && G "$TMP/w-ahead" commit -qm e; rm "$TMP/w-ahead/b.txt"
bash "$KIT" worktree discard ../w-ahead >"$TMP/a5.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-ahead" ] && ok "a5 discard refuses a commit trunk does not hold (rc=$rc)" \
  || { fail "a5 discard dropped an unmerged commit (rc=$rc)"; cat "$TMP/a5.out"; }

# a6. nhánh đã gộp bằng squash (commit không phải tổ tiên, nội dung đã có ở main) + chỉ file xoá: gỡ được
mk w-sq; DEVKIT_ALLOW_BRANCH=1 G "$TMP/w-sq" switch -q -c feat/sq
echo s > "$TMP/w-sq/s.txt"; G "$TMP/w-sq" add s.txt && G "$TMP/w-sq" commit -qm s
echo s > "$R/s.txt"; G "$R" add s.txt && G "$R" commit -qm "s (squash)"; rm "$TMP/w-sq/b.txt"
bash "$KIT" worktree discard ../w-sq >"$TMP/a6.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-sq" ] && ! has_branch feat/sq && ok "a6 discard: squash-merged worktree with deletions is removed, its branch too" \
  || { fail "a6 discard of a squash-merged worktree (rc=$rc)"; cat "$TMP/a6.out"; }

# a6b. (audit T0044) nhánh có tên mang commit trunk CHƯA có (không phải detached nên `remove` không coi là unreachable) + chỉ file xoá:
#      discard chỉ gỡ khi HEAD đã nằm trong trunk — từ chối
mk w-br; DEVKIT_ALLOW_BRANCH=1 G "$TMP/w-br" switch -q -c feat/br
echo u > "$TMP/w-br/u.txt"; G "$TMP/w-br" add u.txt && G "$TMP/w-br" commit -qm u; rm "$TMP/w-br/b.txt"
bash "$KIT" worktree discard ../w-br >"$TMP/a6b.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-br" ] && ok "a6b discard refuses a named branch whose HEAD the trunk lacks (rc=$rc)" \
  || { fail "a6b discard of an unmerged named branch (rc=$rc)"; cat "$TMP/a6b.out"; }

# a7. khoá devkit-kept của một phiên KHÁC còn sống: từ chối dù chỉ có file xoá
mk w-other; rm "$TMP/w-other/b.txt"; G "$R" worktree lock --reason "devkit-kept session=other pid=$SLEEPER" "$TMP/w-other"
bash "$KIT" worktree discard ../w-other >"$TMP/a7.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-other" ] && ok "a7 discard refuses a worktree another live session keeps (rc=$rc)" \
  || { fail "a7 discard took another live session's worktree (rc=$rc)"; cat "$TMP/a7.out"; }

# a9. (OCR r2) file mới đã stage rồi xoá khỏi đĩa (`AD`): nội dung chỉ còn trong index — không phải "file đã xoá", từ chối
mk w-ad; echo staged > "$TMP/w-ad/new.txt"; G "$TMP/w-ad" add new.txt; rm "$TMP/w-ad/new.txt"
bash "$KIT" worktree discard ../w-ad >"$TMP/a9.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-ad" ] && ok "a9 discard refuses a staged file deleted from disk (AD) (rc=$rc)" \
  || { fail "a9 discard dropped a blob only the index held (rc=$rc)"; cat "$TMP/a9.out"; }

# a8. main checkout: từ chối
bash "$KIT" worktree discard "$R" >"$TMP/a8.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -f "$R/a.txt" ] && ok "a8 discard refuses the main checkout (rc=$rc)" || { fail "a8 discard on main (rc=$rc)"; cat "$TMP/a8.out"; }

# --- discard: không còn chế độ "worktree của chính phiên" (review 18/10: bỏ để an toàn) ---------------------------------------------
# b1. khoá devkit-kept với pid = shell của test (tổ tiên của lệnh kit), sửa chưa commit: discard từ chối như mọi worktree có sửa
#     (worktree của chính phiên đi qua `remove` / `finish`, không qua discard)
mk w-own; echo own > "$TMP/w-own/a.txt"
G "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$TMP/w-own"
bash "$KIT" worktree discard ../w-own >"$TMP/b1.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$TMP/w-own/a.txt" 2>/dev/null)" = own ] && ok "b1 discard no longer drops the caller's own uncommitted edit (rc=$rc)" \
  || { fail "b1 discard dropped an uncommitted edit of the caller's own worktree (rc=$rc)"; cat "$TMP/b1.out"; }
# b3. bản cất của ca (a) giữ HEAD và cây làm việc: file đã xoá vẫn đọc được theo HEAD (cha của bản cất)
REF=$(G "$R" for-each-ref --format='%(refname)' 'refs/devkit/discarded/w-del-*' | head -1)
[ -n "$REF" ] && [ "$(G "$R" show "$REF^:b.txt" 2>/dev/null)" = b ] && ! G "$R" cat-file -e "$REF:b.txt" 2>/dev/null \
  && ok "b3 a discard backup ($REF) keeps HEAD as its parent and the working tree as its tree" \
  || fail "b3 discard backup of a1 (ref='$REF')"

# --- remove: khoá devkit-kept của chính phiên gọi ---------------------------------------------------------------------------
mk w-keep; G "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$TMP/w-keep"
bash "$KIT" worktree remove ../w-keep >"$TMP/k1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-keep" ] && ok "k1 remove: the caller's own devkit-kept lock no longer blocks it" \
  || { fail "k1 remove refused the caller's own kept worktree (rc=$rc)"; cat "$TMP/k1.out"; }
mk w-keep2; G "$R" worktree lock --reason "devkit-kept session=other pid=$SLEEPER" "$TMP/w-keep2"
bash "$KIT" worktree remove ../w-keep2 >"$TMP/k2.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-keep2" ] && ok "k2 remove still refuses a worktree another live session keeps (rc=$rc)" \
  || { fail "k2 remove took another live session's kept worktree (rc=$rc)"; cat "$TMP/k2.out"; }
# k3. (review 18/10) remove xoá nhánh đã nằm trong main: commit CHỈ reflog của nhánh còn giữ (nhánh bị dời qua rồi dời về từ main checkout)
#     phải được cất vào refs/devkit/discarded trước khi reflog đó mất cùng nhánh
G "$R" branch k-lone HEAD; mk w-kl k-lone
KL=$(echo kl | G "$R" commit-tree "$(G "$R" rev-parse 'HEAD^{tree}')" -p HEAD)
G "$R" update-ref -m away refs/heads/k-lone "$KL"; G "$R" update-ref -m back refs/heads/k-lone "$(G "$R" rev-parse HEAD)"
bash "$KIT" worktree remove ../w-kl >"$TMP/k3.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ! has_branch k-lone && G "$R" for-each-ref --format='%(objectname)' 'refs/devkit/discarded/' | while read -r o; do G "$R" rev-list "$o"; done | grep -qx "$KL" \
  && ok "k3 remove deletes a merged branch only after keeping a commit only its reflog named" \
  || { fail "k3 remove lost a branch-reflog-only commit (rc=$rc)"; cat "$TMP/k3.out"; }
# k4. (audit T0044) remove mở khoá devkit-kept của chính phiên rồi `git worktree remove` bị từ chối: khoá phải được đặt lại
REALGIT=$(command -v git); SHIM="$TMP/shimgit"; mkdir -p "$SHIM"
printf '#!/bin/sh\ncase " $* " in *" worktree remove "*) echo "fatal: shim refuses" >&2; exit 1;; esac\nexec %s "$@"\n' "$REALGIT" > "$SHIM/git"; chmod +x "$SHIM/git"
mk w-relock; G "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$TMP/w-relock"
PATH="$SHIM:$PATH" bash "$KIT" worktree remove ../w-relock >"$TMP/k4.out" 2>&1; rc=$?
[ "$rc" != 0 ] && G "$R" worktree list --porcelain | grep -A4 "w-relock" | grep -q "^locked devkit-kept session=me pid=$$" \
  && ok "k4 a refused removal puts the caller's devkit-kept lock back (rc=$rc)" \
  || { fail "k4 refused removal left the worktree unlocked (rc=$rc)"; cat "$TMP/k4.out"; G "$R" worktree list --porcelain | grep -A4 w-relock; }
# k5. khoá mang pid của tiến trình NẰM TRÊN `claude` (app Claude, terminal: mọi phiên dùng chung) không phải "của mình".
#     Chỉ chạy được khi test chạy dưới một phiên Claude Code; ngoài đó không có tầng chung để thử.
p=$$; ABOVE=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  line=$(ps -ww -o ppid=,comm= -p "$p" 2>/dev/null) || break
  pp=$(echo "$line" | awk '{print $1}'); cm=$(echo "$line" | cut -d' ' -f2- | sed 's/^ *//')
  if [ "$(basename "$cm")" = claude ]; then ABOVE="$pp"; break; fi
  [ -z "$pp" ] || [ "$pp" -le 1 ] && break; p="$pp"
done
if [ -n "$ABOVE" ] && [ "$ABOVE" -gt 1 ]; then
  mk w-shared; G "$R" worktree lock --reason "devkit-kept session=other pid=$ABOVE" "$TMP/w-shared"
  bash "$KIT" worktree remove ../w-shared >"$TMP/k5.out" 2>&1; rc=$?
  [ "$rc" != 0 ] && [ -e "$TMP/w-shared" ] && ok "k5 a lock naming a process above claude (shared by every session) is not the caller's own (rc=$rc)" \
    || { fail "k5 remove took a worktree locked by a shared ancestor (rc=$rc)"; cat "$TMP/k5.out"; }
else
  echo "• k5 skipped: not running under a Claude Code session"
fi

# --- restore -----------------------------------------------------------------------------------------------------------------
mk w-rs
( cd "$TMP/w-rs" && bash "$KIT" worktree restore "$OLD" -- a.txt ) >"$TMP/r1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$TMP/w-rs/a.txt")" = a1 ] && ok "r1 restore puts a clean path back to the given commit" \
  || { fail "r1 restore (rc=$rc)"; cat "$TMP/r1.out"; }
G "$TMP/w-rs" checkout -q -- a.txt 2>/dev/null; echo edit > "$TMP/w-rs/b.txt"
( cd "$TMP/w-rs" && bash "$KIT" worktree restore "$OLD" -- b.txt ) >"$TMP/r2.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$TMP/w-rs/b.txt")" = edit ] && ok "r2 restore refuses a path with an uncommitted edit (rc=$rc)" \
  || { fail "r2 restore overwrote an uncommitted edit (rc=$rc)"; cat "$TMP/r2.out"; }
mkdir -p "$TMP/w-rs/d"; echo u > "$TMP/w-rs/d/untracked.txt"
( cd "$TMP/w-rs" && bash "$KIT" worktree restore "$OLD" -- d ) >"$TMP/r3.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -f "$TMP/w-rs/d/untracked.txt" ] && ok "r3 restore refuses a path holding an untracked file (rc=$rc)" \
  || { fail "r3 restore over an untracked file (rc=$rc)"; cat "$TMP/r3.out"; }
# r6. (OCR r2) thay đổi đã stage, file trên đĩa trả về đúng HEAD: index vẫn giữ bản stage — từ chối
rm -rf "$TMP/w-rs/d/untracked.txt"; echo staged > "$TMP/w-rs/b.txt"; G "$TMP/w-rs" add b.txt; printf 'b\n' > "$TMP/w-rs/b.txt"
( cd "$TMP/w-rs" && bash "$KIT" worktree restore "$OLD" -- b.txt ) >"$TMP/r6.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(G "$TMP/w-rs" show :b.txt)" = staged ] && ok "r6 restore refuses a path whose index holds a staged change (rc=$rc)" \
  || { fail "r6 restore overwrote a staged change (rc=$rc)"; cat "$TMP/r6.out"; }
( cd "$R" && bash "$KIT" worktree restore "$OLD" -- a.txt ) >"$TMP/r4.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$R/a.txt")" = a2 ] && ok "r4 restore refuses the trunk-mode main checkout (rc=$rc)" \
  || { fail "r4 restore wrote main (rc=$rc)"; cat "$TMP/r4.out"; }
( cd "$TMP/w-rs" && bash "$KIT" worktree restore nosuchsha -- a.txt ) >"$TMP/r5.out" 2>&1; rc=$?
[ "$rc" != 0 ] && ok "r5 restore refuses an unknown commit (rc=$rc)" || { fail "r5 restore of a bad sha (rc=$rc)"; cat "$TMP/r5.out"; }
# r7–r10 (review + audit T0044, 18/10): repo riêng, không trunk mode (restore chạy ở checkout chính). `git checkout <c> -- <path>`
# lặng lẽ xoá file bị ignore đứng ở đường dẫn CHA của file commit mang (cfg ↔ cfg/a.txt) hoặc thư mục ignore ở chỗ một file (foo/ ↔ foo)
R2="$TMP/r2"; mkdir -p "$R2" && G "$R2" init -q -b main . && G "$R2" config devkit.trunkMode false
mkdir -p "$R2/cfg" "$R2/sub"; echo a > "$R2/cfg/a.txt"; echo f > "$R2/foo"; echo s1 > "$R2/sub/s.txt"; echo h1 > "$R2/h.txt"
G "$R2" add -A && G "$R2" commit -qm old; OLD2=$(G "$R2" rev-parse HEAD)
G "$R2" rm -rq cfg foo; printf 'cfg\nfoo/\n' > "$R2/.gitignore"; echo s2 > "$R2/sub/s.txt"; echo h2 > "$R2/h.txt"
G "$R2" add -A && G "$R2" commit -qm new
echo SECRET > "$R2/cfg"; mkdir -p "$R2/foo"; echo key > "$R2/foo/secret.key"
( cd "$R2" && bash "$KIT" worktree restore "$OLD2" -- cfg/a.txt ) >"$TMP/r7.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$R2/cfg" 2>/dev/null)" = SECRET ] && ok "r7 restore refuses when an ignored FILE stands where the commit has a folder (rc=$rc)" \
  || { fail "r7 restore overwrote an ignored file at a parent path (rc=$rc)"; cat "$TMP/r7.out"; }
( cd "$R2" && bash "$KIT" worktree restore "$OLD2" -- foo ) >"$TMP/r8.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$R2/foo/secret.key" 2>/dev/null)" = key ] && ok "r8 restore refuses when an ignored FOLDER stands where the commit has a file (rc=$rc)" \
  || { fail "r8 restore deleted an ignored folder (rc=$rc)"; cat "$TMP/r8.out"; }
G "$R2" update-index --skip-worktree h.txt; echo mine > "$R2/h.txt"
( cd "$R2" && bash "$KIT" worktree restore "$OLD2" -- h.txt ) >"$TMP/r9.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$R2/h.txt")" = mine ] && ok "r9 restore refuses a path git hides with skip-worktree that holds an edit (rc=$rc)" \
  || { fail "r9 restore overwrote a skip-worktree edit (rc=$rc)"; cat "$TMP/r9.out"; }
( cd "$R2/sub" && bash "$KIT" worktree restore "$OLD2" -- "" ) >"$TMP/r10.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$R2/sub/s.txt")" = s2 ] && ok "r10 restore refuses an empty path (git reads it as the whole folder) (rc=$rc)" \
  || { fail "r10 restore of an empty path (rc=$rc)"; cat "$TMP/r10.out"; }
( cd "$R2/sub" && bash "$KIT" worktree restore "$OLD2" -- s.txt ) >"$TMP/r11.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$R2/sub/s.txt")" = s1 ] && ok "r11 restore from a subfolder takes paths relative to it" \
  || { fail "r11 restore from a subfolder (rc=$rc)"; cat "$TMP/r11.out"; }

# --- prune-branch --------------------------------------------------------------------------------------------------------------
G "$R" branch p-anc HEAD~1
bash "$KIT" worktree prune-branch p-anc >"$TMP/p1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ! has_branch p-anc && ok "p1 prune-branch deletes a branch trunk contains" || { fail "p1 prune-branch (rc=$rc)"; cat "$TMP/p1.out"; }
# p4. nhánh đã nằm trong trunk nhưng một worktree đang checkout nó: từ chối (chỉ vì lý do đó)
G "$R" branch p-co HEAD~1; mk w-pco p-co
bash "$KIT" worktree prune-branch p-co >"$TMP/p4.out" 2>&1; rc=$?
[ "$rc" != 0 ] && has_branch p-co && ok "p4 prune-branch refuses a branch a worktree has checked out (rc=$rc)" \
  || { fail "p4 prune-branch of a checked-out branch (rc=$rc)"; cat "$TMP/p4.out"; }
G "$R" worktree remove "$TMP/w-pco" >/dev/null 2>&1
G "$R" branch p-sq HEAD~1; mk w-psq p-sq; echo q > "$TMP/w-psq/q.txt"; G "$TMP/w-psq" add q.txt && G "$TMP/w-psq" commit -qm q
G "$R" worktree remove "$TMP/w-psq" >/dev/null 2>&1
echo q > "$R/q.txt"; G "$R" add q.txt && G "$R" commit -qm "q (squash)"
bash "$KIT" worktree prune-branch p-sq >"$TMP/p2.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ! has_branch p-sq && ok "p2 prune-branch deletes a squash-merged branch" || { fail "p2 prune-branch squash (rc=$rc)"; cat "$TMP/p2.out"; }
G "$R" branch p-new HEAD; mk w-pn p-new; echo n > "$TMP/w-pn/n.txt"; G "$TMP/w-pn" add n.txt && G "$TMP/w-pn" commit -qm n
G "$R" worktree remove "$TMP/w-pn" >/dev/null 2>&1
PATH_NOGH="$TMP/nogh"; mkdir -p "$PATH_NOGH"; printf '#!/bin/sh\nexit 1\n' > "$PATH_NOGH/gh"; chmod +x "$PATH_NOGH/gh"
PATH="$PATH_NOGH:$PATH" bash "$KIT" worktree prune-branch p-new >"$TMP/p3.out" 2>&1; rc=$?
[ "$rc" != 0 ] && has_branch p-new && ok "p3 prune-branch keeps a branch with a commit trunk lacks (rc=$rc)" \
  || { fail "p3 prune-branch deleted an unmerged branch (rc=$rc)"; cat "$TMP/p3.out"; }
TIP=$(G "$R" rev-parse refs/heads/p-new)
FAKE="$TMP/fakegh"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho %s\n' "'[{\"number\":7,\"headRefOid\":\"$TIP\",\"baseRefName\":\"main\",\"isCrossRepository\":false}]'" > "$FAKE/gh"; chmod +x "$FAKE/gh"
PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch p-new >"$TMP/p6.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ! has_branch p-new && ok "p6 prune-branch deletes a branch whose PR merged at this very tip" \
  || { fail "p6 prune-branch with a merged PR (rc=$rc)"; cat "$TMP/p6.out"; }
G "$R" branch p-moved HEAD; mk w-pm p-moved; echo m > "$TMP/w-pm/m.txt"; G "$TMP/w-pm" add m.txt && G "$TMP/w-pm" commit -qm m
G "$R" worktree remove "$TMP/w-pm" >/dev/null 2>&1
printf '#!/bin/sh\necho %s\n' "'[{\"number\":8,\"headRefOid\":\"0000000000000000000000000000000000000000\",\"baseRefName\":\"main\",\"isCrossRepository\":false}]'" > "$FAKE/gh"
PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch p-moved >"$TMP/p7.out" 2>&1; rc=$?
[ "$rc" != 0 ] && has_branch p-moved && ok "p7 prune-branch keeps a branch that moved past its merged PR (rc=$rc)" \
  || { fail "p7 prune-branch deleted commits after the merged PR (rc=$rc)"; cat "$TMP/p7.out"; }
bash "$KIT" worktree prune-branch main >"$TMP/p5.out" 2>&1; rc=$?
[ "$rc" != 0 ] && has_branch main && ok "p5 prune-branch refuses the trunk branch (rc=$rc)" || { fail "p5 prune-branch main (rc=$rc)"; cat "$TMP/p5.out"; }
# p8. (review 18/10) nhánh đã nằm trong trunk, nhưng reflog của nó còn một commit không ref nào giữ (commit rồi reset về): xoá nhánh là
#     xoá reflog đó — commit phải được cất vào refs/devkit/discarded trước
G "$R" branch p-lone HEAD~1
PL=$(echo pl | G "$R" commit-tree "$(G "$R" rev-parse 'HEAD~1^{tree}')" -p HEAD~1)
G "$R" update-ref -m away refs/heads/p-lone "$PL"; G "$R" update-ref -m back refs/heads/p-lone "$(G "$R" rev-parse HEAD~1)"
bash "$KIT" worktree prune-branch p-lone >"$TMP/p8.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ! has_branch p-lone && G "$R" for-each-ref --format='%(objectname)' 'refs/devkit/discarded/' | while read -r o; do G "$R" rev-list "$o"; done | grep -qx "$PL" \
  && ok "p8 prune-branch keeps a commit only the branch reflog named before deleting it" \
  || { fail "p8 prune-branch lost a branch-reflog-only commit (rc=$rc)"; cat "$TMP/p8.out"; }
# p9. (review + audit T0044) PR MERGED đúng tip nhưng vào một nhánh KHÁC trunk (feat/parent): chưa vào trunk, giữ
G "$R" branch p-sub HEAD; mk w-ps p-sub; echo ps > "$TMP/w-ps/ps.txt"; G "$TMP/w-ps" add ps.txt && G "$TMP/w-ps" commit -qm ps
G "$R" worktree remove "$TMP/w-ps" >/dev/null 2>&1
TIP9=$(G "$R" rev-parse refs/heads/p-sub)
printf '#!/bin/sh\necho %s\n' "'[{\"number\":9,\"headRefOid\":\"$TIP9\",\"baseRefName\":\"feat/parent\",\"isCrossRepository\":false}]'" > "$FAKE/gh"
PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch p-sub >"$TMP/p9.out" 2>&1; rc=$?
[ "$rc" != 0 ] && has_branch p-sub && ok "p9 prune-branch keeps a branch whose PR merged into another branch than the trunk (rc=$rc)" \
  || { fail "p9 prune-branch deleted a branch merged only into feat/parent (rc=$rc)"; cat "$TMP/p9.out"; }

# --- gc: bản cất của discard sống 30 ngày ----------------------------------------------------------------------------------------
G "$R" update-ref refs/devkit/discarded/old-20200101-000000 HEAD
bash "$KIT" worktree gc >"$TMP/g1.out" 2>&1
! G "$R" show-ref --verify --quiet refs/devkit/discarded/old-20200101-000000 && [ -n "$REF" ] && G "$R" show-ref --verify --quiet "$REF" \
  && ok "g1 gc drops a discard backup older than 30 days and keeps a fresh one" \
  || { fail "g1 gc and discard backups"; cat "$TMP/g1.out"; }

# --- origin: PR được squash trên GitHub (yêu cầu qua phiên GeelyEx2, 18/10) ------------------------------------------------------------
# finish / remove không được đưa commit GỐC của PR vào main local (main lệch origin mãi, INSTINCT-047): main đồng bộ về origin/<trunk>
# (ff, hoặc reset --keep khi gộp main vào origin không thêm gì); không đồng bộ được thì từ chối, main giữ nguyên.
O3="$TMP/o3.git"; R3="$TMP/r3"; C3="$TMP/c3"
G "$TMP" init -q --bare -b main "$O3"; mkdir -p "$R3" && G "$R3" init -q -b main . && G "$R3" config devkit.trunkMode true
echo base > "$R3/base.txt"; G "$R3" add -A && G "$R3" commit -qm base && G "$R3" remote add origin "$O3" && G "$R3" push -q origin main 2>/dev/null
G "$TMP" clone -q "$O3" "$C3" 2>/dev/null
squash() {   # squash <file> <content>: GitHub gộp PR thành MỘT commit mới trên origin/main
  G "$C3" pull -q --ff-only origin main 2>/dev/null; echo "$2" > "$C3/$1"; G "$C3" add -A && G "$C3" commit -qm "$1 (squash #PR)" && G "$C3" push -q origin main 2>/dev/null
  G "$R3" fetch -q --prune origin 2>/dev/null
}
# s1. worktree detached, commit của nó đã squash lên origin, main local ở sau: finish đưa main về đúng origin/main, không mang commit gốc
( cd "$R3" && bash "$KIT" worktree add ../w-s1 ) >/dev/null 2>&1 || fail "add w-s1"
echo s1 > "$TMP/w-s1/s1.txt"; G "$TMP/w-s1" add s1.txt && G "$TMP/w-s1" commit -qm s1; S1ORIG=$(G "$TMP/w-s1" rev-parse HEAD)
squash s1.txt s1
( cd "$R3" && bash "$KIT" worktree finish ../w-s1 ) >"$TMP/s1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(G "$R3" rev-parse main)" = "$(G "$R3" rev-parse origin/main)" ] && ! G "$R3" merge-base --is-ancestor "$S1ORIG" main && [ ! -e "$TMP/w-s1" ] \
  && ok "s1 finish after a squash on origin moves main to origin/main and drops the worktree, without the PR's own commit" \
  || { fail "s1 finish after a squash (rc=$rc)"; cat "$TMP/s1.out"; G "$R3" log --oneline -5 main; }
# s2. worktree ở nhánh đã PUBLISH (upstream), PR squash rồi nhánh remote bị xoá: finish không còn từ chối mãi; main = origin, nhánh local xoá
( cd "$R3" && bash "$KIT" worktree add ../w-s2 feat/p ) >/dev/null 2>&1 || fail "add w-s2"
echo p > "$TMP/w-s2/p.txt"; G "$TMP/w-s2" add p.txt && G "$TMP/w-s2" commit -qm p && G "$TMP/w-s2" push -q -u origin feat/p 2>/dev/null
squash p.txt p; G "$C3" push -q origin --delete feat/p 2>/dev/null; G "$R3" fetch -q --prune origin 2>/dev/null
( cd "$R3" && bash "$KIT" worktree finish ../w-s2 ) >"$TMP/s2.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(G "$R3" rev-parse main)" = "$(G "$R3" rev-parse origin/main)" ] && [ ! -e "$TMP/w-s2" ] && ! G "$R3" show-ref --verify --quiet refs/heads/feat/p \
  && ok "s2 finish of a published branch whose PR was squash-merged syncs main and deletes the branch" \
  || { fail "s2 finish of a squash-merged published branch (rc=$rc)"; cat "$TMP/s2.out"; }
# s3. như s1 nhưng main local có commit origin chưa có: không đồng bộ được — từ chối, main giữ nguyên, không có commit gốc của PR
( cd "$R3" && bash "$KIT" worktree add ../w-s3 ) >/dev/null 2>&1 || fail "add w-s3"
echo s3 > "$TMP/w-s3/s3.txt"; G "$TMP/w-s3" add s3.txt && G "$TMP/w-s3" commit -qm s3; S3ORIG=$(G "$TMP/w-s3" rev-parse HEAD)
echo l > "$R3/l.txt"; G "$R3" add l.txt && G "$R3" commit -qm local; L3=$(G "$R3" rev-parse main)
squash s3.txt s3
( cd "$R3" && bash "$KIT" worktree finish ../w-s3 ) >"$TMP/s3.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(G "$R3" rev-parse main)" = "$L3" ] && [ -e "$TMP/w-s3" ] \
  && ok "s3 finish refuses when main holds a commit origin lacks: main untouched, the PR's own commit not merged (rc=$rc)" \
  || { fail "s3 finish merged the squashed PR's own commit into a diverged main (rc=$rc)"; cat "$TMP/s3.out"; G "$R3" log --oneline -5 main; }
# p10. prune-branch --remote: PR MERGED vào trunk đúng tip của nhánh REMOTE: xoá cả nhánh local lẫn nhánh trên origin
G "$R3" branch r-done "$L3"; G "$R3" push -q origin r-done 2>/dev/null; TIPR=$(G "$R3" rev-parse r-done)
printf '#!/bin/sh\necho %s\n' "'[{\"number\":10,\"headRefOid\":\"$TIPR\",\"baseRefName\":\"main\",\"isCrossRepository\":false}]'" > "$FAKE/gh"
( cd "$R3" && PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch --remote r-done ) >"$TMP/p10.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ! G "$R3" show-ref --verify --quiet refs/heads/r-done && [ -z "$(G "$R3" ls-remote origin refs/heads/r-done)" ] \
  && ok "p10 prune-branch --remote deletes the local and the origin branch of a PR merged at that tip" \
  || { fail "p10 prune-branch --remote (rc=$rc)"; cat "$TMP/p10.out"; }
# p11. nhánh remote đã đi tiếp sau lần gộp (một commit mới trên origin): không xoá gì, cả local
G "$R3" branch r-moved "$L3"; G "$R3" push -q origin r-moved 2>/dev/null; TIPM=$(G "$R3" rev-parse r-moved)
G "$C3" fetch -q origin r-moved 2>/dev/null; G "$C3" checkout -q -B r-moved FETCH_HEAD 2>/dev/null; echo m2 > "$C3/m2.txt"
G "$C3" add m2.txt && G "$C3" commit -qm m2 && G "$C3" push -q origin r-moved 2>/dev/null; G "$C3" checkout -q main 2>/dev/null
printf '#!/bin/sh\necho %s\n' "'[{\"number\":11,\"headRefOid\":\"$TIPM\",\"baseRefName\":\"main\",\"isCrossRepository\":false}]'" > "$FAKE/gh"
( cd "$R3" && PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch --remote r-moved ) >"$TMP/p11.out" 2>&1; rc=$?
[ "$rc" != 0 ] && G "$R3" show-ref --verify --quiet refs/heads/r-moved && [ -n "$(G "$R3" ls-remote origin refs/heads/r-moved)" ] \
  && ok "p11 prune-branch --remote keeps both when the origin branch moved past the merged PR (rc=$rc)" \
  || { fail "p11 prune-branch --remote deleted a branch that moved on (rc=$rc)"; cat "$TMP/p11.out"; }
# p12. (OCR 18/10) `git push --delete` bị từ chối (mạng, quyền, lease): không xoá gì, cả nhánh local
G "$R3" branch r-fail "$L3"; G "$R3" push -q origin r-fail 2>/dev/null; TIPF=$(G "$R3" rev-parse r-fail)
printf '#!/bin/sh\necho %s\n' "'[{\"number\":12,\"headRefOid\":\"$TIPF\",\"baseRefName\":\"main\",\"isCrossRepository\":false}]'" > "$FAKE/gh"
printf '#!/bin/sh\ncase " $* " in *" push "*) echo "fatal: shim refuses push" >&2; exit 1;; esac\nexec %s "$@"\n' "$REALGIT" > "$SHIM/git"
( cd "$R3" && PATH="$SHIM:$FAKE:$PATH" bash "$KIT" worktree prune-branch --remote r-fail ) >"$TMP/p12.out" 2>&1; rc=$?
[ "$rc" != 0 ] && G "$R3" show-ref --verify --quiet refs/heads/r-fail && [ -n "$(G "$R3" ls-remote origin refs/heads/r-fail)" ] \
  && ok "p12 prune-branch --remote deletes nothing when the push is refused (rc=$rc)" \
  || { fail "p12 prune-branch --remote lost the local branch on a refused push (rc=$rc)"; cat "$TMP/p12.out"; }
# s5–s4 (OCR 18/10): nhánh `reset --keep` của việc đồng bộ. Commit riêng L3 của main nay cũng đã squash lên origin (l.txt): gộp main vào
# origin không thêm gì. s5: index của main có file phiên khác đã stage — reset sẽ làm nó rơi: từ chối, main giữ nguyên
squash l.txt l
echo st > "$R3/st.txt"; G "$R3" add st.txt
( cd "$R3" && bash "$KIT" worktree finish ../w-s3 ) >"$TMP/s5.out" 2>&1; rc=$?
G "$R3" diff --cached --quiet HEAD -- st.txt; s5=$?   # 1 = st.txt vẫn đang stage
[ "$rc" != 0 ] && [ "$(G "$R3" rev-parse main)" = "$L3" ] && [ "$s5" = 1 ] && ok "s5 the reset --keep sync refuses while main's index holds a staged file (rc=$rc)" \
  || { fail "s5 sync with a staged file in main (rc=$rc)"; cat "$TMP/s5.out"; }
G "$R3" rm -q --cached st.txt; rm -f "$R3/st.txt"
# s4. index sạch, một sửa CHƯA commit ở main trên file origin không đổi: reset --keep dời main về origin, giữ nguyên bản sửa; worktree gỡ
echo dirty > "$R3/base.txt"
( cd "$R3" && bash "$KIT" worktree finish ../w-s3 ) >"$TMP/s4.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(G "$R3" rev-parse main)" = "$(G "$R3" rev-parse origin/main)" ] && [ "$(cat "$R3/base.txt")" = dirty ] && [ ! -e "$TMP/w-s3" ] \
  && ! G "$R3" merge-base --is-ancestor "$S3ORIG" main \
  && ok "s4 a main whose own commits origin holds by content moves to origin/main by reset --keep, keeping an uncommitted edit" \
  || { fail "s4 reset --keep sync (rc=$rc)"; cat "$TMP/s4.out"; G "$R3" log --oneline -4 main; }
G "$R3" checkout -q -- base.txt 2>/dev/null
# s6. (OCR 18/10) nhánh đã publish, PR đã squash, nhưng worktree có regression_status.json do NGƯỜI sửa (việc thật): không coi là "chỉ còn
#     đồng bộ" — vẫn từ chối như mọi nhánh đã publish, không commit gì lên nhánh đó
( cd "$R3" && bash "$KIT" worktree add ../w-s6 feat/q ) >/dev/null 2>&1 || fail "add w-s6"
echo q > "$TMP/w-s6/q6.txt"; G "$TMP/w-s6" add q6.txt && G "$TMP/w-s6" commit -qm q6 && G "$TMP/w-s6" push -q -u origin feat/q 2>/dev/null
Q6=$(G "$TMP/w-s6" rev-parse HEAD); squash q6.txt q
mkdir -p "$TMP/w-s6/.agents"; echo 'not json' > "$TMP/w-s6/.agents/regression_status.json"
( cd "$R3" && bash "$KIT" worktree finish ../w-s6 ) >"$TMP/s6.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(G "$TMP/w-s6" rev-parse HEAD)" = "$Q6" ] && [ -e "$TMP/w-s6" ] \
  && ok "s6 a published branch with a person's regression_status.json edit is not synced away or committed to (rc=$rc)" \
  || { fail "s6 published branch with an authored status edit (rc=$rc)"; cat "$TMP/s6.out"; }
# s7–s9 (agent-workbench 18/10): main local giữ commit GỐC của một PR khác (#70: 06bb714..7897399) mà GitHub squash từ một head SAU đó
#     (99114f1 sửa tiếp cùng file): gộp main vào origin xung đột nên luật "không thêm gì" từ chối mãi, main lệch, repo symlink kit vào
#     main (GeelyEx2) không nhận PR mới. Commit thừa nằm trong danh sách commit của một PR MERGED vào trunk mà merge commit đã có trên
#     origin/<trunk> (gh) thì coi là đã tích hợp: main reset --keep về origin. Thiếu một commit, hay merge commit chưa có trên origin: từ chối.
G "$R3" pull -q --ff-only origin main 2>/dev/null
( cd "$R3" && bash "$KIT" worktree add ../w-s7 ) >/dev/null 2>&1 || fail "add w-s7"
echo s7 > "$TMP/w-s7/s7.txt"; G "$TMP/w-s7" add s7.txt && G "$TMP/w-s7" commit -qm s7
echo x1 > "$R3/x.txt"; G "$R3" add x.txt && G "$R3" commit -qm x1; X1=$(G "$R3" rev-parse HEAD)
echo x2 > "$R3/x.txt"; G "$R3" commit -qam x2; X2=$(G "$R3" rev-parse HEAD)
squash x.txt x3; XSQ=$(G "$R3" rev-parse origin/main)   # PR gộp từ head sau x2 (x3): nội dung khác main
squash s7.txt s7
X3=3333333333333333333333333333333333333333
FAKE7="$TMP/fakegh7"; mkdir -p "$FAKE7"
gh7() {   # gh7 <oid merge commit> <oid commit…>: một PR #70 MERGED vào $BASE7 (fork: $FORK7); chỉ trả lời câu tìm PR theo SHA, ghi lại lệnh
  local commits; commits=$(printf '{"oid":"%s"},' "${@:2}"); commits="[${commits%,}]"
  printf '#!/bin/sh\necho "$*" >> "%s"\ncase " $* " in *" pr list "*" --search "*) echo %s;; *) echo "[]";; esac\n' "$FAKE7/args" \
    "'[{\"number\":70,\"headRefOid\":\"$X3\",\"baseRefName\":\"$BASE7\",\"isCrossRepository\":$FORK7,\"mergeCommit\":{\"oid\":\"$1\"},\"commits\":$commits}]'" > "$FAKE7/gh"
  chmod +x "$FAKE7/gh"; : > "$FAKE7/args"
}
BASE7=main; FORK7=false
# s8. PR không chứa x2 (một commit riêng chưa đẩy của main): từ chối, main giữ nguyên
gh7 "$XSQ" "$X1" "$X3"
( cd "$R3" && PATH="$FAKE7:$PATH" bash "$KIT" worktree finish ../w-s7 ) >"$TMP/s8.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(G "$R3" rev-parse main)" = "$X2" ] && [ -e "$TMP/w-s7" ] \
  && ok "s8 finish refuses when one of main's extra commits belongs to no merged PR (rc=$rc)" \
  || { fail "s8 main synced away a commit no merged PR holds (rc=$rc)"; cat "$TMP/s8.out"; }
# s9. merge commit của PR chưa có trên origin/main local (fetch cũ): từ chối, main giữ nguyên
gh7 4444444444444444444444444444444444444444 "$X1" "$X2" "$X3"
( cd "$R3" && PATH="$FAKE7:$PATH" bash "$KIT" worktree finish ../w-s7 ) >"$TMP/s9.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(G "$R3" rev-parse main)" = "$X2" ] && [ -e "$TMP/w-s7" ] \
  && ok "s9 finish refuses when the merged PR's merge commit is not on the local origin/main (rc=$rc)" \
  || { fail "s9 main synced to an origin that lacks the PR's merge commit (rc=$rc)"; cat "$TMP/s9.out"; }
# s10–s12 (review 18/10): PR gộp vào nhánh khác trunk, PR từ fork, gh thoát khác 0 (dù in JSON) — đều từ chối, main giữ nguyên
for c in "s10 dev false PR merged into another branch" "s11 main true PR from a fork" "s12 main false gh fails"; do
  set -- $c; id=$1; BASE7=$2; FORK7=$3; gh7 "$XSQ" "$X1" "$X2" "$X3"; BASE7=main; FORK7=false
  [ "$id" = s12 ] && sed -i.bak 's/esac$/esac; exit 1/' "$FAKE7/gh"   # in đúng câu trả lời của s7 nhưng thoát 1: không tin
  ( cd "$R3" && PATH="$FAKE7:$PATH" bash "$KIT" worktree finish ../w-s7 ) >"$TMP/$id.out" 2>&1; rc=$?
  [ "$rc" != 0 ] && [ "$(G "$R3" rev-parse main)" = "$X2" ] && [ -e "$TMP/w-s7" ] && ok "$id finish refuses: ${c#* * * } (rc=$rc)" \
    || { fail "$id main synced on an untrusted PR answer (rc=$rc)"; cat "$TMP/$id.out"; }
done
# s7. mọi commit thừa của main nằm trong PR #70 đã merge, merge commit có trên origin: main về đúng origin/main, worktree gỡ
gh7 "$XSQ" "$X1" "$X2" "$X3"
( cd "$R3" && PATH="$FAKE7:$PATH" bash "$KIT" worktree finish ../w-s7 ) >"$TMP/s7.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(G "$R3" rev-parse main)" = "$(G "$R3" rev-parse origin/main)" ] && [ "$(cat "$R3/x.txt")" = x3 ] && [ ! -e "$TMP/w-s7" ] \
  && grep -q -- "--search $X2 " "$FAKE7/args" && grep -q -- "--base main " "$FAKE7/args" \
  && ok "s7 finish resets main to origin/main when its extra commits are the pre-squash commits of a merged PR" \
  || { fail "s7 finish with main holding a squash-merged PR's own commits (rc=$rc)"; cat "$TMP/s7.out"; G "$R3" log --oneline -4 main; }

# --- guard: dạng git trần vẫn bị chặn, và lời chặn chỉ sang đúng lệnh kit ---------------------------------------------------------
HOOK="$DEVKIT_DIR/hooks/block-dangerous-git.sh"
guard() {   # guard <lệnh> <chuỗi phải có trong lời chặn>
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$1" "$R" > "$TMP/in.json"
  ( cd "$R" && CLAUDE_PROJECT_DIR="$R" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/guard.err" ); local rc=$?
  [ "$rc" = 2 ] && grep -qF -- "$2" "$TMP/guard.err" && ok "guard: '$1' blocked, points at $2" \
    || { fail "guard: '$1' (rc=$rc)"; cat "$TMP/guard.err"; }
}
guard "git branch -D feat/x" "agent-kit worktree prune-branch"
guard "git worktree remove --force ../w" "agent-kit worktree discard"
guard "git checkout $OLD -- a.txt" "agent-kit worktree restore"
# (OCR r2) `checkout -- <path>` chỉ đáng chặn khi path có thay đổi chưa commit, mà restore luôn từ chối ca đó: không chỉ sang nó
guard "git checkout -- a.txt" "BLOCKED"
grep -qF "agent-kit worktree restore" "$TMP/guard.err" && fail "guard: 'git checkout -- a.txt' points at restore, which always refuses it" \
  || ok "guard: 'git checkout -- a.txt' does not point at restore"
# (OCR r2) khoá devkit-kept là bằng chứng "chính phiên" của discard/remove: chỉ hook ExitWorktree keep đặt nó, không bao giờ bằng tay
guard "git worktree lock --reason \"devkit-kept session=x pid=1234\" ../w" "devkit-kept"
guard "git -C ../w worktree lock --reason=devkit-kept\\ session=x\\ pid=1 ." "devkit-kept"
# (audit T0044) `git restore --source <commit> -- <path>` cũng là việc của restore; `git push --delete` là việc của prune-branch --remote
# (`git restore` trần qua được sau khi hook chép bản dự phòng; nó chỉ bị chặn khi đổi chỗ bằng -C / --git-dir / --work-tree)
guard "git -C . restore --source $OLD -- a.txt" "agent-kit worktree restore"
guard "git -C . restore -s$OLD a.txt" "agent-kit worktree restore"
guard "git push origin --delete feat/x" "agent-kit worktree prune-branch --remote"
# `git checkout main --` (không có path sau --) không phải restore
guard "git checkout main --" "BLOCKED"
grep -qF "agent-kit worktree restore" "$TMP/guard.err" && fail "guard: 'git checkout main --' points at restore" \
  || ok "guard: 'git checkout main --' does not point at restore"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_discard: all passed" || { echo "❌ test_worktree_discard: $FAILS failed"; exit 1; }
