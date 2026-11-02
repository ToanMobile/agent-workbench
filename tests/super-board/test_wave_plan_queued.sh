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
# R1 (review #513): ensure lỗi → không ai rút hàng, nên thẻ đã vào hàng PHẢI được wave chọn lại (không ẩn); ensure ổn → vẫn ẩn.
printf '#!/bin/sh\nexit %s\n' 1 > "$TMP/ensure-fail.sh"; printf '#!/bin/sh\nexit 0\n' > "$TMP/ensure-ok.sh"; chmod +x "$TMP"/ensure-*.sh
plan_ensure() { cfg workflow true; ( cd "$ROOT" && SB_QUEUE_SCHEDULE_BIN="$TMP/$1" SB_GITHUB_HALT_FILE="$TMP/halt.json" bash "$PLAN" --config "$TMP/cfg.json" \
    --items "$TMP/items.json" --deps "$TMP/deps.json" --queued "$TMP/queued.json" 2>"$TMP/err" | jq -c '[.cards[].number] | sort' ); }
[ "$(plan_ensure ensure-fail.sh)" = "[5,6,7]" ] && ok "ensure fails: queued card #5 stays plannable (no drainer)" || fail "ensure fail: $(plan_ensure ensure-fail.sh)"
[ "$(plan_ensure ensure-ok.sh)" = "[6,7]" ] && ok "ensure ok: queued card #5 stays hidden" || fail "ensure ok: $(plan_ensure ensure-ok.sh)"
# R3 (review #513): root_installable (không SB_LAUNCH_AGENTS_DIR) từ chối thư mục tạm: install exit 1 + không có plist; ensure im lặng exit 0.
mkdir -p "$TMP/repo/.claude/bin" "$TMP/repo/.claude/super-board/configs" "$TMP/home" "$TMP/stub"
cp "$ROOT/.claude/bin/super-board-queue-schedule.sh" "$TMP/repo/.claude/bin/"; echo '{}' > "$TMP/repo/.claude/super-board/configs/t.json"
printf '#!/bin/sh\nexit 0\n' > "$TMP/stub/launchctl"; chmod +x "$TMP/stub/launchctl"
case "$TMP/" in /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*)
  ( env -u SB_LAUNCH_AGENTS_DIR HOME="$TMP/home" PATH="$TMP/stub:$PATH" bash "$TMP/repo/.claude/bin/super-board-queue-schedule.sh" install t >"$TMP/ins.out" 2>&1 ); rc=$?
  [ "$rc" = 1 ] && grep -q 'temporary directory' "$TMP/ins.out" && [ -z "$(find "$TMP/home" -name '*.plist')" ] && ok "install refuses a temporary root (exit 1, no plist)" || fail "refuse: rc=$rc $(cat "$TMP/ins.out")" ;;
esac
# R4 (review #513): ensure thoát 0 mà không có drainer (thư mục tạm / AUTOINSTALL=0 không nạp) làm wave ẩn thẻ merge-queue mãi mãi: không có agent nạp thì ensure PHẢI exit != 0.
case "$TMP/" in /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*)
  ( env -u SB_LAUNCH_AGENTS_DIR HOME="$TMP/home" PATH="$TMP/stub:$PATH" bash "$TMP/repo/.claude/bin/super-board-queue-schedule.sh" ensure t >"$TMP/ens.out" 2>&1 ); rc=$?
  [ "$rc" != 0 ] && [ -z "$(find "$TMP/home" -name '*.plist')" ] && ok "ensure on a temporary root exits non-zero (no drainer)" || fail "ensure tmp root: rc=$rc $(cat "$TMP/ens.out")" ;;
esac
printf '#!/bin/sh\n[ "$1" = print ] && exit %s\nexit 0\n' 1 > "$TMP/stub/launchctl"
( SB_LAUNCH_AGENTS_DIR="$TMP/agents" SB_QUEUE_SCHEDULE_AUTOINSTALL=0 HOME="$TMP/home" PATH="$TMP/stub:$PATH" bash "$TMP/repo/.claude/bin/super-board-queue-schedule.sh" ensure t >"$TMP/ens.out" 2>&1 ); rc=$?
[ "$rc" != 0 ] && ok "AUTOINSTALL=0 and nothing loaded: ensure exits non-zero" || fail "autoinstall=0 unloaded: rc=$rc"
printf '#!/bin/sh\nexit 0\n' > "$TMP/stub/launchctl"
( SB_LAUNCH_AGENTS_DIR="$TMP/agents" SB_QUEUE_SCHEDULE_AUTOINSTALL=0 HOME="$TMP/home" PATH="$TMP/stub:$PATH" bash "$TMP/repo/.claude/bin/super-board-queue-schedule.sh" ensure t >"$TMP/ens.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "AUTOINSTALL=0 and the agent is loaded: ensure exits 0" || fail "autoinstall=0 loaded: rc=$rc"
[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
