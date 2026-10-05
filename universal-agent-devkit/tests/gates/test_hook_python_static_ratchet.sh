#!/usr/bin/env bash
# Static ratchet for the shadowed-stdlib hole (see tests/gates/test_hook_python_isolation.sh for the behaviour test).
#
# `python3 -c '…'`, `python3 - <<'PY'`, `python3 <<'PY'`, `python3 -m mod` put the cwd FIRST on sys.path, and the cwd of a hook is the project:
# a json.py / shlex.py / re.py in the project root replaces the stdlib module and can switch a gate off. `python3 -I` (isolated mode) removes
# the cwd (and PYTHON* env and the user site) from sys.path. Rules, for hooks/*.sh, profiles/*/hooks/*.sh, the git pre-commit body and the
# adb-safe-exec wrapper that feeds hardware_safety_gate:
#   1. every INLINE python start (-c, -m, a lone -, a heredoc, `< file`; python / python3 / python3.NN / ${PY:-…} / "$PYTHON"; any flags before
#      it, -X/-W values, a launch continued with a trailing backslash) carries -I — except an ALLOW entry, each with its reason. A python SCRIPT
#      FILE (`python3 "$X/bin/y.py"`) is not inline: its sys.path[0] is the script directory, never the cwd. A child started from hook python as
#      [sys.executable, "-c", …] / ["python3", "-m", …] is the same hole and needs -I too.
#   2. no sys.path.insert(N, …) / append(…) of an expression that can be the empty string (`… or ""`, `os.environ.get(X, "")`): "" is the cwd, so a
#      variable that is empty (proof_gate in a copy-mode install: PROOF_BIN="") puts the project back in front of the stdlib and undoes -I.
#      Guard with os.path.isabs() first, or ALLOW with the reason the value is always set to an absolute path.
# Known limits (not scanned): an interpreter held in a variable that is not named PY* / PYTHON*; python started through xargs / sh -c STRING built
# at run time; a [sys.executable, …] list split over several lines; `shutil.which("python3")` as argv[0]; installers and test commands.
#   HP_KIT=<devkit dir>   scan another copy of the kit (e.g. the unpatched one: RED).
# bash 3.2 compatible wrapper; python3 stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${HP_KIT:-$DEVKIT_DIR}"
python3 -I - "$KIT" <<'PY'
import glob, os, re, sys

KIT = sys.argv[1]
EXTRA = ["scripts/git/git-pre-commit.sh", "profiles/android/scripts/qa/adb-safe-exec.sh"]
FILES = sorted(glob.glob(os.path.join(KIT, "hooks", "*.sh")) + glob.glob(os.path.join(KIT, "profiles", "*", "hooks", "*.sh"))) \
    + [os.path.join(KIT, e) for e in EXTRA]

# (file, text of the line, kind, reason): lines a rule matches that are NOT a hole. kind: "launch" | "path"
ALLOW = [
    ("hooks/block-dangerous-git.sh", "python3 - <<…)", "launch",
     "text of a docstring inside the python body (it explains which shell lines the parser treats as feeding an interpreter), not a launch"),
    ("hooks/comment_claim_guard.sh", "CCG_HOOKDIR", "path", "CCG_HOOKDIR is set by the wrapper to $(cd dirname && pwd): absolute, never empty"),
    ("hooks/review_gate.sh", "CLAIM_HOOKDIR", "path", "CLAIM_HOOKDIR is set by the wrapper to $(cd dirname && pwd): absolute, never empty"),
    ("hooks/session_context.sh", "WT_SCRIPT", "path", "WT_SCRIPT is set by the wrapper to <kit>/scripts/git/worktree.py: never empty"),
    ("hooks/test_evidence_gate.sh", "TE_SELF", "path", "TE_SELF is the hook path ($0, set by the wrapper): realpath of a non-empty path"),
]

