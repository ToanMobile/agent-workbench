#!/usr/bin/env bash
# Test hồi quy (OCR batch 19/10, cùng lớp lỗi với run.sh `stop_in_flight`): `take_check_lock` của super-board-watchdog.sh lấy tuổi khoá
# `check` bằng `stat -f %m`, chỉ đúng trên macOS. GNU stat (Linux) nhận `-f` là "filesystem status": in chữ, nên phép tính tuổi khoá lỗi
# và khoá bỏ lại (check bị kill) không bao giờ được lấy lại → watchdog không còn kiểm runner. Luật: khoá cũ hơn 120 s được lấy lại,
# khoá mới thì không, trên cả stat GNU lẫn stat của máy. WATCHDOG=<file> chạy lại với bản cũ để thấy ĐỎ. Offline, bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WATCHDOG="${WATCHDOG:-$ROOT/.claude/bin/super-board-watchdog.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-wd-lock.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
REAL_PATH="$PATH"

# stat giả kiểu GNU: -c %Y in mtime; -f in chữ filesystem (thành công, không phải số); còn lại lỗi.
mkdir -p "$TMP/gnu-bin"
cat > "$TMP/gnu-bin/stat" <<SH
#!/bin/sh
if [ "\$1" = "-c" ] && [ "\$2" = "%Y" ]; then
  exec python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "\$3"
elif [ "\$1" = "-f" ]; then
  printf '  File: "%s"\n    ID: 0 Namelen: 255     Type: apfs\n' "\$3"
  exit 0
fi
exit 1
SH
chmod +x "$TMP/gnu-bin/stat"

# Trích các hàm cần (file_mtime nếu có, take_check_lock) để chạy đúng code của watchdog mà không chạy phần chính.
awk '/^(file_mtime|take_check_lock)\(\) \{/{p=1} p{print} p&&/^}/{p=0}' "$WATCHDOG" > "$TMP/fn.sh"
grep -q '^take_check_lock()' "$TMP/fn.sh" || { echo "✖ take_check_lock not found in $WATCHDOG"; exit 1; }

# <tên ca> <PATH> <mtime khoá: touch -t hoặc "now"> <rc mong đợi>
case_lock() {
  local name="$1" p="$2" when="$3" want="$4" d="$TMP/case.$RANDOM" rc
  mkdir -p "$d/runner"; mkdir "$d/runner/b.check.lock"
  [ "$when" = now ] || touch -t "$when" "$d/runner/b.check.lock"
  # In TAKEN/BUSY sau khi hàm trả về: hàm chết giữa chừng (lỗi số học trên chữ rác của GNU stat) không in gì, nên không lẫn với
  # một quyết định đúng; khoá lấy lại thì thư mục khoá phải còn đó (được tạo lại).
  rc=$( ( PATH="$p"; DIR="$d/runner"; SLUG=b; NOW=$(date +%s); . "$TMP/fn.sh"
          if take_check_lock; then [ -d "$DIR/b.check.lock" ] && echo TAKEN; else echo BUSY; fi ) 2>/dev/null )
  case "$want:$rc" in 0:TAKEN|1:BUSY) ok "$name ($rc)" ;; *) fail "$name: got '${rc:-nothing: function died}' want $([ "$want" = 0 ] && echo TAKEN || echo BUSY)" ;; esac
}

case_lock "GNU stat: stale lock (2020) is taken back"   "$TMP/gnu-bin:$REAL_PATH" 202001010000 0
case_lock "GNU stat: fresh lock is respected"           "$TMP/gnu-bin:$REAL_PATH" now          1
case_lock "native stat: stale lock (2020) is taken back" "$REAL_PATH"             202001010000 0
case_lock "native stat: fresh lock is respected"        "$REAL_PATH"              now          1

[ "$FAILS" -eq 0 ] && { echo "PASS test_watchdog_lock_mtime"; exit 0; }
echo "FAIL test_watchdog_lock_mtime: $FAILS failure(s)"; exit 1
