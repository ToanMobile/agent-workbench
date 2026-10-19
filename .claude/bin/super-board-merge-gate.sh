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
# Exit codes, all meaningful to the caller:
#   0  merged
#   11 verification failed after merging the base cleanly into the scratch tree —
#      rebasing changes nothing: back to Build to fix the failing verify (the gate
#      quotes its last KẾT LUẬN/VERDICT line), NOT a rebase pass, NOT a Blocked card
#   3  PR is closed without a merge; no merge attempted
#   4  could not take the lock within the timeout
#   5  the base could not be merged in (real conflict) — needs a rebase pass
#   6  the PR head is not the commit that was reviewed — review evidence is void,
#      the card goes back to Review (not Blocked, not a rebase pass)
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

CONFIG=""; PR=""; LOCK_TIMEOUT=1800; STALE_AFTER=""; DRY=0; EXPECT_HEAD=""; SUBJECT=""; MSG_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config)        CONFIG="$2"; shift 2 ;;
    --pr)            PR="$2"; shift 2 ;;
    --expect-head)   EXPECT_HEAD="$2"; shift 2 ;;
    --subject)       SUBJECT="$2"; shift 2 ;;
    --body-file)     MSG_FILE="$2"; shift 2 ;;
    --lock-timeout)  LOCK_TIMEOUT="$2"; shift 2 ;;
    --stale-after)   STALE_AFTER="$2"; shift 2 ;;
    --dry-run)       DRY=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[ -n "$CONFIG" ] && [ -e "$CONFIG" ] || { echo "config not found: ${CONFIG:-<unset>}" >&2; exit 66; }
[ -n "$PR" ] || { echo "--pr <number> is required" >&2; exit 64; }
[ -z "$MSG_FILE" ] || [ -r "$MSG_FILE" ] || { echo "--body-file not readable: $MSG_FILE" >&2; exit 66; }
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

say() { echo "[merge-gate #${PR}] $*" >&2; }
# Notices use the existing bot config. A missing token, or SB_NOTIFY_SKIP=1, does not change the exit.
board_notify() {
  if [ "${SB_NOTIFY_SKIP:-0}" = "1" ]; then
    return 0
  fi
  python3 "$HERE/super-board-notify.py" "$@" || true
}
needs_you_notify() {
  board_notify approve-button --repo "$REPO" --pr "$PR" --head "${HEAD_SHA:-}" --source "$PR" --card "PR #${PR}"
}
# clip <n>: stdin gộp về một dòng, giữ tối đa n KÝ TỰ. INSTINCT-173: dưới locale C `cut -c` cắt theo byte và làm vỡ ký tự tiếng Việt
# (văn bản không còn UTF-8, github-read từ chối). Byte không phải UTF-8 trong lỗi của git thành U+FFFD, không bao giờ vỡ giữa ký tự.
clip() { tr '\n\t' '  ' | python3 -I -c 'import sys; sys.stdout.buffer.write(sys.stdin.buffer.read().decode("utf-8", "replace")[:int(sys.argv[1])].encode("utf-8"))' "$1"; }

# ---- the mutex -------------------------------------------------------------
# mkdir is atomic: it succeeds for exactly one caller and fails for the rest.
# The pid/date inside is for a human reading a stuck lock, never for logic.
acquire() {
  local waited=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
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
  return 0
}
release() { rm -rf "$LOCK_DIR"; }

acquire || { say "could not take the merge lock within ${LOCK_TIMEOUT}s"; exit 4; }
trap release EXIT

say "lock taken; verifying against ${BASE} as it is now"

