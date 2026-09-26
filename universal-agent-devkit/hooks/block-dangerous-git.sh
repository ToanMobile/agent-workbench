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
#   4. FAIL-CLOSED: if the command can't be tokenized, or contains `$(`/backticks
#      whose output could become a command, the raw text is scanned with a broad
#      regex instead. Missing python3 blocks.

INPUT=$(cat)

# ── Fast path (2026-09-23): most Bash calls (ls, cat, npm test, ./gradlew …) contain
# nothing this gate reacts to, and starting python3 for them cost ~70–90 ms each.
# Bash-only: take the command value from the JSON with a builtin regex and allow it
# at once when it has NO backslash / quote / $ / backtick / glob char (anything that
# could hide a word from this check) and none of the trigger words (case-insensitive).
# Everything else — and any payload the regex cannot read — goes to the full parser.
fast_allow() { # $1 = trigger ERE
  local re='"command"[[:space:]]*:[[:space:]]*"([^"\\]*)"' c
  [[ $INPUT =~ $re ]] || return 1
  c="${BASH_REMATCH[1]}"
  case "$c" in ""|*[\'\$\`\*\?\[\]]*) return 1 ;; esac
  shopt -s nocasematch
  if [[ $c =~ $1 ]]; then shopt -u nocasematch; return 1; fi
  shopt -u nocasematch
  return 0
}
fast_allow 'git|eval|devkit_precommit|hookspath' && exit 0

if ! command -v python3 >/dev/null 2>&1; then
  echo "BLOCKED: block-dangerous-git.sh cần 'python3' để phân tích lệnh. Chặn để an toàn." >&2
  exit 2
fi

printf '%s' "$INPUT" | python3 -c '
import fnmatch, json, os, re, shlex, shutil, subprocess, sys, time

try:
    PAYLOAD = json.load(sys.stdin)
    cmd = PAYLOAD.get("tool_input", {}).get("command") or ""
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
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
GIT_OPTS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix", "--config-env"}

def short_flags(args):
    """Letters of every single-dash short-option cluster, e.g. -xdf -> {x,d,f}."""
    out = set()
    for a in args:
        if a.startswith("-") and not a.startswith("--") and len(a) > 1:
            out.update(a[1:])
    return out

def danger_in_git(sub, args):
    long_ = set(a.split("=", 1)[0] for a in args if a.startswith("--"))
    short = short_flags(args)
    pos = [a for a in args if not a.startswith("-")]
    if sub == "reset" and long_ & {"--hard", "--merge", "--keep"}:
        return "reset --hard/--merge/--keep vứt thay đổi"
    if sub == "clean" and ("f" in short or "--force" in long_):
        return "clean --force xoá file chưa track"
    if sub == "branch" and ("D" in short or (("d" in short or "--delete" in long_) and ("f" in short or "--force" in long_))):
        return "branch -D xoá branch chưa merge"
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
PUSH_OPTS_WITH_ARG = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}

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
    elif sub == "push" and not long_ & {"--all", "--branches", "--tags", "--mirror"}:
        vals, k = [], 0
        while k < len(args):
            if args[k] in PUSH_OPTS_WITH_ARG:
                k += 2
                continue
            if not args[k].startswith("-"):
                vals.append(args[k])
            k += 1
        for spec in vals[1:]:
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
    if reason:
        SOLO_HIT.append(reason)
    return reason

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
    root = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    for p in paths:
        if p in (".", "./") or any(c in p for c in "*?[:") or not os.path.isfile(p) or os.path.islink(p):
            return False
        if not os.path.realpath(p).startswith(root + os.sep):
            return False
    PENDING_BACKUPS.extend(os.path.realpath(p) for p in paths)
    return True

def do_backups():
    """Copy the files a restore will overwrite — only after the whole command passed."""
    if not PENDING_BACKUPS:
        return True
    root = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
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

