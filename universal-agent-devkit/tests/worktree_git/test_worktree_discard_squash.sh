#!/usr/bin/env bash
# Hồi quy (#200, 23/10): `worktree discard` từ chối một worktree detached mà PR của nó đã squash vào origin/<trunk> khi main LOCAL chưa
# đồng bộ (.merge-scratch-NCG6nj, 8 commit của PR #160): kiểm kê của `remove` so với HEAD của main checkout nên báo UNREACHABLE. discard
# tự chứng minh thêm với origin/<trunk>: cùng patch-id, hoặc patch cả chuỗi đã nằm trong trunk (squash); mọi điều kiện khác giữ nguyên.
#   s1. chuỗi đã squash trên origin (main local chưa pull) + file tracked bị xoá: gỡ được, có refs/devkit/discarded/*
#   s2. (âm) chuỗi còn một commit mà trunk chưa có patch: từ chối
#   s3. (âm) chuỗi đã squash nhưng có một file bị SỬA (không phải xoá): từ chối
#   s4. chuỗi đã vào origin kiểu rebase-merge (cùng patch-id) rồi origin sửa tiếp (gộp thử xung đột): gỡ được
#   s5. (âm) chuỗi đã squash + một commit rỗng (chỉ có message): từ chối
#   s7. (âm) chuỗi chỉ khác commit đã vào origin ở khoảng trắng (`a 2` vs `a2`; patch-id mặc định coi là một): từ chối
#   s8. (âm) chỉ khác \r\n so với commit đã vào origin: từ chối
#   s9. (âm) chuỗi thêm, xoá, thêm lại x.txt mà origin chỉ có thêm, xoá (so theo số lần, không theo tập): từ chối
#   s10. (âm) commit chỉ đổi con trỏ gitlink, diff.submodule=log + ignoreSubmodules=all: từ chối (ghim kết quả; chặn bằng cả blocker submodule,
#        nên mutant bỏ cờ --submodule=short vẫn sống: cờ đó là lớp phòng thủ thứ hai, chưa có ca riêng)
#   s11. (âm) .gitattributes merge=ours: gộp thử giữ bản trunk nên trông như đã có, discard vẫn từ chối
#   s12. (âm) chuỗi head dài hơn cap: _same_patches_verbatim trả False mà không chạy `git log -p` (#326)
#   s6. (âm) chuỗi đã squash + một commit chỉ còn trong reflog của worktree: từ chối
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
printf 'a1\n' > a.txt; printf 'b1\n' > b.txt; printf 'c\n' > c.txt
G "$R" add -A && G "$R" commit -qm init && G "$R" push -q origin main
mk() { bash "$KIT" worktree add "../$1" >/dev/null 2>&1 || fail "add $1"; }
# chuỗi hai commit (a.txt, b.txt) trên HEAD tách rời của worktree $1
chain() {
  G "$TMP/$1" checkout -q --detach
  printf 'a2\n' > "$TMP/$1/a.txt"; G "$TMP/$1" commit -qam c1
  printf 'b2\n' > "$TMP/$1/b.txt"; G "$TMP/$1" commit -qam c2
}
mk w-sq; mk w-new; mk w-mod; mk w-rb; mk w-em; mk w-rl
mk w-ws
chain w-sq; chain w-new; chain w-mod; chain w-rb; chain w-em; chain w-rl
mk w-gl; G "$TMP/w-gl" checkout -q --detach
printf 'a2\n' > "$TMP/w-gl/a.txt"; G "$TMP/w-gl" commit -qam c1
G "$TMP/w-gl" update-index --add --cacheinfo 160000,"$(G "$R" rev-parse HEAD)",sub; G "$TMP/w-gl" commit -qm bump-gitlink
mk w-mg; G "$TMP/w-mg" checkout -q --detach
printf 'b2\nonly-in-worktree\n' > "$TMP/w-mg/b.txt"; G "$TMP/w-mg" commit -qam mergeours
mk w-crlf; G "$TMP/w-crlf" checkout -q --detach
printf 'a2\n' > "$TMP/w-crlf/a.txt"; G "$TMP/w-crlf" commit -qam c1
printf 'b2\r\n' > "$TMP/w-crlf/b.txt"; G "$TMP/w-crlf" -c core.autocrlf=false commit -qam c2crlf
mk w-dup; G "$TMP/w-dup" checkout -q --detach
printf 'x\n' > "$TMP/w-dup/x.txt"; G "$TMP/w-dup" add x.txt; G "$TMP/w-dup" commit -qm addx
G "$TMP/w-dup" rm -q x.txt; G "$TMP/w-dup" commit -qm delx
printf 'x\n' > "$TMP/w-dup/x.txt"; G "$TMP/w-dup" add x.txt; G "$TMP/w-dup" commit -qm addx2
G "$TMP/w-ws" checkout -q --detach; printf 'a 2\n' > "$TMP/w-ws/a.txt"; G "$TMP/w-ws" commit -qam c1; printf 'b2\n' > "$TMP/w-ws/b.txt"; G "$TMP/w-ws" commit -qam c2
G "$TMP/w-em" commit -q --allow-empty -m "E: chi co message"
printf "x\n" > "$TMP/w-rl/x.txt"; G "$TMP/w-rl" add x.txt; G "$TMP/w-rl" commit -qm lone; G "$TMP/w-rl" reset -q --hard HEAD~1
printf 'e\n' > "$TMP/w-new/e.txt"; G "$TMP/w-new" add e.txt; G "$TMP/w-new" commit -qm c3-new
# PR squash trên GitHub: origin/main nhận đúng patch của chuỗi bằng MỘT commit; main local của repo chưa pull
git clone -q "$TMP/origin.git" "$TMP/pr" && printf 'a2\n' > "$TMP/pr/a.txt" && printf 'b2\n' > "$TMP/pr/b.txt" \
  && G "$TMP/pr" commit -qam "squash #1" && G "$TMP/pr" push -q origin main && G "$R" fetch -q origin

