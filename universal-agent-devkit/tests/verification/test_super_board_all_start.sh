#!/usr/bin/env bash
# Test: super_board_all.py start (scripts/governance) — #1001. Three repos in a temp dir, fake super-board-run.sh in each:
# (a) current-worker.log is a dangling symlink (HvU 05/11: link to a deleted runs/…/worker-review-48.log) → treated as absent,
# (b) a later repo still starts after one repo's start raises, (c) a live current-worker.log symlink is left pointing at its
# target, (d) the launched runner is in its own session, not the caller's process group (a Claude Bash call hung on it).
# No real runner is started: REPOS, get_running_pids and ensure_claude_workspace_trust are replaced. Bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

SB_HEAVY_SLOT_DIR="$TMP/locks" python3 - "$DEVKIT_DIR/scripts/governance/super_board_all.py" "$TMP" <<'PY'
import importlib.util, os, sys, time
script, tmp = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("super_board_all_under_test", script)
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
fails = 0
def check(cond, label, detail=""):
    global fails
    print(("✔ " if cond else "✖ ") + label + ("" if cond else " " + str(detail)))
    fails += 0 if cond else 1

def repo(slug):
    d = os.path.join(tmp, slug)
    os.makedirs(os.path.join(d, ".claude", "bin"))
    os.makedirs(os.path.join(d, "docs", "super-board"))
    run = os.path.join(d, ".claude", "bin", "super-board-run.sh")
    with open(run, "w") as f:   # records its process group and session, then exits
        f.write('#!/bin/sh\npython3 -c "import os;print(os.getpgid(0), os.getsid(0))" > "%s/started.tmp" && mv "%s/started.tmp" "%s/started"\n' % (d, d, d))
    os.chmod(run, 0o755)
    return {"slug": slug, "name": slug, "dir": d, "url": "-"}

dangling, broken, live = repo("zz-dangling"), repo("zz-broken"), repo("zz-live")
wl = lambda r: os.path.join(r["dir"], "docs", "super-board", "current-worker.log")
os.symlink(os.path.join(dangling["dir"], "docs", "super-board", "runs", "gone", "worker-review-48.log"), wl(dangling))
target = os.path.join(live["dir"], "docs", "super-board", "real-worker.log")
with open(target, "w") as f:
    f.write("keep me\n")
os.symlink(target, wl(live))

b.REPOS = [dangling, broken, live]
b.get_running_pids = lambda slug: []
b.ensure_claude_workspace_trust = lambda *a, **k: None
real_clear = b.clear_early_deaths
def clear(rdir):
    if rdir == broken["dir"]:
        raise PermissionError("simulated failure in " + rdir)
    real_clear(rdir)
b.clear_early_deaths = clear

try:
    b.start_all()
    raised = None
except Exception as exc:   # the RED case: one repo's error aborts the whole loop
    raised = exc
check(raised is None, "start_all survives a dangling log symlink and a failing repo", repr(raised))

def wait(path, secs=10):
    end = time.time() + secs
    while time.time() < end and not os.path.exists(path):
        time.sleep(0.1)
    return os.path.exists(path)

check(wait(os.path.join(dangling["dir"], "started")), "the repo with a dangling current-worker.log is started")
check(os.path.isfile(wl(dangling)) and not os.path.islink(wl(dangling)), "  … its dangling symlink is replaced by a plain file")
check(wait(os.path.join(live["dir"], "started")), "a repo after a failing one is still started")
check(not os.path.exists(os.path.join(broken["dir"], "started")), "  … the failing repo itself is not started")
check(os.path.islink(wl(live)) and os.readlink(wl(live)) == target and open(target).read() == "keep me\n",
      "a live current-worker.log symlink keeps its target and content")
if os.path.exists(os.path.join(live["dir"], "started")):
    pgid, sid = (int(x) for x in open(os.path.join(live["dir"], "started")).read().split())
    check(pgid != os.getpgid(0), "the runner is not in the caller's process group", (pgid, os.getpgid(0)))
    check(sid != os.getsid(0), "the runner is in its own session", (sid, os.getsid(0)))
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" = 0 ] && echo "PASS: super_board_all start" || echo "FAIL: super_board_all start (rc=$rc)"
exit "$rc"
