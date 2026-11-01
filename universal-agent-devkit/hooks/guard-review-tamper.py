#!/usr/bin/env python3
"""PreToolUse(Edit|Write|MultiEdit|NotebookEdit|Bash|Read|Grep|Glob) guard: an agent may not write or delete what decides its own
review, nor read or drive the seal that makes a verdict count.

Audit 31/10/2026 (P0c): the 4-way review gate is only as strong as the files behind it. An agent could rewrite a run's
summary.json, its settings (the hook registrations), the hooks, the review scripts or the CI workflow and pass its own gate.
Denied for agent tool calls:
  .git/review-fanout/**         review runs, verdicts, override tokens and log
  .claude/settings*.json        hook registration / permissions
  hooks/** (any DevKit hooks dir and the dir itself: universal-agent-devkit/hooks, .agents/devkit/hooks, hooks/)
  bin/review*  (review-fanout.sh, review-merge.py, review_runner.py, review-full.py, review_sign.py)
  .github/workflows/**          CI
  ~/.config/agent-workbench/**  the summary seal key: not written, and (r14d, BUG-REV-592ad1528c / 738b4fa129) not READ either —
                                Read / Grep / Glob on it or on a folder above it, a Bash line naming it
Bash: write targets through hooks/shell_writes.py with heredoc / `bash -c` bodies scanned (run_bodies); paths resolved through
symlinks; a target or interpreter / sed -i operand holding a glob or brace is judged on its expansions (brace alternatives, a walk
of the folders, a pair like `.git/review-fanou?` that can name a head; too wide to walk: denied, b91e0de56a); a line it cannot
tokenise, an unparsed body, or a relative write after `cd "$VAR"` is denied when the line points at the machinery (fail-closed,
r14d BUG-REV-c23bc3cb6d / 5f7bee1cb0). An interpreter given inline code (python -I -c, /usr/bin/python3 -c,
node --x -e, perl -w -e, bash <<EOF, …; options before -c/-e are skipped, BUG-REV-4a3ec3ef82) that names a protected path is denied
too (its writes cannot be read statically). git that rewrites the tree (28b85d96f4): checkout / restore / reset / rm / mv / clean /
stash with a protected operand, a folder holding the machinery or a glob, and apply / am of a patch file (named anywhere on the
line) whose headers edit a protected path, are denied; ref-driven merge / pull / cherry-pick / rebase / revert and a patch piped
from a producer the guard cannot read are residual. The signer is never driven by an agent (T0021 / T0022, fail closed): a Bash
line that names review_sign / load_key / review-fanout-summary-v1 (any case, after quote removal), holds a word that spells
r…e…v…i…e…w…s…i…g…n through shell syntax (`${u:-…/review_sig?.py}`, `review_{s,x=y}ign.py`, `+(r)eview_sign.py`), or a glob /
brace that expands to the signer from cwd or a folder the line names, is denied unless the whole line is `python3 [-I]
…/review_sign.py verify <file>` or ONE plain read (cat / head / tail / wc / ls / stat / file / shasum / sha256sum / md5 / grep,
`sed -n <lines>p`) with no ; & | ` $( ${ < > # or newline; a command whose name is computed ("$f", {} of find -exec, $( )) on a
line that says `sign` or points at the machinery is denied too, and so is a Write/Edit of a non-document file whose text names
review_sign, load_key or the key path. T0023, a second signal: a line carrying the `sign` subcommand (any case, through quotes,
braces, ${…}, or a glob token like `s?gn`) that also holds glob / brace / $ / backtick / extglob / {} syntax, an interpreter, an
xargs / parallel runner, a computed command or a word naming the signer is denied. Accepted false positives: any other line naming
the signer (`git diff` / `git log` of it, a commit message, `git add` of it), any word with shell syntax that spells review…sign,
and a glob / computed / interpreter line that also has the word sign (`ls s*`, `git commit -m "sign $X"`, `python3 test_sign.py`).
Paths, the key / signer names, interpreter and file-command names and glob components match case-folded (APFS runs
`CP x .GIT/REVIEW-FANOUT/…`; nocaseglob); the folded line only adds to the line parsed as written. A write target computed by
$VAR / $( ) / backtick is denied on a line that points at the machinery.
Residual (same uid, no privilege separation): a script that hides those names (string building, encoding) is not seen, nor a
computed write target on a line with no machinery hint (`cp x "$P"`, P set by an earlier call), nor a file a planted
`…/bin/review_sign.py verify <new path>` creates; the code_hash binding of the seal
(bin/review_sign.py) and the write ban on .git/review-fanout keep a forged verdict out of the run dir.
Reading the code stays allowed. DEVKIT_ALLOW_GATE_EDIT=1 in the hook process environment (the operator's shell / launchd, never a
prefix on the command: the agent cannot set it for its own hooks) turns the guard off for a maintenance session.
Its own errors never block (it reports them on stderr); a shell_writes failure denies a line that names the machinery.
"""
import codecs
import glob
import json
import os
import re
import shlex
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