def analyse_simple(tokens, depth):
    i = 0
    hooks_off = False
    allow_branch = ALLOW_BRANCH[0]
    while i < len(tokens) and (tokens[i] in KEYWORDS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[i])):
        hooks_off = hooks_off or bool(HOOK_OFF_ENV.match(tokens[i]))
        allow_branch = allow_branch or tokens[i] == ALLOW_BRANCH_ENV
        i += 1
    while i < len(tokens):
        prog = tokens[i].rsplit("/", 1)[-1]
        if prog == "env":
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or "=" in tokens[i]):
                hooks_off = hooks_off or bool(HOOK_OFF_ENV.match(tokens[i]))
                allow_branch = allow_branch or tokens[i] == ALLOW_BRANCH_ENV
                i += 2 if tokens[i] in ("-u", "-C", "-S") else 1
        elif prog in WRAPPERS:
            i = skip_wrapper(tokens, i, prog)
        elif tokens[i] in KEYWORDS:
            i += 1
        else:
            break
    if i >= len(tokens):
        return None
    prog, rest = tokens[i].rsplit("/", 1)[-1], tokens[i + 1:]
    # macOS resolves GIT / Git to git, and a glob like g?t or gi[t] can expand to it.
    if prog.lower() == "git" or (re.search(r"[*?\[]", prog) and fnmatch.fnmatch("git", prog)):
        prog = "git"
    if prog in ("cd", "pushd", "popd"):
        CHANGES_DIR.append(prog)
        tgt = next((a for a in rest if not a.startswith("-")), "~")
        unknown = prog == "popd" or rest[:1] == ["-"] or not CUR_DIR[0]
        CUR_DIR[0] = None if unknown else os.path.join(CUR_DIR[0], os.path.expanduser(tgt))
    if prog == "export" and ALLOW_BRANCH_ENV in rest:
        ALLOW_BRANCH[0] = True
    # `$g reset --hard` / `${GIT} clean -f`: a variable in command position may be git.
    if prog.startswith("$"):
        return danger_in_git(rest[0], rest[1:]) if rest else None
    if prog in INTERPRETERS:
        for j, a in enumerate(rest):
            if a in ("-c", "-e", "--eval", "-E", "-r") and j + 1 < len(rest):
                m = RAW.search(rest[j + 1])
                return f"{m.group(1).split()[0]} (gọi qua {prog} {a})" if m else None
        return None
    if prog == "watch":
        j = 0
        while j < len(rest) and rest[j].startswith("-"):
            j += 2 if rest[j] in ("-n", "-d", "--interval") else 1
        return analyse(" ".join(rest[j:]), depth + 1) if j < len(rest) else None
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
            return analyse(" ".join(rest), depth + 1)
        for j, a in enumerate(rest):
            if a == "-c" or (a.startswith("-") and not a.startswith("--") and "c" in a[1:]):
                return analyse(rest[j + 1], depth + 1) if j + 1 < len(rest) else None
        return None
    if prog == "ssh":
        j = 0
        while j < len(rest) and rest[j].startswith("-"):
            j += 2 if rest[j] in ("-p", "-i", "-l", "-o", "-F", "-J", "-L", "-R", "-D") else 1
        return analyse(" ".join(rest[j + 1:]), depth + 1) if j + 1 < len(rest) else None
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
        if opt == "-c" and j + 1 < len(rest) and rest[j + 1].startswith("alias.") and "=" in rest[j + 1]:
            k, v = rest[j + 1].split("=", 1)
            aliases[k[len("alias."):]] = v
        cfg = rest[j + 1] if opt == "-c" and j + 1 < len(rest) else rest[j].split("=", 1)[-1] if opt == "-c" else ""
        if cfg.lower().startswith("core.hookspath"):
            return "git -c core.hooksPath=… tắt git hook (pre-commit kiểm secret/chất lượng)"
        j += 2 if (opt in GIT_OPTS_WITH_ARG and "=" not in rest[j]) else 1
    if j >= len(rest):
        return None
    if rest[j] in aliases:
        reason = git_danger_from_alias(aliases[rest[j]])
        if reason:
            return f"alias {rest[j]} → {reason}"
    relocated = any(o.split("=", 1)[0] in ("-C", "--git-dir", "--work-tree") for o in rest[:j])
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

def strip_subst(text):
    """Each $(...), <(...), >(...) and backtick span becomes one SUBST word; single-quoted text and
    comments stay literal. None when a span is not closed."""
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
            out.append(SUBST)
            i = j
        elif c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                return None
            out.append(SUBST)
            i = j + 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)

SOLO_WORDS = re.compile(r"\bgit\b[^\n]*?\b(push|checkout|switch|branch|worktree)\b")

def analyse(text, depth=0, stripped=False):
    if depth > 5:
        return "lồng lệnh quá sâu để phân tích"
    if not stripped and ("`" in text or "$(" in text or "<(" in text):
        flat = text.replace("\\\n", " ").replace("\n", " ; ")
        m = RAW.search(flat)
        if m:
            return f"{m.group(1).split()[0]} (trong lệnh có $(...)/backtick)"
        plain = strip_subst(text)
        if plain is not None:
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
    for tok in tokens + [";"]:
        if tok in SEPARATORS or set(tok) <= set(";&|\n()"):
            if segment:
                reason = analyse_simple(segment, depth)
                if reason:
                    return reason
            segment = []
            for ch in tok:
                if ch == "(":
                    dirs.append(CUR_DIR[0])
                elif ch == ")" and dirs:
                    CUR_DIR[0] = dirs.pop()
        else:
            segment.append(tok)
    return None

CHANGES_DIR.extend(t for t in re.findall(r"(?:^|[;&|(\s])(cd|pushd)\s", cmd))  # any cd, even after the restore
reason = analyse(cmd)
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
'
