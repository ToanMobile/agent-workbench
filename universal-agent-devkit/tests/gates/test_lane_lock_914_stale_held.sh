#!/usr/bin/env bash
# Test hồi quy (#914 mục 4): lane_lock P5 không nhả slot lane vì marker .held của hậu duệ đã chết.
#   a. hậu duệ ở trạng thái zombie (ps stat Z) có marker .held ⇒ pool_waiting trả None (slot flock đã nhả theo tiến trình chết)
#   b. PID tái dụng: tiến trình hiện có bắt đầu SAU mtime marker (lstart > mtime) ⇒ marker là của tiến trình cũ ⇒ None
#   c. đối chứng: hậu duệ sống, bắt đầu trước mtime marker ⇒ vẫn nhả (trả (pid, nhãn))
# ps giả qua subprocess.run (không tiến trình thật): xác định, bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"

python3 - "$DEVKIT_DIR" <<'PY'
import os, shutil, subprocess, sys, tempfile, time
devkit = sys.argv[1]
sys.path.insert(0, os.path.join(devkit, "bin"))
slot = tempfile.mkdtemp(prefix="dk-914-held-")
os.environ["SB_HEAVY_SLOT_DIR"] = slot
import lane_lock as ll
fails = 0
def check(name, cond, detail=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond else f" — {detail}"))
    fails += 0 if cond else 1

def lstart(epoch):
    return time.strftime("%a %b %e %H:%M:%S %Y", time.localtime(epoch))

def fake_ps(rows):
    """rows: (pid, ppid, stat, start_epoch); hỗ trợ cả định dạng cũ (pid, ppid) lẫn mới (pid, ppid, stat, lstart…)."""
    def run(cmd, **kw):
        fmt = cmd[-1]
        lines = []
        for pid, ppid, stat, st in rows:
            if "stat" in fmt:
                lines.append(f"{pid} {ppid} {stat} {lstart(st)}")
            else:
                lines.append(f"{pid} {ppid}")
        return subprocess.CompletedProcess(cmd, 0, "\n".join(lines) + "\n", "")
    return run

now = time.time()
spawned = now - 100
marker = os.path.join(slot, "gate-1.lock.held")

def put_marker(pid, mtime):
    with open(marker, "w") as f:
        f.write(str(pid))
    os.utime(marker, (mtime, mtime))

def hit(rows, pid, mtime):
    put_marker(pid, mtime)
    ll.subprocess.run = fake_ps(rows)
    tree = ll._descendants(400)
    return ll.pool_waiting(400, spawned, tree)

# a. zombie
r = hit([(400, 1, "S", now - 200), (500, 400, "Z", now - 90)], 500, now - 50)
check("a. hậu duệ zombie có .held ⇒ không nhả", r is None, f"được {r}")
# b. PID tái dụng: tiến trình bắt đầu sau marker
r = hit([(400, 1, "S", now - 200), (501, 400, "S", now - 10)], 501, now - 50)
check("b. tiến trình bắt đầu sau mtime marker (PID tái dụng) ⇒ không nhả", r is None, f"được {r}")
# c. đối chứng
r = hit([(400, 1, "S", now - 200), (502, 400, "S", now - 90)], 502, now - 50)
check("c. hậu duệ sống bắt đầu trước marker ⇒ vẫn nhả", r is not None and r[0] == 502, f"được {r}")
shutil.rmtree(slot, ignore_errors=True)
sys.exit(1 if fails else 0)
PY
rc=$?
if [ "$rc" = 0 ]; then echo "PASS test_lane_lock_914_stale_held"; exit 0; fi
echo "FAIL test_lane_lock_914_stale_held"
exit 1
