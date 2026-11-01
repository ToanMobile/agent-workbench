#!/usr/bin/env bash
# Test hồi quy #520 (phần 2-3): thẻ vào Blocked vì một lệnh ghi GitHub của nó hỏng (card-write-failed, #517) được runner tự ghi
# lại mỗi tick thay vì chờ người:
#  s1  chặn thẻ ghi state cục bộ (inflight/card-write-failed/<N>.json: cột cũ, item, argv) + marker máy đọc được trong comment;
#      Reason tag không 🙋, dòng cuối vẫn `blocked-by:  -`
#  s2  tick sau ghi lại được → phát lại đúng lệnh, thẻ về cột cũ, comment [orchestrator] [report], xoá state, không needs-you
#  s3  ghi lại hỏng 3 tick liên tiếp (mỗi tick là một lần source runner mới = runner khởi động lại) → tick 1-2 chỉ đếm, tick 3
#      gắn needs-you một lần, tick 4 thôi thử lại; không bao giờ halt
#  s4  người đã kéo thẻ khỏi Blocked → xoá state, không ghi gì
#  s5  lệnh hỏng là chuyển cột (`project item-edit`, vd sang Building) → không phát lại lệnh chuyển, chỉ đưa thẻ về cột cũ
#  s6  lệnh hỏng là comment: marker token đã có → không đăng lại; chưa có → đăng lại đúng một lần
#  s7  chuyển về cột cũ hỏng → chỉ tăng bộ đếm, không halt, không chặn thẻ lần nữa
#  s8-s10 đọc marker hỏng; cột cũ là Blocked; Building không lock / nhận thẻ đã huỷ (review vòng 1)
#  s11 vòng chặn ↔ trả về với lệnh không phát lại: sau 2 vòng trong 6 giờ thì needs-you, không trả thẻ về nữa
#  s12 hai lệnh ghi của cùng thẻ hỏng trong một tick → lệnh sau nối vào state, giữ cột cũ, phát lại cả hai theo thứ tự
#  s13 `issue reopen` không phát lại (issue_is_open tự xét lại); s14 không lưu được state → comment không hứa "Retry"
#  s15 board đọc lại rồi lệnh khác của thẻ đã Blocked có state hỏng → nối vào state, không ghi đè (review vòng 2)
# Runner THẬT của checkout chứa file test (ROOT từ $0). Offline, gh giả. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-cwf-sweep.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/sbin" "$TMP/inflight"

