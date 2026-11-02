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
    A body ends at the delimiter line the shell finds (15/10 r4, marker runs under bash 3.2 and zsh): an unquoted one joins its
    backslash-newline lines first, so E\\<newline>OF IS the delimiter; where the shells disagree (a quoted heredoc inside $( ) or
    backticks) nothing of the command is cut. join_continuations: a backslash-newline joins only when its backslash is not escaped.
  - one lexer (lex_words, 15/10 r5): a newline outside quotes is a separator word of its own and a newline inside quotes stays as typed, so a
    quoted script (bash -c '…') reaches the second pass exactly as the shell hands it over; the guards no longer rewrite newlines. A text is
    judged once per reading (readings): continuations joined, and, when a comment ends in a backslash, with the continuations kept as newlines.
  - an interpreter program is cut from the scan only when it cannot start a process (spawns) AND nothing takes its output (Heredoc.captured,
    program_cut): the shell runs what a program prints in a $( ), a redirect or a pipe.
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
                       r"|\bposix_spawnp?\b|\breadpipe\b|\bsyscall\b|\bget(?:status)?output\b|\bpcntl_exec\b|\bspawn_sync\b"
                       # 15/10 r5: JavaScript runtimes that start a process with a TAGGED TEMPLATE ($`cmd`: zx, Bun shell, dax: the tag itself, or the module name for the call forms
                       # $.sync`…` and $({…})`…`) or a Deno call (Deno.Command, Deno.run)
                       r"|\$\s*`|\bzx\b|\bdax\b|\bDeno\.(?:Command|run)\b", re.I)


def spawns(body, prog):
    """True when the program text body of interpreter prog can start a process."""
    return bool(EXEC_SINK.search(body) or (re.match(r"(?:ruby|perl|php)", prog or "") and "`" in body))


def program_cut(h, text):
    """True when the body of the interpreter heredoc h (h.kind == "interp") is only a program's data and may be cut from the scan: it cannot start a process
    (spawns) AND nothing takes its output (h.captured: the shell runs what a program prints in $( ), a redirect or a pipe, 15/10 r5). One predicate for both guards."""
    return h.kind == "interp" and not h.captured and not spawns(h.body(text), h.reader)


class Heredoc:
    """One heredoc. op_start / op_end: the << operator and its word; body_start / body_end: the body; end: just past its
    delimiter line. quoted: a quote or backslash in the word (the shell expands nothing in the body). terminated: a delimiter
    line was found. depth: nesting of $( … ) / ( … ) / `…` at the operator. reader: the program the body (or the text it becomes)
    goes to. kind: "shell" (a shell reads it, here or far), "interp" (an interpreter reads it as its program), "data" (the message
    of a known option or the one file statement of the command, never run: _message_arg, _file_statement) or "other" (anything
    else). cut_ok: the whole command is modeled (_modeled) and no heredoc of it is ambiguous: only then may a body be cut
    (strip_heredocs). in_dq: the operator sits in a double-quoted $( … ). in_subst: it sits in a $( … ) or in backticks. ambiguous:
    the shells read its delimiter line differently (_read_bodies): a quoted body in a $( … ) or backticks, where bash 3.2 removes a
    backslash-newline first and zsh does not. captured (kind "interp" only): something takes what the program prints, a $( ) / backtick / group around it, a
    redirect or a pipe after it (_classify): the shell may run the output."""
    __slots__ = ("op_start", "op_end", "delim", "quoted", "strip_tabs", "depth", "body_start", "body_end", "end",
                 "terminated", "reader", "kind", "in_dq", "cut_ok", "in_subst", "ambiguous", "captured")

    def __init__(self, op_start, op_end, delim, quoted, strip_tabs, depth):
        self.op_start, self.op_end, self.delim, self.quoted = op_start, op_end, delim, quoted
        self.strip_tabs, self.depth = strip_tabs, depth
        self.body_start = self.body_end = self.end = op_end
        self.terminated, self.reader, self.kind, self.in_dq, self.cut_ok = False, "", "other", False, False
        self.in_subst = self.ambiguous = self.captured = False

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


