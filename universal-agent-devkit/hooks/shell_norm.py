"""One reading of a shell command line for the command guards hooks/hardware_safety_gate.sh and hooks/block-dangerous-git.sh.

workflow-improvements.md I.0 W3 / I.1 Việc 2 (14/10): the two guards each had their own idea of which words of a command run as a
command, and each missed forms the other knew (`su -c`, `bash -lc`, `sudo -u X`, `timeout -s SIG N`, `adb shell`, a `<<'EOF'` inside
quotes …). What decides it lives here, once; each guard keeps its own verdict rules.
  - the program word of a simple command: NAME=VAL words, shell keywords, a redirect before the command and the wrappers that run
    the command after them, with the values of their options (prefix_end);
  - the command text another program runs: sh/bash -c (also inside a flag cluster: -lc, -ec), su -c / su USER CMD, ssh host CMD,
    adb shell|exec-out CMD (shell_script, su_command, far_command);
  - brace expansion and path normalisation of a target (braces, norm_path);
  - heredocs, found the way the shell finds them (outside quotes and comments), each with the reader it goes to. A body is cut
    (strip_heredocs) only when the whole command is made of constructs this file models (_modeled) AND the body is the message of a
    known option or the one file statement of the command (_message_arg, _file_statement); everything else stays in the scan, as
    the old hardware gate always did (policy of 15/10, after three review rounds found holes in a scanner that is not the shell).
Standard library only. Loaded by the guards from their own directory (python3 -I keeps the project off sys.path).
"""
import os
import posixpath
import re
import shlex

# wrapper -> (options that take a separate value, positional words before the command it runs)
WRAPPERS = {
    "command": (set(), 0), "builtin": (set(), 0), "exec": ({"-a"}, 0), "nohup": (set(), 0),
    "time": (set(), 0), "caffeinate": ({"-t", "-w"}, 0), "setsid": (set(), 0), "unbuffer": (set(), 0),
    "sudo": ({"-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T", "--user", "--group", "--host", "--prompt", "--close-from",
              "--chdir", "--role", "--type", "--other-user", "--command-timeout"}, 0),
    "doas": ({"-u", "-C"}, 0),
    "nice": ({"-n"}, 0),
    "ionice": ({"-c", "-n", "-p"}, 0),
    "stdbuf": ({"-i", "-o", "-e"}, 0),
    "timeout": ({"-s", "-k", "--signal", "--kill-after"}, 1),
    "gtimeout": ({"-s", "-k", "--signal", "--kill-after"}, 1),   # GNU timeout from Homebrew coreutils
    "arch": ({"-arch", "-e", "-d"}, 0),                           # macOS arch -arm64 / -x86_64 CMD
    "chrt": (set(), 1),
    "taskset": (set(), 1),
    "flock": ({"-w", "-E", "--timeout"}, 1),
}
# Shell reserved words that may stand before a command in the same simple-command slot (`if git …`, `! rm …`, `do rm …`).
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "!", "{", "}"}   # time: a wrapper (time -p CMD)
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
SHELL_OPTS_WITH_ARG = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file"}
SSH_OPTS_WITH_ARG = {"-p", "-i", "-l", "-o", "-F", "-J", "-L", "-R", "-D", "-b", "-c", "-E", "-e", "-I", "-m", "-O", "-Q", "-S",
                     "-W", "-w", "-B"}
ADB_OPTS_WITH_ARG = {"-s", "-t", "-H", "-P", "-L", "--one-device"}
REDIRECT = re.compile(r"^\d*(?:>>?|<|&>)")
REDIRECT_ALONE = re.compile(r"\d*(?:>>?&?|<&?|&>)")   # fullmatch: the target is the next word
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def skip_wrapper(tokens, i, prog):
    """Index of the word after wrapper tokens[i] (prog), its options with their values and its positional words."""
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


def join_fd_dup(segment, tok):
    """True, with the & joined onto segment[0], when tok is the & of a leading N>&M / >&N / N<&M: the lexer cuts it off as a command
    separator, which made `2>&1 git reset --hard` a lone `2>` and a command starting with `1`. Only when segment is just that
    operator: `git push origin main 2>&1` keeps its old reading."""
    if tok == "&" and len(segment) == 1 and re.fullmatch(r"\d*(?:>>?|<)", segment[0]):
        segment[0] += "&"
        return True
    return False


def redirect_len(tokens, i):
    """How many words the redirect at tokens[i] takes (0: none): the operator and its target, and for N>&M, >&N, N<&M the lexer
    splits the & and the descriptor off the operator (`2>&1 git reset --hard` ran git unseen)."""
    t = tokens[i]
    if not REDIRECT.match(t):
        return 0
    if REDIRECT_ALONE.fullmatch(t):
        return 3 if tokens[i + 1:i + 2] == ["&"] and i + 2 < len(tokens) else 2   # N>&M, >&file: the & and its target
    return 1


def env_option(tokens, j):
    """(how many words the env option tokens[j] takes, the STRING of an -S / --split-string option or None). -u -C -P -S and the long
    --unset --chdir --split-string take a value, glued or the next word, alone or as the last letter of a flag cluster: `env -iS STR`
    ran STR unseen (review 15/10)."""
    a = tokens[j]
    if a.startswith("--"):
        name, eq, val = a.partition("=")
        if name in ("--unset", "--chdir", "--split-string"):
            v = val if eq else (tokens[j + 1] if j + 1 < len(tokens) else "")
            return (1 if eq else 2), (v if name == "--split-string" else None)
        return 1, None
    for k, ch in enumerate(a[1:], 1):
        if ch in "uCPS":
            glued = a[k + 1:]
            v = glued or (tokens[j + 1] if j + 1 < len(tokens) else "")
            return (1 if glued else 2), (v if ch == "S" else None)
    return 1, None


