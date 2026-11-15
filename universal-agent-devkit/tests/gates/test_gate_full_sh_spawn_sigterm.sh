#!/usr/bin/env bash
# CI macOS đỏ oan test_gate_full_sigterm_result 1e (PR #1170): SIGTERM đến khi gate_full.sh() đã spawn tiến trình con nhưng chưa vào
# khối try (runner chậm: con ghi ready-file trước khi cha chạy tiếp) ⇒ SystemExit bật ra từ Popen, không ai giết nhóm tiến trình con,
# agent-kit mồ côi. Ca này bắn SIGTERM vào chính tiến trình ngay sau khi Popen tạo con (cửa sổ đó, tất định) và đòi con chết.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 -B - "$DEVKIT_DIR/bin" <<'PY'
import os, signal, subprocess, sys, time
sys.path.insert(0, sys.argv[1])
import gate_full
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))   # = _on_sigterm của cmd_run
orig = subprocess.Popen.__init__
def popen_then_sigterm(self, *a, **k):
    orig(self, *a, **k)
    pids.append(self.pid)
    os.kill(os.getpid(), signal.SIGTERM)   # cha nhận SIGTERM ngay sau khi con đã chạy, trước khi sh() vào try
pids = []
subprocess.Popen.__init__ = popen_then_sigterm
rc = None
try:
    gate_full.sh(["sleep", "30"])
except SystemExit as e:
    rc = e.code
subprocess.Popen.__init__ = orig
pid = pids[0]
dead = False
for _ in range(60):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        dead = True; break
    time.sleep(0.05)
fails = 0
if rc == 143:
    print("✔ SIGTERM vẫn kết thúc sh() bằng SystemExit(143)")
else:
    fails += 1; print(f"✖ SIGTERM giữa lúc spawn không kết thúc sh() (rc={rc})")
if dead:
    print("✔ tiến trình con bị giết khi SIGTERM đến ngay sau spawn")
else:
    fails += 1; print(f"✖ tiến trình con {pid} mồ côi sau SIGTERM giữa lúc spawn")
    os.kill(pid, signal.SIGKILL)
sys.exit(1 if fails else 0)
PY
