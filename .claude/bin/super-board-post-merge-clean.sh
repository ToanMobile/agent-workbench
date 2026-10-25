#!/usr/bin/env bash
# super-board-post-merge-clean.sh <repo-path> <merged-head-ref> [<merged-sha> [<pr-number>]]
# super-board-post-merge-clean.sh --sweep <repo-path> [--dry-run] [--base <branch>] [--min-interval <s>]
# Dọn sau merge, do super-board-merge-gate.sh gọi sau squash merge: xoá worktree của CHÍNH thẻ vừa merge
# (của Builder trên <merged-head-ref>, của Tester issue-<N>-qa) và nhánh local của nó, để không ai phải dọn tay.
# issue-<N>-review của Reviewer được giữ: Reviewer là người chạy gate này, còn các bước sau merge phải làm ở đó
# (run.md); worktree đang chứa cwd của lệnh này cũng được giữ. --sweep gỡ chúng sau (xem dưới).
# Không bao giờ đụng thẻ khác: ngày 2026-10-16 bản đầu khớp mọi issue-*-qa / issue-*-review và xoá --force
# thư mục mà worker của thẻ khác đang dùng. Không mất gì ngoài phần đã merge: worktree còn sửa thật được giữ,
# nhánh chỉ bị xoá khi đầu nhánh vẫn đúng <merged-sha> (đường DevKit: luật của kit, xem remove_wt bên dưới).
# Làm hết sức có thể: không bao giờ làm hỏng lần merge đã xảy ra (luôn exit 0).
#
# 19/10 (issue #96): worktree lane của thẻ đã merge không bao giờ được gỡ, 5 repo đầy đĩa (OfficeReader 28G / 21 worktree).
# Đo trên dữ liệu thật, chúng bị giữ vì: chỉ còn file đã xoá (OR 72-qa, Geely 40-qa), ghi chú memory của agent trong .agents/local/
# (OR 73/80-build), asset Unity tự serialize lại (NFH 3-qa, 53-build/qa) — đều "uncommitted edits" —, worktree review luôn được giữ
# và không ai gỡ sau đó (OR 79-review), rồi "kept branch …: still checked out". Nay:
#  - sửa chưa commit chỉ thuộc hai danh sách của lane (KEEP_RE: cất thành patch vào <git common dir>/super-board/salvage/, ngoài cây
#    làm việc: main của trunk mode không bẩn thêm, như log verify của gate; DROP_RE: rác dựng lại được, bỏ không cất) và file đã xoá:
#    kiểm patch dựng lại đúng, trả worktree về HEAD rồi mới gỡ bằng kit. Sửa ngoài danh sách = việc thật: giữ worktree, in lý do.
#  - PR squash: head đã merge không nằm trong trunk, kit chỉ gỡ worktree detached khi một ref còn giữ head (nhánh, origin/<nhánh>).
#    Không ref nào giữ: lấy refs/pull/<PR>/head của GitHub (GitHub giữ head PR mãi) làm ref giữ tạm, bỏ ref đó khi xong.
#  - --sweep: runner gọi lúc khởi động (startup_reconcile của super-board-run.sh), wave workflow gọi ở cuối mỗi wave (agent Cleanup của
#    super-board-wave.js); dọn worktree + nhánh còn sót của thẻ đã merge (cũng là worktree review sau
#    khi Reviewer làm xong). Chỉ khi: một PR MERGED vào base có head là HEAD của worktree (hoặc HEAD là tổ tiên của head đó) hay là
#    nhánh nó đang checkout, đã merge quá SB_SWEEP_GRACE_S giây (mặc định 900: thời gian cho bước sau merge của Reviewer), issue
#    CLOSED, không lane nào của runner đang giữ thẻ (inflight/<N> có PID sống), không phiên DevKit nào giữ khoá checkout của worktree.
#    Một `gh pr list --search head:issue-<N>-` cho mỗi thẻ có worktree / nhánh còn sót; đọc GitHub hỏng: dừng lượt, không gỡ gì thêm;
#    board đang halt GitHub: không đọc gì (không bao giờ ghi file halt).
#    Chạy lại trong --min-interval giây (mặc định 600) thì bỏ qua ngay. --dry-run chỉ in, không ghi gì.
set -u
MODE=post; DRY=0; MIN_INTERVAL=600; BASE=""; PR=""; HEAD_REF=""; MERGED_SHA=""
if [ "${1:-}" = --sweep ]; then
  MODE=sweep; REPO_ARG="${2:?repo path}"; shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY=1; shift ;;
      --base) BASE="${2-}"; [ $# -ge 2 ] && shift 2 || shift ;;   # rỗng (jq thiếu, base_branch rỗng): dò origin/HEAD như khi không có cờ
      --min-interval) MIN_INTERVAL="${2:?seconds}"; shift 2 ;;
      *) echo "unknown arg: $1" >&2; exit 64 ;;
    esac
  done
  case "$MIN_INTERVAL" in ''|*[!0-9]*) echo "--min-interval: not a number of seconds: $MIN_INTERVAL" >&2; exit 64 ;; esac
else
  REPO_ARG="${1:?repo path}"; HEAD_REF="${2:?merged head ref}"; MERGED_SHA="${3:-}"; PR="${4:-}"
