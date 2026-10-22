#!/usr/bin/env bash
# super-board-merge-train.sh — gom nhiều PR đã qua review thành một đợt: verify MỘT lần, rồi merge từng PR bằng merge gate (#110).
#
# VÌ SAO: 19/10 có 6 PR sẵn sàng cùng lúc; merge gate chạy --force-full riêng cho từng PR trên máy đã quá tải, một lần hết 900 s
# (REG-DK-ALL-01 TIMEOUT, PR #99 đỏ oan). Gate vẫn là nơi quyết định merge (policy, người duyệt, khoá, --match-head-commit);
# train chỉ chứng minh trước cây gộp, để gate khỏi chạy lại đúng bằng chứng đó.
#
# Cách chạy:
#   1. Một PR: exec thẳng merge gate như cũ (không train).
#   2. Nhiều PR: dựng scratch = origin/<base> + lần lượt các head (merge, đúng thứ tự --prs) rồi chạy verify_commands một lần.
#      PR không merge sạch vào chuỗi thì bị loại (kết quả `conflict`, exit 5 như gate).
#   3. Đỏ: chia đôi tìm PR gây lỗi (tập đã xanh + nửa trái, rồi + nửa phải). PR đỏ bị loại, phần còn lại vẫn được chứng minh.
#   4. Ghi biên nhận `<head sha> <cây sau khi merge head đó vào chuỗi>` cho các PR xanh, rồi gọi gate cho từng PR theo thứ tự với
#      `--train-receipt`. Gate tự merge base hiện tại với head: cây trùng biên nhận thì bỏ verify, khác (base đã dời, head đổi,
#      PR đứng trước không merge) thì verify như thường. Biên nhận chỉ rút ngắn, không bao giờ nới tiêu chuẩn.
#      Điều biên nhận chứng minh là cây của CHUỖI đầy đủ (đích cuối của đợt) đã qua verify; trạng thái trung gian của main giữa hai
#      lần merge (mới PR đầu) không được verify riêng.
#
# Usage: super-board-merge-train.sh --config <config.json> --prs <N,M,...> [gate flags: --lock-timeout S --stale-after S ...]
#
# Exit: 0 mọi PR đã merge · 11 có PR đỏ (về Build; dòng `train-red: <N>`) · mã thoát gate đầu tiên khác 0 (gate chặn PR) ·
#       12 verify hết giờ sau một lần chạy lại: PR chưa chứng minh ở lại Review, wave sau thử lại, không PR nào bị quy là đỏ ·
#       5 có PR conflict, không PR nào đỏ/hết giờ · 79/9 của github-read và readiness đi thẳng tới caller.
#       Mỗi PR một dòng `train-result: <N> <merged|red|conflict|timeout|gate-exit-K>` trên stdout.
# ponytail: PR bị gate chặn (policy cần người duyệt) vẫn nằm trong chuỗi verify, nên cây của các PR sau nó lệch biên nhận và chúng verify như thường;
#           nâng lên khi nhiều PR cần người duyệt hay đi chung đợt: gate --dry-run từng PR trước khi dựng chuỗi.
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
LIST=()
IFS=',' read -r -a RAW <<<"$PRS"
for p in "${RAW[@]}"; do
  [[ "$p" =~ ^[0-9]+$ ]] || { echo "--prs wants comma-separated PR numbers, got '${p}'" >&2; exit 64; }
  LIST+=("$p")
done
[ "${#LIST[@]}" -gt 0 ] || { echo "--prs <N,M,...> is required" >&2; exit 64; }

# Một PR: đường cũ, không dòng nào của train.
if [ "${#LIST[@]}" -eq 1 ]; then
  exec bash "$GATE" --config "$CONFIG" --pr "${LIST[0]}" ${PASS[@]+"${PASS[@]}"}
fi

say() { echo "[merge-train] $*" >&2; }
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

REPO_ABS=$(cd "$REPO_PATH" && pwd -P)
MAIN_WT=$(git -C "$REPO_ABS" worktree list --porcelain | sed -n '1s/^worktree //p')
BASE_WT=${MAIN_WT:-$REPO_ABS}
mkdir -p "$BASE_WT/.claude/worktrees"
SCRATCH=$(mktemp -d "$BASE_WT/.claude/worktrees/.train-scratch-XXXXXX")
RECEIPT=$(mktemp); VLOG=$(mktemp)
cleanup() { git -C "$BASE_WT" worktree remove --force "$SCRATCH" 2>/dev/null || true; rm -rf "$SCRATCH" "$RECEIPT" "$VLOG"; }
trap cleanup EXIT

# Head của từng PR, ghim một lần: verify và biên nhận thuộc đúng commit này (gate còn --match-head-commit lúc merge).
HEADS=(); REFS=()
for p in "${LIST[@]}"; do
  # Lấy output trước rồi mới `read`: `read <<<"$(…)" || exit $?` kiểm exit của `read`, mất exit 79 (halt) / 9 của github-read.
  head_out=$(python3 "$GITHUB_READ" --kind head -- pr view "$p" ${REPO:+--repo "$REPO"} --json headRefName,headRefOid \
               -q '.headRefName + " " + .headRefOid') || exit $?
  read -r ref sha <<<"$head_out"
  [ -n "${sha:-}" ] || { say "could not read the head of PR #${p}"; exit 1; }
  REFS+=("$ref"); HEADS+=("$sha")
