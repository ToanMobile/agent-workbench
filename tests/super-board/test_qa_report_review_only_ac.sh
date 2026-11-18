#!/usr/bin/env bash
# Test hồi quy (18/11, PR #1292 / thẻ #1258 → #1298): QA ghi `❌ Not done: AC4 … review độc lập — chuyển lane Review`; merge gate chặn mãi
# (exit 11, qa-report) dù reviewer đã duyệt, thẻ chạm rebuild_cap và bị Blocked. Chọn sửa phía QA, KHÔNG nới checker (cổng không yếu đi).
#  A  checker vẫn chặn mục Not done nêu AC review độc lập, kể cả khi reviewer đã merge-ready + approved-head (không nới cổng).
#  B  cùng report nhưng AC review-only nằm ở ✅ Done + `Next: reviewer` -> exit 0.
#  C  AC code ở ❌ Not done vẫn chặn khi AC review-only đã chuyển sang ✅ Done.
#  D  writing-standard, run.md và super-qa SKILL cùng ghim luật "AC chỉ lane Review không ở Not done, dùng Next: reviewer".
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

mk() { python3 - "$1" "$2" "$3" "$HEAD" <<'PY'
import json, sys
f, done, nd, head = sys.argv[1:5]
body = "## Acceptance criteria\n- [x] AC1 cổng OCR nhận phiên ocr\n  ↳ test exit 0\n- [ ] AC4 reviewer không phải tác giả duyệt PR\n"
c = lambda t: {"author": {"login": "bot"}, "authorAssociation": "OWNER", "body": t}
ab = '{"reviewer":"antigravity","builder":"b","task_id":"T0005-audit","gate_receipt":"r"}'
qa = "[qa] [report] ✅ QA v4 @ d0093822\nDid: test\n✅ Done: " + done + "\n" + (("❌ Not done: " + nd + "\n") if nd else "") + "Next: reviewer\n"
json.dump({"body": body, "author": {"login": "bot"},
  "comments": [c(qa), c("[reviewer] [report] ✅ merge-ready · round 3 · head " + head[:8]), c("approved-head:%s\napproved-by: %s" % (head, ab))]}, open(f, "w"))
PY
}
run() { python3 "$QA" --meta "$1" --head "$HEAD" >"$TMP/out" 2>&1; echo $?; }

mk "$TMP/a.json" "AC1 pass" "AC4 phần review độc lập (không phải tác giả) — chuyển lane Review"
[ "$(run "$TMP/a.json")" = 1 ] && ok "A: Not done nêu AC review-only vẫn chặn (cổng không nới)" || { fail "A: cổng bị nới"; cat "$TMP/out"; }

mk "$TMP/b.json" "AC1 pass; AC4 passed, independent review pending" ""
[ "$(run "$TMP/b.json")" = 0 ] && ok "B: AC review-only ở Done + Next: reviewer qua" || { fail "B: bị chặn"; cat "$TMP/out"; }

mk "$TMP/c.json" "AC4 passed, independent review pending" "AC1 test cổng OCR còn đỏ"
[ "$(run "$TMP/c.json")" = 1 ] && ok "C: AC code ở Not done vẫn chặn" || { fail "C: bị lọt"; cat "$TMP/out"; }

for f in .claude/skills/super-board/references/writing-standard.md .claude/skills/super-board/references/run.md .claude/skills/super-qa/SKILL.md; do
  grep -q "independent review pending" "$ROOT/$f" && grep -q "Next: reviewer" "$ROOT/$f" && grep -q "#1298" "$ROOT/$f" && ok "D: $f ghim luật" || fail "D: $f thiếu luật AC review-only"
done

[ "$FAILS" -eq 0 ] && echo "✅ test_qa_report_review_only_ac: all passed" || { echo "❌ $FAILS failed"; exit 1; }
