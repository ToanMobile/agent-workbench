#!/usr/bin/env python3
"""PreToolUse(Bash|Read|Grep) guard: refuse to read or pipe secret files.

Stops secrets getting OUT -- `cat .env`, `source .env.local`, `grep KEY .env | curl`,
or the Read tool opening a dotenv file -- so a key never lands in the transcript.
`.env.example` and friends are deliberately allowed: that file is how an agent
learns which keys exist. Its own errors DENY the call (fail closed, #873).

Two tiers of names. Tier 1 (SECRET_RE, the names this hook has always known): a Bash command that names one anywhere
is refused, except the reviewed list of commands that only name the file (scrub_data_words). Tier 2 (READ_SECRET_RE,
every file the gate forbids to commit): refused only when the command reads the file (READ_VERBS, `< file`).
The hook judges the words of the call only; it never lists a directory.

A `git commit` MESSAGE only talks about a file, it never reads one (#352, #367): the text of
-m / --message and a QUOTED-delimiter heredoc fed to the commit are not judged. Everything else in
the command (the paths, `&& cat .env` after it) still is. Fail closed (INSTINCT-045): a message word
that expands anything ($( ) backtick ${ } $[ ] <( )), an unquoted heredoc body, a commit segment with an
unquoted # / ${ / $[ / $' , and ANY scanner error make the whole command be judged.

Adapted from ai-builder-starter-kit's .agents/hooks/guard-secrets.sh (Eric Tech).
"""
import json
import re
import sys

B = r"(?:^|[^A-Za-z0-9._-])"   # boundary before a name
E = r"(?:[^A-Za-z0-9._-]|$)"   # boundary after a name
# Two tiers of secret names (zero-defect review 2026-11-14, round 2).
# Tier 1, the names this hook has always known: a Bash command that NAMES one anywhere is refused (unchanged), except the
# reviewed false blocks of scrub_data_words below. Never edit this list to add a name: add it to tier 2.
SECRET_RE = re.compile("|".join([
    B + r"\.env" + E,
    r"\.env\.(?:local|production|prod|staging|development|dev|test)" + E,
    B + r"id_(?:rsa|ed25519|ecdsa)" + E,
    B + r"\.npmrc" + E,
    B + r"credentials(?:\.json)?" + E,
    r"service-account[A-Za-z0-9._-]*\.json",
    r"\.pem" + E,
]), re.I)   # upper case too: .ENV opens the same file on a case-insensitive filesystem (#873)
# Secret names a glob / brace / ANSI-C word can spell without writing the plain name (#873).
GLOB_NAMES = (".env", ".env.local", ".env.production", ".env.prod", ".env.staging", ".env.development", ".env.dev",
              ".env.test", ".npmrc", "id_rsa", "id_ed25519", "id_ecdsa", "credentials.json", "credentials")

# Tier 2, every file bin/post-fix-gate.py forbids to commit (FORBIDDEN_SECRET_FILES, ENV_FILE_PATTERN; INSTINCT-015,
# tests/gates/test_guard_secrets_zero_defect.sh C3x reads the gate's list and fails when the two drift apart) plus the
# credential stores of the home directory. These names are everyday build inputs (keytool -keystore x.jks, gradle
# -Pandroid.injected.signing.store.file=..., git add google-services.json): a command is refused only when it READS the
# file -- the file is an operand of a READ_VERBS command, the target of `< file`, or the path of the Read / Grep tool.
# A template copy (.env.example, local.properties.sample) stays readable.
TEMPLATE_SUFFIXES = (".example", ".sample", ".template", ".dist")
NOT_TEMPLATE = "".join(r"(?<!%s)" % re.escape(s) for s in TEMPLATE_SUFFIXES)
SECRET_EXT = r"(?:key|jks|keystore|p12|pfx|mobileprovision|env)"
# <name>.<SECRET_EXT> as a whole path word: `server.key`, `prod.env`, `$HOME/x.jks`. Not `jq .key`, `obj.key)`, `process.env`.
PATH_WORD = (r"(?:^|[\s'\"=<>:@/])(?!(?:process|import\.meta)\.env(?![A-Za-z0-9_-]))"
             r"[A-Za-z0-9_-][A-Za-z0-9_.-]*\." + SECRET_EXT + r"(?=$|[\s'\";&|)<>])")
