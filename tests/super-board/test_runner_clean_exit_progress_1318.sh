#!/usr/bin/env bash
# Test hồi quy #1318 (19/11, 6 repo): worker build/QA thoát exit 0 sau khi đã làm xong việc nhưng chưa chạy `move`,
# runner tính là "died mid-run" / "exited N times" rồi Blocked ❓ chờ người (42 + 19 lần trong 14 ngày).
# Luật:
#  - Build exit 0 (result success) + comment `[builder]` mới có dòng `Next: QA`, thẻ còn Building -> thẻ sang QA, không comment [blocker],
#    sổ reclaims không tăng.
#  - QA exit 0 + `[qa] [report] ❌` mới, thẻ còn QA -> Ready kèm loop:rebuild-N+1; `✅` -> Review.
#  - Thoát không đổi gì và không comment mới -> đường cũ (Blocked ❓ sau SB_NOOP_MAX), không nới.
#  - Build exit 0 không có comment [builder] mới -> đường reclaim cũ (về Ready), không sang QA.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-clean-exit-1318.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

unset SB_GITHUB_READ_STRICT SB_NOOP_MAX SB_NOOP_WINDOW_S SB_RECLAIM_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/wl"; mkdir -p "$WORKER_LOG_DIR"
BOT_LOGIN="sb-bot"
REBUILD_CAP=2
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
note_worker_limit() { :; }
note_early_death() { :; }
fetch_project_items() { :; }
issue_is_open() { return 0; }
COMMENTS_NOW=4
LAST_COMMENT=""
BUILDER_NEW=1
issue_comment_count() { printf '%s' "$COMMENTS_NOW"; }
issue_last_comment() { printf '%s\n' "$LAST_COMMENT"; }
builder_reported_since() { [ "$BUILDER_NEW" = 1 ]; }

sleep 0 & DEAD=$!; wait "$DEAD"

