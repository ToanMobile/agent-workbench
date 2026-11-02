#!/usr/bin/env python3
"""stabilize_metrics.py - đo "độ ổn định" của gate DevKit từ runs.jsonl (plan ổn định, thẻ #686). Chỉ đọc, thư viện chuẩn.

Đầu vào
  * Tham số vị trí: một hay nhiều file runs.jsonl. Bỏ trống thì đọc
    <git common dir>/postfix-gate/runs.jsonl  +  <git common dir>/postfix-gate/archive/runs-*.jsonl
    (repo lấy từ --repo, mặc định thư mục hiện tại; worktree dùng chung common dir với repo chính).
    Một dòng có mặt ở nhiều file (runs.jsonl và bản archive) chỉ tính một lần (khử trùng theo sha256 của cả dòng).
  * --since / --until: epoch (số) hoặc ISO-8601 (vd 2026-10-29T17:51:00+07:00); lọc theo trường `epoch` của dòng.
  * --repo-prefix P (lặp được, hoặc phân tách bằng dấu phẩy): chỉ tính dòng của repo P và worktree của nó.
    `project` trong runs.jsonl chỉ là tên THƯ MỤC làm việc (issue-123-build, scoped-gate, .merge-scratch-x ... không chứa
    tên repo), nên repo được suy ra từ FILE, không từ dòng: với mỗi file đầu vào, `git rev-parse --git-common-dir` chạy ở
    thư mục chứa file; tên repo = tên thư mục cha của `.git` (worktree dùng chung common dir nên cùng tên repo). Tên repo
    == P (hoặc bắt đầu bằng "P-") thì giữ MỌI dòng của file đó. File không nằm trong repo git (hoặc repo tên khác) thì
    quay về so tên `project` == P hoặc bắt đầu bằng "P-". `meta.repo_by_file` ghi repo suy ra cho từng file và
    `meta.dropped_projects` ghi các project bị loại (để người đọc thấy cái gì bị bỏ).
    Luôn loại project bắt đầu bằng "ocr-" (bản sao review của OCR) trừ khi có --include-ocr.
  * --sampler-csv FILE... : CSV của com.toanmobile.devkit.capacity.sampler (cột `load1`, `epoch`); tìm đường dẫn trong
    "~/Library/Application Support/devkit-capacity/sampler.sh" (LOGDIR=~/Library/Logs/devkit-capacity, file <YYYY-MM-DD>.csv).
  * --json: in JSON thay cho bảng text.

Chỉ số (mỗi dòng runs.jsonl là MỘT lượt chạy gate; sắp xếp theo `epoch`)
  rerun_on_red       Số lượt chạy lại CÙNG `fp` + CÙNG `mode` ngay sau một lượt ĐỎ trên fp đó. Con số chính chỉ tính khi lượt
                     trước có exit == 1 (FAIL). "Ngay sau" = lượt liền trước TRONG CÙNG `project` (lượt BUSY, exit 4, bị bỏ
                     qua như trong suốt); nếu giữa hai lượt có một lượt khác fp thì không tính; dòng không có `fp` không
                     được so. Kèm giờ máy = tổng `total_wall_s` của các lượt chạy lại (công sức lặp lại), tách theo `source`
                     (hook/cli). Chạy lại sau exit 2/3 (gate chặn: edited_test, matrix... không phải đỏ) báo RIÊNG trong
                     `after_blocked`, tách theo `exit_reason`. Chưa có chỗ loại lượt "flaky": gate không ghi cờ đó vào runs.jsonl.
  busy_pct           Tỉ lệ lượt có trường `busy` true (lượt kết thúc khi đang chờ khoá test_run.lock; gồm cả vài lượt exit 2) trên
                     tổng lượt. Số chính là trường `busy`. Báo kèm `exit4_pct` = tỉ lệ lượt exit == 4 (BUSY/stale/budget, gate
                     từ chối chạy).
  machine_hours      Tổng `total_wall_s` / 3600 của mọi lượt; `heavy_full_hours` là riêng lượt full nặng: (mode == "full" hoặc
                     force_full) và có >= 40 suite (max(len(suites), len(ran_suites)) + suites_reused: từ B9 `suites` không liệt
                     kê suite PASS dùng lại), loại lượt exit 4.
                     Lượt BUSY vẫn nằm trong tổng vì `total_wall_s` gồm cả thời gian chờ khoá.
  false_red_pct      Xấp xỉ "đỏ giả": lượt FAIL (verdict FAIL / exit 1) là đỏ giả khi tập suite đỏ của nó (suite trong `suites` có
                     trạng thái khác PASS và UNTESTED) nằm trọn trong `suites`/`ran_suites` của MỘT lượt exit 0 cùng `fp` về
                     sau (lượt xanh chỉ liệt kê suite đã chạy, nên không so cả tập) => suite đỏ chạy lại và xanh trên cùng nội
                     dung => nghi flaky/hạ tầng. Chia cho tổng lượt FAIL; FAIL không ghi suite đỏ nào (lớp tĩnh hoặc danh sách
                     bị cắt) đếm riêng ở `undetermined` và không bao giờ là đỏ giả.
  merge_gate_s       median, p90 (nội suy tuyến tính) của `total_wall_s` cho lượt `merge_point` true. Kèm n và riêng lượt PASS.
  scoped_escalated_pct  Trong các lượt --scoped (mode == "scoped" HOẶC force_reason chứa "--scoped"), tỉ lệ bị leo lên full
                     (force_reason chứa "--scoped → full").
  suites_per_run     median, p90 số suite chạy THẬT mỗi lượt: max(len(ran_suites), số suite trong `suites` có giây chạy
                     `s[2] is not None`). Từ B9 `suites` chỉ liệt kê suite đã chạy hoặc không PASS; suite dùng lại chỉ nằm trong
                     `suites_reused` nên KHÔNG trừ đi. Chỉ tính lượt có ít nhất một suite chạy. Lượt bị cắt (`suites_cut`) là cận dưới.
  load_median        (cần --sampler-csv) trung vị cột load1 của các mẫu trong cửa sổ --since/--until (hoặc cả file).

Giới hạn dữ liệu: runs.jsonl không có SHA commit; dòng > 3000 byte bị gate cắt bớt trường (`*_cut`, `changed_files` tối đa
50); lượt hook (source=hook) và cli trộn lẫn; `fp` là dấu vân tay nội dung, hai worktree cùng nội dung có thể trùng fp.
"""
import argparse
import csv
import datetime
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