# \c + @/cách/backtick, \c + U+0800..U+0FFF (byte UTF-8 đầu 0xE0), \C- của zsh: đều ra NUL.
_ANSI_NUM = re.compile(
    r"\\(?:x([0-9A-Fa-f]{1,2})|u([0-9A-Fa-f]{1,4})|U([0-9A-Fa-f]{1,8})|([0-7]{1,3})"
    r"|(c[@ `])|(c[\u0800-\u0fff])|(C-[@ `])"
    r"|((?:c|C-|M-)\\(?:x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8}|[0-7]{1,3})))"   # \c \C- \M- before a numeric escape: the byte it makes is not modelled, read as NUL (audit T0131)
)


def _ansi_num(esc):
    """The text of one \\xHH / \\NNN / \\uHHHH / \\UHHHHHHHH / \\c@ / \\C-@ escape of a $'…' as the shell decodes it, or None when it is another escape (kept as typed).
    A NUL (code 0, \\c@ \\c<space> \\c<backtick>, \\c + U+0800..U+0FFF, or zsh \\C-@ \\C-<space> \\C-<backtick>) ends the word in bash: it returns a lone NUL for the caller (ansi_c_to_single), which drops the rest of the body (#618); a quote becomes '\\'' (close, literal quote, reopen) so the plain '…' around it stays paired (#526)."""
    m = _ANSI_NUM.fullmatch(esc)
    if not m:
        return None
    hexa, u4, u8, octal, ctrl, utf, cword, nested = m.groups()
    if ctrl or utf or cword or nested:   # control-X là X & 0x1f; ba nhóm này đều ra NUL
        return "\0"
    code = int(hexa or u4 or u8 or octal, 16 if octal is None else 8)
    if octal is not None:
        code &= 0xFF
    if code == 0:
        return "\0"
    if code > 0x10FFFF or 0xD800 <= code <= 0xDFFF:
        return ""
    ch = chr(code)
    return "'\\''" if ch == "'" else ch


def ansi_c_to_single(text, cut_at_nul=True):
    """text with every $'...' outside quotes rewritten as a plain '...' (issue #7: shlex has no $'...', so the backslash-quote inside one ended its quote and
    the lexer paired the quotes of the REST of the line the other way round, which hid a command after it). An escaped quote inside becomes '\\'' (close,
    literal quote, reopen). \\xHH, \\NNN, \\uHHHH and \\UHHHHHHHH are decoded (#526: $'\\x67it' is git, and the rules read the name); the other escapes stay as typed: the text of the word is not what is judged here, its boundaries are.
    An unterminated $'... is left as it is. A backslash escapes inside "..." too (a \" does not close it), and a $ right after an odd run of $ is no start:
    $$ is the PID, so in $$'...' the quote is a plain one."""
    if "$'" not in text:
        return text
    out, i, n, q, dr = [], 0, len(text), None, 0   # dr: the run of $ just before i, outside quotes
    while i < n:
        c = text[i]
        if q != "'" and c == "\\" and i + 1 < n:
            out.append(text[i:i + 2]); i += 2; dr = 0; continue
        if q is None and c == "$" and text.startswith("'", i + 1) and dr % 2 == 0:
            j, body = i + 2, []
            while j < n and text[j] != "'":
                if text[j] == "\\" and j + 1 < n:
                    m = _ANSI_NUM.match(text, j)
                    if m:
                        dec = _ansi_num(m.group(0))
                        if dec == "\0" and cut_at_nul:   # bash kết thúc từ tại NUL: bỏ phần thân còn lại tới nháy đóng (#618)
                            j = m.end()
                            while j < n and text[j] != "'":
                                j += 2 if text[j] == "\\" and j + 1 < n else 1
                            break
                        if dec == "\0":   # cách đọc không cắt: NUL là chỗ ngăn từ (không dán hai bên), giữ phần sau (audit T0131)
                            body.append(" "); j = m.end(); continue
                        body.append(dec); j = m.end(); continue
                    body.append("'\\''" if text[j + 1] == "'" else text[j:j + 2]); j += 2
                else:
                    body.append(text[j]); j += 1
            if j >= n:
                out.append(text[i:]); break
            out.append("'" + "".join(body) + "'"); i = j + 1; dr = 0; continue
        if c in "'\"":
            q = None if q == c else (q or c)
        dr = dr + 1 if c == "$" and q is None else 0
        out.append(c); i += 1
    return "".join(out)