done
git -C "$REPO_PATH" fetch origin "$BASE" ${REFS[@]+"${REFS[@]}"} --quiet
BASE_SHA=$(git -C "$REPO_PATH" rev-parse --verify -q "origin/${BASE}^{commit}") || { say "cannot resolve origin/${BASE}"; exit 1; }
head_of() { local i; for i in "${!LIST[@]}"; do [ "${LIST[$i]}" = "$1" ] && { echo "${HEADS[$i]}"; return 0; }; done; return 1; }

git -C "$REPO_PATH" worktree add --detach "$SCRATCH" "$BASE_SHA" --quiet 2>/dev/null || { say "could not create the train scratch worktree"; exit 1; }
# Cùng cách chuẩn bị scratch như merge gate: DevKit + config cục bộ bị ignore. Cài một lần; reset --hard giữ file bị ignore.
for c in "$REPO_PATH/universal-agent-devkit" "$REPO_PATH/.agents/devkit" "${MAIN_WT:-$REPO_PATH}/universal-agent-devkit" "${MAIN_WT:-$REPO_PATH}/.agents/devkit"; do
  if [ -f "$c/bin/install.sh" ]; then
    bash "$c/bin/install.sh" -t "$SCRATCH" -a claude -y --no-githooks >"$VLOG" 2>&1 \
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
verify_timed_out() {
  local plain
  [ "$1" -eq 124 ] && return 0
  plain=$(LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$VLOG" 2>/dev/null) || return 1
  if printf '%s\n' "$plain" | grep -aqE "KẾT LUẬN|POST-FIX AUDIT GATE VERDICT"; then
    printf '%s\n' "$plain" | LC_ALL=C awk '/^[[:space:]]*\[ \] [^|]*\|/ { if ($0 ~ /^[[:space:]]*\[ \] TIMEOUT[[:space:]]*\|/) t++; else o++ } END { exit !(t > 0 && o == 0) }'
    return
  fi
  printf '%s\n' "$plain" | grep -aqE "TIMEOUT after|quá giới hạn"
}
# verify_set <PR...>: 0 chuỗi dựng được và mọi verify_commands xanh · 1 đỏ · 2 chuỗi không dựng được (không phải lỗi đỏ của PR)
#                     · 3 hết giờ sau một lần chạy lại (máy quá tải, không quy lỗi cho PR nào).
verify_set() {
  local cmd rc try merged
  build_chain "$@" || { say "PR #${CHAIN_FAIL} does not merge into the chain of [$*]"; return 2; }
  merged=$(git -C "$SCRATCH" rev-parse HEAD)
  for cmd in "${VERIFY[@]}"; do
    if [[ "$cmd" == *"post-fix-gate.py"* ]]; then
      [[ "$cmd" == *"--diff"* ]] || cmd="$cmd --diff origin/${BASE}"
      [[ "$cmd" == *"--force-full"* ]] || cmd="$cmd --force-full"
    fi
    try=1
    while :; do
      say "verify [$*]: ${cmd}"
      rc=0
      ( cd "$SCRATCH" && unset POSTFIX_GATE_FORCE_FULL && export DEVKIT_SLOT_PRIORITY="${DEVKIT_SLOT_PRIORITY:-merge}" \
          && DEVKIT_LANG="${DEVKIT_LANG:-vi}" python3 "$HERE/super-board-heavy-slot.py" -- bash -c "$cmd" ) >"$VLOG" 2>&1 || rc=$?
      [ "$rc" -ne 0 ] || break
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

GOOD=(); RED=(); CONFLICT=()
# Một PR không merge sạch vào base + các PR trước: bỏ ra trước, rồi mới chứng minh phần còn lại.
CANDS=()
for p in "${LIST[@]}"; do
  if build_chain ${GOOD[@]+"${GOOD[@]}"} ${CANDS[@]+"${CANDS[@]}"} "$p"; then CANDS+=("$p"); else CONFLICT+=("$p"); fi
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
    if [ "$rc" -eq 2 ]; then CONFLICT+=("$1"); else RED+=("$1"); fi
    return 0
  fi
  local half=$(( $# / 2 )) all=("$@")
  solve "${all[@]:0:$half}"
  solve "${all[@]:$half}"
}
[ "${#CANDS[@]}" -eq 0 ] || solve "${CANDS[@]}"
# PR chưa được chứng minh xanh/đỏ/conflict vì verify hết giờ.
in_list() { local x="$1" e; shift; for e in "$@"; do [ "$e" = "$x" ] && return 0; done; return 1; }
TIMEDOUT=()
for p in "${CANDS[@]+"${CANDS[@]}"}"; do
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

RC=0
for p in "${GOOD[@]+"${GOOD[@]}"}"; do
  GRC=0
  bash "$GATE" --config "$CONFIG" --pr "$p" --expect-head "$(head_of "$p")" --train-receipt "$RECEIPT" ${PASS[@]+"${PASS[@]}"} || GRC=$?
  if [ "$GRC" -eq 0 ]; then echo "train-result: $p merged"; else echo "train-result: $p gate-exit-${GRC}"; [ "$RC" -ne 0 ] || RC=$GRC; fi
done
for p in "${CONFLICT[@]+"${CONFLICT[@]}"}"; do echo "train-result: $p conflict"; done
for p in "${RED[@]+"${RED[@]}"}"; do echo "train-result: $p red"; echo "train-red: $p"; done
for p in "${TIMEDOUT[@]+"${TIMEDOUT[@]}"}"; do echo "train-result: $p timeout"; done
if [ "${#RED[@]}" -gt 0 ]; then exit 11; fi
if [ "$RC" -ne 0 ]; then exit "$RC"; fi
if [ "${#TIMEDOUT[@]}" -gt 0 ]; then exit 12; fi
if [ "${#CONFLICT[@]}" -gt 0 ]; then exit 5; fi
exit 0
