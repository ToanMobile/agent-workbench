#!/usr/bin/env bash
# Test hồi quy (18/11, PR #1292 / thẻ #1258 → #1298): report QA ghi `❌ Not done: AC4 phần review độc lập … — chuyển lane Review`, AC chỉ lane
# Review chứng minh được. Lane Review đã đăng `approved-head:<head>` + `[reviewer] ✅ merge-ready … head <sha7>`, nhưng merge gate vẫn exit 11
# (qa-report) → thẻ chạm rebuild_cap và bị Blocked. Chỉ mục review-only được gỡ, khi có CẢ merge-ready lẫn approved-head đúng head, mới hơn report QA.
#  A  dạng PR #1292 -> exit 0.
#  B  Not done của AC code (không nói review độc lập), reviewer + approved-head đủ -> vẫn exit 1.
#  C  merge-ready ở head KHÁC head PR (approved-head đúng head) -> exit 1.
#  D  có merge-ready đúng head nhưng THIẾU approved-head -> exit 1.
#  E  reviewer + approved-head CŨ hơn report QA -> exit 1.
#  F  mục lẫn `AC1 chưa đạt; AC4 review độc lập` -> exit 1 (vế AC1 vẫn chặn).
#  G  không có --head -> exit 1 (fail closed).
#  I  `AC1 chưa đạt, AC4 review độc lập` (nối bằng dấu phẩy) và `AC1 chưa đạt — chuyển lane Review` -> exit 1.
#  J  `AC4 review độc lập, chuyển lane Review` (dấu phẩy trong chính vế review-only) -> exit 0.
#  H  comment reviewer của người không đáng tin -> exit 1.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QA="${SB_TEST_QA_REPORT:-$ROOT/.claude/bin/super-board-qa-report.py}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qarevonly-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
HEAD=314e948918ea5d31731c0daef2d55fb176627fa6
OTHER=9b538126aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# mk <file> <not-done> <mode>   mode: ok | otherhead | noapproval | old | untrusted
mk() { python3 - "$1" "$2" "$3" "$HEAD" "$OTHER" <<'PY'
import json, sys
f, nd, mode, head, other = sys.argv[1:6]
body = "## Acceptance criteria\n- [x] AC1 cổng OCR nhận phiên ocr\n  ↳ test exit 0\n- [ ] AC4 độc lập: reviewer không phải tác giả duyệt\n"
def c(text, assoc="OWNER", login="bot"):
    return {"author": {"login": login}, "authorAssociation": assoc, "body": text}
qa = c("[qa] [report] ✅ QA v4 · PR #1292 @ d0093822\nDid: test\n" + nd + "\nNext: reviewer\n")
rev_head = other[:8] if mode == "otherhead" else head[:8]
rev = c("<!-- super-review:report -->\n[reviewer] [report] ✅ merge-ready · round 3 · head %s\nDid: đọc AC\n" % rev_head)
ab = '{"reviewer":"antigravity","builder":"issue-1258-build","task_id":"T0005-audit-pr-1292","gate_receipt":"r1"}'
if mode == "selfreview":
    ab = ab.replace("antigravity", "issue-1258-build", 1)
app = c("approved-head:%s\napproved-by: %s" % (head, ab))
if mode == "bareowner":
    app = c("approved-head:%s" % head)
if mode == "baremember":
    app = c("approved-head:%s" % head, "MEMBER")
if mode == "indented":
    app = c("    approved-head:%s\n    approved-by: %s" % (head, ab))
if mode == "untrusted":
    rev = c(rev["body"], "NONE", "stranger"); app = c(app["body"], "NONE", "stranger")
comments = [rev, app, qa] if mode == "old" else [qa, rev, app]
if mode == "rejected":
    comments = [qa, rev, app, c("[reviewer] [report] ❌ bounced · round 4 · head %s\n" % head[:8])]
if mode == "authornone":
    rev = c(rev["body"], "NONE", "bot"); app = c("approved-head:%s" % head, "NONE", "bot"); comments = [qa, rev, app]
if mode == "noapproval":
    comments = [qa, rev]
json.dump({"body": body, "author": {"login": "bot"}, "comments": comments}, open(f, "w"))
PY
}
run() { python3 "$QA" --meta "$1" ${2:+--head "$2"} >"$TMP/out" 2>&1; echo $?; }

