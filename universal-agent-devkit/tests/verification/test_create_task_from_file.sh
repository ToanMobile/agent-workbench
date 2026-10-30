#!/usr/bin/env bash
# Test: createTask (scripts/governance/create_task.py) --from-file KHÔNG kèm --ticket (#695).
# 30/10: --from-file <md> --title ... không --ticket bị bỏ qua lặng lẽ, thẻ nhận body mẫu "Chưa có mô tả chi tiết"
# (5 thẻ #688 #691 #692 #693 #694 phải sửa tay). Bây giờ: cả file là body (## Problem … ## Blocked by), title lấy từ
# --title; file thiếu `## Problem` hoặc đọc lỗi → exit 2 kèm lý do và log gh rỗng (assert 3c); thiếu --title → exit 64.
# Có --ticket: hành vi cũ (đọc đúng mục TICKET-N). gh giả ghi mọi lệnh vào calls.jsonl. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/bin" "$TMP/repo"
export FAKE_LOG="$TMP/calls.jsonl" FAKE_ITEMS="$TMP/items.json"
# Một thẻ Backlog cùng loại (bug) nhắc create_task.py: thẻ mới cùng loại thường được GOM vào đây (xem ca 10).
cat > "$TMP/items.json" <<'JSON'
{"items": [{"status": "Backlog", "labels": ["bug"], "content": {"type": "Issue", "repository": "ToanMobile/agent-workbench", "number": 7, "title": "🐛 [bug] create_task: thẻ cũ", "body": "## Problem\nx create_task.py\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n🟢\n"}}]}
JSON
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
if a[:2] == ["issue", "create"]:
    print("https://github.com/ToanMobile/agent-workbench/issues/1"); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_1"})); sys.exit(0)
if a[:2] in (["project", "item-edit"], ["label", "create"]):
    sys.exit(0)
if a[:2] == ["project", "item-list"]:
    print(open(os.environ["FAKE_ITEMS"]).read()); sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"

run() { : > "$FAKE_LOG"; (cd "$TMP/repo" && python3 "$CT" "$@") >"$TMP/out" 2>&1; echo $?; }
gh_calls() { wc -l < "$FAKE_LOG" | tr -d ' '; }
created_body() { python3 - <<'PY'
import json, os
for l in open(os.environ["FAKE_LOG"]):
    a = json.loads(l).get("gh", [])
    if a[:2] == ["issue", "create"]:
        print(a[a.index("--body") + 1]); break
else:
    print("NONE")
PY
}

cat > "$TMP/card.md" <<'MD'
## Problem
Lỗi thật FROMFILE-MARKER-123.

## Context
- Where: kit

## Fix
Sửa đúng một chỗ.

## Acceptance Criteria
- [ ] Test đỏ rồi xanh

## Risk
🟢 Low

## Blocked by
- None.
MD
TITLE="🐛 [fix] create_task: đọc file làm body"

# 1. --from-file + --title, không --ticket, --dry-run: body in ra là nội dung file (không phải body mẫu).
rc=$(run --dry-run --from-file "$TMP/card.md" --title "$TITLE")
[ "$rc" = "0" ] && ok "1a exit 0" || fail "1a exit $rc: $(cat "$TMP/out")"
grep -q "FROMFILE-MARKER-123" "$TMP/out" && grep -q "## Blocked by" "$TMP/out" && grep -q "Sửa đúng một chỗ" "$TMP/out" \
  && ok "1b body có đủ mục ## Problem … ## Blocked by của file" || fail "1b body không có nội dung file: $(cat "$TMP/out")"
grep -q "Chưa có mô tả chi tiết" "$TMP/out" && fail "1c vẫn ra body mẫu" || ok "1c không ra body mẫu"
grep -qF "$TITLE" "$TMP/out" && ok "1d title lấy từ --title" || fail "1d title sai"

# 2. Chạy thật (gh giả): issue create nhận đúng body từ file.
rc=$(run --from-file "$TMP/card.md" --title "$TITLE")
[ "$rc" = "0" ] && [ "$(created_body | grep -c FROMFILE-MARKER-123)" = "1" ] && ok "2 gh issue create nhận body của file" || fail "2 rc=$rc"

