#!/usr/bin/env python3
"""Biên bản duyệt chéo `claude-verify` (#1328): nguồn duyệt của merge queue ngoài antigravity-pm.

Phiên reviewer (KHÁC phiên builder) review diff merge-base(trunk, head)..head, ghi báo cáo JSON rồi niêm phong:
  seal --repo DIR --head SHA40 --report FILE   báo cáo {head, base, findings:[{id, severity, file, line, snippet, class}], reviewed_at}
  check TASK_ID SHA40 [--top DIR] [--pr N]     exit 0 = biên bản pass đúng head/tree, reviewer ≠ builder; 1 = mọi trường hợp khác
`seal` kiểm: head sha40 có trong repo và == báo cáo; base == merge-base(trunk, head) (push_gate._trunk_ref); mỗi finding có
severity important|nit|pre-existing, file thuộc diff base..head, line nằm trong hunk thêm ở head (pre-existing được ngoài hunk) và
snippet là chuỗi con của đúng dòng đó ở head. verdict = pass khi không có finding important. task_id = CV<yyyymmdd>T<HHMMSS>-<head12>.

Phiên: reviewer = env CLAUDE_CODE_SESSION_ID (rỗng → từ chối). Builder = session_id trong devkit-session.lock của mọi worktree đang
đứng trên MỘT NHÁNH (không detached) có HEAD == head: đó là worktree build của PR; worktree review/qa của board là detached nên
không bị nhầm thành builder. Reviewer trùng builder → từ chối (cả lúc seal lẫn lúc check).

Biên bản: <home của uid>/.claude-verify/records/<task_id>.json = {"payload": "<JSON chuẩn>", "sig": base64|null}. Seal mode
(verdict_seal.seal_mode: chủ repo cài pubkey root-owned) BẬT → chỉ nhận biên bản có chữ ký Ed25519 hợp lệ của pubkey tin cậy; agent
không tự ký được nên `seal` báo "cần chủ repo cài signer claude-verify" và fail closed. Seal mode TẮT → nhận biên bản không ký.

Rủi ro còn lại (ghi rõ, cùng mức biên bản ~/.antigravity-pm khi seal mode tắt): một agent cùng uid tự viết file biên bản dưới ~;
worktree build đã bị xoá (không còn lock) thì không biết builder, chỉ còn kiểm reviewer khác phiên đang giữ worktree đó.
Thư mục biên bản lạ (CLAUDE_VERIFY_HOME) chỉ nhận trong fixture test: DEVKIT_PM_HOME_TEST=1, thư mục dưới gốc tạm cố định VÀ repo
cũng dưới gốc tạm (như push_gate._seal_fixture); ngoài fixture mà đặt biến này → từ chối hết. Không theo $HOME (đọc pwd).
"""
import base64
import datetime
import importlib.util
import json
import os
import re
import subprocess
import sys

TASK_ID = re.compile(r"\ACV[0-9]{8}T[0-9]{6}-[0-9a-f]{12}\Z")
SHA40 = re.compile(r"\A[0-9a-f]{40}\Z")
SESSION = re.compile(r"\A[A-Za-z0-9._:-]{1,128}\Z")
SEVERITIES = ("important", "nit", "pre-existing")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
MAX_BYTES = 2_000_000
HERE = os.path.dirname(os.path.realpath(__file__))


