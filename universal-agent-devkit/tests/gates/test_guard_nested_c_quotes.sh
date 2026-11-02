#!/usr/bin/env bash
# #844 (lane r31quote): giải mã nháy trong script lồng bash -c / sh -c của hooks/shell_norm.py.
#   (a) $"…" (chuỗi locale): bash, sh và ksh đọc $"rm" là rm; shlex đọc là $rm, nên bash -c '$"rm" -rf ~' lọt cả hai guard.
#   (b) trong nháy kép bash bỏ \ trước $, shlex giữ: script của bash -c "\$'rm' -rf ~" là $'rm' -rf ~ (= rm), lexer đọc \$'rm' (= $rm).
# Sửa: shell_norm.readings thêm MỘT cách đọc đã giải mã ($"…" thành "…", KHÔNG BAO GIỜ '…'; \$ trước nháy, trong "…", thành $) bên cạnh cách đọc cũ,
# chặn khi bất kỳ cách đọc nào chặn: không lệnh nào lỏng hơn trước. Hai chiều: dạng lọt bị chặn, lệnh hợp lệ (corpus tìm kiếm rg / grep -E /
# git grep / sed có chữ adb / git / rm trong nháy) vẫn qua. Hook thật, chỉ nạp JSON trên stdin (không lệnh nào được chạy), fixture mktemp.
# GG_HOOK / HW_HOOK trỏ sang một bản khác của hooks/ (đo ĐỎ trên code cũ, mutation).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
NORM_DIR="$(dirname "$GG")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset HARDWARE_SAFETY_GATE HARDWARE_OVERRIDE DEVKIT_ALLOW_BRANCH CDPATH
P="$TMP/work/proj"
mkdir -p "$P"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'z\n' > "$P/README.md"
git -C "$P" add -A && git -C "$P" commit -qm init
FAILS=0
N=0

# run <hook> <lệnh>: rc của hook. Hook văng lỗi thì chặn để an toàn (rc 2, "lỗi nội bộ" / "không nạp được shell_norm.py" qua excepthook):
# tính là một lỗi riêng, không bao giờ là rc 2 mà ca chờ (INSTINCT-032: crash bị tính là pass). Biến chính sách thiết bị của phiên bị xoá.
run() {
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$2" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$1" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if grep -q -E 'Traceback|lỗi nội bộ|python không chạy được|không nạp được .*shell_norm' "$TMP/err"; then
    echo "✖ crash: $2 — $(head -c 200 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; FAILS=$((FAILS + 1))
  fi
  return "$rc"
}

# check <rc chờ> <GG|HW|BOTH> <lệnh>: BOTH = rc 0 ở cả hai guard
check() {
  local want="$1" which="$2" c="$3" h rc
  N=$((N + 1))
  case "$which" in GG) set -- "$GG" ;; HW) set -- "$HW" ;; BOTH) set -- "$GG" "$HW" ;; *) echo "✖ bad case: $which"; FAILS=$((FAILS + 1)); return ;; esac
  for h in "$@"; do
    run "$h" "$c"; rc=$?
    if [ "$rc" = "$want" ]; then echo "✔ rc $rc $(basename "$h" .sh): $c"
    else echo "✖ rc $rc (want $want) $(basename "$h" .sh): $c — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; FAILS=$((FAILS + 1)); fi
  done
}

# Ca: <rc chờ><TAB><guard><TAB><lệnh>, mỗi dòng một ca (heredoc nháy đơn: mọi ký tự giữ nguyên như gõ).
while IFS=$'\t' read -r want which c; do
  case "$want" in ""|\#*) [ -n "$want" ] && echo "   ${want#\# }"; continue ;; esac
  check "$want" "$which" "$c"
