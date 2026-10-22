#!/usr/bin/env bash
# 22/10: gate bị giết bằng tín hiệu (trap EXIT không chạy, ví dụ Bash tool hết 10 phút) để lại khoá merge với pid đã chết và mốc
# "at" còn mới. acquire() chỉ reap theo tuổi (stale-after = 3 x lock-timeout, sàn 1800 s), nên gate kế tiếp chờ hết lock-timeout rồi
# thoát 4 dù không còn ai giữ khoá: PR #176 (thẻ #155) kẹt lane Review hơn một giờ. Khoá có pid đã chết phải được reap ngay;
# khoá của pid còn sống thì vẫn phải chờ như cũ. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-dead-holder-test.XXXXXX")"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$TMP"' EXIT
R="$TMP/repo"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init

# gh giả: mọi lệnh thất bại, nên sau khi lấy được khoá gate dừng ở bước đọc PR, không bao giờ chạm GitHub thật.
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\necho "fake gh: $*" >&2\nexit 1\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_HEAVY_SLOT_DIR="$TMP/slots"
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}' > "$CFG"
LOCK="$R/.claude/super-board/inflight/merge.lock"

# pid chắc chắn đã chết: tiến trình con đã thoát và được wait.
sleep 0 & DEAD=$!; wait "$DEAD" 2>/dev/null
mkdir -p "$LOCK"; date +%s > "$LOCK/at"; echo "$DEAD" > "$LOCK/pid"; echo 9 > "$LOCK/pr"
( cd "$R" && bash "$GATE" --config "$CFG" --pr 5 --expect-head deadbeef --lock-timeout 5 ) >"$TMP/g1.log" 2>&1; rc=$?
if grep -q "could not take the merge lock" "$TMP/g1.log"; then
  fail "dead-holder lock was not reaped: gate gave up after --lock-timeout (rc=$rc)"
elif grep -q "lock taken" "$TMP/g1.log"; then
  ok "lock held by a dead pid is reaped at once (rc=$rc after the lock)"
else
  fail "gate never reached the lock (rc=$rc): $(tail -3 "$TMP/g1.log" | tr '\n' ' ')"
fi
grep -q "reaping a lock whose holder pid $DEAD is gone" "$TMP/g1.log" \
  && ok "the reap names the dead pid" || fail "no log line naming the dead pid $DEAD"

# pid còn sống: khoá phải được giữ, gate chờ hết lock-timeout rồi thoát 4 như trước.
rm -rf "$LOCK" "$SB_GITHUB_HALT_FILE"; sleep 300 & LIVE=$!   # ca 1 chạm gh giả và ghi halt: xoá để ca này tới được khoá
mkdir -p "$LOCK"; date +%s > "$LOCK/at"; echo "$LIVE" > "$LOCK/pid"; echo 9 > "$LOCK/pr"
( cd "$R" && bash "$GATE" --config "$CFG" --pr 5 --expect-head deadbeef --lock-timeout 5 ) >"$TMP/g2.log" 2>&1; rc=$?
[ "$rc" -eq 4 ] && grep -q "could not take the merge lock" "$TMP/g2.log" \
  && ok "lock held by a live pid is still respected (exit 4)" || fail "live-holder lock was stolen (rc=$rc)"
[ "$(cat "$LOCK/pid" 2>/dev/null)" = "$LIVE" ] && ok "live holder's lock left untouched" || fail "live holder's lock was changed"
kill "$LIVE" 2>/dev/null

# khoá không có file pid (gate cũ, hoặc chết giữa mkdir và ghi pid): giữ hành vi cũ theo tuổi, không reap ngay.
rm -rf "$LOCK" "$SB_GITHUB_HALT_FILE"; mkdir -p "$LOCK"; date +%s > "$LOCK/at"
( cd "$R" && bash "$GATE" --config "$CFG" --pr 5 --expect-head deadbeef --lock-timeout 5 ) >"$TMP/g3.log" 2>&1; rc=$?
[ "$rc" -eq 4 ] && ok "lock without a pid file still waits (exit 4)" || fail "pid-less fresh lock was reaped (rc=$rc)"

[ "$FAILS" -eq 0 ] && { echo "✅ test_merge_gate_dead_holder: all passed"; exit 0; }
echo "❌ test_merge_gate_dead_holder: $FAILS failed"; exit 1
