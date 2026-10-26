#!/usr/bin/env python3
"""`agent-kit integrate [--if-due] [--dry-run]` — điểm gộp của repo trunk-push (Q5, pha 2 merge queue, v4 mục 1).

Repo không đi PR: các worktree `finish` vào main LOCAL, rồi ai đó push. Commit trên main local chưa có trên origin chính là hàng đợi;
lệnh này gom cả hàng đợi vào MỘT lượt `post-fix-gate --run-tests --full` thay vì một lượt cho mỗi lần push.

  1. khoá fcntl `<git common dir>/devkit-integrate.lock` (LOCK_NB; bận → exit 0, lượt khác đang gộp);
  2. `git fetch origin <base>`; origin/<base> phải là tổ tiên của HEAD main, không thì dừng (exit 2) — không đốt một lượt --full
     cho một cây không push được;
  3. `--if-due`: chỉ chạy khi số commit chờ ≥ devkit.integrate.batchMax (mặc định 6), commit cũ nhất chờ ≥ devkit.integrate.maxWaitMin
     phút (mặc định 60), hoặc máy rảnh: không `.claude/audit-gate/test_run.lock` nào của các worktree đang bị giữ (thử LOCK_SH|LOCK_NB);
  4. dựng worktree scratch tách rời ở HEAD main (`.claude/worktrees/.merge-scratch-integrate-*`): gate KHÔNG chạy trong checkout main
     (nó ghi checklist tracked ở đó; session_lock.py `_TRUNK_ALLOWED`, v6 item 7). Chạy `--full` ở đó;
  5. xanh → `bin/push_gate.py <main> <sha>` phải nhận biên nhận của cây đó (lúc này scratch còn, push_gate xét biên nhận của linked
     worktree) → `git push origin <sha>:refs/heads/<base>` (đúng commit đã gate, kể cả khi main đã tiến trong lúc gate chạy); đỏ → không
     push, in các commit của đợt (exit 1). Scratch luôn được gỡ.

Exit: 0 xong / chưa tới hạn / hàng đợi rỗng / khoá bận · 1 gate đỏ, push_gate từ chối hoặc push hỏng · 2 dừng trước gate (ngoài repo
git, main detached, thiếu origin/<base>, origin phân kỳ).
ponytail: không tự chia đôi đợt khi đỏ; nâng cấp khi đỏ thường xuyên (đọc log các lượt integrate).
ponytail: biên nhận chỉ được push_gate nhận khi scratch còn (linked worktree); push_gate.py không đọc store theo cây (grep `tree_receipt` trong bin/push_gate.py: 0 dòng, 26/10), nên một
lần `git push` tay sau khi scratch đã gỡ cần gate lại. Nâng cấp ở push_gate.py nếu cần push tay sau integrate.
100% standard library.
"""
import argparse
import contextlib
import fcntl
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEVKIT = os.path.dirname(HERE)
if not os.path.isdir(os.path.join(DEVKIT, "profiles")) and os.path.isdir(os.path.join(os.path.dirname(DEVKIT), "profiles")):
    DEVKIT = os.path.dirname(DEVKIT)   # scripts/git/integrate.py → kit root (như worktree.py)

LOCK_NAME = "devkit-integrate.lock"
SCRATCH_PREFIX = ".merge-scratch-integrate-"   # .merge-scratch-*: worktree.py không tính vào WORKTREE_MAX, gc nhận ra là cây tạm của gate
BATCH_MAX_DEFAULT = 6
MAX_WAIT_MIN_DEFAULT = 60
GIT_TIMEOUT_S = 60
NET_TIMEOUT_S = 120


def _env_seconds(name, default):
    try:
        v = float(os.environ.get(name, default))
    except ValueError:
        return default
    return v if 0 < v < float("inf") else default


GATE_TIMEOUT_S = _env_seconds("DEVKIT_INTEGRATE_GATE_TIMEOUT_S", 7200.0)
INSTALL_TIMEOUT_S = 600


