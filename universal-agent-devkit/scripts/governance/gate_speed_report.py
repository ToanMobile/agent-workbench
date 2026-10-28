#!/usr/bin/env python3
"""Số đo tốc độ post-fix gate từ runs.jsonl (chỉ đọc, stdlib, Python 3.9).

    python3 gate_speed_report.py [--log FILE] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--baseline FILE]

--log mặc định là <git-common-dir>/postfix-gate/runs.jsonl của repo ở thư mục hiện tại. Dòng hỏng bị bỏ và đếm (bộ đọc của
gate_runs_report.py). Ngày tính theo giờ địa phương (TZ); --until gồm cả ngày đó.

Quy ước in ra:
- thời gian impacted: total_wall_s của lượt impacted, tách source cli / hook; bỏ BUSY, REUSED, deferred (không trả giá chạy suite).
  p90 = nearest rank (như gate_runs_report.p90).
  Thêm một dòng "incl. busy/reused flags": chỉ bỏ verdict BUSY/REUSED (lượt không chạy gì), giữ lượt có cờ busy /
  reused_full_pass / deferred — để thấy cả hai số.
- suite liệt kê = mọi dòng trong "suites"; suite thực chạy = dòng có số giây. Với impacted chỉ đếm lượt không BUSY/REUSED/deferred
  và in trung bình mỗi lượt; với mode=full đếm mọi lượt.
- xanh lần đầu: chỉ nhóm theo trường task; lượt thử = lượt impacted không BUSY/REUSED/deferred, theo epoch; nhóm xanh lần đầu khi
  lượt thử đầu tiên là PASS. Không bản ghi nào có task thì in n/a: nhóm theo fp phần lớn chỉ một lượt, không phải task.
- mode=full runs: mode=full không chỉ là --full (còn CI, --record-lesson, POSTFIX_GATE_FORCE_FULL...). Điểm gộp = trường
  merge_point (#472 C) khi có; bản ghi cũ thì project bắt đầu bằng .integrate-scratch- / .merge-scratch- / .train-scratch-
  (worktree tạm của integrate, merge gate, merge train — như bin/batch_canary.py). Khi log có force_reason thì in thêm phân bố
  mỗi ngày theo force_reason (bản ghi thiếu = unknown). Mọi bản ghi mode=full đều đếm, kể cả BUSY (lượt đã được gọi).
- impacted_command used: lượt impacted (bỏ BUSY/REUSED/deferred) có impacted_run=true; chỉ suite matrix có impacted_command mới
  đặt cờ này, nên số này không đo việc thu hẹp test và không vào bảng trước/sau.
- REG-DK-ALL-01: mọi lần suite đó có trong một lượt; p50/p90 trên các lần có số giây. Thêm thời gian lượt impacted (không
  BUSY/REUSED/deferred, có ít nhất một suite có số giây) tách theo REG-DK-ALL-01 có số giây hay không.
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


def wall_or_none(r):
    w = grr.num(r.get("total_wall_s"))
    return w if w is not None else grr.num(r.get("suites_wall_s"))


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
        # bản ghi không có total_wall_s lẫn suites_wall_s không có thời gian: bỏ, không tính là 0 s
        walls = [w for w in (wall_or_none(r) for r in imp if r["source"] == src and not skipped(r)) if w is not None]
        m["impacted_%s_n" % src] = len(walls)
        m["impacted_%s_p50_s" % src], m["impacted_%s_p90_s" % src] = pct_stats(walls)
        # gồm lượt có cờ busy/reused_full_pass/deferred; chỉ bỏ verdict BUSY/REUSED (lượt không chạy suite nào)
        walls = [w for w in (wall_or_none(r) for r in imp if r["source"] == src and r["verdict"] not in ("BUSY", "REUSED"))
                 if w is not None]
        m["impacted_%s_incl_n" % src] = len(walls)
        m["impacted_%s_incl_p50_s" % src], m["impacted_%s_incl_p90_s" % src] = pct_stats(walls)
    # impacted_run chỉ true khi một suite matrix có impacted_command; không đo việc thu hẹp test
    ran_imp = [r for r in imp if not skipped(r)]
    m["impacted_command_used"] = sum(1 for r in ran_imp if r.get("impacted_run") is True)
    m["impacted_command_of"] = len(ran_imp)
    # impacted: chỉ lượt đã trả giá chạy suite, để trung bình mỗi lượt đúng nghĩa
    for name, rs in (("impacted", ran_imp), ("full", full)):
        m["suites_%s_listed" % name] = sum(len(r["suites"]) for r in rs)
        m["suites_%s_ran" % name] = sum(1 for r in rs for s in r["suites"] if ran(s))
    m["suites_impacted_runs"] = len(ran_imp)
    for name, rs in (("impacted", imp), ("full", full)):
        m["verdict_%s" % name] = collections.Counter(r["verdict"] for r in rs)
        m["untested_%s" % name] = collections.Counter(str(r.get("exit_reason")) for r in rs if r["verdict"] == "UNTESTED")
    m["suite_status"] = collections.Counter(str(s[1]) for r in recs for s in r["suites"])
    # xanh lần đầu: chỉ theo task; nhóm theo fp phần lớn chỉ một lượt nên không phải số đo task
    first = collections.OrderedDict()
    m["first_green_skipped"] = 0
    for r in ran_imp:
        task = r.get("task")
        if isinstance(task, str) and task:
            first.setdefault(task, r["verdict"])
        else:
            m["first_green_skipped"] += 1
    m["first_green_groups"] = len(first)
    m["first_green_pass"] = sum(1 for v in first.values() if v == "PASS")
    m["first_green_pct"] = round(100.0 * m["first_green_pass"] / len(first), 1) if first else None
    per_day = collections.OrderedDict()
    reasons = collections.OrderedDict()
    for r in full:
        d = per_day.setdefault(day(r), [0, 0])
        mp = r.get("merge_point")
        if not isinstance(mp, bool):
            # bản ghi cũ (trước #472 C) không có merge_point: dùng quy tắc tiền tố project
            mp = str(r.get("project", "")).startswith(MERGE_POINT_PREFIXES)
        d[0 if mp else 1] += 1
        fr = r.get("force_reason")
        reasons.setdefault(day(r), collections.Counter())[fr if isinstance(fr, str) and fr else "unknown"] += 1
    m["full_per_day"] = per_day
    # chỉ in theo force_reason khi log có trường này (#472 C); log cũ thì bỏ hẳn
    m["full_reason_per_day"] = reasons if any(isinstance(r.get("force_reason"), str) and r["force_reason"] for r in full) else None
    m["full_merge_point"] = sum(v[0] for v in per_day.values())
    m["full_outside"] = sum(v[1] for v in per_day.values())
    a = [s for r in recs for s in r["suites"] if s[0] == ALL01]
    secs = [grr.num(s[2]) for s in a if ran(s)]
    m["all01_n"] = len(a)
    m["all01_status"] = collections.Counter(str(s[1]) for s in a)
    m["all01_p50_s"], m["all01_p90_s"] = pct_stats(secs)
    # lượt impacted có chạy suite (ít nhất một suite có số giây), tách theo REG-DK-ALL-01 có số giây hay không
    for key, has in (("without", False), ("with", True)):
        walls = [wall_or_none(r) for r in ran_imp if any(ran(s) for s in r["suites"])
                 and any(s[0] == ALL01 and ran(s) for s in r["suites"]) == has]
        walls = [w for w in walls if w is not None]
        m["imp_%s_all01_n" % key] = len(walls)
        m["imp_%s_all01_p50_s" % key] = pct_stats(walls)[0]
    # #476: lượt impacted có shadow (map test→nguồn so với cách chọn cũ); miss = suite map bỏ mà thật sự FAIL
    sh = [r for r in imp if isinstance(r.get("shadow_skip"), list)]
    m["shadow_runs"] = len(sh)
    m["shadow_skipped"] = sum(len(r["shadow_skip"]) for r in sh)
    m["shadow_miss"] = sum(len(r["shadow_miss"]) for r in sh if isinstance(r.get("shadow_miss"), list))
    return m


def print_report(label, m, ignored, out):
    w = out.write
    w("== %s ==\n" % label)
    for src in ("cli", "hook"):
        w("impacted %s: n=%d p50=%s p90=%s\n" % (src, m["impacted_%s_n" % src], fmt_s(m["impacted_%s_p50_s" % src]),
                                                fmt_s(m["impacted_%s_p90_s" % src])))
    for src in ("cli", "hook"):
        w("impacted %s incl. busy/reused flags (verdict BUSY/REUSED dropped): n=%d p50=%s p90=%s\n" % (
            src, m["impacted_%s_incl_n" % src], fmt_s(m["impacted_%s_incl_p50_s" % src]), fmt_s(m["impacted_%s_incl_p90_s" % src])))
    n = m["suites_impacted_runs"]
    w("suites impacted: listed=%d ran=%d runs=%d mean_listed=%s mean_ran=%s\n" % (
        m["suites_impacted_listed"], m["suites_impacted_ran"], n, "-" if not n else "%.1f" % (1.0 * m["suites_impacted_listed"] / n),
        "-" if not n else "%.1f" % (1.0 * m["suites_impacted_ran"] / n)))
    # bộ lọc của skipped(): dùng cho thời gian impacted, suite impacted, xanh lần đầu, ALL-01 tách lượt, impacted_command
    w("impacted filter: BUSY, REUSED, deferred and reused_full_pass excluded\n")
    w("suites full: listed=%d ran=%d\n" % (m["suites_full_listed"], m["suites_full_ran"]))
    for name in ("impacted", "full"):
        w("verdict %s: %s\n" % (name, counts(m["verdict_%s" % name])))
        if m["untested_%s" % name]:
            w("untested reasons %s: %s\n" % (name, counts(m["untested_%s" % name])))
    w("suite status: %s\n" % counts(m["suite_status"]))
    if m["first_green_groups"]:
        w("first green impacted (key=task): %d/%d = %.1f%%\n" % (m["first_green_pass"], m["first_green_groups"], m["first_green_pct"]))
        if m["first_green_skipped"]:
            w("first green skipped (no task): %d\n" % m["first_green_skipped"])
    else:
        w("first green impacted: n/a (no task field; fp groups are not tasks)\n")
    for d, (ok, bad) in m["full_per_day"].items():
        w("mode=full runs %s: merge_point=%d outside=%d\n" % (d, ok, bad))
    w("mode=full runs total: merge_point=%d outside=%d (merge point = field merge_point, else %s)\n" % (
        m["full_merge_point"], m["full_outside"], " ".join(p + "*" for p in MERGE_POINT_PREFIXES)))
    w("note: mode=full also covers CI, --record-lesson and POSTFIX_GATE_FORCE_FULL\n")
    if m["full_reason_per_day"]:
        for d, c in m["full_reason_per_day"].items():
            w("mode=full force_reason %s: %s\n" % (d, counts(c)))
    st = m["all01_status"]
    other = m["all01_n"] - sum(st[k] for k in ("PASS", "FAIL", "TIMEOUT", "UNTESTED"))
    w("%s: n=%d PASS=%d FAIL=%d TIMEOUT=%d UNTESTED=%d other=%d p50=%s p90=%s\n" % (
        ALL01, m["all01_n"], st["PASS"], st["FAIL"], st["TIMEOUT"], st["UNTESTED"], other, fmt_s(m["all01_p50_s"]), fmt_s(m["all01_p90_s"])))
    w("impacted without %s (impacted, not BUSY/REUSED/deferred, >=1 suite with seconds, %s without seconds): n=%d p50=%s; "
      "with %s: n=%d p50=%s\n" % (ALL01, ALL01, m["imp_without_all01_n"], fmt_s(m["imp_without_all01_p50_s"]), ALL01,
                                 m["imp_with_all01_n"], fmt_s(m["imp_with_all01_p50_s"])))
    w("impacted_command used (impacted_run): %d/%d\n" % (m["impacted_command_used"], m["impacted_command_of"]))
    if m["shadow_runs"]:
        w("shadow map (#476): runs=%d suites_skipped_by_map=%d missed_FAIL=%d\n" % (m["shadow_runs"], m["shadow_skipped"], m["shadow_miss"]))
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
            print("✖ %s" % problem, file=sys.stderr)
            return 1
    base = None
    # mỗi file đọc riêng để lỗi nêu đúng file hỏng (ValueError của read_runs không mang tên file)
    for which, f in (("log", path), ("baseline", a.baseline)):
        if not f:
            continue
        try:
            got = load(f, a.since, until)
        except (OSError, ValueError) as e:
            print("✖ cannot read %s: %s" % (f, getattr(e, "strerror", None) or e), file=sys.stderr)
            return 1
        if which == "log":
            recs, ignored = got
        else:
            base = got
    cur = metrics(recs)
    print_report("current: %s (%d runs)" % (path, len(recs)), cur, ignored, sys.stdout)
    if base is not None:
        bm = metrics(base[0])
        print_report("baseline: %s (%d runs)" % (a.baseline, len(base[0])), bm, base[1], sys.stdout)
        print_table(bm, cur, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
