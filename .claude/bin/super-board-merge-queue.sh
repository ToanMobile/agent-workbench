#!/usr/bin/env bash
# super-board-merge-queue.sh — hàng đợi merge (Pha 2, 26/10): gom các PR đã duyệt thành MỘT lượt super-board-merge-train.sh, rồi route kết quả.
#
# VÌ SAO: merge train (#110/#228) chạy 0 lần trên 73 PR từ 23/10: reviewer tự gọi merge gate ngay sau khi duyệt, nên runner không bao giờ
# thấy ≥2 thẻ Review đã duyệt để gom. Bộ gom này đứng riêng: reviewer chỉ ghi `approved-head:<sha40>` + gắn nhãn `merge-queue`, rồi lịch
# (hoặc cuối tick runner) gọi `--if-due`; mỗi đợt một lượt verify cho cả nhóm.
#
# Usage: super-board-merge-queue.sh --config <config.json> [--if-due] [--dry-run]
#   Bật/tắt: SB_MERGE_QUEUE=1 bật, =0 tắt, không đặt thì theo config `merge_queue.enabled` (mặc định false).
#   PR vào hàng: mở, không draft, có nhãn `merge-queue`, comment `approved-head:<sha40>` MỚI NHẤT của OWNER/MEMBER/COLLABORATOR khớp
#     `headRefOid`. Không khớp (head dời, không có, người ngoài duyệt) → gỡ nhãn + comment lý do. Draft: bỏ qua, giữ nhãn.
#   --if-due: chỉ gom khi một điều xảy ra: số PR ≥ trần đợt; PR cũ nhất (mốc sự kiện `labeled` trong timeline) chờ ≥ max_wait_min;
#     hoặc máy rảnh (không worker board nào còn sống, merge.lock của gate không còn chủ, không post-fix-gate nào giữ test_run.lock).
#   Trần đợt = merge_queue.batch_max (mặc định 6); đợt trước có PR đỏ thì max(1, batch_max/2) (trạng thái trong merge-queue.state cạnh khoá).
#   --dry-run: in đợt sẽ gửi và lý do rồi thoát trước khối train; reject chỉ in (tests/super-board/test_merge_queue.sh ca 8 kiểm điều này).
#
# Route mỗi `train-result: <PR> <kết quả>` (bước ghi nhãn đi SAU cùng: chết giữa chừng thì lượt sau route lại, không mất việc):
#   merged                        gỡ nhãn; thẻ (nhánh issue-<K>-…) không mang ac-open: đóng issue, card Done, comment ✅ merged <sha>
#   red · gate-exit-11            thẻ về Ready với loop:rebuild-(K+1) (đủ rebuild_cap thì Blocked 🛡); gỡ nhãn
#   conflict · gate-exit-2/5      thẻ về Ready với loop:rebase (đủ rebuild_cap thì Blocked 🛡); gỡ nhãn
#   gate-exit-7/8                 comment 🙋 chép nguyên văn dòng approval-request/human-gate/needs-you, needs-you mark, Blocked; gỡ nhãn
#   gate-exit-3                   comment (GitHub từ chối merge sau verify xanh), Blocked; gỡ nhãn
#   head-moved · gate-exit-6      gỡ nhãn, thẻ ở Review chờ review lại
#   deferred · timeout · gate-exit-4 · gate-exit-K khác   giữ nhãn, chỉ log (đợt sau thử lại; không comment để lịch 10 phút không spam)
#
# Exit: 0 xong / chưa tới hạn / tắt / khoá bận · 79 và 9 của github-read / train đi thẳng lên (9: route các dòng đã có rồi mới thoát) ·
#       64 sai cú pháp · 66 không thấy config · 1 không khoá được (lỗi hệ thống, không phải bận).
# ponytail: ghi lên GitHub là `gh` trần không timeout (như merge gate); bước route lỗi chỉ log rồi sang PR kế. Nâng lên khi thấy treo: bọc timeout.
# ponytail: thẻ incident của canary (Pha 2 v3 mục 3) chưa nối vào đây; làm khi batch_canary.py (lane D) đã vào kit.
set -euo pipefail
export SB_GITHUB_READ_STRICT=1
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GITHUB_READ="$HERE/super-board-github-read.py"
TRAIN="$HERE/super-board-merge-train.sh"
CARD="$HERE/super-board-card.sh"
NEEDS_YOU="$HERE/super-board-needs-you.py"
LABEL="merge-queue"
GATE_STALE_AFTER=5400   # stale-after mặc định của merge gate: max(--lock-timeout 1800 × 3, 1800)

