#!/usr/bin/env bash
# K8 (17/10, Neighbours-From-Hell, Unity): main đi tiếp trong lúc gate gộp chạy, `finish` gộp main vào rồi chạy LẠI toàn bộ gate dù vòng
# trước đã PASS và phần main mới mang vào không đụng test nào (gate Unity 1–6 phút mỗi lần, lần chạy lại bị cắt ở 900 s). Nay vòng sau chỉ
# gate phần main mới mang vào (`--diff <HEAD worktree đã PASS>`): chỉ suite có watch_files khớp file main mới đổi được chạy lại.
#   a  vòng 1 PASS, main đi tiếp bằng file không có suite nào theo dõi: suite KHÔNG chạy lần 2, gộp xong
#   a2 vòng 1 PASS, main đi tiếp bằng một lần đổi tên (file khác hẳn file worktree đổi, nhưng suite theo dõi chúng): vẫn chạy lại, vẫn từ chối
#      — "không giao file" KHÔNG đủ để bỏ gate (đúng ca W1 R3 tồn tại để chặn)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null

repo() {   # lib.sh greet(), app.sh gọi nó, check.sh = suite của ma trận (mọi app*.sh in ok), chỉ theo dõi *.sh
  local p="$TMP/$1"; mkdir -p "$p/.agents" && G "$p" init -q -b main . && G "$p" config user.email t@t && G "$p" config user.name t
  printf 'greet() { echo ok; }\n' > "$p/lib.sh"
  printf '. ./lib.sh\ngreet\n' > "$p/app.sh"
  printf '[ -n "${GATE_COUNT:-}" ] && echo run >> "$GATE_COUNT"\n[ -n "${DURING_GATE:-}" ] && bash "$DURING_GATE"\nfor f in app*.sh; do [ "$(bash "$f" 2>/dev/null)" = ok ] || { echo "FAIL $f"; exit 1; }; done\necho "all apps ok"\n' > "$p/check.sh"
  printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"every app prints ok","command":"bash check.sh"}]}]}\n' \
    > "$p/.agents/regression_matrix.active.json"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/\n' > "$p/.gitignore"
  G "$p" add -A && G "$p" commit -qm base
}
wtadd() { (cd "$TMP/$1" && python3 "$WT" add "$TMP/$1-w" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1-w"; }
newcaller() { printf '. ./lib.sh\ngreet\n' > "$TMP/$1-w/app2.sh" && G "$TMP/$1-w" add app2.sh && G "$TMP/$1-w" commit -qm "app2 calls greet"; }
fin() { (cd "$TMP/$1" && env "${@:2}" WORKTREE_FINISH_RETRIES=0 python3 "$WT" finish "$TMP/$1-w" > "$TMP/out" 2>&1); }

# a: main nhận một file không suite nào theo dõi (notes2.txt) đúng lúc gate vòng 1 chạy
repo a; wtadd a; newcaller a
printf '[ -f "%s/a.moved" ] && exit 0; : > "%s/a.moved"; echo n > "%s/a/notes2.txt"; git -C "%s/a" -c user.email=t@t -c user.name=t add notes2.txt; git -C "%s/a" -c user.email=t@t -c user.name=t commit -qm "main: ghi chú, không suite nào theo dõi"\n' \
  "$TMP" "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/a-move.sh"
: > "$TMP/a.count"
fin a GATE_COUNT="$TMP/a.count" DURING_GATE="$TMP/a-move.sh"; rc=$?
runs="$(wc -l < "$TMP/a.count" | tr -d ' ')"
[ "$rc" = 0 ] && [ -f "$TMP/a/app2.sh" ] && [ -f "$TMP/a/notes2.txt" ] && [ ! -d "$TMP/a-w" ] && [ "$runs" = 1 ] \
  && ok "a vòng 1 PASS, main đi tiếp bằng file không có suite theo dõi: suite chạy 1 lần (không gate lại), gộp xong" \
  || fail "a rc=$rc suite chạy $runs lần (mong 1): $(tail -3 "$TMP/out")"

# a2: main đổi tên greet -> hello (lib.sh, app.sh: không giao với app2.sh của worktree) đúng lúc gate vòng 1 chạy
repo b; wtadd b; newcaller b
printf '[ -f "%s/b.moved" ] && exit 0; : > "%s/b.moved"; printf "hello() { echo ok; }\\n" > "%s/b/lib.sh"; printf ". ./lib.sh\\nhello\\n" > "%s/b/app.sh"; git -C "%s/b" -c user.email=t@t -c user.name=t commit -qam "main: đổi tên greet thành hello"\n' \
  "$TMP" "$TMP" "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/b-move.sh"
: > "$TMP/b.count"
fin b GATE_COUNT="$TMP/b.count" DURING_GATE="$TMP/b-move.sh"; rc=$?
runs="$(wc -l < "$TMP/b.count" | tr -d ' ')"
renamed="$(G "$TMP/b" log -1 --format=%s)"
[ "$rc" = 1 ] && [ ! -f "$TMP/b/app2.sh" ] && [ -d "$TMP/b-w" ] && grep -q "REG-APP-01" "$TMP/out" && [ "$runs" -ge 2 ] && [ "$renamed" = "main: đổi tên greet thành hello" ] \
  && ok "a2 main đổi tên (file không giao với worktree) trong lúc gate: vòng 2 vẫn chạy suite (FLAKY_RETRY có thể chạy lại lần nữa), từ chối REG-APP-01, main đứng ở commit đổi tên" \
  || fail "a2 rc=$rc suite chạy $runs lần, main='$renamed': $(tail -3 "$TMP/out")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_merge_regate: PASS"; exit 0; } || { echo "test_worktree_merge_regate: FAIL ($FAILS)"; exit 1; }