def prefix_end(tokens, i=0):
    """Index of the program word of a simple command: after NAME=VAL words, keywords, a redirect before the command
    (`2>/dev/null rm …`, `> out git …`), env with its options and assignments, and the wrappers. len(tokens) when there is none."""
    while i < len(tokens):
        t, p = tokens[i], tokens[i].rsplit("/", 1)[-1]
        if t in KEYWORDS or ASSIGN.match(t):
            i += 1
        elif REDIRECT.match(t):
            i += redirect_len(tokens, i)
        elif p == "env":
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or "=" in tokens[i]):
                i += env_option(tokens, i)[0] if tokens[i].startswith("-") else 1
        elif p in WRAPPERS:
            i = skip_wrapper(tokens, i, p)
        else:
            break
    return min(i, len(tokens))


def inline_script(tokens):
    """tokens with the command line a wrapper hides made into words: `sudo|doas -s|-i STR` (the shell they start runs STR) becomes
    `sudo … sh -c STR`, and `env -S STR` (STR is split into the words env runs) is replaced by those words. tokens itself when
    there is nothing to expand. Both guards call it first on every simple command (review 15/10: both read STR as a program name)."""
    i, n = 0, len(tokens)
    while i < n:
        t, p = tokens[i], tokens[i].rsplit("/", 1)[-1]
        if t in KEYWORDS or ASSIGN.match(t):
            i += 1
        elif REDIRECT.match(t):
            i += max(1, redirect_len(tokens, i))
        elif p == "env":
            j = i + 1
            while j < n and (tokens[j].startswith("-") or "=" in tokens[j]):
                took, val = env_option(tokens, j) if tokens[j].startswith("-") else (1, None)
                if val is not None:
                    try:
                        words = shlex.split(val)
                    except ValueError:
                        words = val.split()
                    return inline_script(tokens[:j] + words + tokens[j + took:])
                j += took
            i = j
        elif p in WRAPPERS:
            k = skip_wrapper(tokens, i, p)
            if p in ("sudo", "doas") and k < n and _sudo_flags(tokens[i:k]):
                return tokens[:k] + ["sh", "-c", " ".join(tokens[k:])]
            i = k
        else:
            break
    return tokens


def _sudo_flags(words):
    """True when words (sudo / doas and its options) ask for a shell: -s, -i, --shell, --login (alone or in a flag cluster)."""
    values, j = WRAPPERS[os.path.basename(words[0])][0], 1
    while j < len(words) and words[j].startswith("-") and words[j] != "--":
        o = words[j].split("=", 1)[0]
        if o in ("--shell", "--login") or (re.fullmatch(r"-[A-Za-z]*[si][A-Za-z]*", words[j]) and o not in values):
            return True
        j += 2 if (o in values and "=" not in words[j]) else 1
    return False


def shell_script(rest):
    """The script a shell runs with -c (rest: the words after the shell): -c alone or inside a flag cluster (bash -lc, sh -ec);
    options may follow it, the script is the first operand after them (bash -c -- STR, bash -c -e STR). None without -c."""
    for j, a in enumerate(rest):
        if a == "-c" or (len(a) > 1 and a[0] == "-" and a[1] != "-" and "c" in a[1:]):
            k = j + 1
            while k < len(rest) and rest[k] != "--" and len(rest[k]) > 1 and rest[k][0] in "-+":
                k += 2 if rest[k] in SHELL_OPTS_WITH_ARG else 1
            k += 1 if k < len(rest) and rest[k] == "--" else 0
            return rest[k] if k < len(rest) else None
    return None


SU_OPTS_WITH_ARG = {"-s", "--shell", "-g", "--group", "-G", "--supp-group", "-w", "--whitelist-environment"}


def su_command(rest):
    """What `su` runs (rest: the words after su): ("script", STR) for su [OPTS] [USER] -c STR (also --command[=]STR,
    --session-command), ("argv", WORDS) for the Android `su [OPTS] USER CMD…` form, None for an interactive su."""
    for k, a in enumerate(rest):
        name, eq, val = a.partition("=")
        if name in ("--command", "--session-command"):
            return ("script", val) if eq else (("script", rest[k + 1]) if k + 1 < len(rest) else None)
    script = shell_script(rest)
    if script is not None:
        return "script", script
    j = 0
    while j < len(rest) and rest[j].startswith("-") and rest[j] != "--":
        j += 2 if rest[j] in SU_OPTS_WITH_ARG else 1
    j += 1 if j < len(rest) and rest[j] == "--" else 0
    return ("argv", rest[j + 1:]) if j + 1 < len(rest) else None


XARGS_OPTS_WITH_ARG = {"-I", "-J", "-R", "-S", "-n", "-P", "-L", "-d", "-E", "-s", "-a"}   # GNU -i takes its value glued


def xargs_command(rest):
    """Index in rest (the words after xargs) of the command xargs runs: after its options and their values."""
    j = 0
    while j < len(rest) and rest[j].startswith("-") and rest[j] != "--":
        j += 2 if rest[j] in XARGS_OPTS_WITH_ARG else 1
    return min(j + (1 if j < len(rest) and rest[j] == "--" else 0), len(rest))


