#!/usr/bin/env python3
"""Khoá lane cho việc nặng của phiên điều phối (gate, test suite, build, đo A/B), số slot theo tải máy (#716).

    lane_lock.py <tên> [--] <lệnh…>

Luật người dùng (18:03 30/10): load1 < 12 ⇒ tối đa 2 việc nặng cùng lúc; 12 ≤ load1 < 24 ⇒ 1 (KHÔNG còn ai khác giữ slot nào);
load1 ≥ 24 ⇒ không bắt đầu, chờ tải xuống. Đọc tải lỗi ⇒ coi như tải cao (1 slot). Chờ không giới hạn (như khoá mkdir cũ ở
.claude/audit-gate/handoff/work-1644/with_lane_lock.sh), log lại mỗi 60 s.

Khoá là flock trên <thư mục>/lane-<k>.lock (dùng lại heavy_slot._try_lock_path / _unlock): kernel nhả khi wrapper chết, kể cả
kill -9, nên không có khoá mồ côi. Con KHÔNG thừa hưởng fd khoá (close_fds): tiến trình cháu sống sót không giữ slot (#697). TERM/INT/HUP
gửi cho wrapper được chuyển cho con; wrapper chờ con rồi nhả. Exit = exit của lệnh (127 khi không chạy được, 128+sig khi con bị tín hiệu).

Biến: LANE_LOCK_DIR (mặc định <git common dir>/lane-lock, chung cho main và mọi worktree), LANE_LOCK_SLOTS (2), LANE_LOCK_LOAD_TWO (12),
LANE_LOCK_LOAD_MAX (24), LANE_LOCK_POLL_S (5), LANE_LOCK_LOG_S (60), LANE_LOCK_STAGGER_S (60), LANE_LOCK_STAGGER_LOAD (6); tải giả cho
test: DEVKIT_SLOT_LOAD_FILE (của heavy_slot.load_now).
ponytail: không có hàng vé/ưu tiên (2–3 người chờ, jitter tránh đồng pha); ≥ 4 lane chờ thường xuyên thì chuyển sang hàng vé của
heavy_slot.acquire_pool.

#849 — việc NHẸ không chờ ngưỡng tải: lệnh chạy thẳng post-fix-gate.py `--run-tests --scoped` (chỉ cờ trong _LIGHT_FLAGS) mà bộ thăm dò
(scoped_gate.no_full(decide) của chính kit của gate đó, tiến trình con, tối đa LANE_LOCK_LIGHT_PROBE_S = 20 s) đếm ≤ LANE_LOCK_LIGHT_TESTS
(15) test + suite ma trận (kể cả rule chỉ-thêm), toàn test bash, mọi test và suite (trừ đúng lệnh runner kit scoped) `light` theo
heavy_slot.classify. Việc nhẹ lấy slot trống bất kỳ
như lúc tải thấp, không bao giờ quá LANE_LOCK_SLOTS người giữ; hết slot thì chờ slot như cũ. Thăm dò một lần, chỉ khi luật cũ bắt chờ vì
tải; lỗi, quá giờ, lệnh khác (chuỗi `bash -c`, --full, --since, --tree, cờ lạ) ⇒ việc nặng, luật cũ. Không file khoá hay marker mới.
ponytail: số test thay cho thời lượng; đo thấy lượt nhẹ > 5 phút thì xét theo thời lượng ghi nhận. Ở tải 12–24 việc nhẹ có thể vượt việc
nặng (việc nặng cần mọi slot trống); chấp nhận ở 2–3 lane.

#849 (mở rộng 02/11) — lệnh đang CHỜ pool gate của heavy_slot thì nhả slot lane: mỗi LANE_LOCK_POOL_POLL_S (5 s) đọc CHỈ ĐỌC vé
<heavy_slot.slot_dir()>/queue/gate/*.json; vé sống (heavy_slot.ticket_alive), wait_s > 0, đã chờ ≥ LANE_LOCK_POOL_WAIT_S (5 s), ghi sau lúc
con được tạo, và PID của vé là CHÍNH tiến trình con (lệnh là gate, kể cả qua `env …` / `exec`) ⇒ xoá .owner rồi nhả flock, không lấy lại:
phần còn lại của gate chạy trong pool gate (hết giờ pool thì gate báo BUSY, không chạy suite), nên số việc chạy thật ngoài pool không vượt
LANE_LOCK_SLOTS. Wrapper không bao giờ chặn con: không deadlock. Lệnh ghép (`bash -c "…; gate"`) giữ slot như cũ: phần khác của nó chạy
ngoài pool (review 02/11 vòng 2, P2-A/B). ponytail: hậu duệ chờ pool vẫn giữ slot lane; cần nhả cho lệnh ghép thì chỉ khi chứng minh được
phần còn lại nằm trong pool (đã chứng minh cho merge gate: P5 dưới).

P5 (02/11) — merge gate: lệnh con là super-board-merge-gate.sh (argv[0], hoặc `[env K=V…] bash <…/super-board-merge-gate.sh>`) thì mỗi
LANE_LOCK_POOL_POLL_S đọc cây tiến trình MỘT lần (`ps -A -o pid=,ppid=`) và nhả như trên khi một HẬU DUỆ của con có vé chờ pool gate đúng
luật #849, hoặc đang giữ slot pool gate (<slot_dir>/gate-<k>.lock.held ghi PID hậu duệ đó, mtime ≥ lúc tạo con). Vé queue/heavy không
bao giờ tính. ps lỗi ⇒ giữ slot (fail closed), log một lần, thăm lại vòng sau. ponytail: ngoài pool merge gate còn git/gh và, khi gate
REJECT, kiểm "đỏ sẵn trên base" (run_suite_on_base, ≤ 900 s mỗi suite đỏ, không slot): khi đó có thể chạy dư MỘT việc nặng so với
LANE_LOCK_SLOTS (khoá merge xếp merge gate nối tiếp nên không quá 1); cho run_suite_on_base vào pool gate khi đo thấy dư tải đó.

P7 (02/11) — chống dồn: load1 là trung bình trượt 1 phút, trễ 30–60 s; tải vừa tụt dưới ngưỡng thì cả loạt lane chờ vào cùng một vòng
(9 → 88 → 10). Lượt KHÔNG nhẹ chưa lấy khi có ≥ 1 slot lane KHÁC đang bị giữ thật (flock bận) mà lane-<j>.owner của nó mới
< LANE_LOCK_STAGGER_S tuổi (.owner chưa kịp ghi ⇒ tuổi 0), VÀ (lane này đã phải chờ vì tải ở vòng trước — tải ≥ LANE_LOCK_LOAD_TWO hay
không đọc được — hoặc tải ≥ LANE_LOCK_STAGGER_LOAD) ⇒ chờ vòng sau. 0 slot bị giữ ⇒ không bao giờ chặn. Slot bận gặp trên đường thăm
được xét tuổi TRƯỚC khi thử slot sau (hai lane cùng thức không khoá chéo slot 1 / slot 2 rồi cùng nhả). Bị chống dồn chặn thì thăm dò việc
nhẹ #849 như lúc chờ vì tải (việc nhẹ không bị chống dồn, lấy slot trống nếu có). Không file mới trong lock_dir: dùng .owner sẵn có.
"""
from __future__ import annotations

