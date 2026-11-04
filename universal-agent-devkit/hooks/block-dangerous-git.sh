#!/bin/bash
# block-dangerous-git.sh — PreToolUse guard cho Bash tool.
# Adapted từ mattpocock/skills (git-guardrails-claude-code).
# CHỈ chặn lệnh git KHÓ REVERSE / mất việc; CHO PHÉP `git push` thường
# (User thường chủ động yêu cầu push — CLAUDE.md: commit/push khi User yêu cầu).
# Contract: exit 2 + stderr = chặn tool call và trả lý do cho model; exit 0 = cho chạy.
# Bypass khi cần thật: User tự gõ lệnh qua prefix `!` trong prompt.
#
# How it decides (2026-09-23 rewrite — the regex-over-raw-text version was bypassed
# by `git -C . clean -fdx`, `\`-newline continuations and nested quotes, and blocked
# harmless chains like `git checkout main && rm -rf node_modules`):
#   1. Tokenize the command like a shell (python shlex) and split it into simple
#      commands on ; && || | & and newlines.
#   2. For each simple command whose program is git (after env assignments and
#      wrappers like `command`, `env`, `sudo`, `nohup`, `time`), skip git's global
#      options (-C dir, -c k=v, --git-dir=…, --no-pager, …) to find the real
#      subcommand, then check that subcommand's arguments.
#   3. `bash|sh|zsh -c STR`, `eval STR`, `ssh host STR`, `xargs CMD`, `watch CMD`,
#      `find … -exec CMD \;` are analysed recursively; `python|node|perl -c/-e STR`
#      is scanned with the raw regex. Quoted text passed to anything else
#      (echo, commit -m) is data.
#   3b. (2026-09-23 QA K-1/K-2) `( )`, `{ }` and shell keywords (if/then/do/!) split
#      or prefix commands; wrapper option VALUES are skipped (`sudo -u root`,
#      `nice -n 5`, `timeout 5`); `$var` in command position is treated as git;
#      `git -c alias.x=VAL x` checks VAL. Also blocked: `rm -f`, `rebase`,
#      `switch -C`, `checkout -B`. `restore --staged` (index only) is allowed.
#      (2026-09-23) `restore <file>…` of explicit files is allowed after the hook copies
#      them to .claude/audit-gate/restore-backup/; skipping git hooks is blocked:
#      `commit|push --no-verify`, `commit -n`, `-c core.hooksPath=…`, `DEVKIT_PRECOMMIT=0`.
#      Not a full shell parser: indirection through files/functions is out of scope.
#   3c. (2026-09-28) abbreviated long options (`reset --k`, `push --forc`) count as the full one;
#      config that skips hooks or forces a push is blocked in `-c`, `--config-env` and `git config`
#      (core.hooksPath, alias.*, remote.*.push +ref, remote.*.mirror); `branch -f/-M/-C <name>`
#      and `update-ref refs/heads/…` (or --stdin) overwrite a branch.
#   3d. (2026-09-28) the command inside `$(…)`/backticks goes through the same parser as a
#      top-level one; git words in the string literals of `python -c`/`node -e` are checked like
#      git args; git config from the environment (GIT_CONFIG_PARAMETERS, GIT_CONFIG_KEY_n/VALUE_n,
#      GIT_CONFIG_GLOBAL/SYSTEM other than /dev/null; prefix, env or export) and include.path /
#      includeIf.* (an external config file) are blocked.
#   3e. (2026-10-13, tests/gates/test_guard_shell_norm.sh) also blocked: `git checkout <path>` / `<tree-ish> <path>` without --
#      (one operand that names no commit but an existing path or a glob), an interpreter reading a heredoc whose body can start
#      a process (subprocess, os.system, child_process …) and runs a dangerous git command, `git submodule foreach CMD` (CMD is
#      judged), a forced fetch into a local branch (fetch -f / +src:dst), `git pull --rebase|-r`; arch, gtimeout and a redirect
#      before git are skipped like the other wrappers. Allowed now: `git clean` with -n / --dry-run, `git rm -f --cached`.
#   3f. (2026-10-14, workflow-improvements.md I.0 W3, tests/gates/test_guard_shell_norm.sh) the reading of a command line is
#      hooks/shell_norm.py, shared with hardware_safety_gate.sh: wrappers, sh -c in any flag cluster, also `su -c` / `su USER CMD`,
#      `adb shell CMD` and ssh options with a value (all analysed now). Heredocs (policy of 15/10): a body is cut only for a known
#      message option or the one statement of a fully modeled command; every other body stays in the scan (see heredoc_cut in block_dangerous_git_main.py).
#   4. FAIL-CLOSED: if the command can't be tokenized, or contains `$(`/backticks
#      whose output could become a command, the raw text is scanned with a broad
#      regex instead. Missing python3, or an uncaught internal error in the parser, blocks.

INPUT=$(cat)

