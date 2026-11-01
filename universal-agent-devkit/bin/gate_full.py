#!/usr/bin/env python3
"""Lượt --full đêm (#644): gate mặc định là scoped, merge/push không còn chạy --full; lượt THẬT SỰ full trên main chạy ở đây — tay
(skill gate-full) hoặc 00:00 mỗi đêm (bin/gate-full-schedule.sh cài LaunchAgent).

  gate_full.py run [--repo PATH] [--ref origin/main] [--max-wait-s 7200] [--slug owner/repo] [--timeout 900] [--dry-run]

Một lượt:
  1. khoá <common>/postfix-gate/gate-full.lock (pid + lúc bắt đầu, O_EXCL): pid còn sống ⇒ "skip", exit 0; pid chết ⇒ chiếm lại;
  1b. khoá TOÀN MÁY DEVKIT_GATE_FULL_GLOBAL_LOCK (mặc định ~/Library/Caches/devkit-gate-full/global.lock, flock + pid/repo): mỗi lúc
     chỉ MỘT lượt gate-full trên cả máy, mọi repo (lịch đêm 00:00 của nhiều repo cùng nổ, nút "Chạy gate full" của Agent Office);
     bận ⇒ chờ, kiểm mỗi DEVKIT_GATE_FULL_GLOBAL_POLL_S (5 s), tối đa DEVKIT_GATE_FULL_GLOBAL_WAIT_S (21600 s) rồi "skip" (nhả khoá repo);
     file khoá không bao giờ bị gỡ (flock trên inode cố định), nhả = đóng fd;
  2. chờ tải 1 phút ≤ capacity.hold_load() (bin/capacity.py), kiểm mỗi DEVKIT_GATE_FULL_POLL_S (60 s), tối đa --max-wait-s rồi chạy luôn;
  3. git fetch origin, resolve sha của --ref;
  4. scratch `git worktree add --detach <common>/postfix-gate/gate-full-scratch-<stamp> <sha>`, cài DevKit như merge train;
  5. `post-fix-gate.py --run-tests --tree HEAD --no-cache --brief --json` (cây đứng yên: --diff rỗng thì luật không khớp file nào bị
     bỏ — post-fix-gate.py `if not rule_files and args.tree is None: continue`; help của --no-cache: chạy test dù PASS full cuối còn
     đúng nội dung này) rồi `agent-kit test` của kit trong cây (REG-DK-ALL-01
     chỉ chạy test impacted — scratch tách rời chọn theo merge-base với main checkout, không phải cả bộ; `agent-kit test` = hook contract
     + workflow + run_impacted.sh --all, ngoài gate vì quá 900 s/lệnh);
  6. xanh ⇒ nightly/full_pass.json, last_full_green_sha, nightly/history.jsonl;
  7. đỏ ⇒ chạy lại CHỈ suite/test đỏ ở đỉnh, rồi chia đôi các merge first-parent last_green..sha (≤ 16; không có last_green: 8 merge gần
     nhất) ra commit nghi vấn, tạo thẻ P1 qua scripts/governance/create_task.py (đã có thẻ mở cùng suite đỏ (tiêu đề P1, hoặc mã suite trong tiêu đề/body) thì comment vào đó, không tạo trùng);
     MỌI suite đỏ đều nhóm b (thời gian thực / môi trường: nhãn "timing": true trong ma trận, dấu hiệu GROUP_B_SIGN trên dòng không
     phải dòng đạt, hoặc chạy lại ở đỉnh xanh) ⇒ result red-env, không chia đôi, thẻ vẫn mở / ghi thêm (#700).
     DEVKIT_GATE_FULL_BISECT=0 không bao giờ chia đôi, =1 luôn chia đôi (ra commit nghi vấn ⇒ red, #748), auto (mặc định) bỏ chia đôi
     khi red-env. Đỏ (red / red-env) ⇒ truy vết (#759): commit first-parent last_green..sha kèm PR / thẻ, với mỗi suite đỏ các commit
     đụng file test + nguồn nó chạm (đồ thị của bin/scoped_gate.py) hay watch_files cụ thể của ma trận, mức tin cậy chắc / nghi / không rõ;
  8. log <DEVKIT_GATE_FULL_LOG_DIR>/<yyyymmdd-HHMMSS>.log + summary-latest.md (kèm truy vết) + trace-latest.json (máy đọc) +
     summary-<yyyymmdd>.md (lịch đêm đặt biến này =
     ~/Library/Logs/devkit-gate-full/<slug> riêng từng repo; chạy tay không đặt: ~/Library/Logs/devkit-gate-full);
  9. finally: gỡ scratch, nhả khoá.
Kết luận: 0 xanh (hoặc skip), 1 đỏ (suite FAIL thật), 3 chưa kết luận (exit 2/4/5, TIMEOUT, BUSY, môi trường — không thẻ, không ghi
last_full_green_sha; red-env cũng 3 nhưng có thẻ), 2 lỗi chuẩn bị (ref, scratch).
Lượt đêm chạy nice 10 do plist (`/usr/bin/nice -n 10`, con thừa hưởng); gate_full.py không tự đặt nice (#696).
Móc test: DEVKIT_GATE_FULL_CMD (lệnh gate thay thế, shell, cwd = scratch; khi đặt thì không chạy agent-kit test),
DEVKIT_GATE_FULL_CARD_CMD (thay `python3 create_task.py`), DEVKIT_GATE_FULL_LOG_DIR, DEVKIT_GATE_FULL_POLL_S,
DEVKIT_GATE_FULL_GLOBAL_LOCK / _GLOBAL_POLL_S / _GLOBAL_WAIT_S (test đặt khoá toàn máy trong thư mục tạm); tải giả qua
DEVKIT_CAPACITY_LOAD / DEVKIT_CAPACITY_CORES của capacity.py. Stdlib."""

from __future__ import annotations

import argparse
import fcntl
import datetime as dt
import glob
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time

BIN = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(BIN)
sys.path.insert(0, BIN)
import capacity  # noqa: E402  nguồn ngưỡng tải chung (bin/capacity.py), chỉ đọc

