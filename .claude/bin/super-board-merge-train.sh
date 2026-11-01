#!/usr/bin/env bash
# super-board-merge-train.sh — gom nhiều PR đã qua review thành một đợt: verify MỘT lần, rồi merge từng PR bằng merge gate (#110).
#
# VÌ SAO: 19/10 có 6 PR sẵn sàng cùng lúc; merge gate chạy --force-full riêng cho từng PR trên máy đã quá tải, một lần hết 900 s
# (REG-DK-ALL-01 TIMEOUT, PR #99 đỏ oan). Gate vẫn là nơi quyết định merge (policy, người duyệt, khoá, --match-head-commit);
# train chỉ chứng minh trước cây gộp, để gate khỏi chạy lại đúng bằng chứng đó.
#
# Cách chạy:
#   1. Mọi kích thước (cả 1 PR, Pha 2 hàng đợi merge) đi cùng một đường. Trước khi dựng cây: gate `--preflight` từng PR (policy, qa-report,
#      AC, migrations, head; vài giây, không verify/merge). PR rớt preflight rời đợt với `train-result: <N> gate-exit-K`.
#   2. Dựng scratch = origin/<base> + lần lượt các head (merge, đúng thứ tự --prs) rồi chạy verify_commands một lần.
#      PR không merge sạch vào chuỗi thì bị loại (kết quả `conflict`, exit 5 như gate). Hook của repo vẫn chạy trên commit gộp; hook từ
#      chối mà không có file xung đột thì kết quả `gate-exit-5` kèm lời hook ở `train-detail:` (#740/#775), không ghi `conflict`.
#   3. Đỏ: chia đôi tìm PR gây lỗi (tập đã xanh + nửa trái, rồi + nửa phải). PR đỏ bị loại, phần còn lại vẫn được chứng minh.
#   4. Ghi biên nhận `<head sha> <cây sau khi merge head đó vào chuỗi>` cho các PR xanh, rồi gọi gate cho từng PR theo thứ tự với
#      `--train-receipt`. Gate tự merge base hiện tại với head: cây trùng biên nhận thì bỏ verify, khác (base đã dời, head đổi,
#      PR đứng trước không merge) thì verify như thường. Biên nhận chỉ rút ngắn, không bao giờ nới tiêu chuẩn.
#      Trước khi merge gì, mỗi PR xanh qua gate --dry-run (policy/approval, không verify lại); PR bị chặn ra khỏi chuỗi và chuỗi còn lại
#      được verify lại (R11), nên main không dừng ở cây chưa verify vì một PR sau bị policy chặn.
#      PR sạch với base mà chỉ xung đột với PR đứng trước: `deferred`, ở lại Review chờ wave sau (R8). Head ghim không còn trong repo: exit 6.
#      Điều biên nhận chứng minh là cây của CHUỖI đầy đủ (đích cuối của đợt) đã qua verify; trạng thái trung gian của main giữa hai
#      lần merge (mới PR đầu) không được verify riêng.
#
# Usage: super-board-merge-train.sh --config <config.json> --prs <N[:sha],M[:sha],...> [gate flags: --lock-timeout S --stale-after S ...]
#
# Exit: 0 mọi PR đã merge · 11 có PR đỏ (về Build; dòng `train-red: <N>`) · mã thoát gate đầu tiên khác 0 (gate chặn PR) ·
#       12 verify hết giờ sau một lần chạy lại: PR chưa chứng minh ở lại Review, wave sau thử lại, không PR nào bị quy là đỏ ·
#       5 có PR conflict, không PR nào đỏ/hết giờ · 79/9 của github-read và readiness đi thẳng tới caller.
#       6 có PR đã dời head khỏi sha duyệt (`--prs N:sha`): PR đó rời đợt, dòng `head-moved`, ở lại Review chờ review lại.
#       #676: gate được gọi với --require-receipt; base dời sau verify (gate exit 12) thì train fetch base mới và chứng minh lại phần chưa
#       merge NGOÀI khoá merge, tối đa 2 lần; lần thứ 3 phần còn lại `base-moved` (exit 12 như hết giờ: ở lại hàng, queue không tính lần thử).
#       Mỗi PR một dòng `train-result: <N> <merged|red|conflict|deferred|timeout|base-moved|head-moved|gate-exit-K>` trên stdout.
#       Dòng `approval-request:|human-gate:|needs-you:|ac-check:|qa-report:|verification-readiness:` của gate (preflight, --dry-run,
#       merge) và ≤ 20 dòng cuối của verify đỏ (của train, hoặc stderr của gate khi gate đỏ) in lại thành `train-detail: <N> <dòng>`
#       để bên gọi (super-board-merge-queue.sh) chép nguyên văn vào comment issue. Mọi lời gọi gate mang SB_MERGE_CALLER=train.
#       13: queue bật + SB_BOARD_WORKER=1 mà bên gọi không phải queue (SB_MERGE_CALLER=queue): worker gắn nhãn merge-queue thay vì gọi train.
#       4 không kèm train-result: một train khác đang giữ claim của một PR trong --prs (<git-common-dir>/super-board/merge-train.claim.<PR>,
#       #676 — train khác PR chạy song song được); chưa PR nào chạy.
#       PR có head không còn trong repo (nhánh bị force-push / xoá, fork không fetch được): `train-result: <N> gate-exit-6`, phần còn lại chạy tiếp.
# ponytail: preflight lọc PR bị policy chặn trước verify; gate --dry-run sau verify vẫn còn (R11) cho phần preflight không thấy (người duyệt
#           đổi ý giữa chừng): PR bị chặn ở đó ra khỏi chuỗi rồi phần còn lại verify lại, thêm một lượt verify mỗi vòng như vậy.
set -euo pipefail
export SB_GITHUB_READ_STRICT=1
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GITHUB_READ="$HERE/super-board-github-read.py"
GATE="$HERE/super-board-merge-gate.sh"

CONFIG=""; PRS=""; PASS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --prs)    PRS="$2"; shift 2 ;;
    *) PASS+=("$1"); shift ;;
  esac
done
[ -n "$CONFIG" ] && [ -e "$CONFIG" ] || { echo "config not found: ${CONFIG:-<unset>}" >&2; exit 66; }
# F4 (fix-round1-contract.md, "Cờ worker board"): queue bật = (merge_queue.enabled hoặc SB_MERGE_QUEUE=1) VÀ worker_backend "claude-p" hoặc
# "workflow" (thiếu khoá = "workflow", như super-board-run.sh; #453); SB_MERGE_QUEUE=0 luôn tắt. Khi đó worker board (SB_BOARD_WORKER=1) chỉ gắn nhãn
# merge-queue; train chỉ chạy cho super-board-merge-queue.sh (SB_MERGE_CALLER=queue). Đọc SB_MERGE_CALLER của bên gọi TRƯỚC khi train
# tự đặt nó = train ở dưới.
# ponytail: backend codex coi như queue tắt (lane codex tự merge qua gate); thêm khi codex có lịch rút hàng.
if [ "${SB_BOARD_WORKER:-}" = 1 ] && [ "${SB_MERGE_CALLER:-}" != queue ] && [ "${SB_MERGE_QUEUE:-}" != 0 ] \
   && jq -e --arg env "${SB_MERGE_QUEUE:-}" '((.worker_backend // "workflow") | IN("claude-p", "workflow")) and ($env == "1" or .merge_queue.enabled == true)' \
        "$CONFIG" >/dev/null 2>&1; then
  echo "merge-queue: label the PR merge-queue instead of calling the gate directly"
  echo "[merge-train] merge queue is on: a board worker labels the PR merge-queue; only super-board-merge-queue.sh runs the train" >&2
  exit 13
