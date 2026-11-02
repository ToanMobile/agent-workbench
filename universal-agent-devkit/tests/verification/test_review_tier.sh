#!/usr/bin/env bash
# #858: bin/review_tier.py in bậc review S/M/L của PR từ `git diff --numstat <base>...HEAD` (luật chủ repo 02/11, core-rules §18).
# Hợp đồng của thẻ: 8 PR mẫu (numstat thật ghi sẵn ở data/review_tier/pr<N>.numstat, lấy bằng
# `gh api repos/ToanMobile/agent-workbench/pulls/<N>/files` ngày 02/11) ra S,S,M,M,M,L,L,L; diff 5 dòng chạm
# .claude/bin/super-board-merge-gate.sh ra L (qua git thật trong repo mktemp). Thêm: biên 50/51/400/401, test/ma trận/*.md
# không tính dòng và không kích bậc, file nhị phân, --deletes-data, và lỗi thì exit 2 không in bậc (không bao giờ rơi về S).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TIER="$DEVKIT_DIR/bin/review_tier.py"
DATA="$DEVKIT_DIR/tests/verification/data/review_tier"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export GIT_CONFIG_GLOBAL=/dev/null

# expect <bậc> <nhãn> <tham số…>: token đầu dòng 1 của stdout là bậc.
expect() {
  local want="$1" label="$2" got; shift 2
  got="$(python3 "$TIER" "$@" 2>"$TMP/err" | awk 'NR==1{print $1}')"
  [ "$got" = "$want" ] && ok "$label → $want" || fail "$label: muốn $want, được '$got' ($(head -c 300 "$TMP/err"))"
}
# expect_in <bậc> <nhãn> <numstat>: numstat viết ra file tạm (--numstat FILE).
expect_in() { printf '%b' "$3" > "$TMP/in.numstat"; expect "$1" "$2" --numstat "$TMP/in.numstat"; }
[ -f "$TIER" ] && ok "bin/review_tier.py có mặt" || fail "bin/review_tier.py chưa có"

# 1. Tám PR mẫu của thẻ.
for pair in 843:S 797:S 834:M 793:M 824:M 835:L 826:L 742:L; do
  n="${pair%%:*}"; want="${pair#*:}"
  [ -s "$DATA/pr$n.numstat" ] || { fail "fixture pr$n.numstat thiếu"; continue; }
  expect "$want" "PR #$n" --numstat "$DATA/pr$n.numstat"
done
out="$(python3 "$TIER" --numstat "$DATA/pr843.numstat" 2>/dev/null)"
case "$out" in *product_lines=20*) ok "PR #843 đếm 20 dòng sản phẩm (worktree.py +14/-6; ma trận và test không tính)" ;;
  *) fail "PR #843 số dòng sản phẩm sai: '$out'" ;; esac

# 2. Biên số dòng (file không khớp đường dẫn M/L).
expect_in S "50 dòng" '30\t20\tuniversal-agent-devkit/scripts/git/x.py\n'
expect_in M "51 dòng" '30\t21\tuniversal-agent-devkit/scripts/git/x.py\n'
expect_in M "400 dòng" '300\t100\tsrc/a.py\n'
expect_in L "401 dòng (cộng nhiều file)" '300\t0\tsrc/a.py\n100\t1\tsrc/b.py\n'

# 3. Loại trừ: test, ma trận, test_durations, *.md không tính dòng, và đường dẫn của chúng không kích bậc.
expect_in S "chỉ test + ma trận + durations + md" \
  '900\t0\tuniversal-agent-devkit/tests/gates/test_merge_gate_x.sh\n500\t0\ttests/super-board/test_auth.sh\n300\t0\t.agents/regression_matrix.active.json\n9\t0\tuniversal-agent-devkit/tests/lib/test_durations.txt\n200\t0\tdocs/merge-gate.md\n'
expect_in S "file nhị phân (-) tính 0 dòng" '-\t-\tassets/logo.png\n3\t0\tsrc/a.py\n'

