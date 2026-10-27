"""Write targets of one shell command line - the scanner hooks/worktree_guard.sh had inline, shared with bin/session_lock.py.

issues-bugs.md A.1 #3 (13/10): session_lock judged only git writes, gate runs and `>` redirects, so `cp` / `mv` / `rm` / `tee` /
`sed -i` / `touch` into a checkout another session holds went through (11:03 that day). One scanner for both, not a second one.
targets() returns every candidate; each caller decides what counts (worktree_guard: anything in the main checkout; session_lock:
file writes into the held checkout). Standard library only.
"""
import os
import re
import shlex

# `<<WORD` (not the here-string `<<<`), WORD up to a metacharacter with `-` in it (OCR 26/10 r3: `<<END-X` read as END) - as bin/session_lock.py
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)([^\s;&|<>()'\"`\\]+)\1")
DEST_LAST = {"cp", "install", "rsync", "ln", "scp"}
ALL_ARGS = {"mv", "rm", "touch", "truncate", "tee", "mkdir", "rmdir", "chmod", "unlink"}
GIT_WRITE = {"add", "am", "apply", "checkout", "cherry-pick", "clean", "commit", "merge", "mv", "pull",
             "rebase", "reset", "restore", "revert", "rm", "stash", "switch"}
STASH_READ = {"list", "show", "create"}          # `git stash <these>` leaves the tree and refs alone
# Build tools write build dirs / caches into the directory they run in, by construction.
BUILDERS = re.compile(r"^(?:npm|npx|yarn|pnpm|bun|make|gradle|\./gradlew|gradlew|mvn|cargo|go|pytest|jest|"
                      r"vitest|dotnet|swift|flutter)$")
# Interpreters write only what their script says: judged by the operands after the script -
# unless the script is a build tool (`sh ./gradlew …`) or the module a builder / test runner
# / formatter (`python3 -m pytest`), which writes caches and build dirs where it runs.
INTERP = re.compile(r"^(?:python[\d.]*|node|deno|ruby|perl|php|bash|sh|zsh)$")
MODULE_BUILDERS = {"pytest", "unittest", "black", "ruff", "mypy", "pip", "build", "isort", "coverage",
                   "tox", "nox", "setuptools", "pylint"}
PREFIX = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "}", "time", "command",
          "builtin", "exec", "nohup", "sudo", "env", "done", "fi", "nice", "timeout"}
# A prefix's own options come before the command it runs (`env -i rm`, `nice -n 5 rm`, `sudo -n rm`, `timeout 5 rm`); these take a value.
PREFIX_VALUE_OPTS = {"nice": {"-n"}, "env": {"-u", "-C", "-S", "--chdir", "--unset", "--split-string"},
                     "timeout": {"-s", "-k", "--signal", "--kill-after"},
                     "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "--chdir"}}
# ... and these move the directory the command runs in (OpenCodeReview 14/10: `env -C <main> rm f` judged f in the old cwd)
PREFIX_CHDIR = {("env", "-C"), ("env", "--chdir"), ("sudo", "-D"), ("sudo", "--chdir")}
ENV_SPLIT_SHORT = re.compile(r"-[0iv]*S(.*)", re.S)   # env -S, also after its flags (-iS); the rest of the word is the value
ENV_CTRL = {"f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v"}   # env -S's own control-character escapes
# Options whose next word is a VALUE, not a target (principal-code-reviewer 14/10: `chmod +x f`, `mkdir -m 755 d`, `touch -t STAMP f`,
# `truncate -s 0 f`, `touch -r REF f` named the value as a write in the cwd). `--opt=value` carries its value itself.
VALUE_OPTS = {"chmod": {"--reference"}, "cp": {"-S", "--suffix"}, "mv": {"-S", "--suffix"}, "ln": {"-S", "--suffix"},
              "install": {"-m", "-o", "-g", "-S", "--mode", "--owner", "--group", "--suffix"}, "mkdir": {"-m", "--mode"},
              "touch": {"-t", "-d", "-r", "--date", "--reference"}, "truncate": {"-s", "-r", "--size", "--reference"},
              "rsync": {"-e", "--rsh", "-f", "--filter", "--exclude", "--include"}, "scp": {"-i", "-P", "-o", "-F", "-c", "-l", "-J"}}
TARGET_DIR = {"cp", "mv", "install", "ln"}   # `-t DIR` / `--target-directory=DIR`: every source goes into DIR
# A chmod mode may start with `-` (`chmod -w f`, `chmod -x,u+r f`): the first such word is the mode, not an option (OpenCodeReview 14/10)
CHMOD_MODE = re.compile(r"[0-7]{1,4}|[ugoa]*(?:[-+=][rwxXstugo]*)+(?:,[ugoa]*(?:[-+=][rwxXstugo]*)+)*")
# A heredoc a shell reads is command lines (scanned like `bash -c '…'`); one an interpreter reads is a script: what it hands a file-writing call
# as a LITERAL path (python open(p, 'w') / Path(p).write_text, node writeFile / appendFile / createWriteStream, php file_put_contents,
# ruby File.write). ponytail: a computed path (os.path.join, an f-string, argv) is not seen; upgrade by running the script under a scanner.
SHELLS = {"bash", "sh", "zsh"}
_LIT = r"""\(\s*[rbRB]{0,2}(?P<q>['"])(?P<p>[^'"\n]+)(?P=q)"""
_MODE = r"""(?:mode\s*=\s*)?[rbRB]{0,2}['"][rbtU]*[wax+]"""   # a write mode: w / a / x, or a `+` (r+, rb+); r / rb alone read
SCRIPT_WRITES = (
    re.compile(r"\bopen" + _LIT + r"""\s*,\s*(?:\w+\s*=\s*[^,()]+,\s*)*""" + _MODE),   # (keyword arguments may come before mode=)
    re.compile(r"\bPath" + _LIT + r"""\s*\)\s*\.\s*open\s*\(\s*""" + _MODE),
    re.compile(r"\bPath" + _LIT + r"""\s*\)\s*\.\s*(?:write_text|write_bytes)\b"""),
    re.compile(r"\b(?:writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|file_put_contents)" + _LIT),
    re.compile(r"\bFile\s*\.\s*(?:write|binwrite)" + _LIT),
)


def strip_comments(text):
    """`text` without its shell comments: a `#` that starts a word (after whitespace, `;`, `&`, `|`, `(` or at a line start), outside quotes, runs
    to the end of its line. A quote inside a comment (`# don't`) is no quote: shlex read it as one and swallowed every line after it, so the
    writes below it went unseen (INSTINCT-031). Quote- and backslash-aware over the whole text; `$#` and `${#x}` are no comments."""
    out, quote, i, n = [], None, 0, len(text)
    while i < n:
        c = text[i]
        if quote:
            out.append(c)
            if c == "\\" and quote == '"' and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
        elif c == "\\" and i + 1 < n:
            out.append(text[i:i + 2])
            i += 2
            continue
        elif c in "\"'":
            quote = c
            out.append(c)
        elif c == "#" and (i == 0 or text[i - 1] in " \t\n;&|("):
            while i < n and text[i] != "\n":
                i += 1
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


# Số fd dính liền phép chuyển hướng: MỘT chữ số (zsh đọc `10>x` là đối số `10` rồi `>x`; bash đọc là fd 10 - giữ như cũ, xem _drop_fd_numbers)
_FD_NUM = re.compile(r"[0-9](?=[<>])")


def _drop_fd_numbers(text):
    """`text` bỏ số fd dính liền phép chuyển hướng (`2>/dev/null`, `2>>e`, `2>&1`, `1>log`, `0<f`): shell đọc một chữ số không nháy, đứng
    đầu từ và liền trước `<` / `>`, là số của fd được chuyển, không bao giờ là đối số. shlex tách `2>` thành `2` và `>` nên `2` từng được
    đọc là toán hạng cuối = đích của cp / ln / install / rsync / scp (#427 vòng 3: `cp x <checkout bị giữ>/f 2>/dev/null` lọt session_lock
    và worktree_guard), một toán hạng của rm / touch / tee …, thư mục của `cd 2>/dev/null`, hay chính động từ (`2>/dev/null cp …`). Phép
    chuyển hướng và đích của nó giữ nguyên (`2>/tmp/log` vẫn là redirect /tmp/log). Còn là đối số (đo trên bash và zsh 27/10): `2 >f`
    (có cách), `'2'>f`, `\\2>f`, `a\\ 2>f`, `a2>f`, `2&>f`; `>&2>f` (`2` là đích của `>&`). ponytail: `10>f` (fd nhiều chữ số của bash)
    vẫn đọc `10` là đối số như zsh - corpus 27/10 không có lệnh thật nào như thế; nâng lên khi gặp."""
    out, quote, start, i, n = [], None, True, 0, len(text)
    while i < n:
        c = text[i]
        if quote:
            if c == "\\" and quote == '"' and i + 1 < n:
                out.append(text[i:i + 2])
                i += 2
                continue
            if c == quote:
                quote = None
        elif c == "\\":
            out.append(text[i:i + 2])
            i, start = i + 2, False
            continue
        elif c in "\"'":
            quote = c
        elif start and _FD_NUM.match(text, i):   # thành dấu cách, không xoá: `;2>x` / `(2>x` / `&2>x` xoá đi thì shlex gộp `;>` `(>` `&>` làm một
            out.append(" ")
            i, start = i + 1, False
            continue
        # đầu từ: sau khoảng trắng / ; | ( / & (trừ `&` của `>&` `<&`) ngoài nháy - shlex cũng tách từ ở đó
        start = not quote and (c in " \t\r\n;|(" or (c == "&" and text[i - 1:i] not in ("<", ">")))
        out.append(c)
        i += 1
    return "".join(out)


_OPS = set(";&|<>()\n")   # ký tự toán tử của shlex trong targets(): một token chỉ gồm chúng là toán tử - hoặc chữ trong nháy (_scoped)


def _bare_parens(text):
    """Số `(` và `)` của `text` không nằm trong nháy và không bị thoát, theo luật nháy của shlex posix (như strip_comments); None khi luật
    nháy của shlex khác shell ở dòng này: `$'…'` (ANSI-C: `\\'` là nháy được thoát), hay nháy kép đóng khi `$(` / `${` / backtick mở trong
    nó chưa đóng (`"$(echo ")(") x"`: shell đọc nháy lồng, shlex đọc `)(` là toán tử trần)."""
    n, quote, sub, tick, i = 0, None, 0, False, 0
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 2
                continue
            if quote == '"' and (c == "`" or (c == "$" and text[i + 1:i + 2] in ("(", "{")) or (sub and c in "()}")):
                tick = not tick if c == "`" else tick
                sub += 1 if c in "$(" else (-1 if c in ")}" else 0)
                i += 2 if c == "$" else 1
                continue
            if c == quote:
                if sub > 0 or tick:
                    return None
                quote = None
        elif c == "\\":
            i += 2
            continue
        elif c == "$" and text[i + 1:i + 2] == "'":
            return None
        elif c in "\"'":
            quote, sub, tick = c, 0, False
        elif c in "()":
            n += 1
        i += 1
    return n


def _scoped(text, toks):
    """True khi mọi `)` của dòng (`toks`: shlex của `text`) đóng đúng `(` của nó như shell, để targets() đưa thư mục về như trước `(`
    (#427 vòng 3: `(cd ../<anh em> && ls); echo x > out.txt` từng tính out.txt ở anh em). Điều kiện: số `(` và `)` trong token toán tử bằng
    nhau (mẫu `a)` của `case` không có `(`: dòng hợp lệ nào có nó cũng thừa `)`), và tổng của chúng bằng số ngoặc trần của `text` (một chữ
    trong nháy / bị thoát chỉ gồm ngoặc - `")"`, `\\)` - shlex trả như toán tử: `echo ")" "("` cân mà vẫn đóng sai tầng; _bare_parens None:
    `$'…'`, nháy lồng trong `"$( … )"` - shlex đọc nháy khác shell). Không thì thư mục không quay về (như trước): fail closed (INSTINCT-045)."""
    ops = "".join(t for t in toks if t and set(t) <= _OPS)
    return ops.count("(") == ops.count(")") and ops.count("(") + ops.count(")") == _bare_parens(text)


def _home(p):
    """os.path.expanduser(p); `p` nguyên khi nó có NUL (`~a<NUL>b`: getpwnam văng ValueError - review #427 vòng 3: targets() văng thì
    _write_scan của bin/session_lock.py trả None, luật ghi file tắt cho cả dòng). Không file nào có NUL."""
    try:
        return os.path.expanduser(p)
    except ValueError:
        return p


def _cd(here, d):
    """The directory `d` names from `here`; a $VAR / backtick one is unknown: `here` stays (as for cd). NUL: như $VAR (#427 vòng 3)."""
    if "$" in d or "`" in d or "\0" in d:
        return here
    d = os.path.expanduser(d)
    return d if os.path.isabs(d) else os.path.join(here, d)


def _env_split(opt, words):
    """(command line, words left) when `opt` is env's split-string option - `-S LINE`, `-SLINE`, `-iS LINE`, `--split-string LINE`,
    `--split-string=LINE` or an unambiguous prefix of it (`--s…`) - else None. env splits LINE into words and runs them with the
    words after it appended, so LINE is a command, not an option value (OpenCodeReview 14/10: `env -S 'rm f'` was never judged)."""
    m = ENV_SPLIT_SHORT.fullmatch(opt)
    if m and m.group(1):
        return m.group(1), words
    name, eq, val = opt.partition("=")
    long_opt = len(name) > 2 and "--split-string".startswith(name)
    if long_opt and eq:
        return val, words
    if m or long_opt:
        return (words[0], words[1:]) if words else ("", words)
    return None


def _env_words(line):
    r"""The words env -S makes of `line`, by env's own quote rules (measured on macOS env 14/10), or None when env refuses the line or this
    cannot read it as env does. Inside '...' everything is literal but `\\` and `\'`. Inside "..." `\_` is a space and `\c` an error.
    Unquoted, `\_` separates words and `\c` ends the line. `\f \n \r \t \v` are control characters, `\\ \' \" \$ \#` themselves,
    any other escape an error. An unescaped `$` outside '...' is None: env substitutes `${VAR}` and refuses a bare `$`. `#` stays plain text
    (env's comment cuts the line there: judging more words is never open)."""
    words, cur, live, quote, i = [], [], False, None, 0
    while i < len(line):
        ch, i = line[i], i + 1
        if quote == "'":
            if ch == "'":
                quote = None
            elif ch == "\\" and line[i:i + 1] in ("\\", "'"):
                cur.append(line[i])
                i += 1
            else:
                cur.append(ch)
        elif ch == "\\":
            esc, i = line[i:i + 1], i + 1
            if esc == "c":
                if quote:
                    return None
                break
            if esc == "_" and not quote:
                if live:
                    words.append("".join(cur))
                cur, live = [], False
                continue
            if esc == "_":
                esc = " "
            elif esc in ENV_CTRL:
                esc = ENV_CTRL[esc]
            elif not esc or esc not in "\\'\"$#":
                return None
            cur.append(esc)
            live = True
        elif ch == "$":   # outside '...' env substitutes ${VAR} (what the variable holds is not known here) and refuses a bare $
            return None
        elif quote:
            if ch == quote:
                quote = None
            else:
                cur.append(ch)
        elif ch in "'\"":
            quote, live = ch, True
        elif ch in " \t\n\v\f\r":
            if live:
                words.append("".join(cur))
            cur, live = [], False
        else:
            cur.append(ch)
            live = True
    if quote:
        return None
    return words + ["".join(cur)] if live else words


def _operands(base, words):
    """(operands, target directory or None) of a file command's words after the verb: options and their values dropped, an
    empty word dropped (`sed -i ''`), everything after `--` kept."""
    vals, ops, tdir, i, rest = VALUE_OPTS.get(base, ()), [], None, 0, False
    while i < len(words):
        a = words[i]
        i += 1
        if rest or not a.startswith("-") or a == "-" or (base == "chmod" and not ops and a != "--" and CHMOD_MODE.fullmatch(a)):
            if a:
                ops.append(a)
        elif a == "--":
            rest = True
        elif base in TARGET_DIR and a.startswith("--target-directory="):
            tdir = a.split("=", 1)[1]
        elif base in TARGET_DIR and a == "-t" and i < len(words):
            tdir, i = words[i], i + 1
        elif a in vals and i < len(words):
            i += 1
    return ops, tdir


def _inplace_operands(base, words, args):
    """The file operands of `sed -i` / `perl -i` / `ruby -i`: `args` minus the script (sed: the first operand unless -e/-f/--expression gave
    one; the value of -e/-f is dropped too - #427 vòng 3: cả giá trị của cụm cờ kết thúc bằng nó, không có `i` đứng trước: sed `-ne`, perl /
    ruby `-pe` `-lne`), so a script like `$d` or `s/a*/b/` is no target."""
    flag = r"-e|-f|--expression|--file|-[A-Za-hj-z]*[ef]" if base == "sed" else r"-[A-Za-hj-z]*[eE]"
    script = [w for i, w in enumerate(words) if i and re.fullmatch(flag, words[i - 1])]
    ops = [a for a in args if a not in script]
    if base == "sed" and any(w == "-i" and nxt == "" for w, nxt in zip(words, words[1:])):
        ops.remove("")   # BSD `sed -i ''`: hậu tố rỗng, không phải script (script là toán hạng sau nó)
    scripted = any(re.fullmatch(r"-[A-Za-z]*[ef]|--expression.*|--file.*", w) for w in words)
    return ops[1:] if base == "sed" and not scripted else ops


# perl / ruby `-i` (sửa tại chỗ), đứng riêng hay sau các cờ không lấy giá trị (`-pi`, `-lpi.bak`); không phải chữ `i` trong giá trị của
# -M / -I / -e … (`-MList::Util` không phải -i)
_INPLACE_INTERP = re.compile(r"-[acdlnpstTuUvwWX0-9]*i.*")


def _inplace_target(a, here):
    """Đích ghi của một toán hạng sed -i / perl -i / ruby -i: chính nó khi có thật hay bắt đầu bằng $VAR / backtick (caller mở rộng biến hay
    fail closed, như mọi đích không biết); có $VAR / ${…} / $( ) / backtick ở giữa từ hay glob (`*` `?` `[`): thư mục chữ đứng trước phần đó
    (`win_icon_$n.png.meta` -> `.`, `A/*.meta` -> `A`) - file được ghi nằm dưới nó (#427 vòng 3, corpus: `for n in …; do sed -i '' …
    win_icon_$n.png.meta; done` ở main của trunk mode lọt). None: không phải file (không có thật, không biến, không glob)."""
    m = re.search(r"[$`*?[]", a)
    if _exists(a, here) or (m and m.start() == 0 and a[0] in "$`"):
        return a
    if not m:
        return None
    return os.path.dirname(a[:m.start()]) or ("/" if a.startswith("/") else ".")


def _exists(a, here):
    p = _home(a)
    return os.path.exists(p if os.path.isabs(p) else os.path.join(here, p))


def _nested(code, wd, depth, run_bodies):
    """The targets of a script a shell runs (`bash -c`, a heredoc fed to a shell). One that cannot be tokenised, for a caller that runs bodies
    (run_bodies: bin/session_lock.py trunk_write), is a write it cannot rule out: kind "unparsed", where the script runs - it used to count as none."""
    got = targets(code, wd, depth, run_bodies)
    return [("unparsed", "", wd)] if got is None and run_bodies else got or []


def _delimiter_line(cmd, m, start, ends):
    """Offset of the line from `start` on that ends heredoc `m`: the line IS the delimiter, as bash reads it - only `<<-` drops leading TABS
    (OCR 26/10 r2: "  EOF" ended a body here). None when no line does. `ends` caches the line index of `cmd` (built once per kind), so a
    `<<WORD` no line ends costs a lookup, not a scan to the end of the command (r3)."""
    import bisect   # noqa: PLC0415 - only a command with a `<<` gets here
    tabs = m.group(0).startswith("<<-")
    if tabs not in ends:
        at, off = ends.setdefault(tabs, {}), 0
        for ln in cmd.split("\n"):
            at.setdefault(ln.lstrip("\t") if tabs else ln, []).append(off)
            off += len(ln) + 1
    hits = ends[tabs].get(m.group(2), ())
    k = bisect.bisect_left(hits, start)
    return hits[k] if k < len(hits) else None


def targets(cmd, here, depth=0, run_bodies=False):
    """[(kind, target, directory it is relative to)] of the shell line `cmd` run in `here`, or None when it cannot be tokenised.
    kind: "redirect" (a > target; an escaped `\\>` reads as one too, so a caller with its own quote-aware redirect rule skips it),
    "cdvar" (a cd whose directory holds $VAR or a backtick), "file" (cp / install / rsync / ln / scp destination; mv / rm / touch / truncate / tee / mkdir / rmdir / chmod / unlink operands;
    dd of=; sed -i / perl -i operands that exist), "git" (a git write: its -C directory), "build" (a build
    tool or builder module: its working directory), "interp" (an interpreter's operands that exist). A target may hold $VAR or a
    backtick: the caller decides. Heredoc bodies are data, never commands - unless run_bodies and the heredoc feeds a shell (its body is
    scanned like `bash -c '…'`) or an interpreter (its script's literal write paths: "file"); `bash -c '…'` is scanned three levels deep;
    the line of `env -S '…'` / `--split-string` is split into words in place (_env_split).
    A body run_bodies cannot tokenise comes back as ("unparsed", "", directory).
    Thư mục theo cd chữ (cd / pushd; cd có $VAR / backtick / NUL: "cdvar", thư mục giữ); #427 vòng 3: `)` đưa nó về như trước `(` (khi
    _scoped), `popd` về thư mục pushd tương ứng đã rời (ngăn rỗng / không theo được: giữ)."""
    out, bodies, pos, ends = [], [], 0, {}
    while True:                               # heredoc bodies are data, not commands
        m = HEREDOC.search(cmd, pos)
        nl = cmd.find("\n", m.end()) if m else -1
        if not m or nl < 0:
            out.append(cmd[pos:])
            break
        s = _delimiter_line(cmd, m, nl + 1, ends)
        if s is None:   # no line ends it: no heredoc (a `<<EOF` in a comment or a quote) or one bash reads to the end: its lines stay commands (r3)
            out.append(cmd[pos:m.end()])
            pos = m.end()
            continue
        out.append(cmd[pos:nl + 1])
        bodies.append(cmd[nl + 1:s])
        e = cmd.find("\n", s)
        pos = len(cmd) if e < 0 else e
    try:
        text = _drop_fd_numbers(strip_comments("".join(out)))
        lex = shlex.shlex(text, posix=True, punctuation_chars=";&|<>()\n")
        lex.whitespace, lex.whitespace_split, lex.commenters = " \t\r", True, ""
        toks = list(lex)
    except ValueError:
        return None
    # #427 vòng 3: segs xen "(" / ")" (chỉ khi _scoped) - subshell, $( ), <( ), (( )) mở / đóng một tầng thư mục
    scoped, segs, cur = _scoped(text, toks), [], []
    for tok in toks:
        if tok and set(tok) <= set(";&|()\n"):
            if cur:
                segs.append(cur)
                if scoped:   # `<(` `>(` `)>` nằm trong segment (không tách nó): ngoặc của chúng tính sau segment, theo thứ tự
                    segs += [c for t in cur if set(t) <= _OPS for c in t if c in "()"]
            cur = []
            if scoped:
                segs += [c for c in tok if c in "()"]
        else:
            cur.append(tok)
    if cur:
        segs.append(cur)
    found, nbody = [], 0
    # ngăn pushd (popd về thư mục đã rời) và các tầng ( ): (here, ngăn) lúc mở. None: ngăn không theo được - một hàm (thân chạy lúc gọi,
    # không phải chỗ định nghĩa), eval / source / . / dirs, pushd không đích / +N; popd khi đó (hay ngăn rỗng: shell báo lỗi) giữ thư mục
    dirs, scopes = (None if "()" in toks or "function" in toks else []), []
    # HEREDOC reads the raw text (it matches `<<EOF` inside quotes and comments, which shlex reads as no operator) while shlex also emits `<<`
    # for arithmetic (`$((1<<2))`): when the counts differ, pairing a body to an operator by position would hand every later body to the
    # wrong command (OCR2 14). No clever pairing then: after the loop every body is read as a script of this line.
    paired = sum(1 for t in toks if t == "<<") == len(bodies)
    for seg in segs:
        if seg == "(":
            scopes.append((here, None if dirs is None else list(dirs)))
            continue
        if seg == ")":
            if scopes:   # (_scoped: luôn có)
                here, dirs = scopes.pop()
            continue
        words, redirs, fed, i = [], [], [], 0
        while i < len(seg):
            tok = seg[i]
            if tok and set(tok) <= set("<>&|"):
                nxt = seg[i + 1] if i + 1 < len(seg) else ""
                if tok == "<<" and paired:   # the heredocs come in the order of their operators
                    fed.append(bodies[nbody] if nbody < len(bodies) else "")
                    nbody += 1
                if ">" in tok and not tok.endswith("&") and nxt and nxt != "/dev/null" \
                        and not re.fullmatch(r"-|\d+", nxt):
                    redirs.append(nxt)
                i += 2
                continue
            words.append(tok)
            i += 1
        wd = here   # where THIS command runs: `env -C DIR` / `sudo -D DIR` move it, a cd moves `here` for the next ones
        while words and (words[0] in PREFIX or re.fullmatch(r"[A-Za-z_]\w*=.*", words[0])):
            w, words = words[0], words[1:]
            if w in PREFIX_VALUE_OPTS:   # its options (with their values), then timeout's duration
                while words and words[0].startswith("-") and words[0] != "-":
                    opt, words = words[0], words[1:]
                    split = _env_split(opt, words) if w == "env" else None
                    if split is not None:   # its words go first, in place: env options, VAR=, the command and its operands
                        got = _env_words(split[0])
                        if got is None:   # env refuses it (or it cannot be read as env does): never waved through
                            found.append(("unparsed", "", wd))
                            got = split[0].split()   # ... and its operands are still judged, whole (OpenCodeReview 14/10)
                        words = got + split[1]
                    elif "=" in opt and (w, opt.split("=", 1)[0]) in PREFIX_CHDIR:
                        wd = _cd(wd, opt.split("=", 1)[1])
                    elif opt in PREFIX_VALUE_OPTS[w] and words:
                        val, words = words[0], words[1:]
                        if (w, opt) in PREFIX_CHDIR:
                            wd = _cd(wd, val)
                if w == "timeout" and words:
                    words = words[1:]
        verb = words[0] if words else ""
        args = [a for a in words[1:] if not a.startswith("-")]
        hits = [("redirect", r) for r in redirs]
        if verb == "popd":   # (không `continue`: redirect của nó vẫn là đích, như trước)
            if dirs and len(words) == 1:
                here = dirs.pop()
            elif len(words) > 1:
                dirs = None   # popd +N / -n
        elif verb in ("eval", "source", ".", "dirs"):
            dirs = None
        if verb in ("cd", "pushd"):
            if verb == "pushd" and dirs is not None:
                if len(words) == 2 and not words[1].startswith(("+", "-")):
                    dirs.append(here)
                else:
                    dirs = None
            if args and ("$" in args[0] or "`" in args[0] or "\0" in args[0]):
                found.append(("cdvar", args[0], wd))   # where it leads is the caller's to judge: `here` stays
            elif args:
                here = _cd(wd, args[0])
            elif not args:
                here = os.path.expanduser("~")
            continue
        base = os.path.basename(verb)
        if base in DEST_LAST or base in ALL_ARGS:
            ops, tdir = _operands(base, words[1:])
        if base in DEST_LAST and (ops or tdir):
            # -t DIR: DIR; `ln -s TARGET` alone: the link lands in the cwd; else the last operand
            dest = tdir if tdir is not None else ("." if base == "ln" and len(ops) == 1 else ops[-1])
            if not (base in ("scp", "rsync") and re.match(r"[^/]*:", dest)):   # host:path is remote
                hits.append(("file", dest))
        elif base in ALL_ARGS:
            if base == "chmod" and not any(w.startswith("--reference") for w in words[1:]):
                ops = ops[1:]   # the mode (with --reference there is none)
            hits += [("file", a) for a in ops + ([tdir] if tdir is not None else [])]
        elif base == "dd":
            hits += [("file", a[3:]) for a in args if a.startswith("of=")]
        elif base == "sed" and any(re.fullmatch(r"-[A-Za-z]*i.*|--in-place.*", a) for a in words[1:]):
            hits += [("file", t) for t in (_inplace_target(a, wd) for a in _inplace_operands(base, words, args) if a) if t]   # BSD `sed -i ''`: the empty suffix is no file
        elif base in ("perl", "ruby") and any(_INPLACE_INTERP.fullmatch(a) for a in words[1:]):
            hits += [("file", t) for t in (_inplace_target(a, wd) for a in _inplace_operands(base, words, args) if a) if t]
        elif base == "git":
            gdir, sub, skip, rest = wd, "", None, []
            for k, a in enumerate(words[1:], 1):
                if skip:
                    if skip == "-C":   # ~ expanded as the shell does (OpenCodeReview 14/10); a $VAR one stays for the caller
                        gdir = os.path.join(gdir, _home(a))
                    skip = None
                elif a in ("-C", "-c", "--git-dir", "--work-tree"):
                    skip = a
                elif not a.startswith("-"):
                    sub, rest = a, words[k + 1:]
                    break
            if sub == "stash" and rest and rest[0] in STASH_READ:
                sub = ""
            if sub in GIT_WRITE:
                hits.append(("git", gdir))
        elif BUILDERS.match(verb) or BUILDERS.match(base):
            hits.append(("build", wd))
        elif INTERP.match(base):
            code = next((words[k + 1] for k in range(1, len(words) - 1)
                         if base in ("bash", "sh", "zsh") and re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", words[k])), None)
            module = next((words[k + 1] for k in range(1, len(words) - 1) if words[k] == "-m"), None)
            if code is not None:
                if depth < 3:
                    found += _nested(code, wd, depth + 1, run_bodies)
            elif (module and module.split(".")[0] in MODULE_BUILDERS) or \
                    (not module and args and BUILDERS.match(os.path.basename(args[0]))):
                hits.append(("build", wd))
            else:
                hits += [("interp", a) for a in args[1:] if _exists(a, wd)]
                if run_bodies and fed and (not args or ("-s" in words[1:] and base in SHELLS) or "-" in words[1:]):   # the script is on stdin, not a file (python's -s is no such flag)
                    for body in fed:
                        if base not in SHELLS:
                            hits += [("file", w.group("p")) for rx in SCRIPT_WRITES for w in rx.finditer(body)]
                        elif depth < 3:
                            found += _nested(body, wd, depth + 1, run_bodies)
        found += [(kind, t, wd) for kind, t in hits]
    if run_bodies and not paired and depth < 3:   # (a data body read as commands: a false alarm here is the price of never missing a write)
        for body in bodies:
            found += _nested(body, here, depth + 1, run_bodies)
            found += [("file", w.group("p"), here) for rx in SCRIPT_WRITES for w in rx.finditer(body)]
    return found
