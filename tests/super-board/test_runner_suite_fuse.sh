#!/usr/bin/env bash
# Test (#363): cầu chì suite của runner — ≥2 thẻ Blocked cùng suite id (lấy từ comment [blocker] mới nhất có TIMEOUT/FAIL/HANG, mốc = createdAt
# của comment) trong SB_FUSE_WINDOW_H giờ thì giữ thẻ nhỏ nhất, các thẻ còn lại ghi `blocked-by: <keep>` (KHÔNG đóng, KHÔNG sang Done), và ngưng
# giao Builder tới khi mọi thẻ giữ rời Blocked. Đối chứng: một thẻ, hai suite khác nhau, ngoài cửa sổ giờ, nhắc suite ở comment pass/unblock.
# Chạy offline: runner source ở lib mode, gh / đọc card / chuyển cột là stub; trạng thái cầu chì ở INFLIGHT_DIR riêng trong $TMP.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="${SB_TEST_RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-suite-fuse.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo/docs/super-board"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf 'import os, sys\nsys.exit(int(os.environ.get("STUB_BB_RC") or 0)) if os.environ.get("STUB_BB_RC") else print("blocked-by: " + sys.argv[-1])\n' > "$TMP/bin/super-board-blocked-by.py"
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/bin/super-board-blocked-by.py"
export STUB_DIR="$TMP" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX DEVKIT_CAPACITY DEVKIT_CAPACITY_LOAD SB_CAPACITY SB_FUSE_WINDOW_H
export DEVKIT_CAPACITY_CORES=12
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{"repo":{"remote":"o/r"}}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
RUN_MANIFEST="$TMP/manifest"; : > "$RUN_MANIFEST"
REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" | tr '\n' ' ' >> "$TMP/writes"; echo >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
fuse_card_json() { cat "$TMP/card.$1" 2>/dev/null || echo '{"title":"t","comments":[]}'; }   # thẻ nào không có file: không comment
cd "$TMP/repo" || exit 1
git init -q . 2>/dev/null
BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""
BUILD_WORKERS=10; MAX_WORKERS=10
board() { # <số:cột[:nhãn]>... → PROJECT_ITEMS_JSON
  local out="" it n rest col lab
  for it in "$@"; do
    n="${it%%:*}"; rest="${it#*:}"; col="${rest%%:*}"; lab=""; [ "$rest" = "$col" ] || lab="\"${rest#*:}\""
    out="$out{\"id\":\"item$n\",\"status\":\"$col\",\"labels\":[$lab],\"content\":{\"number\":$n}},"
  done
  PROJECT_ITEMS_JSON="{\"items\":[${out%,}]}"
}
hours_ago() { python3 -c 'import time,sys;print(time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime(time.time()-float(sys.argv[1])*3600)))' "$1"; }
# card <n> <comment-json>... → file card.<n>; comment <body> <hours-ago>
comment() { jq -nc --arg b "$1" --arg t "$(hours_ago "${2:-0.1}")" '{body:$b,createdAt:$t}'; }
setcard() { local n="$1"; shift; printf '%s\n' "$@" | jq -sc '{title:"t",comments:.}' > "$TMP/card.$n"; }
blockedtext() { setcard "$1" "$(comment "[builder] [blocker] 🛑 blocked · 🛡 gate
Evidence: $2 TIMEOUT after 900s
blocked-by:  -" "${3:-0.1}")"; }
reset() { rm -f "$INFLIGHT_DIR"/fuse/* "$TMP"/card.*; FUSE_PAUSE_LOGGED=""; unset STUB_BB_RC; : > "$TMP/writes"; : > "$TMP/log"; }
free() { BUILD_FREE=0; build_slot_free; FREE_RC=$?; }


folded() { grep -Eq "gh issue comment $1 .*blocked-by: $2 *$" "$TMP/writes"; }   # thẻ $1 được ghi blocked-by: $2
never_closed() { ! grep -q "issue close" "$TMP/writes" && ! grep -q "^move " "$TMP/writes"; }

# ── 1. một thẻ Blocked vì REG-X: không gộp, Builder vẫn được giao
reset; board 10:Blocked 5:Ready; blockedtext 10 REG-DK-ALL-01
suite_fuse_tick; rc=$?
free
[ "$rc" -eq 1 ] && [ ! -f "$INFLIGHT_DIR/fuse/pause" ] && [ "$FREE_RC" -eq 0 ] && [ "$BUILD_FREE" = 1 ] \
  && ok "one Blocked card: nothing merged, Builder not paused" || fail "one card: rc=$rc free=$FREE_RC BUILD_FREE=$BUILD_FREE"

# ── 2. thẻ thứ hai Blocked cùng suite: giữ #10, #11 ghi blocked-by: 10 (không đóng, không Done), Builder bị ngưng
board 10:Blocked 11:Blocked 5:Ready; blockedtext 11 REG-DK-ALL-01
suite_fuse_tick; free
if folded 11 10 && never_closed && [ "$(cut -f1 "$INFLIGHT_DIR/fuse/pause")" = 10 ] \
   && [ "$FREE_RC" -ne 0 ] && [ "$BUILD_FREE" = 0 ]; then ok "two cards on one suite: #11 gets blocked-by: 10, nothing closed or moved to Done, Builder paused"
else fail "merge: free=$FREE_RC writes=$(tr '\n' '|' < "$TMP/writes") pause=$(cat "$INFLIGHT_DIR/fuse/pause" 2>/dev/null)"; fi

# ── 3. tick sau: không gộp lại (idempotent), vẫn ngưng
board 10:Blocked 11:Blocked 5:Ready; : > "$TMP/writes"
suite_fuse_tick; free
[ ! -s "$TMP/writes" ] && [ "$FREE_RC" -ne 0 ] && ok "next tick: no second comment, Builder still paused" || fail "next tick: writes=$(tr '\n' '|' < "$TMP/writes")"

# ── 4. mọi thẻ giữ rời Blocked: cờ gỡ, Builder chạy lại
board 10:Done 11:Blocked 5:Ready
free
[ "$FREE_RC" -eq 0 ] && [ "$BUILD_FREE" = 1 ] && [ ! -f "$INFLIGHT_DIR/fuse/pause" ] && ok "kept card handled: pause released, Builder dispatch resumes" \
  || fail "release: free=$FREE_RC BUILD_FREE=$BUILD_FREE pause=$(cat "$INFLIGHT_DIR/fuse/pause" 2>/dev/null)"

# ── 5. đối chứng: hai suite khác nhau: không gộp
reset; board 20:Blocked 21:Blocked 5:Ready; blockedtext 20 REG-AAA-01; blockedtext 21 REG-BBB-01
suite_fuse_tick; rc=$?; free
[ "$rc" -eq 1 ] && [ ! -s "$TMP/writes" ] && [ ! -f "$INFLIGHT_DIR/fuse/pause" ] && [ "$FREE_RC" -eq 0 ] \
  && ok "control: two different suites: no merge, no pause" || fail "different suites: writes=$(tr '\n' '|' < "$TMP/writes")"

# ── 6. mốc = createdAt của comment blocker, không phải lúc runner thấy: thẻ 30 bị Blocked 7 h trước (> 6 h) nên không gộp, dù sổ trống (lần đầu triển khai)
reset; board 30:Blocked 31:Blocked 5:Ready; blockedtext 30 REG-DK-ALL-01 7; blockedtext 31 REG-DK-ALL-01
suite_fuse_tick; free
[ ! -s "$TMP/writes" ] && [ "$FREE_RC" -eq 0 ] && ok "blocked time comes from the comment createdAt: a card blocked 7 h ago (window 6 h) is not merged on first sight" \
  || fail "outside window: writes=$(tr '\n' '|' < "$TMP/writes")"
SB_FUSE_WINDOW_H=8 suite_fuse_tick
folded 31 30 && ok "SB_FUSE_WINDOW_H=8 widens the window: merged" || fail "window env: writes=$(tr '\n' '|' < "$TMP/writes")"

# ── 7. thẻ vào Blocked sau cờ ngưng cùng suite: gộp vào thẻ đang giữ cờ dù số nhỏ hơn
reset; board 40:Blocked 39:Blocked 5:Ready; blockedtext 40 REG-DK-ALL-01; blockedtext 39 REG-DK-ALL-01
mkdir -p "$INFLIGHT_DIR/fuse"; printf '40\tREG-DK-ALL-01\t1\n' > "$INFLIGHT_DIR/fuse/pause"
suite_fuse_tick
folded 39 40 && [ "$(cut -f1 "$INFLIGHT_DIR/fuse/pause" | sort -u | tr '\n' ' ')" = "40 " ] \
  && ok "a later card on the same suite is folded into the card that holds the pause" || fail "late card: writes=$(tr '\n' '|' < "$TMP/writes")"

# ── 8. P1: thẻ chỉ NHẮC suite ở comment pass / unblock (không phải [blocker] kèm TIMEOUT) không bị gộp (#320 chỉ nhắc REG-DK-ALL-01)
reset; board 50:Blocked 51:Blocked 5:Ready; blockedtext 50 REG-DK-ALL-01
setcard 51 "$(comment "[builder] [blocker] 🛑 blocked · 🙋 needs a decision
Why blocked: unrelated
blocked-by:  -" 1)" "$(comment "[qa] [report] ✅ REG-DK-ALL-01 PASS after the unblock, no TIMEOUT now" 0.1)" \
  "$(comment "[orchestrator] [report] FAIL noted: see REG-DK-ALL-01" 0.1)"
suite_fuse_tick; free
[ ! -s "$TMP/writes" ] && [ "$FREE_RC" -eq 0 ] && ok "a card that only mentions the suite in a pass/unblock note is not merged" || fail "mention-only card: writes=$(tr '\n' '|' < "$TMP/writes")"
# … và blocker mới nhất không nêu suite thì lấy blocker cũ hơn có TIMEOUT: thẻ 52 có blocker cũ REG-DK-ALL-01 TIMEOUT
reset; board 50:Blocked 52:Blocked; blockedtext 50 REG-DK-ALL-01
setcard 52 "$(comment "[reviewer] [blocker] 🛑 blocked · 🛡
Evidence: REG-DK-ALL-01 HANG
blocked-by:  -" 2)" "$(comment "[builder] [blocker] 🛑 blocked · ❓ later
Why blocked: asks a person
blocked-by:  -" 0.1)"
suite_fuse_tick
folded 52 50 && ok "the newest [blocker] comment that pairs a suite with TIMEOUT/FAIL/HANG is the one used" || fail "older blocker: writes=$(tr '\n' '|' < "$TMP/writes")"

# ── 9. không bao giờ đóng thẻ: ba thẻ cùng suite
reset; board 60:Blocked 61:Blocked 62:Blocked; for n in 60 61 62; do blockedtext $n REG-DK-ALL-01; done
suite_fuse_tick
folded 61 60 && folded 62 60 && never_closed && ok "three duplicates: all get blocked-by: 60, none closed, none moved" || fail "dups: writes=$(tr '\n' '|' < "$TMP/writes")"

# ── 10. bỏ qua thẻ 🙋 needs-you và thẻ đã có blocked-by số
reset; board 70:Blocked 71:Blocked:needs-you 72:Blocked 73:Blocked; for n in 70 71 73; do blockedtext $n REG-DK-ALL-01; done
setcard 72 "$(comment "[builder] [blocker] 🛑 blocked
Evidence: REG-DK-ALL-01 TIMEOUT
blocked-by:  9" 0.1)"
suite_fuse_tick
folded 73 70 && ! grep -q "comment 71 " "$TMP/writes" && ! grep -q "comment 72 " "$TMP/writes" && ok "needs-you card and a card that already has a numeric blocked-by are left alone" \
  || fail "skip: writes=$(tr '\n' '|' < "$TMP/writes")"

# ── 11. hai nhóm suite trong một tick: cờ ngưng giữ CẢ HAI thẻ giữ; chỉ gỡ khi cả hai rời Blocked
reset; board 80:Blocked 81:Blocked 90:Blocked 91:Blocked 5:Ready
blockedtext 80 REG-AAA-01; blockedtext 81 REG-AAA-01; blockedtext 90 REG-BBB-01; blockedtext 91 REG-BBB-01
suite_fuse_tick
folded 81 80 && folded 91 90 && ok "two suite groups in one tick: each group folds its duplicate" || fail "two groups: writes=$(tr '\n' '|' < "$TMP/writes")"
board 80:Done 81:Blocked 90:Blocked 91:Blocked 5:Ready; free
[ "$FREE_RC" -ne 0 ] && ok "#80 left Blocked but #90 still holds the pause: Builder stays paused" || fail "pause released too early (free=$FREE_RC, pause=$(tr '\n' '|' < "$INFLIGHT_DIR/fuse/pause" 2>/dev/null))"
board 80:Done 81:Blocked 90:Done 91:Blocked 5:Ready; free
[ "$FREE_RC" -eq 0 ] && [ ! -f "$INFLIGHT_DIR/fuse/pause" ] && ok "both kept cards left Blocked: pause released" || fail "pause not released (free=$FREE_RC)"

# ── 12. thẻ có NHIỀU suite không bị gộp vào hai nhóm: 100 {AAA,BBB}, 101 {AAA}, 102 {BBB}
reset; board 100:Blocked 101:Blocked 102:Blocked
setcard 100 "$(comment "[builder] [blocker] 🛑 blocked
Evidence: REG-AAA-01 TIMEOUT and REG-BBB-01 FAIL
blocked-by:  -" 0.1)"
blockedtext 101 REG-AAA-01; blockedtext 102 REG-BBB-01
suite_fuse_tick
n100=$(grep -c "comment 100 " "$TMP/writes"); n101=$(grep -c "comment 101 " "$TMP/writes"); n102=$(grep -c "comment 102 " "$TMP/writes")
{ [ "$n100" -le 1 ] && [ "$n101" -le 1 ] && [ "$n102" -le 1 ]; } && folded 101 100 && ok "a card tagged with several suites is in one group only (writes: #100=$n100 #101=$n101 #102=$n102)" \
  || fail "multi-suite: writes=$(tr '\n' '|' < "$TMP/writes")"

# ── 13. board call hỏng: thẻ đã gộp không bị comment lại ở tick sau (sổ folded)
reset; board 110:Blocked 111:Blocked; blockedtext 110 REG-DK-ALL-01; blockedtext 111 REG-DK-ALL-01
gh_write_once() { echo "gh $*" | tr '\n' ' ' >> "$TMP/writes"; echo >> "$TMP/writes"; return 1; }
suite_fuse_tick; : > "$TMP/writes"; suite_fuse_tick; suite_fuse_tick
gh_write_once() { echo "gh $*" | tr '\n' ' ' >> "$TMP/writes"; echo >> "$TMP/writes"; }
[ ! -s "$TMP/writes" ] && ok "gh comment failed once: later ticks do nothing (folded is remembered)" || fail "re-commented after failure: $(tr '\n' '|' < "$TMP/writes")"
# helper không đọc được trạng thái blocker (exit 79): không gộp, không ghi sổ, tick sau thử lại
reset; board 120:Blocked 121:Blocked; blockedtext 120 REG-DK-ALL-01; blockedtext 121 REG-DK-ALL-01
STUB_BB_RC=79 suite_fuse_tick
[ ! -s "$TMP/writes" ] && ok "blocker state unreadable (79): nothing written this tick" || fail "wrote on 79: $(tr '\n' '|' < "$TMP/writes")"
suite_fuse_tick; folded 121 120 && ok "…and the next tick retries and folds" || fail "no retry: $(tr '\n' '|' < "$TMP/writes")"

# ── 14. fuse_paused: PROJECT_ITEMS_JSON rỗng = giữ ngưng (không gỡ cờ)
reset; board 130:Blocked; mkdir -p "$INFLIGHT_DIR/fuse"; printf '130\tREG-X\t1\n' > "$INFLIGHT_DIR/fuse/pause"
SAVE="$PROJECT_ITEMS_JSON"; PROJECT_ITEMS_JSON=""; fuse_paused; rc=$?; PROJECT_ITEMS_JSON="not json"; fuse_paused; rc2=$?; PROJECT_ITEMS_JSON="$SAVE"
{ [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -f "$INFLIGHT_DIR/fuse/pause" ]; } && ok "empty/unreadable board: stays paused and keeps the flag" || fail "empty board: rc=$rc rc2=$rc2 flag=$(ls "$INFLIGHT_DIR/fuse")"

# ── 15. log 'fuse paused' chỉ khi đổi trạng thái, không mỗi tick
reset; board 140:Blocked 5:Ready; mkdir -p "$INFLIGHT_DIR/fuse"; printf '140\tREG-X\t1\n' > "$INFLIGHT_DIR/fuse/pause"
free; free; free
n=$(grep -c "Builder dispatch paused" "$TMP/log")
[ "$n" -eq 1 ] && ok "three paused ticks log the pause once" || fail "pause line logged $n times"
board 140:Done 5:Ready; free; board 141:Blocked 5:Ready; printf '141\tREG-X\t1\n' > "$INFLIGHT_DIR/fuse/pause"; free
n=$(grep -c "Builder dispatch paused" "$TMP/log")
[ "$n" -eq 2 ] && ok "after release, a new pause logs again" || fail "pause lines after re-pause: $n"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
