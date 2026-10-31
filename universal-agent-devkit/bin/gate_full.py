#!/usr/bin/env python3
"""Lượt --full đêm (#644): gate mặc định là scoped, merge/push không còn chạy --full; lượt THẬT SỰ full trên main chạy ở đây — tay
(skill gate-full) hoặc 00:00 mỗi đêm (bin/gate-full-schedule.sh cài LaunchAgent).

  gate_full.py run [--repo PATH] [--ref origin/main] [--max-wait-s 7200] [--slug owner/repo] [--timeout 900] [--dry-run]

Một lượt:
  1. khoá <common>/postfix-gate/gate-full.lock (pid + lúc bắt đầu, O_EXCL): pid còn sống ⇒ "skip", exit 0; pid chết ⇒ chiếm lại;
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
  8. log <DEVKIT_GATE_FULL_LOG_DIR>/<yyyymmdd-HHMMSS>.log + summary-latest.md + summary-<yyyymmdd>.md (lịch đêm đặt biến này =
     ~/Library/Logs/devkit-gate-full/<slug> riêng từng repo; chạy tay không đặt: ~/Library/Logs/devkit-gate-full);
  9. finally: gỡ scratch, nhả khoá.
Kết luận: 0 xanh (hoặc skip), 1 đỏ (suite FAIL thật), 3 chưa kết luận (exit 2/4/5, TIMEOUT, BUSY, môi trường — không thẻ, không ghi
last_full_green_sha), 2 lỗi chuẩn bị (ref, scratch).
Lượt đêm chạy nice 10 do plist (`/usr/bin/nice -n 10`, con thừa hưởng); gate_full.py không tự đặt nice (#696).
Móc test: DEVKIT_GATE_FULL_CMD (lệnh gate thay thế, shell, cwd = scratch; khi đặt thì không chạy agent-kit test),
DEVKIT_GATE_FULL_CARD_CMD (thay `python3 create_task.py`), DEVKIT_GATE_FULL_LOG_DIR, DEVKIT_GATE_FULL_POLL_S; tải giả qua
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
                     "wait_note": "", "red": [], "env_red": [], "suspect": "", "suspect_note": "", "card": "", "notes": []}

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
        label = {"green": "XANH", "red": "ĐỎ", "inconclusive": "CHƯA KẾT LUẬN", "aborted": "BỊ DỪNG (aborted)", "skip": "skip", "error": "LỖI"}.get(i["result"], i["result"])
        out = ["# gate-full đêm %s" % self.started.strftime("%Y-%m-%d %H:%M:%S"), "",
               "- Kết quả: **%s**" % label,
               "- Ref: %s @ %s" % (i["ref"] or "-", i["sha"][:12] or "-"),
               "- Thời gian: %d phút %d giây" % (dur // 60, dur % 60),
               "- Tải lúc bắt đầu: %s (ngưỡng hold_load %s)" % (_fmt(i["load_start"]), i["hold_load"] if i["hold_load"] is not None else "-"),
               "- Chờ tải: %s" % (("%d giây — %s" % (i["waited_s"], i["wait_note"])) if i["waited_s"] or i["wait_note"] else "không")]
        if i["red"]:
            out.append("- Suite/test đỏ: " + ", ".join(i["red"]))
        if i["env_red"]:
            out.append("- Đỏ do môi trường (không tính): " + ", ".join(i["env_red"]))
        if i["suspect"] or i["suspect_note"]:
            out.append("- Commit nghi vấn: %s %s" % (i["suspect"] or "-", i["suspect_note"]))
        if i["card"]:
            out.append("- Thẻ: " + i["card"])
        for n in i["notes"]:
            out.append("- Ghi chú: " + n)
        out.append("- Log: " + self.log_path)
        return "\n".join(out) + "\n"

    def finish(self) -> None:
        text = self.summary()
        # lượt skip (lượt trước còn giữ khoá) chỉ ghi vào log của chính nó: không đè summary của lượt chạy thật đang / vừa chạy
        for name in () if self.info["result"] == "skip" else ("summary-latest.md", "summary-%s.md" % self.started.strftime("%Y%m%d")):
            _write(os.path.join(self.log_dir, name), text)
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
    checks, red, env_red = [], [], []
    for t in data.get("regression_tests") or []:
        if not isinstance(t, dict):
            continue
        st, sid, cmd = t.get("status"), t.get("id") or "?", t.get("command") or ""
        if st == "FAIL" and t.get("env_blocked"):
            env_red.append(sid)
        elif st == "FAIL":
            red.append(sid)
            paths = test_paths("\n".join((t.get("fail_lines") or []) + [t.get("output_tail") or ""]), kit_dir) \
                if "run_impacted.sh" in cmd else []
            if paths:
                checks += [("%s:%s" % (sid, p), "bash " + shlex.quote(p), kit_rel) for p in paths]
            elif cmd:
                checks.append((sid, cmd, "."))
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
    run.info["red"], run.info["env_red"] = red, env_red
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
        run.raw("$ (%s) %s -> %d\n%s" % (label, cmd, rc, "\n".join(out.splitlines()[-15:])))
        if rc == 124:
            return "timeout"
        if rc != 0:
            return "bad"
    return "good"


def bisect(run: Run, repo: str, scratch: str, sha: str, last_green: str, checks: list, timeout: int):
    """(commit nghi vấn, ghi chú). Đỉnh không tái hiện thì không nghi ai (flaky); hết giờ giữa chừng thì chỉ báo khoảng còn lại —
    một lần chạy lại hết giờ không phải "đỏ", tính nó là đỏ thì mọi điểm giữa đều đỏ và thẻ đổ oan cho merge cũ nhất."""
    tip = checks_fail(run, scratch, checks, timeout)
    if tip == "good":
        return "", "(không tái hiện khi chạy lại ở đỉnh: flaky?)"
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
    return merges[lo], ""


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
    problem = ("Lượt --full đêm trên %s @ %s đỏ: %s. Commit nghi vấn: %s %s %s. Log: %s"
               % (i["ref"], sha[:12], ", ".join(i["red"]), i["suspect"] or "-", subj, i["suspect_note"], run.log_path))
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
        "--risk", "🔴 High — main đỏ", "--blocked-by", "None."]
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
            try:
                last_green = open(last_green_path, encoding="utf-8").read().strip()
            except OSError:
                last_green = ""
            run.info["suspect"], run.info["suspect_note"] = bisect(run, repo, scratch, sha, last_green, checks, args.timeout)
            file_card(run, repo, args.slug or origin_slug(repo), sha)
            rc_final = 1
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
                                    "sha": run.info["sha"], "red": run.info["red"], "suspect": run.info["suspect"],
                                    "card": run.info["card"], "log": run.log_path}, ensure_ascii=False) + "\n")
            run.finish()
        finally:
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
