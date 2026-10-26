#!/usr/bin/env bash
# super-board-merge-gate.sh — take the merge mutex, prove the branch still works
# against the base as it is RIGHT NOW, then merge. Release either way.
#
# WHY THIS EXISTS, MEASURED
#
# GitHub's `mergeable: MERGEABLE` / `mergeStateStatus: CLEAN` answers one
# question: does the text conflict? It says nothing about whether the branch
# still compiles against the base it is about to land on. On 2026-08-20 that gap
# was hit twice in one session on the same repo:
#
#   PR #89 read MERGEABLE/CLEAN and failed `tsc` against current `staging`,
#   because a PR that merged after #89 was tested had added a member to a shared
#   interface. Eleven test files that git merged without a single conflict marker
#   no longer typechecked. Merging on GitHub's word would have turned the base
#   branch red.
#
# Nothing textual conflicted. Nothing was wrong with either branch. The two facts
# were simply established at different times, and only one of them was rechecked.
#
# WHY THE CHECK IS INSIDE THE LOCK, NOT BEFORE IT
#
# A check that runs before the mutex proves the branch was good against a base
# that another lane may replace while this one waits its turn — which is exactly
# the stale-approval shape above, reintroduced one level down. Inside the lock,
# nothing can move the base between the proof and the merge.
#
# The cost is one verification run serialised per merge. The alternative, paid
# once, is a red base branch and every lane after it bouncing on someone else's
# failure.
#
# WHY A DIRECTORY LOCK RATHER THAN THE ORCHESTRATOR'S PROMISE CHAIN
#
# The previous mutex lived in the wave workflow as a JS promise chain, which
# serialised the WHOLE Review lane — reading the diff, rerunning the suite and
# the truth-check all queued behind one card, not just the merge. It also could
# not be seen by the `claude-p` backend or by a second orchestrator on another
# machine. `mkdir` is atomic on every POSIX filesystem, so the lock is visible to
# anything that can see the repo.
#
# CONFIG
#
#   verify_commands: ["cd server && npm run typecheck", "cd server && npm test"]
#
# Missing, empty, or whitespace-only commands halt with exit 9 before locking or
# reading GitHub. Configure the owning project's checks; this gate invents none.
#
# Usage:
#   super-board-merge-gate.sh --config <config.json> --pr <number>
#                             [--expect-head <sha>] [--subject <title>] [--body-file <md>]
#                             [--lock-timeout 1800] [--stale-after 5400] [--dry-run]
#                             [--preflight] [--standalone]
#
# MERGE QUEUE (Pha 2, 26/10): merge train cũ chạy 0 lần trên 73 PR vì reviewer/builder tự gọi gate này. Khi merge queue bật
# (config `merge_queue.enabled == true`, hoặc SB_MERGE_QUEUE=1; SB_MERGE_QUEUE=0 luôn tắt; và chỉ khi `worker_backend` của config là
# "claude-p" — backend khác luôn coi là tắt), gate chỉ chạy cho super-board-merge-train.sh / super-board-merge-queue.sh
# (SB_MERGE_CALLER=train|queue) hoặc với `--standalone` (/super-review ngoài board; worker của board, SB_BOARD_WORKER=1, không được dùng);
# mọi lời gọi khác thoát 13 trước khi đọc GitHub hay đụng khoá. `--preflight`: chỉ các kiểm rẻ trước verify (head, merge policy, QA
# report, AC, needs-you), không khoá merge, không scratch, không verify/merge; nút duyệt (exit 7/8) chỉ gửi khi queue tắt (queue bật thì
# queue gửi); qua hết in `preflight: ok` và thoát 0, không qua thì thoát đúng mã gate sẽ thoát ở bước đó.
#
# `--expect-head` is the PR head commit the Reviewer actually reviewed and
# tested (its `headRefOid` when review passed). The gate pins everything to one
# commit: it verifies that commit, and merges with `--match-head-commit`, so a
# push that lands after review — or during verification — cannot ride in on
# evidence gathered for a different commit. Without the flag the gate pins the
# head it reads on entry and warns.
#
# `--subject` / `--body-file` set the squash commit message (writing-standard.md
# § 1): subject = the PR title (`🐛 [fix] receipts: …`), body = the commit bullets
# plus `Closes #N`. Without them GitHub writes its own message.
#
# `--lock-timeout` is how long THIS caller waits for its turn. `--stale-after` is
# how old a lock must be before it is presumed abandoned. They are deliberately
# two numbers: collapsing them means a caller that waits 20 minutes will reap a
# lock legitimately held for 20 minutes by a slow verification run — which is
# exactly the merge it was waiting politely for.
#
# `--train-receipt <file>` (super-board-merge-train.sh): lines `<head sha> <tree sha>`. The train verified the combined tree of several
# PRs once; when this gate's clean merge of the base and the PR head produces exactly the tree recorded for that head, the proof
# already exists and verification is skipped. Any other tree (the base moved, the head changed) verifies as usual.
#
# Exit codes, all meaningful to the caller:
#   0  merged (--preflight: every cheap check passed, stdout `preflight: ok`)
#   13 merge queue is on and the caller is neither the train nor the queue (no --standalone, or --standalone from a board worker
#      with SB_BOARD_WORKER=1): label the PR merge-queue instead; nothing ran, no lock touched
#   11 verification failed after merging the base cleanly into the scratch tree —
#      rebasing changes nothing: back to Build to fix the failing verify (the gate
#      quotes its last KẾT LUẬN/VERDICT line), NOT a rebase pass, NOT a Blocked card
#      — also when the newest `[qa] [report]` comment still has a non-empty `❌ Not done:` line, or a `- [x]` AC of the PR body has
#      no `↳ <proof>` line (super-board-qa-report.py, #364); stdout lists each `qa-report: <reason>`
#   3  PR is closed without a merge; no merge attempted
#   4  could not take the lock within the timeout
#      — or the merge call failed while GitHub still shows the PR OPEN at the verified head (nothing merged; next wave retries)
#   5  the base could not be merged in (real conflict) — needs a rebase pass
#   1  could not read the PR head, resolve origin/<base>, or create the scratch
#      worktree. Not a conflict and not a rebase pass (the lane treats only 2 and 5
#      as a rebase pass).
#   6  the PR head is not the commit that was reviewed — review evidence is void,
#      the card goes back to Review (not Blocked, not a rebase pass)
#   7  (also: the QA report / AC checker could not decide — metadata unreadable or checker crashed: `human-gate: qa-report — …`)
#   7  merge policy says a human merges this one (money / auth / destructive
#      schema, a diff over auto_max_lines — default 400, "big PR — please
#      review" — or merge_policy.default "human"). Stdout lists each
#      `human-gate: <category> — <evidence>`. Nothing ran, nothing merged; the
#      card → Blocked with the 🙋 template: the human reviews and merges it, or
#      comments "done" after its pinned request to approve — the next wave re-runs
#      the gate, which then skips the policy check and merges.
#   9  verification-readiness: repair config.verify_commands (or the DevKit install
#      the scratch tree lacks: no post-fix-gate.py there) and restart; preserve
#      card/worktree/approval state. Never bounce to Build or retry a rebase.
#   79 required GitHub evidence unavailable: local run halt; preserve card and
#      approval state, stop dispatch, and explicitly restart after diagnosis.
#   8  🙋 needs you — the PR has migrations for a database the robot may not
#      touch (merge_policy → migrations.allowed_envs), an allowed migrate command
#      failed, or a human-only step is declared (`needs-you:` line in the PR body,
#      or migrations.human_steps). Stdout lists the exact commands as
#      `needs-you: <command>` lines. Card → Blocked with the 🙋 template; once the
#      current request has verified trusted-human approval, the gate re-runs and
#      merges.
#
# MERGE POLICY AND MIGRATIONS (config, all optional — defaults shown in
# references/config-schema.json)
#
#   merge_policy: { default: "auto"|"human", auto_max_lines: 400, size_exclude,
#                   always_human: { <category>: {labels, paths, keywords} } }
#   migrations:   { globs, allowed_envs, target_env, commands: {<env>: cmd},
#                   human_steps }
#
# Detection reads the PR's labels, changed paths and the diff's ADDED lines
# (keywords, case-insensitive). The policy is checked before verification — a
# card a human will merge does not need the gate's build proof spent on it —
# and migrations run after verification, inside the lock, right before the
# merge. `--dry-run` reports both and runs neither.
set -euo pipefail
# Fixed read commands: a malformed payload is GitHub's, so it halts (#32).
export SB_GITHUB_READ_STRICT=1
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GITHUB_READ="$HERE/super-board-github-read.py"

CONFIG=""; PR=""; LOCK_TIMEOUT=1800; STALE_AFTER=""; DRY=0; EXPECT_HEAD=""; SUBJECT=""; MSG_FILE=""; TRAIN_RECEIPT=""
PREFLIGHT=0; STANDALONE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config)        CONFIG="$2"; shift 2 ;;
    --pr)            PR="$2"; shift 2 ;;
    --expect-head)   EXPECT_HEAD="$2"; shift 2 ;;
    --subject)       SUBJECT="$2"; shift 2 ;;
    --body-file)     MSG_FILE="$2"; shift 2 ;;
    --lock-timeout)  LOCK_TIMEOUT="$2"; shift 2 ;;
    --stale-after)   STALE_AFTER="$2"; shift 2 ;;
    --train-receipt) TRAIN_RECEIPT="$2"; shift 2 ;;
    --dry-run)       DRY=1; shift ;;
    --preflight)     PREFLIGHT=1; shift ;;
    --standalone)    STANDALONE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[ -n "$CONFIG" ] && [ -e "$CONFIG" ] || { echo "config not found: ${CONFIG:-<unset>}" >&2; exit 66; }
[ -n "$PR" ] || { echo "--pr <number> is required" >&2; exit 64; }
[ -z "$MSG_FILE" ] || [ -r "$MSG_FILE" ] || { echo "--body-file not readable: $MSG_FILE" >&2; exit 66; }
# ---- merge queue: một đường merge duy nhất ---------------------------------------
# Đứng trước mọi việc tốn kém (đọc GitHub, khoá, scratch). Config không đọc được thì coi như tắt: đường cũ tự dừng ở bước kiểm config.
MERGE_QUEUE_ON=0
case "${SB_MERGE_QUEUE-}" in
  0) MERGE_QUEUE_ON=0 ;;
  1) MERGE_QUEUE_ON=1 ;;
  *) if jq -e '.merge_queue.enabled == true' "$CONFIG" >/dev/null 2>&1; then MERGE_QUEUE_ON=1; fi ;;
esac
# Chỉ backend claude-p có runner rút hàng (merge_queue_due); backend khác (workflow — mặc định khi thiếu khoá, như super-board-run.sh —
# hoặc codex) luôn coi là tắt, kể cả SB_MERGE_QUEUE=1, để PR không kẹt trong hàng không ai rút. ponytail: hỗ trợ workflow/codex khi có
# Q-schedule.
if [ "$MERGE_QUEUE_ON" -eq 1 ] && ! jq -e '(.worker_backend // "workflow") == "claude-p"' "$CONFIG" >/dev/null 2>&1; then
  MERGE_QUEUE_ON=0
fi
# Queue bật: chỉ train/queue gọi được; --standalone (/super-review ngoài board) đi tiếp, trừ worker do runner phóng (SB_BOARD_WORKER=1):
# worker không được lách hàng đợi bằng --standalone.
QUEUE_REFUSE=0
if [ "$MERGE_QUEUE_ON" -eq 1 ]; then
  if [ "$STANDALONE" -eq 1 ]; then
    [ "${SB_BOARD_WORKER-}" = 1 ] && QUEUE_REFUSE=1
  else
    case "${SB_MERGE_CALLER-}" in train|queue) : ;; *) QUEUE_REFUSE=1 ;; esac
  fi
fi
if [ "$QUEUE_REFUSE" -eq 1 ]; then
  echo "merge-queue: label the PR merge-queue instead of calling the gate directly"
  echo "[merge-gate #${PR}] merge queue is on: only super-board-merge-train.sh / super-board-merge-queue.sh call this gate (or --standalone outside the board, never from a board worker)" >&2
  exit 13
fi
# A lock is presumed abandoned only well past the point a caller stops waiting,
# so a slow-but-alive merge is never stolen from. The floor matters as much as
# the multiple: an impatient caller (say --lock-timeout 6 in a test) would
# otherwise outlive 3x its own wait and reap a lock that was never abandoned.
# Nothing this gate does legitimately exceeds half an hour, so half an hour is
# the earliest anything may be presumed dead.
STALE_FLOOR=1800
if [ -z "$STALE_AFTER" ]; then
  STALE_AFTER=$(( LOCK_TIMEOUT * 3 ))
  [ "$STALE_AFTER" -lt "$STALE_FLOOR" ] && STALE_AFTER="$STALE_FLOOR"
fi

CONFIG_JSON=$(cat "$CONFIG")
printf '%s\n' "$CONFIG_JSON" | python3 "$HERE/super-board-verification-ready.py" --config -
BASE=$(echo "$CONFIG_JSON" | jq -r '.base_branch // "main"')
PROJECT_OWNER=$(echo "$CONFIG_JSON" | jq -r '.project.owner // ""')
PROJECT_NUMBER=$(echo "$CONFIG_JSON" | jq -r '.project.number // ""')
REPO=$(echo "$CONFIG_JSON" | jq -r '.repo.remote // ""' | sed -E 's#^https?://github\.com/##; s#\.git$##')
REPO_PATH=$(echo "$CONFIG_JSON" | jq -r '.repo.path // "."')
export SB_REPO_PATH="$REPO_PATH"
# Read with a while-loop rather than `mapfile`: macOS ships bash 3.2 and every
# other script in this repo runs there, so this one does too.
VERIFY=()
while IFS= read -r line; do
  if [[ "$line" =~ [^[:space:]] ]]; then VERIFY+=("$line"); fi
done < <(echo "$CONFIG_JSON" | jq -r '.verify_commands[] | select(test("\\S"))')

# Defend the shell boundary too: extraction must leave a command to execute.
if [ "${#VERIFY[@]}" -eq 0 ]; then
  echo "verification-readiness: verify_commands yielded no usable shell commands; repair the project config and restart the board." >&2
  exit 9
fi
python3 "$GITHUB_READ" --check

LOCK_DIR="${REPO_PATH}/.claude/super-board/inflight/merge.lock"
mkdir -p "$(dirname "$LOCK_DIR")"

