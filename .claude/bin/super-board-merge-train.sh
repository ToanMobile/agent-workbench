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
#      PR không merge sạch vào chuỗi thì bị loại (kết quả `conflict`, exit 5 như gate).
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
#       Mỗi PR một dòng `train-result: <N> <merged|red|conflict|deferred|timeout|head-moved|gate-exit-K>` trên stdout.
#       Dòng `approval-request:|human-gate:|needs-you:|ac-check:|qa-report:|verification-readiness:` của gate (preflight, --dry-run,
#       merge) và ≤ 20 dòng cuối của verify đỏ (của train, hoặc stderr của gate khi gate đỏ) in lại thành `train-detail: <N> <dòng>`
#       để bên gọi (super-board-merge-queue.sh) chép nguyên văn vào comment issue. Mọi lời gọi gate mang SB_MERGE_CALLER=train.
#       13: queue bật + SB_BOARD_WORKER=1 mà bên gọi không phải queue (SB_MERGE_CALLER=queue): worker gắn nhãn merge-queue thay vì gọi train.
#       4 không kèm train-result: một train khác giữ <git-common-dir>/super-board/merge-train.lock; chưa PR nào chạy.
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
# F4 (fix-round1-contract.md, "Cờ worker board"): queue bật = (merge_queue.enabled hoặc SB_MERGE_QUEUE=1) VÀ worker_backend "claude-p"
# (thiếu khoá = "workflow", như super-board-run.sh); SB_MERGE_QUEUE=0 luôn tắt. Khi đó worker board (SB_BOARD_WORKER=1) chỉ gắn nhãn
# merge-queue; train chỉ chạy cho super-board-merge-queue.sh (SB_MERGE_CALLER=queue). Đọc SB_MERGE_CALLER của bên gọi TRƯỚC khi train
# tự đặt nó = train ở dưới.
# ponytail: backend workflow/codex coi như queue tắt (chưa có ai rút hàng ở đó); thêm khi có Q-schedule.
if [ "${SB_BOARD_WORKER:-}" = 1 ] && [ "${SB_MERGE_CALLER:-}" != queue ] && [ "${SB_MERGE_QUEUE:-}" != 0 ] \
   && jq -e --arg env "${SB_MERGE_QUEUE:-}" '(.worker_backend // "workflow") == "claude-p" and ($env == "1" or .merge_queue.enabled == true)' \
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
# run_gate <PR> <out-stream 1|2> <gate args…>: chạy merge gate, GRC = exit của nó. Stdout của gate đi nguyên vẹn ra luồng cũ (merge: stdout,
# vì `ac-open: #N` / "verify skipped" là của bên gọi; preflight / --dry-run: stderr), stderr của gate đi ra stderr sau khi gate xong
# (giữ trong $GATE_ERR cho đuôi verify đỏ), rồi các dòng approval-request/human-gate/needs-you/ac-check/qa-report/verification-readiness
# (verification-readiness gate in ra stderr) in thêm thành `train-detail: <PR> <dòng>` trên stdout.
GATE_OUT=$(mktemp); GATE_ERR=$(mktemp); DETAIL_DIR=$(mktemp -d)
run_gate() {
  local p="$1" to="$2" line; shift 2
  GRC=0
  bash "$GATE" "$@" >"$GATE_OUT" 2>"$GATE_ERR" 8>&- || GRC=$?
  if [ "$to" = 1 ]; then cat "$GATE_OUT"; else cat "$GATE_OUT" >&2; fi
  cat "$GATE_ERR" >&2
  while IFS= read -r line; do
    case "$line" in
      approval-request:*|human-gate:*|needs-you:*|ac-check:*|qa-report:*|verification-readiness:*) echo "train-detail: $p $line" ;;
    esac
  done < <(cat "$GATE_OUT" "$GATE_ERR")
  return 0
}
# detail_tail <PR> <file>: ≤ 20 dòng cuối không rỗng của log đỏ, bỏ mã màu, thành `train-detail: <PR> <dòng>` (queue chép vào comment issue).
# Đuôi log là dữ liệu tuỳ ý và đi vào comment issue CÔNG KHAI: mọi dòng qua redact_secrets() của kit (regression_checklist.py).
# Không nạp được bộ che thì giấu cả đuôi (đóng an toàn), không bao giờ đăng log thô.
detail_tail() {
  local raw kit="" d k
  raw=$(LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$2" 2>/dev/null | grep -av '^[[:space:]]*$' | tail -20 || true)
  [ -n "$raw" ] || return 0
  for d in "$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)" "$HERE"; do
    for k in "$d/../../universal-agent-devkit/bin" "$d/../../.agents/devkit/bin" "${DEVKIT_ROOT:-/nonexistent}/bin"; do
      [ -f "$k/regression_checklist.py" ] && { kit="$k"; break 2; }
    done
  done
  # Che cả đoạn một lần (không từng dòng): khối khoá PEM nhiều dòng chỉ nhận ra được khi thấy cả khối. Lỗi của bộ che ra stderr của train.
  if [ -n "$kit" ] && printf '%s\n' "$raw" | python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1])