def lex_words(text):
    """The words of a command line as the guards read them, the ONE lexer of both: quotes removed, and ; & | ( ) and a NEWLINE outside quotes words of their
    own (a run of them is one word: &&, ;;, |<nl>), so a newline is a command separator by itself. A newline INSIDE quotes stays in its word exactly as typed.
    ValueError on an unbalanced quote or a trailing backslash. 15/10 r5: both guards used to rewrite every newline of the text to " ;<nl>" before they lexed
    it. That also rewrote the newlines of a quoted script (bash -c '…', eval, ssh host '…'), so a heredoc terminator of that script read "EOF ;" and a later
    line equal to the delimiter swallowed the real command (the verdict of the script differed from the verdict of the same text typed at top level)."""
    text = ansi_c_to_single(text)
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|()\n")
    lex.whitespace, lex.whitespace_split, lex.commenters = " \t\r", True, ""   # real comments are cut by the guards (drop_comments); a # left in a word is data
    return list(lex)


def dq_nested_quote(text):
    """True when a double-quoted string of text holds a $( … ) that holds a double quote of its own ("$(echo "a b"; rm -rf ~)"): the lexer pairs the quotes across the
    substitution, and what the shell runs inside it ends up inside a word. The caller reads such a text as one that does not parse (15/10 r6, review P1-3). Only
    double quotes: a single quote inside "…" is data to the lexer as well. The parentheses are counted without regard to strings: where that is wrong the text is
    flagged or not, never mis-read."""
    i, n, dq = 0, len(text), False
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
        elif c == "\x27" and not dq:
            k = text.find("\x27", i + 1)
            i = n if k < 0 else k + 1
        elif c == "$" and dq and text.startswith("(", i + 1):
            depth, j = 1, i + 2
            while j < n and depth:
                d = text[j]
                if d == "\x22":
                    return True
                if d == "\\":
                    j += 2
                    continue
                depth += (d == "(") - (d == ")")
                j += 1
            i = j
        else:
            dq = not dq if c == "\x22" else dq
            i += 1
    return False


_CONTINUATION = re.compile(r"(?<!\\)((?:\\\\)*)\\\n")


def join_continuations(text):
    """text with every line continuation removed: a backslash-newline whose backslash is not itself escaped, so an ODD run of
    backslashes before the newline (a\\\\<newline> is an escaped backslash and a real newline: bash and zsh agree, and both guards joined
    it, which hid the next line, 15/10 r4 review). One regex pass, linear."""
    return _CONTINUATION.sub(r"\1", text) if "\\\n" in text else text


