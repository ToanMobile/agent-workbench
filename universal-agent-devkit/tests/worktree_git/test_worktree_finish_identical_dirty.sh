#!/usr/bin/env bash
# 17/10 (OfficeReader, GeelyEx2, Goods, Neighbours): bản triển khai super-board được chép thẳng vào main checkout và nằm đó CHƯA commit.
# Commit đúng nội dung đó qua worktree thì `worktree finish` bị git từ chối (`merge --ff-only`: "local changes would be overwritten"),
# dù bản ở main giống hệt từng byte với thứ commit mang về; trunk mode lại cấm agent tự stage ở main, nên không ai gộp được.
# finish phải tự stage đúng các đường dẫn trùng mà nội dung + mode ở main GIỐNG HỆT bản commit mang về (không mất gì), còn lại từ chối
# như cũ. Mỗi ca một main checkout riêng.
#   1 sửa chưa commit ở main giống hệt commit: gộp được, main sạch ở đường dẫn đó
#   2 lệch một byte: vẫn từ chối, main không nhích, file ở main giữ nguyên
#   3 cùng nội dung nhưng khác mode (main có +x): vẫn từ chối
#   4 file CHƯA track ở main giống hệt file commit thêm vào: gộp được, sạch
#   5 index ở main đã stage một bản khác, working tree giống commit: từ chối, bản đã stage của người khác giữ nguyên
#   6 trùng một phần: không stage gì · 7 symlink ở main: không stage · 8 file chưa track bị ignore: không stage
#   9 entry intent-to-add của phiên khác còn nguyên sau khi bị từ chối · 10 nhiều file mới vào main sạch: vẫn gộp
#   11 quá 500 đường dẫn trùng: không stage · 12 commit xoá file main đang sửa: từ chối, giữ sửa
#   13 tên có dấu cách/glob, file chưa track đã stage được trả về chưa track khi ff hỏng
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

new_main() {   # new_main <tên>: main checkout có run.sh đã commit
  P="$TMP/$1"; mkdir -p "$P" && G "$P" init -q -b main . || return 1
  printf 'old\n' > "$P/run.sh"; echo a > "$P/a.txt"
  G "$P" add -A && G "$P" commit -qm init
}
wt() { (cd "$P" && python3 "$WTPY" add "$1" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1"; }
fin() { (cd "$P" && python3 "$WTPY" finish "$@" >"$TMP/out" 2>&1); return $?; }
commit_in() { G "$W" add -A && G "$W" commit -qm "$1"; }

# 1: main giữ bản triển khai chưa commit, worktree commit đúng bản đó
new_main m1; W="$TMP/w1"; wt "$W"; printf 'new\n' > "$W/run.sh"; commit_in deploy; WH="$(G "$W" rev-parse HEAD)"
printf 'new\n' > "$P/run.sh"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ "$(G "$P" rev-parse HEAD)" = "$WH" ] && [ -z "$(G "$P" status --porcelain -- run.sh)" ] && [ "$(cat "$P/run.sh")" = new ] \
  && ok "1: byte-identical uncommitted edit in main: merged, main clean at that path" \
  || fail "1: (rc=$rc, main=$(G "$P" log -1 --format=%s), status='$(G "$P" status --porcelain -- run.sh)'): $(cat "$TMP/out")"

# 2: lệch một byte: không được mất sửa của main
new_main m2; H="$(G "$P" rev-parse HEAD)"; W="$TMP/w2"; wt "$W"; printf 'new\n' > "$W/run.sh"; commit_in deploy
printf 'neW\n' > "$P/run.sh"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && [ "$(cat "$P/run.sh")" = neW ] && [ -z "$(G "$P" diff --cached --name-only)" ] && grep -q "UNCOMMITTED" "$TMP/out" \
  && ok "2: one differing byte: refused as before, main did not move, its edit and index intact" \
  || fail "2: (rc=$rc, main moved: $([ "$(G "$P" rev-parse HEAD)" = "$H" ] && echo no || echo yes), run.sh=$(cat "$P/run.sh"), staged='$(G "$P" diff --cached --name-only)'): $(cat "$TMP/out")"

# 3: cùng nội dung, khác mode
new_main m3; H="$(G "$P" rev-parse HEAD)"; W="$TMP/w3"; wt "$W"; printf 'new\n' > "$W/run.sh"; commit_in deploy
printf 'new\n' > "$P/run.sh"; chmod +x "$P/run.sh"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && [ -x "$P/run.sh" ] && [ -z "$(G "$P" diff --cached --name-only)" ] \
  && ok "3: same bytes, different mode: refused, main did not move" \
  || fail "3: (rc=$rc, main moved: $([ "$(G "$P" rev-parse HEAD)" = "$H" ] && echo no || echo yes)): $(cat "$TMP/out")"

# 4: file chưa track ở main giống hệt file commit thêm vào
new_main m4; W="$TMP/w4"; wt "$W"; printf 'clean\n' > "$W/post-merge-clean.sh"; commit_in deploy; WH="$(G "$W" rev-parse HEAD)"
printf 'clean\n' > "$P/post-merge-clean.sh"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ "$(G "$P" rev-parse HEAD)" = "$WH" ] && [ -z "$(G "$P" status --porcelain)" ] \
  && ok "4: identical untracked file at a path the commit adds: merged, main clean" \
  || fail "4: (rc=$rc, status='$(G "$P" status --porcelain)'): $(cat "$TMP/out")"

