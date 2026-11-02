#!/usr/bin/env bash
# super-board-merge-queue.sh — hàng đợi merge: PR đã duyệt (nhãn `merge-queue` + `approved-head:<sha40>`) vào MỘT lượt super-board-merge-train.sh, rồi route kết quả.
#
# VÌ SAO: reviewer chỉ ghi `approved-head:<sha40>` + gắn nhãn `merge-queue`; lịch (hoặc cuối tick runner) gọi script này. Không gom đợt
# (29/10): `--full` chỉ chạy một lần lúc nửa đêm (gate-full), nên không còn lý do chờ đủ PR hay chờ PR cũ. Mỗi lần gọi, MỌI PR hợp lệ đang
# trong hàng vào một train (một lượt verify cho cả nhóm đang có); không trần đợt, không hạn chờ, không đợi máy rảnh.
#
# #676: mỗi lượt NGẮN — thu train đã xong (merge-queue.inflight), phóng tối đa merge_queue.max_trains (mặc định 3) train nền MỘT PR mỗi train
# (verify main+PR của chính nó, chạy song song qua pool slot; chỉ `gh pr merge` được khoá merge của gate tuần tự hoá), rồi thoát. Lượt sau
# route kết quả. `--wait` (test / tay): chờ các train vừa phóng rồi thu luôn.
#
# Usage: super-board-merge-queue.sh --config <config.json> [--dry-run] [--wait]
#   Bật/tắt: SB_MERGE_QUEUE=1 bật, =0 tắt, không đặt thì theo config `merge_queue.enabled` (mặc định false).
#   PR vào hàng: mở, không draft, có nhãn `merge-queue`, comment `approved-head:<sha40>` MỚI NHẤT của OWNER/MEMBER/COLLABORATOR khớp
#     `headRefOid`. Không khớp (head dời, không có, người ngoài duyệt) → gỡ nhãn + comment lý do. Draft: bỏ qua, giữ nhãn.
#   Thứ tự trong train: PR gắn nhãn cũ nhất trước (mốc sự kiện `labeled` trong timeline, nhớ trong merge-queue.labeled:
#     <PR> <head> <epoch> <nhánh>; nhánh cho Agent Office / status ghép PR với thẻ, #562, và runner dùng mốc cũ nhất để miễn RUNAWAY).
#   --dry-run: in đợt sẽ gửi rồi thoát trước khối train; reject chỉ in (tests/super-board/test_merge_queue.sh ca 8 kiểm điều này).
#
# Route mỗi `train-result: <PR> <kết quả>` (bước ghi nhãn đi SAU cùng: chết giữa chừng thì lượt sau route lại, không mất việc).
# Dòng `train-detail: <PR> <dòng>` của train (dòng gate, đuôi verify đỏ, lời git/hook) chép nguyên văn vào comment issue của red / 11 / 3 / 7 / 8 / 5:
#   merged                        gỡ nhãn; thẻ (nhánh issue-<K>-…, không thì closingIssuesReferences đúng một issue của repo nằm trên
#                                 board, #637) không mang ac-open: đóng issue, card Done, comment ✅ merged <sha>
#   red · gate-exit-11            thẻ về Ready với loop:rebuild-(K+1) (đủ rebuild_cap thì Blocked 🛡); gỡ nhãn. gate-exit-11 = preflight
#                                 (qa-report / AC) chặn trước khi dựng cây: comment nói nguồn đó, không nói verify đỏ (#639).
#   conflict · gate-exit-2/5      thẻ về Ready với loop:rebase (đủ rebuild_cap thì Blocked 🛡); gỡ nhãn
#   gate-exit-7/8                 comment 🙋 chép nguyên văn dòng approval-request/human-gate/needs-you, needs-you mark, Blocked, một tin
#                                 super-board-notify.py approve-button (cùng chữ ký merge gate dùng); gỡ nhãn
#   gate-exit-3                   comment chép dòng của gate (GitHub từ chối merge / PR đóng), Blocked; gỡ nhãn
#   head-moved · gate-exit-6      gỡ nhãn, thẻ ở Review chờ review lại
#   deferred · timeout · gate-exit-4 · gate-exit-K khác · train không in train-result   giữ nhãn, tăng số lần thử trong
#                                 merge-queue.attempts (<PR> <head> <n> <epoch>; head mới đếm lại); n ≥ 3 → comment, thẻ Blocked 🛡, gỡ nhãn.
#                                 Kết quả kết thúc (các dòng trên) xoá dòng của PR. Không tính: exit 79 của train (GitHub dừng đọc) và exit 4
#                                 không train-result (merge-train.lock bận: một train khác đang chạy, PR chưa chạy).
# Nhãn chỉ gỡ khi mọi bước bắt buộc của nhánh route xong (card_move, đóng issue, nhãn loop:*, needs-you mark). Bước nào lỗi: giữ nhãn, ghi
#   merge-queue.pending (<PR> <head> <kết quả> <nhãn loop:* đã gắn>), tính một lần thử (halt 79: không tính); lượt sau route lại từ đó, không
#   dựng train, không comment / notify lại (comment trên thẻ chưa đọc được thì vẫn đăng).
# PR đã merge mà còn nhãn (train merge xong rồi queue chết trước khi route): mỗi lượt đọc thêm `pr list --state merged --label merge-queue`
#   và route `merged` cho PR GitHub xác nhận MERGED (nhãn gỡ sau cùng nên lượt sau thấy lại nếu chết giữa chừng).
#
# Exit: 0 xong / chưa tới hạn / tắt / khoá bận · 79 và 9 của github-read / train đi thẳng lên (9: route các dòng đã có rồi mới thoát) ·
#       64 sai cú pháp · 66 không thấy config · 1 không khoá được (lỗi hệ thống, không phải bận).
#       Đọc GitHub hỏng khi route một PR (#637): PR đó giữ nhãn, các PR còn lại vẫn route; github-read 79 (kể cả 79 của card_move) thì
#       thoát 79 sau khi route xong, và lần route dừng vì halt không tính lần thử.
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

CONFIG=""; DRY=0; WAIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config)  CONFIG="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --wait)    WAIT=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[ -n "$CONFIG" ] && [ -e "$CONFIG" ] || { echo "config not found: ${CONFIG:-<unset>}" >&2; exit 66; }
say() { echo "[merge-queue] $*" >&2; }

CONFIG_JSON=$(cat "$CONFIG")
# Bật = (merge_queue.enabled hoặc SB_MERGE_QUEUE=1) VÀ worker_backend "claude-p" (runner rút mỗi tick) hoặc "workflow" (thiếu khoá = "workflow",
# như super-board-run.sh; lịch super-board-queue-schedule.sh rút, #453); SB_MERGE_QUEUE=0 luôn tắt. Cùng định nghĩa với merge gate, merge
# train và runner (fix-round1-contract.md).
# ponytail: backend codex coi như tắt (lane codex tự merge qua gate với SB_MERGE_QUEUE=0); thêm khi codex có lịch rút hàng.
case "${SB_MERGE_QUEUE:-}" in
  0) ENABLED=false ;;
  *) ENABLED=$(echo "$CONFIG_JSON" | jq -r --arg env "${SB_MERGE_QUEUE:-}" \
       '((.worker_backend // "workflow") | IN("claude-p", "workflow")) and ($env == "1" or .merge_queue.enabled == true)') ;;
