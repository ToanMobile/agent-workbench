#!/usr/bin/env python3
"""#605: duyệt chéo giữa agent thay cho `done` của người, trừ nhóm chỉ người được duyệt.

Reviewer lane đăng một comment riêng chứa đúng một dòng `cross-review-approved: {json}` sau approval-request mới nhất.
validate() nhận khi repo/pr/head/scope khớp request, reviewer khác builder (không phân biệt hoa thường), task_id và
gate_receipt không rỗng, người đăng có quyền ghi. Luật chủ repo 28/10: schema và needs_you (migrate DB live) cũng được
duyệt chéo; chỉ xoá file được bảo vệ (delete-protected) mới cần `done` của người.
Policy: PR xoá file khớp merge_policy.protected_paths → human có category delete-protected.
"""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("approval", ROOT / ".claude/bin/super-board-approval.py")
approval = importlib.util.module_from_spec(spec)
spec.loader.exec_module(approval)
POLICY = ROOT / ".claude/bin/super-board-merge-policy.py"

# #605 (audit T0066 vòng 2): task_id của marker phải có biên bản audit pass của antigravity-pm với auditedHead == head được duyệt,
# và auditedHead phải là commit có trong repo. Repo tạm + PM state giả (ANTIGRAVITY_PM_STATE_HOME chỉ đặt bên trong test này).
import atexit
import os
import shutil

_TMP = tempfile.mkdtemp(prefix="sb-cross-review-")
atexit.register(shutil.rmtree, _TMP, True)
_REPO = os.path.join(_TMP, "repo")
_GIT_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def _git(*args):
    return subprocess.run(["git", "-C", _REPO, *args], check=True, capture_output=True, text=True, env=_GIT_ENV).stdout.strip()


os.makedirs(_REPO)
_git("init", "-q", "-b", "main")
_git("-c", "user.email=t@example.invalid", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "c1")
_C1 = _git("rev-parse", "HEAD")
_git("-c", "user.email=t@example.invalid", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "c2")
_C2 = _git("rev-parse", "HEAD")
_TOP = _git("rev-parse", "--show-toplevel")
os.environ["ANTIGRAVITY_PM_STATE_HOME"] = os.path.join(_TMP, "pm")
# audit T0066 vòng 3: pm home lạ chỉ tính khi là fixture test (DEVKIT_PM_HOME_TEST=1 VÀ dưới thư mục tạm), như push_gate.approved().
os.environ["DEVKIT_PM_HOME_TEST"] = "1"
os.chdir(_REPO)   # approval mặc định đọc biên bản của repo cwd (git toplevel)
TASK = "T0605-review"


def pm_task(task_id, head, verdict="pass", project=None):
    d = Path(_TMP, "pm", "projects", "p", "tasks", task_id)
    d.mkdir(parents=True, exist_ok=True)
    (d / "task.json").write_text(json.dumps({"id": task_id, "project": project or _TOP, "verdicts": {
        "audit": {"verdict": verdict, "reviewer": "pm", "notes": f"fixture\nauditedHead: {head}"}}}))


pm_task(TASK, _C2)

HEAD, OTHER = _C2, "c" * 40
REPO, PR = "o/r", 7
SCOPE = "e" * 64
EXPECTED = {"repo": REPO, "pr": PR, "head": HEAD, "scope": SCOPE}
PLAN_SIZE = {"human": [{"category": "size", "why": "big PR"}], "migrations": [], "run": [], "needs_you": []}
PLAN_SCHEMA = {"human": [{"category": "schema", "why": "keyword drop table"}], "migrations": [], "run": [], "needs_you": []}
PLAN_DELETE = {"human": [{"category": "delete-protected", "why": "deletes a protected file"}], "migrations": [], "run": [],
               "needs_you": []}
PLAN_LIVE = {"human": [], "migrations": ["supabase/migrations/1.sql"], "run": [],
             "needs_you": ["<your live migrate command>   # live: not in allowed_envs"]}
DOT_ENV = "." + "env"   # tên file ghép lúc chạy: hook chặn lệnh shell có chuỗi tên file bí mật


def comment(cid, body, at, login="boss", kind="User", source=1, updated=None):
    return {"id": cid, "body": body, "user": {"login": login, "type": kind}, "created_at": at,
            "updated_at": updated or at, "source": source}


def request_comment():
    return comment(1, "Reason tag: 🙋\n" + approval.marker(approval.request_for(REPO, PR, HEAD, SCOPE)),
                   "2026-10-28T10:00:00Z")


