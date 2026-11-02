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
#      message option or the one statement of a fully modeled command; every other body stays in the scan (see heredoc_cut below).
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

printf '%s' "$INPUT" | python3 -I -c '
import os, sys
# FAIL-CLOSED on a crash (2026-10-04): an uncaught exception exits 1, which Claude Code lets through. Installed before any other
# import. -I (above) keeps the cwd off sys.path: a json.py / shlex.py in the project root would otherwise replace the stdlib module.
def _fail_closed(etype, value, tb):
    try:
        why = (str(value).splitlines() or [""])[0][:100]
        sys.stderr.write("BLOCKED: block-dangerous-git.sh lỗi nội bộ (" + etype.__name__ + ": " + why + "). Chặn để an toàn. Nếu đây là lỗi của cổng: người dùng tự chạy lệnh qua prefix \"!\".\n")
        sys.stderr.flush()
    finally:
        os._exit(2)
sys.excepthook = _fail_closed
import fnmatch, json, re, shlex, shutil, subprocess, time, signal
# Watchdog (same as the hardware gate, whose hook limit is 10 s): a command the parser cannot judge in 7 s is refused with a reason, never
# left to a hook timeout, which is no verdict. SIGALRM also interrupts a regex search in the middle. tests/gates/test_hook_big_command_fast_path.sh
def _too_slow(_sig, _frame):
    try:
        sys.stderr.write("BLOCKED: block-dangerous-git.sh: lệnh quá lớn / quá phức tạp để phân tích trong thời hạn (7 s) — chặn để an toàn. Chia thành lệnh nhỏ hơn, hoặc ghi vào file rồi chạy file.\n")
        sys.stderr.flush()
    finally:
        os._exit(2)
if hasattr(signal, "setitimer"):
    signal.signal(signal.SIGALRM, _too_slow)
    signal.setitimer(signal.ITIMER_REAL, 7)
_GUARD_T0 = time.time()   # (#536) mốc của thời hạn chung khi guard phải gọi helper nhãn merge-queue

# hooks/shell_norm.py: the one reading of a command line that this guard and hardware_safety_gate.sh share (W3, 14/10): wrappers,
# sh -c / su -c / ssh / adb shell, heredocs. Loaded from this hook own directory ($0, a linked install resolved), never from the
# project (python3 -I). Missing: every command that reaches this parser is blocked, with the reason (fail closed).
try:
    _HOOK_DIR = os.path.dirname(os.path.realpath(sys.argv[1])) if len(sys.argv) > 1 else ""
    if not os.path.isabs(_HOOK_DIR):
        raise ImportError("hook path ($0) is not known")
    sys.dont_write_bytecode = True
    sys.path.append(_HOOK_DIR)   # after the stdlib
    import shell_norm
except Exception as e:
    sys.stderr.write("BLOCKED: block-dangerous-git.sh: không nạp được hooks/shell_norm.py cạnh hook (" + str(e)[:120] + ") — chặn để an "
                     "toàn. Cài lại DevKit (agent-kit init); lệnh cần chạy ngay thì người dùng gõ qua prefix \"!\".\n")
    sys.exit(2)

def _fnm(name, pat):
    # Python 3.9 raises re.error for a reversed range ([z-a], the s[:-1] of a script); bash reads such a bracket as "no match"
    try:
        return fnmatch.fnmatch(name, pat)
    except re.error:
        return False

try:
    PAYLOAD = json.load(sys.stdin)
    # toolInput: the camelCase envelope (Grok, hooks/devkit_harness.py); input: as hardware_safety_gate (2026-10-09:
    # {"toolName":"Bash","toolInput":{"command":"git push -f …"}} found no command and passed).
    cmd = (PAYLOAD.get("tool_input") or PAYLOAD.get("toolInput") or PAYLOAD.get("input") or {}).get("command") or ""
except Exception:
    print("BLOCKED: block-dangerous-git.sh không đọc được JSON đầu vào. Chặn để an toàn.", file=sys.stderr)
    sys.exit(2)
if not isinstance(cmd, str) or not cmd.strip():
    sys.exit(0)

SEPARATORS = {";", "&&", "||", "|", "&", "\n", ";;", "|&", "(", ")", "{", "}", "((", "))"}
# Shell reserved words that may precede a command in the same simple-command slot
# (`if git reset --hard; then …`, `! git …`, `do git …`). Skipped, not analysed.
KEYWORDS = shell_norm.KEYWORDS
# wrapper -> (options that take a separate value, number of positional args before the command): the shared table
# (gtimeout and arch since 2026-10-13)
WRAPPERS = shell_norm.WRAPPERS
INTERPRETERS = {"python", "python2", "python3", "node", "perl", "ruby", "php", "deno", "bun"}
# awk runs commands with system() and `print … | "sh"`: the string literals of its program are checked (2026-10-09).
AWKS = {"awk", "gawk", "mawk", "nawk"}
SHELLS = shell_norm.SHELLS
SHELL_OPTS_WITH_ARG = shell_norm.SHELL_OPTS_WITH_ARG
GIT_OPTS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix", "--config-env"}

def short_flags(args):
    """Letters of every single-dash short-option cluster, e.g. -xdf -> {x,d,f}."""
    out = set()
    for a in args:
        if a.startswith("-") and not a.startswith("--") and len(a) > 1:
            out.update(a[1:])
    return out

# git takes any unique prefix of a long option: `git reset --k HEAD~1` IS --keep (measured
# 2026-09-28, git 2.55). Per subcommand: the long options danger_in_git reacts to, and the safe
# options sharing the longest prefix with them (from `git <sub> --git-completion-helper-all`) —
# a prefix of a safe one is ambiguous to git too, so it is left alone.
ABBREV = {
    "pull": ("--rebase", "--recurse-submodules --refmap"),
    "fetch": ("--force", "--filter"),
    "reset": ("--hard --merge --keep", "--mixed"),
    "clean": ("--force", ""),
    "branch": ("--delete --force", "--format"),
    "checkout": ("--force", ""),
    "switch": ("--force --discard-changes --force-create", "--detach"),
    "rm": ("--force", ""),
    "push": ("--force --force-with-lease --force-if-includes --delete --mirror --prune --no-verify --all --branches --tags",
             "--dry-run --follow-tags --no-verbose --progress --atomic --thin --no-thin"),
    "commit": ("--no-verify", "--no-verbose"),
    "merge": ("--no-verify", "--no-verify-signatures"),
    "am": ("--no-verify", "--no-quiet"),
    "gc": ("--prune", ""),
    "worktree": ("--force", ""),
    "update-ref": ("--stdin", ""),
}

def expand_abbrev(sub, args):
    """`--forc` -> `--force` (and `--forc=x` -> `--force=x`) for the options in ABBREV[sub],
    so every check below sees the full name. An exact option name wins; `--` ends the options."""
    danger, safe = (s.split() for s in ABBREV.get(sub, ("", "")))
    out = []
    for k, a in enumerate(args):
        if a == "--":
            return out + args[k:]
        name, eq, val = a.partition("=")
        if name.startswith("--") and len(name) >= 3 and name not in danger and name not in safe:
            hit = next((d for d in danger if d.startswith(name)), None)
            if hit and not any(s.startswith(name) for s in safe):
                a = hit + eq + val
        out.append(a)
    return out

def config_danger(key, val):
    """A config key=val (git -c, --config-env, git config) that skips the hooks or forces a push.
    val None = unknown (from an environment variable). Section and name are case-insensitive."""
    parts = key.lower().split(".")
    if parts == ["core", "hookspath"]:
        return "core.hooksPath tắt git hook (pre-commit kiểm secret/chất lượng)"
    if parts[0] in ("include", "includeif"):
        return "include.path/includeIf nạp file config ngoài, không kiểm được"
    if parts[0] == "alias" and len(parts) > 1:
        return "alias lấy từ biến môi trường, không kiểm được" if val is None else git_danger_from_alias(val)
    if parts == ["push", "default"] and (val is None or val.lower() == "matching"):
        return "push.default=matching đẩy mọi nhánh trùng tên với remote"
    if parts == ["remote", "pushdefault"] or (parts[0] == "branch" and len(parts) > 2 and parts[-1] in ("pushremote", "remote")):
        return "remote.pushDefault / branch.<b>.pushRemote|remote đổi remote mà git push gửi tới, không kiểm được"
    if parts[0] == "url" and len(parts) > 2 and parts[-1] in ("insteadof", "pushinsteadof"):
        return "url.<base>.insteadOf/pushInsteadOf đổi nơi push gửi tới, không kiểm được"
    if parts[0] == "remote" and len(parts) > 2:
        if parts[-1] == "pushurl":
            return "remote.<tên>.pushurl đổi máy chủ mà git push gửi tới, không kiểm được"
        if parts[-1] == "push":
            return "remote.<tên>.push đổi những ref mà git push gửi (cả refspec không glob), không kiểm được"
        if parts[-1] == "mirror" and (val is None or val.lower() not in ("false", "no", "off", "0", "")):
            return "remote.<tên>.mirror = push --mirror ghi đè/xoá trên remote"
    return None

CONFIG_OPTS_WITH_ARG = {"-f", "--file", "--blob", "--type", "--default", "--comment", "--value", "--url"}
CONFIG_READ = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--get-color", "--get-colorbool",
               "--list", "-l", "--unset", "--unset-all", "--remove-section", "--rename-section", "--edit", "-e"}

def config_write_danger(args):
    """`git config [set] <key> <value>` writing a key config_danger rejects. Reads pass."""
    pos, k = [], 0
    while k < len(args):
        a = args[k]
        if a in CONFIG_OPTS_WITH_ARG:
            k += 2
            continue
        if a.split("=", 1)[0] in CONFIG_READ:
            return None
        if not a.startswith("-"):
            pos.append(a)
        k += 1
    if pos[:1] == ["set"]:
        pos = pos[1:]
    elif pos[:1] and pos[0] in ("get", "list", "unset", "rename-section", "remove-section", "edit"):
        return None
    return config_danger(pos[0], pos[1]) if len(pos) >= 2 else None

def clean_dry_run(args):
    """git clean -n / --dry-run: a short cluster letter n before any e (-e takes its pattern, glued or as the next word)."""
    for a in args:
        if a == "--":
            break
        if a == "--dry-run":
            return True
        if a.startswith("-") and not a.startswith("--"):
            for ch in a[1:]:
                if ch == "e":
                    break
                if ch == "n":
                    return True
    return False

def danger_in_git(sub, args):
    args = expand_abbrev(sub, args)
    long_ = set(a.split("=", 1)[0] for a in args if a.startswith("--"))
    short = short_flags(args)
    pos = [a for a in args if not a.startswith("-")]
    if sub == "reset" and long_ & {"--hard", "--merge", "--keep"}:
        return "reset --hard/--merge/--keep vứt thay đổi"
    # (2026-10-13) -n / --dry-run only lists what would go, also next to -f; (14/10, OCR) the letters after a glued -e are its
    # pattern, not flags: git clean -fdx -enode_modules deletes
    if sub == "clean" and ("f" in short or "--force" in long_) and not clean_dry_run(args):
        return "clean --force xoá file chưa track"
    if sub == "branch" and ("D" in short or (("d" in short or "--delete" in long_) and ("f" in short or "--force" in long_))):
        return "branch -D xoá branch chưa merge"
    if sub == "branch" and pos and (short & {"M", "C", "f"} or "--force" in long_):
        return "branch -f/-M/-C ghi đè branch đã có"
    if sub in ("checkout", "switch"):
        if "f" in short or long_ & {"--force", "--discard-changes"}:
            return f"{sub} --force vứt thay đổi local"
        if sub == "checkout" and ("--" in args or "." in pos):
            return "checkout -- <path> vứt thay đổi working tree"
        if (sub == "checkout" and "B" in short) or (sub == "switch" and ("C" in short or "--force-create" in long_)):
            return f"{sub} -B/-C ghi đè branch đã có"
    if sub == "restore":
        staged_only = ("--staged" in long_ or "S" in short) and not ("--worktree" in long_ or "W" in short)
        if not staged_only:
            return "restore vứt thay đổi working tree"
    # (2026-10-13) --cached removes from the index only: the working-tree file stays (like restore --staged)
    if sub == "rm" and ("f" in short or "--force" in long_) and "--cached" not in long_:
        return "rm --force xoá file kèm thay đổi chưa commit"
    if sub == "rebase" and not long_ & {"--abort", "--continue", "--skip", "--quit", "--show-current-patch", "--edit-todo"}:
        return "rebase viết lại lịch sử branch"
    if sub == "pull":   # (2026-10-13) pull --rebase / -r is a rebase; the last of --rebase[=x] / --no-rebase / -r wins
        rebase = False
        for a in args:
            if a == "--":
                break
            if a == "--no-rebase":
                rebase = False
            elif a == "--rebase" or a.startswith("--rebase="):
                rebase = a.partition("=")[2].lower() not in ("false", "no", "off", "0")
            elif a.startswith("-") and not a.startswith("--"):
                for ch in a[1:]:
                    if ch in "sXjoS":   # an option whose value follows glued on (-Xours, -j4): no more flags in this word
                        break
                    rebase = rebase or ch == "r"
        if rebase:
            return "pull --rebase viết lại lịch sử branch (như rebase; dùng git pull --no-rebase hoặc --ff-only)"
    if sub == "fetch":   # (2026-10-13) a forced (--force / +src:dst) fetch INTO a local branch drops its unpushed commits
        forced = "f" in short or "--force" in long_
        for a in pos:
            if ":" not in a or "://" in a or "@" in a.split(":", 1)[0]:
                continue   # no refspec, or a URL / user@host:path remote
            dst = a.split(":", 1)[1]
            dst = dst[len("refs/heads/"):] if dst.startswith("refs/heads/") else dst
            if (forced or a.startswith("+")) and dst and not dst.startswith("refs/"):
                return f"fetch --force / +refspec {a} ghi đè nhánh local, mất commit chưa push"
    if sub == "push":
        if "f" in short or "d" in short or long_ & {"--force", "--force-with-lease", "--force-if-includes", "--delete", "--mirror", "--prune"}:
            return "push --force/--delete/--mirror ghi đè hoặc xoá trên remote"
        if any(a.startswith("+") or a.startswith(":") for a in pos):
            return "push +refspec / :ref ghi đè hoặc xoá trên remote"
    if sub == "stash" and pos[:1] and pos[0] in ("drop", "clear"):
        return "stash drop/clear mất stash"
    if sub == "reflog" and pos[:1] and pos[0] in ("expire", "delete"):
        return "reflog expire/delete mất lịch sử khôi phục"
    if sub == "gc" and any(a.startswith("--prune") for a in args):
        return "gc --prune xoá object không còn tham chiếu"
    if sub == "update-ref" and ("d" in short or "--delete" in long_):
        return "update-ref -d xoá ref"
    if sub == "update-ref" and ("--stdin" in long_ or any(p.startswith("refs/heads/") for p in pos)):
        return "update-ref ghi thẳng vào nhánh (như reset/branch -f)"
    if sub == "config":
        reason = config_write_danger(args)
        if reason:
            return f"git config {reason}"
    if sub in ("filter-branch", "filter-repo"):
        return f"{sub} viết lại lịch sử"
    # Skipping the git hooks skips the pre-commit secret/quality gate (githooks.sh).
    # `commit -n` is --no-verify; the value of -m/-F/-c/-C/-t is message text, not a flag.
    if sub in ("commit", "push", "merge", "am", "cherry-pick", "revert") and "--no-verify" in long_:
        return f"{sub} --no-verify bỏ qua git hook (pre-commit kiểm secret/chất lượng)"
    if sub == "commit":
        prev = ""
        for a in args:
            if (a.startswith("-") and not a.startswith("--") and "n" in a[1:]
                    and prev not in ("-m", "-F", "-c", "-C", "-t", "--message", "--file", "--author", "--date")):
                return "commit -n (--no-verify) bỏ qua pre-commit hook"
            prev = a
    if sub == "worktree" and pos[:1] == ["remove"] and ("f" in short or "--force" in long_):
        return "worktree remove --force mất thay đổi"
    if sub == "worktree" and "lock" in args and any("devkit-kept" in a for a in args):   # (cờ dính liền -r…/-q trước lock: không lệch pos, audit T0044)
        # discard/remove tin khoá này là bằng chứng "worktree của chính phiên" (OCR 18/10): chỉ hook của DevKit được đặt nó
        return "worktree lock devkit-kept giả khoá của phiên (chỉ hook của DevKit đặt khoá này: EnterWorktree, ExitWorktree keep, SessionStart)"
    return None

skip_wrapper = shell_norm.skip_wrapper

def git_danger_from_alias(val):
    """`git -c alias.x=VAL x`: VAL is either `!shell cmd` or git args."""
    if val.startswith("!"):
        return analyse(val[1:], 1)
    try:
        parts = shlex.split(val)
    except ValueError:
        return "alias git không phân tích được"
    if not parts:
        return None
    return danger_in_git(parts[0], parts[1:]) or solo_branch_rule(parts[0], parts[1:], CUR_DIR[0], ALLOW_BRANCH[0])

HOOK_OFF_ENV = re.compile(r"^DEVKIT_PRECOMMIT=0$")