def _load(name):
    """Module của kit cạnh file này (đường thật, không theo env)."""
    spec = importlib.util.spec_from_file_location("cv_" + name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


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


def store(top):
    """Thư mục biên bản, hoặc None khi CLAUDE_VERIFY_HOME đặt mà không phải fixture (fail closed)."""
    if os.environ.get("CLAUDE_VERIFY_HOME"):
        return os.path.join(os.environ["CLAUDE_VERIFY_HOME"], "records") if _fixture(top) else None
    try:
        import pwd  # noqa: PLC0415 - chỉ POSIX
        home = pwd.getpwuid(os.getuid()).pw_dir
    except (ImportError, KeyError):
        return None
    return os.path.join(home, ".claude-verify", "records")


def builder_sessions(top, head):
    """session_id trong lock của các worktree đứng trên một nhánh (không detached) có HEAD == head."""
    rc, out = git(top, "worktree", "list", "--porcelain")
    found = set()
    if rc != 0:
        return found
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


def seal(repo, head, report_path):
    top = os.path.realpath(repo)
    reviewer = (os.environ.get("CLAUDE_CODE_SESSION_ID") or "").strip()
    if not SESSION.fullmatch(reviewer):
        return 2, "CLAUDE_CODE_SESSION_ID rỗng hoặc sai dạng: không biết phiên reviewer"
    if not isinstance(head, str) or not SHA40.fullmatch(head) or _tree(top, head) is None:
        return 2, "--head phải là sha40 của một commit có trong repo"
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
        return 2, "git diff base..head lỗi"
    for f in rep["findings"]:
        why = _finding_problem(top, head, f, lines)
        if why:
            return 2, why
    builders = builder_sessions(top, head)
    if reviewer in builders:
        return 2, "phiên reviewer là phiên builder (giữ worktree nhánh của head): tự duyệt không tính"
    vs = _load("verdict_seal")
    if vs.seal_mode(_fixture(top)):
        return 3, "seal mode bật: cần chủ repo cài signer claude-verify (agent không tự ký được biên bản)"
    st = store(top)
    if st is None:
        return 2, "CLAUDE_VERIFY_HOME chỉ dùng trong fixture test"
    now = datetime.datetime.now(datetime.timezone.utc)
    task_id = f"CV{now:%Y%m%dT%H%M%S}-{head[:12]}"
    verdict = "fail" if any(f["severity"] == "important" for f in rep["findings"]) else "pass"
    payload = {"v": 1, "kind": "claude-verify", "task_id": task_id, "head": head, "tree": _tree(top, head), "base": mb.strip(),
               "verdict": verdict, "findings": rep["findings"], "reviewer_session": reviewer,
               "builder_session": ",".join(sorted(builders)) or None, "ts": now.isoformat()}
    os.makedirs(st, mode=0o700, exist_ok=True)
    path = os.path.join(st, task_id + ".json")
    tmp = f"{path}.tmp{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"payload": json.dumps(payload, sort_keys=True, ensure_ascii=False), "sig": None}, fh)
    os.replace(tmp, path)
    print(f"task_id={task_id} verdict={verdict} → {path}")
    return (0 if verdict == "pass" else 4), None


def check(task_id, sha, top, pr=None):
    """(True, lý do) khi biên bản claude-verify `task_id` là pass đúng head/tree `sha` trong repo `top`; (False, lý do) mọi trường hợp khác."""
    if not isinstance(task_id, str) or not TASK_ID.fullmatch(task_id) or not isinstance(sha, str) or not SHA40.fullmatch(sha):
        return False, "task_id hoặc sha sai dạng"
    top = os.path.realpath(top)
    if pr is not None and _tree(top, sha) is None:
        git(top, "fetch", "--quiet", "origin", f"refs/pull/{int(pr)}/head", timeout=60)
    tree = _tree(top, sha)
    if tree is None:
        return False, f"head {sha[:12]} không có trong repo"
    st = store(top)
    if st is None:
        return False, "CLAUDE_VERIFY_HOME chỉ dùng trong fixture test"
    try:
        path = os.path.join(st, task_id + ".json")
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
    reviewer, builder = payload.get("reviewer_session"), payload.get("builder_session")
    builders = set((builder or "").split(",")) if isinstance(builder, str) else set()
    if not isinstance(reviewer, str) or not SESSION.fullmatch(reviewer) or reviewer in builders \
            or reviewer in builder_sessions(top, sha):
        return False, "reviewer trùng builder hoặc không rõ phiên reviewer"
    return True, "claude-verify pass"


def main(argv):
    import argparse  # noqa: PLC0415
    ap = argparse.ArgumentParser(prog="claude_verify.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("seal")
    s.add_argument("--repo", default=".")
    s.add_argument("--head", required=True)
    s.add_argument("--report", required=True)
    c = sub.add_parser("check")
    c.add_argument("task_id")
    c.add_argument("sha")
    c.add_argument("--top", default=".")
    c.add_argument("--pr", type=int)
    a = ap.parse_args(argv)
    if a.cmd == "seal":
        rc, why = seal(a.repo, a.head, a.report)
        if why:
            print(f"claude-verify: {why}", file=sys.stderr)
        return rc
    ok, why = check(a.task_id, a.sha, a.top, a.pr)
    if not ok:
        print(f"claude-verify: {a.task_id}: {why}", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
