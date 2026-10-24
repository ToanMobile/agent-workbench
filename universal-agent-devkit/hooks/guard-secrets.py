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

Adapted from ai-builder-starter-kit's .agents/hooks/guard-secrets.sh (Eric Tech).
"""
import json
import re
import sys

B = r"(?:^|[^A-Za-z0-9._-])"   # boundary before a name
E = r"(?:[^A-Za-z0-9._-]|$)"   # boundary after a name
SECRET_RE = re.compile("|".join([
    B + r"\.env" + E,
    r"\.env\.(?:local|production|prod|staging|development|dev|test)" + E,
    B + r"id_(?:rsa|ed25519|ecdsa)" + E,
    B + r"\.npmrc" + E,
    B + r"credentials(?:\.json)?" + E,
    r"service-account[A-Za-z0-9._-]*\.json",
    r"\.pem" + E,
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


def judged_text(payload):
    """What the secret patterns are matched against: the command without its commit messages."""
    text = subject(payload)
    if payload.get("tool_name") != "Bash" or "commit" not in text:
        return text
    try:
        return scrub_commit_messages(text)
    except Exception:   # ValueError, RecursionError...: cannot tell message from command, judge it whole (block is the safe side)
        return text


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        text = subject(payload)
        if payload.get("tool_name") == "Bash" and ENV_CHECK.match(text):
            return
        if text and SECRET_RE.search(judged_text(payload)):
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                     "permissionDecision": "deny",
                                                     "permissionDecisionReason": REASON}}))
    except Exception:
        pass  # fail open rather than block every call in the project


if __name__ == "__main__":
    main()
