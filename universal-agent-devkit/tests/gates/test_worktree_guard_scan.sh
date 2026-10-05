#!/usr/bin/env bash
# Speed + equivalence test for the transcript scan in hooks/worktree_guard.sh (devkit-speed plan, item 1a).
#
# The guard's fast path decides "did this session call EnterWorktree?" with `tail -c +N transcript | grep -qE <call regex>`,
# cached per transcript in <project>/.claude/audit-gate/wg_scan/. The FIRST call for a transcript scans all of it: 2.3 s at
# 88 MB, on the first tool call of every resumed session. BSD `tail -c +N` copies byte by byte (that is the slow part);
# `dd bs=65536` reads the same bytes at disk speed and `grep -aF EnterWorktree` hands the very same `grep -E` only the lines
# that hold the literal. dd starts at the 64 KB block holding the offset, so up to 64 KB BEFORE it are scanned too. Checked
# here on synthetic transcripts:
#  1. the cache the hook writes ("<size> <linked>") equals the verdict of the old pipeline (run here as the reference) for
#     many shapes: no call, name only in tool lists / escaped schema text, compact call, spaced/tab/CR variants, call on the
#     last line without a newline, a cache that says "already linked", and the states a real cache produces (a call that
#     arrives after the cached offset, a record cut mid-write at it). The scan is `dd` + `grep`: no `tail`, no python (the
#     guard's own decision python starts only when a call was found);
#  2. a cold scan of an 80 MB transcript: no `tail` (the byte-by-byte copy), and at least 2x faster than the reference
#     pipeline on the same machine;
#  3. the verdict still drives the decision: with a worker that entered a worktree, an Edit of the MAIN checkout is blocked,
#     without the call it is not;
#  4. the hook runs python with the PROJECT as its cwd: a mmap.py / re.py / os.py there (or on PYTHONPATH) must not change
#     the decision (rc 2 for a worker that entered a worktree, as before) — the scan runs no python at all;
#  5. an ARTIFICIAL cache ("no call" over a call that sits up to 64 KB before the offset) is the one place the verdict can
#     differ from the old pipeline: the scan finds the call the old one missed (stricter: the guard blocks, rc 2, where the
#     old scan let the write through).
#   WG_HOOK=<path>  run the same checks against another copy of the hook (e.g. the pristine one: RED).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${WG_HOOK:-$DEVKIT_DIR/hooks/worktree_guard.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
echo "hook: $HOOK"

python3 - "$HOOK" "$TMP" <<'PY'
import json, os, shutil, subprocess, sys, time

hook, tmp = sys.argv[1:3]
PY3, GIT = shutil.which("python3"), shutil.which("git")
RX = '"name":[[:space:]]*"EnterWorktree"[[:space:]]*,[[:space:]]*"input"'
env0 = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") and k != "DEVKIT_WORKTREE"}
env0.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")

main = os.path.join(tmp, "main")
os.makedirs(os.path.join(main, "src"))
subprocess.run([GIT, "init", "-q", main], env=env0, check=True)
open(os.path.join(main, "src", "a.kt"), "w").write("x\n")
subprocess.run([GIT, "-C", main, "add", "-A"], env=env0, check=True)
subprocess.run([GIT, "-C", main, "commit", "-qm", "i"], env=env0, check=True)
wt = os.path.join(tmp, "wt")
subprocess.run([GIT, "-C", main, "worktree", "add", "-q", "--detach", wt], env=env0, check=True)
cache_dir = os.path.join(main, ".claude", "audit-gate", "wg_scan")

STUBS = os.path.join(tmp, "stubs"); os.makedirs(STUBS)
CALLS = os.path.join(tmp, "calls.log")
for _name in ("python3", "tail", "dd"):
    with open(os.path.join(STUBS, _name), "w") as f:
        f.write(f'#!/bin/sh\necho {_name} >> "{CALLS}"\nexec "{shutil.which(_name)}" "$@"\n')
    os.chmod(os.path.join(STUBS, _name), 0o755)

def rec(**kw):
    return json.dumps(kw, separators=(",", ":"))
PAD = "p" * 900
def pad_line(i):
    return rec(type="assistant", cwd=main, message={"role": "assistant", "content": [{"type": "text", "text": PAD + str(i)}]})
CALL = rec(type="assistant", cwd=main, message={"role": "assistant", "content": [
    {"type": "tool_use", "id": "toolu_1", "name": "EnterWorktree", "input": {"path": wt}}]})
RESULT = rec(type="user", cwd=main, message={"role": "user", "content": [
    {"type": "tool_result", "tool_use_id": "toolu_1", "content": "Switched to worktree " + wt}]}, toolUseResult="Switched to worktree " + wt)