# Git reads config from the environment too (2026-09-28: each of these returned exit 0).
GIT_CONFIG_FILE_ENV = {"GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "GIT_CONFIG"}

# (#605, audit T0066 vòng 2) ANTIGRAVITY_PM_STATE_HOME đổi nơi push_gate / post-fix-gate đọc biên bản audit antigravity-pm: agent tự
# đặt nó trên dòng lệnh là tự viết biên bản duyệt. Chỉ test đặt bên trong script của nó (hook chỉ thấy lệnh ngoài).
# DEVKIT_PM_HOME_TEST: công tắc test-only của push_gate (lane I), cùng luật.
PM_STATE_ENVS = ("ANTIGRAVITY_PM_STATE_HOME", "DEVKIT_PM_HOME_TEST")
PM_STATE_MSG = "biến chỉ dành cho test"
# (audit T0066 vòng 3) HOME= đổi ~ nên đổi luôn ~/.antigravity-pm mà gate đọc: lệnh gate / push / integrate kèm HOME do agent đặt → chặn.
# HOME_SET: HOME đã đặt bền trong dòng lệnh này (export HOME=…, HOME=… đứng riêng) nên mọi lệnh sau đó cũng mang nó.
HOME_SET = [False]
GATE_CMD = re.compile(r"super-board-merge-gate\.sh|super-board-merge-queue\.sh|super-board-audit-check\.py|push_gate\.py"
                      r"|super-board-queue-label\.sh"
                      r"|post-fix-gate\.py|\bagent-kit\s+integrate\b|\bgit\s+(?:(?:-C|-c)\s+\S+\s+|--?[\w-]+(?:=\S+)?\s+)*push\b")

def pm_env_in_code(code):
    """(audit T0066 vòng 3) mã interpreter (-c / -e / heredoc) nhắc tên biến pm: nó tự đặt được os.environ rồi gọi push / gate."""
    for name in PM_STATE_ENVS:
        if name in code:
            return f"{PM_STATE_MSG} {name}: mã interpreter nhắc tới nó thì tự đặt được biến rồi gọi push / gate"
    return None

def env_config_danger(assigns):
    """NAME=VAL assignments (command prefix, env, export) that configure git: GIT_CONFIG_PARAMETERS
    and GIT_CONFIG_KEY_n/VALUE_n pairs go through config_danger; a config FILE named by
    GIT_CONFIG_GLOBAL/SYSTEM cannot be read safely here, so only /dev/null passes."""
    for name in PM_STATE_ENVS:
        if name in assigns:
            return f"{PM_STATE_MSG} {name}: lệnh của agent đặt nó thì biên bản audit đọc từ thư mục agent tự viết"
    for name in GIT_CONFIG_FILE_ENV & set(assigns):
        if assigns[name] != "/dev/null":
            return f"{name} nạp file config ngoài, không kiểm được"
    if "GIT_CONFIG_PARAMETERS" in assigns:
        try:
            items = shlex.split(assigns["GIT_CONFIG_PARAMETERS"])
        except ValueError:
            return "GIT_CONFIG_PARAMETERS không phân tích được"
        for item in items:
            key, eq, val = item.partition("=")
            reason = config_danger(key, val if eq else "true")
            if reason:
                return f"GIT_CONFIG_PARAMETERS {reason}"
    for name, key in assigns.items():
        m = re.fullmatch(r"GIT_CONFIG_KEY_(\d+)", name)
        if not m:
            continue
        if "$" in key or "`" in key:
            return f"{name} lấy từ biến, không kiểm được"
        reason = config_danger(key, assigns.get("GIT_CONFIG_VALUE_" + m.group(1)))
        if reason:
            return f"{name} {reason}"
    return None

# One developer, one branch. A new branch or worktree, and a push of <src>:<dst> that the
# local <dst> does not hold, split the code between local and remote (GeelyEx2, 2026-09-26:
# `git push origin <sha>:main` left local main 2 commits behind origin). Allowed only when
# the user asked for a branch: DEVKIT_ALLOW_BRANCH=1 on the command or in the environment.
ALLOW_BRANCH_ENV = "DEVKIT_ALLOW_BRANCH=1"
ALLOW_BRANCH = [os.environ.get("DEVKIT_ALLOW_BRANCH") == "1"]
_cwd = PAYLOAD.get("cwd") if isinstance(PAYLOAD.get("cwd"), str) else ""
CUR_DIR = [_cwd or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()]  # None once a cd is unknowable
SOLO_HIT = []
BRANCH_LIST_SHORT = set("dDmMlaruv")
BRANCH_LIST_LONG = {"--delete", "--move", "--list", "--all", "--remotes", "--contains", "--no-contains",
                    "--merged", "--no-merged", "--points-at", "--show-current", "--set-upstream-to",
                    "--unset-upstream", "--edit-description", "--format", "--sort", "--column", "--verbose"}
PUSH_OPTS_WITH_ARG = {"-o", "--push-option", "--repo", "--receive-pack", "--exec", "--recurse-submodules"}
LONG_PUSH_ARG_OPTS = ("--push-option", "--repo", "--receive-pack", "--exec", "--recurse-submodules")

def push_arg_option(a):
    """The option when `a` takes its value in the NEXT token (-o X, --repo X, --recurse-submodules mode …): the exact
    name or a UNIQUE abbreviation git accepts (--recurse, --rep). An ambiguous prefix is an error in git: left alone."""
    if a == "-o":
        return a
    if not a.startswith("--") or "=" in a or len(a) < 3:
        return None
    hits = [o for o in LONG_PUSH_ARG_OPTS if o.startswith(a)]
    return hits[0] if len(hits) == 1 else None

def solo_out(gdir, *args):
    """Stdout (stripped) of a read-only git query run in gdir; empty when it cannot run or fails."""
    if not gdir or not os.path.isdir(gdir):
        return ""
    try:
        r = subprocess.run(["git", "-C", gdir, *args], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, ValueError, subprocess.SubprocessError):
        return ""

def default_push_remote(gdir):
    """The remote a push with no remote named goes to: branch.<b>.pushRemote, remote.pushDefault, branch.<b>.remote,
    then origin (the order git uses). The hook used to assume origin (a repo whose remote is called github)."""
    cur = solo_out(gdir, "symbolic-ref", "--short", "-q", "HEAD")
    for key in ((f"branch.{cur}.pushRemote",) if cur else ()) + ("remote.pushDefault",) + ((f"branch.{cur}.remote",) if cur else ()):
        val = solo_out(gdir, "config", "--get", key)
        if val:
            return val
    return "origin"

def solo_git(gdir, *args):
    """Exit code of a read-only git query run in gdir; None when it cannot run."""
    if not gdir or not os.path.isdir(gdir):
        return None
    try:
        return subprocess.run(["git", "-C", gdir, *args], stdin=subprocess.DEVNULL,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5).returncode
    except (OSError, ValueError, subprocess.SubprocessError):
        return None

REDIRECT = shell_norm.REDIRECT

def drop_redirects(args):
    """`2>/dev/null`, `> out.txt`: shell redirections are not git arguments."""
    out, skip = [], False
    for a in args:
        if skip:
            skip = False
        elif REDIRECT.match(a):
            skip = bool(re.fullmatch(r"\d*(>>?|<|&>)", a))
        else:
            out.append(a)
    return out

def solo_branch_rule(sub, args, gdir, allow=False):
    """allow (the user asked for a branch) lifts the new-branch checks, never the push of
    <src>:<dst> that the local <dst> does not hold."""
    args = drop_redirects(args)
    if sub == "push":
        args = expand_abbrev(sub, args)   # git accepts --tag, --al, --b: the checks below must see the full names
    long_ = set(a.split("=", 1)[0] for a in args if a.startswith("--"))
    short = short_flags(args)
    pos = [a for a in args if not a.startswith("-")]
    reason = None
    if allow and sub != "push":
        pass
    elif sub == "checkout" and (short & {"b", "t"} or long_ & {"--track", "--orphan"}):
        reason = "checkout -b tạo nhánh mới"
    elif sub == "switch" and (short & {"c", "t"} or long_ & {"--create", "--orphan", "--track"}):
        reason = "switch -c tạo nhánh mới"
    elif sub == "branch" and pos and not (short & BRANCH_LIST_SHORT or long_ & BRANCH_LIST_LONG):
        reason = f"branch {pos[0]} tạo nhánh mới"
    elif sub == "worktree" and pos[:1] == ["add"]:
        reason = "worktree add tạo worktree + nhánh mới"
    elif sub == "push" and "--mirror" not in long_:
        vals, k, repo_opt = [], 0, None
        while k < len(args):
            a = args[k]
            full = push_arg_option(a)
            if full:
                if full == "--repo" and k + 1 < len(args):
                    repo_opt = args[k + 1]
                k += 2
                continue
            if a.startswith("--repo="):
                repo_opt = a.split("=", 1)[1]
            if not a.startswith("-"):
                vals.append(a)
            k += 1
        specs = vals if repo_opt else vals[1:]      # with --repo every positional is a refspec
        for spec in specs:
            if ":" not in spec or spec.startswith(("+", ":")):
                continue
            src, dst = spec.split(":", 1)
            if dst.startswith("refs/") and not dst.startswith("refs/heads/"):
                continue
            if not dst.startswith("refs/heads/") and solo_git(gdir, "rev-parse", "--verify", "-q", "refs/tags/" + dst) == 0:
                continue
            dst = dst[len("refs/heads/"):] if dst.startswith("refs/heads/") else dst
            has = solo_git(gdir, "rev-parse", "--verify", "-q", "refs/heads/" + dst)
            anc = solo_git(gdir, "merge-base", "--is-ancestor", src, "refs/heads/" + dst) if has == 0 else None
            if has == 1:
                if not allow:
                    reason = f"push {spec} tạo nhánh mới \"{dst}\" trên remote (local không có nhánh này)"
            elif anc == 1:
                reason = f"push {spec}: nhánh local \"{dst}\" chưa chứa {src}, remote sẽ lệch khỏi local"
            elif anc != 0:
                reason = (f"push {spec}: không kiểm được nhánh local \"{dst}\" có chứa {src} không "
                          "(repo/thư mục hoặc nguồn không xác định)")
            if reason:
                break
        if not reason and not ("--dry-run" in long_ or "n" in short):     # a dry run uploads nothing
            forced = bool(short & {"f", "d"} or long_ & {"--force", "--force-with-lease", "--force-if-includes", "--delete", "--prune"})
            reason = push_gate_rule(vals, gdir, forced, bool(long_ & {"--all", "--branches"}), "--tags" in long_, repo_opt)
    if reason:
        SOLO_HIT.append(reason)
    return reason


RETARGETED = [False]   # a --git-dir/--work-tree option or a GIT_DIR-like assignment was seen earlier in this command line
RETARGET_ENV = {"GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"}

def tag_name(spec):
    src = spec.partition(":")[0]
    return src[len("refs/tags/"):] if src.startswith("refs/tags/") else src

def plain_tag_spec(spec, gdir, forced):
    """A refspec that names a LOCAL TAG ref and nothing else: not forced or deleting, no leading + or :, the
    destination is empty or that same refs/tags/ ref (a bare `X:X` can land on a remote BRANCH X), the name is
    not also a branch, and it is a real refs/tags/ entry (show-ref, not rev-parse: ORIG_HEAD, v1~0 resolve)."""
    if forced or RETARGETED[0] or spec.startswith(("+", ":")):
        return False
    name = tag_name(spec)
    if not name or solo_git(gdir, "show-ref", "--verify", "--quiet", "refs/tags/" + name) != 0:
        return False
    if solo_git(gdir, "show-ref", "--verify", "--quiet", "refs/heads/" + name) == 0:
        return False
    return spec.partition(":")[2] in ("", "refs/tags/" + name)

def push_gate_rule(vals, gdir, forced=False, all_branches=False, all_tags=False, repo_opt=None):
    """A push the last full gate PASS does not cover (bin/push_gate.py; audit 2026-09-28: the
    rule "every push needs the gate at exit 0" was enforced nowhere). None when covered. A plain tag
    push of commits the remote already has is covered (push_gate.py --tag-remote; 2026-10-04)."""
    if RETARGETED[0]:
        # --git-dir / --work-tree / GIT_DIR make gdir the wrong repository: the receipt checked is not the one pushed from
        return "push với --git-dir/--work-tree/GIT_DIR: hook không biết repo nào gửi đi — đẩy riêng và dùng git -C <thư mục>"
    # 18/10 (người dùng): đích là nhánh PR thì push_gate.py không đòi biên nhận --full (merge gate chạy --full một lần trước khi gộp
    # vào trunk); hook truyền `--dst <remote> <nhánh>` chỉ khi biết chắc đích, mọi nghi ngờ → không truyền → luật biên nhận cũ.
    to = repo_opt or (vals[0] if vals else default_push_remote(gdir))   # cùng remote như `remote` bên dưới
    # Config hook đọc lúc này phải là config git dùng lúc push: lối tắt chỉ cho MỘT lệnh git push trơn (cho phép `cd <đường dẫn> &&`
    # phía trước) — không gán biến (HOME=, GIT_CONFIG_*), không ; & | < > $ ` ( ) quote, \ hay `=` (--repo=, -c k=v): không gì trong cùng
    # lệnh đổi được config hay đích (review 18/10: `.git/con` + hai dấu nháy + `fig`, `HOME=… git push`, `-c push.default=upstream` đều lọt cách dò chữ).
    # Ngoài ra luật cũ khi: `-c`, --follow-tags / push.followTags (tag đi kèm), --repo kèm remote vị trí, remote.<remote>.push/.mirror.
    # [ \t], không \s: xuống dòng là dấu tách lệnh (OCR 18/10: `git config …\ngit push` thành "một lệnh"). \x27 \x22: nháy (file bọc nháy đơn)
    plain = re.sub(r"^[ \t]*cd[ \t]+[^\s;&|<>$`()\x27\x22\\]+[ \t]*&&[ \t]*", "", cmd).strip(" \t")
    mapped = (re.fullmatch(r"git([ \t]+[^\s;&|<>$`()\x27\x22\\=]+)+", plain) is None or re.search(r"(?<!\S)-c(?!\S)", plain) is not None
              or re.search(r"(?<!\S)--fol", plain) is not None or bool(repo_opt and vals)
              or bool(solo_out(gdir, "config", "--get-all", f"remote.{to}.push"))
              or (solo_git(gdir, "config", "--get", f"remote.{to}.mirror") != 1      # có khoá (yes/on/1/khoá trần) hay đọc lỗi
                  and solo_out(gdir, "config", "--bool", "--get", f"remote.{to}.mirror") != "false")
              or solo_out(gdir, "config", "--bool", "--get", "push.followTags") == "true")
    # push.default upstream/tracking ánh xạ cả `git push origin <nhánh>` sang branch.<b>.merge (có thể là main): chỉ simple/current
    implicit_ok = (solo_out(gdir, "config", "--get", "push.default") or "simple") in ("simple", "current")

    def src_branch(src):
        """True khi src là một nhánh local (HEAD trỏ vào nhánh, hoặc refs/heads/<tên> có thật) và không trùng tên tag local."""
        if src == "HEAD":
            return solo_out(gdir, "symbolic-ref", "-q", "HEAD").startswith("refs/heads/")
        name = src[len("refs/heads/"):] if src.startswith("refs/heads/") else src
        return (solo_git(gdir, "show-ref", "--verify", "--quiet", "refs/heads/" + name) == 0
                and (src.startswith("refs/heads/") or solo_git(gdir, "show-ref", "--verify", "--quiet", "refs/tags/" + name) == 1))

    def remote_short_is_branch(dst):
        """Đích ngắn `a:b`: git ghi vào ref tên b mà REMOTE đã có (refs/tags/b chưa fetch về cũng vậy), chưa có thì theo namespace
        của nguồn (OCR 18/10: `v4:feat/x` tạo refs/tags/feat/x). True chỉ khi remote không có ref nào khác refs/heads/b khớp tên b;
        không hỏi được remote → False."""
        try:
            r = subprocess.run(["git", "-C", gdir, "ls-remote", "--refs", to, dst], stdin=subprocess.DEVNULL, capture_output=True,
                               text=True, timeout=10, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
        except (OSError, ValueError, subprocess.SubprocessError):
            return False
        if r.returncode != 0:
            return False
        names = {ln.split("\t", 1)[1] for ln in r.stdout.splitlines() if "\t" in ln}
        dwim = {dst, "refs/" + dst, "refs/tags/" + dst, "refs/heads/" + dst, "refs/remotes/" + dst, f"refs/remotes/{dst}/HEAD"}
        return (names & dwim) <= {"refs/heads/" + dst}

    def push_dst(spec, src):
        """`a:b` → b (refs/heads/b → b; ref khác refs/heads/, b trùng tên tag local hay trên remote, nguồn không phải nhánh → None);
        không có `:` (chỉ push.default simple/current): `HEAD` → nhánh hiện tại, `<nhánh local>` → chính nó; `mapped` → None."""
        spec = spec.lstrip("+")
        if mapped:
            return None
        if ":" in spec:
            dst = spec.split(":", 1)[1]
            if dst.startswith("refs/heads/"):
                return dst[len("refs/heads/"):] or None
            if (not dst or dst.startswith("refs/") or solo_git(gdir, "show-ref", "--verify", "--quiet", "refs/tags/" + dst) != 1
                    or not src_branch(src) or not remote_short_is_branch(dst)):
                return None
            return dst
        if not implicit_ok:
            return None
        if src == "HEAD":
            return solo_out(gdir, "symbolic-ref", "--short", "-q", "HEAD") or None
        if not src_branch(src):
            return None
        return src[len("refs/heads/"):] if src.startswith("refs/heads/") else src

    def default_push_dst():
        """Push không refspec: push.default simple/current → nhánh hiện tại; upstream, matching, …, detached, `mapped` → None."""
        cur = solo_out(gdir, "symbolic-ref", "--short", "-q", "HEAD")
        return cur if cur and implicit_ok and not mapped else None

    revs = []   # (rev, is a plain tag push, destination branch or None) per refspec (one push may name several); none → HEAD
    unresolved = False
    specs_named = bool(vals if repo_opt else vals[1:])
    for spec in (vals if repo_opt else vals[1:]):
        s = spec.lstrip("+").split(":", 1)[0]
        if not s:
            continue                            # :ref deletes are refused by the danger rule
        if re.search(r"[*?\[]", s):            # a glob names many refs: only the two whole-namespace globs map to a sweep
            if s == "refs/heads/*":
                all_branches = True
            elif s == "refs/tags/*":
                all_tags = True
            else:
                return f"push {spec}: refspec có ký tự đại diện, không kiểm được những ref nào sẽ đi"
            continue
        if solo_git(gdir, "rev-parse", "--verify", "-q", s + "^{commit}") != 0:
            if solo_git(gdir, "rev-parse", "--verify", "-q", s) == 0:
                # an object that is not a commit (a tree, a blob): its content would ride along unchecked
                return f"push {spec}: không phải commit (tree/blob), không kiểm được nội dung sắp đẩy"
            unresolved = True   # a name nobody here can resolve (a $b, a $(…) placeholder, a typo): what git sends is unknown,
            continue            # so no tag shortcut anywhere (review round 2: v1 plus an unknown name sent main ungated)
        is_tag = plain_tag_spec(spec, gdir, forced)
        revs.append(("refs/tags/" + tag_name(spec) if is_tag else s, is_tag,   # the full ref: never a pseudoref
                     None if is_tag else push_dst(spec, s)))
    if unresolved:
        revs = [(r, False, None) for r, _, _ in revs]   # một tên không ai giải được: không biết nó đi đâu → mọi refspec theo luật cũ
    # --repo=<name> names it; otherwise the first positional; otherwise the default remote git would use
    remote = repo_opt or (vals[0] if vals else default_push_remote(gdir))
    sweeps = ([["--all-branches", remote]] if all_branches else []) + ([["--all-tags", remote]] if all_tags else [])
    if not revs and not sweeps:
        revs = [("HEAD", False, None if (unresolved or specs_named) else default_push_dst())]
    here = os.path.dirname(os.path.realpath(sys.argv[1])) if len(sys.argv) > 1 else ""
    tool = os.path.join(os.path.dirname(here), "bin", "push_gate.py")
    if not gdir or not os.path.isdir(gdir) or not os.path.isfile(tool):
        return "push: không kiểm được biên nhận gate (thư mục repo hoặc bin/push_gate.py không xác định)"
    # #472 mục A: --via-hook trên MỌI lần gọi — push của agent đi qua hook dùng luật chặt (trunk chỉ qua agent-kit integrate);
    # integrate tự gọi push_gate không có cờ này (tiến trình con của nó, hook không thấy)
    jobs = [[rev] + (["--tag-remote", remote] if is_tag else []) + (["--dst", remote, dst] if dst else []) + ["--via-hook", remote]
            for rev, is_tag, dst in revs] + [s + ["--via-hook", remote] for s in sweeps]
    for job in jobs:
        try:
            r = subprocess.run([sys.executable, tool, gdir] + job, stdin=subprocess.DEVNULL,
                               capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError) as e:
            return f"push: không kiểm được biên nhận gate ({e})"
        if r.returncode != 0:
            # (#472 A: không còn "chưa qua gate" — lời đó đẩy agent chạy lại gate, vòng lặp cũ; lý do và lối ra là của push_gate)
            return f"push {job[0]} bị từ chối: " + ((r.stdout or r.stderr).strip() or f"push_gate exit {r.returncode}")
    return None

RESTORE_FLAGS = {"--worktree", "-W", "--staged", "-S", "--quiet", "-q", "--progress", "--no-progress"}
PENDING_BACKUPS = []   # files to copy once the WHOLE command is allowed
CHANGES_DIR = []       # a cd/pushd anywhere makes relative paths unknowable here

def backup_then_allow_restore(args):
    """`git restore <file>...` naming existing regular files is how an agent undoes its
    own bad edit. It is allowed once the current content is copied to
    .claude/audit-gate/restore-backup/<time>/ — so it can never cost the owner
    uncommitted work. Directories, `.`, globs, pathspec magic and unknown options
    keep being blocked."""
    paths, i = [], 0
    while i < len(args):
        a = args[i]
        if a == "--":
            paths += args[i + 1:]
            break
        if a.startswith("--source="):
            i += 1
        elif a in ("--source", "-s"):
            i += 2
        elif a in RESTORE_FLAGS:
            i += 1
        elif a.startswith("-"):
            return False
        else:
            paths.append(a)
            i += 1
    if not paths or CHANGES_DIR:
        return False
    root = backup_root()
    if not root:
        return False   # no project to keep the backup in: the restore stays blocked
    for p in paths:
        if p in (".", "./") or any(c in p for c in "*?[:") or not os.path.isfile(p) or os.path.islink(p):
            return False
        if not os.path.realpath(p).startswith(root + os.sep):
            return False
    PENDING_BACKUPS.extend(os.path.realpath(p) for p in paths)
    return True

def backup_root():
    """The project the restore backup goes into (2026-10-09): CLAUDE_PROJECT_DIR, else the git tree of the payload cwd (the
    process cwd without one); None outside a git tree — the backup made .claude/audit-gate/ in a non-git cwd."""
    if os.environ.get("CLAUDE_PROJECT_DIR"):
        return os.path.realpath(os.environ["CLAUDE_PROJECT_DIR"])
    try:
        r = subprocess.run(["git", "-C", _cwd or ".", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None

def do_backups():
    """Copy the files a restore will overwrite — only after the whole command passed."""
    if not PENDING_BACKUPS:
        return True
    root = backup_root()
    audit = os.path.join(root, ".claude", "audit-gate")
    dest = os.path.join(audit, "restore-backup", time.strftime("%Y%m%d-%H%M%S"))
    try:
        for p in PENDING_BACKUPS:
            rel = os.path.relpath(p, root)
            os.makedirs(os.path.dirname(os.path.join(dest, rel)), exist_ok=True)
            shutil.copy2(p, os.path.join(dest, rel))
        if not os.path.exists(os.path.join(audit, ".gitignore")):
            with open(os.path.join(audit, ".gitignore"), "w") as fh:
                fh.write("*\n")
    except OSError:
        return False
    return True

STR_LITERAL = re.compile(r"\x22((?:[^\x22\\]|\\.)*)\x22|\x27((?:[^\x27\\]|\\.)*)\x27|`((?:[^`\\]|\\.)*)`")

def git_in_literals(code, allow=None):
    """python -c / node -e source: its string literals, split into words, as git would get them
    ([\x27git\x27,\x27push\x27,\x27--force\x27] or \x27git reset --har HEAD\x27). The word after `git` and its
    global options is the subcommand; the words after it go through danger_in_git (abbreviations
    included). Issue #8: checkout / switch / worktree also go through solo_branch_rule, so a script is no way round the
    one-branch rule (allow: the DEVKIT_ALLOW_BRANCH of the command, default the exported one). The words of ALL literals are one list, so
    only the flag-shaped rules run on it: `branch NAME` and the checkout path rule read positional words and would take the next literal for an operand.
    ponytail: no positional rules on a script, a script that only `git branch NAME`s passes, until the words are split per call."""
    allow = ALLOW_BRANCH[0] if allow is None else allow
    words = []
    for m in STR_LITERAL.finditer(code):
        words += next((g for g in m.groups() if g is not None), "").split()
    for k, w in enumerate(words):
        if w.rsplit("/", 1)[-1].lower() != "git":
            continue
        j = k + 1
        while j < len(words) and words[j].startswith("-"):
            j += 2 if (words[j] in GIT_OPTS_WITH_ARG and "=" not in words[j]) else 1
        if j < len(words):
            reason = danger_in_git(words[j], words[j + 1:])
            if not reason and words[j] in ("checkout", "switch", "worktree"):
                first = next((x for x in range(j + 1, len(words)) if not words[x].startswith("-")), len(words) - 1)
                nxt = next((x for x in range(first + 1, len(words)) if not words[x].startswith("-")), len(words))
                reason = solo_branch_rule(words[j], words[j + 1:nxt], CUR_DIR[0], allow)   # the flags and the first operand of THIS call, not the later literals of the script
            if reason:
                return reason
    return None

def inline_codes(rest):
    """Every word an interpreter may take as a script (issue #8), read fail closed: a flag word whose last letter takes the script (-c -e -E -p -r: the next
    word), a letter c / e inside a cluster with the script glued behind it (-cCODE, -Ic CODE), --eval=CODE / --print=CODE and --eval / --print CODE.
    No flag table: a word that is not a script (python -Wonce, perl -Isrc) is only scanned for git, and the scan goes on to the real -c / -e after it."""
    out = []
    for j, a in enumerate(rest):
        nxt = rest[j + 1:j + 2]
        if a.startswith("--"):
            if a.split("=", 1)[0] in ("--eval", "--print"):
                out += [a.split("=", 1)[1]] if "=" in a else nxt
        elif a.startswith("-") and len(a) > 1:
            if a[-1] in "ceEpr":
                out += nxt
            k = next((k for k in range(1, len(a) - 1) if a[k] in "ce"), 0)   # the first c / e: every later suffix is inside this one (linear, not quadratic)
            out += [a[k + 1:]] if k else []
    return out

# (2026-10-28, #605) Luật chủ repo: DevKit tự động hoàn toàn, chỉ hỏi người khi xoá file QUAN TRỌNG (cùng force push và xoá ref
# trên remote, đã chặn ở danger_in_git). Danh sách = mặc định dưới đây + khoá "protected_delete" (list glob) trong
# <git toplevel>/.antigravity-pm.json; config hỏng/thiếu thì vẫn dùng mặc định. Glob không có "/" khớp tên file ở mọi cấp; glob có
# "/" khớp đường dẫn tính từ git toplevel của file (worktree lồng trong project có gốc riêng); "X/**" = X và mọi thứ bên trong.
# Xoá một thư mục cha của path được bảo vệ (rm -rf .agents, rm -rf .) cũng bị chặn. Xoá file thường không bị hỏi gì thêm.
# (#605 Lane H) rm -r <thư mục có thật> quét nông bên trong (_pd_walk: sâu 3, tối đa 2000 mục, vượt trần thì chặn), và
# python -c / node -e / perl -e / ruby -e có lời gọi xoá với path literal được bảo vệ cũng bị chặn (interp_delete_rule).
# ponytail: toán hạng chứa $VAR / $( ) không biết trước giá trị nên cho qua; script interpreter đọc từ heredoc / file và path
# tính lúc chạy (os.path.join, biến) không được xét; node_modules không được quét bên trong. Nâng cấp khi một ca thật lọt qua.
# tests/gates/test_guard_protected_delete.sh
PROTECTED_DELETE_DEFAULT = (".env*", "*.keystore", "*.jks", "google-services.json",
                            ".agents/regression_matrix.active.json", ".agents/local/memory/**",
                            ".agents/local/rules/**", ".git/**", ".claude/bin/super-board-queue-label.sh")   # #605: stage/handoff trong .agents/local tự dọn được
PROTECTED_DELETE_MSG = "xoá file quan trọng"
_PD_TOP, _PD_PATS = {}, {}

def _pd_toplevel(d):
    if d not in _PD_TOP:
        _PD_TOP[d] = solo_out(d, "rev-parse", "--show-toplevel") or None
    return _PD_TOP[d]

def protected_delete_patterns(root):
    """Mặc định + "protected_delete" của <root>/.antigravity-pm.json (chỉ cộng thêm, không bỏ được mặc định)."""
    if root not in _PD_PATS:
        pats = list(PROTECTED_DELETE_DEFAULT)
        try:
            with open(os.path.join(root, ".antigravity-pm.json"), encoding="utf-8") as f:
                extra = json.load(f).get("protected_delete")
            if isinstance(extra, list):
                pats += [p.strip()[2:] if p.strip().startswith("./") else p.strip() for p in extra if isinstance(p, str) and p.strip()]
        except (OSError, ValueError, AttributeError, TypeError):
            pass   # config hỏng/thiếu: vẫn bảo vệ bằng danh sách mặc định, không bao giờ cho qua hết
        _PD_PATS[root] = pats
    return _PD_PATS[root]

def _pd_locate(word, base):
    """(root, rel) của toán hạng xoá: root = git toplevel chứa nó (hoặc CLAUDE_PROJECT_DIR), rel tính từ root; None ngoài mọi repo."""
    p = os.path.expanduser(word)
    if not os.path.isabs(p):
        if not base:
            return None
        p = os.path.join(base, p)
    p = os.path.normpath(p)
    parent = os.path.dirname(p)
    while parent and parent != os.sep and not os.path.isdir(parent):
        parent = os.path.dirname(parent)
    real = os.path.normpath(os.path.join(os.path.realpath(parent or os.sep), os.path.relpath(p, parent or os.sep)))
    top = _pd_toplevel(parent) if parent else None
    if not top and os.path.isdir(p):
        top = _pd_toplevel(p)   # rm -rf . ở gốc repo: thư mục cha không thuộc repo nào
    roots = [r for r in (top, os.environ.get("CLAUDE_PROJECT_DIR")) if r]
    for r in roots:
        r = os.path.realpath(r)
        if real == r or real.startswith(r.rstrip(os.sep) + os.sep):
            return r, os.path.relpath(real, r).replace(os.sep, "/")
    return None

def _pd_match(rel, pats, names=(), paths=(), start=""):
    """Glob bảo vệ mà xoá rel đụng tới (rel là chính nó, nằm trong, hoặc là thư mục cha của path bảo vệ).
    find: names = giá trị -name/-iname, paths = -path/-ipath/-wholename, start = điểm bắt đầu như đã gõ; có bộ lọc thì
    thư mục cha chỉ bị chặn khi bộ lọc có thể khớp path bảo vệ (find . -name "*.log" -delete vẫn qua)."""
    base = rel.rsplit("/", 1)[-1]
    globby = re.search(r"[*?\[]", rel)
    leaf = [q.rsplit("/", 1)[-1] for q in paths]   # -path: chỉ chiều thuận (-path "./build/*" không chặn vì "*" khớp mọi tên)
    for p in pats:
        if "/" not in p:
            if _fnm(base, p) or any(_fnm(n, p) or _fnm(p, n) for n in names) or any(_fnm(n, p) for n in leaf):
                return p
            continue
        lit = p[:-3] if p.endswith("/**") else p
        if p.endswith("/**") and (rel == lit or rel.startswith(lit + "/")):
            return p
        if _fnm(rel, p):
            return p
        comps = lit.split("/")
        ancestor = rel == "." or lit.startswith(rel + "/") or (globby and any(_fnm("/".join(comps[:k]), rel) for k in range(1, len(comps) + 1)))
        if not ancestor:
            continue
        if not names and not paths:
            return p
        inner = [c for c in comps[len(rel.split("/")) if rel != "." else 0:]] or comps
        under = [os.path.join(start.rstrip("/") or ".", *inner[:k]) for k in range(1, len(inner) + 1)]
        under += [under[-1] + "/x"]   # một file bên trong path bảo vệ: -path "./.git/*"
        if any(_fnm(c, n) for c in comps for n in names) or any(_fnm(u, q) for u in under for q in paths):
            return p
    return None

PD_WALK_DEPTH, PD_WALK_MAX = 8, 2000   # (audit T0066 vòng 2) android/app/src/debug/google-services.json nằm ở cấp 4
PD_WALK_SKIP = {".git", "node_modules"}   # không đi vào bên trong (.git chỉ tính chính nó ở cấp 1; node_modules: cây sinh lại được)

def _pd_walk(root, rel, pats):
    """(#605 Lane H) rm -r <thư mục có thật>: quét nông (sâu PD_WALK_DEPTH, tối đa PD_WALK_MAX mục, không theo symlink).
    Trả glob bảo vệ khớp một mục bên trong, chuỗi lý do khi vượt trần / không đọc được (chặn, fail closed), hoặc None."""
    start = os.path.join(root, rel)
    if rel == "." or os.path.islink(start) or not os.path.isdir(start) or rel.rsplit("/", 1)[-1] in PD_WALK_SKIP:
        return None
    seen, stack = 0, [(start, rel, 0)]
    while stack:
        d, r, depth = stack.pop()
        try:
            with os.scandir(d) as it:
                entries = list(it)
        except OSError as e:
            return ("", f"không đọc được thư mục {r} để kiểm ({e.__class__.__name__})")
        for e in entries:
            seen += 1
            if seen > PD_WALK_MAX:
                return ("", f"thư mục có hơn {PD_WALK_MAX} mục trong {PD_WALK_DEPTH} cấp, không kiểm hết được")
            erel = r + "/" + e.name
            pat = _pd_match(erel, pats)
            if pat:
                return (pat, erel)
            try:
                sub = e.is_dir(follow_symlinks=False)
            except OSError:
                sub = False
            if sub and e.name not in PD_WALK_SKIP:
                if depth + 1 >= PD_WALK_DEPTH:   # còn thư mục ở trần độ sâu: không kiểm hết được, chặn (fail closed)
                    return ("", f"thư mục sâu hơn {PD_WALK_DEPTH} cấp ({erel}), không kiểm hết được")
                stack.append((e.path, erel, depth + 1))
    return None

def protected_delete_rule(words, base, names=(), paths=(), walk=False):
    """Lý do chặn khi một toán hạng xoá đụng file quan trọng; names/paths: bộ lọc -name / -path của find.
    walk (rm -r, interpreter xoá): toán hạng là thư mục có thật thì quét nông bên trong (_pd_walk)."""
    for w in words:
        if "$" in w or SUBST in w or "`" in w:
            continue   # giá trị chỉ biết lúc chạy
        loc = _pd_locate(w, base)
        if not loc:
            continue
        pats = protected_delete_patterns(loc[0])
        pat = _pd_match(loc[1], pats, names, paths, w)
        if pat:
            return f"{PROTECTED_DELETE_MSG} {w} (khớp \"{pat}\" trong danh sách protected_delete)"
        found = _pd_walk(loc[0], loc[1], pats) if walk and not re.search(r"[*?\[]", w) else None
        if found and found[0]:
            return f"{PROTECTED_DELETE_MSG} {w}: bên trong có {found[1]} (khớp \"{found[0]}\" trong danh sách protected_delete)"
        if found:
            return f"{PROTECTED_DELETE_MSG} {w}: {found[1]} (chặn để an toàn)"
    return None

# (#605 Lane H) python -c / node -e / perl -e / ruby -e có lời gọi xoá: mọi chuỗi literal trong code được xét như toán hạng xoá
# (os.remove("x"), Path("x").unlink(), shutil.rmtree("x"), fs.unlinkSync("x"), unlink("x"), FileUtils.rm_rf("x") …).
INTERP_DELETE = re.compile(r"\b(?:remove|removedirs|unlink|unlinkSync|rmSync|rmdirSync|rmtree|rmdir|rm_rf|rm_r|rm|delete)\b")
STR_LIT = re.compile(r"\"((?:[^\"\\\n]|\\.)*)\"|\x27((?:[^\x27\\\n]|\\.)*)\x27")

def interp_delete_rule(code, base):
    if not INTERP_DELETE.search(code):
        return None
    lits = [a or b for a, b in STR_LIT.findall(code)]
    return protected_delete_rule([x for x in lits if x.strip()], base, walk=True)

# (#605 Lane H) Agent đăng comment GitHub bằng chung tài khoản OWNER, nên `approved-head:<sha>` trơn (không kèm `approved-by:`)
# hay một dòng `done` do agent đăng sẽ tự duyệt chính nó (super-board-approved-head.jq, super-board-approval.py). Chỉ người chủ repo
# gõ tay hai thứ đó. gh pr comment / gh issue comment / gh api …/comments: body qua --body, -b, --body-file, -F (file), -f/-F body=,
# --input. approved-head kèm approved-by: và cross-review-approved: vẫn qua (việc của lane reviewer).
# ponytail: body do $(lệnh) sinh ra (không phải heredoc) không đọc được nên cho qua; nâng cấp khi một ca thật lọt qua.
# tests/gates/test_guard_self_approval_comment.sh
SELF_APPROVE_MSG = "agent tự đăng duyệt"
GH_BARE_HEAD = re.compile(r"(?m)^[ \t]*approved-head:[ \t]*[0-9a-f]{40}")
GH_APPROVED_BY = re.compile(r"(?m)^[ \t]*approved-by:")
GH_DONE = re.compile(r"(?mi)^[ \t]*done[.!]?[ \t\r]*$")
GH_BODY_MAX = 1 << 20

def _gh_file(path, base):
    """Nội dung file body (--body-file, @file, --input); None = không đọc được (chặn, fail closed)."""
    if not path or "$" in path or SUBST in path or "`" in path:
        return None
    p = os.path.expanduser(path)
    if not os.path.isabs(p):
        if not base:
            return None
        p = os.path.join(base, p)
    try:
        if not os.path.isfile(p) or os.path.getsize(p) >= GH_BODY_MAX:
            return None
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None

def _gh_stdin_texts():
    """Body đọc từ stdin: các heredoc của lệnh gốc; rỗng = không biết nội dung."""
    try:
        return [h.body(cmd) for h in shell_norm.heredocs(cmd)]
    except Exception:
        return []

def self_approval_text(text):
    if GH_BARE_HEAD.search(text) and not GH_APPROVED_BY.search(text):
        return "dòng approved-head:<sha> không kèm approved-by:"
    if GH_DONE.search(text):
        return "dòng done"
    return None

GH_GLOBAL_ARG = ("-R", "--repo", "-H", "--hostname")   # cờ có tham số đứng trước/sau pr|issue|api (-H của gh api là --header, cũng có tham số)
GH_COMMENT_MUTATION = re.compile(r"\b(?:add|update)\w*Comment\b|\baddPullRequestReview\b")
GH_GQL_BODY = re.compile(r"\bbody\s*:\s*\x22((?:[^\x22\\]|\\.)*)\x22")
GH_GQL_BLOCK = re.compile(r"\bbody\s*:\s*\x22\x22\x22(.*?)\x22\x22\x22", re.S)   # (audit T0066 vòng 3) chuỗi khối GraphQL, nhiều dòng
GH_FIELD_OPTS = ("-f", "--raw-field", "-F", "--field")

def _gh_strip_globals(rest):
    """(audit T0066 vòng 2) bỏ -R/--repo/-H/--hostname cùng giá trị của chúng (tách rời, =, dính liền -Ro/r) ở mọi vị trí."""
    out, k = [], 0
    while k < len(rest):
        a = rest[k]
        if a in GH_GLOBAL_ARG:
            k += 2
            continue
        if (a.startswith(("--repo=", "--hostname=")) or (a[:2] in ("-R", "-H") and len(a) > 2)):
            k += 1
            continue
        out.append(a)
        k += 1
    return out

def _unknowable(v):
    return "$" in v or SUBST in v or "`" in v

def _gh_field_text(opt, v, base):
    """Giá trị một field -f/-F (name=value đã bỏ name): (text, None) hoặc (None, lý do không đọc được)."""
    if opt in ("-F", "--field") and v.startswith("@"):
        if v == "@-":
            texts = _gh_stdin_texts()
            return ("\n".join(texts), None) if texts else (None, "đọc từ stdin không phải heredoc")
        t = _gh_file(v[1:], base)
        return (t, None) if t is not None else (None, f"không đọc được file {v[1:]}")
    return (v, None)

def _gh_graphql_rule(fields, input_src, base):
    """gh api graphql: mutation đăng/sửa comment (addComment, addPullRequestReviewComment …) → xét body literal trong query và
    mọi field khác (body:$b với -f b=…). Query / field không đọc được khi đó là mutation comment → chặn (fail closed)."""
    query, others = None, []
    for opt, nv in fields:
        name, eq, v = nv.partition("=")
        if not eq:
            continue
        text, why = _gh_field_text(opt, v, base)
        if name == "query":
            if text is None:
                return f"{SELF_APPROVE_MSG}: query graphql {why}, không kiểm được nội dung"
            query = text
        else:
            others.append((name, text, why))
    if input_src is not None:
        t = (("\n".join(_gh_stdin_texts()) or None) if input_src == "-" else _gh_file(input_src, base))
        if t is None:
            return f"{SELF_APPROVE_MSG}: không đọc được --input của gh api graphql"
        try:
            o = json.loads(t)
        except ValueError:
            o = None
        if isinstance(o, dict):
            if isinstance(o.get("query"), str):
                query = o["query"]
            for name, val in (o.get("variables") or {}).items() if isinstance(o.get("variables"), dict) else ():
                others.append((name, val if isinstance(val, str) else json.dumps(val), None))
        else:
            query = t
    if query is None:
        return None
    if re.fullmatch(r"\s*\$\{?\w+\}?\s*", query) or SUBST in query or "`" in query:
        return f"{SELF_APPROVE_MSG}: query graphql chỉ biết lúc chạy, không kiểm được nội dung"
    if not GH_COMMENT_MUTATION.search(query):
        return None
    texts = GH_GQL_BLOCK.findall(query)
    for lit in GH_GQL_BODY.findall(GH_GQL_BLOCK.sub("", query)):
        try:
            texts.append(json.loads("\x22" + lit + "\x22"))
        except ValueError:
            texts.append(lit.replace("\\n", "\n"))
    for name, text, why in others:
        if text is None:
            return f"{SELF_APPROVE_MSG}: field {name} của mutation comment {why}, không kiểm được nội dung"
        if _unknowable(text):
            return f"{SELF_APPROVE_MSG}: field {name} của mutation comment chỉ biết lúc chạy, không kiểm được nội dung"
        texts.append(text)
    names = {n for n, _, _ in others}
    plain = GH_GQL_BLOCK.sub("", query)   # body: phải là chuỗi literal hoặc $biến có giá trị trong field / --input
    for m in re.finditer(r"\bbody\s*:\s*(\$?)(\w*)", plain):
        if (m.group(1) and m.group(2) not in names) or (not m.group(1) and (m.group(2) or plain[m.end():m.end() + 1] != "\x22")):
            return f"{SELF_APPROVE_MSG}: body của mutation comment graphql không trích được, không kiểm được nội dung"
    if not texts:   # (audit T0066 vòng 3) mutation comment mà không trích được body nào: không kiểm được → chặn (fail closed)
        return f"{SELF_APPROVE_MSG}: mutation comment graphql không trích được body, không kiểm được nội dung"
    for t in texts:
        why = self_approval_text(t)
        if why:
            return f"{SELF_APPROVE_MSG}: comment có {why}"
    return None

def _gh_graphql_endpoint(x):
    """(audit T0066 vòng 3) `graphql`, `/graphql`, `graphql/`, `https://api.github.com/graphql` đều là endpoint GraphQL."""
    x = x.rstrip("/")
    return x == "graphql" or x.endswith("/graphql")

def gh_comment_rule(rest, base):
    """Lý do chặn khi lệnh gh đăng comment tự duyệt; None khi không phải đăng comment hoặc body sạch."""
    rest = _gh_strip_globals(drop_redirects(rest))
    j = 0
    while j < len(rest) and rest[j].startswith("-"):
        j += 1
    sub, args = rest[j:j + 2], rest[j + 2:]
    api = sub[:1] == ["api"]
    if api:
        args = rest[j + 1:]
    elif sub not in (["pr", "comment"], ["issue", "comment"]):
        return None
    bodies, fields, input_src = [], [], None   # bodies: (literal | file | stdin | json, value); fields: (opt, name=value) của gh api
    k = 0
    while k < len(args):
        a, nxt = args[k], (args[k + 1] if k + 1 < len(args) else None)
        opt, eq, val = a.partition("=")
        has = bool(eq) and a.startswith("--")
        short = not a.startswith("--") and len(a) > 2 and a[:2] in ("-b", "-F", "-f")   # cờ ngắn dính giá trị: -bdone, -Fbare.md
        step = 1
        if not api and (opt in ("--body", "-b") or (short and a[:2] == "-b")):
            bodies.append(("literal", a[2:] if short else val if has else (nxt or "")))
            step = 1 if (short or has) else 2
        elif not api and (opt in ("--body-file", "-F") or (short and a[:2] == "-F")):
            v = a[2:] if short else val if has else nxt
            bodies.append(("stdin" if v == "-" else "file", v))
            step = 1 if (short or has) else 2
        elif api and (a in GH_FIELD_OPTS or (has and opt in ("--raw-field", "--field")) or short):
            o = a[:2] if short else opt
            v = a[2:] if short else val if has else nxt
            if v is not None:
                fields.append((o, v))
            step = 1 if (short or has) else 2
        elif api and opt == "--input":
            input_src = val if has else nxt
            step = 1 if has else 2
        k += step
    if api:
        pos = [x for x in args if not x.startswith("-")]
        if any(_gh_graphql_endpoint(x) for x in pos):
            # pos còn chứa giá trị cờ (-f x=a/graphql): xét graphql rồi VẪN xét nhánh REST …/comments bên dưới
            reason = _gh_graphql_rule(fields, input_src, base)
            if reason:
                return reason
        if not any(re.search(r"(^|/)comments(/|$|\?)", x) for x in pos):
            return None
        for o, nv in fields:
            if nv.startswith("body="):
                v = nv[5:]
                if o in ("-F", "--field") and v.startswith("@"):
                    bodies.append(("stdin" if v == "@-" else "file", v[1:]))
                else:
                    bodies.append(("literal", v))
        if input_src is not None:
            bodies.append(("stdin" if input_src == "-" else "json", input_src))
    for kind, v in bodies:
        texts = []
        if kind == "literal":
            texts = [v] + (_gh_stdin_texts() if _unknowable(v) else [])
        elif kind == "stdin":
            texts = _gh_stdin_texts()
            if not texts:
                return f"{SELF_APPROVE_MSG}: body đọc từ stdin không phải heredoc, không kiểm được nội dung"
        else:
            t = _gh_file(v, base)
            if t is None:
                return f"{SELF_APPROVE_MSG}: không đọc được file body {v} (thiếu, quá 1 MB hoặc đường dẫn chỉ biết lúc chạy)"
            if kind == "json":
                try:
                    o = json.loads(t)
                    t = o.get("body") if isinstance(o, dict) and isinstance(o.get("body"), str) else t
                except ValueError:
                    pass   # không phải JSON: xét nguyên văn
            texts = [t]
        for t in texts:
            why = self_approval_text(t)
            if why:
                return f"{SELF_APPROVE_MSG}: comment có {why}"
    return None

# (#536) Nhãn `merge-queue` chỉ gắn cho PR đã có `approved-head:<sha40>` hợp lệ khớp head hiện tại: 28/10 một phiên agent tự gắn nhãn
# cho PR #517/#524 chưa duyệt, hàng đợi chỉ phát hiện lúc chạy và PR nằm im ~3 giờ. Luật duyệt không viết lại ở đây: guard hỏi helper
# của super-board (`.claude/bin/super-board-queue-label.sh --check <pr>`, dùng chung super-board-approved-head.jq với hàng đợi).
# Helper lấy theo project của phiên (CLAUDE_PROJECT_DIR, không có thì git toplevel của cwd payload), KHÔNG theo `cd` trong lệnh; project
# là linked worktree mà checkout chính có helper thì dùng bản của checkout chính (trunk mode khoá nó, worktree thì agent sửa được).
# `gh pr create|new … --label merge-queue` chặn luôn (PR mới chưa thể có approved-head); thiếu số PR (PR của nhánh hiện tại, số chỉ biết lúc
# chạy, xargs, biến trong script) cũng chặn: guard không biết PR nào sẽ bị gắn nhãn. Helper exit khác 0 / treo / lỗi → chặn.
# ponytail: project chưa có helper (repo app còn bản super-board cũ, hook là symlink tới kit này) thì luật không chạy — chặn ở đó làm
# lane Review của app đứng trước khi đồng bộ; nâng khi super-board-queue-label.sh đã có ở cả 5 repo app.
# universal-agent-devkit/tests/gates/test_guard_merge_queue_label.sh
MQ_LABEL = "merge-queue"
MQ_MSG = "gắn nhãn merge-queue khi PR chưa có approved-head khớp head"
MQ_HELPER = os.path.join(".claude", "bin", "super-board-queue-label.sh")
MQ_HELPER_DEPS = [os.path.join(".claude", "bin", "super-board-approved-head.jq"), os.path.join(".claude", "bin", "super-board-audit-check.py"),
                  os.path.join("universal-agent-devkit", "bin", "push_gate.py"), os.path.join(".agents", "devkit", "bin", "push_gate.py")]
MQ_BUDGET_S = 9.0   # tổng thời gian của guard khi có lời gọi helper: dưới timeout 10 s của hook ở Codex/Gemini/Cursor
# Cờ KHÔNG mang giá trị của gh pr edit / issue edit / pr create (gh 2.103.3 --help); mọi cờ dài khác mang giá trị.
MQ_BOOL_LONG = {"--remove-milestone", "--remove-parent", "--remove-type", "--draft", "--dry-run", "--editor", "--fill",
                "--fill-first", "--fill-verbose", "--no-maintainer-edit", "--web", "--help"}
MQ_BOOL_SHORT = {"create": "defwh", "edit": "h", "api": "ih"}   # cờ ngắn boolean; chữ khác của cụm mang giá trị (pflag)

def _mq_has(v):
    """Danh sách nhãn (phân tách dấu phẩy) có merge-queue; GitHub so tên nhãn không phân biệt hoa thường."""
    return any(x.strip().casefold() == MQ_LABEL for x in (v or "").split(","))

def _mq_git(root, *args):
    """(exit, stdout) của git ở `root`; (-1, "") khi không chạy được / quá 5 s."""
    try:
        r = subprocess.run(["git", "-C", root, *args], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5)
        return r.returncode, r.stdout
    except (OSError, subprocess.SubprocessError):
        return -1, ""

def _mq_helper_at(root):
    """(đường dẫn, lý do chặn) của helper dưới `root`. Git HEAD theo dõi helper mà file vắng (mv, git mv) hoặc khác HEAD (ghi đè,
    sed -i, cp) → lý do chặn: chỉ rm là file bảo vệ, nên mất file không được làm luật thôi chạy (OCR #826). Git không theo dõi: file có
    thì dùng (bản đồng bộ chưa commit), không có thì (None, None)."""
    path = os.path.join(root, MQ_HELPER)
    restore = f"khôi phục: git -C {root} checkout -- {MQ_HELPER}"
    rc, out = _mq_git(root, "ls-tree", "--name-only", "HEAD", "--", MQ_HELPER)
    if rc == -1:
        return None, f"{MQ_MSG}: không kiểm được {MQ_HELPER} của {root} bằng git — chặn để an toàn"
    if rc != 0 or not out.strip():   # chưa có commit / git không theo dõi helper
        return (path if os.path.isfile(path) else None), None
    if not os.path.isfile(path):
        return None, f"{MQ_MSG}: {MQ_HELPER} git đã theo dõi nhưng không còn trong cây ({root}) — {restore}"
    # Luật duyệt helper dùng (jq approved-head, audit-check, push_gate) cũng phải khớp HEAD: sửa chúng trong cây là duyệt mọi PR (OCR
    # final). So NỘI DUNG file với blob của HEAD (hash-object --no-filters), không qua git diff: --assume-unchanged / --skip-worktree /
    # filter giấu thay đổi khỏi diff. Path HEAD không theo dõi dưới dạng file thường (.agents/devkit symlink) bỏ qua; file theo dõi
    # mà trong cây là symlink → không khớp.
    rc, out = _mq_git(root, "ls-tree", "HEAD", "--", MQ_HELPER, *MQ_HELPER_DEPS)
    want = {}
    for line in (out.splitlines() if rc == 0 else []):
        meta, _, rel = line.partition("\t")
        parts = meta.split()
        if len(parts) == 3 and parts[1] == "blob" and parts[0] in ("100644", "100755"):
            want[rel] = parts[2]
    rels = sorted(want)
    got = []
    if rc == 0 and rels and all(os.path.isfile(os.path.join(root, r)) and not os.path.islink(os.path.join(root, r)) for r in rels):
        hrc, hout = _mq_git(root, "hash-object", "--no-filters", "--", *rels)
        got = hout.split() if hrc == 0 else []
    if rc != 0 or not rels or [want[r] for r in rels] != got:
        return None, (f"{MQ_MSG}: {MQ_HELPER} hoặc luật duyệt nó dùng khác bản HEAD ({root}) — khôi phục: git -C {root} checkout -- "
                      f"{chr(32).join(rels or [MQ_HELPER])}, hoặc commit bản sửa trước")
    return path, None

def _mq_helper():
    """(helper, lý do chặn) của project phiên: helper của checkout chính trước khi project là linked worktree, rồi của chính project.
    (None, None) khi project chưa có helper (luật không chạy, ponytail ở đầu mục)."""
    proj = backup_root()
    if not proj:
        return None, None
    rc, common = _mq_git(proj, "rev-parse", "--path-format=absolute", "--git-common-dir")
    common = common.strip().rstrip("/") if rc == 0 else ""
    roots = [os.path.dirname(common)] if common and os.path.basename(common) == ".git" else []
    roots += [proj] if os.path.realpath(proj) not in [os.path.realpath(r) for r in roots] else []
    for root in roots:
        path, why = _mq_helper_at(root)
        if why or path:
            return path, why
    return None, None

def _mq_parse(args, kind):
    """Tách đối số gh theo pflag: [(cờ, giá trị|None)], [positional]. Cụm cờ ngắn (-dl x, -lmerge-queue, -if k=v): chữ boolean đi tiếp,
    chữ đầu tiên mang giá trị lấy phần còn lại của token hoặc token kế. Cờ dài: --x=v, hoặc --x v trừ cờ boolean."""
    flags, pos, k = [], [], 0
    bools = MQ_BOOL_SHORT.get(kind, "h")
    while k < len(args):
        a = args[k]
        nxt = args[k + 1] if k + 1 < len(args) else None
        if a == "--":
            pos.extend(args[k + 1:])
            break
        if a.startswith("--"):
            opt, eq, val = a.partition("=")
            if eq:
                flags.append((opt, val)); k += 1
            elif a in MQ_BOOL_LONG or (kind == "api" and a in ("--paginate", "--slurp", "--silent", "--verbose", "--include",
                                                                "--allow-escape-sequences")):
                flags.append((a, None)); k += 1
            else:
                flags.append((a, nxt)); k += 2
            continue
        if a.startswith("-") and len(a) > 1:
            j, took = 1, False
            while j < len(a):
                c = a[j]
                if c in bools:
                    flags.append(("-" + c, None)); j += 1
                    continue
                v = a[j + 1:]
                if v:
                    flags.append(("-" + c, v)); k += 1
                else:
                    flags.append(("-" + c, nxt)); k += 2
                took = True
                break
            if not took:
                k += 1
            continue
        pos.append(a)
        k += 1
    return flags, pos

def _mq_ghrepo_reason():
    """GH_REPO đặt ở chỗ khác trong dòng lệnh (export, gán trần, subshell, unset…) chứ không làm tiền tố của chính lệnh gh: guard
    không theo được giá trị gh thấy lúc chạy → lý do chặn; None khi dòng lệnh không nhắc GH_REPO."""
    if re.search(r"\bGH_REPO\b", cmd):
        return f"{MQ_MSG}: GH_REPO đặt ngoài lệnh gh (export / gán / unset), không biết gh sẽ gắn nhãn repo nào — ghi --repo OWNER/NAME"
    return None

def _mq_last(flags, names):
    """Giá trị của lần cuối cờ xuất hiện (pflag: cờ lặp thì giá trị sau đè giá trị trước); None khi không có."""
    v = None
    for o, val in flags:
        if o in names:
            v = val
    return v

def _mq_check(helper, sels, repo, base):
    """None = cho gắn nhãn; chuỗi = lý do chặn. sels = các số / URL / nhánh PR (phải có ít nhất một)."""
    if not sels:
        return f"{MQ_MSG}: không thấy số PR trong lệnh (PR của nhánh hiện tại, xargs, biến của script) — ghi số PR thật"
    if not repo and (not base or _unknowable(base) or not os.path.isdir(base)):   # cd $X / popd: repo của lệnh không xác định
        return f"{MQ_MSG}: thư mục chạy lệnh không xác định (cd tới đường dẫn chỉ biết lúc chạy) — ghi --repo OWNER/NAME"
    if IN_XARGS[0]:
        return f"{MQ_MSG}: lệnh chạy qua xargs — số PR do stdin nối thêm, guard không biết PR nào bị gắn nhãn; ghi số PR thật, mỗi lệnh một PR"
    for v in list(sels) + ([repo] if repo else []):
        if _unknowable(v) or "{" in v:
            return f"{MQ_MSG}: số PR / repo chỉ biết lúc chạy ({v}), không kiểm được approved-head — ghi số PR thật hoặc dùng {MQ_HELPER} <pr>"
    try:
        limit = min(max(int(os.environ.get("DEVKIT_QUEUE_LABEL_TIMEOUT") or 8), 1), 8)
    except ValueError:
        limit = 8
    cwd = base if base and os.path.isdir(base) else os.path.dirname(os.path.dirname(os.path.dirname(helper)))
    for sel in sels:
        left = _GUARD_T0 + MQ_BUDGET_S - time.time()   # thời gian còn lại của cả lần guard này (nhiều PR / nhiều lệnh cộng dồn)
        wait = min(limit, left - 0.5)
        if wait < 1:
            return f"{MQ_MSG}: hết thời hạn {MQ_BUDGET_S:.0f} s của guard trước khi kiểm xong PR {sel} — tách lệnh, mỗi lệnh một PR"
        argv = ["bash", helper, "--check", sel] + (["--repo", repo] if repo else [])
        # Helper gọi GitHub có thể lâu hơn watchdog 7 s của parser: dời watchdog tới hết thời hạn chung rồi đặt lại theo phần còn lại.
        # Hết hạn → chặn với lý do của luật này (không để _too_slow gợi ý "chia nhỏ lệnh"), giết cả nhóm tiến trình của helper.
        if hasattr(signal, "setitimer"):
            signal.setitimer(signal.ITIMER_REAL, left + 0.5)
        p, err = None, ""
        try:
            p = subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                 text=True, start_new_session=True)
            _, err = p.communicate(timeout=wait)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:   # INSTINCT-056: macOS có thể từ chối killpg (EPERM)
                p.kill()
            try:
                p.communicate(timeout=1)
            except subprocess.SubprocessError:
                pass
            return f"{MQ_MSG}: không kiểm được approved-head của PR {sel} trong {wait:.0f} s (GitHub chậm) — chặn để an toàn, thử lại sau"
        except (OSError, ValueError, subprocess.SubprocessError) as e:
            return f"{MQ_MSG}: không chạy được {MQ_HELPER} ({e})"
        finally:
            if hasattr(signal, "setitimer"):
                signal.setitimer(signal.ITIMER_REAL, max(0.5, _GUARD_T0 + MQ_BUDGET_S + 0.5 - time.time()))
        if p.returncode != 0:
            why = " ".join(l.strip() for l in (err or "").strip().splitlines()[-3:]) or f"{MQ_HELPER} exit {p.returncode}"
            return f"{MQ_MSG}: {why[:600]}"
    return None

def _mq_label_values(text):
    """Các tên nhãn trong body gh api …/labels: JSON {labels:[…]|"x"}, mảng trần ["x"] / [{"name":"x"}], chuỗi JSON, hay chuỗi trơn."""
    try:
        o = json.loads(text)
    except ValueError:
        return [text]
    if isinstance(o, dict) and o.get("labels") is None:   # không có khoá labels, hoặc labels: null (PATCH title / body)
        return []
    vals = o.get("labels") if isinstance(o, dict) else o
    if isinstance(vals, str):
        return [vals]
    if not isinstance(vals, list):
        return [text]
    return [v.get("name") if isinstance(v, dict) else v for v in vals if isinstance(v, (str, dict))]

def _mq_gql_shell(t):
    """Chuỗi query graphql có nội suy shell dạng thường gặp: `${…}`, hoặc tên field là biến (`{ $M(` / `: $M(`) — GraphQL không
    cho biến ở vị trí tên field. Dạng nội suy cố ý né luật (ghép chuỗi, biến trùng tên biến GraphQL) nằm ngoài phạm vi (#536)."""
    return "${" in t or re.search(r"[{:]\s*\$\w+\s*\(", t) is not None

def _gh_stdin_expanding():
    """Có heredoc KHÔNG quote mà body có `$` / backtick / thay thế lệnh: shell nội suy trước khi gh đọc stdin. Lỗi khi đọc → coi như có."""
    try:
        return any(not h.quoted and _unknowable(h.body(cmd)) for h in shell_norm.heredocs(cmd))
    except Exception:
        return True

def _mq_gql_label(texts):
    """Mutation graphql gắn nhãn: addLabelsToLabelable, hoặc labelIds trong updatePullRequest / updateIssue (createIssue thì không)."""
    blob = "\n".join(texts)
    return bool(re.search(r"addLabelsToLabelable", blob, re.I)
                or (re.search(r"labelIds", blob, re.I) and re.search(r"\bupdate(?:PullRequest|Issue)\b", blob)))

def _mq_api(args, base):
    """gh api: (lý do chặn | None, [số PR], repo) — None, [], None khi không phải lệnh thêm nhãn merge-queue."""
    flags, pos = _mq_parse(args, "api")
    fields = [(o, v) for o, v in flags if v is not None and o in ("-f", "-F", "--field", "--raw-field")]
    input_src = _mq_last(flags, ("--input",))
    method = (_mq_last(flags, ("-X", "--method")) or "").upper() or None
    if any(_gh_graphql_endpoint(x) for x in pos):
        texts, query, query_bad, data_bad = [], None, False, False
        for o, nv in fields:
            name, eq, v = nv.partition("=")
            texts.append(name)
            t, _why = _gh_field_text(o, v, base) if eq else (v, None)
            # Query: `$x` đã khai báo là biến GraphQL, còn lại là nội suy shell (_mq_gql_shell). Field khác: mọi `$` / lệnh con là shell.
            if name == "query":
                bad = t is None or bool(re.fullmatch(r"\s*\$\{?\w+\}?\s*", t)) or SUBST in t or "`" in t or _mq_gql_shell(t)
            else:
                bad = t is None or _unknowable(t) or (v == "@-" and _gh_stdin_expanding())
            if name == "query":
                query, query_bad = (None, True) if bad else (t, False)
            elif bad:
                data_bad = True
            if t is not None:
                texts.append(t)
        if input_src is not None:
            t = ("\n".join(_gh_stdin_texts()) or None) if input_src == "-" else _gh_file(input_src, base)
            # --input là body HTTP thật (-f query=… khi đó chỉ vào URL): không đọc được / heredoc bị shell nội suy → cả query lẫn dữ liệu
            if t is None or (input_src == "-" and _gh_stdin_expanding()):
                query_bad = data_bad = True
            else:
                texts.append(t)
                try:   # --input là JSON {query, variables}: so cả bản đã giải mã (escape \u trong tên mutation)
                    o = json.loads(t)
                    if isinstance(o, dict):
                        if isinstance(o.get("query"), str):   # file / heredoc có quote: chữ nguyên văn, không có nội suy shell
                            query = o["query"]
                            texts.append(query)
                        texts.append(json.dumps(o.get("variables"), ensure_ascii=False))
                except ValueError:
                    query = query if query is not None else t
        if _mq_gql_label(texts):
            return f"{MQ_MSG}: mutation graphql gắn nhãn theo id (addLabelsToLabelable / labelIds), không biết là nhãn nào — dùng {MQ_HELPER} <pr>", [], None
        # Biến shell ở field dữ liệu (threadId, itemId…) không đổi được tên mutation: chỉ chặn khi chính query không đọc được, hoặc query
        # là mutation gắn nhãn được (updatePullRequest / updateIssue) mà dữ liệu không đọc được (labelIds có thể nằm trong đó).
        if query_bad or (data_bad and query is not None and re.search(r"\bupdate(?:PullRequest|Issue)\b|addLabelsToLabelable", query)):
            return f"{MQ_MSG}: mutation graphql có query / biến / --input không đọc được, không kiểm được nó có gắn nhãn không", [], None
        return None, [], None
    if method in ("GET", "DELETE", "HEAD") or (method is None and not fields and input_src is None):
        return None, [], None
    num, repo = None, None
    for x in pos:
        if re.search(r"(?:^|/)repositories/[^/]+/issues/", x):
            return f"{MQ_MSG}: endpoint repositories/<id>/issues/… không cho biết repo, không kiểm được approved-head — dùng {MQ_HELPER} <pr>", [], None
        m = re.search(r"(?:^|/)repos/([^/]+/[^/]+)/issues/([^/?]+)(?:/labels)?/?(?:\?|$)", x) or \
            re.search(r"(?:^|/)issues/([^/?]+)(?:/labels)?/?(?:\?|$)", x)
        if m:
            if m.lastindex == 2:
                repo, num = m.group(1), m.group(2)
            else:
                num = m.group(1)
            break
    if num is None:
        return None, [], None
    if repo and re.fullmatch(r"\{owner\}/\{repo\}", repo):   # placeholder của gh: repo của cwd, như khi không có --repo
        repo = None
    names = []
    for o, nv in fields:
        name, eq, v = nv.partition("=")
        if not eq or not name.startswith("labels"):
            continue
        t, _why = _gh_field_text(o, v, base)
        file_val = o in ("-F", "--field") and v.startswith("@")   # nội dung file / stdin, không phải chữ trên dòng lệnh
        if t is None or (not file_val and _unknowable(t)) or (v == "@-" and _gh_stdin_expanding()):
            return f"{MQ_MSG}: nhãn của gh api …/issues/{num}/labels không đọc được (field {name}), không kiểm được có merge-queue không", [], None
        names.extend(_mq_label_values(t) if t.lstrip().startswith(("[", "{", "\x22")) else [t])
    if input_src is not None:
        t = ("\n".join(_gh_stdin_texts()) or None) if input_src == "-" else _gh_file(input_src, base)
        if t is None or (input_src == "-" and _gh_stdin_expanding()):   # file trên đĩa: shell không nội suy nội dung
            return f"{MQ_MSG}: --input của gh api …/issues/{num}/labels không đọc được, không kiểm được có merge-queue không", [], None
        names.extend(_mq_label_values(t))
    if any(isinstance(n, str) and _mq_has(n) for n in names):
        return None, [num], repo   # num không phải số (biến, {n} của script): _mq_check chặn vì không biết PR
    return None, [], None

def gh_label_rule(rest, base, env_repo=None):
    """Lý do chặn khi lệnh gh thêm nhãn merge-queue cho PR chưa có approved-head khớp head; None khi không phải lệnh đó, PR đủ điều
    kiện, hoặc project chưa có helper."""
    rest = drop_redirects(rest)
    j, lead_repo = 0, None
    while j < len(rest) and rest[j].startswith("-"):   # cờ toàn cục đứng trước lệnh con: gh -R o/r pr edit …
        a = rest[j]
        if a in GH_GLOBAL_ARG and j + 1 < len(rest):
            lead_repo = rest[j + 1] if a in ("-R", "--repo") else lead_repo
            j += 2
            continue
        lead_repo = a[7:] if a.startswith("--repo=") else a[2:] if (a[:2] == "-R" and len(a) > 2) else lead_repo
        j += 1
    k = j + 1
    if rest[j:j + 1] in (["pr"], ["issue"]):   # cờ của lệnh nhóm đứng trước lệnh con (gh pr -R o/r edit 5 …): nhóm pr / issue chỉ có -R / --repo
        while k < len(rest) and rest[k].startswith("-"):
            a = rest[k]
            if a in ("-R", "--repo") and k + 1 < len(rest):
                lead_repo, k = rest[k + 1], k + 2
            elif a.startswith("--repo=") or (a[:2] == "-R" and len(a) > 2):
                lead_repo, k = (a[7:] if a.startswith("--repo=") else a[2:]), k + 1
            else:
                break
    sub, args = rest[j:j + 1] + rest[k:k + 1], rest[k + 1:]
    if sub[:1] == ["api"]:
        reason, sels, api_repo = _mq_api(rest[j + 1:], base)
        if not reason and not sels:
            return None
        helper, hwhy = _mq_helper()   # project chưa có helper: luật không chạy (ponytail ở đầu mục)
        if hwhy:
            return reason or hwhy
        if helper is None or reason:
            return reason if helper else None
        repo = api_repo or env_repo
        why = None if repo else _mq_ghrepo_reason()
        return why or _mq_check(helper, sels, repo, base)
    create = sub in (["pr", "create"], ["pr", "new"])
    if not create and sub not in (["pr", "edit"], ["issue", "edit"]):
        return None
    flags, sels = _mq_parse(args, "create" if create else "edit")
    repo = _mq_last(flags, ("-R", "--repo")) or lead_repo or env_repo
    want = ("--label", "-l") if create else ("--add-label",)
    if not any(o in want and (v is None or _unknowable(v) or _mq_has(v)) for o, v in flags):
        return None
    helper, hwhy = _mq_helper()   # project chưa có helper: luật không chạy (ponytail ở đầu mục)
    if hwhy:
        return hwhy
    if helper is None:
        return None
    why = None if repo else _mq_ghrepo_reason()
    if why:
        return why
    if create:
        return f"{MQ_MSG}: PR mới chưa thể có approved-head — tạo PR không kèm nhãn này, nhãn do lane Review gắn sau khi duyệt ({MQ_HELPER} <pr>)"
    return _mq_check(helper, sels, repo, base)

def _lit_decode(s):
    """Nội dung một string literal của script (\\n, \\t, \\x22 …) như chương trình sẽ thấy; lỗi giải mã → nguyên văn."""
    try:
        return s.encode("latin-1", "backslashreplace").decode("unicode_escape")
    except (UnicodeDecodeError, ValueError):
        return s

def gh_in_literals(code, base):
    """(audit T0066 vòng 2) interpreter (-c / -e / heredoc) gọi gh: dạng danh sách ([\x22gh\x22, \x22issue\x22, …], mỗi literal một đối số,
    giữ xuống dòng của body) và dạng chuỗi (\x22gh pr comment 5 --body done\x22, tách như shell) đều đi qua gh_comment_rule."""
    if "gh" not in code.lower():
        return None
    lits = [_lit_decode(next((g for g in m.groups() if g is not None), "")) for m in STR_LITERAL.finditer(code)]
    for idx, lit in enumerate(lits):
        if lit.rsplit("/", 1)[-1].lower() == "gh":   # (#536 review) macOS chạy GH / Gh như gh
            reason = gh_comment_rule(lits[idx + 1:], base) or gh_label_rule(lits[idx + 1:], base)
        else:
            try:
                ws = shlex.split(lit)
            except ValueError:
                ws = lit.split()
            reason = next((r for r in (gh_comment_rule(ws[k + 1:], base) or gh_label_rule(ws[k + 1:], base)
                                       for k, w in enumerate(ws) if w.rsplit("/", 1)[-1].lower() == "gh") if r), None)
        if reason:
            return reason
    return None

def _operands(args):
    out, end = [], False
    for a in drop_redirects(args):
        if not end and a == "--":
            end = True
        elif end or not a.startswith("-") or a == "-":
            out.append(a)
    return out

def analyse_simple(tokens, depth):
    tokens = shell_norm.inline_script(tokens)   # sudo -s STR, env -S STR: the command line a wrapper hides becomes words
    i = 0
    hooks_off = False
    allow_branch = ALLOW_BRANCH[0]
    assigns = {}   # NAME=VAL set for this command (prefix, env) or exported
    while i < len(tokens) and (tokens[i] in KEYWORDS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[i])):
        hooks_off = hooks_off or bool(HOOK_OFF_ENV.match(tokens[i]))
        allow_branch = allow_branch or tokens[i] == ALLOW_BRANCH_ENV
        if "=" in tokens[i]:
            assigns.update([tokens[i].split("=", 1)])
        i += 1
    while i < len(tokens):
        if REDIRECT.match(tokens[i]):   # (2026-10-13) a redirect before the command: `2>/dev/null git reset --hard`, `2>&1 git …`
            i += shell_norm.redirect_len(tokens, i)
            continue
        prog = tokens[i].rsplit("/", 1)[-1]
        if prog == "env":
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or "=" in tokens[i]):
                # env -S STRING / --split-string=STRING splits STRING into the words env runs (2026-10-09: the value was
                # skipped as an option argument, so `env -S "git reset --hard"` passed): those words replace it.
                t = tokens[i]
                split = (tokens[i + 1] if t in ("-S", "--split-string") and i + 1 < len(tokens)
                         else t[2:] if t.startswith("-S") and len(t) > 2
                         else t.split("=", 1)[1] if t.startswith("--split-string=") else None)
                if split is not None:
                    try:
                        words = shlex.split(split)
                    except ValueError:
                        m = RAW.search(split)
                        return f"{m.group(1).split()[0]} (env -S)" if m else "env -S: chuỗi lệnh không phân tích được"
                    return analyse_simple(tokens[:i] + words + tokens[i + (2 if t in ("-S", "--split-string") else 1):], depth + 1)
                hooks_off = hooks_off or bool(HOOK_OFF_ENV.match(tokens[i]))
                allow_branch = allow_branch or tokens[i] == ALLOW_BRANCH_ENV
                if "=" in tokens[i] and not tokens[i].startswith("-"):
                    assigns.update([tokens[i].split("=", 1)])
                i += 2 if tokens[i] in ("-u", "-C", "-S", "-P") else 1
        elif prog in WRAPPERS:
            i = skip_wrapper(tokens, i, prog)
        elif tokens[i] in KEYWORDS:
            i += 1
        else:
            break
    if i < len(tokens) and tokens[i] in ("export", "declare", "typeset"):
        assigns.update(a.split("=", 1) for a in tokens[i + 1:] if "=" in a and not a.startswith("-"))
        for name in PM_STATE_ENVS:   # export ANTIGRAVITY_PM_STATE_HOME (giá trị gán ở lệnh trước)
            if name in tokens[i + 1:]:
                assigns[name] = ""
    if RETARGET_ENV & set(assigns):
        RETARGETED[0] = True
    reason = env_config_danger(assigns) if assigns else None
    if reason:
        return reason
    if "HOME" in assigns and (i >= len(tokens) or tokens[i] in ("export", "declare", "typeset")):
        HOME_SET[0] = True
    if (HOME_SET[0] or "HOME" in assigns) and i < len(tokens) and GATE_CMD.search(" ".join(tokens[i:])):
        return f"{PM_STATE_MSG} HOME: lệnh gate / push / integrate kèm HOME do agent đặt thì ~/.antigravity-pm là thư mục agent tự viết"
    if i >= len(tokens):
        return None
    prog, rest = tokens[i].rsplit("/", 1)[-1], tokens[i + 1:]
    # macOS resolves GIT / Git to git, and a glob like g?t or gi[t] can expand to it.
    if prog.lower() == "git" or (re.search(r"[*?\[]", prog) and _fnm("git", prog)):
        prog = "git"
    if prog in ("cd", "pushd", "popd"):
        CHANGES_DIR.append(prog)
        tgt = next((a for a in rest if not a.startswith("-")), "~")
        unknown = prog == "popd" or rest[:1] == ["-"] or not CUR_DIR[0]
        CUR_DIR[0] = None if unknown else os.path.join(CUR_DIR[0], os.path.expanduser(tgt))
    if prog == "export" and ALLOW_BRANCH_ENV in rest:
        ALLOW_BRANCH[0] = True
    # (2026-10-22, #144) kill / wait by process NAME reaches every session on the machine: `pkill -f post-fix-gate` killed the gates
    # of other boards, `pgrep -f "git push"` matched the push of another session. A PID the session recorded (`kill $pid`, `wait $pid`)
    # and a plain `pgrep NAME` lookup stay allowed. tests/gates/test_guard_kill_by_name.sh
    lp = prog.lower()
    if lp in ("pkill", "killall") or (lp == "pgrep" and any(
            a == "--full" or (a.startswith("-") and not a.startswith("--") and "f" in a[1:]) for a in rest)):
        return f"kill theo tên ({lp}) trúng tiến trình của mọi phiên/board khác trên máy"
    if prog in ("rm", "unlink"):   # (#605) xoá file quan trọng: người làm hoặc duyệt
        opts = rest[:rest.index("--")] if "--" in rest else rest
        rec = prog == "rm" and any(a == "--recursive" or (a.startswith("-") and not a.startswith("--") and ("r" in a or "R" in a))
                                   for a in opts)
        return protected_delete_rule(_operands(rest), CUR_DIR[0], walk=rec)   # (#605 Lane H) rm -r: quét nông thư mục
    # (#536 review) như git ở trên: macOS chạy GH / Gh như gh, glob g[h] / g? có thể nở ra gh
    if prog.lower() == "gh" or (re.search(r"[*?\[]", prog) and _fnm("gh", prog)):
        prog = "gh"
    if prog == "gh":   # (#605 Lane H) agent không tự đăng approved-head trơn / done; (#536) nhãn merge-queue cần approved-head
        return gh_comment_rule(rest, CUR_DIR[0]) or gh_label_rule(rest, CUR_DIR[0], assigns.get("GH_REPO"))
    # `$g reset --hard` / `${GIT} clean -f`: a variable in command position may be git. So may a $(…) / backtick there
    # (`$(echo gi)t reset --hard`, 2026-10-09): its output is the program name.
    if prog.startswith("$") or SUBST in prog:
        if IN_C_SCRIPT[0] and SUBST in prog:
            PENDING_FEED.append(UNREADABLE_CSUBST)   # bash -c "( $(curl ...) )", "if $(...)", "exec $(...)": the command word is generated text
        return danger_in_git(rest[0], rest[1:]) if rest else None
    if prog in AWKS:
        reason = git_in_literals(" ".join(rest), allow_branch)
        return f"{reason} (gọi qua {prog})" if reason else None
    if prog in INTERPRETERS:
        for code in inline_codes(rest):
            # (#605) os.remove / shutil.rmtree / fs.rmSync … path bảo vệ; gh đăng comment tự duyệt (audit T0066 vòng 2)
            reason = pm_env_in_code(code) or interp_delete_rule(code, CUR_DIR[0]) or gh_in_literals(code, CUR_DIR[0])
            if reason:
                return reason
            m = RAW.search(code)
            if m:
                return f"{m.group(1).split()[0]} (gọi qua {prog})"
            reason = git_in_literals(code, allow_branch)
            if reason:
                return f"{reason} (gọi qua {prog})"
        return None
    if prog == "watch":
        j = 0
        while j < len(rest) and rest[j].startswith("-"):
            j += 2 if rest[j] in ("-n", "-d", "--interval") else 1
        return analyse_free(" ".join(rest[j:]), depth + 1) if j < len(rest) else None
    if prog == "find":
        # (#605) find -delete / -exec rm|unlink: điểm bắt đầu và bộ lọc -name/-path được xét như toán hạng xoá
        if "-delete" in rest or any(a in ("-exec", "-execdir", "-ok", "-okdir") and j + 1 < len(rest)
                                    and rest[j + 1].rsplit("/", 1)[-1] in ("rm", "unlink") for j, a in enumerate(rest)):
            starts = []
            for a in rest:
                if a.startswith("-") or a in ("!", "(", ")"):
                    break
                starts.append(a)
            names = [rest[j + 1] for j, a in enumerate(rest[:-1]) if a in ("-name", "-iname")]
            paths = [rest[j + 1] for j, a in enumerate(rest[:-1]) if a in ("-path", "-ipath", "-wholename", "-iwholename")]
            reason = protected_delete_rule(starts or ["."], CUR_DIR[0], names, paths)
            if reason:
                return reason
        for j, a in enumerate(rest):
            if a in ("-exec", "-execdir", "-ok", "-okdir"):
                sub = []
                for t in rest[j + 1:]:
                    if t in (";", "+"):
                        break
                    sub.append(t)
                reason = analyse_simple(sub, depth + 1)
                if reason:
                    return reason
        return None
    if prog == "su":
        # (2026-10-14, W3) su -c STR runs STR like bash -c; the Android form su [OPTS] USER CMD… runs CMD (shell_norm.su_command)
        ran = shell_norm.su_command(rest)
        if ran and ran[0] == "argv":
            return analyse_simple(ran[1], depth + 1)
        if ran:
            IN_C_SCRIPT[0] += 1
            try:
                return analyse(ran[1], depth + 1)
            finally:
                IN_C_SCRIPT[0] -= 1
        return None
    if prog in SHELLS or prog == "eval":
        if prog == "eval":
            return analyse_free(" ".join(rest), depth + 1)
        # -c alone or in a flag cluster (bash -lc); options may follow -c: the command is the first operand (`bash -c -- STR`,
        # `bash -c -e STR`; 2026-10-09 the `--` was analysed instead of STR). shell_norm.shell_script
        if any(a == "-c" or (a.startswith("-") and not a.startswith("--") and "c" in a[1:]) for a in rest):
            script = shell_norm.shell_script(rest)
            if script is None:
                return None
            IN_C_SCRIPT[0] += 1   # inside the script: a command word made by a command substitution is refused (analyse_simple)
            try:
                return analyse(script, depth + 1)
            finally:
                IN_C_SCRIPT[0] -= 1
        for j, a in enumerate(rest):
            if a.startswith("<<<"):   # bash <<< STR: the here-string is the script
                here = a[3:] if len(a) > 3 else (rest[j + 1] if j + 1 < len(rest) else "")
                if not literal_word(here):
                    PENDING_FEED.append(UNREADABLE_FEED)
                    return None
                return analyse(here, depth + 1)
        if proc_subst_script(rest):
            PENDING_FEED.append(UNREADABLE_PSUBST)
        return None
    far = shell_norm.far_command(prog, rest)   # ssh HOST CMD, and (2026-10-14, W3) adb shell|exec-out CMD on a device
    if far:
        here = CUR_DIR[0]
        if far[1] == "device":
            CUR_DIR[0] = None   # the device directory: not known here
        try:
            return analyse_free(far[0], depth + 1)
        finally:
            CUR_DIR[0] = here
    if prog == "xargs":
        IN_XARGS[0] += 1   # (#536) luật nhãn merge-queue: số PR do stdin nối thêm
        try:
            return analyse_simple(rest[shell_norm.xargs_command(rest):], depth + 1)
        finally:
            IN_XARGS[0] -= 1
    if prog != "git":
        return None
    j = 0
    aliases = {}
    gdir = CUR_DIR[0]
    while j < len(rest) and rest[j].startswith("-"):
        opt = rest[j].split("=", 1)[0]
        if rest[j] == "-C" and j + 1 < len(rest):
            p = os.path.expanduser(rest[j + 1])
            gdir = p if os.path.isabs(p) else (os.path.join(gdir, p) if gdir else None)
        if opt in ("-c", "--config-env"):
            spec = rest[j].split("=", 1)[1] if "=" in rest[j] else (rest[j + 1] if j + 1 < len(rest) else "")
            key, eq, val = spec.partition("=")
            val = (val if eq else "true") if opt == "-c" else None  # --config-env: value in an env var
            if key.lower().startswith("alias."):
                aliases[key[len("alias."):].lower()] = val   # checked only if the alias is run
            else:
                reason = config_danger(key, val)
                if reason:
                    return f"git {opt} {reason}"
        j += 2 if (opt in GIT_OPTS_WITH_ARG and "=" not in rest[j]) else 1
    if j >= len(rest):
        return None
    if rest[j].lower() in aliases:
        reason = config_danger("alias." + rest[j], aliases[rest[j].lower()])
        if reason:
            return f"alias {rest[j]} → {reason}"
    relocated = any(o.split("=", 1)[0] in ("-C", "--git-dir", "--work-tree") for o in rest[:j])
    if any(o.split("=", 1)[0] in ("--git-dir", "--work-tree") for o in rest[:j]):
        RETARGETED[0] = True
    if rest[j] == "restore" and not relocated and backup_then_allow_restore(rest[j + 1:]):
        return None
    if hooks_off and rest[j] in ("commit", "merge", "am", "cherry-pick", "revert"):
        return "DEVKIT_PRECOMMIT=0 tắt pre-commit hook (kiểm secret/chất lượng)"
    if rest[j] == "submodule" and "foreach" in rest[j + 1:]:
        # (2026-10-13) foreach runs its command in every submodule: judged like a command line of its own
        k = rest.index("foreach", j + 1) + 1
        while k < len(rest) and rest[k].startswith("-"):
            k += 1
        here = CUR_DIR[0]
        CUR_DIR[0] = None   # each submodule directory: not known here
        try:
            reason = analyse_free(" ".join(rest[k:]), depth + 1) if k < len(rest) else None
        finally:
            CUR_DIR[0] = here
        if reason:
            return f"{reason} (trong git submodule foreach)"
    if rest[j] == "rm" and not any(a == "--cached" or (a.startswith("--ca") and "--cached".startswith(a.split("=", 1)[0]))
                                   for a in rest[j + 1:]):
        opts = rest[j + 1:rest.index("--")] if "--" in rest[j + 1:] else rest[j + 1:]
        rec = any(a == "--recursive" or (a.startswith("-") and not a.startswith("--") and ("r" in a or "R" in a)) for a in opts)
        reason = protected_delete_rule(_operands(rest[j + 1:]), gdir, walk=rec)   # (#605) git rm xoá cả file trên đĩa; -r quét thư mục
        if reason:
            return reason
    return (danger_in_git(rest[j], rest[j + 1:]) or solo_branch_rule(rest[j], rest[j + 1:], gdir, allow_branch)
            or (checkout_path_rule(rest[j + 1:], gdir) if rest[j] == "checkout" else None))

def checkout_path_rule(args, gdir):
    """(2026-10-13) `git checkout <path>` and `git checkout <tree-ish> <path>…` without -- overwrite working-tree files like
    `checkout -- <path>`. Two operands or more are always <tree-ish> <paths>; one operand is a branch switch when it names a
    commit (rev-parse in gdir), a path when it does not and is an existing file or directory or a glob. A new or tracked branch
    (-b -B -t --orphan --track) and --patch are judged elsewhere. gdir unknown (cd $X): one operand is not judged."""
    args = drop_redirects(args)
    if "--" in args:
        return None   # danger_in_git refuses checkout -- <path>
    short, long_ = short_flags(args), set(a.split("=", 1)[0] for a in args if a.startswith("--"))
    if short & {"b", "B", "t", "p"} or long_ & {"--orphan", "--track", "--patch"}:
        return None
    if "--pathspec-from-file" in long_:
        return "checkout --pathspec-from-file ghi đè file working tree"
    pos = [a for a in args if not a.startswith("-")]
    if len(pos) >= 2:
        return f"checkout {pos[0]} {pos[1]}: <tree-ish> <path> ghi đè file working tree (như checkout -- <path>)"
    if len(pos) == 1 and gdir:
        if solo_git(gdir, "rev-parse", "--verify", "-q", pos[0] + "^{commit}") == 0:
            return None
        if re.search(r"[*?\[]", pos[0]) or os.path.lexists(os.path.join(gdir, os.path.expanduser(pos[0]))):
            return f"checkout {pos[0]}: là đường dẫn, ghi đè file working tree (như checkout -- <path>)"
    return None

RAW = re.compile(
    r"\bgit\b[^;&|\n]*?\s(reset\s+[^;&|\n]*--(hard|merge|keep)"
    r"|clean\b(?![^;&|\n]*\s(?:-(?:(?!e)[A-Za-z])*n|--dry-run))\s+[^;&|\n]*(-[A-Za-z]*f|--force)"
    r"|branch\s+[^;&|\n]*-D"
    r"|(checkout|switch)\s+[^;&|\n]*(\s-[A-Za-z]*f\b|--force|--discard-changes|\s--(\s|$)|\s\.(\s|$))"
    r"|restore\b(?![^;&|\n]*(--staged|\s-S\b))"
    r"|rm\b(?![^;&|\n]*\s--cached\b)\s+[^;&|\n]*(-[A-Za-z]*f\b|--force)|rebase\b(?!\s+--(abort|continue|skip|quit))"
    r"|switch\s+[^;&|\n]*-C\b|checkout\s+[^;&|\n]*-B\b"
    r"|push\s+[^;&|\n]*(\s-[A-Za-z]*[fd]\b|--force|--delete|--mirror|--prune|\s[+:][^\s])"
    r"|stash\s+(drop|clear)|reflog\s+(expire|delete)|gc\s+[^;&|\n]*--prune|update-ref\s+[^;&|\n]*-d\b"
    r"|filter-branch|filter-repo"
    r"|(commit|push|merge)\s+[^;&|\n]*--no-verify|commit\s+(?:[^;&|\n]*\s)?-[A-Za-z]*n\b"
    r"|-c\s*core\.hooks[pP]ath)")

SUBST = "__DEVKIT_SUBST__"
PSUBST = SUBST + "IN__"   # an unquoted <(…): a file that reads what its command prints (contains SUBST: every SUBST test holds)

HEREDOC = re.compile(r"<<-?[ \t]*([\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")

def skip_heredoc(text, j):
    """At `<<DELIM` in text[j:]: index just past the closing DELIM line of the body; None if there is none."""
    m = HEREDOC.match(text.replace("\x27", "\x22"), j)
    nl = text.find("\n", m.end()) if m else -1
    if nl < 0:
        return None
    end = re.compile(r"^[ \t]*" + re.escape(m.group(2)) + r"[ \t]*$", re.M).search(text, nl + 1)
    return end.end() if end else None

def subst_end(text, i):
    """text[i:i+2] opens $( / <( / >(: index just past its closing paren; None when unbalanced.
    Quotes and heredoc bodies inside it do not count their parentheses."""
    depth, j, n = 1, i + 2, len(text)
    while j < n and depth:
        c = text[j]
        if c == "\\":
            j += 2
            continue
        if c in "\x27\x22":
            k = j + 1
            while k < n and text[k] != c:
                k += 2 if (c == "\x22" and text[k] == "\\") else 1
            if k >= n:
                return None
            j = k + 1
            continue
        if text.startswith("<<", j) and not text.startswith("<<<", j):
            k = skip_heredoc(text, j)
            if k is not None:
                j = k
                continue
        depth += {"(": 1, ")": -1}.get(c, 0)
        j += 1
    return None if depth else j

def strip_subst(text, inners=None, outs=None):
    """Each $(...), <(...), >(...) and backtick span becomes one SUBST word; single-quoted text stays
    literal. None when a span is not closed. The text inside each span (a command the shell runs) is
    appended to inners, and that of each unquoted >(...) to outs too. It reads a text whose comments
    are already gone (drop_comments, 15/10 r6): a # here is data."""
    out, i, n, dq = [], 0, len(text), False
    while i < n:
        c = text[i]
        if c == "\\":
            out.append(text[i:i + 2])
            i += 2
        elif c == "\x27" and not dq:
            k = text.find("\x27", i + 1)
            if k < 0:
                return None
            out.append(text[i:k + 1])
            i = k + 1
        elif c == "\x22":
            dq = not dq
            out.append(c)
            i += 1
        elif c in "$<>" and text.startswith("(", i + 1):
            j = subst_end(text, i)
            if j is None:
                return None
            if inners is not None:
                inners.append(text[i + 2:j - 1])
            if outs is not None and c == ">" and not dq:
                outs.append(text[i + 2:j - 1])
            out.append(PSUBST if c == "<" and not dq else SUBST)
            i = j
        elif c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                return None
            if inners is not None:
                inners.append(text[i + 1:j])
            out.append(SUBST)
            i = j + 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)

