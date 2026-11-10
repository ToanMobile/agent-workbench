#!/usr/bin/env bash
# #980: super-review-removed-names.py liệt kê tên bị xoá/đổi ở dòng '-' của diff mà head vẫn dùng ngoài diff (PR #650: đổi REG-DK-ALL-01
# còn sót ở merge-gate, merge-train, gate_speed_report ⇒ 3 thẻ #712 #654 #651). Repo git tạm: đổi tên id ở một file, hai file khác giữ tên cũ
# ⇒ phải liệt kê đúng hai file đó; đổi tên ở MỌI nơi, từ tiếng thường, hay chỗ dùng nằm trong file diff đã chạm ⇒ không in gì; quá --max-names ⇒ cắt.
# review-flow.md bước 2 gọi script. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/.claude/bin/super-review-removed-names.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -f "$TOOL" ] || { fail "thiếu $TOOL"; exit 1; }

REPO="$TMP/repo"; mkdir -p "$REPO/bin"
git -C "$REPO" init -q -b main; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
w() { printf '%s\n' "$2" > "$REPO/bin/$1"; }  # w <file> <nội dung>
w gate.sh 'RULE=REG-DK-ALL-01'
w train.sh 'grep REG-DK-ALL-01 x'
w report.py 'id = "REG-DK-ALL-01"'
w words.txt 'the function stays'
w lib.sh 'helper_old_name()'
w caller.sh 'call lib.sh'
w tokens.txt 'AAA_one BBB_two CCC_three DDD_four'
w use.txt 'AAA_one BBB_two CCC_three DDD_four'
printf 'EEE_dup\nEEE_dup\n' > "$REPO/bin/dup.txt"
git -C "$REPO" add -A; git -C "$REPO" commit -qm base

run() { OUT="$(cd "$REPO" && python3 "$TOOL" --base main "$@" 2>"$TMP/err")"; RC=$?; }
branch() { git -C "$REPO" checkout -q main; git -C "$REPO" checkout -q -b "$1"; }
rename_id() { sed -i.bak 's/REG-DK-ALL-01/REG-DK-ALL-GATES-01/' "$REPO/bin/$1"; rm -f "$REPO/bin/$1.bak"; }

# 1. đổi tên ở gate.sh; train.sh và report.py còn tên cũ ⇒ liệt kê hai file đó, không liệt kê gate.sh (đã sửa trong diff)
branch rename; rename_id gate.sh; git -C "$REPO" commit -qam rename
run
case "$OUT" in *"REG-DK-ALL-01"*"bin/report.py:1"*"bin/train.sh:1"*) ok "tên cũ còn ở train.sh và report.py được liệt kê" ;;
  *) fail "muốn train.sh + report.py, được rc=$RC '$OUT'" ;; esac
case "$OUT" in *"bin/gate.sh"*) fail "liệt kê cả gate.sh (file đã sửa trong diff)" ;; *) ok "file diff đã chạm không bị liệt kê" ;; esac

# 2. đổi ở mọi nơi ⇒ im lặng
branch all; rename_id gate.sh; rename_id train.sh; rename_id report.py; git -C "$REPO" commit -qam all
run; if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then ok "đổi tên ở mọi nơi ⇒ không in gì"; else fail "muốn rỗng, được rc=$RC '$OUT'"; fi

# 3. từ tiếng thường bị xoá khỏi một dòng (còn ở file khác) không phải định danh ⇒ im lặng
branch words; w gate.sh 'use the function here'; git -C "$REPO" commit -qam seed; w gate.sh 'gone'; git -C "$REPO" commit -qam words
run; case "$OUT" in *function*) fail "từ thường 'function' bị coi là định danh: '$OUT'" ;; *) ok "từ tiếng thường không gây nhiễu" ;; esac

# 4. đổi tên file: tên cũ còn được nhắc ở caller.sh (ngoài diff) ⇒ liệt kê
branch delfile; git -C "$REPO" mv bin/lib.sh bin/lib_gone.sh; git -C "$REPO" commit -qam delfile
run; case "$OUT" in *"lib.sh"*"bin/caller.sh:1"*) ok "file bị đổi tên còn được nhắc ở nơi khác ⇒ liệt kê" ;; *) fail "muốn lib.sh ở caller.sh, được '$OUT'" ;; esac

# 5. --max-names cắt và báo còn bao nhiêu
branch many; w tokens.txt 'x'; git -C "$REPO" commit -qam many
run --max-names 2; n="$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
if [ "$n" = 3 ]; then
  case "$OUT" in *"(+2 tên nữa"*) ok "--max-names 2 ⇒ 2 dòng + dòng tóm tắt" ;; *) fail "thiếu dòng tóm tắt: '$OUT'" ;; esac
else fail "muốn 3 dòng, được $n: '$OUT'"; fi

# 5b. file diff chạm mà còn sót tên cũ trong chính nó: reviewer thấy ngay trong diff ⇒ không liệt kê (chỉ chỗ dùng ngoài diff)
branch touched; w dup.txt 'EEE_dup'; git -C "$REPO" commit -qam partial
run; case "$OUT" in *"EEE_dup"*) fail "liệt kê chỗ dùng trong file diff đã chạm: '$OUT'" ;; *) ok "sót tên cũ trong file diff chạm ⇒ không liệt kê" ;; esac

# 6. lỗi git ⇒ exit 64
OUT="$(cd "$REPO" && python3 "$TOOL" --base no-such-ref 2>&1)"; RC=$?
if [ "$RC" -eq 64 ]; then ok "ref sai ⇒ exit 64"; else fail "ref sai: rc=$RC"; fi

if [ "$FAILS" -eq 0 ]; then echo "PASS"; else echo "FAIL ($FAILS)"; exit 1; fi