. "$HERE/super-board-verify-flags.sh"
say() { echo "[merge-gate #${PR}] $*" >&2; }
# Notices use the existing bot config. A missing token, or SB_NOTIFY_SKIP=1, does not change the exit.
board_notify() {
  if [ "${SB_NOTIFY_SKIP:-0}" = "1" ]; then
    return 0
  fi
  python3 "$HERE/super-board-notify.py" "$@" || true
}
# Tiêu đề PR cho tin Telegram (người đọc cần biết việc gì, project nào). Lỗi mạng: rỗng, tin về dạng cũ.
pr_title() {
  if [ -n "$SUBJECT" ]; then printf '%s' "$SUBJECT"; return 0; fi
  gh pr view "$PR" ${REPO:+--repo "$REPO"} --json title -q .title 2>/dev/null || true
}
needs_you_notify() {
  # Queue bật: --preflight / --dry-run không gửi (queue gửi đúng một lần ở nhánh exit 7/8). Queue tắt: cả hai gửi như gate cũ. Train gọi
  # --preflight cho mọi PR và PR rớt preflight rời đợt trước lượt --dry-run, nên preflight im lặng = PR exit 7/8 mất nút duyệt (R2).
  if [ "$MERGE_QUEUE_ON" -eq 1 ] && { [ "$PREFLIGHT" -eq 1 ] || [ "$DRY" -eq 1 ]; }; then return 0; fi
  board_notify approve-button --repo "$REPO" --pr "$PR" --head "${HEAD_SHA:-}" --source "$PR" --card "PR #${PR}" --title "$(pr_title)"
}
# clip <n>: stdin gộp về một dòng, giữ tối đa n KÝ TỰ. INSTINCT-173: dưới locale C `cut -c` cắt theo byte và làm vỡ ký tự tiếng Việt
# (văn bản không còn UTF-8, github-read từ chối). Byte không phải UTF-8 trong lỗi của git thành U+FFFD, không bao giờ vỡ giữa ký tự.
clip() { tr '\n\t' '  ' | python3 -I -c 'import sys; sys.stdout.buffer.write(sys.stdin.buffer.read().decode("utf-8", "replace")[:int(sys.argv[1])].encode("utf-8"))' "$1"; }

# ---- the mutex -------------------------------------------------------------
# mkdir is atomic: it succeeds for exactly one caller and fails for the rest.
# The date inside is for a human reading a stuck lock. pid, pgid and host let a waiter
# reap early: a holder killed by a signal never runs its EXIT trap, and waiting out
# stale-after (90 min by default) for a lock nobody holds left PR #176 stuck in Review
# (22/10). Early reap only when ALL hold: the lock was written on this host (a pid says
# nothing about another machine), the holder pid is gone, and no process is left in its
# process group (a SIGKILL to the shell alone leaves a migration or `gh pr merge` child
# running; review of PR #219). A lock without pgid/host (an older gate), EPERM, a reused
# pid or a group shared with a living caller all read as alive and fall back to the age.
holder_gone() {
  local pid pgid host
  pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
  pgid=$(cat "$LOCK_DIR/pgid" 2>/dev/null || true)
  host=$(cat "$LOCK_DIR/host" 2>/dev/null || true)
  [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null && [ -n "$pgid" ] && [ "$pgid" -gt 0 ] 2>/dev/null || return 1
  [ "$host" = "$(hostname)" ] || return 1
  ! kill -0 "$pid" 2>/dev/null && ! ps -p "$pid" >/dev/null 2>&1 || return 1
  ! kill -0 -- "-$pgid" 2>/dev/null || return 1
  # Re-read the pid last: a holder that exits normally while we look frees the lock, and
  # the next gate's fresh lock (a different pid) must not be removed.
  [ "$(cat "$LOCK_DIR/pid" 2>/dev/null || true)" = "$pid" ] || return 1
  HOLDER_GONE="$pid (group $pgid)"
}
acquire() {
  local waited=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if holder_gone; then
      say "reaping a lock whose holder pid ${HOLDER_GONE} is gone (killed before its EXIT trap ran)"
      rm -rf "$LOCK_DIR"; continue
    fi
    # A lock older than the timeout belongs to a process that died holding it.
    # Reaping it is safe because the only thing it guards is a merge, and a dead
    # merge has already either landed or not.
    if [ -f "$LOCK_DIR/at" ]; then
      local age=$(( $(date +%s) - $(cat "$LOCK_DIR/at" 2>/dev/null || echo 0) ))
      if [ "$age" -gt "$STALE_AFTER" ]; then
        say "reaping a lock abandoned ${age}s ago (stale-after ${STALE_AFTER}s) by pid $(cat "$LOCK_DIR/pid" 2>/dev/null || echo '?')"
        rm -rf "$LOCK_DIR"; continue
      fi
    fi
    [ "$waited" -ge "$LOCK_TIMEOUT" ] && return 1
    sleep 5; waited=$(( waited + 5 ))
  done
  date +%s > "$LOCK_DIR/at"; echo "$$" > "$LOCK_DIR/pid"; echo "$PR" > "$LOCK_DIR/pr"
  ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ' > "$LOCK_DIR/pgid" || true; hostname > "$LOCK_DIR/host" 2>/dev/null || true
  return 0
}
# Chỉ xoá khoá còn mang pid của gate này: gate khác đã chiếm nó (coi là bỏ quên) thì đó là khoá đang sống của gate kia.
# Chạy trong trap EXIT dưới set -e: rm hỏng không được đè mã thoát của gate.
release() { if [ "$(cat "$LOCK_DIR/pid" 2>/dev/null || true)" = "$$" ]; then rm -rf "$LOCK_DIR" 2>/dev/null || true; fi; }

# --preflight không lấy khoá merge: chỉ đọc PR và kiểm rẻ (train gọi nó cho từng PR trước khi dựng cây).
if [ "$PREFLIGHT" -eq 1 ]; then
  say "preflight: cheap checks only (no merge lock, no scratch tree, no verify, no merge)"
else
  acquire || { say "could not take the merge lock within ${LOCK_TIMEOUT}s"; exit 4; }
  trap release EXIT
  say "lock taken; verifying against ${BASE} as it is now"
fi

# ---- the freshness check ---------------------------------------------------
# Scratch proves the merge. When that merge is clean and the PR branch is behind
# the base, the gate fast-forwards the merge commit onto the PR branch. It never
# uses --force. A rejected fast-forward stays exit 11 (not a rebase pass).
# Scratch đặt trong .claude/worktrees của main checkout để cùng phân vùng đĩa (st_dev) cho cp -Rc Unity Library.
REPO_ABS=$(cd "$REPO_PATH" && pwd -P)
MAIN_WT=$(git -C "$REPO_ABS" worktree list --porcelain | sed -n '1s/^worktree //p')
BASE_WT=${MAIN_WT:-$REPO_ABS}
SCRATCH=""
if [ "$PREFLIGHT" -ne 1 ]; then
  mkdir -p "$BASE_WT/.claude/worktrees"
  SCRATCH=$(mktemp -d "$BASE_WT/.claude/worktrees/.merge-scratch-XXXXXX")
fi
# SCRATCH rỗng (--preflight): không gọi worktree remove / rm với đường dẫn rỗng.
cleanup() { [ -z "${HB_PID:-}" ] || kill "$HB_PID" 2>/dev/null || true; if [ -n "$SCRATCH" ]; then git -C "$BASE_WT" worktree remove --force "$SCRATCH" 2>/dev/null || true; fi; rm -rf ${SCRATCH:+"$SCRATCH"} ${META:+"$META"} ${DIFF:+"$DIFF"} ${VERIFY_LOG:+"$VERIFY_LOG"} ${AC_DIR:+"$AC_DIR"} || true; release; }
trap cleanup EXIT

# ---- the head guard --------------------------------------------------------
# Review evidence belongs to one commit. If the branch moved after the Reviewer
# passed it, the tests it reran and the diff it read describe something else.
pr_head() { python3 "$GITHUB_READ" --kind head -- pr view "$PR" ${REPO:+--repo "$REPO"} --json headRefName,headRefOid \
              -q '.headRefName + " " + .headRefOid'; }
HEAD=$(pr_head) || exit $?
read -r HEAD_REF HEAD_SHA <<<"$HEAD"
[ -n "${HEAD_SHA:-}" ] || { say "could not read the PR head from GitHub"; exit 1; }
pr_state() { python3 "$GITHUB_READ" --kind merge-state -- pr view "$PR" ${REPO:+--repo "$REPO"} --json state,mergeCommit,headRefOid; }
STATE=$(pr_state) || exit $?
if [ "$(echo "$STATE" | jq -r .state)" = MERGED ]; then
  say "already merged; no verification, migration, or merge is repeated"
  exit 0
fi
[ "$(echo "$STATE" | jq -r .state)" = OPEN ] || { say "PR is closed; refusing merge"; exit 3; }
if [ -n "$EXPECT_HEAD" ]; then
  case "$HEAD_SHA" in
    "$EXPECT_HEAD"*) : ;;
    *) say "head moved: reviewed ${EXPECT_HEAD}, PR head is now ${HEAD_SHA}"
       say "the review evidence is void — send the card back to Review"
       exit 6 ;;
  esac
else
  say "WARNING: no --expect-head; pinning the head read now (${HEAD_SHA}), not the reviewed one"
fi

# ---- merge policy + migration plan ----------------------------------------
# One read of the PR's labels, paths, size and body plus its diff, classified by
# super-board-merge-policy.py (beside this script). Unreadable → human: a policy
# the gate cannot evaluate must not default to "merge".
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Outside $SCRATCH: `git worktree add` below needs that directory empty.
META=$(mktemp); DIFF=$(mktemp)
# Log của lệnh verify cũng ngoài $SCRATCH (18/10, GeelyEx2): trong cây, ở repo không ignore *.log, nó là file chưa track trong dấu vân tay
# cây (bin/tree_fp.py), nên post-fix-gate không mượn được biên nhận --full của worktree đã PASS đúng nội dung đó và chạy lại mọi suite.
VERIFY_LOG=$(mktemp)
python3 "$GITHUB_READ" --kind metadata -- pr view "$PR" ${REPO:+--repo "$REPO"} --json labels,files,additions,deletions,changedFiles,body,comments,author > "$META"
# #364: report QA mới nhất của người đáng tin còn "❌ Not done" nêu tên một AC, hay AC [x] không có dòng bằng chứng ↳: không merge,
# thẻ về Build (exit 11). Checker thoát 2 (metadata không đọc được), crash, hay thoát 1 mà không in dòng "qa-report:" nào là
# KHÔNG quyết định được: cùng đường với policy không đọc được (exit 7, người duyệt), không phải lỗi build của thẻ.
QA_REPORT_RC=0
QA_REPORT_OUT=$(python3 "$HERE/super-board-qa-report.py" --meta "$META" 2>/dev/null) || QA_REPORT_RC=$?
if [ "$QA_REPORT_RC" -ne 0 ]; then
  if [ "$QA_REPORT_RC" -eq 1 ] && printf '%s\n' "$QA_REPORT_OUT" | grep -q '^qa-report: '; then
    printf '%s\n' "$QA_REPORT_OUT"
    say "QA report/AC not clean — nothing merged; the card goes back to Build"
    exit 11
  fi
  echo "human-gate: qa-report — could not evaluate the QA report / AC (checker exit ${QA_REPORT_RC}; metadata unreadable or checker crashed)"
  say "QA report could not be evaluated — a human merges this one"
  exit 7
fi
python3 "$GITHUB_READ" --kind diff --meta "$META" -- pr diff "$PR" ${REPO:+--repo "$REPO"} > "$DIFF"
PLAN=$(python3 "$HERE/super-board-merge-policy.py" --config "$CONFIG" --meta "$META" --diff "$DIFF") || {
  echo "human-gate: policy — could not classify the PR (unreadable metadata)"
  say "merge policy could not be evaluated — a human merges this one"
  # Không gửi nút Approve: chưa có approval-request (policy không đọc được thì không tạo được request).
  exit 7; }

# The label is display-only. A request posted before `done` pins the exact head
# and policy/commands. Re-read trusted approval evidence; never mint it here.
APPROVED=false
APPROVED_HEAD=   # #262: head người đã duyệt, chốt trước khi gate tự đẩy merge commit của main lên nhánh PR
# Gate đẩy Y rồi thoát (verify đỏ, timeout, exit 4): lượt sau đọc head=Y, không đẩy nữa. Biên nhận ghi X theo Y (chỉ gate ghi, khi đã
# duyệt) để lượt sau vẫn nhận ra Y là merge commit của chính gate; commit người đẩy thêm làm head khác Y thì không có biên nhận.
AH_DIR=$(cd "$REPO_PATH" 2>/dev/null && d=$(git rev-parse --git-common-dir 2>/dev/null) && cd "$d" 2>/dev/null && pwd -P) || AH_DIR=
[ -z "$AH_DIR" ] || AH_DIR="$AH_DIR/super-board/approved-merge-heads"
[ -z "$AH_DIR" ] || [ ! -r "$AH_DIR/$HEAD_SHA" ] || APPROVED_HEAD=$(head -1 "$AH_DIR/$HEAD_SHA")
approval_check() {
  APPROVAL=$(python3 "$HERE/super-board-approval.py" --repo "$REPO" --pr "$PR" \
    --head "$HEAD_SHA" ${APPROVED_HEAD:+--approved-head "$APPROVED_HEAD"} --plan "$PLAN") || APPROVAL='{"approved":false}'
  python3 "$GITHUB_READ" --check || exit $?
  APPROVED=$(echo "$APPROVAL" | jq -r '.approved // false')
}
approval_request() {
  python3 "$HERE/super-board-approval.py" --request --repo "$REPO" --pr "$PR" \
    --head "$HEAD_SHA" --plan "$PLAN"
}
HUMAN=$(echo "$PLAN" | jq -r '.human[] | "human-gate: \(.category) — \(.why)"')
if [ -n "$HUMAN" ] || [ "$(echo "$PLAN" | jq '.needs_you | length')" -gt 0 ]; then
  approval_check
fi
if [ -n "$HUMAN" ] && [ "$APPROVED" != true ]; then
  echo "$HUMAN"
  echo "$PLAN" | jq -r '.needs_you[] | "needs-you: " + .'
  approval_request
  say "merge policy: waiting for a trusted human to approve this exact head"
  needs_you_notify
  exit 7
fi

# ---- AC của thẻ (T0054, 24/10) ---------------------------------------------------
# #315 đóng khi AC "cache REG-DK-ALL-01" chưa ai làm: #318 chỉ ghi "AC của thẻ #315", PR #343 nén 7 AC thành 3 dòng
# đã tick, `Closes` đóng thẻ. super-board-ac-check.py đọc body; trước verify (rẻ, builder sửa được):
#   Closes thẻ khác thẻ của nhánh issue-<N>, hoặc khối sb:ac ít dòng hơn số AC của thẻ → exit 11 (về Build viết lại).
# Còn dòng AC chưa tick (đo số sau merge, thiết bị, người): vẫn merge, nhưng Closes → Refs và thẻ ở lại (ac_after_merge).
# Nhánh không mang issue-<N>: bỏ qua. Không có khối sb:ac: chỉ kiểm Closes lạ, không đọc issue (PR tay giữ hành vi cũ).
AC_DIR=$(mktemp -d); AC_CARD=""; AC_UNTICKED=""; AC_HAS_LABEL=false; AC_RECHECK=false; AC_LIGHT=false; extra=()
jq -r '.body // ""' "$META" > "$AC_DIR/pr.md"
# Subject của commit squash cũng đóng thẻ ("Fix #23: …"): --subject, không có thì tiêu đề PR — kiểm cùng message.
AC_SUBJECT="${SUBJECT:-$(pr_title)}"
{ printf '%s\n\n' "$AC_SUBJECT"; [ -z "$MSG_FILE" ] || cat "$MSG_FILE"; } > "$AC_DIR/check-msg.md"
AC_JSON=$(python3 "$HERE/super-board-ac-check.py" --pr-body "$AC_DIR/pr.md" --msg "$AC_DIR/check-msg.md" --branch "$HEAD_REF") \
  || { say "ac-check could not run"; exit 9; }
