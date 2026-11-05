#!/usr/bin/env bash
# Test hồi quy (#983): gate_speed_report.py đếm lượt mode=scoped (mặc định từ #661) và in chỉ số nghiệm thu duy nhất cho việc tối ưu
# gate: p90 total_wall_s (gồm steps.lock = chờ khoá) của lượt merge gate thật (project .merge-scratch-*), kèm p90 chờ khoá; có
# trong bảng --baseline. Dữ liệu giả, TZ cố định. Tương thích bash 3.2 và Python 3.9; chỉ stdlib.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$DEVKIT_DIR/scripts/governance/gate_speed_report.py"
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


def rec(hour, mode, verdict, wall, project, lock=0.0):
    return {"v": 1, "ts": "", "epoch": calendar.timegm((2026, 11, 2, hour - 7, 0, 0)), "project": project, "mode": mode,
            "source": "cli", "exit": 0 if verdict == "PASS" else 1, "verdict": verdict, "fp": "f%d" % hour,
            "exit_reason": verdict.lower(), "deferred": False, "busy": verdict == "BUSY", "reused_full_pass": False,
            "n_changed": 1, "n_docs": 0, "docs_only": False, "no_test_only": False, "suites": [["X", verdict, wall]],
            "suites_wall_s": wall, "force_full": False, "impacted_run": False, "total_wall_s": wall, "steps": {"lock": lock}}


def write(name, recs):
    p = os.path.join(TMP, name)
    with open(p, "w") as fh:
        for r in recs:
            fh.write(json.dumps(r) + "\n")
    return p


cur = [rec(9, "scoped", "PASS", 600, ".merge-scratch-a", lock=100), rec(10, "scoped", "FAIL", 900, ".merge-scratch-b", lock=300),
       rec(11, "scoped", "PASS", 2700, ".merge-scratch-c", lock=1200), rec(12, "scoped", "PASS", 1500, "lane-x"),
       rec(13, "impacted", "PASS", 50, "lane-y"), rec(14, "full", "PASS", 4000, ".train-scratch-z")]
base = [rec(9, "scoped", "PASS", 3000, ".merge-scratch-a", lock=2000), rec(10, "scoped", "PASS", 3100, ".merge-scratch-b")]
p_cur, p_base = write("cur.jsonl", cur), write("base.jsonl", base)
r = subprocess.run([sys.executable, "-I", SCRIPT, "--log", p_cur, "--baseline", p_base], capture_output=True, text=True)
out = r.stdout
chk(r.returncode == 0, "report exit 0", "rc=%s %s" % (r.returncode, r.stderr[-300:]))
chk("scoped: n=4 " in out, "lượt mode=scoped được đếm (n=4)", out[:600])
chk("merge gate (.merge-scratch-*): n=3 p50=900.0s p90=2700.0s lock_p90=1200.0s" in out,
    "p90 merge gate thật gồm chờ khoá, chỉ lượt .merge-scratch-*", out[:1200])
chk("| merge_gate_p90_s | 3100.0 | 2700.0 | -400.0 |" in out, "bảng --baseline có p90 merge gate", out[-1500:])
chk("| scoped_n | 2 | 4 | 2 |" in out, "bảng --baseline có số lượt scoped", out[-1500:])
print("ALL PASS" if not fails else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
PYEND