esac
[ "$ENABLED" = true ] || { say "merge queue is off (config merge_queue.enabled + worker_backend claude-p or workflow / SB_MERGE_QUEUE); nothing to do"; exit 0; }
BASE=$(echo "$CONFIG_JSON" | jq -r '.base_branch // "main"')
NOTIFY="$HERE/super-board-notify.py"
posint() { case "$1" in ''|*[!0-9]*|0) echo "$2" ;; *) echo "$1" ;; esac; }
REBUILD_CAP=$(posint "$(echo "$CONFIG_JSON" | jq -r '.rebuild_cap // empty')" 2)
REPO=$(echo "$CONFIG_JSON" | jq -r '.repo.remote // ""' | sed -E 's#^https?://github\.com/##; s#\.git$##')
REPO_PATH=$(echo "$CONFIG_JSON" | jq -r '.repo.path // "."')
export SB_REPO_PATH="$REPO_PATH"
SLUG=${REPO:-"{owner}/{repo}"}   # gh api thay {owner}/{repo} bằng repo của thư mục hiện tại

# ---- khoá một bản mỗi repo --------------------------------------------------------------------------------------------------------------
# fcntl.flock trên fd 9 của chính shell này: khoá thuộc open file description, Python thoát rồi shell vẫn giữ tới khi tiến trình kết thúc
# (macOS không có lệnh flock). #676: lượt queue NGẮN (vài giây): thu kết quả train đã xong, phóng train mới chạy nền rồi thoát — khoá
# không bao giờ giữ lúc verify chờ slot. Train chạy với `9>&-` nên không giữ khoá. Train đang chạy của từng PR ghi ở merge-queue.inflight
# (pid kiểm sống + lệnh là queue/train, chống pid tái dùng): lượt sau không phóng train thứ hai cho PR đó. merge-queue.lock.pid: `queue <pid>`.
COMMON=$(cd "$REPO_PATH" && cd "$(git rev-parse --git-common-dir)" && pwd -P) || { say "cannot resolve the git common dir of ${REPO_PATH}"; exit 1; }
QDIR="$COMMON/super-board"; mkdir -p "$QDIR"
LOCK="$QDIR/merge-queue.lock"
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
echo "queue $$" > "$LOCK.pid"   # ai đang giữ khoá (và train của nó, ghi thêm lúc chạy), cho lượt sau và người đọc khi hàng có vẻ kẹt