# ---- the freshness check ---------------------------------------------------
# Scratch proves the merge. When that merge is clean and the PR branch is behind
# the base, the gate fast-forwards the merge commit onto the PR branch. It never
# uses --force. A rejected fast-forward stays exit 11 (not a rebase pass).
# Scratch đặt trong .claude/worktrees của main checkout để cùng phân vùng đĩa (st_dev) cho cp -Rc Unity Library.
REPO_ABS=$(cd "$REPO_PATH" && pwd -P)
MAIN_WT=$(git -C "$REPO_ABS" worktree list --porcelain | sed -n '1s/^worktree //p')
BASE_WT=${MAIN_WT:-$REPO_ABS}
mkdir -p "$BASE_WT/.claude/worktrees"
SCRATCH=$(mktemp -d "$BASE_WT/.claude/worktrees/.merge-scratch-XXXXXX")
cleanup() { git -C "$BASE_WT" worktree remove --force "$SCRATCH" 2>/dev/null || true; rm -rf "$SCRATCH" "${META:-}" "${DIFF:-}" "${VERIFY_LOG:-}"; release; }
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
python3 "$GITHUB_READ" --kind metadata -- pr view "$PR" ${REPO:+--repo "$REPO"} --json labels,files,additions,deletions,changedFiles,body > "$META"
python3 "$GITHUB_READ" --kind diff --meta "$META" -- pr diff "$PR" ${REPO:+--repo "$REPO"} > "$DIFF"
PLAN=$(python3 "$HERE/super-board-merge-policy.py" --config "$CONFIG" --meta "$META" --diff "$DIFF") || {
  echo "human-gate: policy — could not classify the PR (unreadable metadata)"
  say "merge policy could not be evaluated — a human merges this one"
  needs_you_notify
  exit 7; }

