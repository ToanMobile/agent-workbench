#!/usr/bin/env bash
# Test hồi quy #253 (22/10, runner.log): 22/83 lượt build hôm đó kết thúc chặn hoặc no-op ≤5 phút.
# Luật ở đây:
#  1. dispatch_lane build chạy super-board-preflight.sh TRƯỚC khi nhận thẻ: verdict hold (hoặc sequence có blockedBy) thì
#     không claim, không spawn worker, thẻ sang Blocked kèm comment có dòng cuối `blocked-by:`; proceed thì giao như cũ;
#     preflight exit 79 thì dừng cả run (exit 79), không giao.
#  2. SWEPT_CARDS bền qua lần khởi động lại runner: sổ $INFLIGHT_DIR/swept-cards, không chỉ biến RAM.
# Chạy offline: runner source ở lib mode, gh/claude/preflight là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-preflight-swept.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
cp "$ROOT/.claude/bin/super-board-blocked-by.py" "$TMP/bin/"
# gh stub for the blocker-state helper: #8 closed, #45 merged PR, #46 open PR, #99 unknown, #9 open issue
cat > "$TMP/path/gh" <<'SH'
#!/bin/sh
case "$3" in
  8) echo "CLOSED https://github.com/acme/widgets/issues/8" ;;
  45) echo "MERGED https://github.com/acme/widgets/pull/45" ;;
  46) echo "OPEN https://github.com/acme/widgets/pull/46" ;;
  500) echo "HTTP 502" >&2; exit 1 ;;
  99) echo "GraphQL: Could not resolve to an issue or pull request with the number of 99." >&2; exit 1 ;;
  *) echo "OPEN https://github.com/acme/widgets/issues/$3" ;;
esac
SH
# preflight stub: prints $STUB_PREFLIGHT_JSON, exits $STUB_PREFLIGHT_RC, records its calls
cat > "$TMP/bin/super-board-preflight.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/preflight-calls"
printf '%s\n' "${STUB_PREFLIGHT_JSON:-}"
exit "${STUB_PREFLIGHT_RC:-0}"
SH
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo spawned >> "$STUB_DIR/spawned"
SH
chmod +x "$TMP/bin/"* "$TMP/path/claude" "$TMP/path/gh"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{"repo":{"remote":"https://github.com/acme/widgets"}}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"
BOT_LOGIN="bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }   # the issue being dispatched; blocker states come from the real helper + gh stub
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
PROJECT_ITEMS_JSON='{"items":[
 {"id":"PVTI_7","status":"Ready","labels":[],"content":{"type":"Issue","number":7,"title":"card seven","assignees":[]}}]}'