from regression_checklist import redact_secrets
sys.stdout.write(redact_secrets(sys.stdin.read()))' "$kit" > "$DETAIL_DIR/.redacted"; then
    sed "s/^/train-detail: $1 /" "$DETAIL_DIR/.redacted"
  else
    echo "train-detail: $1 (verify log tail hidden: the DevKit secret redactor could not be loaded)"
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

# Một train mỗi repo (Antigravity audit A): fcntl LOCK_EX|LOCK_NB trên fd 8 của chính shell này, giữ tới khi train thoát. Bận → exit 4 trước
# mọi train-result (queue: không kết thúc, không tính lần thử). Tiến trình con sống lâu (gate, verify, cài DevKit) chạy với `8>&-`: train
# bị giết thì khoá đi theo nó, không bị verify mồ côi giữ.
TRAIN_COMMON=$(cd "$REPO_PATH" && cd "$(git rev-parse --git-common-dir)" && pwd -P) || { say "cannot resolve the git common dir of ${REPO_PATH}"; exit 1; }
mkdir -p "$TRAIN_COMMON/super-board"
TRAIN_LOCK="$TRAIN_COMMON/super-board/merge-train.lock"
exec 8>>"$TRAIN_LOCK"
TLRC=0
python3 -I -c '
import errno, fcntl, sys
try:
    fcntl.flock(8, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError as e:
    sys.exit(3 if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EACCES) else (print(e, file=sys.stderr) or 2))
' || TLRC=$?
case "$TLRC" in
  0) ;;
  3) say "another merge train holds ${TRAIN_LOCK}; nothing ran"; exit 4 ;;
  *) say "could not lock ${TRAIN_LOCK} (exit ${TLRC})"; exit 1 ;;
esac
# TERM/INT/HUP (queue chuyển xuống khi nó bị dừng): thoát qua trap EXIT để dọn scratch.
trap 'exit 143' TERM; trap 'exit 130' INT; trap 'exit 129' HUP

REPO_ABS=$(cd "$REPO_PATH" && pwd -P)
MAIN_WT=$(git -C "$REPO_ABS" worktree list --porcelain | sed -n '1s/^worktree //p')
BASE_WT=${MAIN_WT:-$REPO_ABS}
mkdir -p "$BASE_WT/.claude/worktrees"
SCRATCH=$(mktemp -d "$BASE_WT/.claude/worktrees/.train-scratch-XXXXXX")
RECEIPT=$(mktemp); VLOG=$(mktemp)
cleanup() { git -C "$BASE_WT" worktree remove --force "$SCRATCH" 2>/dev/null || true; rm -rf "$SCRATCH" "$RECEIPT" "$VLOG" "$GATE_OUT" "$GATE_ERR" "$DETAIL_DIR"; }
trap cleanup EXIT

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
LIST=("${KEEP[@]}")
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
if ! git -C "$REPO_PATH" fetch origin "$BASE" --quiet; then
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
  git -C "$REPO_PATH" fetch origin "${PF_REFS[$i]}" --quiet 2>/dev/null \
    || git -C "$REPO_PATH" fetch origin "refs/pull/${p}/head" --quiet 2>/dev/null \
    || say "could not fetch ${PF_REFS[$i]} (or pull/${p}/head) of PR #${p}; using the head if it is already here"
  if git -C "$REPO_PATH" cat-file -e "${PF_HEADS[$i]}^{commit}" 2>/dev/null; then
    LIST+=("$p"); REFS+=("${PF_REFS[$i]}"); HEADS+=("${PF_HEADS[$i]}")
  else
    say "head ${PF_HEADS[$i]} of PR #${p} is not in the repo (branch rewritten or gone); the review evidence is void, it leaves the batch"
    BLOCKED+=("$p:6"); [ "$DRYRC" -ne 0 ] || DRYRC=6
  fi
