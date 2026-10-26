#!/usr/bin/env bash
# Test (Pha 2, lane C): runner khi merge queue bật (SB_MERGE_QUEUE: unset = theo config merge_queue.enabled, 0 = tắt, 1 = bật).
#  - Thẻ Review đã vào hàng (PR mở, không draft, nhãn merge-queue, approved-head của OWNER/MEMBER/COLLABORATOR khớp head) không bị
#    phóng reviewer lặp lại; thẻ khác vẫn được review với prompt "vào hàng" (khẳng định ở ca 1 và ca 3 bên dưới).
#  - Nhãn mà head đã dời, hoặc PR còn draft: không tính là đã vào hàng (review lại như thường).
#  - block_noop_workers không ghi no-op cho thẻ Review đã vào hàng; RUNAWAY không đếm chu kỳ khi lần quét Review gần nhất có thẻ chờ gom.
#  - merge_queue_due: tham số gọi bộ gom, exit 3/5, 79/9, công tắc tắt và thiếu script đều được khẳng định ở ca 7 bên dưới.
#  - SB_MERGE_QUEUE=0 giữ nguyên đường cũ (merge-only / train), kể cả khi config bật.
#  - Vòng sửa 1 (R3): queue chỉ bật khi worker_backend của config là "claude-p" (backend khác luôn tắt, kể cả SB_MERGE_QUEUE=1);
#    RUNAWAY chỉ miễn khi PR cũ nhất trong merge-queue.labeled chờ chưa quá 3 × merge_queue.max_wait_min; thẻ Review đã duyệt đúng head
#    mà mất nhãn merge-queue thì runner gắn lại nhãn, không phóng reviewer; mọi worker runner phóng có SB_BOARD_WORKER=1.
# Chạy offline qua lane_dispatch_tick thật: gh/claude là stub, đọc GitHub qua SB_GITHUB_READ giả. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="${SB_TEST_RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-merge-queue-runner.XXXXXX")"
# stub claude ghi PID của chính nó (exec giữ PID) vào $TMP/stub-pids; cleanup chỉ kill các PID đó.
cleanup() { for p in $(cat "$TMP/stub-pids" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
# SB_GITHUB_READ giả: pr list → $STUB_DIR/prs.json; pr view <N> --json comments → $STUB_DIR/comments-<N>.json; thiếu file = đọc hỏng.
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
# Stub bộ gom (file thật do lane B viết): ghi tham số, thoát theo $MQ_RC.
cat > "$TMP/bin/super-board-merge-queue.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/mq-calls"
exit "${MQ_RC:-0}"
SH
chmod +x "$TMP/bin/super-board-merge-queue.sh"
printf '#!/usr/bin/env bash\necho $$ >> "%s/stub-pids"\necho "${SB_BOARD_WORKER:-unset}" >> "%s/worker-env"\nexec sleep 301\n' "$TMP" "$TMP" > "$TMP/path/claude"
chmod +x "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX SB_REVIEW_TRAIN SB_MERGE_QUEUE SB_NOOP_MAX SB_NOOP_WINDOW_S MQ_RC SB_BOARD_WORKER
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; CP='"worker_backend":"claude-p"'; echo "{$CP}" > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
git init -q . 2>/dev/null
REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""; QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""
MAX_WORKERS=3; ACTIVE_WORKERS=0; BUILD_LOAD_MAX=8; REVIEW_WORKERS=1

card() { printf '{"id":"PVTI_%s","status":"%s","labels":[],"content":{"type":"Issue","number":%s,"title":"card %s","assignees":[]}}' "$1" "$2" "$1" "$1"; }
items() { PROJECT_ITEMS_JSON="{\"items\":[$(card 7 "$1"),$(card 8 "$2"),$(card 9 "$3")]}"; }
H1=1111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222
H3=3333333333333333333333333333333333333333
reset() {
  for p in $REVIEW_PID ${REVIEW_EXTRA//:*/}; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""; ACTIVE_WORKERS=0; TRAIN_BATCH=""
  rm -rf "$INFLIGHT_DIR"/[0-9]* "$INFLIGHT_DIR"/noops "$TMP"/prs.json "$TMP"/comments-*.json "$TMP/mq-calls" wl/*
  : > "$TMP/log"; : > "$TMP/writes"; : > "$TMP/worker-env"; echo "{$CP}" > "$CONFIG_PATH"; unset SB_MERGE_QUEUE MQ_RC
  rm -f "$TMP/repo/.git/super-board/merge-queue.labeled"
}
# pr <number> <issue> <head> <labels-json> <isDraft>
pr() { printf '{"number":%s,"headRefName":"issue-%s-x","headRefOid":"%s","labels":%s,"isDraft":%s}' "$1" "$2" "$3" "$4" "$5"; }
MQ='[{"name":"merge-queue"}]'
approve() { printf '{"comments":[{"authorAssociation":"%s","body":"[reviewer] ✅ merge-ready\\napproved-head:%s"}]}' "$2" "$3" > "$TMP/comments-$1.json"; }
tick() { lane_dispatch_tick review Review; }
logs() { ls wl 2>/dev/null | tr '\n' ' '; }
prompt_of() { sed -n 's/^prompt: //p' "wl/worker-review-$1.log" 2>/dev/null | head -1; }
prompt_any() { cat wl/worker-review-*.log 2>/dev/null | sed -n 's/^prompt: //p' | head -1; }

# ── 1. thẻ #7 đã vào hàng (nhãn + approved-head khớp head): không phóng reviewer; #8 chưa duyệt thì được review với prompt "vào hàng"
reset; export SB_MERGE_QUEUE=1; items Review Review Done
printf '[%s,%s]' "$(pr 70 7 "$H1" "$MQ" false)" "$(pr 71 8 "$H2" '[]' false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
[ ! -e wl/worker-review-7.log ] && ok "queued card #7 (merge-queue label + approved-head == head): no reviewer dispatched" || fail "queued card #7 got a worker: $(prompt_of 7 | cut -c1-200)"
[ -e wl/worker-review-8.log ] && ok "  … the next Review card #8 is reviewed instead" || fail "no worker for #8: $(logs)"
prompt_of 8 | grep -q 'super-review on issue #8' && ok "  … with the super-review prompt" || fail "#8 prompt: $(prompt_of 8 | cut -c1-200)"
prompt_of 8 | grep -q 'merge-queue' && ok "  … that tells the reviewer to enter the merge queue (label merge-queue)" || fail "#8 prompt lacks the merge-queue step: $(prompt_of 8 | cut -c1-400)"
prompt_of 8 | grep -qF '[reviewer] [report] ✅ merge-ready · queued PR #' && ok "  … and to post the queued comment on the issue" || fail "#8 prompt lacks the queued issue comment"
prompt_of 8 | grep -q 'super-board-merge-gate.sh\|proceed directly to merge' && fail "#8 prompt still sends the reviewer to the merge gate" || ok "  … and never sends it to the merge gate"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/worker-env" ] && break; sleep 0.2; done
[ "$(sort -u "$TMP/worker-env" 2>/dev/null)" = 1 ] && ok "F4: the worker the runner launched runs with SB_BOARD_WORKER=1" || fail "F4: worker env SB_BOARD_WORKER=$(tr '\n' ' ' < "$TMP/worker-env" 2>/dev/null)"
# tick sau: chỉ còn thẻ đã vào hàng → không phóng gì (không vòng lặp reviewer vô hạn)
reset; export SB_MERGE_QUEUE=1; items Review Done Done
printf '[%s]' "$(pr 70 7 "$H1" "$MQ" false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick; tick
[ -z "$(logs)" ] && ok "only queued cards in Review: two ticks dispatch nothing" || fail "queued card re-dispatched: $(logs)"

# ── 2. nhãn còn nhưng head đã dời / PR draft / người ngoài duyệt: chưa vào hàng → review lại (không merge-only)
reset; export SB_MERGE_QUEUE=1; items Review Done Done
printf '[%s]' "$(pr 70 7 "$H2" "$MQ" false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
prompt_of 7 | grep -q 'super-review on issue #7' && ok "label kept but head moved: the card is reviewed again" || fail "stale queued card: $(prompt_of 7 | cut -c1-200)"
reset; export SB_MERGE_QUEUE=1; items Review Done Done
printf '[%s]' "$(pr 70 7 "$H1" "$MQ" true)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
prompt_of 7 | grep -q 'super-review on issue #7' && ok "labelled draft PR: not queued (the queue takes no drafts), reviewer dispatched" || fail "draft PR treated as queued: $(logs)"
reset; export SB_MERGE_QUEUE=1; items Review Done Done
printf '[%s]' "$(pr 70 7 "$H1" "$MQ" false)" > "$TMP/prs.json"; approve 70 NONE "$H1"; tick
prompt_of 7 | grep -q 'super-review on issue #7' && ok "approved-head from a non-collaborator: not queued, reviewer dispatched" || fail "forged approval queued: $(logs)"

# ── 3. queue bật: không merge-only, không train dù thẻ đã có approved-head khớp head (chưa gắn nhãn).
# Vòng sửa 1 (R3): PR không draft, duyệt đúng head mà thiếu nhãn merge-queue (reviewer chết giữa chừng / nhãn bị gỡ tay) → runner gắn
# lại nhãn và bỏ qua thẻ, không phóng reviewer (review lại tốn 15-30 phút cho một PR đã duyệt).
reset; export SB_MERGE_QUEUE=1; items Review Review Review
printf '[%s,%s,%s]' "$(pr 70 7 "$H1" '[]' false)" "$(pr 71 8 "$H2" '[]' false)" "$(pr 72 9 "$H3" '[]' false)" > "$TMP/prs.json"
approve 70 OWNER "$H1"; approve 71 OWNER "$H2"; approve 72 OWNER "$H3"; tick
prompt_any | grep -q 'merge-train' && fail "queue on: the runner still dispatched a merge train" || ok "queue on: no merge-train worker for three approved cards"
prompt_any | grep -q 'merge-only' && fail "queue on: the runner still dispatched merge-only" || ok "  … and no merge-only worker"
[ -z "$(logs)" ] && ok "  … and no reviewer: approved at head but unlabelled cards are not reviewed again" || fail "approved unlabelled cards re-reviewed: $(logs) $(prompt_any | cut -c1-200)"
{ grep -qxF 'gh pr edit 70 --add-label merge-queue' "$TMP/writes" && grep -qxF 'gh pr edit 71 --add-label merge-queue' "$TMP/writes" \
  && grep -qxF 'gh pr edit 72 --add-label merge-queue' "$TMP/writes"; } \
  && ok "  … the runner puts the merge-queue label back on PRs 70, 71, 72" || fail "no relabel writes: $(tr '\n' ';' < "$TMP/writes")"
grep -q 'merge-train\|merge-only' "$TMP/log" && fail "runner log mentions merge-train/merge-only with the queue on" || ok "  … and the runner log has no merge-train/merge-only line"
# draft + duyệt đúng head + thiếu nhãn: không gắn nhãn (hàng không nhận draft), review lại như cũ
reset; export SB_MERGE_QUEUE=1; items Review Done Done
printf '[%s]' "$(pr 70 7 "$H1" '[]' true)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
{ prompt_of 7 | grep -q 'super-review on issue #7' && ! grep -q 'add-label' "$TMP/writes"; } \
  && ok "  … an approved unlabelled DRAFT PR is not relabelled; the card is reviewed" || fail "draft relabel: writes=$(tr '\n' ';' < "$TMP/writes") $(logs)"
# queue tắt (SB_MERGE_QUEUE=0): không gắn nhãn, đường merge-only cũ
reset; export SB_MERGE_QUEUE=0; items Review Done Done
printf '[%s]' "$(pr 70 7 "$H1" '[]' false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
{ prompt_of 7 | grep -q 'merge-only' && ! grep -q 'add-label' "$TMP/writes"; } \
  && ok "  … queue off: no relabel, the old merge-only path" || fail "queue off relabel: writes=$(tr '\n' ';' < "$TMP/writes") $(prompt_of 7 | cut -c1-120)"

# ── 4. công tắc: unset theo config; SB_MERGE_QUEUE=0 thắng config bật (đường cũ merge-only)
reset; echo "{$CP,\"merge_queue\":{\"enabled\":true}}" > "$CONFIG_PATH"; items Review Done Done
printf '[%s]' "$(pr 70 7 "$H1" "$MQ" false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
[ -z "$(logs)" ] && ok "SB_MERGE_QUEUE unset + config merge_queue.enabled=true: queue on, queued card skipped" || fail "config switch ignored: $(logs)"
# Vòng sửa 1 (R3): backend khác claude-p (thiếu khoá = workflow, workflow, codex) → queue tắt dù config bật hay SB_MERGE_QUEUE=1.
for BK in '' '"worker_backend":"workflow",' '"worker_backend":"codex",'; do
  for SW in '' 1; do
    reset; echo "{${BK}\"merge_queue\":{\"enabled\":true}}" > "$CONFIG_PATH"; [ -z "$SW" ] || export SB_MERGE_QUEUE=$SW
    if merge_queue_on; then fail "backend [${BK:-none}] SB_MERGE_QUEUE=[${SW}]: merge_queue_on says ON"; else ok "backend [${BK:-default workflow}] SB_MERGE_QUEUE=[${SW:-unset}]: queue off"; fi
  done
done
reset; echo '{"merge_queue":{"enabled":true}}' > "$CONFIG_PATH"; export SB_MERGE_QUEUE=1; items Review Done Done
printf '[%s]' "$(pr 70 7 "$H1" "$MQ" false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
prompt_of 7 | grep -q 'merge-only' && ok "  … no worker_backend + SB_MERGE_QUEUE=1: the tick takes the old merge-only path" || fail "backend default queue on in tick: $(logs) $(prompt_of 7 | cut -c1-120)"
reset; echo "{$CP,\"merge_queue\":{\"enabled\":true}}" > "$CONFIG_PATH"; export SB_MERGE_QUEUE=0; items Review Done Done
printf '[%s]' "$(pr 70 7 "$H1" "$MQ" false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
prompt_of 7 | grep -q 'merge-only' && ok "SB_MERGE_QUEUE=0 overrides the config: the old merge-only path" || fail "SB_MERGE_QUEUE=0 lost merge-only: $(prompt_of 7 | cut -c1-200)"
reset; items Review Done Done; printf '[%s]' "$(pr 70 7 "$H1" "$MQ" false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
prompt_of 7 | grep -q 'merge-only' && ok "SB_MERGE_QUEUE unset + no merge_queue in config: queue off, old merge-only path" || fail "default config not off: $(prompt_of 7 | cut -c1-200)"
reset; items Review Done Done; printf '[%s]' "$(pr 70 7 "$H1" "$MQ" false)" > "$TMP/prs.json"; tick
prompt_of 7 | grep -q 'proceed directly to merge via .claude/bin/super-board-merge-gate.sh' && ok "queue off: the reviewer prompt keeps the merge gate sentence" || fail "queue off prompt changed: $(prompt_of 7 | cut -c1-300)"

# ── 5. block_noop_workers: reviewer đúng quy trình để thẻ đã vào hàng ở Review → không bị ghi no-op, không Blocked
COMMENTS_NOW=3
issue_comment_count() { printf '%s' "$COMMENTS_NOW"; }
note_early_death() { :; }
sleep 0 & DEAD=$!; wait "$DEAD"
noop_lock() { printf 'PID=%s\nLANE=review\nSTARTED=2026-10-26T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$TMP/wl-7.log" > "$INFLIGHT_DIR/7"; }
reset; export SB_MERGE_QUEUE=1; items Review Done Done; NOOP_CHECK=""
printf '[%s]' "$(pr 70 7 "$H1" "$MQ" false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"
noop_lock; reap_finished_locks; block_noop_workers; noop_lock; reap_finished_locks; block_noop_workers
if ! grep -q "^move PVTI_7 Blocked" "$TMP/writes" && [ ! -s "$INFLIGHT_DIR/noops/7" ]; then
  ok "queued Review card: two reviewer exits with no new comment are not no-ops (no Blocked, no ledger)"
else
  fail "queued card penalised as no-op: writes=$(tr '\n' ';' < "$TMP/writes") ledger=$(cat "$INFLIGHT_DIR/noops/7" 2>/dev/null | tr '\n' ';')"
fi
reset; export SB_MERGE_QUEUE=1; items Review Done Done; NOOP_CHECK=""
printf '[%s]' "$(pr 70 7 "$H1" '[]' false)" > "$TMP/prs.json"
noop_lock; reap_finished_locks; block_noop_workers; noop_lock; reap_finished_locks; block_noop_workers
grep -q "^move PVTI_7 Blocked" "$TMP/writes" && ok "  … an unqueued Review card is still blocked after two no-op exits" || fail "no-op guard lost for unqueued card: $(tr '\n' ';' < "$TMP/writes")"

# ── 6. RUNAWAY: lần quét Review gần nhất có thẻ chờ gom → chu kỳ không Done không bị đếm; hết thẻ chờ thì đếm lại
reset; export SB_MERGE_QUEUE=1; items Review Done Done; REVIEW=1
printf '[%s]' "$(pr 70 7 "$H1" "$MQ" false)" > "$TMP/prs.json"; approve 70 OWNER "$H1"; tick
NO_PROGRESS_CYCLES=2; NO_PROGRESS_CYCLE_COUNT=0; PREV_DONE_SIG="8,9"; LANDED_COUNT=0; RUNAWAY_PAUSE_UNTIL=0
# Vòng sửa 1 (R3): miễn chỉ khi PR cũ nhất trong <git-common-dir>/super-board/merge-queue.labeled chờ ≤ 3 × max_wait_min (mặc định 60).
LBL="$TMP/repo/.git/super-board/merge-queue.labeled"; mkdir -p "$(dirname "$LBL")"; NOW=$(date +%s)
printf '71 %s %s\n70 %s %s\n' "$H2" "$((NOW - 30))" "$H1" "$((NOW - 60))" > "$LBL"
rc=0; for i in 1 2 3 4; do record_cycle_progress "8,9" || rc=1; done
[ "$rc" = 0 ] && [ "$NO_PROGRESS_CYCLE_COUNT" = 0 ] && ok "queued cards waiting for the batch (oldest 1 min): 4 ticks without Done do not trip RUNAWAY" || fail "RUNAWAY counted queued wait: rc=$rc count=$NO_PROGRESS_CYCLE_COUNT"
printf '71 %s %s\n70 %s %s\n' "$H2" "$((NOW - 30))" "$H1" "$((NOW - 3 * 3600 - 60))" > "$LBL"
NO_PROGRESS_CYCLE_COUNT=0; rc=0; for i in 1 2; do record_cycle_progress "8,9" || rc=1; done
[ "$rc" = 1 ] && ok "  … oldest queued PR waited > 3 × max_wait_min (default 60): RUNAWAY counts again and trips" || fail "RUNAWAY exempt forever for a stuck queue: rc=$rc count=$NO_PROGRESS_CYCLE_COUNT"
echo "{$CP,\"merge_queue\":{\"enabled\":true,\"max_wait_min\":1}}" > "$CONFIG_PATH"
printf '70 %s %s\n' "$H1" "$((NOW - 200))" > "$LBL"
NO_PROGRESS_CYCLE_COUNT=0; rc=0; for i in 1 2; do record_cycle_progress "8,9" || rc=1; done
[ "$rc" = 1 ] && ok "  … max_wait_min is read from the config (1 min: a 200 s wait is over 3 min, trips)" || fail "max_wait_min not read: rc=$rc count=$NO_PROGRESS_CYCLE_COUNT"
echo "{$CP}" > "$CONFIG_PATH"; rm -f "$LBL"
NO_PROGRESS_CYCLE_COUNT=0; rc=0; for i in 1 2; do record_cycle_progress "8,9" || rc=1; done
[ "$rc" = 1 ] && ok "  … no merge-queue.labeled (queue never ran): no exemption, RUNAWAY trips" || fail "missing labeled file exempts forever: rc=$rc count=$NO_PROGRESS_CYCLE_COUNT"
reset; export SB_MERGE_QUEUE=1; items Review Done Done; REVIEW=1
printf '[%s]' "$(pr 70 7 "$H1" '[]' false)" > "$TMP/prs.json"; tick
NO_PROGRESS_CYCLE_COUNT=0; rc=0; for i in 1 2; do record_cycle_progress "8,9" || rc=1; done
[ "$rc" = 1 ] && ok "  … a later Review scan with no queued card counts again (RUNAWAY at no_progress_cycles)" || fail "RUNAWAY never trips once the queue is empty: count=$NO_PROGRESS_CYCLE_COUNT"

# ── 7. merge_queue_due: tham số gọi bộ gom, exit 3/5 (runner chạy tiếp), 79/9 (halt), công tắc tắt, thiếu script
reset; export SB_MERGE_QUEUE=1
( merge_queue_due ); r=$?
{ [ "$r" = 0 ] && grep -qxF -- "--config $CONFIG_PATH --if-due" "$TMP/mq-calls"; } && ok "queue on: merge_queue_due runs super-board-merge-queue.sh --config <cfg> --if-due" || fail "merge-queue not called right: rc=$r calls=$(cat "$TMP/mq-calls" 2>/dev/null)"
export MQ_RC=3; ( merge_queue_due ); r=$?
[ "$r" = 0 ] && grep -q 'merge-queue' "$TMP/log" && ok "  … its exit 3 is logged and the runner keeps going" || fail "merge-queue exit 3 ended the runner: rc=$r"
export MQ_RC=79; ( merge_queue_due ); r=$?
[ "$r" = 79 ] && ok "  … exit 79 halts the runner (exit 79)" || fail "merge-queue exit 79 not a halt: rc=$r"
export MQ_RC=9; ( merge_queue_due ); r=$?
[ "$r" = 9 ] && ok "  … exit 9 halts the runner (exit 9)" || fail "merge-queue exit 9 not a halt: rc=$r"
( set -euo pipefail; MQ_RC=5 merge_queue_due; echo alive > "$TMP/alive" ); r=$?
[ "$r" = 0 ] && [ -e "$TMP/alive" ] && ok "  … under set -euo pipefail a failing merge-queue does not kill the runner" || fail "set -e killed the runner: rc=$r"
reset; export SB_MERGE_QUEUE=0; ( merge_queue_due ); r=$?
[ "$r" = 0 ] && [ ! -e "$TMP/mq-calls" ] && ok "SB_MERGE_QUEUE=0: merge-queue is never called" || fail "queue off but merge-queue called: $(cat "$TMP/mq-calls" 2>/dev/null)"
reset; export SB_MERGE_QUEUE=1; mv "$TMP/bin/super-board-merge-queue.sh" "$TMP/mq.off"; ( merge_queue_due ); r=$?
[ "$r" = 0 ] && ok "merge-queue script missing: logged, runner keeps going" || fail "missing merge-queue ended the runner: rc=$r"
mv "$TMP/mq.off" "$TMP/bin/super-board-merge-queue.sh"

# ── 8. cấu trúc (không phải bằng chứng hành vi): vòng lặp gọi merge_queue_due ở nhánh tick_is_cheap trước continue và ở cuối tick đầy đủ
awk '/^  if tick_is_cheap; then/{f=1} f&&/merge_queue_due/{m=1} f&&/continue/{print (m?"yes":"no"); exit}' "$RUNNER" | grep -qx yes \
  && ok "structure: the cheap-tick branch calls merge_queue_due before continue" || fail "cheap-tick branch lacks merge_queue_due before continue"
awk '/^  gh_checkpoint$/{g=1} g&&/merge_queue_due/{m=1} g&&/record_cycle_progress "\$\(done_signature\)"/{print (m?"yes":"no"); exit}' "$RUNNER" | grep -qx yes \
  && ok "structure: the full tick calls merge_queue_due before the landed-work gate" || fail "full tick lacks merge_queue_due before record_cycle_progress"

# ── 9. super-board-codex-lane.sh (lane review): queue bật thì prompt có bước vào hàng thay bước merge gate; tắt thì giữ bước cũ.
# Cách chạy: ast tách đúng khối `if args.lane == 'build': … elif args.lane == 'review'` rồi exec với os.environ/config giả.
codex_prompt() {   # codex_prompt <SB_MERGE_QUEUE> <config-json> (queue chỉ bật khi config có worker_backend claude-p, vòng sửa 1 R3)
  python3 - "${SB_TEST_CODEX_LANE:-$ROOT/.claude/bin/super-board-codex-lane.sh}" "$1" "$2" <<'PY'
import ast, json, sys, types
src = open(sys.argv[1], encoding='utf-8').read()
tree = ast.parse(src.split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0])
node = next(n for n in tree.body if isinstance(n, ast.If) and "args.lane == 'build'" in ast.unparse(n.test))
env = {} if sys.argv[2] == '' else {'SB_MERGE_QUEUE': sys.argv[2]}
ns = {'os': types.SimpleNamespace(environ=env), 'args': types.SimpleNamespace(lane='review'),
      'card': {'status': 'Review'}, 'config': json.loads(sys.argv[3]), 'prompt': ''}
exec(compile(ast.Module(body=[node], type_ignores=[]), 'codex-lane', 'exec'), ns)
print(ns['prompt'])
PY
}
p=$(codex_prompt 1 '{"worker_backend":"claude-p"}')
{ printf '%s' "$p" | grep -q 'add-label merge-queue' && printf '%s' "$p" | grep -qF 'queued PR #<N>' && ! printf '%s' "$p" | grep -q 'Merge ONLY through'; } \
  && ok "codex lane, SB_MERGE_QUEUE=1: review prompt enters the merge queue, no direct merge gate step" || fail "codex lane queue-on prompt: $(printf '%s' "$p" | tail -c 400)"
p=$(codex_prompt '' '{"worker_backend":"claude-p","merge_queue":{"enabled":true}}')
printf '%s' "$p" | grep -q 'add-label merge-queue' && ok "  … config merge_queue.enabled=true turns it on too" || fail "codex lane ignores config merge_queue.enabled"
p=$(codex_prompt 0 '{"worker_backend":"claude-p","merge_queue":{"enabled":true}}')
{ printf '%s' "$p" | grep -q 'Merge ONLY through the unchanged .claude/bin/super-board-merge-gate.sh' && ! printf '%s' "$p" | grep -q 'add-label merge-queue'; } \
  && ok "  … SB_MERGE_QUEUE=0 keeps the old merge gate step" || fail "codex lane queue-off prompt changed"
for cfg in '{"merge_queue":{"enabled":true}}' '{"worker_backend":"codex","merge_queue":{"enabled":true}}' '{"worker_backend":"workflow"}'; do
  p=$(codex_prompt 1 "$cfg")
  { printf '%s' "$p" | grep -q 'Merge ONLY through the unchanged' && ! printf '%s' "$p" | grep -q 'add-label merge-queue'; } \
    && ok "  … codex lane, backend not claude-p ($cfg) + SB_MERGE_QUEUE=1: queue off, old merge gate step" || fail "codex lane queue on for $cfg"
done

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