def say(msg):
    print(f"integrate: {msg}", flush=True)


def git(cwd, *args, timeout=GIT_TIMEOUT_S):
    """CompletedProcess (text) của `git -C cwd args`; lỗi khởi chạy / quá giờ thành returncode 124 kèm lý do trong stderr."""
    try:
        return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=timeout,
                              stdin=subprocess.DEVNULL, env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(["git", *args], 124, "", f"{type(e).__name__}: {e}")


def config_int(main, key, default):
    r = git(main, "config", "--get", key)
    raw = r.stdout.strip()
    if r.returncode != 0 or not raw:
        return default
    try:
        v = int(raw, 10)
    except ValueError:
        v = 0
    if v < 1:
        say(f"git config {key}={raw!r} không phải số nguyên ≥ 1: dùng mặc định {default}")
        return default
    return v


def worktrees(main):
    """Đường dẫn mọi worktree còn thư mục (main trước); [] khi git không trả lời."""
    r = git(main, "worktree", "list", "--porcelain")
    if r.returncode != 0:
        return []
    return [ln[9:] for ln in r.stdout.splitlines() if ln.startswith("worktree ") and os.path.isdir(ln[9:])]


def busy_test_locks(main):
    """Các test_run.lock đang bị một lượt gate/test giữ (thử LOCK_SH|LOCK_NB rồi nhả ngay; không tạo file nào)."""
    held = []
    for wt in worktrees(main):
        if os.path.basename(wt).startswith(SCRATCH_PREFIX):
            continue
        path = os.path.join(wt, ".claude", "audit-gate", "test_run.lock")
        try:
            fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0))
        except FileNotFoundError:
            continue
        except OSError as e:   # không đọc được: coi là bận (không kết luận "máy rảnh" khi không biết)
            held.append(f"{path} ({e})")
            continue
        try:
            fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
            fcntl.flock(fd, fcntl.LOCK_UN)
        except BlockingIOError:
            held.append(path)
        except OSError as e:
            held.append(f"{path} ({e})")
        finally:
            os.close(fd)
    return held


def due_reasons(main, pending, oldest_epoch):
    batch_max = config_int(main, "devkit.integrate.batchMax", BATCH_MAX_DEFAULT)
    max_wait = config_int(main, "devkit.integrate.maxWaitMin", MAX_WAIT_MIN_DEFAULT)
    reasons = []
    if len(pending) >= batch_max:
        reasons.append(f"{len(pending)} commit chờ ≥ batchMax {batch_max}")
    age_min = (time.time() - oldest_epoch) / 60 if oldest_epoch else 0
    if age_min >= max_wait:
        reasons.append(f"commit cũ nhất chờ {age_min:.0f} phút ≥ maxWaitMin {max_wait}")
    held = busy_test_locks(main)
    if not held:
        reasons.append("máy rảnh (idle): không test_run.lock nào bị giữ")
    return reasons, (batch_max, max_wait, age_min, held)


def remove_scratch(main, scratch):
    r = git(main, "worktree", "remove", "--force", scratch)
    if r.returncode != 0 and os.path.isdir(scratch):
        say(f"git worktree remove {scratch} hỏng ({r.stderr.strip()[-200:]}): xoá thư mục rồi prune")
    shutil.rmtree(scratch, ignore_errors=True)
    git(main, "worktree", "prune")


