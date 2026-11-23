#!/usr/bin/env python3
"""Biên bản duyệt chéo `claude-verify` (#1328): nguồn duyệt của merge queue ngoài antigravity-pm.

  register --lane build|review --repo DIR --issue N --session SID [--engine claude|antigravity]   runner ghi sổ phiên TRƯỚC khi chạy worker (chỉ thêm, không xoá).
      Trong env phiên agent (CLAUDECODE=1 hoặc CLAUDE_CODE_SESSION_ID) → exit 2, trừ khi lệnh mang cờ SB_RUNNER_REGISTER=1 mà
      super-board-run.sh đặt inline; hook PreToolUse (block_dangerous_git_main.py) chặn lệnh Bash của agent gọi register hay mang cờ đó.
  seal --repo DIR --head SHA40 --report FILE --branch issue-N-…      exit 0 pass, 4 = có finding important, 2 = báo cáo/phiên bị từ
                                                                     chối, 3 = không kiểm được (git/kit lỗi, seal mode bật)
  check TASK_ID SHA40 --branch B [--top DIR] [--pr N]                 exit 0 = biên bản pass đúng head/tree, phiên hợp lệ, thẻ của nhánh
                                                                     PR B trùng thẻ biên bản; 1 = còn lại (thiếu --branch cũng là 1)

`seal` kiểm báo cáo {head, base, findings:[{id, severity, file, line, snippet, class}], reviewed_at}: head sha40 == --head và là đỉnh
của nhánh --branch ở origin (refs/remotes/origin/<b>; nhánh local không tính); base == merge-base(trunk, head) (push_gate._trunk_ref); finding có
severity important|nit|pre-existing, file thuộc diff, dòng trong hunk thêm ở head (pre-existing được ngoài hunk), snippet khớp dòng đó.
task_id = CV<yyyymmdd>T<HHMMSS>-<head12>-<6 hex ngẫu nhiên>, ghi O_EXCL (không đè biên bản khác).

Phiên (kiểm cả lúc seal lẫn lúc check): thẻ N lấy từ nhánh issue-N-…. Tập builder = sổ builders của thẻ N (runner ghi --session-id
của worker build trước khi nó chạy, nên builder không tránh được) ∪ session_id trong devkit-session.lock của worktree còn sống đứng trên
nhánh có HEAD == head. Tập builder rỗng, hay lỗi đọc git/sổ → từ chối (fail closed). Reviewer = env CLAUDE_CODE_SESSION_ID, phải có
trong sổ reviewers của thẻ N và không thuộc tập builder. Hệ quả: claude-verify chỉ dùng được cho thẻ do board giao; phiên tay ngoài
board đi Antigravity hoặc chủ repo duyệt.

Biên bản: <home của uid>/.claude-verify/records/<task_id>.json = {"payload": "<JSON chuẩn>", "sig": base64|null}; sổ ở
<home>/.claude-verify/{builders,reviewers}/<repo-key>/issue-<N>.jsonl (repo-key = sha256(git common dir)[:16]). Seal mode
(verdict_seal.seal_mode: chủ repo cài pubkey root-owned) BẬT → chỉ nhận biên bản có chữ ký Ed25519 hợp lệ của pubkey tin cậy; agent
không tự ký được nên `seal` báo "cần chủ repo cài signer claude-verify" (exit 3). Seal mode TẮT → nhận biên bản không ký.

Rủi ro còn lại (chấp nhận; cùng mức biên bản ~/.antigravity-pm khi seal mode tắt; đóng hẳn khi có signer của chủ repo): agent cùng
uid CỐ Ý vòng qua (python -c gọi hàm register, script trong file, sửa thẳng file sổ / biên bản dưới ~) vẫn tự cấp duyệt được. Thư mục lạ (CLAUDE_VERIFY_HOME) chỉ nhận trong fixture test: DEVKIT_PM_HOME_TEST=1,
thư mục dưới gốc tạm cố định VÀ repo cũng dưới gốc tạm (như push_gate._seal_fixture); ngoài fixture → từ chối hết. Không theo $HOME.
"""
import base64
import datetime
import hashlib
import importlib.util
import json
import os
import re
import secrets
import subprocess
import sys

