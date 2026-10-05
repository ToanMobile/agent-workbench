#!/usr/bin/env bash
# Regression test (2026-10-05, round 2 of the hook-python hardening): what the two PreToolUse Bash safety gates
# (hooks/hardware_safety_gate.sh, hooks/block-dangerous-git.sh) do when python itself misbehaves. Both promise FAIL-CLOSED in their headers,
# and Claude Code only blocks on exit 2: every rc != 0 / 2 means the command RAN.
#   1. A reversed bracket range makes Python 3.9's fnmatch raise re.error ([z-a], and the s[:-1] / a[i-1] of any inline script; 3.12 and
#      3.14 do not raise). Before the fix the gate crashed on those commands: rc 1 (the command ran, also the real rules it never reached),
#      and with the excepthook rc 2 = a LEGITIMATE command blocked. bash reads such a bracket as "no match", so must the gate: rc 0.
#      A valid glob that names a tool (a?b remount) must still be recognised.
#   2. python missing / unusable (a pyenv / asdf shim that names a missing version exits 1; a killed python exits 137): the wrapper turned
#      python rc into the hook rc, so the command ran. Now only the python's own 0 and 2 stand, anything else blocks with a reason that
#      says python failed. A command that needs no python (the bash fast path: ls) is unaffected.
# Every case runs once per interpreter found: the python3 on PATH and /usr/bin/python3 when it is a different, working interpreter (the
# macOS system 3.9.6 is the one that raises); the interpreter is put first on PATH through a symlink shim, nothing system-wide changes.
#   HP_KIT=<devkit dir>   run against another copy of the kit (e.g. the unpatched one: RED).
# bash 3.2 compatible wrapper; python3 stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${HP_KIT:-$DEVKIT_DIR}"
export PYTHONDONTWRITEBYTECODE=1
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile

KIT = os.path.realpath(sys.argv[1])
TMP = os.path.realpath(tempfile.mkdtemp(prefix="gatepy."))
PROJ = os.path.join(TMP, "proj")
os.makedirs(PROJ)
fails = []
HSG, BDG = "hardware_safety_gate.sh", "block-dangerous-git.sh"


def check(name, ok, detail=""):
    print(("✔ " if ok else "✖ ") + name + ("" if ok else "  -> " + detail))
    if not ok:
        fails.append(name)


# ── interpreters: the python3 on PATH, and the macOS system one when it differs ──────────────────────────────────────────
interps = {}
for label, cand in (("PATH python3", shutil.which("python3")), ("/usr/bin/python3", "/usr/bin/python3")):
    if not cand or not os.path.exists(cand):
        continue
    try:
        r = subprocess.run([cand, "-I", "-c", "import sys,os; print('%d.%d' % sys.version_info[:2], os.path.realpath(sys.executable))"],
                           capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        continue
    if r.returncode != 0 or not r.stdout.strip():
        continue
    ver, real = r.stdout.split()[0], r.stdout.split()[1]
    if real in [v[1] for v in interps.values()]:
        continue
    interps[label] = (ver, real, cand)
print("interpreters under test: " + ", ".join("%s = %s (%s)" % (k, v[0], v[2]) for k, v in interps.items()))
if not interps:
    print("✖ no working python3 found")
    sys.exit(1)


def shim_dir(name, body=None, target=None):
    d = os.path.join(TMP, "shim_" + name)
    os.makedirs(d)
    p = os.path.join(d, "python3")
    if target:
        os.symlink(target, p)
    else:
        with open(p, "w") as fh:
            fh.write(body)
        os.chmod(p, 0o755)
    return d


def run(hook, cmd, shim):
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": PROJ, "session_id": "t"})
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "PYTHON", "CLAUDE_", "HARDWARE_", "ADB_", "CDPATH"))}
    env.update(PATH=shim + os.pathsep + os.environ["PATH"], CLAUDE_PROJECT_DIR=PROJ, PYTHONDONTWRITEBYTECODE="1",
               XDG_CONFIG_HOME=os.path.join(TMP, "xdg"), HOME=os.path.join(TMP, "home"))
    r = subprocess.run(["bash", os.path.join(KIT, "hooks", hook)], input=payload, capture_output=True, text=True, timeout=60, cwd=PROJ, env=env)
    return r.returncode, r.stderr


