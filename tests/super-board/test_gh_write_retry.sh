#!/usr/bin/env bash
# Test hồi quy #520: một lỗi ghi GitHub thoáng qua (502, timeout, rate limit, mạng) chỉ một lần từng đẩy thẻ vào Blocked và gọi
# người (đường #517), dù thử lại vài giây sau là ghi được. Luật mới của gh_write_once:
#  r1  502 một lần rồi ghi được → trả 0: thẻ KHÔNG vào Blocked, không halt, không comment chặn
#  r2  422 (không thoáng qua) → không thử lại: đúng một lần gọi, thẻ vào Blocked như #517
#  r3  thoáng qua mãi → 3 lần gọi (1 + 2 lần thử lại) rồi đường #517
#  r4  comment: lần 1 báo 502 nhưng GitHub đã đăng (marker token có) → không đăng lần 2
#  r4b comment: lần 1 hỏng và chưa đăng → thử lại đúng một lần, cùng token, đăng một lần
#  r5  comment: không đọc lại được marker → không thử lại (không đăng mù), đường #517
#  r6  lệnh không thuộc thẻ (label create) 502 rồi được → không halt
#  r7  403 rate limit → thử lại; 403 Resource not accessible → không; stderr rỗng → không (như #517)
#  r8  stderr của gh vẫn tới caller
# Dùng runner THẬT của checkout chứa file test này (ROOT từ $0). Offline, gh giả. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-write-retry.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/sbin"
# gh giả:
#  - ghi argv (một dòng, xuống dòng thành ⏎) vào $GH_LOG
#  - đọc comment (`api …/issues/N/comments …`): in một dòng khi token sb-write:… trong argv đã có trong $POSTED; READ_FAIL=1 → 502
#  - lệnh khớp FAIL_PAT hỏng FAIL_TIMES lần đầu (đếm ở $CNT) với stderr FAIL_MSG; POST_ON_FAIL=1: comment vẫn "đã đăng" dù báo lỗi
#  - `issue comment` thành công (hoặc POST_ON_FAIL) → body vào $POSTED
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
line="$*"; printf '%s\n' "${line//$'\n'/⏎}" >> "$GH_LOG"
if [ "$1" = api ] && case "$2" in */comments) true ;; *) false ;; esac; then
  [ "${READ_FAIL:-0}" = 1 ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
  tok=$(printf '%s' "$line" | grep -oE 'sb-write:[0-9]+-[0-9]+-[0-9]+' | head -1)
  [ -n "$tok" ] && grep -qF -- "$tok" "$POSTED" 2>/dev/null && echo 4242
  exit 0
fi
post() { [ "$1 $2" = "issue comment" ] && printf '%s\n' "${line//$'\n'/⏎}" >> "$POSTED"; return 0; }
if [ -n "${FAIL_PAT:-}" ] && printf '%s' "$line" | grep -qE -- "$FAIL_PAT"; then
  n=$(cat "$CNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$CNT"
  if [ "$n" -le "${FAIL_TIMES:-1}" ]; then
    [ "${POST_ON_FAIL:-0}" = 1 ] && post "$@"
    [ -n "${FAIL_MSG:-}" ] && printf '%s\n' "$FAIL_MSG" >&2
    exit 1
  fi
fi
post "$@"
exit 0
SH
cat > "$TMP/sbin/super-board-github-read.py" <<'PY'
#!/usr/bin/env python3
import os, sys
if '--halt' in sys.argv:
    open(os.environ['HALT_LOG'], 'a').write(' '.join(sys.argv[1:]) + '\n')
    sys.exit(79)
if '--check' in sys.argv and os.path.exists(os.environ.get('HALTED_FLAG') or '/nonexistent'):
    sys.exit(79)
PY
chmod +x "$TMP/bin/gh" "$TMP/sbin/"*

ITEMS='{"items":[{"id":"I446","status":"QA","labels":[],"content":{"type":"Issue","number":446,"title":"zombie card","assignees":[]}}]}'

# $1 = tên, phần còn lại = lệnh bash trong runner đã source. Biến FAIL_* / POST_ON_FAIL / READ_FAIL đặt trước khi gọi.
run_case() {
  local name="$1"; shift
  rm -f "$TMP/gh.log" "$TMP/halt.log" "$TMP/posted" "$TMP/cnt" "$TMP/err"; rm -rf "$TMP/inflight"; mkdir -p "$TMP/inflight"
  OUT=$( ( SB_LIB_ONLY=1 . "$RUNNER" >/dev/null 2>&1 || exit 99
      set +e; cd "$TMP" || exit 98
      log() { echo "$*" >> "$TMP/log"; }
      PATH="$TMP/bin:$PATH"; export GH_LOG="$TMP/gh.log" HALT_LOG="$TMP/halt.log" POSTED="$TMP/posted" CNT="$TMP/cnt"
      export FAIL_PAT="${FAIL_PAT:-}" FAIL_TIMES="${FAIL_TIMES:-1}" FAIL_MSG="${FAIL_MSG:-}" POST_ON_FAIL="${POST_ON_FAIL:-0}" READ_FAIL="${READ_FAIL:-0}"
      export SB_WRITE_RETRY_DELAYS="0 0"
      SB_GITHUB_READ="$TMP/sbin/super-board-github-read.py"; RUN_MANIFEST=/dev/null
      INFLIGHT_DIR="$TMP/inflight"; BOT_LOGIN=bot; STATUS_FIELD_ID=F; PROJECT_NODE_ID=P
      STATUS_OPTIONS_JSON='[{"name":"Ready","id":"OREADY"},{"name":"QA","id":"OQA"},{"name":"Blocked","id":"OBLOCKED"},{"name":"Done","id":"ODONE"}]'
      PROJECT_ITEMS_JSON="$ITEMS"
      eval "$*" ) 2>"$TMP/err" )
  RC=$?
}
calls() { grep -cE -- "$1" "$TMP/gh.log" 2>/dev/null || true; }
blocked() { grep -qF 'single-select-option-id OBLOCKED' "$TMP/gh.log" 2>/dev/null; }
blocker_comment() { grep -qF 'issue comment 446 --body [orchestrator] [blocker]' "$TMP/gh.log" 2>/dev/null; }
reset_env() { FAIL_PAT=""; FAIL_TIMES=1; FAIL_MSG=""; POST_ON_FAIL=0; READ_FAIL=0; }

echo "r1. 502 một lần rồi ghi được"
reset_env; FAIL_PAT='^issue edit 446 --remove-assignee'; FAIL_TIMES=1; FAIL_MSG='HTTP 502: Bad Gateway (https://api.github.com/graphql)'
run_case r1 'gh_write_once issue edit 446 --remove-assignee bot; echo "rc=$?"'
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'rc=0'; } && ok "r1: transient 502 once → gh_write_once returns 0" || fail "r1: RC=$RC out=$(echo "$OUT" | tr '\n' '|')"
[ "$(calls '^issue edit 446 --remove-assignee')" = 2 ] && ok "r1: exactly one retry" || fail "r1: attempts=$(calls '^issue edit 446 --remove-assignee')"
{ ! blocked && ! blocker_comment && [ ! -s "$TMP/halt.log" ]; } && ok "r1: card NOT Blocked, no blocker comment, no halt" \
  || fail "r1: blocked=$(blocked && echo y || echo n) comment=$(blocker_comment && echo y || echo n) halt=$(cat "$TMP/halt.log" 2>/dev/null)"

echo "r2. 422 không thử lại → #517"
reset_env; FAIL_PAT='^issue edit 446 --remove-assignee'; FAIL_TIMES=9; FAIL_MSG='HTTP 422: Validation Failed (https://api.github.com/repos/o/r/issues/446)'
run_case r2 'gh_write_once issue edit 446 --remove-assignee bot; echo "rc=$?"'
[ "$(calls '^issue edit 446 --remove-assignee')" = 1 ] && ok "r2: 422 is not retried (one attempt)" || fail "r2: attempts=$(calls '^issue edit 446 --remove-assignee')"
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'rc=1' && blocked && blocker_comment && [ ! -s "$TMP/halt.log" ]; } \
  && ok "r2: card → Blocked with blocker comment, runner continues (#517 path)" || fail "r2: RC=$RC out=$(echo "$OUT" | tr '\n' '|')"

