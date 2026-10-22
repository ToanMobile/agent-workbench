#!/usr/bin/env bash
# Test hồi quy #256 (22/10 22:05-22:15, watchdog log): sau khi máy khởi động lại, một lần đọc board hỏng tạm thời
# (`board read incomplete: 100 of 117 items`, card.sh exit 69) làm runner chết ngay (rc=69). Watchdog khởi động lại 5 lần,
# lần nào cũng chết ở lần đọc đầu, rồi bỏ cuộc: board nằm chết dù 1 phút sau đọc lại được đủ 117/117.
# Luật:
#  A  fetch_project_items đọc lại có backoff (SB_FETCH_RETRY_DELAYS) khi card.sh lỗi; hỏng 2 lần rồi đọc được -> rc 0, cache mới.
#  B  Hỏng mọi lần -> fetch_project_items trả mã lỗi sau đúng (số delay + 1) lần đọc; tick_fetch KHÔNG thoát runner,
#     trả 1 (vòng chính bỏ tick đó) và ghi log; cache cũ giữ nguyên.
#  C  Mã halt có chủ đích (79: GitHub halt) không đọc lại và tick_fetch thoát runner với đúng mã đó.
#  W  Dây nối: vòng chính và paused_tick không còn gọi fetch_project_items trần (mọi lần đọc trong vòng lặp qua tick_fetch).
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-read-retry.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
TICK_SECONDS=0
SB_FETCH_RETRY_DELAYS="0 0 0"

# card.sh giả: STUB_FAILS lần đầu thoát STUB_RC, sau đó in board 2 thẻ. Đếm số lần gọi ở $TMP/calls.
mkdir -p "$TMP/bin"
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
cat > "$TMP/bin/super-board-card.sh" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$STUB_DIR/calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_DIR/calls"
[ "$n" -gt "${STUB_FAILS:-0}" ] || { echo "board read incomplete" >&2; exit "${STUB_RC:-69}"; }
echo '{"items":[{"id":"A","status":"Ready"},{"id":"B","status":"QA"}],"totalCount":2}'
SH
chmod +x "$TMP/bin/super-board-card.sh"
cat > "$TMP/bin/super-board-gh-guard.sh" <<'SH'
sb_gh_quota_merge() { printf '%s\n' "$1"; }
SH
export STUB_DIR="$TMP"
reset_case() { rm -f "$TMP/calls"; : > "$TMP/log"; PROJECT_ITEMS_JSON='{"items":[],"old":true}'; }
calls() { cat "$TMP/calls" 2>/dev/null || echo 0; }

# ── A: hỏng 2 lần rồi đọc được.
reset_case; export STUB_FAILS=2 STUB_RC=69
fetch_project_items; rc=$?
[ "$rc" = 0 ] && [ "$(calls)" = 3 ] && [ "$(echo "$PROJECT_ITEMS_JSON" | jq '.items | length')" = 2 ] \
  && ok "A: a transient read failure is retried with backoff; the 3rd read fills the cache" \
  || fail "A: rc=$rc calls=$(calls) cache=$PROJECT_ITEMS_JSON"

# ── B: hỏng mọi lần.
reset_case; export STUB_FAILS=99 STUB_RC=69
fetch_project_items; rc=$?
[ "$rc" = 69 ] && [ "$(calls)" = 4 ] && [ "$(echo "$PROJECT_ITEMS_JSON" | jq -r '.old')" = true ] \
  && ok "B: fetch gives up after delays+1 reads with the read's code; old cache kept" \
  || fail "B: fetch rc=$rc calls=$(calls) cache=$PROJECT_ITEMS_JSON"
reset_case
( tick_fetch; echo "rc=$?" > "$TMP/tf" ); sub=$?
[ "$sub" = 0 ] && [ "$(cat "$TMP/tf" 2>/dev/null)" = "rc=1" ] && grep -q "skipping this tick" "$TMP/log" \
  && ok "B: tick_fetch keeps the runner alive (returns 1, logs the skipped tick)" \
  || fail "B: tick_fetch subshell rc=$sub result=$(cat "$TMP/tf" 2>/dev/null) log=$(tr '\n' ' ' < "$TMP/log")"

# ── C: halt 79 không đọc lại, thoát runner.
reset_case; export STUB_FAILS=99 STUB_RC=79
( tick_fetch; echo "rc=$?" > "$TMP/tf79" ); sub=$?
[ "$sub" = 79 ] && [ ! -e "$TMP/tf79" ] && [ "$(calls)" = 1 ] \
  && ok "C: a GitHub halt (79) is not retried and still stops the runner with 79" \
  || fail "C: subshell rc=$sub calls=$(calls) returned=$(cat "$TMP/tf79" 2>/dev/null)"

