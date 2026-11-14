#!/usr/bin/env python3
"""PreToolUse(Bash|Read|Grep) guard: refuse to read or pipe secret files.

Stops secrets getting OUT -- `cat .env`, `source .env.local`, `grep KEY .env | curl`,
or the Read tool opening a dotenv file -- so a key never lands in the transcript.
`.env.example` and friends are deliberately allowed: that file is how an agent
learns which keys exist. Its own errors DENY the call (fail closed, #873).

A `git commit` MESSAGE only talks about a file, it never reads one (#352, #367): the text of
-m / --message and a QUOTED-delimiter heredoc fed to the commit are not judged. Everything else in
the command (the paths, `&& cat .env` after it) still is. Fail closed (INSTINCT-045): a message word
that expands anything ($( ) backtick ${ } $[ ] <( )), an unquoted heredoc body, a commit segment with an
unquoted # / ${ / $[ / $' , and ANY scanner error make the whole command be judged.

Adapted from ai-builder-starter-kit's .agents/hooks/guard-secrets.sh (Eric Tech).
"""
import fnmatch
import json
import os
import re
import subprocess
import sys

B = r"(?:^|[^A-Za-z0-9._-])"   # boundary before a name
E = r"(?:[^A-Za-z0-9._-]|$)"   # boundary after a name
# The names below cover every file bin/post-fix-gate.py forbids to commit (FORBIDDEN_SECRET_FILES, ENV_FILE_PATTERN): what may
# not be committed may not be read into the transcript either (INSTINCT-015; tests/gates/test_guard_secrets_zero_defect.sh C3x
# reads the gate's list and fails when the two drift apart). A template copy (.env.example, local.properties.sample) stays readable.
TEMPLATE_SUFFIXES = (".example", ".sample", ".template", ".dist")
NOT_TEMPLATE = "".join(r"(?<!%s)" % re.escape(s) for s in TEMPLATE_SUFFIXES)
SECRET_EXT = r"(?:key|jks|keystore|p12|pfx|mobileprovision|env)"
# <name>.<SECRET_EXT> as a whole path word: `server.key`, `prod.env`, `$HOME/x.jks`. Not `jq .key`, `obj.key)`, `process.env`.
PATH_WORD = (r"(?:^|[\s'\"=<>:@/])(?!(?:process|import\.meta)\.env(?![A-Za-z0-9_-]))"
             r"[A-Za-z0-9_-][A-Za-z0-9_.-]*\." + SECRET_EXT + r"(?=$|[\s'\";&|)<>])")
SECRET_RE = re.compile("|".join([
    B + r"\.env(?:\.[A-Za-z0-9_-]+)*" + NOT_TEMPLATE + E,   # .env and .env.<anything>[.<anything>], not .env.example
    B + r"\.envrc" + E,
    B + r"\.dev\.vars" + E,
    B + r"id_(?:rsa|dsa|ed25519|ecdsa)" + E,
    B + r"\.npmrc" + E,
    B + r"\.(?:netrc|git-credentials|pypirc|dockercfg)" + E,
    r"\.docker/config\.json" + E,        # registry auth
    r"\.kube/config" + E,                # cluster credentials
    r"\.config/gh/hosts\.yml" + E,       # GitHub CLI token
    B + r"credentials(?:\.json)?" + E,
    B + r"secrets\.(?:json|ya?ml)" + E,
    B + r"(?:local|keystore)\.properties" + E,
    r"google-services\.json" + E,
    r"GoogleService-Info\.plist" + E,
    r"service-account[A-Za-z0-9._-]*\.json",
    r"\.pem" + E,
    PATH_WORD,
]), re.I)   # upper case too: .ENV opens the same file on a case-insensitive filesystem (#873)

# Secret names a glob / brace / ANSI-C word can spell without writing the plain name (#873).
GLOB_NAMES = (".env", ".env.local", ".env.production", ".env.prod", ".env.staging", ".env.development", ".env.dev",
              ".env.test", ".npmrc", "id_rsa", "id_dsa", "id_ed25519", "id_ecdsa", "credentials.json", "credentials",
              ".envrc", ".dev.vars", ".netrc", ".git-credentials", ".pypirc", ".dockercfg", "secrets.json",
              "secrets.yml", "secrets.yaml", "local.properties",
              "keystore.properties", "google-services.json", "googleservice-info.plist")
GLOB_EXT = re.compile(r"\.(?:pem|key|jks|keystore|p12|pfx|mobileprovision|env)\Z", re.I)   # *.jks: the extension names a secret
WORD = re.compile(r"[^\s;&|()<>]+")
ANSI_C = re.compile(r"\$'((?:[^'\\]|\\.)*)'", re.S)
FIND_NAME = re.compile(r"-(?:i?name|i?path|i?wholename)[ \t]+(?:'([^']*)'|\"([^\"]*)\"|([^\s;&|()<>]+))")
FIND_EXEC = re.compile(r"(?:^|\s)-(?:exec|execdir|ok|okdir)(?:\s|$)")
BRACE_MAX_LEN, BRACE_MAX_OUT = 4096, 256
BRACE_BUDGET = 200_000   # characters scanned by brace expansion over one whole command; more = hostile, denied (INSTINCT-044)


