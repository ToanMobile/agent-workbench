#!/usr/bin/env bash
# Test hồi quy (#256): `super-board-card.sh items` đọc board qua nhiều trang; board đổi giữa hai trang làm số item lệch totalCount
# (103 vs 102) và script thoát 69 làm runner chết. Luật: lệch số thì đọc lại MỘT lần; lần đọc lại khớp thì thành công; lệch cả hai
# lần thì vẫn lỗi 69 (không nuốt lỗi thật). `gh` giả ở đầu PATH: lần gọi 1 trả totalCount=3 nhưng chỉ 2 node, lần 2 trả đủ 3.
# SB_CARD=<file> chạy lại với bản cũ để thấy ĐỎ. Chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CARD="${SB_CARD:-$ROOT/.claude/bin/super-board-card.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-card-retry.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cache"

node() { printf '{"id":"I%s","fieldValueByName":{"name":"Ready"},"content":{"__typename":"Issue","number":%s,"title":"t%s","url":"u","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[]}}}' "$1" "$1" "$1"; }
SHORT="[{\"data\":{\"repositoryOwner\":{\"projectV2\":{\"items\":{\"totalCount\":3,\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null},\"nodes\":[$(node 1),$(node 2)]}}}}}]"
FULL="[{\"data\":{\"repositoryOwner\":{\"projectV2\":{\"items\":{\"totalCount\":3,\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null},\"nodes\":[$(node 1),$(node 2),$(node 3)]}}}}}]"
printf '%s' "$SHORT" > "$TMP/short.json"
printf '%s' "$FULL" > "$TMP/full.json"

# gh giả: đếm số lần gọi; MODE=flaky → lần 1 lệch, lần sau đủ; MODE=always → luôn lệch.
cat > "$TMP/bin/gh" <<SH
#!/bin/sh
n=\$(cat "$TMP/calls" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > "$TMP/calls"
if [ "\$MODE" = flaky ] && [ "\$n" -gt 1 ]; then cat "$TMP/full.json"; else cat "$TMP/short.json"; fi
SH
chmod +x "$TMP/bin/gh"

run() { rm -f "$TMP/calls"; MODE="$1" PATH="$TMP/bin:$PATH" SB_CARD_CACHE_DIR="$TMP/cache" SB_CARD_RETRY_SLEEP=0 \
  bash "$CARD" --owner o --number 1 --repo o/r items >"$TMP/out" 2>"$TMP/err"; }

run flaky; rc=$?
[ "$rc" -eq 0 ] && ok "lệch rồi khớp: exit 0" || fail "lệch rồi khớp: exit $rc, want 0 ($(tail -1 "$TMP/err"))"
[ "$(jq '.items|length' "$TMP/out" 2>/dev/null)" = 3 ] && ok "trả đủ 3 item" || fail "không trả đủ 3 item"
[ "$(cat "$TMP/calls")" = 2 ] && ok "đọc lại đúng 1 lần" || fail "số lần gọi gh = $(cat "$TMP/calls"), want 2"

run always; rc=$?
[ "$rc" -eq 69 ] && ok "lệch cả hai lần: vẫn exit 69" || fail "lệch cả hai lần: exit $rc, want 69"
[ "$(cat "$TMP/calls")" = 2 ] && ok "không đọc lại quá 1 lần" || fail "số lần gọi gh = $(cat "$TMP/calls"), want 2"

# AC2: stop.sh ghi stop marker TRƯỚC mọi bước dừng/kill (watchdog không khởi động lại trong khe).
STOP="$ROOT/.claude/bin/super-board-stop.sh"
mark=$(grep -n '^if ! write_stop_mark' "$STOP" | head -1 | cut -d: -f1)
kill1=$(grep -nE '^[[:space:]]+kill_pid "' "$STOP" | head -1 | cut -d: -f1)
[ -n "$mark" ] && [ -n "$kill1" ] && [ "$mark" -lt "$kill1" ] \
  && ok "stop.sh: marker (dòng $mark) trước kill đầu tiên (dòng $kill1)" || fail "stop.sh: marker=$mark kill=$kill1"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
