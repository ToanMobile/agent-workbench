#!/usr/bin/env bash
# Test hồi quy (T0052): bin/capacity.py là NGUỒN DUY NHẤT của mọi giới hạn song song (ngưỡng tải, số job test, nhóm suite của gate,
# suite nặng, gate cùng lúc, worker super-board, lane song song) — tính từ số lõi × hệ số DEVKIT_CAPACITY, co lại khi tải cao.
# Hai ngưỡng tải: hold_load (8 × lõi, 12 lõi: 96) — việc BẮT BUỘC (suite của gate, verify của merge gate) chờ trên mức này (người dùng
# 20/10: "dưới 100 thì cho chạy"); busy_load (3 × lõi, 12 lõi: 36) — chỉ để mở thêm việc TÙY CHỌN (worker build thêm của super-board).
#   1. bảng giá trị ở load 0, hệ số 1, cho 1/4/8/12/13/64 lõi (số viết tay, không suy lại từ công thức);
#   2. free_fraction đơn điệu, trong [0.25, 1], không chia 0 với hệ số {0.25, 1/3, 0.5, 1, 2, 4} × tải {0, lõi, hold, 10·hold};
#   3. tải cao thu gate_parallel lại tới 1/4 (có sàn) dần tới hold_load — gate là việc bắt buộc, không co ở busy_load 36 khi máy
#      chạy 45–100 cả ngày; test_jobs KHÔNG co theo tải (người dùng 23/10: máy bận thì chờ trước khi chạy,
#      không thu số test DevKit — pool nhỏ đi giành ít CPU hơn các phiên khác, REG-DK-ALL-01 dễ chạm 900 s);
#   4. DEVKIT_CAPACITY rác (rỗng, chữ, nan, inf, ≤ 0) = hệ số 1; giá trị ngoài [0.25, 4] bị kẹp;
#   5. DEVKIT_CAPACITY_CORES rác = số CPU tiến trình được dùng (os.process_cpu_count → sched_getaffinity → os.cpu_count);
#      DEVKIT_CAPACITY_LOAD rác = tải thật;
#   6. CLI: `load` in số thực hoặc chuỗi rỗng (exit 0), `--json` đủ khoá và mọi số đếm là int ≥ 1, khoá lạ exit 2.
# Chưa có bin/capacity.py thì ĐỎ. Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CAP="$DEVKIT_DIR/bin/capacity.py"
python3 -I - "$CAP" <<'PY'
import contextlib, io, json, math, os, subprocess, sys

CAP = sys.argv[1]
fails = 0


def chk(cond, name, why=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond or not why else " — " + str(why)), flush=True)
    if not cond:
        fails += 1


if not os.path.isfile(CAP):
    print("✖ không có bin/capacity.py: chưa có nguồn sức chứa chung", flush=True)
    sys.exit(1)

# môi trường gốc không mang nút của người gọi: mỗi ca tự đặt biến của nó
BASE = {k: v for k, v in os.environ.items() if not k.startswith("DEVKIT_CAPACITY")}


def cli(*args, **env):
    e = dict(BASE)
    e.update(env)
    r = subprocess.run([sys.executable, CAP] + list(args), capture_output=True, text=True, env=e, timeout=30)
    return r.returncode, r.stdout, r.stderr


COUNT_KEYS = ("busy_load", "hold_load", "test_jobs", "gate_parallel", "heavy_max", "gate_max", "build_workers", "lane_workers",
              "lane_slots_max")

