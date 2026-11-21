#!/usr/bin/env bash
# Test hồi quy #1397:
#  AC1: gỡ assignee (--remove-assignee) là bước dọn claim idempotent — hỏng khi dọn khoá / quét không bao giờ
#       block thẻ hay halt board (exit 79); runner log kèm số issue và chạy tiếp.
#  AC2: lệnh ghi không phải comment (vd `issue edit ... --add-label`) hỏng đến mức halt thì github-halt.json
#       lưu `write_argv` (chứa số issue và đối số đã gửi), không còn `operation: null` trống.
# Chạy offline với runner + super-board-github-read.py THẬT và `gh` giả. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
READ="$ROOT/.claude/bin/super-board-github-read.py"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-rm-assignee-1397.XXXXXX")"
SLEEPER=""
cleanup() { [ -z "$SLEEPER" ] || kill "$SLEEPER" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/bin" "$TMP/inflight"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
line="$*"; printf '%s\n' "${line//$'\n'/⏎}" >> "$GH_LOG"
if [ "$1 $2" = "issue view" ]; then
  echo "OPEN"
  exit 0
fi
if [ "$1 $2" = "api rate_limit" ]; then
  if [ "${RATE_OK:-0}" = 1 ]; then
    echo '{"resources":{"graphql":{"remaining":4000,"reset":1},"core":{"remaining":4000,"reset":1}}}'
    exit 0
  fi
  echo "HTTP 429: rate limit" >&2; exit 1
fi
if [ -n "${FAIL_PAT:-}" ] && printf '%s' "$line" | grep -qE -- "$FAIL_PAT"; then
  printf '%s\n' "${FAIL_MSG:-HTTP 429: rate limit}" >&2
  exit 1
fi
exit 0
SH
chmod +x "$TMP/bin/gh"

sleep 0 & DEAD=$!; wait "$DEAD"

run_in_runner() {
  local pat="$1" msg="$2"; shift 2
  rm -f "$TMP/gh.log" "$TMP/halt.json" "$TMP/log"
  rm -rf "$TMP/inflight"; mkdir -p "$TMP/inflight" "$TMP/wlogs"
  OUT=$( ( SB_LIB_ONLY=1 . "$RUNNER" >/dev/null 2>&1 || exit 99
      set +e; cd "$TMP" || exit 98
      log() { echo "$*" >> "$TMP/log"; }
      PATH="$TMP/bin:$PATH"
      export GH_LOG="$TMP/gh.log" SB_GITHUB_HALT_FILE="$TMP/halt.json"
      export FAIL_PAT="$pat" FAIL_MSG="$msg" SB_WRITE_RETRY_DELAYS="0 0" SB_GITHUB_RETRY_DELAY=0 SB_HALT_RECOVER_DELAY=0 SB_HALT_RECOVER_MAX=0
      SB_GITHUB_READ="$READ"
      RUN_MANIFEST=/dev/null
      INFLIGHT_DIR="$TMP/inflight"
      WORKER_LOG_DIR="$TMP/wlogs"
      BOT_LOGIN=ToanMobile
      STATUS_FIELD_ID=F; PROJECT_NODE_ID=P
      STATUS_OPTIONS_JSON='[{"name":"Ready","id":"OREADY"},{"name":"Building","id":"OBUILD"},{"name":"QA","id":"OQA"},{"name":"Review","id":"OREVIEW"},{"name":"Blocked","id":"OBLOCKED"},{"name":"Done","id":"ODONE"}]'
      eval "$*" ) 2>"$TMP/err" )
  RC=$?
}

gh_has() { grep -qE -- "$1" "$TMP/gh.log" 2>/dev/null; }

echo "A1. reap_finished_locks: gh issue edit --remove-assignee hỏng (và move Blocked cũng hỏng như lúc rate limit) → không halt, tiếp tục chạy"
run_in_runner '^issue edit 1390 --remove-assignee|^project item-edit' 'HTTP 429: rate limit' '
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1390\",\"status\":\"Review\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":1390,\"title\":\"card\",\"assignees\":[\"ToanMobile\"]}}]}"
  printf "PID=%s\nLANE=review\nSTARTED=2026-11-21T05:00:00Z\n" "$DEAD" > "$INFLIGHT_DIR/1390"
  reap_finished_locks
  echo "continued rc=$?"
'
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'continued rc=0' && [ ! -e "$TMP/halt.json" ] && [ ! -e "$TMP/inflight/1390" ]; } \
  && ok "A1: reap_finished_locks continues (rc=0), no github-halt.json, stale lock removed" \
  || fail "A1: RC=$RC out=$(echo "$OUT" | tr '\n' '|') halt=$([ -e "$TMP/halt.json" ] && cat "$TMP/halt.json" || echo none)"