READ_SECRET_RE = re.compile("|".join([
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
    # not local.properties: machine paths (sdk.dir=...) every Android agent reads; the gate still forbids committing it
    # (GATE_ONLY in tests/gates/test_guard_secrets_zero_defect.sh C3x)
    B + r"keystore\.properties" + E,
    r"google-services\.json" + E,
    r"GoogleService-Info\.plist" + E,
    r"service-account[A-Za-z0-9._-]*\.json",
    r"\.pem" + E,
    PATH_WORD,
]), re.I)
READ_GLOB_NAMES = GLOB_NAMES + ("id_dsa", ".envrc", ".dev.vars", ".netrc", ".git-credentials", ".pypirc", ".dockercfg",
                                "secrets.json", "secrets.yml", "secrets.yaml", "keystore.properties",
                                "google-services.json", "googleservice-info.plist")
GLOB_EXT = re.compile(r"\.(?:pem|key|jks|keystore|p12|pfx|mobileprovision|env)\Z", re.I)   # *.jks: the extension names a secret
GENERIC_EXT_GLOB = re.compile(r"\*\.[A-Za-z0-9]+\Z")
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


def _glob_matches_secret(pat, read=False):
    """True when the glob `pat` (its last path part) can spell a secret name and says enough of it: >= 3 literal characters,
    at least half of the name. Linear in len(pat): an NFA over the (<= 24 char) name, no fnmatch, no regex backtracking.
    read=True (the glob is an operand of a read verb, tier 2): the wider name list, a secret extension (*.jks) and a glob
    that starts like the dotenv name (.e*, .en?) count too.
    ponytail: [...] counts as any one character (stricter than the shell), the half-name rule lets `cred*` through."""
    pat = pat.rsplit("/", 1)[-1]
    if not any(c in pat for c in "*?["):
        return False
    if read:
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
    # `*.properties`, `*.json`: an everyday extension glob says nothing of a tier 2 name (gradle.properties, package.json).
    by_extension = bool(GENERIC_EXT_GLOB.match(pat))
    for name in (READ_GLOB_NAMES if read else GLOB_NAMES):
        if 2 * literal < len(name) or (by_extension and name not in GLOB_NAMES):
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


def _hits_secret(text, read=False):
    """Secret named by `text` directly, through $'..' quoting, brace expansion, a glob word or a find -name glob.
    read=False: the tier 1 names (any word of a command); read=True: the tier 2 names (text that is READ)."""
    names = READ_SECRET_RE if read else SECRET_RE
    decoded = _decode_ansi_c(text)
    if names.search(text) or names.search(decoded):
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
            if names.search(w) or _glob_matches_secret(w, read):
                return True
    if FIND_EXEC.search(decoded):
        for m in FIND_NAME.finditer(decoded):
            if _glob_matches_secret(next(g for g in m.groups() if g is not None), read):
                return True
    return False


# ---- Shared helpers of the two tiers -----------------------------------------------------------------------------------------
class _Whole(Exception):
    """Data and code cannot be told apart safely in this command: every word of it is judged."""


SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
SHELL_C = re.compile(r"^-[a-z]*c$")
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
FD_DUP = re.compile(r"^\d*>&(?:\d+|-)$")   # 2>&1, >&2, 2>&-: no file is named
PLAIN_PATH = re.compile(r"^[A-Za-z0-9_./~-]+$")
GREP_TOOLS = {"grep": "grep", "egrep": "grep", "fgrep": "grep", "rg": "rg", "ag": "grep", "ack": "grep"}
SHORT_VALUE = {"grep": "efmABCdD", "rg": "efgtTABCmjMEdr"}
SHORT_FLAG = {"grep": "EFGPivwxclLoqsHhnrRIzabUuTZ0123456789", "rg": "ivwxcloqsSHhnNFPUupIzaLb.0"}
SHORT_NAME = {"e": "regexp", "f": "file", "g": "glob"}
LONG_VALUE = {"regexp", "file", "glob", "iglob", "include", "exclude", "exclude-dir", "exclude-from", "ignore-file", "pre",
              "pre-glob", "type", "type-not", "type-add", "max-count", "context", "after-context", "before-context",
              "max-depth", "maxdepth", "threads", "sort", "sortr", "encoding", "replace", "max-filesize", "max-columns",
              "binary-files", "devices", "directories", "label", "engine", "colors", "path-separator", "context-separator"}