fi
# repo.path là "." trong mọi config board và gate có thể chạy từ một worktree: quy về main checkout.
REPO_PATH=$(git -C "$REPO_ARG" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[ -n "$REPO_PATH" ] || exit 0
HERE_PWD=$(pwd -P)
# 18/10 (NFH PR #38, #45, Geely PR #59): phiên rời worktree của PR bằng ExitWorktree "keep" (khoá devkit-kept) rồi tự chạy merge gate;
# `git worktree remove` trần từ chối worktree bị khoá và phiên phải unlock tay. Có DevKit thì gỡ bằng `worktree.py remove`: nó mở khoá
# devkit-kept của chính phiên gọi hoặc của pid đã chết (khoá của phiên khác còn sống thì git vẫn từ chối) và giữ luật không-mất-việc.
# Nó cũng xoá nhánh của worktree theo luật của kit, KHÔNG theo chốt MERGED_SHA dưới: nội dung đã trong trunk hoặc origin/<trunk> (tổ
# tiên, hay gộp thử ra đúng cây của trunk) và không còn ref remote; mọi commit chỉ nhánh giữ được cất vào refs/devkit/discarded 30 ngày.
# Không có python3: đường git như cũ (OCR 18/10).
KIT_WT=""
# Kit đi cùng script trước (đã review cùng nó), bản của repo sau — như sync_identical của merge gate.
HERE_UP=$(cd "$(dirname "$0")/../.." && pwd)
command -v python3 >/dev/null 2>&1 && for c in "$HERE_UP/universal-agent-devkit" "$HERE_UP/.agents/devkit" "$REPO_PATH/universal-agent-devkit" "$REPO_PATH/.agents/devkit"; do
  # thử chạy một lần (`list` chỉ đọc): kit có mà không chạy được (cú pháp, python quá cũ) thì đường git như cũ, không giữ mọi thứ lại
  if [ -f "$c/scripts/git/worktree.py" ] && (cd "$REPO_PATH" && python3 "$c/scripts/git/worktree.py" list >/dev/null 2>&1); then
    KIT_WT="$c/scripts/git/worktree.py"; break
  fi
done
remove_wt() {
  local out rc=2
  if [ -n "$KIT_WT" ]; then
    # thành công: in lại lời kit (nhánh đã xoá, commit cất ở refs/devkit/discarded 30 ngày, ⚠ memory note đi theo worktree) — OCR 18/10
    out=$(cd "$REPO_PATH" && python3 "$KIT_WT" remove "$1" 2>&1) && { printf '%s\n' "$out" >&2; return 0; }
    rc=$?
    # Có dòng ✖ (exit 1, hay 2 của die(): có việc sẽ mất, git lỗi khi dò bí mật, state không đọc được…) = kit TỪ CHỐI: giữ, git trần không
    # thấy hết những thứ đó. Không có dòng ✖ (kit chết giữa chừng: traceback): đường git như cũ — git vẫn từ chối worktree bẩn hay bị khoá.
    if printf '%s\n' "$out" | grep -q '✖'; then
      echo "kept $1: agent-kit worktree remove refused: $( { printf '%s\n' "$out" | grep -m1 '✖' || printf '%s\n' "$out" | head -1; } | cut -c1-300)" >&2
      return 0
    fi
    [ -e "$1" ] || { echo "removed $1 (agent-kit exited $rc after removing it: $(printf '%s\n' "$out" | tail -1 | cut -c1-200))" >&2; return 0; }
  fi
  git -C "$REPO_PATH" worktree remove "$1" 2>/dev/null || echo "kept $1: git worktree remove failed" >&2
}

COMMON_DIR=$(cd "$REPO_PATH" 2>/dev/null && d=$(git rev-parse --git-common-dir 2>/dev/null) && cd "$d" 2>/dev/null && pwd -P) || COMMON_DIR=""
SALVAGE_DIR="${COMMON_DIR:+$COMMON_DIR/super-board/salvage}"
# Sửa chưa commit không giữ worktree lại, hai loại (OCR batch 19/10):
#  - CẤT (KEEP_RE): ghi chú / state của agent (.agents/local/) và asset Unity (*.asset: thường là tự serialize lại, nhưng có thể là
#    việc thật) — cất thành patch vào $SALVAGE_DIR rồi mới bỏ.
#  - BỎ (DROP_RE, chỉ file CHƯA TRACK): bằng chứng QA (docs/super-board/runs/, reports/), log, rác IDE mới sinh — dựng lại được, không
#    cất: không vào kho object chung, không vào patch; dời tạm sang <tên>.dropped/ tới khi worktree gỡ xong, tên ghi vào bản ghi. Sửa
#    trên một file ĐÃ TRACK dưới các đường dẫn đó (REPORT.md của QA đã commit) thì cất như loại CẤT.
# File đã xoá, kể cả xoá đã stage (` D`, `D `: HEAD vẫn giữ bản của nó), được lấy lại từ HEAD. Đường dẫn khác, hay mọi thay đổi đã stage
# khác (index có thể giữ bản duy nhất), là việc thật: giữ worktree.
KEEP_RE='^\.agents/local/|\.asset$'
DROP_RE='^(docs/super-board/runs/|reports/)|\.log$|(^|/)\.(vscode|idea)/'

# lane_live <N>: in "<pid> <lane>" và trả 0 khi inflight/<N> của runner mang PID còn sống (lane đó đang làm thẻ N). Đọc cả dạng
# trước v1.3.0 (một dòng chỉ có PID, như read_lock của super-board-stop.sh): lane không biết thì in "?" (người gọi giữ mọi worktree).
lane_live() {
  local f="$REPO_PATH/.claude/super-board/inflight/$1" pid lane
  [ -f "$f" ] || return 1
  if grep -q '^PID=' "$f" 2>/dev/null; then
    pid=$(sed -n 's/^PID=//p' "$f" | head -1); lane=$(sed -n 's/^LANE=//p' "$f" | head -1)
  else
    pid=$(head -1 "$f" | tr -d '[:space:]'); lane=""
  fi
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  echo "$pid ${lane:-?}"
}
# session_held <wt>: 0 khi khoá checkout của DevKit (devkit-session.lock trong git dir của worktree) mang pid còn sống, như
# _live_holder của kit; khoá có mà không đọc được cũng coi là còn giữ.
session_held() {
  local gd pid
  gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  [ -f "$gd/devkit-session.lock" ] || return 1
  pid=$(python3 -I -c 'import json, sys
v = json.load(open(sys.argv[1])).get("pid")
print(v if type(v) is int else "")' "$gd/devkit-session.lock" 2>/dev/null) || return 0
  [ -n "$pid" ] && [ "$pid" -gt 1 ] && kill -0 "$pid" 2>/dev/null
}
# locked_by_other <wt>: 0 (và in lý do khoá) khi `git worktree lock` giữ <wt> mà kit sẽ không mở: khoá devkit-kept của một pid còn
# sống không phải tổ tiên của lệnh này (phiên khác), hay khoá khác devkit-kept (người dùng). Khi đó không đụng gì vào worktree: tidy
# sẽ trả phần rác về HEAD trước khi kit từ chối (review 19/10). Khoá của chính phiên gọi hay của pid đã chết: kit mở, 1.
locked_by_other() {
  local reason pid a line ppid comm i=0 re='^devkit-kept session=[A-Za-z0-9][A-Za-z0-9._-]{0,127} pid=([0-9]{1,10})$'
  reason=$(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null \
    | awk -v w="worktree $1" '$0 == w { f = 1; next } /^worktree / { f = 0 } f && /^locked/ { print "L" substr($0, 7); exit }')
  [ -n "$reason" ] || return 1
  reason=${reason#L}; reason=${reason# }
  # Đúng luật kit (worktree.py KEPT_LOCK_RE.fullmatch, kept_lock, _ancestor_pids — OCR): chỉ khoá devkit-kept đúng dạng mới có thể được mở
  [[ "$reason" =~ $re ]] || { echo "${reason:-no reason}"; return 0; }
  pid=${BASH_REMATCH[1]}
  [ "$pid" -gt 1 ] || return 1   # pid 0/1: khoá vô hiệu, kit gỡ
  kill -0 "$pid" 2>/dev/null || ps -p "$pid" >/dev/null 2>&1 || return 1   # ps: pid của user khác (EPERM) vẫn là còn sống (OCR)
  # Tổ tiên của lệnh này, DỪNG ở tiến trình `claude` gần nhất (phía trên là app / terminal / launchd mọi phiên dùng chung)
  a=$$
  while [ "$i" -lt 64 ] && [ -n "$a" ] && [ "$a" -gt 1 ] 2>/dev/null; do
    [ "$a" = "$pid" ] && return 1
    line=$(ps -ww -o ppid=,comm= -p "$a" 2>/dev/null) || break
    read -r ppid comm <<<"$line"
    [ "${comm##*/}" = claude ] && break
    a=$ppid; i=$((i + 1))
  done
  echo "$reason"
}
# run_t <giây> <lệnh…>: chạy với hạn giờ thật. Hết giờ: SIGTERM cả nhóm tiến trình (git kịp dọn file .lock), 5 s sau SIGKILL; exit 124.
# perl alarm không đủ: gh là binary Go và runtime Go bỏ qua SIGALRM (review 19/10 đo: alarm 1 s, binary Go vẫn chạy đủ 4 s).
run_t() {
  python3 -I -c 'import os, signal, subprocess, sys
def stop(signum=None, _frame=None):
    # Con ở nhóm tiến trình riêng: Ctrl-C / SIGTERM gửi cho lệnh này không tới nó, nên tự dừng cả nhóm rồi mới thoát (OCR).
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(p.pid, sig)
            p.wait(timeout=5)
            break
        except ProcessLookupError:
            break
        except subprocess.TimeoutExpired:
            continue
    if signum:   # tín hiệu của người dùng / người gọi: chết đúng bằng nó để shell gọi cũng dừng, không báo nhầm "hết giờ"
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)
    sys.exit(124)
try:
    limit = float(sys.argv[1])   # đọc TRƯỚC khi khởi chạy con: hạn giờ sai dạng không được để lại tiến trình mồ côi (OCR)
except ValueError:
    sys.exit(2)
try:
    p = subprocess.Popen(sys.argv[2:], start_new_session=True)
except OSError:
    sys.exit(127)
for s in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
    signal.signal(s, stop)
try:
    rc = p.wait(timeout=limit)
    sys.exit(128 - rc if rc < 0 else rc)   # chết vì tín hiệu N: 128+N như shell, không 256-N (OCR)
except subprocess.TimeoutExpired:
    stop()' "$@"
}

# tidy <wt>: 0 khi worktree sạch — sẵn sạch, hoặc mọi thay đổi chưa commit thuộc loại CẤT (đã cất vào $SALVAGE_DIR, patch kiểm lại:
# HEAD + patch = đúng ảnh chụp) hay loại BỎ hay là file đã xoá, rồi trả về HEAD. 1 khi giữ (đã in lý do). --dry-run: chỉ nói.
tidy() {
  local wt="$1" st="" e xy p dels=0 keep=0 drop=0 nreal=0 real="" trk="" untr="" kp="" sdel="" delf="" drpz="" head gd name idx1 idx2 dl
  local t1="" t2="" okk=1
  st=$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null) || { echo "kept $wt: git status failed" >&2; return 1; }
  [ -n "$st" ] || return 0
  # (untidy / clean_wt dùng rồi xoá TIDY_SDEL, TIDY_DL, TIDY_DROPZ; một mktemp hỏng giữa chừng: xoá những file đã tạo)
  if ! { st=$(mktemp) && trk=$(mktemp) && untr=$(mktemp) && kp=$(mktemp) && sdel=$(mktemp) && delf=$(mktemp) && drpz=$(mktemp); }; then
    rm -f "$st" "$trk" "$untr" "$kp" "$sdel" "$delf" "$drpz"; echo "kept $wt: uncommitted edits (mktemp failed)" >&2; return 1
  fi
  TIDY_SDEL="$sdel"; TIDY_DL="$delf"; TIDY_DROPZ="$drpz"
  if ! git -C "$wt" status --porcelain=v1 -z --no-renames --untracked-files=all >"$st" 2>/dev/null; then
    rm -f "$st" "$trk" "$untr" "$kp" "$sdel" "$delf" "$drpz"; TIDY_SDEL=""; TIDY_DL=""; TIDY_DROPZ=""
    echo "kept $wt: git status failed" >&2; return 1
  fi
  while IFS= read -r -d '' e; do
    xy=${e:0:2}; p=${e:3}
    case "$xy" in
      " D"|"D ")
        # Chỉ khi file thật sự không còn trên đĩa. Xoá đã stage mà file còn trên đĩa (`git rm --cached`) luôn là việc thật: file bị
        # ignore thì bản trên đĩa (có thể mới hơn HEAD) không vào patch nào (review 19/10); không bị ignore thì `D ` + `??` cùng đường dẫn
        # không trả về HEAD sạch được (checkout lấy lại rồi rm lại xoá).
        if [ ! -e "$wt/$p" ] && [ ! -L "$wt/$p" ]; then
          dels=$((dels + 1)); printf '%s\0' "$p" >>"$trk"; printf '%s\0' "$p" >>"$delf"
          [ "$xy" = " D" ] || printf '%s\0' "$p" >>"$sdel"   # xoá đã stage: untidy stage lại đúng như vậy (OCR)
          continue
        fi ;;
      " M"|" T"|"??")
        # BỎ chỉ áp cho file CHƯA TRACK (ảnh proof, log mới sinh). Sửa trên một file ĐÃ TRACK dưới đường dẫn rác (REPORT.md của QA đã
        # commit) không dựng lại được từ đâu: cất như loại CẤT (review 19/10).
        if [[ "$p" =~ $KEEP_RE ]] || { [ "$xy" != "??" ] && [[ "$p" =~ $DROP_RE ]]; }; then
          keep=$((keep + 1)); printf '%s\0' "$p" >>"$kp"
          if [ "$xy" = "??" ]; then printf '%s\0' "$p" >>"$untr"; else printf '%s\0' "$p" >>"$trk"; fi
          continue
        elif [ "$xy" = "??" ] && [[ "$p" =~ $DROP_RE ]]; then
          # dời sang $name.dropped/ (không xoá): kit còn từ chối gỡ thì untidy trả lại (OCR)
          drop=$((drop + 1)); printf '%s\0' "$p" >>"$drpz"
          continue
        fi ;;
    esac
    nreal=$((nreal + 1)); [ "$nreal" -le 5 ] && real="${real:+$real, }$p"
  done <"$st"
  rm -f "$st"
  if [ "$nreal" -gt 0 ]; then
    echo "kept $wt: uncommitted edits outside the salvage list ($nreal path(s)): $real" >&2
    rm -f "$trk" "$untr" "$kp"; return 1
  fi
  if [ "$DRY" -eq 1 ]; then
    echo "would salvage $wt: $keep file(s) kept in a patch, $drop lane junk file(s) dropped, $dels deleted file(s) restored from HEAD" >&2
    rm -f "$trk" "$untr" "$kp"; return 0
  fi
  head=$(git -C "$wt" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || head=""
  gd=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) || gd=""
  if [ -z "$SALVAGE_DIR" ] || [ -z "$head" ] || [ -z "$gd" ] || ! mkdir -p "$SALVAGE_DIR"; then
    echo "kept $wt: uncommitted edits (no place to salvage them: git dir or HEAD unreadable)" >&2
    rm -f "$trk" "$untr" "$kp"; return 1
  fi
  name="$SALVAGE_DIR/${wt##*/}-$(date +%Y%m%d-%H%M%S)-$$"
  if [ "$keep" -gt 0 ]; then
    okk=0; idx1=$(mktemp); idx2="$idx1.verify"; dl=$(mktemp)   # idx2 chưa tồn tại: git từ chối một file index 0 byte ở vài bản (OCR)
    # Chụp ĐÚNG các file loại CẤT vào một index TẠM chép từ index thật (GIT_INDEX_FILE chỉ cho từng lệnh, không export: index thật không
    # bị đụng; chỉ chúng thành object trong kho chung), rồi dựng lại từ HEAD + patch (+ xoá đã stage có sẵn trong index thật) trong index
    # tạm thứ hai: hai cây phải trùng, không thì không bỏ gì.
    if cp "$gd/index" "$idx1" \
       && GIT_INDEX_FILE="$idx1" git -C "$wt" --literal-pathspecs add -A --pathspec-from-file="$kp" --pathspec-file-nul \
       && t1=$(GIT_INDEX_FILE="$idx1" git -C "$wt" write-tree) \
       && GIT_INDEX_FILE="$idx1" git -C "$wt" diff --cached --binary --no-renames --diff-filter=d "$head" >"$name.patch" \
       && GIT_INDEX_FILE="$idx1" git -C "$wt" diff --cached -z --name-only --no-renames --diff-filter=D "$head" >"$dl" \
       && GIT_INDEX_FILE="$idx2" git -C "$wt" read-tree "$head" \
       && { [ ! -s "$name.patch" ] || GIT_INDEX_FILE="$idx2" git -C "$wt" apply --cached "$name.patch"; } \
       && { [ ! -s "$dl" ] || GIT_INDEX_FILE="$idx2" git -C "$wt" update-index -z --force-remove --stdin <"$dl"; } \
       && t2=$(GIT_INDEX_FILE="$idx2" git -C "$wt" write-tree) && [ "$t1" = "$t2" ]; then
      okk=1
    fi
    rm -f "$idx1" "$idx2" "$dl"
    [ -s "$name.patch" ] || rm -f "$name.patch"
  fi
  rm -f "$kp"
  if [ "$okk" != 1 ]; then
    # worktree chưa bị đụng: patch (có thể dở dang) không có bản ghi nào trỏ tới, bỏ luôn, không để mỗi lượt sweep thêm một file mồ côi
    echo "kept $wt: uncommitted edits (salvage could not be verified: tree ${t1:-?} vs ${t2:-?})" >&2
    rm -f "$trk" "$untr" "$name.patch"; return 1
  fi
  [ ! -s "$delf" ] || tr '\0' '\n' <"$delf" >"$name.deleted.txt"
  [ ! -s "$drpz" ] || tr '\0' '\n' <"$drpz" >"$name.dropped.txt"
  printf 'worktree: %s\nhead: %s\nat: %s\nkept in a patch: %s file(s)%s\nlane junk dropped, not kept: %s file(s)%s\ndeleted, restored from HEAD: %s file(s)%s\n' \
    "$wt" "$head" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$keep" "$( [ -f "$name.patch" ] && printf ' -> git apply --3way %s (on %s)' "$name.patch" "$head")" \
    "$drop" "$( [ -f "$name.dropped.txt" ] && printf ' (%s)' "$name.dropped.txt")" \
    "$dels" "$( [ -s "$delf" ] && printf ' (%s)' "$name.deleted.txt")" >"$name.txt"
  TIDY_NAME="$name"   # clean_wt trả lại đúng các thay đổi này nếu worktree không bị gỡ (untidy)
  # Rác dời sang $name.dropped/ (cùng ổ: chỉ là đổi tên), không vào kho object; clean_wt xoá thư mục đó khi worktree đã gỡ, untidy trả
  # lại khi worktree ở lại. Dời hỏng giữa chừng: trả 1, clean_wt gọi untidy và những gì đã dời được trả lại.
  if [ -s "$drpz" ]; then
    while IFS= read -r -d '' p; do
      mkdir -p "$name.dropped/$(dirname "$p")" && mv "$wt/$p" "$name.dropped/$p" \
        || { echo "kept $wt: could not move lane junk $p aside" >&2; rm -f "$trk" "$untr"; return 1; }
    done <"$drpz"
  fi
  # Trả về HEAD: file đã theo dõi (sửa / xoá) lấy lại bản HEAD, file mới (đã cất hay rác) bị xoá. --literal-pathspecs: tên có * ? [ không
  # là mẫu.
  if { [ ! -s "$trk" ] || git -C "$wt" --literal-pathspecs checkout -q HEAD --pathspec-from-file="$trk" --pathspec-file-nul; } \
     && { [ ! -s "$untr" ] || (cd "$wt" && xargs -0 rm -f -- <"$untr"); } \
     && [ -z "$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null)" ]; then
    rm -f "$trk" "$untr"
    echo "salvaged $wt: $keep kept in a patch, $drop lane junk dropped, $dels deleted file(s) restored -> $name.txt" >&2
    return 0
  fi
  rm -f "$trk" "$untr"
  echo "kept $wt: not clean after salvaging to $name.txt" >&2
  return 1
}