done <<'CASES'
# 4 dạng lọt của #844 (phản biện 01/11) bị chặn
2	HW	bash -c "\$'rm' -rf ~"
2	HW	bash -c '$"rm" -rf ~'
2	GG	bash -c 'g$"it" reset --hard'
2	GG	bash -c 'git $"push" origin --force main'
# đang bị chặn, phải vẫn bị chặn (bẫy nếu $"…" thành '…': thân nháy kép, $( ) chạy)
2	GG	echo $"$(git reset --hard)"
2	GG	bash -c 'echo $"$(git reset --hard)"'
2	HW	bash -c 'echo $"$(rm -rf ~)"'
# cùng họ: shell khác, cờ gộp, su / sudo / timeout / env / eval / xargs, lồng hai tầng, \$" trong nháy kép, escape số trong $'…'
2	HW	sh -c '$"rm" -rf ~'
2	HW	bash -lc '$"rm" -rf ~'
2	HW	su -c '$"rm" -rf ~'
2	HW	sudo bash -c '$"rm" -rf ~'
2	HW	timeout 5 bash -c '$"rm" -rf ~'
2	HW	env bash -c '$"rm" -rf ~'
2	HW	eval '$"rm" -rf ~'
2	HW	eval "\$'rm' -rf ~"
2	HW	echo x | xargs $"rm" -rf ~
2	HW	bash -c 'bash -c "\$'"'"'rm'"'"' -rf ~"'
2	HW	bash -c 'bash -c '"'"'$"rm" -rf ~'"'"''
2	HW	bash -c "\$\"rm\" -rf ~"
2	HW	bash -c "\$'r'm -rf ~"
2	HW	bash -c "\$'\\x72m' -rf ~"
2	HW	bash -c 'x=1 $"rm" -rf ~'
2	HW	bash -c '$"rm"$"" -rf ~'
2	HW	bash -c '$"rm" -rf ~ #x'
2	HW	$"rm" -rf ~
2	GG	bash -c "git \$\"push\" --force origin main"
2	GG	g$"it" reset --hard
2	GG	git $"push" origin --force main
2	GG	bash -c 'true; $"git" push --force origin main'
# plan_review T0001 (blocker 2): $( ) và backtick trong "…" mở lại ngữ cảnh lệnh; một " trong '…' bên trong "$( )" không đóng chuỗi ngoài
2	HW	echo "$( $"rm" -rf ~ )"
2	HW	echo "`$"rm" -rf ~`"
2	HW	echo "$( (cd x); $"rm" -rf ~ )"
2	HW	echo "$(echo '"')"; $"rm" -rf ~
2	HW	bash -c 'echo "$(echo '\''"'\'')"; $"rm" -rf ~'
# ${ … } (cả trong "…"): bash ghép '…' và lồng "…" trong đó (đo bash 3.2: "${x:-'"'}" là một từ, lệnh sau nó chạy)
2	HW	printf '<%s>' "${x:-'"'}"; $"rm" -rf ~
2	HW	printf '<%s>' "${x:-"a b"}"; $"rm" -rf ~
2	HW	printf '<%s>' "${x:-"}"}"; $"rm" -rf ~
2	HW	bash -c 'printf "<%s>" "${x:-'\''"'\''}"; $"rm" -rf ~'
2	HW	echo "$${x}"; $"rm" -rf ~
2	HW	echo "${x:-$(echo '"')}"; $"rm" -rf ~
# plan_review T0001 v2: ${ … } trong "…" vẫn theo quy tắc \$ của nháy kép (bash, sh, zsh)
2	HW	bash -c "${UNSET_VAR:-true; \$'rm' -rf ~; :}"
2	HW	bash -c "${UNSET_VAR:-true; \$\"rm\" -rf ~; :}"
2	GG	bash -c "${UNSET_VAR:-true; g\$\"it\" reset --hard; :}"
# $$ rồi ( / {: zsh và ksh đọc PID và chữ (" đóng chuỗi), bash 3.2 ghép ngoặc: cả hai cách đều được xét
2	HW	printf '<%s>' "$${"; bash -c "\$'rm' -rf ~"
2	HW	ksh -c 'printf "<%s>" "$$("; $"rm" -rf ~'
2	GG	ksh -c 'printf "<%s>" "$$("; g$"it" reset --hard'
2	HW	printf '<%s>' "$${x:-'"'}"; $"rm" -rf ~
2	HW	printf '<%s>' "$$(echo '"')"; $"rm" -rf ~
# plan_review T0001 v3: ' trong "${ … }" là chữ với zsh / ksh (bash 3.2 ghép cặp); ( trần trong ${ } hay `…` là chữ
2	HW	printf '<%s>' "${msg:-don't}"; bash -c "\$'rm' -rf ~"
2	GG	printf '<%s>' "${msg:-don't}"; bash -c "g\$\"it\" reset --hard"
2	HW	bash -c "${UNSET_VAR:-echo \"don't\" >/dev/null; \$'rm' -rf ~}"
2	HW	ksh -c 'printf "<%s>" "${msg:-don'\''t}"; $"rm" -rf ~'
2	GG	ksh -c 'printf "<%s>" "${msg:-don'\''t}"; g$"it" reset --hard'
2	HW	bash -c 'printf "<%s>" "${x:-(}"; $"rm" -rf ~'
2	GG	bash -c 'printf "<%s>" "${x:-(}"; g$"it" reset --hard'
2	GG	bash -c 'printf "<%s>" "${x:-(}"; git $"push" origin --force main'
2	HW	echo "`printf '%s' ${x:-(}`"; $"rm" -rf ~
# plan_review T0001 v4: một $"" / $"|" / $";" vô hại ở chỗ khác không được tắt giải mã cả dòng (van theo từng từ)
2	HW	echo $""; bash -c "\$'rm' -rf ~"
2	HW	grep -F $"|" README.md; bash -c "\$'rm' -rf ~"
2	HW	bash -c 'echo $""; $"rm" -rf ~'
2	HW	bash -c 'printf "%s" $"|"; $"rm" -rf ~'
2	GG	bash -c 'echo $""; g$"it" reset --hard'
2	GG	bash -c 'printf "%s" $";"; g$"it" reset --hard'
2	GG	bash -c 'printf "%s" $""; git $"push" origin --force main'
2	GG	bash -c 'printf "%s" $"&&"; git $"push" origin --force main'
2	HW	echo $"{" ; $"rm" -rf ~
# lệnh hợp lệ trong bash -c qua cả hai guard (hai lệnh bắt buộc của thẻ trước)
0	BOTH	bash -c 'echo hello'
0	BOTH	bash -c "printf '%s' \$'a\tb'"
0	BOTH	bash -c '$$"rm" -rf ~'
0	BOTH	bash -c '"$"rm -rf ~'
0	BOTH	bash -c 'echo "a$"rm -rf ~'
0	BOTH	bash -c 'echo $"hello"'
0	BOTH	bash -c 'echo $"rm -rf ~"'
0	BOTH	bash -c 'printf "%s\n" $"git push --force"'
0	BOTH	bash -c "printf '%s\n' \$\"rm -rf ~\""
0	BOTH	bash -c "echo \$'rm -rf ~'"
0	BOTH	bash -c "echo \$\$\"rm\" -rf"
0	BOTH	bash -c 'adb $"devices"'
# corpus tìm kiếm: rg / grep -E / git grep / sed có chữ adb / git / rm và $"…" / \$'…' trong nháy (luật hội tụ 3) — main cho qua, phải vẫn qua
0	BOTH	rg "git push --force" .
0	BOTH	rg '$"rm -rf"' .
0	BOTH	rg "\$'rm' -rf" .
0	BOTH	rg -n '\$"git reset --hard"' universal-agent-devkit/hooks
0	BOTH	rg -n "bash -c \"\\\$'rm' -rf ~\"" .
0	BOTH	rg -n 'bash -c .\$"rm"' .
0	BOTH	rg "\$'adb' reboot" .
0	BOTH	rg -n "bash -c '\\\$\"rm\" -rf ~'" .
0	BOTH	rg -n "eval '\$\"rm\" -rf ~'" .
0	BOTH	grep -E "\$'rm'" README.md
0	BOTH	grep -E '\$"git reset --hard"' README.md
0	BOTH	grep -E "adb -s \$\"\" reboot" README.md
0	BOTH	grep -rn 'bash -c .\$"rm"' .
0	BOTH	grep -En "g\\\$\"it\" (reset|push)" README.md
0	BOTH	grep -n "\$\"rm\" -rf ~" README.md
0	BOTH	grep -E '(rm|git|adb)\$"' README.md
0	BOTH	git grep -n '$"rm" -rf' -- '*.sh'
0	BOTH	git grep -n "\$'git' reset --hard"
0	BOTH	git grep -E 'git \$"push" origin --force'
0	BOTH	sed -n 's/\$"rm"/x/p' README.md
0	BOTH	sed -n "s/\$'rm'/x/p" README.md
0	BOTH	sed -n '/\$"git push --force"/p' README.md
0	BOTH	sed -E 's/(adb|git|rm) \$"[a-z]+"/X/' README.md
0	BOTH	bash -c 'grep -E "\$\"rm\"" README.md'
0	BOTH	bash -c "rg -n '\$\"git push\"' ."
0	BOTH	bash -c "grep -n \"git reset --hard\" README.md"
0	BOTH	sh -c 'rg "\$\"rm -rf ~\"" .'
0	BOTH	bash -c "rg -n 'adb shell rm' ."
# plan_review T0001 (blocker 1): \$ NGOÀI nháy kép là $ chữ (bash: \$'\' là $\): không đọc thành $'…' (nháy mở sẽ nuốt tham số sau)
0	BOTH	rg \$'\' 'git reset --hard'
0	BOTH	git grep -F \$'\' -- 'git push --force'
0	BOTH	rg \$'\' '; rm -rf ~'
0	BOTH	bash -c "rg \\$'\\' 'git reset --hard'"
0	BOTH	bash -c "rg \\$'\\' '; rm -rf ~'"
0	BOTH	grep -E "\$\(rm -rf" README.md
0	BOTH	printf '%s\n' "\$'rm'" "\$\"git\""
0	BOTH	rg "\${x:-\$\"rm\"}" .
0	BOTH	grep -E '\$\{[a-z]+:-\$"' README.md
0	BOTH	printf '<%s>' "${x:-$"q"}"
0	BOTH	echo "${HOME}" $"rm"
0	BOTH	grep -F "$${" README.md; git grep -F \$'\' -- 'git push --force'
0	BOTH	grep -F "$${" README.md; rg \$'\' '; rm -rf ~'
0	BOTH	git grep -F ${x:-\$'\'} -- 'git push --force'
0	BOTH	echo "${msg:-don't}" "it's"; git grep -F \$'\' -- 'git push --force'
0	BOTH	grep -F "${msg:-don't}" README.md; grep -F "it's" README.md; rg \$'\' '; rm -rf ~'
0	BOTH	printf '<%s>' "${x:-'"'}"; git grep -F \$'\' -- 'git push --force'
0	BOTH	grep -F "${a:-don't}" README.md; grep -F ' }' README.md; rg \$'\' 'git reset --hard'; grep -F '"' README.md
0	BOTH	echo "${x:-(}"; git grep -F \$'\' -- 'git push --force'
0	BOTH	echo "${x:-(}"; rg \$'\' '; rm -rf ~'
0	BOTH	echo "${msg:-don't}"; rg -n "it's" README.md
0	BOTH	grep -F "${x:-(}" README.md
# van ranh giới từ: bỏ $ làm một từ trong nháy thành thứ lexer trả giống từ ngăn cách ("(;" "|" "&&") hay thành từ rỗng: không thêm cách đọc
0	BOTH	echo $"(;" rm -rf ~
0	BOTH	echo $"|" git reset --hard
0	BOTH	printf '%s\n' $"&&" git push --force origin main
0	BOTH	echo $"" rm -rf ~
# plan_review T0001 v4: { } (từ ngăn cách của guard) và chuyển hướng cũng là cú pháp với van
0	BOTH	rg -F $"{" git reset --hard
0	BOTH	grep -F $"}" git push --force
0	BOTH	git grep -F $"{" git reset --hard
0	BOTH	git grep -F $"}" git push --force origin main
0	BOTH	sed -n "p" $"{" git reset --hard
0	BOTH	echo $"{" git reset --hard
0	BOTH	echo $"}" git push --force origin main
0	BOTH	echo "${m:-don't}" "it's"; git grep -F \$'{' git reset --hard
0	BOTH	trap "rm -rf build" EXIT; echo $"{" ; trap - EXIT; cd ~
0	BOTH	rg -F $">>" src/main.py
0	BOTH	echo $">" rm -rf ~
0	BOTH	echo $"2>" git reset --hard
0	BOTH	echo $"!" git reset --hard
# plan_review T0001 v5 / v6: chế độ quét lệch nháy ("${x:-'"'}" của bash, "${m:-don't}" của zsh) không được sửa vào script nháy đơn phía sau, kể cả khi nháy tự cân lại cuối dòng
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; bash -c 'grep -F -e \$'\''\'\'' -e '\''; rm -rf ~'\'' README.md'
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; bash -c 'git grep -F \$'\''\'\'' -- '\''git reset --hard'\'''
0	BOTH	echo "${m:-don't}" "it's"; bash -c 'grep -F -e \$'\''\'\'' -e '\''; rm -rf ~'\'' README.md'
0	BOTH	echo "${m:-don't}" "it's"; bash -c 'git grep -F \$'\''\'\'' -- '\''git reset --hard'\'''
0	BOTH	echo "${m:-don't}" "it's"; bash -c 'sed -n '\''/git push --force/p'\'' README.md; printf "%s\n" \$'\''\'\'' '\''git push --force'\'''
0	BOTH	grep -F "${m:-don't}" README.md; grep -F \' README.md; grep -F a} README.md; bash -c 'git grep -F \$'\''\'\'' -- '\''git reset --hard'\'''; grep -F '"' README.md; grep -F \' README.md
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; rg \$'\'; rg '; git reset --hard ' README.md \$'\'
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; rg \$'\' README.md; rg 'a b ; rm -rf ~' \$'\' README.md
0	BOTH	echo "${m:-don't}" "it's"; rg \$'\'; rg '; git reset --hard ' README.md \$'\'
0	BOTH	echo "${m:-don't}" "it's"; rg \$'\' README.md; rg 'a b ; rm -rf ~' \$'\' README.md
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; bash -c 'rg -F $"{" git reset --hard'; grep -F '}"}"'\' README.md
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; bash -c 'git grep -F $"|" git reset --hard'; grep -F '}"}"'\' README.md
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; bash -c 'sed -n "/p/p" $"{" git push --force'; grep -F '}"}"'\' README.md
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; bash -c 'grep -E $"&&" rm -rf ~'; grep -F '}"}"'\' README.md
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; bash -c 'echo $"" rm -rf ~'; grep -F '}"}"'\' README.md
0	BOTH	echo "${m:-don't}"; bash -c 'rg -F $"{" git reset --hard'; grep -F '}' '"' \' README.md
0	BOTH	echo "${m:-don't}"; bash -c 'git grep -F $"|" git reset --hard'; grep -F '}' '"' \' README.md
0	BOTH	echo "${m:-don't}"; bash -c 'sed -n "/p/p" $"{" git push --force'; grep -F '}' '"' \' README.md
0	BOTH	echo "${m:-don't}"; bash -c 'grep -E $"&&" rm -rf ~'; grep -F '}' '"' \' README.md
0	BOTH	echo "${m:-don't}"; bash -c 'echo $"" rm -rf ~'; grep -F '}' '"' \' README.md
0	BOTH	printf '<%s>' "${x:-'"'}"; bash -c 'echo $"" rm -rf ~'; grep -F '}"'\'\" README.md
0	BOTH	printf '<%s>' "${x:-'"'}" "${y:-'"'}"; bash -c 'echo $"|" git reset --hard'
0	BOTH	echo "${m:-don't}" "it's"; bash -c 'echo $"|" git reset --hard'
0	BOTH	printf '<%s>' "${x:-'"'}"; bash -c 'echo $"" rm -rf ~'
0	BOTH	echo "${m:-don't}"; bash -c 'printf %s $"{" git reset --hard'
# lệnh thường có $"…" / \$ ở cấp ngoài cùng
0	BOTH	echo $"Hello world"
0	BOTH	echo $"rm -rf ~ is dangerous"
0	BOTH	printf $"%s\n" "rm -rf ~"
0	BOTH	printf '%s\n' $"git reset --hard"
0	BOTH	echo \$"rm -rf ~"
0	BOTH	echo "\$'rm' -rf ~"
0	BOTH	echo "\$\"git\" reset --hard"
0	BOTH	git commit -m $"fix: rm -rf handling"
0	BOTH	git log --grep $"reset --hard"
0	BOTH	x=$"hello"; echo "$x"
0	BOTH	ls $"build"
0	BOTH	cat $"README.md"
0	BOTH	git status $"README.md"
0	BOTH	git diff -- $"README.md"
0	BOTH	git add $"README.md"
0	BOTH	rm $"README.md"
0	BOTH	adb $"devices"
0	BOTH	adb -s $"emulator-5554" shell ls
CASES
echo "   nhiều dòng (plan_review T0001): \$( không đóng ở dòng trước, \" trong '…' trong \"\$( )\" ở dòng sau"
check 2 GG $'echo $( ;\n echo "$(echo \'"\')"; g$"it" switch -c evil'
echo "   comment trong backtick (plan_review T0001 v6): # \${ không mở \${ … }"
check 2 HW $'x=`# ${\necho ok`; bash -c "\\$\'rm\' -rf ~"'
check 2 HW $'x=`# ${\necho ok`; $"rm" -rf ~'
echo "   plan_review T0001 v7, blocker 1: tách thô (lexer lỗi, hay \" lồng trong \"\$( )\") bỏ nháy, \$ của \$\"{\" / \$\"\" vẫn được giữ"
check 0 BOTH $'echo "${x:-"a\'b"}"; rg -F $"{" git switch -c x'
check 0 BOTH $'echo "${x:-"a\'b"}"; grep -E $"{" git switch -c x'
check 0 BOTH $'echo "${x:-"a\'b"}"; git grep -F $"}" git switch -c x'
check 0 BOTH $'echo "${x:-"a\'b"}"; sed -n "p" $"{" git switch -c x'
check 0 BOTH $'echo "${x:-"a\'b"}"\ngit grep -F $"}" git switch -c x'
check 0 BOTH 'x="$(rg -F "a b" $"" rm -rf ~)"'
check 0 BOTH 'x="$(grep -E "a b" $"" rm -rf ~)"'
check 0 BOTH 'x="$(sed -n "s/a/b/p" $"" rm -rf ~)"'
check 0 BOTH 'echo "$(echo "a b" $"" rm -rf ~)"'
check 2 HW 'echo "$(echo "a b"; $"rm" -rf ~)"'
check 2 HW $'echo "${x:-"a\'b"}"; $"rm" -rf ~'
echo "   plan_review T0001 v7, blocker 2: # chỉ là comment ở đầu từ như drop_comments (không sau \\ , CR, \` đóng; trong \`…\` dừng ở \` đóng)"
check 2 HW $'x=`# ${`; bash -c "\\$\'rm\' -rf ~"'
check 2 HW $'x=`echo a # note`; bash -c "\\$\'rm\' -rf ~"'
check 2 HW $'x=`echo a # note`; $"rm" -rf ~'
check 2 HW $'echo "v: `echo a # note`"\nbash -c "\\$\'rm\' -rf ~"'
check 2 HW $'echo \\ #; bash -c "\\$\'rm\' -rf ~"'
check 2 GG $'echo \\ #; bash -c "g\\$\\"it\\" reset --hard"'
check 2 HW $'echo a\r#; bash -c "\\$\'rm\' -rf ~"'
check 2 GG $'echo a\r#; bash -c "g\\$\\"it\\" reset --hard"'
check 2 HW $'x=`true`#; bash -c "\\$\'rm\' -rf ~"'
echo "   review PR (OCR, Claude): cách đọc thêm không để lại trạng thái (DEVKIT_ALLOW_BRANCH) cho cách đọc gốc — main chặn thì vẫn chặn"
check 2 GG $'bash -c \'export $"DEVKIT_ALLOW_BRANCH=1"\'; git switch -c evil'
check 2 GG 'x=$(export $"DEVKIT_ALLOW_BRANCH=1"); git switch -c evil'
check 2 GG $'eval \'export $"DEVKIT_ALLOW_BRANCH=1"\'; git switch -c evil'
check 2 GG 'echo "$(export $"DEVKIT_ALLOW_BRANCH=1")"; git checkout -b evil'
check 2 GG $'sh -c \'export $"DEVKIT_ALLOW_BRANCH=1"\'; git worktree add ../x'
check 0 GG 'export DEVKIT_ALLOW_BRANCH=1; git switch -c ok'

