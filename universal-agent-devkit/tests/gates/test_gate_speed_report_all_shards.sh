#!/usr/bin/env bash
# Test hồi quy #651: scripts/governance/gate_speed_report.py gộp nhóm ALL (dòng "REG-DK-ALL-01: ...") theo từng lượt:
#   lượt có REG-DK-ALL-01 (số liệu cũ, cả lượt chuyển tiếp còn chạy song song 3 shard) dùng riêng REG-DK-ALL-01;
#   lượt chỉ có shard REG-DK-ALL-GATES-01 / -WORKTREE-01 / -REST-01 thì cộng số giây các shard, trạng thái là trạng thái xấu nhất;
#   REG-DK-ALL-SHARD-RULES-616-01 (test của quy tắc shard) không thuộc nhóm.
# Trước #651 script so cứng "REG-DK-ALL-01" nên lượt chỉ có shard ra n=0 và bị tính "without REG-DK-ALL-01".
# Dữ liệu giả, TZ cố định (Asia/Ho_Chi_Minh). Tương thích bash 3.2 và Python 3.9; chỉ stdlib.
#   RPT_KIT=<devkit dir>   thử bản kit khác
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${RPT_KIT:-$DEVKIT_DIR}"
SCRIPT="$KIT/scripts/governance/gate_speed_report.py"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
TZ=Asia/Ho_Chi_Minh python3 -I - "$SCRIPT" "$TMP" <<'PYEND'
import calendar, json, os, subprocess, sys

SCRIPT, TMP = sys.argv[1], sys.argv[2]
fails = 0


def chk(cond, good, why=""):
    global fails
    if cond:
        print("✔ " + good, flush=True)
    else:
        fails += 1
        print("✖ %s: %s" % (good, why), flush=True)


def at(hour):
    return calendar.timegm((2026, 10, 29, hour - 7, 0, 0))


def rec(epoch, mode, verdict, wall, suites):
    return {"v": 1, "ts": "", "epoch": epoch, "project": "w", "mode": mode, "source": "cli", "exit": 0 if verdict == "PASS" else 1,
            "verdict": verdict, "fp": "f%d" % epoch, "exit_reason": verdict.lower(), "deferred": False, "busy": False,
            "reused_full_pass": False, "n_changed": 1, "n_docs": 0, "docs_only": False, "no_test_only": False,
            "suites": [list(s) for s in suites], "suites_wall_s": wall, "force_full": False, "impacted_run": False,
            "total_wall_s": wall, "steps": {}}


G, W, R, RULES = "REG-DK-ALL-GATES-01", "REG-DK-ALL-WORKTREE-01", "REG-DK-ALL-REST-01", "REG-DK-ALL-SHARD-RULES-616-01"
runs = [
    # số liệu cũ: chỉ REG-DK-ALL-01
    rec(at(9), "full", "PASS", 700, [("REG-DK-ALL-01", "PASS", 600)]),
    # sau #650: chỉ 3 shard, cộng 100+200+400 = 700; một shard FAIL thì nhóm FAIL; RULES không thuộc nhóm
    rec(at(10), "full", "FAIL", 800, [(G, "PASS", 100), (W, "PASS", 200), (R, "FAIL", 400), (RULES, "PASS", 7)]),
    # lượt chuyển tiếp (#646..#650): REG-DK-ALL-01 cùng 3 shard, dùng riêng REG-DK-ALL-01 để không đếm hai lần
    rec(at(11), "full", "FAIL", 1000, [("REG-DK-ALL-01", "TIMEOUT", 900), (G, "PASS", 50), (W, "PASS", 50), (R, "PASS", 50)]),
    # impacted: shard chạy một phần (10+20 = 30 s), một shard không có số giây -> nhóm UNTESTED, lượt "with"
    rec(at(12), "impacted", "PASS", 300, [(G, "PASS", 10), (W, "UNTESTED", None), (R, "PASS", 20)]),
    # impacted: chỉ RULES và X có số giây -> lượt "without", không có nhóm ALL
    rec(at(13), "impacted", "PASS", 100, [("X", "PASS", 10), (RULES, "PASS", 5)]),
    # impacted: 3 shard đều không có số giây -> nhóm UNTESTED không số giây, lượt "without"
    rec(at(14), "impacted", "PASS", 50, [(G, "UNTESTED", None), (W, "UNTESTED", None), (R, "UNTESTED", None), ("X", "PASS", 5)]),
]
log = os.path.join(TMP, "runs.jsonl")
with open(log, "w") as f:
    f.write("".join(json.dumps(r) + "\n" for r in runs))

if not os.path.isfile(SCRIPT):
    rc, out = 127, "missing script " + SCRIPT
else:
    p = subprocess.run([sys.executable, "-I", SCRIPT, "--log", log], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    rc, out = p.returncode, p.stdout.decode("utf-8", "replace")
print(out)
lines = out.splitlines()
chk(rc == 0, "exit 0", "rc=%s" % rc)
for line, why in [
    # 5 lượt có nhóm ALL; số giây [30, 600, 700, 900]: p50 = 650, p90 nearest rank = 900 (đếm từng shard sẽ ra n=11)
    ("REG-DK-ALL-01: n=5 PASS=1 FAIL=1 TIMEOUT=1 UNTESTED=2 other=0 p50=650.0s p90=900.0s",
     "nhóm ALL gộp -01 cũ và 3 shard theo lượt, cộng số giây shard, lượt chuyển tiếp chỉ tính -01"),
    ("impacted without REG-DK-ALL-01 (impacted, not BUSY/REUSED/deferred, >=1 suite with seconds, REG-DK-ALL-01 without seconds): "
     "n=2 p50=75.0s; with REG-DK-ALL-01: n=1 p50=300.0s", "lượt impacted có shard chạy tính là with, RULES không tính"),
]:
    chk(line in lines, why, "thiếu dòng %r" % line)
chk(any(l.startswith("note: REG-DK-ALL-01 = ") for l in lines), "in rõ nhóm ALL gồm những suite nào", out)

print("%s: %d lỗi" % ("FAIL" if fails else "PASS", fails))
sys.exit(1 if fails else 0)
PYEND
