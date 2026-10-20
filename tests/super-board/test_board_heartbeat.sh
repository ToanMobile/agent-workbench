#!/usr/bin/env bash
# Test hồi quy cho .github/scripts/board_heartbeat.py (cron GitHub Actions chạy ngoài máy Mac).
#
# 20/10 09:00 máy gập nắp ngủ: watchdog trên máy không ghi được gì, mô tả Project vẫn "🟢 đang chạy" suốt 3,5 giờ.
# Cron ngoài máy đọc giờ "cập nhật HH:MM dd/MM" mà watchdog ghi; cũ hơn ngưỡng thì đổi mô tả thành ⚫ mất tín hiệu.
# Test gọi hàm quyết định decide() với giờ cố định (mạng chỉ dùng trong main()). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/board_heartbeat.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$SCRIPT" ] || { echo "✖ missing $SCRIPT"; echo "❌ test_board_heartbeat: 1 failed"; exit 1; }

# decide <mô tả> <bây giờ ISO, +07:00> <ngưỡng phút> → in mô tả mới, hoặc NONE
decide() {
  python3 - "$SCRIPT" "$1" "$2" "$3" <<'PY'
import importlib.util, sys
from datetime import datetime
spec = importlib.util.spec_from_file_location('hb', sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
out = m.decide(sys.argv[2], datetime.fromisoformat(sys.argv[3]), int(sys.argv[4]))
print('NONE' if out is None else out)
PY
}

NOW=2026-10-20T12:33:00+07:00
out=$(decide "🟢 đang chạy từ 07:09 · 🔨#95 từ 08:45 (15p) · cập nhật 09:00 20/10" "$NOW" 20)
case "$out" in "⚫ mất tín hiệu từ 09:00 20/10"*"🟢 đang chạy từ 07:09"*) ok "stale 🟢 (3h33 old) → ⚫ with the last update time and the previous status" ;;
  *) fail "stale board not marked: '$out'" ;; esac
case "$out" in *"cập nhật"*) fail "the old stamp is kept inside the ⚫ text (cron would re-parse it): '$out'" ;; *) ok "old stamp removed from the ⚫ text" ;; esac

out=$(decide "🟢 đang chạy · không có worker · cập nhật 12:25 20/10" "$NOW" 20)
[ "$out" = NONE ] && ok "fresh update (8 min) → unchanged" || fail "fresh board changed: '$out'"

out=$(decide "⚫ mất tín hiệu từ 09:00 20/10 — máy ngủ/tắt/mất mạng · trước đó: 🟢 đang chạy" "$NOW" 20)
[ "$out" = NONE ] && ok "already ⚫ → not rewritten every run" || fail "⚫ rewritten: '$out'"

out=$(decide "Bảng việc của dự án" "$NOW" 20)
[ "$out" = NONE ] && ok "description without a watchdog stamp → untouched" || fail "foreign description changed: '$out'"

out=$(decide "🟢 đang chạy · cập nhật 23:55 19/10" 2026-10-20T00:05:00+07:00 20)
[ "$out" = NONE ] && ok "stamp from yesterday 10 min ago (midnight) → fresh" || fail "midnight crossing misread: '$out'"

out=$(decide "🟢 đang chạy · cập nhật 23:50 31/12" 2026-01-01T09:00:00+07:00 20)
case "$out" in "⚫ mất tín hiệu từ 23:50 31/12"*) ok "stamp from last year's 31/12 → stale (year wrap)" ;; *) fail "year wrap misread: '$out'" ;; esac

out=$(decide "🟢 đang chạy · cập nhật 09:00 31/02" "$NOW" 20)
[ "$out" = NONE ] && ok "impossible date in the stamp → untouched, no crash" || fail "bad date: '$out'"

out=$(decide "⏸️ đã dừng (người dùng stop) · cập nhật 13:02 20/10" 2026-10-20T18:00:00+07:00 20)
[ "$out" = NONE ] && ok "a board the user stopped stays ⏸️ (nothing should update it)" || fail "stopped board marked ⚫: '$out'"

# Thiếu BOARD_PAT (fork, secret chưa đặt): script phải thoát 0 kèm thông báo.
msg=$(env -u BOARD_PAT python3 "$SCRIPT" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$msg" | grep -q 'BOARD_PAT' && ok "no BOARD_PAT secret → exit 0 with a notice" || fail "no secret: rc=$rc '$msg'"

# Repo public: log Actions ai cũng đọc — main() không được in mô tả/tiêu đề Project private (số card, lane).
leak=$(BOARD_PAT=x BOARD_PROJECTS="1 2" python3 - "$SCRIPT" <<'PY2'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('hb', sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
from datetime import datetime, timedelta, timezone
old = (datetime.now(timezone(timedelta(hours=7))) - timedelta(days=2)).strftime('%H:%M %d/%m')   # luôn cũ, không phụ thuộc giờ chạy test
desc = {1: '🟢 đang chạy · SECRET-CARD 🔨#95 · cập nhật ' + old, 2: '⏸️ đã dừng SECRET-OTHER · cập nhật ' + old}
def fake(token, query, variables):
    if 'mutation' in query:
        return {}
    return {'user': {'projectV2': {'id': 'P%d' % variables['n'], 'title': 'SECRET-TITLE', 'shortDescription': desc[variables['n']]}}}
m.graphql = fake
sys.exit(m.main())
PY2
); rc=$?
printf '%s' "$leak" | grep -q 'SECRET' && fail "project data printed to the public Actions log: $leak" \
  || { [ "$rc" -eq 0 ] && printf '%s' "$leak" | grep -q 'project 1: marked ⚫' && ok "public log names only the project number and the ⚫ verdict" || fail "main rc=$rc out='$leak'"; }

# Watchdog ghi 🟢 mới giữa lúc cron đọc và lúc cron ghi: cron đọc lại ngay trước khi ghi, chuỗi đổi thì không đè ⚫.
race=$(BOARD_PAT=x BOARD_PROJECTS="1" python3 - "$SCRIPT" <<'PY2'
import importlib.util, sys
from datetime import datetime, timedelta, timezone
spec = importlib.util.spec_from_file_location('hb', sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
old = (datetime.now(timezone(timedelta(hours=7))) - timedelta(days=2)).strftime('%H:%M %d/%m')
fresh = datetime.now(timezone(timedelta(hours=7))).strftime('%H:%M %d/%m')
reads = []
def fake(token, query, variables):
    if 'mutation' in query:
        print('MUTATION'); return {}
    reads.append(1)
    d = '🟢 đang chạy · cập nhật ' + (old if len(reads) == 1 else fresh)
    return {'user': {'projectV2': {'id': 'P1', 'shortDescription': d}}}
m.graphql = fake
sys.exit(m.main())
PY2
)
printf '%s' "$race" | grep -q MUTATION && fail "cron overwrote a status the watchdog had just refreshed: $race" \
  || ok "status refreshed between read and write → cron does not overwrite it with ⚫"

[ "$FAILS" -eq 0 ] && echo "✅ test_board_heartbeat: all passed" || { echo "❌ test_board_heartbeat: $FAILS failed"; exit 1; }
