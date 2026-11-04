# tests/lib/guard_shell_norm_lib.sh: phần dựng chung của tests/gates/test_guard_shell_norm*.sh (tách 03/11 để shard
# REG-DK-ALL-GATES-01 chạy các phần cùng lúc). Source sau khi đặt DEVKIT_DIR, HW và GG: tạo TMP (xoá khi thoát), FAILS, repo git
# nháp $P và các helper check / check_mcp / check_deny / pair / r5_rows (+ R5_COMMON). Chỉ chạy hook, không bao giờ chạy lệnh.
# Tương thích bash 3.2.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
# a hook that crashes fails closed (rc 2 and "lỗi nội bộ" on stderr): never the verdict a case waits for (review 15/10: su --command)
crashed() { grep -q -E 'lỗi nội bộ|python không chạy được|không nạp được shell_norm.py' "$TMP/err"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset HARDWARE_SAFETY_GATE HARDWARE_OVERRIDE DEVKIT_ALLOW_BRANCH CDPATH

P="$TMP/work/proj"
mkdir -p "$P/src/sub" "$P/build"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/src/a.kt" && printf 'y\n' > "$P/src/sub/b.kt" && printf 'z\n' > "$P/README.md"
git -C "$P" add -A && git -C "$P" commit -qm init && git -C "$P" branch feat

# check <want rc> <hw|git> <command>
check() {
  local want="$1" hook="$2" c="$3" h
  [ "$hook" = hw ] && h="$HW" || h="$GG"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$h" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$? s="${c//$'\n'/ ⏎ }"
  if [ "$rc" = "$want" ] && ! crashed; then ok "$hook rc $rc: ${s:0:110}"; else fail "$hook rc $rc (want $want): ${s:0:110} — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
}

# check_mcp <want rc> <device command>: the same through replicant-mcp adb-shell (its command runs on the device)
check_mcp() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"mcp__replicant-mcp__adb-shell","tool_input":{"command":sys.argv[1]}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$HW" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ] && ! crashed; then ok "mcp rc $rc: $c"; else fail "mcp rc $rc (want $want): $c — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
}
# check_deny <want rc> <command>: with the serial DENIED1 on the device denylist (only literal -s serials here: no adb call)
check_deny() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS=DENIED1 ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$HW" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ] && ! crashed; then ok "deny rc $rc: $c"; else fail "deny rc $rc (want $want): $c — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
}

# pair <want rc> <template with @BODY@>: the template through the git guard with a git danger in the body and through the hardware gate with
# an rm danger in it — each hook must reach the verdict by itself (review 15/10: a git row alone proves nothing about the hw gate)
pair() {
  local g="${2//@BODY@/git reset --hard}" w="${2//@BODY@/rm -rf ~}"   # @BODY@: a heredoc body, @CMD@: the command itself
  check "$1" git "${g//@CMD@/git reset --hard}"; check "$1" hw "${w//@CMD@/rm -rf ~}"
}

# rows_from_py <<'PY' … PY: the generator prints NUL separated triples (want rc, guard, command), each one is a check
r5_rows() {
  local want hook cmd
  while IFS= read -r -d '' -u 3 want && IFS= read -r -d '' -u 3 hook && IFS= read -r -d '' -u 3 cmd; do check "$want" "$hook" "$cmd"; done 3< <(python3 -I -c "$1")
}
R5_COMMON='
import shlex, sys
BS = "\\"
PAY = {"git": "git reset --hard", "hw": "rm -rf ~"}
CTL = {"git": "git status", "hw": "ls"}
def emit(want, hook, cmd):
    sys.stdout.write("%s\0%s\0%s\0" % (want, hook, cmd))
def both(tpl, hooks=("git", "hw"), want="2"):
    for h in hooks:
        emit(want, h, tpl.replace("@CMD@", PAY[h]))
        emit("0", h, tpl.replace("@CMD@", CTL[h]))
WRAPS = ["bash -c %s", "sh -c %s", "bash -lc %s", "eval %s", "ssh host %s", "zsh -c %s", "env bash -c %s", "sudo bash -c %s", "nohup sh -c %s"]
# ssh runs the script on another machine: the hardware gate does not refuse rm -rf ~ there (the remote home), for every version: git guard only
HOOKS_OF = lambda w: ("git",) if w.startswith("ssh") else ("git", "hw")
'