import json
import os
import random
import re
import signal
import stat
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import heavy_slot  # noqa: E402  dùng lại flock và đọc tải của kit, không sửa heavy_slot.py


def _env_num(name: str, default: float) -> float:
    try:
        value = float(os.environ.get(name, "") or default)
    except ValueError:
        return float(default)
    return value if value == value and 0 <= value != float("inf") else float(default)


def _git_common(cwd: str) -> str:
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True,
                           text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return ""
    out = r.stdout.strip()
    return os.path.abspath(out) if r.returncode == 0 and out else ""


def lock_dir() -> str:
    """LANE_LOCK_DIR; không đặt thì <git common dir của CWD>/lane-lock, rồi của repo chứa file này, rồi ~/.claude/super-board/locks/lane-lock."""
    custom = os.environ.get("LANE_LOCK_DIR", "").strip()
    if custom:
        return os.path.abspath(custom)
    common = _git_common(os.getcwd()) or _git_common(os.path.dirname(os.path.abspath(__file__)))
    if common:
        return os.path.join(common, "lane-lock")
    return os.path.join(os.path.expanduser("~"), ".claude", "super-board", "locks", "lane-lock")


def _say(msg: str, err: bool = False) -> None:
    """In log [lock]; pipe đầu ra đã đóng (BrokenPipeError) không được làm hỏng việc nhả khoá."""
    try:
        print(msg, file=sys.stderr if err else sys.stdout, flush=True)
    except OSError:
        pass


def _owners(paths: list) -> str:
    """Chủ của các slot đang bị giữ (thăm flock; file .owner chỉ để đọc, có thể cũ sau kill -9 nên chỉ đọc khi thăm thất bại)."""
    out = []
    for p in paths:
        probe = heavy_slot._try_lock_path(p)
        if probe is not None:
            heavy_slot._unlock(probe)
            continue
        try:
            with open(p[:-5] + ".owner", encoding="utf-8") as f:
                out.append(f.read().strip())
        except OSError:
            out.append(os.path.basename(p))
    return "; ".join(out) or "không ai"