if [ "$(echo "$AC_JSON" | jq -r .skip)" = false ]; then
  AC_CARD=$(echo "$AC_JSON" | jq -r .card)
  foreign=$(echo "$AC_JSON" | jq -r '.foreign_closes | map("#\(.)") | join(", ")')
  if [ -n "$foreign" ]; then
    echo "ac-check: the PR or its squash message closes ${foreign}, but branch ${HEAD_REF} is card #${AC_CARD} — close only #${AC_CARD}; reference the others with Refs"
    say "a PR closes only its own card: back to Build to fix the closing keywords"
    exit 11
  fi
  # Có khối sb:ac, hoặc không có mà PR vẫn tự Closes thẻ (nén về 0 dòng): đối chiếu với AC của thẻ.
  if [ "$(echo "$AC_JSON" | jq -r '.ac or .closes_own')" = true ]; then
    # #319 (T0054): a title lost to a network error is empty, so it was never checked for Closes: wait for the next wave, do not merge on it.
    # Only a PR that carries AC (sb:ac block or an own Closes): a hand-made PR keeps the old behaviour (case E).
    [ -n "$AC_SUBJECT" ] || { say "could not read the PR title; not merging (a squash subject nobody checked for Closes)"; exit 4; }
    python3 "$GITHUB_READ" --kind issue -- issue view "$AC_CARD" ${REPO:+--repo "$REPO"} --json number,title,body,labels > "$AC_DIR/issue.json"
    jq -r '.body // ""' "$AC_DIR/issue.json" > "$AC_DIR/issue.md"
    jq -e 'any(.labels[]?; (.name | ascii_downcase) == "ac-open")' "$AC_DIR/issue.json" >/dev/null && AC_HAS_LABEL=true
    extra=()
    # "AC của thẻ #X": các AC của #X tính vào thẻ này. Danh sách #X lấy từ AC của chính thẻ (lần gọi có --issue-body; lần đầu
    # chưa có body nên luôn rỗng — OCR 24/10). Đọc #X thường, không qua github-read: không đọc được thì ac-check vẫn tính nó
    # ít nhất 1 AC, không đáng halt cả board.
    AC_JSON=$(python3 "$HERE/super-board-ac-check.py" --issue-body "$AC_DIR/issue.md" \
      --pr-body "$AC_DIR/pr.md" --msg "$AC_DIR/check-msg.md" --branch "$HEAD_REF") || { say "ac-check could not run"; exit 9; }
    for x in $(echo "$AC_JSON" | jq -r '(.indirect // [])[]'); do
      gh issue view "$x" ${REPO:+--repo "$REPO"} --json body -q '.body' > "$AC_DIR/x$x.md" 2>/dev/null || : > "$AC_DIR/x$x.md"
      extra+=(--extra-issue-body "$x=$AC_DIR/x$x.md")
    done
    AC_JSON=$(python3 "$HERE/super-board-ac-check.py" --issue-body "$AC_DIR/issue.md" ${extra[@]+"${extra[@]}"} \
      --pr-body "$AC_DIR/pr.md" --msg "$AC_DIR/check-msg.md" --branch "$HEAD_REF") || { say "ac-check could not run"; exit 9; }
    if [ "$(echo "$AC_JSON" | jq -r .collapsed)" = true ]; then
      echo "ac-check: card #${AC_CARD} has $(echo "$AC_JSON" | jq -r .issue_ac) acceptance criteria (cards it refers to included) but the PR's sb:ac block lists $(echo "$AC_JSON" | jq -r .pr_ac) — one line per criterion, each ticked with its own proof or left unticked with the reason"
      say "AC collapsed into fewer lines than the card has: back to Build to rewrite the sb:ac block"
      exit 11
    fi
    AC_UNTICKED=$(echo "$AC_JSON" | jq -r '(.unticked // [])[] | "- " + .')
    AC_RECHECK=true
  else
    # A card branch whose PR carried no AC claim when the gate started (a hand-made PR, case E/K): verify can still outlast an edit that adds one,
    # or a foreign Closes. Recheck it too, lightly (W8, OCR 25/10).
    AC_LIGHT=true
  fi
fi