fi
LIST=(); WANT=()
IFS=',' read -r -a RAW <<<"$PRS"
for p in "${RAW[@]}"; do
  # `N` hoặc `N:<sha40>` (#228 R1): sha là head đã duyệt; PR có head hiện tại khác sha đó rời đợt, không bao giờ merge head chưa ai review.
  [[ "$p" =~ ^[0-9]+(:[0-9a-f]{40})?$ ]] || { echo "--prs wants comma-separated PR numbers (N or N:<head sha>), got '${p}'" >&2; exit 64; }
  LIST+=("${p%%:*}"); WANT+=("$([[ "$p" == *:* ]] && echo "${p#*:}" || echo "")")
done
[ "${#LIST[@]}" -gt 0 ] || { echo "--prs <N,M,...> is required" >&2; exit 64; }
# Gate biết nó được train gọi (lane E: khi hàng đợi merge bật, gate từ chối lời gọi trực tiếp). Đặt cứng, không kế thừa giá trị khác.
export SB_MERGE_CALLER=train

say() { echo "[merge-train] $*" >&2; }
# git_retry <git args…>: #676 — nhiều train song song cùng git common dir ⇒ fetch / worktree add có thể đua khoá ref / config.lock; thử tối
# đa 3 lần, nghỉ 0,5 s. Lỗi thật (mạng, ref không có) vẫn trả 1 sau lần thứ 3.
git_retry() { local t; for t in 1 2 3; do git "$@" && return 0; [ "$t" -eq 3 ] || sleep 0.5; done; return 1; }
# run_gate <PR> <out-stream 1|2> <gate args…>: chạy merge gate, GRC = exit của nó. Stdout của gate đi nguyên vẹn ra luồng cũ (merge: stdout,
# vì `ac-open: #N` / "verify skipped" là của bên gọi; preflight / --dry-run: stderr), stderr của gate đi ra stderr ngay khi gate in
# (tee, #453; giữ trong $GATE_ERR cho đuôi verify đỏ), rồi các dòng approval-request/human-gate/needs-you/ac-check/qa-report/verification-readiness
# (verification-readiness gate in ra stderr) in thêm thành `train-detail: <PR> <dòng>` trên stdout.
GATE_OUT=$(mktemp); GATE_ERR=$(mktemp); GATE_RC=$(mktemp); DETAIL_DIR=$(mktemp -d)
run_gate() {
  local p="$1" to="$2" line try; shift 2
  GRC=0
  # #453: stderr của gate đi qua tee: ra stderr của train NGAY khi gate in (log runner thấy tiến độ), vẫn giữ trong $GATE_ERR.
  # Exit của gate đi qua $GATE_RC vì pipe trả exit của tee.
  # #676: nhiều train song song cùng git common dir ⇒ `git fetch` của gate (merge-gate.sh, trước khoá merge) có thể đua khoá ref và thoát 1.
  # Gate không bao giờ thoát 1 sau `gh pr merge`, nên exit 1 kèm lời khoá ref/.lock được thử lại tối đa 3 lần (nghỉ 0,5 s).
  for try in 1 2 3; do
    { grc=0; bash "$GATE" "$@" >"$GATE_OUT" 8>&- || grc=$?; echo "$grc" >"$GATE_RC"; } 2>&1 | tee "$GATE_ERR" >&2
    GRC=$(cat "$GATE_RC" 2>/dev/null || echo 1)
    [ "$GRC" -eq 1 ] && [ "$try" -lt 3 ] && grep -Eq "cannot lock ref|Unable to create '[^']*\.lock'" "$GATE_ERR" || break
    say "merge gate for PR #${p} hit a git ref lock (another train fetching); retrying (${try}/3)"; sleep 0.5
  done
  if [ "$to" = 1 ]; then cat "$GATE_OUT"; else cat "$GATE_OUT" >&2; fi
  while IFS= read -r line; do
    case "$line" in
      approval-request:*|human-gate:*|needs-you:*|ac-check:*|qa-report:*|verification-readiness:*) echo "train-detail: $p $line" ;;
    esac
  done < <(cat "$GATE_OUT" "$GATE_ERR")
  return 0
}
# detail_tail <PR> <file> [nhãn]: ≤ 20 dòng cuối không rỗng của log, bỏ mã màu, thành `train-detail: <PR> <nhãn: ><dòng>` (queue chép vào
# comment issue). Không nhãn = đuôi log verify đỏ; nhãn `merge-refused` = lời git/hook của note_refused (queue nhận ra bằng tiền tố đó).
# Log là dữ liệu tuỳ ý và đi vào comment issue CÔNG KHAI: mọi dòng qua redact_secrets() của kit (regression_checklist.py).
# Không nạp được bộ che (sb_redact_text, super-board-verify-flags.sh) thì giấu cả đoạn (đóng an toàn), không bao giờ đăng log thô.
detail_tail() {
  local raw pre="${3:+$3: }"
  raw=$(LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$2" 2>/dev/null | grep -av '^[[:space:]]*$' | tail -20 || true)
  [ -n "$raw" ] || return 0
  if printf '%s\n' "$raw" | sb_redact_text > "$DETAIL_DIR/.redacted"; then
    sed "s/^/train-detail: $1 ${pre}/" "$DETAIL_DIR/.redacted"
  else
    echo "train-detail: $1 ${pre}($([ -n "${3:-}" ] && echo "git/hook message" || echo "verify log tail") hidden: the DevKit secret redactor could not be loaded)"
  fi
}
trap 'rm -rf "$GATE_OUT" "$GATE_ERR" "$DETAIL_DIR"' EXIT
. "$HERE/super-board-verify-flags.sh"
CONFIG_JSON=$(cat "$CONFIG")
printf '%s\n' "$CONFIG_JSON" | python3 "$HERE/super-board-verification-ready.py" --config -
BASE=$(echo "$CONFIG_JSON" | jq -r '.base_branch // "main"')
REPO=$(echo "$CONFIG_JSON" | jq -r '.repo.remote // ""' | sed -E 's#^https?://github\.com/##; s#\.git$##')
REPO_PATH=$(echo "$CONFIG_JSON" | jq -r '.repo.path // "."')
export SB_REPO_PATH="$REPO_PATH"
VERIFY=()
while IFS= read -r line; do
  if [[ "$line" =~ [^[:space:]] ]]; then VERIFY+=("$line"); fi
done < <(echo "$CONFIG_JSON" | jq -r '.verify_commands[] | select(test("\\S"))')
[ "${#VERIFY[@]}" -gt 0 ] || { echo "verification-readiness: verify_commands yielded no usable shell commands." >&2; exit 9; }
python3 "$GITHUB_READ" --check

# #676: một train mỗi PR (không còn một train mỗi repo): claim `merge-train.claim.<PR>` (mkdir nguyên tử + file pid) cho từng PR của
# --prs (khử trùng, tăng dần). Hai train khác PR chạy song song; hai train cùng một PR thì train sau thoát 4 trước mọi train-result (queue:
# không kết thúc, không tính lần thử). Hai PR không bao giờ ghi main song song: khoá merge.lock của merge gate bao `gh pr merge`.
# claim_live dưới đây quyết định reap: pid trong claim phải sống VÀ lệnh của nó chứa super-board-merge-train (chống pid tái dùng); sai
# thì claim bị gỡ (train bị SIGKILL để lại). Claim là thư mục, không phải fd mở, nên tiến trình con (verify, gate) không giữ nó.
TRAIN_COMMON=$(cd "$REPO_PATH" && cd "$(git rev-parse --git-common-dir)" && pwd -P) || { say "cannot resolve the git common dir of ${REPO_PATH}"; exit 1; }
mkdir -p "$TRAIN_COMMON/super-board"
TRAIN_STATE="$TRAIN_COMMON/super-board/merge-train.$$.state"
CLAIMED=()
release_claims() {
  local d
  for d in ${CLAIMED[@]+"${CLAIMED[@]}"}; do [ "$(cat "$d/pid" 2>/dev/null || true)" != "$$" ] || rm -rf "$d" 2>/dev/null || true; done
  CLAIMED=()
}
claim_live() {   # claim_live <dir>: 0 khi claim thuộc một merge train còn sống. Chưa có pid: sống chỉ trong 10 s đầu (train vừa mkdir,
  # chưa kịp ghi pid); quá 10 s không pid = train chết giữa mkdir và ghi pid (OCR #676) ⇒ reap được.
  local pid="" t age
  for t in 1 2 3; do pid=$(cat "$1/pid" 2>/dev/null || true); [ -z "$pid" ] || break; sleep 0.05; done
  if [ -z "$pid" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || date +%s) ))
    [ "$age" -lt 10 ]; return
  fi
  kill -0 "$pid" 2>/dev/null && ps -o command= -p "$pid" 2>/dev/null | grep -q 'super-board-merge-train'
}
trap 'release_claims; rm -rf "$GATE_OUT" "$GATE_ERR" "$DETAIL_DIR"' EXIT
for p in $(printf '%s\n' "${LIST[@]}" | sort -un); do
  d="$TRAIN_COMMON/super-board/merge-train.claim.$p"
  if ! mkdir "$d" 2>/dev/null; then
    if claim_live "$d"; then say "another merge train holds PR #${p} (${d}); nothing ran"; exit 4; fi
    # Reap nguyên tử: chỉ một train đổi tên được thư mục claim chết (hai train cùng thấy claim chết thì train thua không xoá nhầm
    # claim mới của train thắng — OCR #676).
    if mv "$d" "$d.reap.$$" 2>/dev/null; then say "reaped the claim of a dead merge train on PR #${p}"; rm -rf "$d.reap.$$"; fi
    mkdir "$d" 2>/dev/null || { say "another merge train took PR #${p} meanwhile; nothing ran"; exit 4; }
  fi
  echo "$$" >"$d/pid.tmp" && mv -f "$d/pid.tmp" "$d/pid"; CLAIMED+=("$d")
