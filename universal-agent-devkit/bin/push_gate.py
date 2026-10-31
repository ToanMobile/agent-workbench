#!/usr/bin/env python3
"""Does the full-gate PASS cover what a `git push` sends? Called by hooks/block-dangerous-git.sh and scripts/git/integrate.py.

#472 mục A (người dùng 27/10, bớt --full): push lên trunk / release/* chỉ đi qua `agent-kit integrate` — điểm gộp chạy --full MỘT lần
trong worktree scratch rồi tự `git push` (tiến trình con của integrate, hook PreToolUse không thấy). Hook truyền `--via-hook <remote>`
cho MỌI lần gọi (chế độ chặt, strict_check()): đích trunk hay không rõ chỉ cho qua khi push không gửi gì mới (remote đã có ĐÚNG commit
đó ở đúng nhánh đích: lần push tay sau integrate không thành vòng lặp). KHÔNG biên nhận nào mở được trunk ở đây, nên không có gì để giả:
biên nhận tự chạy, worktree tự đặt tên .integrate-scratch-*, env CI / POSTFIX_GATE_FULL đều không đổi kết quả. Từ chối thì chỉ đường
integrate, không bảo chạy --full. Nhánh PR, --all-tags và tag của commit remote đã có giữ nguyên. Không có `--via-hook` (integrate tự
gọi trước khi push, CLI): luật biên nhận bên dưới, như cũ — chỉ lời chỉ đường đổi sang integrate.

Rule (rules/essentials.md, Git): every push needs the latest `post-fix-gate --run-tests --full`
at exit 0 on the content pushed, or an edited test an Antigravity audit passed: a pushed commit
whose trailer is `Test-approved-by: antigravity <task-id>` AND an antigravity-pm record of that
task of this repository with an audit pass (approved(); audit 2026-10-09: any line holding
"Test-approved-by:" used to pass). Audit 2026-09-28: nothing enforced it.

The receipt (.git/postfix-gate/full_pass.json, written by post-fix-gate on a full PASS) holds
`head` (HEAD when the gate ran) and `dirty` ({path: blob sha, or null when deleted} for every
file that differed from HEAD). The push passes when `head` is an ancestor of (or is) the pushed
commit and every file changed between them has, in the pushed commit, the blob the gate tested.
A commit that only rewords the gated one (`git commit --amend`, same tree) is covered too (2026-10-09).
The receipt must be what the gate writes, for this repository (receipt_problem(); 2026-10-09: a
hand-written {"exit": 0, "head": "<HEAD>"} passed): anything else counts as no receipt.
#644: when full_pass.json is missing, invalid or does not cover the push, scoped_pass.json next to it (the receipt of a scoped gate run,
"scope": "scoped", run-log line mode scoped) is checked by the same rules; a "task" receipt never opens a push.

Only repos with an active regression matrix are checked: without one no receipt can exist.
Files the gate itself writes after the run (tree_fp.EXCLUDE) are not compared.
ponytail: a file dirty at gate time and left uncommitted (another session's work in a shared
checkout) was in the tested tree but is not pushed — accepted; checking it blocks every push
from a shared checkout. Upgrade when pushes from shared trees are rare.

A plain tag push (the guard passes --tag-remote <name> only for one) of commits the remote already has
uploads nothing new, so it needs no receipt: an old release tag can never contain the commit the last
gate passed (GeelyEx2 / OfficeReader, 2026-10-04). Any doubt falls back to the normal rule.

`git push --tags` / `--all` / `--branches` used to skip the guard altogether (measured 2026-10-04: exit 0 with an
ungated commit). --all-tags <remote>: every tag must point at a commit the remote already advertises, so it never
uploads one. --all-branches <remote>: every local branch has nothing new to send (its tip is in the remote branch of
the same name) or is covered exactly like `git push <remote> <branch>`.

Push một nhánh PR (người dùng 18/10): `--dst <remote> <nhánh>` (hook truyền đích của từng refspec) với đích KHÔNG phải trunk
không cần biên nhận: `--full` chạy đúng một lần, ở merge gate (super-board-merge-gate.sh) ngay trước khi gộp vào main; commit đã
qua pre-commit. Trunk = main/master/trunk/develop/release/*/hotfix/* và nhánh mặc định của remote (refs/remotes/<remote>/HEAD).
Đích rỗng, thiếu, remote không phải tên đã cấu hình (URL), hay ref ngoài refs/heads/ → luật biên nhận cũ.

CLI: push_gate.py <dir> [<rev>] [--tag-remote <name>] [--dst <remote> <branch>] | --all-tags <name> | --all-branches <name>
    [--via-hook <remote>]
→ exit 0 covered · 2 not covered (reason on stdout).
100% standard library.
"""
import glob
import json
import os
import pathlib
import re
import shlex
import stat
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tree_fp  # noqa: E402

MATRIX = os.path.join(".agents", "regression_matrix.active.json")
# #472 mục A: lời chỉ đường khi từ chối push trunk — điểm gộp là integrate; KHÔNG bảo agent chạy --full (vòng lặp cũ: gate xong vẫn chặn)
INTEGRATE = ("push lên trunk / release/* chỉ qua `agent-kit integrate` (điểm gộp: chạy gate một lần trong worktree scratch rồi tự push "
             "đúng commit đó). Đang ở worktree: `agent-kit worktree finish <đường dẫn>` trước, rồi `agent-kit integrate` (không --if-due). "
             "Repo đi PR: push nhánh PR bằng tên (`git push origin <nhánh>`), merge gate lo phần còn lại")
APPROVED = "Test-approved-by:"
APPROVED_VALUE = re.compile(r"antigravity\s+(T\d{4,}-[a-z0-9-]{1,48})")   # antigravity-pm TASK_ID_RE (src/tasks.js)
HEX_SHA = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?")


def git(cwd, *args):
    # surrogateescape: a path git prints that is not valid UTF-8 (cfg_<0xE9>.py) crashed the gate with a traceback (2026-10-09);
    # it now round-trips to the same bytes in argv and stdin, as bin/post-fix-gate.py decodes them
    r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, errors="surrogateescape", timeout=5)
    return r.returncode, r.stdout