BLOCKED_EXITS = (2, 3)        # exit 2 = gate chặn (edited_test, matrix, ...), 3 = chưa kết luận: báo riêng, không tính là "đỏ"
HEAVY_MIN_SUITES = 40         # ngưỡng "lượt full nặng"
SCOPED_ESCALATE_MARK = "--scoped → full"


def parse_time(text):
    """Epoch (số) hoặc ISO-8601 -> epoch giây (float). ISO không có múi giờ hiểu theo giờ máy."""
    if text is None:
        return None
    s = str(text).strip()
    try:
        return float(s)
    except ValueError:
        pass
    s = re.sub(r"Z$", "+00:00", s)
    s = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", s)   # +0700 -> +07:00 (fromisoformat của 3.9 cần dấu :)
    return datetime.datetime.fromisoformat(s).timestamp()


def percentile(values, q):
    """Phân vị q (0..100) bằng nội suy tuyến tính; danh sách rỗng -> None."""
    if not values:
        return None
    v = sorted(values)
    if len(v) == 1:
        return float(v[0])
    pos = (len(v) - 1) * q / 100.0
    lo = int(pos)
    hi = min(lo + 1, len(v) - 1)
    return v[lo] + (v[hi] - v[lo]) * (pos - lo)


def median(values):
    return percentile(values, 50)


def pct(num, den):
    return round(100.0 * num / den, 1) if den else None


def rnd(x, n=1):
    return None if x is None else round(x, n)