# 5: index của main đã có bản stage KHÁC (việc của phiên khác): không được ghi đè
new_main m5; H="$(G "$P" rev-parse HEAD)"; W="$TMP/w5"; wt "$W"; printf 'new\n' > "$W/run.sh"; commit_in deploy
printf 'staged-by-other\n' > "$P/run.sh"; G "$P" add run.sh; printf 'new\n' > "$P/run.sh"
STAGED="$(G "$P" rev-parse :run.sh)"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && [ "$(G "$P" rev-parse :run.sh)" = "$STAGED" ] \
  && ok "5: main's index holds another staged version: refused, that staged entry kept" \
  || fail "5: (rc=$rc, staged kept: $([ "$(G "$P" rev-parse :run.sh)" = "$STAGED" ] && echo yes || echo no)): $(cat "$TMP/out")"

# 6: trùng một phần (a.txt giống hệt, run.sh lệch): tất cả hoặc không, không stage gì
new_main m6; H="$(G "$P" rev-parse HEAD)"; W="$TMP/w6"; wt "$W"; printf 'new\n' > "$W/run.sh"; echo b > "$W/a.txt"; commit_in deploy
echo b > "$P/a.txt"; printf 'other\n' > "$P/run.sh"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && [ -z "$(G "$P" diff --cached --name-only)" ] && [ "$(cat "$P/run.sh")" = other ] \
  && ok "6: partial overlap (one identical, one not): nothing staged, main did not move" \
  || fail "6: (rc=$rc, staged='$(G "$P" diff --cached --name-only)'): $(cat "$TMP/out")"

# 7: ở main là symlink trỏ tới file có đúng nội dung: không phải file thường, không stage
new_main m7; H="$(G "$P" rev-parse HEAD)"; W="$TMP/w7"; wt "$W"; printf 'new\n' > "$W/run.sh"; commit_in deploy
printf 'new\n' > "$TMP/target-m7"; rm "$P/run.sh"; ln -s "$TMP/target-m7" "$P/run.sh"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && [ -L "$P/run.sh" ] && [ -z "$(G "$P" diff --cached --name-only)" ] \
  && ok "7: a symlink in main with the same bytes behind it: refused, the link kept, nothing staged" \
  || fail "7: (rc=$rc, link kept: $([ -L "$P/run.sh" ] && echo yes || echo no)): $(cat "$TMP/out")"

# 8: file chưa track ở main bị git ignore, giống hệt file commit thêm: không tự stage (git add -f mới được), từ chối như cũ
new_main m8; echo 'local.cfg' > "$P/.gitignore"; G "$P" add .gitignore && G "$P" commit -qm ignore; H="$(G "$P" rev-parse HEAD)"
W="$TMP/w8"; wt "$W"; printf 'cfg\n' > "$W/local.cfg"; G "$W" add -f local.cfg && G "$W" commit -qm "track cfg"
printf 'cfg\n' > "$P/local.cfg"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && [ -z "$(G "$P" diff --cached --name-only)" ] && [ "$(cat "$P/local.cfg")" = cfg ] \
  && ok "8: an ignored untracked identical file: refused as before, nothing staged" \
  || fail "8: (rc=$rc, staged='$(G "$P" diff --cached --name-only)'): $(cat "$TMP/out")"