done
# TERM/INT/HUP (queue chuyển xuống khi nó bị dừng): thoát qua trap EXIT để dọn scratch.
trap 'exit 143' TERM; trap 'exit 130' INT; trap 'exit 129' HUP

REPO_ABS=$(cd "$REPO_PATH" && pwd -P)
MAIN_WT=$(git -C "$REPO_ABS" worktree list --porcelain | sed -n '1s/^worktree //p')
BASE_WT=${MAIN_WT:-$REPO_ABS}
mkdir -p "$BASE_WT/.claude/worktrees"
SCRATCH=$(mktemp -d "$BASE_WT/.claude/worktrees/.train-scratch-XXXXXX")
RECEIPT=$(mktemp); VLOG=$(mktemp); CHAIN_ERR=$(mktemp)
cleanup() { git -C "$BASE_WT" worktree remove --force "$SCRATCH" 2>/dev/null || true; rm -rf "$SCRATCH" "$RECEIPT" "$VLOG" "$CHAIN_ERR" "$GATE_OUT" "$GATE_ERR" "$GATE_RC" "$DETAIL_DIR"; rm -f "$TRAIN_STATE" "$TRAIN_STATE.tmp"; release_claims; }
trap cleanup EXIT
# Trạng thái train cho Agent Office / super-board-status.py (#562): `pid`, `started_at`, `step` (gate | merge) và mỗi PR một dòng
# `pr <N> <sha> <ref>`. Ghi nguyên tử, chỉ sau khi giữ khoá và đã đặt trap dọn: train thoát exit 4 (khoá bận) không bao giờ đụng file của train
# đang chạy. Bị SIGKILL thì file mồ côi, người đọc bỏ qua vì `pid` đã chết. Lỗi ghi không bao giờ làm hỏng train.
TRAIN_STARTED=$(date +%s)
train_state() {
  local i
  { echo "pid $$"; echo "started_at ${TRAIN_STARTED}"; echo "step $1"
    for i in "${!LIST[@]}"; do echo "pr ${LIST[$i]} ${HEADS[$i]:-} ${REFS[$i]:-}"; done
  } >"$TRAIN_STATE.tmp" 2>/dev/null && mv -f "$TRAIN_STATE.tmp" "$TRAIN_STATE" 2>/dev/null || true
}

train_state gate
# Head của từng PR, ghim một lần: verify và biên nhận thuộc đúng commit này (gate còn --match-head-commit lúc merge).
HEADS=(); REFS=(); KEEP=(); MOVED=()
for i in "${!LIST[@]}"; do
  p="${LIST[$i]}"
  # Lấy output trước rồi mới `read`: `read <<<"$(…)" || exit $?` kiểm exit của `read`, mất exit 79 (halt) / 9 của github-read.
  head_out=$(python3 "$GITHUB_READ" --kind head -- pr view "$p" ${REPO:+--repo "$REPO"} --json headRefName,headRefOid \
               -q '.headRefName + " " + .headRefOid') || exit $?
  read -r ref sha <<<"$head_out"
  [ -n "${sha:-}" ] || { say "could not read the head of PR #${p}"; exit 1; }
  if [ -n "${WANT[$i]}" ] && [ "${WANT[$i]}" != "$sha" ]; then
    say "PR #${p} head is ${sha}, not the approved ${WANT[$i]}: it leaves the batch and needs a fresh review"
    MOVED+=("$p"); continue
  fi
  KEEP+=("$p"); REFS+=("$ref"); HEADS+=("$sha")
done
for p in ${MOVED[@]+"${MOVED[@]}"}; do echo "train-result: $p head-moved"; done
[ "${#KEEP[@]}" -gt 0 ] || exit 6
LIST=("${KEEP[@]}"); train_state gate
# Preflight (Pha 2, M6): kiểm rẻ của gate cho từng PR trước khi dựng cây nào. PR rớt (policy cần người 7/8, qa-report/AC 11, đóng 3,
# head dời 6…) rời đợt, không tốn lượt verify của cả đợt; 79/9 đi thẳng tới caller.
BLOCKED=(); DRYRC=0; PF_LIST=(); PF_REFS=(); PF_HEADS=(); PREMERGED=()
for i in "${!LIST[@]}"; do
  p="${LIST[$i]}"
  run_gate "$p" 2 --config "$CONFIG" --pr "$p" --expect-head "${HEADS[$i]}" --preflight ${PASS[@]+"${PASS[@]}"}
  case "$GRC" in
    # Qua preflight = exit 0 + dòng `preflight: ok`. Exit 0 không có dòng đó = gate thấy PR đã MERGED: rời chuỗi, kết quả `merged`.
    0) if grep -q '^preflight: ok' "$GATE_OUT"; then PF_LIST+=("$p"); PF_REFS+=("${REFS[$i]}"); PF_HEADS+=("${HEADS[$i]}")
       else say "PR #${p} is already merged (preflight exit 0 without 'preflight: ok')"; PREMERGED+=("$p"); fi ;;
    79|9) echo "train-result: $p gate-exit-${GRC}"; exit "$GRC" ;;
    *) BLOCKED+=("$p:$GRC"); say "PR #${p} fails the gate preflight (exit ${GRC}); it leaves the batch before any tree is built"
       [ "$DRYRC" -ne 0 ] || DRYRC=$GRC ;;
  esac
