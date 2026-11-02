# Sourced, not run: sb_verify_inject_flags <command> <base-branch> [json]
# In ra lệnh verify mà merge gate thật sự chạy: lệnh có token post-fix-gate.py được chèn ` --diff origin/<base> --scoped` (#251, #644:
# QA và merge gate phải chọn CÙNG tập suite cho cùng cây; nguồn duy nhất của luật chèn cờ là hàm này, gate và
# super-board-verify-cmd.sh cùng gọi). Đối số thứ ba `json` (chỉ merge gate): thêm cả ` --json` để đọc điều kiện CHƯA XÁC MINH mà REJECT che
# (#251 R1); --json chỉ đổi định dạng đầu ra, không đổi tập suite. Lệnh không có token đó: in nguyên. Không tách được token: in nguyên, cảnh báo ra stderr.
sb_verify_inject_flags() {
  local cmd="$1" base="$2" want_json="${3:-}" flags="" pfg_re pfg_after pfg_end pfg_rest pfg_args nl=$'\n'
  if [[ "$cmd" == *"post-fix-gate.py"* ]]; then
    # so TOKEN nguyên (chuỗi con thì `--full-name` cũng chặn --scoped); token kết thúc cả ở < > (`--full>log`).
    local tok_re="(^|[[:space:]\"'])--(full|force-full|scoped)(\$|[[:space:]\"';&|)<>])"
    # Không tách được token: để nguyên (không nối cờ vào lệnh khác); cảnh báo chỉ khi cả lệnh còn thiếu cờ (như trước #802).
    pfg_re="(^|[[:space:]\"'\`(){};&|=<>])[^[:space:]\"'\`(){};&|=<>]*post-fix-gate[.]py(\$|[[:space:]\"'\`(){};&|<>])"
    if ! [[ "$cmd" =~ $pfg_re ]]; then
      if [[ "$cmd" != *"--diff"* ]] || ! [[ "$cmd" =~ $tok_re ]]; then
        echo "warning: cannot locate the post-fix-gate.py token in the verify command; --diff/--scoped not added: ${cmd}" >&2
      fi
      printf '%s' "$cmd"; return 0
    fi
    pfg_after="${cmd#*"${BASH_REMATCH[0]}"}"
    pfg_end=$(( ${#cmd} - ${#pfg_after} - ${#BASH_REMATCH[2]} ))
    pfg_rest="${cmd:$pfg_end}"
    # #802: chỉ xét cờ trong phần đối số của post-fix-gate.py (từ sau token tới dấu hết lệnh ; & | ) } backtick, xuống dòng):
    # `… post-fix-gate.py --run-tests && npm run e2e -- --full` có --full của lệnh KHÁC, không phải của gate. Chuyển hướng không kết thúc
    # lệnh (`2>/dev/null --full`, `2>&1 --full`, `&>log --full`, `>|log --full`): bỏ & / | của >& <& &> >| trước khi cắt, không cắt ở < >.
    # ponytail: không hiểu ngoặc kép (`--only "a|b" --full` cắt ở |), nâng lên khi config verify có đối số chứa dấu đó.
    pfg_args="${pfg_rest//>&/> }"; pfg_args="${pfg_args//<&/< }"; pfg_args="${pfg_args//&>/ >}"; pfg_args="${pfg_args//>|/> }"
    pfg_args="${pfg_args%%[;&|)\}\`${nl}]*}"
    [[ "$pfg_args" == *"--diff"* ]] || flags=" --diff origin/${base}"
    # #644: mặc định --scoped (test của diff qua đồ thị import + smoke; #741: không bao giờ tự leo full — lõi chạy test chạm tới nó, không
    # suy ra test thì thêm [core-smoke]). Dòng config
    # còn ghi --full / --force-full thì giữ nguyên ý đó. --full đêm thuộc skill gate-full.
    [[ "$pfg_args" =~ $tok_re ]] || flags="$flags --scoped"
    [ "$want_json" = json ] && { [[ "$pfg_args" == *"--json"* ]] || flags="$flags --json"; }
    if [ -n "$flags" ]; then
      # Cờ chèn ngay sau token post-fix-gate.py (#102): nối vào cuối thì `… post-fix-gate.py --run-tests && npm test` đưa cờ cho npm,
      # `bash -c '…'` đưa cờ cho bash. Lệnh chỉ có một lệnh (phần sau token không có ; & | < > " ' ) } backtick, xuống dòng) giữ như
      # cũ: cờ ở cuối.
      if [[ "$pfg_rest" == *[\;\&\|\<\>\"\'\)\}\`${nl}]* ]]; then
        cmd="${cmd:0:$pfg_end}${flags}${pfg_rest}"
      else
        cmd="$cmd$flags"
      fi
    fi
  fi
  printf '%s' "$cmd"
}

# #226 gap 7 (R1/R3): biên nhận "cây gộp đã verify xanh". Một nguồn khoá cho merge gate (đọc/ghi) và QA (ghi, super-board-verify-cmd.sh --record).
# sb_verified_tree_receipt <tree-sha> <base-branch> <repo-path> <command>... → in đường dẫn biên nhận; rỗng khi không có git common dir.
# Khoá = sha256(tree, từng lệnh SAU khi chèn cờ, hash mọi bin/*.py của kit): kit chạy ngoài cây nên đổi kit phải đổi khoá, và
# post-fix-gate.py nạp các module cùng thư mục (suite_cache.py…), nên băm riêng một file thì sửa module không đổi khoá (OCR 24/10).
# ponytail: chỉ bin/*.py ở cấp một; module nạp từ thư mục khác của kit không vào khoá, nâng lên khi post-fix-gate nạp thêm thư mục.
# Không có công cụ sha256 thì in rỗng (không biên nhận), không bao giờ in đường dẫn thiếu khoá.
sb_verified_tree_receipt() {
  local tree="$1" base="$2" repo="$3" common kit key c f kdir hasher; shift 3
  common=$(cd "$repo" 2>/dev/null && d=$(git rev-parse --git-common-dir 2>/dev/null) && cd "$d" 2>/dev/null && pwd -P) || return 0
  [ -n "$common" ] || return 0
  if command -v shasum >/dev/null 2>&1; then hasher="shasum -a 256"
  elif command -v sha256sum >/dev/null 2>&1; then hasher="sha256sum"
  else return 0; fi
  # R4: kit thiếu ở $repo (worktree không link) thì dùng kit của chính checkout chứa script này; cả hai thiếu mới là `none`.
  kit=none
  for kdir in "$repo/.agents/devkit/bin" "$(dirname "${BASH_SOURCE[0]}")/../../.agents/devkit/bin"; do
    [ -f "$kdir/post-fix-gate.py" ] || continue
    kit=$(for f in "$kdir"/*.py; do git hash-object "$f"; done | $hasher | cut -d' ' -f1)
    break
  done
  key=$({ printf '%s\n%s\n' "$tree" "$kit"; for c in "$@"; do sb_verify_inject_flags "$c" "$base"; echo; done; } | $hasher | cut -d' ' -f1)
  [ -n "$key" ] || return 0
  printf '%s/super-board/verified-trees/%s' "$common" "$key"
}

# sb_redact_text: stdin → stdout qua redact_secrets() của kit (regression_checklist.py). Merge gate và train cùng dùng cho chữ tuỳ ý
# (lời git/hook, đuôi log verify) trước khi in vào log hay comment issue công khai (#775). Che cả đoạn một lần (không từng dòng): khối
# khoá PEM nhiều dòng chỉ nhận ra được khi thấy cả khối. Không nạp được bộ che: trả khác 0, không in gì (bên gọi giấu cả đoạn, không
# bao giờ in thô). Tìm kit cạnh file này (theo link khi bin được link vào thư mục khác), rồi $HERE của bên gọi, rồi $DEVKIT_ROOT.
# Link tương đối giải theo THƯ MỤC CỦA LINK, không theo cwd (cwd của gate/train nằm trong cây PR: không nạp regression_checklist.py
# do PR đặt). macOS không có `readlink -f`: giải một mức bằng tay.
sb_redact_text() {
  local kit="" d k src tgt
  src="${BASH_SOURCE[0]}"
  if tgt=$(readlink "$src" 2>/dev/null) && [ -n "$tgt" ]; then
    case "$tgt" in /*) src="$tgt" ;; *) src="$(dirname "$src")/$tgt" ;; esac
  fi
  for d in "$(cd "$(dirname "$src")" 2>/dev/null && pwd)" "${HERE:-/nonexistent}"; do
    [ -n "$d" ] || continue
    for k in "$d/../../universal-agent-devkit/bin" "$d/../../.agents/devkit/bin" "${DEVKIT_ROOT:-/nonexistent}/bin"; do
      [ -f "$k/regression_checklist.py" ] && { kit="$k"; break 2; }
    done
  done
  [ -n "$kit" ] || { cat >/dev/null; return 1; }
  python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1])
from regression_checklist import redact_secrets
sys.stdout.write(redact_secrets(sys.stdin.buffer.read().decode("utf-8", "replace")))' "$kit"
}