echo "r3. thoáng qua mãi → 3 lần rồi #517"
reset_env; FAIL_PAT='^issue edit 446 --remove-assignee'; FAIL_TIMES=9; FAIL_MSG='Post "https://api.github.com/graphql": net/http: TLS handshake timeout'
run_case r3 'gh_write_once issue edit 446 --remove-assignee bot; echo "rc=$?"'
{ [ "$(calls '^issue edit 446 --remove-assignee')" = 3 ] && blocked && printf '%s\n' "$OUT" | grep -qx 'rc=1'; } \
  && ok "r3: 3 attempts (2 retries), then the card goes to Blocked" || fail "r3: attempts=$(calls '^issue edit 446 --remove-assignee') blocked=$(blocked && echo y || echo n)"

echo "r4. comment đã đăng dù báo 502 → không đăng lần 2"
reset_env; FAIL_PAT='^issue comment 446 --body hello'; FAIL_TIMES=1; FAIL_MSG='HTTP 502: Bad Gateway'; POST_ON_FAIL=1
run_case r4 'gh_write_once issue comment 446 --body "hello"; echo "rc=$?"'
n=$(grep -c 'hello' "$TMP/posted" 2>/dev/null || true)
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'rc=0' && [ "$n" = 1 ] && [ "$(calls '^issue comment 446 --body hello')" = 1 ]; } \
  && ok "r4: marker found after the failed post → treated as written, posted once" || fail "r4: RC=$RC out=$(echo "$OUT" | tr '\n' '|') posted=$n tries=$(calls '^issue comment 446 --body hello')"
