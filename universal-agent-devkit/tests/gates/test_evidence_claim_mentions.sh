#!/usr/bin/env bash
# hooks/test_evidence_gate.sh, the CLAIM reader (Giai đoạn A of the 2026-10-12 /devkit-audit plan; every case below is a sentence
# of a real reply in that session, blocked or let through by the real hook):
#  1. FAIL-OPEN: "Không có test nào fail, 12/12 test pass." passed (rc 0). The first CLAIM match runs from the first "test" to the
#     last "pass" ("test nào fail, 12/12 test pass"), the negator before it exempts it, and finditer() resumes AFTER that match, so
#     the real claim inside it is never read. An exempted match must not hide a later claim that starts inside it.
#  2. FALSE BLOCK: the Vietnamese name of the TDD cycle, "test ĐỎ→XANH", in a plan / a quoted mention: cycle_name_only() knew only
#     the English "red→green".
#  3. FALSE BLOCK: a sentence that MENTIONS the trigger words, each quoted, after a word that says so (chữ "test" đứng gần "xanh",
#     cụm "test ĐỎ→XANH", mẫu `test…xanh`): the words are the subject, not a result. A quoted result without such a word
#     (Kết quả: "12/12 test pass") is still a claim.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${TE_HOOK:-$DEVKIT_DIR/hooks/test_evidence_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P"; git -C "$P" init -q .
TR="$TMP/t.jsonl"; : > "$TR"
N=0
# check <want rc> <reply>: the hook on an empty transcript and a project with no XML, so any claim it reads is unbacked (rc 2)
check() {
  local want="$1" text="$2" rc
  N=$((N + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":"te-men-"+sys.argv[3],"transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' \
    "$TR" "$text" "$N" > "$TMP/in.json"
  CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err"
  rc=$?
  grep -q Traceback "$TMP/err" && rc=99
  if [ "$rc" = "$want" ]; then ok "rc $rc: $text"; else fail "rc $rc (want $want): $text"; fi
}

# 1. a real claim behind an exempted match is still a claim
check 2 'Không có test nào fail, 12/12 test pass.'
check 2 'Chưa có test nào đỏ, test xanh hết.'
check 2 'No test failed, 12/12 tests pass.'
# 2. the Vietnamese cycle name in a plan is not a result; a result after it, or a done-word, still is
check 0 'Lượt này chỉ lên kế hoạch: mỗi sửa sẽ có test ĐỎ→XANH.'
check 0 'Cần chạy test đỏ -> xanh trước khi sửa code.'
check 2 'Test ĐỎ→XANH, 12/12 pass.'
check 2 'Đã chạy test ĐỎ→XANH.'
check 2 'Sẽ commit sau, test ĐỎ→XANH 3/3 pass.'
# 3. quoted mentions after a word that names them
check 0 'Ngay trong phiên này, `test_evidence_gate` chặn nhầm 3 lần chỉ vì câu phủ định hoặc câu mô tả kế hoạch có chữ "test" đứng gần "xanh" hoặc "thành công".'
check 0 'Nhiều khả năng hook đã đọc các cụm như "test ĐỎ→XANH" trong phần mô tả kế hoạch thành một claim, nhưng tôi chưa kiểm.'
check 0 '- Câu mô tả kế hoạch cũng bị coi là claim: cụm "test ĐỎ→XANH" trong kế hoạch khớp mẫu `test…xanh`, dù đó là mô tả việc sẽ làm, không phải kết quả.'
check 2 'Kết quả: "12/12 test pass".'
check 2 'Chữ "test" thì 12/12 test pass.'
check 2 'Cụm "test xanh" đúng, và 12/12 test pass.'
# controls that already behaved (must not move)
check 0 'Lượt trước chỉ là kế hoạch: tôi không chạy test nào trong lượt đó và không khẳng định test nào thành công.'
check 0 'Chưa chạy test, nên chưa biết test có pass hay không.'
check 2 'Đã chạy lại, 12/12 test pass.'
check 2 'Không khẳng định gì thêm, nhưng test xanh hết.'
check 2 'Mỗi sửa có test ĐỎ→XANH, có công tắc tắt và RED-proof.'

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