# ── D: lỗi kéo dài không bị che mãi: bỏ quá SB_READ_SKIP_MAX tick liên tiếp thì thoát với mã của lần đọc (không phải
#    halt) để watchdog khởi động lại có backoff và trần; một lần đọc được đặt lại bộ đếm.
reset_case; export STUB_FAILS=99 STUB_RC=69; SB_READ_SKIP_MAX=2; READ_SKIPS=0
( tick_fetch; tick_fetch; echo two-skips > "$TMP/d2"; tick_fetch; echo "survived" > "$TMP/d3" ); sub=$?
[ "$sub" = 69 ] && [ -e "$TMP/d2" ] && [ ! -e "$TMP/d3" ] \
  && ok "D: the 3rd consecutive skipped tick (cap 2) exits 69 so the watchdog sees a crash" \
  || fail "D: subshell rc=$sub d2=$([ -e "$TMP/d2" ] && echo y) d3=$([ -e "$TMP/d3" ] && echo y)"
reset_case; READ_SKIPS=0
( export STUB_FAILS=99; tick_fetch; tick_fetch; rm -f "$TMP/calls"; export STUB_FAILS=0; tick_fetch
  export STUB_FAILS=99; tick_fetch; tick_fetch; echo alive > "$TMP/d4" ); sub=$?
[ "$sub" = 0 ] && [ -e "$TMP/d4" ] \
  && ok "D: a good read resets the skip count" || fail "D: reset — subshell rc=$sub"
unset SB_READ_SKIP_MAX

# ── E: SB_FETCH_RETRY_DELAYS lạ (1.5, 08, chữ) không làm runner chết vì lỗi số học; bỏ qua giá trị đó.
reset_case; export STUB_FAILS=3 STUB_RC=69
( set -eu; tick_sleep() { echo "$1" >> "$TMP/e.sleeps"; }
  SB_FETCH_RETRY_DELAYS="1.5 08 x 0"; fetch_project_items; echo "rc=$?" > "$TMP/e" ); sub=$?
s1=$(sed -n 1p "$TMP/e.sleeps" 2>/dev/null); s2=$(sed -n 2p "$TMP/e.sleeps" 2>/dev/null); s3=$(sed -n 3p "$TMP/e.sleeps" 2>/dev/null)
[ "$sub" = 0 ] && [ "$(cat "$TMP/e" 2>/dev/null)" = "rc=0" ] && [ "$s1" -ge 10 ] && [ "$s2" -ge 8 ] && [ "$s2" -le 12 ] && [ "$s3" -ge 10 ] \
  && ok "E: odd delays fall back to 10s, 08 is decimal 8 (+jitter), no arithmetic crash" \
  || fail "E: subshell rc=$sub result=$(cat "$TMP/e" 2>/dev/null) sleeps=$s1,$s2,$s3"
rm -f "$TMP/e.sleeps"

# ── G: lỗi tạm thời của lần đọc quota (gh_rate_guard, vd 64) cũng chỉ bỏ tick; halt 79 vẫn dừng.
reset_case; READ_SKIPS=0
( gh_rate_guard() { return 64; }; tick_guard; echo "rc=$?" > "$TMP/g" ); sub=$?
[ "$sub" = 0 ] && [ "$(cat "$TMP/g" 2>/dev/null)" = "rc=1" ] \
  && ok "G: a transient quota-read failure skips the tick" || fail "G: subshell rc=$sub result=$(cat "$TMP/g" 2>/dev/null)"
( gh_rate_guard() { return 79; }; tick_guard; echo "rc=$?" > "$TMP/g79" ); sub=$?
[ "$sub" = 79 ] && [ ! -e "$TMP/g79" ] && ok "G: a quota halt (79) still stops the runner" || fail "G: halt subshell rc=$sub"

# ── G2: payload quota hỏng (không phải số) không lặng lẽ tắt guard: gh_rate_guard trả lỗi, tick_guard bỏ tick.
reset_case; READ_SKIPS=0
( python3() { echo 'not json'; }; tick_guard nosleep; echo "rc=$?" > "$TMP/g2" ); sub=$?
[ "$sub" = 0 ] && [ "$(cat "$TMP/g2" 2>/dev/null)" = "rc=1" ] && grep -q "skipping this tick" "$TMP/log" \
  && ok "G2: a malformed quota payload is reported as a failed read, not silently ignored" \
  || fail "G2: subshell rc=$sub result=$(cat "$TMP/g2" 2>/dev/null) log=$(tr '\n' ' ' < "$TMP/log")"

