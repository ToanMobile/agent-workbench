#!/usr/bin/env bash
# #1199: AC đã tách sang repo khác (nhãn `(repo: <khác>)` trên AC, hay mục Not done dẫn `owner/repo#N`) không được
# làm preflight qa-report thoát 1 (merge gate exit 11, thẻ lặp vòng ac-open). AC của repo này vẫn bị chặn như cũ.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QA="${SB_TEST_QA_REPORT:-$ROOT/.claude/bin/super-board-qa-report.py}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qacross-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# mk <file> <body AC block> <Not done line>
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

AC_LOCAL='- [ ] Merge gate không còn exit 11 vì AC đã tách'
AC_OTHER='- [ ] Drift 5 repo app đồng bộ về pack mới (repo: GeelyEx2)'

mk "$TMP/a.json" "$AC_LOCAL
$AC_OTHER" "❌ Not done: Drift 5 repo app đồng bộ về pack mới (repo: GeelyEx2), đã tách sang ToanMobile/GeelyEx2#42"
[ "$(run "$TMP/a.json")" = 0 ] && ok "AC nhãn (repo: khác) + dẫn issue repo khác: qua" || { fail "AC repo khác vẫn bị chặn"; cat "$TMP/out"; }

mk "$TMP/b.json" "$AC_LOCAL" "❌ Not done: Merge gate không còn exit 11 vì AC đã tách"
[ "$(run "$TMP/b.json")" = 1 ] && ok "AC của repo này chưa xong: vẫn exit 1" || { fail "AC cục bộ không còn bị chặn"; cat "$TMP/out"; }

mk "$TMP/c.json" "$AC_LOCAL" "❌ Not done: AC1 chưa đạt, xem ToanMobile/GeelyEx2#42; Merge gate không còn exit 11 vì AC đã tách"
[ "$(run "$TMP/c.json")" = 1 ] && ok "dẫn repo khác không che AC cục bộ nêu cùng mục: vẫn exit 1" || { fail "mục lẫn bị lọt"; cat "$TMP/out"; }

mk "$TMP/d.json" "$AC_LOCAL" "❌ Not done: AC1 chưa đạt; AC2 đã tách sang ToanMobile/GeelyEx2#42"
[ "$(run "$TMP/d.json")" = 1 ] && ok "nhiều vế (;): AC1 cục bộ không bị che bởi vế AC2 dẫn repo khác" || { fail "mục nhiều vế bị lọt"; cat "$TMP/out"; }

mk "$TMP/e.json" "$AC_LOCAL" "❌ Not done:
- AC1 chưa đạt
- AC2 đã tách sang ToanMobile/GeelyEx2#42"
[ "$(run "$TMP/e.json")" = 1 ] && ok "bullet: AC1 cục bộ không bị che bởi bullet AC2 dẫn repo khác" || { fail "mục bullet bị lọt"; cat "$TMP/out"; }

mk "$TMP/f.json" "$AC_OTHER" "❌ Not done: Drift 5 repo app đồng bộ về pack mới (repo: GeelyEx2)"
[ "$(run "$TMP/f.json")" = 1 ] && ok "AC (repo: khác) chưa dẫn issue đã tách: vẫn exit 1" || { fail "AC repo khác không dẫn issue bị lọt"; cat "$TMP/out"; }

mk "$TMP/g.json" "$AC_LOCAL" "❌ Not done:
- AC2 đã tách sang ToanMobile/GeelyEx2#42
- AC3 thuộc ToanMobile/GeelyEx2#43"
[ "$(run "$TMP/g.json")" = 0 ] && ok "mọi bullet đều dẫn issue repo khác: qua" || { fail "bullet đã tách vẫn bị chặn"; cat "$TMP/out"; }

[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAILS=$FAILS"; exit 1; }