# 1. bảng ở load 0, hệ số 1 (tính tay từ plan T0052 v3)
TABLE = {
    "busy_load":      {1: 3, 4: 12, 8: 24, 12: 36, 13: 39, 64: 192},
    "hold_load":      {1: 8, 4: 32, 8: 64, 12: 96, 13: 104, 64: 512},
    "test_jobs":      {1: 4, 4: 5, 8: 10, 12: 16, 13: 17, 64: 85},
    "gate_parallel":  {1: 2, 4: 2, 8: 4, 12: 6, 13: 6, 64: 32},
    "heavy_max":      {1: 1, 4: 1, 8: 2, 12: 3, 13: 3, 64: 16},
    "gate_max":       {1: 1, 4: 2, 8: 4, 12: 6, 13: 6, 64: 32},
    "build_workers":  {1: 1, 4: 3, 8: 6, 12: 10, 13: 10, 64: 53},
    "lane_workers":   {1: 1, 4: 1, 8: 2, 12: 3, 13: 3, 64: 16},
    "lane_slots_max": {1: 1, 4: 1, 8: 2, 12: 4, 13: 4, 64: 21},
}
for c in (1, 4, 8, 12, 13, 64):
    rc, out, err = cli("--json", DEVKIT_CAPACITY_CORES=str(c), DEVKIT_CAPACITY_LOAD="0")
    try:
        got = json.loads(out)
    except ValueError:
        got = {}
    bad = ["%s=%r(muốn %d)" % (k, got.get(k), TABLE[k][c]) for k in COUNT_KEYS if got.get(k) != TABLE[k][c]]
    chk(rc == 0 and not bad, "1. %d lõi, load 0: mọi khoá đúng bảng" % c, "rc=%s %s %s" % (rc, bad, err[-200:]))
rc, out, err = cli("busy_load", DEVKIT_CAPACITY_CORES="12", DEVKIT_CAPACITY_LOAD="0")
chk(rc == 0 and out.strip() == "36", "1b. CLI một khoá: `capacity.py busy_load` trên 12 lõi in 36", "rc=%s out=%r" % (rc, out))
rc, out, err = cli("test_jobs", DEVKIT_CAPACITY_CORES="08", DEVKIT_CAPACITY_LOAD="0")
chk(rc == 0 and out.strip() == "10", "1c. DEVKIT_CAPACITY_CORES=08 đọc là 8 (không bát phân): test_jobs 10", "rc=%s out=%r" % (rc, out))

# nạp module trong tiến trình để thử free_fraction và các ca lỗi
for k in list(os.environ):
    if k.startswith("DEVKIT_CAPACITY"):
        del os.environ[k]
sys.path.insert(0, os.path.dirname(CAP))
import capacity  # noqa: E402

# 2. free_fraction đơn điệu, không lỗi, trong [0.25, 1]
problems = []
for c in (1, 4, 12, 64):
    for s in (0.25, 1.0 / 3, 0.5, 1.0, 2.0, 4.0):
        hold = capacity.hold_load(c, s)
        loads = (0.0, float(c), float(hold), 10.0 * hold)
        try:
            fr = [capacity.free_fraction(c, s, l) for l in loads]
        except Exception as exc:   # ca test: báo lỗi chứ không dừng cả test
            problems.append("c=%d s=%.3f ném %r" % (c, s, exc))
            continue
        if any(not (0.25 <= f <= 1.0) for f in fr) or any(a < b for a, b in zip(fr, fr[1:])):
            problems.append("c=%d s=%.3f %s" % (c, s, fr))
        if fr[0] != 1.0 or fr[-1] != 0.25:
            problems.append("c=%d s=%.3f đầu/cuối %s" % (c, s, fr))
        for key in COUNT_KEYS:
            for l in loads:
                v = getattr(capacity, key)(c, s, l) if key in ("test_jobs", "gate_parallel") else getattr(capacity, key)(c, s)
                if type(v) is not int or v < 1:
                    problems.append("c=%d s=%.3f %s=%r" % (c, s, key, v))
chk(not problems, "2. free_fraction đơn điệu trong [0.25, 1], mọi khoá là int ≥ 1 trên 4 cỡ máy × 6 hệ số × 4 mức tải", problems[:4])
chk(capacity.free_fraction(12, 1.0, None) == 1.0, "2b. không đọc được tải (None): không co (1.0)")