def setup_kit(main, scratch):
    """Cài DevKit vào scratch đúng như `worktree add` (worktree.install_args) khi main có DevKit; bản cài ghi đè file tracked thì trả lại
    HEAD (như merge gate). Lỗi chỉ được báo: gate tự đỏ nếu thiếu thứ nó cần."""
    try:
        if HERE not in sys.path:
            sys.path.insert(0, HERE)
        import worktree  # noqa: PLC0415 - module anh em, chỉ nạp khi thật sự gate
        cmd = worktree.install_args(main, scratch, None)
    except Exception as e:  # noqa: BLE001 - kit cài dở: gate vẫn chạy, kết luận là của gate
        say(f"không dựng được lệnh cài DevKit vào scratch: {type(e).__name__}: {e}")
        return
    if not cmd:
        return
    try:
        r = subprocess.run(cmd, cwd=scratch, capture_output=True, text=True, timeout=INSTALL_TIMEOUT_S, stdin=subprocess.DEVNULL)
        if r.returncode != 0:
            say(f"cài DevKit vào scratch exit {r.returncode}: {(r.stderr or r.stdout).strip()[-300:]}")
    except (OSError, subprocess.TimeoutExpired) as e:
        say(f"cài DevKit vào scratch hỏng: {type(e).__name__}: {e}")
    git(scratch, "checkout", "-q", "--", ".")