def drop_comments(text):
    """The text without its shell comments: a # that begins a word, outside quotes, up to the end of its line. A # inside a word
    (a#b, $#, an escaped space before it, the ) that ends a substitution), inside ${ } or inside backticks is data, as in bash.
    Quotes, ${ or a backtick still open at the end: from where the first of them opened the text stays whole (fail closed), the comments before it
    are dropped (15/10 r6: the whole text kept its comments, and the apostrophe of one paired with a later real quote in the scanners after this).
    2026-10-10: shlex dropped everything after any #,
    so a command after a comment line or after a#b was never judged; the first fix still read an escaped space, a CR, a ) and a
    # inside ${ } or backticks as a word start (independent review).
    Issue #7: a backslash-newline outside quotes is a continuation, not an escaped character: the # after it starts a word when the character
    BEFORE the backslash would let it (`x \\<nl># '` is a comment, so the next line runs). An escaped $ opens neither ${ } nor $'…'."""
    out, i, n, q, brace, bt, esc = [], 0, len(text), None, 0, False, False
    base = (0, 0)   # (chunks of out, index in text) where the last stretch with nothing open began
    prev = ""   # the last character of the text as the shell reads it: a continuation (backslash-newline) is not one
    dr = 0      # the run of $ just before i: $$ is the PID, so $$' and $${ open nothing
    while i < n:
        c = text[i]
        if q is None and not (brace or bt):
            base = (len(out), i)
        prev_esc, esc = esc, False
        if q is None:
            if c == "\\" and i + 1 < n:
                out.append(text[i:i + 2]); i += 2
                if text[i - 1] == "\n":
                    esc = prev_esc   # a continuation joins what is on both sides: the escape state of the character before it carries over
                else:
                    esc, prev, dr = True, text[i - 1], 0
                continue
            if c in "\x27\x22":
                q = "$\x27" if c == "\x27" and prev == "$" and dr % 2 == 1 and not prev_esc else c
            elif c == "`":
                bt = not bt
            elif c == "{" and prev == "$" and dr % 2 == 1 and not prev_esc:
                brace += 1
            elif c == "}" and brace:
                brace -= 1
            elif c == "#" and not (brace or bt) and (not prev or (not prev_esc and prev in " \t\n;&|(")):
                while i < n and text[i] != "\n":
                    i += 1
                continue
        else:
            if c == "\\" and q != "\x27" and i + 1 < n:
                out.append(text[i:i + 2]); i += 2; continue
            if c == q[-1]:
                q = None
        out.append(c); i += 1; prev = c; dr = dr + 1 if c == "$" else 0
    return "".join(out[:base[0]]) + text[base[1]:] if (q or brace or bt) else "".join(out)


def _comment_continuation(text):
    """True when a line of text that holds a # ends in a continuation: a comment, or something that looks like one, that ends in a backslash."""
    for m in _CONTINUATION.finditer(text):
        if "#" in text[text.rfind("\n", 0, m.start()) + 1:m.start()]:
            return True
    return False


def readings(text):
    """The texts a guard lexes, each judged and the verdicts added (blocked when ANY blocks): text with its continuations joined (what the shell does with
    them), and, only when a COMMENT ends in a backslash (_comment_continuation), text with each continuation kept as the plain newline it is. A comment ends
    at its newline whatever precedes it, and inside SINGLE quotes a backslash-newline is literal for the outer shell: the script it hands to bash -c / eval /
    ssh is `true # c\\<nl>` and a dangerous line, whose next line RUNS, and the joined reading glued it to the comment (15/10 r5, OLD too). That is the only
    place the two differ: a continuation is the inner shell's own to join, and only a comment makes it stay a line break. Which quotes a continuation sits
    in is another model of the shell, two readings are not. The price, pinned in the tests: a comment ending in a backslash inside DOUBLE quotes (the outer
    shell removes it there and nothing runs) is refused all the same."""
    joined = join_continuations(text)
    if joined == text:
        out = [joined]
    else:
        out = [joined]
        kept = _join_outside_single_quotes(text)   # 15/10 r6: the join of the outer text also joined inside the single quotes of a -c script and moved its quoted terminator
        if kept != joined:
            out.append(kept)
        if _comment_continuation(text):
            out.append(_CONTINUATION.sub(r"\1\n", text))
    # Cách đọc không cắt NUL: shell không nuốt phần sau NUL vẫn chạy lệnh đó. Chặn khi bất kỳ cách đọc nào chặn.
    extra = []
    for t in out:
        uncut = ansi_c_to_single(t, cut_at_nul=False)
        if uncut != ansi_c_to_single(t) and uncut not in out and uncut not in extra:
            extra.append(uncut)
    return out + extra


_QUOTE_OR_ESCAPE = re.compile(r"[\\'\x22$)]")