# 9: file commit thêm vào mà main giữ dạng intent-to-add (`git add -N`, việc của phiên khác): không phải "chưa track", không đụng tới
new_main m9; echo 'local.cfg' > "$P/.gitignore"; G "$P" add .gitignore && G "$P" commit -qm ignore; H="$(G "$P" rev-parse HEAD)"
W="$TMP/w9"; wt "$W"; printf 'n\n' > "$W/n.txt"; echo b > "$W/a.txt"; echo theirs > "$W/local.cfg"; G "$W" add -f local.cfg; commit_in deploy
# a.txt giống hệt (được stage), ff vẫn hỏng vì local.cfg bị ignore ở main: nhánh lỗi reset không được xoá entry i-t-a của n.txt
printf 'n\n' > "$P/n.txt"; G "$P" add -N n.txt; echo b > "$P/a.txt"; echo mine > "$P/local.cfg"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && G "$P" ls-files --error-unmatch n.txt >/dev/null 2>&1 && [ -z "$(G "$P" diff --cached --name-only -- a.txt)" ] && [ "$(cat "$P/local.cfg")" = mine ] \
  && ok "9: an intent-to-add entry of another session stays in main's index after a refused merge" \
  || fail "9: (rc=$rc, n.txt in index: $(G "$P" ls-files -- n.txt)): $(cat "$TMP/out")"

# 10: commit thêm nhiều file mới vào main sạch: vẫn gộp (600 đường dẫn ngắn chưa chạm ARG_MAX; lỗi argv của bản đầu cần ~40k file, đã đo bằng probe)
new_main m10; W="$TMP/w10"; wt "$W"; mkdir -p "$W/gen"; for i in $(seq 1 600); do echo "$i" > "$W/gen/f$i.txt"; done; commit_in "many files"; WH="$(G "$W" rev-parse HEAD)"
fin "$W"; rc=$?
[ "$rc" = 0 ] && [ "$(G "$P" rev-parse HEAD)" = "$WH" ] && [ -z "$(G "$P" status --porcelain)" ] \
  && ok "10: 600 new files into a clean main: merged" || fail "10: (rc=$rc): $(cat "$TMP/out")"

# 11: quá IDENTICAL_OVERLAP_MAX (500) đường dẫn trùng giống hệt: không stage gì, từ chối như cũ
new_main m11; mkdir -p "$P/gen"; for i in $(seq 1 501); do echo old > "$P/gen/f$i.txt"; done; G "$P" add -A && G "$P" commit -qm gen; H="$(G "$P" rev-parse HEAD)"
W="$TMP/w11"; wt "$W"; for i in $(seq 1 501); do echo new > "$W/gen/f$i.txt"; echo new > "$P/gen/f$i.txt"; done; commit_in "501 edits"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && [ -z "$(G "$P" diff --cached --name-only)" ] \
  && ok "11: over the cap (501 identical paths): nothing staged, refused" || fail "11: (rc=$rc, staged=$(G "$P" diff --cached --name-only | wc -l)): $(cat "$TMP/out")"

# 12: commit XOÁ một file mà main đang sửa chưa commit: không tự xử lý, sửa ở main giữ nguyên
new_main m12; H="$(G "$P" rev-parse HEAD)"; W="$TMP/w12"; wt "$W"; G "$W" rm -q run.sh && G "$W" commit -qm "drop run.sh"
printf 'mine\n' > "$P/run.sh"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && [ "$(cat "$P/run.sh")" = mine ] && [ -z "$(G "$P" diff --cached --name-only)" ] \
  && ok "12: the commit deletes a file main edits uncommitted: refused, main's edit kept" || fail "12: (rc=$rc): $(cat "$TMP/out")"

# 13: tên có dấu cách / ký tự glob, file chưa track giống hệt được stage, rồi ff hỏng (local.cfg bị ignore): rollback trả nó về chưa track
new_main m13; echo 'local.cfg' > "$P/.gitignore"; G "$P" add .gitignore && G "$P" commit -qm ignore; H="$(G "$P" rev-parse HEAD)"
W="$TMP/w13"; wt "$W"; printf 'x\n' > "$W/a b*.txt"; echo theirs > "$W/local.cfg"; G "$W" add -f local.cfg; commit_in deploy
printf 'x\n' > "$P/a b*.txt"; echo mine > "$P/local.cfg"
fin "$W"; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$H" ] && [ -z "$(G "$P" diff --cached --name-only)" ] \
  && [ "$(G "$P" ls-files --others --exclude-standard -z | tr '\0' '\n')" = 'a b*.txt' ] && [ "$(cat "$P/local.cfg")" = mine ] \
  && ok "13: a staged identical untracked 'a b*.txt' goes back to untracked when the ff fails, main did not move" \
  || fail "13: (rc=$rc, others='$(G "$P" ls-files --others --exclude-standard)', staged='$(G "$P" diff --cached --name-only)'): $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_finish_identical_dirty: all passed" || { echo "❌ test_worktree_finish_identical_dirty: $FAILS failed"; exit 1; }
