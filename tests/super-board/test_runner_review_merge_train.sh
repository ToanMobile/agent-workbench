#!/usr/bin/env bash
# Test (#228): runner gom các thẻ Review đã duyệt (approved-head của #227) thành MỘT worker chạy super-board-merge-train.sh,
# thay vì mỗi reviewer tự chạy merge gate (N PR = N lần verify nối tiếp qua merge.lock).
#  - ≥2 thẻ đã duyệt đúng head → một worker, một prompt `--prs <PR…>` theo thứ tự bảng, lock của MỌI thẻ cùng một PID;
#  - thẻ chưa duyệt / duyệt sai head / người ngoài duyệt không vào đợt; chỉ 1 thẻ đã duyệt → đường merge-only cũ (không train);
#  - worker train không bị coi là zombie khi thẻ đầu đã sang Done mà thẻ khác còn ở Review; hết thẻ Review thì mới bị thu hồi;
#  - run.md ghi hợp đồng routing `train-result:` cho worker.
# Chạy offline qua lane_dispatch_tick thật: gh/claude là stub, đọc GitHub qua SB_GITHUB_READ giả. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-review-train.XXXXXX")"
cleanup() { for p in $(pgrep -f "$TMP/path/claude" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
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
printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/path/claude"
chmod +x "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX SB_REVIEW_TRAIN
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

card() { printf '{"id":"PVTI_%s","status":"%s","labels":[],"content":{"type":"Issue","number":%s,"assignees":[]}}' "$1" "$2" "$1"; }
items() { PROJECT_ITEMS_JSON="{\"items\":[$(card 7 "$1"),$(card 8 "$2"),$(card 9 "$3")]}"; }
H1=1111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222
H3=3333333333333333333333333333333333333333
H9=9999999999999999999999999999999999999999
reset() {
  [ -z "$REVIEW_PID" ] || { kill "$REVIEW_PID" 2>/dev/null; wait "$REVIEW_PID" 2>/dev/null; }
  REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""; ACTIVE_WORKERS=0; TRAIN_BATCH=""
  rm -f "$INFLIGHT_DIR"/[0-9]* "$TMP"/prs.json "$TMP"/comments-*.json wl/*; : > "$TMP/log"; : > "$TMP/writes"
}
# prs <head7> <head8> <head9>: PR 70/71/72 của issue 7/8/9 (PR 79 là của issue khác, không liên quan).
prs() { printf '[{"number":70,"headRefName":"issue-7-a","headRefOid":"%s"},{"number":71,"headRefName":"issue-8-b","headRefOid":"%s"},{"number":72,"headRefName":"issue-9-c","headRefOid":"%s"},{"number":79,"headRefName":"issue-99-z","headRefOid":"%s"}]' "$1" "$2" "$3" "$H9" > "$TMP/prs.json"; }
approve() {   # approve <pr> <assoc> <sha>
  printf '{"comments":[{"authorAssociation":"%s","body":"approved-head:%s"}]}' "$2" "$3" > "$TMP/comments-$1.json"
}
tick() { lane_dispatch_tick review Review; }
logs() { ls wl 2>/dev/null | tr '\n' ' '; }
prompt_any() { cat wl/worker-review-*.log 2>/dev/null | sed -n 's/^prompt: //p' | head -1; }
lock_pid() { sed -n 's/^PID=//p' "$INFLIGHT_DIR/$1" 2>/dev/null | head -1; }

# ── 1. ba thẻ đã duyệt đúng head → MỘT worker, một lượt merge train cho cả 3 PR
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; approve 71 MEMBER "$H2"; approve 72 COLLABORATOR "$H3"; tick
[ "$(ls wl | wc -l | tr -d ' ')" = 1 ] && ok "3 approved cards: exactly one worker dispatched ($(logs))" || fail "expected one worker log, got: $(logs)"
prompt_any | grep -q 'super-board-merge-train.sh' && ok "  … its prompt runs super-board-merge-train.sh" || fail "prompt lacks the merge train: $(prompt_any | cut -c1-200)"
prompt_any | grep -q -- "--prs 70:$H1,71:$H2,72:$H3" && ok "  … over all three PRs in board order, each pinned to its approved head" || fail "prompt lacks the pinned --prs: $(prompt_any | cut -c1-400)"
prompt_any | grep -q 'super-review on issue' && fail "a full review was ordered inside the train prompt" || ok "  … and orders no fresh review"
P7=$(lock_pid 7); P8=$(lock_pid 8); P9=$(lock_pid 9)
{ [ -n "$P7" ] && [ "$P7" = "$P8" ] && [ "$P8" = "$P9" ]; } && ok "  … locks of #7 #8 #9 hold the same live PID ($P7)" || fail "locks differ: 7=$P7 8=$P8 9=$P9"
grep -q 'issue edit 8 --add-assignee bot' "$TMP/writes" && grep -q 'issue edit 9 --add-assignee bot' "$TMP/writes" && ok "  … every card of the batch is claimed" || fail "extras not claimed: $(tr '\n' '|' < "$TMP/writes")"
grep -q 'merge-train' "$TMP/log" && ok "  … and the runner log says merge-train" || fail "no merge-train log line: $(tr '\n' '|' < "$TMP/log")"

# ── 2. tick sau khi worker còn sống: không giao thêm worker nào cho các thẻ trong đợt
rm -f wl/*; tick
[ -z "$(ls wl)" ] && ok "next tick: no second worker for cards already in the train" || fail "second dispatch: $(logs)"

# ── 3. thẻ chưa duyệt / duyệt sai head / người ngoài duyệt không vào đợt
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; approve 71 NONE "$H2"; approve 72 OWNER "$H3"; tick
prompt_any | grep -q -- "--prs 70:$H1,72:$H3" && ok "forged approval (NONE) on #8 stays out: --prs 70:H1,72:H3" || fail "batch wrong: $(prompt_any | cut -c1-300)"
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; approve 71 OWNER "$H1"; approve 72 OWNER "$H3"; tick
prompt_any | grep -q -- "--prs 70:$H1,72:$H3" && ok "stale head approval on #8 stays out: --prs 70:H1,72:H3" || fail "stale approval batched: $(prompt_any | cut -c1-300)"

# ── 4. chỉ một thẻ đã duyệt → đường merge-only cũ, không train
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; tick
prompt_any | grep -q 'merge-train' && fail "a single approved card went through the train" || ok "one approved card: no train"
prompt_any | grep -q 'merge-only' && ok "  … it keeps the #227 merge-only path" || fail "single approved card lost merge-only: $(prompt_any | cut -c1-200)"
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; tick
prompt_any | grep -q 'super-review on issue #7' && ok "no approvals: the full review as before" || fail "no approvals but: $(prompt_any | cut -c1-200)"

# ── 5. công tắc tắt: SB_REVIEW_TRAIN=0 → đường cũ từng thẻ
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; approve 71 OWNER "$H2"; approve 72 OWNER "$H3"; SB_REVIEW_TRAIN=0 tick
prompt_any | grep -q 'merge-train' && fail "SB_REVIEW_TRAIN=0 still batched" || ok "SB_REVIEW_TRAIN=0 restores one merge-only worker per card"

# ── 6. thẻ khoá/đã có worker khác không bị kéo vào đợt
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; approve 71 OWNER "$H2"; approve 72 OWNER "$H3"
sleep 300 & OTHER=$!; printf 'PID=%s\nLANE=review\nSTARTED=now\nWORKER_LOG=x\n' "$OTHER" > "$INFLIGHT_DIR/8"; tick
prompt_any | grep -q -- "--prs 70:$H1,72:$H3" && ok "a card already locked by another worker (#8) is left alone: --prs 70:H1,72:H3" || fail "locked card batched: $(prompt_any | cut -c1-300)"
kill "$OTHER" 2>/dev/null; wait "$OTHER" 2>/dev/null

SB_ZOMBIE_GRACE=0  # test kill trực tiếp, không chờ ân hạn (#237)
# ── 7. zombie: thẻ đầu sang Done trong khi các thẻ khác còn ở Review thì worker train sống; hết thẻ Review thì bị thu hồi
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; approve 71 OWNER "$H2"; approve 72 OWNER "$H3"; tick
TP="$REVIEW_PID"
items Done Review Review; check_lane_zombie review Review
kill -0 "$TP" 2>/dev/null && ok "primary card merged (Done), #8 #9 still in Review: the train worker is not killed" || fail "train worker killed while two cards were still in Review"
items Done Done Done; check_lane_zombie review Review
kill -0 "$TP" 2>/dev/null && fail "train worker kept after every card left Review" || ok "every card left Review: the zombie sweep frees the lane"

# ── 9. R2: bộ lọc đợt phải bằng top_card_in_column — thẻ cần người (needs-you) hoặc thẻ cần thiết bị khi không có thiết bị không vào đợt
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; approve 71 OWNER "$H2"; approve 72 OWNER "$H3"
PROJECT_ITEMS_JSON="{\"items\":[$(card 7 Review),$(card 8 Review | sed 's/"labels":\[\]/"labels":["needs-you"]/'),$(card 9 Review)]}"; tick
prompt_any | grep -q -- "--prs 70:$H1,72:$H3" && ok "a needs-you card (#8) stays out of the batch" || fail "needs-you card batched: $(prompt_any | cut -c1-300)"
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; approve 71 OWNER "$H2"; approve 72 OWNER "$H3"
PROJECT_ITEMS_JSON="{\"items\":[$(card 7 Review),$(card 8 Review | sed 's/"labels":\[\]/"labels":["needs-device"]/'),$(card 9 Review)]}"
NO_DEVICE=true; tick; NO_DEVICE=false
prompt_any | grep -q -- "--prs 70:$H1,71:$H2,72:$H3" && ok "needs-device is not held in Review (same as top_card_in_column): #8 stays in the batch" || fail "needs-device card dropped from Review batch: $(prompt_any | cut -c1-300)"

# ── 10. R3: nhiều lock cùng PID (worker train) khi runner khởi động lại = MỘT worker nhận lại, không N mục REVIEW_EXTRA
reset; items Review Review Review
bash -c 'sleep 300; : "Run one merge-train worker on issues #7, #8, #9 (PRs 70,71,72) for super-board run"' & TW=$!
sleep 1
for i in 7 8 9; do printf 'PID=%s\nLANE=review\nSTARTED=%s\nWORKER_LOG=x\n' "$TW" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/$i"; done
adopt_live_locks
{ [ "$REVIEW_PID" = "$TW" ] && [ -z "$REVIEW_EXTRA" ]; } && ok "one train worker with three locks: adopted once, no extra slots (pid=$REVIEW_PID extra='$REVIEW_EXTRA')" || fail "adoption: REVIEW_PID=$REVIEW_PID REVIEW_EXTRA='$REVIEW_EXTRA' (want $TW and none)"
[ -f "$INFLIGHT_DIR/8" ] && [ -f "$INFLIGHT_DIR/9" ] && ok "  … the locks of #8 #9 are kept" || fail "locks of the batch were dropped"
kill "$TW" 2>/dev/null; wait "$TW" 2>/dev/null; REVIEW_PID=""; REVIEW_EXTRA=""

# ── 11. R4: đợt co về 1 thẻ sau claim → đường merge-only (không train 1 PR), có log
reset; items Review Review Review; prs "$H1" "$H2" "$H3"; approve 70 OWNER "$H1"; approve 71 OWNER "$H2"; approve 72 OWNER "$H3"
eval "$(declare -f try_claim_assignee | sed '1s/.*/orig_try_claim_assignee ()/')"
try_claim_assignee() { case "$1" in 8|9) return 1 ;; esac; orig_try_claim_assignee "$@"; }
tick
prompt_any | grep -q 'merge-train' && fail "a batch of one still ran the train" || ok "batch shrank to one card: no train"
prompt_any | grep -q 'merge-only' && ok "  … it runs the merge-only path for #7" || fail "shrunk batch has no merge-only: $(prompt_any | cut -c1-200)"
grep -q 'train shrank' "$TMP/log" && ok "  … and logs that the train shrank" || fail "no 'train shrank' log: $(tr '\n' '|' < "$TMP/log")"
eval "$(declare -f orig_try_claim_assignee | sed '1s/.*/try_claim_assignee ()/')"

# ── 8. hợp đồng viết: run.md nói runner gom đợt và worker route từng dòng train-result:
grep -q 'one merge-train worker' "$ROOT/.claude/skills/super-board/references/run.md" \
  && ok "run.md documents the runner-batched train worker" || fail "run.md does not document the runner-batched train worker"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