def remote_refs(top, remote):
    """{refname: sha} the remote ITSELF advertises now (git ls-remote), not refs/remotes/* — a ref this repo's agent
    can write (update-ref, fetch . HEAD:refs/remotes/…) or one gone stale (review 2026-10-04). None when <remote>
    is not a configured remote name (a URL), there is no network, git fails or times out."""
    rc, names = git(top, "remote")
    if rc != 0 or remote not in names.split():
        return None
    # ls-remote asks the fetch url; `git push` goes to the push url (remote.<n>.pushurl, pushInsteadOf): when they
    # differ the answer is about another server (review 2026-10-04).
    rc1, fetch_url = git(top, "remote", "get-url", remote)
    rc2, push_url = git(top, "remote", "get-url", "--push", remote)
    if rc1 != 0 or rc2 != 0 or fetch_url.strip() != push_url.strip():
        return None
    try:
        r = subprocess.run(["git", "-C", top, "ls-remote", "--refs", remote], capture_output=True, text=True,
                           errors="surrogateescape", timeout=10, stdin=subprocess.DEVNULL, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    refs = {}
    for ln in r.stdout.splitlines():
        sha, _, name = ln.partition("\t")
        if name:
            refs[name] = sha
    return refs


def unpushed(top, commits, remote):
    """The set of commits reachable from <commits> that the remote does not have, or None when the remote cannot be
    asked (see remote_refs). A commit c of <commits> is on the remote exactly when c is not in the returned set."""
    refs = remote_refs(top, remote)
    if not refs:
        return None
    try:
        chk = subprocess.run(["git", "-C", top, "cat-file", "--batch-check"], input="\n".join(refs.values()) + "\n",
                             capture_output=True, text=True, timeout=5)
        have = [ln.split()[0] for ln in chk.stdout.splitlines() if ln.strip() and not ln.rstrip().endswith("missing")]
        out = subprocess.run(["git", "-C", top, "rev-list", "--stdin"],
                             input="\n".join(commits) + "\n--not\n" + "\n".join(have) + "\n",
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return set(out.stdout.split()) if out.returncode == 0 else None


def toplevel(cwd):
    """(top, why). Inside a .git directory `rev-parse --show-toplevel` fails although `git push` works there
    (review 2026-10-04: cwd=.git made every check fail open as "not a git repo"): the work tree is then the parent of
    a .git dir; a bare repository or any other layout → (None, "no work tree"), never fail-open. (None, None) = not a
    git repo at all."""
    rc, top = git(cwd, "rev-parse", "--show-toplevel")
    if rc == 0 and top.strip():
        return top.strip(), None
    rc, gd = git(cwd, "rev-parse", "--absolute-git-dir")
    if rc != 0:
        return None, None
    gd = gd.strip()
    return (os.path.dirname(gd), None) if os.path.basename(gd) == ".git" else (None, "no work tree")


def on_remote_only(top, rev, remote):
    """True when every commit of rev is on the remote (as the remote itself says). Any doubt → False, and the
    normal receipt rule applies."""
    rc, sha = git(top, "rev-parse", "--verify", "-q", rev + "^{commit}")
    if rc != 0:
        return False
    missing = unpushed(top, [sha.strip()], remote)
    return missing is not None and not missing


def check_all_tags(cwd, remote):
    """(ok, reason) for `git push --tags <remote>`: no new commit may ride along."""
    top, why = toplevel(cwd)
    if why:
        return False, f"repository without a work tree here ({why}): cannot find the gate receipt"
    if top is None:
        return True, "not a git repo"
    rc, out = git(top, "for-each-ref", "--format=%(refname)", "refs/tags")
    if rc != 0:
        return False, "cannot list the tags"
    refs = out.split()
    try:     # one process for every tag (a subprocess per tag took 15 s for 2000 tags and timed out near 6000)
        chk = subprocess.run(["git", "-C", top, "cat-file", "--batch-check"],
                             input="".join(f"{r}^{{commit}}\n" for r in refs), capture_output=True, text=True,
                             errors="surrogateescape", timeout=15)
    except (OSError, subprocess.SubprocessError):
        return False, "cannot read the tags"
    lines = chk.stdout.splitlines()
    if chk.returncode != 0 or len(lines) != len(refs):
        return False, "cannot read the tags"
    pairs, odd = [], []
    for ref, ln in zip(refs, lines):
        (odd if ln.endswith(" missing") else pairs).append((ref[len("refs/tags/"):], ln.split()[0]))
    if odd:
        return False, "--tags would send tag(s) that do not point at a commit: " + ", ".join(n for n, _ in odd[:5])
    if not pairs:
        return True, "no tags"
    missing = unpushed(top, [c for _, c in pairs], remote)
    if missing is None:
        return False, f"cannot ask the remote \"{remote}\" (not a configured remote name, or no network): nothing says the tags' commits are already there"
    off = [n for n, c in pairs if c in missing]
    if off:
        return False, (f"--tags would send {len(off)} tag(s) of commits the remote does not have ({', '.join(off[:5])}): "
                       "push the branch first, through the gate, then the tags")
    return True, "every tag points at a commit the remote already has"


def check_all_branches(cwd, remote, strict=False):
    """(ok, reason) for `git push --all|--branches <remote>`: each local branch has nothing new to send or is covered.
    strict (#472 mục A, qua hook): nhánh nào có thứ mới để gửi là từ chối — không biên nhận nào thay được integrate."""
    top, why = toplevel(cwd)
    if why:
        return False, f"repository without a work tree here ({why}): cannot find the gate receipt"
    if top is None:
        return True, "not a git repo"
    rc, out = git(top, "for-each-ref", "--format=%(refname)", "refs/heads")
    if rc != 0:
        return False, "cannot list the branches"
    refs_raw = remote_refs(top, remote)
    refs = refs_raw or {}
    bad = []
    for ref in out.split():
        rc, tip = git(top, "rev-parse", "--verify", "-q", ref + "^{commit}")
        r_tip = refs.get(ref)
        if refs_raw and ref not in refs_raw:      # (an empty remote is a first push: the receipt rule decides)
            bad.append(f"{ref[len('refs/heads/'):]}: the remote has no such branch, --all would create it (1 dev, 1 branch): "
                       "push it by name or delete it locally")
            continue
        if rc == 0 and r_tip and git(top, "cat-file", "-e", r_tip + "^{commit}")[0] == 0 \
                and subprocess.run(["git", "-C", top, "merge-base", "--is-ancestor", tip.strip(), r_tip],
                                   capture_output=True, timeout=5).returncode == 0:
            continue                      # the remote branch of that name already has everything
        if strict:
            bad.append(f"{ref[len('refs/heads/'):]}: --all sẽ gửi commit remote chưa có; push từng nhánh PR bằng tên, trunk qua integrate")
            continue
        ok, reason = check(top, ref)
        if not ok:
            bad.append(f"{ref[len('refs/heads/'):]}: {reason}")
    return (not bad), "; ".join(bad[:3])


# như main_like của hooks/session_context.sh; không phân biệt hoa thường: remote là thư mục trên APFS thì refs/heads/MAIN là chính file main
TRUNK_LIKE = re.compile(r"(main|master|trunk|develop|release/.+|hotfix/.+)", re.IGNORECASE)


def pr_branch(cwd, remote, dst):
    """True khi `dst` (tên nhánh hoặc refs/heads/<tên>) trên `remote` chắc chắn là một nhánh PR, không phải trunk; mọi nghi ngờ → False.
    ponytail: nhánh mặc định của remote đọc từ refs/remotes/<remote>/HEAD cục bộ (không hỏi mạng); thiếu ref đó thì chỉ danh sách tên
    trunk ở trên bảo vệ — một repo đặt nhánh mặc định tên lạ mà chưa `git remote set-head` thì push lên nhánh đó không cần biên nhận.
    Ref đó cũng có thể cũ: server đổi nhánh mặc định mà ref HEAD cục bộ đã có thì git không tự cập nhật. Nâng cấp: `git ls-remote
    --symref <remote> HEAD` khi gặp repo như vậy; tới lúc đó branch protection phía server là lớp chắn còn lại."""
    if not isinstance(dst, str) or not isinstance(remote, str) or not remote:
        return False
    name = dst[len("refs/heads/"):] if dst.startswith("refs/heads/") else dst
    # `HEAD:heads/main` được git DWIM thành refs/heads/main (review 18/10): tên ngắn mang tiền tố của một namespace ref → nghi ngờ
    if (not name or name.lower().startswith(("refs/", "heads/", "tags/", "remotes/", "-")) or name.upper() == "HEAD"
            or TRUNK_LIKE.fullmatch(name)):
        return False
    top = toplevel(cwd)[0]
    if not top:
        return False
    rc, names = git(top, "remote")
    if rc != 0 or remote not in names.split():
        return False   # URL hay remote lạ: không biết nhánh mặc định của nó
    if git(top, "check-ref-format", "refs/heads/" + name)[0] != 0:
        return False
    # nhánh mặc định đọc theo URL fetch; push đi server khác (pushurl, pushInsteadOf) thì không biết nhánh mặc định của server đó
    rc1, fetch_url = git(top, "remote", "get-url", remote)
    rc2, push_url = git(top, "remote", "get-url", "--push", remote)
    if rc1 != 0 or rc2 != 0 or fetch_url.strip() != push_url.strip():
        return False
    # tên đầy đủ, không --short: có nhánh local tên "origin/prod" thì --short trả "remotes/origin/prod" và phép so trượt (OCR 18/10)
    rc, head = git(top, "symbolic-ref", "-q", f"refs/remotes/{remote}/HEAD")
    return not (rc == 0 and head.strip().lower() == f"refs/remotes/{remote}/{name}".lower())


def nothing_new(cwd, rev, remote, dst):
    """True khi push `rev` lên nhánh `dst` của `remote` không đổi gì: remote (chính nó trả lời, git ls-remote) đang có refs/heads/<dst>
    trỏ ĐÚNG commit của rev. on_remote_only() hỏi commit có ở MỌI ref nào đó của remote (unpushed(): rev-list --not cả danh sách
    ls-remote), nên một commit chỉ nằm trên nhánh PR chưa gate sẽ được `git push origin feat/x:main` đẩy lên main (ca của test #472). So bằng nhau, không phải "là tổ tiên": push ép một
    tổ tiên là lùi trunk. Mọi nghi ngờ (remote là URL, không mạng, đích lạ) → False."""
    if not isinstance(remote, str) or not remote or not isinstance(dst, str) or not dst:
        return False
    name = dst[len("refs/heads/"):] if dst.startswith("refs/heads/") else dst
    top = toplevel(cwd)[0]
    if not top or not name or git(top, "check-ref-format", "refs/heads/" + name)[0] != 0:
        return False
    rc, sha = git(top, "rev-parse", "--verify", "-q", rev + "^{commit}")
    if rc != 0:
        return False
    refs = remote_refs(top, remote)
    return bool(refs) and refs.get("refs/heads/" + name) == sha.strip()


def strict_check(cwd, rev, tag_remote, dst, remote):
    """(ok, reason) cho một push của agent qua hook (#472 mục A). Nhánh PR: như cũ, không cần biên nhận. Tag: chỉ khi remote đã có
    mọi commit của nó. Còn lại (trunk, release/*, đích không rõ): chỉ khi không gửi gì mới — không biên nhận nào mở được; lối ra là
    integrate."""
    if dst and not tag_remote and not rev.startswith("-") and pr_branch(cwd, *dst):
        return True, f"push nhánh PR {dst[1]}: --full chạy một lần ở merge gate trước khi gộp vào trunk"
    top, why = toplevel(cwd)
    if why:
        return False, f"repository without a work tree here ({why})"
    if top is None:
        return True, "not a git repo"
    # như _own_check: repo chưa có ma trận hồi quy thì push_gate chưa áp (test_guard_shell_norm.sh: push trong repo không ma trận)
    if not any(os.path.isfile(os.path.join(d, MATRIX)) for d in (top, os.path.abspath(cwd))):
        # #482: repo đã cài DevKit (có .agents/devkit, symlink cũng tính) mà mất ma trận là bị xoá/đổi tên: fail closed
        if os.path.lexists(os.path.join(top, ".agents", "devkit")):
            return False, f"repo đã cài DevKit nhưng thiếu {MATRIX} (regression matrix): push trunk bị từ chối; khôi phục file rồi chạy agent-kit integrate"
        return True, "no regression matrix"
    if tag_remote:
        if on_remote_only(top, rev, tag_remote):
            return True, "a tag of commits the remote already has: nothing new is pushed"
        return False, f"tag {rev} mang commit remote chưa có: đưa commit lên trunk trước, rồi push tag"
    if dst and nothing_new(top, rev, dst[0], dst[1]):
        return True, f"remote đã có đúng commit này ở {dst[1]}: không gửi gì mới"
    if dst and dst[1]:
        return False, f"push trực tiếp {rev} lên {dst[1]} không qua agent-kit integrate"
    # ponytail: repo đặt push.default=upstream/matching, remote.<n>.push, remote.<n>.mirror hay push.followTags thì hook không bao giờ
    # suy ra đích, nên mọi push nhánh PR ở đó bị từ chối ở đây (trước #472 thì biên nhận --full mở được). Nâng cấp: hỏi `git push
    # --dry-run --porcelain` đích thật khi gặp repo như vậy.
    return False, (f"hook không suy ra được nhánh đích của push {rev} (dấu nháy, `-c`, --follow-tags, biến, hoặc config push.default/"
                   "remote.<n>.push/push.followTags/remote.<n>.mirror): nhánh PR thì push lại dạng trơn `git push origin <nhánh>` "
                   "không kèm những thứ đó (bỏ config đó nếu repo đặt); trunk thì không push tay")


def entries(top, rev, paths):
    """{path: (mode, object sha)} of paths in rev (absent → not in the map), one git call."""
    if not paths:
        return {}
    rc, out = git(top, "ls-tree", "-r", "-z", rev, "--", *paths)
    if rc != 0:
        raise RuntimeError(f"git ls-tree {rev} failed")
    res = {}
    for rec in out.split("\0"):
        if "\t" in rec:
            meta, path = rec.split("\t", 1)
            res[path] = (meta.split()[0], meta.split()[2])
    return res


def blobs(top, rev, paths):
    """{path: blob sha} of paths in rev (absent → not in the map), one git call."""
    return {p: e[1] for p, e in entries(top, rev, paths).items()}


def untestable_only(top, project, paths, rules_dir=None, rev=None):
    """True when every path (repo-relative) is a file post-fix-gate's needs_no_test() says needs no
    test (docs, agent state, the agents' harness config) AND no rule of the project's active matrix
    watches it. The gate's own classifier and matcher are used — never a second rule (INSTINCT-015).
    2026-09-29 (Goods): a commit of .claude/settings.json alone could not be pushed without a full
    gate, which REJECTed unrelated WIP in the working tree. Any doubt → False (a receipt is needed).
    rules_dir: where the matrix and the checklist (`covers` links) are read from, default `project`; issue #5: the receipt
    of a linked worktree is judged by main's matrix and checklist, never by the worktree's own.
    No suite is not no check (25/10): a pushed .claude/settings*.json must also pass the gate's settings_problems() on its
    blob at `rev` (the working tree when rev is None), or the push needs a receipt — and the gate REJECTs it."""
    import importlib.util  # noqa: PLC0415
    rules_dir = rules_dir or project
    prefix = os.path.relpath(project, top).replace(os.sep, "/")
    prefix = "" if prefix == "." else prefix + "/"
    rel = [p[len(prefix):] if p.startswith(prefix) else None for p in paths
           if not any(p == prefix + e or p.startswith(prefix + e + "/") for e in tree_fp.EXCLUDE)]
    if not rel or None in rel:
        return False
    try:
        spec = importlib.util.spec_from_file_location(
            "post_fix_gate", os.path.join(os.path.dirname(os.path.abspath(__file__)), "post-fix-gate.py"))
        pfg = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pfg)
        with open(os.path.join(rules_dir, MATRIX), encoding="utf-8") as f:
            rules = json.load(f).get("rules") or []
        # the gate's own "watched" rule: watch_files + files linked to a rule's tests (INSTINCT-015)
        pfg.get_project_dir = lambda: pathlib.Path(rules_dir)
        covers = pfg.checklist_covers()
        pats = [w for r in rules if isinstance(r, dict) for w in pfg.rule_watch(r, covers)]
        if not all(pfg.needs_no_test(p) and not any(pfg.match_pattern(p, w) for w in pats) for p in rel):
            return False
        for p in (p for p in rel if p in pfg.SETTINGS_FILES):
            if rev:
                rc, text = git(top, "cat-file", "blob", f"{rev}:{prefix}{p}")
                text = text if rc == 0 else None   # not in rev: deleted by the push
            else:
                full = os.path.join(project, p)
                text = pathlib.Path(full).read_text(encoding="utf-8", errors="replace") if os.path.isfile(full) else None
            problems = pfg.settings_problems(p, text, pathlib.Path(project))
            if problems:
                print(f"push_gate: {p}: {pfg._L(problems[0])} — cần biên nhận gate", file=sys.stderr)
                return False
        return True
    except Exception as e:  # noqa: BLE001 — cannot classify: fall back to requiring a receipt
        print(f"push_gate: không phân loại được file sắp push ({e}) — cần biên nhận gate", file=sys.stderr)
        return False


def recovery_hint(top, rev, head):
    """Second line of the "gated commit is not in the history of <rev>" refusal (OfficeReader 2026-10-08: a clone on a detached
    HEAD passed the gate, then `git push origin main` said only that, and nobody could tell the LOCAL main was stale): where the
    repository is, where HEAD is, and - when the branch <rev> is an ancestor of HEAD and the gated commit is in HEAD's history -
    the one command that fast-forwards it. Never raises: a hint must not turn a refusal into a crash."""
    gate_advice = INTEGRATE
    try:
        def is_ancestor(a, b):
            return subprocess.run(["git", "-C", top, "merge-base", "--is-ancestor", a, b],
                                  capture_output=True, timeout=5).returncode == 0
        rc, cur = git(top, "symbolic-ref", "-q", "--short", "HEAD")
        branch = cur.strip() if rc == 0 else ""
        rc, tip = git(top, "rev-parse", "HEAD")
        tip = tip.strip() if rc == 0 else ""
        where = f"repo {top}, " + (f"HEAD ở nhánh {branch}" if branch else "HEAD đang detached") + (f" tại {tip[:10]}" if tip else "")
        rc, _ = git(top, "rev-parse", "--verify", "-q", f"refs/heads/{rev}")
        if rev != "HEAD" and rc == 0 and tip and is_ancestor(rev, tip) and is_ancestor(head, tip):
            fix = f"cd {shlex.quote(top)} && git switch {shlex.quote(rev)} && git merge --ff-only {tip}"
            covered, _why = check(top, tip)   # would the push of HEAD itself pass? (a commit added after the gate would not)
            # #472 mục A: trunk chỉ đi qua integrate (nó tự gate lại), nên không còn lời hứa "không cần chạy lại gate"
            then = f"rồi: {gate_advice}" + ("" if covered else " (HEAD có code mới hơn lần gate)")
            return (f"{where}. Nhánh local {rev} cũ hơn commit đã qua gate (clone detached hoặc đang ở nhánh khác): "
                    f"chạy `{fix}` {then}")
        return f"{where}. Nếu đã pull/rebase/squash sau lần gate: {gate_advice}"
    except (OSError, subprocess.SubprocessError, ValueError, RuntimeError):   # (check() below may raise RuntimeError: a hint never turns a refusal into a crash)
        return f"repo {top}. {gate_advice}"


def _inside(path, root):
    """True when `path` is `root` or lies under it, compared by inode (APFS case, symlinks, /private/tmp spellings)."""
    if not isinstance(path, str) or not path or not root:
        return False
    try:
        want = os.stat(root)
    except OSError:
        return False
    p = os.path.abspath(path)
    while True:
        try:
            if os.path.samestat(os.stat(p), want):
                return True
        except OSError:
            pass
        parent = os.path.dirname(p)
        if parent == p:
            return False
        p = parent


def audit_record(top, task_id):
    """(True, None) when antigravity-pm recorded an audit pass for task `task_id` of this repository; (False, why) otherwise.
    antigravity-pm keeps its task state OUTSIDE the repository (an agent cannot edit it from the work tree):
    ${ANTIGRAVITY_PM_STATE_HOME:-~/.antigravity-pm}/projects/<name>-<hash>/tasks/<id>/task.json, verdicts.audit.verdict
    (mcp-servers/antigravity-pm-mcp src/config.js, src/tasks.js recordVerdict). The task's `project` must be this repository
    (or a directory in it): task ids restart at T0001 in every project. In a linked worktree (a session's or the merge gate's
    scratch) `top` is that worktree while the task names the main checkout: the main checkout of the SAME repository (the
    parent of `git rev-parse --git-common-dir` when that is a `.git` dir) counts too (#605 lane E); git error → top only."""
    verdicts = []
    for audit in _task_audits(top, task_id):
        verdict = audit.get("verdict") if isinstance(audit, dict) else None
        if verdict == "pass":
            return True, None
        verdicts.append(str(verdict or "chưa có"))
    if verdicts:
        return False, f"antigravity-pm: audit của {task_id} chưa pass ({', '.join(verdicts)})"
    return False, f"không có biên bản audit pass của antigravity-pm cho {task_id} trong repo này ({_task_pattern(task_id)})"


# #629: khoảng trắng viết tường minh [ \t\n\r\f\v], đúng tập regex của pm_verdict (mcp-servers/antigravity-pm-mcp/src/tools.js) —
# `\s` của Python khớp cả \x1c-\x1f, \x85, của JS khớp cả NBSP: lệch là notes `auditedHead:\x1f<sha>` lọt qua kiểm audit-agent.json
# của pm_verdict nhưng gate vẫn nhận sha (tests/gates/test_audited_head_ascii_space.sh).
AUDITED_HEAD = re.compile(r"(?<![0-9A-Za-z])auditedHead:[ \t\n\r\f\v]*([0-9a-f]{40})(?![0-9A-Za-z])")
SHA40 = re.compile(r"[0-9a-f]{40}")


def audited_head(top, task_id):
    """sha40 của cây Antigravity đã audit cho task `task_id` của repo này, hoặc None (audit T0066, #605).
    Cùng biên bản ngoài repo và cùng luật repo/checkout chính như audit_record; chỉ tính khi verdicts.audit.verdict == "pass"
    VÀ có sha40 ở verdicts.audit.auditedHead (pm_verdict ghi) hoặc `auditedHead: <sha40>` trong notes VÀ sha đó là commit có trong repo `top`.
    Một task_id cũ đã pass vì thế chỉ duyệt đúng nội dung nó đã audit, không duyệt nội dung sửa sau (chặn replay).
    Thiếu auditedHead, sha lạ, lỗi git → None (fail closed)."""
    # Audit T0066 vòng 3 (#605): cùng điều kiện với approved() — pm home lạ (ANTIGRAVITY_PM_STATE_HOME tự dựng, HOME=/tmp/x) mà không
    # phải fixture test trong thư mục tạm thì biên bản không tính, ở mọi người gọi (post-fix-gate mục duyệt chéo, merge gate).
    if pm_home_overridden() and not pm_home_test_fixture():
        return None
    for audit in _task_audits(top, task_id):
        if not isinstance(audit, dict) or audit.get("verdict") != "pass":
            continue
        # Audit T0066 vòng 2: trường cấu trúc verdicts.audit.auditedHead (pm_verdict ghi) trước, rồi `auditedHead: <sha>` trong notes.
        cands = [audit.get("auditedHead")] if isinstance(audit.get("auditedHead"), str) and SHA40.fullmatch(audit["auditedHead"]) else []
        m = AUDITED_HEAD.search(audit["notes"]) if isinstance(audit.get("notes"), str) else None
        cands += [m.group(1)] if m else []
        for sha in cands:
            try:
                rc, out = git(top, "rev-parse", "--verify", "-q", sha + "^{commit}")
            except (OSError, subprocess.SubprocessError):
                continue
            if rc == 0 and out.strip() == sha:
                return sha
    return None


def head_after(top, base, head):
    """True khi `base` là tổ tiên của (hoặc chính là) `head` — auditedHead nằm SAU base, không phải một cây cũ hơn base mà task cũ đã
    audit (audit T0066 vòng 2, #605: chặn chép lùi test về bản yếu trước base rồi khai task cũ). Lỗi git, thiếu đối số → False."""
    if not base or not head:
        return False
    try:
        return subprocess.run(["git", "-C", top, "merge-base", "--is-ancestor", base, head],
                              capture_output=True, timeout=15).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def range_lower_bounds(top, rng):
    """Các mốc dưới (^sha) của range theo `git rev-parse <rng>` (`A..B` → A, `X^!` → cha của X); None khi lỗi git."""
    try:
        rc, out = git(top, "rev-parse", rng)
    except (OSError, subprocess.SubprocessError):
        return None
    if rc != 0:
        return None
    return [ln[1:] for ln in out.split() if ln.startswith("^")]


def pm_state_home():
    """Thư mục trạng thái antigravity-pm mà push_gate đọc: ${ANTIGRAVITY_PM_STATE_HOME:-~/.antigravity-pm}."""
    return os.path.expanduser(os.environ.get("ANTIGRAVITY_PM_STATE_HOME") or os.path.join("~", ".antigravity-pm"))


def pm_home_overridden():
    """True khi thư mục pm đang đọc KHÔNG phải ~/.antigravity-pm của user hệ điều hành (pwd, không theo $HOME: HOME=/tmp/x cũng là đổi
    chỗ). Biên bản ở chỗ lạ thì agent nào cũng tự dựng được (audit T0066 vòng 2): post-fix-gate coi lời duyệt dựa vào nó là nới lỏng.
    Không đọc được user → True (fail closed)."""
    try:
        import pwd  # noqa: PLC0415 - chỉ có trên POSIX
        default = os.path.join(pwd.getpwuid(os.getuid()).pw_dir, ".antigravity-pm")
        return os.path.realpath(pm_state_home()) != os.path.realpath(default)
    except (ImportError, KeyError, OSError):
        return True


TEST_TMP_ROOTS = ("/tmp", "/private/tmp", "/var/folders", "/private/var/folders")


def pm_home_test_fixture():
    """True chỉ cho fixture của test: DEVKIT_PM_HOME_TEST=1 VÀ pm home nằm dưới thư mục tạm của hệ thống (tempfile.gettempdir(), /tmp,
    /var/folders). Khi đó approved() tính biên bản pm giả; post-fix-gate vẫn coi lượt đó là nới lỏng (không cấp biên nhận).
    ponytail: agent tự đặt được cả hai trên dòng lệnh — lane git guard chặn gán chúng; nâng lên biên bản do PM server ký nếu thấy lách."""
    if os.environ.get("DEVKIT_PM_HOME_TEST") != "1":
        return False
    try:
        import tempfile  # noqa: PLC0415
        home = os.path.realpath(pm_state_home())
        roots = {os.path.realpath(r) for r in (tempfile.gettempdir(), *TEST_TMP_ROOTS)}
    except OSError:
        return False
    return any(home.startswith(r.rstrip(os.sep) + os.sep) for r in roots if r and r != os.sep)


def _task_pattern(task_id):
    return os.path.join(glob.escape(pm_state_home()), "projects", "*", "tasks", task_id, "task.json")


def _task_audits(top, task_id):
    """verdicts.audit (có thể None) của từng task.json `task_id` mà `project` thuộc repo này (top, hoặc checkout chính khi top là
    linked worktree của cùng repo). Dùng chung cho audit_record và audited_head."""
    roots = [top]
    try:
        rc, common = git(top, "rev-parse", "--path-format=absolute", "--git-common-dir")
    except (OSError, subprocess.SubprocessError):
        rc, common = 1, ""
    common = common.strip() if rc == 0 else ""
    if common and os.path.basename(common) == ".git":
        main_root = os.path.dirname(common)
        if not _inside(main_root, top):
            roots.append(main_root)
    for path in sorted(glob.glob(_task_pattern(task_id))):
        try:
            if not stat.S_ISREG(os.stat(path).st_mode) or os.path.getsize(path) > 8_000_000:
                continue
            with open(path, encoding="utf-8") as f:
                task = json.load(f)
        except (OSError, ValueError, RecursionError):
            continue
        if not isinstance(task, dict) or task.get("id") != task_id or not any(_inside(task.get("project"), r) for r in roots):
            continue
        yield (task.get("verdicts") or {}).get("audit") if isinstance(task.get("verdicts"), dict) else None


def approved(top, rng):
    """(True, note) when a commit of rng ends with the trailer `Test-approved-by: antigravity <task-id>` (git's own trailer
    parsing: the last paragraph, line-anchored) and antigravity-pm recorded an audit pass for that task (audit_record) whose
    auditedHead (audited_head) has the same tree as that commit and as the tip of rng (audit T0066, #605: no replay);
    (False, why) when a Test-approved-by line is there but does not count; (False, None) when there is none.
    Audit 2026-10-09: the old check was `"Test-approved-by:" in git log`, so "fix; Test-approved-by: whatever" passed.
    ponytail: the task record lives in a directory of the same user — an agent that writes ~/.antigravity-pm by hand still
    passes; upgrade to a record signed by the PM server if that is ever seen."""
    rc, out = git(top, "log", "--format=%H%x01%(trailers:key=Test-approved-by,valueonly,unfold)%x00", rng)
    if rc != 0:
        return False, None
    values = []                                        # (commit, value), newest commit first
    for rec in out.split("\0"):
        sha, _, trailers = rec.strip("\n").partition("\x01")
        values.extend((sha.strip(), v.strip()) for v in trailers.splitlines() if v.strip())
    tip = None
    whys = []
    for sha, value in values:
        m = APPROVED_VALUE.fullmatch(value)
        if not m:
            whys.append(f"`{APPROVED} {value[:60]}` sai dạng (cần `{APPROVED} antigravity T0001-ten-task`)")
            continue
        # #605 (audit T0066 vòng 2): biên bản ở pm home lạ agent nào cũng tự dựng được — không tính ở mọi đường push (fallback @{u}..rev,
        # receipt-head..rev, post-fix-gate trailer / --since), trừ fixture test bật công tắc trong thư mục tạm (pm_home_test_fixture).
        if pm_home_overridden() and not pm_home_test_fixture():
            whys.append("ANTIGRAVITY_PM_STATE_HOME lạ: biên bản audit không tính")
            continue
        ok, why = audit_record(top, m.group(1))
        if not ok:
            whys.append(why)
            continue
        # Audit T0066 (#605): biên bản pass của một task_id cũ không duyệt nội dung mới (replay). Trailer chỉ tính khi cây của
        # commit mang trailer VÀ cây đầu range đều bằng cây auditedHead PM đã ghi (luồng chuẩn: commit rỗng mang trailer ngay trên
        # cây đã audit); đổi gì sau đó cần audit lại. Không đọc được → không duyệt.
        # ponytail: merge main vào nhánh sau audit đổi cây đầu range → push cần audit lại; merge gate (scratch) không bị ảnh hưởng
        # vì nó duyệt theo blob từng file ở auditedHead (post-fix-gate _trailer_cross_review). Nới khi việc audit lại thành phiền.
        head = audited_head(top, m.group(1))
        if tip is None:
            rc_tip, tip_out = git(top, "rev-list", "-1", rng)
            tip = tip_out.strip() if rc_tip == 0 else ""
        trees = git(top, "rev-parse", f"{sha}^{{tree}}", f"{head}^{{tree}}", f"{tip}^{{tree}}") if head and tip and sha else (1, "")
        got = trees[1].split() if trees[0] == 0 else []
        # Audit T0066 vòng 2: auditedHead phải nằm sau mọi mốc dưới của range — cây cũ trước base (task cũ) không duyệt việc chép lùi.
        lows = range_lower_bounds(top, rng) if head else None
        after = bool(lows) and all(head_after(top, low, head) for low in lows)
        if len(got) == 3 and len(set(got)) == 1 and after:
            return True, f"{APPROVED} antigravity {m.group(1)} (antigravity-pm audit pass)"
        whys.append(f"{APPROVED} antigravity {m.group(1)}: " + (
            "biên bản audit không ghi `auditedHead: <sha>` (hoặc sha không có trong repo)" if not head else
            f"auditedHead {head[:10]} không nằm sau mốc dưới của range (audit một cây cũ trước base): cần audit lại" if not after else
            f"cây đã đổi so với auditedHead {head[:10]} (commit trailer {sha[:10]} / đầu range): cần audit lại"))
    if not whys:
        rc, body = git(top, "log", "--format=%B", rng)
        if rc == 0 and APPROVED in body:
            whys.append(f"`{APPROVED}` chỉ tính khi là trailer cuối commit (`{APPROVED} antigravity <task-id>`)")
    return False, "; ".join(dict.fromkeys(whys[:3])) or None


def tested_fingerprint(top, project, head, dirty, rev, links=None):
    """The tree fingerprint (bin/tree_fp.py) of what the gate tested - commit `head` with the receipt's `dirty` applied,
    tree_fp.EXCLUDE left out - rebuilt from git objects in a throw-away index and object store (the real ones never change).
    links (#156, the receipt's `links`): the dirty paths the gate saw as a symlink, each with the blob of its link text - rebuilt
    exactly as `git add` staged them (120000), whatever sits at that path on this disk.
    None when it cannot be rebuilt exactly - a submodule, or a symlink not in `links` among the dirty paths (the gate's `hash-object
    --stdin-paths` hashes a symlink's TARGET, `git add` its text: a receipt older than `links`), or a file whose mode the gate saw
    cannot be told (the receipt has no modes: the pushed commit's mode when it holds that blob, the file's on disk, else HEAD's, else
    100644; two of them disagreeing is a chmod or core.fileMode doubt) - and the caller then skips the comparison."""
    import hashlib  # noqa: PLC0415
    import tempfile  # noqa: PLC0415
    links = links or {}
    paths = list(dirty)
    at_head, at_rev = entries(top, head, paths), entries(top, rev, paths)
    if any(m in ("160000", "120000") for m, _ in list(at_head.values()) + list(at_rev.values())):
        return None
    lines = []
    for p, sha in dirty.items():
        if p in links:   # #156: gate thấy link ở đây; main sau `worktree finish` có file thường đã track, đoán theo đĩa này là sai
            lines.append(f"120000 {links[p]}\t{p}")
            continue
        if sha is None:
            lines.append(f"0 {'0' * len(head)}\t{p}")
            continue
        modes = {at_rev[p][0]} if p in at_rev and at_rev[p][1] == sha else set()
        try:
            st = os.lstat(os.path.join(top, p))
            if stat.S_ISLNK(st.st_mode):
                return None
            if stat.S_ISREG(st.st_mode):
                modes.add("100755" if st.st_mode & 0o100 else "100644")   # git's rule: the owner's x bit
        except OSError:
            pass
        if len(modes) > 1:
            return None
        lines.append(f"{modes.pop() if modes else (at_head[p][0] if p in at_head else '100644')} {sha}\t{p}")
    rc, objects = git(top, "rev-parse", "--path-format=absolute", "--git-path", "objects")
    if rc != 0:
        raise RuntimeError("git rev-parse --git-path objects failed")
    prefix = os.path.relpath(os.path.realpath(project), os.path.realpath(top)).replace(os.sep, "/")
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "objects", "info"))
        os.makedirs(os.path.join(tmp, "objects", "pack"))
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, "index"), GIT_OBJECT_DIRECTORY=os.path.join(tmp, "objects"),
                   GIT_ALTERNATE_OBJECT_DIRECTORIES=objects.strip())

        def run(cwd, *args, stdin=None):
            r = subprocess.run(["git", "-C", cwd, *args], input=stdin, capture_output=True, text=True, errors="surrogateescape",
                               timeout=60, env=env)
            if r.returncode != 0:
                raise RuntimeError(f"git {args[0]} failed: {r.stderr.strip()[:200]}")
            return r.stdout.strip()
        run(top, "read-tree", head)
        if lines:
            run(top, "update-index", "-z", "--index-info", stdin="\0".join(lines) + "\0")
        run(project, "rm", "-r", "-f", "--cached", "-q", "--ignore-unmatch", "--", *tree_fp.EXCLUDE)   # -f: a throw-away index
        tree = run(top, "write-tree", "--missing-ok")
        if prefix != ".":
            tree = run(top, "rev-parse", f"{tree}:{prefix}")
    return hashlib.sha256(tree.encode()).hexdigest()[:24]