def cross(**over):
    value = {"repo": REPO, "pr": PR, "head": HEAD, "scope": SCOPE, "reviewer": "claude-reviewer",
             "builder": "claude-builder", "task_id": TASK, "gate_receipt": "f" * 40}
    value.update(over)
    return "cross-review-approved: " + json.dumps(value, sort_keys=True)


def perm(login):
    return "write"


def run(*comments, plan=PLAN_SIZE):
    return approval.validate([request_comment(), *comments], EXPECTED, perm,
                             cross_review_ok=approval.cross_review_allowed(plan))


class CrossReview(unittest.TestCase):
    def test_valid_cross_review_approves(self):
        r = run(comment(2, cross(), "2026-10-28T10:05:00Z", login="sb-bot", kind="Bot"))
        self.assertTrue(r["approved"], r)
        self.assertEqual(r["approver"], "cross-review:claude-reviewer")
        self.assertEqual(r["why"], "cross-review by claude-reviewer")
        self.assertEqual(r["approvalId"], 2)

    def test_self_review_case_insensitive_not_approved(self):
        r = run(comment(2, cross(reviewer="Alice", builder="alice"), "2026-10-28T10:05:00Z"))
        self.assertFalse(r["approved"], r)

    def test_head_mismatch_not_approved(self):
        r = run(comment(2, cross(head=OTHER), "2026-10-28T10:05:00Z"))
        self.assertFalse(r["approved"], r)

    def test_empty_gate_receipt_or_task_id_not_approved(self):
        self.assertFalse(run(comment(2, cross(gate_receipt=""), "2026-10-28T10:05:00Z"))["approved"])
        self.assertFalse(run(comment(2, cross(task_id=""), "2026-10-28T10:05:00Z"))["approved"])

    def test_two_marker_lines_not_approved(self):
        self.assertFalse(run(comment(2, cross() + "\n" + cross(), "2026-10-28T10:05:00Z"))["approved"])

    def test_marker_before_request_or_edited_not_approved(self):
        self.assertFalse(run(comment(2, cross(), "2026-10-28T09:55:00Z"))["approved"])
        self.assertFalse(run(comment(2, cross(), "2026-10-28T10:05:00Z", updated="2026-10-28T10:06:00Z"))["approved"])

    def test_marker_from_reader_not_approved(self):
        r = approval.validate([request_comment(), comment(2, cross(), "2026-10-28T10:05:00Z", login="rando")],
                              EXPECTED, lambda u: "read" if u == "rando" else "write", cross_review_ok=True)
        self.assertFalse(r["approved"], r)

    def test_marker_on_other_source_not_approved(self):
        self.assertFalse(run(comment(2, cross(), "2026-10-28T10:05:00Z", source=9))["approved"])

    def test_marker_mixed_with_request_line_supersedes_and_not_approved(self):
        # A marker comment that also holds an approval-request line becomes the newest request itself.
        body = cross() + "\n" + approval.marker(approval.request_for(REPO, PR, HEAD, SCOPE))
        self.assertFalse(run(comment(2, body, "2026-10-28T10:05:00Z"))["approved"])

    def test_delete_protected_ignores_cross_review(self):
        both = {**PLAN_LIVE, "human": PLAN_DELETE["human"] + PLAN_SCHEMA["human"]}
        for plan in (PLAN_DELETE, both):
            r = run(comment(2, cross(), "2026-10-28T10:05:00Z"), plan=plan)
            self.assertFalse(r["approved"], (plan, r))

    def test_schema_and_needs_you_accept_cross_review(self):
        for plan in (PLAN_SCHEMA, PLAN_LIVE):
            r = run(comment(2, cross(), "2026-10-28T10:05:00Z"), plan=plan)
            self.assertTrue(r["approved"], (plan, r))

    def test_human_only_plans_accept_human_done(self):
        for plan in (PLAN_SCHEMA, PLAN_DELETE, PLAN_LIVE):
            r = run(comment(2, "done", "2026-10-28T10:05:00Z"), plan=plan)
            self.assertTrue(r["approved"], (plan, r))

    def test_default_is_fail_closed(self):
        r = approval.validate([request_comment(), comment(2, cross(), "2026-10-28T10:05:00Z")], EXPECTED, perm)
        self.assertFalse(r["approved"], r)

    def test_task_id_without_audit_record_not_approved(self):
        # Builder tự khai task_id không có biên bản audit (audit T0066 vòng 2, BYPASS-R2-04)
        for task in ("T0999-forged", "T0606-nothing"):
            r = run(comment(2, cross(task_id=task), "2026-10-28T10:05:00Z"))
            self.assertFalse(r["approved"], (task, r))

    def test_task_id_bad_shape_not_approved(self):
        for task in ("issue-605-review", "../../x", "T0605-*", "T0605-review\nx"):
            r = run(comment(2, cross(task_id=task), "2026-10-28T10:05:00Z"))
            self.assertFalse(r["approved"], (task, r))

    def test_audit_on_another_head_not_approved(self):
        pm_task("T0607-old", _C1)   # audit pass thật nhưng cho head cũ
        r = run(comment(2, cross(task_id="T0607-old"), "2026-10-28T10:05:00Z"))
        self.assertFalse(r["approved"], r)

    def test_audit_verdict_fail_not_approved(self):
        pm_task("T0608-failed", _C2, verdict="fail")
        r = run(comment(2, cross(task_id="T0608-failed"), "2026-10-28T10:05:00Z"))
        self.assertFalse(r["approved"], r)

    def test_audit_of_another_project_not_approved(self):
        other = os.path.join(_TMP, "other")
        os.makedirs(other, exist_ok=True)
        pm_task("T0609-elsewhere", _C2, project=other)
        r = run(comment(2, cross(task_id="T0609-elsewhere"), "2026-10-28T10:05:00Z"))
        self.assertFalse(r["approved"], r)

    def test_audit_check_cli(self):
        cli = ROOT / ".claude/bin/super-board-audit-check.py"
        ok = subprocess.run([sys.executable, str(cli), TASK, _C2], capture_output=True, text=True, cwd=_REPO)
        self.assertEqual(ok.returncode, 0, ok.stderr)
        for task, sha in ((TASK, _C1), ("T0999-forged", _C2), ("bad id", _C2), (TASK, "zz")):
            r = subprocess.run([sys.executable, str(cli), task, sha], capture_output=True, text=True, cwd=_REPO)
            self.assertEqual(r.returncode, 1, (task, sha, r.stdout, r.stderr))

    def test_overridden_pm_home_without_test_switch_refused(self):
        # audit T0066 vòng 3 (finding 3): HOME=/tmp/x hay ANTIGRAVITY_PM_STATE_HOME lạ mà không phải fixture test → không duyệt
        from unittest import mock
        with mock.patch.dict(os.environ, {"DEVKIT_PM_HOME_TEST": ""}):
            r = run(comment(2, cross(), "2026-10-28T10:05:00Z"))
            cli = subprocess.run([sys.executable, str(ROOT / ".claude/bin/super-board-audit-check.py"), TASK, _C2],
                                 capture_output=True, text=True, cwd=_REPO)
        self.assertFalse(r["approved"], r)
        self.assertEqual(cli.returncode, 1, cli.stderr)

    def test_unreadable_plan_is_human_only(self):
        self.assertFalse(approval.cross_review_allowed(None))
        self.assertFalse(approval.cross_review_allowed({"human": "x"}))