# 3. File thiếu ## Problem → exit 2 kèm lý do; log gh rỗng (assert 3c) nên thẻ chưa được tạo.
printf '## Fix\nchỉ có Fix\n' > "$TMP/noproblem.md"
rc=$(run --from-file "$TMP/noproblem.md" --title "$TITLE")
[ "$rc" = "2" ] && ok "3a thiếu ## Problem → exit 2" || fail "3a exit $rc (want 2)"
grep -q "## Problem" "$TMP/out" && ok "3b thông báo nêu lý do" || fail "3b thiếu lý do: $(cat "$TMP/out")"
[ "$(gh_calls)" = "0" ] && ok "3c không gọi gh" || fail "3c đã gọi gh"
rc=$(run --dry-run --from-file "$TMP/noproblem.md" --title "$TITLE")
[ "$rc" = "2" ] && ok "3d dry-run cũng exit 2" || fail "3d exit $rc"

# 4. File không tồn tại → exit 2, không traceback.
rc=$(run --from-file "$TMP/nope.md" --title "$TITLE")
[ "$rc" = "2" ] && ! grep -q Traceback "$TMP/out" && ok "4 file không đọc được → exit 2" || fail "4 exit $rc: $(cat "$TMP/out")"

# 5. Thiếu --title → exit 64; log gh rỗng (assert 5).
rc=$(run --from-file "$TMP/card.md")
[ "$rc" = "64" ] && [ "$(gh_calls)" = "0" ] && ok "5 thiếu --title → exit 64" || fail "5 exit $rc"

# 6. Có --ticket: hành vi cũ, đọc đúng mục TICKET-N (title từ file).
cat > "$TMP/backlog.md" <<'MD'
### TICKET-1: ⚡ [perf] context: cắt byte

## Problem
Ticket một TICKET-ONE-MARKER.

### TICKET-2: 🐛 [bug] hooks: sửa

## Problem
Ticket hai.
MD
rc=$(run --dry-run --from-file "$TMP/backlog.md" --ticket 1)
[ "$rc" = "0" ] && grep -q "TICKET-ONE-MARKER" "$TMP/out" && ! grep -q "Ticket hai" "$TMP/out" && ok "6 --ticket giữ nguyên hành vi" || fail "6 rc=$rc: $(cat "$TMP/out")"

# 7. --ticket 0 là ticket không hợp lệ: exit 64 (không rơi sang nhánh cả-file), log gh rỗng.
rc=$(run --dry-run --from-file "$TMP/backlog.md" --ticket 0 --title "$TITLE")
[ "$rc" = "64" ] && [ "$(gh_calls)" = "0" ] && ok "7 --ticket 0 → exit 64" || fail "7 exit $rc: $(cat "$TMP/out")"

# 8. --title toàn khoảng trắng bị từ chối như thiếu --title.
rc=$(run --dry-run --from-file "$TMP/card.md" --title "   ")
[ "$rc" = "64" ] && [ "$(gh_calls)" = "0" ] && ok "8 --title toàn khoảng trắng → exit 64" || fail "8 exit $rc: $(cat "$TMP/out")"

# 9. --problem/--fix/--ac đi kèm --from-file: cảnh báo bị bỏ qua, body vẫn là file.
rc=$(run --dry-run --from-file "$TMP/card.md" --title "$TITLE" --problem "PROBLEM-DE-THỪA" --ac "- [ ] AC-DE-THỪA")
[ "$rc" = "0" ] && grep -q "bị bỏ qua" "$TMP/out" && grep -q "FROMFILE-MARKER-123" "$TMP/out" && ! grep -q "PROBLEM-DE-THỪA" "$TMP/out" \
  && ok "9 cờ body thừa được cảnh báo và không vào body" || fail "9 rc=$rc: $(cat "$TMP/out")"

# 10. --from-file không --ticket không bị GOM vào thẻ Backlog có sẵn. Đối chứng: cùng loại thẻ lấy từ --problem thì gom (#7),
#     chứng minh thẻ giả #7 đủ điều kiện gom nên ca --from-file không phải đạt vì fixture sai.
BUGTITLE="🐛 [bug] create_task: đọc file làm body"
rc=$(run --dry-run --title "$BUGTITLE" --problem "x create_task.py" --ac "- [ ] y")
grep -q "Sẽ gom" "$TMP/out" && ok "10a đối chứng: thẻ từ --problem được gom vào #7" || fail "10a fixture không gom được: rc=$rc $(cat "$TMP/out")"
rc=$(run --dry-run --from-file "$TMP/card.md" --title "$BUGTITLE")
[ "$rc" = "0" ] && ! grep -q "Sẽ gom" "$TMP/out" && grep -q "FROMFILE-MARKER-123" "$TMP/out" \
  && ok "10b --from-file không --ticket tạo thẻ riêng, không gom" || fail "10b rc=$rc: $(cat "$TMP/out")"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