_GATE = "post-fix-gate.py"
_PYTHON = re.compile(r"python(?:\d+(?:\.\d+)*)?")
_ASSIGN = re.compile(r"[A-Za-z_]\w*=")
# cờ post-fix-gate được phép ở việc nhẹ; cờ khác (--full, --force-full, --since, --tree, --staged, --matrix, viết tắt argparse…) ⇒ nặng
_LIGHT_FLAGS = {"--run-tests", "--scoped", "--brief", "--json", "--no-cache", "--no-fail-fast", "--no-checklist"}
_LIGHT_VALUE_FLAGS = {"--diff", "--task", "--lang", "-l", "--timeout"}   # --session/--transcript đổi base của gate ⇒ nặng


def gate_call(argv: list):
    """(đường dẫn thật của post-fix-gate.py, base hay "", env của gate) khi argv chạy thẳng `[env K=V…] [python…] …/post-fix-gate.py` với
    --run-tests --scoped và chỉ cờ của _LIGHT_FLAGS / _LIGHT_VALUE_FLAGS; None với mọi lệnh khác (#849)."""
    env = dict(os.environ)
    i = 0
    if argv and os.path.basename(argv[0]) == "env":
        i = 1
        while i < len(argv) and _ASSIGN.match(argv[i]):
            key, _, value = argv[i].partition("=")
            if key.startswith("GIT_"):   # GIT_DIR / GIT_WORK_TREE… đổi repo gate kiểm: không đoán, coi là nặng
                return None
            env[key] = value
            i += 1
    if i < len(argv) and _PYTHON.fullmatch(os.path.basename(argv[i])):
        i += 1
    if i >= len(argv) or os.path.basename(argv[i]) != _GATE:
        return None
    gate, rest, base, seen, k = argv[i], argv[i + 1:], "", set(), 0
    while k < len(rest):
        flag, eq, value = rest[k].partition("=")
        if flag in _LIGHT_VALUE_FLAGS:
            if not eq:
                k += 1
                if k >= len(rest):
                    return None
                value = rest[k]
            if flag == "--diff":
                if not value or ".." in value or value.startswith("-"):
                    return None
                base = value
        elif flag in _LIGHT_FLAGS and not eq:
            seen.add(flag)
        else:
            return None
        k += 1
    if not {"--run-tests", "--scoped"} <= seen or env.get("DEVKIT_GATE_MERGE_CHECK") == "1":   # lượt merge check: base khác lượt task
        return None
    return os.path.realpath(os.path.join(os.getcwd(), gate)), base, env