grep -qE '^api repos/.*/issues/446/comments' "$TMP/gh.log" && ok "r4: the comments of #446 were read back before any retry" || fail "r4: no read-back of comments"
! blocked && ok "r4: card not Blocked" || fail "r4: card Blocked"

echo "r4b. comment hỏng thật, chưa đăng → thử lại một lần, cùng token"
reset_env; FAIL_PAT='^issue comment 446 --body hello'; FAIL_TIMES=1; FAIL_MSG='read: connection reset by peer'
run_case r4b 'gh_write_once issue comment 446 --body "hello"; echo "rc=$?"'
n=$(grep -c 'hello' "$TMP/posted" 2>/dev/null || true)
toks=$(grep '^issue comment 446 --body hello' "$TMP/gh.log" 2>/dev/null | grep -oE 'sb-write:[0-9]+-[0-9]+-[0-9]+' | sort -u | wc -l | tr -d ' ')
{ printf '%s\n' "$OUT" | grep -qx 'rc=0' && [ "$n" = 1 ] && [ "$(calls '^issue comment 446 --body hello')" = 2 ] && [ "$toks" = 1 ]; } \
  && ok "r4b: retried once with the same marker token, posted once" || fail "r4b: out=$(echo "$OUT" | tr '\n' '|') posted=$n tries=$(calls '^issue comment 446 --body hello') tokens=$toks"

echo "r5. không đọc lại được marker → không đăng mù"
reset_env; FAIL_PAT='^issue comment 446 --body hello'; FAIL_TIMES=1; FAIL_MSG='HTTP 503: Service Unavailable'; READ_FAIL=1
run_case r5 'gh_write_once issue comment 446 --body "hello"; echo "rc=$?"'
{ [ "$(calls '^issue comment 446 --body hello')" = 1 ] && blocked; } && ok "r5: marker unreadable → no blind retry, card → Blocked (#517)" \
  || fail "r5: tries=$(calls '^issue comment 446 --body hello') blocked=$(blocked && echo y || echo n)"

echo "r6. lệnh không thuộc thẻ: 502 rồi được → không halt"
reset_env; FAIL_PAT='^label create'; FAIL_TIMES=1; FAIL_MSG='HTTP 502: Bad Gateway'
run_case r6 'gh_write_once label create x --force; echo "rc=$?"'
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'rc=0' && [ ! -s "$TMP/halt.log" ]; } && ok "r6: non-card write retried, no halt" \
  || fail "r6: RC=$RC out=$(echo "$OUT" | tr '\n' '|') halt=$(cat "$TMP/halt.log" 2>/dev/null)"
reset_env; FAIL_PAT='^label create'; FAIL_TIMES=9; FAIL_MSG='HTTP 502: Bad Gateway'
run_case r6b 'gh_write_once label create x --force; echo "rc=$?"'
{ [ "$RC" = 79 ] && [ "$(calls '^label create')" = 3 ] && [ -s "$TMP/halt.log" ]; } && ok "r6b: non-card write still failing after retries → halt 79 as before" \
  || fail "r6b: RC=$RC tries=$(calls '^label create')"