# s1
rm "$TMP/w-sq/c.txt"
bash "$KIT" worktree discard ../w-sq >"$TMP/s1.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-sq" ] && [ -n "$(G "$R" for-each-ref 'refs/devkit/discarded/*')" ] \
  && ok "s1 discard removes a chain squashed into origin/main and leaves a refs/devkit/discarded backup" \
  || { fail "s1 discard of a squashed chain (rc=$rc)"; cat "$TMP/s1.out"; }

# s2
rm "$TMP/w-new/c.txt"
bash "$KIT" worktree discard ../w-new >"$TMP/s2.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-new" ] && grep -q 'holds commits the trunk lacks' "$TMP/s2.out" && ok "s2 discard refuses a chain with a commit the trunk has no patch for (rc=$rc)" \
  || { fail "s2 discard dropped a commit the trunk lacks (rc=$rc)"; cat "$TMP/s2.out"; }

# s3
printf 'edited\n' > "$TMP/w-mod/c.txt"
bash "$KIT" worktree discard ../w-mod >"$TMP/s3.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$TMP/w-mod/c.txt")" = edited ] && ok "s3 discard refuses a modified file even when the chain is integrated (rc=$rc)" \
  || { fail "s3 discard dropped a modified file (rc=$rc)"; cat "$TMP/s3.out"; }

# s5, s6
rm "$TMP/w-em/c.txt"; rm "$TMP/w-rl/c.txt"
bash "$KIT" worktree discard ../w-em >"$TMP/s5.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-em" ] && grep -q 'holds commits the trunk lacks' "$TMP/s5.out" && ok "s5 discard refuses an empty commit (message only) (rc=$rc)" || { fail "s5 discard dropped an empty commit (rc=$rc)"; cat "$TMP/s5.out"; }
bash "$KIT" worktree discard ../w-rl >"$TMP/s6.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-rl" ] && grep -q 'UNREACHABLE' "$TMP/s6.out" && ok "s6 discard refuses a commit only the reflog names (rc=$rc)" || { fail "s6 discard dropped a reflog-only commit (rc=$rc)"; cat "$TMP/s6.out"; }

# s4: origin nhận c1', c2' kiểu rebase-merge (patch-id giống), rồi sửa tiếp a.txt: gộp thử xung đột, chỉ so patch-id gỡ được
git clone -q "$TMP/origin.git" "$TMP/pr2" && G "$TMP/pr2" reset -q --hard "$(G "$R" rev-parse origin/main~1)" \
  && printf 'a2\n' > "$TMP/pr2/a.txt" && G "$TMP/pr2" commit -qam c1 && printf 'b2\n' > "$TMP/pr2/b.txt" && G "$TMP/pr2" commit -qam c2 \
  && printf 'a3\n' > "$TMP/pr2/a.txt" && G "$TMP/pr2" commit -qam later && G "$TMP/pr2" push -q -f origin main && G "$R" fetch -q origin
rm "$TMP/w-rb/c.txt"
bash "$KIT" worktree discard ../w-rb >"$TMP/s4.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-rb" ] && ok "s4 discard removes a chain rebase-merged into origin/main (same patch-ids)" || { fail "s4 discard of a rebase-merged chain (rc=$rc)"; cat "$TMP/s4.out"; }

