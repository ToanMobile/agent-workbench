#!/usr/bin/env bash
# Test #1193: thẻ `session` của phiên chat đã chết không được kẹt ở Building.
#  AC1 phiên chết (không tiến trình, transcript im > ngưỡng), không PR mở → issue bị đóng (completed) kèm comment lý do;
#      runner gọi sweep_dead_sessions trước sweep_closed_cards và đặt lại nhịp của nó (về Done trong ≤ 1 tick).
#  AC2 phiên còn sống (tiến trình hoặc transcript mới), thẻ có PR mở `Closes #N`, thẻ không nhãn session, thẻ Done: không đụng.
#  Đọc hỏng (gh pr list lỗi) → exit 79 và không đóng gì.
# Chạy offline: gh và pgrep là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT/.claude/bin/super-board-session-sweep.py"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-session-sweep.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/tr"
printf '{"project":{"owner":"acme","number":1},"repo":{"path":".","remote":"https://github.com/acme/widgets.git"}}' > "$TMP/cfg.json"
OLD="2020-01-01T00:00:00Z"

# gh stub: issue view N → $TMP/issue-N.json ; pr list → $TMP/prs.json (STUB_PR_FAIL=1 → lỗi) ; issue close → ghi writes.
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB/calls"
case "$1 $2" in
  "pr list") [ -n "${STUB_PR_FAIL:-}" ] && { echo "HTTP 502" >&2; exit 1; }; cat "$STUB/prs.json" ;;
  "issue view") cat "$STUB/issue-$3.json" ;;
  "issue close") echo "close $3 $*" >> "$STUB/writes" ;;
  *) exit 1 ;;
esac
SH
cat > "$TMP/bin/pgrep" <<'SH'
#!/usr/bin/env bash
# pgrep -f SID: sống khi $STUB/alive có SID
grep -qx -- "$2" "$STUB/alive" 2>/dev/null
SH
chmod +x "$TMP/bin/gh" "$TMP/bin/pgrep"
export STUB="$TMP" SB_GH="$TMP/bin/gh" SB_SESSION_PGREP="$TMP/bin/pgrep" SB_SESSION_TRANSCRIPT_GLOBS="$TMP/tr/{sid}.jsonl"
: > "$TMP/alive"

mkissue() { # N SID updatedAt
  printf '{"state":"OPEN","updatedAt":"%s","body":"x\\n<!-- sb:session %s -->"}' "$3" "$2" > "$TMP/issue-$1.json"
}
mkissue 1 dead-sess "$OLD"        # chết, không PR → đóng
mkissue 2 alive-proc "$OLD"       # tiến trình còn
mkissue 3 fresh-tr "$OLD"         # transcript mới
mkissue 4 has-pr "$OLD"           # có PR mở Closes #4
mkissue 5 notsession "$OLD"       # không nhãn session
mkissue 6 donecard "$OLD"         # thẻ Done
echo alive-proc > "$TMP/alive"
touch "$TMP/tr/fresh-tr.jsonl"
touch -t 202001010000 "$TMP/tr/dead-sess.jsonl"
printf '[{"number":90,"body":"Fixes stuff\\n\\nCloses #4"}]' > "$TMP/prs.json"
cat > "$TMP/items.json" <<'J'
{"items":[
 {"id":"a","status":"Building","labels":["session"],"content":{"type":"Issue","number":1}},
 {"id":"b","status":"Building","labels":["session"],"content":{"type":"Issue","number":2}},
 {"id":"c","status":"Building","labels":["session"],"content":{"type":"Issue","number":3}},
 {"id":"d","status":"Building","labels":["session"],"content":{"type":"Issue","number":4}},
 {"id":"e","status":"Building","labels":["bug"],"content":{"type":"Issue","number":5}},
 {"id":"f","status":"Done","labels":["session"],"content":{"type":"Issue","number":6}}]}
J

: > "$TMP/writes"
out=$(python3 "$HELPER" sweep --config "$TMP/cfg.json" --items "$TMP/items.json"); rc=$?
[ "$rc" -eq 0 ] && ok "helper exit 0" || fail "helper exit $rc: $out"
[ "$(grep -c '^close ' "$TMP/writes")" = "1" ] && grep -q "^close 1 .*--reason completed" "$TMP/writes" \
  && ok "only dead session #1 closed (completed)" || fail "writes: $(cat "$TMP/writes")"
grep -q "session sweep\|session ended" "$TMP/writes" && ok "close carries a reason comment" || fail "no reason comment"
for n in 2 3 4 5 6; do grep -q "^close $n " "$TMP/writes" && fail "#$n was closed" || :; done
ok "alive process, fresh transcript, open PR, non-session and Done cards untouched"

# đọc hỏng: không đóng gì
: > "$TMP/writes"
STUB_PR_FAIL=1 python3 "$HELPER" sweep --config "$TMP/cfg.json" --items "$TMP/items.json" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 79 ] && [ ! -s "$TMP/writes" ] && ok "pr list failure → exit 79, nothing closed" || fail "read failure: rc=$rc writes=$(cat "$TMP/writes")"

# runner: sweep_dead_sessions chạy trước sweep_closed_cards và đặt lại nhịp của nó
unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
if ! type sweep_dead_sessions >/dev/null 2>&1; then
  fail "runner has no sweep_dead_sessions"
else
  CONFIG_PATH="$TMP/cfg.json"; RUN_MANIFEST="$TMP/manifest"; : > "$RUN_MANIFEST"
  PROJECT_ITEMS_JSON="$(cat "$TMP/items.json")"
  log() { echo "$*" >> "$TMP/log"; }
  : > "$TMP/writes"; SESSION_SWEEP_NEXT=0; SWEEP_CLOSED_NEXT=99999999999
  sweep_dead_sessions; rc=$?
  [ "$rc" -eq 0 ] && grep -q "^close 1 " "$TMP/writes" && ok "runner sweep closed #1, returned 0" || fail "runner sweep rc=$rc writes=$(cat "$TMP/writes")"
  [ "${SWEEP_CLOSED_NEXT:-1}" = "0" ] && ok "closed-card sweep cadence reset (Done next tick)" || fail "SWEEP_CLOSED_NEXT=$SWEEP_CLOSED_NEXT"
  : > "$TMP/writes"
  sweep_dead_sessions; rc=$?
  [ "$rc" -ne 0 ] && [ ! -s "$TMP/writes" ] && ok "second call inside the cadence does nothing" || fail "cadence not honoured rc=$rc"
  grep -q 'sweep_dead_sessions' "$RUNNER" && awk '/sweep_dead_sessions \|\| true/{a=NR} /if sweep_closed_cards;/{b=NR} END{exit !(a&&b&&a<b)}' "$RUNNER" \
    && ok "tick calls sweep_dead_sessions before sweep_closed_cards" || fail "tick wiring missing/ordered wrong"
fi
[ "$FAILS" -eq 0 ] && echo "ALL PASS" || echo "$FAILS FAILED"
exit "$FAILS"