# Tiến trình con thăm dò (python -I: không nạp module theo cwd / PYTHONPATH). Base rỗng ⇒ nhánh đích như task_trunk của gate (origin/HEAD →
# origin/{main,master,trunk} → {main,master,trunk}); merge-base(base, HEAD) + cây làm việc ⊇ diff gate tự chọn. Phân loại bằng HÀM CỦA CHÍNH
# post-fix-gate.py sẽ chạy (INSTINCT-015, OCR 02/11): needs_no_test, find_matrix_path, load_active_matrix (bản ở merge-base) HỢP bản cây làm
# việc (JSON hỏng ⇒ nặng), checklist_covers + rule_watch. In một dòng JSON ở cuối stdout.
_PROBE = r"""
import importlib.util, json, re, subprocess, sys
gate_file, project, base, limit, own_bin = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
def out(light, why):
    print(json.dumps({"light": light, "why": why}, ensure_ascii=False))
    sys.exit(0)
def ok(ref):
    return subprocess.run(["git", "-C", project, "rev-parse", "--verify", "-q", ref + "^{commit}"], capture_output=True).returncode == 0
if not base:
    r = subprocess.run(["git", "-C", project, "symbolic-ref", "-q", "refs/remotes/origin/HEAD"], capture_output=True, text=True)
    refs = [r.stdout.strip()] if r.returncode == 0 and r.stdout.strip() else []
    refs += [p + n for p in ("refs/remotes/origin/", "refs/heads/") for n in ("main", "master", "trunk")]
    trunk = next((x for x in refs if ok(x)), "")   # như task_trunk của gate: ref hợp lệ đầu tiên
    name = trunk.split("refs/remotes/origin/", 1)[-1] if trunk.startswith("refs/remotes/origin/") else trunk[len("refs/heads/"):]
    br = subprocess.run(["git", "-C", project, "symbolic-ref", "-q", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    # không có nhánh đích, hay đứng ngay trên nó (task_off_trunk sai): gate kiểm upstream..HEAD của cây sạch đi trước upstream, không thì cây
    base = trunk if trunk and name != br else ("@{upstream}" if ok("@{upstream}") else "HEAD")
mb = subprocess.run(["git", "-C", project, "merge-base", base, "HEAD"], capture_output=True, text=True).stdout.strip() or base
sys.path[:0] = [gate_file.rsplit("/", 1)[0], own_bin]   # scoped_gate / heavy_slot của kit gate; heavy_slot thiếu thì của lane_lock
spec = importlib.util.spec_from_file_location("lane_lock_probe_gate", gate_file)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
import scoped_gate as sg
def rules_of(data, where):
    got = data.get("rules", []) if isinstance(data, dict) else None
    if not isinstance(got, list):
        out(False, "ma trận %s: rules không phải danh sách" % where)
    return got
matrix, _trust = gate.load_active_matrix(None, mb)
rules = rules_of(matrix, "ở base")
added = set(gate.trust_additive_matrix(matrix, _trust, None, mb)[2] or ())   # rule chỉ-thêm: gate chạy cả khi watch không khớp
path = gate.find_matrix_path(None)
if path is not None:
    try:
        with open(path, encoding="utf-8") as f:
            rules = rules + rules_of(json.load(f), str(path))
    except (OSError, ValueError) as e:
        out(False, "ma trận %s đọc lỗi (%s)" % (path, e))
res = sg.no_full(sg.decide(project, base, needs_no_test=gate.needs_no_test, matrix_rules=rules), project)
if res.get("graph_error"):
    out(False, "đồ thị lỗi")
tests = list(dict.fromkeys(list(res.get("tests") or []) + list(res.get("smoke") or [])))
odd = [t for t in tests if not t.endswith((".sh", ".bash"))]
if odd:
    out(False, "test không chạy bằng bash: " + odd[0])
# runner kit chỉ chạy danh sách scoped khi lệnh là ĐÚNG runner (tiền tố shard tuỳ chọn, không đối số, không lệnh ghép): `--all` bỏ
# DEVKIT_SCOPED_TESTS (tests/run_impacted.sh), lệnh ghép chạy cả phần khác ⇒ mọi lệnh khác có run_impacted.sh là nặng
runner = re.compile(r"^\s*(?:DEVKIT_IMPACTED_DIRS=[\w!,.-]+\s+)?(?:bash\s+)?[\w./-]*tests/run_impacted\.sh\s*$")
paths = list(res.get("changed") or []) + tests
covers = gate.checklist_covers()
cmds = []
for rule in rules:
    if not isinstance(rule, dict):
        continue
    watch = [p for p in gate.rule_watch(rule, covers) if isinstance(p, str)]
    hit = any(sg.match_pattern(f, p) for f in paths for p in watch)
    for t in rule.get("mandatory_regression_tests") or []:
        c = t.get("command") if isinstance(t, dict) else None
        if not (isinstance(c, str) and c and (hit or t.get("id") in added)) or c in cmds or runner.match(c):
            continue
        if "run_impacted.sh" in c:
            out(False, "runner kit không chỉ chạy danh sách scoped: " + c[:80])
        cmds.append(c)
n = len(tests) + len(cmds)
if n > limit:
    out(False, "%d test + suite > %d" % (n, limit))
import heavy_slot as hs
for c in ["bash " + t for t in tests] + cmds:   # test do decide chọn cũng phân loại (thân script gọi gradle/unity ⇒ nặng)
    cls = hs.classify(c, project)["cls"]
    if cls != "light":
        out(False, "suite %s: %s" % (cls, c[:80]))
out(True, "%d test + suite" % n)
"""


