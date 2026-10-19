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
#  - sửa chưa commit chỉ thuộc danh sách rác của lane (NOISE_RE, và file đã xoá) được cất thành patch vào <git common dir>/
#    super-board/salvage/ (ngoài cây làm việc: main của trunk mode không bẩn thêm, như log verify của gate), kiểm patch dựng lại đúng
#    cây đó, trả worktree về HEAD rồi mới gỡ bằng kit. Sửa ngoài danh sách = việc thật: giữ worktree, in lý do.
#  - PR squash: head đã merge không nằm trong trunk, kit chỉ gỡ worktree detached khi một ref còn giữ head (nhánh, origin/<nhánh>).
#    Không ref nào giữ: lấy refs/pull/<PR>/head của GitHub (GitHub giữ head PR mãi) làm ref giữ tạm, bỏ ref đó khi xong.
#  - --sweep: cho runner gọi mỗi tick / lúc khởi động, dọn worktree + nhánh còn sót của thẻ đã merge (cũng là worktree review sau
#    khi Reviewer làm xong). Chỉ khi: một PR MERGED vào base có head là HEAD của worktree (hoặc HEAD là tổ tiên của head đó) hay là
#    nhánh nó đang checkout, đã merge quá SB_SWEEP_GRACE_S giây (mặc định 900: thời gian cho bước sau merge của Reviewer), issue
#    CLOSED, không lane nào của runner đang giữ thẻ (inflight/<N> có PID sống), không phiên DevKit nào giữ khoá checkout của worktree.
#    Một lần `gh pr list` cho cả repo; đọc GitHub hỏng hay board đang halt GitHub: không gỡ gì (không bao giờ ghi file halt).
#    Chạy lại trong --min-interval giây (mặc định 600) thì bỏ qua ngay. --dry-run chỉ in, không ghi gì.
set -u
MODE=post; DRY=0; MIN_INTERVAL=600; BASE=""; PR=""; HEAD_REF=""; MERGED_SHA=""
if [ "${1:-}" = --sweep ]; then
  MODE=sweep; REPO_ARG="${2:?repo path}"; shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY=1; shift ;;
      --base) BASE="${2:?branch}"; shift 2 ;;
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
# Sửa chưa commit coi là rác của lane (cất thành patch rồi bỏ; không giữ worktree vì nó): ghi chú / state của agent (.agents/local/),
# bằng chứng QA (docs/super-board/runs/, reports/), log, asset Unity tự serialize lại (*.asset), rác IDE. File đã xoá, kể cả xoá đã
# stage (` D`, `D `: HEAD vẫn giữ bản của nó), cũng vậy và được lấy lại từ HEAD. Đường dẫn khác, hay mọi thay đổi đã stage khác (index
# có thể giữ bản duy nhất), là việc thật: giữ worktree.
NOISE_RE='^(\.agents/local/|docs/super-board/runs/|reports/)|\.(asset|log)$|(^|/)\.(vscode|idea)/'

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

