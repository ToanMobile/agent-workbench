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
#   Trần đợt = merge_queue.batch_max (mặc định 6); đợt trước có PR đỏ thì max(1, batch_max/2) (trạng thái trong merge-queue.state cạnh khoá;
#     train hỏng không in train-result nào thì giữ nguyên). Mốc gắn nhãn nhớ trong merge-queue.labeled (<PR> <head> <epoch>).
#   --dry-run: in đợt sẽ gửi và lý do rồi thoát trước khối train; reject chỉ in (tests/super-board/test_merge_queue.sh ca 8 kiểm điều này).
#
# Route mỗi `train-result: <PR> <kết quả>` (bước ghi nhãn đi SAU cùng: chết giữa chừng thì lượt sau route lại, không mất việc).
# Dòng `train-detail: <PR> <dòng>` của train (dòng gate, đuôi verify đỏ) chép nguyên văn vào comment issue của red / 11 / 3 / 7 / 8:
#   merged                        gỡ nhãn; thẻ (nhánh issue-<K>-…) không mang ac-open: đóng issue, card Done, comment ✅ merged <sha>
#   red · gate-exit-11            thẻ về Ready với loop:rebuild-(K+1) (đủ rebuild_cap thì Blocked 🛡); gỡ nhãn. Chỉ `red` (verify đỏ)
#                                 đánh dấu đợt đỏ (đợt sau thu nhỏ); 11 của preflight (qa-report/AC) không phải verify đỏ.
#   conflict · gate-exit-2/5      thẻ về Ready với loop:rebase (đủ rebuild_cap thì Blocked 🛡); gỡ nhãn
#   gate-exit-7/8                 comment 🙋 chép nguyên văn dòng approval-request/human-gate/needs-you, needs-you mark, Blocked, một tin
#                                 super-board-notify.py approve-button (cùng chữ ký merge gate dùng); gỡ nhãn
#   gate-exit-3                   comment chép dòng của gate (GitHub từ chối merge / PR đóng), Blocked; gỡ nhãn
#   head-moved · gate-exit-6      gỡ nhãn, thẻ ở Review chờ review lại
#   deferred · timeout · gate-exit-4 · gate-exit-K khác · train không in train-result   giữ nhãn, tăng số lần thử trong
#                                 merge-queue.attempts (<PR> <head> <n> <epoch>; head mới đếm lại); n ≥ 3 → comment, thẻ Blocked 🛡, gỡ nhãn.
#                                 Kết quả kết thúc (các dòng trên) xoá dòng của PR. Không tính: exit 79 của train (GitHub dừng đọc) và exit 4
#                                 không train-result (merge-train.lock bận: một train khác đang chạy, PR chưa chạy).
# Nhãn chỉ gỡ khi mọi bước bắt buộc của nhánh route xong (card_move, đóng issue, nhãn loop:*, needs-you mark). Bước nào lỗi (khác 79): giữ
#   nhãn, ghi merge-queue.pending (<PR> <head> <kết quả> <nhãn loop:* đã gắn>), tính một lần thử; lượt sau route lại từ đó, không dựng train,
#   không comment / notify lại.
# PR đã merge mà còn nhãn (train merge xong rồi queue chết trước khi route): mỗi lượt đọc thêm `pr list --state merged --label merge-queue`
#   và route `merged` cho PR GitHub xác nhận MERGED (nhãn gỡ sau cùng nên lượt sau thấy lại nếu chết giữa chừng).
#
# Exit: 0 xong / chưa tới hạn / tắt / khoá bận · 79 và 9 của github-read / train đi thẳng lên (9: route các dòng đã có rồi mới thoát) ·
#       64 sai cú pháp · 66 không thấy config · 1 không khoá được (lỗi hệ thống, không phải bận).
# ponytail: ghi lên GitHub là `gh` trần không timeout (như merge gate); bước route lỗi chỉ log rồi sang PR kế. Nâng lên khi thấy treo: bọc timeout.
# ponytail: thẻ incident của canary (Pha 2 v3 mục 3) chưa nối vào đây; làm khi batch_canary.py (lane D) đã vào kit.
set -euo pipefail
export SB_GITHUB_READ_STRICT=1
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GITHUB_READ="$HERE/super-board-github-read.py"
APPROVED_HEAD_JQ="$HERE/super-board-approved-head.jq"   # #605: luật approved-head dùng chung với runner
AUDIT_CHECK="$HERE/super-board-audit-check.py"           # #605: task_id của approved-by ↔ biên bản audit antigravity-pm
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
# Bật = (merge_queue.enabled hoặc SB_MERGE_QUEUE=1) VÀ worker_backend "claude-p" (thiếu khoá = "workflow", như super-board-run.sh);
# SB_MERGE_QUEUE=0 luôn tắt. Cùng định nghĩa với merge gate và merge train (fix-round1-contract.md).
# ponytail: backend workflow/codex coi như tắt (chưa có ai rút hàng ở đó); thêm khi có Q-schedule.
case "${SB_MERGE_QUEUE:-}" in
  0) ENABLED=false ;;
  *) ENABLED=$(echo "$CONFIG_JSON" | jq -r --arg env "${SB_MERGE_QUEUE:-}" \
       '(.worker_backend // "workflow") == "claude-p" and ($env == "1" or .merge_queue.enabled == true)') ;;
