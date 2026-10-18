#!/usr/bin/env bash
# Hồi quy (18/10, người dùng duyệt K2/K4 "làm cả 3"): guard git chặn `git worktree remove --force`, `git branch -D` và
# `git checkout <sha> -- <path>` theo dạng lệnh, kể cả khi không mất gì, nên mỗi lần như vậy là một việc tay cho người dùng.
# Ba lệnh kit tự chứng minh "không mất gì" rồi mới làm; dạng git trần vẫn bị guard chặn như cũ:
#   - worktree discard <path>: (a) chỉ còn file đã xoá / rác IDE chưa track và HEAD đã nằm trong trunk; (b) worktree của CHÍNH phiên
#     gọi (khoá devkit-kept của tiến trình tổ tiên): mọi thứ cất vào refs/devkit/discarded/* trước khi gỡ
#   - worktree restore <sha> -- <path>…: chỉ khi path không có thay đổi chưa commit, không ở main của trunk mode
#   - worktree prune-branch <nhánh>: chỉ khi tip đã nằm trong trunk (tổ tiên hoặc squash) hoặc PR MERGED đúng tip đó
# Kèm: `worktree remove` gỡ được worktree mà khoá devkit-kept là của chính phiên gọi (phiên GeelyEx2 18/10 phải unlock tay).
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

# a2. rác IDE chưa track (.vscode/, *.slnx, *.sln, *.csproj) + một file đã xoá: gỡ được
mk w-ide; mkdir -p "$TMP/w-ide/.vscode"; echo '{}' > "$TMP/w-ide/.vscode/settings.json"
echo x > "$TMP/w-ide/w-ide.slnx"; echo x > "$TMP/w-ide/App.csproj"; rm "$TMP/w-ide/b.txt"
bash "$KIT" worktree discard ../w-ide >"$TMP/a2.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-ide" ] && ok "a2 discard: untracked IDE junk + deletions is removed" \
  || { fail "a2 discard of IDE junk (rc=$rc)"; cat "$TMP/a2.out"; }

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
[ "$rc" = 0 ] && [ ! -e "$TMP/w-sq" ] && ok "a6 discard: squash-merged worktree with deletions is removed" \
  || { fail "a6 discard of a squash-merged worktree (rc=$rc)"; cat "$TMP/a6.out"; }

# a7. khoá devkit-kept của một phiên KHÁC còn sống: từ chối dù chỉ có file xoá
mk w-other; rm "$TMP/w-other/b.txt"; G "$R" worktree lock --reason "devkit-kept session=other pid=$SLEEPER" "$TMP/w-other"
bash "$KIT" worktree discard ../w-other >"$TMP/a7.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-other" ] && ok "a7 discard refuses a worktree another live session keeps (rc=$rc)" \
  || { fail "a7 discard took another live session's worktree (rc=$rc)"; cat "$TMP/a7.out"; }

# a8. main checkout: từ chối
bash "$KIT" worktree discard "$R" >"$TMP/a8.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -f "$R/a.txt" ] && ok "a8 discard refuses the main checkout (rc=$rc)" || { fail "a8 discard on main (rc=$rc)"; cat "$TMP/a8.out"; }

# --- discard (b): worktree của chính phiên gọi -------------------------------------------------------------------------------
# b1. khoá devkit-kept với pid = shell của test (tổ tiên của lệnh kit): sửa chưa commit + commit riêng đều được cất rồi mới gỡ
mk w-own; echo own > "$TMP/w-own/a.txt"; echo f > "$TMP/w-own/f.txt"; G "$TMP/w-own" add f.txt && G "$TMP/w-own" commit -qm f
echo loose > "$TMP/w-own/loose.txt"
G "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$TMP/w-own"
bash "$KIT" worktree discard ../w-own >"$TMP/b1.out" 2>&1; rc=$?
REF=$(G "$R" for-each-ref --format='%(refname)' 'refs/devkit/discarded/w-own-*' | head -1)
[ "$rc" = 0 ] && [ ! -e "$TMP/w-own" ] && [ -n "$REF" ] \
  && [ "$(G "$R" show "$REF:a.txt" 2>/dev/null)" = own ] && [ "$(G "$R" show "$REF:loose.txt" 2>/dev/null)" = loose ] \
  && [ "$(G "$R" show "$REF:f.txt" 2>/dev/null)" = f ] \
  && ok "b1 discard of the caller's own worktree keeps everything in $REF" \
  || { fail "b1 own-session discard (rc=$rc, ref='$REF')"; cat "$TMP/b1.out"; }