ND='❌ Not done: AC4 phần review độc lập (không phải tác giả) — chuyển lane Review'
mk "$TMP/a.json" "$ND" ok
[ "$(run "$TMP/a.json" "$HEAD")" = 0 ] && ok "A: dạng PR #1292 không còn chặn" || { fail "A: bị chặn"; cat "$TMP/out"; }

mk "$TMP/b.json" '❌ Not done: AC1 test cổng OCR chưa đạt, còn 3 lỗi' ok
[ "$(run "$TMP/b.json" "$HEAD")" = 1 ] && ok "B: AC code vẫn chặn" || { fail "B: bị lọt"; cat "$TMP/out"; }

mk "$TMP/c.json" "$ND" otherhead
[ "$(run "$TMP/c.json" "$HEAD")" = 1 ] && ok "C: merge-ready ở head khác không gỡ" || { fail "C: bị lọt"; cat "$TMP/out"; }

mk "$TMP/d.json" "$ND" noapproval
[ "$(run "$TMP/d.json" "$HEAD")" = 1 ] && ok "D: thiếu approved-head không gỡ" || { fail "D: bị lọt"; cat "$TMP/out"; }

mk "$TMP/e.json" "$ND" old
[ "$(run "$TMP/e.json" "$HEAD")" = 1 ] && ok "E: reviewer cũ hơn report QA không gỡ" || { fail "E: bị lọt"; cat "$TMP/out"; }

mk "$TMP/f.json" '❌ Not done: AC1 chưa đạt; AC4 phần review độc lập — chuyển lane Review' ok
[ "$(run "$TMP/f.json" "$HEAD")" = 1 ] && ok "F: vế AC1 trong mục lẫn vẫn chặn" || { fail "F: bị lọt"; cat "$TMP/out"; }

mk "$TMP/g.json" "$ND" ok
[ "$(run "$TMP/g.json")" = 1 ] && ok "G: không --head thì không gỡ" || { fail "G: bị lọt"; cat "$TMP/out"; }

mk "$TMP/h.json" "$ND" untrusted
[ "$(run "$TMP/h.json" "$HEAD")" = 1 ] && ok "H: reviewer không đáng tin không gỡ" || { fail "H: bị lọt"; cat "$TMP/out"; }

mk "$TMP/i.json" '❌ Not done: AC1 test cổng OCR chưa đạt, AC4 phần review độc lập — chuyển lane Review' ok
[ "$(run "$TMP/i.json" "$HEAD")" = 1 ] && ok "I1: AC code nối dấu phẩy vẫn chặn" || { fail "I1: bị lọt"; cat "$TMP/out"; }
mk "$TMP/i2.json" '❌ Not done: AC1 test cổng OCR chưa đạt — chuyển lane Review' ok
[ "$(run "$TMP/i2.json" "$HEAD")" = 1 ] && ok "I2: AC code + 'chuyển lane Review' vẫn chặn" || { fail "I2: bị lọt"; cat "$TMP/out"; }
mk "$TMP/i3.json" '❌ Not done: AC1 chưa đạt (xem review độc lập)' ok
[ "$(run "$TMP/i3.json" "$HEAD")" = 1 ] && ok "I3: chữ trong ngoặc không tính" || { fail "I3: bị lọt"; cat "$TMP/out"; }
mk "$TMP/j.json" '❌ Not done: AC4 phần review độc lập, chuyển lane Review' ok
[ "$(run "$TMP/j.json" "$HEAD")" = 0 ] && ok "J: dấu phẩy trong vế review-only vẫn qua" || { fail "J: bị chặn"; cat "$TMP/out"; }