esac
[ "$ENABLED" = true ] || { say "merge queue is off (config merge_queue.enabled + worker_backend claude-p / SB_MERGE_QUEUE); nothing to do"; exit 0; }
BASE=$(echo "$CONFIG_JSON" | jq -r '.base_branch // "main"')
NOTIFY="$HERE/super-board-notify.py"
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
# (macOS không có lệnh flock). Train chạy với `9>&-` nên không giữ khoá: queue chết giữa đợt thì khoá đi theo nó, hàng không kẹt. Để lượt
# sau không dựng train thứ hai lên train mồ côi còn chạy, merge-queue.lock.pid ghi `queue <pid>` rồi `train <pid>`; lượt giữ được khoá
# kiểm pid train đó trước (còn sống và lệnh của nó là super-board-merge-train, chống pid tái dùng).
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
  3) say "another merge-queue run ($(tr '\n' ' ' < "$LOCK.pid" 2>/dev/null || echo 'pid ?')) holds ${LOCK}; nothing to do"; exit 0 ;;
  *) say "could not lock ${LOCK} (exit ${LRC})"; exit 1 ;;
esac
OLD_TRAIN=$(sed -n 's/^train \([0-9][0-9]*\)$/\1/p' "$LOCK.pid" 2>/dev/null | head -1 || true)
if [ -n "$OLD_TRAIN" ] && kill -0 "$OLD_TRAIN" 2>/dev/null \
   && ps -o command= -p "$OLD_TRAIN" 2>/dev/null | grep -q 'super-board-merge-train'; then
  say "the train of an earlier merge-queue run (pid ${OLD_TRAIN}) is still running; no second train this run"
  exit 0
