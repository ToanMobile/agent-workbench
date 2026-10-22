#!/usr/bin/env bash
# Test hồi quy #189 (22/10, runner.log 11:07-11:23): Ready=0 Building=1 b_workers=1/10 trong khi Backlog có 15 thẻ — runner không
# có đường nào đọc cột Backlog nên lane build nhàn rỗi hàng giờ. Luật của pull_backlog_cards (gọi mỗi expensive tick sau count_board):
#  A  Ready=0, Backlog 3 thẻ đủ Problem/Fix/AC + 1 thẻ needs-you -> kéo đúng 3 thẻ lên Ready, không kéo needs-you; comment [orchestrator].
#  B  Thẻ thiếu AC (hoặc Problem/Fix) không bị kéo; comment nêu lý do đúng một lần cho cùng nội dung (tick sau im lặng).
#  C  Thẻ CLOSED trong Backlog -> Done, không kéo lên Ready.
#  D  Không kéo vượt số worker rảnh: BUILD_WORKERS - BUILD_COUNT - READY; tải >= build_load_max chỉ cho kéo 1 thẻ khi lane rỗng hẳn.
#  E  Cờ tắt (SB_BACKLOG_PULL=0 hoặc backlog_pull:false trong config) -> không đọc, không kéo.
#  F  Thứ tự: thẻ `bug` trước, còn lại theo thứ tự bảng; thẻ wontfix / có assignee người bị bỏ qua.
#  G  #233: thẻ đủ mục nhưng nhắc repo của board khác, hoặc AC toàn việc của người ("prompt thật") -> giữ Backlog, comment một lần.
#  W  Dây nối: vòng chính gọi pull_backlog_cards sau count_board rồi đọc lại bảng.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-backlog-pull.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

unset SB_GITHUB_READ_STRICT SB_BACKLOG_PULL SB_BUILD_LOAD_FILE
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
BOT_LOGIN="sb-bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
fetch_project_items() { :; }
issue_is_open() { ! grep -qx "$1" "$TMP/closed" 2>/dev/null; }
backlog_issue_body() { cat "$TMP/body-$1"; }   # móc test cho lần đọc REST body của một thẻ

GOOD=$'## Problem\nlỗi\n\n## Fix\nsửa\n\n## Acceptance Criteria\n- [ ] test đỏ rồi xanh\n\n## Risk\nthấp\n'
NOAC=$'## Problem\nlỗi\n\n## Fix\nsửa\n\n## Risk\nthấp\n'
NOFIX=$'## Problem\nlỗi\n\n## Acceptance Criteria\n- [ ] x\n'