class DepsCrossReview(unittest.TestCase):
    """--deps --config: thẻ Blocked ra khi marker duyệt chéo hợp lệ và plan hiện tại không chạm nhóm chỉ người."""

    def deps(self, plan, with_config=True):
        import contextlib
        import io
        from unittest import mock
        scope = approval.scope_for(plan)
        req = comment(1, "Reason tag: 🙋\n" + approval.marker(approval.request_for(REPO, PR, HEAD, scope)),
                      "2026-10-28T10:00:00Z", source=40)
        mark = comment(2, cross(scope=scope), "2026-10-28T10:05:00Z", source=40)
        out = io.StringIO()
        argv = ["approval", "--deps", "--repo", REPO] + (["--config", "cfg.json"] if with_config else [])
        with mock.patch.object(approval.GitHub, "pr", lambda self, n: (HEAD, {40})), \
                mock.patch.object(approval.GitHub, "comments", lambda self, n: [req, mark] if n == 40 else []), \
                mock.patch.object(approval.GitHub, "permission", lambda self, u: "write"), \
                mock.patch.object(approval.GitHub, "plan_for", lambda self, n, c: plan), \
                mock.patch.object(sys, "argv", argv), \
                mock.patch.object(sys, "stdin", io.StringIO(json.dumps({"40": {"number": 40, "needsYou": True}}))), \
                contextlib.redirect_stdout(out):
            approval.main()
        return json.loads(out.getvalue())["40"]

    def test_cross_review_clears_card(self):
        e = self.deps(PLAN_SIZE)
        self.assertTrue(e["needsYouDone"], e)
        self.assertEqual(e["approvalWhy"], "cross-review by claude-reviewer")

    def test_human_only_plan_keeps_card_blocked(self):
        self.assertFalse(self.deps(PLAN_DELETE)["needsYouDone"])

    def test_schema_and_live_plans_clear_card(self):
        for plan in (PLAN_SCHEMA, PLAN_LIVE):
            self.assertTrue(self.deps(plan)["needsYouDone"], plan)

    def test_without_config_keeps_card_blocked(self):
        self.assertFalse(self.deps(PLAN_SIZE, with_config=False)["needsYouDone"])