SOLO_WORDS = re.compile(r"\bgit\b[^\n]*?\b(push|checkout|switch|branch|worktree)\b")

# Heredocs (2026-10-14, W3; policy of 15/10 after three review rounds): shell_norm.heredocs finds them. A body is cut only when the whole
# command is made of constructs shell_norm models (cut_ok) AND it is the message of a known option (git commit -m, gh pr create --body …)
# or the one statement of the command (cat > notes.md <<EOF, git commit -F -); every other body stays and is judged as shell lines, quoted
# or not. A body an interpreter reads as its program (python3 - <<EOF, cat <<EOF | node -) is judged as source first (interp_body_danger
# below, on the raw text), then cut when cut_ok. An unquoted body that holds a $ or a backtick is never cut (the shell runs its $( ) at once).
# A heredoc with no delimiter line is never cut (fail closed). NO single quote in this comment: the python source is one bash string.
# A program that can start a process is never cut (15/10 r4): ruby, perl and php run a backtick as a command, and the branch, worktree and hooks-off
# rules read it like any other line; interp_body_danger below judges only RAW and the git words of its literals. Nor is a program whose OUTPUT is
# taken (15/10 r5: $( ), a redirect, a pipe): the shell runs what it prints (shell_norm.program_cut).
def heredoc_cut(h, text):
    return h.kind == "data" or shell_norm.program_cut(h, text)