fi
echo "queue $$" > "$LOCK.pid"   # ai đang giữ khoá (và train của nó, ghi thêm lúc chạy), cho lượt sau và người đọc khi hàng có vẻ kẹt

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
# ---- route (dùng cho kết quả của train và cho PR đã merge còn nhãn) ---------------------------------------------------------------------
# ROUTE_ROWS: "<mốc> <PR> <head> <nhánh>" mỗi dòng (đợt hiện tại + PR merged còn nhãn): card_of / head_of đọc từ đây.
ROUTE_ROWS=""
card_of() { printf '%s\n' "$ROUTE_ROWS" | awk -v p="$1" '$2 == p {print $4; exit}' | sed -nE 's/^issue-([0-9]+)-.*/\1/p'; }
head_of() { printf '%s\n' "$ROUTE_ROWS" | awk -v p="$1" '$2 == p {print $3; exit}'; }
issue_json() { python3 "$GITHUB_READ" --kind issue -- issue view "$1" ${REPO:+--repo "$REPO"} --json number,title,body,labels,state; }
card_move() {   # card_move <issue> <Status>: 79 dừng cả lượt; lỗi khác log rồi trả 1 (nhãn giữ lại, lượt sau route lại)
  local rc=0
  bash "$CARD" --config "$CONFIG" move "$1" "$2" >/dev/null || rc=$?
  [ "$rc" -ne 79 ] || { say "card move #$1 $2: GitHub reads halted"; exit 79; }
  [ "$rc" -eq 0 ] || { say "card move #$1 $2 failed (exit ${rc})"; return 1; }
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
             the merge queue cannot finish this PR on its own; only the step below changes that
To unblock:  [ ] $6
Owner:       repo owner
Move back:   drag this card to Ready after the steps above are done
blocked-by: -" || true
}
# Trần body (#470): GitHub từ chối comment > 65536 ký tự. Mỗi dòng ≤ 400 ký tự, cả khối ≤ 12000 ký tự; dòng đầu (kết luận, suite đỏ) giữ, phần dư cắt
# kèm một dòng báo. Chi tiết đầy đủ nằm ở log của train (stdout của queue), không ở comment.
detail_lines() {
  [ -n "${TOUT:-}" ] && [ -r "$TOUT" ] || return 0
  sed -nE "s/^train-detail: $1 //p" "$TOUT" | LC_ALL=C awk -v max=12000 '
    { l = substr($0, 1, 400); if (length($0) > 400) l = l " …"
      if (used + length(l) + 1 > max) { cut = 1; next }
      print l; used += length(l) + 1 }
    END { if (cut) print "… (detail truncated: the full train log is in the merge-queue output)" }'
}
# rebuild_or_rebase <PR> <issue> <rebuild|rebase> <why>: loop:rebuild-N hiện có ≥ rebuild_cap → Blocked 🛡, không thì về Ready.
# Trả 0 chỉ khi các bước bắt buộc (nhãn loop:*, card_move) xong. Lượt route lại (RETRY=1): không comment lại; nhãn loop:* đã gắn ở lượt
# trước (LABEL_DONE=1) thì không gắn lần nữa (không đẩy loop:rebuild-N lên hai lần cho cùng một lần đỏ).
RETRY=0; LABEL_DONE=0
rebuild_or_rebase() {
  local p="$1" k="$2" kind="$3" why="$4" ij labs cur rm=() l det
  det=$(detail_lines "$p")
  if [ "$RETRY" -eq 1 ] && [ "$LABEL_DONE" -eq 1 ]; then card_move "$k" Ready; return; fi
  ij=$(issue_json "$k") || exit $?
  labs=$(printf '%s' "$ij" | jq -r '.labels[].name')
  cur=$(printf '%s\n' "$labs" | sed -nE 's/^loop:rebuild-([0-9]+)$/\1/p' | sort -n | tail -1); cur=${cur:-0}
  if [ "$cur" -ge "$REBUILD_CAP" ]; then
    [ "$RETRY" -eq 1 ] || block_comment "$k" "$p" "🛡" "rebuild_cap ${REBUILD_CAP} reached (loop:rebuild-${cur}) and the merge queue saw ${why}" \
      "train-result for PR #${p}: ${why}${det:+
${det}}" "a person looks at why this card keeps failing, then drags it to Ready"
    card_move "$k" Blocked
    return
  fi
  if [ "$kind" = rebuild ]; then
    for l in $labs; do case "$l" in loop:rebuild-*) rm+=(--remove-label "$l") ;; esac; done
    add_label "$k" "loop:rebuild-$((cur + 1))" ${rm[@]+"${rm[@]}"} || return 1
    LABEL_DONE=1
    [ "$RETRY" -eq 1 ] || gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ red · PR #${p} back to Build (loop:rebuild-$((cur + 1)))
Did: verified the merge-queue batch with super-board-merge-train.sh
❌ Not done: ${why}${det:+; the gate / verify lines:
${det}}
Next: Builder fixes the failing verify, QA and Review run again" || true
  else
    add_label "$k" "loop:rebase" || return 1
    LABEL_DONE=1
    [ "$RETRY" -eq 1 ] || gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ conflict · PR #${p} needs a rebase pass (loop:rebase)