OPTIONAL_VALUE = {"context"}   # BSD grep: `--context WORD` does not take WORD (GNU grep does): not understood
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


def _split_redirects(raw, start):
    """(args, outs) of the words from `start` on. args = indexes of the ordinary words; outs = [(indexes, target text)] of the
    output redirections (`> f`, `>>f`, `2> f`). An input redirection and its target are in neither: they are always judged."""
    args, outs, i, n = [], [], start, len(raw)
    while i < n:
        w = raw[i]
        if _unquoted(w, "<"):
            i += 2 if w[-1] == "<" else 1
        elif _unquoted(w, ">"):
            target = w[w.rfind(">") + 1:].lstrip("|")
            if FD_DUP.match(w):
                i += 1
            elif target:
                outs.append(([i], target))
                i += 1
            else:
                outs.append(([i, i + 1] if i + 1 < n else [i], raw[i + 1] if i + 1 < n else ""))
                i += 2
        else:
            args.append(i)
            i += 1
    return args, outs


def _grep_args(raw, k, tool):
    """What the words after raw[k] (grep / rg) are: (data, trusted, explicit). data = indexes of the words that are a search
    pattern or an exclusion, never a file that is read. explicit = the pattern came from -e / --regexp / -f / --file: every
    positional word is then a FILE (A1). trusted = every option was understood; when False nothing may be taken for data."""
    data, positional, state = [], [], {"trusted": True, "explicit": False}
    n = len(raw)

    def option_value(name, at, val):
        if at >= n:
            state["trusted"] = False
        elif name == "regexp":
            data.append(at)
            state["explicit"] = True
        elif name == "file":
            state["explicit"] = True       # the pattern FILE is read: it stays judged
        elif name in ("exclude", "glob", "iglob"):
            text = _plain(val)
            if text is None:
                state["trusted"] = False
            elif name == "exclude" or text.startswith("!"):
                data.append(at)            # an exclusion; an include / a plain glob NAMES what is read and stays judged

    i, dashdash = k + 1, False
    while i < n:
        w = raw[i]
        if _unquoted(w, "<>"):   # a redirection and its target: never the pattern
            i += 2 if w[-1] in "<>" else 1
            continue
        if dashdash or not w.startswith("-") or w == "-":
            positional.append(i)
        elif w == "--":
            dashdash = True
        elif w.startswith("--"):
            name, eq, val = w[2:].partition("=")
            if name in LONG_VALUE or (tool == "rg" and name in ("color", "colour")):
                if not eq and name in OPTIONAL_VALUE:
                    state["trusted"] = False
                at = i if eq else i + 1
                option_value(name, at, val if eq else (raw[at] if at < n else ""))
                i = at
            elif not (name in LONG_FLAG and not eq):
                state["trusted"] = False
        else:
            for p in range(1, len(w)):
                c = w[p]
                if c in SHORT_VALUE[tool]:
                    at = i if w[p + 1:] else i + 1
                    option_value(SHORT_NAME.get(c, c), at, w[p + 1:] or (raw[at] if at < n else ""))
                    i = at
                    break
                if c not in SHORT_FLAG[tool]:
                    state["trusted"] = False
        i += 1
    if positional and not state["explicit"]:
        data.append(positional[0])   # the first positional word is the pattern only when no -e / -f gave one
    return data, state["trusted"], state["explicit"]