TASK_ID = re.compile(r"\ACV[0-9]{8}T[0-9]{6}-[0-9a-f]{12}-[0-9a-f]{6}\Z")
SHA40 = re.compile(r"\A[0-9a-f]{40}\Z")
SESSION = re.compile(r"\A[A-Za-z0-9._:-]{1,128}\Z")
BRANCH = re.compile(r"\Aissue-([0-9]{1,9})(?:-[A-Za-z0-9._/-]{1,200})?\Z")
ENGINES = ("claude", "antigravity")
SEVERITIES = ("important", "nit", "pre-existing")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
MAX_BYTES = 2_000_000
HERE = os.path.dirname(os.path.realpath(__file__))


class Unchecked(Exception):
    """Không kiểm được (git / kit / sổ lỗi): người gọi từ chối, không bao giờ coi là đạt."""


def _load(name):
    """Module của kit cạnh file này (đường thật, không theo env); lỗi nạp → Unchecked."""
    try:
        spec = importlib.util.spec_from_file_location("cv_" + name, os.path.join(HERE, name + ".py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception as e:   # noqa: BLE001 - kit thiếu/hỏng: báo rõ, không traceback
        raise Unchecked(f"không nạp được {name}.py của kit ({e.__class__.__name__})") from None


def git(top, *args, timeout=30):
    try:
        r = subprocess.run(["git", "-C", top, *args], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return 1, ""
    return r.returncode, r.stdout


def _fixture(top):
    """Fixture test: công tắc DEVKIT_PM_HOME_TEST=1 + CLAUDE_VERIFY_HOME dưới gốc tạm + repo dưới gốc tạm."""
    home = os.environ.get("CLAUDE_VERIFY_HOME")
    if os.environ.get("DEVKIT_PM_HOME_TEST") != "1" or not home:
        return False
    vs = _load("verdict_seal")
    return vs._under_tmp(home) and vs.fixture_repo(top)


def root(top):
    """Thư mục gốc claude-verify; CLAUDE_VERIFY_HOME ngoài fixture → Unchecked (fail closed)."""
    if os.environ.get("CLAUDE_VERIFY_HOME"):
        if not _fixture(top):
            raise Unchecked("CLAUDE_VERIFY_HOME chỉ dùng trong fixture test")
        return os.environ["CLAUDE_VERIFY_HOME"]
    try:
        import pwd  # noqa: PLC0415 - chỉ POSIX
        return os.path.join(pwd.getpwuid(os.getuid()).pw_dir, ".claude-verify")
    except (ImportError, KeyError):
        raise Unchecked("không đọc được home của uid") from None


def _ledger(top, lane, issue):
    rc, common = git(top, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if rc != 0 or not common.strip():
        raise Unchecked("git rev-parse --git-common-dir lỗi")
    key = hashlib.sha256(os.path.realpath(common.strip()).encode()).hexdigest()[:16]
    return os.path.join(root(top), "builders" if lane == "build" else "reviewers", key, f"issue-{int(issue)}.jsonl")


def ledger_sessions(top, lane, issue):
    """Các session id trong sổ; không có file = rỗng; dòng hỏng / lỗi đọc → Unchecked."""
    return {s for s, _ in ledger_rows(top, lane, issue)}


def ledger_rows(top, lane, issue):
    """[(session, ts datetime)] theo thứ tự ghi; không có file = []; dòng hỏng / ts sai dạng / lỗi đọc → Unchecked."""
    return [(s, t) for s, t, _ in _rows(top, lane, issue)]


def _rows(top, lane, issue):
    """[(session, ts, engine)]; dòng không có engine = claude (sổ cũ). Engine lạ → Unchecked (fail closed)."""
    path = _ledger(top, lane, issue)
    try:
        with open(path, encoding="utf-8") as fh:
            rows = [json.loads(line) for line in fh if line.strip()]
    except FileNotFoundError:
        return []
    except (OSError, ValueError, RecursionError) as e:
        raise Unchecked(f"sổ {lane} hỏng ({e.__class__.__name__})") from None
    if not all(isinstance(r, dict) and isinstance(r.get("session"), str) and SESSION.fullmatch(r["session"]) for r in rows):
        raise Unchecked(f"sổ {lane} có dòng sai dạng")
    if any(r.get("engine", "claude") not in ENGINES for r in rows):
        raise Unchecked(f"sổ {lane} có engine lạ")
    try:
        out = [(r["session"], datetime.datetime.fromisoformat(r["ts"]), r.get("engine", "claude")) for r in rows]
    except (KeyError, TypeError, ValueError):
        raise Unchecked(f"sổ {lane} có ts sai dạng") from None
    if any(t.tzinfo is None for _, t, _ in out):
        raise Unchecked(f"sổ {lane} có ts thiếu múi giờ")
    return out


def agent_env():
    """True khi lệnh chạy trong env phiên agent mà không có cờ runner (register bị từ chối)."""
    agent = os.environ.get("CLAUDECODE") == "1" or bool(os.environ.get("CLAUDE_CODE_SESSION_ID"))
    return agent and os.environ.get("SB_RUNNER_REGISTER") != "1"


def register(top, lane, issue, session, engine="claude"):
    if engine not in ENGINES or lane not in ("build", "review") or not SESSION.fullmatch(session or "") or not 0 < int(issue) < 10 ** 9:
        raise Unchecked("register: lane/issue/session sai dạng")
    path = _ledger(top, lane, issue)
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    line = json.dumps({"session": session, "engine": engine, "ts": datetime.datetime.now(datetime.timezone.utc).isoformat()}) + "\n"
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, line.encode())
    finally:
        os.close(fd)


def lock_builders(top, head):
    """session_id trong lock của worktree còn sống đứng trên một nhánh (không detached) có HEAD == head; git lỗi → Unchecked."""
    rc, out = git(top, "worktree", "list", "--porcelain")
    if rc != 0:
        raise Unchecked("git worktree list lỗi")
    found = set()
    sl = _load("session_lock")
    for block in out.split("\n\n"):
        f = dict(line.split(" ", 1) for line in block.splitlines() if " " in line)
        if f.get("HEAD") != head or not f.get("branch") or "worktree" not in f:
            continue
        rc, gdir = git(f["worktree"], "rev-parse", "--absolute-git-dir", timeout=10)
        lock = sl.read_lock(os.path.join(gdir.strip(), sl.LOCK)) if rc == 0 else None
        sid = lock.get("session_id") if lock else None
        if isinstance(sid, str) and sid.strip():
            found.add(sid.strip())
    return found


def session_problem(top, head, issue, reviewer, recorded_builders=()):
    """Lý do từ chối phiên reviewer của thẻ `issue`, hoặc None; lỗi kiểm → Unchecked."""
    build_rows = ledger_rows(top, "build", issue)
    # Review vòng 1 (R1/R2): lượt build do engine không phải Claude (agy: không hook, không env phiên) không kiểm được "reviewer ≠ builder"
    # và có thể tự register reviewer → thẻ đó không dùng được claude-verify (fail closed); đi Antigravity hoặc chủ repo duyệt.
    other = sorted({e for _, _, e in _rows(top, "build", issue) if e != "claude"})
    if other:
        return f"thẻ #{issue} có lượt build không phải Claude ({', '.join(other)}): claude-verify không kiểm được phiên đó"
    # Nguồn xác thực builder phải tới từ sổ runner hoặc lock worktree thật; recorded_builders chỉ mở rộng tập cấm tự duyệt, không thay thế sổ rỗng.
    known_builders = {s for s, _ in build_rows} | lock_builders(top, head)
    known_builders.discard("")
    if not known_builders:
        return f"không biết phiên builder của thẻ #{issue} (sổ builders rỗng): claude-verify chỉ dùng cho thẻ board giao"
    builders = known_builders | set(recorded_builders)
    builders.discard("")
    if not isinstance(reviewer, str) or not SESSION.fullmatch(reviewer):
        return "không rõ phiên reviewer"
    if reviewer in builders:
        return "phiên reviewer là phiên builder của thẻ: tự duyệt không tính"
    reviews = [t for s, t in ledger_rows(top, "review", issue) if s == reviewer]
    if not reviews:
        return f"phiên reviewer không có trong sổ reviewers của thẻ #{issue} (runner chưa giao review cho phiên này)"
    # T0005: reviewer của vòng trước (sid đã lộ trong sổ/log worker) không duyệt được commit của lượt build sau nó.
    builds = [t for _, t in build_rows]
    if builds and max(reviews) <= max(builds):
        return f"phiên reviewer được giao trước lượt build mới nhất của thẻ #{issue}: chỉ reviewer giao sau lượt build đó mới duyệt được"
    return None


def added_lines(top, base, head):
    """{file: set(dòng thêm ở head), hoặc None khi file bị xoá ở head} của diff base..head; None khi git lỗi."""
    rc, out = git(top, "-c", "core.quotePath=false", "diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", base, head)
    if rc != 0:
        return None
    files, cur, header, minus = {}, None, False, None
    for line in out.splitlines():
        if line.startswith("diff --git "):
            cur, header, minus = None, True, None   # dòng ---/+++ chỉ đọc ở phần đầu, không nhầm dòng nội dung "++ x" được thêm
        elif header and line.startswith("+++ "):
            cur = line[6:].rstrip("\t") if line.startswith("+++ b/") else None
            if cur is not None:
                if files.get(cur) is None:
                    files[cur] = set()   # typechange: khối xoá đứng trước khối thêm cùng tên; còn ở head thì không phải đã xoá
            elif line == "+++ /dev/null" and minus is not None:
                files[minus] = None   # --no-renames: file bị xoá hẳn ở head
        elif header and line.startswith("--- a/"):
            minus = line[6:].rstrip("\t")   # tên có khoảng trắng: git thêm tab cuối dòng
            files.setdefault(minus, set())   # file bị xoá vẫn thuộc diff, không có dòng thêm
        elif line.startswith("@@"):
            header = False
            m = HUNK.match(line)
            if m and cur is not None:
                start, n = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
                files[cur].update(range(start, start + n))
    return files


def _finding_problem(top, head, base, f, lines):
    if not isinstance(f, dict) or not all(isinstance(f.get(k), str) and f[k].strip() for k in ("id", "severity", "file", "snippet")):
        return "finding thiếu id/severity/file/snippet"
    if f["severity"] not in SEVERITIES:
        return f"finding {f['id']}: severity {f['severity']!r} không thuộc {SEVERITIES}"
    ln = f.get("line")
    if type(ln) is not int or ln < 1:
        return f"finding {f['id']}: thiếu số dòng (line)"
    if f["file"] not in lines:
        return f"finding {f['id']}: {f['file']} không thuộc diff base..head"
    # #1323: file bị xoá ở head (thuộc diff, không có ở head) → dòng và snippet đối chiếu với base; không có hunk thêm để đòi.
    deleted = lines[f["file"]] is None
    ref, where = (base, "base (file đã xoá ở head)") if deleted else (head, "head")
    if not deleted and f["severity"] != "pre-existing" and ln not in lines[f["file"]]:
        return f"finding {f['id']}: {f['file']}:{ln} không nằm trong hunk thêm ở head"
    rc, text = git(top, "show", f"{ref}:{f['file']}")
    rows = text.split("\n") if rc == 0 else []
    if ln > len(rows) or f["snippet"].strip() not in rows[ln - 1]:
        return f"finding {f['id']}: snippet không khớp {f['file']}:{ln} ở {where}"
    return None


def _tree(top, head):
    rc, out = git(top, "rev-parse", "--verify", "-q", head + "^{tree}")
    return out.strip() if rc == 0 else None


def _branch_tip(top, branch):
    rc, out = git(top, "rev-parse", "--verify", "-q", f"refs/remotes/origin/{branch}^{{commit}}")
    if rc == 0:
        yield out.strip()


def seal(repo, head, report_path, branch):
    """(exit, lý do lỗi|None)."""
    top = os.path.realpath(repo)
    reviewer = (os.environ.get("CLAUDE_CODE_SESSION_ID") or "").strip()
    if not SESSION.fullmatch(reviewer):
        return 2, "CLAUDE_CODE_SESSION_ID rỗng hoặc sai dạng: không biết phiên reviewer"
    if not isinstance(head, str) or not SHA40.fullmatch(head) or _tree(top, head) is None:
        return 2, "--head phải là sha40 của một commit có trong repo"
    m = BRANCH.fullmatch(branch or "")
    if not m or head not in set(_branch_tip(top, branch)):
        return 2, f"--branch {branch} phải là nhánh issue-<N>-… có đỉnh đúng bằng head"
    issue = int(m.group(1))
    try:
        with open(report_path, encoding="utf-8") as fh:
            rep = json.load(fh)
    except (OSError, ValueError, RecursionError) as e:
        return 2, f"không đọc được báo cáo: {e.__class__.__name__}"
    if not isinstance(rep, dict) or rep.get("head") != head or not isinstance(rep.get("findings"), list):
        return 2, "báo cáo phải có head == --head và mảng findings"
    trunk = _load("push_gate")._trunk_ref(top)
    rc, mb = git(top, "merge-base", trunk, head) if trunk else (1, "")
    if rc != 0 or rep.get("base") != mb.strip():
        return 2, "base của báo cáo không phải merge-base(trunk, head)"
    lines = added_lines(top, mb.strip(), head)
    if lines is None:
        return 3, "git diff base..head lỗi"
    for f in rep["findings"]:
        why = _finding_problem(top, head, mb.strip(), f, lines)
        if why:
            return 2, why
    why = session_problem(top, head, issue, reviewer)
    if why:
        return 2, why
    if _load("verdict_seal").seal_mode(_fixture(top)):
        return 3, "seal mode bật: cần chủ repo cài signer claude-verify (agent không tự ký được biên bản)"
    builders = sorted(ledger_sessions(top, "build", issue) | lock_builders(top, head))
    now = datetime.datetime.now(datetime.timezone.utc)
    task_id = f"CV{now:%Y%m%dT%H%M%S}-{head[:12]}-{secrets.token_hex(3)}"
    verdict = "fail" if any(f["severity"] == "important" for f in rep["findings"]) else "pass"
    payload = {"v": 1, "kind": "claude-verify", "task_id": task_id, "head": head, "tree": _tree(top, head), "base": mb.strip(),
               "verdict": verdict, "findings": rep["findings"], "reviewer_session": reviewer, "builder_session": ",".join(builders),
               "issue": issue, "branch": branch, "ts": now.isoformat()}
    st = os.path.join(root(top), "records")
    os.makedirs(st, mode=0o700, exist_ok=True)
    path = os.path.join(st, task_id + ".json")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)   # không bao giờ đè biên bản đã có
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump({"payload": json.dumps(payload, sort_keys=True, ensure_ascii=False), "sig": None}, fh)
    print(f"task_id={task_id} verdict={verdict} → {path}")
    return (0 if verdict == "pass" else 4), None


def is_task_id(value):
    """True khi `value` đúng khuôn mã biên bản claude-verify (CV...)."""
    return isinstance(value, str) and bool(TASK_ID.fullmatch(value))


def home_overridden():
    """True khi đang đọc CLAUDE_VERIFY_HOME khác mặc định (~/.claude-verify của uid)."""
    return bool(os.environ.get("CLAUDE_VERIFY_HOME"))


def current_issue_branch(top):
    """Tên nhánh hiện tại nếu khớp khuôn issue-<N>-..., ngược lại None (detached hoặc nhánh thường)."""
    rc, out = git(top, "symbolic-ref", "-q", "--short", "HEAD")
    br = out.strip() if rc == 0 else ""
    return br if BRANCH.fullmatch(br) else None


def edited_files(top, base, head):
    """Danh sách đường dẫn đã có bị sửa/xoá/đổi kiểu (M/D/T) trong diff base..head; None khi lỗi git."""
    rc, out = git(top, "-c", "core.quotePath=false", "diff", "--name-status", "--no-renames", "-z", base, head)
    if rc != 0:
        return None
    parts = out.split("\0")
    return [parts[i + 1] for i in range(0, len(parts) - 1, 2) if parts[i][:1] in ("M", "D", "T") and parts[i + 1]]


def _norm_ts(ts):
    """Chuẩn hoá mốc thời gian ISO sang UTC dạng YYYY-MM-DDTHH:MM:SS.ffffffZ để so thứ tự ổn định."""
    if not isinstance(ts, str) or not ts.strip():
        return ""
    try:
        dt = datetime.datetime.fromisoformat(ts.strip().replace("Z", "+00:00"))
        if dt.tzinfo is None:
            return ""
        return dt.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    except ValueError:
        return ""


def _read_payload(top, task_id, require_seal=True):
    """Đọc biên bản <task_id>.json, kiểm tra chữ ký Ed25519 khi seal mode bật (nếu require_seal=True) và khuôn payload cơ bản."""
    try:
        path = os.path.join(root(top), "records", task_id + ".json")
        if os.path.getsize(path) > MAX_BYTES:
            return None, "biên bản quá lớn"
        with open(path, encoding="utf-8") as fh:
            rec = json.load(fh)
        payload_s, sig = rec["payload"], rec.get("sig")
        payload = json.loads(payload_s)
    except (OSError, ValueError, KeyError, TypeError, RecursionError) as e:
        return None, f"không đọc được biên bản {task_id}: {e.__class__.__name__}"
    if require_seal:
        vs = _load("verdict_seal")
        on, pub = vs.trusted_pubkey(_fixture(top))
        if on:
            try:
                ok = pub is not None and isinstance(sig, str) and vs.ed25519_verify(pub, payload_s.encode("utf-8"),
                                                                                      base64.b64decode(sig, validate=True))
            except (ValueError, TypeError):
                ok = False
            if not ok:
                return None, "seal mode bật: biên bản không có chữ ký hợp lệ của pubkey tin cậy"
    if not isinstance(payload, dict) or payload.get("v") != 1 or payload.get("kind") != "claude-verify" \
            or payload.get("task_id") != task_id:
        return None, "biên bản sai v/kind/task_id"
    return payload, None


def _check_payload(payload, sha, top, pr, branch):
    """Kiểm tra nội dung payload đã đọc: head/tree, verdict pass, nhánh thẻ khớp và phiên reviewer != builder."""
    if pr is not None and _tree(top, sha) is None:
        git(top, "fetch", "--quiet", "origin", f"refs/pull/{int(pr)}/head", timeout=60)
    tree = _tree(top, sha)
    if tree is None:
        return False, f"head {sha[:12]} không có trong repo"
    if payload.get("head") != sha or payload.get("tree") != tree:
        return False, f"biên bản cho head/tree khác {sha[:12]}"
    findings = payload.get("findings")
    if payload.get("verdict") != "pass" or not isinstance(findings, list) \
            or any(not isinstance(f, dict) or f.get("severity") == "important" for f in findings):
        return False, "verdict không phải pass"
    issue = payload.get("issue")
    if type(issue) is not int or issue <= 0:
        return False, "biên bản không ghi thẻ (issue)"
    if not branch:
        return False, "thiếu --branch (nhánh PR): không buộc được biên bản vào thẻ"
    m = BRANCH.fullmatch(branch)
    if not m or int(m.group(1)) != issue:
        return False, f"nhánh PR {branch} không thuộc thẻ issue #{issue} của biên bản"
    recorded = payload.get("builder_session")
    why = session_problem(top, sha, issue, payload.get("reviewer_session"),
                          recorded.split(",") if isinstance(recorded, str) else ())
    return (False, why) if why else (True, "claude-verify pass")


def check(task_id, sha, top, pr=None, branch=None):
    """(True, lý do) khi biên bản claude-verify `task_id` hợp lệ cho head `sha` trong repo `top`; (False, lý do) mọi trường hợp khác."""
    try:
        return _check(task_id, sha, top, pr, branch)
    except Unchecked as e:
        return False, str(e)


def _check(task_id, sha, top, pr, branch):
    if not is_task_id(task_id) or not isinstance(sha, str) or not SHA40.fullmatch(sha):
        return False, "task_id hoặc sha sai dạng"
    top = os.path.realpath(top)
    payload, why = _read_payload(top, task_id, require_seal=True)
    if payload is None:
        return False, why
    return _check_payload(payload, sha, top, pr, branch)


def verified_scope(task_id, top, sha=None, pr=None, branch=None, trunk=None, require_seal=True):
    """Xác minh biên bản claude-verify cho chốt duyệt test cũ bị sửa: qua đủ kiểm tra check(), cộng ràng buộc phạm vi
    base == merge-base(trunk, head) và tính danh sách file đã có bị sửa/xoá (M/D/T) trong base..head.
    Trả (payload, edited, None) khi hợp lệ, (None, None, lý do) mọi trường hợp khác (fail closed)."""
    try:
        return _verified_scope(task_id, top, sha, pr, branch, trunk, require_seal)
    except Unchecked as e:
        return None, None, str(e)


def _verified_scope(task_id, top, sha, pr, branch, trunk, require_seal):
    if not is_task_id(task_id):
        return None, None, "task_id không phải mã claude-verify"
    top = os.path.realpath(top)
    payload, why = _read_payload(top, task_id, require_seal=require_seal)
    if payload is None:
        return None, None, why
    head = sha if sha is not None else payload.get("head")
    if not isinstance(head, str) or not SHA40.fullmatch(head):
        return None, None, "head của biên bản sai dạng"
    # Ràng buộc nhánh thẻ: ưu tiên nhánh truyền vào, rồi nhánh issue-<N>- hiện đang checkout; detached (scratch merge gate) dùng branch trong payload.
    eff_branch = branch or current_issue_branch(top) or (payload.get("branch") if isinstance(payload.get("branch"), str) else None)
    ok, why = _check_payload(payload, head, top, pr, eff_branch)
    if not ok:
        return None, None, why
    base = payload.get("base")
    if not isinstance(base, str) or not SHA40.fullmatch(base):
        return None, None, "biên bản thiếu base sha40 hợp lệ"
    trunk_ref = trunk or _load("push_gate")._trunk_ref(top)
    if not trunk_ref:
        return None, None, "không xác định được nhánh đích để kiểm phạm vi base..head"
    rc, mb = git(top, "merge-base", trunk_ref, head)
    if rc != 0 or mb.strip() != base:
        return None, None, f"base của biên bản ({base[:10]}) không phải merge-base({trunk_ref}, head)"
    edited = edited_files(top, base, head)
    if edited is None:
        return None, None, "git diff base..head lỗi"
    return payload, edited, None


def scan_records(top, require_seal=True, include_fail=False, trunk=None):
    """Quét biên bản claude-verify thuộc repo `top` (chỉ quét khi repo có sổ reviewers/<repo-key>/).
    Bản pass phải qua đủ verified_scope(); bản fail (khi include_fail=True) chỉ cần khớp head/tree và reviewer có trong sổ thẻ
    để chặn replay pass cũ. Lỗi đọc / home lạ ngoài fixture → [] (fail closed)."""
    try:
        top = os.path.realpath(top)
        rc, common = git(top, "rev-parse", "--path-format=absolute", "--git-common-dir")
        if rc != 0 or not common.strip():
            return []
        key = hashlib.sha256(os.path.realpath(common.strip()).encode()).hexdigest()[:16]
        base_dir = root(top)
        rev_dir = os.path.join(base_dir, "reviewers", key)
        if not os.path.isdir(rev_dir):
            return []
        issues = set()
        for fn in os.listdir(rev_dir):
            m = re.fullmatch(r"issue-([0-9]{1,9})\.jsonl", fn)
            if m:
                issues.add(int(m.group(1)))
        if not issues:
            return []
        rec_dir = os.path.join(base_dir, "records")
        if not os.path.isdir(rec_dir):
            return []
    except (Unchecked, OSError):
        return []
    cur_branch = current_issue_branch(top)
    out = []
    try:
        names = sorted(os.listdir(rec_dir))
    except OSError:
        return []
    for fn in names:
        if not fn.endswith(".json"):
            continue
        tid = fn[:-5]
        if not is_task_id(tid):
            continue
        try:
            payload, _why = _read_payload(top, tid, require_seal=False)
        except Unchecked:
            return []
        if payload is None:
            continue
        issue = payload.get("issue")
        head = payload.get("head")
        if type(issue) is not int or issue not in issues or not isinstance(head, str) or not SHA40.fullmatch(head):
            continue
        tree = _tree(top, head)
        if tree is None or payload.get("tree") != tree:
            continue
        findings = payload.get("findings")
        is_pass = payload.get("verdict") == "pass" and isinstance(findings, list) \
            and not any(not isinstance(f, dict) or f.get("severity") == "important" for f in findings)
        if is_pass:
            vp, edited, _vwhy = verified_scope(tid, top, sha=head, branch=cur_branch, trunk=trunk, require_seal=require_seal)
            if vp is not None:
                out.append({"task_id": tid, "head": head, "base": vp["base"], "verdict": "pass",
                            "ts": _norm_ts(vp.get("ts")), "edited": edited, "issue": issue,
                            "branch": vp.get("branch"), "reviewer_session": vp.get("reviewer_session")})
        elif include_fail:
            # Biên bản fail làm luật chặt hơn: chỉ tính khi thuộc đúng thẻ nhánh hiện tại (nếu có) và reviewer nằm trong sổ reviewers thẻ đó.
            eff_br = cur_branch or (payload.get("branch") if isinstance(payload.get("branch"), str) else None)
            bm = BRANCH.fullmatch(eff_br or "")
            if not bm or int(bm.group(1)) != issue:
                continue
            try:
                if payload.get("reviewer_session") not in ledger_sessions(top, "review", issue):
                    continue
            except Unchecked:
                continue
            out.append({"task_id": tid, "head": head, "base": payload.get("base") if isinstance(payload.get("base"), str) else None,
                        "verdict": "fail", "ts": _norm_ts(payload.get("ts")), "edited": None, "issue": issue,
                        "branch": payload.get("branch"), "reviewer_session": payload.get("reviewer_session")})
    return out


def main(argv):
    import argparse  # noqa: PLC0415
    ap = argparse.ArgumentParser(prog="claude_verify.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("register")
    g.add_argument("--lane", required=True, choices=("build", "review"))
    g.add_argument("--repo", default=".")
    g.add_argument("--issue", required=True, type=int)
    g.add_argument("--session", required=True)
    g.add_argument("--engine", choices=ENGINES, default="claude")
    s = sub.add_parser("seal")
    s.add_argument("--repo", default=".")
    s.add_argument("--head", required=True)
    s.add_argument("--report", required=True)
    s.add_argument("--branch", required=True)
    c = sub.add_parser("check")
    c.add_argument("task_id")
    c.add_argument("sha")
    c.add_argument("--top", default=".")
    c.add_argument("--pr", type=int)
    c.add_argument("--branch")
    a = ap.parse_args(argv)
    if a.cmd == "check":
        ok, why = check(a.task_id, a.sha, a.top, a.pr, a.branch)
        if not ok:
            print(f"claude-verify: {a.task_id}: {why}", file=sys.stderr)
        return 0 if ok else 1
    try:
        if a.cmd == "register":
            if agent_env():
                print("claude-verify: register chỉ do runner gọi (env phiên agent: CLAUDECODE/CLAUDE_CODE_SESSION_ID)", file=sys.stderr)
                return 2
            register(os.path.realpath(a.repo), a.lane, a.issue, a.session, a.engine)
            return 0
        rc, why = seal(a.repo, a.head, a.report, a.branch)
    except Unchecked as e:
        rc, why = 3, str(e)
    except OSError as e:
        rc, why = 3, f"ghi biên bản/sổ lỗi ({e.__class__.__name__})"
    if why:
        print(f"claude-verify: {why}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
