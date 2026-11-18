#!/usr/bin/env bash
# #1302: lane QA kiểm đầu nhánh PR trước khi chốt kết quả. In một dòng và thoát:
#   0  current <sha>        đầu nhánh vẫn là sha QA đang chạy: giữ kết quả
#   10 rerun <sha> ...      đầu đã đổi: bỏ kết quả cũ, chạy lại QA trên <sha> (đã đứng yên)
#   11 blocked ...          head vẫn đổi sau N lần thử, hoặc không đứng yên trong --max-wait
# --sha = sha của origin/<PR branch> lúc QA bắt đầu (không phải HEAD của worktree QA sau khi merge main).
# Dùng: super-board-qa-head.sh --branch B --sha S [--attempt K] [--max-tries N]
#        [--settle 120] [--poll 5] [--max-wait 900]    (K = số lần QA đã chạy lại, tính từ 1)
set -u
branch=""; sha=""; attempt=1; max_tries=3; settle=120; poll=5; max_wait=900
while [ $# -gt 0 ]; do
  case "$1" in
    --branch|--sha|--attempt|--max-tries|--settle|--poll|--max-wait)
      [ $# -ge 2 ] || { echo "blocked: cờ $1 thiếu giá trị"; exit 11; } ;;
  esac
  case "$1" in
    --branch) branch="${2:-}"; shift 2 ;;
    --sha) sha="${2:-}"; shift 2 ;;
    --attempt) attempt="${2:-}"; shift 2 ;;
    --max-tries) max_tries="${2:-}"; shift 2 ;;
    --settle) settle="${2:-}"; shift 2 ;;
    --poll) poll="${2:-}"; shift 2 ;;
    --max-wait) max_wait="${2:-}"; shift 2 ;;
    *) echo "blocked: đối số lạ $1"; exit 11 ;;
  esac
done
for _kv in "attempt=$attempt" "max-tries=$max_tries" "settle=$settle" "poll=$poll" "max-wait=$max_wait"; do
  case "${_kv#*=}" in ''|*[!0-9]*) echo "blocked: cờ --${_kv%%=*} phải là số nguyên không âm (nhận '${_kv#*=}')"; exit 11 ;; esac
done
[ -n "$branch" ] && [ -n "$sha" ] || { echo "blocked: thiếu --branch hoặc --sha"; exit 11; }
remote="${SB_QA_HEAD_REMOTE:-origin}"

head_of() { git ls-remote "$remote" "refs/heads/$branch" 2>/dev/null | awk 'NR==1{print $1}'; }

cur="$(head_of)"
[ -n "$cur" ] || { echo "blocked: không đọc được head của $branch trên $remote"; exit 11; }
if [ "$cur" = "$sha" ]; then echo "current $cur"; exit 0; fi

if [ $((10#$attempt)) -ge $((10#$max_tries)) ]; then
  echo "blocked: head $branch vẫn đổi sau $attempt lần chạy QA (tối đa $max_tries); head mới nhất $cur"
  exit 11
fi

# Đợi head đứng yên: không đổi trong $settle giây (kiểm mỗi $poll giây), tối đa $max_wait giây.
start=$(date +%s); stable_since=$start
while :; do
  sleep "$poll"
  now=$(date +%s)
  nxt="$(head_of)"
  # ls-remote lỗi/rỗng KHÔNG phải head đứng yên: chặn thay vì rerun giả.
  [ -n "$nxt" ] || { echo "blocked: không đọc được head của $branch trên $remote khi đợi đứng yên (head cuối biết: $cur)"; exit 11; }
  if [ "$nxt" != "$cur" ]; then cur="$nxt"; stable_since=$now; fi
  if [ $((now - stable_since)) -ge "$settle" ]; then
    echo "rerun $cur attempt=$((10#$attempt + 1))/$max_tries (head đổi từ $sha)"
    exit 10
  fi
  if [ $((now - start)) -ge "$max_wait" ]; then
    echo "blocked: head $branch không đứng yên trong ${max_wait}s (đổi liên tục, $attempt lần chạy QA); head mới nhất $cur"
    exit 11
  fi
done