# ---- Tier 1 exemptions: words that only NAME a secret file (review 2026-11-14, list B) ----------------------------------------
# The old hook refused these everyday commands although none reads the file. This is the complete, reviewed list; every other
# command that names a tier 1 file is refused as before:
#   test / [ / [[ -f X, ls X, touch X, chmod M X                (look at or create the name, never the content)
#   git rm --cached X, git check-ignore / status / ls-files X    (not `git status -v`: it prints the diff)
#   cp <template file> X                                         (only the destination)
#   echo / printf text; `>` only into /dev/null, .gitignore or the dotenv file itself (a write, not a read); not `printf -v`
#   cat >> .gitignore <<'QUOTED' ... (the heredoc body)
#   grep / rg: the PATTERN word (only without -e / -f), --exclude=G, --glob '!G'
#   gh pr create --title T --body T
#   find ... -name G                                             (no -exec / -ok / -delete)
#   docker compose --env-file X up|down|build|...                (not `config`: it prints the values)
#   ssh -i X host ...
# Each is decided per simple command (split on ; && || | & and newlines). Fail closed: a simple command with $( ) or a backtick
# or an unquoted # / ${ keeps all its words, so does one piped on (its output can become a read); a command with <( ), $_,
# xargs / read, eval / source or a shell is judged whole.
DOLLAR_UNDERSCORE = re.compile(r"\$_(?![A-Za-z0-9_])|\$\{_\}")   # $_ = the last argument of the previous command
NAME_CONSUMERS = {"xargs", "parallel", "read", "mapfile", "readarray"}   # turn a printed name into an argument
CODE_RUNNERS = {"eval", "source", "."}
NAME_ONLY = {"test", "[", "[[", "ls", "touch", "chmod"}
TEXT_ONLY = {"echo", "printf"}
GIT_NAME_ONLY = {"check-ignore", "status", "ls-files"}   # plus `rm --cached`
GITIGNORE = r"(?:[A-Za-z0-9_./~-]*/)?\.gitignore"
# The dotenv target is a name SECRET_RE knows, so the file written stays guarded (`> .env.py; python3 .env.py` is not).
SAFE_TEXT_TARGET = re.compile(r"^(?:/dev/null|%s|(?:[A-Za-z0-9_./~-]*/)?\.env"
                              r"(?:\.(?:local|production|prod|staging|development|dev|test))?)$" % GITIGNORE)
FUNC_DEF = re.compile(r"\(\s*\)")   # name() { ... }: a function can give an exempt command name another meaning
GITIGNORE_TARGET = re.compile("^%s$" % GITIGNORE)
CP_FLAGS = re.compile(r"^-[fipnvaRr]+$")
EXEMPT_GREP = {"grep", "egrep", "fgrep", "rg"}
FIND_NAME_OPTS = {"-name", "-iname", "-path", "-ipath", "-wholename", "-iwholename"}
FIND_ACTIONS = {"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"}
COMPOSE_VALUE_OPTS = {"--env-file", "-f", "--file", "-p", "--project-name", "--profile", "--project-directory", "--ansi",
                      "--progress", "--parallel"}
COMPOSE_SAFE = {"up", "down", "build", "pull", "push", "ps", "start", "stop", "restart", "rm", "create", "kill", "pause",
                "unpause", "top", "images", "ls"}
SSH_VALUE_OPTS = set("-" + c for c in "BbcDEeFIiJLlmOopQRSWw")