# ── 1. reversed bracket range ───────────────────────────────────────────────────────────────────────────────────────────
RANGE_CMDS = [
    ("python3 - <<'EOF' with s[:-1]", "python3 - <<'EOF'\ns = 'abc'\nprint(s[:-1])\nEOF"),
    ("python3 - <<EOF (unquoted) with s[:-1]", "python3 - <<EOF\ns=abc\nprint(s[:-1])\nEOF"),
    ("python3 -c with a[i-1]", "python3 -c 'print(a[i-1])' x"),
    ("echo [z-a] after a $ pipeline", "echo \"$HOME\" | awk '{print $1}'; echo [z-a]"),
    ("a word that is a reversed range in command position", "s[:-1] foo"),
    ("sed with [9-0]", "git log --oneline -3 | sed 's/[9-0]//'"),
    # "no match" means no match: a reversed-range word is not adb / git, whatever follows it
    ("reversed-range word + adb-looking tail is not adb", "s[:-1] remount"),
    ("reversed-range word + git-looking tail is not git", "s[:-1] reset --hard HEAD~1"),
]
for label, (ver, real, cand) in interps.items():
    shim = shim_dir("i%s" % ver.replace(".", ""), target=cand)
    for hook in (HSG, BDG):
        for name, cmd in RANGE_CMDS:
            rc, err = run(hook, cmd, shim)
            check("python %s  %s: reversed range is no match, command allowed (rc 0): %s" % (ver, hook[:12], name), rc == 0,
                  "rc=%s %s" % (rc, err.strip()[:160]))
    # a valid glob that names a tool is still seen through, and the real rules still fire
    rc, err = run(HSG, "a?b remount", shim)
    check("python %s  %s: a?b remount is still blocked (rc 2)" % (ver, HSG[:12]), rc == 2, "rc=%s %s" % (rc, err.strip()[:120]))
    rc, err = run(HSG, "[a-b]db remount", shim)
    check("python %s  %s: [a-b]db remount is still blocked (rc 2)" % (ver, HSG[:12]), rc == 2, "rc=%s %s" % (rc, err.strip()[:120]))
    rc, err = run(BDG, "g?t reset --hard HEAD~1", shim)
    check("python %s  %s: g?t reset --hard is still blocked (rc 2)" % (ver, BDG[:12]), rc == 2, "rc=%s %s" % (rc, err.strip()[:120]))

# ── 2. python unusable: only its own 0 / 2 may stand ────────────────────────────────────────────────────────────────────
BROKEN = {
    "version-manager shim, missing version (exit 1)": '#!/bin/sh\necho "pyenv: version 9.9.9 is not installed" >&2\nexit 1\n',
    "python killed by a signal (rc 137)": '#!/bin/sh\nkill -KILL $$\n',
    "exit 3": '#!/bin/sh\nexit 3\n',
}
CHAIN = "git reset --hard HEAD~3; " + "r" + "m -rf \"/opt/x\""
for n, (sname, body) in enumerate(BROKEN.items()):
    shim = shim_dir("broken%d" % n, body=body)
    for hook in (HSG, BDG):
        rc, err = run(hook, CHAIN, shim)
        check("%s: %s blocks the chain when python is broken (rc 2, says python)" % (sname, hook[:12]),
              rc == 2 and "python" in err.lower(), "rc=%s %s" % (rc, err.strip()[:160]))
        rc, err = run(hook, 'git status "$PWD"', shim)
        check("%s: %s fails closed on a command that needs python (rc 2)" % (sname, hook[:12]), rc == 2, "rc=%s %s" % (rc, err.strip()[:160]))
        rc, err = run(hook, "ls -la", shim)
        check("%s: %s still allows a command that needs no python (bash fast path, rc 0)" % (sname, hook[:12]), rc == 0,
              "rc=%s %s" % (rc, err.strip()[:160]))

shutil.rmtree(TMP, ignore_errors=True)
if fails:
    print("❌ test_gate_python_failures: %d failed" % len(fails))
    sys.exit(1)
print("✅ test_gate_python_failures: all passed")
PY
