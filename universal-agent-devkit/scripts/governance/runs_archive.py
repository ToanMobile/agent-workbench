#!/usr/bin/env python3
"""runs_archive.py - lưu trữ runs.jsonl của post-fix-gate theo ngày (plan ổn định 0.5, thẻ #686). Thư viện chuẩn.

Vì sao: <git common dir>/postfix-gate/runs.jsonl bị gate xoay/cắt theo thời gian, mất dữ liệu đo (mốc A phải chép tay).
Mỗi lần chạy (launchd StartInterval 3600) script này:
  1. đọc runs.jsonl (CHỈ ĐỌC, không bao giờ ghi/sửa/xoá file gốc);
  2. lấy các dòng có `epoch` >= mốc lần trước - 6 giờ (mốc = epoch lớn nhất đã thấy, lưu trong
     <common>/postfix-gate/archive/.runs-archive.state, JSON). Gối đầu 6 giờ để không mất dòng ghi muộn hay cùng giây;
     phần gối đầu được bước 3 khử trùng;
  3. nối vào <common>/postfix-gate/archive/runs-<YYYYMMDD>.jsonl, ngày theo `epoch` của DÒNG tính theo UTC (không phụ thuộc
     múi giờ của launchd/TZ; ngày UTC lệch giờ VN 7 tiếng), khử trùng
     bằng sha256 của cả dòng (đọc file ngày đích để biết dòng nào đã có) nên chạy lại bao nhiêu lần cũng không trùng;
  4. ghi nguyên tử: file tạm cùng thư mục + os.replace, dưới flock(<archive>/.lock) để hai lần chạy không đè nhau.
Dòng cuối chưa có "\\n" (gate đang ghi dở) và dòng không phải JSON có `epoch` bị bỏ qua, lần sau sẽ lấy lại nếu hợp lệ.

Dùng:  runs_archive.py --repo <đường dẫn repo>        (common dir lấy từ git rev-parse --git-common-dir)
       runs_archive.py --common-dir <thư mục>          (test: thư mục giả chứa postfix-gate/runs.jsonl)
Thoát 0 kể cả khi chưa có runs.jsonl (không có gì để lưu); 2 khi tham số/repo sai hoặc không ghi được.
"""
import argparse
import fcntl
import hashlib
import json
import math
import os
import subprocess
import sys
import time

STATE_NAME = ".runs-archive.state"
LOCK_NAME = ".lock"
SLACK_S = 6 * 3600     # gối đầu 6 giờ so với mốc (nhiều worktree cùng ghi, epoch tính trước lúc ghi)


def common_dir_of(repo):
    """git common dir của repo (worktree dùng chung), hoặc None."""
    try:
        res = subprocess.run(["git", "-C", repo, "rev-parse", "--git-common-dir"],
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if res.returncode != 0:
        return None
    return os.path.abspath(os.path.join(repo, res.stdout.strip()))


def day_name(epoch):
    return time.strftime("%Y%m%d", time.gmtime(epoch))


def read_state(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return float(json.load(fh).get("last_epoch", 0.0))
    except (OSError, ValueError, TypeError, AttributeError):
        return 0.0     # chưa có / hỏng: lấy lại từ đầu, khử trùng bảo đảm không nhân đôi


def atomic_write(path, data):
    """Ghi bytes `data` vào path qua file tạm cùng thư mục rồi os.replace."""
    tmp = "%s.tmp.%d" % (path, os.getpid())
    try:
        with open(tmp, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def archive(common):
    """Chạy một lượt; trả dict thống kê."""
    base = os.path.join(common, "postfix-gate")
    src = os.path.join(base, "runs.jsonl")
    out = {"read": 0, "new": 0, "duplicate": 0, "skipped": 0, "files": []}
    if not os.path.isfile(src):
        return out
    adir = os.path.join(base, "archive")
    os.makedirs(adir, exist_ok=True)
    with open(os.path.join(adir, LOCK_NAME), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state_path = os.path.join(adir, STATE_NAME)
        since = read_state(state_path)
        with open(src, "rb") as fh:          # chỉ đọc
            content = fh.read()
        now = time.time()
        by_day = {}                           # YYYYMMDD (UTC) -> [(raw, sha)]
        max_epoch = since
        for raw in content.split(b"\n")[:-1]:   # phần tử cuối là đoạn chưa có "\n": bỏ
            raw = raw.strip()
            if not raw:
                continue
            out["read"] += 1
            try:
                epoch = float(json.loads(raw.decode("utf-8"))["epoch"])
            except (ValueError, KeyError, TypeError, OverflowError):
                out["skipped"] += 1
                continue
            # epoch vô lý (NaN, inf, <= 0, xa tương lai) không được đặt mốc hay đặt tên file ngày: bỏ qua, không crash
            if not (math.isfinite(epoch) and 0 < epoch < now + 86400):
                out["skipped"] += 1
                continue
            if epoch < since - SLACK_S:      # chừa một khoảng gối đầu: dòng ghi muộn (epoch nhỏ hơn mốc) vẫn được lấy, dedupe lo phần trùng
                continue
            max_epoch = max(max_epoch, epoch)
            by_day.setdefault(day_name(epoch), []).append((raw, hashlib.sha256(raw).hexdigest()))
        for day, items in sorted(by_day.items()):
            dest = os.path.join(adir, "runs-%s.jsonl" % day)
            existing = b""
            have = set()
            if os.path.isfile(dest):
                with open(dest, "rb") as fh:
                    existing = fh.read()
                for line in existing.split(b"\n"):
                    if line.strip():
                        have.add(hashlib.sha256(line.strip()).hexdigest())
            fresh = []
            for raw, sha in items:
                if sha in have:
                    out["duplicate"] += 1
                    continue
                have.add(sha)
                fresh.append(raw)
            if not fresh:
                continue
            if existing and not existing.endswith(b"\n"):
                existing += b"\n"
            atomic_write(dest, existing + b"\n".join(fresh) + b"\n")
            out["new"] += len(fresh)
            out["files"].append(dest)
        atomic_write(state_path, json.dumps({"last_epoch": max_epoch}).encode("utf-8"))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Nối runs.jsonl vào archive/runs-<ngày>.jsonl (xem docstring đầu file).")
    ap.add_argument("--repo", default=".", help="repo (mặc định thư mục hiện tại)")
    ap.add_argument("--common-dir", help="ghi đè git common dir (dùng cho test)")
    args = ap.parse_args(argv)
    common = args.common_dir or common_dir_of(args.repo)
    if not common or not os.path.isdir(common):
        print("runs_archive: không tìm thấy git common dir (repo=%s)" % args.repo, file=sys.stderr)
        return 2
    try:
        res = archive(common)
    except OSError as exc:
        print("runs_archive: lỗi ghi archive: %s" % exc, file=sys.stderr)
        return 2
    if res["skipped"]:
        print("runs_archive: CẢNH BÁO bỏ qua %d dòng không đọc được hoặc epoch vô lý (NaN, inf, <= 0, xa tương lai)" % res["skipped"],
              file=sys.stderr)
    print("runs_archive: đọc %d dòng, nối %d mới, %d trùng, %d bỏ qua, %d file" % (
        res["read"], res["new"], res["duplicate"], res["skipped"], len(res["files"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