# 4. Đường dẫn M và L.
expect_in M ".claude/bin/ 2 dòng" '1\t1\t.claude/bin/super-board-card.sh\n'
expect_in M "kit hooks/ 2 dòng" '2\t0\tuniversal-agent-devkit/hooks/x.sh\n'
expect_in M "post-fix-gate 1 dòng" '1\t0\tuniversal-agent-devkit/bin/post-fix-gate.py\n'
expect_in L "merge-gate 5 dòng (numstat)" '3\t2\t.claude/bin/super-board-merge-gate.sh\n'
expect_in L "bin/review* 1 dòng" '1\t0\tuniversal-agent-devkit/bin/review_tier.py\n'
expect_in L "Auth ở repo app (không phân biệt hoa thường)" '2\t1\tapp/src/main/java/com/x/AuthRepository.kt\n'
expect_in L "rename sang đường dẫn migration" '1\t1\tdb/{old => migrations}/v2.sql\n'
expect_in S "rename file sản phẩm vào tests/ (đường dẫn mới là test)" '5\t5\tsrc/{a.py => tests/test_a.py}\n'
printf '' > "$TMP/empty.numstat"
expect S "diff rỗng" --numstat "$TMP/empty.numstat"
expect L "--deletes-data (thẻ xoá dữ liệu)" --numstat "$TMP/empty.numstat" --deletes-data
got="$(printf '1\t1\t.claude/bin/super-board-card.sh\n' | python3 "$TIER" --numstat - 2>/dev/null | awk '{print $1}')"
[ "$got" = M ] && ok "--numstat - đọc stdin → M" || fail "--numstat - đọc stdin: '$got'"

# 5. Git thật: diff 5 dòng chạm .claude/bin/super-board-merge-gate.sh ra L; 2 dòng chạm file thường ra S.
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$TMP/repo"; mkdir -p "$R/.claude/bin" "$R/src"
G "$R" init -q -b main . || fail "setup: git init"
printf 'l%s\n' 1 2 3 4 5 6 7 8 9 10 > "$R/.claude/bin/super-board-merge-gate.sh"
printf 'a\nb\n' > "$R/src/a.py"
G "$R" add -A && G "$R" commit -qm base || fail "setup: commit base"
G "$R" checkout -q -b pr || fail "setup: nhánh pr"
printf 'l1\nX2\nX3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nl11\n' > "$R/.claude/bin/super-board-merge-gate.sh"   # +3 −2 = 5 dòng
G "$R" commit -qam "5 dòng merge-gate" || fail "setup: commit pr"
got="$(cd "$R" && python3 "$TIER" --base main 2>"$TMP/err")"
case "$got" in "L product_lines=5 "*merge-gate*) ok "git: 5 dòng chạm super-board-merge-gate.sh → L ($got)" ;;
  *) fail "git: 5 dòng merge-gate: '$got' ($(head -c 300 "$TMP/err"))" ;; esac
G "$R" checkout -q -b pr2 main && printf 'a\nc\nd\n' > "$R/src/a.py" && G "$R" commit -qam "2 dòng src" || fail "setup: pr2"
got="$(cd "$R" && python3 "$TIER" --base main 2>/dev/null | awk '{print $1}')"
[ "$got" = S ] && ok "git: 2 dòng src/a.py → S" || fail "git: 2 dòng src/a.py: '$got'"

# 6. Lỗi không bao giờ thành S: base không tồn tại, base dạng cờ, dòng numstat sai ⇒ exit 2, stdout rỗng.
fails_closed() {
  local label="$1" out rc; shift
  out="$("$@" 2>/dev/null)"; rc=$?
  [ "$rc" = 2 ] && [ -z "$out" ] && ok "$label → exit 2, không in bậc" || fail "$label: rc=$rc stdout='$out'"
}
fails_closed "base không tồn tại" sh -c "cd '$R' && exec python3 '$TIER' --base no-such-ref"
fails_closed "base dạng cờ (--output=…)" sh -c "cd '$R' && exec python3 '$TIER' --base=--output=$TMP/x"
printf 'abc\t1\tsrc/a.py\n' > "$TMP/bad.numstat"
fails_closed "dòng numstat sai" python3 "$TIER" --numstat "$TMP/bad.numstat"
[ ! -e "$TMP/x" ] && ok "base dạng cờ không ghi file" || fail "base dạng cờ đã ghi $TMP/x"

[ "$FAILS" = 0 ] && echo "✅ test_review_tier: PASS" || { echo "❌ test_review_tier: $FAILS failed"; exit 1; }
