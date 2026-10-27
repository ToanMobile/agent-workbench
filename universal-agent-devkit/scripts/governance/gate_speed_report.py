#!/usr/bin/env python3
"""Số đo tốc độ post-fix gate từ runs.jsonl (chỉ đọc, stdlib, Python 3.9).

    python3 gate_speed_report.py [--log FILE] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--baseline FILE]

--log mặc định là <git-common-dir>/postfix-gate/runs.jsonl của repo ở thư mục hiện tại. Dòng hỏng bị bỏ và đếm (bộ đọc của
gate_runs_report.py). Ngày tính theo giờ địa phương (TZ); --until gồm cả ngày đó.

Quy ước in ra:
- thời gian impacted: total_wall_s của lượt impacted, tách source cli / hook; bỏ BUSY, REUSED, deferred (không trả giá chạy suite).
  p90 = nearest rank (như gate_runs_report.p90).
- suite liệt kê = mọi dòng trong "suites"; suite thực chạy = dòng có số giây.
- xanh lần đầu: nhóm theo trường task khi bản ghi có, không thì theo fp; lượt thử = lượt impacted không BUSY/REUSED/deferred,
  theo epoch; nhóm xanh lần đầu khi lượt thử đầu tiên là PASS. Nhóm không có lượt thử nào không tính.
- --full hợp lệ = project bắt đầu bằng .integrate-scratch- / .merge-scratch- / .train-scratch- (worktree tạm của integrate, merge
  gate, merge train — như bin/batch_canary.py); mọi --full khác (kể cả final-gate, gate-batch-integrate) là ngoài điểm gộp.
  Mọi bản ghi --full đều đếm, kể cả BUSY (lượt đã được gọi).
- REG-DK-ALL-01: mọi lần suite đó có trong một lượt; p50/p90 trên các lần có số giây.
--baseline FILE: in thêm bảng | metric | baseline | current | delta | cho cùng cửa sổ --since/--until.
"""
import argparse
import collections
import os
import statistics
import sys
import time
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gate_runs_report as grr  # noqa: E402  (bộ đọc runs.jsonl của kit: kiểm chặt, đọc đuôi file lớn)

MERGE_POINT_PREFIXES = (".integrate-scratch-", ".merge-scratch-", ".train-scratch-")
ALL01 = "REG-DK-ALL-01"


def day_epoch(text):
    """Epoch của 00:00 giờ địa phương ngày YYYY-MM-DD; sai định dạng thì argparse báo lỗi (exit 2)."""
    try:
        return time.mktime(datetime.strptime(text, "%Y-%m-%d").timetuple())
    except ValueError:
        raise argparse.ArgumentTypeError("cần YYYY-MM-DD: %r" % text)


def day(r):
    return time.strftime("%Y-%m-%d", time.localtime(grr.num(r["epoch"])))


def ran(s):
    return s[2] is not None


def skipped(r):
    """Lượt không trả giá chạy suite: BUSY, REUSED, deferred."""
    return grr.excluded(r) or r["verdict"] == "REUSED" or r.get("reused_full_pass") is True


def counts(c):
    return " ".join("%s=%d" % kv for kv in sorted(c.items()))


def pct_stats(values):
    if not values:
        return None, None
    return float(statistics.median(values)), float(grr.p90(values))


def fmt_s(v):
    return "-" if v is None else "%.1fs" % v


def load(path, since, until):
    now = time.time()
    data = grr.read_runs(path, since, now)
    recs = [r for r in data["recs"] if until is None or grr.num(r["epoch"]) < until]
    recs.sort(key=lambda r: grr.num(r["epoch"]))
    return recs, data["ignored"]


def metrics(recs):
    """Các số đo của một tập bản ghi; dict phẳng cho bảng trước/sau và các bảng con để in."""
    m = {}
    imp = [r for r in recs if r["mode"] == "impacted"]
    full = [r for r in recs if r["mode"] == "full"]
    for src in ("cli", "hook"):
        walls = [grr.wall(r) for r in imp if r["source"] == src and not skipped(r)]
        m["impacted_%s_n" % src] = len(walls)
        m["impacted_%s_p50_s" % src], m["impacted_%s_p90_s" % src] = pct_stats(walls)
    for name, rs in (("impacted", imp), ("full", full)):
        m["suites_%s_listed" % name] = sum(len(r["suites"]) for r in rs)
        m["suites_%s_ran" % name] = sum(1 for r in rs for s in r["suites"] if ran(s))
        m["verdict_%s" % name] = collections.Counter(r["verdict"] for r in rs)
        m["untested_%s" % name] = collections.Counter(str(r.get("exit_reason")) for r in rs if r["verdict"] == "UNTESTED")
    m["suite_status"] = collections.Counter(str(s[1]) for r in recs for s in r["suites"])
    # xanh lần đầu: nhóm theo task (khi có) hoặc fp
    first = collections.OrderedDict()
    for r in imp:
        if skipped(r):
            continue
        key = r.get("task") if isinstance(r.get("task"), str) and r.get("task") else "fp:%s" % r.get("fp")
        first.setdefault(key, r["verdict"])
    m["first_green_groups"] = len(first)
    m["first_green_pass"] = sum(1 for v in first.values() if v == "PASS")
    m["first_green_pct"] = round(100.0 * m["first_green_pass"] / len(first), 1) if first else None
    per_day = collections.OrderedDict()
    for r in full:
        d = per_day.setdefault(day(r), [0, 0])
        d[0 if str(r.get("project", "")).startswith(MERGE_POINT_PREFIXES) else 1] += 1
    m["full_per_day"] = per_day
    m["full_merge_point"] = sum(v[0] for v in per_day.values())
    m["full_outside"] = sum(v[1] for v in per_day.values())
    a = [s for r in recs for s in r["suites"] if s[0] == ALL01]
    secs = [grr.num(s[2]) for s in a if ran(s)]
    m["all01_n"] = len(a)
    m["all01_status"] = collections.Counter(str(s[1]) for s in a)
    m["all01_p50_s"], m["all01_p90_s"] = pct_stats(secs)
    return m