echo "   locale_to_double (public, lane T4 dùng): bỏ \$ của \$\"…\" ngoài nháy, không bao giờ sinh nháy đơn"
python3 -I - "$NORM_DIR" <<'PY' || FAILS=$((FAILS + 1))
import sys
sys.path.insert(0, sys.argv[1])
import shell_norm as s
cases = [
    ('$"rm" -rf ~', '"rm" -rf ~'),
    ('g$"it" reset --hard', 'g"it" reset --hard'),
    ('x$"a"$"b"', 'x"a""b"'),
    ('echo $"$(git reset --hard)"', 'echo "$(git reset --hard)"'),   # bẫy: thân nháy kép giữ nguyên, không thành nháy đơn
    ('$$"x"', '$$"x"'),          # $$ là PID, "x" nháy thường
    ('$$$"x"', '$$"x"'),         # dãy $ chẵn trước nó: chỗ bắt đầu
    ('"a$"b', '"a$"b'),          # trong nháy kép: không phải chỗ bắt đầu
    ("'$\"x\"'", "'$\"x\"'"),    # trong nháy đơn
    ("$'a$\"b'", "$'a$\"b'"),    # trong thân $'…'
    ("$'a\\'$\"b' $\"c\"", "$'a\\'$\"b' \"c\""),   # \' trong $'…' không đóng nó
    ('\\$"x"', '\\$"x"'),        # $ đã escape
    ('no dollar quote here', 'no dollar quote here'),
    ('echo "$( $"rm" -rf ~ )"', 'echo "$( "rm" -rf ~ )"'),                 # $( ) trong "…" là ngữ cảnh lệnh
    ('echo "`$"rm" -rf ~`"', 'echo "`"rm" -rf ~`"'),                       # backtick trong "…" cũng vậy
    ('echo "`echo a`$"x""', 'echo "`echo a`$"x""'),                         # backtick đã đóng: lại trong "…", $" là chữ
    ('echo "$( (cd x); $"rm" )"', 'echo "$( (cd x); "rm" )"'),             # ( ) trong $( ) không đóng $( ) sớm
    ("echo \"$(echo '\"')\"; $\"rm\"", "echo \"$(echo '\"')\"; \"rm\""),   # " trong '…' trong "$( )" không đóng chuỗi ngoài
    ('echo "$(echo "a$"b")"', 'echo "$(echo "a$"b")"'),                    # trong "…" lồng: không giải mã
    ('"${x:-$"q"}"', '"${x:-"q"}"'),                                         # ${ } trong "…": bash đọc $"q" là q
    ('"${x:-(}"; $"rm"', '"${x:-(}"; "rm"'),                                 # ( trần trong ${ } là chữ, } vẫn đóng
    ('"${U:-\\$"q"}"', '"${U:-\\$"q"}"'),                                     # \$ trong ${ } của "…": locale_to_double không bỏ \ (chỉ _decoded)
    ("\"${msg:-don't}\"; $\"rm\"", "\"${msg:-don't}\"; \"rm\""),             # zsh, ksh: ' trong "${ }" là chữ (mặc định)
    ('"$${x}"; $"rm"', '"$${x}"; "rm"'),
    ('"$${"; $"rm"', '"$${"; "rm"'),      # zsh, ksh: $$ là PID, { chữ, " đóng chuỗi, lệnh sau chạy (mặc định)
    ('"$$("; $"rm"', '"$$("; "rm"'),      # $( cũng vậy
    ('x=`echo a # note`; $"rm" -rf ~', 'x=`echo a # note`; "rm" -rf ~'),   # v7: comment trong `…` dừng ở ` đóng
    ('echo a\\\n#; $"rm" -rf ~', 'echo a\\\n#; "rm" -rf ~'),               # v7: # sau a\<nl> (nối dòng) nối vào từ a, không phải comment
    ('echo \\ #; $"rm" -rf ~', 'echo \\ #; "rm" -rf ~'),                     # v7: # sau dấu cách đã escape là chữ
    ('x=`true`#; $"rm" -rf ~', 'x=`true`#; "rm" -rf ~'),                     # v7: # ngay sau ` đóng là chữ
    ('echo a\r#; $"rm" -rf ~', 'echo a\r#; "rm" -rf ~'),                     # v7: CR không tách từ
]
bad = 0
fn = getattr(s, "locale_to_double", None)
if fn is None:
    print("✖ shell_norm.locale_to_double không có")
    sys.exit(1)