def _join_outside_single_quotes(text):
    """text with the backslash-newlines joined as the OUTER shell joins them: not inside single quotes or $'…' (literal there: the script a -c script gets is
    its own, the inner shell joins it itself, and not inside a quoted heredoc body of that script: x\\<newline>EOF is no terminator there), yes outside quotes
    and inside "…" (a $( ) inside "…" is a context of its own again). Read in addition to the text joined everywhere, never instead: where this model of the
    shell is wrong the other reading still holds what the old one held."""
    out, i, n, stack = [], 0, len(text), []   # stack: "dq" inside "…", "sub" inside $( )
    while i < n:
        m = _QUOTE_OR_ESCAPE.search(text, i)
        if not m:
            out.append(text[i:])
            break
        k, c = m.start(), m.group()
        out.append(text[i:k])
        dq = bool(stack) and stack[-1] == "dq"
        i = k + 1
        if c == "\\":
            if text[k + 1:k + 2] != "\n":
                out.append(text[k:k + 2])
            i = k + 2
        elif c == "\x27" and not dq:   # single quotes: literal up to the next one
            e = text.find("\x27", k + 1)
            e = n - 1 if e < 0 else e
            out.append(text[k:e + 1])
            i = e + 1
        elif c == "$" and text.startswith("\x27", k + 1) and not dq:   # $'…': backslash escapes inside, a continuation among them stays
            e = k + 2
            while e < n and text[e] != "\x27":
                e += 2 if text[e] == "\\" else 1
            out.append(text[k:e + 1])
            i = e + 1
        elif c == "\x22":
            if dq:
                stack.pop()
            else:
                stack.append("dq")
            out.append(c)
        elif c == "$" and text.startswith("(", k + 1):
            stack.append("sub")
            out.append("$(")
            i = k + 2
        elif c == ")" and stack and stack[-1] == "sub":
            stack.pop()
            out.append(c)
        else:
            out.append(c)
    return "".join(out)


def _find_end(text, pos, h, join):
    """(body_end, end, terminated) of heredoc h whose body starts at text[pos]: the first line equal to the delimiter (tabs dropped for
    <<-). join: the shell removes a backslash-newline before it compares, so a delimiter split by one (E\\<newline>OF) is the delimiter
    and a line ended by an odd run of backslashes takes the next line (x\\<newline>EOF is xEOF). No delimiter line: the rest of the text."""
    n = len(text)
    while pos < n:
        eol = text.find("\n", pos)
        line = text[pos:] if eol < 0 else text[pos:eol]
        nxt = n if eol < 0 else eol + 1
        while join and eol >= 0 and (len(line) - len(line.rstrip("\\"))) % 2:
            eol = text.find("\n", nxt)
            line = line[:-1] + (text[nxt:] if eol < 0 else text[nxt:eol])
            nxt = n if eol < 0 else eol + 1
        if (line.lstrip("\t") if h.strip_tabs else line).rstrip("\r") == h.delim:
            return pos, nxt, True
        pos = nxt
    return n, n, False


def _read_bodies(text, nl, pending):
    """Fill in the bodies of the heredocs of the line that ends at the newline text[nl], in order; the index just past the
    last delimiter line. A heredoc with no delimiter line takes the rest of the text (terminated stays False).
    Where the delimiter line is: an unquoted body joins its continuation lines first (bash and zsh, marker runs of 15/10 r4: E\\<newline>OF
    ends it), a quoted one at top level joins nothing, and a quoted one inside $( … ) or backticks is read both ways (bash 3.2 removes
    the continuations of a $( … ), zsh and bash 5 do not; backticks: both do): the earlier end is taken and the heredoc is ambiguous,
    which keeps every body of the command in the scan (heredocs)."""
    pos = nl + 1
    for h in pending:
        h.body_start = pos
        reads = [_find_end(text, pos, h, not h.quoted)]
        if h.quoted and h.in_subst:
            reads.append(_find_end(text, pos, h, True))
        h.ambiguous = len(set(reads)) > 1
        h.body_end, h.end, h.terminated = min(reads, key=lambda r: (r[1], not r[2]))
        pos = h.end
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
                h.in_subst = "cmd$" in frames or "cmd`" in frames
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
        # sudo -s / -i / --shell (doas -s) with no command word starts a shell that reads its stdin: inline_script needs a word to turn
        # into `sh -c STR`, so one is lent here and the answer is "sh" only when that is what came out (15/10 r4: it was "", a reader that is no shell)
        lent = inline_script(list(words) + ["_"])
        return ("sh", []) if lent[-3:-1] == ["sh", "-c"] else ("", [])
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
    k = 1 if prog in ("deno", "bun") and rest[:1] == ["run"] else 0   # deno run -A - <<EOF: run is the subcommand, the program comes from stdin
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


