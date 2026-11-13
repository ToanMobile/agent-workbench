#!/usr/bin/env bash
# #858 PR2: super-board-review-plan.sh đọc bậc review S/M/L (review_tier.py) và in các bên review theo config `review_tiers`.
# PR giả trong repo git tạm: bậc S ⇒ 1 bên (claude), M ⇒ 2, diff 5 dòng chạm super-board-merge-gate.sh ⇒ L 4 bên; config tuỳ biến
# được đọc; danh sách rỗng / config hỏng / thiếu review_tier.py không làm mất bên review (thiếu bậc ⇒ L). review-flow.md và run.md gọi script.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLAN="$ROOT/.claude/bin/super-board-review-plan.sh"
TIER_PY="$ROOT/universal-agent-devkit/bin/review_tier.py"
CONF="$ROOT/.claude/super-board/configs/agent-workbench.json"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# repo tạm: main có kit review_tier.py (không nằm trong diff), mỗi PR giả là một nhánh từ main.
REPO="$TMP/repo"
mkdir -p "$REPO/src" "$REPO/.claude/bin" "$REPO/universal-agent-devkit/bin"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
cp "$TIER_PY" "$REPO/universal-agent-devkit/bin/review_tier.py" 2>/dev/null || fail "thiếu $TIER_PY"
printf 'a\n' > "$REPO/src/app.py"; printf 'x\n' > "$REPO/.claude/bin/super-board-merge-gate.sh"
git -C "$REPO" add -A; git -C "$REPO" commit -qm base

branch() {  # branch <tên> <file> <số dòng thêm>
  git -C "$REPO" checkout -q main; git -C "$REPO" checkout -q -b "$1"
  i=0; while [ "$i" -lt "$3" ]; do echo "l$i" >> "$REPO/$2"; i=$((i + 1)); done
  git -C "$REPO" commit -qam "$1"
}
branch pr-s src/app.py 3
branch pr-m src/app.py 60
branch pr-l .claude/bin/super-board-merge-gate.sh 5

run() {  # run <nhánh> [tham số…] ⇒ $OUT, $RC, $ERR
  b="$1"; shift
  git -C "$REPO" checkout -q "$b"
  OUT="$(cd "$REPO" && bash "$PLAN" --base main "$@" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
}
expect() {  # expect <nhãn> <bậc> <danh sách>
  tier="$(printf '%s\n' "$OUT" | sed -n '1s/ .*//p')"
  revs="$(printf '%s\n' "$OUT" | sed -n 's/^reviewers: //p')"
  if [ "$RC" -eq 0 ] && [ "$tier" = "$2" ] && [ "$revs" = "$3" ]; then ok "$1: $tier ⇒ $revs"
  else fail "$1: muốn $2 ⇒ '$3', được rc=$RC '$OUT' (stderr: $ERR)"; fi
}

[ -f "$PLAN" ] || fail "thiếu $PLAN"

run pr-s;                        expect "PR S, không config" S "claude"
n="$(printf '%s\n' "$OUT" | sed -n 's/^reviewers: //p' | wc -w | tr -d ' ')"
[ "$n" = 1 ] && ok "bậc S ⇒ đúng 1 bên review" || fail "bậc S ⇒ $n bên"
run pr-m;                        expect "PR M 60 dòng" M "claude antigravity"
run pr-l;                        expect "PR L 5 dòng merge-gate" L "claude antigravity ocr"
n="$(printf '%s\n' "$OUT" | sed -n 's/^reviewers: //p' | wc -w | tr -d ' ')"
[ "$n" = 3 ] && ok "bậc L ⇒ đúng 3 bên review (13/11: bỏ Grok)" || fail "bậc L ⇒ $n bên"
run pr-s --deletes-data;         expect "PR S + thẻ xoá dữ liệu" L "claude antigravity ocr"

# config thật của board: có review_tiers và in đúng luật chủ repo
jq -e '.review_tiers.S and .review_tiers.M and .review_tiers.L' "$CONF" >/dev/null 2>&1 \
  && ok "config agent-workbench có review_tiers S/M/L" || fail "config agent-workbench thiếu review_tiers S/M/L"
run pr-s --config "$CONF";       expect "config thật, PR S" S "claude"
run pr-m --config "$CONF";       expect "config thật, PR M" M "claude antigravity"
run pr-l --config "$CONF";       expect "config thật, PR L" L "claude antigravity ocr"