# gh giả: ghi argv; lệnh khớp FAIL_PAT hỏng (stderr FAIL_MSG, mặc định 422 = không thoáng qua); đọc comment trả token có trong $POSTED
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
line="$*"; printf '%s\n' "${line//$'\n'/⏎}" >> "$GH_LOG"
if [ "$1" = api ] && case "$2" in */comments) true ;; *) false ;; esac; then
  [ "${READ_FAIL:-0}" = 1 ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
  tok=$(printf '%s' "$line" | grep -oE 'sb-write:[0-9]+-[0-9]+-[0-9]+' | head -1)
  [ -n "$tok" ] && grep -qF -- "$tok" "$POSTED" 2>/dev/null && echo 4242
  exit 0
fi
if [ -n "${FAIL_PAT:-}" ] && printf '%s' "$line" | grep -qE -- "$FAIL_PAT"; then
  printf '%s\n' "${FAIL_MSG:-HTTP 422: Validation Failed}" >&2; exit 1
fi
[ "$1 $2" = "issue comment" ] && printf '%s\n' "${line//$'\n'/⏎}" >> "$POSTED"
exit 0
SH
cat > "$TMP/sbin/super-board-github-read.py" <<'PY'
#!/usr/bin/env python3
import os, sys
if '--halt' in sys.argv:
    open(os.environ['HALT_LOG'], 'a').write(' '.join(sys.argv[1:]) + '\n')
    sys.exit(79)
PY
cat > "$TMP/sbin/super-board-needs-you.py" <<'PY'
#!/usr/bin/env python3
import os, sys
import json
open(os.environ['NY_LOG'], 'a').write(json.dumps(sys.argv[1:], ensure_ascii=False) + '\n')
PY
chmod +x "$TMP/bin/gh" "$TMP/sbin/"*
printf '{"repo":{"remote":"https://github.com/acme/widgets"}}' > "$TMP/cfg.json"

board() {   # board <status của #446>
  printf '{"items":[{"id":"I446","status":"%s","labels":[],"content":{"type":"Issue","number":446,"title":"zombie card","assignees":[]}}]}' "$1"
}
# run_tick <cột của #446 trên board> <lệnh>: một lần source runner mới (như runner khởi động lại), state trong $TMP/inflight giữ nguyên.
run_tick() {
  local col="$1"; shift
  rm -f "$TMP/gh.log"
  OUT=$( ( SB_LIB_ONLY=1 . "$RUNNER" >/dev/null 2>&1 || exit 99
      set +e; cd "$TMP" || exit 98
      log() { echo "$*" >> "$TMP/log"; }
      PATH="$TMP/bin:$PATH"; export GH_LOG="$TMP/gh.log" HALT_LOG="$TMP/halt.log" POSTED="$TMP/posted" NY_LOG="$TMP/ny.log"
      export FAIL_PAT="${FAIL_PAT:-}" FAIL_MSG="${FAIL_MSG:-}" READ_FAIL="${READ_FAIL:-0}" SB_WRITE_RETRY_DELAYS="0 0"
      SB_GITHUB_READ="$TMP/sbin/super-board-github-read.py"; RUN_MANIFEST=/dev/null; CONFIG_PATH="$TMP/cfg.json"
      INFLIGHT_DIR="$TMP/inflight"; BOT_LOGIN=bot; STATUS_FIELD_ID=F; PROJECT_NODE_ID=P
      STATUS_OPTIONS_JSON='[{"name":"Ready","id":"OREADY"},{"name":"Building","id":"OBUILD"},{"name":"QA","id":"OQA"},{"name":"Blocked","id":"OBLOCKED"},{"name":"Done","id":"ODONE"}]'
      PROJECT_ITEMS_JSON="$(board "$col")"
      eval "$*" ) 2>/dev/null )
  RC=$?
}
STATE="$TMP/inflight/card-write-failed/446.json"
gh_has() { grep -qE -- "$1" "$TMP/gh.log" 2>/dev/null; }
ghl() { cat "$TMP/gh.log" 2>/dev/null | tr '\n' '|'; }
fresh() { rm -rf "$TMP/inflight" "$TMP/posted" "$TMP/ny.log" "$TMP/halt.log" "$TMP/log"; mkdir -p "$TMP/inflight"; FAIL_PAT=""; FAIL_MSG=""; READ_FAIL=0; }
# block_446 <lệnh gh_write_once …>: lệnh ghi của #446 hỏng (422) khi #446 ở QA → thẻ vào Blocked qua đường #517
block_446() { FAIL_PAT="$1"; shift; run_tick QA "$*"; FAIL_PAT=""; }

echo "s1. chặn thẻ ghi state + marker"
fresh
block_446 '^issue edit 446 --remove-assignee' 'gh_write_once issue edit 446 --remove-assignee bot; echo "rc=$?"'
{ printf '%s\n' "$OUT" | grep -qx 'rc=1' && gh_has 'single-select-option-id OBLOCKED'; } && ok "s1: #446 Blocked via the #517 path" || fail "s1: out=$OUT"
{ [ -s "$STATE" ] && [ "$(jq -r .from "$STATE")" = QA ] && [ "$(jq -r .item "$STATE")" = I446 ] \
  && [ "$(jq -c '.argvs[0]' "$STATE")" = '["issue","edit","446","--remove-assignee","bot"]' ] && [ "$(jq -r .fails "$STATE")" = 0 ]; } \
  && ok "s1: local state saved (from=QA, item, argv, fails=0)" || fail "s1: state=$(cat "$STATE" 2>/dev/null)"
c=$(grep -F 'issue comment 446 --body [orchestrator] [blocker]' "$TMP/gh.log" 2>/dev/null)
{ printf '%s' "$c" | grep -qF 'sb-card-write-failed {"issue":446,"from":"QA"}' && printf '%s' "$c" | grep -qF 'blocked-by:  -' \
  && ! printf '%s' "$c" | grep -q 'Reason tag:[^⏎]*🙋'; } && ok "s1: comment carries the machine-readable card-write-failed marker, no 🙋, blocked-by:  -" \
  || fail "s1: comment=$(printf '%s' "$c" | cut -c1-300)"

echo "s2. tick sau ghi lại được → về cột cũ"
run_tick Blocked 'sweep_card_write_failed; echo "rc=$?"'
{ gh_has '^issue edit 446 --remove-assignee bot$' && gh_has 'single-select-option-id OQA' && gh_has '^issue comment 446 --body \[orchestrator\] \[report\]'; } \
  && ok "s2: write re-applied, card back to QA, report comment" || fail "s2: gh=$(ghl | cut -c1-400)"
{ [ ! -e "$STATE" ] && [ ! -s "$TMP/ny.log" ] && [ ! -s "$TMP/halt.log" ]; } && ok "s2: state cleared, no needs-you, no halt" \
  || fail "s2: state=$([ -e "$STATE" ] && echo kept || echo gone) ny=$(cat "$TMP/ny.log" 2>/dev/null) halt=$(cat "$TMP/halt.log" 2>/dev/null)"

echo "s3. ghi lại hỏng 3 tick liên tiếp → needs-you, thôi thử lại"
fresh
block_446 '^issue edit 446 --remove-assignee' 'gh_write_once issue edit 446 --remove-assignee bot'
FAIL_PAT='^issue edit 446 --remove-assignee'
run_tick Blocked 'sweep_card_write_failed; echo "rc=$?"'
{ [ "$RC" = 0 ] && [ "$(jq -r .fails "$STATE" 2>/dev/null)" = 1 ] && [ ! -s "$TMP/ny.log" ] && ! gh_has 'OQA'; } \
  && ok "s3: tick 1 fails → counter 1, no needs-you, card stays Blocked" || fail "s3 t1: RC=$RC state=$(cat "$STATE" 2>/dev/null) ny=$(cat "$TMP/ny.log" 2>/dev/null)"
run_tick Blocked 'sweep_card_write_failed'
{ [ "$(jq -r .fails "$STATE" 2>/dev/null)" = 2 ] && [ ! -s "$TMP/ny.log" ]; } && ok "s3: tick 2 (fresh runner) → counter 2 survives the restart" \
  || fail "s3 t2: state=$(cat "$STATE" 2>/dev/null)"
run_tick Blocked 'sweep_card_write_failed'
{ [ "$(grep -c '"--issue", "446"' "$TMP/ny.log" 2>/dev/null)" = 1 ] && grep -q '^\["mark"' "$TMP/ny.log" && [ "$(jq -r .gave_up "$STATE" 2>/dev/null)" = true ]; } \
  && ok "s3: tick 3 → needs-you marked once, retries stop (gave_up)" || fail "s3 t3: ny=$(cat "$TMP/ny.log" 2>/dev/null) state=$(cat "$STATE" 2>/dev/null)"
run_tick Blocked 'sweep_card_write_failed'
{ ! gh_has '^issue edit 446 --remove-assignee' && [ "$(grep -c '"--issue", "446"' "$TMP/ny.log" 2>/dev/null)" = 1 ]; } \
  && ok "s3: tick 4 → no retry, needs-you not marked again" || fail "s3 t4: gh=$(ghl) ny=$(cat "$TMP/ny.log" 2>/dev/null)"
[ ! -s "$TMP/halt.log" ] && ok "s3: no halt at any tick" || fail "s3: halt=$(cat "$TMP/halt.log")"
# --action/--next phải qua bộ lọc one_line THẬT của super-board-needs-you.py (dòng máy, việc agent tự làm được, > 500 ký tự → exit 64)
v=$(python3 -I - "$ROOT/.claude/bin/super-board-needs-you.py" "$TMP/ny.log" <<'PY2'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("ny", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
a = json.loads(open(sys.argv[2]).readline())
try:
    m.one_line(a[a.index("--action") + 1], "--action"); m.one_line(a[a.index("--next") + 1], "--next"); print("ok")
except ValueError as e:
    print("refused: %s" % e)
PY2
)
[ "$v" = ok ] && ok "s3: --action/--next pass the real needs-you one_line filter" || fail "s3: needs-you would refuse: $v"

echo "s4. người kéo thẻ khỏi Blocked → xoá state"
fresh
block_446 '^issue edit 446 --remove-assignee' 'gh_write_once issue edit 446 --remove-assignee bot'
had=$([ -s "$STATE" ] && echo yes || echo no)
run_tick Ready 'sweep_card_write_failed'
{ [ "$had" = yes ] && [ ! -e "$STATE" ] && ! gh_has '^issue edit 446'; } && ok "s4: card no longer Blocked → state dropped, nothing written" \
  || fail "s4: state=$([ -e "$STATE" ] && echo kept || echo gone) gh=$(ghl)"

echo "s5. chuyển cột hỏng → không phát lại lệnh chuyển, chỉ về cột cũ"
fresh
FAIL_PAT='^project item-edit .*option-id OBUILD'; run_tick Ready 'set_card_status I446 Building; echo "rc=$?"'; FAIL_PAT=""
[ "$(jq -r .from "$STATE" 2>/dev/null)" = Ready ] && ok "s5: failed Building move → state from=Ready" || fail "s5: state=$(cat "$STATE" 2>/dev/null)"
run_tick Blocked 'sweep_card_write_failed'
{ ! gh_has 'option-id OBUILD' && gh_has 'option-id OREADY' && [ ! -e "$STATE" ]; } && ok "s5: no replay of the Building move, card back to Ready, state cleared" \
  || fail "s5: gh=$(ghl)"

echo "s6. comment hỏng: marker có → không đăng lại; chưa có → đăng một lần"
fresh
block_446 '^issue comment 446 --body hello' 'gh_write_once issue comment 446 --body hello'
tok=$(jq -r '.argvs[0] | join(" ")' "$STATE" 2>/dev/null | grep -oE 'sb-write:[0-9]+-[0-9]+-[0-9]+')
[ -n "$tok" ] && ok "s6: saved argv keeps the comment's marker token" || fail "s6: no token in state argv: $(cat "$STATE" 2>/dev/null)"
printf 'issue comment 446 --body hello⏎<!-- %s -->\n' "$tok" >> "$TMP/posted"   # GitHub đã đăng dù gh báo lỗi
run_tick Blocked 'sweep_card_write_failed'
{ ! gh_has '^issue comment 446 --body hello' && [ ! -e "$STATE" ] && gh_has 'option-id OQA'; } && ok "s6: comment already on GitHub → not posted again, card back to QA" \
  || fail "s6a: gh=$(ghl | cut -c1-300)"
fresh
block_446 '^issue comment 446 --body hello' 'gh_write_once issue comment 446 --body hello'
run_tick Blocked 'sweep_card_write_failed'
{ [ "$(grep -c '^issue comment 446 --body hello' "$TMP/gh.log" 2>/dev/null)" = 1 ] && [ ! -e "$STATE" ]; } && ok "s6: comment missing → posted once on the retry" \
  || fail "s6b: gh=$(ghl | cut -c1-300)"

echo "s7. về cột cũ hỏng → chỉ đếm, không halt, không chặn lại"
fresh
block_446 '^issue edit 446 --remove-assignee' 'gh_write_once issue edit 446 --remove-assignee bot'
FAIL_PAT='option-id OQA'; run_tick Blocked 'sweep_card_write_failed; echo "rc=$?"'; FAIL_PAT=""
{ [ "$RC" = 0 ] && [ "$(jq -r .fails "$STATE" 2>/dev/null)" = 1 ] && [ ! -s "$TMP/halt.log" ] && ! gh_has 'OBLOCKED' \
  && ! gh_has '\[orchestrator\] \[blocker\]'; } && ok "s7: restore move fails → counter 1, no halt, not blocked again" \
  || fail "s7: RC=$RC state=$(cat "$STATE" 2>/dev/null) halt=$(cat "$TMP/halt.log" 2>/dev/null)"

echo "s8. comment: đọc lại marker hỏng → tick hỏng, không đăng mù"
fresh
block_446 '^issue comment 446 --body hello' 'gh_write_once issue comment 446 --body hello'
READ_FAIL=1; run_tick Blocked 'sweep_card_write_failed'; READ_FAIL=0
{ ! gh_has '^issue comment 446 --body hello' && [ "$(jq -r .fails "$STATE" 2>/dev/null)" = 1 ] && ! gh_has 'option-id OQA'; } \
  && ok "s8: marker read fails → not posted, counter 1, card stays Blocked" || fail "s8: gh=$(ghl | cut -c1-300) state=$(cat "$STATE" 2>/dev/null)"

echo "s9. thẻ đã Blocked có chủ đích, comment chặn sau đó hỏng → chỉ đăng lại, giữ Blocked"
fresh
FAIL_PAT='^issue comment 446 --body \[orchestrator\] \[blocker\] 🛑 blocked · pre-flight'
run_tick QA 'set_card_status I446 Blocked; gh_write_once issue comment 446 --body "[orchestrator] [blocker] 🛑 blocked · pre-flight hold"'; FAIL_PAT=""
[ "$(jq -r .from "$STATE" 2>/dev/null)" = Blocked ] && ok "s9: cache follows the successful Blocked move → state from=Blocked" || fail "s9: state=$(cat "$STATE" 2>/dev/null)"
run_tick Blocked 'sweep_card_write_failed'
{ gh_has '^issue comment 446 --body \[orchestrator\] \[blocker\] 🛑 blocked · pre-flight' && ! gh_has 'option-id O(QA|READY)' && ! gh_has 'back to' && [ ! -e "$STATE" ]; } \
  && ok "s9: comment re-posted, card stays Blocked, no back-to report" || fail "s9: gh=$(ghl | cut -c1-300)"

echo "s10. Building mà không còn lock → về Ready; --add-assignee của lượt nhận đã huỷ → không phát lại"
fresh
FAIL_PAT='^issue edit 446 --add-assignee'; run_tick Building 'gh_write_once issue edit 446 --add-assignee bot'; FAIL_PAT=""
[ "$(jq -r .from "$STATE" 2>/dev/null)" = Building ] && ok "s10: state from=Building" || fail "s10: state=$(cat "$STATE" 2>/dev/null)"
run_tick Blocked 'sweep_card_write_failed'
{ ! gh_has '^issue edit 446 --add-assignee' && gh_has 'option-id OREADY' && ! gh_has 'option-id OBUILD' && [ ! -e "$STATE" ]; } \
  && ok "s10: no lock → claim not replayed, card back to Ready (not an empty Building)" || fail "s10: gh=$(ghl | cut -c1-300)"

echo "s11. vòng chặn ↔ trả về (chuyển Building hỏng mãi) → sau 2 vòng: needs-you, không trả về nữa"
fresh
FAIL_PAT='^project item-edit .*option-id OBUILD'
for cyc in 1 2; do
  run_tick Ready 'set_card_status I446 Building'
  run_tick Blocked 'sweep_card_write_failed'
  gh_has 'option-id OREADY' && ok "s11: cycle ${cyc} → card back to Ready" || fail "s11: cycle ${cyc} not restored: $(ghl | cut -c1-200)"
done
run_tick Ready 'set_card_status I446 Building'
[ "$(jq -r .cycles "$STATE" 2>/dev/null)" = 2 ] && ok "s11: third block carries cycles=2" || fail "s11: state=$(cat "$STATE" 2>/dev/null)"
run_tick Blocked 'sweep_card_write_failed'
{ ! gh_has 'option-id OREADY' && grep -q '"--issue", "446"' "$TMP/ny.log" 2>/dev/null && [ "$(jq -r .gave_up "$STATE" 2>/dev/null)" = true ]; } \
  && ok "s11: third round → needs-you, card stays Blocked, no more bouncing" || fail "s11: gh=$(ghl | cut -c1-200) ny=$(cat "$TMP/ny.log" 2>/dev/null)"
FAIL_PAT=""

echo "s12. hai lệnh ghi của cùng thẻ hỏng trong một tick → nối vào state, phát lại theo thứ tự"
fresh
FAIL_PAT='^issue edit 446 --remove-assignee|^issue comment 446 --body back'
run_tick Ready 'gh_write_once issue edit 446 --remove-assignee bot; gh_write_once issue comment 446 --body "back to Ready"'; FAIL_PAT=""
{ [ "$(jq -r .from "$STATE" 2>/dev/null)" = Ready ] && [ "$(jq -r '.argvs | length' "$STATE" 2>/dev/null)" = 2 ] \
  && [ "$(grep -c 'issue comment 446 --body \[orchestrator\] \[blocker\]' "$TMP/gh.log")" = 1 ]; } \
  && ok "s12: second failure appended (from=Ready kept, 2 commands, one blocker comment)" || fail "s12: state=$(cat "$STATE" 2>/dev/null) gh=$(ghl | cut -c1-300)"
run_tick Blocked 'sweep_card_write_failed'
a=$(grep -n '^issue edit 446 --remove-assignee bot$' "$TMP/gh.log" | cut -d: -f1); b=$(grep -n '^issue comment 446 --body back to Ready' "$TMP/gh.log" | cut -d: -f1)
{ [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && gh_has 'option-id OREADY' && [ ! -e "$STATE" ]; } \
  && ok "s12: both writes re-applied in order, card back to Ready" || fail "s12: a=$a b=$b gh=$(ghl | cut -c1-300)"

echo "s13. issue reopen không phát lại"
fresh
FAIL_PAT='^issue reopen 446'; run_tick QA 'gh_write_once issue reopen 446'; FAIL_PAT=""
run_tick Blocked 'sweep_card_write_failed'
{ ! gh_has '^issue reopen 446' && gh_has 'option-id OQA' && [ ! -e "$STATE" ]; } && ok "s13: reopen not replayed blind, card back to QA (issue_is_open decides again)" \
  || fail "s13: gh=$(ghl | cut -c1-200)"

echo "s14. không lưu được state → comment chặn không hứa tự ghi lại"
fresh
FAIL_PAT='^issue edit 446 --remove-assignee'; run_tick QA 'INFLIGHT_DIR=""; gh_write_once issue edit 446 --remove-assignee bot'; FAIL_PAT=""
c=$(grep -F 'issue comment 446 --body [orchestrator] [blocker]' "$TMP/gh.log" 2>/dev/null)
{ [ -n "$c" ] && ! printf '%s' "$c" | grep -q 'Retry:' && ! printf '%s' "$c" | grep -q 'retrying'; } \
  && ok "s14: no state → no Retry line, header without 'retrying'" || fail "s14: comment=$(printf '%s' "$c" | cut -c1-200)"

echo "s15. thẻ đã Blocked có state, board đọc lại (CARD_WRITE_BLOCKED rỗng), lệnh khác của thẻ hỏng → nối vào state, giữ cột cũ"
fresh
FAIL_PAT='^issue edit 446 --remove-assignee'; run_tick QA 'gh_write_once issue edit 446 --remove-assignee bot'
FAIL_PAT='^issue comment 446 --body second'; run_tick Blocked 'gh_write_once issue comment 446 --body second'; FAIL_PAT=""
{ [ "$(jq -r .from "$STATE" 2>/dev/null)" = QA ] && [ "$(jq -r '.argvs | length' "$STATE" 2>/dev/null)" = 2 ] \
  && ! grep -q 'issue comment 446 --body \[orchestrator\] \[blocker\]' "$TMP/gh.log"; } \
  && ok "s15: later failure on a Blocked card with state → appended (from=QA kept), no second blocker comment" \
  || fail "s15: state=$(cat "$STATE" 2>/dev/null) gh=$(ghl | cut -c1-200)"

echo "pass=$PASS fail=$FAIL"; [ "$FAIL" = 0 ]