HOLDS=()   # "<ref> <sha>" của ref giữ tạm do lần chạy này tạo; bỏ khi thoát
drop_holds() { local x; for x in ${HOLDS[@]+"${HOLDS[@]}"}; do git -C "$REPO_PATH" update-ref -d "${x% *}" "${x#* }" 2>/dev/null || true; done; }
trap drop_holds EXIT
# hold_head <wt> <pr> <merged-head>: 0 khi một ref (refs/heads|remotes|tags — cái kit đếm) giữ HEAD của <wt>. Không ref nào: lấy
# refs/pull/<pr>/head của GitHub vào refs/remotes/super-board-hold/pull-<pr>, chỉ khi nó đúng <merged-head> và HEAD là nó hay tổ tiên
# của nó; ref đó được bỏ khi thoát (commit vẫn ở GitHub). Ngoài refs/remotes/origin/: một `git fetch --prune` (của phiên khác) trong
# lúc gỡ không xoá được nó (OCR batch); không remote nào tên super-board-hold nên không lệnh prune nào chạm tới. 1: không giữ được.
hold_head() {
  local h r got
  h=$(git -C "$1" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || return 1
  [ -n "$(git -C "$REPO_PATH" for-each-ref --count=1 --contains "$h" refs/heads refs/remotes refs/tags 2>/dev/null)" ] && return 0
  [ -n "$2" ] && [ -n "$3" ] || return 1
  git -C "$REPO_PATH" merge-base --is-ancestor "$h" "$3" 2>/dev/null || return 1
  # số PR (vào refspec): `*` sẽ kéo mọi PR head về ref không ai bỏ (review)
  case "$2" in ''|*[!0-9]*) HOLD_WHY="PR number '$2' is not a number"; return 1 ;; esac
  r="refs/remotes/super-board-hold/pull-$2"
  if git -C "$REPO_PATH" rev-parse -q --verify "$r" >/dev/null; then   # ref cùng tên của ai khác mà không giữ HEAD: không đè
    HOLD_WHY="$r already exists and does not hold HEAD $h"; return 1
  fi
  # không có hạn giờ (run_t) thì không đọc remote: giữ worktree
  command -v python3 >/dev/null 2>&1 || { HOLD_WHY="no python3 to fetch refs/pull/$2/head with a deadline"; return 1; }
  if [ "$DRY" -eq 1 ]; then   # chỉ đọc: GitHub phải thật sự có refs/pull/<pr>/head đúng head đã merge thì mới hứa gỡ (OCR batch)
    got=$(GIT_TERMINAL_PROMPT=0 run_t "${SB_CLEAN_FETCH_TIMEOUT:-30}" git -C "$REPO_PATH" ls-remote origin "refs/pull/$2/head" 2>/dev/null | cut -f1) || got=""
    [ "$got" = "$3" ] || { HOLD_WHY="fetch of refs/pull/$2/head failed (GitHub has ${got:-no such ref}, the merged head is $3)"; return 1; }
    echo "would hold ${h} with ${r} (GitHub refs/pull/$2/head)" >&2; return 0
  fi
  # Hạn giờ thật cho cả remote SSH (http.lowSpeed* chỉ áp cho HTTP): ở chế độ post lệnh này chạy khi merge gate còn giữ mutex.
  local rc=0
  GIT_TERMINAL_PROMPT=0 run_t "${SB_CLEAN_FETCH_TIMEOUT:-30}" git -C "$REPO_PATH" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
    fetch -q --no-tags origin "+refs/pull/$2/head:$r" >/dev/null 2>&1 || rc=$?
  got=$(git -C "$REPO_PATH" rev-parse -q --verify "$r" 2>/dev/null) || got=""
  [ -z "$got" ] || HOLDS+=("$r $got")
  if [ "$rc" -ne 0 ]; then
    HOLD_WHY="fetch of refs/pull/$2/head $( [ "$rc" -eq 124 ] && echo "timed out after ${SB_CLEAN_FETCH_TIMEOUT:-30}s" || echo "failed (exit $rc)")"; return 1
  fi
  [ "$got" = "$3" ] || { HOLD_WHY="GitHub refs/pull/$2/head is ${got:-<missing>}, not the merged $3"; return 1; }
}
# untidy <wt>: kit giữ worktree sau khi tidy đã cất và trả phần rác về HEAD: đặt lại đúng các thay đổi đó (patch + file đã xoá), worktree
# "được giữ" thì như cũ (review 19/10). Trả lại đủ: bỏ bản cất ($TIDY_NAME.*); trả lại hỏng hay dở: bản cất còn ở $TIDY_NAME.txt.
untidy() {
  local ok=1 p
  # Rác đã dời sang $TIDY_NAME.dropped/ về chỗ cũ trước tiên (đường dẫn riêng, không đụng patch): luôn trả, kể cả khi patch hỏng (OCR).
  if [ -s "$TIDY_DROPZ" ]; then
    while IFS= read -r -d '' p; do
      [ -e "$TIDY_NAME.dropped/$p" ] || [ -L "$TIDY_NAME.dropped/$p" ] || continue
      mkdir -p "$1/$(dirname "$p")" && mv -f "$TIDY_NAME.dropped/$p" "$1/$p" || ok=0
    done <"$TIDY_DROPZ"
    [ "$ok" != 1 ] || rm -rf "$TIDY_NAME.dropped"
  fi
  # Bước trả về HEAD hỏng giữa chừng thì patch không áp lại được: không động gì nữa (không xoá file nào), bản cất còn nguyên (OCR).
  if [ -f "$TIDY_NAME.patch" ] && ! git -C "$1" apply --check --binary "$TIDY_NAME.patch" 2>/dev/null; then
    echo "kept $1: it stays, its lane edits could not be put back cleanly (left as is): they are in $TIDY_NAME.txt" >&2; return 0
  fi
  [ ! -f "$TIDY_NAME.patch" ] || git -C "$1" apply --binary "$TIDY_NAME.patch" 2>/dev/null || ok=0
  [ ! -s "$TIDY_DL" ] || (cd "$1" && xargs -0 rm -f -- <"$TIDY_DL") || ok=0
  [ ! -s "$TIDY_SDEL" ] || git -C "$1" update-index -z --force-remove --stdin <"$TIDY_SDEL" || ok=0
  if [ "$ok" = 1 ]; then
    # Mọi thứ đã về lại worktree: bản cất trùng với chính worktree, bỏ nó — không thì worktree được giữ lại thêm một bộ .patch + .txt
    # vào salvage/ ở mỗi lượt sweep (OCR batch). Trả lại hỏng: giữ bản cất, nó là bản duy nhất.
    rm -f "$TIDY_NAME.patch" "$TIDY_NAME.txt" "$TIDY_NAME.deleted.txt" "$TIDY_NAME.dropped.txt"
    echo "restored $1: it stays, so its lane edits, junk and deletions are back as they were (no salvage record kept)" >&2
  else echo "kept $1: it stays, but putting its lane edits back failed: they are in $TIDY_NAME.txt / .dropped/" >&2; fi
}
# clean_wt <wt> <pr> <merged-head>: phần chung của hai chế độ cho một worktree đã được chọn: khoá phiên, ref giữ head, rác, gỡ.
clean_wt() {
  local wt="$1" head why
  if session_held "$wt"; then echo "kept $wt: a live session holds its checkout lock" >&2; return 0; fi
  if why=$(locked_by_other "$wt"); then echo "kept $wt: locked ($why), not touched" >&2; return 0; fi
  HOLD_WHY=""
  if ! hold_head "$wt" "$2" "$3"; then
    # Commit trên HEAD detached mà không nhánh/remote nào chứa (vd repro Tester chưa push) sẽ chỉ còn trong reflog.
    head=$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null || true)
    echo "kept $wt: HEAD ${head:-<unknown>} is on no branch or remote${HOLD_WHY:+ ($HOLD_WHY)}" >&2
    return 0
  fi
  TIDY_NAME=""; TIDY_DL=""; TIDY_SDEL=""; TIDY_DROPZ=""
  if ! tidy "$wt"; then
    [ -z "$TIDY_NAME" ] || untidy "$wt"
    rm -f "$TIDY_DL" "$TIDY_SDEL" "$TIDY_DROPZ"; return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    echo "would remove $wt" >&2; DRY_GONE="$DRY_GONE$wt"$'\n'; rm -f "$TIDY_DL" "$TIDY_SDEL" "$TIDY_DROPZ"; return 0
  fi
  remove_wt "$wt"
  if [ -n "$TIDY_NAME" ] && [ -d "$wt" ]; then
    untidy "$wt"   # kit (hay git) từ chối gỡ — reflog, rebase dở, submodule, bí mật chỉ worktree có…: trả lại mọi thứ đã dời / cất
  elif [ -n "$TIDY_NAME" ]; then
    rm -rf "$TIDY_NAME.dropped"   # worktree đã gỡ: rác lane bỏ hẳn (tên vẫn trong $TIDY_NAME.dropped.txt)
  fi
  rm -f "$TIDY_DL" "$TIDY_SDEL" "$TIDY_DROPZ"
}
DRY_GONE=""   # --dry-run: worktree "would remove" (nhánh chúng checkout được tính như đã thả)
# Bản cất quá 30 ngày được bỏ, như refs/devkit/discarded của kit: thư mục salvage không thành chỗ đầy đĩa mới (OCR). Cả hai chế độ.
prune_salvage() {
  [ "$DRY" -eq 0 ] && [ -n "$SALVAGE_DIR" ] && [ -d "$SALVAGE_DIR" ] || return 0
  find "$SALVAGE_DIR" -maxdepth 1 -type f \( -name '*.patch' -o -name '*.txt' \) -mtime +30 -exec rm -f {} + 2>/dev/null || true
  # thư mục rác dời tạm (<tên>.dropped/) chỉ sót lại khi lần chạy trước chết giữa chừng
  find "$SALVAGE_DIR" -maxdepth 1 -type d -name '*.dropped' -mtime +30 -exec rm -rf {} + 2>/dev/null || true
}
# wt_order: đọc "đường dẫn" trên stdin, in worktree detached trước rồi worktree trên nhánh: gỡ worktree trên nhánh có thể xoá nhánh
# (luật kit), sau đó head chỉ nhánh đó giữ không còn ref nào.
wt_order() {
  local wt att=()
  while IFS= read -r wt; do
    if git -C "$wt" symbolic-ref -q HEAD >/dev/null 2>&1; then att+=("$wt"); else printf '%s\n' "$wt"; fi
  done
  for wt in ${att[@]+"${att[@]}"}; do printf '%s\n' "$wt"; done
}

