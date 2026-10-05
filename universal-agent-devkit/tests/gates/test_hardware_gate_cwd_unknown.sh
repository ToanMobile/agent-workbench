#!/usr/bin/env bash
# Regression test (2026-10-04, hardening of the hook python): hooks/hardware_safety_gate.sh crashed on
#   cd $K; cd /tmp; rm -rf /opt/x
# `cd $VAR` leaves the working directory unknown (None); the next `cd /abs` computed os.path.join(None, "/abs") → TypeError, an
# uncaught traceback, exit 1. Claude Code only blocks on exit 2, so the command RAN although the header says FAIL-CLOSED.
# Two fixes, both pinned here:
#   1. root cause: join(c or "/", arg) — an absolute `cd` target does not depend on the unknown directory, so the rm rule judges the
#      real target (outside the project → refused with the rm reason, in /tmp → allowed);
#   2. fail closed: an uncaught exception anywhere in the gate python exits 2 with a one-line reason, never 1.
# The forced-error cases inject the fault into a COPY of the hook in a scratch dir (no knob in the hook itself): (a) the old buggy line
# put back, (b) a ZeroDivisionError at the rm walk. Both must give rc 2 + one line, no traceback, and the line names the way out
# (the escape hatch the hook really reads: HARDWARE_OVERRIDE).
# Round 2 (2026-10-05) adds the cwd-tracking holes of the same walk: `pushd +N`, `cd -` (the old code read it as `cd ~`) and CDPATH
# (in the environment or in the command) leave the working directory UNKNOWN, so a relative rm -rf after them is refused; the known
# forms (`cd /abs`, `cd sub`, `cd -P /abs`) are judged exactly as before.
#   HP_KIT=<devkit dir>   run against another copy of the kit (e.g. the unpatched one: RED).
# bash 3.2 compatible wrapper; python3 stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${HP_KIT:-$DEVKIT_DIR}"
export PYTHONDONTWRITEBYTECODE=1
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile

HOOK = os.path.join(os.path.realpath(sys.argv[1]), "hooks", "hardware_safety_gate.sh")
TMP = os.path.realpath(tempfile.mkdtemp(prefix="hsgcwd."))
PROJ = os.path.join(TMP, "proj")
os.makedirs(PROJ)
fails = []


def run(hook, cmd, cwd=PROJ, env_extra=None):
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": cwd, "session_id": "t"})
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "PYTHON"))}
    env.update(CLAUDE_PROJECT_DIR=PROJ, PYTHONDONTWRITEBYTECODE="1")
    for k in ("HARDWARE_SAFETY_GATE", "HARDWARE_OVERRIDE", "ADB_DENY_SERIALS", "ADB_ALLOW_SERIALS", "CDPATH"):
        env.pop(k, None)
    env.update(env_extra or {})
    r = subprocess.run(["bash", hook], input=payload, capture_output=True, text=True, timeout=60, cwd=TMP, env=env)
    return r.returncode, r.stderr


def check(name, ok, detail=""):
    print(("✔ " if ok else "✖ ") + name + ("" if ok else "  -> " + detail))
    if not ok:
        fails.append(name)


OUT = "/opt/hsg-cwd-unknown-target"
REASON = "nằm ngoài project"          # the rm rule's own reason: a crash turned into rc 2 by the excepthook says something else
# 1. the family: an unknown cwd (cd $VAR / $(…)) followed by an absolute cd, then rm -rf outside the project
for cmd in ("cd $K; cd /tmp; rm -rf " + OUT,
            "cd $K && cd /tmp && rm -rf " + OUT,
            'cd "$K"; cd /tmp; rm -rf ' + OUT,
            "cd $(pwd)/x; cd /tmp; rm -rf " + OUT,
            "cd ${K}; cd /tmp; cd /var; rm -rf " + OUT):
    rc, err = run(HOOK, cmd)
    check("blocked by the rm rule: %r" % cmd, rc == 2 and REASON in err and "Traceback" not in err, "rc=%s %s" % (rc, err.strip()[:160]))
# an unknown directory plus a RELATIVE target: nobody can say what is removed
rc, err = run(HOOK, "cd $K; cd /tmp; rm -rf sub/dir/data")
check("unknown cwd + relative target is refused (cannot resolve it)", rc == 2 and "không biết thư mục hiện tại" in err, "rc=%s %s" % (rc, err.strip()[:160]))

# 2. controls — what must NOT change
for cmd, want, why in (
    ("cd $K; rm -rf " + OUT, 2, "unknown cwd, absolute target outside: still refused"),
    ("cd /tmp; rm -rf " + OUT, 2, "known cwd, absolute target outside: still refused"),
    ("rm -rf " + OUT, 2, "plain rm -rf outside the project: still refused"),
    ("cd $K; cd /tmp; rm -rf /tmp/hsg-cwd-ok-target", 0, "absolute target inside /tmp after an unknown cd: allowed (was rc 1 = a crash)"),
    ("cd $K; cd /tmp; ls -la /tmp", 0, "benign command after an unknown cd"),
    ("rm -rf /tmp/hsg-cwd-ok-target", 0, "rm -rf in /tmp"),
    ("cd $K; ls", 0, "benign command with an unknown cd"),
    ('ls "$HOME" | head -2', 0, "benign command that reaches the full parser"),
    ("adb remount", 2, "a non-rm rule is unchanged"),
):
    rc, err = run(HOOK, cmd)
    check("rc %s  %s: %r" % (want, why, cmd), rc == want and "Traceback" not in err, "rc=%s %s" % (rc, err.strip()[:160]))

