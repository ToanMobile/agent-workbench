#!/usr/bin/env bash
# #1102 (đối chiếu #1099, #1151): (a) `for NAME in <từ cố định>; do … > /tmp/q-$NAME.log; done` được qua khi MỌI giá trị khai triển ra ngoài
# main, mọi biến chưa biết khác vẫn bị chặn; (b) công cụ sửa file của Grok (search_replace, hashline_edit) ghi vào main bị chặn như Edit,
# ghi vào worktree thì qua. Replay hook thật session_lock.sh với phong bì Grok (như test_session_lock_grok_shell.sh).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT SB_BOARD_WORKER
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_lock.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

M="$TMP/main"; W2="$M/.claude/worktrees/lane-grok"
mkdir -p "$M" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
printf '.agents/local/memory/\n.claude/audit-gate/\n/.claude/worktrees/\n' > "$M/.gitignore"
echo a > "$M/a.txt" && git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" worktree add -q --detach "$W2" HEAD
git -C "$M" config devkit.trunkMode true
OUT="$TMP/out"; mkdir -p "$OUT/sub"; ln -s "$M" "$TMP/lnk"

# hook <tool_name> <cwd> <session> <command> [tool_input JSON] -> mã thoát của hook
hook() {
  python3 -I -c '
import json, sys
tool, cwd, sid, cmd = sys.argv[1:5]
ti = json.loads(sys.argv[5]) if len(sys.argv) > 5 else {"command": cmd}
print(json.dumps({"hookEventName": "pre_tool_use", "hook_event_name": "PreToolUse", "sessionId": sid, "session_id": sid,
                  "cwd": cwd, "workspaceRoot": cwd, "toolName": tool, "tool_name": tool, "toolInput": ti, "tool_input": ti}))
' "$1" "$2" "$3" "$4" ${5:+"$5"} > "$TMP/in.json"
  ( cd "$2" && CLAUDE_PROJECT_DIR="$2" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
}
# want <rc> <tool> <cwd> <command> <label> [tool_input JSON]
want() {
  local rc
  hook "$2" "$3" "g-$$" "$4" ${6:+"$6"}; rc=$?
  [ "$rc" = "$1" ] && ok "$5 [$2: rc $rc]" || fail "$5 [$2: rc $rc, want $1] $(head -c 140 "$TMP/err" | tr '\n' ' ')"
}

# (a) for-loop tĩnh
want 0 Bash "$M" 'for t in a b; do bash x.sh >/tmp/q-$t.log; done' "for-loop: redirect /tmp/q-\$t.log, giá trị cố định"
want 0 Bash "$M" "for t in a b; do echo x > $OUT/\$t.log; done" "for-loop: redirect vào thư mục ngoài main"
want 2 Bash "$M" 'for t in a b; do echo x >/tmp/q-$u.log; done' "for-loop: biến chưa biết khác vẫn chặn"
want 2 Bash "$M" 'for t in a b; do echo x > $t; done' "for-loop: đích tương đối trong main (cwd = main)"
want 2 Bash "$M" 'for t in .a b; do echo x > $t; done' "for-loop: tiền tố '.' -> file trong main"
want 2 Bash "$M" "for t in ../main/a.txt; do echo x > $OUT/\$t; done" "for-loop: giá trị có ../ đi vào main"
want 2 Bash "$M" "for t in ../../main/a.txt; do echo x > $OUT/sub/\$t; done" "for-loop: ../.. thật vào main"
want 2 Bash "$M" "for t in a.txt; do echo x > $TMP/lnk/\$t; done" "for-loop: symlink vào main"
want 2 Bash "$M" "for t in a.txt; do ln -sfn $M $OUT/l; echo x > $OUT/l/\$t; done" "for-loop: ln cùng dòng"
want 2 Bash "$M" 'for t in a?; do echo x > /tmp/q-$t; done' "for-loop: ký tự ? trong giá trị"
want 2 Bash "$M" 'for t in *; do echo x > /tmp/q-$t; done' "for-loop: glob trong danh sách"
want 2 Bash "$M" 'for t in $(ls); do echo x > /tmp/q-$t; done' "for-loop: danh sách là thay thế lệnh"
want 2 Bash "$M" "for t in a b; do echo x > $M/\$t.txt; done" "for-loop: đích tuyệt đối trong main"
want 2 Bash "$M" 't=/tmp/ok; for t in a.txt; do echo x > $t; done' "for-loop: NAME còn được gán trước vòng lặp"
want 2 Bash "$M" 'for t in a.txt; do echo x > $t; t=/tmp/ok; done' "for-loop: NAME gán lại trong thân"
want 2 Bash "$M" 'for t in a.txt; do echo x > $t' "for-loop: thiếu done"
want 2 Bash "$M" 'echo x > $t; for t in /tmp/a; do :; done' "for-loop: redirect dùng \$t TRƯỚC vòng lặp"
want 2 Bash "$M" 'for t in /tmp/a; do :; done; echo x > $t' "for-loop: redirect dùng \$t SAU vòng lặp"
want 2 Bash "$M" 'for t in a; do for t in b; do echo x > /tmp/q-$t; done; done' "for-loop: hai vòng cùng tên"
want 2 Bash "$M" 'for a in 1 2 3 4 5 6 7 8 9; do for b in 1 2 3 4 5 6 7 8 9; do echo x > /tmp/q-$a-$b; done; done' "for-loop: quá 64 tổ hợp"
want 0 Bash "$M" 'for a in 1 2; do for b in x y; do echo x > /tmp/q-$a-$b; done; done' "for-loop: hai biến lồng nhau, ngoài main"
want 2 Bash "$M" 't=/tmp/ok; for t in $(ls); do echo x > $t; done' "for-loop: danh sách động, NAME đã gán trước đó"
# #1102 R1 (reviewer bounce): biến vòng lặp bị gán lại bằng lệnh nội bộ (không phải `NAME=`): giá trị đến từ file / stdin, hook không biết nó trỏ đâu
want 2 Bash "$M" 'for t in a; do read t < /tmp/p; echo x > /tmp/q-$t; done' "for-loop R1: read gán lại NAME"
want 2 Bash "$M" 'for t in a; do printf -v t %s "$(cat /tmp/p)"; echo x > /tmp/q-$t; done' "for-loop R1: printf -v gán lại NAME"
want 2 Bash "$M" 'for t in a; do mapfile -t t < /tmp/p; echo x > /tmp/q-$t; done' "for-loop R1: mapfile gán lại NAME"
want 2 Bash "$M" 'for t in a; do readarray t < /tmp/p; echo x > /tmp/q-$t; done' "for-loop R1: readarray gán lại NAME"
want 2 Bash "$M" 'for t in a; do declare t=$(cat /tmp/p); echo x > /tmp/q-$t; done' "for-loop R1: declare gán lại NAME"
want 2 Bash "$M" 'for t in a; do export t; read t < /tmp/p; echo x > /tmp/q-$t; done' "for-loop R1: export + read"
want 2 Bash "$M" 'for t in a; do getopts x t; echo x > /tmp/q-$t; done' "for-loop R1: getopts gán NAME"
want 2 Bash "$M" 'for t in a; do read -r a t < /tmp/p; echo x > /tmp/q-$t; done' "for-loop R1: read -r nhiều tên"
want 0 Bash "$M" 'for t in a b; do bash x.sh >/tmp/q-$t.log; done' "for-loop R1: ca đối chứng vẫn qua"
# #1102 R5 (reviewer bounce 3): for lồng cùng tên, đích hai biến, cờ gộp (`-vt`, `-at`) và `. file` gán NAME mà văn bản không có `t=`
want 2 Bash "$M" 'for t in a; do for t in $(cat /tmp/p); do echo x > /tmp/q-$t; done; done' "for-loop R5: vòng trong cùng tên, danh sách động"
want 2 Bash "$M" 'for t in a; do for t in b $(cat /tmp/p); do echo x > /tmp/q-$t; done; done' "for-loop R5: vòng trong cùng tên, danh sách lẫn"
want 2 Bash "$M" 'for a in 1; do for t in b; do echo x > /tmp/$a-$t; t=/tmp/ok; done; done' "for-loop R5: đích hai biến, NAME gán lại trong thân"
want 2 Bash "$M" 'for t in a; do printf -vt %s "$(cat /tmp/p)"; echo x > /tmp/q-$t; done' "for-loop R5: printf -vt (cờ gộp)"
want 2 Bash "$M" 'for t in a; do read -at < /tmp/p; echo x > /tmp/q-$t; done' "for-loop R5: read -at (cờ gộp)"
want 2 Bash "$M" 'for t in a; do . /tmp/p.sh; echo x > /tmp/q-$t; done' "for-loop R5: . file có thể gán NAME"
want 2 Bash "$M" 'for t in a; do source /tmp/p.sh; echo x > /tmp/q-$t; done' "for-loop R5: source file có thể gán NAME"
want 0 Bash "$M" 'for t in a b; do ./run.sh -v >/tmp/q-$t.log; done' "for-loop R5: ca đối chứng (./run.sh, cờ -v) vẫn qua"
# #1102 R6 (reviewer bounce 4): biến vòng bị đổi ngầm - eval, `{ . f; }`, ${t#..}, _ / REPLY / PWD, cd trong vòng, `for t; do`.
# cwd = $W2 (worktree, ngoài main): hook tưởng đích là tên tương đối an toàn, còn thực tế shell ghi vào main.
want 2 Bash "$W2" "for t in a; do eval \"t=$M/x\"; echo x > \$t; done" "for-loop R6a: eval gán NAME"
want 2 Bash "$W2" "for t in a; do { . /tmp/p.sh; }; echo x > \$t; done" "for-loop R6a: { . file; } gán NAME"
want 2 Bash "$W2" "for t in $M/a; do echo x > \${t#$M/}; cd $M; done" "for-loop R6b: \${t#..} cắt tiền tố"
want 2 Bash "$W2" "for t in a; do echo x > \${t:-$M/x}; done" "for-loop R6b: \${t:-..}"
want 2 Bash "$W2" "for _ in a; do echo x > \$_; done" "for-loop R6c: biến _ do shell đặt"
want 2 Bash "$W2" "for PWD in a; do echo x > \$PWD/f; done" "for-loop R6c: biến PWD"
want 2 Bash "$W2" "for REPLY in a; do echo x > \$REPLY; done" "for-loop R6c: biến REPLY"
want 2 Bash "$W2" "for t in a; do cd $M; echo x > q-\$t; done" "for-loop R6d: cd trong vòng, đích tương đối"
want 2 Bash "$W2" "for t in a; do pushd $M; echo x > q-\$t; done" "for-loop R6d: pushd trong vòng"
want 2 Bash "$W2" "for t; do echo x > q-\$t; done" "for-loop R6e: for t; do (không có in)"
want 0 Bash "$W2" 'for t in a b; do echo ${t} > /tmp/q-${t}.log; done' "for-loop R6: ca đối chứng \${t} vẫn qua"

# #1102 R7 (reviewer bounce 5, whitelist): `for t;` sau `t=`, `printf -v` khi vòng khác tên, `for` giả trong nháy, tên che bằng `$(..)` / nháy / `$'\x74'`.
want 2 Bash "$W2" "set -- $M/a.txt; t=/tmp/ok; for t; do echo x > \$t; done" "for-loop R7a: for t; sau t="
want 2 Bash "$W2" "t=/tmp/ok; for i in 1; do printf -v t $M/a.txt; echo x > \$t; done" "for-loop R7b: printf -v khi vòng khác tên"
want 2 Bash "$W2" "for t in a.txt; do echo \"; for p in /tmp/out; do\" > \$p$M/\$t; echo done; done" "for-loop R7c: for giả trong nháy"
want 2 Bash "$W2" "t=/tmp/ok; printf -v \$(basename /t) $M/a.txt; echo x > \$t" "for-loop R7d: printf -v \$(..)"
want 2 Bash "$W2" "t=/tmp/ok; printf -v t\"f\" $M/a.txt; echo x > \$t" "for-loop R7d: printf -v t\"f\""
want 2 Bash "$W2" "t=/tmp/ok; declare t\"f\"=$M/a.txt; echo x > \$t" "for-loop R7d: declare t\"f\"="
want 2 Bash "$W2" "t=/tmp/ok; printf -v \$'\\x74' $M/a.txt; echo x > \$t" "for-loop R7d: printf -v \$'\\x74'"
want 0 Bash "$W2" 'for t in a b; do echo x > /tmp/q-$t.log; done' "for-loop R7: ca đối chứng vẫn qua"

# hiệu năng: thư mục đích có hàng nghìn entry - hook không liệt kê / glob thư mục, nên không chậm đáng kể
BIG="$TMP/big"; mkdir -p "$BIG"; python3 -I -c 'import sys; [open(sys.argv[1] + "/q-%d.log" % i, "w").close() for i in range(5000)]' "$BIG"
T0=$(python3 -I -c 'import time; print(time.time())')
want 0 Bash "$M" "for t in a b c; do echo x > $BIG/q-\$t.log; done" "for-loop: thư mục 5000 entry vẫn qua"
T1=$(python3 -I -c 'import time; print(time.time())')
python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[2]) - float(sys.argv[1]) < 3.0 else 1)' "$T0" "$T1" && ok "for-loop: thư mục lớn không làm hook chậm (<3 s)" || fail "for-loop: thư mục lớn làm hook chậm"

# (b) công cụ sửa file của Grok
for T in search_replace hashline_edit; do
  want 2 "$T" "$M" "" "$T vào a.txt của checkout chính (file_path)" '{"file_path":"'"$M"'/a.txt","old_string":"a","new_string":"b"}'
  want 2 "$T" "$M" "" "$T vào checkout chính (khoá path)" '{"path":"'"$M"'/a.txt"}'
  want 0 "$T" "$W2" "" "$T vào worktree" '{"file_path":"'"$W2"'/a.txt","old_string":"a","new_string":"b"}'
done

[ "$FAILS" = 0 ] && { echo "OK"; exit 0; } || { echo "$FAILS fail"; exit 1; }