TEST_PATH = re.compile(r"^\s*✖\s+((?:hooks/)?tests/\S+\.(?:sh|py|mjs))\s*$")
ISSUE_URL = re.compile(r"https://github\.com/[^\s/]+/[^\s/]+/issues/\d+")
# #700: dấu hiệu nhóm b — đỏ vì thời gian thực / môi trường (watchdog 7 s của hook, bài bị run_bounded.py giết khi quá hạn, SIGKILL): chạy
# lại ở commit cũ cũng đỏ y như vậy nên chia đôi không quy được cho ai. Chỉ xét dòng KHÔNG phải dòng đạt. Không có chữ TIMEOUT: không runner
# nào in nó vào output bài test (suite TIMEOUT đã là env_red), chỉ test của chính gate in — đỏ thật của gate sẽ bị tính nhóm b.
# ponytail: test về chính watchdog / run_bounded in các dấu hiệu này cả khi đỏ thật; chỉ bỏ chia đôi khi MỌI ca đỏ đều có dấu hiệu và thẻ
# vẫn ghi đủ suite — gặp ca đổ oan thì thu hẹp mẫu về đúng dòng của runner.
GROUP_B_SIGN = re.compile(r"quá lớn / quá phức tạp để phân tích trong thời hạn|killed after \d+(?:\.\d+)?s \(deadline\)|\bKilled: 9\b")
# tổng kết của tests/lib/case_runner.sh hc_summary khi mọi ca không đạt đều ENV-BLOCKED (watchdog dưới tải, #714) và không ca nào lệch
ENV_BLOCKED_SUMMARY = re.compile(r"^ENV-BLOCKED: hook watchdog fired under load, no verdict\s*$", re.M)
PASS_HEAD = re.compile(r"^\s*(?:✔|✓|✅|ok\b|PASS\b)")
FAIL_BLOCK = re.compile(r"^\s*(?:✖|✘|✗|❌|not ok\b)")
# bỏ dòng tổng đếm cuối file test ("FAIL: 2 case(s)", "FAIL (2)", "FAIL: 2", "FAIL test_x (2)"): nó đếm lại các ca ✖ đã xét, không là lá
BARE_FAIL = re.compile(r"^\s*FAIL\b(?!:?\s*(?:\(\d+\)|\d+(?:\s+(?:case\(s\)|cases?\b).*)?|test_\w+\s+\(\d+\))\s*$)")
# #749: dòng hỏng khác ngoài khối — có nó thì dòng tổng kết ENV-BLOCKED không đủ để gọi là nhóm b
OTHER_FAIL = re.compile(r"^\s*(?:FAIL(?:ED)?\b|Traceback \(most recent call last\):)", re.M)
# #749: post-fix-gate flaky_retry nối "lần đầu + mốc này + lần chạy lại" vào cùng output / log bằng chứng
RETRY_MARK = re.compile(r"^# --- chạy lại 1 lần \((?:FLAKY|INFRA)_RETRY\) — exit -?\d+ ---\s*$")
# #749: regression_checklist.write_evidence giữ 1 MB cuối của log lớn, thân log mở đầu bằng dòng này. Tìm ở mọi dòng chứ không neo đầu
# file: giá trị "# command:" nhiều dòng làm lệch phần đầu; dòng này lọt vào output thật thì chỉ thêm một lần chia đôi (phía an toàn)
TRUNCATED_HEAD = re.compile(r"^… \(đầu log bị cắt", re.M)
FETCH_TIMEOUT_S = 300
GATE_TIMEOUT_S = 6 * 3600       # trần cả lượt gate (mỗi suite đã có --timeout riêng)
KIT_TEST_TIMEOUT_S = 2 * 3600   # agent-kit test cả bộ (~5–10 phút lúc rảnh)


