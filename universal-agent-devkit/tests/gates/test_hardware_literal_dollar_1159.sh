#!/usr/bin/env bash
# #1159: hooks/hardware_safety_gate.sh chặn nhầm bash -c '"$"rm -rf ~' từ #1076 (#830, rm_var_command). Lexer bỏ nháy nên "$"rm thành
# chữ $rm như "$rm"; nhưng "$" là một $ CHỮ trong sh, bash, zsh (cả trong bash -c "…", eval, heredoc: đo bằng printf 13/11), lệnh chạy là
# chương trình tên $rm, không phải rm. Sửa: chữ có mọi $ là "$" (literal_dollar_words) không phải biến chứa tên lệnh.
# Hai chiều: "$"rm qua; mọi dạng tên lệnh từ biến của #830 vẫn bị chặn, kể cả khi shell chạy lệnh mở lại $rm (eval, sudo -s, ssh,
# bash -c "\$rm", heredoc không nháy) và chuỗi locale ""$"rm" (bash đọc là rm). '$'rm và \$rm ở mức ngoài cùng vẫn bị chặn (ponytail của sửa
# này, không ghim trong test). Hook thật, chỉ nạp JSON trên stdin (không lệnh nào được chạy), fixture mktemp.
# HW_HOOK=<đường dẫn hook> chạy bản hook khác (bản chưa sửa: ĐỎ ở ca cho qua; bản nới '$' / \$ ở mọi mức: ĐỎ ở ca lồng).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset HARDWARE_SAFETY_GATE HARDWARE_OVERRIDE CDPATH
P="$TMP/work/proj"
mkdir -p "$P"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'z\n' > "$P/README.md"
git -C "$P" add -A && git -C "$P" commit -qm init
FAILS=0
N=0

# check <rc chờ> <lệnh>: rc của hook. Hook văng lỗi (Traceback, lỗi nội bộ) tính là lỗi riêng, không bao giờ là rc 2 mà ca chờ.
check() {
  local want="$1" c="$2" rc
  N=$((N + 1))
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$HW" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  rc=$?
  if grep -q -E 'Traceback|lỗi nội bộ|python không chạy được|không nạp được' "$TMP/err"; then
    echo "✖ crash: $c — $(head -c 200 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; FAILS=$((FAILS + 1)); return
  fi
  if [ "$rc" = "$want" ]; then echo "✔ rc $rc: $c"
  else echo "✖ rc $rc (want $want): $c — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; FAILS=$((FAILS + 1)); fi
}

# Ca: <rc chờ><TAB><lệnh>, mỗi dòng một ca (heredoc nháy đơn: mọi ký tự giữ nguyên như gõ). \n trong lệnh là xuống dòng.
while IFS=$'\t' read -r want c; do
  case "$want" in ""|\#*) [ -n "$want" ] && echo "   ${want#\# }"; continue ;; esac
  check "$want" "$(printf '%b' "$c")"
done <<'CASES'
# "$" là $ chữ: chương trình tên $rm, không phải rm (#1159)
0	bash -c '"$"rm -rf ~'
0	"$"rm -rf ~
0	"$"rm -rf ~/x
0	sh -c '"$"rm -rf ~'
0	eval '"$"rm -rf ~'
0	"$"{rm} -rf ~
0	"$"'rm' -rf ~
0	bash -c "\"$\"rm -rf ~"
# tên lệnh từ biến (#830 / #1076) vẫn bị chặn
2	$rm -rf ~
2	${rm} -rf ~
2	"$rm" -rf ~
2	"${rm}" -rf ~
2	$RM -rf ~
2	${x:-rm} -rf ~
2	$X$Y -rf ~
2	bash -c '$rm -rf ~'
# chuỗi locale: bash đọc $"rm" là rm, kể cả sau "" hay '' (chuỗi rỗng)
2	""$"rm" -rf ~
2	''$"rm" -rf ~
2	bash -c '""$"rm" -rf ~'
# shell chạy lệnh mở lại $rm: cờ "$ chữ" không được lọt qua phép nối / lex mới
2	eval "$"rm -rf ~
2	eval \\$rm -rf ~
2	eval '$rm' -rf ~
2	eval "\\$rm -rf ~"
2	sudo -s "$"rm -rf ~
2	bash -c "\\$rm -rf ~"
2	bash -c "'$rm' -rf ~"
2	bash -c "$"'rm -rf ~'
2	bash <<EOF\n\\$rm -rf ~\nEOF
2	bash <<EOF\n'$rm' -rf ~\nEOF
CASES

# Đơn vị: literal_dollar_words theo dõi nháy như shell. Ở trên, chuỗi locale còn được cách đọc đã giải mã của #844 chặn; ở đây chính bộ
# quét không được đánh dấu $ của $"…" (ngoài nháy kép) hay $ trong nháy đơn. Nạp module với lệnh vô hại `true`, tắt hẹn giờ 7 s của nó.
echo "   literal_dollar_words (đơn vị)"
UNIT=$(cd "$P" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"true"}}' | REPO_ROOT="$P" XDG_CONFIG_HOME="$TMP/xdg" python3 -I -c '
import importlib.util, os, signal, sys
d = sys.argv[1]
sys.path.append(d)
spec = importlib.util.spec_from_file_location("hw_unit", os.path.join(d, "hardware_safety_gate_main.py"))
m = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
except SystemExit:
    pass
signal.setitimer(signal.ITIMER_REAL, 0)
sys.excepthook = sys.__excepthook__
import shell_norm
cases = [("\"$\"rm -rf ~", [True, False, False]), ("\"\"$\"rm\" -rf ~", [False, False, False]),
         ("\x27\"\x27$\"rm\" -rf ~", [False, False, False]), ("x=\x27\"$\"\x27 \"$\"rm", [False, True]),
         ("\"$\"{rm} x", [True, False]), ("\"$\"$rm", [False]), ("\"$x\" \"$\"y", [False, True]),
         ("\"$\"rm $(true)", [False, False, False, False, False])]
for text, want in cases:
    got = [isinstance(w, m.LiteralDollar) for w in m.literal_dollar_words(text, shell_norm.lex_words(text))]
    print(("✔" if got == want else "✖") + " literal_dollar_words(%r) = %r (want %r)" % (text, got, want))
' "$(dirname "$HW")" 2>&1)
printf '%s\n' "$UNIT"
N=$((N + 8))
FAILS=$((FAILS + $(printf '%s\n' "$UNIT" | grep -c -v '^✔')))

echo "cases: $N"
echo "FAILS=$FAILS"
if [ "$FAILS" -eq 0 ]; then echo "PASS: test_hardware_literal_dollar_1159"; exit 0; fi
echo "FAIL: test_hardware_literal_dollar_1159 ($FAILS)"; exit 1