Did: merged the PR head into origin/<base> in the merge-queue batch
❌ Not done: ${why}
Next: Builder rebases onto the base, verification green, then Review again" || true
  fi
  card_move "$k" Ready
}
ATTEMPTS="$QDIR/merge-queue.attempts"; ATTEMPT_MAX=3
# merge-queue.pending: "<PR> <head> <kết quả> <nhãn loop:* đã gắn 0|1>" — kết quả kết thúc mà một bước bắt buộc của route lỗi. Lượt sau route
# lại từ dòng này (không dựng train, không verify lại, không comment / notify lại); mỗi lần lỗi tính một lần thử (trần 3 → PR rời hàng).
PENDING="$QDIR/merge-queue.pending"
drop_row() {   # drop_row <file> <PR>
  [ -f "$1" ] || return 0
  awk -v p="$2" '$1 != p' "$1" > "$1.tmp" && mv -f "$1.tmp" "$1"
}
attempt_clear() { drop_row "$ATTEMPTS" "$1"; drop_row "$PENDING" "$1"; }   # PR rời bảng đếm và hàng route lại
# attempt_retry <PR> <kết quả>: kết quả không kết thúc. n+1 cho dòng <PR> <head> (head khác = đếm lại từ 1); n ≥ 3 → PR rời hàng 🛡.
attempt_retry() {
  local p="$1" res="$2" head k n why ok=0
  head=$(head_of "$p"); k=$(card_of "$p")
  n=$(awk -v p="$p" -v h="$head" '$1 == p && $2 == h {print $3; exit}' "$ATTEMPTS" 2>/dev/null || true)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  { awk -v p="$p" '$1 != p' "$ATTEMPTS" 2>/dev/null || true; echo "$p $head $n $(date +%s)"; } > "$ATTEMPTS.tmp" && mv -f "$ATTEMPTS.tmp" "$ATTEMPTS"
  if [ "$n" -lt "$ATTEMPT_MAX" ]; then say "PR #${p}: ${res}; stays queued for the next batch (try ${n}/${ATTEMPT_MAX})"; return 0; fi
  why="the merge queue ran PR #${p} in ${n} batches without a final result (last: ${res})"
  if [ -n "$k" ]; then
    block_comment "$k" "$p" "🛡" "$why" "train-result for PR #${p}: ${res}" \
      "a person looks at why its batches keep ending in ${res}, then labels the PR ${LABEL} again or drags the card to Ready"
    card_move "$k" Blocked || ok=1
  fi
  gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 left the queue · 🛡 ${why}
Next: a person looks at why, then labels the PR ${LABEL} again${k:+ (card #$k is Blocked)}" || true
  # Trần: PR rời hàng dù card_move lỗi, để không route lại vô hạn mỗi tick.
  [ "$ok" -eq 0 ] || say "PR #${p}: moving card #${k} to Blocked failed too; the PR leaves the queue anyway (comment above)"
  unlabel "$p"; attempt_clear "$p"
}
# route_one <PR> <kết quả>: một train-result. Nhãn chỉ gỡ khi mọi bước bắt buộc của nhánh trả 0; bước nào lỗi (khác 79, đi thẳng lên)
# thì giữ nhãn, ghi merge-queue.pending và tính một lần thử: lượt sau route lại từ pending, chỉ làm lại các bước bắt buộc.
route_one() {
  local p="$1" res="$2" k st msha ij det title ok=0 head prow
  k=$(card_of "$p"); head=$(head_of "$p")
  prow=$(awk -v p="$p" -v h="$head" '$1 == p && $2 == h {print $4; exit}' "$PENDING" 2>/dev/null || true)
  RETRY=0; LABEL_DONE=0
  if [ -n "$prow" ]; then RETRY=1; [ "$prow" != 1 ] || LABEL_DONE=1; fi
  case "$res" in
    merged)
      st=$(python3 "$GITHUB_READ" --kind merge-state -- pr view "$p" ${REPO:+--repo "$REPO"} --json state,mergeCommit,headRefOid) || exit $?
      if [ "$(printf '%s' "$st" | jq -r .state)" != MERGED ]; then
        say "train says PR #${p} merged but GitHub shows $(printf '%s' "$st" | jq -r .state); label kept${k:+, card #$k left as is}"; return 0
      fi
      if [ -n "$k" ]; then
        msha=$(printf '%s' "$st" | jq -r '.mergeCommit.oid')
        ij=$(issue_json "$k") || exit $?
        if printf '%s' "$ij" | jq -e 'any(.labels[]?; (.name | ascii_downcase) == "ac-open")' >/dev/null; then
          say "PR #${p} merged; card #${k} carries ac-open: left open (the gate moved it to Ready)"
        else
          # Comment một lần (lượt route đầu); `Closes #K` thường đã làm GitHub đóng issue lúc merge, nên chỉ đóng khi còn mở.
          [ "$RETRY" -eq 1 ] || gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ✅ merged ${msha} · PR #${p}
Did: merged through the merge queue (one verify for the batch)
✅ Done: PR #${p} merged as ${msha}" || true
          [ "$(printf '%s' "$ij" | jq -r '.state // "OPEN"')" != OPEN ] || gh_w issue close "$k" ${REPO:+--repo "$REPO"} || ok=1
          card_move "$k" Done || ok=1
        fi
      fi ;;
    red|gate-exit-11)
      det=$(detail_lines "$p")
      [ "$RETRY" -eq 1 ] || gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ red · ${res}
Did: verified the merge-queue batch; this PR is the one that turns it red${det:+
${det}}
Next: back to Build${k:+ (card #$k)}" || true
      [ -z "$k" ] || rebuild_or_rebase "$p" "$k" rebuild "${res} (verify red with this PR in the batch)" || ok=1 ;;
    conflict|gate-exit-2|gate-exit-5)
      [ "$RETRY" -eq 1 ] || gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ conflict · ${res}
Did: merged this PR into origin/<base> for the merge-queue batch
Next: rebase pass${k:+ (card #$k)}" || true
      [ -z "$k" ] || rebuild_or_rebase "$p" "$k" rebase "${res} (the base does not merge in cleanly)" || ok=1 ;;
    gate-exit-7|gate-exit-8)
      det=$(detail_lines "$p")
      if [ -n "$k" ]; then
        [ "$RETRY" -eq 1 ] || gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 blocked · 🙋 the merge gate wants a person for PR #${p} (${res})
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
          --next "comment đúng một chữ done trên issue để duyệt (hoặc tự merge PR #${p})" >/dev/null || { say "needs-you mark #${k} failed"; ok=1; }
        card_move "$k" Blocked || ok=1
        [ "$RETRY" -eq 1 ] || gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 blocked · 🙋 needs a person (${res}); request on issue #${k}" || true
      elif [ "$RETRY" -eq 0 ]; then
        gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 blocked · 🙋 the merge gate wants a person (${res})
${det}" || true
      fi
      # Một tin Telegram có nút Approve (lượt route đầu), cùng chữ ký merge gate dùng (needs_you_notify, --source = PR). Lỗi chỉ log.
      if [ "$RETRY" -eq 0 ]; then
        title=$(gh pr view "$p" ${REPO:+--repo "$REPO"} --json title -q .title 2>/dev/null || true)
        python3 "$NOTIFY" approve-button --repo "$REPO" --pr "$p" --head "$head" --source "$p" --card "PR #${p}" --title "$title" \
          || say "approve-button notify for PR #${p} failed (exit $?)"
      fi ;;
    gate-exit-3)
      det=$(detail_lines "$p")
      [ "$RETRY" -eq 1 ] || gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 blocked · 🔑 the merge gate exited 3 after a green verify (GitHub refused the merge, or the PR is closed)${det:+
${det}}" || true
      if [ -n "$k" ]; then
        [ "$RETRY" -eq 1 ] || block_comment "$k" "$p" "🔑" "the merge gate exited 3 for PR #${p} after a green verify (GitHub refused the merge, or the PR is closed)" \
          "train-result: ${p} gate-exit-3${det:+
${det}}" "a person reads the gate lines above, fixes what GitHub refused, or merges PR #${p}"
        card_move "$k" Blocked || ok=1
      fi ;;
    head-moved|gate-exit-6)
      gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ⚠ head moved · ${res}