NAME_ONLY = [
    rec(type="user", cwd=main, message={"role": "user", "content": "tools: Bash, EnterWorktree, ExitWorktree"}),
    rec(type="user", cwd=main, message={"role": "user", "content": '{"name":"EnterWorktree","input":{}} as schema text'}),   # escaped quotes
    '{"type":"system","tools":["Bash","EnterWorktree"]}',
    '"EnterWorktree"',
    'EnterWorktree",  "input"',
]

def gen(path, lines_before, extra=(), lines_after=0, first_cwd=main, trailing_newline=True):
    with open(path, "w") as f:
        f.write(rec(type="user", cwd=first_cwd, message={"role": "user", "content": "hi"}) + "\n")
        for i in range(lines_before):
            f.write(pad_line(i) + "\n")
        for j, e in enumerate(extra):
            last = j == len(extra) - 1 and lines_after == 0 and not trailing_newline
            f.write(e if last else e + "\n")
        for i in range(lines_after):
            f.write(pad_line(i) + "\n")

def reference(path, frm):
    """The pipeline the hook used before: verdict for the bytes from offset `frm`."""
    r = subprocess.run(["bash", "-c", f'tail -c +{frm + 1} "$1" 2>/dev/null | grep -qE \'{RX}\'', "ref", path])
    return 1 if r.returncode == 0 else 0

def hook_run(tp, cache=None, tool="Bash", file_path=None, stubs=False, cwd=None, env_extra=None):
    shutil.rmtree(os.path.join(main, ".claude"), ignore_errors=True)
    if cache is not None:
        os.makedirs(cache_dir)
        open(os.path.join(cache_dir, tp.replace("/", "_")), "w").write(cache)
    inp = {"command": "ls"} if tool == "Bash" else {"file_path": file_path or os.path.join(main, "src", "a.kt")}
    d = {"session_id": "s", "transcript_path": tp, "cwd": main, "hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": inp}
    env = dict(env0); env["CLAUDE_PROJECT_DIR"] = main
    env.update(env_extra or {})
    if stubs:
        env["PATH"] = STUBS + os.pathsep + env["PATH"]
        open(CALLS, "w").close()
    t = time.perf_counter()
    r = subprocess.run(["bash", hook], input=json.dumps(d).encode(), capture_output=True, env=env, cwd=cwd or tmp)
    dt = time.perf_counter() - t
    cp = os.path.join(cache_dir, tp.replace("/", "_"))
    c = open(cp).read().split() if os.path.exists(cp) else None
    log = open(CALLS).read().split() if stubs else []
    calls = {n: log.count(n) for n in ("python3", "tail", "dd")}
    return r.returncode, r.stdout.decode(errors="replace"), r.stderr.decode(errors="replace"), c, dt, calls

fails = 0
def report(ok, msg):
    global fails
    if not ok:
        fails += 1
    print(("✔ " if ok else "✖ ") + msg)

# ── 1. verdict equality (≈ 3 MB each) and the commands the scan runs ──
def scan_commands_ok(calls, want):
    """dd + grep, never the byte-by-byte `tail`; python only for the guard's own decision when a call was found."""
    return calls["tail"] == 0 and calls["dd"] == 1 and calls["python3"] == want
variants = {
    "no EnterWorktree at all": ([], 3000),
    "name only in tool lists / escaped schema text": (NAME_ONLY, 3000),
    "compact call near the end": ([CALL, RESULT], 3000),
    "call right after the first record": ([CALL, RESULT], 0),
    'spaced call ("name": "EnterWorktree", "input")': ([CALL.replace('"name":"EnterWorktree","input"', '"name": "EnterWorktree", "input"'), RESULT], 3000),
    "tab / CR whitespace inside the call": (['{"type":"assistant","x":{"name":\t"EnterWorktree"\r,\t"input":{}}}'], 3000),
    "call split by a newline (not a call)": (['{"name":"EnterWorktree",', '"input":{}}'], 3000),
    "name and input on different keys order (not a call)": (['{"input":{},"name":"EnterWorktree"}'], 3000),
    "call on the last line without a newline": ([CALL], 3000),
}
for name, (extra, n) in variants.items():
    tp = os.path.join(tmp, "t_%d.jsonl" % abs(hash(name)))
    gen(tp, n, extra, lines_after=0 if name == "call on the last line without a newline" else (3000 if n == 0 else 200),
        trailing_newline=name != "call on the last line without a newline")
    size = os.path.getsize(tp)
    want = reference(tp, 0)
    rc, out, err, cache, dt, calls = hook_run(tp, stubs=True)
    ok = cache == [str(size), str(want)] and rc == 0 and out == "" and err == "" and scan_commands_ok(calls, want)
    report(ok, f"cold scan, {name}: reference linked={want}, hook cache={cache}, rc={rc}, commands={calls}")
    os.remove(tp)