# tidy <wt>: 0 khi worktree sạch — sẵn sạch, hoặc mọi thay đổi chưa commit thuộc danh sách rác và đã được cất vào $SALVAGE_DIR
# (patch kiểm lại: HEAD + patch + file đã xoá = đúng cây làm việc) rồi trả về HEAD. 1 khi giữ (đã in lý do). --dry-run: chỉ nói.
tidy() {
  local wt="$1" st e xy p dels=0 noise=0 nreal=0 real="" trk untr sdel head gd name idx1 idx2 dl t1="" t2="" okk=0
  st=$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null) || { echo "kept $wt: git status failed" >&2; return 1; }
  [ -n "$st" ] || return 0
  st=$(mktemp) && trk=$(mktemp) && untr=$(mktemp) && sdel=$(mktemp) || { echo "kept $wt: uncommitted edits (mktemp failed)" >&2; return 1; }
  TIDY_SDEL="$sdel"   # clean_wt xoá nó
  if ! git -C "$wt" status --porcelain=v1 -z --no-renames --untracked-files=all >"$st" 2>/dev/null; then
    rm -f "$st" "$trk" "$untr"; echo "kept $wt: git status failed" >&2; return 1
  fi
  while IFS= read -r -d '' e; do
    xy=${e:0:2}; p=${e:3}
    case "$xy" in
      " D"|"D ")
        # Chỉ khi file thật sự không còn trên đĩa. Xoá đã stage mà file còn trên đĩa (`git rm --cached`) luôn là việc thật: file bị
        # ignore thì bản trên đĩa (có thể mới hơn HEAD) không vào patch nào (review 19/10); không bị ignore thì `D ` + `??` cùng đường dẫn
        # không trả về HEAD sạch được (checkout lấy lại rồi rm lại xoá).
        if [ ! -e "$wt/$p" ] && [ ! -L "$wt/$p" ]; then
          dels=$((dels + 1)); printf '%s\0' "$p" >>"$trk"
          [ "$xy" = " D" ] || printf '%s\0' "$p" >>"$sdel"   # xoá đã stage: untidy stage lại đúng như vậy (OCR)
          continue
        fi ;;
      " M"|" T"|"??")
        if [[ "$p" =~ $NOISE_RE ]]; then
          noise=$((noise + 1))
          if [ "$xy" = "??" ]; then printf '%s\0' "$p" >>"$untr"; else printf '%s\0' "$p" >>"$trk"; fi
          continue
        fi ;;
    esac
    nreal=$((nreal + 1)); [ "$nreal" -le 5 ] && real="${real:+$real, }$p"
  done <"$st"
  rm -f "$st"
  if [ "$nreal" -gt 0 ]; then
    echo "kept $wt: uncommitted edits outside the salvage list ($nreal path(s)): $real" >&2
    rm -f "$trk" "$untr"; return 1
  fi
  if [ "$DRY" -eq 1 ]; then
    echo "would salvage $wt: $noise edited or new file(s) on the salvage list, $dels deleted file(s) restored from HEAD" >&2
    rm -f "$trk" "$untr"; return 0
  fi
  head=$(git -C "$wt" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || head=""
  gd=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) || gd=""
  if [ -z "$SALVAGE_DIR" ] || [ -z "$head" ] || [ -z "$gd" ] || ! mkdir -p "$SALVAGE_DIR"; then
    echo "kept $wt: uncommitted edits (no place to salvage them: git dir or HEAD unreadable)" >&2
    rm -f "$trk" "$untr"; return 1
  fi
  name="$SALVAGE_DIR/${wt##*/}-$(date +%Y%m%d-%H%M%S)-$$"
  idx1=$(mktemp); idx2="$idx1.verify"; dl=$(mktemp)   # idx2 chưa tồn tại: git từ chối một file index 0 byte ở vài bản (OCR)
  # Chụp cây làm việc vào một index TẠM chép từ index thật (GIT_INDEX_FILE chỉ cho từng lệnh, không export: index thật không bị đụng),
  # rồi dựng lại từ HEAD + patch + danh sách file đã xoá trong index tạm thứ hai: hai cây phải trùng, không thì không bỏ gì.
  if cp "$gd/index" "$idx1" \
     && GIT_INDEX_FILE="$idx1" git -C "$wt" add -A -- . \
     && t1=$(GIT_INDEX_FILE="$idx1" git -C "$wt" write-tree) \
     && GIT_INDEX_FILE="$idx1" git -C "$wt" diff --cached --binary --no-renames --diff-filter=d "$head" >"$name.patch" \
     && GIT_INDEX_FILE="$idx1" git -C "$wt" diff --cached -z --name-only --no-renames --diff-filter=D "$head" >"$dl" \
     && GIT_INDEX_FILE="$idx2" git -C "$wt" read-tree "$head" \
     && { [ ! -s "$name.patch" ] || GIT_INDEX_FILE="$idx2" git -C "$wt" apply --cached "$name.patch"; } \
     && { [ ! -s "$dl" ] || GIT_INDEX_FILE="$idx2" git -C "$wt" update-index -z --force-remove --stdin <"$dl"; } \
     && t2=$(GIT_INDEX_FILE="$idx2" git -C "$wt" write-tree) && [ "$t1" = "$t2" ]; then
    okk=1
  fi
  rm -f "$idx1" "$idx2"
  [ -s "$name.patch" ] || rm -f "$name.patch"
  if [ "$okk" != 1 ]; then
    echo "kept $wt: uncommitted edits (salvage could not be verified: tree ${t1:-?} vs ${t2:-?})" >&2
    rm -f "$trk" "$untr" "$dl"; return 1
  fi
  [ ! -s "$dl" ] || tr '\0' '\n' <"$dl" >"$name.deleted.txt"
  printf 'worktree: %s\nhead: %s\nat: %s\nedited or new (lane noise): %s file(s)%s\ndeleted, restored from HEAD: %s file(s)%s\n' \
    "$wt" "$head" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$noise" "$( [ -f "$name.patch" ] && printf ' -> git apply --3way %s (on %s)' "$name.patch" "$head")" \
    "$dels" "$( [ -s "$dl" ] && printf ' (%s)' "$name.deleted.txt")" >"$name.txt"
  TIDY_NAME="$name"; TIDY_DL="$dl"   # clean_wt trả lại đúng các thay đổi này nếu worktree không bị gỡ (untidy)
  # Trả về HEAD: file đã theo dõi (sửa / xoá) lấy lại bản HEAD, file mới (đã cất) bị xoá. --literal-pathspecs: tên có * ? [ không là mẫu.
  if { [ ! -s "$trk" ] || git -C "$wt" --literal-pathspecs checkout -q HEAD --pathspec-from-file="$trk" --pathspec-file-nul; } \
     && { [ ! -s "$untr" ] || (cd "$wt" && xargs -0 rm -f -- <"$untr"); } \
     && [ -z "$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null)" ]; then
    rm -f "$trk" "$untr"
    echo "salvaged $wt: $noise edited or new, $dels deleted file(s) -> $name.txt" >&2
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
# refs/pull/<pr>/head của GitHub vào refs/remotes/origin/pull/<pr>/head, chỉ khi nó đúng <merged-head> và HEAD là nó hay tổ tiên
# của nó; ref đó được bỏ khi thoát (commit vẫn ở GitHub). 1: không giữ được, người gọi giữ worktree.
hold_head() {
  local h r got
  h=$(git -C "$1" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || return 1
  [ -n "$(git -C "$REPO_PATH" for-each-ref --count=1 --contains "$h" refs/heads refs/remotes refs/tags 2>/dev/null)" ] && return 0
  [ -n "$2" ] && [ -n "$3" ] || return 1
  git -C "$REPO_PATH" merge-base --is-ancestor "$h" "$3" 2>/dev/null || return 1
  # số PR (vào refspec): `*` sẽ kéo mọi PR head về ref không ai bỏ (review)
  case "$2" in ''|*[!0-9]*) HOLD_WHY="PR number '$2' is not a number"; return 1 ;; esac
  r="refs/remotes/origin/pull/$2/head"
  if git -C "$REPO_PATH" rev-parse -q --verify "$r" >/dev/null; then   # ref cùng tên của ai khác mà không giữ HEAD: không đè
    HOLD_WHY="$r already exists and does not hold HEAD $h"; return 1
  fi
  if [ "$DRY" -eq 1 ]; then echo "would hold ${h} with ${r} (GitHub refs/pull/$2/head)" >&2; return 0; fi
  # không có hạn giờ (run_t) thì không fetch: giữ worktree
  command -v python3 >/dev/null 2>&1 || { HOLD_WHY="no python3 to fetch $r with a deadline"; return 1; }
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
# "được giữ" thì như cũ (review 19/10). Bản cất vẫn còn ở $TIDY_NAME.txt.
untidy() {
  local ok=1
  # Bước trả về HEAD hỏng giữa chừng thì patch không áp lại được: không động gì nữa (không xoá file nào), bản cất còn nguyên (OCR).
  if [ -f "$TIDY_NAME.patch" ] && ! git -C "$1" apply --check --binary "$TIDY_NAME.patch" 2>/dev/null; then
    echo "kept $1: it stays, its lane edits could not be put back cleanly (left as is): they are in $TIDY_NAME.txt" >&2; return 0
  fi
  [ ! -f "$TIDY_NAME.patch" ] || git -C "$1" apply --binary "$TIDY_NAME.patch" 2>/dev/null || ok=0
  [ ! -s "$TIDY_DL" ] || (cd "$1" && xargs -0 rm -f -- <"$TIDY_DL") || ok=0
  [ ! -s "$TIDY_SDEL" ] || git -C "$1" update-index -z --force-remove --stdin <"$TIDY_SDEL" || ok=0
  if [ "$ok" = 1 ]; then echo "restored $1: it stays, so its lane edits are back as they were (copy in $TIDY_NAME.txt)" >&2
  else echo "kept $1: it stays, but putting its lane edits back failed: they are in $TIDY_NAME.txt" >&2; fi
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
  TIDY_NAME=""; TIDY_DL=""; TIDY_SDEL=""
  if ! tidy "$wt"; then
    [ -z "$TIDY_NAME" ] || untidy "$wt"
    rm -f "$TIDY_DL" "$TIDY_SDEL"; return 0
  fi
  if [ "$DRY" -eq 1 ]; then echo "would remove $wt" >&2; DRY_GONE="$DRY_GONE$wt"$'\n'; rm -f "$TIDY_SDEL"; return 0; fi
  remove_wt "$wt"
  # kit (hay git) từ chối gỡ — reflog, rebase dở, submodule, bí mật chỉ worktree có…: trả lại phần rác đã cất
  [ -z "$TIDY_NAME" ] || [ ! -d "$wt" ] || untidy "$wt"
  rm -f "$TIDY_DL" "$TIDY_SDEL"
}
DRY_GONE=""   # --dry-run: worktree "would remove" (nhánh chúng checkout được tính như đã thả)
# Bản cất quá 30 ngày được bỏ, như refs/devkit/discarded của kit: thư mục salvage không thành chỗ đầy đĩa mới (OCR). Cả hai chế độ.
prune_salvage() {
  [ "$DRY" -eq 0 ] && [ -n "$SALVAGE_DIR" ] && [ -d "$SALVAGE_DIR" ] || return 0
  find "$SALVAGE_DIR" -maxdepth 1 -type f \( -name '*.patch' -o -name '*.txt' \) -mtime +30 -exec rm -f {} + 2>/dev/null || true
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
  [ $(( $(date +%s) - last )) -lt "$MIN_INTERVAL" ] && exit 0
fi
GH_READ="$(cd "$(dirname "$0")" && pwd)/super-board-github-read.py"
if [ -f "$GH_READ" ] && ! SB_REPO_PATH="$REPO_PATH" python3 "$GH_READ" --check >/dev/null 2>&1; then
  echo "sweep skipped: GitHub reads are halted for this board (super-board-github-read.py --check)" >&2; exit 0
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

JSON=$(gh_t pr list --state merged --base "$BASE" --limit 200 --json number,headRefName,headRefOid,baseRefName,isCrossRepository,mergedAt) \
  || { echo "sweep: gh pr list failed; nothing removed" >&2; exit 0; }
# Mỗi PR merged của một thẻ: "<N>\t<PR>\t<nhánh>\t<head>\t<old|young>". Dòng đọc không được: bỏ dòng đó (không gỡ theo nó).
ROWS=$(printf '%s' "$JSON" | python3 -I -c '
import calendar, json, re, sys, time
grace, base = int(sys.argv[1]), sys.argv[2]
for r in json.load(sys.stdin):
    try:
        m = re.match(r"issue-([0-9]+)-", r["headRefName"])
        if not m or r["isCrossRepository"] is not False or r["baseRefName"] != base or not re.fullmatch(r"[0-9a-f]{40}", r["headRefOid"]):
            continue
        age = time.time() - calendar.timegm(time.strptime(r["mergedAt"], "%Y-%m-%dT%H:%M:%SZ"))
        print(m.group(1), r["number"], r["headRefName"], r["headRefOid"], "old" if age >= grace else "young", sep="\t")
    except (KeyError, TypeError, ValueError):
        continue
' "$GRACE" "$BASE") || { echo "sweep: gh pr list output unreadable; nothing removed" >&2; exit 0; }
# Stamp chỉ sau một lần đọc GitHub thành công: lỗi thoáng qua không chặn lần thử lại trong --min-interval giây (OCR).
[ "$DRY" -eq 1 ] || [ -z "$STAMP" ] || { mkdir -p "${STAMP%/*}" && date +%s >"$STAMP"; } 2>/dev/null || true
prune_salvage

for n in $NS; do
  rows=$(printf '%s\n' "$ROWS" | awk -F'\t' -v n="$n" '$1 == n')
  if [ -z "$rows" ]; then [ "$DRY" -eq 0 ] || echo "kept card $n: no merged PR of it into $BASE" >&2; continue; fi
  if printf '%s\n' "$rows" | grep -q $'\tyoung$'; then echo "kept card $n: a PR of it merged under ${GRACE}s ago (Reviewer's post-merge steps)" >&2; continue; fi
  if live=$(lane_live "$n"); then echo "kept card $n: live ${live#* } lane (pid ${live%% *}) holds it" >&2; continue; fi
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
      if [ -n "$br" ]; then [ "$br" = "$rref" ] || continue
      elif [ -z "$h" ] || { [ "$h" != "$roid" ] && ! git -C "$REPO_PATH" merge-base --is-ancestor "$h" "$roid" 2>/dev/null; }; then continue
      fi
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
exit 0