PROTECTED = re.compile(
    r"(?:^|/)\.git/review-fanout(?:/|$)"
    r"|(?:^|/)\.claude/settings[^/]*\.json$"
    r"|(?:^|/)hooks(?:/|$)"
    r"|(?:^|/)bin/review[^/]*$"
    r"|(?:^|/)\.github/workflows(?:/|$)"
    r"|(?:^|/)\.config/agent-workbench(?:/|$)", re.I)   # APFS opens .GIT/REVIEW-FANOUT as .git/review-fanout
SECRET_DIR = os.path.join("~", ".config", "agent-workbench")
_INTERP = r"(?:[\w.~/-]*/)?(?i:python[\d.]*|node|deno|bun|ruby|perl|php)"   # APFS runs PYTHON3 too
_SHELL = r"(?:[\w.~/-]*/)?(?i:bash|sh|zsh|dash|ksh)"
_OPT = r"(?:\s+-{1,2}[A-Za-z][\w.=-]*(?:\s+(?![-<])[^\s;&|<>]+)??)*?"
INLINE = re.compile(r"(?:^|[\s;&|(`])(?:" + _INTERP + _OPT + r"\s+(?:-[A-Za-z]*[cer][A-Za-z]*\b|-(?=\s|$)|<<|<\s*\S)"
                    r"|" + _SHELL + _OPT + r"\s+(?:-[A-Za-z]*c[A-Za-z]*\b|-s\b|-(?=\s|$)|<<|<\s*\S))")
PATH_WORD = re.compile(r"[\w.~/-]*(?:\.git/review-fanout|\.claude/settings[\w.-]*\.json|hooks(?:/[\w.-]+)?|bin/review[\w.-]*"
                       r"|\.github/workflows|\.config/agent-workbench)[\w./-]*", re.I)
# a computed cd target or a relative write that points at the machinery (used only after `cd "$VAR"` / an unparsed line / a
# computed write target)
MACHINERY_HINT = re.compile(r"review-fanout|git-(?:common-)?dir|\.git\b|\.claude|\bhooks\b|workflows|\.config|summary\.json|settings[^/\s]*\.json", re.I)
KEY_WORD = re.compile(r"\.config/agent-workbench|review\.key", re.I)
SIGNER_WORD = re.compile(r"\breview_sign\b|\bload_key\b|review-fanout-summary-v1", re.I)
# lệnh bộ ký duy nhất agent được chạy (ac772c846b): CẢ dòng là `python3 [-I] [<path>/]review_sign.py verify <file>` — không nối
# lệnh, thế lệnh, redirect, comment, dòng thứ hai hay code inline đi kèm (search không neo cho lọt `-c '…load_key…' # …`)
VERIFY_ONLY = re.compile(r"[ \t]*(?:[\w.~/-]*/)?python[\d.]*(?:[ \t]+-I)?[ \t]+(?:[\w.~/-]*/)?review_sign\.py[ \t]+verify"
                         r"[ \t]+[\w.~/@+=:-]+[ \t]*")
# git ghi lại cây làm việc (28b85d96f4): các lệnh này lấy nội dung từ ref / index / stash cho đúng đường dẫn chúng nhận;
# apply / am ghi đường dẫn trong bản vá. merge / pull / cherry-pick / rebase / revert / stash pop đi theo ref, không theo đường
# dẫn: phần dư (cùng lớp với script cất tên đi), như ghi chú Residual ở trên.
GIT_PATH_WRITE = {"checkout", "restore", "reset", "rm", "mv", "clean", "stash"}
GIT_PATCH = {"apply", "am"}
PATCH_NO_WRITE = {"--check", "--stat", "--numstat", "--summary", "--abort", "--quit", "--show-current-patch"}
PATCH_HEAD = re.compile(r"^(?:diff --git |--- |\+\+\+ |rename (?:from|to) |copy (?:from|to) )(.+)$", re.M)
C_QUOTED = re.compile(r'"((?:[^"\\]|\\.)*)"')
# một thư mục chứa máy review: `git checkout REF -- .` hay `-- universal-agent-devkit` ghi lại cả hooks/ bên trong nó
MACHINERY_UNDER = (".claude/settings*.json", ".github/workflows", ".git/review-fanout", "hooks", "*/hooks", "*/*/hooks",
                   "bin/review*", "*/bin/review*")