Did: the PR head is no longer the approved one (or its branch is gone from origin); the approval is void
Next: a fresh review of the new head, then a new approved-head and the ${LABEL} label" || true ;;
    deferred|timeout|gate-exit-4|*) attempt_retry "$p" "$res"; return 0 ;;
  esac
  if [ "$ok" -ne 0 ]; then
    say "PR #${p} (${res}): a routing step failed; label kept, the next run routes it again from merge-queue.pending"
    { awk -v p="$p" '$1 != p' "$PENDING" 2>/dev/null || true; echo "$p $head $res $LABEL_DONE"; } > "$PENDING.new" && mv -f "$PENDING.new" "$PENDING"
    attempt_retry "$p" "routing ${res} failed"
    return 0
  fi
  unlabel "$p"; attempt_clear "$p"
}
# PR merged còn nhãn (train merge xong, queue chết trước khi route): route `merged` sau khi GitHub xác nhận MERGED. --dry-run chỉ in.
recover_merged() {
  local merged_json n head ref st
  merged_json=$(python3 "$GITHUB_READ" --kind array -- pr list ${REPO:+--repo "$REPO"} --state merged --base "$BASE" --label "$LABEL" \
                  --limit 50 --json number,headRefName,headRefOid) || exit $?
  while read -r n head ref; do
    [ -n "${n:-}" ] || continue
    if [ "$DRY" -eq 1 ]; then say "would route PR #${n} as merged (merged while still labelled ${LABEL})"; continue; fi
    ROUTE_ROWS="${ROUTE_ROWS}0 ${n} ${head} ${ref}"$'\n'
    say "PR #${n} merged but still labelled ${LABEL}: routing it as merged"
    route_one "$n" merged </dev/null
  done < <(printf '%s' "$merged_json" | jq -r '.[] | "\(.number) \(.headRefOid) \(.headRefName)"')
}
recover_merged
PRS_JSON=$(python3 "$GITHUB_READ" --kind array -- pr list ${REPO:+--repo "$REPO"} --state open --base "$BASE" --label "$LABEL" --limit 200 \
             --json number,headRefName,headRefOid,isDraft) || exit $?
