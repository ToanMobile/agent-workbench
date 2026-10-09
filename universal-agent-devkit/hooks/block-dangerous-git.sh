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
  c="${c//\\/}"; c="${c//\'/}"; c="${c//\"/}"
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
fast_allow 'git|eval|devkit_precommit|hookspath|[|]([^|]*[^[:alnum:]_.-])?(ba|z|da|k|fi)?sh([^[:alnum:]_.-]|$)|<<<|<[(]|>[(]' && exit 0

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
import fnmatch, json, re, shlex, shutil, subprocess, time

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
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "!", "{", "}", "time"}
# wrapper -> (options that take a separate value, number of positional args before the command)
WRAPPERS = {
    "command": (set(), 0), "builtin": (set(), 0), "exec": ({"-a"}, 0), "nohup": (set(), 0),
    "time": (set(), 0), "caffeinate": ({"-t", "-w"}, 0), "setsid": (set(), 0), "unbuffer": (set(), 0),
    "sudo": ({"-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"}, 0),
    "doas": ({"-u", "-C"}, 0),
    "nice": ({"-n"}, 0),
    "ionice": ({"-c", "-n", "-p"}, 0),
    "stdbuf": ({"-i", "-o", "-e"}, 0),
    "timeout": ({"-s", "-k", "--signal", "--kill-after"}, 1),
    "chrt": (set(), 1),
    "taskset": (set(), 1),
    "flock": ({"-w", "-E", "--timeout"}, 1),
}
INTERPRETERS = {"python", "python2", "python3", "node", "perl", "ruby", "php", "deno", "bun"}
# awk runs commands with system() and `print … | "sh"`: the string literals of its program are checked (2026-10-09).
AWKS = {"awk", "gawk", "mawk", "nawk"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
SHELL_OPTS_WITH_ARG = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file"}
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

def danger_in_git(sub, args):
    args = expand_abbrev(sub, args)
    long_ = set(a.split("=", 1)[0] for a in args if a.startswith("--"))
    short = short_flags(args)
    pos = [a for a in args if not a.startswith("-")]
    if sub == "reset" and long_ & {"--hard", "--merge", "--keep"}:
        return "reset --hard/--merge/--keep vứt thay đổi"
    if sub == "clean" and ("f" in short or "--force" in long_):
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
    if sub == "rm" and ("f" in short or "--force" in long_):
        return "rm --force xoá file kèm thay đổi chưa commit"
    if sub == "rebase" and not long_ & {"--abort", "--continue", "--skip", "--quit", "--show-current-patch", "--edit-todo"}:
        return "rebase viết lại lịch sử branch"
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
    return None

def skip_wrapper(tokens, i, prog):
    opts_arg, npos = WRAPPERS[prog]
    i += 1
    while i < len(tokens) and tokens[i].startswith("-") and tokens[i] != "--":
        opt = tokens[i].split("=", 1)[0]
        i += 2 if (opt in opts_arg and "=" not in tokens[i]) else 1
    if i < len(tokens) and tokens[i] == "--":
        i += 1
    if prog == "nice" and i < len(tokens) and re.match(r"^-?\d+$", tokens[i]):
        i += 1
    return i + npos

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

def env_config_danger(assigns):
    """NAME=VAL assignments (command prefix, env, export) that configure git: GIT_CONFIG_PARAMETERS
    and GIT_CONFIG_KEY_n/VALUE_n pairs go through config_danger; a config FILE named by
    GIT_CONFIG_GLOBAL/SYSTEM cannot be read safely here, so only /dev/null passes."""
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

REDIRECT = re.compile(r"^\d*(>>?|<|&>)")

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
    revs = []   # (rev, is a plain tag push) per refspec (one push may name several); none → HEAD
    unresolved = False
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
        revs.append(("refs/tags/" + tag_name(spec) if is_tag else s, is_tag))   # the full ref: never a pseudoref
    if unresolved:
        revs = [(r, False) for r, _ in revs]
    # --repo=<name> names it; otherwise the first positional; otherwise the default remote git would use
    remote = repo_opt or (vals[0] if vals else default_push_remote(gdir))
    sweeps = ([["--all-branches", remote]] if all_branches else []) + ([["--all-tags", remote]] if all_tags else [])
    if not revs and not sweeps:
        revs = [("HEAD", False)]
    here = os.path.dirname(os.path.realpath(sys.argv[1])) if len(sys.argv) > 1 else ""
    tool = os.path.join(os.path.dirname(here), "bin", "push_gate.py")
    if not gdir or not os.path.isdir(gdir) or not os.path.isfile(tool):
        return "push: không kiểm được biên nhận gate (thư mục repo hoặc bin/push_gate.py không xác định)"
    jobs = [[rev] + (["--tag-remote", remote] if is_tag else []) for rev, is_tag in revs] + sweeps
    for job in jobs:
        try:
            r = subprocess.run([sys.executable, tool, gdir] + job, stdin=subprocess.DEVNULL,
                               capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError) as e:
            return f"push: không kiểm được biên nhận gate ({e})"
        if r.returncode != 0:
            return f"push {job[0]} chưa qua gate: " + ((r.stdout or r.stderr).strip() or f"push_gate exit {r.returncode}")
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

def git_in_literals(code):
    """python -c / node -e source: its string literals, split into words, as git would get them
    ([\x27git\x27,\x27push\x27,\x27--force\x27] or \x27git reset --har HEAD\x27). The word after `git` and its
    global options is the subcommand; the words after it go through danger_in_git (abbreviations
    included). Only danger_in_git: a literal that merely names a new branch is not blocked."""
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
            if reason:
                return reason
    return None

def analyse_simple(tokens, depth):
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
                i += 2 if tokens[i] in ("-u", "-C", "-S") else 1
        elif prog in WRAPPERS:
            i = skip_wrapper(tokens, i, prog)
        elif tokens[i] in KEYWORDS:
            i += 1
        else:
            break
    if i < len(tokens) and tokens[i] in ("export", "declare", "typeset"):
        assigns.update(a.split("=", 1) for a in tokens[i + 1:] if "=" in a and not a.startswith("-"))
    if RETARGET_ENV & set(assigns):
        RETARGETED[0] = True
    reason = env_config_danger(assigns) if assigns else None
    if reason:
        return reason
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
    # `$g reset --hard` / `${GIT} clean -f`: a variable in command position may be git. So may a $(…) / backtick there
    # (`$(echo gi)t reset --hard`, 2026-10-09): its output is the program name.
    if prog.startswith("$") or SUBST in prog:
        if IN_C_SCRIPT[0] and SUBST in prog:
            PENDING_FEED.append(UNREADABLE_CSUBST)   # bash -c "( $(curl ...) )", "if $(...)", "exec $(...)": the command word is generated text
        return danger_in_git(rest[0], rest[1:]) if rest else None
    if prog in AWKS:
        reason = git_in_literals(" ".join(rest))
        return f"{reason} (gọi qua {prog})" if reason else None
    if prog in INTERPRETERS:
        for j, a in enumerate(rest):
            if a in ("-c", "-e", "--eval", "-E", "-r") and j + 1 < len(rest):
                m = RAW.search(rest[j + 1])
                if m:
                    return f"{m.group(1).split()[0]} (gọi qua {prog} {a})"
                reason = git_in_literals(rest[j + 1])
                return f"{reason} (gọi qua {prog} {a})" if reason else None
        return None
    if prog == "watch":
        j = 0
        while j < len(rest) and rest[j].startswith("-"):
            j += 2 if rest[j] in ("-n", "-d", "--interval") else 1
        return analyse_free(" ".join(rest[j:]), depth + 1) if j < len(rest) else None
    if prog == "find":
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
    if prog in SHELLS or prog == "eval":
        if prog == "eval":
            return analyse_free(" ".join(rest), depth + 1)
        for j, a in enumerate(rest):
            if a == "-c" or (a.startswith("-") and not a.startswith("--") and "c" in a[1:]):
                # Options may follow -c: the command is the first operand (`bash -c -- STR`, `bash -c -e STR`; 2026-10-09
                # the `--` was analysed instead of STR).
                k = j + 1
                while k < len(rest) and rest[k] != "--" and len(rest[k]) > 1 and rest[k][0] in "-+":
                    k += 2 if rest[k] in SHELL_OPTS_WITH_ARG else 1
                k += 1 if k < len(rest) and rest[k] == "--" else 0
                if k >= len(rest):
                    return None
                IN_C_SCRIPT[0] += 1   # inside the script: a command word made by a command substitution is refused (analyse_simple)
                try:
                    return analyse(rest[k], depth + 1)
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
    if prog == "ssh":
        j = 0
        while j < len(rest) and rest[j].startswith("-"):
            j += 2 if rest[j] in ("-p", "-i", "-l", "-o", "-F", "-J", "-L", "-R", "-D") else 1
        return analyse_free(" ".join(rest[j + 1:]), depth + 1) if j + 1 < len(rest) else None
    if prog == "xargs":
        j = 0
        while j < len(rest) and rest[j].startswith("-"):
            j += 2 if rest[j] in ("-I", "-n", "-P", "-L", "-d", "-E", "-s") else 1
        return analyse_simple(rest[j:], depth + 1)
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
    return danger_in_git(rest[j], rest[j + 1:]) or solo_branch_rule(rest[j], rest[j + 1:], gdir, allow_branch)

RAW = re.compile(
    r"\bgit\b[^;&|\n]*?\s(reset\s+[^;&|\n]*--(hard|merge|keep)"
    r"|clean\s+[^;&|\n]*(-[A-Za-z]*f|--force)"
    r"|branch\s+[^;&|\n]*-D"
    r"|(checkout|switch)\s+[^;&|\n]*(\s-[A-Za-z]*f\b|--force|--discard-changes|\s--(\s|$)|\s\.(\s|$))"
    r"|restore\b(?![^;&|\n]*(--staged|\s-S\b))"
    r"|rm\s+[^;&|\n]*(-[A-Za-z]*f\b|--force)|rebase\b(?!\s+--(abort|continue|skip|quit))"
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
    """Each $(...), <(...), >(...) and backtick span becomes one SUBST word; single-quoted text and
    comments stay literal. None when a span is not closed. The text inside each span (a command
    the shell runs) is appended to inners, and that of each unquoted >(...) to outs too."""
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
        elif c == "#" and not dq and (i == 0 or text[i - 1] in " \t\n;&|("):
            k = text.find("\n", i)
            i = n if k < 0 else k
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

HEREDOC_Q = re.compile(r"<<-?[ \t]*(?:\x27(\w+)\x27|\x22(\w+)\x22|\\(\w+))")
RUNS_INPUT = re.compile(r"(?:^|[\s|;&(/])(?:ba|z|da|k|fi)?sh\b|\b(?:python\d?(?:\.\d+)?|node|ruby|perl|php|ssh|eval|xargs|source)\b|(?:^|\s)\.\s")

def drop_literal_heredocs(text):
    """Remove the body of a QUOTED heredoc (<<\x27X\x27, <<"X", <<\\X) that nothing executes: it is
    literal text — a commit message quoting `git restore` was blocked (2026-09-28). Kept when the
    line feeds it to a shell or interpreter (bash <<\x27X\x27, cat <<\x27X\x27 | sh, python3 - <<…) and for
    an unquoted <<X, whose $(…) the shell runs. No terminator: kept whole (fail closed)."""
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        m = HEREDOC_Q.search(line)
        if not m:
            continue
        # The command that reads the heredoc: its own segment of the line (pipes included).
        a = max(line.rfind(x, 0, m.start()) for x in (";", "&&", "||"))
        ends = [k for k in (line.find(x, m.end()) for x in (";", "&&", "||")) if k >= 0]
        if RUNS_INPUT.search(line[a + 1 if a >= 0 else 0:min(ends) if ends else len(line)]):
            continue
        word = next(g for g in m.groups() if g)
        end = next((k for k in range(i, len(lines)) if lines[k].strip("\t") == word), None)
        if end is None:
            out.extend(lines[i:])
            break
        out.append(lines[end])
        i = end + 1
    return "\n".join(out)

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

# ── Text fed to a shell on stdin (2026-10-09, tests/gates/test_git_guard_shell_feed.sh) ──────────────────────────────
# `echo STR | bash`, `bash <<< STR`, `… | xargs sh -c`: the shell runs what it reads, so it is analysed like a -c string when
# the producer is a literal (echo / printf / cat with a here-doc or here-string; a here-doc body is analysed where it
# stands in the command). Text a command GENERATES (cat FILE, curl, base64 -d, a $… word) cannot be read here: the
# command is then blocked with UNREADABLE_FEED, unless something else in it blocks first.
UNREADABLE_FEED = ("shell chạy văn bản do lệnh khác sinh ra (pipe / here-string vào sh, bash, xargs sh -c): cổng không "
                   "đọc được nội dung — chỉ echo / printf / cat <<heredoc literal được phân tích; chạy thẳng lệnh đó")
PENDING_FEED = []   # an unreadable feed: the verdict when nothing else in the command blocks
IN_C_SCRIPT = [0]   # depth of bash -c scripts being analysed
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
    """Index of the program word of a simple command: after NAME=…, keywords, env (and its options) and wrappers."""
    i = 0
    while i < len(seg):
        t, p = seg[i], seg[i].rsplit("/", 1)[-1]
        if t in KEYWORDS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
        elif p == "env":
            i += 1
            while i < len(seg) and (seg[i].startswith("-") or "=" in seg[i]):
                i += 2 if seg[i] in ("-u", "-C", "-S") else 1
        elif p in WRAPPERS:
            i = skip_wrapper(seg, i, p)
        else:
            break
    return i

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

def analyse_free(text, depth):
    """analyse() of text that is not the script of the enclosing bash -c itself (an eval operand, an ssh or watch command, the body of a
    $(...) or an arithmetic expansion): a command substitution there is ordinary, only the script own command word is judged."""
    saved = IN_C_SCRIPT[0]
    IN_C_SCRIPT[0] = 0
    try:
        return analyse(text, depth)
    finally:
        IN_C_SCRIPT[0] = saved

def analyse(text, depth=0, stripped=False):
    if depth > 5:
        return "lồng lệnh quá sâu để phân tích"
    if depth == 0:
        text = drop_literal_heredocs(text)
    live = outside_single_quotes(text)
    if not stripped and ("`" in live or "$(" in live or "<(" in live or ">(" in live):
        flat = text.replace("\\\n", " ").replace("\n", " ; ")
        m = RAW.search(flat)
        if m:
            return f"{m.group(1).split()[0]} (trong lệnh có $(...)/backtick)"
        # 2026-09-28: the command inside $(...)/backticks gets the same parser as a top-level one
        # (the raw regex above knows no abbreviation: `echo $(git reset --har HEAD~1)` passed).
        inners, outs = [], []
        plain = strip_subst(text, inners, outs)
        if plain is not None:
            if any(out_subst_shell(o) for o in outs):
                PENDING_FEED.append(UNREADABLE_OSUBST)
            for inner in inners:
                here = CUR_DIR[0]   # a cd inside $(...) runs in a subshell
                reason = analyse_free(inner, depth + 1)
                CUR_DIR[0] = here
                if reason:
                    return reason
            return analyse(plain, depth + 1, True)
        if SOLO_WORDS.search(text):  # an unclosed $( / backtick hides the rest: fail closed
            SOLO_HIT.append("lệnh có $( hoặc backtick không đóng, không kiểm được push/nhánh trong đó; tách lệnh git ra riêng")
            return SOLO_HIT[-1]
        return None
    text = text.replace("\\\n", " ").replace("\n", " ; ")
    try:
        lex = shlex.shlex(text, posix=True, punctuation_chars=";&|()")
        lex.whitespace = " \t\r"
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        m = RAW.search(text)
        return f"{m.group(1).split()[0]} (lệnh không phân tích được)" if m else None
    segment = []
    dirs = []
    data_groups = []   # one flag per open paren: NAME=( ... ) and (( ... )) hold data, so a substitution there is no command word
    feed = None   # after a pipe: the producer segment ([] = a ( … ) / { … } group, not one literal command)
    for tok in tokens + [";"]:
        if tok in SEPARATORS or set(tok) <= set(";&|\n()"):
            opens_data = bool(segment) and segment[-1].endswith("=")
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
if reason and reason in SOLO_HIT:
    print(f"BLOCKED: {cmd!r} — {reason}. Luật \"1 dev, 1 nhánh\" (DevKit): làm thẳng trên nhánh hiện tại. "
          "Đưa code lên remote: merge/ff vào nhánh local bằng một lệnh riêng (kiểm exit code), rồi "
          "`git push origin <nhánh>`; không push `<sha>:<nhánh>` mà local chưa chứa. Nhánh/worktree mới chỉ khi "
          "User yêu cầu: chạy lại với DEVKIT_ALLOW_BRANCH=1 trước lệnh git.", file=sys.stderr)
    sys.exit(2)
if reason:
    print(f"BLOCKED: {cmd!r} — {reason}. User đã chặn thao tác git khó revert này. "
          "Nếu thực sự cần, User sẽ tự chạy qua prefix \"!\".", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
' "$0"
rc=$?
case "${rc}" in 0|2) exit "${rc}" ;; esac
echo "BLOCKED: block-dangerous-git.sh: python không chạy được (rc ${rc}). Chặn để an toàn (người dùng tự chạy lệnh qua prefix ! nếu đây là lỗi của cổng)." >&2
exit 2