PY = re.compile(r"""(?<![\w"'.$-])python3?(?:\.\d+)?(?=[\s<]|$)""")
PYVAR = re.compile(r"""(?<![\w$])"?\$\{?(?:PY|PYTHON|PYBIN|PY3)\w*(?::?[-=+][^}\s"]*)?\}?"?(?=[\s<])""")
SUBPROC = re.compile(r"""\[\s*(?:sys\.executable|["']python3?(?:\.\d+)?["'])\s*,([^\]]*)\]""")
UNGUARDED = re.compile(r"""sys\.path\.(?:insert\(\s*\d+\s*,|append\()[^\n]*?(?:\bor\s*["']{2}|environ\.get\([^()]*,\s*["']{2}\s*\))""")


def after_launch(rest):
    """None when `rest` (the words after the interpreter) start a script file or something else; else whether -I was among the flags
    of an inline start (-c / -m / lone - / heredoc / < file)."""
    toks, iso, k = rest.split(), False, 0
    if not toks:
        return False              # `… | python3` at the end of a line: the program comes from stdin
    while k < len(toks):
        t = toks[k]
        if re.match(r"<(?!\()[^>]*$", t):
            return iso            # heredoc, here-string or `< file` (not a usage hint such as <devkit>/x.py)
        if t == "-":
            return iso
        m = re.match(r"-([A-Za-z]+)", t)
        if t.startswith("--") or not m:
            return None
        letters = m.group(1)
        iso = iso or "I" in letters
        if letters.endswith("c") or "m" in letters:
            return iso
        if letters in ("X", "W") and t == "-" + letters:
            k += 1                # -X opt / -W arg take a separate word
        k += 1
    return None


def logical_lines(text):
    """(first physical line, text): a trailing backslash continues the line (a launch split as `python3 \\` / `-c '…'`)."""
    out, buf, start = [], "", 0
    for n, line in enumerate(text.splitlines(), 1):
        if not buf:
            start = n
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        out.append((start, buf + line))
        buf = ""
    if buf:
        out.append((start, buf))
    return out


def scan(text):
    """([(line no, line, kind)] of holes, number of inline starts seen). kind: inline | subprocess | path"""
    bad, seen = [], 0
    for n, line in logical_lines(text):
        if line.lstrip().startswith("#"):
            continue
        for rx in (PY, PYVAR):
            for m in rx.finditer(line):
                iso = after_launch(line[m.end():])
                if iso is None:
                    continue
                seen += 1
                if not iso:
                    bad.append((n, line.strip(), "inline"))
        for m in SUBPROC.finditer(line):
            lits = re.findall(r"""["'](-[A-Za-z]+)["']""", m.group(1))
            if any(l[1:].endswith("c") or "m" in l[1:] for l in lits):
                seen += 1
                if not any("I" in l[1:] for l in lits):
                    bad.append((n, line.strip(), "subprocess"))
        if UNGUARDED.search(line):
            bad.append((n, line.strip(), "path"))
    return bad, seen


fails = []