grep -qE 'remove-assignee.*1390|1390.*remove-assignee' "$TMP/log" 2>/dev/null \
  && ok "A1: log records failed remove-assignee sweep with issue #1390" \
  || fail "A1: missing #1390 failure log ($(cat "$TMP/log" 2>/dev/null))"

echo "A2. reap_finished_locks: #1390 trên board, chỉ --remove-assignee hỏng → không chuyển thẻ sang Blocked"
run_in_runner '^issue edit 1390 --remove-assignee' 'HTTP 422: Validation Failed' '
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1390\",\"status\":\"Review\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":1390,\"title\":\"card\",\"assignees\":[\"ToanMobile\"]}}]}"
  printf "PID=%s\nLANE=review\nSTARTED=2026-11-21T05:00:00Z\n" "$DEAD" > "$INFLIGHT_DIR/1390"
  reap_finished_locks
  echo "continued rc=$?"
'
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'continued rc=0' && ! gh_has 'OBLOCKED' && ! gh_has '^issue comment 1390 --body \[orchestrator\] \[blocker\]' && [ ! -e "$TMP/halt.json" ]; } \
  && ok "A2: failed remove-assignee does not move #1390 to Blocked or halt" \
  || fail "A2: RC=$RC gh=$(tr '\n' '|' < "$TMP/gh.log" 2>/dev/null)"

echo "A3. các điểm dọn --remove-assignee khác (adopt_live_locks recycled PID, reclaim_stranded_building) → không halt, log số issue"
sleep 300 & SLEEPER=$!
run_in_runner '^issue edit 1391 --remove-assignee' 'HTTP 429: rate limit' '
  PROJECT_ITEMS_JSON="{\"items\":[]}"
  printf "PID=%s\nLANE=build\nSTARTED=2020-01-01T00:00:00Z\n" "$SLEEPER" > "$INFLIGHT_DIR/1391"
  adopt_live_locks
  echo "adopt rc=$?"
'
kill "$SLEEPER" 2>/dev/null || true; wait "$SLEEPER" 2>/dev/null || true; SLEEPER=""
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'adopt rc=0' && [ ! -e "$TMP/halt.json" ] && grep -q '1391' "$TMP/log"; } \
  && ok "A3a: adopt_live_locks recycled-PID remove-assignee failure does not halt, logs #1391" \
  || fail "A3a: RC=$RC out=$(echo "$OUT" | tr '\n' '|') log=$(cat "$TMP/log" 2>/dev/null)"

run_in_runner '^issue edit 1392 --remove-assignee' 'HTTP 429: rate limit' '
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1392\",\"status\":\"Building\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":1392,\"title\":\"card\",\"assignees\":[\"ToanMobile\"]}}]}"
  reclaim_stranded_building 1392 "worker lost"
  echo "reclaim rc=$?"
'
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'reclaim rc=0' && ! gh_has 'OBLOCKED' && [ ! -e "$TMP/halt.json" ] && grep -q '1392' "$TMP/log"; } \
  && ok "A3b: reclaim_stranded_building remove-assignee failure does not halt, logs #1392" \
  || fail "A3b: RC=$RC out=$(echo "$OUT" | tr '\n' '|') log=$(cat "$TMP/log" 2>/dev/null)"

echo "B1. AC2: lệnh ghi không phải comment (issue edit --add-label) hỏng đến halt → github-halt.json có write_argv chứa số issue"
run_in_runner '^issue edit 1390 --add-label' 'HTTP 502: Bad Gateway' '
  PROJECT_ITEMS_JSON="{\"items\":[]}"
  gh_write_once issue edit 1390 --add-label urgent
  echo "unexpected=$?"