def light_job(argv: list) -> tuple:
    """(True, lý do) khi argv là gate scoped NHỎ (#849); (False, lý do) với mọi việc khác và mọi lỗi của bộ thăm dò (fail closed)."""
    call = gate_call(argv)
    if call is None:
        return False, "không phải gate --scoped"
    gate_file, base, env = call
    if not (os.path.isfile(gate_file) and os.path.isfile(os.path.join(os.path.dirname(gate_file), "scoped_gate.py"))):
        return False, "không thấy post-fix-gate.py / scoped_gate.py của gate"
    target = env.get("CLAUDE_PROJECT_DIR") or env.get("TARGET_DIR")   # như get_project_dir của gate
    if target and os.path.exists(target):
        project = os.path.realpath(target)
    else:
        try:
            r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            return False, "không đọc được gốc repo"
        project = os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else os.path.realpath(os.getcwd())
    limit = int(_env_num("LANE_LOCK_LIGHT_TESTS", 15))
    try:
        r = subprocess.run([sys.executable, "-I", "-c", _PROBE, gate_file, project, base, str(limit),
                            os.path.dirname(os.path.abspath(__file__))], capture_output=True, text=True,
                           timeout=_env_num("LANE_LOCK_LIGHT_PROBE_S", 20.0), env=env, cwd=project)
    except subprocess.TimeoutExpired:
        return False, "thăm dò quá giờ"
    except (OSError, subprocess.SubprocessError) as exc:
        return False, f"thăm dò không chạy được ({exc})"
    try:
        verdict = json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        verdict = None
    if r.returncode != 0 or not isinstance(verdict, dict) or not isinstance(verdict.get("light"), bool):
        tail = (r.stderr.strip().splitlines() or [f"rc {r.returncode}"])[-1][:120]
        return False, f"thăm dò lỗi ({tail})"
    return verdict["light"], str(verdict.get("why") or "")


def _read_small(path: str, limit: int) -> bytes:
    """Tối đa limit byte của một FILE THƯỜNG (O_NOFOLLOW, O_NONBLOCK: symlink lỗi, FIFO không treo — INSTINCT-040); fd luôn đóng."""
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    try:
        return os.read(fd, limit) if stat.S_ISREG(os.fstat(fd).st_mode) else b""
    finally:
        os.close(fd)


def _gate_tickets() -> list:
    """[(pid, t0, nhãn)] của vé pool gate còn sống (heavy_slot.ticket_alive) và wait_s > 0 (wait_s 0 = lượt thăm chỗ trống của gate).
    Hàm này chỉ mở vé để đọc (không dùng heavy_slot._read_tickets: thân hàm đó gọi os.remove trên vé chết); vé lỗi ⇒ bỏ vé đó."""
    qdir = os.path.join(heavy_slot.slot_dir(), "queue", "gate")
    try:
        names = [n for n in os.listdir(qdir) if n.endswith(".json")]
    except OSError:
        return []
    now = time.time()
    out = []
    for n in names:
        try:
            t = json.loads(_read_small(os.path.join(qdir, n), 65536).decode("utf-8"))
            if isinstance(t, dict) and heavy_slot.ticket_alive(t, now) and float(t.get("wait_s")) > 0:
                out.append((int(t.get("pid")), float(t.get("t0")), str(t.get("label") or "")[:60]))
        except (OSError, ValueError, TypeError, OverflowError, RecursionError):   # pid 1e400, JSON lồng quá sâu, file rỗng…
            continue
    return out


_MERGE_GATE = "super-board-merge-gate.sh"
_HELD = re.compile(r"gate-\d+\.lock\.held")   # marker của heavy_slot._write_gate_held; không khớp file tạm <held>.<pid>.<rand>.tmp


def merge_gate_call(argv: list) -> bool:
    """P5: argv chạy thẳng super-board-merge-gate.sh — argv[0] là nó, hoặc `[env K=V…] [bash] <…/super-board-merge-gate.sh> …`.
    Lệnh ghép (`bash -c "…"`), cờ của bash / env ⇒ False (luật cũ)."""
    i = 0
    if argv and os.path.basename(argv[0]) == "env":
        i = 1
        while i < len(argv) and _ASSIGN.match(argv[i]):
            i += 1
    if i < len(argv) and os.path.basename(argv[i]) == "bash":
        i += 1
    return i < len(argv) and os.path.basename(argv[i]) == _MERGE_GATE


class _Tree(set):
    """Tập PID hậu duệ + `started` {pid: epoch lúc tiến trình bắt đầu} (chỉ những PID ps báo được lstart)."""
    started: dict


def _lstart(parts: list):
    """lstart của ps (`Mon Nov  3 11:08:00 2026`, 5 token, locale C) → epoch; None khi không đọc được."""
    try:
        return time.mktime(time.strptime(" ".join(parts), "%a %b %d %H:%M:%S %Y"))
    except (ValueError, OverflowError):
        return None


