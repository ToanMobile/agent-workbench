"""One reading of a shell command line for the command guards hooks/hardware_safety_gate.sh and hooks/block-dangerous-git.sh.

workflow-improvements.md I.0 W3 / I.1 Việc 2 (14/10): the two guards each had their own idea of which words of a command run as a
command, and each missed forms the other knew (`su -c`, `bash -lc`, `sudo -u X`, `timeout -s SIG N`, `adb shell`, a `<<'EOF'` inside
quotes …). What decides it lives here, once; each guard keeps its own verdict rules.
  - the program word of a simple command: NAME=VAL words, shell keywords, a redirect before the command and the wrappers that run
    the command after them, with the values of their options (prefix_end);
  - the command text another program runs: sh/bash -c (also inside a flag cluster: -lc, -ec), su -c / su USER CMD, ssh host CMD,
    adb shell|exec-out CMD (shell_script, su_command, far_command);
  - brace expansion and path normalisation of a target (braces, norm_path);
  - heredocs, found the way the shell finds them (outside quotes and comments): a QUOTED body is data the shell never reads as
    commands, an unquoted body is data too except its $(…) / `…`, and a body that a shell or an interpreter reads is handed back
    as what it is (heredocs, strip_heredocs).
Standard library only. Loaded by the guards from their own directory (python3 -I keeps the project off sys.path).
"""
import codecs
import os
import posixpath
import re
import shlex

# wrapper -> (options that take a separate value, positional words before the command it runs)
WRAPPERS = {
    "command": (set(), 0), "builtin": (set(), 0), "exec": ({"-a"}, 0), "nohup": (set(), 0),
    "time": (set(), 0), "caffeinate": ({"-t", "-w"}, 0), "setsid": (set(), 0), "unbuffer": (set(), 0),
    "sudo": ({"-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"}, 0),
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
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "!", "{", "}", "time"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
SHELL_OPTS_WITH_ARG = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file"}
SSH_OPTS_WITH_ARG = {"-p", "-i", "-l", "-o", "-F", "-J", "-L", "-R", "-D", "-b", "-c", "-E", "-e", "-I", "-m", "-O", "-Q", "-S",
                     "-W", "-w", "-B"}
ADB_OPTS_WITH_ARG = {"-s", "-t", "-H", "-P", "-L", "--one-device"}
REDIRECT = re.compile(r"^\d*(?:>>?|<|&>)")
REDIRECT_ALONE = re.compile(r"\d*(?:>>?|<|&>)")   # fullmatch: the target is the next word
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


def prefix_end(tokens, i=0):
    """Index of the program word of a simple command: after NAME=VAL words, keywords, a redirect before the command
    (`2>/dev/null rm …`, `> out git …`), env with its options and assignments, and the wrappers. len(tokens) when there is none."""
    while i < len(tokens):
        t, p = tokens[i], tokens[i].rsplit("/", 1)[-1]
        if t in KEYWORDS or ASSIGN.match(t):
            i += 1
        elif REDIRECT.match(t):
            i += 2 if REDIRECT_ALONE.fullmatch(t) else 1
        elif p == "env":
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or "=" in tokens[i]):
                i += 2 if tokens[i] in ("-u", "-C", "-S", "--unset", "--chdir") else 1
        elif p in WRAPPERS:
            i = skip_wrapper(tokens, i, p)
        else:
            break
    return min(i, len(tokens))


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
        if j < len(rest) and rest[j] in ("shell", "exec-out"):
            j += 1
            while j < len(rest) and re.fullmatch(r"-[nTtx]+", rest[j]):
                j += 1
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


def braces(word, cap=64):
    """The words a shell brace expansion makes of word (/{system,vendor} -> /system /vendor), at most cap; what is left past the
    cap stays unexpanded. ${…} is a parameter, not a brace group."""
    out, todo = [], [word]
    while todo and len(out) + len(todo) <= cap:
        w = todo.pop()
        m = BRACE.search(w)
        if not m:
            out.append(w)
            continue
        todo.extend(w[:m.start()] + alt + w[m.end():] for alt in m.group(1).split(","))
    return out + todo


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
# The shell part of the line test block-dangerous-git.sh used before 14/10 (drop_literal_heredocs RUNS_INPUT, its interpreter
# words left out): a body whose line matched it was judged as shell, and still is, so this reading is never looser than that one.
LEGACY_SHELL_LINE = re.compile(r"(?:^|[\s|;&(/])(?:ba|z|da|k|fi)?sh\b|\b(?:ssh|eval|xargs|source)\b|(?:^|\s)\.\s")