# A heredoc an interpreter reads as its PROGRAM is source code, not shell lines (2026-10-13): the -c rule applies to it (RAW, then
# the git words of its string literals), but only when the body can start a process — a body that merely holds git commands as
# data (a table of test cases) stays allowed (shell_norm.spawns; in ruby, perl and php a backtick runs a command too) — or when its output is
# captured (h.captured, 15/10 r5): a program that only prints the command line a shell then runs is a command source too.
def interp_body_danger(body, prog, captured=False):
    """The reason the program an interpreter reads from a heredoc runs a dangerous git command, or None."""
    reason = pm_env_in_code(body)   # (audit T0066 vòng 3) trước spawns: os.environ[…] rồi import push_gate không sinh tiến trình
    if reason:
        return reason
    if not (captured or shell_norm.spawns(body, prog)):
        return None
    reason = gh_in_literals(body, CUR_DIR[0])   # (#605) chương trình heredoc gọi gh đăng comment tự duyệt
    if reason:
        return reason
    hit = RAW.search(body)
    reason = f"{hit.group(1).split()[0]}" if hit else git_in_literals(body)
    return f"{reason} (chương trình {prog} đọc từ heredoc)" if reason else None

def outside_single_quotes(text):
    """The text with single-quoted spans removed: a backtick or $( there is literal, never run
    (a grep pattern was blocked, 2026-09-28). An executed quoted string (bash -c, eval) is
    analysed again on its own. An unclosed quote keeps everything (fail closed)."""
    out, i, n, dq = [], 0, len(text), False
    while i < n:
        c = text[i]
        if c == "\\":
            out.append(text[i:i + 2])
            i += 2
        elif c == "\x27" and not dq:
            k = text.find("\x27", i + 1)
            if k < 0:
                return text
            i = k + 1
        else:
            dq = (not dq) if c == "\x22" else dq
            out.append(c)
            i += 1
    return "".join(out)