if [ "$MODE" = post ]; then
  N=$(printf '%s' "$HEAD_REF" | sed -nE 's#^issue-([0-9]+)-.*#\1#p')
  CANDS=()
  if [ -n "$N" ]; then
    for wt in "$REPO_PATH/.claude/worktrees"/issue-"$N"-*; do [ -d "$wt" ] && CANDS+=("$wt"); done
  else
    # Nhánh PR thường (không phải của thẻ): chỉ worktree đang ở ĐÚNG nhánh vừa merge (của phiên đã mở PR), không bao giờ main checkout
    cur=""
    while IFS= read -r line; do
      case "$line" in
        "worktree "*) cur="${line#worktree }" ;;
        "branch refs/heads/$HEAD_REF")   # chỉ worktree do phiên dựng (.claude/worktrees/<tên>); worktree người tự dựng nơi khác: để yên (OCR 18/10)
          case "$cur" in "$REPO_PATH/.claude/worktrees/"*) CANDS+=("$cur") ;; esac ;;
      esac
    done < <(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null)
    # không worktree nào của phiên: nhánh local cùng tên là của người dùng, không đụng (như trước: nhánh thường chưa bao giờ bị xoá, OCR 18/10)
    [ "${#CANDS[@]}" -gt 0 ] || exit 0
  fi
  LIVE=""; [ -n "$N" ] && LIVE=$(lane_live "$N")
  while IFS= read -r wt; do
    [ -n "$wt" ] && [ -d "$wt" ] || continue
    case "$HERE_PWD/" in "$(cd "$wt" && pwd -P)"/*) continue ;; esac
    case "${wt##*/}" in
      "issue-$N-review") continue ;;
      "issue-$N-qa") ;;
      *) [ "$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null)" = "$HEAD_REF" ] || continue ;;
    esac
    # một lane của runner còn sống trên đúng worktree này (inflight/<N>: LANE): để yên
    if [ -n "$LIVE" ] && { [ "${LIVE#* }" = "?" ] || [ "${wt##*/}" = "issue-$N-${LIVE#* }" ]; }; then
      echo "kept $wt: live ${LIVE#* } lane (pid ${LIVE%% *}) holds card $N" >&2; continue
    fi
    clean_wt "$wt" "$PR" "$MERGED_SHA"
  done < <(printf '%s\n' ${CANDS[@]+"${CANDS[@]}"} | wt_order)
  tip=$(git -C "$REPO_PATH" rev-parse --verify -q "refs/heads/$HEAD_REF" 2>/dev/null || true)
  if [ -n "$tip" ] && [ -n "$MERGED_SHA" ] && [ "$tip" = "$MERGED_SHA" ]; then
    git -C "$REPO_PATH" branch -D "$HEAD_REF" >/dev/null 2>&1 || echo "kept branch $HEAD_REF: still checked out" >&2
  elif [ -n "$tip" ]; then
    echo "kept branch $HEAD_REF: its tip ${tip} is not the merged ${MERGED_SHA:-<unknown>}" >&2
  fi
  prune_salvage
  exit 0
