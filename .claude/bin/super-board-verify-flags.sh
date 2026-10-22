# Sourced, not run: sb_verify_inject_flags <command> <base-branch>
# In ra lệnh verify mà merge gate thật sự chạy: lệnh có token post-fix-gate.py được chèn ` --diff origin/<base> --force-full` (#251:
# QA và merge gate phải chọn CÙNG tập suite cho cùng cây; nguồn duy nhất của luật chèn cờ là hàm này, gate và
# super-board-verify-cmd.sh cùng gọi). Lệnh không có token đó: in nguyên. Không tách được token: in nguyên, cảnh báo ra stderr.
sb_verify_inject_flags() {
  local cmd="$1" base="$2" flags="" pfg_re pfg_after pfg_end pfg_rest
  if [[ "$cmd" == *"post-fix-gate.py"* ]]; then
    [[ "$cmd" == *"--diff"* ]] || flags=" --diff origin/${base}"
    [[ "$cmd" == *"--force-full"* ]] || flags="$flags --force-full"
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