NOW=$(date +%s)
# Thứ tự đọc từ rẻ tới đắt (runner gọi --if-due mỗi tick 30 s): một `pr list`; máy rảnh / đủ đợt quyết ngay; mốc gắn nhãn (REST timeline)
# chỉ đọc khi cần và nhớ trong merge-queue.labeled theo <PR> <head>; comment approved-head (GraphQL) chỉ đọc khi đợt đã tới hạn.
CANDS=$(printf '%s' "$PRS_JSON" | jq -r '.[] | select(.isDraft != true) | "\(.number) \(.headRefOid) \(.headRefName)"')
# PR có dòng merge-queue.pending cùng head: kết quả đã có, chỉ route lại các bước bắt buộc, không vào đợt (không verify lại).
if [ -s "$PENDING" ] && [ -n "$CANDS" ]; then
  KEEP_CANDS=""
  while read -r n head ref; do
    [ -n "${n:-}" ] || continue
    res=$(awk -v p="$n" -v h="$head" '$1 == p && $2 == h {print $3; exit}' "$PENDING")
    if [ -z "$res" ]; then KEEP_CANDS="${KEEP_CANDS}${n} ${head} ${ref}"$'\n'; continue; fi
    if [ "$DRY" -eq 1 ]; then say "would route PR #${n} again (${res}, a routing step failed last run)"; continue; fi
    ROUTE_ROWS="${ROUTE_ROWS}0 ${n} ${head} ${ref}"$'\n'
    say "PR #${n}: routing ${res} again (a routing step failed last run)"
    route_one "$n" "$res" </dev/null
  done < <(printf '%s\n' "$CANDS")
  CANDS=${KEEP_CANDS%$'\n'}