def _descendants(root: int):
    """P5: tập PID gồm root và mọi hậu duệ còn sống (một lần `ps -A -o pid=,ppid=,stat=,lstart=`); None khi ps lỗi (chỗ gọi giữ slot).
    Hậu duệ zombie (stat Z) bị bỏ (#914 mục 4): tiến trình đã chết, flock của nó đã nhả. `started` ghi lstart để _gate_held loại marker
    .held cũ hơn tiến trình mang PID đó (PID tái dụng)."""
    try:
        r = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,stat=,lstart="], capture_output=True, text=True, timeout=10,
                           env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    kids, zombie, started = {}, set(), {}
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0].isdigit() and parts[1].isdigit():
            pid = int(parts[0])
            kids.setdefault(int(parts[1]), []).append(pid)
            if parts[2].startswith("Z"):
                zombie.add(pid)
            st = _lstart(parts[3:8])
            if st is not None:
                started[pid] = st
    out = _Tree({root})
    out.started = started
    todo = [root]
    while todo:
        for kid in kids.get(todo.pop(), ()):
            if kid not in out:
                todo.append(kid)
                if kid not in zombie:
                    out.add(kid)
    return out


def _gate_held(pids: set, spawned: float):
    """P5: (pid, nhãn) khi <slot_dir>/gate-<k>.lock.held (slot pool gate đang giữ) ghi một PID trong pids và mtime ≥ spawned; None khi
    không. Chỉ đọc (_read_small: symlink / FIFO không treo); marker lỗi ⇒ bỏ marker đó. Marker cũ hơn lúc tiến trình mang PID đó bắt
    đầu (lstart > mtime + 2 s) là của tiến trình đã chết trùng số ⇒ bỏ (#914 mục 4)."""
    d = heavy_slot.slot_dir()
    started = getattr(pids, "started", {})
    try:
        names = [n for n in os.listdir(d) if _HELD.fullmatch(n)]
    except OSError:
        return None
    for n in names:
        path = os.path.join(d, n)
        try:
            pid = int(_read_small(path, 64).decode("ascii").strip())
            mtime = os.stat(path, follow_symlinks=False).st_mtime
            if pid in pids and mtime >= spawned and started.get(pid, 0.0) <= mtime + 2.0:
                return pid, "giữ " + n[:-5]
        except (OSError, ValueError, UnicodeDecodeError):
            continue
    return None


def pool_waiting(root: int, spawned: float, tree=None):
    """(pid, nhãn) khi CHÍNH tiến trình con root (lệnh là gate, kể cả qua `env …` / `exec`) có vé chờ pool gate đã chờ
    ≥ LANE_LOCK_POOL_WAIT_S; None khi không. Vé ghi trước lúc con được tạo (t0 < spawned) là vé mồ côi của một PID cũ trùng số.
    tree (P5, chỉ merge gate): tập PID hậu duệ của root — vé của một hậu duệ bất kỳ, hay slot pool gate hậu duệ đang giữ, cũng tính."""
    min_age = _env_num("LANE_LOCK_POOL_WAIT_S", 5.0)
    now = time.time()
    pids = {root} if tree is None else tree
    for pid, t0, label in _gate_tickets():
        if pid in pids and t0 >= spawned and now - t0 >= min_age:
            return pid, label
    return None if tree is None else _gate_held(tree, spawned)


def _owner_fresh(path: str, now: float) -> bool:
    """P7: lane-<j>.owner của slot (đang bị giữ) mới < LANE_LOCK_STAGGER_S tuổi; chưa có / không đọc được ⇒ tuổi 0 (fail closed)."""
    try:
        age = now - os.stat(path[:-5] + ".owner").st_mtime
    except OSError:
        age = 0.0
    return age < _env_num("LANE_LOCK_STAGGER_S", 60.0)


STAGGERED = -1   # cap trả về khi chống dồn (P7) chặn (slot bận còn non; có thể vẫn còn slot trống)