def far_command(prog, rest):
    """(text, where) of the command line another machine runs: `ssh [OPTS] HOST CMD…` -> ("CMD …", "ssh"),
    `adb [OPTS] shell|exec-out [-n -T -t -x] CMD…` -> ("CMD …", "device"). adb and ssh join their words with spaces and the far
    shell splits them again. None for anything else, and for an interactive ssh / adb shell."""
    if prog in ("adb", "adb.exe"):
        j = 0
        while j < len(rest) and rest[j].startswith("-"):
            j += 2 if rest[j] in ADB_OPTS_WITH_ARG else 1
        while j < len(rest) and re.fullmatch(r"wait-for-[\w-]+", rest[j]):   # adb wait-for-device shell CMD
            j += 1
        if j < len(rest) and rest[j] in ("shell", "exec-out"):
            j += 1
            while j < len(rest) and (re.fullmatch(r"-[nTtx]+", rest[j]) or rest[j] == "-e"):   # -e ESCAPE takes a value
                j += 2 if rest[j] == "-e" else 1
            return (" ".join(rest[j:]), "device") if j < len(rest) else None
        return None
    if prog == "ssh":
        j = 0
        while j < len(rest) and rest[j].startswith("-") and rest[j] != "--":
            a = rest[j]
            j += 1
            if a in SSH_OPTS_WITH_ARG:
                j += 1
                continue
            for k, ch in enumerate(a[1:], 1):   # a cluster (-tp 22): the first letter with a value takes the rest or the next word
                if "-" + ch in SSH_OPTS_WITH_ARG:
                    j += 1 if k == len(a) - 1 else 0
                    break
        j += 1 if j < len(rest) and rest[j] == "--" else 0
        return (" ".join(rest[j + 1:]), "ssh") if j + 1 < len(rest) else None
    return None


def adb_shell(rest):
    """True when the words after adb name the shell / exec-out subcommand (also glued to a heredoc: adb shell<<EOF)."""
    j = 0
    while j < len(rest) and rest[j].startswith("-"):
        j += 2 if rest[j] in ADB_OPTS_WITH_ARG else 1
    return j < len(rest) and re.match(r"(?:shell|exec-out)(?![\w-])", rest[j]) is not None


BRACE = re.compile(r"(?<!\$)\{([^{}]*,[^{}]*)\}")


BRACE_BOMB = "/"   # what a brace expansion past the cap is judged as: the worst target there is


def braces(word, cap=64):
    """The words a shell brace expansion makes of word (/{system,vendor} -> /system /vendor), at most cap. Past the cap the rest is
    not expanded and the result ends with BRACE_BOMB: fail closed, a command that builds its target from 128 words is refused
    (review 15/10: /{,x}{,x}{,x}{,x}{,x}{,x}{,x}system was allowed while 6 groups were refused). ${…} is a parameter, not a brace group."""
    out, todo = [], [word]
    while todo and len(out) + len(todo) <= cap:
        w = todo.pop()
        m = BRACE.search(w)
        if not m:
            out.append(w)
            continue
        todo.extend(w[:m.start()] + alt + w[m.end():] for alt in m.group(1).split(","))
    return out + [BRACE_BOMB] if todo else out


def norm_path(p):
    """An absolute path as the kernel resolves its words: //, /./ and .. folded (/sdcard/../system -> /system)."""
    return posixpath.normpath("/" + p.lstrip("/"))




# ── Heredocs ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Programs that read a heredoc as data only: the body is never run (a commit message, a file written with cat > f, a PR body).
# Not here: read / mapfile (the variable may be eval'd later), sed / awk (they can run commands), anything not known.
DATA_READERS = {"cat", "tee", "git", "gh", "glab", "wc", "grep", "egrep", "fgrep", "rg", "sort", "uniq", "head", "tail", "jq",
                "yq", "diff", "cmp", "base64", "tr", "cut", "column", "nl", "tac", "iconv", "printf", "echo", "true", ":",
                "pbcopy", "md5", "md5sum", "shasum", "sha1sum", "sha256sum", "cksum", "envsubst", "patch", "curl"}
# Programs that run a heredoc, or the text it becomes, as shell commands, here or on another machine.
SHELL_RUNNERS = SHELLS | {"ssh", "eval", "source", ".", "su", "xargs", "at", "batch", "script", "expect", "watch"}
INTERPRETER = re.compile(r"python\d?(?:\.\d+)?|pypy\d?|node|nodejs|ruby|perl|php|deno|bun")
# per interpreter: (options that take a separate value, options after which the program is inline / a module / a file)
INTERP_OPTS = {"python": ({"-W", "-X"}, {"-c", "-m"}),
               "node": ({"-r", "--require", "--import", "--loader", "--env-file"}, {"-e", "-p", "--eval", "--print"}),
               "ruby": ({"-r", "-I", "-C", "-E"}, {"-e"}),
               "perl": (set(), {"-e", "-E"}),
               "php": ({"-d", "-c"}, {"-r", "-f"})}
RUNNERS = {"uv", "poetry", "pipenv", "pdm", "rye", "hatch"}               # `uv run [opts] python - <<EOF`
# What lets an interpreter program start a process (a command line of its own). The body of a program that has none of these cannot
# run a command; one that has any is still read as commands by the guards (a backtick in ruby / perl / php runs a command too).
EXEC_SINK = re.compile(r"\bsubprocess\b|\bos\.(?:system|popen|exec\w*|spawn\w*)\b|\bPopen\b|\bcheck_(?:output|call)\b"
                       r"|\bcreate_subprocess_\w+|\bpty\.spawn\b"
                       r"|\bchild_process\b|\b(?:execSync|execFileSync|spawnSync|spawn|execa)\b|\bsystem\b|\bexec(?:[lv]\w*|file\w*)?\b"
                       r"|\bpopen\w*\b|\bshell_exec\b|\bpassthru\b|\bproc_open\b|\bIO\.popen\b|\bOpen3\b|%x\W|\bqx\W"
                       r"|\bopen\b[^\n]*\||\bsh\.\w+\s*\(|\bfrom\s+sh\s+import\b|\bplumbum\b|\bpexpect\b|\bdelegator\b"
                       r"|\bposix_spawnp?\b|\breadpipe\b|\bsyscall\b|\bget(?:status)?output\b|\bpcntl_exec\b|\bspawn_sync\b", re.I)