set_card() {   # set_card <number> <status> [labels-json]
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"$2\",\"labels\":${3:-[\"bug\"]},\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[\"sb-bot\"]}}]}"
}
clean_log() {   # clean_log <lane> <issue>: log của worker đã thoát sạch (exit 0 + result success)
  printf '=== dispatch #%s at 2026-11-19T10:00:00Z ===\n{"type":"result","subtype":"success","is_error":false,"result":"done"}\nworker_exit: exit=0 signal=none elapsed=205s\n' "$2" \
    > "$WORKER_LOG_DIR/worker-$1-$2.log"
}
lock() {   # lock <issue> <lane> <from-col> <comments0>
  printf 'PID=%s\nLANE=%s\nSTARTED=2026-11-19T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=%s\nCOMMENTS0=%s\n' \
    "$DEAD" "$2" "$WORKER_LOG_DIR/worker-$2-$1.log" "$3" "$4" > "$INFLIGHT_DIR/$1"
}
reset_case() { : > "$TMP/writes"; : > "$TMP/log"; rm -rf "${INFLIGHT_DIR:?}"/*; NOOP_CHECK=""; NOOP_MOVED=0; RECLAIM_BUILDING=""; RECLAIM_MOVED=0
  COMMENTS_NOW=4; LAST_COMMENT=""; BUILDER_NEW=1; }
build_cycle() { reap_finished_locks; reclaim_dead_builds; }
qa_cycle() { reap_finished_locks; block_noop_workers; }

cd "$TMP" || exit 1

# ── A (AC1): build exit 0, thẻ Building, `[builder] … Next: QA` mới -> sang QA, không [blocker], không tăng reclaim.
reset_case
clean_log build 200; set_card 200 Building; lock 200 build Building 3
LAST_COMMENT=$'[builder] [report] ✅ built\nDid: fix\nNext: QA rồi Review chạy lại'
build_cycle
if grep -qx "move PVTI_200 QA" "$TMP/writes" && ! grep -q "blocker" "$TMP/writes" && ! grep -qx "move PVTI_200 Ready" "$TMP/writes" \
   && [ ! -s "$INFLIGHT_DIR/reclaims/200" ] && [ "${RECLAIM_MOVED:-0}" = 1 ]; then
  ok "A: clean build exit + [builder] Next: QA -> #200 Building -> QA, no blocker, reclaim ledger untouched"
else
  fail "A: expected move to QA (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── A2: lặp 3 lần (vượt SB_RECLAIM_MAX=2) vẫn sang QA, không bao giờ Blocked.
reset_case
for i in 1 2 3; do
  clean_log build 201; set_card 201 Building; lock 201 build Building 3
  LAST_COMMENT=$'[builder] [report] ✅ built\nNext: QA'
  build_cycle
done
if [ "$(grep -cx 'move PVTI_201 QA' "$TMP/writes")" = 3 ] && ! grep -q "Blocked" "$TMP/writes"; then
  ok "A2: three clean build exits in a row never reach the reclaim cap"
else
  fail "A2: reclaim cap hit on clean exits (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── B: build exit 0 nhưng không có comment [builder] mới -> đường reclaim cũ (Ready), không sang QA.
reset_case
clean_log build 202; set_card 202 Building; lock 202 build Building 3; BUILDER_NEW=0
LAST_COMMENT="something else"
build_cycle
if grep -qx "move PVTI_202 Ready" "$TMP/writes" && ! grep -qx "move PVTI_202 QA" "$TMP/writes"; then
  ok "B: clean build exit without a new [builder] comment keeps the old reclaim path (Ready)"
else
  fail "B: no-comment build exit misrouted (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── B2: comment [builder] mới nhưng Next không nhắc QA -> đường cũ.
reset_case
clean_log build 203; set_card 203 Building; lock 203 build Building 3
LAST_COMMENT=$'[builder] [report] ⚠️ stuck\nNext: người xem'
build_cycle
if grep -qx "move PVTI_203 Ready" "$TMP/writes" && ! grep -qx "move PVTI_203 QA" "$TMP/writes"; then
  ok "B2: [builder] comment without Next: QA keeps the old reclaim path"
else
  fail "B2: misrouted (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── C (AC2): QA exit 0 + `[qa] [report] ❌` mới, thẻ còn QA -> Ready + loop:rebuild-1.
reset_case
clean_log qa 210; set_card 210 QA; COMMENTS_NOW=4; lock 210 qa QA 3
LAST_COMMENT=$'[qa] [report] ❌ AC2 fail @ abc1234\nDid: ran tests'
qa_cycle
if grep -qx "move PVTI_210 Ready" "$TMP/writes" && grep -q "gh issue edit 210 --add-label loop:rebuild-1" "$TMP/writes" \
   && ! grep -q "blocker" "$TMP/writes" && [ "${NOOP_MOVED:-0}" = 1 ]; then
  ok "C: clean QA exit + new [qa] [report] ❌ -> #210 QA -> Ready with loop:rebuild-1"
else
  fail "C: expected Ready + loop:rebuild-1 (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── C2: đã có loop:rebuild-1 -> N+1 = 2 và nhãn cũ bị gỡ.
reset_case
clean_log qa 211; set_card 211 QA '["bug","loop:rebuild-1"]'; lock 211 qa QA 3
LAST_COMMENT=$'[qa] [report] ❌ AC1 fail'
qa_cycle
if grep -qx "move PVTI_211 Ready" "$TMP/writes" && grep -q "gh issue edit 211 --add-label loop:rebuild-2 --remove-label loop:rebuild-1" "$TMP/writes"; then
  ok "C2: loop:rebuild-1 -> loop:rebuild-2 (old label removed)"
else
  fail "C2: counter not advanced (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── C3: đã chạm rebuild_cap -> không tự route ❌ (đường cũ giữ nguyên).
reset_case
clean_log qa 212; set_card 212 QA '["bug","loop:rebuild-2"]'; lock 212 qa QA 3
LAST_COMMENT=$'[qa] [report] ❌ AC1 fail'
qa_cycle
if ! grep -qx "move PVTI_212 Ready" "$TMP/writes"; then
  ok "C3: card at rebuild_cap is not auto-routed to Ready"
else
  fail "C3: cap bypassed (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── D: QA exit 0 + `[qa] [report] ✅` -> Review.
reset_case
clean_log qa 213; set_card 213 QA; lock 213 qa QA 3
LAST_COMMENT=$'[qa] [report] ✅ pass @ abc1234'
qa_cycle
if grep -qx "move PVTI_213 Review" "$TMP/writes"; then
  ok "D: clean QA exit + [qa] [report] ✅ -> Review"
else
  fail "D: pass report not routed (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── E (AC3): QA thoát không comment mới -> vẫn Blocked ❓ ở lần thứ hai như cũ.
reset_case
clean_log qa 214; set_card 214 QA; COMMENTS_NOW=3
lock 214 qa QA 3; qa_cycle
lock 214 qa QA 3; qa_cycle
if grep -qx "move PVTI_214 Blocked" "$TMP/writes" && grep -q "Reason tag:  ❓" "$TMP/writes" && ! grep -qx "move PVTI_214 Review" "$TMP/writes"; then
  ok "E: QA exits with no new comment still end in Blocked ❓ (not loosened)"
else
  fail "E: no-op path changed (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── F: comment mới của QA không phải [report] ✅/❌ (vd [blocker]) -> không route, đường cũ (tiến triển, không Blocked).
reset_case
clean_log qa 215; set_card 215 QA; lock 215 qa QA 3
LAST_COMMENT=$'[qa] [blocker] ⛔ cannot push'
qa_cycle
if ! grep -q "^move " "$TMP/writes"; then
  ok "F: a [qa] [blocker] comment is not turned into a verdict"
else
  fail "F: blocker misrouted (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS test_runner_clean_exit_progress_1318"; exit 0; }
echo "FAIL test_runner_clean_exit_progress_1318 ($FAILS)"; exit 1
