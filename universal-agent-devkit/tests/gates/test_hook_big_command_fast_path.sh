#!/usr/bin/env bash
# hooks/block-dangerous-git.sh + hooks/hardware_safety_gate.sh: a BIG command must be decided fast (review 15/10, found by a second reviewer).
# fast_allow stripped the JSON escape marks with ${c//\\/}, which is quadratic on macOS /bin/bash 3.2.57: a 20 KB multi-line command
# (every newline is a \n in the payload) took 14-18 s in each guard, and the hardware gate's PreToolUse hook has "timeout": 10 in
# .claude/settings.json, templates/claude_settings.json and hooks/hooks.json (the git guard sets none there). A hook killed at its timeout
# is no verdict, so a big command could pass both guards by being slow. The hardware gate had a second quadratic: rm_hits. Each case runs the real hook under /bin/bash (3.2 on macOS) with a
# hard kill (subprocess timeout) at BOUND seconds; the verdicts are the ones the fast path and the parser gave all along: a benign big
# command passes, and a dangerous line hidden after 20 KB of harmless text is still blocked (by the hook that owns it). Payload JSON only:
# no command is ever run.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
BOUND="${BIG_COMMAND_BOUND_S:-3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
[ -x /bin/bash ] || { echo "skip: no /bin/bash"; exit 0; }
unset HARDWARE_SAFETY_GATE HARDWARE_OVERRIDE DEVKIT_ALLOW_BRANCH CDPATH
P="$TMP/work/proj"
mkdir -p "$P"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/a.txt" && git -C "$P" add -A && git -C "$P" commit -qm init

python3 -I - "$GG" "$HW" "$P" "$TMP" "$BOUND" <<'PY'
import concurrent.futures as cf
import json
import os
import subprocess
import sys
import time

gg, hw, proj, tmp, bound = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5])
ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
ENV.update(CLAUDE_PROJECT_DIR=proj, XDG_CONFIG_HOME=os.path.join(tmp, "xdg"), ADB_DENY_SERIALS="", ADB_ALLOW_SERIALS="", ANDROID_SERIAL="")
HOOK = {"git": gg, "hw": hw}


def lines(n):
    out, size, i = [], 0, 0
    while size < n:
        out.append("echo line %d of the harmless text" % i)
        size += len(out[-1]) + 1
        i += 1
    return "\n".join(out)


def quoted(n):   # many quotes: the quote replacements of the fast path are quadratic too
    out, size, i = [], 0, 0
    while size < n:
        out.append("echo \"a%d\" 'b%d' \"c\" 'd'" % (i, i))
        size += len(out[-1]) + 1
        i += 1
    return "\n".join(out)


def rms(n):   # a cleanup script: many rm words (rm_hits walked every word after each rm: quadratic, 56 KB of them took 20 s)
    out, size, i = [], 0, 0
    while size < n:
        out.append("rm -f x%d" % i)
        size += len(out[-1]) + 1
        i += 1
    return "\n".join(out)


def builds(n):   # rm -rf of build outputs: the gate asks git (a subprocess) about each target
    out, size, i = [], 0, 0
    while size < n:
        out.append("rm -rf build/x%d" % i)
        size += len(out[-1]) + 1
        i += 1
    return "\n".join(out)


N = 20000
L, Q, R, B = lines(N), quoted(N), rms(50000), builds(50000)
# 200 KB of lines that all start with a tool word the gate knows, and 300 KB of them on ONE line (no separator: no pattern can stop early):
# the patterns of the hardware gate re-scan the line for every word (30 s and more here). Past its 7 s watchdog a guard refuses with a reason.
BIG_DD = "\n".join("dd if=a of=b%d" % i for i in range(200000 // 18))
NOSEP = "dd if=a of=b " * (300000 // 14)
# (name, command, git guard rc, hardware gate rc, slow ok): a rc is one int or a tuple of ints. slow ok: the time-limit refusal (rc 2 with
# "thời hạn" in the reason) is also a verdict. The others run under BOUND seconds, the hook limit being 10 s: decided, with the right rc.
CASES = [
    ("multi-line echo", L, 0, 0, False),
    ("quotes everywhere", Q, 0, 0, False),
    ("heredoc written to notes", "cat > notes.md <<'EOF'\n" + L + "\nEOF", 0, 0, False),
    ("heredoc body that only mentions the danger", "cat > notes.md <<'EOF'\n" + L + "\ngit reset --hard\nrm -rf ~\nEOF", 0, 0, False),
    ("git danger after 20 KB", L + "\ngit reset --hard", 2, 0, False),
    ("rm danger after 20 KB", L + "\nrm -rf ~", 0, 2, False),
    ("git danger after 20 KB of quotes", Q + "\ngit reset --hard", 2, 0, False),
    ("rm danger after 20 KB of quotes", Q + "\nrm -rf ~", 0, 2, False),
    ("many rm words", R, 0, 0, False),
    ("rm danger after many rm words", R + "\nrm -rf ~", 0, 2, False),
    ("git danger after many rm words", R + "\ngit reset --hard", 2, 0, False),
    ("git danger after a heredoc", "cat > notes.md <<'EOF'\n" + L + "\nEOF\ngit reset --hard", 2, 0, False),
    ("rm danger after a heredoc", "cat > notes.md <<'EOF'\n" + L + "\nEOF\nrm -rf ~", 0, 2, False),
    ("rm -rf of build outputs, one git call each", B, 0, (0, 2), True),
    ("100 KB of dd lines", "\n".join("dd if=a of=b%d" % i for i in range(100000 // 18)), 0, (0, 2), True),
    ("200 KB of dd lines", BIG_DD, 0, (0, 2), True),
    ("300 KB of dd words on one line", NOSEP, 0, 2, True),
]
EXTREME = 9   # seconds: the hook limit is 10, the watchdog 7


def run(job):
    hook, name, cmd, limit = job
    payload = json.dumps({"session_id": "s", "transcript_path": "", "cwd": proj, "hook_event_name": "PreToolUse",
                          "tool_name": "Bash", "tool_input": {"command": cmd, "description": "d"}})
    t = time.perf_counter()
    try:   # the hard kill: a hook that is still running at the limit is no verdict
        p = subprocess.run(["/bin/bash", HOOK[hook]], input=payload, capture_output=True, text=True, errors="replace", cwd=proj,
                           env=ENV, timeout=limit)
        return time.perf_counter() - t, p.returncode, p.stderr
    except subprocess.TimeoutExpired:
        return time.perf_counter() - t, "KILLED", ""


jobs = [(h, name, cmd, EXTREME if slow else bound) for name, cmd, _g, _w, slow in CASES for h in ("git", "hw")]
with cf.ThreadPoolExecutor(6) as ex:
    results = list(ex.map(run, jobs))
fails = 0
for (hook, name, cmd, limit), (dt, rc, err) in zip(jobs, results):
    _n, _c, g, w, slow = next(c for c in CASES if c[0] == name)
    want = g if hook == "git" else w
    want = want if isinstance(want, tuple) else (want,)
    ok = (rc in want or (slow and rc == 2 and "thời hạn" in err)) and "lỗi nội bộ" not in err
    fails += not ok
    print(("✔ " if ok else "✖ ") + f"{hook} {len(cmd) // 1000} KB {name}: rc {rc} (want {want}) in {dt:.2f}s (limit {limit:g}s)")
print(f"{len(jobs)} runs, {fails} failed")
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS (rc $rc)"; exit 1; }
