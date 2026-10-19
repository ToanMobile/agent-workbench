#!/usr/bin/env bash
# Test hồi quy (OCR batch 19/10, MEDIUM): `stop_in_flight` của super-board-run.sh lấy mtime stop marker bằng `stat -f %m`, chỉ đúng
# trên macOS. GNU stat (Linux) nhận `-f` là "filesystem status": in chữ rác mà vẫn thành công, nên `[ "$t" -le ... ]` lỗi và nhánh
# "stop thắng" thắng mãi mãi. Luật ở đây: `file_mtime` trả đúng epoch giây trên cả hai kiểu stat, và `stop_in_flight` quyết đúng theo nó.
# `stat` giả đặt đầu PATH mô phỏng GNU stat (nhận -c %Y, còn -f in thông tin filesystem dạng chữ). RUNNER=<file> chạy lại với bản cũ
# để thấy ĐỎ. Chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="${RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-stop-mtime.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
REAL_PATH="$PATH"
FAKE_PATH="$TMP/gnu-bin:$PATH"

# Mốc thật lấy bằng python (không phụ thuộc kiểu stat), để so với kết quả của file_mtime.
MARK="$TMP/board.stopped"
echo "PID=999999" > "$MARK"
touch -t 202001010000 "$MARK"
WANT=$(python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$MARK")

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

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { :; }
# stop_in_flight nằm sau chỗ SB_LIB_ONLY trả về, nên trích đúng hàm đó ra để chạy.
awk '/^stop_in_flight\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$RUNNER" > "$TMP/fn.sh"
[ -s "$TMP/fn.sh" ] || { echo "✖ stop_in_flight not found in $RUNNER"; exit 1; }
. "$TMP/fn.sh"
STOP_MARK="$MARK"

# ── 1. GNU stat: file_mtime trả đúng epoch.
PATH="$FAKE_PATH"
got=$(file_mtime "$MARK" 2>&1)
[ "$got" = "$WANT" ] && ok "GNU stat: file_mtime = $WANT" || fail "GNU stat: file_mtime gave '$got' want '$WANT'"
# ── 2. macOS (stat thật của máy): file_mtime trả đúng epoch.
PATH="$REAL_PATH"
got=$(file_mtime "$MARK" 2>&1)
[ "$got" = "$WANT" ] && ok "native stat: file_mtime = $WANT" || fail "native stat: file_mtime gave '$got' want '$WANT'"
# ── 3. file không có: file_mtime lỗi, stop_in_flight giữ hành vi an toàn (stop thắng = 0).
file_mtime "$TMP/missing" >/dev/null 2>&1 && fail "missing file: file_mtime should fail" || ok "missing file: file_mtime fails"
STOP_MARK="$TMP/missing"; stop_in_flight; rc=$?
[ "$rc" -eq 0 ] && ok "unreadable mtime: stop wins (rc=0)" || fail "unreadable mtime: rc=$rc want 0"
STOP_MARK="$MARK"
# ── 4. stop_in_flight dưới GNU stat: marker CŨ hơn runner, PID chết = `stop` rồi `run` tuần tự → không phải stop đang chạy (rc=1).
#       Bản cũ (stat -f) nuốt chữ rác, `[ ... -le ]` lỗi → luôn rc=0 = ĐỎ.
PATH="$FAKE_PATH"
RUNNER_BORN=$((WANT + 100)); stop_in_flight; rc=$?
[ "$rc" -eq 1 ] && ok "GNU stat: old marker + dead PID -> not in flight (rc=1)" || fail "GNU stat: old marker rc=$rc want 1"
# ── 5. marker MỚI hơn runner → stop thắng (rc=0).
RUNNER_BORN=$((WANT - 100)); stop_in_flight; rc=$?
[ "$rc" -eq 0 ] && ok "GNU stat: marker newer than runner -> stop wins (rc=0)" || fail "GNU stat: new marker rc=$rc want 0"
# ── 6. cùng hai ca với stat thật của máy.
PATH="$REAL_PATH"
RUNNER_BORN=$((WANT + 100)); stop_in_flight; rc=$?
[ "$rc" -eq 1 ] && ok "native stat: old marker + dead PID -> rc=1" || fail "native stat: old marker rc=$rc want 1"
RUNNER_BORN=$((WANT - 100)); stop_in_flight; rc=$?
[ "$rc" -eq 0 ] && ok "native stat: marker newer than runner -> rc=0" || fail "native stat: new marker rc=$rc want 0"

PATH="$REAL_PATH"
[ "$FAILS" -eq 0 ] && { echo "ALL OK"; exit 0; }
echo "$FAILS FAIL"; exit 1