# config tuỳ biến được đọc; danh sách rỗng / sai kiểu / JSON hỏng ⇒ mặc định (không bậc nào 0 bên)
printf '{"review_tiers":{"S":["claude","ocr"]}}' > "$TMP/c1.json"
run pr-s --config "$TMP/c1.json"; expect "config tuỳ biến S" S "claude ocr"
run pr-m --config "$TMP/c1.json"; expect "config thiếu bậc M ⇒ mặc định" M "claude antigravity"
printf '{"review_tiers":{"S":[]}}' > "$TMP/c2.json"
run pr-s --config "$TMP/c2.json"; expect "S rỗng ⇒ mặc định" S "claude"
printf '{"review_tiers":{"S":[1,"ocr"]}}' > "$TMP/c3.json"
run pr-s --config "$TMP/c3.json"; expect "S sai kiểu ⇒ bỏ cả danh sách" S "claude"
printf '{"review_tiers": ' > "$TMP/c4.json"
run pr-s --config "$TMP/c4.json"; expect "config hỏng ⇒ mặc định" S "claude"
case "$ERR" in *review_tiers*) ok "config hỏng có cảnh báo stderr" ;; *) fail "config hỏng không cảnh báo: '$ERR'" ;; esac
# mặc định là sàn: config chỉ thêm bên, không bớt (PR sửa config của chính nó không tự giảm bên review)
printf '{"review_tiers":{"L":["claude"],"M":["claude"]}}' > "$TMP/c5.json"
run pr-l --config "$TMP/c5.json"; expect "config L ít bên hơn luật ⇒ vẫn đủ 3" L "claude antigravity ocr"
run pr-m --config "$TMP/c5.json"; expect "config M ít bên hơn luật ⇒ vẫn 2" M "claude antigravity"
printf '{"review_tiers":{"S":["ocr","foo"]}}' > "$TMP/c6.json"
run pr-s --config "$TMP/c6.json"; expect "tên bên lạ ⇒ bỏ cả danh sách" S "claude"
# 13/11: chủ repo bỏ Grok — grok là tên lạ ⇒ bỏ cả danh sách, không bên nào chạy grok
printf '{"review_tiers":{"L":["claude","antigravity","ocr","grok"],"S":["grok"]}}' > "$TMP/c9.json"
run pr-l --config "$TMP/c9.json"; expect "config còn grok ở L ⇒ bỏ, mặc định 3 bên" L "claude antigravity ocr"
run pr-s --config "$TMP/c9.json"; expect "config S chỉ grok ⇒ bỏ" S "claude"
printf '{"review_tiers":{"S":["ocr","claude","ocr"]}}' > "$TMP/c7.json"
run pr-s --config "$TMP/c7.json"; expect "tên trùng ⇒ một lần" S "claude ocr"
printf '{"review_tiers":{"S":["ocr\\n"]}}' > "$TMP/c8.json"
run pr-s --config "$TMP/c8.json"; expect "tên có xuống dòng ⇒ bỏ" S "claude"

# PR sửa review_tier.py của chính nó cho ra S: bản ở base vẫn tính, giữ bậc cao hơn
git -C "$REPO" checkout -q main; git -C "$REPO" checkout -q -b pr-self
printf 'print("S product_lines=0 reasons=-")\n' > "$REPO/universal-agent-devkit/bin/review_tier.py"
git -C "$REPO" commit -qam pr-self
run pr-self;                     expect "PR tự hạ review_tier.py ⇒ bậc của base (L)" L "claude antigravity ocr"

# thiếu review_tier.py ⇒ bậc L (không rơi về S)
git -C "$REPO" checkout -q pr-s
mv "$REPO/universal-agent-devkit" "$TMP/kit-off"
run pr-s;                        expect "thiếu review_tier.py ⇒ L" L "claude antigravity ocr"
case "$ERR" in *"bậc L"*) ok "thiếu review_tier.py có cảnh báo stderr" ;; *) fail "thiếu review_tier.py không cảnh báo: '$ERR'" ;; esac
mv "$TMP/kit-off" "$REPO/universal-agent-devkit"
SB_REVIEW_TIER_PY="$TMP/none.py" run pr-s; expect "SB_REVIEW_TIER_PY trỏ file thiếu ⇒ L" L "claude antigravity ocr"

# reviewer đọc bậc: review-flow.md (super-review, SKILL.md bắt đọc trước khi review) và run.md bước 4 (lane board) gọi script
for f in "$ROOT/.claude/skills/super-review/references/review-flow.md" "$ROOT/.claude/skills/super-board/references/run.md"; do
  grep -q 'super-board-review-plan.sh' "$f" && ok "${f#$ROOT/} gọi super-board-review-plan.sh" \
    || fail "${f#$ROOT/} chưa gọi super-board-review-plan.sh"
done
RUNMD="$ROOT/.claude/skills/super-board/references/run.md"
FLOW="$ROOT/.claude/skills/super-review/references/review-flow.md"
# ocr-review: -b là mô tả (--background), base đi bằng --from/--to; -b origin/<base> chỉ diff working tree rỗng (0 file)
grep -qF 'ocr-review --from origin/<base> --to HEAD' "$RUNMD" && ok "run.md: lệnh OCR dùng --from/--to" || fail "run.md: lệnh OCR sai"
grep -qF 'ocr-review -b origin/' "$RUNMD" && fail "run.md còn 'ocr-review -b origin/'" || ok "run.md không dùng -b làm base"
grep -qF -- '--deletes-data' "$FLOW" && ok "review-flow.md có --deletes-data" || fail "review-flow.md thiếu --deletes-data"
# review-flow bước 2 không còn bắt OCR ở mọi bậc
grep -qF 'when `ocr` is a side of the tier' "$FLOW" && ok "review-flow.md: OCR chỉ bắt buộc khi có trong bậc" \
  || fail "review-flow.md còn bắt OCR ở mọi bậc"
grep -qF 'OCR stands in' "$RUNMD" && ok "run.md: bậc S Claude lỗi ⇒ OCR thay" || fail "run.md thiếu OCR thay Claude ở bậc S"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
