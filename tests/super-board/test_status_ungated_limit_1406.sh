#!/usr/bin/env bash
# Test hồi quy #1406 (review R2 của PR #1413): mục Health của super-board-status.py đọc `gh pr list --limit 100`, thấp hơn ngưỡng
# max(200, …) của super-board-audit-sweep.py; repo có > 100 PR merge trong 7 ngày bị đếm thiếu âm thầm.
#   L1. 150 PR merge ngoài gate trong 7 ngày ⇒ Health báo đủ 150 (trước sửa: 100);
#   L2. lệnh gh pr list xin --limit >= 200 (không thấp hơn audit-sweep);
#   L3. danh sách chạm trần mà PR cũ nhất vẫn trong cửa sổ 7 ngày ⇒ số đếm là cận dưới, hiển thị `N+` (không thiếu âm thầm);
#   L4. danh sách chạm trần nhưng đã có PR cũ hơn 7 ngày ⇒ số đếm đủ, không có dấu `+`.
# Offline; gh giả tôn trọng --limit như gh thật. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATUS="$ROOT/.claude/bin/super-board-status.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

T="$(mktemp -d "${TMPDIR:-/tmp}/sb-status-ungated-limit-1406.XXXXXX")"
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/repo/.claude/super-board/configs" "$T/bin"
git -C "$T/repo" init -q -b main
cat > "$T/repo/.claude/super-board/configs/demo.json" <<'JSON'
{
  "project": {"owner": "o", "number": 1, "title": "Demo"},
  "repo": {"path": ".", "remote": "https://github.com/o/r"},
  "base_branch": "main",
  "timezone": "Asia/Ho_Chi_Minh"
}
JSON
# gh giả: `pr list` trả TOTAL PR (mới nhất trước), cắt theo --limit; OLD_FROM > 0 ⇒ PR từ vị trí đó trở đi merge 10 ngày trước.
cat > "$T/bin/gh" <<'PY'
#!/usr/bin/env python3
import datetime as dt, json, os, sys
a = sys.argv[1:]
if a[:2] == ["api", "graphql"]:
    print(json.dumps({"data": {"repositoryOwner": {"projectV2": {"items": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": []}}}}}))
    sys.exit(0)
if a[:2] == ["pr", "list"]:
    limit = int(a[a.index("--limit") + 1]) if "--limit" in a else 30
    with open(os.environ["FAKE_DIR"] + "/limit.log", "a") as fh:
        fh.write("%d\n" % limit)
    total, old_from = int(os.environ.get("TOTAL", "0")), int(os.environ.get("OLD_FROM", "0"))
    now = dt.datetime.now(dt.timezone.utc)
    prs = []
    for i in range(total):
        age = dt.timedelta(days=10) if old_from and i >= old_from else dt.timedelta(hours=1, seconds=i)
        oid = "%040x" % (i + 1)
        prs.append({"number": 1000 + i, "headRefOid": oid, "mergeCommit": {"oid": oid},
                    "mergedAt": (now - age).strftime("%Y-%m-%dT%H:%M:%SZ")})
    print(json.dumps(prs[:limit]))
    sys.exit(0)
sys.exit(0)
PY
chmod +x "$T/bin/gh"
export FAKE_DIR="$T"
health() { (cd "$T/repo" && TOTAL="$1" OLD_FROM="${2:-0}" PATH="$T/bin:$PATH" python3 "$STATUS" demo 2>/dev/null) | grep "ungated merges (7d)"; }

: > "$T/limit.log"
line="$(health 150)"
printf '%s\n' "$line" | grep -Eq 'ungated merges \(7d\): 150( |$)' \
  && ok "L1 150 PR merge ngoài gate trong 7 ngày được đếm đủ 150" || fail "L1 đếm thiếu: $line"
lim="$(tail -1 "$T/limit.log")"
[ "${lim:-0}" -ge 200 ] && ok "L2 gh pr list xin --limit $lim (>= 200, không thấp hơn audit-sweep)" || fail "L2 --limit quá thấp: ${lim:-?}"

line="$(health 1000)"
printf '%s\n' "$line" | grep -Eq "ungated merges \(7d\): ${lim}\+( |$)" \
  && ok "L3 chạm trần --limit mà PR cũ nhất còn trong 7 ngày: hiển thị cận dưới ${lim}+" || fail "L3 đếm thiếu âm thầm khi chạm trần: $line"

line="$(health 1000 120)"
printf '%s\n' "$line" | grep -Eq 'ungated merges \(7d\): 120( |$)' \
  && ok "L4 chạm trần nhưng đã thấy PR cũ hơn 7 ngày: số đếm đủ (120), không có dấu +" || fail "L4 sai: $line"

[ "$FAILS" -eq 0 ] && { echo "✅ test_status_ungated_limit_1406: all passed"; exit 0; }
echo "❌ test_status_ungated_limit_1406: $FAILS failed"; exit 1