DOC_EXT = (".md", ".rst", ".txt", ".adoc")
# b91e0de56a: a write target / operand holding a glob or brace is judged on what the shell can make of it, not on its text
GLOB = re.compile(r"[*?\[{]")
SEQ = re.compile(r"(-?\d+)\.\.(-?\d+)(?:\.\.-?\d+)?|([A-Za-z])\.\.([A-Za-z])(?:\.\.-?\d+)?")
# (parent, child names) of the machinery: a pattern pair that can name one counts even before the folder exists (review-fanout.sh
# earlier on the same line makes the run dir)
HEADS = ((".git", ("review-fanout",)), (".claude", ("settings.json", "settings.local.json")), (".github", ("workflows",)),
         (".config", ("agent-workbench",)))
SIGNER_NAMES = ("review_sign.py", "review_sign")
SIGNER_LETTERS = "reviewsign"
# command names APFS runs in any case (`CP`, `TEE`, `GIT`, `PYTHON3`): folded before shell_writes / the git scan read the line
VERBS = re.compile(r"(?<![\w.-])(?i:cp|mv|rm|tee|install|rsync|ln|scp|touch|truncate|mkdir|rmdir|chmod|unlink|dd|sed|perl|ruby|"
                   r"python[\d.]*|node|deno|bun|php|bash|sh|zsh|dash|ksh|git|cd|pushd|popd|env|sudo|nohup|nice|timeout|exec|"
                   r"command|builtin|time)(?![\w.-])")
DIR_READS = 2000   # folder listings one glob may cost; past it (or 5000 paths) the glob is too wide to judge: denied
REASON = ("Blocked by guard-review-tamper: agents may not write or delete the review machinery ({}). The 4-way review gate "
          "decides on these files; change them through a reviewed PR by the operator (DEVKIT_ALLOW_GATE_EDIT=1 in the hook "
          "environment for a maintenance session).")
SEAL_REASON = ("Blocked by guard-review-tamper: the review seal ({}) is neither read nor driven by an agent — a verdict counts "
               "only when review-fanout.sh signs it. Run the review with review-fanout.sh; check a seal with "
               "`review-fanout.sh --verify-summary <summary.json>`.")


def _real(p):
    """realpath of the deepest existing ancestor + the rest: a write through a symlink lands where the link points."""
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


def _norm(p, cwd):
    p = os.path.expanduser(str(p))
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)


def protected(p, cwd):
    if not p:
        return False
    n = _norm(p, cwd)
    return bool(PROTECTED.search(n) or PROTECTED.search(_real(n)))


def _braces(w, cap=256):
    """Brace expansion of w as bash / zsh do it ({a,b} lists, {1..3} / {a..c} sequences, innermost first; ${…} and a brace with
    neither stay literal), or None past cap words."""
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


def _match(pat, name):
    """True when glob component pat can match file name name, read loosely enough to cover bash and zsh: * and ? stay in one
    component, any [...] is one character, case-folded (nocaseglob / NO_CASE_GLOB, APFS), and only a pattern starting with .
    or [ reaches a dot name."""
    pat, name = pat.lower(), name.lower()
    if name.startswith(".") and not pat.startswith((".", "[")):
        return False
    rx, i = "", 0
    while i < len(pat):
        j = _bracket_end(pat, i) if pat[i] == "[" else None
        rx += "[^/]*" if pat[i] == "*" else "[^/]" if pat[i] == "?" or j else re.escape(pat[i])
        i = (j or i) + 1
    return re.fullmatch(rx, name, re.S) is not None


def _lead(w, here):
    """w with a leading $HOME / ${HOME} / $PWD / ${PWD} / ~+ replaced as the shell does (~ and ~user: _norm)."""
    m = re.match(r"(?:\$\{(HOME|PWD)\}|\$(HOME|PWD)|~(\+))(?=/|$)", w)
    if not m:
        return w
    return (os.path.expanduser("~") if (m.group(1) or m.group(2)) == "HOME" else here) + w[m.end():]