for src, want in cases:
    got = fn(src)
    ok = got == want and got.count("\x27") == src.count("\x27")
    print(("✔ " if ok else "✖ ") + repr(src) + " -> " + repr(got) + ("" if ok else " (want " + repr(want) + ")"))
    bad += not ok
# readings: cách đọc cũ vẫn ở đầu (không lỏng hơn), cách đọc giải mã được THÊM
for src, dec in [('$"rm" -rf ~', '"rm" -rf ~'),
                 ('bash -c "\\$\x27rm\x27 -rf ~"', 'bash -c "$\x27rm\x27 -rf ~"'),     # \$ trong "…": bash bỏ \, shlex giữ
                 ('bash -c "\\$\\"rm\\" -rf ~"', 'bash -c "$\\"rm\\" -rf ~"'),
                 ('rg \\$\x27\\\x27 \x27git reset --hard\x27', None),                 # blocker 1: \$ ngoài "…" là $ chữ, không thêm cách đọc
                 ('bash -c \\$\x27rm -rf ~\x27', None),                               # \$ ngoài "…": script là $rm -rf ~ (bash, zsh), không đọc thành rm
                 ('echo $"(;" rm -rf ~', None),                                       # van: "(;" thành từ giống từ ngăn cách
                 ('echo $"" rm -rf ~', None),                                         # van: từ $ thành rỗng
                 ('"${x:-\x27"\x27}"; $"rm"', '"${x:-\x27"\x27}"; "rm"'),               # bash 3.2 ghép \x27…\x27 trong "${ }" (bash32)
                 ('echo $"{" git reset --hard', None),                               # van: { là từ ngăn cách với guard
                 ('echo $"2>x" git reset --hard', None),                             # van: 2>x thành chuyển hướng
                 ('echo $"{" ; $"rm" -rf ~', 'echo $"{" ; "rm" -rf ~'),               # van theo từng từ: chỉ giữ $ của "{", vẫn giải mã "rm"
                 ('bash -c "\\\\\\$\x27rm\x27 -rf ~"', 'bash -c "\\\\$\x27rm\x27 -rf ~"'),   # \\ là cặp escape, \$ sau nó mới mất \
                 ('bash -c "${U:-true; \\$\x27rm\x27 -rf ~; :}"', 'bash -c "${U:-true; $\x27rm\x27 -rf ~; :}"'),   # ${ } trong "…": \$ vẫn mất \
                 ('printf x "$${x:-\x27"\x27}"; $"rm"', 'printf x "$${x:-\x27"\x27}"; "rm"'),   # cách đọc bash 3.2: ${ ghép cả sau $$
                 ('echo "${m:-don\x27t}"; bash -c "\\$\x27rm\x27 -rf ~"', 'echo "${m:-don\x27t}"; bash -c "$\x27rm\x27 -rf ~"'),   # zsh/ksh: \x27 chữ trong "${ }"
                 ('echo "${m:-don\x27t}" "it\x27s"; git grep -F \\$\x27\\\x27 -- \x27git push --force\x27', None),   # van ranh giới từ: bỏ \ làm lệch cách tách từ thì không thêm cách đọc
                 ('printf x "${x:-\x27"\x27}"; bash -c \x27echo $"" rm -rf ~\x27', None),   # plan_review v5: chế độ zsh lệch (không cân), bash: script nháy đơn để nguyên
                 ('echo "${m:-don\x27t}"; bash -c \x27printf %s $"{" git reset --hard\x27', None),   # chế độ bash32 lệch (không cân)
                 ('$"rm" -rf ~ \x27x', None),   # nháy đơn chưa đóng: lượt quét không cân, không thêm cách đọc
                 ('echo "$(echo \\$\x27x\x27)"', None),   # \$ trong $( ) của "…": ngữ cảnh lệnh, \ là escape thật
                 ('"${x:-\x27"\x27}" "\\$\x27y\x27"', None),   # bash32 thấy "…", lexer thấy \x27…\x27: không bỏ \
                 ('printf x "${x:-\x27"\x27}" "${y:-\x27"\x27}"; bash -c \x27echo $"" rm -rf ~\x27; grep -F \x27}"}"\x27\\\x27 f', None),   # v6: không sửa trong \x27…\x27 đã đóng của lexer
                 ('x=`# don\x27t\necho ok`; $"rm" -rf ~', 'x=`# don\x27t\necho ok`; "rm" -rf ~'),   # v6: comment trong `…` (có \x27) không làm lệch
                 ('echo "$(echo "a\x27b")"; echo $"" rm -rf ~', None)]:   # v6: lexer lỗi, tách thô vẫn giữ $ của $""
    r = s.readings(src)
    ok = r[0] == src and (len(r) == 1 if dec is None else dec in r[1:])
    print(("✔ " if ok else "✖ ") + "readings(" + repr(src) + ") = " + repr(r))
    bad += not ok