drop_comments = shell_norm.drop_comments   # one copy for both guards (issue #7)

# ── Text fed to a shell on stdin (2026-10-09, tests/gates/test_git_guard_shell_feed.sh) ──────────────────────────────
# `echo STR | bash`, `bash <<< STR`, `… | xargs sh -c`: the shell runs what it reads, so it is analysed like a -c string when
# the producer is a literal (echo / printf / cat with a here-doc or here-string; a here-doc body is analysed where it
# stands in the command). Text a command GENERATES (cat FILE, curl, base64 -d, a $… word) cannot be read here: the
# command is then blocked with UNREADABLE_FEED, unless something else in it blocks first.
UNREADABLE_FEED = ("shell chạy văn bản do lệnh khác sinh ra (pipe / here-string vào sh, bash, xargs sh -c): cổng không "
                   "đọc được nội dung — chỉ echo / printf / cat <<heredoc literal được phân tích; chạy thẳng lệnh đó")
PENDING_FEED = []   # an unreadable feed: the verdict when nothing else in the command blocks
IN_C_SCRIPT = [0]   # depth of bash -c scripts being analysed
IN_XARGS = [0]      # (#536) depth of xargs commands being analysed
ESCAPE = re.compile(r"\\(x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{4}|0?[0-7]{1,3}|.)", re.S)
ESCAPE_CHARS = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "e": "\x1b", "\\": "\\"}
PRINTF_SPEC = re.compile(r"%(?:%|[-+ #0]*\d*(?:\.\d+)?([a-zA-Z]))")