def spawns(body, prog):
    """True when the program text body of interpreter prog can start a process."""
    return bool(EXEC_SINK.search(body) or (re.match(r"(?:ruby|perl|php)", prog or "") and "`" in body))


class Heredoc:
    """One heredoc. op_start / op_end: the << operator and its word; body_start / body_end: the body; end: just past its
    delimiter line. quoted: a quote or backslash in the word (the shell expands nothing in the body). terminated: a delimiter
    line was found. depth: nesting of $( … ) / ( … ) / `…` at the operator. reader: the program the body (or the text it becomes)
    goes to. kind: "shell" (a shell reads it, here or far), "interp" (an interpreter reads it as its program), "data" (the message
    of a known option or the one file statement of the command, never run: _message_arg, _file_statement) or "other" (anything
    else). cut_ok: the whole command is modeled (_modeled): only then may a body be cut (strip_heredocs). in_dq: the operator
    sits in a double-quoted $( … )."""
    __slots__ = ("op_start", "op_end", "delim", "quoted", "strip_tabs", "depth", "body_start", "body_end", "end",
                 "terminated", "reader", "kind", "in_dq", "cut_ok")

    def __init__(self, op_start, op_end, delim, quoted, strip_tabs, depth):
        self.op_start, self.op_end, self.delim, self.quoted = op_start, op_end, delim, quoted
        self.strip_tabs, self.depth = strip_tabs, depth
        self.body_start = self.body_end = self.end = op_end
        self.terminated, self.reader, self.kind, self.in_dq, self.cut_ok = False, "", "other", False, False

    def body(self, text):
        return text[self.body_start:self.body_end]


def _heredoc_word(text, i):
    """(end index, word with its quotes removed, quoted) of the heredoc word that starts at text[i]."""
    out, quoted, n = [], False, len(text)
    while i < n and text[i] not in " \t\n;&|()<>":
        c = text[i]
        if c == "$" and text[i + 1:i + 2] in ("\x27", "\x22"):   # <<$'EOF' / <<$"EOF": bash and zsh read them differently: no heredoc
            return i, "", quoted                                    # here, the lines after it are judged as commands (not decoded)
        if c in "\x27\x22":
            k = text.find(c, i + 1)
            if k < 0 or "\n" in text[i:k]:
                return i, "", quoted
            out.append(text[i + 1:k])
            quoted, i = True, k + 1
        elif c == "\\" and i + 1 < n:
            out.append(text[i + 1])
            quoted, i = True, i + 2
        else:
            out.append(c)
            i += 1
    return i, "".join(out), quoted


def _read_bodies(text, nl, pending):
    """Fill in the bodies of the heredocs of the line that ends at the newline text[nl], in order; the index just past the
    last delimiter line. A heredoc with no delimiter line takes the rest of the text (terminated stays False)."""
    pos = nl + 1
    for h in pending:
        h.body_start = pos
        while True:
            if pos >= len(text):
                h.body_end = h.end = len(text)
                return len(text)
            eol = text.find("\n", pos)
            line = text[pos:] if eol < 0 else text[pos:eol]
            if (line.lstrip("\t") if h.strip_tabs else line).rstrip("\r") == h.delim:
                h.body_end, h.terminated = pos, True
                pos = h.end = len(text) if eol < 0 else eol + 1
                break
            if eol < 0:
                h.body_end = h.end = len(text)
                return len(text)
            pos = eol + 1
    return pos