def _walk(path, reads):
    """Paths the absolute glob path can name: a glob component against the folder's entries, ** as any run of folders (zsh,
    bash globstar; dot folders skipped as they do), a literal component kept whether or not it exists (the write may create it).
    None once reads (a one-item list of folder listings left) runs out or the paths pass 5000."""
    cur = ["/"]
    for comp in path.split("/")[1:]:
        if not comp or not GLOB.search(comp):
            cur = [os.path.join(d, comp) for d in cur] if comp else cur
            continue
        nxt = []
        for d in cur:
            stack = [d]
            while stack:
                x = stack.pop()
                if reads[0] <= 0:
                    return None
                reads[0] -= 1
                try:
                    with os.scandir(x) as it:
                        ents = list(it)
                except OSError:
                    continue
                if comp == "**":
                    nxt.append(x)
                    stack += [e.path for e in ents if not e.name.startswith(".") and e.is_dir()]
                else:
                    nxt += [e.path for e in ents if _match(comp, e.name)]
        cur = nxt
        if len(cur) > 5000:
            return None
    return cur


def _glob_paths(word, here):
    """What the shell can make of a word holding a glob or brace: its brace alternatives plus, for each one with a glob, the paths
    the walk names; None when too wide to judge."""
    alts = _braces(word)
    if alts is None:
        return None
    out, reads = list(alts), [DIR_READS]
    for a in alts:
        if GLOB.search(a):
            got = _walk(_norm(_lead(a, here), here), reads)
            if got is None:
                return None
            out += got
    return out


def _glob_hit(paths, here):
    """True when one of a glob word's paths (_glob_paths; None: too wide) is protected, or a (parent, child) pair of its
    components can name a head of HEADS (`.git/review-fanou?`, `.claude/setting*.json`, `.gi?/review-fanout`)."""
    if paths is None:
        return True
    for p in paths:
        c = _norm(_lead(p, here), here).lower().split("/")
        if protected(p, here) or any(_match(c[i - 1], pp) and any(_match(c[i], n) for n in names)
                                     for i in range(1, len(c)) for pp, names in HEADS):
            return True
    return False


def _names_signer(w, cwd):
    """True when shell word w can be the signer file: named (any case), or a glob / brace whose alternative names it, whose
    pattern with a literal character besides `.py` can match it, or whose walk finds it (a bare `*.py` / `*` is judged by the
    walk only: `python3 -m pytest tests/*.py`)."""
    if SIGNER_WORD.search(w):
        return True
    if not GLOB.search(w):
        return False
    paths = _glob_paths(w, cwd)
    for a in paths if paths is not None else [w]:
        b = a.rstrip("/").rsplit("/", 1)[-1].lower()
        if SIGNER_WORD.search(a) or (re.sub(r"[*?\[\]!^]", "", re.sub(r"\.py$", "", b)) and
                                     any(_match(b, n) for n in SIGNER_NAMES)):
            return True
    return False


def _spells_signer(word):
    """T0022: a word holding shell syntax (* ? [ ] { } $ ( ) @ + ! , = : ~ ` \\ ' ") that still spells r…e…v…i…e…w…s…i…g…n in
    order once that syntax is deleted, case-insensitive, a ? or a [...] standing for one letter (`${u:-…/review_sig?.py}`,
    `review_{s,x=y}ign.py`, `+(r)eview_sign.py`, `review_sig[n].py`); `review/*.md` does not."""
    if not re.search(r"[*?\[\]{}$()@+!,=:~`\\'\"]", word):
        return False
    w, k, i = word.lower(), 0, 0
    while i < len(w) and k < len(SIGNER_LETTERS):
        j = _bracket_end(w, i) if w[i] == "[" else None
        k += w[i] == "?" or bool(j) or w[i] == SIGNER_LETTERS[k]
        i = (j or i) + 1
    return k == len(SIGNER_LETTERS)