def unescape(s):
    """The escapes printf, echo -e and zsh echo turn into characters: \\x67 is g."""
    def one(m):
        e = m.group(1)
        if e[0] in "xu" and len(e) > 1:
            return chr(int(e[1:], 16))
        if e[0] in "01234567":
            return chr(int(e, 8) & 0xFF)
        return ESCAPE_CHARS.get(e, "\\" + e)
    return ESCAPE.sub(one, s)

def literal_word(w):
    """No $var, $(…) or backtick left in the word: its text is what the command line says."""
    return "$" not in w and "`" not in w and SUBST not in w

def printf_text(args):
    """What `printf FMT ARG…` prints, close enough to scan: FMT escapes, %s / %b filled from the ARGs, FMT reused."""
    args = args[1:] if args[:1] == ["--"] else args
    if not args:
        return ""
    fmt, vals, pos, out = unescape(args[0]), args[1:], [0], []
    def fill(m):
        if m.group(0) == "%%":
            return "%"
        v = vals[pos[0]] if pos[0] < len(vals) else ""
        pos[0] += 1
        return unescape(v) if m.group(1) == "b" else v
    while len(out) < 64:
        start = pos[0]
        out.append(PRINTF_SPEC.sub(fill, fmt))
        if pos[0] == start or pos[0] >= len(vals):
            break
    return "".join(out)