def try_take(paths: list, load, light: bool = False, stagger: bool = False) -> tuple:
    """Một lượt xin slot theo tải. Trả (fh, chỉ số slot, cap) khi lấy được, (None, None, cap) khi phải chờ.
    light (#849): bỏ ngưỡng tải, lấy slot trống bất kỳ như lúc tải thấp (không quá len(paths) người giữ).
    stagger (P7, chỉ lượt không nhẹ): slot khác bị giữ mà .owner còn non ⇒ (None, None, STAGGERED)."""
    two = _env_num("LANE_LOCK_LOAD_TWO", 12.0)
    cap_max = _env_num("LANE_LOCK_LOAD_MAX", 24.0)
    if not light and load is not None and load >= cap_max:
        return None, None, 0
    if light or (load is not None and load < two):
        stagger = stagger and not light
        now = time.time()
        for i, path in enumerate(paths):
            fh = heavy_slot._try_lock_path(path)
            if fh is None:
                if stagger and _owner_fresh(path, now):   # xét slot bận TRƯỚC khi thử slot sau: không khoá chéo với lane cùng thức
                    return None, None, STAGGERED
                continue
            if stagger:   # slot sau slot vừa lấy: thăm flock, bận mà .owner còn non ⇒ nhả, chờ vòng sau
                for later in paths[i + 1:]:
                    probe = heavy_slot._try_lock_path(later)
                    if probe is not None:
                        heavy_slot._unlock(probe)
                    elif _owner_fresh(later, now):
                        heavy_slot._unlock(fh)
                        return None, None, STAGGERED
            return fh, i, len(paths)
        return None, None, len(paths)
    # tải cao (hoặc đọc lỗi): 1 slot = phải lấy được slot đầu VÀ mọi slot khác đang trống (không ai khác giữ)
    fh = heavy_slot._try_lock_path(paths[0])
    if fh is None:
        return None, None, 1
    for path in paths[1:]:
        probe = heavy_slot._try_lock_path(path)
        if probe is None:
            heavy_slot._unlock(fh)
            return None, None, 1
        heavy_slot._unlock(probe)
    return fh, 0, 1


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        print("dùng: lane_lock.py <tên> [--] <lệnh…>", file=sys.stderr)
        return 2
    name = args.pop(0)
    if args and args[0] == "--":
        args.pop(0)
    if not args:
        print("dùng: lane_lock.py <tên> [--] <lệnh…>", file=sys.stderr)
        return 2
    d = lock_dir()
    os.makedirs(d, mode=0o700, exist_ok=True)
    slots = max(1, int(_env_num("LANE_LOCK_SLOTS", 2)))
    paths = [os.path.join(d, f"lane-{k}.lock") for k in range(1, slots + 1)]
    poll = max(0.02, _env_num("LANE_LOCK_POLL_S", 5.0))
    log_every = _env_num("LANE_LOCK_LOG_S", 60.0)
    t0 = time.monotonic()
    last_log = None
    light = None   # (bool, lý do) của #849: thăm dò một lần, chỉ khi luật cũ vừa bắt chờ vì tải (tải thấp, hay lấy được ngay: không tốn gì)
    load_waited = False   # P7: lane này đã phải chờ vì tải ở một vòng trước
    stagger_t0 = None     # P7: lúc lane bị chống dồn lần đầu; quá LANE_LOCK_STAGGER_S thì thôi (review: job ngắn nối đuôi làm lane chờ đói)
    while True:
        load = heavy_slot.load_now()
        is_light = bool(light and light[0])
        stagger = not is_light and (load_waited or load is None or load >= _env_num("LANE_LOCK_STAGGER_LOAD", 6.0)) and (
            stagger_t0 is None or time.monotonic() - stagger_t0 < _env_num("LANE_LOCK_STAGGER_S", 60.0))
        fh, idx, cap = try_take(paths, load, is_light, stagger)
        if cap == STAGGERED and stagger_t0 is None:
            stagger_t0 = time.monotonic()
        high = load is None or load >= _env_num("LANE_LOCK_LOAD_TWO", 12.0)
        if fh is None and light is None and (high or cap == STAGGERED):
            light = light_job(args)
            _say(f"[lock] {name} " + (f"nhẹ ({light[1]}): bỏ ngưỡng tải, vẫn giữ số slot" if light[0] else f"việc nặng ({light[1]})"))
            if light[0]:
                fh, idx, cap = try_take(paths, load, True)
        if fh is not None:
            break
        load_waited = load_waited or high
        now = time.monotonic()
        if last_log is None or now - last_log >= log_every:
            why = f"load {load:.1f} ≥ {_env_num('LANE_LOCK_LOAD_MAX', 24.0):g}" if cap == 0 else f"đủ {cap} slot"
            if cap == STAGGERED:
                why = f"chống dồn: slot khác vừa được lấy < {_env_num('LANE_LOCK_STAGGER_S', 60.0):g} s"
            if load is None:
                why += " (không đọc được tải: coi là tải cao)"
            _say(f"[lock] {name} chờ ({why}; đang giữ: {_owners(paths)}) {time.strftime('%T')}")
            last_log = now
        time.sleep(poll + random.uniform(0.0, min(1.0, poll * 0.25)))
    waited = time.monotonic() - t0
    owner = paths[idx][:-5] + ".owner"
    t1 = time.monotonic()
    rc = 127
    proc = None
    forwarded = {}
    released = None   # monotonic lúc nhả slot sớm (#849: lệnh chờ pool gate); từ đó slot và .owner có thể là của lane khác
    spawned = 0.0   # time.time() ngay trước Popen: vé của con phải ghi sau lúc này

    def _signal_group(sig) -> bool:
        """Gửi sig cho cả nhóm của con; False khi nhóm không còn (macOS: nhóm chỉ còn zombie trả PermissionError)."""
        try:
            os.killpg(proc.pid, sig)
            return True
        except (ProcessLookupError, PermissionError):
            return False
        except OSError:
            return False

    def _forward(sig, _frame):
        forwarded["sig"] = sig
        if proc is not None:
            _signal_group(sig)

    old = {s: signal.signal(s, _forward) for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
    try:   # mọi bước sau khi giữ slot nằm trong try: lỗi ở đâu cũng nhả slot
        try:
            with open(owner, "w", encoding="utf-8") as f:
                f.write(f"{name} pid {os.getpid()} từ {time.strftime('%T')}\n")
        except OSError:
            pass
        ltxt = "?" if load is None else f"{load:.1f}"
        _say(f"[lock] {name} giữ khoá {time.strftime('%T')} (slot {idx + 1}/{len(paths)}, cho phép {cap}, chờ {waited:.0f} s, load {ltxt}"
             f"{', nhẹ' if light and light[0] else ''})")
        try:
            spawned = time.time()
            proc = subprocess.Popen(args, close_fds=True, start_new_session=True)
        except OSError as exc:
            _say(f"[lock] {name}: không chạy được {args[0]}: {exc}", err=True)
        else:
            if forwarded:   # tín hiệu tới trước khi con kịp chạy: gửi lại cho nhóm của con
                _signal_group(forwarded["sig"])
            pool_poll = max(0.05, _env_num("LANE_LOCK_POOL_POLL_S", 5.0))   # None: thôi thăm dò (đã nhả, hoặc lỗi bất ngờ ⇒ giữ slot)
            merge_gate = merge_gate_call(args)   # P5: hậu duệ của merge gate ở pool gate cũng nhả
            ps_failed = False
            while True:
                try:
                    status = proc.wait(timeout=None if released is not None else pool_poll)
                    break
                except InterruptedError:
                    continue
                except subprocess.TimeoutExpired:
                    try:
                        tree = None
                        if merge_gate:
                            tree = _descendants(proc.pid)
                            if tree is None:   # fail closed: giữ slot, thăm lại vòng sau; log một lần
                                if not ps_failed:
                                    _say(f"[lock] {name}: ps lỗi khi tìm hậu duệ của merge gate; giữ slot lane", err=True)
                                ps_failed = True
                                continue
                        waiting = pool_waiting(proc.pid, spawned, tree)
                    except Exception as exc:  # noqa: BLE001 - thăm dò vé không được làm chết wrapper khi con còn chạy
                        _say(f"[lock] {name}: thăm dò pool gate lỗi ({exc!r}); giữ slot tới khi lệnh xong", err=True)
                        pool_poll = None
                        continue
                    if waiting is not None:   # .owner xoá TRƯỚC khi nhả: không xoá owner của người lấy slot sau
                        try:
                            os.remove(owner)
                        except OSError:
                            pass
                        heavy_slot._unlock(fh)
                        released = time.monotonic()
                        who = "hậu duệ của merge gate ở" if tree is not None else "lệnh đang chờ"
                        _say(f"[lock] {name} nhả slot lane sau {released - t1:.0f} s: {who} pool gate (pid {waiting[0]}"
                             f"{', ' + waiting[1] if waiting[1] else ''}); phần còn lại của gate chạy trong pool, không lấy lại")
            rc = status if status >= 0 else 128 - status
            # cháu cùng nhóm còn sống: chờ ân hạn LANE_LOCK_GRACE_S rồi mới nhả slot; nhận tín hiệu thì giết nốt nhóm sau ân hạn
            grace_end = time.monotonic() + _env_num("LANE_LOCK_GRACE_S", 5.0)
            while _signal_group(0) and time.monotonic() < grace_end:
                time.sleep(0.1)
            if _signal_group(0):
                if forwarded:
                    _signal_group(signal.SIGKILL)
                _say(f"[lock] {name}: nhóm tiến trình của lệnh vẫn còn sau ân hạn"
                     f"{' (đã KILL vì nhận tín hiệu)' if forwarded else ''}", err=True)
    finally:
        for s, h in old.items():
            signal.signal(s, h)
        if released is None:
            try:
                os.remove(owner)
            except OSError:
                pass
            heavy_slot._unlock(fh)
        early = "" if released is None else f", nhả slot sớm sau {released - t1:.0f} s"
        _say(f"[lock] {name} nhả khoá rc={rc} {time.strftime('%T')} (giữ {time.monotonic() - t1:.0f} s{early})")
    return rc


if __name__ == "__main__":
    sys.exit(main())
