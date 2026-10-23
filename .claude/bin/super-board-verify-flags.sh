# Sourced, not run: sb_verify_inject_flags <command> <base-branch> [json]
# In ra lệnh verify mà merge gate thật sự chạy: lệnh có token post-fix-gate.py được chèn ` --diff origin/<base> --force-full` (#251:
# QA và merge gate phải chọn CÙNG tập suite cho cùng cây; nguồn duy nhất của luật chèn cờ là hàm này, gate và
# super-board-verify-cmd.sh cùng gọi). Đối số thứ ba `json` (chỉ merge gate): thêm cả ` --json` để đọc điều kiện CHƯA XÁC MINH mà REJECT che
# (#251 R1); --json chỉ đổi định dạng đầu ra, không đổi tập suite. Lệnh không có token đó: in nguyên. Không tách được token: in nguyên, cảnh báo ra stderr.
sb_verify_inject_flags() {
  local cmd="$1" base="$2" want_json="${3:-}" flags="" pfg_re pfg_after pfg_end pfg_rest
  if [[ "$cmd" == *"post-fix-gate.py"* ]]; then
    [[ "$cmd" == *"--diff"* ]] || flags=" --diff origin/${base}"
    [[ "$cmd" == *"--force-full"* ]] || flags="$flags --force-full"
    [ "$want_json" = json ] && { [[ "$cmd" == *"--json"* ]] || flags="$flags --json"; }
    if [ -n "$flags" ]; then
      # Cờ chèn ngay sau token post-fix-gate.py (#102): nối vào cuối thì `… post-fix-gate.py --run-tests && npm test` đưa cờ cho npm,
      # `bash -c '…'` đưa cờ cho bash. Lệnh chỉ có một lệnh (phần sau token không có ; & | < > " ' ) }) giữ như cũ: cờ ở cuối.
      # Không tách được token: để nguyên và cảnh báo (không nối cờ vào lệnh khác).
      pfg_re="(^|[[:space:]\"'\`(){};&|=<>])[^[:space:]\"'\`(){};&|=<>]*post-fix-gate[.]py(\$|[[:space:]\"'\`(){};&|<>])"
      if [[ "$cmd" =~ $pfg_re ]]; then
        pfg_after="${cmd#*"${BASH_REMATCH[0]}"}"
        pfg_end=$(( ${#cmd} - ${#pfg_after} - ${#BASH_REMATCH[2]} ))
        pfg_rest="${cmd:$pfg_end}"
        if [[ "$pfg_rest" == *[\;\&\|\<\>\"\'\)\}]* ]]; then
          cmd="${cmd:0:$pfg_end}${flags}${pfg_rest}"
        else
          cmd="$cmd$flags"
        fi
      else
        echo "warning: cannot locate the post-fix-gate.py token in the verify command; --diff/--force-full not added: ${cmd}" >&2
      fi
    fi
  fi
  printf '%s' "$cmd"
}

# #226 gap 7 (R1/R3): biên nhận "cây gộp đã verify xanh". Một nguồn khoá cho merge gate (đọc/ghi) và QA (ghi, super-board-verify-cmd.sh --record).
# sb_verified_tree_receipt <tree-sha> <base-branch> <repo-path> <command>... → in đường dẫn biên nhận; rỗng khi không có git common dir.
# Khoá = sha256(tree, từng lệnh SAU khi chèn cờ, hash post-fix-gate.py của kit): kit chạy ngoài cây nên đổi kit phải đổi khoá.
sb_verified_tree_receipt() {
  local tree="$1" base="$2" repo="$3" common kit key c; shift 3
  common=$(cd "$repo" 2>/dev/null && d=$(git rev-parse --git-common-dir 2>/dev/null) && cd "$d" 2>/dev/null && pwd -P) || return 0
  [ -n "$common" ] || return 0
  kit=$(git hash-object "$repo/.agents/devkit/bin/post-fix-gate.py" 2>/dev/null || echo none)
  key=$({ printf '%s\n%s\n' "$tree" "$kit"; for c in "$@"; do sb_verify_inject_flags "$c" "$base"; echo; done; } | shasum -a 256 | cut -d' ' -f1)
  printf '%s/super-board/verified-trees/%s' "$common" "$key"
}