def prog_index(seg):
    """Index of the program word of a simple command: after NAME=…, keywords, a redirect, env (and its options) and wrappers."""
    return shell_norm.prefix_end(seg)

def reads_script(seg):
    """A shell that runs what arrives on its stdin (no -c, no script operand, or -s / a lone -, stdin not redirected), or
    xargs running a shell (the piped words become its command line)."""
    i = prog_index(seg)
    if i >= len(seg):
        return False
    prog, rest = seg[i].rsplit("/", 1)[-1], seg[i + 1:]
    if prog == "xargs":
        j = 0
        while j < len(rest) and rest[j].startswith("-"):
            j += 2 if rest[j] in ("-I", "-n", "-P", "-L", "-d", "-E", "-s", "-a") else 1
        k = j + prog_index(rest[j:])
        return k < len(rest) and rest[k].rsplit("/", 1)[-1] in SHELLS
    if prog not in SHELLS:
        return False
    j, s_flag = 0, False
    while j < len(rest):
        a = rest[j]
        if a.startswith("<"):
            return False             # < FILE / <<X / <<< STR: stdin is not the pipe (a here-string is checked on its own)
        if REDIRECT.match(a):
            j += 2 if re.fullmatch(r"\d*(>>?|<|&>)", a) else 1
            continue
        if a == "--":
            j += 1
            break
        if len(a) > 1 and a[0] in "-+":
            short = a[0] == "-" and not a.startswith("--")
            if short and "c" in a[1:]:
                return False         # -c STR: analysed as a command string
            s_flag = s_flag or (short and "s" in a[1:])
            j += 2 if a in SHELL_OPTS_WITH_ARG else 1
            continue
        break
    return s_flag or j >= len(rest) or rest[j] == "-"

# A shell fed by process substitution (2026-10-09, tests/gates/test_git_guard_process_subst.sh): `bash <(curl …)` runs the
# text <(…) prints as its script, `bash < <(…)` reads it on stdin — generated text, refused like UNREADABLE_FEED. Not
# `diff <(a) <(b)` (no shell), `bash x.sh <(…)` (an argument), `eval "$(…)"`, `bash x.sh`, `bash < file` (documented limits).
UNREADABLE_PSUBST = ("shell chạy văn bản do process substitution sinh ra (bash <(…), bash < <(…)): cổng không đọc được "
                     "nội dung — chạy thẳng lệnh đó")
# `bash -c "$(curl …)"` and `… | tee >(sh)` (2026-10-09, tests/gates/test_git_guard_shell_subst.sh) run the same generated text: -c with
# a command substitution as its script, and a shell inside an output process substitution reading what tee writes to it. Still
# allowed (documented limits): `eval "$(…)"`, `source <(…)`, `. <(…)`, `bash x.sh`, `bash < file`, `bash -c "echo $(date)"`.
UNREADABLE_CSUBST = ("shell -c chạy văn bản do $(…) sinh ra (bash -c \"$(curl …)\"): cổng không đọc được nội dung — "
                     "chạy thẳng lệnh đó")
UNREADABLE_OSUBST = ("shell trong >(…) đọc văn bản do lệnh khác ghi vào (… | tee >(sh)): cổng không đọc được nội dung — "
                     "chạy thẳng lệnh đó")

def out_subst_shell(inner):
    """True when a command inside >(…) is a shell that runs what is written to it (no -c, no script operand, or -s / a lone -)."""
    for part in re.split(r"[;&|\n]+", inner):
        try:
            words = shlex.split(part)
        except ValueError:
            continue
        if words and reads_script(words):
            return True
    return False