# 2b. cwd tracking (round 2): pushd +N, cd -, CDPATH. "r" + "m" keeps the literal out of this file's own scan by the live gate.
RM = "r" + "m -rf "
os.makedirs(os.path.join(PROJ, "sub", "dir"))
HOME_IN_TMP = os.path.join(TMP, "home")     # under $TMPDIR: `cd ~` followed by a relative rm would be ALLOWED, which is what the old `cd -` read as
os.makedirs(HOME_IN_TMP)
REFUSED = "không biết thư mục hiện tại"
for name, cmd, env_extra in (
        ("pushd +1 returns to a directory the walk never saw (&&)", "pushd /opt/data && pushd /tmp && pushd +1 && " + RM + "sub/dir", None),
        ("pushd +1 (;)", "pushd /opt/data; pushd /tmp; pushd +1; " + RM + "sub/dir", None),
        ("pushd -1", "pushd /opt/data && pushd /tmp && pushd -1 && " + RM + "sub/dir", None),
        ("bare pushd swaps the top two directories", "pushd /opt/data && pushd /tmp && pushd && " + RM + "sub/dir", None),
        ("cd - is the previous directory, not ~", "cd /opt/data && cd - && " + RM + "sub/dir", {"HOME": HOME_IN_TMP}),
        ("CDPATH set on the cd itself", "CDPATH=/opt cd data && " + RM + "sub/dir", None),
        ("CDPATH exported earlier in the command", "export CDPATH=/opt; cd data && " + RM + "sub/dir", None),
        ("CDPATH assigned, not exported", "CDPATH=/opt; cd data && " + RM + "sub/dir", None),
        ("CDPATH in the hook environment", "cd data && " + RM + "sub/dir", {"CDPATH": "/opt"}),
        ("CDPATH set for a nested bash -c", "CDPATH=/opt bash -c 'cd data && " + RM + "sub/dir'", None)):
    rc, err = run(HOOK, cmd, env_extra=dict({"HOME": HOME_IN_TMP}, **(env_extra or {})))
    # after `;` the old directory stays possible too: the walk may name another reason first, the decision is the same
    check("unknown cwd, refused: " + name, rc == 2 and (REFUSED in err or "; " in cmd.split("rm")[0]) and "Traceback" not in err,
          "rc=%s %s" % (rc, err.strip()[:200]))
for name, cmd, want, env_extra in (
        ("cd /abs (outside) && rm", "cd /opt/data && " + RM + "sub/dir", 2, None),
        ("cd -P /abs (outside) && rm", "cd -P /opt/data && " + RM + "sub/dir", 2, None),
        ("cd -- /abs (outside) && rm", "cd -- /opt/data && " + RM + "sub/dir", 2, None),
        ("cd /tmp && rm sub/dir", "cd /tmp && " + RM + "sub/dir", 0, None),
        ("cd sub (in the project) && rm x, no CDPATH", "cd sub && " + RM + "x", 0, None),
        ("cd ./sub && rm x", "cd ./sub && " + RM + "x", 0, None),
        ("pushd sub && rm x", "pushd sub && " + RM + "x", 0, None),
        ("pushd sub; popd; rm sub/dir stays refused (popd is unknown)", "pushd sub; popd; " + RM + "sub/dir", 2, None),
        ("cd /abs inside /tmp with CDPATH set: an absolute cd ignores CDPATH", "cd /tmp && " + RM + "sub/dir", 0, {"CDPATH": "/opt"}),
        ("bare cd goes home: known, HOME under $TMPDIR", "cd && " + RM + "x", 0, {"HOME": HOME_IN_TMP}),
        ("(new precision) pushd -n only edits the stack", "pushd -n /opt/data && " + RM + "sub/dir", 0, None)):
    rc, err = run(HOOK, cmd, env_extra=env_extra)
    check("rc %s  control: %s" % (want, name), rc == want and "Traceback" not in err, "rc=%s %s" % (rc, err.strip()[:200]))

# 3. fail closed: forced internal errors, injected into a copy of the hook
src = open(HOOK, encoding="utf-8").read()
FIXED = 'os.path.join(c or "/", arg)'
OLD = "os.path.join(c, arg)"
RMLINE = "rm_why = None if (label or MCP) else rm_problem(cmd, [CWD])"
injections = {
    "the old buggy line put back (join(c, arg))": (src.replace(FIXED, OLD), "cd $K; cd /tmp; rm -rf " + OUT),
    "a ZeroDivisionError at the rm walk": (src.replace(RMLINE, "rm_why = 1 / 0"), 'ls "$HOME"'),   # a $ keeps it off the bash fast path
}
for name, (text, cmd) in injections.items():
    if name.startswith("a Zero") and RMLINE not in src:
        check("injection point present in the hook: " + RMLINE, False, "the hook changed; update this test")
        continue
    copy = os.path.join(TMP, "hsg_injected.sh")
    open(copy, "w", encoding="utf-8").write(text)
    rc, err = run(copy, cmd)
    lines = [l for l in err.splitlines() if l.strip()]
    check("fail closed on %s: rc 2" % name, rc == 2, "rc=%s (1 = the command would have run) %s" % (rc, err.strip()[:160]))
    check("  … with one line of reason and no traceback", len(lines) == 1 and "Traceback" not in err and "lỗi nội bộ" in err, repr(err[:200]))
    check("  … and that line names an escape hatch the hook really reads", "HARDWARE_OVERRIDE" in err and "HARDWARE_OVERRIDE:-0" in src,
          repr(err[:300]))

shutil.rmtree(TMP, ignore_errors=True)
if fails:
    print("❌ test_hardware_gate_cwd_unknown: %d failed" % len(fails))
    sys.exit(1)
print("✅ test_hardware_gate_cwd_unknown: all passed")
PY