# card <n> <status> <labels-json> [assignees-json] -> một phần tử items; add_body <n> <body>
CARDS=""
card() { CARDS="${CARDS:+$CARDS,}{\"id\":\"PVTI_$1\",\"status\":\"$2\",\"labels\":$3,\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":${4:-[]}}}"; }
add_body() { printf '%s' "$2" > "$TMP/body-$1"; }
board() { PROJECT_ITEMS_JSON="{\"items\":[$CARDS]}"; }
reset_case() {
  : > "$TMP/writes"; : > "$TMP/log"; : > "$TMP/closed"
  rm -rf "$INFLIGHT_DIR"/* "$TMP"/body-* "$TMP/load"
  CARDS=""; BUILD_WORKERS=10; BUILD_COUNT=0; READY=0; BUILD_LOAD_MAX=60
  unset SB_BACKLOG_PULL; CONFIG_PATH=/dev/null
  SB_BUILD_LOAD_FILE="$TMP/load"; echo 1.0 > "$TMP/load"
}
moved_to_ready() { grep -c "^move .* Ready$" "$TMP/writes"; }

cd "$TMP" || exit 1

# ── A: 3 thẻ đủ AC + 1 needs-you, Ready=0 -> đúng 3 thẻ lên Ready.
reset_case
card 301 Backlog '["bug"]'; card 302 Backlog '[]'; card 303 Backlog '[{"name":"feature"}]'; card 304 Backlog '["needs-you"]'
for n in 301 302 303 304; do add_body $n "$GOOD"; done
board
pull_backlog_cards; rc=$?
if [ "$rc" -eq 0 ] && [ "$(moved_to_ready)" = 3 ] && ! grep -q "PVTI_304" "$TMP/writes" \
   && [ "$(grep -c '^gh issue comment .*\[orchestrator\]' "$TMP/writes")" = 3 ]; then
  ok "A: 3 đủ AC lên Ready, needs-you #304 không bị kéo, 3 comment [orchestrator]"
else
  fail "A: rc=$rc writes: $(tr '\n' ';' < "$TMP/writes")"
fi

# ── B: thiếu AC / Fix không bị kéo, comment lý do một lần.
reset_case
card 311 Backlog '[]'; card 312 Backlog '[]'
add_body 311 "$NOAC"; add_body 312 "$NOFIX"
board
pull_backlog_cards; rc=$?
c1=$(grep -c '^gh issue comment' "$TMP/writes")
pull_backlog_cards >/dev/null
c2=$(grep -c '^gh issue comment' "$TMP/writes")
if [ "$rc" -ne 0 ] && [ "$(moved_to_ready)" = 0 ] && [ "$c1" = 2 ] && [ "$c2" = 2 ] \
   && grep -q "Acceptance Criteria" "$TMP/writes" && grep -q "Fix" "$TMP/writes"; then
  ok "B: thẻ thiếu AC/Fix không kéo, comment lý do 1 lần mỗi thẻ (tick 2 im lặng)"
else
  fail "B: rc=$rc moved=$(moved_to_ready) c1=$c1 c2=$c2 writes: $(tr '\n' ';' < "$TMP/writes")"
fi

# ── C: thẻ CLOSED -> Done, không lên Ready.
reset_case
card 321 Backlog '[]'; card 322 Backlog '[]'
add_body 321 "$GOOD"; add_body 322 "$GOOD"; echo 321 > "$TMP/closed"
board
pull_backlog_cards; rc=$?
if [ "$rc" -eq 0 ] && grep -qx "move PVTI_321 Done" "$TMP/writes" && ! grep -qx "move PVTI_321 Ready" "$TMP/writes" \
   && grep -qx "move PVTI_322 Ready" "$TMP/writes"; then
  ok "C: #321 CLOSED -> Done (không dispatch), #322 lên Ready"
else
  fail "C: rc=$rc writes: $(tr '\n' ';' < "$TMP/writes")"
fi

# ── D1: chỉ kéo bằng số worker rảnh (10 - 3 đang chạy - 2 Ready = 5).
reset_case
for n in 331 332 333 334 335 336 337 338; do card $n Backlog '[]'; add_body $n "$GOOD"; done
board; BUILD_COUNT=3; READY=2
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 5 ]; then ok "D1: kéo đúng 5 = 10 worker - 3 chạy - 2 Ready"; else fail "D1: moved=$(moved_to_ready)"; fi
# D2: tải trên ngưỡng, đã có worker -> không kéo thêm.
reset_case
for n in 341 342 343; do card $n Backlog '[]'; add_body $n "$GOOD"; done
board; BUILD_COUNT=1; READY=0; echo 99 > "$TMP/load"
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 0 ]; then ok "D2: tải 99 >= 60 và lane đã bận -> không kéo"; else fail "D2: moved=$(moved_to_ready)"; fi
# D3: tải trên ngưỡng, lane rỗng hẳn -> chỉ 1 thẻ.
reset_case
for n in 351 352 353; do card $n Backlog '[]'; add_body $n "$GOOD"; done
board; echo 99 > "$TMP/load"
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 1 ]; then ok "D3: tải cao, lane rỗng -> kéo đúng 1 thẻ"; else fail "D3: moved=$(moved_to_ready)"; fi
# D4: tải đọc không được -> như tải cao.
reset_case
for n in 361 362; do card $n Backlog '[]'; add_body $n "$GOOD"; done
board; BUILD_COUNT=1; : > "$TMP/load"
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 0 ]; then ok "D4: tải không đọc được, lane bận -> không kéo"; else fail "D4: moved=$(moved_to_ready)"; fi

# ── E: cờ tắt.
reset_case
card 371 Backlog '[]'; add_body 371 "$GOOD"; board
SB_BACKLOG_PULL=0 pull_backlog_cards; rc=$?
printf '{"backlog_pull": false}' > "$TMP/cfg.json"
CONFIG_PATH="$TMP/cfg.json" pull_backlog_cards; rc2=$?
if [ "$rc" -ne 0 ] && [ "$rc2" -ne 0 ] && [ ! -s "$TMP/writes" ]; then ok "E: SB_BACKLOG_PULL=0 và backlog_pull:false đều tắt"; else fail "E: rc=$rc rc2=$rc2 writes: $(tr '\n' ';' < "$TMP/writes")"; fi

# ── F: bug trước; wontfix và thẻ có assignee người bỏ qua.
reset_case
card 381 Backlog '[]'; card 382 Backlog '["bug"]'; card 383 Backlog '["wontfix"]'; card 384 Backlog '[]' '["alice"]'
for n in 381 382 383 384; do add_body $n "$GOOD"; done
board; BUILD_COUNT=0; READY=0; BUILD_WORKERS=1
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 1 ] && grep -qx "move PVTI_382 Ready" "$TMP/writes"; then
  ok "F: trần 1, thẻ bug #382 đi trước #381; wontfix #383 và thẻ của alice #384 bị bỏ"
else
  fail "F: writes: $(tr '\n' ';' < "$TMP/writes")"
fi
reset_case
card 391 Backlog '["wontfix"]'; card 392 Backlog '[]' '["alice"]'; add_body 391 "$GOOD"; add_body 392 "$GOOD"; board
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 0 ]; then ok "F2: chỉ còn wontfix + thẻ có assignee -> không kéo"; else fail "F2: moved=$(moved_to_ready)"; fi

# ── G: #233 thẻ đủ Problem/Fix/AC nhưng nhắc repo board khác, hoặc AC toàn việc của người -> giữ Backlog, comment một lần.
reset_case
FOREIGN=$'## Problem\nlỗi ở ToanMobile/GeelyEx2\n\n## Fix\nsửa\n\n## Acceptance Criteria\n- [ ] test đỏ rồi xanh\n'
HUMANAC=$'## Problem\nlỗi\n\n## Fix\nsửa\n\n## Acceptance Criteria\n- [ ] Chạy ≥100 prompt thật\n'
card 401 Backlog '[]'; card 402 Backlog '[]'; card 403 Backlog '[]'
add_body 401 "$FOREIGN"; add_body 402 "$HUMANAC"; add_body 403 "$GOOD"
board
pull_backlog_cards >/dev/null
g1=$(grep -c '^gh issue comment' "$TMP/writes"); gm=$(moved_to_ready)
pull_backlog_cards >/dev/null
g2=$(grep -c '^gh issue comment' "$TMP/writes")
if [ "$gm" = 1 ] && grep -qx "move PVTI_403 Ready" "$TMP/writes" && ! grep -q "PVTI_401 Ready\|PVTI_402 Ready" "$TMP/writes" \
   && grep -q "GeelyEx2" "$TMP/writes" && [ "$(grep -c '^gh issue comment .*⏸' "$TMP/writes")" = 2 ] \
   && [ "$(grep -c "GeelyEx2" "$TMP/writes")" = 1 ]; then
  ok "G: #401 (repo khác) và #402 (AC cần người) giữ Backlog kèm lý do, tick 2 im lặng; #403 lên Ready"
else
  fail "G: moved=$gm g1=$g1 g2=$g2 writes: $(tr '\n' ';' < "$TMP/writes")"
fi

# ── W: dây nối trong vòng chính.
wire=$(grep -n 'pull_backlog_cards' "$RUNNER" | tail -1 | cut -d: -f1)
cnt=$(grep -n '^  count_board$' "$RUNNER" | tail -1 | cut -d: -f1)
if [ -n "$wire" ] && [ -n "$cnt" ] && [ "$wire" -gt "$cnt" ] && sed -n "${wire},$((wire + 2))p" "$RUNNER" | grep -q 'fetch_project_items'; then
  ok "W: vòng chính gọi pull_backlog_cards sau count_board rồi đọc lại bảng"
else
  fail "W: pull_backlog_cards chưa được nối vào vòng chính (wire=${wire:-none} count_board=${cnt:-none})"
fi

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
