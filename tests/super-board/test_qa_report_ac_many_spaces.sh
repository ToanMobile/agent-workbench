#!/usr/bin/env bash
# #1314 (R1 của #1298): AC_ID phải nhận `AC` + nhiều khoảng trắng + số (trước #1299 nhận), mà vẫn không O(n²) trên `AC` + 60000 khoảng trắng.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECKER="$ROOT/.claude/bin/super-board-qa-report.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-acsp-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
now() { python3 -c 'import time; print(time.time())'; }
secs() { python3 -c 'import sys; print(int(float(sys.argv[2]) - float(sys.argv[1])))' "$1" "$2"; }
mkmeta() {  # mkmeta <file> <Not done text>
  python3 - "$1" "$2" <<'PY'
import json, sys
f, nd = sys.argv[1:3]
json.dump({"body": "## Acceptance criteria\n- [ ] AC4 size message still wrong on mobile\n", "author": {"login": "bot"},
           "comments": [{"author": {"login": "bot"}, "authorAssociation": "OWNER",
                         "body": "[qa] [report] ❌ failing · v1\n❌ Not done: " + nd + "\n"}]}, open(f, "w"))
PY
}
for named in "AC       4 test đỏ" "AC          4 test đỏ" "AC       - 4 test đỏ" "AC4 test đỏ" "AC - 4 test đỏ" "ac  -  3 test đỏ"; do
  mkmeta "$TMP/m.json" "$named"
  timeout 10 python3 "$CHECKER" --meta "$TMP/m.json" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] && ok "'$named' names an AC (exit 1)" || fail "'$named' exit $rc (want 1)"
done
SP=$(python3 -c 'print("AC" + " " * 60000 + "x")')
mkmeta "$TMP/m.json" "$SP"
t0=$(now); timeout 30 python3 "$CHECKER" --meta "$TMP/m.json" >/dev/null 2>&1; rc=$?; t1=$(now)
[ "$(secs "$t0" "$t1")" -lt 5 ] && [ "$rc" -eq 0 ] && ok "Not done: AC + 60000 spaces + x in $(secs "$t0" "$t1") s, exit 0" || fail "Not done AC + 60000 spaces took $(secs "$t0" "$t1") s, exit $rc"
python3 - "$TMP/b.json" <<'PY'
import json, sys
json.dump({"body": "## Acceptance criteria\n- [ ] AC" + " " * 60000 + "x size message\n", "author": {"login": "bot"},
           "comments": [{"author": {"login": "bot"}, "authorAssociation": "OWNER",
                         "body": "[qa] [report] ❌ failing · v1\n❌ Not done: AC" + " " * 60000 + "x\n"}]}, open(sys.argv[1], "w"))
PY
t0=$(now); timeout 30 python3 "$CHECKER" --meta "$TMP/b.json" >/dev/null 2>&1; rc=$?; t1=$(now)
[ "$(secs "$t0" "$t1")" -lt 5 ] && ok "PR body + Not done AC + 60000 spaces in $(secs "$t0" "$t1") s (exit $rc)" || fail "PR body AC + 60000 spaces took $(secs "$t0" "$t1") s"
[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