fi

# ---- --sweep ----------------------------------------------------------------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || { echo "sweep: python3 not found; nothing done" >&2; exit 0; }
STAMP="${COMMON_DIR:+$COMMON_DIR/super-board/sweep.stamp}"
if [ "$DRY" -eq 0 ] && [ "$MIN_INTERVAL" -gt 0 ] && [ -n "$STAMP" ] && [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null); case "$last" in ''|*[!0-9]*) last=0 ;; esac
  # 0 <= now - last: stamp ở tương lai (đồng hồ lệch, khôi phục backup) không chặn sweep tới khi đồng hồ bắt kịp (OCR batch)
  since=$(( $(date +%s) - last ))
  [ "$since" -ge 0 ] && [ "$since" -lt "$MIN_INTERVAL" ] && exit 0
fi
GH_READ="$(cd "$(dirname "$0")" && pwd)/super-board-github-read.py"
if [ -f "$GH_READ" ] && ! SB_REPO_PATH="$REPO_PATH" python3 "$GH_READ" --check >/dev/null 2>&1; then
  echo "sweep skipped: GitHub reads are halted for this board (super-board-github-read.py --check)" >&2; exit 0
fi
# Một sweep một lúc (OCR batch): runner (startup) và wave (Cleanup) cùng gọi; hai lượt chồng nhau thì lượt này bỏ ref giữ tạm khi thoát
# trong lúc lượt kia còn gỡ, và cả hai cùng checkout / rm một worktree. Khoá flock của kernel (python fcntl, macOS không có flock(1))
# giữ trên một fd được kế thừa qua exec của chính script này: tiến trình chết là khoá tự nhả, không có "khoá cũ" phải đoán sống chết
# (bản mkdir + pid có khe đua khi lấy lại khoá: OCR). --dry-run chỉ đọc nên không cần khoá.
if [ "$DRY" -eq 0 ] && [ -n "$COMMON_DIR" ] && [ -z "${SB_SWEEP_LOCKED:-}" ] && mkdir -p "$COMMON_DIR/super-board" 2>/dev/null; then
  exec python3 -I -c 'import fcntl, os, sys