fi
for n in $(printf '%s' "$PRS_JSON" | jq -r '.[] | select(.isDraft == true) | .number'); do say "PR #${n} is a draft; skipped (label kept)"; done
N=0; [ -z "$CANDS" ] || N=$(printf '%s\n' "$CANDS" | wc -l | tr -d ' ')
[ "$N" -gt 0 ] || { say "nothing queued"; exit 0; }
LABELED="$QDIR/merge-queue.labeled"
ROWS=""   # "<mốc gắn nhãn epoch> <PR> <head> <nhánh>" mỗi dòng, cũ nhất trước
load_rows() {
  local n head ref at tl cache="" out=""
  [ -z "$ROWS" ] || return 0
  [ ! -r "$LABELED" ] || cache=$(cat "$LABELED")
  while read -r n head ref; do
    [ -n "${n:-}" ] || continue
    at=$(printf '%s\n' "$cache" | awk -v n="$n" -v h="$head" '$1 == n && $2 == h {print $3; exit}')
    if [ -z "$at" ]; then
      tl=$(python3 "$GITHUB_READ" --kind json -- api "repos/${SLUG}/issues/${n}/timeline?per_page=100" --paginate --slurp) || exit $?
      at=$(printf '%s' "$tl" | jq -r --arg l "$LABEL" '[.[][]? | select(.event == "labeled" and .label.name == $l) | .created_at | fromdateiso8601] | max // empty')
      [ -n "$at" ] || { say "PR #${n}: no labeled event for ${LABEL} in its timeline; counting it as labelled now"; at=$NOW; }
    fi
    out="${out}${at} ${n} ${head} ${ref}"$'\n'
  done < <(printf '%s\n' "$CANDS")
  ROWS=$(printf '%s' "$out" | sort -n -k1,1 -k2,2)
  printf '%s\n' "$ROWS" | awk 'NF {print $2, $3, $1}' > "$LABELED.tmp" && mv -f "$LABELED.tmp" "$LABELED"
}

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
BUSY=""
if [ "$N" -ge "$CAP" ]; then DUE="${N} PR(s) queued ≥ batch cap ${CAP}"
elif ! BUSY=$(machine_busy); then DUE="machine idle"
else
  load_rows
  WAITED=$(( NOW - $(printf '%s\n' "$ROWS" | head -1 | cut -d' ' -f1) ))
  if [ "$WAITED" -ge $(( MAX_WAIT_MIN * 60 )) ]; then DUE="oldest PR waited $(( WAITED / 60 )) min ≥ ${MAX_WAIT_MIN}"
  else DUE=""; fi
fi
if [ "$IF_DUE" -eq 1 ] && [ -z "$DUE" ]; then
  say "not due: ${N} PR(s), oldest $(( WAITED / 60 )) min (< ${MAX_WAIT_MIN}), cap ${CAP}; busy: ${BUSY}"
  exit 0
fi
[ -n "$DUE" ] || DUE="run by hand (busy: ${BUSY})"
load_rows

# Đợt: đi từ PR cũ nhất, đọc comment duyệt từng PR (GraphQL) tới khi đủ trần; PR duyệt sai rời hàng ngay lượt này.
BATCH=""; NB=0
while read -r at n head ref; do
  [ -n "${n:-}" ] && [ "$NB" -lt "$CAP" ] || continue
  comments=$(python3 "$GITHUB_READ" --kind object -- pr view "$n" ${REPO:+--repo "$REPO"} --json comments) || exit $?
  # Cùng luật với review_approved_head của runner (#227, #605): một file jq chung, comment approved-head cuối cùng của người có
  # quyền ghi thắng; kèm `approved-by:` thì nguồn duyệt chéo phải đủ trường và không tự duyệt.
  verdict=$(printf '%s' "$comments" | jq -r -f "$APPROVED_HEAD_JQ") || { say "cannot evaluate approvals for PR #$n (jq failed); left in the queue"; continue; }
  IFS=$'\t' read -r vstate approved vwhy <<<"$verdict" || true
  if [ -z "$approved" ]; then reject "$n" "no \`approved-head:<sha40>\` from an OWNER/MEMBER/COLLABORATOR on this PR"; continue; fi
  if [ "$vstate" != ok ]; then reject "$n" "approved-head ${approved:0:7}: ${vwhy:-invalid approval}"; continue; fi
  if [ "$approved" != "$head" ]; then reject "$n" "approved-head ${approved:0:7} is not the PR head ${head:0:7} (pushed after approval)"; continue; fi
  # #605 (audit T0066 vòng 2): task_id của approved-by là lời khai; chỉ tính khi antigravity-pm có audit pass với auditedHead == head.
  case "$vwhy" in
    owner) ;;
    task:?*) if ! ( cd "$REPO_PATH" && python3 "$AUDIT_CHECK" "${vwhy#task:}" "$head" ) 2>/dev/null; then
               reject "$n" "approved-by task_id ${vwhy#task:} has no antigravity-pm audit pass with auditedHead ${head:0:7}"; continue
             fi ;;
    *) reject "$n" "approved-head ${approved:0:7}: approval source unreadable"; continue ;;
  esac
  BATCH="${BATCH}${at} ${n} ${head} ${ref}"$'\n'; NB=$((NB + 1))