CONFIG=""; IF_DUE=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config)  CONFIG="${2:-}"; shift 2 ;;
    --if-due)  IF_DUE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[ -n "$CONFIG" ] && [ -e "$CONFIG" ] || { echo "config not found: ${CONFIG:-<unset>}" >&2; exit 66; }
say() { echo "[merge-queue] $*" >&2; }

CONFIG_JSON=$(cat "$CONFIG")
case "${SB_MERGE_QUEUE:-}" in
  0) ENABLED=false ;;
  1) ENABLED=true ;;
  *) ENABLED=$(echo "$CONFIG_JSON" | jq -r '(.merge_queue.enabled // false) == true') ;;
esac
[ "$ENABLED" = true ] || { say "merge queue is off (config merge_queue.enabled / SB_MERGE_QUEUE); nothing to do"; exit 0; }
posint() { case "$1" in ''|*[!0-9]*|0) echo "$2" ;; *) echo "$1" ;; esac; }
BATCH_MAX=$(posint "$(echo "$CONFIG_JSON" | jq -r '.merge_queue.batch_max // empty')" 6)
MAX_WAIT_MIN=$(posint "$(echo "$CONFIG_JSON" | jq -r '.merge_queue.max_wait_min // empty')" 60)
REBUILD_CAP=$(posint "$(echo "$CONFIG_JSON" | jq -r '.rebuild_cap // empty')" 2)
REPO=$(echo "$CONFIG_JSON" | jq -r '.repo.remote // ""' | sed -E 's#^https?://github\.com/##; s#\.git$##')
REPO_PATH=$(echo "$CONFIG_JSON" | jq -r '.repo.path // "."')
export SB_REPO_PATH="$REPO_PATH"
SLUG=${REPO:-"{owner}/{repo}"}   # gh api thay {owner}/{repo} bằng repo của thư mục hiện tại

# ---- khoá một bản mỗi repo --------------------------------------------------------------------------------------------------------------
# fcntl.flock trên fd 9 của chính shell này: khoá thuộc open file description, Python thoát rồi shell vẫn giữ tới khi tiến trình kết thúc
# (macOS không có lệnh flock). Train con kế thừa fd: queue bị giết giữa đợt thì lượt mới vẫn không chạy chồng lên train đang chạy.
COMMON=$(cd "$REPO_PATH" && cd "$(git rev-parse --git-common-dir)" && pwd -P) || { say "cannot resolve the git common dir of ${REPO_PATH}"; exit 1; }
QDIR="$COMMON/super-board"; mkdir -p "$QDIR"
LOCK="$QDIR/merge-queue.lock"; STATE="$QDIR/merge-queue.state"
exec 9>>"$LOCK"
LRC=0
python3 -I -c '
import errno, fcntl, sys
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError as e:
    sys.exit(3 if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EACCES) else (print(e, file=sys.stderr) or 2))
' || LRC=$?
case "$LRC" in
  0) ;;
  3) say "another merge-queue run holds ${LOCK}; nothing to do"; exit 0 ;;
  *) say "could not lock ${LOCK} (exit ${LRC})"; exit 1 ;;
esac

