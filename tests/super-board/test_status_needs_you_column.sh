#!/usr/bin/env bash
# Test hồi quy #138: Project có option Status "Needs You" (ngoài 7 cột chuẩn) — super-board-status.py phải vẽ nó thành một ô riêng
# và nhóm "Waiting on you" phải đếm cả thẻ ở đó. Trước fix: thẻ bị bỏ khỏi kanban, "Waiting on you: (none)".
#  1. group_by_status: option lạ vào by_status, 7 cột chuẩn vẫn đủ khóa.
#  2. render_kanban: ô "Needs You [2]" có cả 2 thẻ; không có thẻ Needs You thì không có ô đó (đầu ra cũ nguyên vẹn).
#  3. waiting_on_person: liệt kê 2 thẻ Needs You, kể cả khi không có nhãn.
# Chạy offline, không gọi gh. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

OUT="$(cd "$ROOT" && PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT/.claude/bin/super-board-status.py" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
items = [
    {"number": 70, "title": "cần chữ ký", "labels": [], "status": "Needs You"},
    {"number": 71, "title": "cần tài khoản store", "labels": [], "status": "Needs You"},
    {"number": 72, "title": "đang build", "labels": [], "status": "Building"},
]
plain = [i for i in items if i["status"] != "Needs You"]
by = m.group_by_status(items)
print("keys_ok=%s" % all(s in by for s in m.BOARD_ORDER))
print("needs=" + ",".join(str(i["number"]) for i in by.get("Needs You", [])))
glyph = lambda n: "·"
box = m.render_kanban(by, glyph, glyph)
print("box_has_both=%s" % ("Needs You" in box and "#70" in box and "#71" in box))
print("waiting=" + ",".join(str(i["number"]) for i in m.waiting_on_person(items)))
base = m.render_kanban(m.group_by_status(plain), glyph, glyph)
print("plain_no_box=%s" % ("Needs You" not in base))
print("plain_same_as_old=%s" % (base == m.render_kanban({s: [i for i in plain if i["status"] == s] for s in m.BOARD_ORDER}, glyph, glyph)))
PY
)"
chk() { printf '%s\n' "$OUT" | grep -qx "$1"; }
chk "keys_ok=True" && chk "needs=71,70" && ok "group_by_status: Needs You thành nhóm riêng, 7 cột chuẩn đủ" || fail "group_by_status: $(echo "$OUT" | tr '\n' ' ')"
chk "box_has_both=True" && ok "render_kanban: ô Needs You có 2 thẻ" || fail "render_kanban: $(echo "$OUT" | tr '\n' ' ')"
chk "waiting=71,70" && ok "waiting_on_person: 2 thẻ Needs You" || fail "waiting: $(echo "$OUT" | tr '\n' ' ')"
chk "plain_no_box=True" && chk "plain_same_as_old=True" && ok "không có thẻ Needs You: đầu ra không đổi" || fail "plain: $(echo "$OUT" | tr '\n' ' ')"

[ "$FAILS" -eq 0 ] && echo "✅ test_status_needs_you_column: all passed" || { echo "❌ test_status_needs_you_column: $FAILS failed"; exit 1; }