done < <(printf '%s\n' "$ROWS")
BATCH=${BATCH%$'\n'}
[ "$NB" -gt 0 ] || { say "no queued PR carries a valid approval; nothing to run"; exit 0; }
PRS_ARG=$(printf '%s\n' "$BATCH" | awk '{printf "%s%s:%s", (NR > 1 ? "," : ""), $2, $3}')
if [ "$DRY" -eq 1 ]; then
  echo "merge-queue: would run super-board-merge-train.sh --prs ${PRS_ARG} (${DUE}; cap ${CAP}$([ "$LAST_RED" = true ] && echo ', halved after a red batch'))"
  exit 0
fi
say "batch of $(printf '%s\n' "$BATCH" | wc -l | tr -d ' ') (${DUE}; cap ${CAP}): ${PRS_ARG}"

# ---- một lượt train ---------------------------------------------------------------------------------------------------------------------
ROUTE_ROWS="${ROUTE_ROWS}${BATCH}"$'\n'
TOUT=$(mktemp); ERRF=$(mktemp)
TPID=""
trap 'rm -f "$TOUT" "$ERRF"' EXIT
# Queue bị dừng (TERM/INT/HUP của runner hay người) giữa đợt: chuyển tín hiệu xuống train con rồi thoát, không bỏ train chạy mồ côi.
# SIGKILL không bắt được: lượt sau thấy `train <pid>` còn sống trong merge-queue.lock.pid và không dựng train thứ hai.
forward_stop() { [ -z "$TPID" ] || kill -TERM "$TPID" 2>/dev/null || true; exit "$1"; }
trap 'forward_stop 143' TERM; trap 'forward_stop 130' INT; trap 'forward_stop 129' HUP
TRC=0
# 9>&-: train và mọi tiến trình nền của nó (verify, gate) không mang khoá của queue; queue chết thì khoá đi theo nó, không kẹt hàng.
SB_MERGE_CALLER=queue bash "$TRAIN" --config "$CONFIG" --prs "$PRS_ARG" >"$TOUT" 9>&- &
TPID=$!
echo "train $TPID" >> "$LOCK.pid"
wait "$TPID" || TRC=$?
TPID=""
echo "queue $$" > "$LOCK.pid"
cat "$TOUT"
if [ "$TRC" -eq 79 ]; then say "train exit 79 (GitHub reads halted); nothing routed, labels kept"; exit 79; fi
if ! grep -q '^train-result: ' "$TOUT"; then
  if [ "$TRC" -eq 4 ]; then
    # Train thấy merge-train.lock bận (một train khác đang chạy): các PR chưa chạy, không tính lần thử.
    say "train exit 4 (another train holds merge-train.lock); nothing ran, labels kept, no attempt counted"; exit 0
  fi
  say "train exit ${TRC} with no train-result line; nothing routed, labels and the red mark kept; one attempt counted per PR"
  while read -r _ p _ _; do [ -n "${p:-}" ] && attempt_retry "$p" "train exit ${TRC} without a train-result" </dev/null; done < <(printf '%s\n' "$BATCH")
  [ "$TRC" -ne 9 ] || exit 9
  exit 0
fi
# Chỉ `red` (verify đỏ của train / gate) đánh dấu đợt đỏ; gate-exit-11 của preflight (qa-report/AC) không làm đợt sau nhỏ lại.
if grep -qE '^train-result: [0-9]+ red$' "$TOUT"; then RED_NOW=true; else RED_NOW=false; fi
printf '{"last_red":%s,"at":%s,"prs":"%s","train_exit":%s}\n' "$RED_NOW" "$(date +%s)" "$PRS_ARG" "$TRC" > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"

# ---- route từng train-result ------------------------------------------------------------------------------------------------------------
while read -r p res; do
  [ -n "${p:-}" ] || continue
  route_one "$p" "$res" </dev/null
done < <(sed -nE 's/^train-result: ([0-9]+) (.+)$/\1 \2/p' "$TOUT")

if [ "$TRC" -eq 9 ]; then say "train exit 9 (verification readiness): routed what it reported; stopping"; exit 9; fi
exit 0