tp = os.path.join(tmp, "small.jsonl")
gen(tp, 50, [CALL, RESULT], lines_after=5)
rc, out, err, cache, dt, calls = hook_run(tp, stubs=True)
report(cache == [str(os.path.getsize(tp)), "1"] and scan_commands_ok(calls, 1), f"small transcript with a call: cache={cache}, commands={calls}")
gen(tp, 50, NAME_ONLY, lines_after=5)
rc, out, err, cache, dt, calls = hook_run(tp, stubs=True)
report(cache == [str(os.path.getsize(tp)), "0"] and scan_commands_ok(calls, 0), f"small transcript without a call: cache={cache}, commands={calls}")

# ── incremental scans: the cache holds the size at the last scan; the next scan starts 4 KB before it ──
def head(path, extra_lines=()):
    gen(path, 3000, extra_lines, lines_after=0)
# (a) the states a real cache produces: the previous scan saw the file up to S1 with no call
tp = os.path.join(tmp, "inc_a.jsonl")
head(tp); s1 = os.path.getsize(tp)
with open(tp, "a") as f:
    f.write(CALL + "\n" + RESULT + "\n")
size = os.path.getsize(tp)
want = reference(tp, s1 - 4096)
rc, out, err, cache, dt, calls = hook_run(tp, cache=f"{s1} 0\n")
report(want == 1 and cache == [str(size), "1"] and rc == 0, f"incremental, a call arrives after the cached offset: reference linked={want}, hook cache={cache}")
# (b) the previous scan ran while the record was half written (cut 40 bytes into the call line)
tp = os.path.join(tmp, "inc_b.jsonl")
head(tp)
with open(tp, "a") as f:
    f.write(CALL[:40])
s1 = os.path.getsize(tp)
with open(tp, "a") as f:
    f.write(CALL[40:] + "\n" + RESULT + "\n")
size = os.path.getsize(tp)
want = reference(tp, s1 - 4096)
rc, out, err, cache, dt, calls = hook_run(tp, cache=f"{s1} 0\n")
report(want == 1 and cache == [str(size), "1"] and rc == 0, f"incremental, record cut mid-write at the cached offset: reference linked={want}, hook cache={cache}")
# (c) cache far before the call, no call before it; cache at 0; already linked; a file shorter than its cache
tp = os.path.join(tmp, "inc_c.jsonl")
gen(tp, 3000, [CALL, RESULT], lines_after=200)
size = os.path.getsize(tp)
call_at = open(tp, "rb").read().index(b'"name":"EnterWorktree","input"')
for label, off, seen in (("cache at 0", 0, 0), ("cache far before the call", call_at - 600000, 0), ("cache says linked already", size - 10, 1)):
    want = 1 if seen == 1 else reference(tp, max(off - 4096, 0))
    rc, out, err, cache, dt, calls = hook_run(tp, cache=f"{off} {seen}\n")
    expect = [str(off), "1"] if seen == 1 else [str(size), str(want)]      # "already linked" scans nothing, cache untouched
    report(cache == expect and rc == 0, f"incremental, {label}: reference linked={want}, hook cache={cache}")
tp2 = os.path.join(tmp, "shrunk.jsonl")
gen(tp2, 3000, [CALL, RESULT], lines_after=200)
rc, out, err, cache, dt, calls = hook_run(tp2, cache=f"{os.path.getsize(tp2) + 5000000} 1\n")
report(cache == [str(os.path.getsize(tp2)), "1"], f"a transcript shorter than its cache is scanned again from 0: cache={cache}")

# ── 2. speed: cold scan of 80 MB with no call ──
big = os.path.join(tmp, "big.jsonl")
gen(big, 82000, NAME_ONLY * 20, lines_after=100)
bsize = os.path.getsize(big)
t = time.perf_counter(); want = reference(big, 0); t_ref = time.perf_counter() - t
rc, out, err, cache, dt, calls = hook_run(big, stubs=True)
bound = max(0.5, t_ref / 2)       # generous: the suite may share the machine with others; the command count above is the exact bound
report(cache == [str(bsize), str(want)], f"80 MB cold scan verdict: reference {want}, hook cache={cache}")
report(scan_commands_ok(calls, 0), f"80 MB cold scan runs dd + grep, no tail, no python: {calls}")
report(dt < bound, f"80 MB cold scan: hook {dt:.2f} s vs old pipeline {t_ref:.2f} s (must be under {bound:.2f} s)")
gen(big, 82000, [CALL, RESULT], lines_after=100)
t = time.perf_counter(); want = reference(big, 0); t_ref = time.perf_counter() - t
rc, out, err, cache, dt, calls = hook_run(big)
report(cache == [str(os.path.getsize(big)), str(want)] and want == 1, f"80 MB transcript with a call: reference {want}, hook cache={cache}")