# The label is display-only. A request posted before `done` pins the exact head
# and policy/commands. Re-read trusted approval evidence; never mint it here.
APPROVED=false
approval_check() {
  APPROVAL=$(python3 "$HERE/super-board-approval.py" --repo "$REPO" --pr "$PR" \
    --head "$HEAD_SHA" --plan "$PLAN") || APPROVAL='{"approved":false}'
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

git -C "$REPO_PATH" fetch origin "$HEAD_REF" "$BASE" --quiet
# Chốt commit base một lần, merge đúng commit đó: verify đỏ thì đếm "chậm hơn base" theo chính nó. Đọc lại origin/<base> sau vài phút
# verify có thể đã bị phiên khác fetch đi; suy từ HEAD^2 thì sai khi merge là fast-forward lên một merge commit (OCR 18/10).
BASE_SHA=$(git -C "$REPO_PATH" rev-parse --verify -q "origin/${BASE}^{commit}") || {
  say "cannot resolve origin/${BASE} after fetch"; exit 5; }

git -C "$REPO_PATH" worktree add --detach "$SCRATCH" "$HEAD_SHA" --quiet 2>/dev/null || {
  say "could not create a scratch worktree for ${HEAD_REF}@${HEAD_SHA}"; exit 5; }

if ! git -C "$SCRATCH" merge "$BASE_SHA" --no-edit --quiet 2>/dev/null; then
  CONFLICTS=$(git -C "$SCRATCH" diff --name-only --diff-filter=U | tr '\n' ' ')
  say "the base does not merge in cleanly — conflicts: ${CONFLICTS}"
  say "this is a rebase pass for the Builder lane, not a Blocked card"
  exit 5
fi

# Nhánh chậm hơn base nhưng merge scratch sạch: đẩy fast-forward lên đúng nhánh PR
# rồi mới verify. Timeout phía dưới vẫn thử lại một lần. Không --force.
MERGED_SHA=$(git -C "$SCRATCH" rev-parse HEAD)
BEHIND_NOW=$(git -C "$REPO_PATH" rev-list --count "${HEAD_SHA}..${BASE_SHA}" 2>/dev/null || echo 0)
if [ "${BEHIND_NOW:-0}" -gt 0 ] 2>/dev/null && [ "$MERGED_SHA" != "$HEAD_SHA" ]; then
  if git -C "$REPO_PATH" push origin "${MERGED_SHA}:refs/heads/${HEAD_REF}"; then
    say "updated ${HEAD_REF} in place ${HEAD_SHA} -> ${MERGED_SHA} (clean merge of ${BASE}, no --force)"
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

# Chạy lệnh verify trong scratch: post-fix-gate.py tự giữ heavy slot, các lệnh verify khác được bọc qua super-board-heavy-slot.py.
run_verify_cmd() {
  local c="$1"
  if [[ "$c" == *"post-fix-gate.py"* ]]; then
    ( cd "$SCRATCH" && unset POSTFIX_GATE_FORCE_FULL && DEVKIT_LANG="${DEVKIT_LANG:-vi}" eval "$c" ) >"$VERIFY_LOG" 2>&1
  else
    ( cd "$SCRATCH" && unset POSTFIX_GATE_FORCE_FULL && DEVKIT_LANG="${DEVKIT_LANG:-vi}" python3 "$HERE/super-board-heavy-slot.py" -- bash -c "$c" ) >"$VERIFY_LOG" 2>&1
  fi
}

# Kiểm tra lỗi verify có phải do timeout (exit 124 hoặc log chứa TIMEOUT / timed out / quá giới hạn) để thử lại đúng 1 lần.
is_verify_timeout() {
  local rc="$1" log_file="$2" wt_log
  # Gate đã in kết luận thì suite bên trong có chữ "timed out" không được chạy lại cả --full.
  if [ -f "$log_file" ] && grep -aqE "KẾT LUẬN|POST-FIX AUDIT GATE VERDICT" "$log_file" 2>/dev/null; then
    return 1
  fi
  [ "$rc" -eq 124 ] && return 0
  if [ -f "$log_file" ] && grep -aqE "TIMEOUT after|quá giới hạn" "$log_file" 2>/dev/null; then
    return 0
  fi
  wt_log="$(git -C "$SCRATCH" rev-parse --absolute-git-dir 2>/dev/null)/postfix-gate/last_output.log"
  [ -f "$wt_log" ] || return 1
  if grep -aqE "KẾT LUẬN|POST-FIX AUDIT GATE VERDICT" "$wt_log" 2>/dev/null; then
    return 1
  fi
  grep -aqE "TIMEOUT after|quá giới hạn" "$wt_log" 2>/dev/null
}

# ---- chờ máy bớt tải trước verify ------------------------------------------------
# 19/10: verify --full chạy lúc tải 1 phút ~60 (5 board cùng build), REG-DK-ALL-01 của PR #87 chọn 127 test và quá 900 s, thẻ #12
# quay về Ready mãi. Chờ tải xuống dưới SB_MERGE_LOAD_MAX (mặc định 2 × số lõi), tối đa SB_MERGE_LOAD_WAIT_S (mặc định 1800 s,
# 0 = không chờ); hết giờ vẫn verify như cũ, không bỏ bước nào. Chờ trong khoá, ngay trước verify: các lối ra nhanh phía trên
# (đã merge, đóng, head đổi, cần người) không phải chờ; tuổi khoá ≤ 1800 + 2 × 900 s, dưới STALE_AFTER mặc định 5400 s.
# SB_MERGE_LOAD_FILE: móc test, đọc tải từ file thay cho os.getloadavg().
load_now() {
  if [ -n "${SB_MERGE_LOAD_FILE:-}" ]; then tr -d '[:space:]' < "$SB_MERGE_LOAD_FILE" 2>/dev/null || true
  else python3 -c 'import os; print(int(os.getloadavg()[0]))' 2>/dev/null || true; fi
}
wait_for_load() {
  local max="${SB_MERGE_LOAD_MAX:-}" cap="${SB_MERGE_LOAD_WAIT_S:-1800}" poll="${SB_MERGE_LOAD_POLL_S:-30}" waited=0 load nap
  [ "$DRY" -eq 1 ] && return 0
  # ^[1-9][0-9]{0,5}$: không có số 0 đứng đầu (bash đọc 08 là bát phân và set -e dừng gate) và không tràn số.
  [[ "$cap" =~ ^[1-9][0-9]{0,5}$ ]] || return 0
  [[ "$poll" =~ ^[1-9][0-9]{0,5}$ ]] || poll=30
  [[ "$max" =~ ^[1-9][0-9]{0,5}$ ]] || max=$(( $(python3 -c 'import os; print(os.cpu_count() or 4)' 2>/dev/null || echo 4) * 2 ))
  while :; do
    load=$(load_now)
    [[ "$load" =~ ^[0-9]{1,6}$ ]] || { say "cannot read the machine load ('${load}'); verifying without waiting"; return 0; }
    load=$((10#$load))
    if [ "$load" -lt "$max" ]; then
      [ "$waited" -gt 0 ] && say "load ${load} after ${waited}s; verifying"
      return 0
    fi
    [ "$waited" -ge "$cap" ] && { say "load still ${load} after ${waited}s; verifying anyway"; return 0; }
    [ "$waited" -eq 0 ] && say "waiting for load ${load} to drop below ${max} before verify (at most ${cap}s)"
    nap=$(( cap - waited < poll ? cap - waited : poll ))
    sleep "$nap"; waited=$(( waited + nap ))
  done
}
wait_for_load

for cmd in "${VERIFY[@]}"; do
  if [[ "$cmd" == *"post-fix-gate.py"* ]]; then
    [[ "$cmd" == *"--diff"* ]] || cmd="$cmd --diff origin/${BASE}"
    [[ "$cmd" == *"--force-full"* ]] || cmd="$cmd --force-full"
    # Không bao giờ tự thêm --auto-approve-tests ở đây: duyệt test bị sửa là quyết định của từng board (config của nó).
  fi
  say "verify: ${cmd}"
  VRC=0
  run_verify_cmd "$cmd" || VRC=$?
  if [ "$VRC" -ne 0 ] && is_verify_timeout "$VRC" "$VERIFY_LOG"; then
    say "verify timed out (exit ${VRC}); retrying once: ${cmd}"
    VRC=0
    run_verify_cmd "$cmd" || VRC=$?
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
say "verified green against ${BASE} (${#VERIFY[@]} command(s))"

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
  say "dry run: would squash-merge PR #${PR}"
  exit 0
fi

# --match-head-commit makes GitHub refuse if anything was pushed after HEAD_SHA,
# including during the verification run above.
python3 "$GITHUB_READ" --check
if gh pr merge "$PR" ${REPO:+--repo "$REPO"} --squash --delete-branch \
     ${SUBJECT:+--subject "$SUBJECT"} ${MSG_FILE:+--body-file "$MSG_FILE"} \
     --match-head-commit "$HEAD_SHA" 2>&1 | tail -3 >&2; then
  say "merged ${HEAD_SHA}"
  board_notify send --card "PR #${PR}" --text "merged ${HEAD_SHA}"
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
        merged_tree=$(git -C "$MAIN_PATH" merge-tree --write-tree "$TARGET_SHA" "$local_tip" 2>/dev/null) || merged_tree=""
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
  bash "$HERE/super-board-post-merge-clean.sh" "$REPO_PATH" "$HEAD_REF" "$HEAD_SHA" "$PR" >&2 || true
  if [ -f "$REPO_PATH/.claude/hooks/cleanup-wt.py" ]; then
    ( cd "$REPO_PATH" && python3 .claude/hooks/cleanup-wt.py --post-merge --base "$BASE" </dev/null ) >&2 || true
  fi
  exit 0
fi
STATE=$(pr_state) || exit $?
if [ "$(echo "$STATE" | jq -r .state)" = MERGED ]; then
  say "merge response was lost; GitHub confirms the merge commit"
  exit 0
fi
NOW_SHA=$(echo "$STATE" | jq -r .headRefOid)
if [ "$NOW_SHA" != "$HEAD_SHA" ]; then
  say "head moved during the gate: verified ${HEAD_SHA}, PR head is now ${NOW_SHA}"
  say "the review evidence is void — send the card back to Review"
  exit 6
fi
python3 "$GITHUB_READ" --halt "Merge response failed and GitHub has not confirmed a merge; reconcile PR #${PR} before restarting. No merge was retried."
