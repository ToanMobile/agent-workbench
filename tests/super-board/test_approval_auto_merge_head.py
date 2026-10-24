#!/usr/bin/env python3
"""#262: người duyệt head X, merge gate tự gộp main sạch thành head Y — duyệt vẫn hiệu lực trên Y, không đòi `done` lại.

Gate truyền `approved_head=X` (head nó đọc TRƯỚC khi tự đẩy merge commit) kèm `head=Y` (head của chính nó đẩy). Duyệt chỉ gắn với X;
một commit người/agent đẩy thêm làm head hiện tại khác Y thì vẫn đòi duyệt lại. Không truyền approved_head thì giữ hành vi cũ.
"""
import importlib.util
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("approval", ROOT / ".claude/bin/super-board-approval.py")
approval = importlib.util.module_from_spec(spec)
spec.loader.exec_module(approval)

X, Y, Z, W = ("a" * 40, "b" * 40, "c" * 40, "d" * 40)
REPO, PR = "o/r", 7
SCOPE = "e" * 64


class FakeGitHub(approval.GitHub):
    def __init__(self, current_head, request_head):
        super().__init__(REPO)
        self.current_head = current_head
        request = approval.request_for(REPO, PR, request_head, SCOPE)
        self._comments = [
            {"id": 1, "body": "Reason tag: 🙋\n" + approval.marker(request), "user": {"login": "boss", "type": "User"},
             "created_at": "2026-10-22T10:00:00Z", "updated_at": "2026-10-22T10:00:00Z", "source": 1},
            {"id": 2, "body": "done", "user": {"login": "boss", "type": "User"},
             "created_at": "2026-10-22T10:05:00Z", "updated_at": "2026-10-22T10:05:00Z", "source": 1},
        ]

    def pr(self, number):
        return self.current_head, {1}

    def comments(self, number):
        return list(self._comments) if number == 1 else []   # check() reads the linked issue and the PR itself

    def permission(self, login):
        return "admin"


class ApprovalAutoMergeHead(unittest.TestCase):
    def test_approved_x_gate_merged_to_y_still_approved(self):
        r = FakeGitHub(current_head=Y, request_head=X).check(PR, Y, SCOPE, approved_head=X)
        self.assertTrue(r["approved"], r)

    def test_without_approved_head_a_moved_head_still_needs_new_approval(self):
        r = FakeGitHub(current_head=Y, request_head=X).check(PR, Y, SCOPE)
        self.assertFalse(r["approved"], r)

    def test_commit_pushed_after_the_gate_merge_voids_approval(self):
        r = FakeGitHub(current_head=Z, request_head=X).check(PR, Y, SCOPE, approved_head=X)
        self.assertFalse(r["approved"], r)
        self.assertTrue(r.get("headChanged"), r)

    def test_request_for_another_head_is_not_covered(self):
        r = FakeGitHub(current_head=Y, request_head=W).check(PR, Y, SCOPE, approved_head=X)
        self.assertFalse(r["approved"], r)

    def test_cli_accepts_approved_head(self):
        import subprocess
        out = subprocess.run([sys.executable, str(ROOT / ".claude/bin/super-board-approval.py"), "--repo", REPO, "--pr", str(PR),
                              "--head", Y, "--approved-head", X, "--plan", json.dumps({})],
                             capture_output=True, text=True)
        self.assertNotIn("unrecognized arguments", out.stderr)


if __name__ == "__main__":
    unittest.main()
