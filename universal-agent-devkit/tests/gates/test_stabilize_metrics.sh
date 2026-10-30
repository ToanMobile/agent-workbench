#!/usr/bin/env bash
# Regression test: scripts/governance/stabilize_metrics.py đo độ ổn định gate từ runs.jsonl (plan ổn định #686).
# Mỗi chỉ số có một bộ dữ liệu giả riêng, tính tay, kiểm số CHÍNH XÁC qua --json:
#   rerun_on_red (cùng project + fp + mode ngay sau lượt đỏ; BUSY trong suốt; flaky bị loại; ocr-* và repo khác bị lọc),
#   busy_pct (trường busy; exit4_pct kèm), machine_hours (+ full nặng >= 40 suite, loại BUSY), false_red_pct,
#   merge_gate_s (median/p90 nội suy), scoped_escalated_pct, suites_per_run, load_median (CSV sampler + cửa sổ thời gian),
#   khử trùng khi một dòng nằm ở nhiều file, mặc định đọc runs.jsonl + archive/runs-*.jsonl của common dir git,
#   chỉ đọc (sha256 file đầu vào không đổi).
#   SM_SCRIPT=<file>  thử bản khác của script (chưa có script: ĐỎ; bản mutant: phải đỏ)
#   SM_PY=<python>    trình thông dịch (mặc định python3)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${SM_SCRIPT:-$DEVKIT_DIR/scripts/governance/stabilize_metrics.py}"
PYBIN="${SM_PY:-python3}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
"$PYBIN" -I - "$SCRIPT" "$TMP" <<'PYEND'
import hashlib, json, os, subprocess, sys

SCRIPT, TMP = sys.argv[1], sys.argv[2]
PY = sys.executable
fails = 0
BASE = 1793233651   # một epoch thật của mốc A


def chk(cond, good, why=""):
    global fails
    if cond:
        print("✔ " + good, flush=True)
    else:
        fails += 1
        print("✖ %s: %s" % (good, why), flush=True)
    return bool(cond)


def row(n, project="agent-workbench", **kw):
    r = {"v": 1, "epoch": BASE + n, "ts": "t%d" % n, "project": project, "mode": "full", "source": "cli", "exit": 0,
         "verdict": "PASS", "fp": "fp%d" % n, "exit_reason": "pass", "busy": False, "merge_point": False,
         "force_full": False, "force_reason": "", "suites": [], "suites_reused": 0, "ran_suites": [], "total_wall_s": 10.0}
    r.update(kw)
    if r["exit"] == 1:
        r["verdict"], r["exit_reason"] = "FAIL", "fail"
    if r["exit"] == 4:
        r["verdict"], r["exit_reason"], r["busy"] = "BUSY", "busy", True
    return r