done
if [ "${#LIST[@]}" -eq 0 ]; then early_results; exit "$DRYRC"; fi
BASE_SHA=$(git -C "$REPO_PATH" rev-parse --verify -q "origin/${BASE}^{commit}") || { say "cannot resolve origin/${BASE}"; exit 1; }
head_of() { local i; for i in "${!LIST[@]}"; do [ "${LIST[$i]}" = "$1" ] && { echo "${HEADS[$i]}"; return 0; }; done; return 1; }

git -C "$REPO_PATH" worktree add --detach "$SCRATCH" "$BASE_SHA" --quiet 2>/dev/null || { say "could not create the train scratch worktree"; exit 1; }
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

# build_chain <PR...>: scratch = base + các head theo thứ tự. 1 nếu một head không merge sạch (in PR đó ra stderr qua $CHAIN_FAIL).
CHAIN_FAIL=""
build_chain() {
  local p
  git -C "$SCRATCH" reset -q --hard "$BASE_SHA"; git -C "$SCRATCH" clean -qfd 2>/dev/null || true
  for p in "$@"; do
    if ! git -C "$SCRATCH" merge --no-edit --quiet "$(head_of "$p")" >/dev/null 2>&1; then
      git -C "$SCRATCH" merge --abort 2>/dev/null || true
      CHAIN_FAIL="$p"; return 1
    fi
  done
  return 0
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
    printf '%s\n' "$plain" | LC_ALL=C awk '/^[[:space:]]*\[ \] [^|]*\|/ { if ($0 ~ /^[[:space:]]*\[ \] TIMEOUT[[:space:]]*\|/) t++; else o++ } END { exit !(t > 0 && o == 0) }'
    return
  fi
  printf '%s\n' "$plain" | grep -aqE "TIMEOUT after|quá giới hạn"
)
# verify_set <PR...>: 0 chuỗi dựng được và mọi verify_commands xanh · 1 đỏ · 2 chuỗi không dựng được (không phải lỗi đỏ của PR)
#                     · 3 hết giờ sau một lần chạy lại (máy quá tải, không quy lỗi cho PR nào).
verify_set() {
  local cmd run_cmd busy_line rc try merged
  build_chain "$@" || { say "PR #${CHAIN_FAIL} does not merge into the chain of [$*]"; return 2; }
  merged=$(git -C "$SCRATCH" rev-parse HEAD)
  for cmd in "${VERIFY[@]}"; do
    cmd=$(sb_verify_inject_flags "$cmd" "$BASE")
    run_cmd=$(sb_verify_inject_flags "$cmd" "$BASE" json)
    try=1
    while :; do
      say "verify [$*]: ${cmd}"
      rc=0
      # CLAUDE_PROJECT_DIR / TARGET_DIR của bên gọi (cây chính) thắng cwd trong get_project_dir của post-fix-gate: bỏ để verify kiểm scratch.
      ( cd "$SCRATCH" && unset POSTFIX_GATE_FORCE_FULL CLAUDE_PROJECT_DIR TARGET_DIR && export DEVKIT_SLOT_PRIORITY="${DEVKIT_SLOT_PRIORITY:-merge}" \
          DEVKIT_GATE_SLOT_WAIT_S="${DEVKIT_GATE_SLOT_WAIT_S:-1800}" \
          && DEVKIT_LANG="${DEVKIT_LANG:-vi}" python3 "$HERE/super-board-heavy-slot.py" -- bash -c "$run_cmd" ) >"$VLOG" 2>&1 8>&- || rc=$?
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
      say "red [$*]: $(tail -3 "$VLOG" | tr '\n' ' ' | cut -c1-300)"
      return 1
    done
  done
  return 0
}