def _data_words(cmd, words, raw, k, name):
    """Indexes of the words of one simple command (command word raw[k], basename `name`) that cannot make it read a file."""
    rest = cmd[words[-1][1]:].lstrip(" \t")
    # What a command prints can become a read further down a pipe (`ls X | cat`-style consumers, echo "cat X" | python3).
    # `&> file` saves it: the & ends the simple command, so the redirection is not among its words.
    piped = (rest.startswith("|") and not rest.startswith("||")) or rest.startswith("&>") or raw[-1][-1] in "<>"
    args, outs = _split_redirects(raw, k + 1)
    # ... and so can a list of names saved to a file (`ls X > names; cat $(cat names)`).
    kept = piped or any(target != "/dev/null" for _idx, target in outs)
    if name in NAME_ONLY:
        return [] if kept else args
    if name in TEXT_ONLY:   # text written to a file can be run later: only the targets of SAFE_TEXT_TARGET
        if piped or (name == "printf" and any(raw[i].startswith("-v") for i in args)):
            return []       # `printf -v VAR` assigns a variable
        if any(not SAFE_TEXT_TARGET.match(target) for _idx, target in outs):
            return []
        return args + [i for idx, _target in outs for i in idx]
    if name == "git":   # only `git [-C dir] <sub>`: `-c alias.x=!cmd` and friends keep every word judged
        j = k + 1
        while j + 1 < len(raw) and raw[j] == "-C":
            j += 2
        sub = raw[j] if j < len(raw) else ""
        rest_words = raw[j + 1:]
        if kept or (sub == "status" and any(w.startswith("-v") or w == "--verbose" for w in rest_words)):
            return []   # `git status -v` prints the diff of the file
        if sub in GIT_NAME_ONLY or (sub == "rm" and "--cached" in rest_words):
            return _split_redirects(raw, j + 1)[0]
        return []
    if name == "cp":    # `cp .env.example .env`: only the DESTINATION, and only when every source is a template file
        after = range(k + 1, len(raw))
        files = [i for i in after if not raw[i].startswith("-")]
        if (len(files) >= 2 and all(CP_FLAGS.match(raw[i]) for i in after if raw[i].startswith("-"))
                and all(PLAIN_PATH.match(raw[i]) for i in files)
                and all(raw[i].lower().endswith(TEMPLATE_SUFFIXES) for i in files[:-1])):
            return [files[-1]]
        return []
    if name in EXEMPT_GREP:   # a brace / glob word becomes several words in the shell: positions cannot be trusted then
        if any(_unquoted(w, "{*?[") for w in raw):
            return []
        data, trusted, explicit = _grep_args(raw, k, GREP_TOOLS[name])
        return data if trusted and not explicit else []
    if name == "gh" and raw[k + 1:k + 3] == ["pr", "create"]:   # --title / --body text; --body-file stays judged
        out = []
        for i in range(k + 3, len(raw)):
            if raw[i] in ("--title", "--body", "-t", "-b") and i + 1 < len(raw) and not _unquoted(raw[i + 1], "<>"):
                out.append(i + 1)
            elif raw[i].startswith(("--title=", "--body=")):
                out.append(i)
        return out
    if name == "find":   # the name pattern of a listing; an action that runs or deletes keeps every word judged
        if kept or any(w in FIND_ACTIONS for w in raw):
            return []
        return [i + 1 for i in range(k + 1, len(raw) - 1) if raw[i] in FIND_NAME_OPTS]
    if name in ("docker", "docker-compose"):
        j = k + 1
        if name == "docker":
            if raw[j:j + 1] != ["compose"]:
                return []
            j += 1
        out, sub = [], None
        while j < len(raw):
            if raw[j] in COMPOSE_VALUE_OPTS:
                if raw[j] == "--env-file" and j + 1 < len(raw):
                    out.append(j + 1)
                j += 2
            elif raw[j].startswith("--env-file="):
                out.append(j)
                j += 1
            elif raw[j].startswith("-"):
                j += 1
            else:
                sub = raw[j]
                break
        return out if sub in COMPOSE_SAFE and not piped else []
    if name == "ssh":   # the identity file is used, not printed; only before the host (a later -i belongs to the remote command)
        out, j = [], k + 1
        while j < len(raw) and raw[j].startswith("-"):
            if raw[j] == "-i" and j + 1 < len(raw) and PLAIN_PATH.match(raw[j + 1]):
                out.append(j + 1)
            j += 2 if raw[j] in SSH_VALUE_OPTS else 1
        return out
    return []


def scrub_data_words(cmd):
    """cmd with the words that only name a file blanked. Raises _Whole / ValueError when the command must be judged whole."""
    if "<(" in cmd or ">(" in cmd or DOLLAR_UNDERSCORE.search(cmd) or FUNC_DEF.search(cmd):
        raise _Whole
    out = list(cmd)

    def blank(a, b):
        for p in range(a, b):
            if out[p] != "\n":
                out[p] = " "

    for words, bodies, risky in _segments(cmd):
        raw = [cmd[a:b] for a, b in words]
        k = _head(raw)
        if k >= len(raw):
            continue
        name = raw[k].rsplit("/", 1)[-1]
        if (name in CODE_RUNNERS or name in SHELLS or name in ("function", "alias")
                or any(w.rsplit("/", 1)[-1] in NAME_CONSUMERS for w in raw)):
            raise _Whole
        if risky or any("$(" in w or "`" in w for w in raw):
            continue
        for idx in _data_words(cmd, words, raw, k, name):
            blank(*words[idx])
        if name == "cat" and bodies:   # cat >> .gitignore <<'EOF': the body is text appended to the ignore file
            args, outs = _split_redirects(raw, k + 1)
            if not args and len(outs) == 1 and GITIGNORE_TARGET.match(outs[0][1]):
                for a, b in bodies:
                    blank(a, b)
    return "".join(out)


