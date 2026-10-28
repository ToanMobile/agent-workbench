#!/usr/bin/env python3
"""`agent-kit integrate [--if-due] [--dry-run]` — điểm gộp của repo trunk-push (Q5, pha 2 merge queue, v4 mục 1).

Repo không đi PR: các worktree `finish` vào main LOCAL, rồi ai đó push. Commit trên main local chưa có trên origin chính là hàng đợi;
lệnh này gom cả hàng đợi vào MỘT lượt `post-fix-gate --run-tests --full` thay vì một lượt cho mỗi lần push.

  1. khoá fcntl `<git common dir>/devkit-integrate.lock` (LOCK_NB; bận → exit 0, lượt khác đang gộp);
  2. `git fetch origin <base>`; origin/<base> phải là tổ tiên của HEAD main, không thì dừng (exit 2) — không đốt một lượt --full
     cho một cây không push được;
  3. `--if-due`: chỉ chạy khi số commit chờ ≥ devkit.integrate.batchMax (mặc định 6), commit cũ nhất chờ ≥ devkit.integrate.maxWaitMin
     phút (mặc định 60), hoặc máy rảnh: không `.claude/audit-gate/test_run.lock` nào của các worktree đang bị giữ (thử LOCK_SH|LOCK_NB);
  4. dựng worktree scratch tách rời ở HEAD main (`.claude/worktrees/.integrate-scratch-*`): gate KHÔNG chạy trong checkout main
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
import glob
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEVKIT = os.path.dirname(HERE)
if not os.path.isdir(os.path.join(DEVKIT, "profiles")) and os.path.isdir(os.path.join(os.path.dirname(DEVKIT), "profiles")):
    DEVKIT = os.path.dirname(DEVKIT)   # scripts/git/integrate.py → kit root (như worktree.py)

LOCK_NAME = "devkit-integrate.lock"
# Không dùng .merge-scratch-*: batch_canary.py đếm tiền tố đó là lượt merge gate lẻ (PR đi đường lẻ), mà integrate là điểm gộp theo đợt.
# Tên scratch: .integrate-scratch-<pid chủ>-<ngẫu nhiên>. SIGTERM/SIGINT/SIGHUP → SystemExit → `finally` gỡ scratch; SIGKILL không chạy được gì,
# nên lượt integrate kế tiếp (đang giữ khoá) dọn mọi scratch mồ côi trước khi làm việc khác (sweep_orphans, #475).
SCRATCH_PREFIX = ".integrate-scratch-"
GATE_STOP_S = 30   # sau SIGTERM nhóm tiến trình gate: chờ chừng này rồi SIGKILL cả nhóm
STOP_SIGNALS = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)   # HUP: terminal đóng; gate ở phiên riêng nên không còn tự nhận nó
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


def _owner_alive(name):
    """True khi pid chủ ghi trong tên scratch (.integrate-scratch-<pid>-…) còn sống và không phải tiến trình này."""
    head = name[len(SCRATCH_PREFIX):].split("-", 1)[0]
    if not head.isdigit() or int(head) == os.getpid():
        return False
    try:
        os.kill(int(head), 0)
    except (ProcessLookupError, OverflowError, ValueError):   # chết, hoặc không phải pid (tên kiểu cũ toàn chữ số)
        return False
    except PermissionError:   # pid của người dùng khác: coi là còn sống, không xoá
        pass
    return True


def sweep_orphans(main):
    """Gỡ các scratch integrate mồ côi (lượt trước bị SIGKILL: `finally` không chạy, bản chép dotenv/keystore còn trên đĩa). Gọi khi đang
    giữ khoá integrate, nên không lượt integrate nào khác của repo đang dùng chúng; pid chủ còn sống thì để yên."""
    root = os.path.join(main, ".claude", "worktrees")
    try:
        names = [n for n in os.listdir(root) if n.startswith(SCRATCH_PREFIX)]
    except FileNotFoundError:
        return
    except OSError as e:
        say(f"không đọc được {root} để dọn scratch mồ côi: {e}")
        return
    for name in names:
        if _owner_alive(name):
            continue
        say(f"gỡ scratch mồ côi của một lượt integrate đã chết: {name}")
        remove_scratch(main, os.path.join(root, name))


def setup_kit(main, scratch):
    """Cài DevKit vào scratch đúng như `worktree add` (worktree.install_args) khi main có DevKit; bản cài ghi đè file tracked thì trả lại
    HEAD (như merge gate). True = scratch dùng được (cài xong, hoặc main không có DevKit); False = cài hỏng: scratch thiếu kit nên gate sẽ
    chạy hook/bin của bản working copy main chứ không phải của HEAD, che mất lỗi cài (#477) — người gọi không gate, không push."""
    try:
        if HERE not in sys.path:
            sys.path.insert(0, HERE)
        import worktree  # noqa: PLC0415 - module anh em, chỉ nạp khi thật sự gate
        cmd = worktree.install_args(main, scratch, None)
    except Exception as e:  # noqa: BLE001 - không dựng được lệnh cài: báo, người gọi dừng
        say(f"không dựng được lệnh cài DevKit vào scratch: {type(e).__name__}: {e}")
        return False
    if not cmd:
        return True
    try:
        r = subprocess.run(cmd, cwd=scratch, capture_output=True, text=True, timeout=INSTALL_TIMEOUT_S, stdin=subprocess.DEVNULL)
        if r.returncode != 0:
            say(f"cài DevKit vào scratch exit {r.returncode}: {(r.stderr or r.stdout).strip()[-300:]}")
            return False
    except (OSError, subprocess.TimeoutExpired) as e:
        say(f"cài DevKit vào scratch hỏng: {type(e).__name__}: {e}")
        return False
    git(scratch, "checkout", "-q", "--", ".")
    return True


def copy_ignored(main, scratch):
    """Chép vào scratch các file bị git ignore mà gate cần (worktree.copy_ignored, danh sách chung với merge train): thiếu hook thì
    `agent-kit health` trong scratch đỏ ("hook đăng ký nhưng thiếu file"), REG-WB-CONFIG-01 đỏ và integrate không bao giờ push được
    (agent-workbench #463). Chạy SAU setup_kit như `worktree add`. Lỗi chỉ được báo: gate tự đỏ nếu thiếu thứ nó cần."""
    try:
        if HERE not in sys.path:
            sys.path.insert(0, HERE)
        import worktree  # noqa: PLC0415 - module anh em, chỉ nạp khi thật sự gate
        copied = worktree.copy_ignored(main, scratch)
    except Exception as e:  # noqa: BLE001 - kit cài dở: gate vẫn chạy, kết luận là của gate
        say(f"không chép được file bị ignore vào scratch: {type(e).__name__}: {e}")
        return
    if copied:
        say(f"đã chép vào scratch {len(copied)} file bị ignore: {', '.join(copied[:8])}")


def copy_approved_tests(main, scratch):
    """Chép lời duyệt test-theo-tên của main (.claude/audit-gate/approved_tests.json) sang scratch (#481): gate đọc approved_tests.json của
    PROJECT của nó = scratch, nên không chép thì test sửa đã duyệt ở main vẫn chặn (exit 2) và chỉ còn cờ duyệt hàng loạt. Chỉ chép mục còn
    đúng: dạng list gắn với mtime của file duyệt, nên một test sửa SAU lúc duyệt (mtime mới hơn) bị bỏ; dạng {path: sha256} giữ mục nào nội dung
    trong scratch còn khớp. Scratch nhận dạng {path: sha256} của nội dung scratch (gate chỉ duyệt đúng nội dung đó). Luật không đổi: file
    chưa duyệt vẫn chặn. Lỗi chỉ được báo, gate tự chặn khi thiếu lời duyệt."""
    src = os.path.join(main, ".claude", "audit-gate", "approved_tests.json")
    if not os.path.isfile(src):
        return
    try:
        appr_t = os.stat(src).st_mtime
        with open(src, encoding="utf-8") as fh:
            saved = json.load(fh)
        wants = {f: None for f in saved} if isinstance(saved, list) else dict(saved) if isinstance(saved, dict) else {}
        keep = {}
        for f, want in wants.items():
            if not isinstance(f, str) or os.path.isabs(f) or ".." in f.split("/"):
                continue
            mine, theirs = os.path.join(main, f), os.path.join(scratch, f)
            if not (os.path.isfile(mine) and os.path.isfile(theirs)):
                continue
            with open(theirs, "rb") as th:
                digest = hashlib.sha256(th.read()).hexdigest()
            if want is None:   # dạng list: duyệt có hiệu lực khi test ở main không đổi sau lúc duyệt và scratch (HEAD) cùng nội dung với main
                with open(mine, "rb") as mh:
                    unchanged = os.stat(mine).st_mtime <= appr_t and hashlib.sha256(mh.read()).hexdigest() == digest
            else:
                unchanged = isinstance(want, str) and want.strip().lower() == digest
            if unchanged:
                keep[f] = digest
        if not keep:
            return
        dst = os.path.join(scratch, ".claude", "audit-gate")
        os.makedirs(dst, exist_ok=True)
        with open(os.path.join(dst, "approved_tests.json"), "w", encoding="utf-8") as out:
            json.dump(keep, out)
        say(f"đã chép vào scratch lời duyệt test của {len(keep)} file: {', '.join(sorted(keep)[:8])}")
    except (OSError, ValueError) as e:
        say(f"không chép được lời duyệt test vào scratch: {type(e).__name__}: {e}")


def run_gate(scratch, remote):
    """Exit code của `post-fix-gate --run-tests --full --brief --diff <origin/base>` trong scratch (124 khi quá
    DEVKIT_INTEGRATE_GATE_TIMEOUT_S). --diff: scratch tách rời không có upstream, cây sạch không --diff thì gate trả 3 (nothing to audit);
    origin/<base>..HEAD đúng là nội dung sẽ push (như mặc định @{u}..HEAD của gate trên một nhánh có upstream). Đây là lượt --full duy
    nhất của cả đợt (điểm gộp)."""
    gate = os.path.join(DEVKIT, "bin", "post-fix-gate.py")
    env = dict(os.environ, CLAUDE_PROJECT_DIR=scratch, DEVKIT_SLOT_PRIORITY="merge")
    try:
        # Phiên riêng: nhóm tiến trình của gate (gate + suite con) dừng được trọn bằng killpg khi integrate bị SIGTERM/SIGINT (#475).
        p = subprocess.Popen([sys.executable, gate, "--run-tests", "--full", "--brief", "--diff", remote], cwd=scratch, env=env,
                             stdin=subprocess.DEVNULL, start_new_session=True)
    except OSError as e:
        say(f"gate không chạy được: {e}")
        return 127
    try:
        return p.wait(timeout=GATE_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        stop_gate_group(p, 60)   # SIGTERM: gate dừng suite và trả lại những gì nó đã đổi
        say(f"gate không xong trong {GATE_TIMEOUT_S:g} s (DEVKIT_INTEGRATE_GATE_TIMEOUT_S)")
        return 124
    except BaseException:   # integrate bị tín hiệu dừng (SystemExit) hay lỗi bất kỳ: dừng cả nhóm gate rồi để `finally` gỡ scratch
        stop_gate_group(p)
        raise


def stop_gate_group(p, grace=GATE_STOP_S):
    """SIGTERM nhóm tiến trình của gate (gate tự dọn suite, kể cả suite ở phiên riêng của nó), chờ `grace` giây, rồi SIGKILL cả nhóm:
    không để gate mồ côi chạy tiếp."""
    for sig, wait_s in ((signal.SIGTERM, grace), (signal.SIGKILL, 5)):
        try:
            os.killpg(p.pid, sig)
        except ProcessLookupError:
            break
        except PermissionError:   # macOS: killpg trả EPERM khi nhóm còn zombie (như _signal_group của post-fix-gate) → gửi leader
            with contextlib.suppress(OSError):
                p.send_signal(sig)
        except OSError as e:
            say(f"không gửi được {sig.name} tới nhóm gate {p.pid}: {e}")
        try:
            p.wait(timeout=wait_s)
        except subprocess.TimeoutExpired:
            continue
        if sig == signal.SIGTERM:   # gate đã thoát; cháu còn sót trong nhóm (suite gate không dọn) thì SIGKILL nốt
            with contextlib.suppress(OSError):
                os.killpg(p.pid, signal.SIGKILL)
        break
    say(f"đã dừng nhóm tiến trình gate {p.pid}")


def push_gate_ok(main, sha):
    """(ok, lý do) theo bin/push_gate.py — cùng luật hook block-dangerous-git áp cho một `git push` của agent."""
    try:
        r = subprocess.run([sys.executable, os.path.join(DEVKIT, "bin", "push_gate.py"), main, sha], capture_output=True, text=True,
                           timeout=GIT_TIMEOUT_S * 2, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, f"{type(e).__name__}: {e}"
    return r.returncode == 0, (r.stdout or r.stderr).strip()


def integrate(main, base, args):
    if glob.glob(os.path.join(main, ".claude", "super-board", "configs", "*.json")):   # #576: a super-board repo lands by PR + merge gate
        say("repo có super-board (.claude/super-board/configs): main chỉ nhận việc qua PR + merge gate, integrate không push main. "
            "Push nhánh và mở PR (open a PR) thay vì gộp vào main local")
        return 2
    if not args.dry_run:
        sweep_orphans(main)
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
    scratch = tempfile.mkdtemp(prefix=f"{SCRATCH_PREFIX}{os.getpid()}-", dir=os.path.join(main, ".claude", "worktrees"))
    try:
        add = git(main, "worktree", "add", "--detach", "--quiet", scratch, head, timeout=600)
        if add.returncode != 0:
            say(f"không dựng được worktree scratch: {add.stderr.strip()[-300:]}")
            return 1
        if not setup_kit(main, scratch):
            say("scratch không có DevKit của HEAD: không gate, không push (gate trên cây thiếu kit không đại diện cho commit sẽ push)")
            return 1
        copy_ignored(main, scratch)
        copy_approved_tests(main, scratch)
        rc = run_gate(scratch, remote)
        if rc == 4:   # hàng đợi gate toàn máy / khoá dự án bận (T0056): không phải đỏ, đợt giữ nguyên cho lượt sau
            say("gate bận (busy, exit 4): chưa kiểm được gì, không push; lượt integrate sau thử lại")
            return 0
        if rc != 0:
            say(f"gate ĐỎ (exit {rc}): không push. Các commit trong đợt:\n{batch}")
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
        for s in STOP_SIGNALS:   # tín hiệu đến giữa lúc gỡ không được cắt ngang việc xoá bản chép secret
            signal.signal(s, signal.SIG_IGN)
        remove_scratch(main, scratch)


def _on_signal(signum, _frame):
    """SIGTERM/SIGINT/SIGHUP → SystemExit(128+sig): các `finally` chạy (dừng nhóm gate, gỡ scratch kèm bản chép secret, nhả khoá). Tín hiệu thứ
    hai bị bỏ qua để không cắt ngang chính việc dọn đó."""
    for s in STOP_SIGNALS:
        signal.signal(s, signal.SIG_IGN)
    with contextlib.suppress(OSError):   # stdout là pipe đã đóng (Ctrl-C trên `… | tee`): BrokenPipeError không được thay SystemExit
        say(f"nhận {signal.Signals(signum).name}: dừng gate, gỡ scratch")
    raise SystemExit(128 + signum)


def main(argv):
    ap = argparse.ArgumentParser(prog="agent-kit integrate", description=__doc__.split("\n\n")[0])
    ap.add_argument("--if-due", action="store_true", help="chỉ gộp khi tới hạn (batchMax, maxWaitMin hoặc máy rảnh)")
    ap.add_argument("--dry-run", action="store_true", help="chỉ nói sẽ làm gì: không gate, không push")
    ap.add_argument("path", nargs="?", default=os.getcwd(), help="một thư mục trong repo (mặc định: thư mục hiện tại)")
    args = ap.parse_args(argv)
    for s in STOP_SIGNALS:
        signal.signal(s, _on_signal)
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