def _scan(text):
    """(heredocs in order, depth-0 separators [(start, end)], depth-0 pipe positions) of a command line. Separators are ; && ||
    & ;; and newlines outside quotes and $( … ) / ( … ) / `…`; the bodies read after a newline belong to its separator span."""
    docs, pending, seps, pipes = [], [], [], []
    frames = ["cmd"]       # "cmd" top level; "cmd$" $( … ); "cmd(" ( … ); "cmd`" `…`; "dq" "…"; "arith" $(( … )) / (( … ))
    i, n, word_start = 0, len(text), True
    while i < n:
        c, top = text[i], frames[-1]
        if top == "dq":
            if c == "\\":
                i += 2
                continue
            if c == "\x22":
                frames.pop()
            elif c == "$" and text.startswith("((", i + 1):
                frames.append("arith")
                i += 3
                continue
            elif c == "$" and text.startswith("(", i + 1):
                frames.append("cmd$")
                i += 2
                word_start = True
                continue
            elif c == "`":
                frames.append("cmd`")
                word_start = True
            i += 1
            continue
        if top == "arith":
            if c == "(":
                frames.append("arith")
            elif c == ")":
                frames.pop()
                if text.startswith(")", i + 1) and frames[-1] != "arith":
                    i += 1             # the second paren of ))
            i += 1
            continue
        # a command context
        if c == "\\":
            i += 2                     # an escaped character; \<newline> continues the line
            word_start = False
            continue
        if c == "\x27":
            k = text.find("\x27", i + 1)
            i = n if k < 0 else k + 1
            word_start = False
            continue
        if c == "$" and text.startswith("\x27", i + 1):   # $'…': backslash escapes inside
            k = i + 2
            while k < n and text[k] != "\x27":
                k += 2 if text[k] == "\\" else 1
            i, word_start = k + 1, False
            continue
        if c == "\x22":
            frames.append("dq")
            i, word_start = i + 1, False
            continue
        if c == "#" and word_start:
            k = text.find("\n", i)
            i = n if k < 0 else k      # the newline itself still ends the line (and starts pending bodies)
            continue
        if c == "$" and text.startswith("((", i + 1):
            frames.append("arith")
            i += 3
            continue
        if c == "(" and word_start and text.startswith("(", i + 1):   # (( … )) arithmetic command
            frames.append("arith")
            i += 2
            continue
        if c == "$" and text.startswith("(", i + 1):
            frames.append("cmd$")
            i, word_start = i + 2, True
            continue
        if c == "(":
            frames.append("cmd(")
            i, word_start = i + 1, True
            continue
        if c == ")":
            if top in ("cmd$", "cmd("):
                frames.pop()
            i, word_start = i + 1, False
            continue
        if c == "`":
            if top == "cmd`":
                frames.pop()
            else:
                frames.append("cmd`")
            i, word_start = i + 1, True
            continue
        if text.startswith("<<<", i):
            i, word_start = i + 3, False   # a here-string: no heredoc (its last two < are no operator either)
            continue
        if text.startswith("<<", i):
            j = i + 2
            strip = text.startswith("-", j)
            j += 1 if strip else 0
            while j < n and text[j] in " \t":
                j += 1
            end, word, quoted = _heredoc_word(text, j)
            if word:
                h = Heredoc(i, end, word, quoted, strip, len(frames) - 1)
                h.in_dq = len(frames) > 1 and frames[-2] == "dq" and frames[-1] in ("cmd$", "cmd`")
                docs.append(h)
                pending.append(h)
                i, word_start = end, False
                continue
            i += 2
            continue
        if c == "\n":
            if len(frames) == 1:
                seps.append((i, i + 1))
            if pending:
                j = _read_bodies(text, i, pending)
                if len(frames) == 1:
                    seps[-1] = (i, j)
                i, pending, word_start = j, [], True
                continue
            i, word_start = i + 1, True
            continue
        if c in ";&|" and len(frames) == 1 and not (c == "&" and i and text[i - 1] in "<>"):
            two = text[i:i + 2]
            if two in ("&&", "||", ";;"):
                seps.append((i, i + 2))
                i += 2
            elif c == "|":
                pipes.append(i)
                i += 2 if two == "|&" else 1
            elif two == "&>":
                i += 2                 # &> redirect
            else:
                seps.append((i, i + 1))
                i += 1
            word_start = True
            continue
        word_start = c in " \t;&|("
        i += 1
    return docs, seps, pipes


def _words(s):
    try:
        lex = shlex.shlex(s, posix=True, punctuation_chars=";&|()")
        lex.whitespace, lex.whitespace_split, lex.commenters = " \t\r\n", True, ""
        return list(lex)
    except ValueError:
        return s.split()


def _program(words):
    """(program basename, words after it) of a simple command; `uv run …` and friends are looked through."""
    k = prefix_end(words)
    while k < len(words) and words[k] in ("(", "{", "!", "$", "`"):
        k = prefix_end(words, k + 1)
    if k + 1 < len(words) and os.path.basename(words[k]) in RUNNERS and words[k + 1] == "run":
        k += 2
        while k < len(words) and words[k].startswith("-"):
            k += 1
    if k >= len(words):
        return "", []
    return os.path.basename(words[k].lstrip("(`")), words[k + 1:]


def _interp(prog):
    """The INTERP_OPTS family of an interpreter program name, or None."""
    if not INTERPRETER.fullmatch(prog):
        return None
    return next((f for f in ("python", "node", "ruby", "perl", "php") if prog.startswith(f)),
                "python" if prog.startswith("pypy") else "node")   # deno, bun: node-like options


def _program_on_stdin(prog, rest):
    """True when interpreter prog (rest: its words) takes its program from stdin: no inline program, module or script file
    operand, or the operand is `-`."""
    values, inline = INTERP_OPTS[_interp(prog)]
    k = 0
    while k < len(rest):
        a = rest[k]
        if a in inline or a.split("=", 1)[0] in inline:
            return False
        if a == "-":
            return True
        if REDIRECT.match(a) or a.startswith("<"):
            k += 2 if REDIRECT_ALONE.fullmatch(a) else 1
            continue
        if a.startswith("-"):
            k += 2 if a in values else 1
            continue
        return False            # a script file: the heredoc is its input
    return True


def _program_inline(prog, rest):
    """True when interpreter prog has an inline program (python -c STR, node -e STR …)."""
    values, inline = INTERP_OPTS[_interp(prog)]
    return any(a in inline and a not in ("-m", "-f") for a in rest)


def _segment(text, start, end, cut):
    """text[start:end] without the [s, e) spans of cut (heredoc bodies)."""
    parts, pos = [], start
    for s, e in cut:
        if e <= start or s >= end:
            continue
        parts.append(text[pos:max(pos, s)])
        pos = max(pos, e)
    parts.append(text[pos:end] if pos < end else "")
    return "\n".join(parts)


# ── What may be cut (policy of 15/10, after three review rounds: the lane cut heredoc bodies with a scanner that is not the shell) ──
# A body is cut (strip_heredocs) only when BOTH hold:
#   1. the whole command is made of constructs this file models, outside the bodies (_modeled): plain words, '…' and "…" quotes,
#      $( … ), redirections, ; && || | and newlines, and a heredoc word that is plain. A ${ … }, $[ … ], $(( … )), a backtick, $'…', a
#      subshell or group, a keyword, trap / eval / source / exec, a background &, <( … ), <<<, a backslash or a stray # means no
#      heredoc found here can be trusted: nothing is cut and the body stays in the scan, as the old hardware gate always did;
#   2. the body is data by one of two shapes and no other: the message of a known option (_message_arg: git commit -m "$(cat <<'EOF'
#      … EOF\n)", gh pr create --body …) or the one statement of the command (_file_statement: cat > notes.md <<'EOF' … EOF, tee,
#      git commit -F -) with nothing after it. What follows a written file is NOT tracked any more: a file written and then run,
#      moved, hooked or read by a program set up before the write was a hole on every round.
MAX_HEREDOCS = 24
# A path in a git hook dir or a git config file, or a git hook by name: writing it is writing code something later runs.
HOOKDIR = re.compile(r"(?:^|[/\s'\"=])\.git(?:/|\b)|(?:^|[/\s'\"=])\.?(?:githooks|husky|hooks)(?:/|[\s'\"`)]|$)|\.gitconfig|\.gitattributes")
HOOKNAME = re.compile(r"(?:^|/)(?:pre-commit|prepare-commit-msg|commit-msg|post-commit|pre-rebase|post-checkout|post-merge|pre-push|"
                      r"pre-receive|post-receive|post-update|pre-auto-gc|post-rewrite|pre-merge-commit|applypatch-msg|pre-applypatch|"
                      r"post-applypatch|fsmonitor-watchman|reference-transaction|push-to-checkout|sendemail-validate)$")