for m in selfreview baremember rejected authornone indented; do
  mk "$TMP/m_$m.json" "$ND" $m
  [ "$(run "$TMP/m_$m.json" "$HEAD")" = 1 ] && ok "M: $m không gỡ" || { fail "M: $m bị lọt"; cat "$TMP/out"; }
done
mk "$TMP/m_bare.json" "$ND" bareowner
[ "$(run "$TMP/m_bare.json" "$HEAD")" = 0 ] && ok "M: approved-head trần của OWNER gỡ" || { fail "M: owner bare bị chặn"; cat "$TMP/out"; }

# P1 của review: AC code có dấu phẩy/gạch ngang trong chính chữ AC, hay nối bằng từ (và/nên/and), không được gỡ.
ACX='- [ ] parser xử lý file rỗng, file null không crash'
python3 - "$TMP/n.json" <<'PY'
import json, sys
head = "314e948918ea5d31731c0daef2d55fb176627fa6"
c = lambda t: {"author": {"login": "bot"}, "authorAssociation": "OWNER", "body": t}
ab = '{"reviewer":"antigravity","builder":"b","task_id":"T0005-audit","gate_receipt":"r"}'
qa = c("[qa] [report] ✅ QA\n❌ Not done: parser xử lý file rỗng, file null không crash — vẫn crash\n")
json.dump({"body": "## Acceptance criteria\n- [ ] parser xử lý file rỗng, file null không crash\n", "author": {"login": "bot"},
  "comments": [qa, c("[reviewer] [report] ✅ merge-ready · head 314e9489\n"), c("approved-head:%s\napproved-by: %s" % (head, ab))]}, open(sys.argv[1], "w"))
PY
[ "$(run "$TMP/n.json" "$HEAD")" = 1 ] && ok "N: AC code có dấu phẩy trong chữ AC vẫn chặn" || { fail "N: bị lọt"; cat "$TMP/out"; }
for nd in '❌ Not done: AC1 chưa đạt và AC4 review độc lập' '❌ Not done: AC1 cổng OCR còn đỏ nên lane Review kiểm lại' '❌ Not done: AC4 review độc lập và AC1 chưa đạt'; do
  mk "$TMP/o.json" "$nd" ok
  [ "$(run "$TMP/o.json" "$HEAD")" = 1 ] && ok "O: '$nd' vẫn chặn" || { fail "O: '$nd' bị lọt"; cat "$TMP/out"; }
done

# P2 vòng 3: mục mở đầu bằng "AC<n> review độc lập" nhưng còn tả lỗi code (cùng dòng hay dòng nối tiếp) không được gỡ.
for nd in '❌ Not done: AC1 phần review độc lập chưa có, phần code: test 413 vẫn đỏ' '❌ Not done: AC1 review độc lập — test 413 vẫn đỏ, payload 2 MB trả 500'; do
  mk "$TMP/p.json" "$nd" ok
  [ "$(run "$TMP/p.json" "$HEAD")" = 1 ] && ok "P: '$nd' vẫn chặn" || { fail "P: '$nd' bị lọt"; cat "$TMP/out"; }
done
mk "$TMP/p2.json" '❌ Not done: AC1 review độc lập chưa có
  - test 413 vẫn đỏ' ok
[ "$(run "$TMP/p2.json" "$HEAD")" = 1 ] && ok "P: dòng nối tiếp mô tả lỗi code vẫn chặn" || { fail "P: dòng nối tiếp bị lọt"; cat "$TMP/out"; }
mk "$TMP/p3.json" '❌ Not done: AC4 phần review độc lập (không phải tác giả) chưa có, chuyển sang lane Review.' ok
[ "$(run "$TMP/p3.json" "$HEAD")" = 0 ] && ok "P: 'chưa có, chuyển sang lane Review' vẫn qua" || { fail "P: bị chặn"; cat "$TMP/out"; }

[ "$FAILS" -eq 0 ] && echo "✅ test_qa_report_review_only_ac: all passed" || { echo "❌ $FAILS failed"; exit 1; }
