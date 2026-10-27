#!/usr/bin/env bash
# #453 (Q-schedule): backend workflow với merge_queue.enabled — thẻ Review có PR đã vào hàng (nhãn merge-queue) chờ lịch super-board-queue-
# schedule.sh gom; wave không được chọn nó (nếu không mỗi wave lại phóng một reviewer cho thẻ đã duyệt). Queue tắt: wave chọn như cũ.
# Chạy offline (--items/--deps/--queued). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLAN="${SB_TEST_BIN:-$ROOT/.claude/bin}/super-board-wave-plan.sh"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-wpq.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/items.json" <<'J'
{"items":[
 {"id":"I5","status":"Review","labels":["feature"],"content":{"type":"Issue","number":5,"title":"queued","assignees":[]}},
 {"id":"I6","status":"Review","labels":["feature"],"content":{"type":"Issue","number":6,"title":"not queued","assignees":[]}},
 {"id":"I7","status":"QA","labels":["feature"],"content":{"type":"Issue","number":7,"title":"in qa","assignees":[]}}]}
J
echo '{}' > "$TMP/deps.json"
echo '[{"headRefName":"issue-5-add-thing"}]' > "$TMP/queued.json"
cfg() { printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"},"worker_backend":"%s","verify_commands":["true"],"merge_queue":{"enabled":%s}}' "$1" "$2" > "$TMP/cfg.json"; }
plan() {   # plan <backend> <enabled> [env SB_MERGE_QUEUE]
  cfg "$1" "$2"
  ( cd "$ROOT" && SB_MERGE_QUEUE="${3:-}" SB_QUEUE_SCHEDULE_AUTOINSTALL=0 SB_GITHUB_HALT_FILE="$TMP/halt.json" bash "$PLAN" --config "$TMP/cfg.json" \
      --items "$TMP/items.json" --deps "$TMP/deps.json" --queued "$TMP/queued.json" 2>"$TMP/err" | jq -c '[.cards[].number] | sort' )
}
[ "$(plan workflow true)" = "[6,7]" ] && ok "workflow + queue on: the queued Review card #5 is not planned" || fail "workflow on: $(plan workflow true) $(head -c 200 "$TMP/err")"
[ "$(plan workflow false)" = "[5,6,7]" ] && ok "workflow + queue off: every Review card is planned" || fail "workflow off: $(plan workflow false)"
[ "$(plan workflow false 1)" = "[6,7]" ] && ok "SB_MERGE_QUEUE=1 turns the filter on over the config" || fail "env on: $(plan workflow false 1)"
[ "$(plan workflow true 0)" = "[5,6,7]" ] && ok "SB_MERGE_QUEUE=0 turns the filter off over the config" || fail "env off: $(plan workflow true 0)"
[ "$(plan codex true)" = "[5,6,7]" ] && ok "backend codex: queue off, no filter" || fail "codex: $(plan codex true)"
[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
