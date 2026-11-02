#!/usr/bin/env bash
# #742 tách A1 (critical scan 31/10, BUG-REV-gpp-*): guard-protected-push.py phải thấy force push lên main nằm sau
# wrapper/keyword (time, nohup, nice, timeout, env -i, sudo -u, if/then, { }, !), trong `bash -lc STR`, sau --signed /
# --repo, sau một comment có dấu nháy; đọc payload camelCase (toolInput); config FIFO không làm treo hook.
# Mỗi ca chặn có một ca đối chứng vô hại (cùng dạng, không force) phải vẫn được phép (INSTINCT-045).
# ĐỎ trên hook của main d49f26cf (mọi dạng trên trả ALLOW, FIFO treo); XANH sau khi áp hunk guard của #742.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
unset SB_ALLOW_PROTECTED_PUSH   # công tắc tắt guard từ shell gọi test sẽ làm mọi kiểm tra chạy trên guard đã tắt
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DK/hooks/guard-protected-push.py"
FAILS=0

judge() {
  local name="$1" cmd="$2" branch="$3" want="$4" got
  got="$(python3 -c '
import importlib.util, sys
path, cmd, branch = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("gpp", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
reason = mod.check(cmd, "/repo", {"main", "master"}, lambda d: branch)
print("ALLOW" if reason is None else "BLOCK")
' "$HOOK" "$cmd" "$branch" 2>&1)"
  if [ "$got" = "$want" ]; then
    echo "✔ $name"
  else
    echo "✖ $name: got $got, want $want"
    FAILS=$((FAILS + 1))
  fi
}

judge "--signed takes no separate value (BUG-REV-gpp-signed)" "git push --signed -f origin main" feat BLOCK
judge "control: --signed without force stays allowed" "git push --signed origin main" feat ALLOW
judge "--repo=origin: every positional is a refspec (BUG-REV-gpp-repo-opt)" "git push -f --repo=origin main" feat BLOCK
judge "control: --repo=origin without force stays allowed" "git push --repo=origin main" feat ALLOW
judge "--repo origin: every positional is a refspec" "git push --repo origin -f main" feat BLOCK
judge "control: --repo origin without force stays allowed" "git push --repo origin main" feat ALLOW
for w in "if true; then git push -f origin main; fi" "time git push -f origin main" "{ git push -f origin main; }" \
         "nohup git push -f origin main" "nice -n 5 git push -f origin main" "timeout 30 git push -f origin main" \
         "env -i A=1 git push -f origin main" "! git push -f origin main" "sudo -u me git push -f origin main"; do
  judge "wrapper/keyword is skipped (BUG-REV-gpp-wrappers): $w" "$w" feat BLOCK
  c="${w/push -f/push}"
  judge "control: same wrapper without force stays allowed: $c" "$c" feat ALLOW
done
judge "sh -c STR is read (BUG-REV-gpp-wrappers)" "bash -lc 'git push --force origin main'" feat BLOCK
judge "control: sh -c STR without force stays allowed" "bash -lc 'git push origin main'" feat ALLOW
judge "a quote in a comment does not hide the next line (BUG-REV-gpp-comment)" "echo hi # it's
git push -f origin main" feat BLOCK
judge "control: comment with a quote, then a plain push stays allowed" "echo hi # it's
git push origin main" feat ALLOW

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.email t@t
git -C "$TMP/repo" config user.name t
git -C "$TMP/repo" commit -q --allow-empty -m init
# run_hook <payload-json>: the hook as the harness runs it (stdin JSON), killed after 5 s (prints TIMEOUT); stderr kept apart
run_hook() {
  python3 - "$HOOK" "$TMP/repo" "$1" <<'PY'
import os, subprocess, sys
hook, repo, payload = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    r = subprocess.run([sys.executable, hook], input=payload, capture_output=True, text=True, timeout=5,
                       env={**os.environ, "CLAUDE_PROJECT_DIR": repo})
    print(r.stdout.strip() + ("\nSTDERR:" + r.stderr.strip() if r.stderr.strip() else ""))
except subprocess.TimeoutExpired:
    print("TIMEOUT")
PY
}
payload() {   # payload <key> <command>
  python3 -c 'import json,sys; print(json.dumps({sys.argv[1]:{"command":sys.argv[2]},"cwd":sys.argv[3]}))' "$1" "$2" "$TMP/repo"
}
out="$(run_hook "$(payload toolInput "git push -f origin main")")"
case "$out" in *Force\ push*) echo "✔ camelCase toolInput payload is judged (BUG-REV-gpp-payload)" ;;
  *) echo "✖ camelCase payload not judged: $out"; FAILS=$((FAILS + 1)) ;; esac
out="$(run_hook "$(payload toolInput "git push origin main")")"
[ -z "$out" ] && echo "✔ control: camelCase payload with a plain push stays allowed, stderr empty" \
  || { echo "✖ camelCase plain push: $out"; FAILS=$((FAILS + 1)); }
out="$(run_hook '[1, 2]')"
case "$out" in *Traceback*|TIMEOUT|*deny*) echo "✖ a non-object payload crashed, hung or denied: $out"; FAILS=$((FAILS + 1)) ;;
  *) echo "✔ a non-object payload is no verdict, no traceback" ;; esac
mkdir -p "$TMP/repo/.claude/super-board/configs" && mkfifo "$TMP/repo/.claude/super-board/configs/x.json"
out="$(run_hook "$(payload tool_input "git push -f origin main")")"
case "$out" in *Force\ push*) echo "✔ a FIFO config does not hang the guard (BUG-REV-gpp-payload, INSTINCT-040)" ;;
  *) echo "✖ FIFO config hung or no deny: $out"; FAILS=$((FAILS + 1)) ;; esac
out="$(run_hook "$(payload tool_input "git push origin main")")"
[ -z "$out" ] && echo "✔ control: FIFO config, plain push stays allowed" \
  || { echo "✖ FIFO config, plain push: $out"; FAILS=$((FAILS + 1)); }
rm -f "$TMP/repo/.claude/super-board/configs/x.json"

[ "$FAILS" = 0 ] && exit 0
echo "$FAILS failure(s)"
exit 1
