#!/usr/bin/env python3
"""Biên bản duyệt chéo `claude-verify` (#1328): nguồn duyệt của merge queue ngoài antigravity-pm.

  register --lane build|review --repo DIR --issue N --session SID   runner ghi sổ phiên TRƯỚC khi chạy worker (chỉ thêm, không xoá).
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
    path = _ledger(top, lane, issue)
    try:
        with open(path, encoding="utf-8") as fh:
            rows = [json.loads(line) for line in fh if line.strip()]
    except FileNotFoundError:
        return set()
    except (OSError, ValueError, RecursionError) as e:
        raise Unchecked(f"sổ {lane} hỏng ({e.__class__.__name__})") from None
    if not all(isinstance(r, dict) and isinstance(r.get("session"), str) and SESSION.fullmatch(r["session"]) for r in rows):
        raise Unchecked(f"sổ {lane} có dòng sai dạng")
    return {r["session"] for r in rows}


def agent_env():
    """True khi lệnh chạy trong env phiên agent mà không có cờ runner (register bị từ chối)."""
    agent = os.environ.get("CLAUDECODE") == "1" or bool(os.environ.get("CLAUDE_CODE_SESSION_ID"))
    return agent and os.environ.get("SB_RUNNER_REGISTER") != "1"


def register(top, lane, issue, session):
    if lane not in ("build", "review") or not SESSION.fullmatch(session or "") or not 0 < int(issue) < 10 ** 9:
        raise Unchecked("register: lane/issue/session sai dạng")
    path = _ledger(top, lane, issue)
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    line = json.dumps({"session": session, "ts": datetime.datetime.now(datetime.timezone.utc).isoformat()}) + "\n"
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
    builders = ledger_sessions(top, "build", issue) | lock_builders(top, head) | set(recorded_builders)
    builders.discard("")
    if not builders:
        return f"không biết phiên builder của thẻ #{issue} (sổ builders rỗng): claude-verify chỉ dùng cho thẻ board giao"
    if not isinstance(reviewer, str) or not SESSION.fullmatch(reviewer):
        return "không rõ phiên reviewer"
    if reviewer in builders:
        return "phiên reviewer là phiên builder của thẻ: tự duyệt không tính"
    if reviewer not in ledger_sessions(top, "review", issue):
        return f"phiên reviewer không có trong sổ reviewers của thẻ #{issue} (runner chưa giao review cho phiên này)"
    return None


def added_lines(top, base, head):
    """{file: set(dòng thêm ở head)} của diff base..head; None khi git lỗi."""
    rc, out = git(top, "-c", "core.quotePath=false", "diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", base, head)
    if rc != 0:
        return None
    files, cur, header = {}, None, False
    for line in out.splitlines():
        if line.startswith("diff --git "):
            cur, header = None, True   # dòng ---/+++ chỉ đọc ở phần đầu, không nhầm dòng nội dung "++ x" được thêm
        elif header and line.startswith("+++ "):
            cur = line[6:] if line.startswith("+++ b/") else None
            if cur is not None:
                files.setdefault(cur, set())
        elif header and line.startswith("--- a/"):
            files.setdefault(line[6:], set())   # file bị xoá vẫn thuộc diff, không có dòng thêm
        elif line.startswith("@@"):
            header = False
            m = HUNK.match(line)
            if m and cur is not None:
                start, n = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
                files[cur].update(range(start, start + n))
    return files


def _finding_problem(top, head, f, lines):
    if not isinstance(f, dict) or not all(isinstance(f.get(k), str) and f[k].strip() for k in ("id", "severity", "file", "snippet")):
        return "finding thiếu id/severity/file/snippet"
    if f["severity"] not in SEVERITIES:
        return f"finding {f['id']}: severity {f['severity']!r} không thuộc {SEVERITIES}"
    ln = f.get("line")
    if type(ln) is not int or ln < 1:
        return f"finding {f['id']}: thiếu số dòng (line)"
    if f["file"] not in lines:
        return f"finding {f['id']}: {f['file']} không thuộc diff base..head"
    if f["severity"] != "pre-existing" and ln not in lines[f["file"]]:
        return f"finding {f['id']}: {f['file']}:{ln} không nằm trong hunk thêm ở head"
    rc, text = git(top, "show", f"{head}:{f['file']}")
    rows = text.split("\n") if rc == 0 else []
    if ln > len(rows) or f["snippet"].strip() not in rows[ln - 1]:
        return f"finding {f['id']}: snippet không khớp {f['file']}:{ln} ở head"
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
        why = _finding_problem(top, head, f, lines)
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


def check(task_id, sha, top, pr=None, branch=None):
    """(True, lý do) khi biên bản claude-verify `task_id` hợp lệ cho head `sha` trong repo `top`; (False, lý do) mọi trường hợp khác."""
    try:
        return _check(task_id, sha, top, pr, branch)
    except Unchecked as e:
        return False, str(e)


def _check(task_id, sha, top, pr, branch):
    if not isinstance(task_id, str) or not TASK_ID.fullmatch(task_id) or not isinstance(sha, str) or not SHA40.fullmatch(sha):
        return False, "task_id hoặc sha sai dạng"
    top = os.path.realpath(top)
    if pr is not None and _tree(top, sha) is None:
        git(top, "fetch", "--quiet", "origin", f"refs/pull/{int(pr)}/head", timeout=60)
    tree = _tree(top, sha)
    if tree is None:
        return False, f"head {sha[:12]} không có trong repo"
    try:
        path = os.path.join(root(top), "records", task_id + ".json")
        if os.path.getsize(path) > MAX_BYTES:
            return False, "biên bản quá lớn"
        with open(path, encoding="utf-8") as fh:
            rec = json.load(fh)
        payload_s, sig = rec["payload"], rec.get("sig")
        payload = json.loads(payload_s)
    except (OSError, ValueError, KeyError, TypeError, RecursionError) as e:
        return False, f"không đọc được biên bản {task_id}: {e.__class__.__name__}"
    vs = _load("verdict_seal")
    on, pub = vs.trusted_pubkey(_fixture(top))
    if on:
        try:
            ok = pub is not None and isinstance(sig, str) and vs.ed25519_verify(pub, payload_s.encode("utf-8"),
                                                                                  base64.b64decode(sig, validate=True))
        except (ValueError, TypeError):
            ok = False
        if not ok:
            return False, "seal mode bật: biên bản không có chữ ký hợp lệ của pubkey tin cậy"
    if not isinstance(payload, dict) or payload.get("v") != 1 or payload.get("kind") != "claude-verify" \
            or payload.get("task_id") != task_id:
        return False, "biên bản sai v/kind/task_id"
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


def main(argv):
    import argparse  # noqa: PLC0415
    ap = argparse.ArgumentParser(prog="claude_verify.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("register")
    g.add_argument("--lane", required=True, choices=("build", "review"))
    g.add_argument("--repo", default=".")
    g.add_argument("--issue", required=True, type=int)
    g.add_argument("--session", required=True)
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
            register(os.path.realpath(a.repo), a.lane, a.issue, a.session)
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
