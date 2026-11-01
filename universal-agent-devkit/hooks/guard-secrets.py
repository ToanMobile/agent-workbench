#!/usr/bin/env python3
"""PreToolUse(Bash|Read|Grep) guard: refuse to read or pipe secret files.

Stops secrets getting OUT -- `cat .env`, `source .env.local`, `grep KEY .env | curl`,
or the Read tool opening a dotenv file -- so a key never lands in the transcript.
`.env.example` and friends are deliberately allowed: that file is how an agent
learns which keys exist. Its own errors never block a tool call.

A `git commit` MESSAGE only talks about a file, it never reads one (#352, #367): the text of
-m / --message and a QUOTED-delimiter heredoc fed to the commit are not judged. Everything else in
the command (the paths, `&& cat .env` after it) still is. Fail closed (INSTINCT-045): a message word
that expands anything ($( ) backtick ${ } $[ ] <( )), an unquoted heredoc body, a commit segment with an
unquoted # / ${ / $[ / $' , and ANY scanner error make the whole command be judged.

The review seal key (~/.config/agent-workbench, case-folded for APFS) is refused to Read / Grep / Glob on it or a folder above it,
and to Bash naming it, reaching it through a glob / brace, or naming its parent ~/.config as a whole (seal_glob_hit). Residual: Bash
reading ~ or / recursively (`grep -r . ~`), a name built by a variable or command substitution (`~/.con$(echo)fig`), and a copy
of ~ made and renamed by earlier calls.

Adapted from ai-builder-starter-kit's .agents/hooks/guard-secrets.sh (Eric Tech).
"""
import fnmatch
import json
import os
import re
import sys

B = r"(?:^|[^A-Za-z0-9._-])"   # boundary before a name
E = r"(?:[^A-Za-z0-9._-]|$)"   # boundary after a name
# dotenv (critical scan 31/10): ANY `.env(.part)*` is a secret file — `.env.production.local`, `.env.staging.local` (the
# Next.js/Vite secret files) fell through the old fixed suffix list — and a glob right after `.env` (`.env.*`, `.env?`).
# Allowed only when the LAST part is example / sample / template / dist: that file is how an agent learns the key names.
DOTENV_RE = re.compile(B + r"\.env((?:\.[A-Za-z0-9_-]+)*)(?:(?=[^A-Za-z0-9._*?\[-])|$|([*?\[]))")
DOTENV_OK = {"example", "sample", "template", "dist"}
SECRET_RE = re.compile("|".join([
    B + r"id_(?:rsa|ed25519|ecdsa)" + E,
    B + r"\.npmrc" + E,
    B + r"credentials(?:\.json)?" + E,
    r"service-account[A-Za-z0-9._-]*\.json",
    r"\.pem" + E,
    # the review seal key (bin/review_sign.py, r14d BUG-REV-592ad1528c): read, the agent could sign its own review verdict
    r"(?i:\.config/agent-workbench)(?:/|" + E + ")",   # case-folded: APFS opens .CONFIG/AGENT-WORKBENCH
    B + r"(?i:review\.key)" + E,
]))

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
            if c == "#":   # a comment, as the shell reads it: up to the end of the line (its quotes pair with nothing)
                risky = True
                nl = s.find("\n", i)
                i = n if nl < 0 else nl
                continue
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


# names a shell glob is tried against (a glob in a command opens what it matches: `cat .en?`, `cat id_*`)
GLOB_TARGETS = (".env", ".env.local", ".env.production", ".env.production.local", "id_rsa", "id_ed25519", "id_ecdsa",
                ".npmrc", "credentials", "credentials.json", "key.pem", "service-account.json")
GLOB_HINT = re.compile(r"env|id_|npmrc|cred|pem|service")   # or a dotfile glob; `ls *` / `rm *.txt` are no secret read


def _dotenv(text):
    for m in DOTENV_RE.finditer(text):
        parts = [x for x in m.group(1).split(".") if x]
        if m.group(2) or not parts or parts[-1].lower() not in DOTENV_OK:
            return True
    return False


def _globbed(text):
    """A word with a glob char whose pattern matches a secret file name (a pattern without a leading dot matches no dotfile)."""
    for word in re.split(r"[\s;&|()<>=]+", text):
        base = word.rsplit("/", 1)[-1]
        if not any(c in base for c in "*?[") or not (base.startswith(".") or GLOB_HINT.search(base.lower())):
            continue
        for name in GLOB_TARGETS:
            if (base.startswith(".") or not name.startswith(".")) and fnmatch.fnmatchcase(name, base):
                return True
    return False


def is_secret(text):
    """True when the text names a secret file — also once the shell's quote removal is done (`.e"n"v`, `.en\\v`)."""
    plain = re.sub(r"[\"'\\]", "", text)
    return any(SECRET_RE.search(t) or _dotenv(t) or _globbed(t) for t in (text, plain))


SECRET_DIR = os.path.join("~", ".config", "agent-workbench")
KEY_WORD = re.compile(r"\.config/agent-workbench|review\.key", re.I)