try:
    f = open(sys.argv[1], "a")
    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    print("sweep skipped: another sweep is running (it holds " + sys.argv[1] + ")", file=sys.stderr)
    sys.exit(0)
except OSError as e:   # khoá không mở được (thư mục, quyền, ổ chỉ đọc): vẫn exit 0 như hợp đồng, nói lý do (review)
    print("sweep skipped: cannot take the sweep lock " + sys.argv[1] + ": " + str(e), file=sys.stderr)
    sys.exit(0)
os.set_inheritable(f.fileno(), True)
os.environ["SB_SWEEP_LOCKED"] = "1"
os.execvp("bash", ["bash"] + sys.argv[2:])' "$COMMON_DIR/super-board/sweep.lock" \
    "$0" --sweep "$REPO_ARG" ${BASE:+--base "$BASE"} --min-interval "$MIN_INTERVAL"
fi
if [ -z "$BASE" ]; then
  BASE=$(git -C "$REPO_PATH" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  for b in main master; do [ -n "$BASE" ] || ! git -C "$REPO_PATH" show-ref -q --verify "refs/heads/$b" || BASE="$b"; done
fi
[ -n "$BASE" ] || { echo "sweep: base branch unknown (pass --base); nothing done" >&2; exit 0; }
GRACE="${SB_SWEEP_GRACE_S:-900}"; case "$GRACE" in ''|*[!0-9]*) GRACE=900 ;; esac
# gh với hạn giờ thật (run_t): đọc hỏng / treo thì không gỡ gì
gh_t() { (cd "$REPO_PATH" && run_t "${SB_CLEAN_GH_TIMEOUT:-20}" gh "$@"); }

# worktree của phiên dưới .claude/worktrees/ gắn với một thẻ: theo tên thư mục issue-<N>-…, không thì theo nhánh issue-<N>-…
WT_P=(); WT_N=(); NS=" "
cur=""; br=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*) cur="${line#worktree }"; br="" ;;
    "branch refs/heads/"*) br="${line#branch refs/heads/}" ;;
    "")
      case "$cur" in
        "$REPO_PATH/.claude/worktrees/"*)
          n=$(printf '%s' "${cur##*/}" | sed -nE 's#^issue-([0-9]+)-.*#\1#p')
          [ -n "$n" ] || n=$(printf '%s' "$br" | sed -nE 's#^issue-([0-9]+)-.*#\1#p')
          if [ -n "$n" ]; then WT_P+=("$cur"); WT_N+=("$n"); case "$NS" in *" $n "*) ;; *) NS="$NS$n " ;; esac; fi ;;
      esac
      cur="" ;;
  esac
