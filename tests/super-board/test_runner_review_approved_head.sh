#!/usr/bin/env bash
# Test (#227): thẻ Review đã được duyệt đúng head hiện tại thì lượt sau chỉ chạy lại merge gate (merge-only), không review lại.
#  - comment `approved-head:<sha>` của người có quyền ghi (OWNER/MEMBER/COLLABORATOR) khớp head PR hiện tại → prompt merge-only;
#  - head đổi, không có comment, comment của người ngoài, đọc GitHub hỏng → review đầy đủ như cũ;
#  - merge gate exit 4 (thẻ ở lại Review) → tick sau vẫn merge-only, không có lượt review mới.
# Chạy offline qua lane_dispatch_tick thật: gh/claude là stub, đọc GitHub qua SB_GITHUB_READ giả. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-approved-head.XXXXXX")"
cleanup() { for p in $(pgrep -f "$TMP/path/claude" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
# SB_GITHUB_READ giả: pr list → $STUB_DIR/prs.json; pr view <N> --json comments → $STUB_DIR/comments-<N>.json; thiếu file = đọc hỏng (exit 1).
cat > "$TMP/bin/super-board-github-read.py" <<'PY'
import os, sys
a = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
d = os.environ['STUB_DIR']
if a[:2] == ['pr', 'list']: f = d + '/prs.json'
elif a[:2] == ['pr', 'view']: f = d + '/comments-' + a[2] + '.json'
else: sys.exit(1)
if not os.path.exists(f): sys.exit(1)
sys.stdout.write(open(f).read())
PY
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/path/claude"
chmod +x "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX
# Pha 2: mọi ca dưới đây là đường lùi khi merge queue tắt (merge-only của #227); hành vi khi bật ở test_runner_merge_queue.sh.
export SB_MERGE_QUEUE=0
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
git init -q . 2>/dev/null
REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""; QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""
MAX_WORKERS=3; ACTIVE_WORKERS=0; BUILD_LOAD_MAX=8; REVIEW_WORKERS=1
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_7","status":"Review","labels":[],"content":{"type":"Issue","number":7,"assignees":[]}}]}'

H1=1111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222
reset() {
  [ -z "$REVIEW_PID" ] || { kill "$REVIEW_PID" 2>/dev/null; wait "$REVIEW_PID" 2>/dev/null; }
  REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""; ACTIVE_WORKERS=0
  rm -f "$INFLIGHT_DIR"/[0-9]* "$TMP"/prs.json "$TMP"/comments-*.json wl/*; : > "$TMP/log"; : > "$TMP/writes"
}
pr_head() { printf '[{"number":70,"headRefName":"issue-7-demo","headRefOid":"%s"},{"number":71,"headRefName":"issue-77-other","headRefOid":"%s"}]' "$1" "$H2" > "$TMP/prs.json"; }
comment() {   # comment <assoc> <body>
  printf '{"comments":[{"authorAssociation":"%s","body":%s}]}' "$1" "$(printf '%s' "$2" | jq -Rs .)" > "$TMP/comments-70.json"
}
tick() { lane_dispatch_tick review Review; }
prompt_of() { sed -n 's/^prompt: //p' wl/worker-review-7.log | head -1; }
is_merge_only() { prompt_of | grep -q 'merge-only'; }
is_full_review() { prompt_of | grep -q 'super-review on issue #7' && ! is_merge_only; }

# ── 1. duyệt đúng head hiện tại → merge-only, kèm --expect-head, không bảo review lại
reset; pr_head "$H1"; comment OWNER "[reviewer] ✅ merge-ready
approved-head:$H1"; tick
is_merge_only && ok "approved head == PR head: the worker gets the merge-only prompt" || fail "approved head not merge-only: $(prompt_of | cut -c1-200)"
prompt_of | grep -q -- "--expect-head $H1" && ok "  … pinned to the approved head (--expect-head $H1)" || fail "prompt lacks --expect-head $H1"
prompt_of | grep -q 'PR #70' && ok "  … and names the PR" || fail "prompt lacks PR #70"
grep -q 'merge-only' "$TMP/log" && ok "  … and the runner log says merge-only" || fail "no merge-only log line: $(tr '\n' '|' < "$TMP/log")"

# ── 2. merge gate exit 4: thẻ ở lại Review, worker chết → tick sau vẫn merge-only, không phải review đầy đủ
kill "$REVIEW_PID" 2>/dev/null; wait "$REVIEW_PID" 2>/dev/null; rm -f wl/*; reap_finished_locks; tick
is_merge_only && ok "next tick (card still in Review after gate exit 4): merge-only again, no fresh review" || fail "second tick: $(prompt_of | cut -c1-200)"

# ── 3. head đổi → duyệt mất hiệu lực → review đầy đủ
reset; pr_head "$H2"; comment OWNER "approved-head:$H1"; tick
is_full_review && ok "head moved after approval: full review again" || fail "stale approval honoured: $(prompt_of | cut -c1-200)"

# ── 4. không có duyệt / người ngoài duyệt / đọc GitHub hỏng → review đầy đủ
reset; pr_head "$H1"; comment OWNER "just a note"; tick
is_full_review && ok "no approved-head comment: full review" || fail "no approval but not full review"
reset; pr_head "$H1"; comment NONE "approved-head:$H1"; tick
is_full_review && ok "approved-head from a non-collaborator (NONE): ignored, full review" || fail "forged approval honoured"
reset; tick
is_full_review && ok "GitHub read fails: falls back to the full review (fail safe)" || fail "read failure not full review"
reset; pr_head "$H1"; comment CONTRIBUTOR "approved-head:$H1"; tick
is_full_review && ok "approved-head from a CONTRIBUTOR: ignored, full review" || fail "contributor approval honoured"

# ── 5. nhiều comment: cái cuối cùng thắng (duyệt cũ sai head + duyệt mới đúng head, và ngược lại)
reset; pr_head "$H1"
printf '{"comments":[{"authorAssociation":"OWNER","body":"approved-head:%s"},{"authorAssociation":"OWNER","body":"approved-head:%s"}]}' "$H2" "$H1" > "$TMP/comments-70.json"; tick
is_merge_only && ok "latest approved-head comment wins (old one on another head is ignored)" || fail "latest approval not used"
reset; pr_head "$H1"
printf '{"comments":[{"authorAssociation":"OWNER","body":"approved-head:%s"},{"authorAssociation":"OWNER","body":"approved-head:%s"}]}' "$H1" "$H2" > "$TMP/comments-70.json"; tick
is_full_review && ok "  … and a newer approval for another head voids the older one" || fail "older approval honoured over newer"

# ── 5b. #605 Lane F: approved-head kèm `approved-by: {json}` = nguồn duyệt chéo; tự duyệt (reviewer == builder) bị từ chối.
# audit T0066 vòng 2: task_id phải có biên bản audit pass của antigravity-pm với auditedHead == head PR (commit có trong repo).
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"   # PM state giả chỉ trong test này
pm_task() {   # pm_task <task_id> <auditedHead> [verdict]
  mkdir -p "$TMP/pm/projects/p/tasks/$1"
  jq -n --arg id "$1" --arg p "$(git rev-parse --show-toplevel)" --arg h "$2" --arg v "${3:-pass}" \
    '{id:$id,project:$p,verdicts:{audit:{verdict:$v,reviewer:"pm",notes:("fixture\nauditedHead: "+$h)}}}' > "$TMP/pm/projects/p/tasks/$1/task.json"
}
git -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m c1; RH0=$(git rev-parse HEAD)
git -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m c2; RH=$(git rev-parse HEAD)
pm_task T0605-cross "$RH"; pm_task T0606-old "$RH0"; pm_task T0607-failed "$RH" fail
BY_OK='{"reviewer":"antigravity","builder":"claude-builder","task_id":"T0605-cross","gate_receipt":"r1"}'
reset; pr_head "$RH"; comment COLLABORATOR "approved-head:$RH
approved-by: $BY_OK
note: } trailing"; tick
is_merge_only && ok "#605 cross-review marker (reviewer≠builder) at the head: merge-only" || fail "#605 valid marker not merge-only: $(prompt_of | cut -c1-200)"
for t in T0999-forged T0606-old T0607-failed issue-605; do
  reset; pr_head "$RH"; comment MEMBER "approved-head:$RH
approved-by: {\"reviewer\":\"antigravity\",\"builder\":\"claude-builder\",\"task_id\":\"$t\",\"gate_receipt\":\"r1\"}"; tick
  is_full_review && ok "#605 approved-by task_id $t without a matching audit pass: rejected, full review" || fail "#605 task_id $t honoured"
done
reset; pr_head "$H1"; comment MEMBER "approved-head:$H1
approved-by: {\"reviewer\":\"Claude-Builder\",\"builder\":\"claude-builder\",\"task_id\":\"t\",\"gate_receipt\":\"r\"}"; tick
is_full_review && ok "#605 reviewer == builder (case-insensitive): self-review rejected, full review" || fail "#605 self-review honoured"
reset; pr_head "$H2"; comment MEMBER "approved-head:$H1
approved-by: $BY_OK"; tick
is_full_review && ok "#605 marker on another head: full review" || fail "#605 head mismatch honoured"
reset; pr_head "$H1"; comment MEMBER "approved-head:$H1
approved-by: {not json"; tick
is_full_review && ok "#605 malformed approved-by: rejected, no fallback to bare" || fail "#605 malformed marker honoured"
reset; pr_head "$H1"; comment MEMBER "approved-head:$H1
approved-by: {\"reviewer\":\"a\",\"builder\":\"b\",\"task_id\":\"\",\"gate_receipt\":\"r\"}"; tick
is_full_review && ok "#605 empty task_id: rejected" || fail "#605 empty field honoured"
reset; pr_head "$H1"; comment OWNER "approved-head:$H1"; tick
is_merge_only && ok "#605 bare approved-head from the OWNER: still accepted" || fail "#605 bare OWNER approval lost"
# #605 Lane H: approved-head trơn chỉ OWNER; MEMBER / COLLABORATOR trơn và trường số bị từ chối.
reset; pr_head "$H1"; comment MEMBER "approved-head:$H1"; tick
is_full_review && ok "#605 bare approved-head from a MEMBER: rejected (approved-by required), full review" || fail "#605 bare MEMBER approval honoured"
reset; pr_head "$H1"; comment COLLABORATOR "approved-head:$H1"; tick
is_full_review && ok "#605 bare approved-head from a COLLABORATOR: rejected, full review" || fail "#605 bare COLLABORATOR approval honoured"
reset; pr_head "$H1"; comment MEMBER "approved-head:$H1
approved-by: {\"reviewer\":1,\"builder\":2,\"task_id\":3,\"gate_receipt\":4}"; tick
is_full_review && ok "#605 numeric approved-by fields: rejected (strings only)" || fail "#605 numeric approved-by honoured"

# ── 6. hợp đồng viết: run.md bảo Reviewer ghi `approved-head:` trước khi chạy gate
grep -q 'approved-head:' "$ROOT/.claude/skills/super-board/references/run.md" && ok "run.md tells the Reviewer to post approved-head:<sha> before the gate" || fail "run.md does not mention approved-head:"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