class Heredoc:
    """One heredoc. op_start / op_end: the << operator and its word; body_start / body_end: the body; end: just past its
    delimiter line. quoted: a quote or backslash in the word (the shell expands nothing in the body). terminated: a delimiter
    line was found. depth: nesting of $( … ) / ( … ) / `…` at the operator. reader: the program the body (or the text it becomes)
    goes to. kind: "shell" (a shell runs it, here or on another machine, also from the file a data reader wrote it to: cat > x.sh
    <<EOF … bash x.sh), "interp" (an interpreter reads it as its program), "interp_file" (written to a file an interpreter then
    runs), "data" (a data-only reader: nothing runs it) or "other" (a reader not known: neither)."""
    __slots__ = ("op_start", "op_end", "delim", "quoted", "strip_tabs", "depth", "body_start", "body_end", "end",
                 "terminated", "reader", "kind")

    def __init__(self, op_start, op_end, delim, quoted, strip_tabs, depth):
        self.op_start, self.op_end, self.delim, self.quoted = op_start, op_end, delim, quoted
        self.strip_tabs, self.depth = strip_tabs, depth
        self.body_start = self.body_end = self.end = op_end
        self.terminated, self.reader, self.kind = False, "", "other"

    def body(self, text):
        return text[self.body_start:self.body_end]


def _heredoc_word(text, i):
    """(end index, word with its quotes removed, quoted) of the heredoc word that starts at text[i]."""
    out, quoted, n = [], False, len(text)
    while i < n and text[i] not in " \t\n;&|()<>":
        c = text[i]
        if c == "$" and text[i + 1:i + 2] in ("\x27", "\x22"):   # <<$'EOF' / <<$"EOF": the word is EOF, bash drops the $
            if text[i + 1] == "\x27":                             # $'…': backslash escapes (bash decodes $'E\x4fF' to EOF)
                k = i + 2
                while k < n and text[k] != "\x27" and text[k] != "\n":
                    k += 2 if text[k] == "\\" else 1
                if k >= n or text[k] != "\x27":
                    return i, "", quoted
                try:
                    out.append(codecs.decode(text[i + 2:k].encode("utf-8"), "unicode_escape") if "\\" in text[i + 2:k] else text[i + 2:k])
                except ValueError:                                # an escape we cannot read: no heredoc here, the lines are judged
                    return i, "", quoted
                quoted, i = True, k + 1
                continue
            i += 1
            continue                                              # $"…": the next pass reads "…" as a plain quoted word
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


# Programs that only look at a file they are given (a written heredoc named by them is not run).
FILE_TOOLS = DATA_READERS | {"chmod", "ls", "stat", "file", "cp", "mv", "rm", "touch", "ln", "mkdir", "open", "less", "more",
                             "code", "vim", "nano", "wc", "test", "["}
# Programs that run a file of a fixed name without naming it: their recipes are shell lines (make runs a Makefile).
IMPLICIT_RUN = {"make": {"Makefile", "makefile", "GNUmakefile"}, "gmake": {"Makefile", "makefile", "GNUmakefile"},
                "just": {"justfile", "Justfile", ".justfile"}}
_LINE_SEP = re.compile(r"&&|\|\||;|\n")
READ_OPTS_WITH_ARG = {"read": {"-d", "-p", "-t", "-u", "-n", "-N", "-i"}, "mapfile": {"-d", "-n", "-O", "-s", "-u", "-C", "-c"}}


def _after(text, h):
    """The command text after the operator, its body cut out: the rest of its own line (cat > a <<EOF && bash a) and what
    follows the delimiter line."""
    return text[h.op_end:h.body_start] + text[h.end:]


def _commands(after):
    """[(start, end, [(stage start, stage end, program, words)])] of each command line of after, split at ; && || newline, its
    pipeline split at |."""
    out, pos = [], 0
    for s in list(_LINE_SEP.finditer(after)) + [None]:
        end = s.start() if s else len(after)
        stages, q = [], pos
        for piece in after[pos:end].split("|"):
            stages.append((q, q + len(piece)) + _program(_words(piece.lstrip("&"))))
            q += len(piece) + 1
        out.append((pos, end, stages))
        pos = s.end() if s else end
    return out


def _written_file_use(text, seg, h):
    """(use, program) of the file the reader writes the body to (> F, >> F, tee F) in the text after the body: use "shell" (a
    shell runs it, it is run as a command — bash x.sh, ./x.sh, source x.sh — or make runs it as its Makefile), "interp" (an
    interpreter runs it: python3 x.py; program: that interpreter), "data" (only file tools name it), "other" (a program not
    known names it) or None (the reader writes no file, or no later command names it). Each use is judged by the whole
    pipeline of its command."""
    names = {m.group(1).strip("\x22\x27") for m in re.finditer(r"(?<![<\d&])>>?\|?[ \t]*([^\s;&|<>()]+)", seg)}
    words = _words(seg)
    for k, w in enumerate(words):
        if os.path.basename(w) == "tee":
            names.update(x for x in words[k + 1:] if not x.startswith("-") and not set(x) <= set(";&|()"))
            break
    after, uses = _after(text, h), {}
    bases = {os.path.basename(x.rstrip("/")) for x in names - {"/dev/null", "-"}} - {""}
    cmds = _commands(after) if bases else []
    for base in bases:
        for _a, _b, stages in cmds:
            if any(base in IMPLICIT_RUN.get(p, ()) for _s, _e, p, _w in stages):
                uses.setdefault("shell", "make")
        for m in re.finditer(r"(?<![\w.-])" + re.escape(base) + r"(?![\w-])", after):
            stages = next((st for a, b, st in cmds if a <= m.start() <= b), [])
            here = next((_program(_words(after[s:m.end()].lstrip("&")))[0] for s, e, _p, _w in stages if s <= m.start() <= e), "")
            progs = [p for _s, _e, p, _w in stages]
            if any(p in SHELL_RUNNERS for p in progs) or here == base:   # ... or the file is the command itself (./x.sh)
                uses.setdefault("shell", here)
            elif any(_interp(p) for p in progs):
                uses.setdefault("interp", next(p for p in progs if _interp(p)))
            elif all(p in FILE_TOOLS for p in progs if p):
                uses.setdefault("data", "")
            else:
                uses.setdefault("other", "")
    use = next((u for u in ("shell", "other", "interp", "data") if u in uses), None)
    return use, uses.get(use, "")