# ---- Tier 2: does the command READ a file? ------------------------------------------------------------------------------------
# The closed list of read verbs. A tier 2 name is refused only as an operand of one of them (or as the target of `< file`).
# Adding a verb here needs a deny + an allow case in tests/gates/test_guard_secrets_zero_defect.sh (group RV).
PLAIN_READERS = {"cat", "head", "tail", "less", "more", "bat", "nl", "tac", "source", ".", "cut", "sort", "uniq", "strings",
                 "xxd", "hexdump", "od", "base64"}   # every word after the verb is a file it reads
PATTERN_READERS = {"grep", "egrep", "fgrep", "rg", "ag", "ack"}    # not the pattern word, not an exclusion
SCRIPT_READERS = {"sed", "awk", "gawk"}                            # not the script (the first word, or the -e values)
# A local copy / archive (cp, mv, install, ln, tar, zip, scp / rsync between local paths) prints nothing and is NOT a read:
# agents copy google-services.json and keystores into a worktree every day. Tier 1 names keep the old verdict (`cp .env x`).
REMOTE_COPIERS = {"scp", "rsync"}                                  # the sources, only when the destination is a remote host
REMOTE_TARGET = re.compile(r"(?:[A-Za-z0-9_.-]+@)?[A-Za-z0-9_.-]+:(?!\\)|[a-z]+://", re.I)
UPLOAD_READERS = {"curl", "wget"}                                  # only @file and the upload options
KEY_READERS = {"openssl"}                                          # not the file after -out / -keyout
INLINE_READERS = {"python", "python3", "node", "ruby"}             # only a -c / -e script that opens a file
READ_VERBS = (PLAIN_READERS | PATTERN_READERS | SCRIPT_READERS | REMOTE_COPIERS | UPLOAD_READERS | KEY_READERS
              | INLINE_READERS)
INLINE_SCRIPT_OPTS = {"-c", "-e", "-p", "--eval", "--print"}
READ_CALL = re.compile(r"open|read|load|slurp|require\(", re.I)
UPLOAD_VALUE_OPTS = {"-T", "--upload-file", "--post-file", "--body-file", "--netrc-file", "-K", "--config"}
OPENSSL_OUT = {"-out", "-keyout"}
# A command that runs another one: the wrapped command is judged like the bare one. name -> its options that take a value.
WRAPPERS = {"timeout": {"-s", "--signal", "-k", "--kill-after"}, "sudo": {"-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U"},
            "env": {"-u", "-C", "-S"}, "nice": {"-n"}, "nohup": set(), "command": set(), "exec": {"-a"}, "time": set(),
            "xargs": {"-n", "-I", "-P", "-L", "-d", "-E", "-s", "-J", "-R"}}
READ_VERB_WORD = re.compile(r"(?:^|[\s;&|(`'\"/])(?:%s)(?=\s|$)|<" % "|".join(sorted(re.escape(v) for v in READ_VERBS)))


def _base(word):
    return word.lstrip("\\").rsplit("/", 1)[-1]


def _unwrap(raw, k):
    """(index of the command word behind timeout / sudo / env / nice / ... wrappers, True when xargs is one of them)."""
    via_xargs = False
    while k < len(raw) and _base(raw[k]) in WRAPPERS:
        name = _base(raw[k])
        via_xargs = via_xargs or name == "xargs"
        k += 1
        while k < len(raw) and raw[k].startswith("-"):
            k += 2 if raw[k] in WRAPPERS[name] else 1
        if name == "timeout":
            k += 1   # the duration
        while k < len(raw) and ASSIGN.match(raw[k]):
            k += 1   # env VAR=value, sudo VAR=value
    return k, via_xargs


def _unquote(word):
    """The text inside one quoted word (best effort), the word itself when it is not quoted."""
    if len(word) >= 2 and word[0] == word[-1] and word[0] in "'\"":
        inner = word[1:-1]
        return inner.replace('\\"', '"').replace("\\$", "$").replace("\\`", "`") if word[0] == '"' else inner
    return word