# 3. tải cao thu gate_parallel lại tới 1/4, có sàn (12 lõi: low 12, hold 96); test_jobs giữ theo lõi ở mọi mức tải
cases = ((0.0, 16, 6), (12.0, 16, 6), (24.0, 16, 5), (36.0, 16, 4), (60.0, 16, 3), (90.0, 16, 2), (400.0, 16, 2))
bad = []
for l, tj, gp in cases:
    got = (capacity.test_jobs(12, 1.0, l), capacity.gate_parallel(12, 1.0, l))
    if got != (tj, gp):
        bad.append("load %g -> %s (muốn %s)" % (l, got, (tj, gp)))
chk(not bad, "3. 12 lõi: tải 0/12/24/36/60/90/400 -> test_jobs 16 (không co), gate_parallel 6/6/5/4/3/2/2", bad)
rc, out, err = cli("test_jobs", DEVKIT_CAPACITY_CORES="12", DEVKIT_CAPACITY_LOAD="24")
chk(rc == 0 and out.strip() == "16", "3b. CLI: 12 lõi tải 24 -> test_jobs vẫn 16 (máy bận thì chờ, không thu số job)", "rc=%s out=%r" % (rc, out))
rc, out, err = cli("gate_parallel", DEVKIT_CAPACITY_CORES="12", DEVKIT_CAPACITY_LOAD="24")
chk(rc == 0 and out.strip() == "5", "3c. CLI đọc DEVKIT_CAPACITY_LOAD: 12 lõi tải 24 -> gate_parallel 5", "rc=%s out=%r" % (rc, out))

# 4. DEVKIT_CAPACITY rác = hệ số 1; ngoài [0.25, 4] bị kẹp
bad = []
for junk in ("", "abc", "nan", "inf", "-inf", "-1", "0", "1e999"):
    rc, out, err = cli("busy_load", DEVKIT_CAPACITY=junk, DEVKIT_CAPACITY_CORES="12", DEVKIT_CAPACITY_LOAD="0")
    if rc != 0 or out.strip() != "36":
        bad.append("%r -> rc=%s %r" % (junk, rc, out + err[-120:]))
chk(not bad, "4. DEVKIT_CAPACITY rác (rỗng, chữ, nan, inf, ≤ 0, tràn) = hệ số 1: busy_load 36 trên 12 lõi", bad)
for val, key, want in (("2", "busy_load", "72"), ("2", "build_workers", "20"), ("100", "busy_load", "144"),
                       ("0.1", "busy_load", "9"), ("0.1", "build_workers", "2"), ("0.5", "test_jobs", "8")):
    rc, out, err = cli(key, DEVKIT_CAPACITY=val, DEVKIT_CAPACITY_CORES="12", DEVKIT_CAPACITY_LOAD="0")
    chk(rc == 0 and out.strip() == want, "4b. DEVKIT_CAPACITY=%s: %s = %s trên 12 lõi" % (val, key, want), "rc=%s out=%r" % (rc, out))

# 5. DEVKIT_CAPACITY_CORES / DEVKIT_CAPACITY_LOAD rác: bỏ nguồn đó, dùng số CPU tiến trình được dùng
if hasattr(os, "process_cpu_count"):
    real = os.process_cpu_count()
elif hasattr(os, "sched_getaffinity"):
    real = len(os.sched_getaffinity(0))
else:
    real = os.cpu_count()
real = real or 4
for junk in ("abc", "0", "-3", "1.5", "", "9" * 400):
    rc, out, err = cli("cores", DEVKIT_CAPACITY_CORES=junk, DEVKIT_CAPACITY_LOAD="0")
    chk(rc == 0 and out.strip() == str(real), "5. DEVKIT_CAPACITY_CORES=%r bị bỏ: dùng số CPU của tiến trình (%d)" % (junk[:8], real),
        "rc=%s out=%r err=%r" % (rc, out, err[-200:]))
# 5c. thứ tự nguồn số lõi: process_cpu_count (3.13+, theo affinity / cgroup) → sched_getaffinity → cpu_count (cả máy) → 4
_MISSING = object()
_saved = {n: getattr(os, n, _MISSING) for n in ("process_cpu_count", "sched_getaffinity", "cpu_count")}


def _set(name, value):
    if value is _MISSING:
        if hasattr(os, name):
            delattr(os, name)
    else:
        setattr(os, name, value)


