#!/usr/bin/env bash
# Test hồi quy: scripts/governance/gate_speed_report.py đọc runs.jsonl của post-fix-gate (--log <file>) và in số đo tốc độ gate:
#   trung vị / p90 thời gian impacted tách cli và hook (bỏ BUSY, REUSED, deferred); số suite liệt kê và số suite thực chạy;
#   phân bố verdict theo mode, UNTESTED theo exit_reason; trạng thái suite (có TIMEOUT); tỉ lệ xanh lần đầu theo task (có trường task)
#   hoặc fp; --full mỗi ngày tách điểm gộp hợp lệ (.integrate-scratch-*, .merge-scratch-*, .train-scratch-*) và ngoài điểm gộp;
#   thống kê REG-DK-ALL-01; --since / --until theo ngày giờ địa phương; --baseline in bảng trước/sau.
# Dữ liệu giả, TZ cố định (Asia/Ho_Chi_Minh) để ngày không trôi theo máy.
#   RPT_KIT=<devkit dir>   thử bản kit khác (bản chưa có script: ĐỎ)
# Tương thích bash 3.2 và Python 3.9; chỉ stdlib.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${RPT_KIT:-$DEVKIT_DIR}"
SCRIPT="$KIT/scripts/governance/gate_speed_report.py"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
TZ=Asia/Ho_Chi_Minh python3 -I - "$SCRIPT" "$TMP" <<'PYEND'
import calendar, json, os, re, subprocess, sys

SCRIPT, TMP = sys.argv[1], sys.argv[2]
fails = 0


def chk(cond, good, why=""):
    global fails
    if cond:
        print("✔ " + good, flush=True)
    else:
        fails += 1
        print("✖ %s: %s" % (good, why), flush=True)


def at(day, hour):
    # giờ địa phương +07 của tháng 10/2026
    return calendar.timegm((2026, 10, day, hour - 7, 0, 0))


def rec(epoch, mode, source, verdict, wall, fp, project="w", reason=None, suites=(), task=None, narrowed=False):
    r = {"v": 1, "ts": "", "epoch": epoch, "project": project, "mode": mode, "source": source, "exit": 0 if verdict == "PASS" else 1,
         "verdict": verdict, "fp": fp, "exit_reason": reason or verdict.lower(), "deferred": False, "busy": verdict == "BUSY",
         "reused_full_pass": verdict == "REUSED", "n_changed": 1, "n_docs": 0, "docs_only": False, "no_test_only": False,
         "suites": [list(s) for s in suites], "suites_wall_s": wall, "force_full": False, "impacted_run": narrowed,
         "total_wall_s": wall, "steps": {}}
    if task:
        r["task"] = task
    return r


base = [
    rec(at(25, 9), "impacted", "cli", "PASS", 100, "A", narrowed=True, suites=[("X", "PASS", 10), ("Y", "UNTESTED", None)]),
    rec(at(25, 10), "impacted", "cli", "FAIL", 200, "B", suites=[("X", "FAIL", 20)]),
    rec(at(25, 11), "impacted", "cli", "PASS", 300, "B"),
    rec(at(25, 12), "impacted", "cli", "UNTESTED", 5, "C", reason="edited_test", suites=[("X", "UNTESTED", None)]),
    rec(at(25, 13), "impacted", "cli", "PASS", 400, "C"),
]
cur = base + [
    rec(at(25, 14), "impacted", "cli", "FAIL", 10, "F", task="T1"),
    rec(at(25, 15), "impacted", "cli", "PASS", 20, "G", task="T1"),
    rec(at(25, 9), "impacted", "hook", "BUSY", 1, "D"),
    rec(at(25, 10), "impacted", "hook", "PASS", 50, "D"),
    rec(at(25, 11), "impacted", "hook", "REUSED", 2, "E"),
    rec(at(25, 16), "full", "cli", "PASS", 1000, "H", project=".merge-scratch-ab",
        suites=[("REG-DK-ALL-01", "PASS", 600), ("Z", "PASS", 5)]),
    rec(at(25, 17), "full", "cli", "FAIL", 950, "I", project="issue-1-build", suites=[("REG-DK-ALL-01", "TIMEOUT", 900)]),
    rec(at(26, 9), "full", "cli", "PASS", 400, "J", project=".integrate-scratch-x", suites=[("REG-DK-ALL-01", "PASS", 300)]),
    rec(at(26, 10), "full", "cli", "PASS", 30, "K", project=".train-scratch-y", suites=[("REG-DK-ALL-01", "UNTESTED", None)]),
    rec(at(26, 11), "full", "cli", "BUSY", 1, "L", project="final-gate"),
]
cur_path, base_path = os.path.join(TMP, "cur.jsonl"), os.path.join(TMP, "base.jsonl")
with open(cur_path, "w") as f:
    f.write("".join(json.dumps(r) + "\n" for r in cur) + "not json\n")