class _BraceBudget(Exception):
    pass

# The one sanctioned way to ask "is KEY set?": super-board-env-check.sh prints
# present / empty / missing per key and never a value. Allowed only as a single
# plain call -- no pipe, redirect, chain or substitution can ride along.
ENV_CHECK = re.compile(
    r"^[ \t]*(?:(?:bash|sh)[ \t]+)?(?:[A-Za-z0-9_./-]*/)?super-board-env-check\.sh"
    r"(?:[ \t]+[A-Za-z0-9_./=-]+)*[ \t]*\Z")

REASON = ("Blocked by guard-secrets: this touches a secret file. Read the checked-in example env "
          "file (.env.example) for the key names, or ask the user to run the command themselves "
          "with the ! prefix.")

# Một message chỉ được xoá khi KHÔNG chứa thứ shell sẽ thực thi/khai triển.
EXPANDS = ("$(", "`", "${", "$[", "<(")
# Ngoại lệ duy nhất: `"$(cat <<'WORD'\n...\nWORD\n)"` (delimiter có quote => thân là dữ liệu thuần).
QUOTED_CAT_HEREDOC = re.compile(r"\A\"\$\(cat[ \t]+<<[ \t]*'([A-Za-z0-9_]+)'\n(.*)\n\1\n\)\"\Z", re.S)
HEREDOC_STOP = " \t\n;&|()<>"
MSG_VALUE = re.compile(r"^-[A-Za-z]*m$|^--message$")        # the next word is the message: -m, -am, --message
MSG_ATTACHED = re.compile(r"^-m.|^--message=")              # the message is part of this word: -m"x", --message=x
GIT_VALUE_OPTS = {"-c", "-C", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def _heredoc_at(s, j):
    """Heredoc opened by the `<<` at s[j]: (tag, strip_tabs, quoted, end) or None. The delimiter is the WHOLE shell word
    (`<<END.`, `<<EOF-1`, `<<E"OF"`). A delimiter that expands ($x, backtick) raises ValueError: its tag is unknowable."""
    n = len(s)
    j += 2
    strip = s.startswith("-", j)
    if strip:
        j += 1
    while j < n and s[j] in " \t":
        j += 1
    tag, quoted, start = [], False, j
    while j < n and s[j] not in HEREDOC_STOP:
        c = s[j]
        if c == "'":
            k = s.find("'", j + 1)
            if k < 0:
                raise ValueError("unterminated quote in heredoc delimiter")
            tag.append(s[j + 1:k])
            quoted, j = True, k + 1
        elif c == '"':
            k = j + 1
            while k < n and s[k] != '"':
                if s[k] in "$`":
                    raise ValueError("expansion in heredoc delimiter")
                k += 2 if s[k] == "\\" else 1
            if k >= n:
                raise ValueError("unterminated quote in heredoc delimiter")
            tag.append(s[j + 1:k].replace("\\", ""))
            quoted, j = True, k + 1
        elif c == "\\":
            tag.append(s[j + 1:j + 2])
            quoted, j = True, j + 2
        elif c in "$`":
            raise ValueError("expansion in heredoc delimiter")
        else:
            tag.append(c)
            j += 1
    if j == start:
        return None
    return "".join(tag), strip, quoted, j


def _skip_quoted(s, i, q):
    """Index just past the quote opened at s[i] (q is ' or "), or raise ValueError when it never closes."""
    n = len(s)
    j = i + 1
    while j < n:
        c = s[j]
        if q == '"' and c == "\\":
            j += 2
            continue
        if q == '"' and c == "$" and s[j + 1:j + 2] == "(":
            j = _skip_paren(s, j + 1)
            continue
        if q == '"' and c == "`":
            j = _skip_backtick(s, j)
            continue
        if c == q:
            return j + 1
        j += 1
    raise ValueError("unterminated quote")


def _skip_backtick(s, i):
    j = s.find("`", i + 1)
    if j < 0:
        raise ValueError("unterminated backtick")
    return j + 1


def _skip_heredoc_bodies(s, j, pending):
    """Index past the bodies of the heredocs `pending` [(tag, strip_tabs, quoted)] opened on the line that ends just before s[j]."""
    n = len(s)
    for tag, strip, _quoted in pending:
        while j < n:
            k = s.find("\n", j)
            line = s[j:n if k < 0 else k]
            j = n if k < 0 else k + 1
            if (line.lstrip("\t") if strip else line) == tag:
                break
    return j


def _skip_paren(s, i):
    """Index just past the ( at s[i] and its matching ), quotes, nesting and heredocs honoured (raises ValueError)."""
    n, depth, j, pending = len(s), 0, i, []
    while j < n:
        c = s[j]
        if c == "\n" and pending:   # `$(cat <<'EOF' ... EOF)`: the body is opaque text, an apostrophe in it opens no quote
            j = _skip_heredoc_bodies(s, j + 1, pending)
            pending = []
            continue
        if c == "<" and s.startswith("<<", j) and not s.startswith("<<<", j):
            m = _heredoc_at(s, j)
            if m:
                pending.append(m[:3])
                j = m[3]
                continue
        if c == "\\":
            j += 2
            continue
        if c in "'\"":
            j = _skip_quoted(s, j, c)
            continue
        if c == "`":
            j = _skip_backtick(s, j)
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    raise ValueError("unterminated $(")


def _segments(s):
    """[(words, heredocs, risky)] per simple command: words = [(start, end)] raw spans, heredocs = [(start, end)] spans of
    QUOTED-delimiter bodies (an unquoted body expands, so it is never data), risky = an unquoted # ${ $[ $' was seen
    (comment / expansion that can turn a `<<WORD` into something the shell does not treat as a heredoc)."""
    n, i = len(s), 0
    segs = []
    words, bodies, pending, ws, risky = [], [], [], None, False

    def end_word(at):
        nonlocal ws
        if ws is not None:
            words.append((ws, at))
            ws = None

    def end_seg():
        nonlocal words, bodies, pending, risky
        segs.append((words, bodies, risky))
        words, bodies, pending, risky = [], [], [], False

    while i < n:
        c = s[i]
        if c == "\n":
            end_word(i)
            i += 1
            for pend in pending:   # the bodies of the heredocs this line opened
                start = i
                i = _skip_heredoc_bodies(s, i, [pend])
                if pend[2]:
                    bodies.append((start, i))
            pending = []
            end_seg()
            continue
        if c in ";&|()":
            end_word(i)
            end_seg()
            i += 1
            continue
        if c in " \t":
            end_word(i)
            i += 1
            continue
        if c == "<" and s.startswith("<<", i) and not s.startswith("<<<", i):
            m = _heredoc_at(s, i)
            if m:
                pending.append(m[:3])
                end_word(i)
                i = m[3]
                continue
        if ws is None:
            ws = i
        if c == "#" or (c == "$" and s[i + 1:i + 2] in ("{", "[", "'", '"')):
            risky = True
        if c == "\\":
            i += 2
        elif c in "'\"":
            i = _skip_quoted(s, i, c)
        elif c == "`":
            i = _skip_backtick(s, i)
        elif c == "$" and s[i + 1:i + 2] == "(":
            i = _skip_paren(s, i + 1)
        else:
            i += 1
    end_word(min(i, n))
    end_seg()
    return segs


def _commit_words(raw):
    """True when the words of one simple command are `git [opts] commit ...`."""
    k = 0
    while k < len(raw) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", raw[k]):
        k += 1                                      # leading VAR=value
    if k >= len(raw) or raw[k] != "git":
        return False
    k += 1
    while k < len(raw) and raw[k].startswith("-"):
        k += 2 if raw[k] in GIT_VALUE_OPTS else 1
    return k < len(raw) and raw[k] == "commit"


def _safe_message(word):
    """True when the text of a message word is plain data: nothing in it is expanded by the shell, except the exact
    `"$(cat <<'WORD' ... WORD\n)"` whose body has no line equal to WORD (the shell would run what follows that line)."""
    if not any(x in word for x in EXPANDS):
        return True
    m = QUOTED_CAT_HEREDOC.match(word)
    return bool(m) and m.group(1) not in m.group(2).split("\n")


def scrub_commit_messages(cmd):
    """cmd with the message text of every `git commit` blanked (-m / --message values, quoted-delimiter heredoc bodies).
    Raises ValueError when the command cannot be trusted to scan (open quote, risky segment): the caller judges it whole."""
    out = list(cmd)

    def blank(a, b):
        for p in range(a, b):
            if out[p] != "\n":
                out[p] = " "

    for words, bodies, risky in _segments(cmd):
        raw = [cmd[a:b] for a, b in words]
        if not _commit_words(raw):
            continue
        if risky:
            raise ValueError("commit segment has an unquoted # / ${ / $[ / $'")
        for idx, w in enumerate(raw):
            if MSG_VALUE.match(w) and idx + 1 < len(words):
                if _safe_message(raw[idx + 1]):
                    blank(*words[idx + 1])
            elif MSG_ATTACHED.match(w) and _safe_message(w):
                blank(*words[idx])
        for a, b in bodies:
            blank(a, b)
    return "".join(out)


def _decode_ansi_c(text):
    """text with every $'...' replaced by what the shell makes of it ($'\\x2eenv' -> the dotenv name); undecodable: kept."""
    def one(m):
        try:
            return m.group(1).encode("latin-1", "backslashreplace").decode("unicode_escape")
        except (UnicodeError, ValueError):
            return m.group(0)
    return ANSI_C.sub(one, text)


def _brace_expand(word, budget):
    """Bounded brace expansion of one word ({a,b} comma lists; ${ is not a brace).
    budget = [chars left] shared by the whole command: every pass over a word spends len(word); empty -> _BraceBudget.
    A word over BRACE_MAX_LEN or more than BRACE_MAX_OUT results is hostile too: _BraceBudget (never skip the unchecked rest)."""
    if len(word) > BRACE_MAX_LEN:
        raise _BraceBudget
    out, todo = [], [word]
    while todo:
        if len(out) >= BRACE_MAX_OUT:
            raise _BraceBudget
        w = todo.pop()
        budget[0] -= len(w)
        if budget[0] < 0:
            raise _BraceBudget
        i = next((k for k, c in enumerate(w) if c == "{" and (k == 0 or w[k - 1] != "$")), -1)
        if i < 0:
            out.append(w.replace("\x00", "{"))
            continue
        depth, j, cuts = 0, i, [i]
        while j < len(w):
            if w[j] == "{":
                depth += 1
            elif w[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            elif w[j] == "," and depth == 1:
                cuts.append(j)
            j += 1
        if j < len(w) and len(cuts) < 2:   # {x}: bash keeps it literal, we also judge it stripped (stricter, #873)
            todo.append(w[:i] + w[i + 1:j] + w[j + 1:])
            out.append(w.replace("\x00", "{"))
            continue
        if j >= len(w):   # unclosed: the { stays literal, look at the rest of the word
            todo.append(w[:i] + "\x00" + w[i + 1:])
            continue
        cuts.append(j)
        for a, b in zip(cuts, cuts[1:]):
            todo.append(w[:i] + w[a + 1:b] + w[j + 1:])
    return out


def _glob_matches_secret(pat):
    """True when the glob `pat` (its last path part) can spell a secret name and says enough of it: >= 3 literal characters,
    at least half of the name. Linear in len(pat): an NFA over the (<= 17 char) name, no fnmatch, no regex backtracking.
    ponytail: [...] counts as any one character (stricter than the shell), the half-name rule lets `cred*` through."""
    pat = pat.rsplit("/", 1)[-1]
    if not any(c in pat for c in "*?["):
        return False
    low = pat.lower()
    if GLOB_EXT.search(low):   # *.jks, cert*.p12, *.env
        return True
    if low.startswith(".env") and low[4:5] in (".", "*", "?", "[") and not low.endswith(TEMPLATE_SUFFIXES):
        return True            # .env*, .env.*.local: any dotenv variant
    head = re.split(r"[*?\[]", low, maxsplit=1)[0]
    if len(head) >= 2 and ".env".startswith(head):
        return True            # .e*, .en*: too short for the half-name rule below, and it still opens the dotenv file
    toks, i, n, last = [], 0, len(pat), pat.rfind("]")
    while i < n:
        c = pat[i]
        if c == "[" and i < last:
            k = pat.find("]", i + 2 if pat[i + 1:i + 2] in ("!", "^", "]") else i + 1)
            i = k + 1 if k >= 0 else n
            toks.append(("?", ""))
            continue
        toks.append(("*", "") if c == "*" else ("?", "") if c == "?" else ("c", c.lower()))
        i += 1
    literal = sum(1 for k, _ in toks if k == "c")
    if literal < 3:
        return False
    for name in GLOB_NAMES:
        if 2 * literal < len(name):
            continue
        states = {0}
        for kind, ch in toks:
            nxt = set()
            for st in states:
                if kind == "*":
                    nxt.update(range(st, len(name) + 1))
                elif st < len(name) and (kind == "?" or name[st] == ch):
                    nxt.add(st + 1)
            states = nxt
            if not states:
                break
        if len(name) in states:
            return True
    return False


def _hits_secret(text):
    """Secret named by `text` directly, through $'..' quoting, brace expansion, a glob word or a find -name glob."""
    decoded = _decode_ansi_c(text)
    if SECRET_RE.search(text) or SECRET_RE.search(decoded):
        return True
    budget = [BRACE_BUDGET]
    for word in WORD.findall(decoded):
        if any(q in word for q in "'\"\\`"):
            continue   # quoted / escaped words do not glob; the plain-name regex above already judged them
        try:
            expanded = _brace_expand(word, budget) if "{" in word else (word,)
        except _BraceBudget:
            return True   # so much brace work in one command is not an everyday command: deny instead of timing out
        for w in expanded:
            if SECRET_RE.search(w) or _glob_matches_secret(w):
                return True
    if FIND_EXEC.search(decoded):
        for m in FIND_NAME.finditer(decoded):
            if _glob_matches_secret(next(g for g in m.groups() if g is not None)):
                return True
    return False


# ---- Words that only NAME a secret file (zero-defect review 2026-11-14, C3d) -------------------------------------------------
# `test -f .env`, `ls .env`, `git rm --cached .env`, a grep PATTERN, an --exclude glob, the text of echo / gh --body: none of
# them reads the file. Such words are blanked before the name patterns run; everything else in the command is still judged.
# Fail closed: a simple command with $( ) or a backtick, an unquoted # / ${ , or an option this code does not know keeps all its
# words; a command that can turn a printed name or text back into a read (xargs, read, eval, source, a shell without a literal
# -c script, $_, <( )) is judged whole, as before.
class _Whole(Exception):
    """Data and code cannot be told apart safely in this command: every word of it is judged."""


DOLLAR_UNDERSCORE = re.compile(r"\$_(?![A-Za-z0-9_])|\$\{_\}")   # $_ = the last argument of the previous command
NAME_CONSUMERS = {"xargs", "parallel", "read", "mapfile", "readarray"}   # turn a printed name into an argument
CODE_RUNNERS = {"eval", "source", "."}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
SHELL_C = re.compile(r"^-[a-z]*c$")
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
NAME_ONLY = {"test", "[", "[[", "ls", "stat"}            # look at the name / metadata, never the content
TEXT_ONLY = {"echo", "printf"}                           # their arguments are text, unless the text is piped on
GIT_NAME_ONLY = {"check-ignore", "status", "ls-files"}   # plus `rm --cached`
GH_TEXT = {"pr", "issue", "release"}
SAFE_TEXT_TARGET = re.compile(r"^(?:/dev/null|(?:[A-Za-z0-9_./~-]*/)?\.[A-Za-z]*ignore)$")   # .gitignore, .dockerignore
PLAIN_PATH = re.compile(r"^[A-Za-z0-9_./~-]+$")
CP_FLAGS = re.compile(r"^-[fipnvaRr]+$")
GREP_TOOLS = {"grep": "grep", "egrep": "grep", "fgrep": "grep", "rg": "rg"}
SHORT_VALUE = {"grep": "efmABCdD", "rg": "efgtTABCmjMEdr"}
SHORT_FLAG = {"grep": "EFGPivwxclLoqsHhnrRIzabUuTZ0123456789", "rg": "ivwxcloqsSHhnNFPUupIzaLb.0"}
SHORT_NAME = {"e": "regexp", "f": "file", "g": "glob"}
LONG_VALUE = {"regexp", "file", "glob", "iglob", "include", "exclude", "exclude-dir", "exclude-from", "ignore-file", "pre",
              "pre-glob", "type", "type-not", "type-add", "max-count", "context", "after-context", "before-context",
              "max-depth", "maxdepth", "threads", "sort", "sortr", "encoding", "replace", "max-filesize", "max-columns",
              "binary-files", "devices", "directories", "label", "engine", "colors", "path-separator", "context-separator"}
LONG_FLAG = {"line-number", "ignore-case", "smart-case", "case-sensitive", "fixed-strings", "word-regexp", "line-regexp",
             "invert-match", "count", "files-with-matches", "files-without-match", "only-matching", "quiet", "silent",
             "no-messages", "with-filename", "no-filename", "recursive", "dereference-recursive", "extended-regexp",
             "basic-regexp", "perl-regexp", "hidden", "no-ignore", "no-ignore-vcs", "no-ignore-parent", "no-ignore-global",
             "no-ignore-dot", "unrestricted", "no-heading", "heading", "column", "no-line-number", "pcre2", "multiline",
             "multiline-dotall", "follow", "text", "null", "null-data", "json", "vimgrep", "trim", "stats", "pretty",
             "no-config", "crlf", "glob-case-insensitive", "one-file-system", "binary", "search-zip", "line-buffered",
             "byte-offset", "initial-tab", "color", "colour", "files"}


def _unquoted(word, chars):
    """True when one of `chars` stands outside quotes in `word` (or the word cannot be scanned)."""
    i, n = 0, len(word)
    while i < n:
        c = word[i]
        if c == "\\":
            i += 2
        elif c in "'\"":
            try:
                i = _skip_quoted(word, i, c)
            except ValueError:
                return True
        elif c in chars:
            return True
        else:
            i += 1
    return False


def _plain(word):
    """The text of a shell word that is a literal: bare, or one '...' / "..." holding nothing the shell expands. Else None."""
    if len(word) >= 2 and word[0] == word[-1] and word[0] in "'\"":
        inner = word[1:-1]
        if word[0] in inner or (word[0] == '"' and any(c in inner for c in "$`\\")):
            return None
        return inner
    return None if any(c in word for c in "'\"\\$`") else word


def _head(raw):
    """Index of the command word of a simple command: after VAR=value words and shell keywords (if, then, !, ...)."""
    k = 0
    while k < len(raw) and (ASSIGN.match(raw[k]) or raw[k] in KEYWORDS):
        k += 1
    return k


def _all_args(raw, start):
    """Indexes of the words from `start` on, without redirections and their targets (a file read by `<` is still judged)."""
    out, i = [], start
    while i < len(raw):
        if _unquoted(raw[i], "<>"):
            i += 2 if raw[i][-1] in "<>" else 1
            continue
        out.append(i)
        i += 1
    return out


def _grep_args(raw, k, tool):
    """What the words after raw[k] (grep / rg) are. data = indexes of the words that are a search pattern or an exclusion, never
    a file that is read; paths = indexes of the files / directories searched; trusted = every option was understood (-f FILE and
    an unknown option are not: nothing is blanked then)."""
    info = {"data": [], "paths": [], "trusted": True, "pattern": False, "recursive": False, "hidden": False,
            "no_ignore": False, "include": [], "exclude": []}
    unrestricted = 0

    def option_value(name, at, val):
        if name == "regexp":
            info["data"].append(at)
            info["pattern"] = True
        elif name == "file":
            info["trusted"] = False
        elif name in ("exclude", "exclude-dir", "glob", "iglob", "include"):
            text = _plain(val)
            if text is None:
                info["trusted"] = False
            elif name in ("exclude", "exclude-dir"):
                info["data"].append(at)
                if name == "exclude":
                    info["exclude"].append(text)
            elif name != "include" and text.startswith("!"):
                info["data"].append(at)
                info["exclude"].append(text[1:])
            else:
                info["include"].append(text)   # an include NAMES what is read: it stays judged
        elif name in ("directories", "d") and val == "recurse":
            info["recursive"] = True

    n, i, dashdash = len(raw), k + 1, False
    while i < n:
        w = raw[i]
        if _unquoted(w, "<>"):   # a redirection and its target: never the pattern
            i += 2 if w[-1] in "<>" else 1
            continue
        if dashdash or not w.startswith("-") or w == "-":
            if info["pattern"]:
                info["paths"].append(i)
            else:
                info["data"].append(i)
                info["pattern"] = True
        elif w == "--":
            dashdash = True
        elif w.startswith("--"):
            name, eq, val = w[2:].partition("=")
            if name in LONG_VALUE or (tool == "rg" and name in ("color", "colour")):
                at = i if eq else i + 1
                option_value(name, at, val if eq else (raw[at] if at < n else ""))
                i = at
            elif name in LONG_FLAG and not eq:
                if name in ("recursive", "dereference-recursive"):
                    info["recursive"] = True
                elif name == "hidden":
                    info["hidden"] = True
                elif name.startswith("no-ignore"):
                    info["no_ignore"] = True
                elif name == "unrestricted":
                    unrestricted += 1
            else:
                info["trusted"] = False
        else:
            for p in range(1, len(w)):
                c = w[p]
                if c in SHORT_VALUE[tool]:
                    at = i if w[p + 1:] else i + 1
                    option_value(SHORT_NAME.get(c, c), at, w[p + 1:] or (raw[at] if at < n else ""))
                    i = at
                    break
                if c not in SHORT_FLAG[tool]:
                    info["trusted"] = False
                elif tool == "grep" and c in "rR":
                    info["recursive"] = True
                elif tool == "rg" and c == "u":
                    unrestricted += 1
                elif tool == "rg" and c == ".":
                    info["hidden"] = True
        i += 1
    if unrestricted:
        info["no_ignore"] = True
        info["hidden"] = info["hidden"] or unrestricted > 1
    return info


def _data_words(cmd, words, raw, k, name):
    """Indexes of the words of one simple command (command word raw[k], basename `name`) that cannot make it read a file."""
    rest = cmd[words[-1][1]:].lstrip(" \t")
    # What a command prints can become a read further down a pipe (`ls X | cat`-style consumers, echo "cat X" | python3).
    piped = (rest.startswith("|") and not rest.startswith("||")) or raw[-1][-1] in "<>"
    if name in NAME_ONLY:
        return [] if piped else _all_args(raw, k + 1)
    if name in TEXT_ONLY:   # text written to a file can be run later: only an ignore file or /dev/null as the target
        for i in range(k + 1, len(raw)):
            if _unquoted(raw[i], ">"):
                target = raw[i].lstrip("0123456789>&|") or (raw[i + 1] if i + 1 < len(raw) else "")
                if not SAFE_TEXT_TARGET.match(target):
                    return []
        return [] if piped else _all_args(raw, k + 1)
    if name == "git":   # only `git [-C dir] <sub>`: `-c alias.x=!cmd` and friends keep every word judged
        j = k + 1
        while j + 1 < len(raw) and raw[j] == "-C":
            j += 2
        sub = raw[j] if j < len(raw) else ""
        rest_words = raw[j + 1:]
        if piped or (sub == "status" and any(w.startswith("-v") or w == "--verbose" for w in rest_words)):
            return []   # `git status -v` prints the diff of the file
        if sub in GIT_NAME_ONLY or (sub == "rm" and "--cached" in rest_words):
            return _all_args(raw, j + 1)
        return []
    if name == "cp":    # `cp .env.example .env`: only the DESTINATION, and only when every source is a template file
        rest = range(k + 1, len(raw))
        files = [i for i in rest if not raw[i].startswith("-")]
        if (len(files) >= 2 and all(CP_FLAGS.match(raw[i]) for i in rest if raw[i].startswith("-"))
                and all(PLAIN_PATH.match(raw[i]) for i in files)
                and all(raw[i].lower().endswith(TEMPLATE_SUFFIXES) for i in files[:-1])):
            return [files[-1]]
        return []
    if name in GREP_TOOLS:   # a brace / glob word becomes several words in the shell: positions cannot be trusted then
        if any(_unquoted(w, "{*?[") for w in raw):
            return []
        info = _grep_args(raw, k, GREP_TOOLS[name])
        return info["data"] if info["trusted"] else []
    if name == "gh" and len(raw) > k + 1 and raw[k + 1] in GH_TEXT:   # --title / --body text; --body-file stays judged
        out = []
        for i in range(k + 2, len(raw)):
            if raw[i] in ("--title", "--body", "-t", "-b") and i + 1 < len(raw) and not _unquoted(raw[i + 1], "<>"):
                out.append(i + 1)
            elif raw[i].startswith(("--title=", "--body=")):
                out.append(i)
        return out
    return []


def scrub_data_words(cmd, depth=0):
    """cmd with the words that only name a file blanked. Raises _Whole / ValueError when the command must be judged whole."""
    if depth > 3 or "<(" in cmd or ">(" in cmd or DOLLAR_UNDERSCORE.search(cmd):
        raise _Whole
    out = list(cmd)
    for words, _bodies, risky in _segments(cmd):
        raw = [cmd[a:b] for a, b in words]
        k = _head(raw)
        if k >= len(raw):
            continue
        name = raw[k].rsplit("/", 1)[-1]
        if name in CODE_RUNNERS or any(w.rsplit("/", 1)[-1] in NAME_CONSUMERS for w in raw):
            raise _Whole
        if name in SHELLS:   # only `sh -c '<literal script>'` is understood: the script is scrubbed like a command of its own
            script = _plain(raw[k + 2]) if len(raw) > k + 2 and SHELL_C.match(raw[k + 1]) else None
            if script is None or raw[k + 2][0] not in "'\"":
                raise _Whole
            a, b = words[k + 2]
            out[a + 1:b - 1] = _scrubbed(script, depth + 1)
            continue
        if risky or any("$(" in w or "`" in w for w in raw):
            continue
        for idx in _data_words(cmd, words, raw, k, name):
            a, b = words[idx]
            for p in range(a, b):
                if out[p] != "\n":
                    out[p] = " "
    return "".join(out)


def _scrubbed(cmd, depth=0):
    return scrub_data_words(scrub_commit_messages(cmd) if "commit" in cmd else cmd, depth)


# ---- A recursive search over a tree that holds a secret file (C3e) ------------------------------------------------------------
# `grep -r KEY .` names no secret file and prints the dotenv file in the tree all the same. The directories such a search reads
# are listed (bounded) and the call is refused when a secret-named file is among what it would read.
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "build", "dist", "target", ".gradle", "__pycache__"}
SCAN_DEPTH, SCAN_MAX = 2, 2000   # ponytail: the directory and its sub-directories, 2000 entries; a secret deeper down is not
                                 # seen (upgrade: walk deeper once a real leak shows it), a larger listing is refused
# The Grep tool runs ripgrep, which skips what .gitignore hides. ponytail: taken from ripgrep's documented default, not measured
# against the tool; set False to refuse a Grep over any directory that holds a secret file, ignored or not.
GREP_TOOL_HONOURS_GITIGNORE = True
TREE_REASON = ("Blocked by guard-secrets: this search would read the secret file %s in the tree. Search a narrower path, "
               "exclude it (grep --exclude='.env*', rg -g '!.env*', a Grep glob such as *.py) or use git grep.")
TREE_BIG = ("Blocked by guard-secrets: the directory is too large to check for secret files before a recursive search. "
            "Search a narrower path or use git grep.")


class _TooBig(Exception):
    pass


def _tree_secrets(root):
    """Secret-named files in `root` and its sub-directories (SCAN_DEPTH levels). More than SCAN_MAX entries: _TooBig."""
    found, seen, todo = [], 0, [(root, 1)]
    while todo:
        folder, depth = todo.pop()
        try:
            with os.scandir(folder) as entries:
                for e in entries:
                    seen += 1
                    if seen > SCAN_MAX:
                        raise _TooBig
                    if e.is_dir(follow_symlinks=False):
                        if depth < SCAN_DEPTH and e.name not in SKIP_DIRS:
                            todo.append((e.path, depth + 1))
                    elif SECRET_RE.search(e.name):
                        found.append(e.name)
        except OSError:
            continue   # unreadable directory: the search cannot read it either
    return found


def _git_visible_secrets(root):
    """Secret-named files under `root` that .gitignore does not hide (tracked + untracked), any depth; None outside a repo."""
    try:
        p = subprocess.run(["git", "-C", root, "ls-files", "-co", "--exclude-standard", "-z"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        raise _TooBig
    if p.returncode != 0:
        return None
    names = (path.rsplit("/", 1)[-1] for path in p.stdout.split("\0") if path)
    return [name for name in names if SECRET_RE.search(name)]


def _glob_hit(name, glob, empty):
    """True when the file name matches the last path part of `glob` ({a,b} expanded); a glob with no name part: `empty`."""
    try:
        parts = _brace_expand(glob.lower(), [BRACE_BUDGET]) if "{" in glob else [glob.lower()]
    except _BraceBudget:
        raise _TooBig
    for part in parts:
        part = part.rsplit("/", 1)[-1]
        if (empty if not part else fnmatch.fnmatchcase(name.lower(), part)):
            return True
    return False


def _exposed(root, include, exclude, honour_gitignore):
    """Name of a secret file a recursive search of `root` would read, or None."""
    names = _git_visible_secrets(root) if honour_gitignore else None
    if names is None:
        names = _tree_secrets(root)
    for name in names:
        if any(_glob_hit(name, g, False) for g in exclude):
            continue
        if include and not any(_glob_hit(name, g, True) for g in include):
            continue
        return name
    return None


def _search_exposes(cmd, cwd):
    """Name of a secret file that a `grep -r` / an rg over hidden or ignored files in `cmd` would read, or None.
    A literal `cd DIR` earlier in the command moves the directory the targets are resolved against; a glob target is checked
    as the directory the glob sits in.
    ponytail: a $VAR target / cd and a script inside `sh -c` are not followed; upgrade when a leak through one is seen."""
    try:
        segs = _segments(cmd)
    except Exception:   # an open quote: the shell refuses the command too
        return None
    for words, _bodies, _risky in segs:
        raw = [cmd[a:b] for a, b in words]
        k = _head(raw)
        name = raw[k].rsplit("/", 1)[-1] if k < len(raw) else ""
        if name == "cd" and len(raw) > k + 1 and _plain(raw[k + 1]) is not None:
            cwd = os.path.join(cwd, os.path.expanduser(_plain(raw[k + 1])))
            continue
        tool = GREP_TOOLS.get(name)
        if not tool:
            continue
        info = _grep_args(raw, k, tool)
        if not (info["recursive"] if tool == "grep" else info["hidden"] or info["no_ignore"]):
            continue
        for target in [raw[i] for i in info["paths"]] or ["."]:
            path = _plain(target)
            if path is None:
                continue
            glob_at = min((path.find(c) for c in "*?[{" if c in path), default=-1)
            if glob_at >= 0:
                path = os.path.dirname(path[:glob_at]) or "."
            path = os.path.join(cwd, os.path.expanduser(path))
            if os.path.isdir(path):
                hit = _exposed(path, info["include"], info["exclude"], tool == "rg" and not info["no_ignore"])
                if hit:
                    return hit
    return None


def tree_reason(payload):
    """Why this call is refused although it names no secret file: the tree it searches holds one. None: nothing found."""
    tool = payload.get("tool_name") or ""
    ti = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or os.getcwd()
    try:
        if tool == "Bash":
            hit = _search_exposes(ti.get("command") or "", cwd)
        elif tool == "Grep":
            path = os.path.join(cwd, os.path.expanduser(ti.get("path") or "."))
            if not os.path.isdir(path):
                return None
            glob = str(ti.get("glob") or "")
            include, exclude = ([], [glob[1:]]) if glob.startswith("!") else ([glob] if glob else [], [])
            hit = _exposed(path, include, exclude, GREP_TOOL_HONOURS_GITIGNORE)
        else:
            return None
    except _TooBig:
        return TREE_BIG
    return TREE_REASON % hit if hit else None


def subject(payload):
    """The text this tool call can expose: a shell command or a file path."""
    tool = payload.get("tool_name") or ""
    ti = payload.get("tool_input") or {}
    if tool == "Bash":
        return ti.get("command") or ""
    if tool == "Read":
        return ti.get("file_path") or ""
    if tool == "Grep":   # a `!glob` EXCLUDES files: it names nothing that is read
        return " ".join(v for v in (str(ti.get(k) or "") for k in ("path", "glob")) if not v.startswith("!"))
    return ""


def judged_text(payload):
    """What the secret patterns are matched against: the command without its commit messages and its data-only words."""
    text = subject(payload)
    if payload.get("tool_name") != "Bash":
        return text
    if "commit" in text:
        try:
            text = scrub_commit_messages(text)
        except Exception:   # ValueError, RecursionError...: cannot tell message from command, judge it whole (block is the safe side)
            return text
    try:
        return scrub_data_words(text)
    except Exception:       # _Whole, ValueError, RecursionError: every word stays judged
        return text


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        text = subject(payload)
        if payload.get("tool_name") == "Bash" and ENV_CHECK.match(text):
            return
        reason = REASON if text and _hits_secret(judged_text(payload)) else tree_reason(payload)
        if reason:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                     "permissionDecision": "deny",
                                                     "permissionDecisionReason": reason}}))
    except Exception as exc:   # fail CLOSED (#873): a scanner we cannot trust must not wave a tool call through
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                 "permissionDecision": "deny",
                                                 "permissionDecisionReason":
                                                 "Blocked by guard-secrets: internal hook error (%s), refusing "
                                                 "to judge this call safe." % type(exc).__name__}}))


if __name__ == "__main__":
    main()