def _signer_named(cmd, cwd):
    """The first word of the line that names the signer or can expand to it, or None: SIGNER_WORD (as written, or after the
    shell's quote removal: `review_s"ign"`), a word that spells it through shell syntax (_spells_signer), or a glob / brace
    (_names_signer) walked from cwd and from every folder the line names (`find bin -name '*.py' -exec {} …`,
    `cd bin && for f in ???????????.py`)."""
    plain = re.sub(r"[\"'\\]", "", cmd)
    m = SIGNER_WORD.search(cmd) or SIGNER_WORD.search(plain)
    if m:
        return m.group(0)
    hit = next((w for w in re.split(r"[\s;&|<>]+", cmd) if _spells_signer(w)), None)
    if hit:
        return hit
    words = [w for w in re.split(r"[\s;&|()<>=`]+", plain) if w]
    dirs = [cwd] + [d for d in dict.fromkeys(_norm(w, cwd) for w in words if not GLOB.search(w)) if os.path.isdir(d)][:8]
    return next((w for w in words if GLOB.search(w) and any(_names_signer(w, d) for d in dirs)), None)


# a command whose name is computed ($f, "./$f", {} of find -exec, $( ), a backtick): what it runs cannot be named, so a line that
# says `sign` or points at the machinery is denied with it (fail closed: `ls bin | while read f; do "bin/$f" sign …; done`)
COMPUTED_RUN = re.compile(r"(?:^|[;&|(\n`{]|(?<![\w-])(?:do|then|else|exec|nohup|time|command|builtin|env|xargs|sudo|nice|-exec|"
                          r"-execdir|-ok|-okdir)(?![\w-]))[ \t]*[^\s;&|=]*(?:\$|\{\}|`)")

# T0021 / T0022: a line that names the signer runs only as VERIFY_ONLY or as ONE plain read of it — any other line naming it is
# denied (fail closed). No git / rg / less / more: each has a pager / exec / textconv option family (`git grep -nO<pager>`).
SIGNER_READS = {"cat", "head", "tail", "wc", "ls", "stat", "file", "shasum", "sha256sum", "md5", "grep", "egrep", "fgrep", "sed"}
NOT_PLAIN = re.compile(r"[;&|`<>#\n]|\$[({]")   # an operator, substitution, redirection, comment or second line anywhere
SAFE_SED = re.compile(r"(?:\d+|\$)(?:,(?:\d+|\$))?p|/[^/]*/p")   # nothing after the closing / but p: no w / W / e / r command

# T0023: every CLI signing needs the literal subcommand `sign` (review_sign.py signs only when argv[1] == "sign"). A line that
# carries it (_carries_sign) AND can reach the signer without naming it plainly — a glob / brace / $ / backtick / extglob / {}
# word, an interpreter, an xargs / parallel runner, a computed command or a word naming the signer — is denied (fail closed).
RUNS_INTERP = re.compile(r"(?:^|[\s;&|(`])" + _INTERP + r"(?=\s|$)")
REACH_SYNTAX = re.compile(r"[*?\[\]{}$`]|[@+!]\(|(?:^|[\s/;&|(])(?i:xargs|parallel)(?=\s|$)")


def _carries_sign(cmd):
    """True when, after quote / backslash removal and brace expansion, a word split on every non-alphanumeric char holds the
    token `sign` (any case: `${x:-sign}`, `"sign"`, `s''ign`, `s\\ign`, `{sign,x}`), or a glob token with a literal letter that
    can match it (`s?gn`, `s*`, `[s]ign`, `si*`)."""
    for w in re.sub(r"[\"'\\]", "", cmd).split():
        for a in _braces(w) or [w]:
            if any(t.lower() == "sign" for t in re.split(r"[^A-Za-z0-9]+", a)) or any(
                    re.search(r"[*?\[]", t) and re.search(r"[A-Za-z]", t) and _match(t, "sign")
                    for t in re.split(r"[^A-Za-z0-9*?\[\]!^]+", a)):
                return True
    return False


def _signer_read(cmd):
    """True when the whole line is one plain read: a SIGNER_READS command with plain words only (sed: only `sed -n <lines>p
    <files>` or `sed -n /re/p <files>`)."""
    if NOT_PLAIN.search(cmd):
        return False
    try:
        w = shlex.split(cmd)
    except ValueError:
        return False
    if not w or w[0] not in SIGNER_READS:
        return False
    return w[0] != "sed" or (len(w) > 3 and w[1] == "-n" and bool(SAFE_SED.fullmatch(w[2]))
                             and not any(a.startswith("-") for a in w[3:]))