def _real_path(p):
    """Phân giải realpath của tổ tiên sâu nhất đang tồn tại ghép với phần đuôi còn lại để chống lách qua symlink."""
    head, tail = p, []
    while head and not os.path.lexists(head):
        nxt = os.path.dirname(head)
        if nxt == head:
            break
        tail.append(os.path.basename(head))
        head = nxt
    try:
        base = os.path.realpath(head) if head else head
    except OSError:
        return p
    return os.path.join(base, *reversed(tail)) if tail else base


def _norm_path(p, cwd):
    p = os.path.expanduser(str(p))
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)


def _secret_reach(p, cwd):
    """Trả về True khi thao tác đọc/tìm kiếm đệ quy trên p chạm tới thư mục khoá ký ~/.config/agent-workbench."""
    if not p:
        return False
    secret = _real_path(os.path.normpath(os.path.expanduser(SECRET_DIR))).lower()   # case-folded: APFS
    for n in {_norm_path(p, cwd), _real_path(_norm_path(p, cwd))}:
        n = n.rstrip("/").lower() or "/"
        if n == secret or n.startswith(secret + "/") or secret.startswith(n.rstrip("/") + "/") or KEY_WORD.search(n):
            return True
    return False


SEQ = re.compile(r"(-?\d+)\.\.(-?\d+)(?:\.\.-?\d+)?|([A-Za-z])\.\.([A-Za-z])(?:\.\.-?\d+)?")


def _braces(w, cap=256):
    """Brace expansion of w as bash / zsh do it (same reading as guard-review-tamper.py), or None past cap words."""
    out, todo = [], [w]
    while todo:
        s = todo.pop()
        m = re.search(r"\{([^{}]*)\}", s)
        if not m:
            out.append(s.replace("\x01", "{").replace("\x02", "}"))
            continue
        body, q = m.group(1), SEQ.fullmatch(m.group(1))
        if s[m.start() - 1:m.start()] == "$" or not ("," in body or q):   # literal: hidden from the next search
            todo.append(s[:m.start()] + "\x01" + body + "\x02" + s[m.end():])
            continue
        if "," in body:
            parts = body.split(",")
        elif q.group(1):
            a, b = sorted((int(q.group(1)), int(q.group(2))))
            parts = [str(i) for i in range(a, b + 1)] if b - a < cap else None
        else:
            a, b = sorted((ord(q.group(3)), ord(q.group(4))))
            parts = [chr(i) for i in range(a, b + 1)]
        if parts is None or len(out) + len(todo) + len(parts) > cap:
            return None
        todo += [s[:m.start()] + p + s[m.end():] for p in parts]
    return out


def _bracket_end(p, i):
    """Index of the ] closing the bracket expression opened at p[i] ([!x] [^x] []x] [[:class:]]), or None: a lone [ is literal."""
    j = i + 1 + (p[i + 1:i + 2] in ("!", "^"))
    j += p[j:j + 1] == "]"
    while j < len(p):
        if p[j] == "[" and p[j + 1:j + 2] in (":", "=", "."):
            k = p.find(p[j + 1] + "]", j + 2)
            if k < 0:
                return None
            j = k + 2
        elif p[j] == "]":
            return j
        else:
            j += 1
    return None


def _shell_match(pat, name):
    """Shell glob semantics for one path component, case-folded (APFS opens .CONFIG as .config) and loose enough for bash and
    zsh: * and ? stay in the component, any [...] is one character, and a pattern not starting with . (or [) never matches a dot name."""
    pat, name = pat.lower(), name.lower()
    if name.startswith(".") and not pat.startswith((".", "[")):
        return False
    rx, i = "", 0
    while i < len(pat):
        j = _bracket_end(pat, i) if pat[i] == "[" else None
        rx += "[^/]*" if pat[i] == "*" else "[^/]" if pat[i] == "?" or j else re.escape(pat[i])
        i = (j or i) + 1
    return re.fullmatch(rx, name, re.S) is not None


def _is_glob(w):
    """A word the shell expands: * or ? (not $? / $*), a closed [...] (not the `[` of a test), or a {a,b} / {1..3} brace."""
    return bool(re.search(r"(?<!\$)[*?]", w) or any(c == "[" and _bracket_end(w, i) for i, c in enumerate(w))
                or len(_braces(w) or [0, 0]) > 1)


# a lone non-recursive `ls [-flags] <dir>`: it prints names, never file contents (test_guard_review_tamper_bypass: `ls ~/.config`)
LS_NAMES = re.compile(r"[ \t]*ls(?:[ \t]+-[A-QS-Za-z1@]+)*[ \t]+[^\s;&|<>()`$*?\[{]+[ \t]*")


