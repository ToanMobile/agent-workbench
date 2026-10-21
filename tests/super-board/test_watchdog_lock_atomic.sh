#!/usr/bin/env bash
# Test hồi quy (#115 điểm 4): `take_check_lock` của super-board-watchdog.sh lấy lại khoá cũ quá 120 s bằng rmdir rồi mkdir,
# không nguyên tử. Hai `check` cùng đọc tuổi khoá là cũ: check đầu rmdir + mkdir xong (giữ khoá mới), check sau rmdir đúng
# khoá MỚI đó rồi mkdir lại — cả hai cùng giữ khoá và cùng khởi động runner. Luật: N check cùng gặp một khoá cũ thì đúng một
# check giữ được khoá.
# `stat` giả ngủ 0.5 s sau khi đọc để cả 8 tiến trình cùng thấy khoá cũ trước khi ai kịp lấy lại (tái hiện cửa sổ đua).
# WATCHDOG=<file> chạy lại với bản cũ để thấy ĐỎ. Offline, bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WATCHDOG="${WATCHDOG:-$ROOT/.claude/bin/super-board-watchdog.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-wd-atomic.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

REAL_STAT="$(command -v stat)"
mkdir -p "$TMP/slow-bin"
printf '#!/bin/sh\n"%s" "$@"; rc=$?; sleep 0.5; exit $rc\n' "$REAL_STAT" > "$TMP/slow-bin/stat"
chmod +x "$TMP/slow-bin/stat"

awk '/^(file_mtime|take_check_lock)\(\) \{/{p=1} p{print} p&&/^}/{p=0}' "$WATCHDOG" > "$TMP/fn.sh"
grep -q '^take_check_lock()' "$TMP/fn.sh" || { echo "✖ take_check_lock not found in $WATCHDOG"; exit 1; }

D="$TMP/runner"; mkdir -p "$D/b.check.lock"; touch -t 202001010000 "$D/b.check.lock"
N=8
for i in $(seq 1 $N); do
  ( PATH="$TMP/slow-bin:$PATH"; DIR="$D"; SLUG=b; NOW=$(date +%s); . "$TMP/fn.sh"
    if take_check_lock; then echo "TAKEN" > "$TMP/won.$i"; sleep 2; fi ) >/dev/null 2>&1 &
done
wait
won=$(ls "$TMP"/won.* 2>/dev/null | wc -l | tr -d ' ')
[ "$won" = 1 ] && ok "one of $N checks that meet the same stale lock holds it" \
  || fail "$won of $N checks hold the check lock at once (want 1)"

# Khoá cũ không có tranh chấp vẫn được lấy lại; khoá mới thì không.
( PATH="$PATH"; DIR="$TMP/solo"; SLUG=b; NOW=$(date +%s); mkdir -p "$DIR/b.check.lock"; touch -t 202001010000 "$DIR/b.check.lock"
  . "$TMP/fn.sh"; take_check_lock && [ -d "$DIR/b.check.lock" ] ) && ok "an uncontended stale lock is taken back" || fail "an uncontended stale lock was not taken back"
( PATH="$PATH"; DIR="$TMP/fresh"; SLUG=b; NOW=$(date +%s); mkdir -p "$DIR/b.check.lock"
  . "$TMP/fn.sh"; take_check_lock ) && fail "a fresh lock was taken" || ok "a fresh lock is respected"

[ "$FAILS" -eq 0 ] && { echo "PASS test_watchdog_lock_atomic"; exit 0; }
echo "FAIL test_watchdog_lock_atomic: $FAILS failure(s)"; exit 1
