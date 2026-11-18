#!/usr/bin/env bash
# Test hồi quy (18/11, PR #1292 / thẻ #1258 → #1298): QA ghi `❌ Not done: AC4 … review độc lập — chuyển lane Review`; merge gate chặn mãi
# (exit 11, qa-report) dù reviewer đã duyệt, thẻ chạm rebuild_cap và bị Blocked. Sửa checker TỐI THIỂU, không đọc chữ tự do.
#  A  dạng #1292 (một dòng, mở đầu `AC4 phần review độc lập`) + [reviewer] ✅ merge-ready đúng head + approved-head 40 ký tự hợp lệ, cả hai mới hơn QA -> exit 0.
#  B  vẫn exit 1: thiếu approved-head · reviewer ở head khác · reviewer ❌ mới nhất · thiếu --head · approved-head cũ hơn QA · approved-head sai head.
#  C  vẫn exit 1: AC code ở Not done · mục trộn AC review-only với AC khác · mục review-only nhiều dòng.
#  D  QA ghi AC review-only ở ✅ Done + Next: reviewer -> exit 0; writing-standard, run.md, super-qa SKILL ghim luật.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QA="$ROOT/.claude/bin/super-board-qa-report.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qarevonly-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
HEAD=314e948918ea5d31731c0daef2d55fb176627fa6
OTHER=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# mk <file> <done> <not_done> <reviewer line tail> <approved sha|none> [order: ok|approved-first]
mk() { python3 - "$@" <<'PY'
import json, sys
f, done, nd, rev, appr, order = sys.argv[1:7]
body = "## Acceptance criteria\n- [x] AC1 cổng OCR nhận phiên ocr\n  ↳ test exit 0\n- [ ] AC4 reviewer không phải tác giả duyệt PR\n"
c = lambda t: {"author": {"login": "bot"}, "authorAssociation": "OWNER", "body": t}
ab = '{"reviewer":"antigravity","builder":"b","task_id":"T0005-audit","gate_receipt":"r"}'
qa = "[qa] [report] ✅ QA v4 @ d0093822\nDid: test\n✅ Done: " + done + "\n" + (("❌ Not done: " + nd + "\n") if nd else "") + "Next: reviewer\n"
r = c("[reviewer] [report] " + rev)
a = c("approved-head:%s\napproved-by: %s" % (appr, ab)) if appr != "none" else None
cm = [c(qa)]
if order == "approved-first" and a: cm = [a] + cm + [r]
else: cm += [r] + ([a] if a else [])
json.dump({"body": body, "author": {"login": "bot"}, "comments": cm}, open(f, "w"))
PY
}
run() { python3 "$QA" --meta "$1" ${2-"--head"} ${3-$HEAD} >"$TMP/out" 2>&1; echo $?; }
RO="AC4 phần review độc lập (không phải tác giả) — chuyển lane Review"
MR="✅ merge-ready · round 3 · head ${HEAD:0:8}"
expect() { [ "$1" = "$2" ] && ok "$3" || { fail "$3 (rc=$1, muốn $2)"; cat "$TMP/out"; }; }

mk "$TMP/a.json" "AC1 pass" "$RO" "$MR" "$HEAD" ok
expect "$(run "$TMP/a.json")" 0 "A: dạng #1292 + reviewer + approved-head đúng head qua"

mk "$TMP/b1.json" "AC1 pass" "$RO" "$MR" none ok;                    expect "$(run "$TMP/b1.json")" 1 "B1: thiếu approved-head vẫn chặn"
mk "$TMP/b2.json" "AC1 pass" "$RO" "✅ merge-ready · head ${OTHER:0:8}" "$HEAD" ok; expect "$(run "$TMP/b2.json")" 1 "B2: reviewer ở head khác vẫn chặn"
mk "$TMP/b3.json" "AC1 pass" "$RO" "❌ not merge-ready · head ${HEAD:0:8}" "$HEAD" ok; expect "$(run "$TMP/b3.json")" 1 "B3: reviewer ❌ mới nhất vẫn chặn"
expect "$(python3 "$QA" --meta "$TMP/a.json" >"$TMP/out" 2>&1; echo $?)" 1 "B4: thiếu --head vẫn chặn"
mk "$TMP/b5.json" "AC1 pass" "$RO" "$MR" "$HEAD" approved-first;     expect "$(run "$TMP/b5.json")" 1 "B5: approved-head cũ hơn QA vẫn chặn"
mk "$TMP/b6.json" "AC1 pass" "$RO" "$MR" "$OTHER" ok;                expect "$(run "$TMP/b6.json")" 1 "B6: approved-head sai head vẫn chặn"

mk "$TMP/c1.json" "AC4 pass" "AC1 test cổng OCR còn đỏ" "$MR" "$HEAD" ok;  expect "$(run "$TMP/c1.json")" 1 "C1: AC code ở Not done vẫn chặn"
mk "$TMP/c2.json" "AC1 pass" "AC4 phần review độc lập; AC1 test còn đỏ" "$MR" "$HEAD" ok; expect "$(run "$TMP/c2.json")" 1 "C2: mục trộn AC khác vẫn chặn"
mk "$TMP/c3.json" "AC1 pass" "AC4 phần review độc lập
  - AC4 code còn lỗi crash" "$MR" "$HEAD" ok;                            expect "$(run "$TMP/c3.json")" 1 "C3: mục nhiều dòng vẫn chặn"

mk "$TMP/d.json" "AC1 pass; AC4 passed, independent review pending" "" "$MR" none ok
expect "$(run "$TMP/d.json")" 0 "D1: AC review-only ở Done + Next: reviewer qua"
for f in .claude/skills/super-board/references/writing-standard.md .claude/skills/super-board/references/run.md .claude/skills/super-qa/SKILL.md; do
  grep -q "independent review pending" "$ROOT/$f" && grep -q "Next: reviewer" "$ROOT/$f" && grep -q "#1298" "$ROOT/$f" && ok "D: $f ghim luật" || fail "D: $f thiếu luật AC review-only"
done

[ "$FAILS" -eq 0 ] && echo "✅ test_qa_report_review_only_ac: all passed" || { echo "❌ $FAILS failed"; exit 1; }