'
{ [ "$RC" = 79 ] && [ -s "$TMP/halt.json" ] \
  && [ "$(jq -c '.write_argv' "$TMP/halt.json" 2>/dev/null)" = '["issue","edit","1390","--add-label","urgent"]' ] \
  && [ "$(jq -r '.operation' "$TMP/halt.json" 2>/dev/null)" = "null" ]; } \
  && ok "B1: non-comment write halt records exact write_argv with issue #1390 (not bare operation:null)" \
  || fail "B1: RC=$RC halt=$(cat "$TMP/halt.json" 2>/dev/null)"

echo "B2. block_card_after_failed_write cũng hỏng → halt vẫn giữ nguyên write_argv của lệnh ghi gốc"
run_in_runner '^issue edit 1390 --add-label|^project item-edit' 'HTTP 502: Bad Gateway' '
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I1390\",\"status\":\"Ready\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":1390,\"title\":\"card\",\"assignees\":[]}}]}"
  gh_write_once issue edit 1390 --add-label urgent
  echo "unexpected=$?"
'
{ [ "$RC" = 79 ] && [ -s "$TMP/halt.json" ] \
  && [ "$(jq -c '.write_argv' "$TMP/halt.json" 2>/dev/null)" = '["issue","edit","1390","--add-label","urgent"]' ]; } \
  && ok "B2: halt after failed card block still preserves original write_argv in github-halt.json" \
  || fail "B2: RC=$RC halt=$(cat "$TMP/halt.json" 2>/dev/null)"

echo "B3. hợp đồng github-read với halt có write_argv: --check=79, --resume=79 (không phát lại mù), --reconcile=11, --resume --reconciled giữ write_argv"
PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" RATE_OK=1 python3 "$READ" --check >/dev/null 2>&1; c_rc=$?
PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" RATE_OK=1 python3 "$READ" --resume >/dev/null 2>&1; r_rc=$?
PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" RATE_OK=1 python3 "$READ" --reconcile >/dev/null 2>&1; rec_rc=$?
PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" RATE_OK=1 python3 "$READ" --resume --reconciled "checked #1390 on GitHub" >/dev/null 2>&1; ok_rc=$?
arch=$(ls "$TMP"/github-halt-reconciled-*.json 2>/dev/null | head -1)
{ [ "$c_rc" = 79 ] && [ "$r_rc" = 79 ] && [ "$rec_rc" = 11 ] && [ "$ok_rc" = 0 ] && [ ! -e "$TMP/halt.json" ] \
  && [ -n "$arch" ] && [ "$(jq -c '.write_argv' "$arch" 2>/dev/null)" = '["issue","edit","1390","--add-label","urgent"]' ]; } \
  && ok "B3: --check/--resume/--reconcile/--resume --reconciled preserve write-halt semantics and archive write_argv" \
  || fail "B3: check=$c_rc resume=$r_rc reconcile=$rec_rc reconciled=$ok_rc arch=$(cat "${arch:-/dev/null}" 2>/dev/null)"

echo "B4. --write-argv sai dạng bị từ chối (exit 64, không ghi halt)"
rm -f "$TMP/halt.json"
for bad in 'not-json' '[]' '123' '["issue", 1390]'; do
  SB_GITHUB_HALT_FILE="$TMP/halt.json" python3 "$READ" --halt "x" --write-argv "$bad" >/dev/null 2>&1; b_rc=$?
  { [ "$b_rc" = 64 ] && [ ! -e "$TMP/halt.json" ]; } || { fail "B4: bad=$bad rc=$b_rc"; break; }
done
SB_GITHUB_HALT_FILE="$TMP/halt.json" python3 "$READ" --write-argv '["issue","edit","1"]' --check >/dev/null 2>&1; nohalt_rc=$?
[ "$nohalt_rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ok "B4: invalid --write-argv or missing --halt exits 64 without halting" \
  || fail "B4: nohalt_rc=$nohalt_rc"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
