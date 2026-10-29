#!/usr/bin/env bash
# Test hồi quy (29/10, #607 #614): PR #613/#615 nằm trên nhánh `fix-…` (không phải `issue-<N>-…`), đã duyệt đúng head và mang nhãn
# merge-queue, nhưng review_approved_head chỉ tìm PR theo tiền tố nhánh nên không thấy: runner giao reviewer cho thẻ đã vào hàng,
# reviewer đúng là không làm gì, hai lần no-op thì thẻ bị đẩy Blocked.
# Luật:
#  - Không có PR nhánh `issue-<N>-`: PR mở có closingIssuesReferences chứa N (đúng một PR) được coi là PR của thẻ.
#  - Nhánh `issue-<N>-` vẫn thắng; hai PR cùng đóng N (không có nhánh issue-<N>-) → không chọn (review đầy đủ, an toàn như cũ).
#  - Duyệt sai head vẫn mất hiệu lực; block_noop_workers không đẩy Blocked thẻ Review có PR như vậy đã vào hàng.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-closing-ref.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
# SB_GITHUB_READ giả: pr list → $STUB_DIR/prs.json; pr view <N> --json comments → $STUB_DIR/comments-<N>.json; thiếu file = đọc hỏng.
cat > "$TMP/github-read.py" <<'PY'
import os, sys
a = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
d = os.environ['STUB_DIR']
if a[:2] == ['pr', 'list']: f = d + '/prs.json'
elif a[:2] == ['pr', 'view']: f = d + '/comments-' + a[2] + '.json'
else: sys.exit(1)
if not os.path.exists(f): sys.exit(1)
sys.stdout.write(open(f).read())
PY
export STUB_DIR="$TMP"

unset SB_GITHUB_READ_STRICT SB_NOOP_MAX SB_NOOP_WINDOW_S
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/github-read.py"
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/wl"; mkdir -p "$WORKER_LOG_DIR"
BOT_LOGIN="sb-bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
merge_queue_on() { return 0; }
issue_status() { printf 'Review'; }
issue_comment_count() { printf '3'; }
issue_locked() { return 1; }

H1=1111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222
approve() { printf '{"comments":[{"authorAssociation":"OWNER","body":"approved-head:%s"}]}' "$2" > "$TMP/comments-$1.json"; }
prs() { printf '%s' "$1" > "$TMP/prs.json"; }
mq='"labels":[{"name":"merge-queue"}],"isDraft":false'

# ── 1. nhánh fix-…, Closes #607, duyệt đúng head → tìm thấy PR (cả khi đòi nhãn merge-queue)
prs "[{\"number\":613,\"headRefName\":\"fix-607-worktree-no-cap\",\"headRefOid\":\"$H1\",$mq,\"closingIssuesReferences\":[{\"number\":607}]}]"
approve 613 "$H1"
got=$(review_approved_head 607 merge-queue)
[ "$got" = "613 $H1" ] && ok "non-issue branch closing #607, approved at head: PR found via closingIssuesReferences" || fail "closing-ref PR not found: '$got'"

# ── 2. duyệt head khác → không chọn
approve 613 "$H2"
review_approved_head 607 merge-queue >/dev/null && fail "stale approval honoured on closing-ref PR" || ok "  … approval on another head still voids it"

# ── 3. nhánh issue-<N>- thắng PR đóng N khác
prs "[{\"number\":612,\"headRefName\":\"other-fix\",\"headRefOid\":\"$H2\",$mq,\"closingIssuesReferences\":[{\"number\":607}]},{\"number\":613,\"headRefName\":\"issue-607-demo\",\"headRefOid\":\"$H1\",$mq,\"closingIssuesReferences\":[]}]"
approve 613 "$H1"; approve 612 "$H2"
got=$(review_approved_head 607 merge-queue)
[ "$got" = "613 $H1" ] && ok "issue-<N>- branch still wins over another PR closing N" || fail "branch match lost: '$got'"

# ── 4. hai PR cùng đóng N, không có nhánh issue-<N>- → mơ hồ, không chọn
prs "[{\"number\":612,\"headRefName\":\"a\",\"headRefOid\":\"$H1\",$mq,\"closingIssuesReferences\":[{\"number\":607}]},{\"number\":613,\"headRefName\":\"b\",\"headRefOid\":\"$H1\",$mq,\"closingIssuesReferences\":[{\"number\":607}]}]"
approve 612 "$H1"; approve 613 "$H1"
review_approved_head 607 merge-queue >/dev/null && fail "ambiguous: two PRs close #607 but one was picked" || ok "two PRs closing N: none picked (full review, fail safe)"

# ── 5. PR đóng issue khác → không chọn
prs "[{\"number\":613,\"headRefName\":\"fix-x\",\"headRefOid\":\"$H1\",$mq,\"closingIssuesReferences\":[{\"number\":6070}]}]"
approve 613 "$H1"
review_approved_head 607 merge-queue >/dev/null && fail "PR closing #6070 taken for #607" || ok "PR closing another issue: not picked"

# ── 6. đường thật: worker review no-op 2 lần trên thẻ có PR closing-ref đã vào hàng → không đẩy Blocked
prs "[{\"number\":613,\"headRefName\":\"fix-607-worktree-no-cap\",\"headRefOid\":\"$H1\",$mq,\"closingIssuesReferences\":[{\"number\":607}]}]"
approve 613 "$H1"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_607","status":"Review","labels":[],"content":{"type":"Issue","number":607,"title":"card 607","assignees":[]}}]}'
: > "$TMP/writes"
for _ in 1 2; do NOOP_CHECK=" 607:review:Review:3"; block_noop_workers; done
grep -q 'move PVTI_607 Blocked' "$TMP/writes" 2>/dev/null && fail "queued closing-ref card pushed to Blocked as a no-op" || ok "queued closing-ref card: review no-ops do not block it"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