def run_log_has(rp, receipt, mode="full"):
    """True when <git common dir>/postfix-gate/runs.jsonl (bin/post-fix-gate.py _log_gate_run, written right after the receipt) holds
    the line of this full PASS: mode full, exit 0, verdict PASS or REUSED, same project name, logged 0-900 s after the receipt.
    mode="scoped" (#644): dòng của lượt scoped cho biên nhận scoped_pass.json — dòng mode full không mở biên nhận scoped và ngược lại."""
    gdir = os.path.dirname(os.path.dirname(rp))
    parent = os.path.dirname(gdir)
    base = os.path.dirname(parent) if os.path.basename(parent) == "worktrees" else gdir   # as post-fix-gate _run_log_dir
    try:
        fd = os.open(os.path.join(base, "postfix-gate", "runs.jsonl"), os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    except OSError:
        return False
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return False
        n = min(st.st_size, 4 << 20)
        raw = os.pread(fd, n, st.st_size - n)
    except OSError:
        return False
    finally:
        os.close(fd)
    # carried_from: biên nhận mà `worktree finish` chép từ worktree sang main (issue #5): dòng log mang tên project gốc của worktree
    t, name = float(receipt["time"]), os.path.basename(str(receipt.get("carried_from") or receipt["project"]))[:64]
    for line in reversed(raw.splitlines()):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        epoch = rec.get("epoch") if isinstance(rec, dict) else None
        if not isinstance(epoch, int) or isinstance(epoch, bool):
            continue
        if epoch < t - 60:
            return False   # older than the receipt: lines are appended in time order
        if (epoch <= t + 900 and rec.get("mode") == mode and rec.get("exit") == 0 and not isinstance(rec.get("exit"), bool)
                and rec.get("verdict") in ("PASS", "REUSED") and rec.get("project") == name):
            return True
    return False


def receipt_problem(top, rp, receipt, rev="HEAD", scope="full"):
    """None when the full-pass receipt is what bin/post-fix-gate.py write_full_pass_receipt() writes on a full PASS of THIS
    repository - every field present with its type, `head` a commit here, `project` this repository, no failed suite, the
    fingerprint equal to that of head+dirty rebuilt from git, and the run-log line of that run present; else what is wrong.
    Audit 2026-10-09: a hand-written {"exit": 0, "head": "<HEAD>"} let any push through.
    ponytail: the receipt and runs.jsonl are files this user can write: a forger who rebuilds the fingerprint the way
    tree_fp.py does and appends a run-log line still passes - or, since issue #5, sets `carried_from` to any worktree's name and
    `time` next to a real full PASS line of that worktree, no line appended; upgrade to a receipt signed with a key the agent cannot read
    (the user's keychain / ssh-agent) if a forged receipt is ever seen.
    scope="scoped" (#644): biên nhận scoped_pass.json của lượt gate scoped — cùng mọi kiểm tra trên, cộng `scope` đúng "scoped" (thiếu hay
    "task" đều bị từ chối), các trường scoped_tests / reasons / base / tree đúng dạng, và dòng runs.jsonl mode scoped."""
    def number(v):
        return isinstance(v, (int, float)) and not isinstance(v, bool) and v == v and abs(v) != float("inf")
    # T0061 Pha 1: biên nhận task (lượt --run-tests không --full) chỉ cho XONG của task, không bao giờ cho push (tests/gates/test_task_receipt_doors.sh ca 2)
    if scope == "scoped":
        if receipt.get("scope") != "scoped":
            return "scoped_pass.json không mang scope scoped (scope %s)" % str(receipt.get("scope"))[:20]
    elif receipt.get("scope", "full") != "full":
        return "biên nhận task (scope task, không phải biên nhận của điểm gộp)"
    if receipt.get("exit") != 0 or isinstance(receipt.get("exit"), bool):
        return "exit không phải 0"
    head = receipt.get("head")
    if not isinstance(head, str) or not HEX_SHA.fullmatch(head) or git(top, "cat-file", "-e", head + "^{commit}")[0] != 0:
        return "head không phải một commit của repo này"
    missing = [k for k in ("time", "tested_at", "fingerprint", "project", "dirty", "tests", "result_format", "gate_sha",
                           "matrix_sha", "local_sha") if k not in receipt]
    if scope == "scoped":
        missing += [k for k in ("scoped_tests", "reasons", "base", "tree") if k not in receipt]
    if missing:
        return "thiếu " + ", ".join(missing)
    if scope == "scoped" and not (all(isinstance(receipt[k], list) and all(isinstance(x, str) for x in receipt[k]) for k in ("scoped_tests", "reasons"))
                                  and all(isinstance(receipt[k], str) and HEX_SHA.fullmatch(receipt[k]) for k in ("base", "tree"))):
        return "scoped_tests / reasons / base / tree không đúng dạng"
    if not number(receipt["time"]) or not number(receipt["tested_at"]) or receipt["time"] > time.time() + 300:
        return "time / tested_at không phải mốc thời gian hợp lệ"
    project = receipt["project"]
    if not isinstance(project, str) or not os.path.isdir(project) or not _inside(project, top):
        return f"project {str(project)[:80]} không thuộc repo {top}"
    dirty = receipt["dirty"]
    if not isinstance(dirty, dict) or not all(isinstance(p, str) and p and (v is None or (isinstance(v, str) and HEX_SHA.fullmatch(v)))
                                              for p, v in dirty.items()):
        return "dirty không đúng dạng {đường dẫn: blob sha | null}"
    links = receipt.get("links", {})   # #156; biên nhận ghi trước đó không có: dựng lại như cũ
    # dirty null (link tới thư mục / link treo) thì không: phép so nội dung đọc null == null là "giống", mục link sẽ làm khớp dấu vân tay
    if not isinstance(links, dict) or not all(dirty.get(p) is not None and isinstance(v, str) and HEX_SHA.fullmatch(v)
                                              for p, v in links.items()):
        return "links không đúng dạng {đường dẫn có blob trong dirty: blob sha}"
    tests = receipt["tests"]
    if not isinstance(tests, list) or not all(isinstance(t, dict) and isinstance(t.get("id"), str) and isinstance(t.get("status"), str)
                                              for t in tests):
        return "tests không đúng dạng"
    failed = [t["id"] for t in tests if t["status"] in ("FAIL", "TIMEOUT")]
    if failed:
        return "suite không PASS: " + ", ".join(failed[:5])
    fp = receipt["fingerprint"]
    if not isinstance(fp, str) or not re.fullmatch(r"[0-9a-f]{24}", fp):
        return "fingerprint (dấu vân tay code) thiếu hoặc sai dạng"
    want = tested_fingerprint(top, project, head, dirty, rev, links)
    if want is not None and want != fp:
        return "fingerprint không khớp code head+dirty mà biên nhận ghi"
    if not run_log_has(rp, receipt, mode=scope):
        return ("không có dòng runs.jsonl mode scoped của lần chạy gate này (biên nhận không do lượt gate scoped ghi)" if scope == "scoped"
                else "không có dòng runs.jsonl của lần chạy gate này (biên nhận không do post-fix-gate --full ghi)")
    return None


def linked_worktrees(top):
    """Work trees of the repository other than top (`git worktree list --porcelain`); [] when git cannot say."""
    rc, out = git(top, "worktree", "list", "--porcelain")
    if rc != 0:
        return []
    return [ln[9:] for ln in out.splitlines() if ln.startswith("worktree ") and os.path.realpath(ln[9:]) != os.path.realpath(top)]


def check(cwd, rev="HEAD", tag_remote=None, linked=False):
    """(ok, reason). linked=True: chỉ xét biên nhận của chính worktree đó, không dự phòng tiếp."""
    ok, reason = _own_check(cwd, rev, tag_remote, linked)
    if ok or linked:
        return ok, reason
    # Trunk mode (issue #5): gate chạy trong linked worktree và ghi biên nhận dưới git dir của worktree đó; main chỉ nhận merge nên
    # biên nhận của main (không có, hoặc cũ: bản `worktree finish` chép về lần trước) không phủ code sắp push. Biên nhận của từng
    # linked worktree được xét theo cùng luật như của main, trừ một điểm: file nào "không cần test" do MA TRẬN VÀ CHECKLIST CỦA MAIN
    # quyết (xem `rules_dir` trong _own_check), worktree không tự miễn test cho mình.
    # ponytail: runs.jsonl đã ghi `fp` (19/10) nhưng một dòng full non-PASS mới hơn cùng fingerprint vẫn chưa thu hồi biên nhận PASS
    # cũ hơn. Từ chối khi thấy một suite flaky được push qua đường này; làm sớm có thể chặn UNTESTED hoặc thiếu thiết bị của cùng cây.
    top = toplevel(cwd)[0]
    rc, sha = git(top, "rev-parse", "--verify", "-q", rev + "^{commit}") if top else (1, "")
    skipped = []
    for wt in linked_worktrees(top) if rc == 0 else []:
        try:   # tag_remote=None: cách worktree nhìn remote (config riêng của worktree) không phải biên nhận; main đã tự hỏi remote rồi
            covered = _own_check(wt, sha.strip(), None, linked=True)[0]
        except (subprocess.SubprocessError, RuntimeError, OSError) as e:   # worktree hỏng dở: không phủ, nhưng không chặn các worktree khác
            skipped.append(f"{wt} ({e})")
            continue
        if covered:
            return True, f"covered by the gate receipt of the linked worktree {wt}"
    if skipped:
        reason += "; không xét được biên nhận của linked worktree: " + ", ".join(skipped[:3])
    return ok, reason


def _own_check(cwd, rev, tag_remote, linked):
    """(ok, reason) theo biên nhận của chính checkout `cwd`; linked=True: không lối tắt nào ngoài một biên nhận thật."""
    top, why = toplevel(cwd)
    if why:
        return False, f"repository without a work tree here ({why}): cannot find the gate receipt"
    if top is None:
        # worktree đã mất thư mục (prunable) không phải "không có repo": nó không bảo lãnh được gì cho main
        return (False, "linked worktree has no work tree") if linked else (True, "not a git repo")
    if tag_remote and on_remote_only(top, rev, tag_remote):
        return True, "a tag of commits the remote already has: nothing new is pushed"
    rp, srp = tree_fp.receipt_path(top), tree_fp.scoped_receipt_path(top)
    receipt = _read_receipt(rp)
    # #644: biên nhận của lượt gate scoped (scoped_pass.json cạnh full_pass.json) chỉ được xét khi file có mặt; vắng thì mọi lời từ chối
    # giữ nguyên từng chữ như trước
    has_scoped = os.path.lexists(srp)
    scoped = _read_receipt(srp) if has_scoped else None
    # a project outside this repository is not this repository's (a forged one could name a directory with no matrix)
    project = receipt.get("project") if receipt and _inside(receipt.get("project"), top) else top
    sproject = scoped.get("project") if scoped and _inside(scoped.get("project"), top) else top
    homes = [d for d in dict.fromkeys((project, sproject, top, os.path.abspath(cwd))) if os.path.isfile(os.path.join(d, MATRIX))]
    if not homes:
        # main có ma trận (nếu không thì main đã trả True); worktree không ma trận chưa chạy test hồi quy nào để bảo lãnh
        if linked:
            return False, "no regression matrix in this linked worktree"
        # #482 as in strict_check: a repo with the DevKit installed (.agents/devkit, a symlink counts) that lost its matrix
        # had it deleted or renamed — fail closed instead of "no matrix, nothing to check"
        if os.path.lexists(os.path.join(top, ".agents", "devkit")):
            return False, f"DevKit installed (.agents/devkit) but {MATRIX} is missing: restore it, then run agent-kit integrate"
        return True, "no regression matrix"
    problem = None
    if receipt is not None and receipt.get("exit") == 0 and receipt.get("head"):
        problem = receipt_problem(top, rp, receipt, rev)
    full_ok = not (receipt is None or problem or receipt.get("exit") != 0 or not receipt.get("head"))
    if full_ok:
        ok, full_why = _covered(top, rev, receipt, project, linked)
        if ok or not has_scoped:
            return ok, full_why
    # biên nhận --full không có / không hợp lệ / không phủ rev: thử biên nhận scoped với CÙNG mọi kiểm tra (receipt_problem scope="scoped")
    sproblem, scoped_why = None, None
    if has_scoped:
        if scoped is None or scoped.get("exit") != 0 or isinstance(scoped.get("exit"), bool) or not scoped.get("head"):
            sproblem = "scoped_pass.json không phải biên nhận exit 0 (có head)"
        else:
            sproblem = receipt_problem(top, srp, scoped, rev, scope="scoped") or _scoped_base_problem(top, scoped)
        if not sproblem:
            ok, scoped_why = _covered(top, rev, scoped, sproject, linked)
            if ok:
                return True, "covered by the scoped gate receipt" if scoped_why == "covered" else scoped_why
    if full_ok:
        return False, f"{full_why}; biên nhận scoped: {sproblem or scoped_why}"
    # không biên nhận nào dùng được (scoped hợp lệ mà không phủ rev cũng vậy: file scoped có mặt không được bỏ hai lối approved / docs-only dưới đây)
    if linked:
        return False, "no usable receipt in this linked worktree"
    ok, why_not = approved(top, "@{u}.." + rev)
    if ok:
        return True, why_not
    # --no-renames: a rename is also a delete of the old path (src/Foo.kt -> docs/Foo.md is code leaving)
    rc, out = git(top, "diff", "--name-only", "--no-renames", "-z", "@{u}", rev)
    if rc == 0 and untestable_only(top, homes[0], [p for p in out.split("\0") if p], rev=rev):
        return True, "only files that need no test (docs / agent config), none watched by the matrix"
    return False, ("chưa có biên nhận gate --full exit 0 (có head) cho code sắp push"
                   + (f" (biên nhận hiện có không hợp lệ: {problem})" if problem else "") + (f"; {why_not}" if why_not else "")
                   + (f"; biên nhận scoped không dùng được: {sproblem or scoped_why}" if has_scoped else ""))


def _scoped_base_problem(top, receipt):
    """None khi `base` của biên nhận scoped đã có trên remote: tổ tiên của @{u} hay origin/HEAD, origin/main, origin/master (nhánh PR gộp
    origin/main rồi gate --diff origin/main: base là đỉnh origin/main, chưa trên @{u}); else lý do. Biên nhận scoped chỉ chứng minh
    base..cây: base là commit chưa push thì commit giữa base và đích lên remote mà không test nào chạy."""
    seen = []
    for ref in ("@{u}", "refs/remotes/origin/HEAD", "refs/remotes/origin/main", "refs/remotes/origin/master"):
        rc, sha = git(top, "rev-parse", "--verify", "-q", ref + "^{commit}")
        if rc == 0 and sha.strip():
            seen.append(ref)
            if git(top, "merge-base", "--is-ancestor", receipt["base"], sha.strip())[0] == 0:
                return None
    if seen:
        return (f"base {receipt['base'][:10]} của biên nhận scoped chưa có trên đích push ({', '.join(seen)}): "
                "commit giữa base và đích chưa được test")
    return "không có đích push (@{u} / origin/HEAD / origin/main / origin/master) để kiểm base của biên nhận scoped"


def _read_receipt(rp):
    """Biên nhận JSON (dict) ở rp, None khi thiếu / không đọc được / không phải object."""
    try:   # O_NONBLOCK + regular file only: a FIFO planted at the receipt blocked open() until the hook timed out (issues-bugs A.4)
        with os.fdopen(os.open(rp, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0)), encoding="utf-8") as f:
            if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
                raise OSError("the receipt is not a regular file")
            receipt = json.load(f)
    except (TypeError, OSError, ValueError, RecursionError):
        receipt = None
    return receipt if isinstance(receipt, dict) else None