def run_gate(scratch, remote):
    """Exit code của `post-fix-gate --run-tests --full --brief --diff <origin/base>` trong scratch (124 khi quá
    DEVKIT_INTEGRATE_GATE_TIMEOUT_S). --diff: scratch tách rời không có upstream, cây sạch không --diff thì gate trả 3 (nothing to audit);
    origin/<base>..HEAD đúng là nội dung sẽ push (như mặc định @{u}..HEAD của gate trên một nhánh có upstream)."""
    gate = os.path.join(DEVKIT, "bin", "post-fix-gate.py")
    env = dict(os.environ, CLAUDE_PROJECT_DIR=scratch, DEVKIT_SLOT_PRIORITY="merge")
    try:
        p = subprocess.Popen([sys.executable, gate, "--run-tests", "--full", "--brief", "--diff", remote], cwd=scratch, env=env,
                             stdin=subprocess.DEVNULL)
    except OSError as e:
        say(f"gate không chạy được: {e}")
        return 127
    try:
        return p.wait(timeout=GATE_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        p.terminate()   # SIGTERM: gate dừng suite và trả lại những gì nó đã đổi
        try:
            p.wait(timeout=60)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()
        say(f"gate không xong trong {GATE_TIMEOUT_S:g} s (DEVKIT_INTEGRATE_GATE_TIMEOUT_S)")
        return 124


def push_gate_ok(main, sha):
    """(ok, lý do) theo bin/push_gate.py — cùng luật hook block-dangerous-git áp cho một `git push` của agent."""
    try:
        r = subprocess.run([sys.executable, os.path.join(DEVKIT, "bin", "push_gate.py"), main, sha], capture_output=True, text=True,
                           timeout=GIT_TIMEOUT_S * 2, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, f"{type(e).__name__}: {e}"
    return r.returncode == 0, (r.stdout or r.stderr).strip()


def integrate(main, base, args):
    fetch = git(main, "fetch", "--quiet", "origin", base, timeout=NET_TIMEOUT_S)
    if fetch.returncode != 0:
        say(f"git fetch origin {base} hỏng: {fetch.stderr.strip()[-300:]}")
        return 2
    remote = f"refs/remotes/origin/{base}"
    if git(main, "rev-parse", "--verify", "-q", remote + "^{commit}").returncode != 0:
        say(f"không có origin/{base}: chưa có gì để gộp vào")
        return 2
    head = git(main, "rev-parse", "HEAD").stdout.strip()
    if git(main, "merge-base", "--is-ancestor", remote, head).returncode != 0:
        say(f"origin/{base} đã phân kỳ (diverged) với main local: origin có commit main chưa có. Đưa origin vào main trước "
            f"(`git pull --no-rebase origin {base}` trong một worktree rồi finish), không chạy gate")
        return 2
    log = git(main, "log", "--format=%H %ct %h %s", f"{remote}..{head}")
    pending = [ln.split(" ", 3) for ln in log.stdout.splitlines() if ln.strip()]
    if not pending:
        say(f"không có commit nào chờ (nothing to integrate): main = origin/{base}")
        return 0
    oldest = min(int(p[1]) for p in pending)
    reasons, (batch_max, max_wait, age_min, held) = due_reasons(main, pending, oldest)
    if args.if_due and not reasons:
        say(f"chưa tới hạn (not due): {len(pending)}/{batch_max} commit, cũ nhất {age_min:.0f}/{max_wait} phút, "
            f"đang chạy test: {', '.join(held[:3])}")
        return 0
    batch = "\n".join(f"  {p[2]} {p[3] if len(p) > 3 else ''}" for p in pending)
    why = "; ".join(reasons) if args.if_due else "chạy tay"
    if args.dry_run:
        say(f"--dry-run: sẽ gate --full rồi push {len(pending)} commit ({why}):\n{batch}")
        return 0
    say(f"gộp {len(pending)} commit ({why}): gate --full một lần trên {head[:10]}")
    os.makedirs(os.path.join(main, ".claude", "worktrees"), exist_ok=True)
    scratch = tempfile.mkdtemp(prefix=SCRATCH_PREFIX, dir=os.path.join(main, ".claude", "worktrees"))
    try:
        add = git(main, "worktree", "add", "--detach", "--quiet", scratch, head, timeout=600)
        if add.returncode != 0:
            say(f"không dựng được worktree scratch: {add.stderr.strip()[-300:]}")
            return 1
        setup_kit(main, scratch)
        rc = run_gate(scratch, remote)
        if rc != 0:
            say(f"gate ĐỎ (exit {rc}{', bận: thử lại sau' if rc == 4 else ''}): không push. Các commit trong đợt:\n{batch}")
            return 1
        ok, reason = push_gate_ok(main, head)
        if not ok:
            say(f"gate xanh nhưng push_gate không nhận biên nhận của cây {head[:10]}: {reason}. Không push")
            return 1
        push = git(main, "push", "--quiet", "origin", f"{head}:refs/heads/{base}", timeout=NET_TIMEOUT_S)
        if push.returncode != 0:
            say(f"git push origin {head[:10]}:{base} hỏng (origin vừa tiến? chạy lại integrate): {push.stderr.strip()[-300:]}")
            return 1
        say(f"đã push {len(pending)} commit lên origin/{base} @ {head[:10]}:\n{batch}")
        return 0
    finally:
        remove_scratch(main, scratch)


def main(argv):
    ap = argparse.ArgumentParser(prog="agent-kit integrate", description=__doc__.split("\n\n")[0])
    ap.add_argument("--if-due", action="store_true", help="chỉ gộp khi tới hạn (batchMax, maxWaitMin hoặc máy rảnh)")
    ap.add_argument("--dry-run", action="store_true", help="chỉ nói sẽ làm gì: không gate, không push")
    ap.add_argument("path", nargs="?", default=os.getcwd(), help="một thư mục trong repo (mặc định: thư mục hiện tại)")
    args = ap.parse_args(argv)
    trees = worktrees(args.path)
    if not trees:
        say(f"{args.path} không phải repo git có work tree")
        return 2
    main_wt = trees[0]
    ref = git(main_wt, "symbolic-ref", "-q", "HEAD")
    if ref.returncode != 0 or not ref.stdout.strip().startswith("refs/heads/"):
        say(f"checkout main {main_wt} không đứng trên nhánh nào: không biết push vào đâu")
        return 2
    base = ref.stdout.strip()[len("refs/heads/"):]
    common = git(main_wt, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()
    try:
        lock = open(os.path.join(common, LOCK_NAME), "a")   # noqa: SIM115 - giữ fd tới hết lượt
    except OSError as e:
        say(f"không mở được khoá {LOCK_NAME}: {e}")
        return 2
    with lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            say("một lượt integrate khác đang chạy (khoá bận / busy): bỏ qua lượt này")
            return 0
        try:
            return integrate(main_wt, base, args)
        finally:
            with contextlib.suppress(OSError):
                fcntl.flock(lock, fcntl.LOCK_UN)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