done < <(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null; echo)
while IFS= read -r b; do
  n=$(printf '%s' "$b" | sed -nE 's#^issue-([0-9]+)-.*#\1#p')
  [ -n "$n" ] && case "$NS" in *" $n "*) ;; *) NS="$NS$n " ;; esac
done < <(git -C "$REPO_PATH" for-each-ref --format='%(refname:short)' 'refs/heads/issue-*' 2>/dev/null)
[ "$NS" != " " ] || exit 0

# merged_rows <N>: PR MERGED của đúng thẻ N, mỗi dòng "<N>\t<PR>\t<nhánh>\t<head>\t<old|young>". Hỏi GitHub theo số thẻ, không lấy N PR
# mới nhất của repo: thẻ cũ bị đẩy khỏi danh sách và worktree của nó bị giữ mãi (OCR batch: `--limit 200`). `head:` của tìm kiếm GitHub
# khớp lỏng (issue-7- còn trả issue-70-…) nên lọc chặt ^issue-<N>- lại. Dòng đọc không được: bỏ dòng đó. 1: gh hỏng hay trả gì không đọc
# được.
merged_rows() {
  local json
  json=$(gh_t pr list --state merged --base "$BASE" --search "head:issue-$1-" --limit 100 \
           --json number,headRefName,headRefOid,baseRefName,isCrossRepository,mergedAt) || return 1
  printf '%s' "$json" | python3 -I -c '
import calendar, json, re, sys, time
grace, base, n = int(sys.argv[1]), sys.argv[2], sys.argv[3]
for r in json.load(sys.stdin):
    try:
        m = re.match(r"issue-([0-9]+)-", r["headRefName"])
        if not m or m.group(1) != n or r["isCrossRepository"] is not False or r["baseRefName"] != base \
                or not re.fullmatch(r"[0-9a-f]{40}", r["headRefOid"]):
            continue
        age = time.time() - calendar.timegm(time.strptime(r["mergedAt"], "%Y-%m-%dT%H:%M:%SZ"))
        print(n, r["number"], r["headRefName"], r["headRefOid"], "old" if age >= grace else "young", sep="\t")
    except (KeyError, TypeError, ValueError):
        continue
' "$GRACE" "$BASE" "$1"
}
prune_salvage