reset() { : > "$TMP/writes"; : > "$TMP/log"; rm -f "$TMP/spawned" "$TMP/preflight-calls" "$INFLIGHT_DIR"/*; }
PF="$TMP/bin/super-board-preflight.sh"

# ── 1a. hold → không claim, không worker, thẻ sang Blocked, comment có `blocked-by:` cuối
reset
export STUB_PREFLIGHT_RC=0 STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"hold","tag":"done","reason":"already delivered","evidence":["PR #31 merged and closes #7"],"blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
sleep 0.3
[ ! -e "$TMP/spawned" ] && [ ! -e "$INFLIGHT_DIR/7" ] && ! grep -q -- "--add-assignee" "$TMP/writes" \
  && ok "preflight hold: no claim, no worker" || fail "hold still dispatched (spawned=$(cat "$TMP/spawned" 2>/dev/null) writes=$(cat "$TMP/writes"))"
grep -q "move PVTI_7 Blocked" "$TMP/writes" && ok "  … card moved to Blocked" || fail "  card not moved to Blocked: $(cat "$TMP/writes")"
grep -q "blocked-by:" "$TMP/writes" && ok "  … comment carries a blocked-by: line" || fail "  no blocked-by: line in the comment"
[ -s "$TMP/preflight-calls" ] && grep -q -- "--repo acme/widgets" "$TMP/preflight-calls" && grep -q -- "--issues 7" "$TMP/preflight-calls" \
  && ok "  … preflight was asked about acme/widgets #7" || fail "  preflight call wrong: $(cat "$TMP/preflight-calls" 2>/dev/null)"

# ── 1b. proceed → giao như cũ
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"proceed","tag":"clean","reason":"","blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
sleep 0.5
[ -e "$INFLIGHT_DIR/7" ] && grep -q -- "issue edit 7 --add-assignee bot" "$TMP/writes" && ok "preflight proceed: card dispatched" || fail "proceed did not dispatch"

# ── 1c. sequence không blockedBy → proceed (chỉ là ghi chú xung đột, không chặn)
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap PR #9","blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
[ -e "$INFLIGHT_DIR/7" ] && ok "sequence with empty blockedBy: still dispatched" || fail "sequence/empty blockedBy was blocked"

# ── 1d. sequence có blockedBy → Blocked, dòng cuối blocked-by: 9
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap PR #52","blockedBy":[9]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
[ ! -e "$INFLIGHT_DIR/7" ] && grep -q "move PVTI_7 Blocked" "$TMP/writes" && grep -Eq "blocked-by: +9" "$TMP/writes" \
  && ok "sequence with blockedBy [9]: Blocked with 'blocked-by: 9'" || fail "sequence/blockedBy wrong: $(cat "$TMP/writes")"

# ── 1d2. blocker đã đóng (#8) → không chặn, giao (số đã đóng là đúng mẫu #200)
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap PR #52","blockedBy":[8]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
[ -e "$INFLIGHT_DIR/7" ] && ! grep -q "move PVTI_7 Blocked" "$TMP/writes" && ok "closed blocker #8 does not park the card" || fail "closed blocker parked the card: $(cat "$TMP/writes")"
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap PR #52","blockedBy":[8,9]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
grep -Eq "blocked-by: +9$" "$TMP/writes" && ok "mixed blockers: only the open #9 is written" || fail "mixed blockers wrong: $(cat "$TMP/writes")"

# ── 1d3. blockedBy là số PR (merged → coi đã đóng; open PR / số không tồn tại → không dừng board, giao như cũ)
export SB_GITHUB_HALT_FILE="$TMP/halt.json"
for nums in 45 46 99; do
  reset; rm -f "$TMP/halt.json"
  export STUB_PREFLIGHT_JSON="{\"7\":{\"number\":7,\"verdict\":\"sequence\",\"tag\":\"overlap\",\"reason\":\"overlap\",\"blockedBy\":[$nums]}}"
  ( SB_PREFLIGHT="$PF" dispatch_lane build 7 ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ -e "$INFLIGHT_DIR/7" ] && [ ! -e "$TMP/halt.json" ] && ok "blockedBy [$nums]: no halt, card dispatched" || fail "blockedBy [$nums] wrong (rc=$rc halt=$(ls "$TMP/halt.json" 2>/dev/null))"
done

# ── 1d4. gh lỗi thoáng qua khi đọc blocker (helper exit 79): runner sống, không giao, không chặn thẻ
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap","blockedBy":[500]}}'
( SB_PREFLIGHT="$PF" dispatch_lane build 7 ) >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$INFLIGHT_DIR/7" ] && ! grep -q "move PVTI_7 Blocked" "$TMP/writes" && ok "blocker read outage: runner survives, nothing dispatched or parked" || fail "blocker outage handling wrong (rc=$rc writes=$(cat "$TMP/writes"))"

# ── 1g. hold dựa trên độ giống / too-big là phán đoán → giao như cũ; unclear (mechanical) → chặn
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"hold","tag":"done","reason":"already delivered","evidence":["PR #31 merged: \"similar title\""],"blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
[ -e "$INFLIGHT_DIR/7" ] && ok "similarity-only hold is dispatched (Builder step 0 judges)" || fail "similarity-only hold was parked"
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"hold","tag":"too-big","reason":"too big","evidence":["x"],"blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
[ -e "$INFLIGHT_DIR/7" ] && ok "too-big hold is dispatched" || fail "too-big hold was parked"
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"hold","tag":"unclear","reason":"no AC","evidence":["issue #7 body"],"blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
[ ! -e "$INFLIGHT_DIR/7" ] && grep -q "move PVTI_7 Blocked" "$TMP/writes" && ok "unclear (no AC) is parked" || fail "unclear not parked"

# ── 1h. preflight lỗi khác 79 / không verdict → giao như cũ, không crash
reset
export STUB_PREFLIGHT_RC=3 STUB_PREFLIGHT_JSON=''
( SB_PREFLIGHT="$PF" dispatch_lane build 7 ) >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -e "$INFLIGHT_DIR/7" ] && ok "preflight crash (rc 3): dispatched without it, runner survives" || fail "rc 3 handling wrong (rc=$rc)"
export STUB_PREFLIGHT_RC=0

# ── 1i. chuyển thẻ sang Blocked hỏng → không comment (tick sau không lặp comment)
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"hold","tag":"done","reason":"already delivered","evidence":["PR #31 merged and closes #7"],"blockedBy":[]}}'
set_card_status() { return 1; }
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
! grep -q "issue comment" "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/7" ] && ok "failed move: no comment, no dispatch" || fail "failed move still commented/dispatched: $(cat "$TMP/writes")"
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }

# ── 1e. preflight exit 79 (không đọc được GitHub) → dừng run, không giao
reset
export STUB_PREFLIGHT_RC=79 STUB_PREFLIGHT_JSON=''
( SB_PREFLIGHT="$PF" dispatch_lane build 7 ) >/dev/null 2>&1; rc=$?
[ "$rc" = 79 ] && [ ! -e "$INFLIGHT_DIR/7" ] && ok "preflight exit 79 halts the run, nothing dispatched" || fail "exit 79 handling wrong (rc=$rc)"
export STUB_PREFLIGHT_RC=0

# ── 1f. lane qa không chạy preflight
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"hold","tag":"done","reason":"x","blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane qa 7 >/dev/null 2>&1
[ ! -s "$TMP/preflight-calls" ] && ok "qa lane is not pre-flighted" || fail "qa lane ran preflight"

# ── 2. SWEPT_CARDS còn sau khi runner khởi động lại
reset
cat > "$TMP/bin/super-board-wave-plan.sh" <<'SH'
#!/usr/bin/env bash
echo '{"sweep":[{"number":7,"clearedBy":[160]}]}'
SH
chmod +x "$TMP/bin/super-board-wave-plan.sh"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_7","status":"Blocked","labels":[],"content":{"type":"Issue","number":7,"assignees":[]}}]}'
RUN_MANIFEST="$TMP/manifest"
SWEPT_CARDS=""
sweep_blocked_cards >/dev/null 2>&1
[ "$(grep -c "move PVTI_7 Ready" "$TMP/writes")" = 1 ] && ok "first sweep moves #7 Blocked → Ready" || fail "first sweep did not move #7: $(cat "$TMP/writes")"
: > "$TMP/writes"
unset SWEPT_CARDS      # = a runner restart: the RAM variable is gone
sweep_blocked_cards >/dev/null 2>&1
[ ! -s "$TMP/writes" ] && ok "after a restart the same (card, blockers) is NOT swept again" || fail "restart re-swept #7: $(cat "$TMP/writes")"
: > "$TMP/writes"
cat > "$TMP/bin/super-board-wave-plan.sh" <<'SH'
#!/usr/bin/env bash
echo '{"sweep":[{"number":7,"clearedBy":[161]}]}'
SH
sweep_blocked_cards >/dev/null 2>&1
[ "$(grep -c "move PVTI_7 Ready" "$TMP/writes")" = 1 ] && ok "a different blocker set is still swept" || fail "new blocker set was not swept: $(cat "$TMP/writes")"

[ "$FAILS" -eq 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