def _fetch_fixture(name):
    """(local, sha): repo `local` có remote origin; sha chỉ có ở origin dưới refs/pull/7/head, local chưa có object."""
    base = os.path.join(_TMP, name)
    origin, work, local = (os.path.join(base, d) for d in ("origin.git", "work", "local"))

    def git(*a):
        return subprocess.run(["git", *a], check=True, capture_output=True, text=True, env=_GIT_ENV).stdout.strip()

    git("init", "-q", "--bare", origin)
    git("init", "-q", "-b", "main", work)
    git("-C", work, "-c", "user.email=t@example.invalid", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "pr")
    sha = git("-C", work, "rev-parse", "HEAD")
    git("-C", work, "push", "-q", origin, "HEAD:refs/pull/7/head")
    git("init", "-q", "-b", "main", local)
    git("-C", local, "remote", "add", "origin", origin)
    return git("-C", local, "rev-parse", "--show-toplevel"), sha


class RepoTopAndFetch(unittest.TestCase):
    """audit T0066 vòng 3 (finding 2): biên bản xét theo repo của board (--repo-path), không theo cwd; head PR chưa có object
    trong repo thì fetch refs/pull/<n>/head trước khi đối chiếu auditedHead."""

    def test_check_uses_repo_path_and_fetches_missing_head(self):
        from unittest import mock
        local, sha = _fetch_fixture("check")
        pm_task("T0610-fetched", sha, project=local)
        req = comment(1, "Reason tag: 🙋\n" + approval.marker(approval.request_for(REPO, PR, sha, SCOPE)),
                      "2026-10-28T10:00:00Z", source=PR)
        mark = comment(2, cross(head=sha, task_id="T0610-fetched"), "2026-10-28T10:05:00Z", source=PR)
        cwd = os.getcwd()
        os.chdir(_TMP)   # cwd KHÔNG phải repo: biên bản phải xét theo repo_path
        try:
            with mock.patch.object(approval.GitHub, "pr", lambda self, n: (sha, set())), \
                    mock.patch.object(approval.GitHub, "comments", lambda self, n: [req, mark] if n == PR else []), \
                    mock.patch.object(approval.GitHub, "permission", lambda self, u: "write"):
                r = approval.GitHub(REPO, repo_path=local).check(PR, sha, SCOPE, cross_review_ok=True)
        finally:
            os.chdir(cwd)
        self.assertTrue(r["approved"], r)

    def test_audit_check_cli_fetches_pr_head(self):
        local, sha = _fetch_fixture("cli")
        pm_task("T0611-cli", sha, project=local)
        cli = ROOT / ".claude/bin/super-board-audit-check.py"
        r = subprocess.run([sys.executable, str(cli), "--top", local, "--pr", "7", "T0611-cli", sha],
                           capture_output=True, text=True, cwd=_TMP)
        self.assertEqual(r.returncode, 0, r.stderr)
        bad = subprocess.run([sys.executable, str(cli), "--top", local, "--pr", "8", "T0611-cli", "d" * 40],
                             capture_output=True, text=True, cwd=_TMP)
        self.assertEqual(bad.returncode, 1, bad.stderr)   # ref không có ở origin: fetch lỗi → từ chối như cũ


