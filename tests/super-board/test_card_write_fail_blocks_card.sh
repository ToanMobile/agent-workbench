#!/usr/bin/env bash
# Test hồi quy 28/10: một lệnh ghi GitHub về MỘT thẻ hỏng (04:33 gỡ assignee #446 sau khi diệt worker QA zombie) làm gh_write_once
# halt + exit 79, cả board đứng tới 07:05. Luật mới (lệnh của người dùng: "lỗi task thì đưa vô blocked chứ ko dừng board"):
#  a. lệnh ghi của một thẻ (`issue <verb> <N>`, `project item-edit --id <item>`) hỏng → thẻ đó vào Blocked + comment chặn
#     (`blocked-by:  -`, sweep không tự thả), gh_write_once trả 1, runner chạy tiếp, không bản ghi halt;
#  b. chính bước chặn thẻ (chuyển Blocked hoặc comment) cũng hỏng → halt exit 79 như cũ, bản ghi halt là của lệnh ghi gốc;
#  c. lệnh ghi không thuộc thẻ nào (`label create`) hỏng → halt exit 79 như cũ;
#  d. dispatch_lane: chuyển thẻ sang Building hỏng và thẻ đã vào Blocked → không phóng worker, không ghi lock.
# Dùng runner THẬT của checkout chứa file test này (ROOT từ $0, INSTINCT-057). Chạy offline, gh giả. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-cardfail.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/sbin"
# gh giả: ghi argv (một dòng, xuống dòng thành ⏎), hỏng khi argv khớp regex FAIL_PAT (neo ^: body comment chặn có trích lệnh hỏng).
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
line="$*"; printf '%s\n' "${line//$'\n'/⏎}" >> "$GH_LOG"
[ -n "${FAIL_PAT:-}" ] && printf '%s' "$line" | grep -qE -- "$FAIL_PAT" && exit 1
exit 0
SH
# github-read giả: --check qua; --halt ghi bản ghi rồi exit 79 như helper thật.
cat > "$TMP/sbin/super-board-github-read.py" <<'PY'
#!/usr/bin/env python3
import os, sys
if '--halt' in sys.argv:
    open(os.environ['HALT_LOG'], 'a').write(' '.join(sys.argv[1:]) + '\n')
    sys.exit(79)
PY
printf 'import sys\nsys.exit(0)\n' > "$TMP/sbin/super-board-skills-ready.py"
printf '#!/usr/bin/env bash\ntouch "$WRAP_MARK"\n' > "$TMP/sbin/wrap.sh"
chmod +x "$TMP/bin/gh" "$TMP/sbin/"*

ITEMS='{"items":[{"id":"I446","status":"QA","labels":[],"content":{"type":"Issue","number":446,"title":"zombie card","assignees":[]}},
 {"id":"I447","status":"Ready","labels":[],"content":{"type":"Issue","number":447,"title":"ready card","assignees":[]}}]}'

# $1 = tên case, $2 = FAIL_PAT, phần còn lại = lệnh bash chạy trong runner đã source. In ra stdout của lệnh; RC = mã thoát subshell.
run_case() {
  local name="$1" pat="$2"; shift 2
  rm -f "$TMP/gh.log" "$TMP/halt.log" "$TMP/log" "$TMP/wrap.mark"; rm -rf "$TMP/inflight"; mkdir -p "$TMP/inflight"
  OUT=$( ( SB_LIB_ONLY=1 . "$RUNNER" >/dev/null 2>&1 || exit 99
      set +e; cd "$TMP" || exit 98
      log() { echo "$*" >> "$TMP/log"; }
      PATH="$TMP/bin:$PATH"; export GH_LOG="$TMP/gh.log" HALT_LOG="$TMP/halt.log" FAIL_PAT="$pat" WRAP_MARK="$TMP/wrap.mark"
      SB_GITHUB_READ="$TMP/sbin/super-board-github-read.py"; SB_WORKER_WRAP="$TMP/sbin/wrap.sh"; RUN_MANIFEST=/dev/null
      INFLIGHT_DIR="$TMP/inflight"; WORKER_LOG_DIR="$TMP/wlogs"; BOT_LOGIN=bot
      STATUS_FIELD_ID=F; PROJECT_NODE_ID=P
      STATUS_OPTIONS_JSON='[{"name":"Ready","id":"OREADY"},{"name":"Building","id":"OBUILD"},{"name":"QA","id":"OQA"},{"name":"Blocked","id":"OBLOCKED"},{"name":"Done","id":"ODONE"}]'
      PROJECT_ITEMS_JSON="$ITEMS"
      eval "$*" ) 2>/dev/null )
  RC=$?
  NAME="$name"
}
gh_has() { grep -qF -- "$1" "$TMP/gh.log" 2>/dev/null; }

# ── a. gỡ assignee của #446 hỏng (đúng sự cố 28/10)
run_case a '^issue edit 446 --remove-assignee' 'gh_write_once issue edit 446 --remove-assignee bot; echo "continued rc=$?"; issue_status 446'
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'continued rc=1'; } \
  && ok "a: card write fails → gh_write_once returns 1, runner continues (no exit 79)" || fail "a: rc=$RC out=$(echo "$OUT" | tr '\n' '|')"
gh_has 'project item-edit --id I446 --project-id P --field-id F --single-select-option-id OBLOCKED' \
  && ok "a: #446 moved to Blocked" || fail "a: no Blocked move in gh log: $(cat "$TMP/gh.log" 2>/dev/null | cut -c1-120)"
{ grep -F 'issue comment 446 --body [orchestrator] [blocker] 🛑 blocked' "$TMP/gh.log" 2>/dev/null | grep -qF 'blocked-by:  -'; } \
  && ok "a: block-template comment on #446, last line blocked-by:  -" || fail "a: blocker comment missing or wrong"