try:
    _set("process_cpu_count", lambda: 3); _set("sched_getaffinity", lambda pid: {0, 1}); _set("cpu_count", lambda: 7)
    got_a = capacity.cores()
    _set("process_cpu_count", lambda: None)
    got_b = capacity.cores()
    _set("process_cpu_count", _MISSING)
    got_c = capacity.cores()
    _set("sched_getaffinity", _MISSING)
    got_d = capacity.cores()
    _set("cpu_count", lambda: None)
    got_e = capacity.cores()
finally:
    for n, v in _saved.items():
        _set(n, v)
chk((got_a, got_b, got_c, got_d, got_e) == (3, 2, 2, 7, 4),
    "5c. số lõi = CPU tiến trình được dùng: process_cpu_count 3 > affinity 2 > cpu_count 7 > 4", (got_a, got_b, got_c, got_d, got_e))
rc, out, err = cli("load", DEVKIT_CAPACITY_LOAD="abc")
chk(rc == 0 and "Traceback" not in err, "5b. DEVKIT_CAPACITY_LOAD rác: không lỗi, đọc tải thật", "rc=%s err=%r" % (rc, err[-200:]))

# 6. CLI
rc, out, err = cli("load", DEVKIT_CAPACITY_LOAD="2.5")
chk(rc == 0 and out.strip() == "2.5", "6. `capacity.py load` in tải (2.5)", "rc=%s out=%r" % (rc, out))
for key, env, want in (("cores", {"DEVKIT_CAPACITY_CORES": "12"}, "12"), ("scale", {"DEVKIT_CAPACITY": "2"}, "2.0"),
                       ("free_fraction", {"DEVKIT_CAPACITY_CORES": "12", "DEVKIT_CAPACITY_LOAD": "24"}, "0.8928571428571429"),
                       ("hold_load", {"DEVKIT_CAPACITY_CORES": "12"}, "96")):
    rc, out, err = cli(key, **env)
    chk(rc == 0 and out.strip() == want, "6a. `capacity.py %s` in %s" % (key, want), "rc=%s out=%r err=%r" % (rc, out, err[-200:]))
saved = os.getloadavg


def _no_load():
    raise OSError("không có getloadavg")


os.getloadavg = _no_load
try:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = capacity.main(["load"])
    chk(code == 0 and buf.getvalue() == "\n" and capacity.load() is None,
        "6b. không đọc được tải: `load` in chuỗi rỗng, exit 0", "code=%r out=%r" % (code, buf.getvalue()))
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = capacity.main(["--json"])
    d = json.loads(buf.getvalue())
    chk(code == 0 and d.get("load") is None and d.get("test_jobs", 0) >= 4,
        "6c. không đọc được tải: --json có load null và vẫn đủ số", buf.getvalue()[:200])
finally:
    os.getloadavg = saved
rc, out, err = cli("--json", DEVKIT_CAPACITY_CORES="12", DEVKIT_CAPACITY_LOAD="3")
try:
    d = json.loads(out)
except ValueError:
    d = {}
miss = [k for k in COUNT_KEYS + ("cores", "scale", "load", "free_fraction") if k not in d]
notint = [k for k in COUNT_KEYS if type(d.get(k)) is not int or d.get(k) < 1]
chk(rc == 0 and not miss and not notint and d.get("load") == 3.0 and d.get("cores") == 12,
    "6d. --json hợp lệ, đủ mọi khoá, mọi số đếm là int ≥ 1, load là số thực", "rc=%s thiếu=%s không-int=%s %r" % (rc, miss, notint, out[:200]))
for args in (["bogus"], [], ["busy_load", "extra"]):
    rc, out, err = cli(*args)
    chk(rc == 2 and "Traceback" not in err and out == "", "6e. khoá lạ / thiếu khoá / thừa đối số %s: exit 2, stdout rỗng" % args,
        "rc=%s out=%r err=%r" % (rc, out, err[-200:]))

print(("❌ test_capacity: %d lỗi" % fails) if fails else "✅ test_capacity: tất cả PASS", flush=True)
sys.exit(1 if fails else 0)
PY