# 0. the scanner itself: what it must flag (1) and leave alone (0)
SAMPLE = {
    "python3 -c 'x'": 1, "x | python3 -c 'x'": 1, "python3 - <<'PY'": 1, "python3 <<'PY'": 1, "A=1 python3 -S -c 'x'": 1,
    "a=\"$(python3 -c 'x' \"$0\")\"": 1, "python3 -I -c 'x'": 0, "python3 -I - <<'PY'": 0, "python3 -I -S -c 'x'": 0,
    "python3 -SI -c 'x'": 0, "python3 -I <<'PY'": 0, "exec python3 \"$HERE/../bin/session_lock.py\"": 0,
    "python3 \"$HARNESS\" fields": 0, "echo 'python3 .agents/devkit/bin/post-fix-gate.py --run-tests'": 0,
    "subprocess.run([sys.executable, \"-c\", code])": 1, "subprocess.run([sys.executable, \"-I\", \"-c\", code])": 0,
    "subprocess.run([sys.executable, tool, gdir])": 0, "# python3 -c 'x' in a comment": 0,
    # added 2026-10-05 (round 2): versioned / pathed / variable interpreters, -m, flags with values, continued launches, stdin forms
    "python3.12 -c 'x'": 1, "python3.9 - <<'PY'": 1, "/usr/bin/python3 -c 'x'": 1, "env python3 -c 'x'": 1, "python -c 'x'": 1,
    "python3.12 -I -c 'x'": 0, "python3 -m json.tool": 1, "python3 -I -m json.tool": 0, "python3 -X utf8 -c 'x'": 1,
    "python3 -W ignore -c 'x'": 1, "python3 -X utf8 -I -c 'x'": 0, "python3 -Ic 'x'": 0, "python3 -c'x'": 1, "python3 -Sc 'x'": 1,
    "\"$PY\" -c 'x'": 1, "${PY:-python3} -c 'x'": 1, "\"$PYTHON\" - <<'PY'": 1, "\"$PY\" -I -c 'x'": 0, "printf x | python3": 1,
    "python3 < script.py": 1, "python3 \\\n  -c 'x'": 1, "python3 -I \\\n  -c 'x'": 0, "python3 \\\n  -I -c 'x'": 0,
    "python3 -u \"$X\"": 0, "python3 --version": 0, "echo \"python3 .agents/x.py\"": 0, "x = {\"python\", \"python3\", \"node\"}": 0,
    "re.compile(r\"python\\S*\\s+-m\\s+(pytest|unittest)\")": 0, "subprocess.run([sys.executable, \"-m\", \"pytest\"])": 1,
    "subprocess.run([\"python3.12\", \"-c\", code])": 1, "subprocess.run([\"python3\", \"-I\", \"-c\", code])": 0,
    "subprocess.run([sys.executable, \"-I\", \"-m\", \"x\"])": 0,
    # the empty-string sys.path hole (proof_gate in a copy-mode install)
    "sys.path.insert(0, os.environ.get(\"PROOF_BIN\") or \"\")": 1, "sys.path.insert(0, os.environ.get(\"X\", \"\"))": 1,
    "sys.path.insert(1, os.path.dirname(os.environ.get(\"W\") or \"\"))": 1, "sys.path.append(os.environ.get(\"X\") or \"\")": 1,
    "sys.path.insert(0, _pb)": 0, "sys.path.insert(0, os.path.join(devkit, \"bin\"))": 0, "sys.path.insert(0, os.environ[\"TS_BIN\"])": 0,
    "if os.path.isabs(_pb): sys.path.insert(0, _pb)": 0,
}
for line, want in SAMPLE.items():
    got = len(scan(line)[0])
    if got != want:
        fails.append("scanner self-check: %r flagged %d, expected %d" % (line, got, want))

# 1. the real files
total, allowed_hit = 0, set()
for path in FILES:
    rel = os.path.relpath(path, KIT)
    if not os.path.isfile(path):
        fails.append("missing file: " + rel)
        continue
    bad, seen = scan(open(path, encoding="utf-8").read())
    total += seen
    for n, line, kind in bad:
        ak = "path" if kind == "path" else "launch"
        hit = [a for a in ALLOW if a[0] == rel and a[2] == ak and a[1] in line]
        if hit:
            allowed_hit.add(hit[0][:2])
            continue
        what = {"path": "sys.path entry that can be the empty string (= the cwd)", "subprocess": "python child without -I"}.get(kind, "inline python without -I")
        fails.append("%s:%d: %s: %s" % (rel, n, what, line[:110]))
if total < 34:
    fails.append("scanner found only %d inline python starts in %d files (expected 34+): it has gone blind" % (total, len(FILES)))

# 2. every ALLOW entry still matches something (a stale entry would hide a future hole)
for f, frag, kind, reason in ALLOW:
    if (f, frag) not in allowed_hit:
        fails.append("stale ALLOW entry (matches no line): %s %r" % (f, frag))

print("scanned %d files, %d inline python starts, %d allow-listed" % (len(FILES), total, len(ALLOW)))
for f in fails:
    print("✖ " + f)
if fails:
    print("❌ test_hook_python_static_ratchet: %d failed" % len(fails))
    sys.exit(1)
print("✅ test_hook_python_static_ratchet: every inline python start runs isolated (-I), no sys.path entry can be the cwd")
PY