# Only a file that is text for people (never run, never read as configuration by a tool of the project) is a data target; a path
# with no extension, a script, a shell startup file, ~/.config/git/config, a Makefile … are not in the list.
TEXT_EXT = {".md", ".markdown", ".txt", ".rst", ".csv", ".tsv", ".log", ".json", ".yaml", ".yml", ".toml", ".xml", ".html", ".diff", ".patch", ".sql"}
NOT_TEXT = {"package.json", "composer.json", "tasks.json", "launch.json", ".pre-commit-config.yaml", ".pre-commit-config.yml",
            "lefthook.yml", "lefthook.yaml", "docker-compose.yml", "docker-compose.yaml", ".gitlab-ci.yml", "pubspec.yaml", "Pipfile"}
_DELIM = re.compile(r"""(?:'[A-Za-z0-9_]+'|"[A-Za-z0-9_]+"|[A-Za-z0-9_]+)""")
_SK_BAD = frozenset(("if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "function", "select",
                     "coproc", "trap", "eval", "source", "exec", "{", "}"))
_SK_KEEP = frozenset(WRAPPERS) | {"env", "command", "builtin", "!"}


def _sk_dq(s, i, depth):
    """Index just past the closing " of a double-quoted string that starts after s[i - 1], or -1 when it holds anything not modeled."""
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\x22":
            return i + 1
        if c == "\\":
            if s[i + 1:i + 2] == "\n":
                return -1
            i += 2
        elif c == "`":
            return -1
        elif c == "$":
            nxt = s[i + 1:i + 2]
            if nxt == "(":
                if s[i + 2:i + 3] == "(":
                    return -1
                i = _sk(s, i + 2, depth + 1, True)
                if i < 0:
                    return -1
            elif nxt in ("{", "["):
                return -1
            else:
                i += 1
        else:
            i += 1
    return -1


def _sk(s, i, depth, sub):
    """Parse s[i:] as a command list made only of modeled constructs: the index just past it (past the ) of a $( … ) when sub), or -1."""
    if depth > 12:
        return -1
    n, word, cmdpos, target = len(s), [], True, False

    def flush():
        nonlocal word, cmdpos, target
        if not word:
            return True
        w = "".join(word)
        word = []
        if target:
            target = False
            return True
        if w in _SK_BAD or (w == "." and cmdpos):
            return False
        cmdpos = cmdpos and (w in _SK_KEEP or ASSIGN.match(w) is not None)
        return True

    while i < n:
        c = s[i]
        if c in " \t":
            if not flush():
                return -1
            i += 1
        elif c == "\n":
            if not flush():
                return -1
            cmdpos, i = True, i + 1
        elif c == "#" and not word:        # a comment: it ends at the newline, which stays
            k = s.find("\n", i)
            i = n if k < 0 else k
        elif c == "\\" or c == "`" or c == "(":
            return -1
        elif c == "'":
            k = s.find("'", i + 1)
            if k < 0:
                return -1
            word.append("q")
            i = k + 1
        elif c == "\x22":
            i = _sk_dq(s, i + 1, depth)
            if i < 0:
                return -1
            word.append("q")
        elif c == "$":
            nxt = s[i + 1:i + 2]
            if nxt == "(":
                if s[i + 2:i + 3] == "(":
                    return -1
                i = _sk(s, i + 2, depth + 1, True)
                if i < 0:
                    return -1
                word.append("q")
            elif nxt in ("{", "[", "\x27", "\x22"):
                return -1
            else:
                word.append("v")
                i += 1
        elif c == ")":
            return i + 1 if sub and flush() else -1
        elif c in "<>":
            if s.startswith(("<<<", "<(", ">("), i):
                return -1
            if word and "".join(word).isdigit():
                word = []                  # a descriptor: 2>&1
            elif not flush():
                return -1
            if s.startswith("<<", i):
                j = i + 2 + (s[i + 2:i + 3] == "-")
                while j < n and s[j] in " \t":
                    j += 1
                m = _DELIM.match(s, j)
                if not m or (m.end() < n and s[m.end()] not in " \t\n;|&)<>"):
                    return -1
                i = m.end()
            else:
                i += 1
                if s[i:i + 1] in (">", "&", "|") and c == ">" or s[i:i + 1] in ("&", ">") and c == "<":
                    i += 1
                target = True
        elif c == "&":
            if s.startswith("&&", i):
                if not flush():
                    return -1
                cmdpos, i = True, i + 2
            elif s.startswith("&>", i):
                if not flush():
                    return -1
                i += 3 if s.startswith("&>>", i) else 2
                target = True
            else:
                return -1                  # a background &
        elif c == "|" or c == ";":
            if s.startswith(";;", i) or not flush():
                return -1
            cmdpos, i = True, i + (2 if s.startswith(("||", "|&"), i) else 1)
        else:
            word.append(c)
            i += 1
    return -1 if sub or not flush() else n