def _secret_reach(p, cwd):
    """True when a read of p (a file, or a folder searched recursively) reaches the seal key's folder."""
    if not p:
        return False
    secret = _real(os.path.normpath(os.path.expanduser(SECRET_DIR))).lower()   # case-folded: APFS
    for n in {_norm(p, cwd), _real(_norm(p, cwd))}:
        n = n.rstrip("/").lower() or "/"
        if n == secret or n.startswith(secret + "/") or secret.startswith(n.rstrip("/") + "/") or KEY_WORD.search(n):
            return True
    return False


def _git_calls(cmd):
    """Trả về ([(subcommand, từ phía sau)] của mọi lệnh git trên dòng, mọi từ trên dòng) — đã bỏ dấu nháy qua shlex;
    dòng shlex không tách được trả ([], []) (shell_writes sẽ trả None và nhánh gọi fail-closed)."""
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|<>()\n")
        lex.whitespace, lex.whitespace_split, lex.commenters = " \t\r", True, ""
        toks = list(lex)
    except ValueError:
        return [], []
    calls, seg = [], []
    for t in toks + [";"]:
        if not (t and set(t) <= set(";&|()\n")):
            seg.append(t)
            continue
        k = next((i for i, w in enumerate(seg) if os.path.basename(w) == "git"), None)
        skip = None
        for i, a in enumerate(seg[k + 1:] if k is not None else [], (k or 0) + 1):
            if skip:
                skip = None
            elif a in ("-C", "-c", "--git-dir", "--work-tree"):
                skip = a
            elif not a.startswith("-"):
                calls.append((a, seg[i + 1:]))
                break
        seg = []
    return calls, [t for t in toks if not set(t) <= set(";&|()<>\n")]


def _git_operand_hit(a, dirs):
    """Toán hạng checkout/restore/reset/rm/mv/clean/stash chạm máy review: đường dẫn được bảo vệ, thư mục chứa máy review,
    hoặc glob / pathspec magic không khai triển tĩnh được (fail-closed)."""
    if re.search(r"[*?\[]", a) or a.startswith(":"):
        return True
    for d in dirs:
        if protected(a, d):
            return True
        n = _real(_norm(a, d))
        if os.path.isdir(n) and any(glob.glob(os.path.join(glob.escape(n), m)) for m in MACHINERY_UNDER):
            return True
    return False


def _patch_paths(value):
    """Các đường dẫn trong một dòng header patch: giải mã C-quoted (core.quotePath, INSTINCT-089) và bỏ tiền tố a/ b/."""
    out = []
    for q in C_QUOTED.findall(value):
        try:
            out.append(codecs.escape_decode(q.encode("utf-8"))[0].decode("utf-8", "replace"))
        except ValueError:
            out.append(q)
    out += C_QUOTED.sub(" ", value).split()
    return [re.sub(r"^[ab]/", "", p) for p in out]


def _patch_hits(words, dirs):
    """Đường dẫn được bảo vệ bị sửa bởi file patch nêu bất kỳ đâu trên dòng (toán hạng, `< f`, `cat f |`, nguồn của cp)."""
    hits = []
    for w in dict.fromkeys(words):
        for d in dirs:
            p = _real(_norm(w, d))
            try:
                if not os.path.isfile(p) or os.path.getsize(p) > (8 << 20):
                    continue
                with open(p, "rb") as f:
                    text = f.read().decode("utf-8", "replace")
            except OSError:
                continue
            hits += [t for m in PATCH_HEAD.finditer(text) for t in _patch_paths(m.group(1)) if PROTECTED.search(t)]
            break
    return hits