# drop_card <N>: thẻ BỊ BỎ (gom vào thẻ khác, hết cần) = issue CLOSED với stateReason NOT_PLANNED quá GRACE giây. Không có PR MERGED để
# dựa vào, nên merged_rows trả rỗng và sweep trước đây bỏ qua mãi: 24/10 repo này có 20 worktree / 31 nhánh khi chỉ 4 thẻ chạy, 14 nhánh
# là của thẻ đã gom (issue đóng 23/10, PR vẫn MỞ). Đóng PR mở của thẻ (kèm lời nhắn), gỡ worktree bằng kit (còn sửa thật thì kit từ chối:
# giữ), xoá nhánh local bằng `prune-branch --dropped` (kit tự kiểm lại issue + không còn PR mở, cất commit riêng vào refs/devkit/discarded
# 30 ngày). 0 = thẻ bị bỏ (đã xử lý), 1 = không phải. Lane còn sống đã bị loại trước khi gọi.
drop_card() {
  local n="$1" info st age prs p i wt br co
  info=$(gh_t issue view "$n" --json state,stateReason,closedAt 2>/dev/null) || return 1
  st=$(printf '%s' "$info" | python3 -I -c '
import calendar, json, sys, time
try:
    d = json.load(sys.stdin)
    age = time.time() - calendar.timegm(time.strptime(d["closedAt"], "%Y-%m-%dT%H:%M:%SZ"))
    print(d["state"], d["stateReason"], int(age))
except (KeyError, TypeError, ValueError):
    print("? ? 0")') || return 1
  age="${st##* }"
  case "$st" in "CLOSED NOT_PLANNED "*|"CLOSED DUPLICATE "*) ;; *) return 1 ;; esac
  if [ "$age" -lt "$GRACE" ]; then echo "kept card $n: closed as not planned under ${GRACE}s ago" >&2; return 0; fi
  # Không có kit: không gỡ worktree / nhánh bằng git trần (bỏ qua luật không-mất-việc của kit); PR mở vẫn đóng được, nhưng chỉ sau khi đọc được danh sách
  [ -n "$KIT_WT" ] || { echo "kept card $n: no DevKit (agent-kit worktree) to prove its worktrees and branches safe" >&2; return 0; }
  prs=$(gh_t pr list --state open --search "head:issue-$n-" --limit 100 --json number,headRefName,isCrossRepository 2>/dev/null) \
    || { echo "kept card $n: gh pr list failed; nothing closed or removed" >&2; return 0; }
  prs=$(printf '%s' "$prs" | python3 -I -c '
import json, re, sys
try:
    for r in json.load(sys.stdin):
        if re.match(r"issue-" + sys.argv[1] + r"-", r["headRefName"]) and r.get("isCrossRepository") is False:
            print(r["number"])
except (KeyError, TypeError, ValueError):
    sys.exit(1)' "$n") || { echo "kept card $n: gh pr list gave an unreadable answer; nothing closed or removed" >&2; return 0; }
  # A live session or a lock on one of the card's worktrees: leave the whole card as it is. Closing its PRs first and keeping the worktree after
  # would cut off a lane that is still working (W4, OCR 25/10).
  i=0
  while [ "$i" -lt "${#WT_P[@]}" ]; do
    wt="${WT_P[$i]}"; i=$((i + 1))
    [ "${WT_N[$((i - 1))]}" = "$n" ] && [ -d "$wt" ] || continue
    # Same exemptions as the removal loop below: a worktree on another card's branch (folded work continues there) is not this card's lane.
    br=$(git -C "$wt" symbolic-ref -q --short HEAD 2>/dev/null) || br=""
    case "$br" in ""|"issue-$n-"*) ;; *) continue ;; esac
    if session_held "$wt"; then echo "kept card $n: a live session holds $wt; nothing closed or removed" >&2; return 0; fi
    if p=$(locked_by_other "$wt"); then echo "kept card $n: $wt is locked ($p); nothing closed or removed" >&2; return 0; fi
  done
  for p in $prs; do
    if [ "$DRY" -eq 1 ]; then echo "would close PR #$p (card $n closed as not planned)" >&2
    elif gh_t pr close "$p" --comment "Closed by the sweep: card #$n was closed as not planned (folded into another card or dropped). Its pushed branch stays recoverable from this PR (refs/pull/$p/head); a local branch is deleted only once pushed." >/dev/null 2>&1
    then echo "closed PR #$p (card $n closed as not planned)" >&2
    else echo "kept card $n: gh pr close #$p failed; its worktrees and branches stay" >&2; return 0; fi
  done
  i=0
  while [ "$i" -lt "${#WT_P[@]}" ]; do
    wt="${WT_P[$i]}"; i=$((i + 1))
    [ "${WT_N[$((i - 1))]}" = "$n" ] && [ -d "$wt" ] || continue
    case "$HERE_PWD/" in "$(cd "$wt" && pwd -P)"/*) echo "kept $wt: it holds this sweep's working directory" >&2; continue ;; esac
    # worktree issue-<N>-… mà đang ở nhánh của thẻ khác (việc của thẻ gom tiếp tục ở checkout cũ): không phải của thẻ bị bỏ
    br=$(git -C "$wt" symbolic-ref -q --short HEAD 2>/dev/null) || br=""
    case "$br" in ""|"issue-$n-"*) ;; *) echo "kept $wt: it is on branch $br, not a branch of card $n" >&2; continue ;; esac
    if session_held "$wt"; then echo "kept $wt: a live session holds its checkout lock" >&2; continue; fi
    if p=$(locked_by_other "$wt"); then echo "kept $wt: locked ($p), not touched" >&2; continue; fi
    if [ "$DRY" -eq 1 ]; then echo "would ask agent-kit to remove $wt (card $n closed as not planned; kept if it holds real work)" >&2; DRY_GONE="$DRY_GONE$wt"$'\n'
    else remove_wt "$wt"; fi
  done
  while IFS= read -r br; do
    [ -n "$br" ] || continue
    co=$(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null | awk -v b="branch refs/heads/$br" '/^worktree /{w=substr($0,10)} $0==b{print w; exit}')
    if [ -n "$co" ] && ! printf '%s' "$DRY_GONE" | grep -qxF "$co"; then echo "kept branch $br: still checked out at $co" >&2; continue; fi
    if [ "$DRY" -eq 1 ]; then echo "would ask agent-kit prune-branch --dropped for $br (card $n closed as not planned; deleted only if pushed and no open PR)" >&2
    else
      p=$(cd "$REPO_PATH" && python3 "$KIT_WT" prune-branch --dropped "$br" 2>&1) || p="kept branch $br: $(printf '%s\n' "$p" | grep -m1 '✖' | cut -c1-300)"
      printf '%s\n' "$p" >&2
    fi
  done < <(git -C "$REPO_PATH" for-each-ref --format='%(refname:short)' "refs/heads/issue-$n-*" 2>/dev/null)
  return 0
}

READ_OK=0
# Mỗi thẻ là một lần gọi search API của GitHub (~30 lần/phút): một lượt xử lý tối đa 20 thẻ, thứ tự xáo ngẫu nhiên, để lượt dừng giữa
# chừng (giới hạn, gh hỏng) không bỏ đói mãi các thẻ cuối danh sách (OCR). Thẻ chưa tới lượt thì lần sweep sau.
NS=$(printf '%s\n' $NS | sort -R 2>/dev/null | head -20 | tr '\n' ' ')
for n in $NS; do
  # lane sống trước: không tốn lần đọc GitHub nào cho thẻ đang làm
  if live=$(lane_live "$n"); then echo "kept card $n: live ${live#* } lane (pid ${live%% *}) holds it" >&2; continue; fi
  # gh hỏng / treo: dừng cả lượt (các thẻ sau cũng sẽ hỏng), không gỡ gì thêm
  rows=$(merged_rows "$n") || { echo "sweep: gh pr list failed (card $n); stopping, nothing more removed" >&2; break; }
  READ_OK=1
  if [ -z "$rows" ]; then
    drop_card "$n" || { [ "$DRY" -eq 0 ] || echo "kept card $n: no merged PR of it into $BASE" >&2; }
    continue
  fi
  if printf '%s\n' "$rows" | grep -q $'\tyoung$'; then echo "kept card $n: a PR of it merged under ${GRACE}s ago (Reviewer's post-merge steps)" >&2; continue; fi
  st=$(gh_t issue view "$n" --json state -q .state 2>/dev/null) || st="?"
  [ "$st" = CLOSED ] || { echo "kept card $n: issue state ${st:-?}, not CLOSED" >&2; continue; }
  i=0; list=""
  while [ "$i" -lt "${#WT_P[@]}" ]; do [ "${WT_N[$i]}" = "$n" ] && list="$list${WT_P[$i]}"$'\n'; i=$((i + 1)); done
  while IFS= read -r wt; do
    [ -n "$wt" ] && [ -d "$wt" ] || continue
    case "$HERE_PWD/" in "$(cd "$wt" && pwd -P)"/*) echo "kept $wt: it holds this sweep's working directory" >&2; continue ;; esac
    br=$(git -C "$wt" symbolic-ref -q --short HEAD 2>/dev/null) || br=""
    h=$(git -C "$wt" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || h=""
    pr=""; oid=""
    while IFS=$'\t' read -r _n rpr rref roid _age; do
      # Worktree trên nhánh: đúng nhánh của PR đó. Mọi worktree, có nhánh hay detached: HEAD là head đã merge hay tổ tiên của nó —
      # nhánh có commit mới sau lần merge (việc tiếp sau merge) thì giữ worktree, không gỡ chỉ vì khớp tên nhánh (OCR batch lượt 2).
      [ -z "$br" ] || [ "$br" = "$rref" ] || continue
      [ -n "$h" ] || continue
      [ "$h" = "$roid" ] || git -C "$REPO_PATH" merge-base --is-ancestor "$h" "$roid" 2>/dev/null || continue
      pr="$rpr"; oid="$roid"; break
    done <<<"$rows"
    if [ -z "$pr" ]; then
      echo "kept $wt: ${br:+on branch $br, }HEAD ${h:-<unknown>} is not the head of a merged PR of card $n" >&2; continue
    fi
    clean_wt "$wt" "$pr" "$oid"
  done < <(printf '%s' "$list" | wt_order)
  # Nhánh của PR đã merge: kit `prune-branch` (xoá chỉ khi PR MERGED đúng tip, không worktree nào checkout; commit chỉ reflog còn
  # giữ được cất vào refs/devkit/discarded 30 ngày). Không DevKit: giữ.
  while IFS=$'\t' read -r _n rpr rref roid _age; do
    tip=$(git -C "$REPO_PATH" rev-parse -q --verify "refs/heads/$rref" 2>/dev/null) || continue
    co=$(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null | awk -v b="branch refs/heads/$rref" '/^worktree /{w=substr($0,10)} $0==b{print w; exit}')
    if [ -n "$co" ] && ! printf '%s' "$DRY_GONE" | grep -qxF "$co"; then
      echo "kept branch $rref: still checked out at $co" >&2; continue
    fi
    if [ -z "$KIT_WT" ]; then   # (dry-run nói đúng như lần chạy thật: OCR)
      echo "kept branch $rref: no DevKit (agent-kit worktree prune-branch) to prove it safe" >&2
    elif [ "$DRY" -eq 1 ]; then
      if [ "$tip" = "$roid" ]; then echo "would delete branch $rref (PR #$rpr merged at its tip)" >&2
      else echo "would ask agent-kit prune-branch for $rref: tip $tip is not the merged $roid, deleted only if the trunk holds its content" >&2; fi
    else
      out=$(cd "$REPO_PATH" && python3 "$KIT_WT" prune-branch "$rref" 2>&1) || out="kept branch $rref: $(printf '%s\n' "$out" | grep -m1 '✖' | cut -c1-300)"
      printf '%s\n' "$out" >&2
    fi
  done <<<"$rows"
done
# Stamp chỉ khi đã đọc GitHub được ít nhất một lần: lỗi thoáng qua không chặn lần thử lại trong --min-interval giây (OCR).
[ "$DRY" -eq 1 ] || [ "$READ_OK" != 1 ] || [ -z "$STAMP" ] || { mkdir -p "${STAMP%/*}" && date +%s >"$STAMP"; } 2>/dev/null || true
exit 0