def _modeled(text, docs):
    """True when the text outside the heredoc bodies is made only of constructs the scanner models, and every heredoc word is plain
    and terminated: only then is where the scanner puts a body where the shell puts it."""
    if re.search(r"[\x00-\x08\x0b-\x1f\x7f]", text):
        return False
    out, pos = [], 0
    for h in sorted(docs, key=lambda d: d.op_start):
        raw = text[h.op_start + 2:h.op_end].lstrip("-").strip(" \t")
        if not h.terminated or h.body_start < pos or _DELIM.fullmatch(raw) is None:
            return False
        out.append(text[pos:h.body_start])
        pos = h.end
    out.append(text[pos:])
    s = "".join(out)
    return _sk(s, 0, 0, False) == len(s)


_PATHW = r"[A-Za-z0-9_./~+@-]+"
_DELIMW = _DELIM.pattern
_STMT = [re.compile(p) for p in (
    r"cat\s*>>?\s*(?P<t>%s)\s*<<-?\s*%s(?:\s+2>/dev/null)?" % (_PATHW, _DELIMW),
    r"cat\s*<<-?\s*%s\s*>>?\s*(?P<t>%s)(?:\s+2>/dev/null)?" % (_DELIMW, _PATHW),
    r"tee\s+(?:-a\s+)?(?P<t>%s)\s*<<-?\s*%s" % (_PATHW, _DELIMW),
    r"git\s+commit(?:\s+(?:-q|-s|-a|-v|--quiet|--signoff|--all|--verbose|--allow-empty|--amend|--no-edit))*"
    r"\s+(?:-F\s*-|--file=-|--file\s+-)(?:\s+(?:-q|-s|-a|-v|--quiet|--signoff|--all|--verbose|--allow-empty|--amend|--no-edit))*"
    r"\s*<<-?\s*%s" % _DELIMW)]
_PREFIX = re.compile(r"(?:(?:cd|mkdir\s+-p)\s+%s\s*&&\s*)*" % _PATHW)


def _text_target(t):
    base = t.rsplit("/", 1)[-1]
    return (os.path.splitext(base)[1].lower() in TEXT_EXT and base not in NOT_TEXT
            and not HOOKDIR.search(t) and not HOOKNAME.search(t) and not t.startswith("-"))


def _file_statement(text, h, ndocs):
    """True when the heredoc is the ONE statement of the command: cat > F <<EOF (also >>, or the redirect after the word), tee F or
    git commit -F -, optionally after `cd DIR &&` / `mkdir -p DIR &&`, with only blank lines and comments around it, and F is a text
    file (TEXT_EXT) that is no hook, no config and no script."""
    if ndocs != 1 or not h.terminated:
        return False
    ls = text.rfind("\n", 0, h.op_start) + 1
    nl = text.find("\n", h.op_end)
    line = text[ls:nl if nl >= 0 else len(text)].strip()
    around = text[:ls].splitlines() + text[h.end:].splitlines()
    if any(x.strip() and not x.strip().startswith("#") for x in around):
        return False
    rest = line[_PREFIX.match(line).end():].strip()
    for rx in _STMT:
        m = rx.fullmatch(rest)
        if m:
            return "t" not in rx.groupindex or _text_target(m.group("t"))
    return False


_MSG = {("git", "commit"): ("-m", "--message"), ("git", "tag"): ("-m", "--message"), ("git", "merge"): ("-m", "--message"),
        ("git", "notes"): ("-m", "--message"),
        ("gh", "pr"): ("-b", "--body", "-t", "--title"), ("gh", "issue"): ("-b", "--body", "-t", "--title"),
        ("gh", "release"): ("-n", "--notes", "-t", "--title")}
_MSG_SUB = {"pr": ("create", "comment", "edit", "review"), "issue": ("create", "comment", "edit"), "release": ("create",),
            "notes": ("add", "append")}


def _message_arg(text, h):
    """True when the heredoc is `"$(cat <<'EOF' … EOF\\n)"` as the VALUE of the message option of a known command: git commit | tag |
    merge | notes add -m / --message, gh pr | issue create | comment | edit | review -b / --body / -t / --title, gh release create
    -n / --notes / -t / --title. cat is the only reader and the delimiter is quoted; never for -c, config, alias, -e, bisect run …"""
    if not (h.in_dq and h.quoted and h.terminated):
        return False
    k = text.rfind("\x22$(", 0, h.op_start)
    nl = text.find("\n", h.op_end)
    if (k < 0 or text[k + 3:h.op_start].strip() != "cat" or text[h.op_end:nl if nl >= 0 else len(text)].strip()
            or not re.match(r"\s*\)\x22", text[h.end:])):
        return False
    words = _words(re.split(r"&&|\|\||[;|\n]", text[:k])[-1])
    prog, rest = _program(words)
    if prog not in ("git", "gh") or not rest:
        return False
    opt = rest[-1][:-1] if rest[-1].startswith("--") and rest[-1].endswith("=") else rest[-1]
    pos = [a for a in rest[:-1] if not a.startswith("-")]
    if any(a in ("-c", "--config-env") for a in rest[:-1]) or not pos or (prog, pos[0]) not in _MSG:
        return False
    opts = _MSG[(prog, pos[0])]
    if opt not in opts and not (prog == "git" and pos[0] != "notes" and re.fullmatch(r"-[A-Za-z]*m", opt)):
        return False
    return prog == "git" and pos[0] != "notes" or (len(pos) > 1 and pos[1] in _MSG_SUB[pos[0]])


SOURCE_EXT = {".py": "python3", ".js": "node", ".mjs": "node", ".cjs": "node", ".rb": "ruby", ".pl": "perl", ".php": "php"}