# s7: PHẢI chạy sau s4 — chỉ khi origin đã có c1/c2 tách rời (patch-id mặc định giống chuỗi `a 2`) ca này mới phân biệt được --verbatim
rm "$TMP/w-ws/c.txt"
bash "$KIT" worktree discard ../w-ws >"$TMP/s7.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-ws" ] && grep -q 'holds commits the trunk lacks' "$TMP/s7.out" && ok "s7 discard refuses a whitespace-only difference from the integrated patch (rc=$rc)" || { fail "s7 discard dropped a whitespace-different commit (rc=$rc)"; cat "$TMP/s7.out"; }

# s8, s9: origin nhận add/del của x.txt (không có lần add thứ hai)
git clone -q "$TMP/origin.git" "$TMP/pr3" && printf 'x\n' > "$TMP/pr3/x.txt" && G "$TMP/pr3" add x.txt && G "$TMP/pr3" commit -qm addx \
  && G "$TMP/pr3" rm -q x.txt && G "$TMP/pr3" commit -qm delx && G "$TMP/pr3" push -q origin main && G "$R" fetch -q origin
for w in w-crlf w-dup; do
  tag=s8; [ "$w" = w-dup ] && tag=s9
  bash "$KIT" worktree discard "../$w" >"$TMP/$tag.out" 2>&1; rc=$?
  [ "$rc" != 0 ] && [ -e "$TMP/$w" ] && grep -q 'holds commits the trunk lacks' "$TMP/$tag.out" && ok "$tag discard refuses $w (rc=$rc)" || { fail "$tag discard dropped $w (rc=$rc)"; cat "$TMP/$tag.out"; }
done

# thuộc tính merge chỉ bật từ đây: b.txt có merge=ours thì mọi ca trên (cùng đổi b.txt) bị từ chối vì lý do khác
mkdir -p "$R/.git/info"; printf 'b.txt merge=ours\n' > "$R/.git/info/attributes"; G "$R" config merge.ours.driver true
G "$R" config diff.submodule log; G "$R" config diff.ignoreSubmodules all   # chỉ s10 cần; gỡ ngay sau vòng này (config của worktree là config chung)
for w in w-gl w-mg; do
  tag=s10; [ "$w" = w-mg ] && tag=s11
  bash "$KIT" worktree discard "../$w" >"$TMP/$tag.out" 2>&1; rc=$?
  # s11 phải bị từ chối ĐÚNG vì chuỗi chưa vào trunk (không phải lý do khác); s10 bị chặn bởi blocker submodule nên giữ phép kiểm cũ
  need=''; [ "$tag" = s11 ] && need='holds commits the trunk lacks'
  [ "$rc" != 0 ] && [ -e "$TMP/$w" ] && grep -q "$need" "$TMP/$tag.out" && ok "$tag discard refuses $w (rc=$rc)" || { fail "$tag discard dropped $w (rc=$rc)"; cat "$TMP/$tag.out"; }
done

G "$R" config --unset diff.submodule; G "$R" config --unset diff.ignoreSubmodules
# #358 mục 7: cấu hình của w-gl chỉ phục vụ s10; sau s10 config chung của repo không còn mang nó (không rò sang ca khác)
leak=$(G "$R" config --get-regexp '^diff\.(submodule|ignoresubmodules)$' 2>/dev/null)
[ -z "$leak" ] && ok "config chung không còn diff.submodule / diff.ignoreSubmodules sau s10" || fail "config chung còn lại sau s10: $leak"

# s12 (#326): cap áp cho CẢ base..head, không chỉ base..tip — chuỗi head dài không được chạy `git log -p` + patch-id
if python3 - "$DEVKIT_DIR/scripts/git" "$R" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import worktree as w
main = sys.argv[2]; calls = []; orig = w._git_bytes
w._git_bytes = lambda cwd, *a, **k: (calls.append(a), orig(cwd, *a, **k))[1]
g = lambda *a: w.git(main, "-c", "user.email=t@t", "-c", "user.name=t", *a)
base = g("rev-parse", "HEAD").stdout.strip()
for i in range(3):
    open(main + "/cap.txt", "w").write(f"{i}\n"); g("add", "cap.txt"); g("commit", "-qm", f"cap{i}")
head = g("rev-parse", "HEAD").stdout.strip(); g("reset", "-q", "--hard", base)
ok = w._same_patches_verbatim(main, base, head, cap=2)
sys.exit(0 if ok is False and not any(a[0] == "log" for a in calls) else 1)
PY
then ok "s12 a head chain over the cap returns False without git log -p"; else fail "s12 head chain over the cap still ran git log -p"; fi

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
