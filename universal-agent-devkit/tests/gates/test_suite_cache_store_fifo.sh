#!/usr/bin/env bash
# #355 / #371: một FIFO đặt tại file phụ của kho suite cache (learned_inputs.json, <khoá>.run, prune.stamp) không được làm
# bin/suite_cache.py treo: open() trần trên FIFO chặn mãi (gate TIMEOUT vô hạn, #353). Mỗi ca chạy trong một tiến trình con có hạn giờ
# cứng; treo = ĐỎ (không để chính test treo).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PY="$(python3 -c 'import sys; print(sys.executable)')"
exec "$PY" -I - "$DEVKIT_DIR/bin" <<'EOF'
import os, subprocess, sys, tempfile, shutil

BIN = sys.argv[1]
fails = 0
KEY = "a" * 64
CASES = {
    "learned_inputs.json": """
fifo = os.path.join(sc.store, "learned_inputs.json")
os.mkfifo(fifo)
assert sc.load_learned() == {}, "FIFO phải đọc như file rỗng"
""",
    "<khoá>.run": """
fifo = os.path.join(sc.store, KEY + ".run")
os.mkfifo(fifo)
os.utime(fifo, (1, 1))   # marker đã quá 10 s: coi như marker hỏng, bỏ đi và giành lại
with sc.inflight(KEY) as mode:
    assert mode == "run", mode
""",
    "sentinel_report.jsonl": """
fifo = os.path.join(sc.store, "sentinel_report.jsonl")
os.mkfifo(fifo)
msg = sc.contradiction(KEY, {"id": "REG-F", "command": "true"}, {"pass_n": 1, "head": None}, True)
assert msg, "contradiction vẫn phải trả câu báo dù không ghi được báo cáo"
""",
    "prune.stamp": """
fifo = os.path.join(sc.store, "prune.stamp")
os.mkfifo(fifo)
sc.prune(now=time.time() + 10 * suite_cache.PRUNE_EVERY_S)
""",
}
CHILD = """
import os, sys, subprocess, tempfile, time
sys.path.insert(0, %(bin)r)
import suite_cache
d = tempfile.mkdtemp(prefix="fifo-store-")
try:
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    for cmd in (["init", "-q", "."], ["config", "user.email", "t@t"], ["config", "user.name", "t"],
                ["config", "commit.gpgsign", "false"]):
        subprocess.run(["git", *cmd], cwd=d, env=env, check=True)
    open(os.path.join(d, "a.txt"), "w").write("x\\n")
    subprocess.run(["git", "add", "-A"], cwd=d, env=env, check=True)
    subprocess.run(["git", "commit", "-qm", "init"], cwd=d, env=env, check=True)
    sc = suite_cache.SuiteCache(d, [], None, {}, "x", 1, {})
    assert sc.store, "kho phải có đường dẫn"
    os.makedirs(sc.store, exist_ok=True)
    KEY = %(key)r
%(body)s
finally:
    import shutil; shutil.rmtree(d, ignore_errors=True)
print("OK")
"""
for name, body in CASES.items():
    body = "\n".join("    " + l for l in body.strip("\n").splitlines())
    code = CHILD % {"bin": BIN, "key": KEY, "body": body}
    p = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         start_new_session=True)
    try:
        out, _ = p.communicate(timeout=30)
        if p.returncode == 0 and "OK" in out:
            print("✔ FIFO ở %s: không treo, kho vẫn dùng được" % name)
        else:
            print("✖ FIFO ở %s: rc=%s %s" % (name, p.returncode, out.strip()[-300:])); fails += 1
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, 9); p.wait()
        print("✖ FIFO ở %s: TREO (quá 30 s)" % name); fails += 1
sys.exit(1 if fails else 0)
EOF
