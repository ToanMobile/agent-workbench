#!/usr/bin/env bash
# Test hồi quy (16/11, PR #1170 / thẻ #974 bị merge gate exit 11 dù đã có #1199): mục Not done viết `AC3 (mô tả) tách sang owner/repo#N, …`
# bị từ chối vì names_ac tách đoạn nhỏ theo cả ngoặc, nên mã `AC3` đứng một mình, tách khỏi cụm "tách sang owner/repo#N" ngay sau ngoặc.
#  A  `AC3 (mô tả) tách sang ToanMobile/GeelyEx2#406, chỉ đo được sau sync …` -> qua (exit 0).
#  B  cùng dạng nhưng KHÔNG dẫn issue repo khác (`AC3 (mô tả) chưa đạt, chỉ đo được sau sync`) -> vẫn exit 1.
#  C  dẫn repo khác nhưng không nói đã tách (`AC3 (mô tả) chưa đạt, xem ToanMobile/GeelyEx2#42`) -> vẫn exit 1.
#  D  vế khác trong cùng mục vẫn nêu AC cục bộ: `AC3 (mô tả) tách sang ToanMobile/GeelyEx2#406; AC1 chưa đạt` -> vẫn exit 1.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QA="${SB_TEST_QA_REPORT:-$ROOT/.claude/bin/super-board-qa-report.py}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qasplit-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mk() { python3 - "$1" "$2" "$3" <<'PY'
import json, sys
f, ac, nd = sys.argv[1:4]
body = "## Acceptance criteria\n" + ac + "\n"
qa = "[qa] [report] ❌ @ abc1234\n" + nd + "\n"
json.dump({"body": body, "author": {"login": "bot"},
           "comments": [{"author": {"login": "bot"}, "authorAssociation": "OWNER", "body": qa}]}, open(f, "w"))
PY
}
run() { python3 "$QA" --meta "$1" >"$TMP/out" 2>&1; echo $?; }

AC='- [x] AC1 đạt
  ↳ QA: test exit 0
- [ ] (repo: GeelyEx2) Drift 5 repo app = 0 sau sync'

mk "$TMP/a.json" "$AC" "❌ Not done: AC3 (drift 5 repo app = 0 sau sync) tách sang ToanMobile/GeelyEx2#406, chỉ đo được sau đợt sync, ngoài phạm vi PR kit này (quy ước #1199)."
[ "$(run "$TMP/a.json")" = 0 ] && ok "A: AC3 (mô tả) tách sang owner/repo#N không bị chặn" || { fail "A: dạng của #1170 vẫn bị chặn"; cat "$TMP/out"; }

mk "$TMP/b.json" "$AC" "❌ Not done: AC3 (drift 5 repo app = 0 sau sync) chưa đạt, chỉ đo được sau đợt sync"
[ "$(run "$TMP/b.json")" = 1 ] && ok "B: không dẫn issue repo khác vẫn exit 1" || { fail "B: bị lọt"; cat "$TMP/out"; }

mk "$TMP/c.json" "$AC" "❌ Not done: AC3 (drift 5 repo app = 0 sau sync) chưa đạt, xem ToanMobile/GeelyEx2#42"
[ "$(run "$TMP/c.json")" = 1 ] && ok "C: dẫn repo khác nhưng không nói đã tách vẫn exit 1" || { fail "C: bị lọt"; cat "$TMP/out"; }

mk "$TMP/d.json" "$AC" "❌ Not done: AC3 (drift 5 repo app = 0 sau sync) tách sang ToanMobile/GeelyEx2#406; AC1 chưa đạt"
[ "$(run "$TMP/d.json")" = 1 ] && ok "D: vế khác nêu AC cục bộ vẫn exit 1" || { fail "D: bị lọt"; cat "$TMP/out"; }

[ "$FAILS" -eq 0 ] && echo "✅ test_qa_report_split_after_parenthetical: all passed" || { echo "❌ $FAILS failed"; exit 1; }