# ── D2: SB_READ_SKIP_MAX lạ không tắt trần (dùng mặc định 5).
reset_case; export STUB_FAILS=99 STUB_RC=69; READ_SKIPS=0
( SB_FETCH_RETRY_DELAYS=""; SB_READ_SKIP_MAX=5s; i=0; while [ $i -lt 7 ]; do tick_fetch nosleep; i=$((i + 1)); done
  echo survived > "$TMP/d5" ); sub=$?
[ "$sub" = 69 ] && [ ! -e "$TMP/d5" ] && ok "D2: a non-numeric SB_READ_SKIP_MAX keeps the default cap" \
  || fail "D2: subshell rc=$sub survived=$([ -e "$TMP/d5" ] && echo y)"

# ── P: tick_fetch nosleep (paused_tick) không ngủ thêm một tick sau khi đọc hỏng: vòng chính tự ngủ sau paused_tick.
reset_case; export STUB_FAILS=99 STUB_RC=69; READ_SKIPS=0
( SB_FETCH_RETRY_DELAYS=""; gh_rate_guard() { :; }; sweep_lane_zombies() { :; }
  tick_sleep() { echo "$1" >> "$TMP/p.sleeps"; }; PAUSED_TICKS=$((PAUSED_READ_EVERY - 1)); paused_tick ); sub=$?
[ "$sub" = 0 ] && [ ! -s "$TMP/p.sleeps" ] \
  && ok "P: a failed paused read adds no tick sleep of its own (the caller sleeps)" \
  || fail "P: subshell rc=$sub sleeps=$(tr '\n' ' ' < "$TMP/p.sleeps" 2>/dev/null)"

# ── R: gh_rate_guard (quota thấp) ngủ tới reset dưới `set -u`, không vấp biến chưa đặt; reset lạ vẫn ngủ 60s.
( set -eu
  python3() { echo '{"resources":{"graphql":{"remaining":10,"reset":0}}}'; }
  tick_sleep() { echo "slept $1" > "$TMP/r"; }
  gh_rate_guard ); sub=$?
[ "$sub" = 0 ] && [ "$(cat "$TMP/r" 2>/dev/null)" = "slept 60" ] \
  && ok "R: gh_rate_guard sleeps 60s on a low quota under set -u" || fail "R: subshell rc=$sub result=$(cat "$TMP/r" 2>/dev/null)"
rm -f "$TMP/r"
( python3() { echo '{"resources":{"graphql":{"remaining":10,"reset":"soon"}}}'; }
  tick_sleep() { echo "slept $1" > "$TMP/r"; }
  gh_rate_guard; echo "rc=$?" > "$TMP/r2" ); sub=$?
[ "$sub" = 0 ] && [ "$(cat "$TMP/r" 2>/dev/null)" = "slept 60" ] && [ "$(cat "$TMP/r2")" = "rc=0" ] \
  && ok "R: a non-numeric reset still sleeps the 60s floor (errexit off under tick_guard)" \
  || fail "R: odd reset — rc=$(cat "$TMP/r2" 2>/dev/null) slept=$(cat "$TMP/r" 2>/dev/null)"

# ── E2: SB_FETCH_RETRY_DELAYS="*" không bị glob thành hàng loạt lần đọc lại (cwd có nhiều file).
reset_case; export STUB_FAILS=99 STUB_RC=69
( SB_FETCH_RETRY_DELAYS="*"; tick_sleep() { :; }; cd "$ROOT" && fetch_project_items ); sub=$?
[ "$sub" = 69 ] && [ "$(calls)" = 2 ] && ok "E2: a glob character in the delays is one delay, not a file list" \
  || fail "E2: rc=$sub calls=$(calls), want 69 / 2"

# ── W: dây nối trong vòng chính và paused_tick.
loop=$(sed -n '/Expensive-tick path/,$p' "$RUNNER")
paused=$(sed -n '/^paused_tick()/,/^}/p' "$RUNNER")
[ -n "$loop" ] && ! printf '%s\n%s\n' "$loop" "$paused" | grep -qE '(^|[;[:space:]])(fetch_project_items|gh_rate_guard)([;[:space:]]|$)' \
  && printf '%s\n' "$loop" | grep -q 'tick_fetch' \
  && ok "W: the main loop and paused_tick read the board only through tick_fetch" \
  || fail "W: a bare fetch_project_items is still in the main loop / paused_tick"

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_board_read_retry: all passed" || { echo "❌ $FAILS failed"; exit 1; }