GOOD=(); RED=(); GATERED=(); CONFLICT=(); DEFERRED=()   # BLOCKED / DRYRC: đã khởi tạo ở preflight
# Một PR không merge sạch vào base + các PR trước: bỏ ra trước, rồi mới chứng minh phần còn lại.
# Sạch với base mà chỉ xung đột với PR đứng trước (R8): không phải lỗi của PR, ở lại Review chờ wave sau (lúc đó base đã có PR trước).
CANDS=()
for p in "${LIST[@]}"; do
  if build_chain ${CANDS[@]+"${CANDS[@]}"} "$p"; then CANDS+=("$p")
  elif build_chain "$p"; then DEFERRED+=("$p")
  else CONFLICT+=("$p"); fi
done
# solve <PR...>: GOOD dài ra bằng các PR xanh; PR đỏ vào RED. Đỏ thì chia đôi, đúng một PR đỏ thì đó là thủ phạm.
# Hết giờ (3) dừng cả chia đôi (ABORT): PR chưa chứng minh được không bị quy là đỏ. Chuỗi không dựng được (2) ở đúng một PR → CONFLICT.
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
    if [ "$rc" -eq 2 ]; then CONFLICT+=("$1"); else RED+=("$1"); detail_tail "$1" "$VLOG" > "$DETAIL_DIR/red-$1"; fi
    return 0
  fi
  local half=$(( $# / 2 )) all=("$@")
  solve "${all[@]:0:$half}"
  solve "${all[@]:$half}"
}
[ "${#CANDS[@]}" -eq 0 ] || solve "${CANDS[@]}"
# R11: biên nhận chỉ chứng minh cây của CHUỖI ĐẦY ĐỦ. PR sau bị gate chặn giữa đợt (policy cần người, exit 7…) sẽ để main dừng ở một
# cây chưa ai verify. Nên trước khi merge gì: gate --dry-run từng PR xanh (biên nhận dry = cây merge(base, head), nên không verify lại, chỉ
# chạy policy/approval); PR bị chặn ra khỏi chuỗi và phần còn lại được chứng minh lại. Lặp tối đa số PR lần.
# ponytail: gate chặn sau preflight (đua với người duyệt/chờ khoá) vẫn có thể để main ở cây đã verify của tiền tố chuỗi trước đó; nâng lên khi
#           cần tuyệt đối: merge các PR bằng một ref-update duy nhất thay vì từng gate.
in_list() { local x="$1" e; shift; for e in "$@"; do [ "$e" = "$x" ] && return 0; done; return 1; }
PENDING=()   # PR chưa chứng minh vì verify hết giờ ở lượt solve trước; vòng preflight ghi đè CANDS nên phải giữ riêng
while [ "${#GOOD[@]}" -gt 0 ]; do
  : >"$RECEIPT"
  for p in "${GOOD[@]}"; do
    echo "$(head_of "$p") $(git -C "$SCRATCH" merge-tree --write-tree "$BASE_SHA" "$(head_of "$p")" 2>/dev/null || echo none)" >>"$RECEIPT"
  done
  NEWGOOD=(); DROPPED=0
  for p in "${GOOD[@]}"; do
    run_gate "$p" 2 --config "$CONFIG" --pr "$p" --expect-head "$(head_of "$p")" --train-receipt "$RECEIPT" --dry-run ${PASS[@]+"${PASS[@]}"}
    case "$GRC" in
      0) NEWGOOD+=("$p") ;;
      79|9) echo "train-result: $p gate-exit-${GRC}"; exit "$GRC" ;;
      *) BLOCKED+=("$p:$GRC"); DROPPED=1; say "PR #${p} is blocked by the merge gate (exit ${GRC}); the chain is proved again without it"
         [ "$DRYRC" -ne 0 ] || DRYRC=$GRC ;;
    esac
  done
  [ "$DROPPED" -eq 1 ] || break
  for p in "${CANDS[@]+"${CANDS[@]}"}"; do
    in_list "$p" ${GOOD[@]+"${GOOD[@]}"} ${RED[@]+"${RED[@]}"} ${CONFLICT[@]+"${CONFLICT[@]}"} || PENDING+=("$p")
  done
  CANDS=(${NEWGOOD[@]+"${NEWGOOD[@]}"}); GOOD=(); ABORT=0
  [ "${#CANDS[@]}" -eq 0 ] || solve "${CANDS[@]}"