def bash_hits(cmd, cwd):
    hits = []
    named = [w for w in PATH_WORD.findall(cmd) if protected(w, cwd)]
    if KEY_WORD.search(cmd):
        return ["seal:" + KEY_WORD.search(cmd).group(0)]
    sig = _signer_named(cmd, cwd)
    if sig and not VERIFY_ONLY.fullmatch(cmd) and not _signer_read(cmd):
        return ["seal:" + sig]
    plain = re.sub(r"[\"'\\]", "", cmd)
    if not VERIFY_ONLY.fullmatch(cmd) and not _signer_read(cmd) and _carries_sign(cmd) and (
            sig or REACH_SYNTAX.search(plain) or RUNS_INTERP.search(re.sub(r"[\"'\\`]", " ", cmd)) or COMPUTED_RUN.search(plain)):
        return ["seal:the `sign` subcommand on a line that can reach the signer"]
    if COMPUTED_RUN.search(re.sub(r"[\"'\\]", "", cmd)):
        if re.search(r"(?<![\w.-])sign(?![\w.-])", cmd):
            return ["seal:a computed command that signs"]
        if MACHINERY_HINT.search(cmd):
            hits.append("a computed command on a line that points at the machinery")
    try:
        import shell_writes
        literal = shell_writes._literal_exists = getattr(shell_writes, "_literal_exists", shell_writes._exists)

        def glob_exists(a, here):
            """shell_writes reports an interpreter's / sed -i's operand only when it exists literally (b91e0de56a): a glob
            operand exists when one of its expansions does (or it is too wide to judge), and a protected path counts before
            it exists (`python3 w.py .git/review-fanout/H/new`; a bare word like `hooks` stays an argument; a VERIFY_ONLY line
            keeps the literal rule: its summary is judged only once it exists)."""
            if literal(a, here) or ("/" in a and protected(a, here) and not VERIFY_ONLY.fullmatch(cmd)):
                return True
            ps = _glob_paths(a, here) if GLOB.search(a) else []
            return ps is None or any(os.path.lexists(_norm(_lead(p, here), here)) for p in ps)
        shell_writes._exists = glob_exists   # this hook process only
        # the line is parsed as written; its case-folded copy (APFS runs `CP`, `TEE`, `GIT`) can only add targets — parsed alone it
        # would also fold a heredoc delimiter or body line and move where a body ends (audit of c42aef31)
        folded = VERBS.sub(lambda m: m.group(0).lower(), cmd)
        parses = [shell_writes.targets(cmd, cwd, run_bodies=True)]
        if folded != cmd:
            parses.append(shell_writes.targets(folded, cwd, run_bodies=True))
        if any(p is None for p in parses):   # bash vẫn chạy dòng shlex không tách được ($'..', nháy lẻ): fail-closed khi chạm máy review
            hits += named or ([cmd.strip()[:60]] if MACHINERY_HINT.search(cmd) else [])
        got = [t for p in parses if p for t in p]
        for part in parses:
            cd_unknown = ""
            for kind, target, here in part or []:
                if kind == "cdvar":   # `cd "$VAR"`: đích tương đối phía sau không đọc tĩnh được thư mục gốc
                    cd_unknown = str(target)
                    continue
                if kind == "unparsed":
                    hits += named or ([cmd.strip()[:60]] if MACHINERY_HINT.search(cmd) else [])
                    continue
                if kind in ("redirect", "file", "interp") and target:
                    # b91e0de56a: a glob / brace target is judged on its expansions; a zsh group or qualifier right after it
                    # (`.git/(review-fanout|x)/…`, `f(N)`) cannot be read: fail closed when the line points at the machinery
                    globbed = GLOB.search(str(target)) is not None
                    paths = _glob_paths(str(target), here or cwd) if globbed else [target]
                    if protected(target, here or cwd) or (globbed and _glob_hit(paths, here or cwd)) or \
                            (re.search(r"(?:^|[\s<>|&;(])" + re.escape(str(target)) + r"\(", cmd) and MACHINERY_HINT.search(cmd)):
                        hits.append(target)
                    elif kind == "file" and re.search(r"\b(?:cp|mv|rsync|scp|ln|rm|rmdir)\b", folded) and \
                            any(re.search(r"(?i)(?:^|/)\.(?:git|claude|github)/*$", str(p)) for p in paths or []):
                        # Chặn chép đè hoặc xoá thư mục cha chứa máy review (8ec050fad4: cp -R /tmp/review-fanout <common>/.git/)
                        hits.append(target)
                    elif kind != "interp" and re.search(r"\$\(|`|^\$", _lead(str(target), here or cwd)) and \
                            MACHINERY_HINT.search(cmd):
                        hits.append(target)   # a computed target ($(…), `…`, $VAR) on a line that points at the machinery
                    elif cd_unknown and not os.path.isabs(os.path.expanduser(str(target))) and \
                            (MACHINERY_HINT.search(cd_unknown) or MACHINERY_HINT.search(str(target))):
                        hits.append(f"{cd_unknown}/{target}")
        # 28b85d96f4: ("git", dir) của shell_writes không còn bị bỏ qua — đường dẫn tương đối tính theo cwd và thư mục của
        # từng lệnh git (sau cd / -C)
        dirs = [cwd] + [str(t) for kind, t, _ in got if kind == "git" and t]
        calls, words = _git_calls(cmd)
        if folded != cmd:
            more = _git_calls(folded)
            calls, words = calls + more[0], words + more[1]
        for sub, rest in calls:
            ops = [a for a in rest if not a.startswith("-") and a not in ("<", ">")]
            if sub == "stash" and ops[:1] in (["list"], ["show"], ["create"]):
                continue
            if sub in GIT_PATH_WRITE:
                hits += named + [a for a in (ops or (["."] if sub == "clean" else [])) if _git_operand_hit(a, dirs)]
            elif sub in GIT_PATCH and ("--apply" in rest or not PATCH_NO_WRITE & set(rest)):
                hits += named + _patch_hits(words, dirs)
    except Exception as e:   # noqa: BLE001 — fail closed on a line that names the machinery
        sys.stderr.write(f"guard-review-tamper: shell_writes unavailable ({e.__class__.__name__}) — textual check only\n")
        hits += named
    if INLINE.search(cmd):
        hits += named
    return hits