# ---- chờ máy bớt tải trước verify ------------------------------------------------
# 19/10: verify --full chạy lúc tải 1 phút ~60 (5 board cùng build), REG-DK-ALL-01 của PR #87 chọn 127 test và quá 900 s, thẻ #12
# quay về Ready mãi. Chờ tải xuống dưới SB_MERGE_LOAD_MAX, không đặt thì `merge_load_max` của config board, thiếu nữa thì capacity
# hold_load (T0052, 8 × lõi, 12 lõi: 96 — verify là việc bắt buộc), capacity vắng thì cùng công thức 8 × số lõi (20/10, người dùng: "dưới 100 thì cho chạy" — máy tải 45–86 cả ngày, 2 × lõi = 24 không bao giờ đạt nên PR nào cũng chờ hết giờ chờ); tối
# đa SB_MERGE_LOAD_WAIT_S, không đặt thì
# `merge_load_wait_s` của config board (thiếu = 0 = không chờ: board tự bật; test dựng config tạm không có khoá nên không chờ, và
# không phải đặt biến trong thư viện test dùng chung — sửa file đó kéo cả 291 test DevKit vào REG-DK-ALL-01, 19/10).
# Hết giờ vẫn verify như cũ, không bỏ bước nào. Chờ trong khoá, sau các lối ra nhanh (đã merge, đóng, head đổi,
# cần người) và TRƯỚC khi fetch/chốt base: verify chạy trên base mới nhất, không phải base của 15 phút trước. Head đổi lúc chờ thì
# scratch dựng từ head cũ và `gh pr merge --match-head-commit` từ chối. Mốc "at" của khoá được làm mới mỗi lượt poll.
# ponytail: gate khác xếp hàng ở acquire có thể hết LOCK_TIMEOUT (1800 s) và thoát 4 (giữ ở Review, wave sau thử lại) khi chờ lâu;
# chấp nhận được vì verify dưới tải cao cũng đỏ, đổi sang hàng đợi có thứ tự khi nhiều PR cùng repo hay kẹt ở exit 4.
# SB_MERGE_LOAD_FILE: móc test, đọc tải từ file thay cho os.getloadavg().
load_now() {
  if [ -n "${SB_MERGE_LOAD_FILE:-}" ]; then tr -d '[:space:]' < "$SB_MERGE_LOAD_FILE" 2>/dev/null || true
  else python3 -c 'import os; print(int(os.getloadavg()[0]))' 2>/dev/null || true; fi
}
wait_for_load() {
  local max="${SB_MERGE_LOAD_MAX:-}" cap="${SB_MERGE_LOAD_WAIT_S:-}" poll="${SB_MERGE_LOAD_POLL_S:-30}" waited=0 load nap
  [ -n "$cap" ] || cap=$(printf '%s\n' "$CONFIG_JSON" | jq -r '.merge_load_wait_s // 0' 2>/dev/null || echo 0)
  local max_src="SB_MERGE_LOAD_MAX"
  [ -n "$max" ] || { max=$(printf '%s\n' "$CONFIG_JSON" | jq -r '.merge_load_max // empty' 2>/dev/null || true); max_src="config merge_load_max"; }
  LOAD_WAITED=0
  # LOAD_WAIT_ON=1: gate này đã bật chờ tải (cap > 0 sau kiểm tra) và đọc được tải — chỉ khi đó run_verify_cmd mới đặt
  # DEVKIT_SLOT_LOAD_WAIT_S=0 (OCR 21/10: tải không đọc được thì gate không chờ, bên trong tự chờ tải).
  LOAD_WAIT_ON=0
  [ "$DRY" -eq 1 ] && return 0
  # --preflight không giữ khoá: không chờ, không ghi mốc "at" vào khoá có thể là của gate khác.
  [ "$PREFLIGHT" -eq 1 ] && return 0
  # Tối đa 6 chữ số (không tràn số); 10# đọc 08 là tám (không có nó bash đọc bát phân và set -e dừng gate).
  [[ "$cap" =~ ^[0-9]{1,6}$ ]] || { say "SB_MERGE_LOAD_WAIT_S='${cap}' is not a number of seconds; not waiting for the load"; return 0; }
  cap=$((10#$cap)); [ "$cap" -gt 0 ] || return 0
  # Khoá được làm mới lúc chờ nên không bao giờ "bỏ quên": giữ việc chờ dưới nửa LOCK_TIMEOUT để gate xếp hàng còn lượt.
  if [ "$cap" -gt $(( LOCK_TIMEOUT / 2 )) ]; then
    say "SB_MERGE_LOAD_WAIT_S=${cap} is over half the lock timeout; waiting at most $(( LOCK_TIMEOUT / 2 ))s"
    cap=$(( LOCK_TIMEOUT / 2 )); [ "$cap" -gt 0 ] || return 0
  fi
  if [[ "$poll" =~ ^[0-9]{1,6}$ ]] && [ $((10#$poll)) -gt 0 ]; then poll=$((10#$poll))
  else say "SB_MERGE_LOAD_POLL_S='${poll}' is not a positive number; polling every 30s"; poll=30; fi
  if [[ "$max" =~ ^[0-9]{1,6}$ ]] && [ $((10#$max)) -gt 0 ]; then max=$((10#$max))
  else
    [ -n "$max" ] && say "${max_src}='${max}' is not a positive number; using the capacity hold load"
    # T0052: ngưỡng của việc bắt buộc capacity hold_load (8 × lõi, 12 lõi: 96, cùng ngưỡng với heavy_slot; busy_load 36 chỉ cho
    # worker tùy chọn của runner); capacity vắng, lỗi hay in rác thì cùng công thức 8 × số lõi (review 23/10: 2 × lõi cũ = 24 không
    # bao giờ đạt trên máy này, mọi PR lại chờ hết merge_load_wait_s — đúng lỗi T0052 sửa).
    max=$("${SB_CAPACITY:-$HERE/super-board-capacity.py}" hold_load 2>/dev/null) || max=""
    if [[ "$max" =~ ^[0-9]{1,6}$ ]] && [ $((10#$max)) -gt 0 ]; then max=$((10#$max))
    else max=$(( $(python3 -c 'import os; print(os.cpu_count() or 4)' 2>/dev/null || echo 4) * 8 )); fi
  fi
  while :; do
    # Khoá được giữ cả lúc chờ: làm mới mốc "at" để gate khác không coi nó là khoá bỏ quên. Ghi hỏng không phải lý do bỏ verify.
    # Ghi qua file tạm rồi mv: gate khác đọc `at` giữa lúc `>` cắt file thì nhận chuỗi rỗng và $(( )) lỗi cú pháp.
    { date +%s > "$LOCK_DIR/at.$$" && mv -f "$LOCK_DIR/at.$$" "$LOCK_DIR/at"; } 2>/dev/null \
      || say "could not refresh the merge lock stamp ${LOCK_DIR}/at"
    load=$(load_now)
    [[ "$load" =~ ^[0-9]{1,6}$ ]] || { say "cannot read the machine load ('${load}'); verifying without waiting"; LOAD_WAIT_ON=0; return 0; }
    load=$((10#$load)); LOAD_WAIT_ON=1
    if [ "$load" -lt "$max" ]; then
      [ "$waited" -gt 0 ] && say "load ${load} after ${waited}s; verifying"
      return 0
    fi
    [ "$waited" -ge "$cap" ] && { say "load still ${load} after ${waited}s; verifying anyway"; return 0; }
    [ "$waited" -eq 0 ] && say "waiting for load ${load} to drop below ${max} before verify (at most ${cap}s)"
    nap=$(( cap - waited < poll ? cap - waited : poll ))
    sleep "$nap"; waited=$(( waited + nap )); LOAD_WAITED=$waited
  done
}
# #288: biên nhận của merge train đã chứng minh đúng cây này thì verify bị bỏ, nên không chờ tải: mỗi PR của đợt từng chờ tới
# merge_load_wait_s để rồi không chạy gì. Cây dự kiến = merge-tree(base, head), đúng cây train ghi (và cây merge scratch bên dưới).
SKIP_LOAD_WAIT=0
if [ "$DRY" -ne 1 ] && [ "$PREFLIGHT" -ne 1 ] && [ -n "$TRAIN_RECEIPT" ] && [ -r "$TRAIN_RECEIPT" ]; then
  PRE_TREE=$(awk -v h="$HEAD_SHA" '$1 == h { print $2 }' "$TRAIN_RECEIPT" | head -1)
  if [ -n "$PRE_TREE" ] && git -C "$REPO_PATH" fetch origin "$HEAD_REF" "$BASE" --quiet 2>/dev/null; then
    [ "$PRE_TREE" != "$(git -C "$REPO_PATH" merge-tree --write-tree "origin/${BASE}" "$HEAD_SHA" 2>/dev/null)" ] || SKIP_LOAD_WAIT=1
  fi
fi
if [ "$SKIP_LOAD_WAIT" -eq 1 ]; then LOAD_WAITED=0; LOAD_WAIT_ON=0; say "train receipt matches the tree to merge: verify will be skipped, not waiting for the load"
else wait_for_load; fi
# Đã chờ thì PR có thể đã đổi: đọc lại head và trạng thái, không verify code không còn là PR.
if [ "${LOAD_WAITED:-0}" -gt 0 ]; then
  NOW_HEAD=$(pr_head) || exit $?
  STATE=$(pr_state) || exit $?
  [ "$(echo "$STATE" | jq -r .state)" = MERGED ] && { say "merged on GitHub while waiting for the load; nothing to repeat"; exit 0; }
  [ "$(echo "$STATE" | jq -r .state)" = OPEN ] || { say "PR closed while waiting for the load; refusing merge"; exit 3; }
  if [ "$NOW_HEAD" != "$HEAD" ]; then
    say "head moved while waiting for the load: ${HEAD_SHA} -> ${NOW_HEAD#* }"
    say "the review evidence is void — send the card back to Review"
    exit 6
  fi
fi

git -C "$REPO_PATH" fetch origin "$HEAD_REF" "$BASE" --quiet
# Chốt commit base một lần, merge đúng commit đó: verify đỏ thì đếm "chậm hơn base" theo chính nó. Đọc lại origin/<base> sau vài phút
# verify có thể đã bị phiên khác fetch đi; suy từ HEAD^2 thì sai khi merge là fast-forward lên một merge commit (OCR 18/10).
BASE_SHA=$(git -C "$REPO_PATH" rev-parse --verify -q "origin/${BASE}^{commit}") || {
  say "cannot resolve origin/${BASE} after fetch"; exit 1; }

# T0054: không có --body-file thì GitHub lấy message squash từ các commit của nhánh — từ khoá Closes trong đó cũng đóng thẻ.
# Đọc bằng `git log` trên các ref vừa fetch: Closes thẻ lạ → exit 11; còn AC chưa tick thì log này (đã đổi Closes → Refs) thành
# message squash, giữ danh sách commit và trailer (Co-Authored-By, Test-approved-by).
if [ -n "$AC_CARD" ] && [ -z "$MSG_FILE" ]; then
  git -C "$REPO_PATH" log --reverse --format='* %s%n%n%b' "${BASE_SHA}..${HEAD_SHA}" > "$AC_DIR/log.md" 2>/dev/null || : > "$AC_DIR/log.md"
  LOG_JSON=$(python3 "$HERE/super-board-ac-check.py" --pr-body /dev/null --msg "$AC_DIR/log.md" --branch "$HEAD_REF") || LOG_JSON='{}'
  foreign=$(echo "$LOG_JSON" | jq -r '(.foreign_closes // []) | map("#\(.)") | join(", ")')
  if [ -n "$foreign" ]; then
    # Commit đã push thì builder không sửa được message mà không viết lại lịch sử (force-push bị chặn): exit 11 sẽ lặp.
    # Gate tự dùng log đó làm message squash, từ khoá đóng thẻ khác đổi thành Refs.
    python3 "$HERE/super-board-ac-check.py" --rewrite-closes "$AC_DIR/log.md" --card "$AC_CARD" --foreign >/dev/null
    MSG_FILE="$AC_DIR/log.md"
    say "a commit on ${HEAD_REF} closes ${foreign}; the squash message turns those into Refs (only card #${AC_CARD} may close)"
  fi
  # Chỉ commit tự `Closes #<thẻ>` (body không có sb:ac, không Closes) thì AC chưa được đối chiếu ở trên: thẻ có AC → nén về 0 dòng.
  if [ "$(echo "$LOG_JSON" | jq -r '.closes_own // false')" = true ] && [ ! -s "$AC_DIR/issue.md" ] \
     && [ "$(echo "$AC_JSON" | jq -r '.ac // false')" = false ]; then
    python3 "$GITHUB_READ" --kind issue -- issue view "$AC_CARD" ${REPO:+--repo "$REPO"} --json number,title,body,labels > "$AC_DIR/issue.json"
    jq -r '.body // ""' "$AC_DIR/issue.json" > "$AC_DIR/issue.md"
    n_ac=$(python3 "$HERE/super-board-ac-check.py" --issue-body "$AC_DIR/issue.md" --pr-body /dev/null --msg "$AC_DIR/log.md" \
      --branch "$HEAD_REF" | jq -r '.issue_ac // 0')
    if [ "${n_ac:-0}" -gt 0 ]; then
      echo "ac-check: a commit on ${HEAD_REF} closes card #${AC_CARD} (${n_ac} acceptance criteria) but the PR has no sb:ac block — list every criterion in it, one line each"
      say "AC collapsed into fewer lines than the card has: back to Build to rewrite the sb:ac block"
      exit 11
    fi
  fi
fi

# ---- --preflight dừng ở đây: phần sau là scratch + verify + migrate + merge ------------------------------------------------------
# Bước chỉ người làm (needs_you của policy: migration ngoài allowed_envs, human_steps, dòng needs-you: trong body) gate thường báo SAU
# verify (exit 8, khối migrations bên dưới); preflight báo ngay để train không verify một PR sẽ dừng ở exit 8. Lệnh migrate của env được
# phép không chạy trong preflight.
if [ "$PREFLIGHT" -eq 1 ]; then
  if [ "$(echo "$PLAN" | jq '.needs_you | length')" -gt 0 ] && [ "$APPROVED" != true ]; then
    echo "$PLAN" | jq -r '.needs_you[] | "needs-you: " + .'
    approval_request
    say "preflight: 🙋 needs you before this merges"
    needs_you_notify
    exit 8
  fi
  echo "preflight: ok"
  exit 0
fi

git -C "$REPO_PATH" worktree add --detach "$SCRATCH" "$HEAD_SHA" --quiet 2>/dev/null || {
  say "could not create a scratch worktree for ${HEAD_REF}@${HEAD_SHA}"; exit 1; }

if ! git -C "$SCRATCH" merge "$BASE_SHA" --no-edit --quiet 2>/dev/null; then
  CONFLICTS=$(git -C "$SCRATCH" diff --name-only --diff-filter=U | tr '\n' ' ')
  say "the base does not merge in cleanly — conflicts: ${CONFLICTS}"
  say "this is a rebase pass for the Builder lane, not a Blocked card"
  exit 5
fi

# Nhánh chậm hơn base nhưng merge scratch sạch: đẩy fast-forward lên đúng nhánh PR
# rồi mới verify. Timeout phía dưới vẫn thử lại một lần. Không --force.
MERGED_SHA=$(git -C "$SCRATCH" rev-parse HEAD)
TRAIN_PROVED=0; TREE_PROVED=0
if [ -n "$TRAIN_RECEIPT" ] && [ -r "$TRAIN_RECEIPT" ]; then
  TRAIN_TREE=$(awk -v h="$HEAD_SHA" '$1 == h { print $2 }' "$TRAIN_RECEIPT" | head -1)
  [ -z "$TRAIN_TREE" ] || [ "$TRAIN_TREE" != "$(git -C "$SCRATCH" rev-parse 'HEAD^{tree}')" ] || TRAIN_PROVED=1
fi
# #226 gap 7: biên nhận theo cây gộp. Verify xanh ghi <git common dir>/super-board/verified-trees/<sha256(tree + lệnh verify)>; lượt gate sau
# (vd. lượt trước thoát exit 4 sau verify) trên đúng cây gộp và đúng bộ lệnh bỏ verify. Base đổi, head đổi hay lệnh đổi: khoá khác, verify đủ.
TREE_RECEIPT=$(sb_verified_tree_receipt "$(git -C "$SCRATCH" rev-parse 'HEAD^{tree}')" "$BASE" "$REPO_PATH" "${VERIFY[@]}")
TREE_KEY=${TREE_RECEIPT##*/}
if [ "$TRAIN_PROVED" -eq 0 ] && [ -n "$TREE_RECEIPT" ] && [ -f "$TREE_RECEIPT" ]; then TRAIN_PROVED=1; TREE_PROVED=1; fi
BEHIND_NOW=$(git -C "$REPO_PATH" rev-list --count "${HEAD_SHA}..${BASE_SHA}" 2>/dev/null || echo 0)
if [ "${BEHIND_NOW:-0}" -gt 0 ] 2>/dev/null && [ "$MERGED_SHA" != "$HEAD_SHA" ]; then
  if [ "$DRY" -eq 1 ]; then
    # --dry-run không ghi lên remote: đầu PR đổi thì --expect-head của lần gọi thật sau đó thoát exit 6 (head moved).
    say "dry run: ${HEAD_REF} is ${BEHIND_NOW} commit(s) behind ${BASE}; the real run would update it to ${MERGED_SHA} (nothing pushed)"
  elif git -C "$REPO_PATH" push origin "${MERGED_SHA}:refs/heads/${HEAD_REF}"; then
    say "updated ${HEAD_REF} in place ${HEAD_SHA} -> ${MERGED_SHA} (clean merge of ${BASE}, no --force)"
    # Duyệt của người gắn với head cũ; merge commit này do chính gate đẩy (cha là head cũ + base) nên duyệt vẫn phủ nó. Commit khác
    # đẩy thêm sau đó làm head khác MERGED_SHA, approval.py báo headChanged và đòi duyệt lại.
    if [ "$APPROVED" = true ]; then
      APPROVED_HEAD=${APPROVED_HEAD:-$HEAD_SHA}
      [ -z "$AH_DIR" ] || { mkdir -p "$AH_DIR" && printf '%s\n' "$APPROVED_HEAD" > "$AH_DIR/$MERGED_SHA"; } \
        || say "could not record the approved head for ${MERGED_SHA}: a second gate run will ask for approval again"
    fi
    HEAD_SHA=$MERGED_SHA
  else
    say "clean merge of ${BASE} could not fast-forward ${HEAD_REF}; not a rebase pass"
    exit 11
  fi
fi

# Populate git-ignored DevKit symlinks so post-fix-gate / REG-WB-CONFIG-01 succeed in SCRATCH
# 19/10: REPO_PATH "." thường là worktree Reviewer, nơi .agents/devkit (bị ignore) không có: chỉ tìm ở đó thì không cài gì và mọi
# verify đỏ vì thiếu post-fix-gate.py (Goods #48, NFH #61, OfficeReader #74/#159). Tìm ở "." rồi ở main checkout. Không lấy bản đi kèm
# gate: thử 19/10, nó cài DevKit vào scratch của repo không có DevKit và test_merge_gate_scratch_clean.sh đỏ (11 file chưa track).
# --no-githooks: cài vào scratch không ghi đè hook git dùng chung của repo.
DK_MAIN=$(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p') || true
DK_INSTALL=""
for c in "$REPO_PATH/universal-agent-devkit" "$REPO_PATH/.agents/devkit" "${DK_MAIN:-$REPO_PATH}/universal-agent-devkit" \
         "${DK_MAIN:-$REPO_PATH}/.agents/devkit"; do
  if [ -f "$c/bin/install.sh" ]; then DK_INSTALL="$c/bin/install.sh"; break; fi
done
if [ -n "$DK_INSTALL" ]; then
  DK_RC=0
  bash "$DK_INSTALL" -t "$SCRATCH" -a claude -y --no-githooks >"$VERIFY_LOG" 2>&1 || DK_RC=$?
  [ "$DK_RC" -eq 0 ] || say "DevKit install into the scratch tree failed (exit ${DK_RC}): $(tail -3 "$VERIFY_LOG" | clip 300)"
  git -C "$SCRATCH" checkout -q -- . 2>/dev/null || true
else
  : >"$VERIFY_LOG"
  say "no DevKit install.sh in ${REPO_PATH} or ${DK_MAIN:-the main checkout}: the scratch tree has no .agents/devkit"
fi
# Config cục bộ bị git ignore (google-services.json, local.properties…) để build trong SCRATCH không đỏ vì môi trường.
bash "$HERE/super-board-scratch-config.sh" "$REPO_PATH" "$SCRATCH" || true
# Lệnh verify gọi post-fix-gate mà scratch không có nó: lỗi môi trường, không phải lỗi PR. Exit 11 sẽ đẩy thẻ về Build/Blocked dù PR
# không có gì sai (OCR 19/10): dừng bằng exit 9 (verification-readiness), giữ nguyên thẻ.
for cmd in "${VERIFY[@]}"; do
  for p in .agents/devkit/bin/post-fix-gate.py universal-agent-devkit/bin/post-fix-gate.py; do
    # Chỉ đường dẫn tương đối gốc scratch, ở ranh giới token: đầu lệnh, sau dấu cách, ngoặc kép / đơn, backtick, ( ) { } ; & | = < >,
    # có hay không "./" (`python3 "./.agents/…"`, `cd x &&./…`, `bash -c ".agents/…"` lọt qua bản so " $p" cũ: OCR #97, issue #98).
    # Một đường dẫn tuyệt đối hay ../ (trước nó là "/") vẫn chạy như cũ. Dấu chấm thành [.]: không phụ thuộc cách bash bỏ ngoặc (OCR).
    re="(^|[[:space:]\"'\`(){};&|=<>])(\./)?${p//./[.]}(\$|[[:space:]\"'\`(){};&|<>])"
    if [[ "$cmd" =~ $re ]] && [ ! -f "$SCRATCH/$p" ]; then
      # Không tiền tố "[merge-gate #N]": dòng phải bắt đầu đúng "verification-readiness:" như dòng exit 9 ở trên
      # (super-board-codex-lane.sh: detail của exit 9 bắt đầu đúng chữ đó).
      echo "verification-readiness: the scratch tree has no ${p} (the DevKit could not be installed there) — an environment problem, not PR #${PR}; the card stays where it is.${DK_INSTALL:+ Install log: $(tail -3 "$VERIFY_LOG" 2>/dev/null | clip 300)}" >&2
      exit 9
    fi
  done
done

# Chạy lệnh verify trong scratch: post-fix-gate.py tự xin quyền chạy cho từng suite, các lệnh verify khác được bọc qua
# super-board-heavy-slot.py. DEVKIT_SLOT_LOAD_WAIT_S=0 CHỈ khi wait_for_load ở trên đã bật chờ tải (LOAD_WAIT_ON=1: cap > 0 theo
# merge_load_max / merge_load_wait_s): tải đã được chờ, bên trong không chờ lần nữa (merge chặn người khác). cap = 0 (config thiếu
# merge_load_wait_s — mặc định của hầu hết board — hay SB_MERGE_LOAD_WAIT_S=0): không đặt gì, bên trong tự chờ tải như mọi lượt (OCR
# 20/10: ép 0 ở đây thì verify của các board đó chạy không xét tải lần nào). Giá trị người gọi đã đặt thì giữ nguyên.
# DEVKIT_SLOT_PRIORITY=merge: đứng đầu hàng đợi khoá Unity (bin/heavy_slot.py),
# và post-fix-gate không chạy lần chạy thật hằng ngày (sentinel) trong merge gate.
# Khoá còn của gate này thì làm mới mốc "at" (như wait_for_load) để mỗi bước dài sau đó được trọn STALE_AFTER — nếu không, gate
# khác coi khoá của một verify + retry dài là bỏ quên, chiếm khoá và merge song song trên base cũ. Khoá đã bị gate khác chiếm (pid
# của nó) thì dừng: không merge, không làm mới mốc khoá của gate kia (release cũng không xoá nó). Exit 4 như lúc không lấy được
# khoá: thẻ ở yên, lượt sau thử lại.
own_lock_or_stop() {
  local holder
  holder=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
  if [ "$holder" != "$$" ]; then
    say "the merge lock now belongs to pid ${holder:-?} (another gate reaped it); stopping without merging"
    exit 4
  fi
  # Ghi mốc hỏng (gate khác vừa rm -rf khoá sau lúc kiểm pid, hay thư mục khoá không ghi được): coi như mất khoá — đi tiếp thì
  # khoá có thể bị coi là bỏ quên giữa chừng. Fail-closed.
  if ! { date +%s > "$LOCK_DIR/at.$$" && mv -f "$LOCK_DIR/at.$$" "$LOCK_DIR/at"; } 2>/dev/null; then
    say "could not refresh the merge lock stamp ${LOCK_DIR}/at; stopping without merging"
    exit 4
  fi
}

# #146: một lần verify dài (chờ heavy slot + suite 900 s) vượt STALE_AFTER thì gate khác reap khoá và merge song song. Trong lúc verify
# chạy, tiến trình nền làm mới mốc "at" mỗi STALE_AFTER/3 giây (tối đa 60 s), CHỈ khi khoá còn mang pid của gate này: khoá đã bị
# gate khác chiếm thì không ghi vào nó. Dừng ngay khi verify xong (stop_heartbeat, cả trong trap EXIT).
# ponytail: giữa lúc đọc pid và mv vẫn có cửa sổ mili giây nếu gate khác reap + mkdir đúng lúc đó; own_lock_or_stop trước merge bắt được.
HB_PID=""
start_heartbeat() {
  local every=$(( STALE_AFTER / 3 )) owner="$$"
  [ "$every" -gt 60 ] && every=60
  [ "$every" -ge 1 ] || every=1
  (
    while sleep "$every"; do
      kill -0 "$owner" 2>/dev/null || exit 0   # gate bị SIGKILL (trap EXIT không chạy): không làm mới khoá của gate đã chết
      [ "$(cat "$LOCK_DIR/pid" 2>/dev/null || true)" = "$owner" ] || exit 0
      { date +%s > "$LOCK_DIR/at.hb$owner" && mv -f "$LOCK_DIR/at.hb$owner" "$LOCK_DIR/at"; } 2>/dev/null || exit 0
    done
  ) >/dev/null 2>&1 &
  HB_PID=$!
  say "heartbeat pid ${HB_PID} refreshes the lock every ${every}s while verify runs"
}
stop_heartbeat() {
  [ -n "$HB_PID" ] || return 0
  kill "$HB_PID" 2>/dev/null || true
  wait "$HB_PID" 2>/dev/null || true
  HB_PID=""
}

run_verify_cmd() {
  local c="$1" rc=0
  own_lock_or_stop
  start_heartbeat
  run_verify_cmd_inner "$c" || rc=$?
  stop_heartbeat
  return "$rc"
}
# CLAUDE_PROJECT_DIR / TARGET_DIR của bên gọi (runner, agent) bị gỡ: post-fix-gate ưu tiên chúng hơn cwd, giữ lại là verify kiểm cây chính thay
# cho cây gộp trong SCRATCH (xanh sai). tests/super-board/test_merge_gate_verify_log_outside.sh.
run_verify_cmd_inner() {
  local c="$1"
  if [[ "$c" == *"post-fix-gate.py"* ]]; then
    ( cd "$SCRATCH" && unset POSTFIX_GATE_FORCE_FULL CLAUDE_PROJECT_DIR TARGET_DIR && export DEVKIT_SLOT_PRIORITY="${DEVKIT_SLOT_PRIORITY:-merge}" \
        DEVKIT_GATE_SLOT_WAIT_S="${DEVKIT_GATE_SLOT_WAIT_S:-1800}" \
        && { [ "${LOAD_WAIT_ON:-0}" -ne 1 ] || export DEVKIT_SLOT_LOAD_WAIT_S="${DEVKIT_SLOT_LOAD_WAIT_S:-0}"; } \
        && DEVKIT_LANG="${DEVKIT_LANG:-vi}" eval "$c" ) >"$VERIFY_LOG" 2>&1
  else
    ( cd "$SCRATCH" && unset POSTFIX_GATE_FORCE_FULL CLAUDE_PROJECT_DIR TARGET_DIR && export DEVKIT_SLOT_PRIORITY="${DEVKIT_SLOT_PRIORITY:-merge}" \
        DEVKIT_GATE_SLOT_WAIT_S="${DEVKIT_GATE_SLOT_WAIT_S:-1800}" \
        && { [ "${LOAD_WAIT_ON:-0}" -ne 1 ] || export DEVKIT_SLOT_LOAD_WAIT_S="${DEVKIT_SLOT_LOAD_WAIT_S:-0}"; } \
        && DEVKIT_LANG="${DEVKIT_LANG:-vi}" python3 "$HERE/super-board-heavy-slot.py" -- bash -c "$c" ) >"$VERIFY_LOG" 2>&1
  fi
}

# Gate post-fix-gate đỏ CHỈ vì suite quá giờ (#142, 18/10: REG-DK-ALL-01 TIMEOUT 900 s khi máy tải cao): exit 1 với kết luận REJECT
# (exit 1 còn là CHƯA XÁC MINH khi project bị gỡ), dòng "Lớp tĩnh … : đạt" / "Static checks … : passed", có ít nhất một dòng suite
# `[ ] TIMEOUT |` và không dòng suite đỏ nào khác. Dòng suite = đầu dòng (sau khoảng trắng) là `[ ] <bất kỳ> |` sau khi bỏ mã màu:
# `TIMEOUT (HANG)` (post-fix-gate #370: quá giờ lúc máy rảnh) cũng là TIMEOUT nên được chạy lại; trạng thái lạ (FAIL_INFRA…) vẫn bị đếm là đỏ khác (fail-closed); dòng đuôi output của suite bắt đầu bằng "|" nên không bị đếm.
# Thiếu dòng lớp tĩnh, kết luận không REJECT hay không có dòng suite nào: không phân loại được → không chạy lại.
gate_red_only_by_timeout() {
  local rc="$1" log_file="$2"
  [ "$rc" -eq 1 ] || return 1
  LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$log_file" 2>/dev/null | LC_ALL=C awk '
    /(KẾT LUẬN CỔNG POST-FIX AUDIT|POST-FIX AUDIT GATE VERDICT):.*REJECT/ { rej = 1 }
    /^[[:space:]]*• (Lớp tĩnh|Static checks) \(.*\): / {
      if (static != 2) static = ($0 ~ /: (đạt|passed)[[:space:]]*$/) ? 1 : 2
    }
    /^[[:space:]]*\[ \] [^|]*\|/ {
      if ($0 ~ /^[[:space:]]*\[ \] TIMEOUT( \(HANG\))?[[:space:]]*\|/) t++; else other++
    }
    END { exit !(rej && static == 1 && t > 0 && other == 0) }'
}

# Kiểm tra lỗi verify có phải do timeout để thử lại đúng 1 lần: exit 124 của chính lệnh verify; gate đã in kết luận thì chỉ khi
# mọi suite đỏ là TIMEOUT (gate_red_only_by_timeout — chữ "timed out" trong output một suite FAIL không tính); lệnh verify khác
# (không có dòng kết luận) thì log chứa TIMEOUT after / quá giới hạn. Lần chạy lại quyết định kết quả.
is_verify_timeout() {
  local rc="$1" log_file="$2" wt_log
  [ "$rc" -eq 124 ] && return 0
  if [ -f "$log_file" ] && grep -aqE "KẾT LUẬN|POST-FIX AUDIT GATE VERDICT" "$log_file" 2>/dev/null; then
    gate_red_only_by_timeout "$rc" "$log_file"
    return
  fi
  if [ -f "$log_file" ] && grep -aqE "TIMEOUT after|quá giới hạn" "$log_file" 2>/dev/null; then
    return 0
  fi
  wt_log="$(git -C "$SCRATCH" rev-parse --absolute-git-dir 2>/dev/null)/postfix-gate/last_output.log"
  [ -f "$wt_log" ] || return 1
  if grep -aqE "KẾT LUẬN|POST-FIX AUDIT GATE VERDICT" "$wt_log" 2>/dev/null; then
    gate_red_only_by_timeout "$rc" "$wt_log"
    return
  fi
  grep -aqE "TIMEOUT after|quá giới hạn" "$wt_log" 2>/dev/null
}
# #251: verify đỏ vì suite đã đỏ SẴN trên origin/<base> không phải lỗi của PR. Suite đỏ = dòng `[ ] FAIL | <id>` trong log gate
# đã REJECT (exit 1) với lớp tĩnh "đạt"; trạng thái khác (TIMEOUT, UNTESTED, NOT RUN, FAIL_INFRA…) hay thiếu dòng kết luận → không phân loại
# được (fail-closed). In ra id suite, mỗi dòng một id; thoát 1 khi không có suite đỏ hoặc không phân loại được.
gate_red_suite_ids() {
  local log_file="$1"
  LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$log_file" 2>/dev/null | LC_ALL=C awk '
    /(KẾT LUẬN CỔNG POST-FIX AUDIT|POST-FIX AUDIT GATE VERDICT):.*REJECT/ { rej = 1 }
    /^[[:space:]]*• (Lớp tĩnh|Static checks) \(.*\): / {
      if (static != 2) static = ($0 ~ /: (đạt|passed)[[:space:]]*$/) ? 1 : 2
    }
    /^[[:space:]]*\[ \] [^|]*\|/ {
      split($0, parts, "|"); st = parts[1]; sub(/^[[:space:]]*\[ \][[:space:]]*/, "", st); sub(/[[:space:]]+$/, "", st)
      if (st != "FAIL") odd = 1
      id = parts[2]; sub(/^[[:space:]]+/, "", id); sub(/[[:space:]].*$/, "", id)
      if (id == "") odd = 1; else ids[++n] = id
    }
    END { if (!(rej && static == 1 && n > 0 && !odd)) exit 1; for (i = 1; i <= n; i++) print ids[i] }'
}

# Chạy lệnh suite trên cây base trong scratch (giới hạn 900 s như gate), trong nhóm tiến trình riêng bị kill cả nhóm khi quá giờ,
# env không có GIT_* / POSTFIX_GATE_FORCE_FULL: 1 = đỏ thật, 0 = xanh, 2 = không chạy được (126/127), 124 = quá giờ.
run_suite_on_base() {
  ( cd "$SCRATCH" && python3 -I -c '
import os, signal, subprocess, sys
env = {k: v for k, v in os.environ.items()
       if not k.startswith("GIT_") and k not in ("POSTFIX_GATE_FORCE_FULL", "CLAUDE_PROJECT_DIR", "TARGET_DIR")}
p = subprocess.Popen(sys.argv[1], shell=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
try:
    rc = p.wait(timeout=900)
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL)
    p.wait()
    sys.exit(124)
sys.exit(2 if rc in (126, 127) else (1 if rc else 0))' "$1" )
}

# Mở thẻ bug riêng cho suite đỏ sẵn trên base (không trùng: bỏ qua nếu đã có thẻ mở nhắc id đó). Lỗi mở thẻ → return 1.
file_red_on_base_card() {
  local id="$1" name="$2" url found
  if [ "$DRY" -eq 1 ]; then say "dry run: would file a bug card for ${id} (red on origin/${BASE})"; return 0; fi
  found=$(gh issue list ${REPO:+--repo "$REPO"} --state open --label bug --search "\"${id}\" in:title" --json number --jq length 2>/dev/null) || found=""
  # Tra cứu lỗi (mạng, rate limit) không phải "chưa có thẻ": mở thẻ ở đây có thể trùng; không chứng minh được → giữ PR đỏ.
  if ! [[ "$found" =~ ^[0-9]+$ ]]; then say "could not look up open cards for ${id}; not filing, PR stays red"; return 1; fi
  if [ "$found" != 0 ]; then
    say "open card for ${id} already exists; not filing another"; return 0
  fi
  url=$(gh issue create ${REPO:+--repo "$REPO"} --label bug \
    --title "🐛 [fix] suite ${id} đỏ sẵn trên ${BASE}" \
    --body "## Problem
Merge gate (PR #${PR}) thấy suite \`${id}\` (${name}) đỏ cả trên cây gộp lẫn trên origin/${BASE}: lỗi có sẵn, không do PR. PR vẫn được merge.

## Context
- **Where:** suite \`${id}\` trong \`.agents/regression_matrix.active.json\`
  - a. Phát hiện ở merge gate PR #${PR} (#251)
- **Who:** Lập trình viên / Agent

## Fix
Tìm nguyên nhân gốc vì sao \`${id}\` đỏ trên ${BASE} và sửa tại đó.

## Acceptance Criteria
- [ ] Test: \`${id}\` xanh trên origin/${BASE}.
- [ ] Gate --full exit 0.

## Risk
🟡 Medium

## Blocked by
- None." 2>/dev/null) || { say "could not file the bug card for ${id}"; return 1; }
  say "filed ${url} for ${id} (red on origin/${BASE})"
  if [ -n "$PROJECT_OWNER" ] && [ -n "$PROJECT_NUMBER" ]; then
    gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$url" >/dev/null 2>&1 \
      || say "could not add ${url} to project ${PROJECT_OWNER}/${PROJECT_NUMBER}; the issue exists"
  fi
  return 0
}

# #251 R1: post-fix-gate.py xét REJECT TRƯỚC các điều kiện CHƯA XÁC MINH (ma trận không tin được, test đã có bị sửa, file không đọc được, test
# mới mồ côi, code chưa có test, không suite nào khớp): khi có suite đỏ, log chỉ còn REJECT và các điều kiện đó chưa từng được đánh giá. Dòng JSON
# cuối của `--json` vẫn mang chúng. Chỉ khi JSON có mặt và mọi điều kiện sạch (trường thiếu = không sạch) mới coi REJECT là chỉ do suite đỏ.
gate_masked_conditions_clean() {
  local line
  line=$(LC_ALL=C grep -a '^{.*"exit_code"' "$1" 2>/dev/null | tail -1) || return 1
  [ -n "$line" ] || return 1
  printf '%s' "$line" | jq -e '(.matrix_problem // "x") == "" and ((.tests_touched // ["x"]) | length) == 0 and ((.unreadable // ["x"]) | length) == 0
    and ((.uncovered // ["x"]) | length) == 0 and ((.orphan_tests // ["x"]) | length) == 0 and (.busy == false) and (.budget_exhausted == false)
    and ((.regression_tests // []) | length) > 0' >/dev/null 2>&1
}

# Verify đỏ (exit $1, log $2, lệnh $3): mọi suite đỏ cũng đỏ trên origin/<base> (scratch reset về BASE_SHA, chạy lệnh trong ma trận
# CỦA BASE, rồi trả về MERGED_SHA)? Có → mở thẻ cho từng suite, return 0 (không REJECT PR). Mọi trường hợp khác → return 1: giữ kết quả
# đỏ như cũ. Fail-closed: lệnh verify ghép nhiều lệnh (`; & | < >` hay xuống dòng: lệnh khác có thể chưa chạy hay đỏ vì PR); suite
# không có trong ma trận của base hay có lệnh khác với cây gộp (PR thêm/sửa suite thì PR chịu); suite xanh, quá giờ hay không chạy
# được trên base.
red_only_on_base() {
  local rc="$1" log_file="$2" vcmd="$3" ids id bcmd mcmd name p all_red=1 sr pfg_cmd_re
  local base_matrix="$SCRATCH/.red-on-base-matrix.json" merged_matrix="$SCRATCH/.agents/regression_matrix.active.json"
  local jqq='[.. | objects | select(.id? == $id and (.command? | type) == "string")] | first // empty'
  local ids_list=() names=() cmds=()
  [ "$rc" -eq 1 ] || return 1
  case "$vcmd" in *[\;\&\|\<\>]*|*$'\n'*) return 1 ;; esac
  # R2: không ghép lệnh là chưa đủ: `./scripts/verify.sh`, `make verify` có thể chạy post-fix-gate rồi bước khác cũng exit 1. Phải là chính
  # post-fix-gate.py (tuỳ chọn biến môi trường VAR=x và python/python3 đứng trước).
  pfg_cmd_re='^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(python3?[[:space:]]+(-[A-Za-z]+[[:space:]]+)*)?[^[:space:]]*post-fix-gate[.]py([[:space:]]|$)'
  [[ "$vcmd" =~ $pfg_cmd_re ]] || return 1
  gate_masked_conditions_clean "$log_file" || { say "the gate log carries no clean --json (or an UNVERIFIED condition hidden by REJECT); red stays red"; return 1; }
  [ -f "$merged_matrix" ] || return 1
  git -C "$SCRATCH" show "${BASE_SHA}:.agents/regression_matrix.active.json" >"$base_matrix" 2>/dev/null || { rm -f "$base_matrix"; return 1; }
  ids=$(gate_red_suite_ids "$log_file") || { rm -f "$base_matrix"; return 1; }
  while IFS= read -r id; do
    bcmd=$(jq -r --arg id "$id" "$jqq | .command" "$base_matrix" 2>/dev/null) || bcmd=""
    mcmd=$(jq -r --arg id "$id" "$jqq | .command" "$merged_matrix" 2>/dev/null) || mcmd=""
    if [ -z "$bcmd" ] || [ "$bcmd" != "$mcmd" ]; then
      say "red suite ${id} is not the same suite in the matrix of origin/${BASE}; the PR owns it"; rm -f "$base_matrix"; return 1
    fi
    name=$(jq -r --arg id "$id" "$jqq | .name // \"\"" "$base_matrix" 2>/dev/null) || name=""
    ids_list+=("$id"); names+=("$name"); cmds+=("$bcmd")
  done <<<"$ids"
  rm -f "$base_matrix"
  git -C "$SCRATCH" reset -q --hard "$BASE_SHA" 2>/dev/null || return 1
  for p in "${!ids_list[@]}"; do
    sr=0; run_suite_on_base "${cmds[$p]}" || sr=$?
    if [ "$sr" -ne 1 ]; then
      all_red=0
      if [ "$sr" -eq 0 ]; then say "${ids_list[$p]} is green on origin/${BASE}: the PR broke it"
      else say "${ids_list[$p]} did not run to a red result on origin/${BASE} (exit ${sr})"; fi
      break
    fi
  done
  # reset --hard trả file đã track; clean bỏ file chưa track do suite base tạo (file bị ignore như DevKit giữ nguyên).
  git -C "$SCRATCH" reset -q --hard "$MERGED_SHA" 2>/dev/null && git -C "$SCRATCH" clean -fdq 2>/dev/null \
    || { say "scratch tree could not be restored to ${MERGED_SHA}"; return 1; }
  [ "$all_red" -eq 1 ] || return 1
  for p in "${!ids_list[@]}"; do
    file_red_on_base_card "${ids_list[$p]}" "${names[$p]}" || return 1
    say "${ids_list[$p]} is red on origin/${BASE} too: not this PR's fault"
  done
  return 0
}

for cmd in "${VERIFY[@]}"; do
  if [ "$TREE_PROVED" -eq 1 ]; then say "verify skipped: this exact merged tree was already verified green with the same commands (receipt ${TREE_KEY:0:12})"; break; fi
  if [ "$TRAIN_PROVED" -eq 1 ]; then say "verify skipped: the merge train already proved this exact tree"; break; fi
  cmd=$(sb_verify_inject_flags "$cmd" "$BASE")
  run_cmd=$(sb_verify_inject_flags "$cmd" "$BASE" json)   # #251 R1: chạy kèm --json, hiển thị/so sánh không có
  # Không bao giờ tự thêm --auto-approve-tests ở đây: duyệt test bị sửa là quyết định của từng board (config của nó).
  say "verify: ${cmd}"
  VRC=0
  run_verify_cmd "$run_cmd" || VRC=$?
  if [ "$VRC" -ne 0 ] && is_verify_timeout "$VRC" "$VERIFY_LOG"; then
    # Suite bị giết giữa chừng có thể để lại file đã track bị sửa, `git add` hay cả commit trong scratch: trả cây và index về đúng
    # commit đã merge (file bị ignore như DevKit, config cục bộ giữ nguyên). Không trả được thì giữ kết quả đỏ của lần 1 (chạy lại
    # trên cây không còn là MERGED_SHA có thể xanh sai).
    if git -C "$SCRATCH" reset -q --hard "$MERGED_SHA" 2>/dev/null; then
      say "verify timed out (exit ${VRC}); retrying once: ${cmd}"
      VRC=0
      run_verify_cmd "$run_cmd" || VRC=$?
    else
      say "verify timed out (exit ${VRC}) but the scratch tree could not be reset; not retrying"
    fi
  fi
  if [ "$VRC" -ne 0 ] && red_only_on_base "$VRC" "$VERIFY_LOG" "$cmd"; then
    say "verify red only on suites that are red on origin/${BASE} too (#251): not rejecting the PR"
    VRC=0
    TREE_RECEIPT=""   # verify tolerated red suites: no receipt, the next gate checks them against the base again
  fi
  if [ "$VRC" -eq 4 ]; then
    # T0056: post-fix-gate thoát 4 kèm JSON .busy == true (hàng đợi gate toàn máy hoặc khoá dự án bận) là tình trạng tạm thời,
    # không phải lỗi code của PR: thoát 4 để thẻ ở lại Review, không đẩy xuống nhánh exit 11.
    BUSY_LINE=$(LC_ALL=C grep -a '^{.*"exit_code"' "$VERIFY_LOG" 2>/dev/null | tail -1 || true)
    if [ -n "$BUSY_LINE" ] && printf '%s' "$BUSY_LINE" | jq -e '.exit_code == 4 and .busy == true' >/dev/null 2>&1; then
      say "verify busy (exit 4, gate queue / project lock busy): ${cmd} — keeping PR #${PR} in Review"
      exit 4
    fi
  fi
  if [ "$VRC" -ne 0 ]; then
    say "FAILED: ${cmd}"
    WT_LOG="$(git -C "$SCRATCH" rev-parse --absolute-git-dir 2>/dev/null)/postfix-gate/last_output.log"
    if [ -f "$WT_LOG" ]; then
      cat "$WT_LOG" >>"$VERIFY_LOG" 2>/dev/null || true
    fi
    # 18/10 (GeelyEx2 #48): log nằm trong git common dir, không trong REPO_PATH ("." thường là một worktree: file chưa track ở đó chặn
    # `worktree remove` ở repo không ignore mẫu này).
    # `|| true`: dưới set -e, một rev-parse hỏng làm script dừng trước exit 11. Đường dẫn tuyệt đối lấy bằng cd + pwd thay cho --path-format
    # (OCR 18/10: git cũ hơn 2.31 không biết cờ này; universal-agent-devkit/scripts/governance/lane_plan.py cũng chạy lại không có nó).
    VLOG_DIR="$(cd "$REPO_PATH" 2>/dev/null && d=$(git rev-parse --git-common-dir 2>/dev/null) && cd "$d" 2>/dev/null && pwd -P || true)"
    VLOG="${VLOG_DIR:+$VLOG_DIR/super-board/last-merge-verify-pr-${PR}.log}"
    { [ -n "$VLOG" ] && mkdir -p "$VLOG_DIR/super-board" && cp "$VERIFY_LOG" "$VLOG"; } 2>/dev/null || VLOG="(not saved)"
    tail -60 "$VERIFY_LOG" >&2
    # Merge vào scratch đã sạch (không conflict): verify đỏ luôn thoát 11 kèm mã thoát và dòng KẾT LUẬN cuối, không đẩy về Build để rebase vô ích.
    VERDICT=$(LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$VERIFY_LOG" | grep -a -E "KẾT LUẬN|VERDICT" | tail -1 \
      | LC_ALL=C sed 's/^[[:space:]]*//' | clip 300 || true)
    WHY="exit ${VRC}: ${VERDICT:-no KẾT LUẬN/VERDICT line, see the log tail above}"
    BEHIND=$(git -C "$REPO_PATH" rev-list --count "${HEAD_SHA}..${BASE_SHA}" 2>/dev/null) || BEHIND=unknown
    if [ "$BEHIND" = unknown ]; then
      say "verify failed (${WHY}); could not tell whether the branch is behind ${BASE} (log saved to ${VLOG})"
    elif [ "$BEHIND" -gt 0 ]; then
      say "verify failed (${WHY}) after clean scratch merge of ${BASE} (${BEHIND} commit(s) behind; log saved to ${VLOG})"
    else
      say "verify failed (${WHY}) on a branch not behind ${BASE} (log saved to ${VLOG})"
    fi
    exit 11
  fi
done
# #288: tiền tố `verified green against` giữ nguyên (proof_gate.sh đọc nó); phần sau nói thật số lệnh đã chạy ở đây.
if [ "$TREE_PROVED" -eq 1 ]; then say "verified green against ${BASE} (0 command(s) run here; a receipt of this exact merged tree and commands exists)"
elif [ "$TRAIN_PROVED" -eq 1 ]; then say "verified green against ${BASE} (0 command(s) run here; the merge train proved this exact tree)"
else say "verified green against ${BASE} (${#VERIFY[@]} command(s))"; fi
if [ "$TRAIN_PROVED" -eq 0 ] && [ -n "$TREE_RECEIPT" ]; then
  mkdir -p "${TREE_RECEIPT%/*}" && : > "$TREE_RECEIPT" || say "could not write the verified-tree receipt ${TREE_RECEIPT}; the next gate verifies again"
  # Biên nhận cũ hơn 14 ngày không còn cây nào khớp: dọn để thư mục không lớn mãi (OCR 24/10).
  find "${TREE_RECEIPT%/*}" -type f -mtime +14 -delete 2>/dev/null || true
fi
own_lock_or_stop   # verify dài có thể đã để gate khác chiếm khoá: không merge song song với nó

python3 "$GITHUB_READ" --check

# ---- migrations (inside the lock, after the build proof) -------------------
# Run the configured migrate command for every allowed env, from the verified
# scratch tree. Collect, never stop early, so a human gets every command at once.
NEEDS=()
while IFS= read -r line; do [ -n "$line" ] && NEEDS+=("$line"); done \
  < <(echo "$PLAN" | jq -r '.needs_you[]')
if [ "$(echo "$PLAN" | jq '.migrations | length')" -gt 0 ]; then
  say "migrations in this PR: $(echo "$PLAN" | jq -r '.migrations | join(" ")')"
  while IFS=$'\t' read -r env cmd; do
    [ -n "$env" ] || continue
    if [ "$DRY" -eq 1 ]; then say "dry run: would migrate ${env}: ${cmd}"; continue; fi
    say "migrate ${env}: ${cmd}"
    python3 "$GITHUB_READ" --check
    if ! ( cd "$SCRATCH" && eval "$cmd" ) >"$SCRATCH/.migrate.log" 2>&1; then
      say "FAILED: migrate ${env}"; tail -20 "$SCRATCH/.migrate.log" >&2
      NEEDS+=("${cmd}   # ${env}: failed in the merge gate — fix, run it, then mark done")
    fi
  done < <(echo "$PLAN" | jq -r '.run[] | [.env, .cmd] | @tsv')
fi
if [ "${#NEEDS[@]}" -gt 0 ]; then
  if [ "$APPROVED" = true ] && [ "$(echo "$PLAN" | jq '.needs_you | length')" -eq "${#NEEDS[@]}" ]; then
    say "a trusted human confirmed the current head and human steps"
  else
    for n in "${NEEDS[@]}"; do echo "needs-you: $n"; done
    approval_request
    say "🙋 needs you before this merges — card → Blocked with the commands above"
    needs_you_notify
    exit 8
  fi
fi

# An approval can be superseded while verification/migrations run. Re-read just
# before merging; GitHub independently pins the code with --match-head-commit.
if [ "$APPROVED" = true ]; then
  # Code remains pinned; body-declared human steps and config can change without
  # a commit. Reclassify them too instead of reusing the old approval scope.
  python3 "$GITHUB_READ" --kind metadata -- pr view "$PR" ${REPO:+--repo "$REPO"} --json labels,files,additions,deletions,changedFiles,body > "$META"
  PLAN=$(python3 "$HERE/super-board-merge-policy.py" --config "$CONFIG" --meta "$META" --diff "$DIFF") || {
    say "human approval scope could not be refreshed"
    needs_you_notify
    exit 7; }
  approval_check
  if [ "$APPROVED" != true ]; then
    approval_request
    say "human approval changed during verification; keep the card Blocked"
    needs_you_notify
    if [ -n "$HUMAN" ]; then exit 7; else exit 8; fi
  fi
fi

# ---- the merge -------------------------------------------------------------
if [ "$DRY" -eq 1 ]; then
  [ -z "$AC_UNTICKED" ] || say "dry run: card #${AC_CARD} has unproven AC — would turn Closes into Refs and keep the card open (ac-open)"
  say "dry run: would squash-merge PR #${PR}"
  exit 0
fi

# #319 (T0054): verify may have run > 900 s and a reviewer may have edited the PR body meanwhile. Take the AC verdict again from the body as it
# is now (the card's own AC and the cards it refers to were read before verify): collapsed or foreign closes → back to Build, a newly unticked
# line → the Refs branch below. Unreadable body → not merging, the next wave tries again.
CUR_TITLE=""
# The light recheck only ADDS a guard to a PR that used to merge with none: when GitHub cannot be read for it, fall back to that old behaviour
# (warn, no exit 4) instead of blocking every hand-made card-branch PR on a read error.
if [ "$AC_LIGHT" = true ]; then
  if gh pr view "$PR" ${REPO:+--repo "$REPO"} --json body -q '.body' > "$AC_DIR/pr.md" 2>/dev/null \
     && { [ -n "$SUBJECT" ] || CUR_TITLE=$(gh pr view "$PR" ${REPO:+--repo "$REPO"} --json title -q .title 2>/dev/null) && [ -n "${CUR_TITLE:-$SUBJECT}" ]; }; then :
  else
    say "warning: could not re-read the PR body/title for the pre-merge recheck; merging on the pre-verify check"
    AC_LIGHT=false; CUR_TITLE=""
  fi
fi
if [ "$AC_RECHECK" = true ] || [ "$AC_LIGHT" = true ]; then
  if [ "$AC_LIGHT" != true ]; then   # light mode read both above
    gh pr view "$PR" ${REPO:+--repo "$REPO"} --json body -q '.body' > "$AC_DIR/pr.md" \
      || { say "could not re-read the PR body before merging; not merging (the AC verdict may be stale)"; exit 4; }
  fi
  # The TITLE is editable during verify too (W7, OCR 25/10): read it again, check it for Closes, and keep it as the squash subject when none was given,
  # so GitHub cannot pick a title nobody checked. A --subject the caller gave was checked before verify and stays.
  if [ -z "$SUBJECT" ]; then
    [ "$AC_LIGHT" = true ] || CUR_TITLE=$(gh pr view "$PR" ${REPO:+--repo "$REPO"} --json title -q .title 2>/dev/null || true)
    [ -n "$CUR_TITLE" ] || { say "could not re-read the PR title before merging; not merging (a squash subject nobody checked for Closes)"; exit 4; }
    { printf '%s\n\n' "$CUR_TITLE"; [ "$AC_LIGHT" = true ] || [ -z "$MSG_FILE" ] || cat "$MSG_FILE"; } > "$AC_DIR/check-msg.md"
  elif [ "$AC_LIGHT" = true ]; then
    : > "$AC_DIR/check-msg.md"
  fi
  if [ "$AC_RECHECK" = true ]; then
    AC_JSON=$(python3 "$HERE/super-board-ac-check.py" --issue-body "$AC_DIR/issue.md" ${extra[@]+"${extra[@]}"} \
      --pr-body "$AC_DIR/pr.md" --msg "$AC_DIR/check-msg.md" --branch "$HEAD_REF") || { say "ac-check could not run"; exit 9; }
  else
    AC_JSON=$(python3 "$HERE/super-board-ac-check.py" --pr-body "$AC_DIR/pr.md" --msg "$AC_DIR/check-msg.md" --branch "$HEAD_REF") \
      || { say "ac-check could not run"; exit 9; }
  fi
  foreign=$(echo "$AC_JSON" | jq -r '.foreign_closes | map("#\(.)") | join(", ")')
  collapsed=$(echo "$AC_JSON" | jq -r '.collapsed // false')
  if [ "$AC_LIGHT" = true ] && [ -z "$foreign" ] && [ "$(echo "$AC_JSON" | jq -r '.ac or .closes_own')" = true ]; then
    # Light mode checks the body and the title only (not MSG_FILE, whose commit log may say Closes #<card> legitimately, case F),
    # so an own Closes or an sb:ac block here is new: the same input at gate start takes the heavy path.
    say "the PR body or title gained an sb:ac block or Closes #${AC_CARD} during verify; its AC were never compared with the card's. Not merging; the next wave retries"
    exit 4
  fi
  # Pin the squash subject to the title just checked, so GitHub cannot pick a later edit (W7).
  [ -z "$CUR_TITLE" ] || [ -n "$SUBJECT" ] || SUBJECT="${CUR_TITLE} (#${PR})"
  if [ -n "$foreign" ] || [ "$collapsed" = true ]; then
    # Each clause only when its own condition holds (OCR 24/10): a foreign Closes alone must not tell Build to rewrite a sb:ac block that is fine.
    msg=""
    [ -n "$foreign" ] && msg="closes ${foreign} (branch is card #${AC_CARD})"
    [ "$collapsed" = true ] && msg="${msg:+$msg / }lists $(echo "$AC_JSON" | jq -r .pr_ac) AC lines but card #${AC_CARD} has $(echo "$AC_JSON" | jq -r .issue_ac)"
    echo "ac-check: the PR body changed during verify and now ${msg}"
    # the hint names only what is wrong too (OCR O2): a foreign Closes is not an sb:ac problem and a collapsed block is not a keyword problem
    hint=""
    [ -n "$foreign" ] && hint="fix the closing keywords"
    [ "$collapsed" = true ] && hint="${hint:+$hint and }rewrite the sb:ac block"
    say "back to Build: ${hint}"
    exit 11
  fi
  AC_UNTICKED=$(echo "$AC_JSON" | jq -r '(.unticked // [])[] | "- " + .')
fi

# T0054: còn dòng AC chưa tick → GitHub không được tự đóng thẻ khi merge. Đổi từ khoá đóng #<thẻ> thành Refs trong body PR
# (gh pr edit, không đổi head) và trong message squash (bản chép; không có --body-file thì message chỉ "Refs #<thẻ>").
# Ghi body hỏng thì không merge: thẻ sẽ bị đóng với AC chưa chứng minh — đúng lỗi này chặn. Lần sau gate chạy lại.
if [ -n "$AC_UNTICKED" ]; then
  # Trước mọi lần ghi lên GitHub: không có subject đã kiểm thì không merge (và không để PR bị sửa dở).
  if [ -z "$SUBJECT" ] && [ -z "$AC_SUBJECT" ]; then
    say "could not read the PR title for the squash subject; not merging (GitHub would use a title nobody checked for Closes)"
    exit 4
  fi
  # Đọc lại body ngay trước khi ghi: verify có thể đã chạy > 900 s, ghi bản cũ sẽ đè sửa đổi của lane khác trong lúc đó.
  gh pr view "$PR" ${REPO:+--repo "$REPO"} --json body -q '.body' > "$AC_DIR/pr.md" \
    || { say "could not re-read the PR body before turning Closes #${AC_CARD} into Refs; not merging"; exit 4; }
  if [ "$(python3 "$HERE/super-board-ac-check.py" --rewrite-closes "$AC_DIR/pr.md" --card "$AC_CARD")" = rewritten ]; then
    gh pr edit "$PR" ${REPO:+--repo "$REPO"} --body-file "$AC_DIR/pr.md" >/dev/null \
      || { say "could not rewrite Closes #${AC_CARD} in the PR body; not merging (the card would close with unproven AC)"; exit 4; }
  fi
  if [ -n "$MSG_FILE" ]; then cp "$MSG_FILE" "$AC_DIR/msg.md"; else cp "$AC_DIR/log.md" "$AC_DIR/msg.md" 2>/dev/null || : > "$AC_DIR/msg.md"; fi
  python3 "$HERE/super-board-ac-check.py" --rewrite-closes "$AC_DIR/msg.md" --card "$AC_CARD" >/dev/null
  grep -q "#${AC_CARD}\b" "$AC_DIR/msg.md" || printf '\nRefs #%s\n' "$AC_CARD" >> "$AC_DIR/msg.md"
  MSG_FILE="$AC_DIR/msg.md"
  # Subject squash: --subject, không có thì tiêu đề PR như GitHub vẫn dùng ("<tiêu đề> (#PR)") — Closes trong đó cũng đổi.
  [ -n "$SUBJECT" ] || SUBJECT="${AC_SUBJECT} (#${PR})"
  printf '%s\n' "$SUBJECT" > "$AC_DIR/subject.md"
  python3 "$HERE/super-board-ac-check.py" --rewrite-closes "$AC_DIR/subject.md" --card "$AC_CARD" >/dev/null
  SUBJECT=$(head -1 "$AC_DIR/subject.md")
elif [ "$AC_HAS_LABEL" = true ]; then
  # Đủ AC: gỡ nhãn TRƯỚC merge — sau merge `Closes` đã đóng issue, runner thấy CLOSED + ac-open sẽ mở lại nó.
  gh issue edit "$AC_CARD" ${REPO:+--repo "$REPO"} --remove-label ac-open >/dev/null 2>&1 \
    && say "card #${AC_CARD}: every AC proven — label ac-open removed" \
    || { say "could not remove label ac-open from #${AC_CARD}; not merging (the runner would reopen the closed card)"; exit 4; }
fi
# Sau merge (cả khi phản hồi merge bị mất mà GitHub xác nhận MERGED): còn AC chưa tick → nhãn ac-open, mở lại nếu đã đóng,
# comment liệt kê, thẻ về Ready, in `ac-open: #N` cho lane. Đủ AC mà nhãn còn → gỡ nhãn. Lỗi ở đây chỉ cảnh báo: đã merge rồi.
ac_after_merge() {
  [ -n "$AC_CARD" ] && [ -n "$AC_UNTICKED" ] || return 0   # đủ AC: nhãn đã gỡ trước merge
  echo "ac-open: #${AC_CARD}"
  gh label create ac-open ${REPO:+--repo "$REPO"} --color FBCA04 --description "PR merged, acceptance criteria not all proven" >/dev/null 2>&1 || true
  gh issue edit "$AC_CARD" ${REPO:+--repo "$REPO"} --add-label ac-open >/dev/null 2>&1 || say "warning: could not label #${AC_CARD} ac-open"
  gh issue reopen "$AC_CARD" ${REPO:+--repo "$REPO"} >/dev/null 2>&1 || true   # đã mở thì gh báo lỗi vô hại
  printf '%s\n' "[merge-gate] [report] ⏳ PR #${PR} merged · AC chưa chứng minh hết — thẻ ở lại" \
    "Did: merge ${HEAD_SHA:0:12}; Closes #${AC_CARD} đổi thành Refs để thẻ không tự đóng" \
    "❌ Chưa chứng minh:" "$AC_UNTICKED" \
    "Next: PR sau của thẻ chép ĐỦ mọi dòng AC vào khối sb:ac — dòng đã chứng minh giữ [x] kèm PR #${PR}, dòng còn lại chứng minh ở PR đó. Dòng chỉ người/thiết bị làm được: block-template 🙋. Thẻ không vào Done khi còn nhãn ac-open." \
    > "$AC_DIR/comment.md"
  gh issue comment "$AC_CARD" ${REPO:+--repo "$REPO"} --body-file "$AC_DIR/comment.md" >/dev/null 2>&1 || say "warning: could not comment on #${AC_CARD}"
  bash "$HERE/super-board-card.sh" --config "$CONFIG" move "$AC_CARD" Ready >&2 || say "warning: could not move #${AC_CARD} to Ready"
  say "card #${AC_CARD} keeps label ac-open: $(printf '%s\n' "$AC_UNTICKED" | grep -c .) AC line(s) not proven — do not close it or move it to Done"
}

# --match-head-commit makes GitHub refuse if anything was pushed after HEAD_SHA,
# including during the verification run above.
python3 "$GITHUB_READ" --check
own_lock_or_stop   # migration / làm mới approval có thể dài: vẫn đúng chủ khoá ngay trước khi merge
if gh pr merge "$PR" ${REPO:+--repo "$REPO"} --squash --delete-branch \
     ${SUBJECT:+--subject "$SUBJECT"} ${MSG_FILE:+--body-file "$MSG_FILE"} \
     --match-head-commit "$HEAD_SHA" 2>&1 | tail -3 >&2; then
  say "merged ${HEAD_SHA}"
  ac_after_merge
  board_notify send --card "PR #${PR}" --repo "$REPO" --title "$(pr_title)" --text "✅ đã merge ${HEAD_SHA}"
  # Dọn sau merge: fast-forward nhánh base local và xoá worktree + nhánh local của CHÍNH thẻ vừa merge
  # (không bao giờ của thẻ khác), để không phải dọn tay. worktree_merge_gate.state là sổ nợ worktree toàn repo
  # của hook DevKit: hook tự dọn sổ đó, gate này không bao giờ xoá.
  # repo.path là "." và Reviewer chạy gate từ worktree issue-<N>-review của nó (HEAD detached): ff phải nhắm main
  # checkout (dòng đầu `git worktree list`), như super-board-post-merge-clean.sh, không phải worktree review.
  MAIN_PATH=$(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p') || true
  [ -n "$MAIN_PATH" ] || MAIN_PATH="$REPO_PATH"
  # Fetch hỏng, bị bỏ qua hay git từ chối ff thì báo kèm lý do của git: base local cũ phải lộ ra, merge vẫn thành công.
  if ! fetch_err=$(git -C "$MAIN_PATH" fetch origin "$BASE" --quiet 2>&1 >/dev/null); then
    say "warning: fetch origin ${BASE} failed in ${MAIN_PATH}; local base may be stale: $(printf '%s' "$fetch_err" | clip 300)"
  fi
  # K13 (OfficeReader PR #143, 18/10): main giữ bản CHƯA commit (file dở, hoặc file chưa track) trùng byte + mode với origin/<base> thì
  # ff / `reset --keep` từ chối dù không gì mất, và main kẹt sau origin. sync_identical <ff|reset>: dùng đúng luật của DevKit
  # `worktree finish` (worktree.py _stage_identical_overlap, 1fa169d: index bằng HEAD, file thường, mode + byte giống hệt; một đường dẫn
  # khác là không stage gì), stage đúng các đường dẫn đó rồi ff / reset lại; hỏng thì trả index các đường dẫn đó về HEAD. 0 = đã dời,
  # in số đường dẫn đã stage. DevKit không có hàm đó (bản cũ) hay không chạy được: 1, hành vi như trước.
  # sync_identical <ff|reset> <đầu nhánh đã chốt>: ngay trước lệnh git, nhánh checkout vẫn phải là $BASE và đầu nhánh vẫn là commit đã
  # chốt (một phiên khác commit trong lúc kiểm thì không dời, trả index về như cũ; `reset --keep` dời nhánh ĐANG checkout).
  # sync_identical check <đầu nhánh>: chỉ chạy chốt va chạm file bị ignore (0 = không va chạm), cho lần `reset --keep` thường (audit 18/10).
  sync_identical() {
    local c rc
    # DevKit đi kèm chính gate trước (code đã review cùng nó), bản ở main checkout sau: worktree Reviewer có thể không có .agents/devkit
    # (OfficeReader, review 18/10). Không DevKit nào: chế độ `check` vẫn chạy (luật va chạm chỉ cần git), stage thì không (hành vi cũ).
    for c in "$HERE/../../universal-agent-devkit" "$HERE/../../.agents/devkit" "$MAIN_PATH/universal-agent-devkit" "$MAIN_PATH/.agents/devkit" ""; do
      if [ -n "$c" ]; then [ -f "$c/scripts/git/worktree.py" ] || continue; elif [ "$1" != check ]; then continue; fi
      python3 - "${c:+$c/scripts/git/worktree.py}" "$MAIN_PATH" "$TARGET_SHA" "$1" "$2" "$BASE" "$PR" <<'PY'
import importlib.util, subprocess, sys, unicodedata
main, target, mode, pinned, base, pr = sys.argv[2:8]
# surrogateescape: một tên file bị ignore không phải UTF-8 (thư mục build/cache) không làm crash bước kiểm (OCR 18/10)
git = lambda *a: subprocess.run(["git", "-C", main, *a], capture_output=True, text=True, errors="surrogateescape")
# File / thư mục / link bị git IGNORE va chạm với một đường dẫn target đổi (cấu hình cục bộ, link node_modules…): ff / `reset --keep` sẽ
# đè nó im lặng. Trước khi stage, bản dở trùng byte làm git từ chối nên vô tình giữ được nó; nay không stage gì, main như cũ (review 18/10,
# A.4). Va chạm = trùng, là cha, hoặc là con của một đường dẫn đổi, so KHÔNG phân biệt hoa thường (ổ macOS); git lỗi = không làm gì.
# ponytail: thư mục ignore là CHA của file target thêm cũng chặn (thừa, an toàn); tách theo nội dung thư mục nếu gặp nhiều.
d = git("diff", "--no-renames", "--name-only", "-z", pinned, target)
ign = git("ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory")
if d.returncode or ign.returncode:
    sys.exit(1)
fold = lambda p: unicodedata.normalize("NFC", p).casefold()   # APFS: không phân biệt hoa thường, NFD và NFC là một tên
changed_raw = [p for p in d.stdout.split("\0") if p]
changed = {fold(p) for p in changed_raw}
near = set(changed)
for p in changed:   # mọi thư mục cha của một đường dẫn đổi
    parts = p.split("/")
    near.update("/".join(parts[:i]) for i in range(1, len(parts)))
for e in (fold(x.rstrip("/")) for x in ign.stdout.split("\0") if x):
    parts = e.split("/")
    if e in near or any("/".join(parts[:i]) in changed for i in range(1, len(parts))):
        sys.exit(4)   # 4 = va chạm thật (để gate báo đúng lý do); lỗi git / python khác = 1
if mode == "check":
    sys.exit(0)
try:   # DevKit chỉ cần từ đây (stage); nạp sau chốt va chạm để `check` không phụ thuộc nó
    spec = importlib.util.spec_from_file_location("devkit_worktree", sys.argv[1])
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    stage = mod._stage_identical_overlap
except Exception:   # noqa: BLE001 — bản DevKit cũ / nạp hỏng: thử bản DevKit kế tiếp (exit 3), không in traceback vào log gate
    sys.exit(3)
# Đã có trong index mà khác HEAD TRƯỚC lần stage này (phiên khác: stage thường, rename — cả hai phía nhờ --no-renames —, hay
# `git add -N`, hiện ra nhờ --ita-visible-in-index): không bao giờ bị trả về HEAD (review 18/10).
staged_now = lambda: git("diff", "--cached", "--no-renames", "--ita-visible-in-index", "--name-only", "-z")
pre = staged_now()
if pre.returncode:
    sys.exit(1)
keep = set(pre.stdout.split("\0")) - {""}
if mode == "reset" and keep:   # `reset --keep` đặt lại CẢ index về target: entry phiên khác (kể cả `add -N`) sẽ rơi (audit 18/10)
    sys.exit(1)
try:
    staged = stage(main, pinned, target)
except Exception:   # noqa: BLE001 — tên không phải UTF-8, git hết giờ, lỗi parse…: trả về HEAD đúng các đường dẫn lần này đã stage
    now = staged_now()
    mine = sorted((set(now.stdout.split("\0")) - keep) & set(changed_raw)) if now.returncode == 0 else []
    if mine:   # bị chặn bởi IDENTICAL_OVERLAP_MAX của stage(): argv không phình theo diff
        git("reset", "-q", "--", *(":(literal)" + p for p in mine))
    sys.exit(1)
if not staged:
    sys.exit(1)
if git("symbolic-ref", "--quiet", "--short", "HEAD").stdout.strip() == base and git("rev-parse", "refs/heads/" + base).stdout.strip() == pinned:
    r = git(*(["merge", "--ff-only", "--no-overwrite-ignore", target] if mode == "ff" else ["reset", "--keep", target]))
    if r.returncode == 0:
        print(len(staged))
        sys.exit(0)
    why = r.stderr.strip()[-200:]
else:
    why = "the checkout changed while it was being checked"
git("reset", "-q", "--", *(":(literal)" + p for p in staged))
print(f"[merge-gate #{pr}] note: staged {len(staged)} identical path(s) but did not move: {why}", file=sys.stderr)
sys.exit(1)
PY
      rc=$?
      [ "$rc" -eq 3 ] && continue
      return "$rc"
    done
    return 1
  }
  # Chốt origin/<base> thành MỘT commit (audit 18/10): một `git fetch` của phiên khác giữa các bước dưới không đổi được đích đã kiểm.
  TARGET_SHA=$(git -C "$MAIN_PATH" rev-parse --verify --quiet "origin/$BASE^{commit}" 2>/dev/null) || TARGET_SHA="origin/$BASE"
  # Chỉ khi main checkout đang ở $BASE: nếu không, ff-only sẽ đẩy nhánh nào đang được checkout.
  if [ "$(git -C "$MAIN_PATH" symbolic-ref --quiet --short HEAD 2>/dev/null)" = "$BASE" ]; then
    # --no-overwrite-ignore: mặc định của merge là ghi đè file bị git ignore (cấu hình cục bộ, link node_modules) ở đường dẫn origin thêm.
    if ! ff_err=$(git -C "$MAIN_PATH" merge --ff-only --no-overwrite-ignore "$TARGET_SHA" 2>&1 >/dev/null); then
      # `--squash` ghi lại các commit của PR thành MỘT commit mới trên origin, còn trunk mode đã đưa chính các commit đó vào base
      # local: hai bên lệch nhau mãi và ff không bao giờ được. Khi gộp base local vào origin/<base> KHÔNG thêm gì (cây gộp = cây
      # origin: base local không giữ việc nào mà origin chưa có, kể cả khi origin còn nhận PR khác trước đó), chỉ cần dời nhánh về
      # origin/<base>: `reset --keep` giữ nguyên sửa chưa commit, không tạo merge commit (luật AGENTS §7.1: main chỉ ff) và tự từ
      # chối nếu chạm file đang sửa. Base local còn commit riêng chưa đẩy (việc của phiên khác), hoặc main đang dở merge /
      # cherry-pick / revert / rebase / am / bisect của phiên khác: để nguyên, vẫn báo cảnh báo (`reset --keep` xoá cả CHERRY_PICK_HEAD,
      # REVERT_HEAD). Đường dẫn trạng thái lấy từ git dir TUYỆT ĐỐI của main (gate thường chạy từ worktree liên kết, cwd khác main).
      # Không bao giờ `merge --abort` (nó huỷ cả merge và phần xung đột đã giải tay của người khác).
      main_gd=$(git -C "$MAIN_PATH" rev-parse --absolute-git-dir 2>/dev/null) || main_gd=""
      busy=""
      for st in MERGE_HEAD SQUASH_MSG CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_LOG; do
        [ -n "$main_gd" ] && [ -e "$main_gd/$st" ] && busy="${busy:+$busy, }$st"
      done
      if [ -z "$main_gd" ]; then
        say "warning: ${BASE} in ${MAIN_PATH} not fast-forwarded; its git dir could not be read, left alone: $(printf '%s' "$ff_err" | clip 200)"
      elif [ -n "$busy" ]; then
        say "warning: ${BASE} in ${MAIN_PATH} not fast-forwarded; ${busy} in progress there, left alone: $(printf '%s' "$ff_err" | clip 200)"
      elif ident_ff=0 && ff_tip=$(git -C "$MAIN_PATH" rev-parse "refs/heads/$BASE" 2>/dev/null) \
           && git -C "$MAIN_PATH" merge-base --is-ancestor "$ff_tip" "$TARGET_SHA" 2>/dev/null \
           && ident_ff=1 && n_ident=$(sync_identical ff "$ff_tip"); then   # chỉ khi ff được về nguyên tắc (base local là tổ tiên origin)
        say "note: ${BASE} in ${MAIN_PATH} fast-forwarded after staging ${n_ident} uncommitted path(s) identical to origin/${BASE} (nothing lost)"
      else
        # Chốt đầu nhánh một lần: mọi so sánh dùng đúng commit này, và chỉ dời nếu ngay trước khi dời đầu nhánh vẫn là nó (một phiên
        # khác commit/ff vào base trước đó thì để nguyên). Còn một khe vài mili-giây giữa kiểm lại và `reset` mà git không có phép
        # so-và-đổi nguyên tử cho trường hợp này: commit lọt vào khe đó vẫn nằm trong reflog.
        local_tip=$(git -C "$MAIN_PATH" rev-parse "refs/heads/$BASE" 2>/dev/null) || local_tip=""
        origin_tree=$(git -C "$MAIN_PATH" rev-parse "$TARGET_SHA^{tree}" 2>/dev/null) || origin_tree=""
        # #309: cwd = $SCRATCH (cleanup() deletes it): a merge driver killed with the gate leaves its .merge_file_* there, never in $MAIN_PATH.
        # --attr-source keeps the repo's merge drivers applying, as `git -C "$MAIN_PATH"` did.
        main_gd=$(git -C "$MAIN_PATH" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || main_gd=""
        merged_tree=""
        [ -z "$main_gd" ] || merged_tree=$(cd "$SCRATCH" && git --git-dir="$main_gd" --attr-source="$TARGET_SHA" merge-tree --write-tree "$TARGET_SHA" "$local_tip" 2>"$SCRATCH/mt.err") || merged_tree=""
        # git 2.38-2.41 có merge-tree --write-tree nhưng không có --attr-source (exit 129, "unknown option"): thử lại không cờ đó (#358).
        if [ -z "$merged_tree" ] && grep -q 'attr-source' "$SCRATCH/mt.err" 2>/dev/null; then
          # Như lệnh chính (#309): cwd = $SCRATCH và --git-dir thay cho cờ -C vào checkout của người dùng (-C đổi cwd về đó,
          # merge driver bị giết sẽ để .merge_file_* ở đó). main_gd chắc có giá trị: lần thử đầu chỉ đỏ vì lỗi attr-source.
          merged_tree=$(cd "$SCRATCH" && git --git-dir="$main_gd" merge-tree --write-tree "$TARGET_SHA" "$local_tip" 2>/dev/null) || merged_tree=""
        fi
        # git < 2.38 không có merge-tree --write-tree: rơi về so cây hai nhánh.
        if [ -z "$merged_tree" ] && git -C "$MAIN_PATH" diff --quiet "$TARGET_SHA" "$local_tip" 2>/dev/null; then merged_tree="$origin_tree"; fi
        # `reset --keep` cũng đặt lại INDEX về commit đích: file phiên khác đã stage (khác HEAD) sẽ rơi khỏi index (thành untracked).
        # Index khác HEAD (rc 1) hoặc không đọc được (rc khác, vd index.lock) thì không dời, chỉ cảnh báo đúng lý do.
        can_move=0
        [ -n "$local_tip" ] && [ -n "$origin_tree" ] && [ "$merged_tree" = "$origin_tree" ] && can_move=1
        # --ita-visible-in-index: một entry `git add -N` của phiên khác cũng là index khác HEAD (reset --keep làm nó rơi; audit 18/10)
        idx_rc=0; git -C "$MAIN_PATH" diff --cached --quiet --ita-visible-in-index 2>/dev/null || idx_rc=$?
        ff_why=$(printf '%s' "$ff_err" | clip 200) || ff_why="(git error not readable)"   # merge đã xong: set -e không được dừng ở đây
        if [ "$can_move" != 1 ]; then
          say "warning: ${BASE} in ${MAIN_PATH} not fast-forwarded; local base is stale: ${ff_why}"
        elif [ "$idx_rc" -eq 1 ]; then
          say "warning: ${BASE} in ${MAIN_PATH} not fast-forwarded; another session has staged changes there (a reset would drop them from the index), left alone: ${ff_why}"
        elif [ "$idx_rc" -ne 0 ]; then
          say "warning: ${BASE} in ${MAIN_PATH} not fast-forwarded; its index could not be read (exit ${idx_rc}), left alone: ${ff_why}"
        elif { chk_rc=0; sync_identical check "$local_tip" >/dev/null || chk_rc=$?; [ "$chk_rc" -ne 0 ]; }; then
          # `reset --keep` không có --no-overwrite-ignore: cùng chốt va chạm file bị ignore với đường stage (audit 18/10); lỗi = không dời.
          # Đặt TRƯỚC bước kiểm lại nhánh/đầu nhánh dưới đây, để bước kiểm lại vẫn sát lệnh reset (khe vài ms, không phải thời gian chạy python).
          if [ "$chk_rc" -eq 4 ]; then
            say "warning: ${BASE} in ${MAIN_PATH} not fast-forwarded; a git-ignored local file or link is in the way of origin/${BASE} (a reset would overwrite it), left alone: ${ff_why}"
          else
            say "warning: ${BASE} in ${MAIN_PATH} not fast-forwarded; the ignored-file check could not run (exit ${chk_rc}: git or python3 failed), left alone: ${ff_why}"
          fi
        elif [ "$(git -C "$MAIN_PATH" symbolic-ref --quiet --short HEAD 2>/dev/null)" != "$BASE" ] \
             || [ "$(git -C "$MAIN_PATH" rev-parse "refs/heads/$BASE" 2>/dev/null)" != "$local_tip" ]; then
          # `reset` dời nhánh ĐANG được checkout: một phiên khác đổi nhánh/commit giữa chừng thì không đụng.
          say "warning: ${BASE} in ${MAIN_PATH} not fast-forwarded; the checkout changed while it was being checked, left alone: ${ff_why}"
        elif reset_err=$(git -C "$MAIN_PATH" reset --keep "$TARGET_SHA" 2>&1 >/dev/null); then
          say "note: ${BASE} in ${MAIN_PATH} could not fast-forward (the squash rewrote the PR's commits) but held nothing origin lacks; moved to origin/${BASE}"
        elif [ "$ident_ff" != 1 ] && n_ident=$(sync_identical reset "$local_tip"); then   # đường ff đã thử đúng các đường dẫn đó
          say "note: ${BASE} in ${MAIN_PATH} moved to origin/${BASE} after staging ${n_ident} uncommitted path(s) identical to it (nothing lost)"
        else
          say "warning: ${BASE} in ${MAIN_PATH} not fast-forwarded; local base is stale: ${ff_why} | reset to origin/${BASE} refused too: $(printf '%s' "$reset_err" | clip 200)"
        fi
      fi
    fi
  else
    say "note: ${BASE} in ${MAIN_PATH} not fast-forwarded (main checkout is not on ${BASE})"
  fi
  # Số PR: worktree detached ở head đã squash mà không ref nào còn giữ thì bước dọn giữ tạm head bằng refs/pull/<PR>/head (19/10, #96).
  # Bộ dọn DUY NHẤT sau merge (U2, audit 25/10): nó hỏi worktree.py từng bước gỡ. Không còn gọi .claude/hooks/cleanup-wt.py --post-merge
  # (hook người dùng tự cài, luật "merged" riêng, `git worktree remove` / `git branch -D` trần) ngay sau nó.
  bash "$HERE/super-board-post-merge-clean.sh" "$REPO_PATH" "$HEAD_REF" "$HEAD_SHA" "$PR" >&2 || true
  exit 0
fi
# gh pr merge lỗi (vd. GraphQL 5xx tạm thời của GitHub, 22/10 PR #176): đọc lại PR vài lần có giãn cách (GitHub có thể vừa merge
# xong phía server). MERGED → coi như đã merge; head đổi → bằng chứng review mất hiệu lực; vẫn OPEN đúng head đã verify sau mọi
# lần đọc = GitHub xác nhận CHƯA merge: thoát 4 (thẻ ở lại Review, wave sau chạy lại gate; lần đó gặp MERGED thì exit 0 ở đầu gate),
# không halt cả board và không gọi lại merge ở đây. Đọc lỗi → github-read tự halt như cũ; trạng thái khác (CLOSED…) → halt như cũ.
MERGE_RECHECKS=${SB_MERGE_RECHECKS:-3}
MERGE_RECHECK_DELAY=${SB_MERGE_RECHECK_DELAY_S:-10}
case "$MERGE_RECHECKS" in ''|*[!0-9]*|0) MERGE_RECHECKS=3;; esac
case "$MERGE_RECHECK_DELAY" in ''|*[!0-9]*) MERGE_RECHECK_DELAY=10;; esac
i=0
while :; do
  STATE=$(pr_state) || exit $?
  if [ "$(echo "$STATE" | jq -r .state)" = MERGED ]; then
    say "merge response was lost; GitHub confirms the merge commit"
    ac_after_merge
    exit 0
  fi
  NOW_SHA=$(echo "$STATE" | jq -r .headRefOid)
  if [ "$NOW_SHA" != "$HEAD_SHA" ]; then
    say "head moved during the gate: verified ${HEAD_SHA}, PR head is now ${NOW_SHA}"
    say "the review evidence is void — send the card back to Review"
    exit 6
  fi
  [ "$(echo "$STATE" | jq -r .state)" = OPEN ] || break
  i=$((i + 1))
  if [ "$i" -ge "$MERGE_RECHECKS" ]; then
    say "the merge call failed but GitHub still shows PR #${PR} OPEN at the verified head ${HEAD_SHA} after ${i} re-read(s): nothing was merged"
    say "leave the card in Review; the next wave re-runs the gate (no merge retried here, no board halt)"
    exit 4
  fi
  sleep "$MERGE_RECHECK_DELAY"
done
python3 "$GITHUB_READ" --halt "Merge response failed and GitHub has not confirmed a merge; reconcile PR #${PR} before restarting. No merge was retried." \
  --verify "{\"kind\":\"pr-merged\",\"pr\":${PR}}"