done
# PR chưa được chứng minh xanh/đỏ/conflict vì verify hết giờ.
TIMEDOUT=()
for p in "${PENDING[@]+"${PENDING[@]}"}" "${CANDS[@]+"${CANDS[@]}"}"; do
  in_list "$p" ${GOOD[@]+"${GOOD[@]}"} ${RED[@]+"${RED[@]}"} ${CONFLICT[@]+"${CONFLICT[@]}"} || TIMEDOUT+=("$p")
done

# Biên nhận: cây sau từng head của chuỗi GOOD (đúng tập vừa qua verify xanh ở lượt solve gần nhất có thêm PR).
if [ "${#GOOD[@]}" -gt 0 ]; then
  build_chain "${GOOD[@]}" || { say "internal: the verified chain no longer builds"; exit 1; }
  : >"$RECEIPT"
  git -C "$SCRATCH" reset -q --hard "$BASE_SHA"
  for p in "${GOOD[@]}"; do
    git -C "$SCRATCH" merge --no-edit --quiet "$(head_of "$p")" >/dev/null 2>&1 || { say "internal: chain merge failed for #${p}"; exit 1; }
    echo "$(head_of "$p") $(git -C "$SCRATCH" rev-parse 'HEAD^{tree}')" >>"$RECEIPT"
  done
fi

RC=$DRYRC
for p in ${PREMERGED[@]+"${PREMERGED[@]}"}; do echo "train-result: $p merged"; done
for b in "${BLOCKED[@]+"${BLOCKED[@]}"}"; do echo "train-result: ${b%%:*} gate-exit-${b##*:}"; done
for p in "${GOOD[@]+"${GOOD[@]}"}"; do
  run_gate "$p" 1 --config "$CONFIG" --pr "$p" --expect-head "$(head_of "$p")" --train-receipt "$RECEIPT" ${PASS[@]+"${PASS[@]}"}
  case "$GRC" in
    0)     echo "train-result: $p merged" ;;
    79|9)  echo "train-result: $p gate-exit-${GRC}"; exit "$GRC" ;;   # R7: halt / readiness của gate đi thẳng tới caller, không bị che bởi 11
    11)    echo "train-result: $p red"; echo "train-red: $p"; GATERED+=("$p")   # R7: verify riêng của gate đỏ = PR về Build, có dòng train-red
           detail_tail "$p" "$GATE_ERR" ;;   # gate in đuôi log verify đỏ ra stderr
    *)     echo "train-result: $p gate-exit-${GRC}"; [ "$RC" -ne 0 ] || RC=$GRC ;;
  esac
done
for p in "${DEFERRED[@]+"${DEFERRED[@]}"}"; do echo "train-result: $p deferred"; done
for p in "${CONFLICT[@]+"${CONFLICT[@]}"}"; do echo "train-result: $p conflict"; done
for p in "${RED[@]+"${RED[@]}"}"; do echo "train-result: $p red"; echo "train-red: $p"; cat "$DETAIL_DIR/red-$p" 2>/dev/null || true; done
for p in "${TIMEDOUT[@]+"${TIMEDOUT[@]}"}"; do echo "train-result: $p timeout"; done
if [ "${#RED[@]}" -gt 0 ] || [ "${#GATERED[@]}" -gt 0 ]; then exit 11; fi
if [ "$RC" -ne 0 ]; then exit "$RC"; fi
if [ "${#TIMEDOUT[@]}" -gt 0 ]; then exit 12; fi
if [ "${#CONFLICT[@]}" -gt 0 ]; then exit 5; fi
if [ "${#MOVED[@]}" -gt 0 ]; then exit 6; fi
exit 0