def _substitutions(word):
    """Texts of the $( ) and backtick command substitutions of a shell word (none inside single quotes)."""
    out, i, n, dq = [], 0, len(word), False
    while i < n:
        c = word[i]
        if c == "\\":
            i += 2
        elif c == "'" and not dq:
            j = word.find("'", i + 1)
            i = n if j < 0 else j + 1
        elif c == '"':
            dq = not dq
            i += 1
        elif c == "$" and word[i + 1:i + 2] == "(":
            j = _skip_paren(word, i + 1)
            out.append(word[i + 2:j - 1])
            i = j
        elif c == "`":
            j = _skip_backtick(word, i)
            out.append(word[i + 1:j - 1])
            i = j
        else:
            i += 1
    return out


def _input_target(word):
    """What follows an unquoted `<` in a word (`<f` -> "f", `<` -> ""): the file an input redirection reads. None: there is
    no input redirection (`<<<`, `<&3` and quoted `<` are none)."""
    i, n = 0, len(word)
    while i < n:
        c = word[i]
        if c == "\\":
            i += 2
        elif c in "'\"":
            i = _skip_quoted(word, i, c)
        elif c == "$" and word[i + 1:i + 2] == "(":
            i = _skip_paren(word, i + 1)
        elif c == "`":
            i = _skip_backtick(word, i)
        elif c == "<":
            return None if word[i + 1:i + 2] in ("<", "&") else word[i + 1:]
        else:
            i += 1
    return None


def _read_operands(raw, k, name):
    """The words of a READ_VERBS command (command word raw[k]) that name a file it reads."""
    args = _split_redirects(raw, k + 1)[0]   # an output file is written, an input redirection is judged by _reads_secret
    if name in PATTERN_READERS:
        # A glob / brace file word becomes several words in the shell: only the words BEFORE the first one keep their place.
        first_glob = min((i for i in args if not raw[i].startswith("-") and _unquoted(raw[i], "{*?[")), default=len(raw))
        data, trusted, _explicit = _grep_args(raw, k, GREP_TOOLS[name])
        skip = set(i for i in data if i < first_glob) if trusted else set()
        kept = [raw[i] for i in args if i not in skip]
        # --include='*.jks' / -g '*.jks': grep expands the quoted glob itself, so it is judged without its quotes too
        return kept + [w.replace("'", "").replace('"', "").replace("=", " ") for w in kept if "'" in w or '"' in w]
    if name in SCRIPT_READERS:
        skip, explicit, script_opts = set(), False, ("-e", "--expression") if name == "sed" else ()
        for pos, i in enumerate(args):
            if raw[i] in script_opts and pos + 1 < len(args):
                skip.add(args[pos + 1])
                explicit = True
            elif raw[i] in ("-f", "--file") or raw[i].startswith(("-f", "--file=", "--expression=")):
                explicit = True
        if not explicit:   # the first word that is not an option (nor the '' of `sed -i ''`) is the script
            first = next((i for i in args if not raw[i].startswith("-") and raw[i] not in ("''", '""')), None)
            skip.add(first)
        return [raw[i] for i in args if i not in skip]
    if name in REMOTE_COPIERS:   # only a copy TO another host sends the content away; the sources are every other word
        files = [i for i in args if not raw[i].startswith("-")]
        if len(files) < 2 or not REMOTE_TARGET.match(raw[files[-1]].strip("'\"")):
            return []
        return [raw[i] for i in args if i != files[-1]]
    if name in UPLOAD_READERS:
        return [raw[i] for pos, i in enumerate(args)
                if "@" in raw[i] or raw[i].startswith(tuple(o + "=" for o in UPLOAD_VALUE_OPTS if o.startswith("--")))
                or (pos and raw[args[pos - 1]] in UPLOAD_VALUE_OPTS)]
    if name in KEY_READERS:
        return [raw[i] for pos, i in enumerate(args) if not (pos and raw[args[pos - 1]] in OPENSSL_OUT)]
    if name in INLINE_READERS:
        return [raw[i] for pos, i in enumerate(args)
                if pos and raw[args[pos - 1]] in INLINE_SCRIPT_OPTS and READ_CALL.search(raw[i])]
    return [raw[i] for i in args]