def _covered(top, rev, receipt, project, linked):
    """(ok, reason): biên nhận đã qua receipt_problem có phủ những gì push `rev` gửi đi không (head là tổ tiên, mọi file đổi từ head đã được
    test đúng blob). Tách khỏi _own_check (#644) để biên nhận --full và biên nhận scoped đi cùng một đường."""
    head = receipt["head"]
    if subprocess.run(["git", "-C", top, "merge-base", "--is-ancestor", head, rev],
                      capture_output=True, timeout=5).returncode != 0:
        # D3 (2026-10-09): `git commit --amend` that only rewords the gated commit leaves its tree as it was - the same content,
        # covered like the gated commit itself. Any other rewrite (rebase, squash, an amend that changes a file) is refused.
        rc, trees = git(top, "rev-parse", head + "^{tree}", rev + "^{tree}")
        same_tree = rc == 0 and len(set(trees.split())) == 1 and len(trees.split()) == 2
        if not same_tree:
            return False, (f"lần gate PASS gần nhất ({head[:10]}) không nằm trong lịch sử của {rev} (pull/rebase sau gate?)\n"
                           + recovery_hint(top, rev, head))
    ok, why_not = approved(top, f"{head}..{rev}")
    if ok:
        return True, why_not
    rc, out = git(top, "diff", "--name-only", "--no-renames", "-z", head, rev)
    if rc != 0:
        raise RuntimeError("git diff failed")
    prefix = os.path.relpath(project, top).replace(os.sep, "/")
    prefix = "" if prefix == "." else prefix + "/"
    def kept(p):
        return p and not any(p == prefix + e or p.startswith(prefix + e + "/") for e in tree_fp.EXCLUDE)
    changed = [p for p in out.split("\0") if kept(p)]
    dirty = receipt.get("dirty") or {}
    if linked or receipt.get("carried_from"):
        # biên nhận ghi blob của từng file dirty lúc gate chạy: so cả các file đó với rev, kể cả khi head..rev không đổi chúng
        # (worktree ở HEAD của main có gate PASS nhờ sửa CHƯA commit thì không phủ HEAD của main; ca L10 của test). Biên nhận
        # `worktree finish` chép sang main cũng vậy: sửa chưa commit đó được finish commit rồi main đảo lại thì head..rev rỗng (ca L15)
        seen = set(changed)
        changed += [p for p in dirty if kept(p) and p not in seen]
    now, then = blobs(top, rev, changed), blobs(top, head, changed)
    bad = [p for p in changed if now.get(p) != (dirty[p] if p in dirty else then.get(p))]
    rules_dir = None
    if linked:
        # "không cần test" là quyết định của main (ma trận + liên kết covers trong checklist của main), không phải của worktree:
        # worktree tự phân loại bằng checklist/ma trận của chính nó thì miễn được file main đang theo dõi (README.md→REG-1, ca L18).
        # Không tìm được main hay ma trận của main thì untestable_only trả False: cần biên nhận phủ cả file đó.
        rc, listing = git(top, "worktree", "list", "--porcelain")
        main_top = listing.split("\n", 1)[0][9:] if rc == 0 and listing.startswith("worktree ") else ""
        rules_dir = os.path.normpath(os.path.join(main_top, os.path.relpath(project, top))) if main_top else os.devnull
    # linked: main quyết, và quy tắc chặt hơn mà riêng worktree có (liên kết covers git-ignored của nó) cũng giữ file lại (ca L19)
    if bad and untestable_only(top, project, bad, rules_dir, rev=rev) and (not linked or untestable_only(top, project, bad, rev=rev)):
        return True, "files changed since the gate need no test (docs / agent config), none watched by the matrix"
    if bad:
        return False, (f"{len(bad)} file sắp push khác bản gate đã test (sửa/commit sau lần gate PASS): "
                       + ", ".join(bad[:5]) + (f"; {why_not}" if why_not else ""))
    return True, "covered"