def _code_operand(inner, top, top_rest, tail):
    """True when the heredoc is `$(cat <<EOF … EOF\\n)` as the word right after the inline-code option of an interpreter (python3 -c "$(cat
    <<'EOF' …)"): what cat prints IS the program, nothing else reads it, and the operator ends its line (no pipe or redirect after it). The
    body of `python3 -c "pass" "$(cat <<EOF …)"` is a later ARGUMENT: the program may run it (node -e "…execSync(process.argv[1])", 15/10 r4)."""
    if inner != "cat" or tail.strip() or not _interp(top):
        return False
    inline = INTERP_OPTS[_interp(top)][1]
    k = next((j for j, a in enumerate(top_rest) if a in inline and a not in ("-m", "-f")), -1)
    return 0 <= k < len(top_rest) - 1 and top_rest[k + 1].startswith("$(")


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
# Only a file that is PROSE for people is a data target: nothing a tool executes or reads as configuration (json, yaml, toml, xml, sql,
# patch, Taskfile, settings, CI files …), no path without an extension, no script, no shell startup file, no Makefile, no hook.
TEXT_EXT = {".md", ".markdown", ".txt", ".rst"}
# Not prose for people even with a prose extension (15/10 r4): the instruction files an agent reads (CLAUDE.md, AGENTS.md, GEMINI.md), the build and
# dependency lists a tool reads (CMakeLists.txt, requirements*.txt, constraints*.txt), and anything in a folder an agent or its host reads as config.
NOT_PROSE_NAME = re.compile(r"(?:claude|agents|gemini)\.md|cmakelists\.txt|(?:.*[-_.])?(?:requirements|constraints)(?:[-_.].*)?\.txt", re.I)
AGENT_DIR = re.compile(r"(?:^|[/\s'\"=])\.(?:claude|agents|gemini|codex|cursor|github)(?:/|[\s'\"`)]|$)", re.I)
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
    """True when the text outside the heredoc bodies is made only of constructs the scanner models (a heredoc word that is not plain
    fails the parse too): only then is where the scanner puts a body where the shell puts it."""
    if re.search(r"[\x00-\x08\x0b-\x1f\x7f]", text):
        return False
    out, pos = [], 0
    for h in sorted(docs, key=lambda d: d.op_start):
        if h.body_start < pos:
            return False
        out.append(text[pos:h.body_start])
        pos = h.end
    out.append(text[pos:])
    s = "".join(out)
    return _sk(s, 0, 0, False) == len(s)


_PATHW = r"[A-Za-z0-9_./~+@-]+"
_ARGW = r"[A-Za-z0-9_./=:@+,-]+"   # a plain word: an option of git commit or a path after --, nothing the shell expands or quotes
_DELIMW = _DELIM.pattern
_STMT = [re.compile(p) for p in (
    r"cat\s*>>?\s*(?P<t>%s)\s*<<-?\s*%s(?:\s+2>/dev/null)?" % (_PATHW, _DELIMW),
    r"cat\s*<<-?\s*%s\s*>>?\s*(?P<t>%s)(?:\s+2>/dev/null)?" % (_DELIMW, _PATHW),
    r"tee\s+(?:-a\s+)?(?P<t>%s)\s*<<-?\s*%s" % (_PATHW, _DELIMW),
    r"git\s+commit(?:\s+%s)*?\s+(?:-F\s*-|--file=-|--file\s+-)(?:\s+%s)*\s*<<-?\s*%s" % (_ARGW, _ARGW, _DELIMW))]