done
# early_results: kết quả đã chốt trước khi dựng cây (PR đã merge, PR rớt preflight / hỏng ref) — in trước mọi lối thoát sớm, để bên gọi
# luôn có train-result cho mọi PR đã nhận (Antigravity audit B).
early_results() {
  for p in ${PREMERGED[@]+"${PREMERGED[@]}"}; do echo "train-result: $p merged"; done
  for b in ${BLOCKED[@]+"${BLOCKED[@]}"}; do echo "train-result: ${b%%:*} gate-exit-${b##*:}"; done
}
if [ "${#PF_LIST[@]}" -eq 0 ]; then early_results; exit "$DRYRC"; fi
if ! git_retry -C "$REPO_PATH" fetch origin "$BASE" --quiet; then
  say "cannot fetch origin/${BASE}; every PR waits for the next batch"
  early_results; for p in "${PF_LIST[@]}"; do echo "train-result: $p deferred"; done
  exit 1
fi
# Từng PR một: nhánh không còn trên origin (fork, nhánh bị xoá) không làm hỏng cả đợt. Nhánh không fetch được thì thử refs/pull/<N>/head
# (GitHub giữ ref này cho cả PR từ fork). R9: SHA đã ghim không còn trong repo (nhánh bị force-push sau lúc đọc) = head đã dời, như gate
# exit 6: chỉ PR đó rời đợt (`gate-exit-6`), phần còn lại verify/merge tiếp.
LIST=(); REFS=(); HEADS=()
for i in "${!PF_LIST[@]}"; do
  p="${PF_LIST[$i]}"
  git_retry -C "$REPO_PATH" fetch origin "${PF_REFS[$i]}" --quiet 2>/dev/null \
    || git_retry -C "$REPO_PATH" fetch origin "refs/pull/${p}/head" --quiet 2>/dev/null \
    || say "could not fetch ${PF_REFS[$i]} (or pull/${p}/head) of PR #${p}; using the head if it is already here"
  if git -C "$REPO_PATH" cat-file -e "${PF_HEADS[$i]}^{commit}" 2>/dev/null; then
    LIST+=("$p"); REFS+=("${PF_REFS[$i]}"); HEADS+=("${PF_HEADS[$i]}")
  else
    say "head ${PF_HEADS[$i]} of PR #${p} is not in the repo (branch rewritten or gone); the review evidence is void, it leaves the batch"
    BLOCKED+=("$p:6"); [ "$DRYRC" -ne 0 ] || DRYRC=6
  fi
done
if [ "${#LIST[@]}" -eq 0 ]; then early_results; exit "$DRYRC"; fi
train_state gate
BASE_SHA=$(git -C "$REPO_PATH" rev-parse --verify -q "origin/${BASE}^{commit}") || { say "cannot resolve origin/${BASE}"; exit 1; }
head_of() { local i; for i in "${!LIST[@]}"; do [ "${LIST[$i]}" = "$1" ] && { echo "${HEADS[$i]}"; return 0; }; done; return 1; }

# edited_review_stale <PR>: #643 — PR có test sửa đã duyệt mà origin/<base> (BASE_SHA hiện tại) không còn là tổ tiên head ⇒ duyệt cũ: 0.
# 1 = còn đúng (hoặc không có test sửa). Lỗi khác của bộ kiểm: thoát train với mã đó (như trước #676).
edited_review_stale() {
  local emeta et_rc=0
  emeta=$(mktemp)
  gh pr view "$1" ${REPO:+--repo "$REPO"} --json labels,files,comments >"$emeta" 2>/dev/null || printf '{}' >"$emeta"
  bash "$HERE/super-board-install-edited-test-approval.sh" --has-edited-tests "$emeta" "$(head_of "$1")" >/dev/null 2>&1 || et_rc=$?
  rm -f "$emeta"
  case "$et_rc" in 0) ;; 1) return 1 ;; *) exit "$et_rc" ;; esac
  ! git -C "$REPO_PATH" merge-base --is-ancestor "$BASE_SHA" "$(head_of "$1")"
}
# #643: duyệt test sửa mà base đã đi trước head thì rời đợt trước khi dựng scratch. Không làm đỏ cả chuỗi.
for p in "${LIST[@]}"; do
  if edited_review_stale "$p"; then
    say "PR #${p}: edited-test review is stale before the chain"
    early_results
    echo "train-result: $p gate-exit-2"
    exit 2
  fi
done

git_retry -C "$REPO_PATH" worktree add --detach "$SCRATCH" "$BASE_SHA" --quiet 2>/dev/null || { say "could not create the train scratch worktree"; exit 1; }
# Cùng cách chuẩn bị scratch như merge gate: DevKit + config cục bộ bị ignore. Cài một lần; reset --hard giữ file bị ignore.
for c in "$REPO_PATH/universal-agent-devkit" "$REPO_PATH/.agents/devkit" "${MAIN_WT:-$REPO_PATH}/universal-agent-devkit" "${MAIN_WT:-$REPO_PATH}/.agents/devkit"; do
  if [ -f "$c/bin/install.sh" ]; then
    bash "$c/bin/install.sh" -t "$SCRATCH" -a claude -y --no-githooks >"$VLOG" 2>&1 8>&- \
      || say "DevKit install into the scratch tree failed: $(tail -3 "$VLOG" | tr '\n' ' ')"
    git -C "$SCRATCH" checkout -q -- . 2>/dev/null || true
    break
  fi
done
bash "$HERE/super-board-scratch-config.sh" "$REPO_PATH" "$SCRATCH" || true
for cmd in "${VERIFY[@]}"; do
  for p in .agents/devkit/bin/post-fix-gate.py universal-agent-devkit/bin/post-fix-gate.py; do
    if [[ "$cmd" == *"$p"* ]] && [ ! -f "$SCRATCH/$p" ]; then
      echo "verification-readiness: the scratch tree has no ${p} (the DevKit could not be installed there) — an environment problem, not a PR; nothing merged." >&2
      exit 9
    fi
  done
done