def _reads_secret(cmd, depth=0):
    """True when `cmd` reads a tier 2 secret file: per simple command, behind wrappers, inside $( ), backticks and `sh -c`."""
    if depth > 4:
        raise _Whole
    for words, _bodies, _risky in _segments(cmd):
        raw = [cmd[a:b] for a, b in words]
        for i, w in enumerate(raw):
            target = _input_target(w)
            if target is not None and _hits_secret(target or (raw[i + 1] if i + 1 < len(raw) else ""), True):
                return True
            if any(_reads_secret(inner, depth + 1) for inner in _substitutions(w)):
                return True
        k, via_xargs = _unwrap(raw, _head(raw))
        if k >= len(raw):
            continue
        name = _base(raw[k])
        if name in SHELLS:   # sh -c '<script>': the script is a command of its own
            for i in range(k + 1, len(raw) - 1):
                if SHELL_C.match(raw[i]):
                    script = _unquote(raw[i + 1])
                    if _reads_secret(script, depth + 1):
                        return True
                    # sh -c 'cat "$1"' _ FILE: the words after the script are its arguments
                    if READ_VERB_WORD.search(script) and _hits_secret(" ".join(raw[i + 2:]), True):
                        return True
                    break
        elif name == "eval":
            if _reads_secret(" ".join(_unquote(w) for w in raw[k + 1:]), depth + 1):
                return True
        if via_xargs:   # the file names arrive on stdin: every word of the command may be one of them
            if (name in READ_VERBS or name in SHELLS) and (
                    _hits_secret(cmd, True)
                    or any(_glob_matches_secret(next(g for g in m.groups() if g is not None), True)
                           for m in FIND_NAME.finditer(cmd))):
                return True
        elif name == "find":   # find ... -exec <read verb> {}: the names find matches are read
            runs = [_base(raw[i + 1]) for i in range(k + 1, len(raw) - 1) if raw[i] in ("-exec", "-execdir", "-ok", "-okdir")]
            if any(r in READ_VERBS or r in SHELLS for r in runs) and _hits_secret(" ".join(raw), True):
                return True
        elif name in READ_VERBS:
            operands = _read_operands(raw, k, name)
            if operands and _hits_secret(" ".join(operands), True):
                return True
    return False


def _bash_denied(cmd):
    """True when a Bash command names a tier 1 secret file outside the exempt words, or reads a tier 2 one."""
    judged = cmd
    if "commit" in cmd:
        try:
            judged = scrub_commit_messages(cmd)
        except Exception:   # ValueError, RecursionError...: cannot tell message from command, judge it whole (block is the safe side)
            return _hits_secret(cmd) or _reads_secret_closed(cmd)
    try:
        named = scrub_data_words(judged)
    except Exception:       # _Whole, ValueError, RecursionError: every word stays judged
        named = judged
    return _hits_secret(named) or _reads_secret_closed(judged)


def _reads_secret_closed(cmd):
    """_reads_secret, fail closed: a command the scanner cannot split is refused when it holds a read verb (or `<`) and a
    tier 2 name anywhere."""
    try:
        return _reads_secret(cmd)
    except Exception:
        return bool(READ_VERB_WORD.search(cmd)) and _hits_secret(cmd, True)


def subject(payload):
    """The text this tool call can expose: a shell command or a file path."""
    tool = payload.get("tool_name") or ""
    ti = payload.get("tool_input") or {}
    if tool == "Bash":
        return ti.get("command") or ""
    if tool == "Read":
        return ti.get("file_path") or ""
    if tool == "Grep":
        return " ".join(str(ti.get(k) or "") for k in ("path", "glob"))
    return ""


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        text = subject(payload)
        if payload.get("tool_name") == "Bash":
            denied = bool(text) and not ENV_CHECK.match(text) and _bash_denied(text)
        else:   # Read / Grep name the file they open: both tiers
            denied = bool(text) and (_hits_secret(text) or _hits_secret(text, True))
        if denied:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                     "permissionDecision": "deny",
                                                     "permissionDecisionReason": REASON}}))
    except Exception as exc:   # fail CLOSED (#873): a scanner we cannot trust must not wave a tool call through
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                 "permissionDecision": "deny",
                                                 "permissionDecisionReason":
                                                 "Blocked by guard-secrets: internal hook error (%s), refusing "
                                                 "to judge this call safe." % type(exc).__name__}}))


if __name__ == "__main__":
    main()
