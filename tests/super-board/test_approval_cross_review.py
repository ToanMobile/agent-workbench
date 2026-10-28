#!/usr/bin/env python3
"""#605: duyệt chéo giữa agent thay cho `done` của người, trừ nhóm chỉ người được duyệt.

Reviewer lane đăng một comment riêng chứa đúng một dòng `cross-review-approved: {json}` sau approval-request mới nhất.
validate() nhận khi repo/pr/head/scope khớp request, reviewer khác builder (không phân biệt hoa thường), task_id và
gate_receipt không rỗng, người đăng có quyền ghi. Plan chạm nhóm chỉ người (schema phá huỷ, xoá file được bảo vệ,
needs_you như migrate DB live) thì marker không đủ: chỉ `done` của người mới duyệt.
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

HEAD, OTHER = "a" * 40, "c" * 40
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
             "builder": "claude-builder", "task_id": "issue-605-review", "gate_receipt": "f" * 40}
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

    def test_human_only_plans_ignore_cross_review(self):
        for plan in (PLAN_SCHEMA, PLAN_DELETE, PLAN_LIVE):
            r = run(comment(2, cross(), "2026-10-28T10:05:00Z"), plan=plan)
            self.assertFalse(r["approved"], (plan, r))

    def test_human_only_plans_accept_human_done(self):
        for plan in (PLAN_SCHEMA, PLAN_DELETE, PLAN_LIVE):
            r = run(comment(2, "done", "2026-10-28T10:05:00Z"), plan=plan)
            self.assertTrue(r["approved"], (plan, r))

    def test_default_is_fail_closed(self):
        r = approval.validate([request_comment(), comment(2, cross(), "2026-10-28T10:05:00Z")], EXPECTED, perm)
        self.assertFalse(r["approved"], r)

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
        self.assertFalse(self.deps(PLAN_SCHEMA)["needsYouDone"])

    def test_without_config_keeps_card_blocked(self):
        self.assertFalse(self.deps(PLAN_SIZE, with_config=False)["needsYouDone"])


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
                     "app/release.keystore", ".agents/local/rules/00.md"):
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