with open(base_path, "w") as f:
    f.write("".join(json.dumps(r) + "\n" for r in base))


def run(*args):
    if not os.path.isfile(SCRIPT):
        return 127, "missing script " + SCRIPT
    p = subprocess.run([sys.executable, "-I", SCRIPT] + list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    return p.returncode, p.stdout.decode("utf-8", "replace")


rc, out = run("--log", cur_path)
print(out)
chk(rc == 0, "exit 0 trên log hợp lệ", "rc=%s" % rc)
for line, why in [
    ("impacted cli: n=7 p50=100.0s p90=400.0s", "cli: bỏ BUSY/REUSED, trung vị và p90 nearest-rank"),
    ("impacted hook: n=1 p50=50.0s p90=50.0s", "hook tách riêng, BUSY và REUSED không tính"),
    ("suites impacted: listed=4 ran=2", "suite liệt kê và suite có số giây"),
    ("suites full: listed=5 ran=4", "suite của --full"),
    ("verdict impacted: BUSY=1 FAIL=2 PASS=5 REUSED=1 UNTESTED=1", "phân bố verdict impacted"),
    ("verdict full: BUSY=1 FAIL=1 PASS=3", "phân bố verdict full"),
    ("untested reasons impacted: edited_test=1", "UNTESTED theo lý do"),
    ("suite status: FAIL=1 PASS=4 TIMEOUT=1 UNTESTED=3", "trạng thái suite có TIMEOUT"),
    ("first green impacted (key=task|fp): 2/5 = 40.0%", "xanh lần đầu: task gộp F+G, BUSY bỏ qua, chỉ REUSED không tính"),
    ("full 2026-10-25: merge_point=1 outside=1", "--full ngày 25 tách điểm gộp"),
    ("full 2026-10-26: merge_point=2 outside=1", "--full ngày 26: integrate + train hợp lệ, final-gate ngoài"),
    ("REG-DK-ALL-01: n=4 PASS=2 FAIL=0 TIMEOUT=1 UNTESTED=1 other=0 p50=600.0s p90=900.0s", "thống kê ALL-01"),
    ("impacted narrowed (impacted_run): 1/8", "lượt impacted có suite chạy lệnh thu hẹp (BUSY/REUSED không tính)"),
    ("ignored lines: 1", "dòng hỏng bị bỏ và đếm"),
]:
    chk(line in out.splitlines(), why, "thiếu dòng %r" % line)

rc, out = run("--log", cur_path, "--since", "2026-10-26")
chk(rc == 0 and "full 2026-10-25" not in out and "full 2026-10-26: merge_point=2 outside=1" in out
    and "REG-DK-ALL-01: n=2 PASS=1 FAIL=0 TIMEOUT=0 UNTESTED=1 other=0 p50=300.0s p90=300.0s" in out, "--since lọc theo ngày địa phương", out)
rc, out = run("--log", cur_path, "--until", "2026-10-25")
chk(rc == 0 and "full 2026-10-26" not in out and "REG-DK-ALL-01: n=2 PASS=1 FAIL=0 TIMEOUT=1 UNTESTED=0 other=0 p50=750.0s p90=900.0s" in out,
    "--until gồm cả ngày cuối", out)

rc, out = run("--log", cur_path, "--baseline", base_path)
chk(rc == 0 and re.search(r"^\| impacted_cli_p50_s \| 200\.0 \| 100\.0 \| -100\.0 \|$", out, re.M) is not None,
    "--baseline in bảng trước/sau với delta", out)
chk(re.search(r"^\| first_green_pct \| 33\.3 \| 40\.0 \| 6\.7 \|$", out, re.M) is not None, "bảng có tỉ lệ xanh lần đầu", out)
# OCR 27/10: số lượt thu hẹp so theo tỉ lệ (hai cửa sổ khác số lượt): baseline 1/5, current 1/8
chk(re.search(r"^\| impacted_narrowed_pct \| 20\.0 \| 12\.5 \| -7\.5 \|$", out, re.M) is not None, "bảng so tỉ lệ thu hẹp, không so số đếm", out)

rc, out = run("--log", os.path.join(TMP, "nope.jsonl"))
chk(rc != 0 and "nope.jsonl" in out, "log không có thì exit khác 0 và nêu tên file", out)
rc, out = run("--log", cur_path, "--since", "26/10")
chk(rc == 2, "--since sai định dạng: lỗi tham số", "rc=%s" % rc)

# review 27/10: --log hỏng thì lỗi nêu đúng --log (không đổ cho --baseline), lỗi ra stderr, stdout rỗng
if os.path.isfile(SCRIPT):
    p = subprocess.run([sys.executable, "-I", SCRIPT, "--log", TMP, "--baseline", os.path.join(TMP, "missing-base.jsonl")],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    err = p.stderr.decode("utf-8", "replace")
    chk(p.returncode != 0 and ("cannot read %s:" % TMP) in err and "missing-base" not in err and not p.stdout.strip(),
        "--log hỏng: lỗi nêu đúng --log, ra stderr", "rc=%s out=%r err=%r" % (p.returncode, p.stdout, err))
    # chiều ngược lại: --log tốt, --baseline hỏng thì lỗi nêu --baseline
    bad_base = os.path.join(TMP, "missing-base.jsonl")
    p = subprocess.run([sys.executable, "-I", SCRIPT, "--log", cur_path, "--baseline", bad_base],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    err = p.stderr.decode("utf-8", "replace")
    chk(p.returncode != 0 and ("cannot read %s:" % bad_base) in err and not p.stdout.strip(),
        "--baseline hỏng: lỗi nêu đúng --baseline, stdout rỗng", "rc=%s out=%r err=%r" % (p.returncode, p.stdout[:200], err))
else:
    chk(False, "--log hỏng: lỗi nêu đúng --log, ra stderr", "missing script")

# review 27/10: bản ghi không có task lẫn fp không gộp chung một nhóm xanh lần đầu; bản ghi không có thời gian không tính là 0 s
odd = [rec(at(25, 9), "impacted", "cli", "FAIL", 100, None), rec(at(25, 10), "impacted", "cli", "PASS", 300, None),
       rec(at(25, 11), "impacted", "cli", "PASS", 200, "Q")]
for r in odd[:2]:
    del r["fp"]
del odd[2]["total_wall_s"], odd[2]["suites_wall_s"]
odd_path = os.path.join(TMP, "odd.jsonl")
with open(odd_path, "w") as f:
    f.write("".join(json.dumps(r) + "\n" for r in odd))
rc, out = run("--log", odd_path)
chk("first green impacted (key=task|fp): 1/1 = 100.0%" in out.splitlines() and "first green skipped (no task/fp): 2" in out.splitlines(),
    "không task/fp: không gộp nhóm, đếm riêng", out)
chk("impacted cli: n=2 p50=200.0s p90=300.0s" in out.splitlines(), "bản ghi không có thời gian không tính là 0 s", out)

print("%s: %d lỗi" % ("FAIL" if fails else "PASS", fails))
sys.exit(1 if fails else 0)
PYEND