def _source_target(text, h):
    """The interpreter of the script a cat / tee heredoc writes (cat > x.py <<EOF → python3), from the extension of the file; "" else.
    Such a body is judged as source by the git guard whatever follows, and never cut: it may be run by anything."""
    ls = text.rfind("\n", 0, h.op_start) + 1
    nl = text.find("\n", h.op_end)
    line = text[ls:nl if nl >= 0 else len(text)]
    m = re.search(r">>?\s*(%s)|\btee\s+(?:-a\s+)?(%s)" % (_PATHW, _PATHW), line)
    return SOURCE_EXT.get(os.path.splitext(m.group(1) or m.group(2))[1].lower(), "") if m else ""


def _classify(text, h, seps, pipes, cut, ndocs):
    """Set h.reader and h.kind. The reader is the command the operator belongs to (the one just before it on its line, inside
    any $( … )) and the top-level command around it, with the stages of its pipeline. kind: "shell" a shell reads it (here or far),
    "interp" an interpreter reads it as its program, "source" it is written to a script (never cut), "data" it is a message or the one file statement (never run), else "other";
    only "data" and "interp" are ever cut, and only when the command is modeled (h.cut_ok)."""
    start = max((e for s, e in seps if e <= h.op_start), default=0)
    end = min((s for s, e in seps if s >= h.op_end), default=len(text))
    stages, pos, mine = [], start, 0
    for p in [p for p in pipes if start <= p < end] + [end]:
        if pos <= h.op_start < p:
            mine = len(stages)
        stages.append(_program(_words(_segment(text, pos, p, cut).lstrip("&"))))
        pos = p + 1
    line_start = text.rfind("\n", 0, h.op_start) + 1
    near = re.split(r"&&|\|\||[;|(]|\$\(|`", text[line_start:h.op_start])[-1]
    inner, inner_rest = _program(_words(near))
    top, top_rest = stages[mine]
    h.reader = inner or top
    if any(p in SHELL_RUNNERS or (p in ("adb", "adb.exe") and adb_shell(r)) for p, r in stages + [(inner, inner_rest)]):
        h.kind = "shell"
    elif _interp(inner) and _program_on_stdin(inner, inner_rest):          # python3 - <<EOF, also inside $( … )
        h.kind, h.reader = "interp", inner
    elif any(_interp(p) and _program_on_stdin(p, r) for p, r in stages[mine + 1:]):   # cat <<EOF | python3 -
        h.kind, h.reader = "interp", next(p for p, r in stages[mine + 1:] if _interp(p) and _program_on_stdin(p, r))
    elif h.depth and _interp(top) and _program_inline(top, top_rest):      # python3 -c "$(cat <<EOF …)"
        h.kind, h.reader = "interp", top
    elif inner in ("cat", "tee") and _source_target(text, h):               # cat > x.py <<EOF: a script, run by who knows
        h.kind, h.reader = "source", _source_target(text, h)
    elif _message_arg(text, h) or _file_statement(text, h, ndocs):
        h.kind = "data"
    else:
        h.kind = "other"


def heredocs(text):
    """[Heredoc] of a command line, in order, each with its reader and kind. The shell's rules: `<<` / `<<-` (not `<<<`) outside
    quotes, comments and arithmetic starts one; a quote or backslash in its word makes the body literal; the body starts after
    the end of the line that holds the operator (several heredocs on one line follow each other) and ends at a line that is
    exactly the word (leading tabs dropped for <<-). Inside $( … ) and backticks the same holds. h.cut_ok: the command is modeled
    (_modeled) and has at most MAX_HEREDOCS heredocs: no body of a command that is not is ever cut."""
    docs, seps, pipes = _scan(text)
    cut = sorted((h.body_start, h.end) for h in docs if h.end > h.body_start)
    many = len(docs) > MAX_HEREDOCS   # each heredoc is classified against the whole text: past the bound nothing is cut
    ok = bool(docs) and not many and _modeled(text, docs)
    for h in docs:
        h.cut_ok = ok
        if many:
            h.kind = "shell"
        else:
            _classify(text, h, seps, pipes, cut, len(docs))
    return docs


def expansions(body):
    """The command substitutions the shell runs in an UNQUOTED heredoc body: each $( … ) and `…`, whole, in order (\\$ and
    \\` are literal)."""
    out, i, n = [], 0, len(body)
    while i < n:
        c = body[i]
        if c == "\\":
            i += 2
        elif c == "$" and body.startswith("(", i + 1):
            depth, j = 1, i + 2
            while j < n and depth:
                if body[j] == "\\":
                    j += 2
                    continue
                depth += {"(": 1, ")": -1}.get(body[j], 0)
                j += 1
            out.append(body[i:j])
            i = j
        elif c == "`":
            j = i + 1
            while j < n and body[j] != "`":
                j += 2 if body[j] == "\\" else 1
            out.append(body[i:j + 1])
            i = j + 1
        else:
            i += 1
    return out


def strip_heredocs(text, drop, docs=None):
    """text with the body and delimiter line of each heredoc h with drop(h) true cut out. An unquoted body that is cut leaves
    its command substitutions in its place, one per line: the shell runs them whatever reads the body. A heredoc with no
    delimiter line is never cut (the rest of the text stays commands to judge: fail closed)."""
    docs = heredocs(text) if docs is None else docs
    out, pos = [], 0
    for h in docs:
        if not h.terminated or not h.cut_ok or h.body_start < pos or not drop(h):
            continue
        out.append(text[pos:h.body_start])
        if not h.quoted:
            out.extend(e + "\n" for e in expansions(h.body(text)))
        pos = h.end
    out.append(text[pos:])
    return "".join(out)