# ── 3. the verdict still drives the decision ──
main_file = os.path.join(main, "src", "a.kt")
tp = os.path.join(tmp, "enter.jsonl")
gen(tp, 3000, [CALL, RESULT], lines_after=50)
rc, out, err, cache, dt, calls = hook_run(tp, tool="Edit", file_path=main_file)
report(rc == 2 and "WORKTREE GUARD" in err, f"big transcript with EnterWorktree: Edit of the MAIN checkout blocked (rc={rc})")
rc, out, err, cache, dt, calls = hook_run(tp, tool="Edit", file_path=os.path.join(wt, "src", "a.kt"))
report(rc == 0, f"  … an Edit inside the worktree is allowed (rc={rc})")
gen(tp, 3000, NAME_ONLY, lines_after=50)
rc, out, err, cache, dt, calls = hook_run(tp, tool="Edit", file_path=main_file)
report(rc == 0, f"big transcript that only names the tool: Edit of the main checkout allowed (rc={rc})")

# ── 4. cwd modules: the project dir is on python's path; the scan must not depend on it (it runs no python) ──
def shadow_dir(name, mods):
    d = os.path.join(tmp, name); os.makedirs(d)
    for m in mods:
        with open(os.path.join(d, m + ".py"), "w") as f:
            f.write(f'open({os.path.join(tmp, "shadow_ran_" + m)!r}, "w").write("x")\nraise SystemExit(0)\n')
    return d
def ran(mods):
    return [m for m in mods if os.path.exists(os.path.join(tmp, "shadow_ran_" + m))]
tp = os.path.join(tmp, "shadowed.jsonl")
gen(tp, 3000, [CALL, RESULT], lines_after=50)
sd = shadow_dir("shadowA", ["mmap"])
rc, out, err, cache, dt, calls = hook_run(tp, tool="Edit", file_path=main_file, cwd=sd)
report(ran(["mmap"]) == [] and cache == [str(os.path.getsize(tp)), "1"] and rc == 2,
       f"a mmap.py in the hook's cwd changes nothing: call seen, main checkout guarded (rc={rc}, as the old pipeline: 2), cache={cache}, ran={ran(['mmap'])}")
rc, out, err, cache, dt, calls = hook_run(tp, tool="Edit", file_path=main_file, env_extra={"PYTHONPATH": sd})
report(ran(["mmap"]) == [] and cache == [str(os.path.getsize(tp)), "1"] and rc == 2, f"  … nor one on PYTHONPATH (rc={rc}, cache={cache}, ran={ran(['mmap'])})")
gen(tp, 3000, NAME_ONLY, lines_after=50)
mods = ["re", "os", "json", "shlex"]
sd = shadow_dir("shadowB", mods)
rc, out, err, cache, dt, calls = hook_run(tp, tool="Edit", file_path=main_file, cwd=sd, stubs=True)
report(ran(mods) == [] and cache == [str(os.path.getsize(tp)), "0"] and rc == 0 and calls["python3"] == 0,
       f"re.py / os.py / json.py / shlex.py in the hook's cwd: nothing runs them (ran={ran(mods)}, cache={cache}, rc={rc}, python starts={calls['python3']})")

# ── 5. an artificial cache: "no call" over a call that sits before the offset (a real cache cannot say that) ──
# dd starts at the 64 KB block holding the offset, so a call in that block, up to 64 KB before it, is found where
# `tail -c +N` (exactly 4 KB before the offset) would miss it: stricter (rc 2 where the old scan gave 0), never looser.
tp = os.path.join(tmp, "artificial.jsonl")
for n_pad in range(3000, 3100):
    gen(tp, n_pad, [CALL, RESULT], lines_after=300)
    c = open(tp, "rb").read().index(b'"name":"EnterWorktree","input"')
    frm = c + len(CALL) + 200
    if (frm // 65536) * 65536 <= c - 1000:
        break
rc, out, err, cache, dt, calls = hook_run(tp, tool="Edit", file_path=main_file, cache=f"{frm + 4096} 0\n")
old_v = reference(tp, frm)
new_v = int(cache[1]) if cache and len(cache) == 2 else -1
report(old_v == 0 and new_v == 1 and rc == 2,
       f"artificial cache over a call 1 KB inside the block before the offset: old pipeline misses it ({old_v}), the scan finds it ({new_v}), main checkout guarded (rc={rc})")

print()
print(f"{fails} failed")
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" -eq 0 ] && echo "✅ test_worktree_guard_scan: all passed" || echo "❌ test_worktree_guard_scan: failed"
exit "$rc"