# build_chain <PR...>: scratch = base + các head theo thứ tự, bằng `git merge` thật: hook của repo vẫn chạy trên commit gộp (chỉ đạo trên
# #740: không tắt hook trong train/gate; hook phải tự nhận commit gộp sạch, như guard-check của GeelyEx2 sau #181).
# 0: CHAIN_TREES = "<head> <cây sau khi gộp head đó vào chuỗi>" từng bước (biên nhận cho gate).
# 1: một head không merge được: CHAIN_FAIL = PR đó, CHAIN_WHY = lý do. CHAIN_CONFLICT=1 khi có file xung đột thật; 0 khi git/hook từ chối
#    commit gộp mà không có file xung đột (#740/#775: trước đây stderr bị nuốt, PR thành deferred/conflict không lý do). Lời git/hook ở
#    $CHAIN_ERR (ghi ra file, không `$(…)`: hook để tiến trình nền giữ ống thì `$(…)` treo, review #772).
CHAIN_FAIL=""; CHAIN_WHY=""; CHAIN_CONFLICT=0; CHAIN_TREES=()
build_chain() {
  local p files why
  CHAIN_FAIL=""; CHAIN_WHY=""; CHAIN_CONFLICT=0; CHAIN_TREES=()
  git -C "$SCRATCH" reset -q --hard "$BASE_SHA"; git -C "$SCRATCH" clean -qfd 2>/dev/null || true
  for p in "$@"; do
    if ! git -C "$SCRATCH" merge --no-edit --quiet "$(head_of "$p")" >"$CHAIN_ERR" 2>&1 8>&-; then
      files=$(git -C "$SCRATCH" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ' || true)
      if [ -n "$files" ]; then
        CHAIN_CONFLICT=1; CHAIN_WHY="conflicts: ${files% }"
      else
        # Lý do của hook thường ở dòng ĐẦU (tail cắt mất khi hook in nhiều dòng); bỏ dòng "Not committing merge…" git tự thêm.
        # Lời hook là dữ liệu tuỳ ý và log train vào manifest run: qua bộ che secret như train-detail. `sed -n` (không `head`): đọc hết
        # ống, không SIGPIPE dưới pipefail.
        why=$(sed -e '/^Not committing merge/d' -e '/^[[:space:]]*$/d' "$CHAIN_ERR" | sed -n '1,8p' | sb_redact_text | tr '\n' ' ' | cut -c1-600) \
          || why="(git/hook message hidden: the DevKit secret redactor could not be loaded)"
        CHAIN_WHY="a git hook or git itself refused the local merge commit (no conflicting file): ${why}"
      fi
      git -C "$SCRATCH" merge --abort 2>/dev/null || true
      CHAIN_FAIL="$p"; return 1
    fi
    CHAIN_TREES+=("$(head_of "$p") $(git -C "$SCRATCH" rev-parse 'HEAD^{tree}')")
  done
  return 0
}
# note_refused <PR>: PR một mình cũng bị git/hook từ chối commit gộp (không có file xung đột, lời ở $CHAIN_ERR của lượt build_chain vừa
# rồi): kết quả `gate-exit-5` — đúng mã merge gate thoát khi gộp base vào scratch bị từ chối (GeelyEx2 #179), nên queue và runner route
# như gate (rebase pass: Builder tự gộp base với commit hợp lệ với hook). Lời hook thành train-detail (qua bộ che secret của detail_tail).
REFUSED=()
note_refused() {
  # Bỏ dòng trắng TRƯỚC khi lấy 20 dòng đầu; hook im lặng (thoát khác 0, không in gì) vẫn có một dòng merge-refused để queue nhận ra.
  sed -e '/^Not committing merge/d' -e '/^[[:space:]]*$/d' "$CHAIN_ERR" | sed -n '1,20p' > "$DETAIL_DIR/.refused-src" || true
  [ -s "$DETAIL_DIR/.refused-src" ] || echo "(a git hook refused the local merge commit without printing a reason)" > "$DETAIL_DIR/.refused-src"
  detail_tail "$1" "$DETAIL_DIR/.refused-src" merge-refused > "$DETAIL_DIR/refused-$1"
  REFUSED+=("$1")
}
# verify_timed_out <rc>: verify hết giờ chứ không đỏ. Cùng tiêu chí với is_verify_timeout của merge gate: exit 124; gate đã in KẾT LUẬN thì chỉ khi
# mọi suite đỏ là TIMEOUT; lệnh khác (không có dòng kết luận) thì log chứa "TIMEOUT after" / "quá giới hạn".
# Thân hàm là subshell tắt pipefail: log lớn làm `grep -q` thoát sớm, printf nhận SIGPIPE, pipeline trả 141 (#579).
verify_timed_out() (
  set +o pipefail
  local plain
  [ "$1" -eq 124 ] && return 0
  plain=$(LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$VLOG" 2>/dev/null) || return 1
  if printf '%s\n' "$plain" | grep -aqE "KẾT LUẬN|POST-FIX AUDIT GATE VERDICT"; then
    printf '%s\n' "$plain" | LC_ALL=C awk '/^[[:space:]]*\[ \] [^|]*\|/ { if ($0 ~ /^[[:space:]]*\[ \] TIMEOUT([[:space:]]+\(HANG\))?[[:space:]]*\|/) t++; else o++ } END { exit !(t > 0 && o == 0) }'
    return
  fi
  printf '%s\n' "$plain" | grep -aqE "TIMEOUT after|quá giới hạn"
)
# single_red_test <log>: #578 — in đường dẫn test khi verify đỏ CHỈ vì đúng một test của một suite REG-DK-ALL-* (#616: gồm shard): gate REJECT, lớp tĩnh đạt, đúng một dòng
# suite `[ ] FAIL | REG-DK-ALL-*`, đúng một dòng đuôi `| ✖ <test>.sh` (đuôi thụt lề của test lồng nhau không tính). Mọi trường hợp khác
# (tên test mất vì log bị cắt, hai test trở lên, suite khác đỏ, đường dẫn lạ) thoát 1: đỏ ngay như cũ. Log là dữ liệu: đường dẫn phải khớp mẫu hẹp.
single_red_test() {
  local t
  t=$(LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$1" 2>/dev/null | LC_ALL=C awk '
    /(KẾT LUẬN CỔNG POST-FIX AUDIT|POST-FIX AUDIT GATE VERDICT):.*REJECT/ { rej = 1 }
    /^[[:space:]]*• (Lớp tĩnh|Static checks) \(.*\): / { if (static != 2) static = ($0 ~ /: (đạt|passed)[[:space:]]*$/) ? 1 : 2 }
    /^[[:space:]]*\[ \] [^|]*\|/ {
      rows++; split($0, parts, "|"); st = parts[1]; sub(/^[[:space:]]*\[ \][[:space:]]*/, "", st); sub(/[[:space:]]+$/, "", st)
      id = parts[2]; sub(/^[[:space:]]+/, "", id); sub(/[[:space:]].*$/, "", id)
      if (st != "FAIL" || id !~ /^REG-DK-ALL-[A-Z0-9-]+$/) bad = 1   # #616: REG-DK-ALL-01 và các suite shard REG-DK-ALL-<NHÓM>-01
    }
    /^[[:space:]]*\| ✖ [^[:space:]]+[[:space:]]*$/ { line = $0; sub(/^[[:space:]]*\| ✖ /, "", line); sub(/[[:space:]]*$/, "", line); if (!(line in seen)) { seen[line] = 1; n++; name = line } }
    END { if (rej && static == 1 && rows == 1 && !bad && n == 1) print name; else exit 1 }') || return 1
  [[ "$t" =~ ^[A-Za-z0-9_][A-Za-z0-9_./-]*\.sh$ ]] && [[ "$t" != *..* ]] && {
    # run_impacted.sh prints the path relative to the kit; in agent-workbench the kit sits under universal-agent-devkit/ (#616, T0070 F3)
    if [ -f "$SCRATCH/$t" ]; then printf '%s\n' "$t"
    elif [ -f "$SCRATCH/universal-agent-devkit/$t" ]; then printf '%s\n' "universal-agent-devkit/$t"
    else return 1; fi
  }
}
# rerun_one_test <test>: chạy đúng test đó một lần trên cây scratch của lượt verify (cùng môi trường và hàng đợi tải), ghi vào $VLOG. 0 = xanh.
# ponytail: không có trần thời gian riêng (test tự giới hạn), nâng khi gặp test treo; một lần, không lặp lại tới khi xanh.
rerun_one_test() {
  ( cd "$SCRATCH" && unset POSTFIX_GATE_FORCE_FULL CLAUDE_PROJECT_DIR TARGET_DIR && export DEVKIT_SLOT_PRIORITY="${DEVKIT_SLOT_PRIORITY:-merge}" \
      DEVKIT_GATE_SLOT_WAIT_S="${DEVKIT_GATE_SLOT_WAIT_S:-1800}" \
      && python3 "$HERE/super-board-heavy-slot.py" -- bash "$1" ) >>"$VLOG" 2>&1 8>&-
}
FLAKY=()
# note_flaky <PR> <test>: ghi rõ flaky vào PR (comment) và vào thẻ riêng của test (một thẻ bug mở, không trùng). Lỗi gh chỉ cảnh báo: PR đã xanh.
note_flaky() {
  local p="$1" t="$2" found
  echo "train-flaky: $p $t"
  gh pr comment "$p" ${REPO:+--repo "$REPO"} --body "[reviewer] [flaky] Merge-train: \`$t\` (REG-DK-ALL-01) đỏ ở lượt verify đầu, xanh khi chạy lại riêng đúng test đó một lần; các kiểm khác đều đạt. Ghi nhận flaky (nhạy tải), PR không bị gán red." >/dev/null 2>&1 \
    || say "could not comment the flaky note on PR #${p}"
  found=$(gh issue list ${REPO:+--repo "$REPO"} --state open --label bug --search "\"$t\" flaky in:title" --json number --jq length 2>/dev/null) || found=""
  [[ "$found" =~ ^[0-9]+$ ]] || { say "could not look up the flaky card for ${t}; not filing"; return 0; }
  [ "$found" = 0 ] || return 0
  gh issue create ${REPO:+--repo "$REPO"} --label bug --title "🐛 [fix] test flaky: ${t}" \
    --body "## Problem
Merge-train (PR #${p}) thấy \`${t}\` đỏ ở lượt verify REG-DK-ALL-01 rồi xanh khi chạy lại riêng: nhạy tải, đỏ không ổn định.

## Context
- **Where:** \`${t}\`

## Fix
Làm test ổn định (bỏ phụ thuộc thời gian/tải) thay vì để merge-train chạy lại.

## Acceptance Criteria
- [ ] Test xanh ổn định khi máy tải cao

## Risk
🟢 Low — chỉ đụng test

## Blocked by
- None." >/dev/null 2>&1 || say "could not file the flaky card for ${t}"
}
# verify_set <PR...>: 0 chuỗi dựng được và mọi verify_commands xanh · 1 đỏ · 2 chuỗi không dựng được (không phải lỗi đỏ của PR)
#                     · 3 hết giờ sau một lần chạy lại (máy quá tải, không quy lỗi cho PR nào).
verify_set() {
  local cmd run_cmd busy_line rc try merged p emeta
  build_chain "$@" || { say "PR #${CHAIN_FAIL} does not merge into the chain of [$*]: ${CHAIN_WHY}"; return 2; }
  # #643: clean -qfd giữ file ignore. Xoá rồi cài lại theo đúng các PR của lượt này, kẻo nửa chuỗi trước còn sót.
  rm -f "$SCRATCH/.claude/audit-gate/approved_tests.json"
  for p in "$@"; do
    emeta=$(mktemp)
    gh pr view "$p" ${REPO:+--repo "$REPO"} --json labels,files,comments >"$emeta" 2>/dev/null || printf '{}' >"$emeta"
    bash "$HERE/super-board-install-edited-test-approval.sh" \
      --scratch "$SCRATCH" --sha "$(head_of "$p")" --meta "$emeta" --pr "$p" --top "$REPO_PATH"
    rm -f "$emeta"
  done
  merged=$(git -C "$SCRATCH" rev-parse HEAD)
  for cmd in "${VERIFY[@]}"; do
    cmd=$(sb_verify_inject_flags "$cmd" "$BASE")
    run_cmd=$(sb_verify_inject_flags "$cmd" "$BASE" json)
    # #647: đêm và merge-train không được dừng ở suite đỏ đầu. Chỉ lệnh post-fix-gate nhận cờ này.
    case "$cmd" in
      *post-fix-gate*)
        case " $cmd " in
          *" --no-fail-fast "*) ;;
          *) cmd="$cmd --no-fail-fast" ;;
        esac
        case " $run_cmd " in
          *" --no-fail-fast "*) ;;
          *) run_cmd="$run_cmd --no-fail-fast" ;;
        esac
        ;;
    esac
    try=1
    while :; do
      say "verify [$*]: ${cmd}"
      rc=0
      # CLAUDE_PROJECT_DIR / TARGET_DIR của bên gọi (cây chính) thắng cwd trong get_project_dir của post-fix-gate: bỏ để verify kiểm scratch.
      # #676: lệnh post-fix-gate gọi THẲNG như merge gate (run_verify_cmd_inner): bọc trong super-board-heavy-slot.py đặt
      # DEVKIT_SLOT_ADVISORY_HELD=1 nên post-fix-gate bỏ qua pool heavy — nhiều train song song sẽ lách trần suite nặng. Lệnh khác vẫn qua slot.
      local slot_wrap=(python3 "$HERE/super-board-heavy-slot.py" --)
      [[ "$run_cmd" != *"post-fix-gate.py"* ]] || slot_wrap=()
      ( cd "$SCRATCH" && unset POSTFIX_GATE_FORCE_FULL CLAUDE_PROJECT_DIR TARGET_DIR && export DEVKIT_SLOT_PRIORITY="${DEVKIT_SLOT_PRIORITY:-merge}" \
          DEVKIT_GATE_SLOT_WAIT_S="${DEVKIT_GATE_SLOT_WAIT_S:-1800}" \
          && DEVKIT_LANG="${DEVKIT_LANG:-vi}" ${slot_wrap[@]+"${slot_wrap[@]}"} bash -c "$run_cmd" ) >"$VLOG" 2>&1 8>&- || rc=$?
      [ "$rc" -ne 0 ] || break
      # T0056: post-fix-gate thoát 4 kèm JSON .busy == true (hàng đợi gate / khoá dự án bận): trả 3 NGAY, không retry (tránh 1800s × 2 chạm trần 3600s).
      if [ "$rc" -eq 4 ]; then
        busy_line=$(LC_ALL=C grep -a '^{.*"exit_code"' "$VLOG" 2>/dev/null | tail -1 || true)
        if [ -n "$busy_line" ] && printf '%s' "$busy_line" | jq -e '.exit_code == 4 and .busy == true' >/dev/null 2>&1; then
          say "verify busy (exit 4) for [$*]; keeping PRs in Review without retry"
          return 3
        fi
      fi
      if verify_timed_out "$rc"; then
        # Suite bị giết giữa chừng có thể để lại file sửa dở: trả cây về đúng commit đã dựng rồi chạy lại đúng một lần, như merge gate.
        if [ "$try" -eq 1 ] && git -C "$SCRATCH" reset -q --hard "$merged" 2>/dev/null; then
          say "verify timed out (exit ${rc}); retrying once"; try=2; continue
        fi
        say "verify timed out (exit ${rc}) for [$*]; not blaming any PR"
        return 3
      fi
      # #578: đỏ chỉ vì đúng một test của REG-DK-ALL-01 (nhạy tải): chạy lại riêng test đó một lần. Xanh = flaky, verify coi như đạt;
      # đỏ lần hai (hay không đủ điều kiện) = red như mọi lần. Không nới: hai test trở lên / suite khác đỏ không vào đường này.
      if flaky_test=$(single_red_test "$VLOG"); then
        say "verify red only by ${flaky_test} (REG-DK-ALL-01); re-running that test once"
        if rerun_one_test "$flaky_test"; then
          case " ${FLAKY[*]-} " in *" $flaky_test "*) ;; *) FLAKY+=("$flaky_test") ;; esac; say "${flaky_test} passed on re-run: flaky, not blaming any PR"; break
        fi
        say "${flaky_test} red on re-run too"; echo "[merge-train] re-ran ${flaky_test}: red again" >>"$VLOG"
      fi
      say "red [$*]: $(tail -3 "$VLOG" | tr '\n' ' ' | cut -c1-300)"
      return 1
    done
  done
  return 0
}

GOOD=(); RED=(); GATERED=(); CONFLICT=(); DEFERRED=()   # BLOCKED / DRYRC: đã khởi tạo ở preflight
# Một PR không merge sạch vào base + các PR trước: bỏ ra trước, rồi mới chứng minh phần còn lại.
# Sạch với base mà chỉ xung đột với PR đứng trước (R8): không phải lỗi của PR, ở lại Review chờ wave sau (lúc đó base đã có PR trước).
# Git/hook từ chối commit gộp (không file xung đột): một mình cũng bị → note_refused (gate-exit-5); chỉ trong chuỗi → deferred như R8.
# Mọi nhánh ghi lý do vào log (#740/#775).
# classify_unchained <PR>: PR vừa không dựng được vào một chuỗi (lý do ở CHAIN_WHY của lượt build_chain vừa rồi) — dựng lại một mình
# trên base: được ⇒ DEFERRED (R8); không ⇒ CONFLICT (có file xung đột) hoặc note_refused (git/hook từ chối). Dùng ở vòng ứng viên và
# trong solve (chuỗi GOOD + PR khác chuỗi ứng viên khi một PR giữa chừng bị loại).
classify_unchained() {
  local chain_why=$CHAIN_WHY
  if build_chain "$1"; then
    DEFERRED+=("$1"); say "PR #$1 merges into origin/${BASE} alone but not after the PRs before it (${chain_why}); deferred to the next wave"
  elif [ "$CHAIN_CONFLICT" -eq 1 ]; then
    CONFLICT+=("$1"); say "PR #$1 does not merge into origin/${BASE}: ${CHAIN_WHY}"
  else
    note_refused "$1"; say "PR #$1: ${CHAIN_WHY}; not a content conflict (result gate-exit-5, as the merge gate exits here)"
  fi
}
# solve <PR...>: GOOD dài ra bằng các PR xanh; PR đỏ vào RED. Đỏ thì chia đôi, đúng một PR đỏ thì đó là thủ phạm.
# Hết giờ (3) dừng cả chia đôi (ABORT): PR chưa chứng minh được không bị quy là đỏ. Chuỗi không dựng được (2) ở đúng một PR → classify_unchained.
ABORT=0
solve() {
  [ "$#" -gt 0 ] && [ "$ABORT" -eq 0 ] || return 0
  local rc=0
  verify_set ${GOOD[@]+"${GOOD[@]}"} "$@" || rc=$?
  case "$rc" in
    0) GOOD+=("$@"); return 0 ;;
    3) ABORT=1; return 0 ;;
  esac
  if [ "$#" -eq 1 ]; then
    # Đỏ đúng một PR: $VLOG lúc này là log của lệnh verify đỏ với PR này (lượt sau ghi đè), giữ đuôi của nó cho train-detail.
    if [ "$rc" -eq 2 ]; then classify_unchained "$1"
    else RED+=("$1"); detail_tail "$1" "$VLOG" > "$DETAIL_DIR/red-$1"; fi
    return 0
  fi
  local half=$(( $# / 2 )) all=("$@")
  solve "${all[@]:0:$half}"
  solve "${all[@]:$half}"
}
in_list() { local x="$1" e; shift; for e in "$@"; do [ "$e" = "$x" ] && return 0; done; return 1; }
PENDING=()   # PR chưa chứng minh vì verify hết giờ; vòng R11 / lượt chứng minh lại ghi đè CANDS nên phải giữ riêng
note_unproven() {
  local p
  for p in ${CANDS[@]+"${CANDS[@]}"}; do
    in_list "$p" ${GOOD[@]+"${GOOD[@]}"} ${RED[@]+"${RED[@]}"} ${CONFLICT[@]+"${CONFLICT[@]}"} \
      ${REFUSED[@]+"${REFUSED[@]}"} ${DEFERRED[@]+"${DEFERRED[@]}"} ${PENDING[@]+"${PENDING[@]}"} || PENDING+=("$p")
  done
}
# prove <PR...>: chứng minh trên BASE_SHA hiện tại: chuỗi ứng viên (R8), solve, rồi R11. Xong: GOOD = chuỗi đã chứng minh, RECEIPT = cây sau
# từng head. PROVE_MOVED=1 khi gate --dry-run thấy base đã dời (exit 12): GOOD là tập cần chứng minh lại. Trả 0 mọi lúc (set -e vẫn bật
# bên trong; bên gọi đọc cờ, không đọc mã trả).
# R11: biên nhận chỉ chứng minh cây của CHUỖI ĐẦY ĐỦ. PR sau bị gate chặn giữa đợt (policy cần người, exit 7…) sẽ để main dừng ở một cây
# chưa ai verify. Nên trước khi merge gì: gate --dry-run từng PR xanh (biên nhận dry = cây merge(base, head), nên không verify lại, chỉ chạy
# policy/approval); PR bị chặn ra khỏi chuỗi và phần còn lại được chứng minh lại. Train một PR bỏ vòng này (#676: không có PR thứ hai nào để
# main dừng giữa chừng; gate merge thật vẫn chạy đủ policy).
# ponytail: gate chặn sau preflight (đua với người duyệt/chờ khoá) vẫn có thể để main ở cây đã verify của tiền tố chuỗi trước đó; nâng lên khi
#           cần tuyệt đối: merge các PR bằng một ref-update duy nhất thay vì từng gate.
# base_really_moved: gate --require-receipt vừa thoát 12. Fetch lại origin/<base>: 0 khi base THẬT SỰ khác BASE_SHA (PR khác vừa merge) hoặc
# không fetch được (để vòng dời base xử lý). 1 khi base đứng yên: cây của gate khác biên nhận vì lý do khác — gate gộp head+base còn train
# gộp base+head, với file merge=union thứ tự dòng khác (review #676 P1). Khi đó bên gọi để gate tự verify như trước #676, không lặp mãi.
base_really_moved() {
  git_retry -C "$REPO_PATH" fetch origin "$BASE" --quiet || return 0
  [ "$(git -C "$REPO_PATH" rev-parse --verify -q "origin/${BASE}^{commit}" || true)" != "$BASE_SHA" ]
}
PROVE_MOVED=0
prove() {
  local p j
  PROVE_MOVED=0; CANDS=(); GOOD=(); ABORT=0
  train_state gate
  for p in "$@"; do
    if build_chain ${CANDS[@]+"${CANDS[@]}"} "$p"; then CANDS+=("$p"); else classify_unchained "$p"; fi
  done
  [ "${#CANDS[@]}" -eq 0 ] || solve "${CANDS[@]}"
  while [ "${#GOOD[@]}" -gt 1 ]; do
    : >"$RECEIPT"
    for p in "${GOOD[@]}"; do
      echo "$(head_of "$p") $(git -C "$SCRATCH" merge-tree --write-tree "$BASE_SHA" "$(head_of "$p")" 2>/dev/null || echo none)" >>"$RECEIPT"
    done
    NEWGOOD=(); DROPPED=0; j=0
    for p in "${GOOD[@]}"; do
      run_gate "$p" 2 --config "$CONFIG" --pr "$p" --expect-head "$(head_of "$p")" --train-receipt "$RECEIPT" --dry-run --require-receipt ${PASS[@]+"${PASS[@]}"}
      if [ "$GRC" -eq 12 ] && ! base_really_moved; then
        say "PR #${p}: origin/${BASE} did not move but the gate's tree differs from the train receipt (merge orientation, e.g. merge=union); the gate verifies it itself"
        run_gate "$p" 2 --config "$CONFIG" --pr "$p" --expect-head "$(head_of "$p")" --train-receipt "$RECEIPT" --dry-run ${PASS[@]+"${PASS[@]}"}
      fi
      case "$GRC" in
        0) NEWGOOD+=("$p") ;;
        79|9) early_results; echo "train-result: $p gate-exit-${GRC}"; exit "$GRC" ;;
        # Base dời giữa dry run: chứng minh lại PR đã qua dry run + PR chưa tới lượt; PR vừa bị chặn ở lượt này (BLOCKED) KHÔNG vào lại
        # (OCR #676: không merge PR đã bị chặn, không in hai kết quả cho một PR).
        12) say "origin/${BASE} moved during the dry run of PR #${p}"; note_unproven
            GOOD=(${NEWGOOD[@]+"${NEWGOOD[@]}"} "${GOOD[@]:$j}"); PROVE_MOVED=1; return 0 ;;
        *) BLOCKED+=("$p:$GRC"); DROPPED=1; say "PR #${p} is blocked by the merge gate (exit ${GRC}); the chain is proved again without it"
           [ "$RC" -ne 0 ] || RC=$GRC ;;
      esac
      j=$((j + 1))
    done
    [ "$DROPPED" -eq 1 ] || break
    note_unproven
    CANDS=(${NEWGOOD[@]+"${NEWGOOD[@]}"}); GOOD=(); ABORT=0
    [ "${#CANDS[@]}" -eq 0 ] || solve "${CANDS[@]}"
  done
  note_unproven
  # Biên nhận: cây sau từng head của chuỗi GOOD (đúng tập vừa qua verify xanh ở lượt solve gần nhất có thêm PR).
  if [ "${#GOOD[@]}" -gt 0 ]; then
    build_chain "${GOOD[@]}" || { say "internal: the verified chain no longer builds (#${CHAIN_FAIL}: ${CHAIN_WHY})"; exit 1; }
    printf '%s\n' "${CHAIN_TREES[@]}" >"$RECEIPT"
  fi
  return 0
}

# Merge: từng PR của GOOD qua gate với --require-receipt (#676). Gate thoát 12 = origin/<base> đã dời sau khi train verify (PR khác vừa
# merge): train KHÔNG để gate verify trong khoá merge, mà fetch base mới, kiểm lại #643, chứng minh lại phần CHƯA merge ngoài khoá (prove:
# chia đôi như lượt đầu) rồi merge tiếp. Tối đa 2 lần base dời mỗi train; lần thứ 3 thì phần còn lại `base-moved` (ở lại hàng, queue không
# đếm lần thử).
RC=$DRYRC; MOVES=0; MERGED_OK=(); GATEX=(); BASEMOVED=(); TODO=("${LIST[@]}")
while [ "${#TODO[@]}" -gt 0 ]; do
  prove "${TODO[@]}"
  TODO=()
  if [ "$PROVE_MOVED" -eq 1 ]; then
    TODO=(${GOOD[@]+"${GOOD[@]}"})
  else
    train_state merge
    i=0
    for p in ${GOOD[@]+"${GOOD[@]}"}; do
      run_gate "$p" 1 --config "$CONFIG" --pr "$p" --expect-head "$(head_of "$p")" --train-receipt "$RECEIPT" --require-receipt ${PASS[@]+"${PASS[@]}"}
      if [ "$GRC" -eq 12 ] && ! base_really_moved; then
        say "PR #${p}: origin/${BASE} did not move but the gate's tree differs from the train receipt (merge orientation, e.g. merge=union); the gate verifies it itself"
        run_gate "$p" 1 --config "$CONFIG" --pr "$p" --expect-head "$(head_of "$p")" --train-receipt "$RECEIPT" ${PASS[@]+"${PASS[@]}"}
      fi
      case "$GRC" in
        0)     MERGED_OK+=("$p"); echo "train-result: $p merged"; for t in ${FLAKY[@]+"${FLAKY[@]}"}; do note_flaky "$p" "$t"; done ;;
        79|9)  early_results; echo "train-result: $p gate-exit-${GRC}"; exit "$GRC" ;;   # R7: halt / readiness của gate đi thẳng tới caller
        11)    echo "train-result: $p red"; echo "train-red: $p"; GATERED+=("$p")   # R7: verify riêng của gate đỏ = PR về Build, có dòng train-red
               detail_tail "$p" "$GATE_ERR" ;;   # gate in đuôi log verify đỏ ra stderr
        12)    TODO=("${GOOD[@]:$i}"); say "origin/${BASE} moved before PR #${p} merged"; break ;;
        *)     GATEX+=("$p"); echo "train-result: $p gate-exit-${GRC}"; [ "$RC" -ne 0 ] || RC=$GRC ;;
      esac
      i=$((i + 1))
    done
  fi
  [ "${#TODO[@]}" -gt 0 ] || break
  MOVES=$((MOVES + 1))
  NEW_BASE=""
  if [ "$MOVES" -le 2 ] && git_retry -C "$REPO_PATH" fetch origin "$BASE" --quiet; then
    NEW_BASE=$(git -C "$REPO_PATH" rev-parse --verify -q "origin/${BASE}^{commit}" || true)
  fi
  if [ -z "$NEW_BASE" ]; then
    say "origin/${BASE} moved ${MOVES} time(s) during this train (or cannot be fetched again): [${TODO[*]}] wait for the next run (base-moved)"
    BASEMOVED+=("${TODO[@]}"); break
  fi
  BASE_SHA=$NEW_BASE; KEEP=()
  for p in "${TODO[@]}"; do
    if edited_review_stale "$p"; then
      say "PR #${p}: edited-test review is stale on the moved base"; BLOCKED+=("$p:2"); [ "$RC" -ne 0 ] || RC=2
    else KEEP+=("$p"); fi
  done
  TODO=(${KEEP[@]+"${KEEP[@]}"})
  [ "${#TODO[@]}" -eq 0 ] || say "origin/${BASE} is now ${BASE_SHA:0:12}: proving [${TODO[*]}] again outside the merge lock (move ${MOVES}/2)"
done
# PR chưa được chứng minh xanh/đỏ/conflict vì verify hết giờ (và không có kết quả nào khác về sau).
BLOCKED_IDS=(); for b in ${BLOCKED[@]+"${BLOCKED[@]}"}; do BLOCKED_IDS+=("${b%%:*}"); done
TIMEDOUT=()
for p in ${PENDING[@]+"${PENDING[@]}"}; do
  in_list "$p" ${MERGED_OK[@]+"${MERGED_OK[@]}"} ${GATERED[@]+"${GATERED[@]}"} ${GATEX[@]+"${GATEX[@]}"} ${RED[@]+"${RED[@]}"} \
    ${CONFLICT[@]+"${CONFLICT[@]}"} ${REFUSED[@]+"${REFUSED[@]}"} ${DEFERRED[@]+"${DEFERRED[@]}"} ${BASEMOVED[@]+"${BASEMOVED[@]}"} \
    ${BLOCKED_IDS[@]+"${BLOCKED_IDS[@]}"} ${TIMEDOUT[@]+"${TIMEDOUT[@]}"} || TIMEDOUT+=("$p")
done

early_results
for p in "${DEFERRED[@]+"${DEFERRED[@]}"}"; do echo "train-result: $p deferred"; done
for p in "${CONFLICT[@]+"${CONFLICT[@]}"}"; do echo "train-result: $p conflict"; done
for p in "${REFUSED[@]+"${REFUSED[@]}"}"; do echo "train-result: $p gate-exit-5"; cat "$DETAIL_DIR/refused-$p" 2>/dev/null || true; done
for p in "${RED[@]+"${RED[@]}"}"; do echo "train-result: $p red"; echo "train-red: $p"; cat "$DETAIL_DIR/red-$p" 2>/dev/null || true; done
for p in "${TIMEDOUT[@]+"${TIMEDOUT[@]}"}"; do echo "train-result: $p timeout"; done
for p in "${BASEMOVED[@]+"${BASEMOVED[@]}"}"; do echo "train-result: $p base-moved"; done
if [ "${#RED[@]}" -gt 0 ] || [ "${#GATERED[@]}" -gt 0 ]; then exit 11; fi
if [ "$RC" -ne 0 ]; then exit "$RC"; fi
if [ "${#TIMEDOUT[@]}" -gt 0 ] || [ "${#BASEMOVED[@]}" -gt 0 ]; then exit 12; fi
if [ "${#CONFLICT[@]}" -gt 0 ] || [ "${#REFUSED[@]}" -gt 0 ]; then exit 5; fi
if [ "${#MOVED[@]}" -gt 0 ]; then exit 6; fi
exit 0