def write(name, rows, raw_extra=""):
    path = os.path.join(TMP, name)
    with open(path, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
        fh.write(raw_extra)
    return path


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def run(*args, cwd=None):
    p = subprocess.run([PY, "-I", SCRIPT] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=cwd, timeout=120)
    return p.returncode, p.stdout.decode(), p.stderr.decode()


def metrics(*args, cwd=None):
    rc, out, err = run(*(list(args) + ["--json"]), cwd=cwd)
    if rc != 0:
        return None, "rc=%s err=%s" % (rc, err[-300:])
    try:
        return json.loads(out), ""
    except ValueError as exc:
        return None, "JSON hỏng: %s" % exc


def S(i):
    return [["s%d" % k, "PASS", 1.0] for k in range(i)]


print("python %s, script %s" % (sys.version.split()[0], SCRIPT), flush=True)
if not chk(os.path.isfile(SCRIPT), "script tồn tại", SCRIPT):
    sys.exit(1)

# ── rerun_on_red ─────────────────────────────────────────────────────────────
rr = [
    row(1, fp="F1", exit=1, total_wall_s=100),                    # đỏ
    row(2, fp="F1", exit=1, total_wall_s=200),                    # chạy lại sau đỏ (cli)        -> 1
    row(3, fp="F1", exit=0, total_wall_s=300),                    # chạy lại sau đỏ (cli)        -> 2
    row(4, fp="F2", exit=1, mode="impacted", source="hook", total_wall_s=10),
    row(5, fp="F3", exit=0, mode="impacted", source="hook"),      # fp khác xen giữa: không tính
    row(6, fp="F2", exit=0, mode="impacted", source="hook"),      # prev (F3) xanh: không tính
    row(7, fp="F4", exit=1),
    row(8, fp="F4", exit=1, force_reason="flaky: thử lại"),       # flaky: loại
    row(9, fp="F5", exit=1, source="cli"),
    row(10, fp="F5", exit=4, source="cli"),                        # BUSY trong suốt
    row(11, fp="F5", exit=0, source="hook", total_wall_s=50),      # sau đỏ qua BUSY (hook)       -> 3
    row(12, fp="F6", exit=1, mode="impacted"),
    row(13, fp="F6", exit=1, mode="full"),                         # cùng fp nhưng khác mode: không tính
    row(14, project="agent-workbench-b", fp="F1", exit=0),          # project khác: không tính
    row(20, project="ocr-9", fp="O1", exit=1),
    row(21, project="ocr-9", fp="O1", exit=0),                      # ocr-*: bị loại mặc định
    row(30, project="foo", fp="X1", exit=1),
    row(31, project="foo", fp="X1", exit=0),                        # repo khác: chỉ tính khi không có --repo-prefix
]
p = write("rr.jsonl", rr)
m, why = metrics(p, "--repo-prefix", "agent-workbench")
if chk(m is not None, "rerun: chạy với --repo-prefix", why):
    r = m["metrics"]["rerun_on_red"]
    chk(r["count"] == 3, "rerun_on_red.count == 3", r)
    chk(abs(r["hours"] - 550 / 3600.0) < 0.006, "rerun_on_red.hours == 0.15", r["hours"])
    chk(r["by_source"].get("cli", {}).get("count") == 2 and r["by_source"].get("hook", {}).get("count") == 1, "tách theo source cli 2 / hook 1", r["by_source"])
    chk(r["excluded_flaky"] == 1, "lượt flaky bị loại và đếm riêng", r)
    chk(r["by_prev_exit_reason"].get("fail", {}).get("count") == 3, "tách theo exit_reason lượt đỏ trước", r["by_prev_exit_reason"])
    chk(m["meta"]["rows"] == 14, "meta.rows == 14 (ocr-9 và foo bị lọc, agent-workbench-b vào)", m["meta"])
m, why = metrics(p)
if chk(m is not None, "rerun: không prefix", why):
    chk(m["metrics"]["rerun_on_red"]["count"] == 4, "không prefix: foo vào, ocr-9 vẫn bị loại => 4", m["metrics"]["rerun_on_red"])
m, why = metrics(p, "--include-ocr")
if chk(m is not None, "rerun: --include-ocr", why):
    chk(m["metrics"]["rerun_on_red"]["count"] == 5, "--include-ocr => 5", m["metrics"]["rerun_on_red"])
m, why = metrics(p, "--repo-prefix", "agent-workbench", "--since", str(BASE + 3), "--until", str(BASE + 11))
if chk(m is not None, "rerun: cửa sổ --since/--until epoch", why):
    chk(m["metrics"]["rerun_on_red"]["count"] == 1, "cửa sổ [3,11]: r3 mất lượt đỏ trước, chỉ còn r11 => 1", m["metrics"]["rerun_on_red"])
m, why = metrics(p, "--repo-prefix", "agent-workbench", "--since", "2026-10-29T00:00:00+00:00", "--until", "2026-10-30T23:59:59Z")
if chk(m is not None, "rerun: --since/--until dạng ISO", why):
    chk(m["metrics"]["rerun_on_red"]["count"] == 3, "ISO bao trùm cả file => 3", m["metrics"]["rerun_on_red"])
sha_before = sha(p)
run(p)
chk(sha(p) == sha_before, "chỉ đọc: sha256 file đầu vào không đổi")

# ── busy ─────────────────────────────────────────────────────────────────────
bz = [row(i, exit=4) for i in (1, 2, 3)] + [row(4, exit=2, verdict="UNTESTED", exit_reason="edited_test", busy=True)] + [row(i) for i in range(5, 11)]
m, why = metrics(write("busy.jsonl", bz))
if chk(m is not None, "busy: chạy", why):
    b = m["metrics"]["busy"]
    chk(b["busy_pct"] == 40.0 and b["busy_flag"] == 4, "busy_pct == 40.0 (4/10 trường busy)", b)
    chk(b["exit4_pct"] == 30.0 and b["exit4"] == 3, "exit4_pct == 30.0 (3/10)", b)

# ── machine_hours ────────────────────────────────────────────────────────────
mh = [
    row(1, total_wall_s=3600, suites=S(40)),                              # full nặng
    row(2, total_wall_s=1800, suites=S(10)),                              # full nhẹ
    row(3, total_wall_s=1800, mode="impacted", source="hook", suites=S(45)),   # không phải full
    row(4, total_wall_s=900, exit=4, suites=S(45)),                       # BUSY: không tính là nặng
]
m, why = metrics(write("mh.jsonl", mh))
if chk(m is not None, "machine_hours: chạy", why):
    h = m["metrics"]["machine_hours"]
    chk(h["total_hours"] == 2.25, "total_hours == 2.25", h)
    chk(h["heavy_full_hours"] == 1.0 and h["heavy_full_runs"] == 1, "heavy_full 1 lượt / 1.0 h", h)
    chk(h["heavy_full_share_pct"] == 44.4, "heavy_full_share_pct == 44.4", h)

# ── false_red ────────────────────────────────────────────────────────────────
ab = [["a", "PASS", 1.0], ["b", "PASS", 1.0]]
abc = ab + [["c", "PASS", 1.0]]
fr = [
    row(1, fp="A", exit=1, suites=ab), row(2, fp="A", exit=0, suites=ab),      # đỏ giả
    row(3, fp="B", exit=1, suites=ab), row(4, fp="B", exit=0, suites=abc),     # tập suite đổi: không tính
    row(5, fp="C", exit=0, suites=ab), row(6, fp="C", exit=1, suites=ab),      # PASS đến TRƯỚC FAIL: không tính
    row(7, fp="D", exit=1, suites=ab),                                          # không bao giờ xanh
]
m, why = metrics(write("fr.jsonl", fr))
if chk(m is not None, "false_red: chạy", why):
    f = m["metrics"]["false_red"]
    chk(f["fail_runs"] == 4 and f["false_red"] == 1 and f["false_red_pct"] == 25.0, "1/4 FAIL là đỏ giả => 25.0", f)

# ── merge_gate_s ─────────────────────────────────────────────────────────────
mg = [row(1, merge_point=True, total_wall_s=100), row(2, merge_point=True, total_wall_s=200),
      row(3, merge_point=True, total_wall_s=400, exit=1), row(4, total_wall_s=9999)]
m, why = metrics(write("mg.jsonl", mg))
if chk(m is not None, "merge_gate: chạy", why):
    g = m["metrics"]["merge_gate_s"]
    chk(g["n"] == 3 and g["median_s"] == 200.0 and g["p90_s"] == 360.0, "n=3 median 200 p90 360 (nội suy)", g)
    chk(g["pass_n"] == 2 and g["pass_median_s"] == 150.0 and g["pass_p90_s"] == 190.0, "riêng PASS: n=2 median 150 p90 190", g)

# ── scoped_escalated_pct ─────────────────────────────────────────────────────
ESC = "--scoped → full: khớp lõi ⇒ full"
sc = [row(1, mode="scoped"), row(2, force_reason=ESC), row(3, force_reason=ESC), row(4, force_reason=ESC), row(5, force_reason="--full")]
m, why = metrics(write("sc.jsonl", sc))
if chk(m is not None, "scoped: chạy", why):
    s = m["metrics"]["scoped_escalated"]
    chk(s["scoped_runs"] == 4 and s["escalated"] == 3 and s["scoped_escalated_pct"] == 75.0, "3/4 lượt --scoped leo full => 75.0 (--full không tính)", s)

# ── suites_per_run ───────────────────────────────────────────────────────────
sp = [
    row(1, ran_suites=["a", "b", "c", "d"], suites=S(9)),
    row(2, suites=[["a", "PASS", 1], ["b", "PASS", 1], ["c", "PASS", 1], ["d", "UNTESTED", None], ["e", "PASS", 1]], suites_reused=1),
    row(3, exit=4, suites=[["a", "UNTESTED", None]] * 3),                  # BUSY: không suite nào chạy
    row(4, ran_suites=["x"] * 10),
]
m, why = metrics(write("sp.jsonl", sp))
if chk(m is not None, "suites_per_run: chạy", why):
    q = m["metrics"]["suites_per_run"]
    chk(q["runs_counted"] == 3 and q["median"] == 4.0 and q["p90"] == 8.8, "n=3 [3,4,10] median 4 p90 8.8", q)

# ── load_median ──────────────────────────────────────────────────────────────
csvp = os.path.join(TMP, "load.csv")
with open(csvp, "w") as fh:
    fh.write("ts,epoch,event,load1,load5\n")
    for i, ld in enumerate((1, 3, 5, 100)):
        fh.write("t,%d,sample,%s,0\n" % (BASE + i, ld))
    fh.write("t,%d,sample,xx,0\n" % (BASE + 9))        # load1 không phải số: bỏ qua
m, why = metrics(write("ld.jsonl", [row(1)]), "--sampler-csv", csvp)
if chk(m is not None, "load: chạy", why):
    chk(m["metrics"]["load_median"]["median"] == 4.0 and m["metrics"]["load_median"]["samples"] == 4, "median [1,3,5,100] == 4.0", m["metrics"]["load_median"])
m, why = metrics(write("ld.jsonl", [row(1)]), "--sampler-csv", csvp, "--until", str(BASE + 2))
if chk(m is not None, "load: --until", why):
    chk(m["metrics"]["load_median"]["median"] == 3.0, "cửa sổ đến BASE+2: median [1,3,5] == 3.0", m["metrics"]["load_median"])

# ── khử trùng + mặc định đọc common dir git ─────────────────────────────────
repo = os.path.join(TMP, "repo")
subprocess.run(["git", "init", "-q", repo], check=True, timeout=60)
pg = os.path.join(repo, ".git", "postfix-gate")
os.makedirs(os.path.join(pg, "archive"))
rows_all = [row(1, fp="Z1", exit=1), row(2, fp="Z1", exit=0), row(3, fp="Z3", exit=0)]
with open(os.path.join(pg, "runs.jsonl"), "w") as fh:
    for r in rows_all[1:]:
        fh.write(json.dumps(r) + "\n")
with open(os.path.join(pg, "archive", "runs-20261029.jsonl"), "w") as fh:
    for r in rows_all[:2]:                    # dòng 2 nằm ở CẢ HAI file
        fh.write(json.dumps(r) + "\n")
m, why = metrics("--repo", repo)
if chk(m is not None, "mặc định: đọc runs.jsonl + archive/runs-*.jsonl", why):
    chk(m["meta"]["rows"] == 3 and m["meta"]["duplicates"] == 1, "3 lượt, 1 dòng trùng bị khử", m["meta"])
    chk(m["metrics"]["rerun_on_red"]["count"] == 1, "rerun nối được qua ranh giới hai file => 1", m["metrics"]["rerun_on_red"])
# ── --repo-prefix suy repo từ FILE: worktree đặt tên bất kỳ vẫn được tính ──────
wrepo = os.path.join(TMP, "agent-workbench")
subprocess.run(["git", "init", "-q", wrepo], check=True, timeout=60)
wrows = [row(1, project="issue-1-build", fp="W1", exit=1), row(2, project="issue-1-build", fp="W1", exit=0),
         row(3, project="scoped-gate", fp="W2", exit=0), row(4, project="ocr-3", fp="W3", exit=0),
         row(5, project="agent-workbench", fp="W4", exit=0)]
wpg = os.path.join(wrepo, ".git", "postfix-gate")
os.makedirs(wpg)
with open(os.path.join(wpg, "runs.jsonl"), "w") as fh:
    for r in wrows:
        fh.write(json.dumps(r) + "\n")
os.makedirs(os.path.join(wrepo, "audit"))
copy = os.path.join(wrepo, "audit", "baseline.jsonl")
with open(copy, "w") as fh:
    for r in wrows:
        fh.write(json.dumps(r) + "\n")
m, why = metrics(copy, "--repo-prefix", "agent-workbench")
if chk(m is not None, "repo từ file: bản sao trong checkout agent-workbench", why):
    chk(m["meta"]["rows"] == 4, "giữ 4 dòng (worktree tên lạ vào, ocr-3 ra)", m["meta"])
    chk(m["meta"]["dropped_projects"] == {"ocr-3": 1}, "meta.dropped_projects ghi ocr-3", m["meta"]["dropped_projects"])
    chk(m["metrics"]["rerun_on_red"]["count"] == 1, "rerun của issue-1-build được tính => 1", m["metrics"]["rerun_on_red"])
    chk(list(m["meta"]["repo_by_file"].values()) == ["agent-workbench"], "meta.repo_by_file", m["meta"]["repo_by_file"])
m, why = metrics("--repo", wrepo, "--repo-prefix", "agent-workbench")
if chk(m is not None, "repo từ file: mặc định đọc <repo>/.git/postfix-gate/runs.jsonl", why):
    chk(m["meta"]["rows"] == 4, "giữ 4 dòng qua đường mặc định", m["meta"])
m, why = metrics(copy, "--repo-prefix", "repo-khac")
if chk(m is not None, "repo từ file: tiền tố của repo khác", why):
    chk(m["meta"]["rows"] == 0 and m["meta"]["dropped_projects"].get("issue-1-build") == 2, "repo khác => 0 dòng, project bị loại được liệt kê", m["meta"])
m, why = metrics(copy, "--repo-prefix", "scoped-gate")
if chk(m is not None, "repo từ file: tiền tố trùng tên project của repo khác", why):
    chk(m["meta"]["rows"] == 1, "tên repo không khớp => quay về so tên project, scoped-gate khớp => 1 dòng", m["meta"])
rc, out, err = run("--repo", os.path.join(TMP, "khong-co-repo"))
chk(rc == 2, "repo không có runs.jsonl => exit 2", "rc=%s" % rc)
rc, out, err = run(os.path.join(TMP, "khong-co.jsonl"))
chk(rc == 2, "file không tồn tại => exit 2", "rc=%s" % rc)
rc, out, err = run(p, "--repo-prefix", "agent-workbench")
chk(rc == 0 and "rerun_on_red" in out and "3 lượt" in out, "bảng text có dòng rerun_on_red", out[:300])

print("\n%d lỗi" % fails if fails else "\nTất cả PASS")
sys.exit(1 if fails else 0)
PYEND