_PREFIX = re.compile(r"(?:(?:cd|mkdir\s+-p)\s+%s\s*&&\s*)*" % _PATHW)


def _text_target(t, prefix=""):
    """t: the file written; prefix: the `cd DIR &&` / `mkdir -p DIR &&` before the statement (a prose file in a hooks dir is no data either)."""
    base = t.rsplit("/", 1)[-1]
    return (os.path.splitext(base)[1].lower() in TEXT_EXT and not base.startswith(".")   # a dotfile is a setting of something, never prose
            and not HOOKDIR.search(prefix + " " + t) and not HOOKNAME.search(t) and not t.startswith("-")
            and not NOT_PROSE_NAME.fullmatch(base) and not AGENT_DIR.search(prefix + " " + t)
            and not t.startswith(("/", "~")) and ".." not in t.split("/"))   # a note file inside the project: no absolute, ~ or .. target


def _file_statement(text, h):
    """True when the heredoc is the ONE statement of the command: cat > F <<EOF (also >>, or the redirect after the word), tee F or
    git commit -F -, optionally after `cd DIR &&` / `mkdir -p DIR &&`, with only blank lines and comments around it (so no second
    heredoc, no later statement), and F is a prose file (TEXT_EXT) outside any hooks dir."""
    if not h.terminated:
        return False
    ls = text.rfind("\n", 0, h.op_start) + 1
    nl = text.find("\n", h.op_end)
    line = text[ls:nl if nl >= 0 else len(text)].strip()
    around = text[:ls].splitlines() + text[h.end:].splitlines()
    if any(x.strip() and not x.strip().startswith("#") for x in around):
        return False
    pre = _PREFIX.match(line).end()
    rest = line[pre:].strip()
    for rx in _STMT:
        m = rx.fullmatch(rest)
        if m:
            return "t" not in rx.groupindex or _text_target(m.group("t"), line[:pre])
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


def _eol(text, i):
    """Index of the first newline at or after i that no backslash escapes (a line continues past one that is), else len(text)."""
    while True:
        nl = text.find("\n", i)
        if nl < 0:
            return len(text)
        k = nl
        while k > 0 and text[k - 1] == "\\":
            k -= 1
        if (nl - k) % 2 == 0:
            return nl
        i = nl + 1


def _classify(text, h, seps, pipes, cut, outside):
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
    # The stages after a pipe on the operator line, at any depth: `pipes` holds the depth-0 pipes only, so `$(cat <<'EOF' | sh` showed no sink
    # and the body was cut as an interpreter program (15/10 r4). Any piece after the first | counts, quotes ignored: more is judged, never less.
    tail = text[h.op_end:_eol(text, h.op_end)]
    later = [_program(_words(x)) for x in re.split(r"[|;&)`]+", tail.split("|", 1)[1])] if "|" in tail else []
    # What takes the output of an interpreter program (15/10 r5): a program that cannot start a process still PRINTS, and the shell runs what is printed when it
    # is captured ($(python3 - <<EOF …), a redirect to a file that is run, a pipe into tee, a { … } > f group). Such a program is judged as a command source and
    # never cut. Textual and wide on purpose, no model of which command a redirect belongs to: any frame around the program ($( ), backticks, ( ), <( ); `own`
    # are the ones that belong to the heredoc itself: python3 -c "$(cat <<EOF …)" has the $( and the quote), or a > or a | anywhere in the command outside the
    # bodies (`feed`: the one pipe that feeds an interpreter from cat <<EOF | python3 - is no capture).
    def taken(own, feed):
        return h.depth > own or ">" in outside or outside.count("|") > feed

    if any(p in SHELL_RUNNERS or (p in ("adb", "adb.exe") and adb_shell(r)) for p, r in stages + [(inner, inner_rest)] + later):
        h.kind = "shell"
    elif _interp(inner) and _program_on_stdin(inner, inner_rest):          # python3 - <<EOF, also inside $( … )
        h.kind, h.reader = "interp", inner
        h.captured = taken(0, 0)
    elif any(_interp(p) and _program_on_stdin(p, r) for p, r in stages[mine + 1:] + later):   # cat <<EOF | python3 -
        h.kind, h.reader = "interp", next(p for p, r in stages[mine + 1:] + later if _interp(p) and _program_on_stdin(p, r))
        h.captured = taken(0, 1)
    elif h.depth and _code_operand(inner, top, top_rest, tail):             # python3 -c "$(cat <<EOF …)"
        h.kind, h.reader = "interp", top
        h.captured = taken(2 if h.in_dq else 1, 0)
    elif inner in ("cat", "tee") and _source_target(text, h):               # cat > x.py <<EOF: a script, run by who knows
        h.kind, h.reader = "source", _source_target(text, h)
    elif _message_arg(text, h) or _file_statement(text, h):
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
    ok = bool(docs) and not many and not any(h.ambiguous for h in docs) and _modeled(text, docs)   # ambiguous: where a body ends is not known
    outside = _segment(text, 0, len(text), cut) if docs and not many else ""   # the command without any body (what _classify reads for a capture)
    for h in docs:
        h.cut_ok = ok
        if many:
            h.kind = "shell"
        else:
            _classify(text, h, seps, pipes, cut, outside)
    return docs