def _content(tool, ti):
    if tool == "Write":
        return str(ti.get("content") or "")
    if tool == "Edit":
        return str(ti.get("new_string") or "")
    if tool == "MultiEdit":
        return "\n".join(str(e.get("new_string") or "") for e in (ti.get("edits") or []) if isinstance(e, dict))
    if tool == "NotebookEdit":
        return str(ti.get("new_source") or "")
    return ""


def read_reason(tool, ti, cwd):
    """Lý do chặn khi Read/Grep/Glob/NotebookRead chạm tới thư mục khoá ký, ngược lại trả None (ae4413f24a): hỗ trợ khoá
    camelCase, Grep/Glob bỏ trống path thì xét cwd, và mẫu Glob được cắt tại ký tự đại diện đầu tiên (* ? [ {) sau khi ghép
    với thư mục gốc tìm kiếm. Hàm cùng logic cũng chạy ở guard-secrets.py cho Read|Grep trong .claude/settings.json (e8eb813d18)."""
    paths = [str(p) for p in (ti.get(k) for k in ("file_path", "filePath", "path", "notebook_path", "notebookPath")) if p]
    if tool in ("Grep", "Glob") and not ti.get("path"):
        paths.append(cwd)
    for p in paths:
        if _secret_reach(p, cwd):
            return SEAL_REASON.format(p)
    pat = str(ti.get("pattern") or "") if tool == "Glob" else ""
    if pat:
        full = _norm(pat, str(ti.get("path") or cwd))
        lit = re.split(r"[*?\[{]", full, maxsplit=1)[0]
        if lit != full and not lit.endswith("/"):
            lit = os.path.dirname(lit)
        if KEY_WORD.search(pat) or _secret_reach(lit or "/", cwd):
            return SEAL_REASON.format(pat)
    return None


def judge(payload):
    if not isinstance(payload, dict):
        return None
    tool = str(payload.get("tool_name") or payload.get("toolName") or "")
    ti = next((v for v in (payload.get(k) for k in ("tool_input", "toolInput", "input")) if isinstance(v, dict)), {})
    cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) and payload.get("cwd") else os.getcwd()
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        p = ti.get("file_path") or ti.get("filePath") or ti.get("notebook_path") or ti.get("path") or ""
        if protected(p, cwd):
            return REASON.format(p)
        text = _content(tool, ti)
        if not str(p).lower().endswith(DOC_EXT):
            m = KEY_WORD.search(text) or SIGNER_WORD.search(text)
            if m:
                return SEAL_REASON.format(m.group(0))
        return None
    if tool in ("Read", "Grep", "Glob", "NotebookRead"):
        return read_reason(tool, ti, cwd)
    if tool == "Bash":
        hits = bash_hits(str(ti.get("command") or ""), cwd)
        seal = [h[5:] for h in hits if h.startswith("seal:")]
        if seal:
            return SEAL_REASON.format(seal[0])
        return REASON.format(", ".join(sorted(set(hits))[:3])) if hits else None
    return None


def main():
    if os.environ.get("DEVKIT_ALLOW_GATE_EDIT") == "1":
        return
    try:
        reason = judge(json.loads(sys.stdin.read() or "{}"))
    except Exception as e:   # noqa: BLE001 — never block unrelated work on a guard error, but say so
        sys.stderr.write(f"guard-review-tamper: skipped ({e.__class__.__name__}: {str(e)[:160]})\n")
        return
    if reason:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                 "permissionDecisionReason": reason}}))


if __name__ == "__main__":
    main()