# ---- PR trong hàng ----------------------------------------------------------------------------------------------------------------------
gh_w() {   # ghi lên GitHub; lỗi chỉ log (bước route sau vẫn chạy), trả 1
  local err
  if err=$(gh "$@" 2>&1 >/dev/null); then return 0; fi
  say "gh $1 $2 $3 failed: $(printf '%s' "$err" | tail -1 | cut -c1-200)"; return 1
}
reject() {   # reject <PR> <lý do>: PR rời hàng (gỡ nhãn + comment). --dry-run chỉ in.
  if [ "$DRY" -eq 1 ]; then say "would drop PR #$1 from the queue: $2"; return 0; fi
  gh_w pr comment "$1" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ⚠ left the queue · PR #$1
Did: checked the approval before batching
❌ Not done: $2
Next: review again; write a new \`approved-head:<sha40>\` for the current head and label \`$LABEL\`" || true
  gh_w pr edit "$1" ${REPO:+--repo "$REPO"} --remove-label "$LABEL" || true
}
PRS_JSON=$(python3 "$GITHUB_READ" --kind array -- pr list ${REPO:+--repo "$REPO"} --state open --label "$LABEL" --limit 200 \
             --json number,headRefName,headRefOid,isDraft) || exit $?
NOW=$(date +%s)
ROWS=""   # "<mốc gắn nhãn epoch> <PR> <head> <nhánh>" mỗi dòng
while read -r n head ref draft; do
  [ -n "${n:-}" ] || continue
  if [ "$draft" = true ]; then say "PR #${n} is a draft; skipped (label kept)"; continue; fi
  comments=$(python3 "$GITHUB_READ" --kind object -- pr view "$n" ${REPO:+--repo "$REPO"} --json comments) || exit $?
  # Cùng luật với review_approved_head của runner (#227): comment approved-head cuối cùng của người có quyền ghi thắng.
  approved=$(printf '%s' "$comments" | jq -r '
    [.comments[] | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR")
      | (.body | capture("(?m)^approved-head:(?<sha>[0-9a-f]{40})\\s*$")? // empty) | .sha] | last // empty')
  if [ -z "$approved" ]; then reject "$n" "no \`approved-head:<sha40>\` from an OWNER/MEMBER/COLLABORATOR on this PR"; continue; fi
  if [ "$approved" != "$head" ]; then reject "$n" "approved-head ${approved:0:7} is not the PR head ${head:0:7} (pushed after approval)"; continue; fi
  tl=$(python3 "$GITHUB_READ" --kind json -- api "repos/${SLUG}/issues/${n}/timeline?per_page=100" --paginate --slurp) || exit $?
  at=$(printf '%s' "$tl" | jq -r --arg l "$LABEL" '[.[][]? | select(.event == "labeled" and .label.name == $l) | .created_at | fromdateiso8601] | max // empty')
  [ -n "$at" ] || { say "PR #${n}: no labeled event for ${LABEL} in its timeline; counting it as labelled now"; at=$NOW; }
  ROWS="${ROWS}${at} ${n} ${head} ${ref}"$'\n'
done < <(printf '%s' "$PRS_JSON" | jq -r '.[] | "\(.number) \(.headRefOid) \(.headRefName) \(.isDraft)"')
ROWS=$(printf '%s' "$ROWS" | sort -n -k1,1 -k2,2)
N=0; [ -z "$ROWS" ] || N=$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')
[ "$N" -gt 0 ] || { say "nothing queued"; exit 0; }

LAST_RED=false
[ ! -r "$STATE" ] || LAST_RED=$(jq -r '.last_red // false' "$STATE" 2>/dev/null || echo false)
CAP=$BATCH_MAX
if [ "$LAST_RED" = true ]; then CAP=$(( BATCH_MAX / 2 )); [ "$CAP" -ge 1 ] || CAP=1; fi

# ---- tới hạn chưa (--if-due) -----------------------------------------------------------------------------------------------------------
# machine_busy: 0 + in lý do nếu còn việc nặng trên máy. Chỉ đọc: không xoá khoá nào, không tạo file test_run.lock (sự có mặt của nó là
# "đã từng chạy" với post-fix-gate.py), mở O_RDONLY (mở "w" làm rỗng bản ghi chủ khoá mà Stop hook đọc).
machine_busy() {
  local inf="$REPO_PATH/.claude/super-board/inflight" f pid pgid host at age wts held
  for f in "$inf"/[0-9]*; do
    [ -f "$f" ] || continue
    pid=$(sed -n 's/^PID=//p' "$f" 2>/dev/null | head -1)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "board worker for #$(basename "$f") (pid ${pid})"; return 0; fi
  done
  if [ -d "$inf/merge.lock" ]; then
    # Cùng điều kiện holder_gone của merge gate: chỉ coi là đã đi khi khoá ghi trên máy này, pid chết và nhóm tiến trình không còn ai.
    pid=$(cat "$inf/merge.lock/pid" 2>/dev/null || true); pgid=$(cat "$inf/merge.lock/pgid" 2>/dev/null || true)
    host=$(cat "$inf/merge.lock/host" 2>/dev/null || true); at=$(cat "$inf/merge.lock/at" 2>/dev/null || echo "$NOW")
    case "$at" in ''|*[!0-9]*) at=$NOW ;; esac
    age=$(( NOW - at ))
    local gone=1
    { [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null && [ -n "$pgid" ] && [ "$pgid" -gt 0 ] 2>/dev/null && [ "$host" = "$(hostname)" ] \
      && ! kill -0 "$pid" 2>/dev/null && ! ps -p "$pid" >/dev/null 2>&1 && ! kill -0 -- "-$pgid" 2>/dev/null; } || gone=0
    if [ "$gone" -eq 0 ] && [ "$age" -le "$GATE_STALE_AFTER" ]; then echo "merge gate lock held (pid ${pid:-?}, ${age}s)"; return 0; fi
  fi
  wts=$(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  held=$(printf '%s\n' "$wts" | python3 -I -c '
import fcntl, os, sys
for wt in sys.stdin.read().splitlines():
    p = os.path.join(wt, ".claude", "audit-gate", "test_run.lock")
    if not wt or not os.path.isfile(p):
        continue
    try:
        fd = os.open(p, os.O_RDONLY)
    except OSError:
        continue
    try:
        fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
    except OSError:
        print(p); break
    finally:
        os.close(fd)
')
  if [ -n "$held" ]; then echo "post-fix-gate holds ${held}"; return 0; fi
  return 1
}
OLDEST=$(printf '%s\n' "$ROWS" | head -1 | cut -d' ' -f1)
WAITED=$(( NOW - OLDEST ))
if [ "$N" -ge "$CAP" ]; then DUE="${N} PR(s) queued ≥ batch cap ${CAP}"
elif [ "$WAITED" -ge $(( MAX_WAIT_MIN * 60 )) ]; then DUE="oldest PR waited $(( WAITED / 60 )) min ≥ ${MAX_WAIT_MIN}"
elif BUSY=$(machine_busy); then DUE=""
else DUE="machine idle"; fi
if [ "$IF_DUE" -eq 1 ] && [ -z "$DUE" ]; then
  say "not due: ${N} PR(s), oldest $(( WAITED / 60 )) min (< ${MAX_WAIT_MIN}), cap ${CAP}; busy: ${BUSY}"
  exit 0
fi
[ -n "$DUE" ] || DUE="run by hand (busy: ${BUSY})"

BATCH=$(printf '%s\n' "$ROWS" | head -n "$CAP")
PRS_ARG=$(printf '%s\n' "$BATCH" | awk '{printf "%s%s:%s", (NR > 1 ? "," : ""), $2, $3}')
if [ "$DRY" -eq 1 ]; then
  echo "merge-queue: would run super-board-merge-train.sh --prs ${PRS_ARG} (${DUE}; cap ${CAP}$([ "$LAST_RED" = true ] && echo ', halved after a red batch'))"
  exit 0
fi
say "batch of $(printf '%s\n' "$BATCH" | wc -l | tr -d ' ') (${DUE}; cap ${CAP}): ${PRS_ARG}"

# ---- một lượt train ---------------------------------------------------------------------------------------------------------------------
TOUT=$(mktemp); ERRF=$(mktemp)
trap 'rm -f "$TOUT" "$ERRF"' EXIT
TRC=0
SB_MERGE_CALLER=queue bash "$TRAIN" --config "$CONFIG" --prs "$PRS_ARG" >"$TOUT" || TRC=$?
cat "$TOUT"
if [ "$TRC" -eq 79 ]; then say "train exit 79 (GitHub reads halted); nothing routed, labels kept"; exit 79; fi
if grep -qE '^train-result: [0-9]+ (red|gate-exit-11)$' "$TOUT"; then RED_NOW=true; else RED_NOW=false; fi
printf '{"last_red":%s,"at":%s,"prs":"%s","train_exit":%s}\n' "$RED_NOW" "$(date +%s)" "$PRS_ARG" "$TRC" > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"

# ---- route ------------------------------------------------------------------------------------------------------------------------------
card_of() { printf '%s\n' "$BATCH" | awk -v p="$1" '$2 == p {print $4}' | sed -nE 's/^issue-([0-9]+)-.*/\1/p'; }
issue_json() { python3 "$GITHUB_READ" --kind issue -- issue view "$1" ${REPO:+--repo "$REPO"} --json number,title,body,labels,state; }
card_move() {   # card_move <issue> <Status>: 79 dừng cả lượt; lỗi khác chỉ log
  local rc=0
  bash "$CARD" --config "$CONFIG" move "$1" "$2" >/dev/null || rc=$?
  [ "$rc" -ne 79 ] || { say "card move #$1 $2: GitHub reads halted"; exit 79; }
  [ "$rc" -eq 0 ] || say "card move #$1 $2 failed (exit ${rc})"
}
unlabel() { gh_w pr edit "$1" ${REPO:+--repo "$REPO"} --remove-label "$LABEL" || true; }
add_label() {   # add_label <issue> <label> [--remove-label X …]: tạo nhãn khi repo chưa có rồi thử lại một lần
  local k="$1" l="$2"; shift 2
  gh_w issue edit "$k" ${REPO:+--repo "$REPO"} --add-label "$l" "$@" && return 0
  gh_w label create "$l" ${REPO:+--repo "$REPO"} --color BFD4F2 --force || return 1
  gh_w issue edit "$k" ${REPO:+--repo "$REPO"} --add-label "$l" "$@"
}
block_comment() {   # block_comment <issue> <PR> <emoji> <one-line reason> <evidence> <to-unblock>
  gh_w issue comment "$1" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 blocked · $3 $4
Card:        #$1
PR:          #$2
Reason tag:  $3
Why blocked: $4
Evidence:    $5
Checked:     the merge queue ran super-board-merge-train.sh on this PR
What blocks: $6
Why I (bot) cannot decide:
             the merge gate refused this merge; only the step below changes that
To unblock:  [ ] $6
Owner:       repo owner
Move back:   drag this card to Ready after the steps above are done
blocked-by: -" || true
}
# rebuild_or_rebase <PR> <issue> <rebuild|rebase> <why>: loop:rebuild-N hiện có ≥ rebuild_cap → Blocked 🛡, không thì về Ready.
rebuild_or_rebase() {
  local p="$1" k="$2" kind="$3" why="$4" ij labs cur rm=() l
  ij=$(issue_json "$k") || exit $?
  labs=$(printf '%s' "$ij" | jq -r '.labels[].name')
  cur=$(printf '%s\n' "$labs" | sed -nE 's/^loop:rebuild-([0-9]+)$/\1/p' | sort -n | tail -1); cur=${cur:-0}
  if [ "$cur" -ge "$REBUILD_CAP" ]; then
    block_comment "$k" "$p" "🛡" "rebuild_cap ${REBUILD_CAP} reached (loop:rebuild-${cur}) and the merge queue saw ${why}" \
      "train-result for PR #${p}: ${why}" "a person looks at why this card keeps failing, then drags it to Ready"
    card_move "$k" Blocked
    return 0
  fi
  if [ "$kind" = rebuild ]; then
    for l in $labs; do case "$l" in loop:rebuild-*) rm+=(--remove-label "$l") ;; esac; done
    add_label "$k" "loop:rebuild-$((cur + 1))" ${rm[@]+"${rm[@]}"} || true
    gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ red · PR #${p} back to Build (loop:rebuild-$((cur + 1)))
Did: verified the merge-queue batch with super-board-merge-train.sh
❌ Not done: ${why}; the verify log is in the train output of this run
Next: Builder fixes the failing verify, QA and Review run again" || true
  else
    add_label "$k" "loop:rebase" || true
    gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ conflict · PR #${p} needs a rebase pass (loop:rebase)
Did: merged the PR head into origin/<base> in the merge-queue batch
❌ Not done: ${why}
Next: Builder rebases onto the base, verification green, then Review again" || true
  fi
  card_move "$k" Ready
}
detail_lines() { sed -nE "s/^train-detail: $1 //p" "$TOUT"; }

while read -r p res; do
  [ -n "${p:-}" ] || continue
  k=$(card_of "$p")
  case "$res" in
    merged)
      if [ -n "$k" ]; then
        st=$(python3 "$GITHUB_READ" --kind merge-state -- pr view "$p" ${REPO:+--repo "$REPO"} --json state,mergeCommit,headRefOid) || exit $?
        if [ "$(printf '%s' "$st" | jq -r .state)" = MERGED ]; then
          msha=$(printf '%s' "$st" | jq -r '.mergeCommit.oid')
          ij=$(issue_json "$k") || exit $?
          if printf '%s' "$ij" | jq -e 'any(.labels[]?; (.name | ascii_downcase) == "ac-open")' >/dev/null; then
            say "PR #${p} merged; card #${k} carries ac-open: left open (the gate moved it to Ready)"
          else
            gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ✅ merged ${msha} · PR #${p}
Did: merged through the merge queue (one verify for the batch)
✅ Done: PR #${p} merged as ${msha}" || true
            [ "$(printf '%s' "$ij" | jq -r '.state // "OPEN"')" != OPEN ] || gh_w issue close "$k" ${REPO:+--repo "$REPO"} || true
            card_move "$k" Done
          fi
        else
          say "train says PR #${p} merged but GitHub shows $(printf '%s' "$st" | jq -r .state); card #${k} left as is"
        fi
      fi
      unlabel "$p" ;;
    red|gate-exit-11)
      gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ red · ${res}
Did: verified the merge-queue batch; this PR is the one that turns it red
Next: back to Build${k:+ (card #$k)}" || true
      [ -z "$k" ] || rebuild_or_rebase "$p" "$k" rebuild "${res} (verify red with this PR in the batch)"
      unlabel "$p" ;;
    conflict|gate-exit-2|gate-exit-5)
      gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ conflict · ${res}
Did: merged this PR into origin/<base> for the merge-queue batch
Next: rebase pass${k:+ (card #$k)}" || true
      [ -z "$k" ] || rebuild_or_rebase "$p" "$k" rebase "${res} (the base does not merge in cleanly)"
      unlabel "$p" ;;
    gate-exit-7|gate-exit-8)
      det=$(detail_lines "$p")
      if [ -n "$k" ]; then
        gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 blocked · 🙋 the merge gate wants a person for PR #${p} (${res})
Card:        #${k}
PR:          #${p}
Reason tag:  🙋
Why blocked: merge gate ${res}: merge_policy or a human-only step (lines below, copied from the gate)
${det}
To unblock:  [ ] review PR #${p} and merge it yourself
             [ ] OR comment \`done\` on this issue to approve — the next wave merges it
Owner:       repo owner
Move back:   comment done (or merge PR #${p})
blocked-by: -" || true
        python3 "$NEEDS_YOU" mark ${REPO:+--repo "$REPO"} --issue "$k" \
          --action "xem PR #${p} (merge gate ${res}) rồi tự merge, hoặc duyệt theo comment 🙋 trên thẻ" \
          --next "comment đúng một chữ done trên issue để duyệt (hoặc tự merge PR #${p})" >/dev/null || say "needs-you mark #${k} failed"
        card_move "$k" Blocked
        gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 blocked · 🙋 needs a person (${res}); request on issue #${k}" || true
      else
        gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 blocked · 🙋 the merge gate wants a person (${res})
${det}" || true
      fi
      unlabel "$p" ;;
    gate-exit-3)
      gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 blocked · 🔑 GitHub refused the merge after a green verify (branch protection / required check)" || true
      if [ -n "$k" ]; then
        block_comment "$k" "$p" "🔑" "GitHub refused to merge PR #${p} after a green verify (gate exit 3)" \
          "train-result: ${p} gate-exit-3" "a repo admin fixes the branch protection / required check, or merges PR #${p}"
        card_move "$k" Blocked
      fi
      unlabel "$p" ;;
    head-moved|gate-exit-6)
      gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ⚠ head moved · ${res}
Did: the PR head is no longer the approved one; the approval is void
Next: a fresh review of the new head, then a new approved-head and the ${LABEL} label" || true
      unlabel "$p" ;;
    deferred|timeout|gate-exit-4) say "PR #${p}: ${res}; stays queued for the next batch" ;;
    *) say "PR #${p}: ${res}; label kept (no route for it)" ;;
  esac
done < <(sed -nE 's/^train-result: ([0-9]+) (.+)$/\1 \2/p' "$TOUT")

if [ "$TRC" -eq 9 ]; then say "train exit 9 (verification readiness): routed what it reported; stopping"; exit 9; fi
exit 0