# ---- PR trong hàng ----------------------------------------------------------------------------------------------------------------------
# #453: gh ghi bị chặn trần SB_GH_WRITE_TIMEOUT giây (mặc định 15; macOS không có `timeout`): gh treo thì cả nhóm tiến trình của nó bị giết,
# gh_w trả 1 như mọi lỗi ghi khác (giữ nhãn, lượt sau route lại) và hàng đợi không chết.
gh_w() {   # ghi lên GitHub; lỗi chỉ log (bước route sau vẫn chạy), trả 1
  local err
  if err=$(python3 -I -c '
import os, signal, subprocess, sys
p = subprocess.Popen(["gh"] + sys.argv[2:], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, start_new_session=True)
try:
    _, e = p.communicate(timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL); p.communicate()
    print("timed out after " + sys.argv[1] + " s", file=sys.stderr); sys.exit(124)
sys.stderr.write(e); sys.exit(p.returncode)
' "${SB_GH_WRITE_TIMEOUT:-15}" "$@" 2>&1); then return 0; fi
  say "gh $1 $2 $3 failed: $(printf '%s' "$err" | tail -1 | cut -c1-200)"; return 1
}
reject() {   # reject <PR> <lý do> [nhánh]: PR rời hàng (gỡ nhãn + comment), báo cả thẻ PR đóng (#536). --dry-run chỉ in.
  if [ "$DRY" -eq 1 ]; then say "would drop PR #$1 from the queue: $2"; return 0; fi
  gh_w pr comment "$1" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ⚠ left the queue · PR #$1
Did: checked the approval before batching
❌ Not done: $2
Next: review again; write a new \`approved-head:<sha40>\` for the current head and label \`$LABEL\`" || true
  gh_w pr edit "$1" ${REPO:+--repo "$REPO"} --remove-label "$LABEL" || true
  reject_note_card "$1" "${3:-}" "$2"
}
# #536 (28/10: PR #517 rời hàng 07:49, các thẻ phụ thuộc đứng im ~3 giờ không ai được báo): thẻ mà PR đóng — nhánh issue-<K>-, không thì
# closingIssuesReferences đúng một issue (CLOSES) — nhận một comment ngắn. Chỉ khi card.sh xác nhận K nằm trên board. Mọi lỗi đọc/ghi ở đây
# bị bỏ qua (PR đã có comment ở trên) và không đụng READ_HALT: card.sh đọc qua github-read, đọc hỏng ghi file halt; nên lần đọc này dùng
# SB_GITHUB_HALT_FILE riêng chưa tồn tại (xoá ngay sau) để không bao giờ để lại github-halt.json thật làm dừng hàng đợi hay board.
reject_note_card() {   # reject_note_card <PR> <nhánh> <lý do>
  local k haltf
  k=$(sed -nE 's/^issue-([0-9]+)-.*/\1/p' <<<"${2:-}")
  [ -n "$k" ] || k=$(awk -v p="$1" '$1 == p {print $2; exit}' <<<"$CLOSES")   # #762: here-string, không printf | awk exit
  [ -n "$k" ] || return 0
  haltf=$(mktemp -u "${TMPDIR:-/tmp}/sb-mq-note-halt.XXXXXX") || return 0
  if ! SB_GITHUB_HALT_FILE="$haltf" bash "$CARD" --config "$CONFIG" item-id "$k" >/dev/null 2>&1; then
    rm -f "$haltf"; return 0
  fi
  rm -f "$haltf"
  gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ⚠ PR #$1 left the queue
Did: the merge queue dropped PR #$1 before batching
❌ Not done: $3
Next: the PR needs a fresh review and \`approved-head:<sha40>\` for its current head, then the \`$LABEL\` label again" || true
}
# ---- route (dùng cho kết quả của train và cho PR đã merge còn nhãn) ---------------------------------------------------------------------
# ROUTE_ROWS: "<mốc> <PR> <head> <nhánh>" mỗi dòng (đợt hiện tại + PR merged còn nhãn): card_of / head_of đọc từ đây.
ROUTE_ROWS=""
# CLOSES: "<PR> <issue>" mỗi dòng, PR có closingIssuesReferences trỏ ĐÚNG MỘT issue của repo này (#637). resolve_card dùng khi nhánh không
# theo mẫu issue-<N>- (PR tay, nhánh fix-…), cùng luật với review_approved_head của runner (#607/#614). Lấy cùng lượt `pr list`; resolve_card
# chạy trực tiếp ở shell hiện tại (không qua subshell `$(…)`), hỏi card.sh item-id (có cache) xem issue có nằm trên board không để không ghi
# nhầm lên issue thường ngoài board và vẫn truyền được READ_HALT / ROUTE_HALT lên shell cha khi gặp exit 79.
CLOSES=""
closes_rows() {   # closes_rows <JSON mảng PR của pr list>: in "<PR> <issue>"; 0 hoặc ≥ 2 issue (hay issue repo khác) thì không in
  printf '%s' "$1" | jq -r --arg r "$REPO" '.[] | . as $pr | [(.closingIssuesReferences // [])[]
    | select($r == "" or ((((.repository.owner.login // "") + "/" + (.repository.name // "")) | ascii_downcase) == ($r | ascii_downcase)))
    | .number] | unique | select(length == 1) | "\($pr.number) \(.[0])"'
}
# #762: awk đọc từ here-string, không `printf … | awk '…; exit'`: dưới pipefail, awk thoát ở dòng khớp khi printf còn đang ghi thì printf
# nhận EPIPE/SIGPIPE, hàm trả lỗi dù đã in đúng kết quả, và dưới set -e giết hàng đợi giữa lượt route (đỏ chập chờn khi máy tải nặng;
# tất định khi ROUTE_ROWS lớn hơn bộ đệm ống).
CARD_OF=""
resolve_card() {   # resolve_card <PR>: gán CARD_OF = số thẻ trên board ("" khi không có thẻ); trả 0 = xong, 1 = đọc lỗi (CARD_OF="")
  local k rc=0
  CARD_OF=""
  k=$(awk -v p="$1" '$2 == p {print $4; exit}' <<<"$ROUTE_ROWS" | sed -nE 's/^issue-([0-9]+)-.*/\1/p')
  if [ -n "$k" ]; then CARD_OF="$k"; return 0; fi
  k=$(awk -v p="$1" '$1 == p {print $2; exit}' <<<"$CLOSES")   # nhánh issue-<N>- thắng; không có thì closingIssuesReferences
  [ -n "$k" ] || return 0
  bash "$CARD" --config "$CONFIG" item-id "$k" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then CARD_OF="$k"; return 0; fi
  if [ "$rc" -eq 3 ]; then say "PR #$1 closes #${k}, which is not on the board: routed as a PR without a card"; return 0; fi
  read_failed "$rc" "$1" "whether #${k} is on the board"
  return 1
}
head_of() { awk -v p="$1" '$2 == p {print $3; exit}' <<<"$ROUTE_ROWS"; }
# #637: lỗi đọc GitHub trong lượt route chỉ bỏ PR đó (nhãn giữ, lượt sau route lại), các PR còn lại và merge-queue.attempts vẫn được ghi.
# github-read thoát 79 (halt) thì nhớ lại: route nốt phần không cần đọc rồi thoát 79 (như exit 9 của train).
# ROUTE_HALT: lượt route_one hiện tại gặp halt (đọc hay card_move) ⇒ ghi pending nhưng không tính lần thử (như exit 79 của train).
READ_HALT=0; ROUTE_HALT=0
read_failed() {   # read_failed <rc> <PR> <đọc gì>
  [ "$1" -ne 79 ] || { READ_HALT=1; ROUTE_HALT=1; }
  say "PR #$2: reading $3 failed (github-read exit $1); label kept, the next run routes it again"
}
issue_json() { python3 "$GITHUB_READ" --kind issue -- issue view "$1" ${REPO:+--repo "$REPO"} --json number,title,body,labels,state; }
card_move() {   # card_move <issue> <Status>: lỗi log rồi trả 1 (nhãn giữ lại, lượt sau route lại); 79 nhớ halt, thoát 79 sau khi route xong
  local rc=0
  bash "$CARD" --config "$CONFIG" move "$1" "$2" >/dev/null || rc=$?
  [ "$rc" -ne 79 ] || { READ_HALT=1; ROUTE_HALT=1; say "card move #$1 $2: GitHub reads halted"; return 1; }
  [ "$rc" -eq 0 ] || { say "card move #$1 $2 failed (exit ${rc})"; return 1; }
}
UNLABELED=" "   # #676: PR đã gỡ nhãn trong lượt này (trễ nhất quán của nhãn trên GitHub): không phóng train cho nó nữa
unlabel() { UNLABELED="${UNLABELED}$1 "; gh_w pr edit "$1" ${REPO:+--repo "$REPO"} --remove-label "$LABEL" || true; }
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
# kèm một dòng báo. Chi tiết đầy đủ nằm ở log của train (stdout của queue), không ở comment. Khi route lại từ merge-queue.pending (TOUT đã xoá),
# đọc bản chụp merge-queue.detail.<PR> của lượt trước để không mất chi tiết chặn / lỗi verify.
detail_lines() {
  local raw
  if [ -n "${TOUT:-}" ] && [ -r "$TOUT" ]; then
    raw=$(sed -nE "s/^train-detail: $1 //p" "$TOUT")
  elif [ -r "$QDIR/merge-queue.detail.$1" ]; then
    raw=$(cat "$QDIR/merge-queue.detail.$1")
  else
    return 0
  fi
  [ -n "$raw" ] || return 0
  LC_ALL=C awk -v max=12000 '
    { l = substr($0, 1, 400); if (length($0) > 400) l = l " …"
      if (used + length(l) + 1 > max) { cut = 1; next }
      print l; used += length(l) + 1 }
    END { if (cut) print "… (detail truncated: the full train log is in the merge-queue output)" }' <<<"$raw"
}
# rebuild_or_rebase <PR> <issue> <rebuild|rebase> <why> [tag] [did]: loop:rebuild-N hiện có ≥ rebuild_cap → Blocked 🛡, không thì về Ready.
# tag / did: chữ đầu và dòng Did của comment rebuild (mặc định của verify đỏ; preflight exit 11 truyền chữ riêng, #639).
# Trả 0 chỉ khi các bước bắt buộc (nhãn loop:*, card_move) xong. Lượt route lại (RETRY=1): không comment lại; nhãn loop:* đã gắn ở lượt
# trước (LABEL_DONE=1) thì không gắn lần nữa (không đẩy loop:rebuild-N lên hai lần cho cùng một lần đỏ).
# CARD_RETRY: như RETRY nhưng cho comment trên thẻ; 0 khi lượt trước chưa đọc được thẻ (pending cột 4 = r, CARD_UNREAD=1): thẻ chưa có
# comment nào, nên lượt route lại vẫn comment trên thẻ (comment trên PR thì không lặp).
RETRY=0; LABEL_DONE=0; CARD_RETRY=0; CARD_UNREAD=0; CARD_UNKNOWN=0
rebuild_or_rebase() {
  local p="$1" k="$2" kind="$3" why="$4" tag="${5:-red}" did="${6:-verified the merge-queue batch with super-board-merge-train.sh}" ij labs cur rm=() l det
  det=$(detail_lines "$p")
  if [ "$RETRY" -eq 1 ] && [ "$LABEL_DONE" -eq 1 ]; then card_move "$k" Ready; return; fi
  ij=$(issue_json "$k") || { read_failed $? "$p" "card #${k}"; CARD_UNREAD=1; return 1; }
  labs=$(printf '%s' "$ij" | jq -r '.labels[].name')
  cur=$(printf '%s\n' "$labs" | sed -nE 's/^loop:rebuild-([0-9]+)$/\1/p' | sort -n | tail -1); cur=${cur:-0}
  if [ "$cur" -ge "$REBUILD_CAP" ]; then
    [ "$CARD_RETRY" -eq 1 ] || block_comment "$k" "$p" "🛡" "rebuild_cap ${REBUILD_CAP} reached (loop:rebuild-${cur}) and the merge queue saw ${why}" \
      "train-result for PR #${p}: ${why}${det:+
${det}}" "a person looks at why this card keeps failing, then drags it to Ready"
    card_move "$k" Blocked
    return
  fi
  if [ "$kind" = rebuild ]; then
    for l in $labs; do case "$l" in loop:rebuild-*) rm+=(--remove-label "$l") ;; esac; done
    add_label "$k" "loop:rebuild-$((cur + 1))" ${rm[@]+"${rm[@]}"} || return 1
    LABEL_DONE=1
    [ "$CARD_RETRY" -eq 1 ] || gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ ${tag} · PR #${p} back to Build (loop:rebuild-$((cur + 1)))
Did: ${did}
❌ Not done: ${why}${det:+; the gate / verify lines:
${det}}
Next: Builder fixes $([ "$tag" = red ] && echo "the failing verify" || echo "what the merge gate ${tag} refused"), QA and Review run again" || true
  else
    add_label "$k" "loop:rebase" || return 1
    LABEL_DONE=1
    # tag ở nhánh rebase: `conflict`, hoặc `merge refused` khi train in lời git/hook (gate-exit-5 không file xung đột, #775). Chỉ
    # `merge refused` chép train-detail (một nơi quyết định: route_one chọn tag); conflict không kèm dòng nào, như comment PR.
    [ "${5:-conflict}" = "merge refused" ] || det=""
    [ "$CARD_RETRY" -eq 1 ] || gh_w issue comment "$k" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ ${5:-conflict} · PR #${p} needs a rebase pass (loop:rebase)
Did: merged the PR head into origin/<base> in the merge-queue batch
❌ Not done: ${why}${det:+; the git / hook lines:
${det}}
Next: Builder rebases onto the base, verification green, then Review again" || true
  fi
  card_move "$k" Ready
}
ATTEMPTS="$QDIR/merge-queue.attempts"; ATTEMPT_MAX=3
# merge-queue.pending: "<PR> <head> <kết quả> <0|1|r|u>" (1 = nhãn loop:* đã gắn, r = chưa đọc được thẻ, u = chưa xác minh thẻ có trên
# board không nên chưa ghi gì lên PR/issue) — kết quả kết thúc mà một bước bắt buộc của route lỗi. Lượt sau route lại từ dòng này (không dựng
# train, không verify lại, không lặp comment đã đăng); mỗi lần lỗi tính một lần thử (trừ halt 79; trần 3 → PR rời hàng).
PENDING="$QDIR/merge-queue.pending"
drop_row() {   # drop_row <file> <PR>
  [ -f "$1" ] || return 0
  awk -v p="$2" '$1 != p' "$1" > "$1.tmp" && mv -f "$1.tmp" "$1"
}
BASEMOVED_F="$QDIR/merge-queue.basemoved"
attempt_clear() { drop_row "$ATTEMPTS" "$1"; drop_row "$PENDING" "$1"; drop_row "$BASEMOVED_F" "$1"; rm -f "$QDIR/merge-queue.detail.$1"; }   # PR rời bảng đếm và hàng route lại
# attempt_retry <PR> <kết quả>: kết quả không kết thúc. n+1 cho dòng <PR> <head> (head khác = đếm lại từ 1); n ≥ 3 → PR rời hàng 🛡.
attempt_retry() {
  local p="$1" res="$2" head k="" n why ok=0
  ROUTE_HALT=0
  head=$(head_of "$p")
  n=$(awk -v p="$p" -v h="$head" '$1 == p && $2 == h {print $3; exit}' "$ATTEMPTS" 2>/dev/null || true)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  { awk -v p="$p" '$1 != p' "$ATTEMPTS" 2>/dev/null || true; echo "$p $head $n $(date +%s)"; } > "$ATTEMPTS.tmp" && mv -f "$ATTEMPTS.tmp" "$ATTEMPTS"
  if [ "$n" -lt "$ATTEMPT_MAX" ]; then say "PR #${p}: ${res}; stays queued for the next batch (try ${n}/${ATTEMPT_MAX})"; return 0; fi
  # Chỉ tra thẻ khi đã chạm trần (n < trần không dùng thẻ). Nếu card.sh halt (79): dừng ngay trước block_comment để không ghi nhầm lên
  # issue ngoài board, giữ nhãn + dòng attempts; lỗi khác 79 (69/66): k="" để PR vẫn rời hàng mà không đụng issue chưa xác minh.
  if resolve_card "$p"; then
    k=$CARD_OF
  elif [ "$ROUTE_HALT" -eq 1 ]; then
    say "PR #${p}: GitHub reads halted while checking its card at the retry cap; label kept, the next run retries"
    return 0
  else
    ok=1
  fi
  why="the merge queue ran PR #${p} in ${n} batches without a final result (last: ${res})"
  if [ -n "$k" ]; then
    block_comment "$k" "$p" "🛡" "$why" "train-result for PR #${p}: ${res}" \
      "a person looks at why its batches keep ending in ${res}, then labels the PR ${LABEL} again or drags the card to Ready"
    card_move "$k" Blocked || ok=1
  fi
  # Halt (79) khi chuyển thẻ: như bản cũ thoát 79 ngay tại card_move — PR giữ nhãn và dòng attempts, chưa comment rời hàng (thẻ chưa
  # Blocked); lượt sau (sau --resume) chạm trần lần nữa và chuyển thẻ (comment blocker trên thẻ có thể lặp một lần, như bản cũ).
  if [ "$ROUTE_HALT" -eq 1 ]; then say "PR #${p}: GitHub reads halted while moving card #${k} to Blocked; label kept, the next run retries"; return 0; fi
  gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [blocker] 🛑 left the queue · 🛡 ${why}
Next: a person looks at why, then labels the PR ${LABEL} again${k:+ (card #$k is Blocked)}" || true
  # Trần: PR rời hàng dù card_move / tra thẻ lỗi, để không route lại vô hạn mỗi tick.
  [ "$ok" -eq 0 ] || say "PR #${p}: moving its card to Blocked failed too; the PR leaves the queue anyway (comment above)"
  unlabel "$p"; attempt_clear "$p"
}
# route_one <PR> <kết quả>: một train-result. Nhãn chỉ gỡ khi mọi bước bắt buộc của nhánh trả 0; bước nào lỗi (lỗi đọc qua read_failed)
# thì giữ nhãn, ghi merge-queue.pending và tính một lần thử (halt 79 thì không tính): lượt sau route lại từ pending, chỉ làm lại các bước
# bắt buộc.
route_one() {
  local p="$1" res="$2" k="" st msha ij det title ok=0 head prow tag did src why
  head=$(head_of "$p")
  prow=$(awk -v p="$p" -v h="$head" '$1 == p && $2 == h {print $4; exit}' "$PENDING" 2>/dev/null || true)
  RETRY=0; LABEL_DONE=0; CARD_UNREAD=0; CARD_UNKNOWN=0; ROUTE_HALT=0
  if [ -n "$prow" ] && [ "$prow" != u ]; then RETRY=1; [ "$prow" != 1 ] || LABEL_DONE=1; fi
  CARD_RETRY=$RETRY; [ "$prow" != r ] || CARD_RETRY=0
  case "$res" in
    merged)
      # Không đọc được trạng thái: như GitHub chưa thấy MERGED (nhãn giữ, không tính lần thử); lượt sau recover_merged hoặc train xét lại.
      st=$(python3 "$GITHUB_READ" --kind merge-state -- pr view "$p" ${REPO:+--repo "$REPO"} --json state,mergeCommit,headRefOid) \
        || { read_failed $? "$p" "its merge state"; return 0; }
      if [ "$(printf '%s' "$st" | jq -r .state)" != MERGED ]; then
        k=$(awk -v p="$p" '$2 == p {print $4; exit}' <<<"$ROUTE_ROWS" | sed -nE 's/^issue-([0-9]+)-.*/\1/p')
        say "train says PR #${p} merged but GitHub shows $(printf '%s' "$st" | jq -r .state); label kept${k:+, card #$k left as is}"; return 0
      fi
      # Không tra được thẻ trên board: như chưa đọc được thẻ (giữ nhãn, không pending, không tính lần thử; lượt sau recover_merged xử lý).
      resolve_card "$p" || return 0
      k=$CARD_OF
      if [ -n "$k" ]; then
        msha=$(printf '%s' "$st" | jq -r '.mergeCommit.oid')
        # Thẻ không đọc được: chưa ghi gì cho PR này, nên như chưa route (nhãn giữ, không pending, không tính lần thử); lượt sau
        # recover_merged route lại từ đầu và comment ✅. Không tính lần thử: PR đã merge không bao giờ bị trần đẩy sang Blocked.
        ij=$(issue_json "$k") || { read_failed $? "$p" "card #${k}"; return 0; }
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
    red|gate-exit-11|conflict|gate-exit-2|gate-exit-5|gate-exit-7|gate-exit-8|gate-exit-3)
      # Phải biết chắc PR có thẻ trên board hay không trước mọi lệnh ghi PR/issue (cột u = chưa ghi gì, lượt sau đăng đủ comment + detail).
      if ! resolve_card "$p"; then
        CARD_UNKNOWN=1; ok=1
      else
        k=$CARD_OF
        case "$res" in
          red|gate-exit-11)
            det=$(detail_lines "$p")
            # #639: gate-exit-11 của train là preflight / --dry-run của gate (qa-report, AC) chặn PR trước khi dựng cây; verify đỏ của gate
            # train đã đổi thành `red`. Cùng đường về Build, nhưng comment nói đúng nguồn chặn, không nói verify đỏ khi không suite nào chạy.
            if [ "$res" = red ]; then
              tag=red; did="verified the merge-queue batch; this PR is the one that turns it red"; why="${res} (verify red with this PR in the batch)"
            else
              src=$(printf '%s\n' "$det" | sed -nE 's/^(qa-report|ac-check):.*/\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//')
              tag=preflight; did="the merge gate preflight refused this PR (${src:-exit 11}) before any tree was built; no verify ran"
              why="${res} (merge gate preflight ${src:-exit 11}; no verify ran)"
            fi
            [ "$RETRY" -eq 1 ] || gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ ${tag} · ${res}
Did: ${did}${det:+
${det}}
Next: back to Build${k:+ (card #$k)}" || true
            [ -z "$k" ] || rebuild_or_rebase "$p" "$k" rebuild "$why" "$tag" "$did" || ok=1 ;;
          conflict|gate-exit-2|gate-exit-5)
            # #775: train in gate-exit-5 kèm train-detail `merge-refused: …` từ note_refused (super-board-merge-train.sh; build_chain gọi
            # nó khi git merge thất bại mà `git diff --diff-filter=U` rỗng): chép các dòng đó, chữ "merge refused". gate-exit-5 không có
            # dòng mang tiền tố đó (gate tự thoát 5) và conflict giữ chữ cũ.
            det=$(detail_lines "$p")
            if [ "$res" = gate-exit-5 ] && grep -q '^merge-refused: ' <<<"$det"; then
              tag="merge refused"; why="${res} (a git hook or git refused the local merge commit; no conflicting file)"
            else
              tag=conflict; why="${res} (the base does not merge in cleanly)"; det=""
            fi
            [ "$RETRY" -eq 1 ] || gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ❌ ${tag} · ${res}
Did: merged this PR into origin/<base> for the merge-queue batch${det:+
${det}}
Next: rebase pass${k:+ (card #$k)}" || true
            [ -z "$k" ] || rebuild_or_rebase "$p" "$k" rebase "$why" "$tag" || ok=1 ;;
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
        esac
      fi ;;
    head-moved|gate-exit-6)
      gh_w pr comment "$p" ${REPO:+--repo "$REPO"} --body "[merge-queue] [report] ⚠ head moved · ${res}
Did: the PR head is no longer the approved one (or its branch is gone from origin); the approval is void
Next: a fresh review of the new head, then a new approved-head and the ${LABEL} label" || true ;;
    # #676: train thua đua khi main đang tiến (base dời quá 2 lần trong một train): giữ nhãn, KHÔNG tính lần thử (PR khoẻ không bao giờ
    # bị đẩy sang Blocked vì main tiến nhanh), không comment; lượt sau phóng train mới trên base mới.
    # Chống đói (OCR #676): base-moved liên tiếp đếm riêng ở merge-queue.basemoved (<PR> <head> <n>); lần thứ 5 mới tính MỘT lần thử
    # (attempt_retry: trần 3 ⇒ comment + Blocked 🛡) để người thấy PR không bao giờ thắng đua. Head mới đếm lại.
    base-moved)
      local bm
      bm=$(awk -v p="$p" -v h="$head" '$1 == p && $2 == h {print $3; exit}' "$BASEMOVED_F" 2>/dev/null || true)
      bm=$(( ${bm:-0} + 1 ))
      { awk -v p="$p" '$1 != p' "$BASEMOVED_F" 2>/dev/null || true; echo "$p $head $bm"; } > "$BASEMOVED_F.tmp" && mv -f "$BASEMOVED_F.tmp" "$BASEMOVED_F"
      if [ "$bm" -ge 5 ]; then
        drop_row "$BASEMOVED_F" "$p"
        attempt_retry "$p" "base-moved ${bm} times in a row (origin/${BASE} keeps moving while its train verifies)"; return 0
      fi
      say "PR #${p}: base-moved (origin/${BASE} kept moving during its train, ${bm}/5); stays queued, no attempt counted"; return 0 ;;
    deferred|timeout|gate-exit-4|*) attempt_retry "$p" "$res"; return 0 ;;
  esac
  if [ "$ok" -ne 0 ]; then
    say "PR #${p} (${res}): a routing step failed; label kept, the next run routes it again from merge-queue.pending"
    if [ -n "${TOUT:-}" ] && [ -r "$TOUT" ]; then
      sed -nE "s/^train-detail: $p //p" "$TOUT" > "$QDIR/merge-queue.detail.$p"
    fi
    local col=$LABEL_DONE; [ "$CARD_UNREAD" -eq 0 ] || col=r; [ "$CARD_UNKNOWN" -eq 0 ] || col=u
    { awk -v p="$p" '$1 != p' "$PENDING" 2>/dev/null || true; echo "$p $head $res $col"; } > "$PENDING.new" && mv -f "$PENDING.new" "$PENDING"
    if [ "$ROUTE_HALT" -eq 1 ]; then say "PR #${p}: GitHub reads halted; not counted as a try"; return 0; fi
    attempt_retry "$p" "routing ${res} failed"
    return 0
  fi
  unlabel "$p"; attempt_clear "$p"
}
# ---- train nền theo PR (#676) -----------------------------------------------------------------------------------------------------------
# merge-queue.inflight: "<PR> <head> <ref> <issue đóng|0> <pid> <dir>" mỗi dòng — train của PR đang chạy nền (pid = subshell phóng nó),
# kết quả ở <dir>/out, mã thoát ở <dir>/rc (chỉ ghi khi train thoát bình thường; chết vì tín hiệu thì không có rc).
INFLIGHT="$QDIR/merge-queue.inflight"
TRAINS_DIR="$QDIR/merge-queue.trains"
COLLECTED=" "; HALT_RC=0
in_str() { case "$1" in *" $2 "*) return 0 ;; esac; return 1; }   # in_str "<danh sách cách nhau bởi dấu cách>" <PR>
inflight_alive() {   # inflight_alive <pid>: subshell phóng train còn sống (lệnh vẫn là queue/train: chống pid tái dùng)
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null && ps -o command= -p "$1" 2>/dev/null | grep -Eq 'super-board-merge-(queue|train)'
}
live_inflight() {   # in " <PR> <PR> … " của các dòng inflight có train còn chạy
  local n pid out=" "
  [ -s "$INFLIGHT" ] || { printf ' '; return 0; }
  while read -r n _ _ _ pid _; do
    [ -n "${n:-}" ] || continue
    inflight_alive "$pid" && out="${out}${n} "
  done < "$INFLIGHT"
  printf '%s' "$out"
}
# collect: route mọi train đã xong (có rc, hoặc pid chết). Chạy TRƯỚC recover_merged / pending (A1): ROUTE_ROWS và CLOSES dựng thẳng từ
# dòng inflight (PR đã merge / đóng không còn trong `pr list --state open`). Train exit 79 (GitHub dừng đọc): không route, không tính lần
# thử (như trước #676), HALT_RC=79; exit 9: route các dòng đã có, HALT_RC=9 (79 thắng). Train chết không rc: một lần thử.
collect() {
  [ "$DRY" -eq 0 ] && [ -s "$INFLIGHT" ] || return 0
  local n head ref ci pid dir trc keep="" p res
  while read -r n head ref ci pid dir; do
    [ -n "${n:-}" ] || continue
    if [ ! -f "$dir/rc" ] && inflight_alive "$pid"; then keep="${keep}${n} ${head} ${ref} ${ci} ${pid} ${dir}"$'\n'; continue; fi
    ROUTE_ROWS="${ROUTE_ROWS}0 ${n} ${head} ${ref}"$'\n'
    [ "$ci" = 0 ] || CLOSES="${CLOSES}${n} ${ci}"$'\n'
    COLLECTED="${COLLECTED}${n} "
    TOUT="$dir/out"; trc=$(cat "$dir/rc" 2>/dev/null || true)
    cat "$TOUT" 2>/dev/null || true   # log của queue thấy nguyên kết quả train, như trước
    # stderr của train (log train + merge gate) và của launcher: trước #676 đi thẳng ra stderr của queue (log runner); giữ như vậy trước khi
    # xoá thư mục (audit Antigravity #676).
    cat "$dir/err" "$dir/launch.log" >&2 2>/dev/null || true
    if [ -z "$trc" ]; then
      say "PR #${n}: its train (pid ${pid}) ended without an exit code (killed); one attempt counted"
      attempt_retry "$n" "train died without a result" </dev/null
    elif [ "$trc" -eq 79 ]; then
      say "PR #${n}: train exit 79 (GitHub reads halted); nothing routed, label kept"; HALT_RC=79
    elif ! grep -q '^train-result: ' "$TOUT" 2>/dev/null; then
      if [ "$trc" -eq 4 ]; then say "PR #${n}: train exit 4 (another train holds this PR); nothing ran, no attempt counted"
      else
        say "PR #${n}: train exit ${trc} with no train-result line; one attempt counted"
        attempt_retry "$n" "train exit ${trc} without a train-result" </dev/null
      fi
      [ "$trc" -ne 9 ] || [ "$HALT_RC" -eq 79 ] || HALT_RC=9
    else
      while read -r p res; do
        [ -n "${p:-}" ] || continue
        route_one "$p" "$res" </dev/null
      done < <(sed -nE 's/^train-result: ([0-9]+) (.+)$/\1 \2/p' "$TOUT")
      [ "$trc" -ne 9 ] || [ "$HALT_RC" -eq 79 ] || HALT_RC=9
    fi
    rm -rf "$dir"
  done < "$INFLIGHT"
  printf '%s' "$keep" > "$INFLIGHT.tmp" && mv -f "$INFLIGHT.tmp" "$INFLIGHT"
  TOUT=""
}
# launch_train <PR> <head> <ref>: một train cho MỘT PR (cây main+PR của chính nó), chạy nền, tách khỏi lượt queue này. set +e trong subshell
# (queue chạy set -e); TERM/INT/HUP tới subshell được chuyển xuống đúng train; train chết vì tín hiệu (≥ 129) thì KHÔNG ghi rc ⇒ lượt sau
# thấy pid chết không rc ⇒ một lần thử. 9>&-: train không giữ khoá queue; stdout/stderr của launcher ra file: bên gọi đọc queue qua ống
# không bị train nền giữ ống tới khi xong. Launcher chạy trong SESSION RIÊNG (os.setsid rồi exec bash; macOS không có lệnh setsid):
# launchd (super-board-queue-schedule.sh, không đặt AbandonProcessGroup) giết cả process group của job khi queue thoát — cùng group
# thì mọi train nền chết sau mỗi lượt lịch (OCR #676).
LAUNCHED=()
LAUNCHER='set +e; cpid=""
trap "[ -z \"\$cpid\" ] || kill -TERM \"\$cpid\" 2>/dev/null; wait \"\$cpid\" 2>/dev/null; exit 143" TERM INT HUP
SB_MERGE_CALLER=queue bash "$1" --config "$2" --prs "$3" >"$4/out" 2>"$4/err" </dev/null &
cpid=$!; wait "$cpid"; rc=$?
[ "$rc" -ge 129 ] || { echo "$rc" >"$4/rc.tmp" && mv -f "$4/rc.tmp" "$4/rc"; }'
launch_train() {
  local n="$1" head="$2" ref="$3" dir ci
  mkdir -p "$TRAINS_DIR"
  dir=$(mktemp -d "$TRAINS_DIR/pr${n}.XXXXXX")
  ci=$(awk -v p="$n" '$1 == p {print $2; exit}' <<<"$CLOSES"); ci=${ci:-0}
  python3 -I -c 'import os, sys
os.setsid(); open(sys.argv[-1] + "/session", "w").close()
os.execvp("bash", ["bash", "-c"] + sys.argv[1:])' \
    "$LAUNCHER" merge-queue-launch "$TRAIN" "$CONFIG" "${n}:${head}" "$dir" 9>&- >"$dir/launch.log" 2>&1 </dev/null &
  LAUNCHED+=("$!")
  # Chờ launcher TÁCH session xong (dấu <dir>/session ghi ngay sau os.setsid) rồi mới tiếp / thoát: queue thoát trước đó thì launchd giết cả
  # process group lúc python còn khởi động (~14 ms, lâu hơn khi tải cao) — audit Antigravity #676. Tối đa 5 s.
  local w=0
  while [ ! -e "$dir/session" ] && [ "$w" -lt 250 ]; do sleep 0.02; w=$((w + 1)); done
  [ -e "$dir/session" ] || say "PR #${n}: the train launcher did not report its own session within 5 s (a later kill of this run's process group may take it)"
  echo "${n} ${head} ${ref} ${ci} $! ${dir}" >> "$INFLIGHT"
  say "PR #${n}: train started for ${n}:${head} (pid $!, ${dir})"
}

collect
if [ "$READ_HALT" -eq 1 ] || [ "$HALT_RC" -eq 79 ]; then say "GitHub reads halted while routing finished trains; no new train this run"; exit 79; fi
if [ "$HALT_RC" -eq 9 ]; then say "a train exited 9 (verification readiness): routed what it reported; stopping"; exit 9; fi
LIVE=$(live_inflight)

# PR merged còn nhãn (train merge xong, queue chết trước khi route): route `merged` sau khi GitHub xác nhận MERGED. --dry-run chỉ in.
# PR vừa thu ở collect hoặc đang có train sống thì bỏ qua (kết quả của train sẽ route nó).
recover_merged() {
  local merged_json n head ref st
  merged_json=$(python3 "$GITHUB_READ" --kind array -- pr list ${REPO:+--repo "$REPO"} --state merged --base "$BASE" --label "$LABEL" \
                  --limit 50 --json number,headRefName,headRefOid,closingIssuesReferences) || exit $?
  CLOSES="${CLOSES}$(closes_rows "$merged_json")"$'\n'
  while read -r n head ref; do
    [ -n "${n:-}" ] || continue
    if in_str "$COLLECTED" "$n" || in_str "$LIVE" "$n"; then continue; fi
    if [ "$DRY" -eq 1 ]; then say "would route PR #${n} as merged (merged while still labelled ${LABEL})"; continue; fi
    ROUTE_ROWS="${ROUTE_ROWS}0 ${n} ${head} ${ref}"$'\n'
    say "PR #${n} merged but still labelled ${LABEL}: routing it as merged"
    route_one "$n" merged </dev/null
  done < <(printf '%s' "$merged_json" | jq -r '.[] | "\(.number) \(.headRefOid) \(.headRefName)"')
}
recover_merged
PRS_JSON=$(python3 "$GITHUB_READ" --kind array -- pr list ${REPO:+--repo "$REPO"} --state open --base "$BASE" --label "$LABEL" --limit 200 \
             --json number,headRefName,headRefOid,isDraft,closingIssuesReferences) || exit $?
CLOSES="${CLOSES}$(closes_rows "$PRS_JSON")"$'\n'
NOW=$(date +%s)
# Mốc gắn nhãn (REST timeline) nhớ trong merge-queue.labeled theo <PR> <head>, nên các tick sau không đọc lại timeline. #676: labeled phản
# ánh MỌI PR còn trong hàng (cả PR đang có train, PR chờ route lại) cho runner (RUNAWAY) / status; PR vừa gỡ nhãn trong lượt này thì bỏ.
CANDS=""
while read -r n head ref; do
  [ -n "${n:-}" ] || continue
  in_str "$UNLABELED" "$n" || CANDS="${CANDS}${n} ${head} ${ref}"$'\n'
done < <(printf '%s' "$PRS_JSON" | jq -r '.[] | select(.isDraft != true) | "\(.number) \(.headRefOid) \(.headRefName)"')
CANDS=${CANDS%$'\n'}
for n in $(printf '%s' "$PRS_JSON" | jq -r '.[] | select(.isDraft == true) | .number'); do say "PR #${n} is a draft; skipped (label kept)"; done
LABELED="$QDIR/merge-queue.labeled"
if [ -z "$CANDS" ]; then rm -f "$LABELED"; say "nothing queued"; exit 0; fi
ROWS=""   # "<mốc gắn nhãn epoch> <PR> <head> <nhánh>" mỗi dòng, cũ nhất trước
load_rows() {
  local n head ref at tl cache="" out=""
  [ -z "$ROWS" ] || return 0
  [ ! -r "$LABELED" ] || cache=$(cat "$LABELED")
  while read -r n head ref; do
    [ -n "${n:-}" ] || continue
    at=$(awk -v n="$n" -v h="$head" '$1 == n && $2 == h {print $3; exit}' <<<"$cache")   # #762: không printf | awk exit
    if [ -z "$at" ]; then
      tl=$(python3 "$GITHUB_READ" --kind json -- api "repos/${SLUG}/issues/${n}/timeline?per_page=100" --paginate --slurp) || exit $?
      at=$(printf '%s' "$tl" | jq -r --arg l "$LABEL" '[.[][]? | select(.event == "labeled" and .label.name == $l) | .created_at | fromdateiso8601] | max // empty')
      [ -n "$at" ] || { say "PR #${n}: no labeled event for ${LABEL} in its timeline; counting it as labelled now"; at=$NOW; }
    fi
    out="${out}${at} ${n} ${head} ${ref}"$'\n'
  done < <(printf '%s\n' "$CANDS")
  ROWS=$(printf '%s' "$out" | sort -n -k1,1 -k2,2)
  printf '%s\n' "$ROWS" | awk 'NF {print $2, $3, $1, $4}' > "$LABELED.tmp" && mv -f "$LABELED.tmp" "$LABELED"
}
load_rows

# PR có dòng merge-queue.pending cùng head: kết quả đã có, chỉ route lại các bước bắt buộc (không phóng train, không verify lại). PR vừa thu
# ở collect thì không route lại lần nữa trong lượt này. PR đang có train sống: không phóng thêm.
LAUNCH_ROWS=""
while read -r at n head ref; do
  [ -n "${n:-}" ] || continue
  res=""; [ ! -s "$PENDING" ] || res=$(awk -v p="$n" -v h="$head" '$1 == p && $2 == h {print $3; exit}' "$PENDING")
  if [ -n "$res" ]; then
    in_str "$COLLECTED" "$n" && continue
    if [ "$DRY" -eq 1 ]; then say "would route PR #${n} again (${res}, a routing step failed last run)"; continue; fi
    ROUTE_ROWS="${ROUTE_ROWS}0 ${n} ${head} ${ref}"$'\n'
    say "PR #${n}: routing ${res} again (a routing step failed last run)"
    route_one "$n" "$res" </dev/null
    continue
  fi
  if in_str "$LIVE" "$n"; then say "PR #${n}: its train is still running; not started again"; continue; fi
  LAUNCH_ROWS="${LAUNCH_ROWS}${at} ${n} ${head} ${ref}"$'\n'
done < <(printf '%s\n' "$ROWS")
if [ "$READ_HALT" -eq 1 ]; then say "GitHub reads halted while routing PRs from an earlier run; no train this run"; exit 79; fi

# Duyệt: đi từ PR cũ nhất, đọc comment duyệt từng PR (GraphQL); PR duyệt sai rời hàng ngay lượt này. Phóng tối đa
# merge_queue.max_trains (mặc định 3) trừ số train còn chạy; PR dư nằm yên trong hàng (lượt sau), không tính lần thử.
MAX_TRAINS=$(posint "$(echo "$CONFIG_JSON" | jq -r '.merge_queue.max_trains // empty')" 3)
NLIVE=0; for n in $LIVE; do NLIVE=$((NLIVE + 1)); done
SLOTS=$((MAX_TRAINS - NLIVE)); NB=0
while read -r at n head ref; do
  [ -n "${n:-}" ] || continue
  comments=$(python3 "$GITHUB_READ" --kind object -- pr view "$n" ${REPO:+--repo "$REPO"} --json comments) || exit $?
  # Cùng luật với review_approved_head của runner (#227, #605): một file jq chung, comment approved-head cuối cùng của người có
  # quyền ghi thắng; kèm `approved-by:` thì nguồn duyệt chéo phải đủ trường và không tự duyệt.
  verdict=$(printf '%s' "$comments" | jq -r -f "$APPROVED_HEAD_JQ") || { say "cannot evaluate approvals for PR #$n (jq failed); left in the queue"; continue; }
  IFS=$'\t' read -r vstate approved vwhy <<<"$verdict" || true
  if [ -z "$approved" ]; then reject "$n" "no \`approved-head:<sha40>\` from an OWNER/MEMBER/COLLABORATOR on this PR" "$ref"; continue; fi
  if [ "$vstate" != ok ]; then reject "$n" "approved-head ${approved:0:7}: ${vwhy:-invalid approval}" "$ref"; continue; fi
  if [ "$approved" != "$head" ]; then reject "$n" "approved-head ${approved:0:7} is not the PR head ${head:0:7} (pushed after approval)" "$ref"; continue; fi
  # #605 (audit T0066 vòng 2): task_id của approved-by là lời khai; chỉ tính khi antigravity-pm có audit pass với auditedHead == head.
  case "$vwhy" in
    owner) ;;
    # audit T0066 vòng 3: --pr = head chưa có object trong repo thì fetch refs/pull/<n>/head trước; fetch lỗi → loại như cũ.
    task:?*) if ! ( cd "$REPO_PATH" && python3 "$AUDIT_CHECK" --pr "$n" "${vwhy#task:}" "$head" ) 2>/dev/null; then
               reject "$n" "approved-by task_id ${vwhy#task:} has no antigravity-pm audit pass with auditedHead ${head:0:7}" "$ref"; continue
             fi ;;
    *) reject "$n" "approved-head ${approved:0:7}: approval source unreadable" "$ref"; continue ;;
  esac
  if [ "$NB" -ge "$SLOTS" ]; then say "PR #${n}: ${NLIVE} train(s) running + ${NB} started ≥ merge_queue.max_trains ${MAX_TRAINS}; waits for the next run"; continue; fi
  NB=$((NB + 1))
  if [ "$DRY" -eq 1 ]; then echo "merge-queue: would run super-board-merge-train.sh --prs ${n}:${head}"; continue; fi
  ROUTE_ROWS="${ROUTE_ROWS}${at} ${n} ${head} ${ref}"$'\n'
  launch_train "$n" "$head" "$ref"
done < <(printf '%s' "$LAUNCH_ROWS")
[ "$NB" -gt 0 ] || say "no new train this run"
[ "$DRY" -eq 0 ] || exit 0

# ---- --wait (test / chạy tay): chờ các train vừa phóng rồi thu luôn ----------------------------------------------------------------------
# Thả khoá TRƯỚC khi chờ (lượt queue khác vẫn chạy được), lấy lại khoá (chờ có trần) rồi thu như đầu lượt. Chỉ ở đây queue chuyển TERM /
# INT / HUP xuống các subshell phóng train (chúng chuyển tiếp xuống train). Không có --wait (cách super-board-run.sh merge_queue_due và
# plist của super-board-queue-schedule.sh gọi queue, grep 01/11): queue thoát ngay, lượt sau thu.
[ "$WAIT" -eq 1 ] && [ "${#LAUNCHED[@]}" -gt 0 ] || exit 0
forward_stop() { local t; for t in ${LAUNCHED[@]+"${LAUNCHED[@]}"}; do kill -TERM "$t" 2>/dev/null || true; done; exit "$1"; }
trap 'forward_stop 143' TERM; trap 'forward_stop 130' INT; trap 'forward_stop 129' HUP
exec 9>&-
for t in "${LAUNCHED[@]}"; do wait "$t" 2>/dev/null || true; done
exec 9>>"$LOCK"
python3 -I -c '
import fcntl, sys, time
end = time.time() + float(sys.argv[1])
while True:
    try:
        fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB); break
    except OSError:
        if time.time() > end: sys.exit(3)
        time.sleep(0.2)
' "${SB_MQ_WAIT_LOCK_S:-600}" || { say "--wait: could not take ${LOCK} again; the next run routes the finished trains"; exit 0; }
echo "queue $$" > "$LOCK.pid"
READ_HALT=0; HALT_RC=0; ROUTE_ROWS=""; COLLECTED=" "
collect
if [ "$READ_HALT" -eq 1 ] || [ "$HALT_RC" -eq 79 ]; then say "GitHub reads halted while routing: routed what needed no read; stopping"; exit 79; fi
if [ "$HALT_RC" -eq 9 ]; then say "train exit 9 (verification readiness): routed what it reported; stopping"; exit 9; fi
exit 0