def _assigned_vars(stages, seg):
    """Variable names this command fills from the heredoc: read [-opts] NAME…, mapfile / readarray NAME, NAME=$(…)."""
    names = set()
    for p, r in stages:
        if p in ("read", "mapfile", "readarray"):
            k = 0
            while k < len(r):
                a = r[k]
                if a == "-a" and k + 1 < len(r):
                    names.add(r[k + 1])
                    k += 2
                elif a in READ_OPTS_WITH_ARG["read" if p == "read" else "mapfile"]:
                    k += 2
                elif a.startswith("-") or a.startswith("<") or REDIRECT.match(a):
                    k += 1
                else:
                    names.add(a)
                    k += 1
    names.update(re.findall(r"(?:^|[\s;&|(])([A-Za-z_]\w*)=\$\(", seg))
    return {n for n in names if re.fullmatch(r"[A-Za-z_]\w*", n)}


def _var_run_later(text, h, names):
    """True when a later shell runner (eval, bash -c, source …) takes one of these variables: the body runs as commands."""
    if not names:
        return False
    rx, after = re.compile(r"\$\{?(?:" + "|".join(map(re.escape, sorted(names))) + r")\b"), _after(text, h)
    return any(rx.search(after[a:b]) and any(p in SHELL_RUNNERS for _s, _e, p, _w in st) for a, b, st in _commands(after))


def _classify(text, h, seps, pipes, cut):
    """Set h.reader and h.kind. The reader is the command the operator belongs to (the one just before it on its line, inside
    any $( … )) and the top-level command around it, with the stages of its pipeline."""
    start = max((e for s, e in seps if e <= h.op_start), default=0)
    end = min((s for s, e in seps if s >= h.op_end), default=len(text))
    seg = _segment(text, start, end, cut)
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
    if LEGACY_SHELL_LINE.search(seg) or any(
            p in SHELL_RUNNERS or (p in ("adb", "adb.exe") and adb_shell(r))
            or (p in ("sudo", "doas") and {"-s", "-i"} & set(r)) for p, r in stages + [(inner, inner_rest)]):
        h.kind = "shell"
        return
    if _var_run_later(text, h, _assigned_vars(stages + [(inner, inner_rest)], seg)):   # read X <<EOF … then eval "$X"
        h.kind = "shell"
        return
    if _interp(inner) and _program_on_stdin(inner, inner_rest):          # python3 - <<EOF, also inside $( … )
        h.kind, h.reader = "interp", inner
        return
    for p, r in stages[mine + 1:]:                                          # cat <<EOF | python3 -
        if _interp(p) and _program_on_stdin(p, r):
            h.kind, h.reader = "interp", p
            return
    if h.depth and _interp(top) and _program_inline(top, top_rest):         # python3 -c "$(cat <<EOF …)"
        h.kind, h.reader = "interp", top
        return
    if inner in DATA_READERS and top in DATA_READERS and all(p in DATA_READERS for p, _ in stages[mine + 1:]):
        # cat > x.sh <<EOF … then bash x.sh: what runs the file decides (interp_file: an interpreter program in a file)
        use, prog = _written_file_use(text, seg, h)
        h.kind = {"shell": "shell", "other": "other", "interp": "interp_file"}.get(use, "data")
        h.reader = prog if use == "interp" else h.reader
        return
    h.kind = "other"


def heredocs(text):
    """[Heredoc] of a command line, in order, each with its reader and kind. The shell's rules: `<<` / `<<-` (not `<<<`) outside
    quotes, comments and arithmetic starts one; a quote or backslash in its word makes the body literal; the body starts after
    the end of the line that holds the operator (several heredocs on one line follow each other) and ends at a line that is
    exactly the word (leading tabs dropped for <<-). Inside $( … ) and backticks the same holds."""
    docs, seps, pipes = _scan(text)
    cut = sorted((h.body_start, h.end) for h in docs if h.end > h.body_start)
    for h in docs:
        _classify(text, h, seps, pipes, cut)
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
        if not h.terminated or h.body_start < pos or not drop(h):
            continue
        out.append(text[pos:h.body_start])
        if not h.quoted:
            out.extend(e + "\n" for e in expansions(h.body(text)))
        pos = h.end
    out.append(text[pos:])
    return "".join(out)