def proc_subst_script(rest):
    """rest: the words after a shell (no -c, no <<<). True when its script is a <(…): the script operand, or stdin with no
    script operand (or -s / a lone -)."""
    j, s_flag, stdin_ps, script, opts = 0, False, False, None, True
    while j < len(rest):
        a = rest[j]
        if REDIRECT.match(a):
            two = bool(re.fullmatch(r"\d*(>>?|<|&>)", a))
            src = rest[j + 1] if two and j + 1 < len(rest) else a
            stdin_ps = stdin_ps or (re.match(r"0?<(?![<&])", a) is not None and PSUBST in src)
            j += 2 if two else 1
            continue
        if opts and a == "--":
            opts = False
        elif opts and len(a) > 1 and a[0] in "-+":
            s_flag = s_flag or (a[0] == "-" and not a.startswith("--") and "s" in a[1:])
            j += 2 if a in SHELL_OPTS_WITH_ARG else 1
            continue
        elif script is None:
            script, opts = a, False
        j += 1
    if script is not None and script != "-" and not s_flag:
        return PSUBST in script
    return stdin_ps

def feed_texts(seg):
    """Readings of what a literal producer writes to the pipe (each analysed), or None when it is not a literal."""
    i = prog_index(seg)
    if i >= len(seg):
        return None
    prog, args = seg[i].rsplit("/", 1)[-1], seg[i + 1:]
    if prog == "cat":
        texts, here, k = [], False, 0
        while k < len(args):
            a = args[k]
            if a.startswith("<<"):
                here = True
                w = a[3:] if a.startswith("<<<") else ""
                if a in ("<<", "<<-", "<<<"):
                    w = args[k + 1] if k + 1 < len(args) else ""
                    k += 1
                if a.startswith("<<<"):
                    if not literal_word(w):
                        return None
                    texts.append(w)
            elif REDIRECT.match(a):
                k += 1 if re.fullmatch(r"\d*(>>?|<|&>)", a) else 0
            elif a != "-" and not a.startswith("-"):
                return None          # cat FILE: what it prints is not in the command
            k += 1
        return texts if here else None
    if prog not in ("echo", "printf"):
        return None
    args = drop_redirects(args)
    if not all(literal_word(a) for a in args):
        return None
    if prog == "printf":
        return [printf_text(args), "\n".join(unescape(a) for a in args)]
    while args and re.fullmatch(r"-[neE]+", args[0]):
        args = args[1:]
    text = " ".join(args)
    return [text, unescape(text)]

def judge_feed(producer, depth):
    """producer piped into a shell: the reason its text is dangerous, None; an unreadable producer is noted in PENDING_FEED."""
    texts = feed_texts(producer) if producer else None
    if texts is None:
        PENDING_FEED.append(UNREADABLE_FEED)
        return None
    for t in texts:
        here = CUR_DIR[0]   # the fed shell is its own process: a cd in it does not move this command
        reason = analyse(t, depth + 1) if t.strip() else None
        CUR_DIR[0] = here
        if reason:
            return reason
    return None

def crude_words(line):
    """The words of a line that lex_words cannot read: quotes and backslashes dropped (as the hardware gate reads a text it cannot parse), the
    shell separators kept as words of their own. It cannot fail, so a quote left open by prose never turns a rule off."""
    return re.findall(r"[;&|()]+|[^\s;&|()]+", re.sub(r"[\\\x27\x22]", "", line))

def scan_words(pre, depth, opened=False):
    """The verdict of one reading of a command text (shell_norm.readings): its words, segment by segment (analyse_simple), and the text a literal producer
    feeds to a shell (judge_feed). opened: a heredoc body that stays in the scan had a line with a quote it does not close (shell_norm.scan_text, 15/10 r6):
    the text is read as one that does not parse, whatever the lexer would make of it."""
    try:
        if opened:
            raise ValueError("a body line with an open quote")
        tokens = shell_norm.lex_words(pre)
    except ValueError:
        # an unbalanced quote or a trailing backslash (a prose body that stays in the scan: dont, 5" screen): RAW first, then each line alone and
        # a line that still does not parse word by word with its quotes dropped. Every rule stays on; it used to be RAW only (15/10 r4)
        m = RAW.search(pre.replace("\n", " ; "))
        if m:
            return f"{m.group(1).split()[0]} (lệnh không phân tích được)"
        tokens = []
        for line in pre.split("\n"):
            try:
                tokens += shell_norm.lex_words(line)
            except ValueError:
                tokens += crude_words(line)
            tokens.append(";")
    segment = []
    dirs = []
    data_groups = []   # one flag per open paren: NAME=( ... ) and (( ... )) hold data, so a substitution there is no command word
    feed = None   # after a pipe: the producer segment ([] = a ( … ) / { … } group, not one literal command)
    for tok in tokens + [";"]:
        if shell_norm.join_fd_dup(segment, tok):   # 2>&1 git …: the & belongs to the redirect
            continue
        if tok in SEPARATORS or set(tok) <= set(";&|\n()"):
            opens_data = tok.startswith("(") and bool(segment) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=", segment[-1]) is not None
            if segment:
                saved_c = IN_C_SCRIPT[0]
                if any(data_groups):
                    IN_C_SCRIPT[0] = 0
                try:
                    reason = analyse_simple(segment, depth)
                finally:
                    IN_C_SCRIPT[0] = saved_c
                if reason:
                    return reason
                if feed is not None and reads_script(segment):
                    reason = judge_feed(feed, depth)
                    if reason:
                        return reason
            if "|" in tok and "||" not in tok:
                feed = segment if segment and ")" not in tok.split("|", 1)[0] else []
            elif tok not in ("(", "{"):
                feed = None   # `a | ( sh )` / `a | { sh; }`: the pipe reaches the first command of the group
            segment = []
            for ch in tok:
                if ch == "(":
                    dirs.append(CUR_DIR[0])
                    data_groups.append(opens_data or tok.count("(") > 1)
                elif ch == ")":
                    if data_groups:
                        data_groups.pop()
                    if dirs:
                        CUR_DIR[0] = dirs.pop()
        else:
            segment.append(tok)
    return None

def analyse_free(text, depth):
    """analyse() of text that is not the script of the enclosing bash -c itself (an eval operand, an ssh or watch command, the body of an
    arithmetic expansion): a command substitution there is ordinary, only the script own command word is judged."""
    saved = IN_C_SCRIPT[0]
    IN_C_SCRIPT[0] = 0
    try:
        return analyse(text, depth)
    finally:
        IN_C_SCRIPT[0] = saved

def analyse(text, depth=0, stripped=False, opened=False):
    if depth > 5:
        return "lồng lệnh quá sâu để phân tích"
    if not stripped and "<<" in text:   # every level: a bash -c / eval string holds heredocs of its own
        docs = shell_norm.heredocs(text)
        for h in docs:
            if h.kind in ("interp", "source"):   # a program an interpreter reads, or a script written to a file (no delimiter line: the rest of the text, 15/10 r4)
                reason = interp_body_danger(h.body(text), h.reader, h.captured)
                if reason:
                    return reason
        # a body that stays is not quote-scoped (15/10 r6): the quote characters of its lines that do not close them are dropped before every quote scanner below
        # (outside_single_quotes, strip_subst, drop_comments, the lexer), or they pair with a quote of another body and hide the command between them
        text, opened = shell_norm.scan_text(text, lambda h: heredoc_cut(h, text), docs)
    # Comments are gone before the two quote scanners below (15/10 r6, marker runs): an apostrophe in a comment paired with a later quote and hid a "$( )" between
    # them, and a # after a backslash-newline or inside ${ } read as a comment dropped the command substitution after it. drop_comments is the one model of what a
    # comment is (escape, ${ }, backticks); strip_subst has none of its own any more.
    nc = text if stripped else drop_comments(text)
    live = outside_single_quotes(nc) + outside_single_quotes(text)   # a substitution in either reading enters the branch (RAW reads the text as typed: a pinned false positive)
    if not stripped and ("`" in live or "$(" in live or "<(" in live or ">(" in live):
        for flat in shell_norm.readings(text):   # joined, and as typed: a backslash-newline inside single quotes is literal there (15/10 r5)
            m = RAW.search(flat.replace("\n", " ; "))
            if m:
                return f"{m.group(1).split()[0]} (trong lệnh có $(...)/backtick)"
        # 2026-09-28: the command inside $(...)/backticks gets the same parser as a top-level one
        # (the raw regex above knows no abbreviation: `echo $(git reset --har HEAD~1)` passed).
        inners, outs = [], []
        plain = strip_subst(nc, inners, outs)
        if plain is not None:
            if any(out_subst_shell(o) for o in outs):
                PENDING_FEED.append(UNREADABLE_OSUBST)
            for inner in inners:
                here = CUR_DIR[0]   # a cd inside $(...) runs in a subshell
                arith = inner.startswith("(") and subst_end("$" + inner, 0) == len(inner) + 1   # only $(( … )) is data: its first paren closes at the very end
                reason = (analyse_free if arith else analyse)(inner, depth + 1)   # $((:); $(cmd)) is a subshell, a plain $( … ) runs in the -c shell
                CUR_DIR[0] = here
                if reason:
                    return reason
            return analyse(plain, depth + 1, True, opened)
        if SOLO_WORDS.search(text):  # an unclosed $( / backtick hides the rest: fail closed
            SOLO_HIT.append("lệnh có $( hoặc backtick không đóng, không kiểm được push/nhánh trong đó; tách lệnh git ra riêng")
            return SOLO_HIT[-1]
        # no return here (15/10 r4): an unclosed span (a lone backtick or $( in a prose body that stays in the scan) used to END the analysis, which
        # turned off every rule that RAW and SOLO_WORDS lack (DEVKIT_PRECOMMIT=0 git commit …). The text goes on to the word-by-word reading below.
    # Each reading of the text (shell_norm.readings) is read from where the command started; the verdicts are added: blocked when ANY blocks. The state a
    # reader leaves behind (the directory after a cd) is the first reading, as before the second one existed.
    start_dir = first_dir = CUR_DIR[0]
    for n, pre in enumerate(shell_norm.readings(drop_comments(text))):
        CUR_DIR[0] = start_dir if n else CUR_DIR[0]
        reason = scan_words(pre, depth, opened)
        if reason:
            return reason
        first_dir = CUR_DIR[0] if n == 0 else first_dir
    CUR_DIR[0] = first_dir
    return None

# Only a cd BEFORE the last restore can move the paths it resolves (GeelyEx2 2026-09-27:
# "restore -- f && cd CarConnect && ./gradlew ..." was blocked). A loop, function, eval or
# xargs can re-run the restore after a later cd: then every cd counts.
_rs = [m.start() for m in re.finditer(r"\brestore\b", cmd)]
_upto = len(cmd) if not _rs or re.search(r"\b(do|done|eval|xargs|function)\b|\(\)\s*\{", cmd) else _rs[-1]
CHANGES_DIR.extend(t for t in re.findall(r"(?:^|[;&|(\s])(cd|pushd)\s", cmd[:_upto]))
# (RETARGETED is set from the parsed tokens in analyse_simple: a regex over the raw text was beaten by GIT_""DIR.)
reason = analyse(cmd) or (PENDING_FEED[0] if PENDING_FEED else None)
if not reason and not do_backups():
    reason = "không sao lưu được file trước khi restore"
if reason and reason.startswith("push") and "agent-kit integrate" in reason:
    # #472 mục A: push_gate đã nói đúng lối ra (integrate); lời "1 dev, 1 nhánh" bên dưới bảo `git push origin <nhánh>`, trái với nó
    print(f"BLOCKED: {cmd!r} — {reason}.", file=sys.stderr)
    sys.exit(2)
if reason and any(reason.startswith(h) for h in SOLO_HIT):
    print(f"BLOCKED: {cmd!r} — {reason}. Luật \"1 dev, 1 nhánh\" (DevKit): làm thẳng trên nhánh hiện tại. "
          "Đưa code lên remote: merge/ff vào nhánh local bằng một lệnh riêng (kiểm exit code), rồi "
          "`git push origin <nhánh>`; không push `<sha>:<nhánh>` mà local chưa chứa. Nhánh/worktree mới chỉ khi "
          "User yêu cầu: chạy lại với DEVKIT_ALLOW_BRANCH=1 trước lệnh git. Ngoại lệ đã duyệt sẵn: checkout đang bị phiên khác giữ "
          "-> TỰ chạy `agent-kit worktree add ../<repo>-<việc>` (không phải git worktree add), xong `agent-kit worktree finish <đường dẫn>`.", file=sys.stderr)
    sys.exit(2)
if reason and reason.startswith(PROTECTED_DELETE_MSG):
    print(f"BLOCKED: {cmd!r} — {reason}. Luật chủ repo (#605): xoá file quan trọng chỉ do NGƯỜI làm hoặc duyệt — agent không tự xoá. "
          "Hỏi người dùng một lần (AskUserQuestion); người dùng tự chạy qua prefix \"!\" nếu đồng ý. Danh sách: mặc định của hook + "
          "khoá \"protected_delete\" trong .antigravity-pm.json. Xoá file khác vẫn tự làm, không cần hỏi.", file=sys.stderr)
    sys.exit(2)
if reason and reason.startswith(SELF_APPROVE_MSG):
    print(f"BLOCKED: {cmd!r} — {reason}. Luật #605: `approved-head:<sha>` trơn (không kèm dòng `approved-by:`) và `done` chỉ người "
          "chủ repo gõ tay — agent đăng bằng chung tài khoản OWNER nên đăng chúng là tự duyệt. Lane reviewer: đăng `approved-head:<sha>` "
          "kèm dòng `approved-by: {\"reviewer\",\"builder\",\"task_id\",\"gate_receipt\"}` (reviewer khác builder), hoặc "
          "`cross-review-approved: {...}`.", file=sys.stderr)
    sys.exit(2)
if reason and reason.startswith(MQ_MSG):
    print(f"BLOCKED: {cmd!r} — {reason}. Luật #536: nhãn merge-queue chỉ gắn cho PR đã được lane Review duyệt đúng head "
          "(approved-head:<sha40> + approved-by, audit Antigravity pass) — gắn qua .claude/bin/super-board-queue-label.sh <pr> sau khi duyệt.",
          file=sys.stderr)
    sys.exit(2)
if reason and reason.startswith(PM_STATE_MSG):
    print(f"BLOCKED: {cmd!r} — {reason}. Luật #605: biên bản audit antigravity-pm chỉ do PM server ghi ở ~/.antigravity-pm; ANTIGRAVITY_PM_STATE_HOME / DEVKIT_PM_HOME_TEST "
          "chỉ test tự đặt bên trong script của nó. Chạy lệnh không kèm biến; chạy test thì gọi thẳng script test.", file=sys.stderr)
    sys.exit(2)
if reason and reason.startswith("kill theo tên"):
    print(f"BLOCKED: {cmd!r} — {reason}. Chạy lệnh nền rồi giữ PID của chính nó: `cmd & pid=$!`, sau đó `wait $pid` / `kill -0 $pid` / "
          "`kill $pid`. Nếu thực sự cần, User sẽ tự chạy qua prefix \"!\".", file=sys.stderr)
    sys.exit(2)
if reason:
    # K2/K4 (18/10): ba lệnh kit tự chứng minh không mất gì rồi mới làm đúng việc này; dạng git trần vẫn bị chặn ở đây
    kit = ("agent-kit worktree prune-branch <nhánh> (chỉ xoá khi trunk đã có nó hoặc PR đã MERGED vào trunk đúng tip)" if reason.startswith("branch -D")
           else "agent-kit worktree prune-branch --remote <nhánh> (chỉ xoá nhánh trên origin khi PR đã MERGED vào trunk đúng tip của nó)"
           if reason.startswith("push") and re.search(r"(\s--delete\b|\s-[A-Za-z]*d[A-Za-z]*\b|\s:\S)", cmd)
           else "agent-kit worktree discard <đường dẫn> (chỉ còn file đã xoá / rác IDE, HEAD đã trong trunk, không phiên sống nào giữ)"
           if reason.startswith("worktree remove --force")
           else "agent-kit worktree restore <commit> -- <path> (chỉ path không có thay đổi chưa commit, không file ignore nào nằm đường)"
           if (reason.startswith("checkout") and ("<tree-ish>" in reason or re.search(r"\bcheckout\s+[^-\s]\S*\s+--\s+\S", cmd)))
           or (reason.startswith("restore") and re.search(r"\s(?:--source\b|-[A-Za-z]*s)", cmd))
           else None)   # (checkout -- <path> không kèm commit chỉ đáng chặn khi path bẩn: restore luôn từ chối ca đó)
    print(f"BLOCKED: {cmd!r} — {reason}. User đã chặn thao tác git khó revert này. "
          + (f"Không mất gì thì dùng `{kit}`; còn không: " if kit else "")
          + "Nếu thực sự cần, User sẽ tự chạy qua prefix \"!\".", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
' "$0"
rc=$?
case "${rc}" in 0|2) exit "${rc}" ;; esac
echo "BLOCKED: block-dangerous-git.sh: python không chạy được (rc ${rc}). Chặn để an toàn (người dùng tự chạy lệnh qua prefix ! nếu đây là lỗi của cổng)." >&2
exit 2