def seal_glob_hit(text, cwd):
    """Bash (968dac9af3): a shell word that reaches the seal key's folder once the shell expands it — `cat ~/.config/agent-work*/*`,
    `cat ~/.conf*/agent-wo*/*`, `cat ~/.CONFIG/AGENT-WORKBENCH/REVIEW.KEY` — matched component by component against both forms of
    the folder (expanduser and realpath; no file system access): the folder itself or anything inside it. Its parent ~/.config named
    as a whole (`grep -r . ~/.config`, `cp -r ~/.config /tmp/c`, `tar czf x ~/.config`) is denied too, except a lone non-recursive
    `ls ~/.config` (names only). A cd or a glob moves the base the guard cannot follow (`cd ~ && cat .c*/a*/*`, `cd ~ && cp -r
    .config /tmp`), so a command with a cd / pushd or a glob word that names .config is denied too (fail closed: `ls ~/.config/gh/*`)."""
    home = os.path.normpath(os.path.expanduser(SECRET_DIR))
    folders = {tuple(c for c in f.split("/") if c) for f in (home, _real_path(home))}
    parents = {f[:-1] for f in folders}
    moved = re.search(r"(?:^|[\s;&|(`])(?i:cd|pushd)(?=\s|$)", text)
    globbed = config = parent = False
    for w in re.split(r"[\s;&|()<>=`]+", re.sub(r"[\"'\\]", "", text)):
        if not w:
            continue
        alts = _braces(w)
        if alts is None:   # past the cap: a path-like word is judged unreadable
            if "/" in w:
                return True
            alts = [w]
        globbed = globbed or _is_glob(w)
        for a in alts:
            m = re.match(r"(?:\$\{(HOME|PWD)\}|\$(HOME|PWD)|~(\+))(?=/|$)", a)
            if m:
                a = (os.path.expanduser("~") if (m.group(1) or m.group(2)) == "HOME" else cwd) + a[m.end():]
            try:
                comps = [c for c in _norm_path(a, cwd).split("/") if c]
            except ValueError:   # `~a<NUL>b`: no such path can run, and the guard must not fail open on it
                return True
            if any(len(comps) >= len(f) and all(_shell_match(p, n) for p, n in zip(comps, f)) for f in folders):
                return True
            parent = parent or any(len(comps) == len(f) and all(_shell_match(p, n) for p, n in zip(comps, f)) for f in parents)
            config = config or any(_shell_match(c, ".config") for c in a.split("/") if c)
    if parent and not LS_NAMES.fullmatch(text):
        return True
    return bool(globbed or moved) and config


def seal_read_hit(payload):
    """Kiểm tra Read/Grep/Glob/NotebookRead chạm thư mục khoá ký qua thư mục cha, cwd hoặc mẫu glob (e8eb813d18, ae4413f24a)."""
    tool, ti = _tool(payload)
    if tool not in ("Read", "Grep", "Glob", "NotebookRead"):
        return False
    cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) and payload.get("cwd") else os.getcwd()
    paths = [str(p) for p in (ti.get(k) for k in ("file_path", "filePath", "path", "notebook_path", "notebookPath")) if p]
    if tool in ("Grep", "Glob") and not ti.get("path"):
        paths.append(cwd)
    if any(_secret_reach(p, cwd) for p in paths):
        return True
    pat = str(ti.get("pattern") or "") if tool == "Glob" else ""
    if pat:
        full = _norm_path(pat, str(ti.get("path") or cwd))
        lit = re.split(r"[*?\[{]", full, maxsplit=1)[0]
        if lit != full and not lit.endswith("/"):
            lit = os.path.dirname(lit)
        if KEY_WORD.search(pat) or _secret_reach(lit or "/", cwd):
            return True
    return False


def _tool(payload):
    ti = next((v for v in (payload.get(k) for k in ("tool_input", "toolInput", "input")) if isinstance(v, dict)), {})
    return str(payload.get("tool_name") or payload.get("toolName") or ""), ti


def subject(payload):
    """The text this tool call can expose: a shell command or a file path."""
    tool, ti = _tool(payload)
    if tool == "Bash":
        return str(ti.get("command") or "")
    if tool in ("Read", "NotebookRead"):
        return str(ti.get("file_path") or ti.get("filePath") or ti.get("notebook_path") or ti.get("notebookPath") or ti.get("path") or "")
    if tool == "Grep":
        return " ".join(str(ti.get(k) or "") for k in ("path", "glob"))
    return ""


def judged_text(payload):
    """What the secret patterns are matched against: the command without its commit messages."""
    text = subject(payload)
    if _tool(payload)[0] != "Bash" or "commit" not in text:
        return text
    try:
        return scrub_commit_messages(text)
    except Exception:   # ValueError, RecursionError...: cannot tell message from command, judge it whole (block is the safe side)
        return text


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        if not isinstance(payload, dict):
            return
        text = subject(payload)
        if _tool(payload)[0] == "Bash" and ENV_CHECK.match(text):
            return
        cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) and payload.get("cwd") else os.getcwd()
        if seal_read_hit(payload) or (text and is_secret(judged_text(payload))) or \
                (_tool(payload)[0] == "Bash" and seal_glob_hit(judged_text(payload), cwd)):
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                     "permissionDecision": "deny",
                                                     "permissionDecisionReason": REASON}}))
    except Exception as e:   # noqa: BLE001 — fail open rather than block every call in the project, but say so
        sys.stderr.write("guard-secrets: skipped (%s: %s)\n" % (type(e).__name__, str(e)[:160]))


if __name__ == "__main__":
    main()