class Run:
    """Trạng thái một lượt: log, tóm tắt."""

    def __init__(self, log_dir: str):
        self.log_dir = log_dir
        os.makedirs(log_dir, exist_ok=True)
        self.started = dt.datetime.now()
        self.stamp = self.started.strftime("%Y%m%d-%H%M%S")
        self.log_path = os.path.join(log_dir, self.stamp + ".log")
        self.log_f = open(self.log_path, "a", encoding="utf-8")
        self.info = {"result": "?", "ref": "", "sha": "", "load_start": None, "hold_load": None, "waited_s": 0,
                     "wait_note": "", "red": [], "env_red": [], "group_b": [], "suspect": "", "suspect_note": "", "card": "",
                     "notes": [], "trace": None}

    def log(self, msg: str) -> None:
        line = "[gate-full %s] %s" % (dt.datetime.now().strftime("%H:%M:%S"), msg)
        print(line, flush=True)
        self.log_f.write(line + "\n")
        self.log_f.flush()

    def raw(self, text: str) -> None:
        self.log_f.write(text if text.endswith("\n") else text + "\n")
        self.log_f.flush()

    def summary(self) -> str:
        i = self.info
        dur = int((dt.datetime.now() - self.started).total_seconds())
        label = {"green": "XANH", "red": "ĐỎ", "red-env": "ĐỎ NHÓM B (thời gian thực / môi trường, red-env)", "inconclusive": "CHƯA KẾT LUẬN",
                 "aborted": "BỊ DỪNG (aborted)", "skip": "skip", "error": "LỖI"}.get(i["result"], i["result"])
        out = ["# gate-full đêm %s" % self.started.strftime("%Y-%m-%d %H:%M:%S"), "",
               "- Kết quả: **%s**" % label,
               "- Ref: %s @ %s" % (i["ref"] or "-", i["sha"][:12] or "-"),
               "- Thời gian: %d phút %d giây" % (dur // 60, dur % 60),
               "- Tải lúc bắt đầu: %s (ngưỡng hold_load %s)" % (_fmt(i["load_start"]), i["hold_load"] if i["hold_load"] is not None else "-"),
               "- Chờ tải: %s" % (("%d giây — %s" % (i["waited_s"], i["wait_note"])) if i["waited_s"] or i["wait_note"] else "không")]
        if i["red"]:
            out.append("- Suite/test đỏ: " + ", ".join(i["red"]))
        if i["group_b"]:
            out.append("- Suite đỏ nhóm b (thời gian thực / môi trường): " + ", ".join(i["group_b"]))
        if i["env_red"]:
            out.append("- Đỏ do môi trường (không tính): " + ", ".join(i["env_red"]))
        if i["suspect"] or i["suspect_note"]:
            out.append("- Commit nghi vấn: %s %s" % (i["suspect"] or "-", i["suspect_note"]))
        if i["card"]:
            out.append("- Thẻ: " + i["card"])
        for n in i["notes"]:
            out.append("- Ghi chú: " + n)
        out.append("- Log: " + self.log_path)
        tr = i["trace"]
        if tr:
            def ref(c):
                s = "PR #%d" % c["pr"] if c.get("pr") else c["sha"][:12]
                return s + (" (thẻ %s)" % " ".join("#%d" % n for n in c["issues"]) if c.get("issues") else "")
            out += ["", "## Truy vết (#759)", "",
                    "- Khoảng: %s — %d commit first-parent: %s" % (tr["range"], len(tr["commits"]),
                                                                 ", ".join(ref(c) for c in tr["commits"]) or "-")]
            for t in tr["tests"]:
                out.append("- %s%s: %s" % (t["id"], " (%s)" % ", ".join(t["files"]) if t["files"] else "", "; ".join(
                    "%s %s — %s" % (c["confidence"], ref(c), c["why"]) if c.get("sha") else "%s — %s" % (c["confidence"], c["why"])
                    for c in t["candidates"])))
            out.append("- JSON: " + os.path.join(self.log_dir, "trace-latest.json"))
        return "\n".join(out) + "\n"

    def finish(self) -> None:
        text = self.summary()
        # lượt skip (lượt trước còn giữ khoá) chỉ ghi vào log của chính nó: không đè summary của lượt chạy thật đang / vừa chạy
        for name in () if self.info["result"] == "skip" else ("summary-latest.md", "summary-%s.md" % self.started.strftime("%Y%m%d")):
            _write(os.path.join(self.log_dir, name), text)
        if self.info["result"] != "skip":   # máy đọc (#759): cùng lượt với summary-latest.md; lượt không đỏ thì "tests" rỗng
            i = self.info
            _write(os.path.join(self.log_dir, "trace-latest.json"), json.dumps(dict(
                {"at": self.started.isoformat(timespec="seconds"), "result": i["result"], "ref": i["ref"], "sha": i["sha"],
                 "suspect": i["suspect"], "last_green": "", "range": "", "commits": [], "tests": []}, **(i["trace"] or {})),
                ensure_ascii=False, indent=1) + "\n")
        self.raw(text)
        self.log_f.close()


def _fmt(v):
    return "-" if v is None else ("%.2f" % v)


def _write(path: str, text: str) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def sh(cmd, cwd=None, timeout=None, env=None, shell=False):
    """(exit, stdout+stderr) trong process group riêng: hết giờ / SIGTERM thì giết cả cây con. Hết giờ: exit 124."""
    p = subprocess.Popen(cmd, cwd=cwd, env=env, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, errors="replace", start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out
    except subprocess.TimeoutExpired:
        _kill_group(p)
        out, _ = p.communicate()
        return 124, (out or "") + "\n[gate-full] TIMEOUT after %ss\n" % timeout
    except BaseException:   # SIGTERM (SystemExit) / ^C: không để cây con sống sót rồi re-raise
        _kill_group(p)
        raise


def _kill_group(p) -> None:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(p.pid, sig)
        except (ProcessLookupError, PermissionError):
            return
        try:
            p.wait(timeout=10)
            return
        except subprocess.TimeoutExpired:
            continue


def git(repo, *args, timeout=120):
    return sh(["git", "-C", repo] + list(args), timeout=timeout)


def git_out(repo, *args) -> str:
    rc, out = git(repo, *args)
    return out.strip() if rc == 0 else ""


# --- khoá ---------------------------------------------------------------------------------------------------------------------

def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _lock_pid(path: str):
    try:
        raw = open(path, encoding="utf-8").read().strip()
    except OSError:
        return None
    try:
        return int(json.loads(raw).get("pid"))
    except (ValueError, TypeError, AttributeError):
        m = re.match(r"\d+", raw)
        return int(m.group(0)) if m else None


_LOCK_FD = None   # fd giữ flock suốt tiến trình (đóng là nhả khoá)


def acquire_lock(path: str):
    """None khi đã chiếm; pid của lượt đang chạy khi phải skip (-1: lượt kia chưa kịp ghi pid).
    Khoá thật là flock trên file (không còn khe giữa tạo file và ghi pid để lượt thứ hai đọc file rỗng rồi gỡ khoá của lượt đầu); pid trong
    file chỉ để hiển thị, cộng một luật cũ: pid sống khác mình (khoá ghi tay / bản cũ không flock) cũng là bận."""
    global _LOCK_FD
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for _ in range(3):
        fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            return _lock_pid(path) or -1
        try:
            same = os.fstat(fd).st_ino == os.stat(path).st_ino
        except FileNotFoundError:
            same = False
        if not same:   # lượt trước vừa gỡ file sau khi ta mở: khoá inode cũ vô nghĩa, mở lại
            os.close(fd)
            continue
        pid = _lock_pid(path)
        if pid and pid != os.getpid() and _alive(pid):
            os.close(fd)   # không đụng nội dung khoá của lượt kia
            return pid
        os.ftruncate(fd, 0)
        os.write(fd, json.dumps({"pid": os.getpid(), "started": dt.datetime.now().isoformat(timespec="seconds")}).encode())
        _LOCK_FD = fd
        return None
    return _lock_pid(path) or -1   # file khoá bị thay liên tục giữa các lần thử


def release_lock(path: str) -> None:
    global _LOCK_FD
    if _LOCK_FD is None:   # chỉ nhả khoá của chính mình
        return
    try:
        os.unlink(path)   # gỡ khi còn giữ flock: lượt sau mở inode mới (acquire_lock so inode)
    except FileNotFoundError:
        pass
    os.close(_LOCK_FD)
    _LOCK_FD = None


_GLOBAL_FD = None   # fd giữ flock khoá toàn máy


def global_lock_path() -> str:
    return os.environ.get("DEVKIT_GATE_FULL_GLOBAL_LOCK") or os.path.expanduser("~/Library/Caches/devkit-gate-full/global.lock")


def _global_holder(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as f:
            d = json.loads(f.read() or "{}")
        return "pid %s, repo %s, từ %s" % (d.get("pid"), d.get("repo"), d.get("started"))
    except (OSError, ValueError):
        return "chưa rõ"


def acquire_global(run: "Run", repo: str) -> bool:
    """Chờ khoá toàn máy (một lượt gate-full mỗi lúc trên cả máy). False khi chờ quá DEVKIT_GATE_FULL_GLOBAL_WAIT_S.
    Không gỡ file khoá khi nhả (khác khoá repo): mọi lượt flock cùng một inode nên không có khe đổi inode; Agent Office dò bằng LOCK_SH|NB."""
    global _GLOBAL_FD
    path = global_lock_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    poll = float(os.environ.get("DEVKIT_GATE_FULL_GLOBAL_POLL_S") or 5)
    max_wait = float(os.environ.get("DEVKIT_GATE_FULL_GLOBAL_WAIT_S") or 21600)
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
    start = time.monotonic()
    waited = False
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError:
            if not waited:
                run.log("chờ khoá toàn máy %s: lượt gate-full khác đang chạy (%s)" % (path, _global_holder(path)))
                waited = True
            left = max_wait - (time.monotonic() - start)
            if left <= 0:
                os.close(fd)
                run.info["global_wait_s"] = int(time.monotonic() - start)
                return False
            time.sleep(max(0.05, min(poll, left)))
    os.ftruncate(fd, 0)
    os.write(fd, json.dumps({"pid": os.getpid(), "started": dt.datetime.now().isoformat(timespec="seconds"), "repo": repo}).encode())
    _GLOBAL_FD = fd
    if waited:
        run.info["global_wait_s"] = int(time.monotonic() - start)
        run.log("có khoá toàn máy sau %d giây" % run.info["global_wait_s"])
    return True


def release_global() -> None:
    global _GLOBAL_FD
    if _GLOBAL_FD is None:
        return
    try:
        os.ftruncate(_GLOBAL_FD, 0)
    except OSError:
        pass
    os.close(_GLOBAL_FD)
    _GLOBAL_FD = None


# --- scratch ------------------------------------------------------------------------------------------------------------------

def remove_scratch(repo: str, path: str) -> None:
    git(repo, "worktree", "remove", "--force", path)
    if os.path.isdir(path):
        shutil.rmtree(path, ignore_errors=True)
    git(repo, "worktree", "prune")


def install_devkit(run: Run, repo: str, scratch: str) -> None:
    """Như super-board-merge-train.sh: install.sh -t <scratch> -a claude -y --no-githooks, trả file đã theo dõi về commit, rồi
    super-board-scratch-config.sh. Kit của chính cây scratch trước (đúng phiên bản của ref), rồi kit của repo."""
    for c in (os.path.join(scratch, "universal-agent-devkit"), os.path.join(repo, "universal-agent-devkit"),
              os.path.join(repo, ".agents", "devkit")):
        inst = os.path.join(c, "bin", "install.sh")
        if os.path.isfile(inst):
            rc, out = sh(["bash", inst, "-t", scratch, "-a", "claude", "-y", "--no-githooks"], timeout=1800)
            run.raw(out)
            if rc != 0:
                run.log("cài DevKit vào scratch lỗi (exit %d): %s" % (rc, " ".join(out.strip().splitlines()[-3:])))
            git(scratch, "checkout", "-q", "--", ".")
            break
    cfg = os.path.join(repo, ".claude", "bin", "super-board-scratch-config.sh")
    if os.path.isfile(cfg):
        rc, out = sh(["bash", cfg, repo, scratch], timeout=600)
        run.raw(out)


def scratch_kit(scratch: str):
    for c in ("universal-agent-devkit", os.path.join(".agents", "devkit")):
        if os.path.isfile(os.path.join(scratch, c, "bin", "post-fix-gate.py")):
            return c
    return None


# --- phân tích kết quả -------------------------------------------------------------------------------------------------------

def last_json(out: str) -> dict:
    for line in reversed((out or "").splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                v = json.loads(line)
                return v if isinstance(v, dict) else {}
            except ValueError:
                continue
    return {}


def test_paths(text: str, kit_dir: str) -> list:
    """Đường dẫn ✖ tests/… (run_impacted.sh in tương đối với kit) còn tồn tại trong kit của scratch."""
    seen = []
    for line in (text or "").splitlines():
        m = TEST_PATH.match(line)
        if m and m.group(1) not in seen and kit_dir and os.path.isfile(os.path.join(kit_dir, m.group(1))):
            seen.append(m.group(1))
    return seen


def group_b_text(text: str) -> bool:
    """Nhóm b khi MỌI khối hỏng LÁ có dấu hiệu GROUP_B_SIGN (trên dòng không phải dòng đạt); không có khối nào thì chỉ khi có dòng tổng
    kết ENV_BLOCKED_SUMMARY. Khối = dòng mở đầu ✖/✘/✗/❌/not ok + các dòng thụt sâu hơn ngay sau nó; dòng mở đầu thụt sâu hơn mở khối con,
    khối có khối con chỉ xét qua các khối con (một file test có ca watchdog lẫn ca đỏ thật là đỏ thật). Cùng dòng mở đầu dưới cùng khối cha
    lặp lại (fail_lines + đuôi output) là một khối. Dòng "FAIL <ca>" trần (danh sách chạy của hook_contract_test.sh) không mở khối.
    #749: mỗi lần chạy (lần đầu, mỗi lần chạy lại sau RETRY_MARK) xét riêng — lần đầu đỏ thật, lần lại dính watchdog cùng tên ca là đỏ thật;
    dòng chi tiết "FAIL …" trần không dấu hiệu là một lá đỏ thật (khối có con hay khối lá: dấu hiệu ở dòng khác có thể là của ca khác,
    như 'Killed: 9' của helper bị giết); log bằng chứng bị cắt đầu (ca đỏ thật có thể nằm ở phần bị cắt) không bao giờ là nhóm b; không
    có khối thì dòng tổng kết chỉ đủ khi không có Traceback / dòng FAIL(ED) trần.
    ponytail: không có log bằng chứng (chỉ fail_lines + đuôi) mà đuôi có mốc chạy lại thì fail_lines (dòng mở đầu, không chi tiết) thành lá
    không dấu hiệu ở lần đầu ⇒ không nhóm b — phía an toàn (thêm một lần chia đôi); post-fix-gate vốn luôn ghi log bằng chứng."""
    text = text or ""
    if TRUNCATED_HEAD.search(text):
        return False
    blocks, parents, bare, stack, run_no = {}, set(), set(), [], 0   # stack: [(thụt lề, khoá khối)] từ ngoài vào trong
    for line in text.splitlines():
        if RETRY_MARK.match(line):
            run_no, stack = run_no + 1, []
            continue
        if not line.strip():
            continue   # dòng trống không đóng khối
        ind = len(line) - len(line.lstrip())
        while stack and ind <= stack[-1][0]:
            stack.pop()
        sign = bool(GROUP_B_SIGN.search(line)) and not PASS_HEAD.match(line)
        if FAIL_BLOCK.match(line):
            parent = stack[-1][1] if stack else None
            if parent is not None:
                parents.add(parent)
            key = (run_no, parent, line.strip())
            blocks[key] = blocks.get(key, False) or sign
            stack.append((ind, key))
        elif stack:
            key = stack[-1][1]   # dòng chi tiết thuộc khối trong cùng
            blocks[key] = blocks[key] or sign
            if not sign and BARE_FAIL.match(line):
                bare.add(key)
    leaves = [v for k, v in blocks.items() if k not in parents] + [False for _ in bare]
    if leaves:
        return all(leaves)
    return bool(ENV_BLOCKED_SUMMARY.search(text)) and not OTHER_FAIL.search(text)


def suite_output(run: Run, scratch: str, t: dict, fallback: str) -> str:
    """Toàn văn output của suite đỏ để phân loại nhóm b: log bằng chứng post-fix-gate ghi trong scratch (t["log"], 1 MB cuối) — fail_lines
    chỉ có 8 dòng đầu khớp FAIL (dòng ✔ … FAIL … chiếm chỗ), đuôi 2000 ký tự: ca đỏ thật ở giữa log nằm ngoài cả hai. Không có log ⇒ fallback."""
    log = t.get("log")
    if not (scratch and isinstance(log, str) and log):
        return fallback
    try:
        with open(os.path.join(scratch, log), encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError as exc:
        run.log("không đọc được log suite %s (%s): phân loại theo fail_lines + đuôi output" % (t.get("id"), exc))
        return fallback


def timing_ids(matrix_path: str) -> set:
    """Mã suite gắn "timing": true trong ma trận gate đã dùng (gate --json ghi matrix_path); đọc lỗi ⇒ không suite nào."""
    try:
        with open(matrix_path or "", encoding="utf-8") as f:
            rules = json.load(f).get("rules") or []
    except (OSError, ValueError, AttributeError):
        return set()
    return {t.get("id") for r in rules if isinstance(r, dict) for t in r.get("mandatory_regression_tests") or []
            if isinstance(t, dict) and t.get("timing") is True}


def _full_gate_out(scratch: str, gate_out: str) -> str:
    gitdir = git_out(scratch, "rev-parse", "--absolute-git-dir") if scratch and os.path.isdir(scratch) else ""
    last_out = os.path.join(gitdir, "postfix-gate", "last_output.log") if gitdir else ""
    if last_out and os.path.isfile(last_out):   # --brief: toàn văn (✖ tests/… của REG-DK-ALL-01) nằm ở đây
        try:
            with open(last_out, encoding="utf-8", errors="replace") as f:
                return f.read() + "\n" + gate_out
        except OSError as exc:
            return gate_out + "\n[gate-full] không đọc được last_output.log: %s\n" % exc
    return gate_out


def collect_red(run: Run, scratch: str, kit_rel, gate_rc: int, gate_out: str, kit_rc, kit_out: str,
                record_notes: bool = True):
    """(verdict, checks). checks: [(nhãn, lệnh shell, cwd tương đối scratch)] — chỉ phần đỏ để chạy lại khi chia đôi."""
    data = last_json(gate_out)
    kit_dir = os.path.join(scratch, kit_rel) if kit_rel else ""
    timing = timing_ids(data.get("matrix_path"))
    checks, red, env_red, group_b = [], [], [], []
    for t in data.get("regression_tests") or []:
        if not isinstance(t, dict):
            continue
        st, sid, cmd = t.get("status"), t.get("id") or "?", t.get("command") or ""
        if st == "FAIL" and t.get("env_blocked"):
            env_red.append(sid)
        elif st == "FAIL":
            red.append(sid)
            # "--" ở cột 0 đóng mọi khối: output_tail = out[-2000:] mở đầu bằng mẩu cắt dở, không được dính vào khối cuối của fail_lines
            text = "\n".join((t.get("fail_lines") or []) + ["--", t.get("output_tail") or ""])
            paths = test_paths(text, kit_dir) if "run_impacted.sh" in cmd else []
            if paths:
                checks += [("%s:%s" % (sid, p), "bash " + shlex.quote(p), kit_rel) for p in paths]
            elif cmd:
                checks.append((sid, cmd, "."))
            if sid in timing or group_b_text(suite_output(run, scratch, t, text)):
                group_b.append(sid)
        elif st in ("TIMEOUT", "UNTESTED"):
            env_red.append("%s (%s)" % (sid, st))
    if kit_rc not in (None, 0):
        paths = test_paths(kit_out, kit_dir)
        if paths:
            red.append("agent-kit test")
            checks += [("agent-kit test:%s" % p, "bash " + shlex.quote(p), kit_rel) for p in paths]
        elif kit_rc == 124:
            env_red.append("agent-kit test (TIMEOUT)")
        else:
            red.append("agent-kit test")
            checks.append(("agent-kit test", "bash %s/bin/agent-kit test" % shlex.quote(kit_rel), "."))
        if kit_rc != 124 and group_b_text(kit_out):
            group_b.append("agent-kit test")
    run.info["red"], run.info["env_red"], run.info["group_b"] = red, env_red, group_b
    if red:
        return "red", checks
    if gate_rc == 0 and data.get("accepted", True) is not False and kit_rc in (None, 0):
        return "green", []
    why = "gate exit %d" % gate_rc
    if data.get("busy"):
        why += " (BUSY)"
    if "--tree:" in (gate_out or ""):
        why += " (--tree từ chối cây scratch: xem log)"
    if record_notes:
        run.info["notes"].append(why + " — không có suite FAIL thật: không thẻ, không ghi last_full_green_sha")
    return "inconclusive", []


# --- chia đôi -----------------------------------------------------------------------------------------------------------------

FAIL_HEAD = re.compile(r"^[ \t]*(?:✖|✘|✗|❌|FAIL|not ok)")   # #721: cùng mẫu dk_fail_lines của tests/run_impacted.sh


def red_excerpt(out: str, tail: int = 15, cap: int = 40) -> str:
    """15 dòng cuối của một lần chạy lại đỏ, trước đó các dòng hỏng nằm sớm hơn (tối đa 40) — #721: log chia đôi 31/10 chỉ có
    'failures: 2', hai dòng ✖ A33/A23 nằm trước 15 dòng cuối."""
    lines = (out or "").splitlines()
    early = [l for l in lines[:-tail] if FAIL_HEAD.match(l)]
    more = ["… còn %d dòng hỏng nữa" % (len(early) - cap)] if len(early) > cap else []
    return "\n".join(early[:cap] + more + (["… (%d dòng cuối)" % tail] if early else []) + lines[-tail:])


def checks_fail(run: Run, scratch: str, checks: list, timeout: int) -> str:
    """"bad" (một phần đỏ chạy lại vẫn đỏ), "good", hay "timeout" (hết giờ: không kết luận được commit này)."""
    for label, cmd, cwd in checks:
        d = os.path.join(scratch, cwd)
        if cwd != "." and not os.path.isdir(d):
            continue
        m = re.match(r"bash '?([^' ]+)'?$", cmd)
        if m and cwd != "." and not os.path.isfile(os.path.join(d, m.group(1))):
            continue   # test chưa có ở commit này: chưa vỡ ở đây
        rc, out = sh(cmd, cwd=d, timeout=KIT_TEST_TIMEOUT_S if "agent-kit" in cmd else timeout, shell=True)
        run.raw("$ (%s) %s -> %d\n%s" % (label, cmd, rc, red_excerpt(out) if rc else "\n".join(out.splitlines()[-15:])))
        if rc == 124:
            return "timeout"
        if rc != 0:
            return "bad"
    return "good"


TIP_GOOD = "(không tái hiện khi chạy lại ở đỉnh: flaky?)"


def bisect(run: Run, repo: str, scratch: str, sha: str, last_green: str, checks: list, timeout: int):
    """(commit nghi vấn, ghi chú). Đỉnh không tái hiện thì không nghi ai (flaky); hết giờ giữa chừng thì chỉ báo khoảng còn lại —
    một lần chạy lại hết giờ không phải "đỏ", tính nó là đỏ thì mọi điểm giữa đều đỏ và thẻ đổ oan cho merge cũ nhất."""
    tip = checks_fail(run, scratch, checks, timeout)
    if tip == "good":
        return "", TIP_GOOD
    if tip == "timeout":
        return "", "(chạy lại ở đỉnh hết giờ: không chia đôi)"
    known_good = bool(last_green) and git(repo, "merge-base", "--is-ancestor", last_green, sha)[0] == 0
    # mọi commit first-parent (không chỉ merge): repo land bằng squash / fast-forward không có merge nào, `--merges` rỗng thì luôn đổ cho đỉnh
    # ponytail: tối đa 16 commit từ last_green (8 khi không có), main đi > 16 commit một đêm thì commit cũ nhất trong cửa sổ có thể bị đổ oan
    if known_good:
        merges = git_out(repo, "rev-list", "--first-parent", "--reverse", "%s..%s" % (last_green, sha)).split()[-16:]
    else:
        merges = list(reversed(git_out(repo, "rev-list", "--first-parent", "-n", "8", sha).split()))
    if not merges:
        return sha, "(không có commit trong phạm vi: chính đỉnh)"
    run.log("chia đôi %d commit first-parent (%s)" % (len(merges), "từ last_green" if known_good else "8 commit gần nhất, không có last_green"))
    lo, hi = 0, len(merges)   # merges[hi] = đỉnh, đã biết đỏ
    while lo < hi:
        mid = (lo + hi) // 2
        git(scratch, "checkout", "-q", "-f", "--detach", merges[mid])
        state = checks_fail(run, scratch, checks, timeout)
        run.log("  %s %s" % (merges[mid][:12], {"bad": "đỏ", "good": "xanh"}.get(state, "hết giờ")))
        if state == "timeout":
            end = merges[hi][:12] if hi < len(merges) else sha[:12]
            return "", "(hết giờ ở %s: nghi vấn trong khoảng %s..%s)" % (merges[mid][:12], merges[lo][:12], end)
        if state == "bad":
            hi = mid
        else:
            lo = mid + 1
    if lo == len(merges):
        return sha, "(sau merge cuối: commit trên first-parent tới đỉnh)"
    if not known_good and lo == 0:   # không có mốc xanh: chưa chứng minh merge cũ nhất là chỗ vỡ đầu tiên
        return "", "(merge cũ nhất trong 8 — %s — đã đỏ: vỡ từ trước phạm vi, chưa có last_full_green_sha)" % merges[0][:12]
    if lo == 0:   # mốc xanh là của lượt trước, lượt này không chạy lại: chưa thấy commit nào xanh (#748 không coi đây là tái hiện)
        return merges[0], "(commit đầu tiên sau last_full_green_sha; lượt này chưa thấy commit nào xanh)"
    return merges[lo], ""


# --- truy vết (#759) ----------------------------------------------------------------------------------------------------------

# ponytail: "(#N)" cuối tiêu đề là số PR với squash merge của GitHub; commit đẩy thẳng lên trunk ghi "(#<thẻ>)" thì N là thẻ — không
# hỏi GitHub (lượt đêm không phụ thuộc mạng); cần phân biệt thì tra `gh pr view N` lúc đọc
PR_REF = re.compile(r"\(#(\d+)\)|^Merge pull request #(\d+)\b")
ISSUE_REF = re.compile(r"\b(?:refs|closes|fixes|resolves)\s+#(\d+)", re.I)
TRACE_MAX = 40   # commit first-parent tối đa trong khoảng truy vết


def _commit_info(repo: str, c: str) -> dict:
    """sha, PR (số "(#N)" cuối tiêu đề — squash merge của GitHub), thẻ (#N khác trong tiêu đề + Refs/Closes/Fixes #N trong body), file đổi
    so với cha first-parent."""
    rc, out = git(repo, "log", "-1", "--format=%s%x00%b", c)
    subj, _, body = (out if rc == 0 else "").partition("\x00")
    subj = subj.strip()
    prs = [a or b for a, b in PR_REF.findall(subj)]
    pr = int(prs[-1]) if prs else None
    issues = sorted({int(n) for n in re.findall(r"#(\d+)", subj) + ISSUE_REF.findall(body)} - {pr})
    files = git_out(repo, "diff", "--name-only", "--no-renames", c + "^", c).splitlines()
    return {"sha": c, "pr": pr, "issues": issues, "subject": subj, "files": files}


def _suite_files(scratch: str, checks: list, sid: str) -> list:
    """File test của một suite đỏ, tương đối gốc repo: đường dẫn tests/… của run_impacted (nhãn "<suite>:<test>") hoặc token của lệnh là
    file có trong scratch."""
    out = []
    for label, cmd, cwd in checks:
        if label.split(":")[0] != sid:
            continue
        if ":" in label:
            cand = [os.path.normpath(os.path.join(cwd, label.split(":", 1)[1]))]
        else:
            try:
                cand = shlex.split(cmd)
            except ValueError:
                cand = cmd.split()
        out += [p for p in cand if p not in out and not os.path.isabs(p) and not p.startswith("..")
                and os.path.isfile(os.path.join(scratch, p))]
    return out


def _watch_globs(matrix_path: str, sid: str) -> list:
    """watch_files cụ thể của các luật ma trận nêu suite này (bỏ `*` / `<thư mục cấp 1>/**`: phủ cả repo, không chỉ ra ai)."""
    import scoped_gate
    try:
        with open(matrix_path or "", encoding="utf-8") as f:
            rules = json.load(f).get("rules") or []
    except (OSError, ValueError, AttributeError):
        return []
    globs = []
    for r in rules:
        if isinstance(r, dict) and any(isinstance(t, dict) and t.get("id") == sid for t in r.get("mandatory_regression_tests") or []):
            globs += [p for p in r.get("watch_files") or [] if isinstance(p, str) and not scoped_gate._catch_all(p) and p not in globs]
    return globs


def trace(run: Run, repo: str, scratch: str, sha: str, last_green: str, checks: list, matrix_path: str) -> dict:
    """Truy vết một lượt đỏ (#759): commit first-parent last_green..sha (không có mốc xanh: 8 commit gần nhất như chia đôi), với mỗi suite
    đỏ các commit đụng file test, nguồn test chạm tới (bao đóng của bin/scoped_gate.py trên scratch @ sha) hoặc watch_files cụ thể của nó.
    Mức tin cậy: "chắc" = commit nghi vấn của chia đôi (tái hiện: đỉnh đỏ, commit trước xanh) VÀ đụng file của suite; "nghi" = chỉ một
    trong hai; "không rõ" = không commit nào trong khoảng đụng tới."""
    import scoped_gate
    known_good = bool(last_green) and git(repo, "merge-base", "--is-ancestor", last_green, sha)[0] == 0
    revs = git_out(repo, "rev-list", "--first-parent", "%s..%s" % (last_green, sha)) if known_good \
        else git_out(repo, "rev-list", "--first-parent", "-n", "8", sha)
    revs = revs.split()
    # ponytail: giữ TRACE_MAX commit MỚI nhất (như chia đôi giữ 16); bị cắt thì khoảng ghi rõ số commit cũ hơn không xét
    commits = [_commit_info(repo, c) for c in revs[:TRACE_MAX]]   # mới nhất trước
    git(scratch, "checkout", "-q", "-f", "--detach", sha)   # chia đôi có thể để scratch ở commit cũ
    tm = None
    tests = []
    for sid in run.info["red"]:
        files = _suite_files(scratch, checks, sid)
        if files and tm is None:
            tm = scoped_gate.test_map(scratch)
        related = set(files) | {f for f, ts in (tm or {}).items() if set(ts) & set(files)}
        globs = _watch_globs(matrix_path, sid)
        cands = []
        for c in commits:
            hit = [f for f in c["files"] if f in related or any(scoped_gate.match_pattern(f, g) for g in globs)]
            suspect = c["sha"] == run.info["suspect"]
            if not hit and not suspect:
                continue
            why = ("commit nghi vấn của chia đôi" if suspect else "") + (", " if suspect and hit else "") + \
                  ("đụng " + ", ".join(hit[:3]) + (" (+%d)" % (len(hit) - 3) if len(hit) > 3 else "") if hit else "")
            cands.append({"sha": c["sha"], "pr": c["pr"], "issues": c["issues"], "confidence": "chắc" if suspect and hit else "nghi",
                          "why": why})
        cands.sort(key=lambda x: x["confidence"] != "chắc")
        tests.append({"id": sid, "files": files, "candidates": cands or [{"confidence": "không rõ",
                      "why": "không commit nào trong khoảng đụng file test / nguồn liên quan"}]})
    rng = "%s..%s" % (last_green[:12], sha[:12]) if known_good else "8 commit gần nhất (%s)" % (
        "last_full_green_sha %s không phải tổ tiên của đỉnh" % last_green[:12] if last_green else "chưa có ref xanh")
    if len(revs) > TRACE_MAX:
        rng += " — chỉ xét %d commit mới nhất, %d commit cũ hơn không xét" % (TRACE_MAX, len(revs) - TRACE_MAX)
    return {"last_green": last_green if known_good else "", "range": rng,
            "commits": [{k: c[k] for k in ("sha", "pr", "issues", "subject")} for c in commits], "tests": tests}


# --- thẻ P1 -------------------------------------------------------------------------------------------------------------------

def origin_slug(repo: str) -> str:
    url = git_out(repo, "remote", "get-url", "origin")
    m = re.search(r"github\.com[:/]+([^/\s]+)/([^/\s]+?)(?:\.git)?/?$", url)
    return "%s/%s" % (m.group(1), m.group(2)) if m else ""


CARD_PREFIX = "🐛 [fix] P1 gate-full đêm"


SUITE_ID = re.compile(r"^(?:REG|BUG)-[A-Za-z0-9_-]+$")


def open_issue_for(slug: str, first: str) -> str:
    """URL của thẻ còn mở cho cùng suite đỏ đầu tiên, "" khi không có. Hai nguồn khớp, thẻ CARD_PREFIX trước:
    thẻ gate-full đêm (tiêu đề CARD_PREFIX + suite, đêm nào cũng được: phản biện #644 finding 9) rồi thẻ mở tay có đúng mã suite
    trong tiêu đề HOẶC body (#662: #659/#660 tiêu đề khác mẫu ⇒ lượt đêm mở thẻ P1 trùng). Mã suite so như một token, không khớp lỏng.
    `first` không phải mã REG-/BUG- (vd. "agent-kit test") thì chỉ khớp thẻ CARD_PREFIX: một lệnh nhắc trong body thẻ thường
    không phải cùng lỗi (#662 R1)."""
    if not slug or not shutil.which("gh") or not first or first == "?":
        return ""
    by_id = bool(SUITE_ID.match(first))
    query = '"%s" in:title,body' % first if by_id else '"gate-full đêm" in:title'
    rc, out = sh(["gh", "issue", "list", "--repo", slug, "--state", "open", "--search", query,
                  "--json", "title,url,body", "--limit", "50"], timeout=60)
    if rc != 0:
        return ""
    try:
        items = json.loads(out.strip().splitlines()[-1]) if out.strip() else []
    except ValueError:
        return ""
    items = [it for it in items if isinstance(it, dict)] if isinstance(items, list) else []
    titles = [it.get("title") if isinstance(it.get("title"), str) else "" for it in items]
    for it, t in zip(items, titles):
        if t.startswith(CARD_PREFIX) and (": %s " % first in t or ": %s (" % first in t):
            return it.get("url") or "(issue mở cùng suite)"
    if not by_id:
        return ""
    token = re.compile(r"(?<![A-Za-z0-9_-])%s(?![A-Za-z0-9_-])" % re.escape(first))
    for it, t in zip(items, titles):
        body = it.get("body") if isinstance(it.get("body"), str) else ""
        if not t.startswith(CARD_PREFIX) and (token.search(t) or token.search(body)):
            return it.get("url") or "(issue mở cùng suite)"
    return ""


def file_card(run: Run, repo: str, slug: str, sha: str) -> None:
    i = run.info
    first = i["red"][0].split(":")[0] if i["red"] else "?"
    more = " (+%d)" % (len(i["red"]) - 1) if len(i["red"]) > 1 else ""
    title = "%s %s: %s%s đỏ" % (CARD_PREFIX, run.started.strftime("%Y-%m-%d"), first, more)
    subj = git_out(repo, "log", "-1", "--format=%s", i["suspect"]) if i["suspect"] else ""
    env = i["result"] == "red-env"
    problem = ("Lượt --full đêm trên %s @ %s đỏ: %s. %sCommit nghi vấn: %s %s %s. Log: %s"
               % (i["ref"], sha[:12], ", ".join(i["red"]),
                  # #748: có chia đôi hay không do suspect_note nói (BISECT=1 vẫn chia đôi lượt red-env)
                  "Mọi suite đỏ đều nhóm b (thời gian thực / môi trường: %s). " % ", ".join(i["group_b"]) if env else "",
                  i["suspect"] or "-", subj, i["suspect_note"], run.log_path))
    dup = open_issue_for(slug, first)
    if dup:
        # đêm sau vẫn đỏ cùng suite: ghi thêm vào thẻ đang mở, không mở thẻ mới (lỗi comment chỉ ghi log)
        rc, out = sh(["gh", "issue", "comment", dup, "--body", "[gate-full] đêm %s vẫn đỏ. %s"
                      % (run.started.strftime("%Y-%m-%d"), problem)], cwd=repo, timeout=60) if shutil.which("gh") else (1, "")
        i["card"] = dup + " (đã có, ghi thêm kết quả đêm nay)"
        run.log("thẻ mở cùng suite đã có: %s (comment exit %d)" % (dup, rc))
        return
    base = shlex.split(os.environ["DEVKIT_GATE_FULL_CARD_CMD"]) if os.environ.get("DEVKIT_GATE_FULL_CARD_CMD") \
        else [sys.executable, os.path.join(KIT, "scripts", "governance", "create_task.py")]
    cmd = base + (["--repo", slug] if slug else []) + [
        "--new-card", "gate-full đêm", "--labels", "bug", "--title", title, "--problem", problem,
        "--fix", "Sửa hoặc revert commit nghi vấn %s cho các suite/test đỏ chạy lại PASS trên main." % (i["suspect"][:12] or "-"),
        "--ac", "Các suite/test đỏ (%s) chạy lại PASS trên origin/main" % ", ".join(i["red"]),
        "--ac", "Lượt gate_full.py run kế tiếp XANH, last_full_green_sha trỏ tới main mới",
        "--risk", "🟡 Medium — nhóm b (thời gian thực / môi trường), chưa chứng minh main đỏ" if env else "🔴 High — main đỏ",
        "--blocked-by", "None."]
    rc, out = sh(cmd, cwd=repo, timeout=300)
    run.raw(out)
    m = ISSUE_URL.search(out or "")
    i["card"] = m.group(0) if m else ("tạo thẻ lỗi (exit %d), xem log" % rc)
    run.log("thẻ: " + i["card"])


# --- lượt chính ---------------------------------------------------------------------------------------------------------------

def wait_load(run: Run, max_wait_s: int) -> None:
    hold = capacity.hold_load()
    load = capacity.load()
    run.info["load_start"], run.info["hold_load"] = load, hold
    if load is None or load <= hold:
        return
    poll = float(os.environ.get("DEVKIT_GATE_FULL_POLL_S") or 60)
    start = time.monotonic()
    run.log("tải %.2f > hold_load %d: chờ (tối đa %d giây)" % (load, hold, max_wait_s))
    while load is not None and load > hold and time.monotonic() - start < max_wait_s:
        time.sleep(min(poll, max(0.0, max_wait_s - (time.monotonic() - start))) or 0.1)
        load = capacity.load()
    run.info["waited_s"] = int(time.monotonic() - start)
    if load is not None and load > hold:
        run.info["wait_note"] = "chờ hết hạn %d giây, tải vẫn %.2f > %d: chạy luôn" % (max_wait_s, load, hold)
    else:
        run.info["wait_note"] = "tải xuống %.2f ≤ %d" % (load or 0.0, hold)
    run.log(run.info["wait_note"])


def cmd_run(args) -> int:
    repo = os.path.abspath(args.repo)
    common = git_out(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        print("gate-full: %s không phải repo git" % repo, file=sys.stderr)
        return 2
    pg = os.path.join(common, "postfix-gate")
    lock = os.path.join(pg, "gate-full.lock")
    log_dir = os.environ.get("DEVKIT_GATE_FULL_LOG_DIR") or os.path.expanduser("~/Library/Logs/devkit-gate-full")
    if args.dry_run:
        print("gate-full dry-run: repo=%s ref=%s sha=%s lock=%s scratch=%s/gate-full-scratch-<stamp> log=%s hold_load=%s load=%s"
              % (repo, args.ref, git_out(repo, "rev-parse", "--verify", "-q", args.ref + "^{commit}") or "?", lock, pg, log_dir,
                 capacity.hold_load(), capacity.load()))
        return 0
    # Không os.nice ở đây (#696): mức nice đặt MỘT chỗ, ở plist (`/usr/bin/nice -n 10`); con thừa hưởng nên mọi lệnh dưới nice 10.
    # Chạy tay (`gate_full.py run`) thì chạy ở nice của shell; muốn nice 10 thì tự `nice -n 10`.
    run = Run(log_dir)
    run.info["ref"] = args.ref
    holder = acquire_lock(lock)
    if holder is not None:
        run.info["result"] = "skip"
        run.info["notes"].append("skip: lượt trước đang chạy (pid %s giữ %s)" % (holder, lock))
        run.log("skip: lượt trước đang chạy (pid %s)" % holder)
        run.finish()
        return 0
    try:
        got_global = acquire_global(run, repo)
    except BaseException:   # SIGTERM / Ctrl-C khi đang chờ: nhả khoá repo
        release_lock(lock)
        raise
    if not got_global:
        run.info["result"] = "skip"
        run.info["notes"].append("skip: chờ khoá toàn máy %s quá %d giây (lượt gate-full khác chạy quá lâu: %s)"
                                 % (global_lock_path(), run.info.get("global_wait_s", 0), _global_holder(global_lock_path())))
        run.log(run.info["notes"][-1])
        release_lock(lock)
        run.finish()
        return 0
    aborted = False
    completed = False
    scratch = ""
    kit_rel = None
    gate_rc = None
    gate_out = ""
    gate_out_full = ""
    kit_rc, kit_out = None, ""
    rc_final = 2

    def _on_sigterm(*_):
        nonlocal aborted
        if aborted:
            return   # tránh SIGTERM lặp cắt ngang khối finally đang gỡ scratch / ghi history
        aborted = True
        sys.exit(143)

    signal.signal(signal.SIGTERM, _on_sigterm)   # launchd bootout / tắt máy: finally vẫn gỡ scratch
    try:
        for old in glob.glob(os.path.join(pg, "gate-full-scratch-*")):   # lượt chết trước (đang giữ khoá nên chắc chắn của lượt cũ)
            run.log("gỡ scratch sót: " + old)
            remove_scratch(repo, old)
        wait_load(run, args.max_wait_s)
        rc, out = git(repo, "fetch", "origin", "--quiet", timeout=FETCH_TIMEOUT_S)
        if rc != 0:
            run.info["notes"].append("git fetch origin lỗi (exit %d): dùng ref đang có" % rc)
            run.log("git fetch origin lỗi: " + out.strip()[-300:])
        sha = git_out(repo, "rev-parse", "--verify", "-q", args.ref + "^{commit}")
        if not sha:
            run.info["result"] = "error"
            run.info["notes"].append("không resolve được ref " + args.ref)
            completed = True
            return 2
        run.info["sha"] = sha
        scratch = os.path.join(pg, "gate-full-scratch-" + run.stamp)
        rc, out = git(repo, "worktree", "add", "--detach", scratch, sha, timeout=600)
        if rc != 0:
            run.info["result"] = "error"
            run.info["notes"].append("không tạo được scratch: " + out.strip()[-300:])
            completed = True
            return 2
        run.log("scratch %s @ %s" % (scratch, sha[:12]))
        override = os.environ.get("DEVKIT_GATE_FULL_CMD")
        env = dict(os.environ, DEVKIT_SLOT_PRIORITY="nightly")   # hàng đợi heavy_slot: đêm đứng sau merge/push/interactive
        if override:
            gate_rc, gate_out = sh(override, cwd=scratch, timeout=GATE_TIMEOUT_S, env=env, shell=True)
        else:
            install_devkit(run, repo, scratch)
            kit_rel = scratch_kit(scratch)
            if not kit_rel:
                run.info["result"] = "error"
                run.info["notes"].append("scratch không có post-fix-gate.py (cài DevKit lỗi?)")
                completed = True
                return 2
            gate_cmd = [sys.executable, os.path.join(scratch, kit_rel, "bin", "post-fix-gate.py"),
                        "--run-tests", "--tree", "HEAD", "--no-cache", "--no-fail-fast", "--brief", "--json",
                        "--timeout", str(args.timeout)]
            run.log("$ " + " ".join(shlex.quote(c) for c in gate_cmd))
            gate_rc, gate_out = sh(gate_cmd, cwd=scratch, timeout=GATE_TIMEOUT_S, env=env)
        run.raw(gate_out)
        run.log("gate exit %d" % gate_rc)
        gitdir = git_out(scratch, "rev-parse", "--absolute-git-dir")
        gate_out_full = _full_gate_out(scratch, gate_out)
        full_pass = os.path.join(gitdir, "postfix-gate", "full_pass.json") if gitdir else ""
        full_pass_copy = os.path.join(pg, "nightly", ".full_pass.pending")
        if full_pass and os.path.isfile(full_pass):   # chép TRƯỚC khi gỡ scratch: git dir của nó đi theo worktree
            os.makedirs(os.path.dirname(full_pass_copy), exist_ok=True)
            shutil.copyfile(full_pass, full_pass_copy)
        ak = os.path.join(scratch, "universal-agent-devkit", "bin", "agent-kit")
        if not override and os.path.isfile(ak):
            run.log("$ bash universal-agent-devkit/bin/agent-kit test")
            kit_rc, kit_out = sh(["bash", ak, "test"], cwd=scratch, timeout=KIT_TEST_TIMEOUT_S, env=env)
            run.raw(kit_out)
            run.log("agent-kit test exit %d" % kit_rc)
        verdict, checks = collect_red(run, scratch, kit_rel or "universal-agent-devkit", gate_rc, gate_out_full, kit_rc, kit_out)
        run.info["result"] = verdict
        last_green_path = os.path.join(pg, "last_full_green_sha")
        if verdict == "green":
            nightly = os.path.join(pg, "nightly")
            os.makedirs(nightly, exist_ok=True)
            if os.path.isfile(full_pass_copy):
                os.replace(full_pass_copy, os.path.join(nightly, "full_pass.json"))
            else:
                run.info["notes"].append("gate xanh nhưng scratch không có full_pass.json")
            _write(last_green_path, sha + "\n")
            rc_final = 0
        elif verdict == "red":
            mode = os.environ.get("DEVKIT_GATE_FULL_BISECT") or "auto"
            if mode not in ("0", "auto", "1"):
                run.info["notes"].append("DEVKIT_GATE_FULL_BISECT=%s không hợp lệ (0|auto|1): dùng auto" % mode)
                mode = "auto"
            all_b = set(run.info["red"]) <= set(run.info["group_b"])
            try:
                last_green = open(last_green_path, encoding="utf-8").read().strip()
            except OSError:
                last_green = ""
            if mode == "0" or (mode == "auto" and all_b):
                run.info["suspect_note"] = "(không chia đôi: %s)" % (
                    "DEVKIT_GATE_FULL_BISECT=0" if mode == "0" else "mọi suite đỏ đều nhóm b — thời gian thực / môi trường")
                run.log("không chia đôi " + run.info["suspect_note"])
            else:
                run.info["suspect"], run.info["suspect_note"] = bisect(run, repo, scratch, sha, last_green, checks, args.timeout)
                # chạy lại ở đỉnh xanh hết (khác lần đầu): mọi suite đỏ là nhóm b — chỉ khi suite nào cũng có lệnh đã chạy lại; suite
                # không có command (ma trận thiếu) thì "xanh" là rỗng, giữ red như cũ
                rerun = {c[0].split(":")[0] for c in checks}
                if run.info["suspect_note"] == TIP_GOOD and set(run.info["red"]) <= rerun:
                    all_b, run.info["group_b"] = True, list(run.info["red"])
                elif run.info["suspect"] and not run.info["suspect_note"]:
                    # #748: chia đôi (BISECT=1) THẤY commit trước nghi vấn xanh ở lượt này và nghi vấn đỏ: tái hiện được, main đỏ. Mọi
                    # suspect có ghi chú (commit đầu sau mốc xanh cũ, chính đỉnh, đỉnh chạy lại xanh) chưa là bằng chứng ⇒ giữ red-env
                    all_b = False
            if all_b:
                run.info["result"] = "red-env"
            try:   # truy vết chỉ để đọc: lỗi của nó không đổi kết luận, thẻ hay exit của lượt
                run.info["trace"] = trace(run, repo, scratch, sha, last_green, checks, last_json(gate_out_full).get("matrix_path"))
            except Exception as exc:
                run.log("truy vết lỗi: %r" % exc)
                run.info["notes"].append("truy vết lỗi: %r" % exc)
            file_card(run, repo, args.slug or origin_slug(repo), sha)
            rc_final = 3 if all_b else 1
        else:
            rc_final = 3
        completed = True
        return rc_final
    finally:
        try:
            if aborted and not completed:
                try:
                    if run.info["result"] == "?" and gate_rc is not None:
                        collect_red(run, scratch, kit_rel or "universal-agent-devkit", gate_rc,
                                    gate_out_full or _full_gate_out(scratch, gate_out), kit_rc, kit_out, record_notes=False)
                except Exception as exc:
                    run.log("lỗi thu suite đỏ khi nhận SIGTERM: %s" % exc)
                run.info["result"] = "aborted"
                run.info["notes"].append("bị dừng bởi SIGTERM (exit 143)")
            elif run.info["result"] == "?":
                run.info["result"] = "error"
            if scratch:
                remove_scratch(repo, scratch)
            pending = os.path.join(pg, "nightly", ".full_pass.pending")
            if os.path.exists(pending):
                os.unlink(pending)
            hist = os.path.join(pg, "nightly")
            os.makedirs(hist, exist_ok=True)
            with open(os.path.join(hist, "history.jsonl"), "a", encoding="utf-8") as f:
                f.write(json.dumps({"at": run.started.isoformat(timespec="seconds"), "result": run.info["result"], "ref": run.info["ref"],
                                    "sha": run.info["sha"], "red": run.info["red"], "group_b": run.info["group_b"],
                                    "suspect": run.info["suspect"],
                                    "card": run.info["card"], "log": run.log_path}, ensure_ascii=False) + "\n")
            run.finish()
        finally:
            release_global()
            release_lock(lock)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="gate_full.py", description="Lượt post-fix-gate full đêm trên main trong scratch tách rời (#644)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="chạy một lượt full")
    r.add_argument("--repo", default=".", help="repo (mặc định: thư mục hiện tại)")
    r.add_argument("--ref", default="origin/main", help="ref cần kiểm (mặc định origin/main; --tree chỉ nhận cây đã có trên origin)")
    r.add_argument("--max-wait-s", type=int, default=7200, help="chờ tải xuống tối đa (giây), quá thì chạy luôn")
    r.add_argument("--slug", default="", help="owner/repo cho thẻ P1 (mặc định suy từ origin)")
    r.add_argument("--timeout", type=int, default=900, help="giới hạn mỗi suite (giây), cũng dùng khi chia đôi")
    r.add_argument("--dry-run", action="store_true", help="chỉ in kế hoạch, không fetch, không scratch, không chạy")
    args = ap.parse_args(argv)
    return cmd_run(args)


if __name__ == "__main__":
    sys.exit(main())