def print_report(label, m, ignored, out):
    w = out.write
    w("== %s ==\n" % label)
    for src in ("cli", "hook"):
        w("impacted %s: n=%d p50=%s p90=%s\n" % (src, m["impacted_%s_n" % src], fmt_s(m["impacted_%s_p50_s" % src]),
                                                fmt_s(m["impacted_%s_p90_s" % src])))
    for name in ("impacted", "full"):
        w("suites %s: listed=%d ran=%d\n" % (name, m["suites_%s_listed" % name], m["suites_%s_ran" % name]))
    for name in ("impacted", "full"):
        w("verdict %s: %s\n" % (name, counts(m["verdict_%s" % name])))
        if m["untested_%s" % name]:
            w("untested reasons %s: %s\n" % (name, counts(m["untested_%s" % name])))
    w("suite status: %s\n" % counts(m["suite_status"]))
    pct = m["first_green_pct"]
    w("first green impacted (key=task|fp): %d/%d = %s\n" % (m["first_green_pass"], m["first_green_groups"],
                                                            "-" if pct is None else "%.1f%%" % pct))
    for d, (ok, bad) in m["full_per_day"].items():
        w("full %s: merge_point=%d outside=%d\n" % (d, ok, bad))
    w("full total: merge_point=%d outside=%d (merge point = %s)\n" % (m["full_merge_point"], m["full_outside"],
                                                                      " ".join(p + "*" for p in MERGE_POINT_PREFIXES)))
    st = m["all01_status"]
    other = m["all01_n"] - sum(st[k] for k in ("PASS", "FAIL", "TIMEOUT", "UNTESTED"))
    w("%s: n=%d PASS=%d FAIL=%d TIMEOUT=%d UNTESTED=%d other=%d p50=%s p90=%s\n" % (
        ALL01, m["all01_n"], st["PASS"], st["FAIL"], st["TIMEOUT"], st["UNTESTED"], other, fmt_s(m["all01_p50_s"]), fmt_s(m["all01_p90_s"])))
    w("ignored lines: %d\n" % ignored)


TABLE_KEYS = ("impacted_cli_n", "impacted_cli_p50_s", "impacted_cli_p90_s", "impacted_hook_n", "impacted_hook_p50_s",
              "impacted_hook_p90_s", "suites_impacted_listed", "suites_impacted_ran", "first_green_pct", "full_merge_point",
              "full_outside", "all01_n", "all01_p50_s", "all01_p90_s")


def print_table(b, c, out):
    def cell(v):
        return "-" if v is None else ("%.1f" % v if isinstance(v, float) else str(v))
    out.write("| metric | baseline | current | delta |\n|---|---|---|---|\n")
    for k in TABLE_KEYS:
        bv, cv = b[k], c[k]
        delta = None if bv is None or cv is None else (round(cv - bv, 1) if isinstance(cv, float) or isinstance(bv, float) else cv - bv)
        out.write("| %s | %s | %s | %s |\n" % (k, cell(bv), cell(cv), cell(delta)))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--log", help="runs.jsonl (mặc định: của repo ở thư mục hiện tại)")
    ap.add_argument("--since", type=day_epoch, help="YYYY-MM-DD, giờ địa phương, gồm ngày này")
    ap.add_argument("--until", type=day_epoch, help="YYYY-MM-DD, giờ địa phương, gồm ngày này")
    ap.add_argument("--baseline", help="runs.jsonl để so (bảng trước/sau)")
    a = ap.parse_args(argv)
    until = None if a.until is None else time.mktime((datetime.fromtimestamp(a.until) + timedelta(days=1)).timetuple())
    path = a.log
    if not path:
        path, _, problem = grr.log_file(os.getcwd())
        if problem:
            print("✖ %s" % problem)
            return 1
    try:
        recs, ignored = load(path, a.since, until)
        base = load(a.baseline, a.since, until) if a.baseline else None
    except (OSError, ValueError) as e:
        print("✖ cannot read %s: %s" % (e.filename if getattr(e, "filename", None) else (a.baseline or path), e))
        return 1
    cur = metrics(recs)
    print_report("current: %s (%d runs)" % (path, len(recs)), cur, ignored, sys.stdout)
    if base is not None:
        bm = metrics(base[0])
        print_report("baseline: %s (%d runs)" % (a.baseline, len(base[0])), bm, base[1], sys.stdout)
        print_table(bm, cur, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
