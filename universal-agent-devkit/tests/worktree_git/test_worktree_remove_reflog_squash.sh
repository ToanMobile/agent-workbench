#!/usr/bin/env bash
# Hồi quy (#421): `worktree remove` từ chối UNREACHABLE một worktree detached mà các commit gốc chỉ còn trong reflog (checkout --detach
# origin/main sau khi PR squash) dù cả chuỗi đã nằm trong trunk dưới dạng squash. remove phải tự chứng minh như discard (_chain_in_trunk)
# và cất bản dự phòng vào refs/devkit/discarded/* trước khi gỡ.
#   r1. chuỗi squash vào origin/main, worktree detach sang origin/main (commit chỉ còn reflog): gỡ được + có refs/devkit/discarded/*
#   r2. (âm) commit chỉ còn trong reflog mà trunk KHÔNG có patch: vẫn từ chối UNREACHABLE, worktree còn nguyên
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

git init -q --bare -b main "$TMP/origin.git"
R="$TMP/rd"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
G "$R" config devkit.trunkMode true; G "$R" remote add origin "$TMP/origin.git"
printf 'a1\n' > a.txt; printf 'b1\n' > b.txt
G "$R" add -A && G "$R" commit -qm init && G "$R" push -q origin main
mk() { bash "$KIT" worktree add "../$1" >/dev/null 2>&1 || fail "add $1"; }
mk w-sq; mk w-new
G "$TMP/w-sq" checkout -q --detach
printf 'a2\n' > "$TMP/w-sq/a.txt"; G "$TMP/w-sq" commit -qam c1
printf 'b2\n' > "$TMP/w-sq/b.txt"; G "$TMP/w-sq" commit -qam c2
G "$TMP/w-new" checkout -q --detach
printf 'e\n' > "$TMP/w-new/e.txt"; G "$TMP/w-new" add e.txt; G "$TMP/w-new" commit -qm only-here
# PR squash trên origin (main local chưa pull); hai worktree rời sang origin/main: commit của chúng chỉ còn trong reflog
git clone -q "$TMP/origin.git" "$TMP/pr" && printf 'a2\n' > "$TMP/pr/a.txt" && printf 'b2\n' > "$TMP/pr/b.txt" \
  && G "$TMP/pr" commit -qam "squash #1" && G "$TMP/pr" push -q origin main && G "$R" fetch -q origin
G "$TMP/w-sq" checkout -q --detach origin/main
G "$TMP/w-new" checkout -q --detach origin/main

# r2 trước r1: r1 thêm refs/devkit/discarded, r2 không được dựa vào nó
bash "$KIT" worktree remove ../w-new >"$TMP/r2.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-new" ] && grep -q 'UNREACHABLE' "$TMP/r2.out" && ok "r2 remove refuses a reflog-only commit the trunk has no patch for (rc=$rc)" \
  || { fail "r2 remove dropped a reflog-only commit the trunk lacks (rc=$rc)"; cat "$TMP/r2.out"; }

bash "$KIT" worktree remove ../w-sq >"$TMP/r1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-sq" ] && [ -n "$(G "$R" for-each-ref 'refs/devkit/discarded/*')" ] \
  && ok "r1 remove drops reflog-only commits whose patch the trunk holds (squash) and keeps a refs/devkit/discarded backup" \
  || { fail "r1 remove of a squashed chain (rc=$rc)"; cat "$TMP/r1.out"; }
# bản cất giữ commit reflog-only làm cha: đọc lại được nội dung gốc
ref=$(G "$R" for-each-ref --format='%(refname)' 'refs/devkit/discarded/*' | head -1)
[ -n "$ref" ] && [ "$(G "$R" rev-list --count "$ref" --not origin/main)" -ge 3 ] \
  && ok "r1 the backup keeps the two reflog-only commits as ancestors" || fail "r1 backup lacks the reflog-only commits"

# r3: HEAD vẫn ở cuối chuỗi (không có commit chỉ-reflog), squash chỉ có trên origin: vẫn phải có bản cất trước khi gỡ
mk w-hd; G "$TMP/w-hd" checkout -q --detach
printf 'a2\n' > "$TMP/w-hd/a.txt"; G "$TMP/w-hd" commit -qam c1
printf 'b2\n' > "$TMP/w-hd/b.txt"; G "$TMP/w-hd" commit -qam c2
before=$(G "$R" for-each-ref 'refs/devkit/discarded/*' | wc -l)
bash "$KIT" worktree remove ../w-hd >"$TMP/r3.out" 2>&1; rc=$?
after=$(G "$R" for-each-ref 'refs/devkit/discarded/*' | wc -l)
[ "$rc" = 0 ] && [ ! -e "$TMP/w-hd" ] && [ "$after" -gt "$before" ] \
  && ok "r3 remove of a detached chain squashed into the trunk keeps a backup (no reflog-only commit)" \
  || { fail "r3 remove of a detached squashed chain (rc=$rc, backups $before->$after)"; cat "$TMP/r3.out"; }

# r4: reflog trộn — một commit đã squash, một commit trunk không có patch: từ chối (all, không phải any)
mk w-mix; G "$TMP/w-mix" checkout -q --detach
printf 'a2\n' > "$TMP/w-mix/a.txt"; G "$TMP/w-mix" commit -qam c1
printf 'z\n' > "$TMP/w-mix/z.txt"; G "$TMP/w-mix" add z.txt; G "$TMP/w-mix" commit -qm only-here
G "$TMP/w-mix" checkout -q --detach origin/main
bash "$KIT" worktree remove ../w-mix >"$TMP/r4.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-mix" ] && grep -q 'UNREACHABLE' "$TMP/r4.out" && ok "r4 remove refuses a mixed reflog (one squashed, one not in the trunk)" \
  || { fail "r4 remove dropped a mixed reflog (rc=$rc)"; cat "$TMP/r4.out"; }

# r5: reflog-only commits đã squash nhưng HEAD có commit trunk chưa có: từ chối (HEAD cũng phải nằm trong trunk)
mk w-hn; G "$TMP/w-hn" checkout -q --detach
printf 'a2\n' > "$TMP/w-hn/a.txt"; G "$TMP/w-hn" commit -qam c1
G "$TMP/w-hn" checkout -q --detach origin/main
printf 'y\n' > "$TMP/w-hn/y.txt"; G "$TMP/w-hn" add y.txt; G "$TMP/w-hn" commit -qm head-only
bash "$KIT" worktree remove ../w-hn >"$TMP/r5.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-hn" ] && grep -q 'UNREACHABLE' "$TMP/r5.out" && ok "r5 remove refuses when HEAD holds a commit the trunk lacks" \
  || { fail "r5 remove dropped a HEAD commit the trunk lacks (rc=$rc)"; cat "$TMP/r5.out"; }

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