def policy(cfg, files, diff):
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp)
        (p / "cfg.json").write_text(json.dumps(cfg))
        (p / "meta.json").write_text(json.dumps({"labels": [], "body": "", "files": files,
                                                 "additions": 0, "deletions": 1, "changedFiles": len(files)}))
        (p / "pr.diff").write_text(diff)
        out = subprocess.run([sys.executable, str(POLICY), "--config", str(p / "cfg.json"), "--meta",
                              str(p / "meta.json"), "--diff", str(p / "pr.diff")], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def deletion(path):
    return (f"diff --git a/{path} b/{path}\ndeleted file mode 100644\nindex 1111111..0000000\n"
            f"--- a/{path}\n+++ /dev/null\n@@ -1 +0,0 @@\n-x\n")


class PolicyDeleteProtected(unittest.TestCase):
    CFG = {"merge_policy": {"default": "auto"}}

    def cats(self, plan):
        return [h["category"] for h in plan["human"]]

    def test_deleting_protected_default_path_goes_to_human(self):
        for path in (".agents/regression_matrix.active.json", DOT_ENV + ".local", "app/" + DOT_ENV,
                     "app/release.keystore", ".agents/local/rules/00.md",
                     # #605 Lane H: đồng bộ với PROTECTED_DELETE_DEFAULT của block-dangerous-git.sh
                     "app/google-services.json", "google-services.json"):
            plan = policy(self.CFG, [{"path": path, "additions": 0, "deletions": 1}], deletion(path))
            self.assertIn("delete-protected", self.cats(plan), (path, plan))
            self.assertFalse(approval.cross_review_allowed(plan))

    def test_editing_protected_path_is_not_a_deletion(self):
        path = ".agents/regression_matrix.active.json"
        diff = f"diff --git a/{path} b/{path}\nindex 1..2 100644\n--- a/{path}\n+++ b/{path}\n@@ -1 +1 @@\n-x\n+y\n"
        plan = policy(self.CFG, [{"path": path, "additions": 1, "deletions": 1}], diff)
        self.assertNotIn("delete-protected", self.cats(plan), plan)

    def test_deleting_unprotected_path_stays_auto(self):
        plan = policy(self.CFG, [{"path": "src/old.py", "additions": 0, "deletions": 1}], deletion("src/old.py"))
        self.assertEqual(plan["human"], [], plan)
        self.assertTrue(approval.cross_review_allowed({**plan, "human": [{"category": "size", "why": "x"}]}))

    def test_configured_protected_paths_replace_default(self):
        cfg = {"merge_policy": {"default": "auto", "protected_paths": ["secrets/**"]}}
        plan = policy(cfg, [{"path": "secrets/k.pem", "additions": 0, "deletions": 1}], deletion("secrets/k.pem"))
        self.assertIn("delete-protected", self.cats(plan), plan)
        plan = policy(cfg, [{"path": DOT_ENV, "additions": 0, "deletions": 1}], deletion(DOT_ENV))
        self.assertNotIn("delete-protected", self.cats(plan), plan)

    def test_binary_delete_through_github_read(self):
        # Cùng đường của merge gate: gh giả → super-board-github-read.py --kind diff → policy. File nhị phân bị xoá
        # không có dòng ---/+++ (chỉ `deleted file mode` + `Binary files ... differ`).
        import os
        path = "app/release.keystore"
        diff = (f"diff --git a/{path} b/{path}\ndeleted file mode 100644\nindex 1111111..0000000\n"
                f"Binary files a/{path} and /dev/null differ\n")
        files = [{"path": path, "additions": 0, "deletions": 0}]
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "bin").mkdir()
            (p / "bin/gh").write_text('#!/usr/bin/env bash\ncat "$FAKE_DIFF"\n')
            (p / "bin/gh").chmod(0o755)
            (p / "in.diff").write_text(diff)
            meta = {"labels": [], "body": "", "files": files, "additions": 0, "deletions": 0, "changedFiles": 1}
            (p / "meta.json").write_text(json.dumps(meta))
            env = dict(os.environ, PATH=f"{p / 'bin'}:{os.environ['PATH']}", FAKE_DIFF=str(p / "in.diff"),
                       SB_GITHUB_HALT_FILE=str(p / "halt.json"), SB_GITHUB_RETRY_DELAY="0", SB_GITHUB_READ_STRICT="1")
            read = subprocess.run([sys.executable, str(ROOT / ".claude/bin/super-board-github-read.py"), "--kind", "diff",
                                   "--meta", str(p / "meta.json"), "--", "pr", "diff", "9", "--repo", "o/r"],
                                  capture_output=True, text=True, env=env)
            self.assertEqual(read.returncode, 0, read.stderr)
            plan = policy(self.CFG, files, read.stdout)
        self.assertIn("delete-protected", self.cats(plan), plan)

    def test_rename_away_from_protected_path_counts_as_delete(self):
        diff = (f"diff --git a/{DOT_ENV} b/env.bak\nsimilarity index 100%\nrename from {DOT_ENV}\nrename to env.bak\n")
        plan = policy(self.CFG, [{"path": "env.bak", "additions": 0, "deletions": 0}], diff)
        self.assertIn("delete-protected", self.cats(plan), plan)


if __name__ == "__main__":
    unittest.main()