# ── Fast path (2026-09-23): most Bash calls (ls, cat, npm test, ./gradlew …) contain
# nothing this gate reacts to, and starting python3 for them cost ~70–90 ms each.
# Bash-only: take the command value from the JSON with a builtin regex and allow it
# at once when it has NO backslash / quote / $ / backtick / glob char (anything that
# could hide a word from this check) and none of the trigger words (case-insensitive).
# Everything else — and any payload the regex cannot read — goes to the full parser.
fast_allow() { # $1 = trigger ERE
  local re='"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)"' c
  [[ $INPUT =~ $re ]] || return 1
  c="${BASH_REMATCH[1]}"
  # A REAL backslash (JSON \\: printf '\x67it' | sh, a gi\<newline>t continuation) or a \u escape can spell a word: parser.
  case "$c" in ""|*[\$\`\*\?\[\]]*|*'\\'*|*'\u'*) return 1 ;; esac
  # Quotes only hide a word by splitting it (g'i't, "gi"t): dropped before the check, with the JSON escape marks (\" \n), so a
  # quoted argument no longer sends every grep -n "x" to python (2026-10-09, tests/gates/test_hook_fast_path_quotes.sh: ~55 ms a call).
  # ${c//\\/} is quadratic on macOS /bin/bash 3.2: a 20 KB multi-line command (a \n per line) took 14-18 s, the hook timeout is 10 s
  # (tests/gates/test_hook_big_command_fast_path.sh). A long one goes through one linear tr; tr failing leaves the decision to the parser.
  if (( ${#c} > 256 )); then c="$(printf '%s' "$c" | LC_ALL=C tr -d '\\\047\042')" || return 1
  else c="${c//\\/}"; c="${c//\'/}"; c="${c//\"/}"; fi
  shopt -s nocasematch
  if [[ $c =~ $1 ]]; then shopt -u nocasematch; return 1; fi
  shopt -u nocasematch
  return 0
}
# A pipe into a shell (`cat x | sh`, `… | xargs bash -c`) or a here-string (`bash <<< …`) runs text the fast path cannot
# see: the parser reads it (2026-10-09, tests/gates/test_git_guard_shell_feed.sh). Bracket expressions, not \b: POSIX
# ERE has no \b (glibc adds it, macOS regcomp need not). A process substitution <(…) can be a shell's script (`bash <(curl …)`,
# 2026-10-09, tests/gates/test_git_guard_process_subst.sh): the parser reads it too, and so does `tee >(sh)`, a shell that reads
# what an output process substitution is fed (tests/gates/test_git_guard_shell_subst.sh). `bash -c "$(…)"` has a `$`: the parser.
# (#605) rm / unlink / find -delete: parser kiểm danh sách protected_delete. (#605 Lane H) gh (comment tự duyệt) và lời gọi xoá
# của interpreter (os.remove, os.unlink, shutil.rmtree, fs.rmSync, File.delete, FileUtils.rm_rf …) cũng vào parser.
# (audit T0066 vòng 2) ANTIGRAVITY_PM_STATE_HOME (chỉ dành cho test) cũng vào parser; (vòng 3) HOME= cũng vậy (lệnh gate / push kèm HOME lạ).
fast_allow 'git|eval|devkit_precommit|hookspath|antigravity_pm_state_home|devkit_pm_home_test|(^|[^[:alnum:]_])home=|pkill|killall|pgrep|(^|[^[:alnum:]_.-])(rm|unlink|gh)([^[:alnum:]_.-]|$)|-delete|unlink|remove|rmtree|rmsync|rmdirsync|rm_r|[.]delete|[|]([^|]*[^[:alnum:]_.-])?(ba|z|da|k|fi)?sh([^[:alnum:]_.-]|$)|<<<|<[(]|>[(]' && exit 0

if ! command -v python3 >/dev/null 2>&1; then
  echo "BLOCKED: block-dangerous-git.sh cần 'python3' để phân tích lệnh. Chặn để an toàn." >&2
  exit 2
fi

# The python of this guard is hooks/block_dangerous_git_main.py, beside this file (#967: inline code is compiled again at every
# Bash call, an imported module is cached: ~33 ms CPU less per call, measured 04/11). This loader: the hook directory from
# realpath($0), never the project (-I keeps the cwd off sys.path); bytecode only in the private directory of hooks/prompt_context.sh
# (#823: a real directory of this user that nobody else can write, lstat), else none, never a __pycache__ beside the hook. The
# module cannot be loaded: blocked with the reason (fail closed).
printf '%s' "$INPUT" | python3 -I -c '
import sys, os, stat
def _not_loaded(etype, value, tb):
    try:
        why = (str(value).splitlines() or [""])[0][:120]
        sys.stderr.write("BLOCKED: block-dangerous-git.sh: không nạp được hooks/block_dangerous_git_main.py cạnh hook (" + etype.__name__ + ": " + why
                         + ") — chặn để an toàn. Cài lại DevKit (agent-kit init); lệnh cần chạy ngay thì người dùng gõ qua prefix \"!\".\n")
        sys.stderr.flush()
    finally:
        os._exit(2)
sys.excepthook = _not_loaded   # the module installs its own fail-closed hook as its first statement
_d = os.path.dirname(os.path.realpath(sys.argv[1])) if len(sys.argv) > 1 else ""
if not os.path.isabs(_d):
    raise ImportError("hook path ($0) is not known")
sys.dont_write_bytecode = True
_c = os.environ.get("TMPDIR") or os.environ.get("XDG_CACHE_HOME") or (os.environ.get("HOME") or "") + "/.cache"
_c = (_c[:-1] if _c.endswith("/") else _c) + "/devkit-pycache-" + str(os.getuid())
if os.path.isabs(_c) and hasattr(sys, "pycache_prefix"):
    try:
        if not os.path.isdir(_c):
            os.mkdir(_c, 0o700)
        _st = os.lstat(_c)
    except OSError:
        _st = None   # no private bytecode directory (cannot be made, a dangling link, a race lost): uncached, as before #967
    if _st is not None and stat.S_ISDIR(_st.st_mode) and _st.st_uid == os.getuid() and not _st.st_mode & 0o022:
        sys.pycache_prefix = _c
        sys.dont_write_bytecode = False
sys.path.append(_d)   # after the stdlib
import block_dangerous_git_main
' "$0"
rc=$?
case "${rc}" in 0|2) exit "${rc}" ;; esac
echo "BLOCKED: block-dangerous-git.sh: python không chạy được (rc ${rc}). Chặn để an toàn (người dùng tự chạy lệnh qua prefix ! nếu đây là lỗi của cổng)." >&2
exit 2