# --- remove: khoá devkit-kept của chính phiên gọi ---------------------------------------------------------------------------
mk w-keep; G "$R" worktree lock --reason "devkit-kept session=me pid=$$" "$TMP/w-keep"
bash "$KIT" worktree remove ../w-keep >"$TMP/k1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-keep" ] && ok "k1 remove: the caller's own devkit-kept lock no longer blocks it" \
  || { fail "k1 remove refused the caller's own kept worktree (rc=$rc)"; cat "$TMP/k1.out"; }
mk w-keep2; G "$R" worktree lock --reason "devkit-kept session=other pid=$SLEEPER" "$TMP/w-keep2"
bash "$KIT" worktree remove ../w-keep2 >"$TMP/k2.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-keep2" ] && ok "k2 remove still refuses a worktree another live session keeps (rc=$rc)" \
  || { fail "k2 remove took another live session's kept worktree (rc=$rc)"; cat "$TMP/k2.out"; }

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
( cd "$R" && bash "$KIT" worktree restore "$OLD" -- a.txt ) >"$TMP/r4.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$R/a.txt")" = a2 ] && ok "r4 restore refuses the trunk-mode main checkout (rc=$rc)" \
  || { fail "r4 restore wrote main (rc=$rc)"; cat "$TMP/r4.out"; }
( cd "$TMP/w-rs" && bash "$KIT" worktree restore nosuchsha -- a.txt ) >"$TMP/r5.out" 2>&1; rc=$?
[ "$rc" != 0 ] && ok "r5 restore refuses an unknown commit (rc=$rc)" || { fail "r5 restore of a bad sha (rc=$rc)"; cat "$TMP/r5.out"; }

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
printf '#!/bin/sh\necho %s\n' "'[{\"number\":7,\"headRefOid\":\"$TIP\"}]'" > "$FAKE/gh"; chmod +x "$FAKE/gh"
PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch p-new >"$TMP/p6.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ! has_branch p-new && ok "p6 prune-branch deletes a branch whose PR merged at this very tip" \
  || { fail "p6 prune-branch with a merged PR (rc=$rc)"; cat "$TMP/p6.out"; }
G "$R" branch p-moved HEAD; mk w-pm p-moved; echo m > "$TMP/w-pm/m.txt"; G "$TMP/w-pm" add m.txt && G "$TMP/w-pm" commit -qm m
G "$R" worktree remove "$TMP/w-pm" >/dev/null 2>&1
printf '#!/bin/sh\necho %s\n' "'[{\"number\":8,\"headRefOid\":\"0000000000000000000000000000000000000000\"}]'" > "$FAKE/gh"
PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch p-moved >"$TMP/p7.out" 2>&1; rc=$?
[ "$rc" != 0 ] && has_branch p-moved && ok "p7 prune-branch keeps a branch that moved past its merged PR (rc=$rc)" \
  || { fail "p7 prune-branch deleted commits after the merged PR (rc=$rc)"; cat "$TMP/p7.out"; }
bash "$KIT" worktree prune-branch main >"$TMP/p5.out" 2>&1; rc=$?
[ "$rc" != 0 ] && has_branch main && ok "p5 prune-branch refuses the trunk branch (rc=$rc)" || { fail "p5 prune-branch main (rc=$rc)"; cat "$TMP/p5.out"; }

# --- gc: bản cất của discard sống 30 ngày ----------------------------------------------------------------------------------------
G "$R" update-ref refs/devkit/discarded/old-20200101-000000 HEAD
bash "$KIT" worktree gc >"$TMP/g1.out" 2>&1
! G "$R" show-ref --verify --quiet refs/devkit/discarded/old-20200101-000000 && [ -n "$REF" ] && G "$R" show-ref --verify --quiet "$REF" \
  && ok "g1 gc drops a discard backup older than 30 days and keeps a fresh one" \
  || { fail "g1 gc and discard backups"; cat "$TMP/g1.out"; }

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
guard "git checkout -- a.txt" "agent-kit worktree restore"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_discard: all passed" || { echo "❌ test_worktree_discard: $FAILS failed"; exit 1; }