# _same_shape: cùng số từ chưa đủ, vai trò từng chỗ (chữ / chuyển hướng / cú pháp) phải giữ
for a, b, want in [("echo a x b", "echo a x b", True), ("echo a x b", "echo a ; b", False), ("echo a >x b", "echo a ax b", False),
                   ("rg a", "git a", False), ("echo x", "echo $x", True), ("echo $x", "echo x", False), ("echo x", "echo \\x", True),
                   ("echo \x22\x22 b", "echo $\x22\x22 b", False),
                   ("echo ; b", "echo | b", False),
                   ("echo \x27unclosed", "echo \x27still", True), ("echo \x27unclosed", "echo ok", False)]:
    got = s._same_shape(a, b)
    ok = got == want
    print(("✔ " if ok else "✖ ") + "_same_shape(" + repr(a) + ", " + repr(b) + ") = " + str(got))
    bad += not ok
# _lexer_quotes()[0]: chỉ \ mà lex_words đọc trong nháy kép (không trong nháy đơn, không ngoài nháy)
t = "a \"\\$x\" \x27\\$y\x27 \\$z $\x27\\$w\x27"
got, want = s._lexer_quotes(t)[0], {t.index("\\")}
print(("✔ " if got == want else "✖ ") + "_lexer_quotes(" + repr(t) + ")[0]" + ") = " + repr(sorted(got)))
bad += got != want
sys.exit(1 if bad else 0)
PY

echo "cases: $N"
[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
