#!/usr/bin/env bash
# Trunk mode (bin/session_lock.py trunk_write): a session in a linked worktree must be able to redirect output to a scratch file whose
# NAME holds a variable, `bash "$f" >/tmp/q-$t.log 2>&1`. Until 2026-11-10 any `$VAR` the line does not assign was refused ("Đích là biến"),
# even with an absolute directory outside main in front of it, so super-board QA workers could not run their tests (qa-839: 12 blocks).
# Rule now: the variable may sit only in the LAST path component, after an absolute directory that is neither inside main nor holds `..`.
# Table: command -> expected hook exit (0 allow, 2 block), cwd = a linked worktree of a trunk-mode repo.
#   SLT_KIT=<devkit dir>   run the same table against another copy of the kit (the unpatched one: RED).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${SLT_KIT:-$DEVKIT_DIR}"
export PYTHONDONTWRITEBYTECODE=1
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile

KIT = os.path.realpath(sys.argv[1])
SCRIPT = os.path.join(KIT, "bin", "session_lock.py")
tmp = os.path.realpath(tempfile.mkdtemp(prefix="sltleaf_"))


def sh(*a, cwd=None):
    r = subprocess.run(list(a), cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"setup failed: {a}: {r.stderr[:200]}")
    return r.stdout


MAIN = os.path.join(tmp, "main")
os.makedirs(MAIN)
sh("git", "init", "-q", MAIN)
sh("git", "-C", MAIN, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
WT = os.path.join(tmp, "wt")
sh("git", "-C", MAIN, "worktree", "add", "-q", "-b", "lane", WT)
sh("git", "-C", MAIN, "config", "devkit.trunkMode", "true")


def hook(cmd):
    p = {"hook_event_name": "PreToolUse", "session_id": "me", "cwd": WT, "tool_name": "Bash", "tool_input": {"command": cmd}}
    env = {k: v for k, v in os.environ.items() if k not in ("WORKTREE_TRUNK_MODE", "DEVKIT_ALLOW_SHARED_CHECKOUT")}
    try:
        return subprocess.run([sys.executable, "-I", SCRIPT], input=json.dumps(p), capture_output=True, text=True, env=env,
                              cwd=WT, timeout=20).returncode
    except subprocess.TimeoutExpired:
        return 124


cases = [
    ("leaf variable after an absolute scratch dir",      'for t in a b; do bash x_$t.sh >/tmp/q-$t.log 2>&1; done', 0),
    ("leaf variable, braces",                            'bash x.sh >/tmp/q-${t}.log 2>&1',                        0),
    ("tee to a leaf variable",                           'bash x.sh 2>&1 | tee /tmp/qa-$t.log | tail -3',          0),
    ("literal scratch file (control)",                   'bash x.sh >/tmp/q.log 2>&1',                             0),
    ("variable in the directory part",                   'bash x.sh >/tmp/$d/q.log 2>&1',                          2),
    ("variable with a slash after it",                   'bash x.sh >/tmp/q-$t/sub.log 2>&1',                      2),
    ("variable first, no known directory",               'bash x.sh >$T/q.log 2>&1',                               2),
    ("leaf variable inside main",                        'bash x.sh >%s/docs/$f 2>&1' % MAIN,                      2),
    ("leaf variable under a dotdot directory",          'bash x.sh >/tmp/../%s/$f 2>&1' % MAIN.lstrip("/"),        2),
    ("command substitution in the name",                 'bash x.sh >/tmp/q-$(date).log 2>&1',                     2),
]
bad = 0
for name, cmd, want in cases:
    got = hook(cmd)
    ok = got == want
    bad += not ok
    print(("ok   " if ok else "FAIL ") + f"{name}: want {want}, got {got}")
shutil.rmtree(tmp, ignore_errors=True)
sys.exit(1 if bad else 0)
PY
