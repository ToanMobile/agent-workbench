#!/usr/bin/env bash
# Test hồi quy #189 (22/10, runner.log 11:07-11:23): Ready=0 Building=1 b_workers=1/10 trong khi Backlog có 15 thẻ — runner không
# có đường nào đọc cột Backlog nên lane build nhàn rỗi hàng giờ. Luật của pull_backlog_cards (gọi mỗi expensive tick sau count_board):
#  A  Ready=0, Backlog 3 thẻ đủ Problem/Fix/AC + 1 thẻ needs-you -> kéo đúng 3 thẻ lên Ready, không kéo needs-you; comment [orchestrator].
#  B  Thẻ thiếu AC (hoặc Problem/Fix) không bị kéo; comment nêu lý do đúng một lần cho cùng nội dung (tick sau im lặng).
#  C  Thẻ CLOSED trong Backlog -> Done, không kéo lên Ready.
#  D  Không kéo vượt số worker rảnh: BUILD_WORKERS - BUILD_COUNT - READY; tải >= build_load_max chỉ cho kéo 1 thẻ khi lane rỗng hẳn.
#  E  Cờ tắt (SB_BACKLOG_PULL=0 hoặc backlog_pull:false trong config) -> không đọc, không kéo.
#  F  Thứ tự: thẻ `bug` trước, còn lại theo thứ tự bảng; thẻ wontfix / có assignee người bị bỏ qua.
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
backlog_issue_comments() { cat "$TMP/comments-$1" 2>/dev/null || echo '[]'; }   # móc test cho lần đọc REST comment (mảng [{id,body}])
backlog_mark_needs_you() { echo "needs-you $1" >> "$TMP/writes"; }

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
  rm -rf "$INFLIGHT_DIR"/* "$TMP"/body-* "$TMP"/comments-* "$TMP/load"
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

# ── G/H/I/J (#232): thẻ đã bị đỗ / bị builder chặn không bị kéo lại; thẻ bị kéo rồi chặn 2 lần dừng hẳn + needs-you.
BLOCK=$'[builder] [blocker] 🛑 blocked · 📦 wrong-place\nCard: #1\nReason tag:  📦\nblocked-by:  -'
PULL=$'[orchestrator] [report] ⬆️ Backlog → Ready · build lane idle\nNext: builder'
PARK=$'[orchestrator] [report] đã đưa thẻ về Backlog vì sai board'

# G1: block comment 📦 mới nhất -> không kéo. G2: body bị sửa sau comment đó -> kéo.
reset_case
card 401 Backlog '[]'; add_body 401 "$GOOD"; board
printf '%s' "[{\"id\":7,\"body\":$(printf '%s' "$BLOCK" | jq -Rs .)}]" > "$TMP/comments-401"
pull_backlog_cards >/dev/null
g1=$(moved_to_ready)
add_body 401 "${GOOD}
## Ghi chú
đã sửa"
pull_backlog_cards >/dev/null
g2=$(moved_to_ready)
if [ "$g1" = 0 ] && [ "$g2" = 1 ]; then ok "G: block 📦 mới nhất -> không kéo; sửa body sau đó -> kéo"; else fail "G: trước sửa moved=$g1 sau sửa moved=$g2 (muốn 0 rồi 1)"; fi

# G3: comment của người mới hơn block -> kéo.
reset_case
card 402 Backlog '[]'; add_body 402 "$GOOD"; board
printf '%s' "[{\"id\":7,\"body\":$(printf '%s' "$BLOCK" | jq -Rs .)},{\"id\":8,\"body\":\"đã đúng board, kéo lại đi\"}]" > "$TMP/comments-402"
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 1 ]; then ok "G3: comment người mới hơn block -> kéo"; else fail "G3: moved=$(moved_to_ready)"; fi

# I: orchestrator 'về Backlog' chưa bị thay thế -> không kéo.
reset_case
card 403 Backlog '[]'; add_body 403 "$GOOD"; board
printf '%s' "[{\"id\":9,\"body\":$(printf '%s' "$PARK" | jq -Rs .)}]" > "$TMP/comments-403"
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 0 ]; then ok "I: comment orchestrator 'về Backlog' -> không kéo"; else fail "I: moved=$(moved_to_ready)"; fi

# H: kéo -> chặn -> kéo -> chặn (2 lần) -> không kéo dù body mới sửa, needs-you đúng một lần cho thẻ.
reset_case
card 404 Backlog '[]'; add_body 404 "$GOOD"; board
printf '%s' "[{\"id\":1,\"body\":$(printf '%s' "$PULL" | jq -Rs .)},{\"id\":2,\"body\":$(printf '%s' "$BLOCK" | jq -Rs .)},{\"id\":3,\"body\":$(printf '%s' "$PULL" | jq -Rs .)},{\"id\":4,\"body\":$(printf '%s' "$BLOCK" | jq -Rs .)}]" > "$TMP/comments-404"
pull_backlog_cards >/dev/null
add_body 404 "${GOOD}
## Ghi chú
sửa lần nữa"
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 0 ] && grep -q "^needs-you 404$" "$TMP/writes"; then ok "H: bị kéo rồi chặn 2 lần -> dừng kéo, needs-you"; else fail "H: moved=$(moved_to_ready) writes: $(tr '\n' ';' < "$TMP/writes")"; fi

# J: bị kéo rồi chặn đúng 1 lần, body đã sửa sau block -> vẫn kéo được (chưa tới 2 lần).
reset_case
card 405 Backlog '[]'; add_body 405 "$GOOD"; board
printf '%s' "[{\"id\":1,\"body\":$(printf '%s' "$PULL" | jq -Rs .)},{\"id\":2,\"body\":$(printf '%s' "$BLOCK" | jq -Rs .)},{\"id\":3,\"body\":\"đã sửa body\"}]" > "$TMP/comments-405"
pull_backlog_cards >/dev/null
if [ "$(moved_to_ready)" = 1 ] && ! grep -q "^needs-you" "$TMP/writes"; then ok "J: 1 lần chặn + comment người mới hơn -> kéo, không needs-you"; else fail "J: moved=$(moved_to_ready)"; fi

# ── W: dây nối trong vòng chính.
wire=$(grep -n 'pull_backlog_cards' "$RUNNER" | tail -1 | cut -d: -f1)
cnt=$(grep -n '^  count_board$' "$RUNNER" | tail -1 | cut -d: -f1)
if [ -n "$wire" ] && [ -n "$cnt" ] && [ "$wire" -gt "$cnt" ] && sed -n "${wire},$((wire + 2))p" "$RUNNER" | grep -qE 'fetch_project_items|tick_fetch'; then   # #256: vòng chính đọc qua tick_fetch
  ok "W: vòng chính gọi pull_backlog_cards sau count_board rồi đọc lại bảng"
else
  fail "W: pull_backlog_cards chưa được nối vào vòng chính (wire=${wire:-none} count_board=${cnt:-none})"
fi

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