def strip_heredocs(text, drop, docs=None):
    """text with the body and delimiter line of each heredoc h with drop(h) true cut out. Never cut (the text stays commands to
    judge: fail closed): a heredoc with no delimiter line, one of a command that is not modeled, and an UNQUOTED one whose body holds a $
    or a backtick, since the shell runs its $( … ) / `…` whatever reads the body and we do not pair parentheses ourselves (review 15/10:
    a ")" in a string, a # comment or a case pattern cut the extraction short and dropped the rest of the body from the scan)."""
    return _strip(text, drop, docs, False)[0]


def scan_text(text, drop, docs=None):
    """(text, open_quote): the text the guards scan. strip_heredocs, and every body that stays in the scan is not quote-scoped (15/10 r6): the quote characters ' and
    " of each line of it that does not close its own quotes are removed (_plain_body), so that no quote scanner after this (the lexer, the comment dropper, the
    single-quote and $( ) strippers of the git guard) pairs one with a quote of another body, or of the command around it, and loses what lies between them.
    open_quote: some line was so changed; the git guard then reads the text as it reads one that does not parse (RAW first, then line by line)."""
    return _strip(text, drop, docs, True)


def _closes(line):
    """True when every quote character of line is closed on it, as the lexer reads it (a line over 4000 characters is not lexed: it counts as open)."""
    if len(line) > 4000:
        return False
    try:
        lex_words(line)
    except ValueError:
        return False
    return True


def _plain_body(body):
    """(body, changed): body without the quote characters ' and " of each line whose quotes do not close on it. A line that holds no quote, or closes them, is kept."""
    lines = body.split("\n")
    changed = False
    for i, line in enumerate(lines):
        if ("'" in line or '"' in line) and not _closes(line):
            lines[i], changed = line.replace("'", "").replace('"', ""), True
    return "\n".join(lines), changed


def _strip(text, drop, docs, plain):
    docs = heredocs(text) if docs is None else docs
    out, pos, opened = [], 0, False
    for h in docs:
        if h.body_start < pos:
            continue
        if h.terminated and h.cut_ok and drop(h) and (h.quoted or not re.search(r"[$`]", h.body(text))):
            out.append(text[pos:h.body_start])
            pos = h.end
        elif plain and h.body_end > h.body_start:
            body, changed = _plain_body(h.body(text))
            if changed:
                out.append(text[pos:h.body_start])
                out.append(body)
                pos, opened = h.body_end, True
    out.append(text[pos:])
    return "".join(out), opened