def _common_dir(folder):
    """Đường dẫn tuyệt đối của git common dir chứa thư mục `folder`, hoặc None (không phải repo / không chạy được git)."""
    try:
        res = subprocess.run(["git", "-C", folder, "rev-parse", "--git-common-dir"],
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if res.returncode != 0 or not res.stdout.strip():
        return None
    return os.path.abspath(os.path.join(folder, res.stdout.strip()))


def default_inputs(repo):
    """runs.jsonl + archive/runs-*.jsonl của common dir git của `repo`; (danh sách file, lỗi)."""
    common = _common_dir(repo)
    if not common:
        return [], "không phải repo git: %s" % repo
    base = os.path.join(common, "postfix-gate")
    files = [os.path.join(base, "runs.jsonl")] + sorted(glob.glob(os.path.join(base, "archive", "runs-*.jsonl")))
    return [f for f in files if os.path.isfile(f)], None


def name_matches(name, prefixes):
    return any(name == p or name.startswith(p + "-") for p in prefixes)


def repo_name_of_file(path):
    """Tên repo chứa `path` (thư mục cha của git common dir), hoặc None nếu file không nằm trong repo git."""
    common = _common_dir(os.path.dirname(os.path.abspath(path)))
    if not common:
        return None
    base = os.path.basename(common)
    if base == ".git":
        return os.path.basename(os.path.dirname(common))
    return base[:-4] if base.endswith(".git") else base


def project_ok(project, prefixes, include_ocr, file_in_repo=False):
    project = project or ""
    if not include_ocr and project.startswith("ocr-"):
        return False
    if not prefixes or file_in_repo:
        return True
    return name_matches(project, prefixes)


def load_rows(paths, since, until, prefixes, include_ocr):
    """Đọc các file, khử trùng theo sha256 của dòng, lọc, sắp theo epoch. Trả (rows, thống kê)."""
    seen = set()
    rows = []
    stats = {"lines": 0, "bad_json": 0, "duplicates": 0, "filtered_out": 0, "repo_by_file": {}, "dropped_projects": {}}
    for path in paths:
        repo = repo_name_of_file(path) if prefixes else None
        stats["repo_by_file"][path] = repo
        in_repo = repo is not None and name_matches(repo, prefixes)
        with open(path, "rb") as fh:
            for raw in fh:
                raw = raw.strip()
                if not raw:
                    continue
                stats["lines"] += 1
                digest = hashlib.sha256(raw).digest()
                if digest in seen:
                    stats["duplicates"] += 1
                    continue
                seen.add(digest)
                try:
                    row = json.loads(raw.decode("utf-8"))
                    epoch = float(row["epoch"])
                except (ValueError, KeyError, TypeError):
                    stats["bad_json"] += 1
                    continue
                if not isinstance(row, dict):
                    stats["bad_json"] += 1
                    continue
                if not project_ok(row.get("project"), prefixes, include_ocr, in_repo):
                    name = row.get("project") or ""
                    stats["dropped_projects"][name] = stats["dropped_projects"].get(name, 0) + 1
                    stats["filtered_out"] += 1
                    continue
                if (since is not None and epoch < since) or (until is not None and epoch > until):
                    stats["filtered_out"] += 1
                    continue
                rows.append(row)
    rows.sort(key=lambda r: float(r["epoch"]))
    return rows, stats


def wall(row):
    try:
        return float(row.get("total_wall_s") or 0.0)
    except (TypeError, ValueError):
        return 0.0


def suite_ids(row):
    return frozenset(s[0] for s in (row.get("suites") or []) if isinstance(s, (list, tuple)) and s)


def failing_ids(row):
    """Id các suite mà lượt này ghi là đỏ (trạng thái khác PASS và UNTESTED)."""
    return frozenset(s[0] for s in (row.get("suites") or [])
                     if isinstance(s, (list, tuple)) and len(s) > 1 and s[1] not in ("PASS", "UNTESTED"))


def n_suites(row):
    """Tổng suite của lượt (B9: `suites` chỉ liệt kê suite đã chạy hoặc không PASS, suite dùng lại chỉ nằm trong suites_reused)."""
    listed = max(len(row.get("suites") or []), len(row.get("ran_suites") or []))
    return listed + int(row.get("suites_reused") or 0)


def m_rerun_on_red(rows):
    last = {}                       # project -> lượt gần nhất không phải BUSY
    red = {"count": 0, "hours": 0.0}
    blocked = {"count": 0, "hours": 0.0}
    by_source, blocked_by_reason = {}, {}
    for r in rows:
        if r.get("exit") == 4:
            continue                # BUSY trong suốt: không phải lượt chạy, cũng không cắt chuỗi
        prev = last.get(r.get("project"))
        last[r.get("project")] = r
        if not prev or not prev.get("fp") or prev.get("fp") != r.get("fp") or prev.get("mode") != r.get("mode"):
            continue                # không có fp thì không so (None == None sẽ ghép nhầm)
        w = wall(r)
        if prev.get("exit") == 1:
            red["count"] += 1
            red["hours"] += w
            s = by_source.setdefault(r.get("source") or "?", {"count": 0, "hours": 0.0})
            s["count"] += 1
            s["hours"] += w / 3600.0
        elif prev.get("exit") in BLOCKED_EXITS:
            blocked["count"] += 1
            blocked["hours"] += w
            k = blocked_by_reason.setdefault(prev.get("exit_reason") or "?", {"count": 0, "hours": 0.0})
            k["count"] += 1
            k["hours"] += w / 3600.0
    runs = sum(1 for r in rows if r.get("exit") != 4)
    for d in (by_source, blocked_by_reason):
        for v in d.values():
            v["hours"] = round(v["hours"], 2)
    return {"count": red["count"], "hours": round(red["hours"] / 3600.0, 2), "pct_of_executed_runs": pct(red["count"], runs),
            "by_source": by_source,
            "after_blocked": {"count": blocked["count"], "hours": round(blocked["hours"] / 3600.0, 2),
                              "by_prev_exit_reason": blocked_by_reason}}


def m_busy(rows):
    n = len(rows)
    e4 = sum(1 for r in rows if r.get("exit") == 4)
    flag = sum(1 for r in rows if r.get("busy"))
    return {"runs": n, "busy_flag": flag, "busy_pct": pct(flag, n), "exit4": e4, "exit4_pct": pct(e4, n)}


def m_machine_hours(rows):
    total = sum(wall(r) for r in rows) / 3600.0
    heavy = [r for r in rows if (r.get("mode") == "full" or r.get("force_full"))
             and r.get("exit") != 4 and n_suites(r) >= HEAVY_MIN_SUITES]
    hh = sum(wall(r) for r in heavy) / 3600.0
    return {"total_hours": round(total, 2), "heavy_full_runs": len(heavy), "heavy_full_hours": round(hh, 2),
            "heavy_full_share_pct": pct(hh, total)}


def m_false_red(rows):
    passes = {}                     # fp -> [(epoch, id suite có mặt trong lượt)] của các lượt exit 0
    for r in rows:
        if r.get("exit") == 0 and r.get("fp"):
            passes.setdefault(r["fp"], []).append((float(r["epoch"]), suite_ids(r) | frozenset(r.get("ran_suites") or [])))
    fails = [r for r in rows if r.get("verdict") == "FAIL" or r.get("exit") == 1]
    false_red = 0
    undetermined = 0                # FAIL không ghi suite đỏ nào (đỏ ở lớp tĩnh, hoặc danh sách bị cắt): không phân loại được
    for r in fails:
        red = failing_ids(r)
        if not red:
            undetermined += 1
            continue
        for ep, present in passes.get(r.get("fp"), []):
            # ran_suites bị gate cắt id ở 40 ký tự nên so cả dạng cắt
            if ep > float(r["epoch"]) and all(i in present or i[:40] in present for i in red):
                false_red += 1
                break
    return {"fail_runs": len(fails), "false_red": false_red, "undetermined": undetermined,
            "false_red_pct": pct(false_red, len(fails))}


def m_merge_gate(rows):
    sel = [r for r in rows if r.get("merge_point")]
    walls = [wall(r) for r in sel]
    pw = [wall(r) for r in sel if r.get("exit") == 0]
    return {"n": len(sel), "median_s": rnd(median(walls)), "p90_s": rnd(percentile(walls, 90)),
            "pass_n": len(pw), "pass_median_s": rnd(median(pw)), "pass_p90_s": rnd(percentile(pw, 90))}


def m_scoped(rows):
    scoped = [r for r in rows if r.get("mode") == "scoped" or "--scoped" in (r.get("force_reason") or "")]
    esc = [r for r in scoped if SCOPED_ESCALATE_MARK in (r.get("force_reason") or "")]
    return {"scoped_runs": len(scoped), "escalated": len(esc), "scoped_escalated_pct": pct(len(esc), len(scoped))}


def ran_count(row):
    """Số suite chạy thật. Từ B9 `suites` chỉ có suite đã chạy (có giây) hoặc không PASS; suite dùng lại KHÔNG nằm trong đó
    (chỉ đếm ở `suites_reused`), nên không trừ suites_reused."""
    timed = sum(1 for s in (row.get("suites") or []) if isinstance(s, (list, tuple)) and len(s) > 2 and s[2] is not None)
    return max(len(row.get("ran_suites") or []), timed)


def m_suites_per_run(rows):
    counts = [c for c in (ran_count(r) for r in rows) if c > 0]
    cut = sum(1 for r in rows if r.get("suites_cut") or r.get("ran_suites_cut"))
    return {"runs_counted": len(counts), "median": rnd(median(counts)), "p90": rnd(percentile(counts, 90)),
            "rows_with_cut_lists": cut}


def m_load(csv_files, since, until):
    vals = []
    for path in csv_files:
        with open(path, newline="", encoding="utf-8", errors="replace") as fh:
            for rec in csv.DictReader(fh):
                try:
                    load = float(rec["load1"])
                    ep = float(rec["epoch"])
                except (KeyError, TypeError, ValueError):
                    continue
                if (since is not None and ep < since) or (until is not None and ep > until):
                    continue
                vals.append(load)
    return {"samples": len(vals), "median": rnd(median(vals), 2), "p90": rnd(percentile(vals, 90), 2)}


def compute(rows, csv_files=None, since=None, until=None):
    out = {
        "rerun_on_red": m_rerun_on_red(rows),
        "busy": m_busy(rows),
        "machine_hours": m_machine_hours(rows),
        "false_red": m_false_red(rows),
        "merge_gate_s": m_merge_gate(rows),
        "scoped_escalated": m_scoped(rows),
        "suites_per_run": m_suites_per_run(rows),
    }
    if csv_files:
        out["load_median"] = m_load(csv_files, since, until)
    return out


def fmt_ts(epoch):
    return datetime.datetime.fromtimestamp(epoch).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def render_text(res):
    m, meta = res["metrics"], res["meta"]
    rr, bz, mh, fr = m["rerun_on_red"], m["busy"], m["machine_hours"], m["false_red"]
    mg, sc, sp = m["merge_gate_s"], m["scoped_escalated"], m["suites_per_run"]
    lines = ["stabilize_metrics: %d lượt (đọc %d dòng, trùng %d, hỏng %d, lọc bỏ %d); %s -> %s" % (
        meta["rows"], meta["lines"], meta["duplicates"], meta["bad_json"], meta["filtered_out"],
        meta["first_ts"] or "-", meta["last_ts"] or "-")]
    lines.append("%-22s %-34s %s" % ("chỉ số", "giá trị", "ghi chú"))
    lines.append("-" * 100)

    def row(name, val, note=""):
        lines.append("%-22s %-34s %s" % (name, val, note))

    row("rerun_on_red", "%d lượt / %.2f h" % (rr["count"], rr["hours"]),
        "%s%% lượt đã chạy; chỉ tính sau lượt exit 1" % rr["pct_of_executed_runs"])
    for k, v in sorted(rr["by_source"].items()):
        row("  nguồn " + k, "%d lượt / %.2f h" % (v["count"], v["hours"]))
    ab = rr["after_blocked"]
    row("  sau exit 2/3 (riêng)", "%d lượt / %.2f h" % (ab["count"], ab["hours"]), "gate chặn: edited_test, matrix... (không phải đỏ)")
    for k, v in sorted(ab["by_prev_exit_reason"].items(), key=lambda kv: -kv[1]["count"]):
        row("    sau " + k, "%d lượt / %.2f h" % (v["count"], v["hours"]))
    row("busy_pct", "%s%% (%d/%d busy true)" % (bz["busy_pct"], bz["busy_flag"], bz["runs"]),
        "exit 4: %d (%s%%)" % (bz["exit4"], bz["exit4_pct"]))
    row("machine_hours", "%.2f h" % mh["total_hours"], "tổng total_wall_s")
    row("  full nặng", "%.2f h (%d lượt)" % (mh["heavy_full_hours"], mh["heavy_full_runs"]),
        "%s%% tổng; full >= %d suite" % (mh["heavy_full_share_pct"], HEAVY_MIN_SUITES))
    row("false_red_pct", "%s%% (%d/%d FAIL)" % (fr["false_red_pct"], fr["false_red"], fr["fail_runs"]),
        "suite đỏ của FAIL nằm trong lượt exit 0 sau đó, cùng fp; %d FAIL không ghi suite đỏ" % fr["undetermined"])
    row("merge_gate_s", "median %s, p90 %s (n=%d)" % (mg["median_s"], mg["p90_s"], mg["n"]),
        "merge_point; riêng PASS: median %s p90 %s n=%d" % (mg["pass_median_s"], mg["pass_p90_s"], mg["pass_n"]))
    row("scoped_escalated_pct", "%s%% (%d/%d)" % (sc["scoped_escalated_pct"], sc["escalated"], sc["scoped_runs"]),
        "lượt --scoped bị leo full")
    row("suites_per_run", "median %s, p90 %s (n=%d)" % (sp["median"], sp["p90"], sp["runs_counted"]),
        "suite chạy thật; %d dòng có danh sách bị cắt (cận dưới)" % sp["rows_with_cut_lists"])
    if "load_median" in m:
        ld = m["load_median"]
        row("load_median", "%s (p90 %s, n=%d)" % (ld["median"], ld["p90"], ld["samples"]), "cột load1 của sampler")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Đo độ ổn định gate DevKit từ runs.jsonl (xem docstring đầu file).")
    ap.add_argument("files", nargs="*", help="file runs.jsonl (mặc định: runs.jsonl + archive/runs-*.jsonl của --repo)")
    ap.add_argument("--repo", default=".", help="repo để tìm common dir khi không truyền file (mặc định thư mục hiện tại)")
    ap.add_argument("--since", help="epoch hoặc ISO-8601")
    ap.add_argument("--until", help="epoch hoặc ISO-8601")
    ap.add_argument("--repo-prefix", action="append", default=[], help="chỉ giữ project == P hoặc P-* (lặp được / dấu phẩy)")
    ap.add_argument("--include-ocr", action="store_true", help="giữ cả project ocr-*")
    ap.add_argument("--sampler-csv", nargs="+", default=[], help="CSV của capacity sampler (cột load1, epoch)")
    ap.add_argument("--json", action="store_true", help="in JSON")
    args = ap.parse_args(argv)

    try:
        since, until = parse_time(args.since), parse_time(args.until)
    except ValueError as exc:
        print("stabilize_metrics: thời gian sai: %s" % exc, file=sys.stderr)
        return 2
    prefixes = [p for chunk in args.repo_prefix for p in chunk.split(",") if p]
    files = list(args.files)
    if not files:
        files, problem = default_inputs(args.repo)
        if problem or not files:
            print("stabilize_metrics: không có runs.jsonl (%s)" % (problem or "chưa có file"), file=sys.stderr)
            return 2
    missing = [f for f in files + args.sampler_csv if not os.path.isfile(f)]
    if missing:
        print("stabilize_metrics: không thấy file: %s" % ", ".join(missing), file=sys.stderr)
        return 2

    rows, stats = load_rows(files, since, until, prefixes, args.include_ocr)
    meta = dict(stats)
    meta.update({"files": files, "rows": len(rows), "repo_prefix": prefixes,
                 "first_ts": fmt_ts(float(rows[0]["epoch"])) if rows else None,
                 "last_ts": fmt_ts(float(rows[-1]["epoch"])) if rows else None})
    res = {"meta": meta, "metrics": compute(rows, args.sampler_csv, since, until)}
    print(json.dumps(res, ensure_ascii=False, indent=2, sort_keys=True) if args.json else render_text(res))
    return 0


if __name__ == "__main__":
    sys.exit(main())