echo "r7. phân loại 403 / stderr rỗng"
reset_env; FAIL_PAT='^issue edit 446'; FAIL_TIMES=1; FAIL_MSG='HTTP 403: You have exceeded a secondary rate limit. Please wait a few minutes before you try again.'
run_case r7a 'gh_write_once issue edit 446 --add-label x; echo "rc=$?"'
{ printf '%s\n' "$OUT" | grep -qx 'rc=0' && [ "$(calls '^issue edit 446')" = 2 ]; } && ok "r7a: 403 secondary rate limit is retried" || fail "r7a: out=$(echo "$OUT" | tr '\n' '|') tries=$(calls '^issue edit 446')"
reset_env; FAIL_PAT='^issue edit 446'; FAIL_TIMES=9; FAIL_MSG='HTTP 403: Resource not accessible by integration'
run_case r7b 'gh_write_once issue edit 446 --add-label x; echo "rc=$?"'
[ "$(calls '^issue edit 446 --add-label')" = 1 ] && ok "r7b: 403 without rate limit is not retried" || fail "r7b: tries=$(calls '^issue edit 446 --add-label')"
reset_env; FAIL_PAT='^issue edit 446'; FAIL_TIMES=9; FAIL_MSG=''
run_case r7c 'gh_write_once issue edit 446 --add-label x; echo "rc=$?"'
[ "$(calls '^issue edit 446 --add-label')" = 1 ] && ok "r7c: failure with empty stderr is not retried" || fail "r7c: tries=$(calls '^issue edit 446 --add-label')"
reset_env; FAIL_PAT='^issue edit 446'; FAIL_TIMES=9; FAIL_MSG='GraphQL: Could not resolve to an Issue with the number of 446. (repository.issue) — timeout'
run_case r7d 'gh_write_once issue edit 446 --add-label x; echo "rc=$?"'
[ "$(calls '^issue edit 446 --add-label')" = 1 ] && ok "r7d: 'Could not resolve to an Issue' (not found) is not retried even with a transient word" || fail "r7d: tries=$(calls '^issue edit 446 --add-label')"

echo "r8. stderr của gh vẫn tới caller"
reset_env; FAIL_PAT='^issue edit 446'; FAIL_TIMES=9; FAIL_MSG='HTTP 422: unique-stderr-marker'
run_case r8 'gh_write_once issue edit 446 --add-label x; echo "rc=$?"'
grep -qF 'unique-stderr-marker' "$TMP/err" && ok "r8: gh stderr is passed through" || fail "r8: stderr lost: $(head -c 200 "$TMP/err")"

echo "r9. trần 2 lần thử lại giữ cả khi SB_WRITE_RETRY_DELAYS dài hơn (review P3-3)"
reset_env; FAIL_PAT='^issue edit 446 --remove-assignee'; FAIL_TIMES=9; FAIL_MSG='HTTP 502: Bad Gateway'
run_case r9 'SB_WRITE_RETRY_DELAYS="0 0 0 0"; gh_write_once issue edit 446 --remove-assignee bot; echo "rc=$?"'
[ "$(calls '^issue edit 446 --remove-assignee')" = 3 ] && ok "r9: 4 delays configured → still 3 attempts" \
  || fail "r9: attempts=$(calls '^issue edit 446 --remove-assignee')"

echo "r10. board bị halt trong lúc ngủ chờ thử lại → không ghi lại nữa (gh_checkpoint sau mỗi lần ngủ, OCR final)"
reset_env; FAIL_PAT='^issue edit 446 --remove-assignee'; FAIL_TIMES=9; FAIL_MSG='HTTP 502: Bad Gateway'
run_case r10 'rm -f "$TMP/halted"; export HALTED_FLAG="$TMP/halted"; tick_sleep() { : > "$TMP/halted"; }; gh_write_once issue edit 446 --remove-assignee bot; echo "rc=$?"'
{ [ "$RC" = 79 ] && [ "$(calls '^issue edit 446 --remove-assignee')" = 1 ] && ! blocked; } \
  && ok "r10: halted during the retry sleep → exits 79, no second write, card not moved" \
  || fail "r10: RC=$RC attempts=$(calls '^issue edit 446 --remove-assignee') blocked=$(blocked && echo y || echo n)"
rm -f "$TMP/halted"

echo "pass=$PASS fail=$FAIL"; [ "$FAIL" = 0 ]