grep -F 'issue comment 446' "$TMP/gh.log" 2>/dev/null | grep -qF 'issue edit 446 --remove-assignee bot' \
  && ok "a: comment names the uncertain write" || fail "a: comment does not name the failed write"
grep -F 'issue comment 446' "$TMP/gh.log" 2>/dev/null | grep -q 'Reason tag:[^⏎]*🙋' \
  && fail "a: Reason tag carries 🙋 (approval-request semantics: a 'done' reply would jump it to Review)" || ok "a: Reason tag is not the 🙋 merge-approval tag"
[ ! -s "$TMP/halt.log" ] && ok "a: no halt record" || fail "a: halt record written: $(cat "$TMP/halt.log")"
printf '%s\n' "$OUT" | tail -1 | grep -qx 'Blocked' && ok "a: board cache shows #446 Blocked this tick" || fail "a: cache status '$(printf '%s\n' "$OUT" | tail -1)'"

# ── a2. project item-edit (Done) của #446 hỏng → map item → #446, thẻ vào Blocked
run_case a2 '^project item-edit .*option-id ODONE' 'set_card_status I446 Done; echo "continued rc=$?"'
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'continued rc=1' && gh_has 'single-select-option-id OBLOCKED' && [ ! -s "$TMP/halt.log" ]; } \
  && ok "a2: item-edit of I446 fails → mapped to #446, Blocked, no halt" || fail "a2: rc=$RC out=$(echo "$OUT" | tr '\n' '|') halt=$(cat "$TMP/halt.log" 2>/dev/null)"

# ── b. chính bước chuyển Blocked cũng hỏng → halt 79 như cũ
run_case b '^issue edit 446 --remove-assignee|^project item-edit' 'gh_write_once issue edit 446 --remove-assignee bot; echo "continued rc=$?"'
{ [ "$RC" = 79 ] && ! printf '%s\n' "$OUT" | grep -q continued && grep -q 'issue edit' "$TMP/halt.log" 2>/dev/null; } \
  && ok "b: Blocked move fails too → exit 79 with a halt record of the original write" || fail "b: rc=$RC out=$OUT halt=$(cat "$TMP/halt.log" 2>/dev/null)"
# ── b2. comment chặn hỏng → halt 79
run_case b2 '^issue edit 446 --remove-assignee|^issue comment' 'gh_write_once issue edit 446 --remove-assignee bot; echo "continued rc=$?"'
{ [ "$RC" = 79 ] && ! printf '%s\n' "$OUT" | grep -q continued && [ -s "$TMP/halt.log" ]; } \
  && ok "b2: blocker comment fails → exit 79 with a halt record" || fail "b2: rc=$RC out=$OUT"
# ── b3. thẻ không có trên board (không map được item) → halt 79
run_case b3 '^issue edit 999 --remove-assignee' 'gh_write_once issue edit 999 --remove-assignee bot; echo "continued rc=$?"'
{ [ "$RC" = 79 ] && [ -s "$TMP/halt.log" ]; } && ok "b3: card not on the board → exit 79 as before" || fail "b3: rc=$RC out=$OUT"

# ── c. lệnh ghi không thuộc thẻ nào → halt 79 như cũ
run_case c '^label create' 'gh_write_once label create x --force; echo "continued rc=$?"'
{ [ "$RC" = 79 ] && ! printf '%s\n' "$OUT" | grep -q continued && grep -q 'label create' "$TMP/halt.log" 2>/dev/null && ! gh_has item-edit; } \
  && ok "c: non-card write fails → exit 79, no card moved" || fail "c: rc=$RC out=$OUT halt=$(cat "$TMP/halt.log" 2>/dev/null)"

# ── d. dispatch_lane: chuyển #447 sang Building hỏng → thẻ vào Blocked, không phóng worker
DSTUBS='issue_locked() { return 1; }; issue_is_open() { return 0; }; worktree_disk_room() { return 0; }; resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
  preflight_gate() { return 0; }; dispatch_baseline() { :; }; agent_office_args() { AO_ARGS=(); AO_NONCE=x; }; global_slot_register() { :; }
  claude_model_for_tier() { echo m; }; lane_worktree_hint() { :; }; resume_hint() { :; }; PROJECT_OWNER=o; PROJECT_NUMBER=1; DISPATCH_COUNT=0; DISPATCH_LOG=""'
run_case d '^project item-edit .*option-id OBUILD' "$DSTUBS"'; dispatch_lane build 447; echo "continued rc=$?"; sleep 1'
{ [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'continued rc=0' && gh_has 'single-select-option-id OBLOCKED' \
  && [ ! -e "$TMP/inflight/447" ] && [ ! -e "$TMP/wrap.mark" ]; } \
  && ok "d: Building move fails → #447 Blocked, no worker spawned, no lock" \
  || fail "d: rc=$RC out=$(echo "$OUT" | tr '\n' '|') lock=$([ -e "$TMP/inflight/447" ] && echo yes || echo no) worker=$([ -e "$TMP/wrap.mark" ] && echo yes || echo no)"
# d2 (đối chứng): chuyển Building thành công → worker vẫn được phóng như cũ
run_case d2 '' "$DSTUBS"'; dispatch_lane build 447; echo "continued rc=$?"; sleep 1'
{ [ "$RC" = 0 ] && [ -e "$TMP/inflight/447" ] && [ -e "$TMP/wrap.mark" ]; } \
  && ok "d2: control — Building move succeeds → worker spawned and locked as before" || fail "d2: rc=$RC out=$(echo "$OUT" | tr '\n' '|')"

echo "pass=$PASS fail=$FAIL"; [ "$FAIL" = 0 ]
