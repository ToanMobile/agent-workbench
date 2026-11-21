#!/usr/bin/env bash
# Test hồi quy #1406: super-board-status.py hiển thị số PR merge ngoài gate trong 7 ngày (đếm tổng + theo ngày) dưới Health.
# Offline; không gọi gh thật. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATUS="$ROOT/.claude/bin/super-board-status.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

T="$(mktemp -d "${TMPDIR:-/tmp}/sb-status-ungated-1406.XXXXXX")"
trap 'rm -rf "$T"' EXIT

OUT="$(cd "$ROOT" && PYTHONDONTWRITEBYTECODE=1 python3 - "$STATUS" "$T" 2>&1 <<'PY'
import datetime as dt, importlib.util, json, pathlib, sys
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

if not hasattr(m, "summarize_ungated_merges") or not hasattr(m, "ungated_merges_line"):
    print("MISSING_API")
    sys.exit(0)

common = pathlib.Path(sys.argv[2]) / ".git"
receipts = common / "postfix-gate" / "merge_receipts"
receipts.mkdir(parents=True)

now = dt.datetime(2026, 11, 21, 9, 0, 0, tzinfo=dt.timezone.utc)  # 16:00 VN
h1, h2, h3, h4 = "a" * 40, "b" * 40, "c" * 40, "d" * 40
(receipts / f"10-{h1}.json").write_text(json.dumps({"pr": 10, "head": h1, "squash": h1}))

prs = [
    {"number": 10, "headRefOid": h1, "mergeCommit": {"oid": h1}, "mergedAt": "2026-11-20T05:00:00Z"},   # có biên nhận -> bỏ qua
    {"number": 11, "headRefOid": h2, "mergeCommit": {"oid": h2}, "mergedAt": "2026-11-20T20:00:00Z"},   # 2026-11-21 03:00 VN -> ngoài gate
    {"number": 12, "headRefOid": h3, "mergeCommit": {"oid": h3}, "mergedAt": "2026-11-19T10:00:00Z"},   # 2026-11-19 17:00 VN -> ngoài gate
    {"number": 13, "headRefOid": h4, "mergeCommit": {"oid": h4}, "mergedAt": "2026-11-10T10:00:00Z"},   # > 7 ngày -> ngoài cửa sổ
]

s = m.summarize_ungated_merges(prs, common, now_epoch=int(now.timestamp()), tz_name="Asia/Ho_Chi_Minh")
print("total=%s" % s["total_7d"])
print("by_date=%s" % json.dumps(s["by_date"], sort_keys=True))
line = m.ungated_merges_line(s)
print("line=%s" % line)
print("zero_line=%s" % m.ungated_merges_line({"total_7d": 0, "by_date": {}, "ok": True}))
print("err_line=%s" % m.ungated_merges_line({"total_7d": 0, "by_date": {}, "ok": False}))
PY
)"

if printf '%s\n' "$OUT" | grep -qx "MISSING_API"; then
  echo "✖ RED: super-board-status.py thiếu summarize_ungated_merges / ungated_merges_line"
  exit 1
fi

printf '%s\n' "$OUT" | grep -qx 'total=2' && ok "đếm đúng 2 PR merge ngoài gate trong 7 ngày (bỏ PR có biên nhận và PR > 7 ngày)" || fail "total sai: $OUT"
printf '%s\n' "$OUT" | grep -qx 'by_date={"2026-11-19": 1, "2026-11-21": 1}' && ok "đếm đúng theo ngày theo múi giờ config" || fail "by_date sai: $OUT"
printf '%s\n' "$OUT" | grep -q 'line=.*ungated merges (7d): 2' && ok "dòng Health hiển thị số PR merge ngoài gate 7 ngày" || fail "line sai: $OUT"
printf '%s\n' "$OUT" | grep -q 'zero_line=.*ungated merges (7d): 0' && ok "0 PR ngoài gate hiển thị 0" || fail "zero_line sai: $OUT"
printf '%s\n' "$OUT" | grep -q 'err_line=.*ungated merges (7d): ?' && ok "lỗi đọc gh hiển thị ?" || fail "err_line sai: $OUT"

[ "$FAILS" -eq 0 ] && { echo "✅ test_status_ungated_merges_1406: all passed"; exit 0; }
echo "❌ test_status_ungated_merges_1406: $FAILS failed"; exit 1