def main(argv):
    if hasattr(sys.stderr, "reconfigure"):   # untestable_only()'s warning may name a non-UTF-8 path too (see the print below)
        sys.stderr.reconfigure(errors="backslashreplace")
    argv = list(argv)
    tag_remote = None
    if "--tag-remote" in argv:
        k = argv.index("--tag-remote")
        tag_remote = argv[k + 1] if k + 1 < len(argv) else None
        del argv[k:k + 2]
    dst = None
    if "--dst" in argv:
        k = argv.index("--dst")
        dst = argv[k + 1:k + 3] if k + 2 < len(argv) else [None, None]   # thiếu giá trị: đích không rõ → luật cũ
        del argv[k:k + 3]
        if "--dst" in argv:
            dst = [None, None]   # hai --dst: không biết cái nào là đích thật → luật cũ
    # #472 mục A: có `--via-hook` ở bất kỳ đâu (kể cả thiếu giá trị, hay hai lần) là chế độ chặt — không bao giờ rơi về luật biên nhận
    strict, single, hook_remote = "--via-hook" in argv, argv.count("--via-hook") == 1, None
    while "--via-hook" in argv:   # hai cờ: không biết remote nào → hook_remote None, không gì là "không gửi gì mới"
        k = argv.index("--via-hook")
        hook_remote = argv[k + 1] if single and k + 1 < len(argv) else None
        del argv[k:k + 2]
    cwd = argv[1] if len(argv) > 1 else "."
    rev = argv[2] if len(argv) > 2 else "HEAD"
    try:
        if rev in ("--all-tags", "--all-branches") and len(argv) > 3:
            if rev == "--all-tags":
                ok, reason = check_all_tags(cwd, argv[3])
            else:
                ok, reason = check_all_branches(cwd, argv[3], strict=strict)
        elif strict:
            # đích của --dst phải cùng remote với remote hook đang push (một lệnh một remote); lệch → coi như đích không rõ
            ok, reason = strict_check(cwd, rev, tag_remote, dst if dst and dst[0] == hook_remote else None, hook_remote)
        elif dst and not tag_remote and not rev.startswith("-") and pr_branch(cwd, *dst):   # sweep thiếu đối số, tag: luật cũ
            ok, reason = True, f"push nhánh PR {dst[1]}: --full chạy một lần ở merge gate trước khi gộp vào trunk"
        else:
            ok, reason = check(cwd, rev, tag_remote)
    except (subprocess.TimeoutExpired, RuntimeError, OSError) as e:
        ok, reason = False, f"không kiểm được biên nhận gate ({e})"
    except Exception as e:  # noqa: BLE001 - chế độ chặt không bao giờ fail-open; ngoài nó giữ hành vi cũ (lỗi lạ nổ ra như trước)
        if not strict:
            raise
        ok, reason = False, f"không kiểm được push ({type(e).__name__}: {e})"
    if not ok:
        # backslashreplace: a reason naming a non-UTF-8 path or tag (decoded with surrogateescape) crashed the print on a
        # strict UTF-8 stdout (macOS, 2026-10-09). Set here, not at start: importing post-fix-gate.py resets it to "replace".
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(errors="backslashreplace")
        # a reason with a second line carries its own next step (recovery_hint): the generic one would contradict it
        print(reason if "\n" in reason else f"{reason} — {INTEGRATE}")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
