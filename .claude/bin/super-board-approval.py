#!/usr/bin/env python3
"""Read-only, head-bound human approval shared by the planner and merge gate.

A trusted request pins the code and human steps BEFORE a human replies `done`.
#605: outside the human-only categories, a reviewer lane's `cross-review-approved: {json}` marker replaces `done`.
Labels only describe UI state. They never authorize a merge. No GitHub writes.
"""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
from datetime import datetime
import hashlib
import json
import re
import subprocess
import sys
import tempfile

_reader_spec = importlib.util.spec_from_file_location("github_read", Path(__file__).with_name("super-board-github-read.py"))
github_read = importlib.util.module_from_spec(_reader_spec)
_reader_spec.loader.exec_module(github_read)
_audit_spec = importlib.util.spec_from_file_location("audit_check", Path(__file__).with_name("super-board-audit-check.py"))
audit_check = importlib.util.module_from_spec(_audit_spec)
_audit_spec.loader.exec_module(audit_check)

PREFIX = "approval-request: "
SHA = re.compile(r"[0-9a-f]{40}\Z")
SCOPE = re.compile(r"[0-9a-f]{64}\Z")
BLOCK = re.compile(r"Reason tag:[^\n]*🙋|^approval-request:", re.M)
DONE = re.compile(r"\s*done[.!]?\s*\Z", re.I)
CROSS = "cross-review-approved: "
CROSS_FIELDS = ("reviewer", "builder", "task_id", "gate_receipt")
# #605: nhóm chỉ người duyệt được (luật chủ repo 28/10, bản sau): chỉ xoá file được bảo vệ (merge_policy.protected_paths).
# Schema và mọi mục needs_you (migrate DB live) duyệt chéo được như việc khác.
HUMAN_ONLY = {"delete-protected"}
# GitHub's closing keywords: KEYWORD[:] #N or KEYWORD[:] owner/repo#N.
CLOSES = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+([\w.-]+/[\w.-]+)?#(\d+)\b", re.I)


def body_links(body, repo):
    """Same-repo issues a PR body closes; other-repo references are ignored."""
    return {int(n) for other, n in CLOSES.findall(body) if not other or other.lower() == repo}


def scope_for(plan):
    # Exclude UI-only `done`; a label change must not change what was approved.
    relevant = {key: plan.get(key, []) for key in ("human", "migrations", "run", "needs_you")}
    return hashlib.sha256(json.dumps(relevant, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def cross_review_allowed(plan):
    """True khi plan không chạm nhóm chỉ người; plan thiếu hoặc đọc không được → False (chỉ `done` của người)."""
    if not isinstance(plan, dict):
        return False
    human, needs = plan.get("human", []), plan.get("needs_you", [])
    if not isinstance(human, list) or not isinstance(needs, list):
        return False
    return all(isinstance(h, dict) and isinstance(h.get("category"), str) and h["category"] not in HUMAN_ONLY
               for h in human)


def parse_cross_review(comment, request):
    """Marker duyệt chéo hợp lệ cho đúng `request` → dict, không thì None. Đúng một dòng marker trong comment."""
    lines = [line for line in (comment.get("body") or "").splitlines() if line.startswith(CROSS)]
    if len(lines) != 1:
        return None
    try:
        value = json.loads(lines[0][len(CROSS):])
    except ValueError:
        return None
    if (not isinstance(value, dict) or not isinstance(value.get("repo"), str)
            or value["repo"].lower() != request["repo"].lower() or type(value.get("pr")) is not int
            or value["pr"] != request["pr"] or value.get("head") != request["head"]
            or value.get("scope") != request["scope"]):
        return None
    if any(not isinstance(value.get(k), str) or not value[k].strip() for k in CROSS_FIELDS):
        return None
    if value["reviewer"].strip().lower() == value["builder"].strip().lower():
        return None   # tự duyệt
    return value


def request_for(repo, pr, head, scope):
    return {"repo": repo.lower(), "pr": int(pr), "head": head, "scope": scope}


def marker(request):
    return PREFIX + json.dumps(request, sort_keys=True, separators=(",", ":"))


def parse_request(comment):
    lines = [line for line in (comment.get("body") or "").splitlines() if line.startswith(PREFIX)]
    if len(lines) != 1:
        return None
    try:
        value = json.loads(lines[0][len(PREFIX):])
        if (not isinstance(value, dict) or not isinstance(value.get("repo"), str)
                or not re.fullmatch(r"[^/\s]+/[^/\s]+", value["repo"])
                or type(value.get("pr")) is not int or value["pr"] < 1
                or not SHA.fullmatch(value.get("head", ""))
                or not SCOPE.fullmatch(value.get("scope", ""))):
            return None
        return value
    except (ValueError, TypeError):
        return None


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError("missing comment timestamp")
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("comment timestamp lacks timezone")
    return result


def trusted_blocks(comments, permission):
    result = []
    for block in comments:
        if not BLOCK.search(block.get("body") or ""):
            continue
        user = block.get("user") or {}
        if not user.get("login") or user.get("type") not in ("User", "Bot"):
            raise ValueError("requester identity could not be verified")
        if permission(user["login"]) in ("write", "maintain", "admin"):
            result.append(block)
    return result


def validate(comments, expected, permission, cross_review_ok=False, audited=None):
    """Pure verdict; permission(login) is a current repository permission lookup.

    cross_review_ok (#605) = cross_review_allowed(plan) của caller; mặc định False: chỉ `done` của người.
    audited(task_id) (#605, audit T0066 vòng 2) = auditedHead của audit pass antigravity-pm cho task đó, hoặc None; marker duyệt chéo
    chỉ tính khi nó đúng bằng head của request. Mặc định: biên bản của repo cwd (super-board-audit-check.py); GitHub.check truyền repo
    của board (--repo-path, audit T0066 vòng 3).
    """
    audited = audited or audit_check.audited
    def hold(why):
        return {"approved": False, "why": why}

    if not SHA.fullmatch(expected.get("head", "")):
        return hold("current PR head is unavailable")
    try:
        blocks = trusted_blocks(comments, permission)
        if not blocks:
            return hold("no request from a trusted repository collaborator")
        # Any later human block supersedes the old request, including one with
        # missing/malformed metadata. Equal-second requests are ambiguous: hold.
        latest_time = max(timestamp(c.get("created_at")) for c in blocks)
        latest = [c for c in blocks if timestamp(c.get("created_at")) == latest_time]
        if len(latest) != 1:
            return hold("ambiguous newest human request")
        request_comment = latest[0]
        request = parse_request(request_comment)
        if request is None or any(request.get(k) != v for k, v in expected.items()):
            return hold("the latest request does not cover the current code and human steps")
        if timestamp(request_comment.get("updated_at")) != latest_time:
            return hold("approval request was edited; post a fresh request")
        requester = request_comment.get("user") or {}
        if not requester.get("login") or permission(requester["login"]) not in ("write", "maintain", "admin"):
            return hold("requester authority could not be verified")
        if not isinstance(request_comment.get("source"), int) or not request_comment.get("id"):
            return hold("request identity is missing")
        for comment in comments:
            if not comment.get("id") or comment.get("source") != request_comment.get("source"):
                continue
            done = DONE.fullmatch(comment.get("body") or "")
            review = None if done or not cross_review_ok else parse_cross_review(comment, request)
            if review is not None and audited(review["task_id"]) != request["head"]:
                review = None   # task_id tự khai không có audit pass cho đúng head này
            if not done and review is None:
                continue
            created = timestamp(comment.get("created_at"))
            if created <= latest_time or timestamp(comment.get("updated_at")) != created:
                continue
            author = comment.get("user") or {}
            # `done` chỉ của người (User); marker duyệt chéo do lane reviewer đăng, có thể là Bot có quyền ghi.
            if (not author.get("login") or author.get("type") not in (("User",) if done else ("User", "Bot"))
                    or permission(author["login"]) not in ("write", "maintain", "admin")):
                continue
            ids = {"request": request, "requestId": request_comment.get("id"), "approvalId": comment.get("id")}
            if done:
                return {"approved": True, "why": "trusted human confirmed the current request",
                        "approver": author["login"], **ids}
            return {"approved": True, "why": f"cross-review by {review['reviewer']}",
                    "approver": f"cross-review:{review['reviewer']}", "builder": review["builder"],
                    "taskId": review["task_id"], "gateReceipt": review["gate_receipt"], **ids}
        if cross_review_ok:
            return hold("waiting for a cross-review marker or a trusted human done on the current request")
        return hold("waiting for a trusted human to comment done on the current request")
    except (ValueError, TypeError, KeyError):
        return hold("approval evidence is incomplete or unreadable")


class GitHub:
    def __init__(self, repo, repo_path=None):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
            raise ValueError("missing or invalid repository")
        self.repo = repo.lower()
        self.permissions = {}
        # audit T0066 vòng 3: biên bản audit xét theo repo của board (config repo.path), không theo cwd của tiến trình gọi.
        self.top = audit_check.repo_top(repo_path or ".")

    @staticmethod
    def read(*args):
        kind = ("approval" if "graphql" in args else "comments" if "--paginate" in args
                else "permission" if args[-1].endswith("/permission") else "json")
        return github_read.read(list(args), kind)[1]

    def permission(self, login):
        if not re.fullmatch(r"[A-Za-z0-9_-]+(?:\[bot\])?", login):
            return None
        if login not in self.permissions:
            value = self.read("api", f"repos/{self.repo}/collaborators/{login}/permission")
            self.permissions[login] = value.get("permission")
        return self.permissions[login]

    def comments(self, number):
        pages = self.read("api", "--paginate", "--slurp",
                          f"repos/{self.repo}/issues/{number}/comments?per_page=100")
        if not isinstance(pages, list) or not pages or any(not isinstance(p, list) for p in pages):
            raise ValueError("unreadable comments")
        if any(not isinstance(c, dict) for page in pages for c in page):
            raise ValueError("unreadable comment")
        return [dict(comment, source=number) for page in pages for comment in page]

    def pr(self, number):
        # Paginate linked issues too: an omitted newer request must never make
        # an older approval authoritative. Remote-repository links are ignored.
        # GitHub fills closingIssuesReferences only for PRs into the default
        # branch; the body's closing keywords, read in this same head-pinned
        # snapshot, are added on every base (see below).
        query = '''query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){
          repository(owner:$owner,name:$repo){defaultBranchRef{name}
            pullRequest(number:$pr){headRefOid state baseRefName body
            closingIssuesReferences(first:100,after:$endCursor){
              pageInfo{hasNextPage endCursor} nodes{number repository{nameWithOwner}}
            }}}}'''
        owner, name = self.repo.split("/")
        pages = self.read("api", "graphql", "--paginate", "--slurp", "-f", f"query={query}",
                          "-F", f"owner={owner}", "-F", f"repo={name}", "-F", f"pr={number}")
        snapshots, issues = set(), set()
        if not isinstance(pages, list) or not pages:
            raise ValueError("unreadable PR")
        for page in pages:
            if page.get("errors"):
                raise ValueError("incomplete PR response")
            repository = page["data"]["repository"]
            pr = repository["pullRequest"]
            if pr["state"] != "OPEN":
                raise ValueError("PR is not open")
            snapshots.add((pr["headRefOid"], pr["baseRefName"], pr["body"],
                           (repository["defaultBranchRef"] or {}).get("name")))
            links = pr["closingIssuesReferences"]
            for issue in links["nodes"]:
                if issue["repository"]["nameWithOwner"].lower() == self.repo:
                    issues.add(issue["number"])
        if links["pageInfo"]["hasNextPage"] or len(snapshots) != 1:
            raise ValueError("PR changed or issue links are incomplete")
        head, base, body, default = snapshots.pop()
        if not all(isinstance(v, str) for v in (head, base, body, default)) or not SHA.fullmatch(head):
            raise ValueError("unreadable PR head, base or body")
        # The body's closing keywords count on every base: GitHub skips one written in a code span (`Closes #N`),
        # which left #321 approved by a human yet "not linked" forever (24/10). Same head-pinned snapshot, same authors.
        issues |= body_links(body, self.repo)
        return head, issues

    def plan_for(self, number, config):
        """Plan merge-policy HIỆN TẠI của PR `number` (cùng lệnh đọc, cùng bộ phân loại với merge gate); lỗi → None."""
        meta = github_read.read(["pr", "view", str(number), "--repo", self.repo, "--json",
                                 "labels,files,additions,deletions,changedFiles,body"], "metadata")[1]
        diff = github_read.read(["pr", "diff", str(number), "--repo", self.repo], "diff", meta)[1]
        with tempfile.TemporaryDirectory() as tmp:
            paths = {"meta": Path(tmp) / "meta.json", "diff": Path(tmp) / "pr.diff"}
            paths["meta"].write_text(json.dumps(meta))
            paths["diff"].write_text(diff)
            run = subprocess.run([sys.executable, str(Path(__file__).with_name("super-board-merge-policy.py")),
                                  "--config", config, "--meta", str(paths["meta"]), "--diff", str(paths["diff"])],
                                 capture_output=True, text=True, timeout=60)
        if run.returncode != 0:
            return None
        plan = json.loads(run.stdout)
        return plan if isinstance(plan, dict) else None

    def policy_cleared(self, number, config):
        """True when the CURRENT merge policy no longer asks a human about PR `number`.

        A card parked by an old `human-gate:` stays Blocked until someone types `done`; when the policy changed
        since (cap removed, category dropped), nobody should have to. Same reads and same classifier as the merge
        gate; only an empty `human` and `needs_you` counts. Anything unreadable stays "needs a human".
        """
        plan = self.plan_for(number, config)
        return plan is not None and not plan.get("human") and not plan.get("needs_you")

    def check(self, number, head=None, scope=None, issue=None, approved_head=None, cross_review_ok=False):
        current_head, issues = self.pr(number)
        if issue is not None and issue not in issues:
            return {"approved": False, "why": "request issue is not linked to this PR"}
        if head is not None and current_head != head:
            return {"approved": False, "headChanged": True, "why": "PR head changed after review"}
        comments = []
        for source in sorted(issues | {number}):
            comments.extend(self.comments(source))
        # #262: `head` là head merge gate vừa tự đẩy (gộp main sạch); duyệt gắn với head người đã duyệt (approved_head), đã chốt
        # trước khi gate đẩy. Head hiện tại khác `head` (có commit mới) thì đã bị chặn ở trên.
        expected = {"repo": self.repo, "pr": number, "head": approved_head or current_head}
        if scope is not None:
            expected["scope"] = scope
        def audited(task_id):
            # Chỉ gọi khi có marker duyệt chéo đọc được. Head PR chưa fetch về repo của board thì auditedHead không kiểm được:
            # fetch refs/pull/<n>/head trước (lỗi → không duyệt).
            if not self.top:
                return None
            audit_check.ensure_commit(self.top, expected["head"], number)
            return audit_check.audited(task_id, self.top)
        return validate(comments, expected, self.permission, cross_review_ok=cross_review_ok, audited=audited)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--repo-path", help="checkout của repo board (config repo.path) chứa biên bản audit; mặc định cwd")
    ap.add_argument("--pr", type=int)
    ap.add_argument("--head")
    ap.add_argument("--approved-head", help="head người đã duyệt khi --head là merge commit gate tự đẩy (#262)")
    ap.add_argument("--plan", help="JSON plan from merge-policy")
    ap.add_argument("--request", action="store_true", help="print a pinned request; no network or writes")
    ap.add_argument("--deps", action="store_true", help="enrich the dependency graph on stdin")
    ap.add_argument("--config", help="with --deps: re-run the merge policy; a card whose policy no longer asks a human is cleared")
    args = ap.parse_args()
    if args.request:
        if not args.pr or not args.head or not SHA.fullmatch(args.head) or not args.plan:
            ap.error("request requires --pr, full --head and --plan")
        print(marker(request_for(args.repo, args.pr, args.head, scope_for(json.loads(args.plan)))))
        return
    if args.deps:
        graph = json.load(sys.stdin)
        github = GitHub(args.repo, args.repo_path) if args.repo else None
        for entry in graph.values():
            entry["needsYouDone"] = False
            entry["approvalRefresh"] = False
            if not entry.get("needsYou") or github is None:
                continue
            try:
                comments = github.comments(entry["number"])
                blocks = trusted_blocks(comments, github.permission)
                latest = max(blocks, key=lambda c: timestamp(c.get("created_at"))) if blocks else {}
                request = parse_request(latest)
                if request is None or request["repo"] != github.repo:
                    continue
                result = github.check(request["pr"], head=request["head"], issue=entry["number"])
                # Identifies THIS approval (head + request comment) so the runner acts on it once, and on a later one again.
                entry["approvalKey"] = f"{request['head'][:12]}:{latest.get('id', '')}"
                entry["needsYouDone"] = result["approved"]
                entry["approvalRefresh"] = result.get("headChanged", False)
                entry["approvalWhy"] = result["why"]
                plan = (github.plan_for(request["pr"], args.config)
                        if args.config and not result["approved"] and not entry["approvalRefresh"] else None)
                if plan is not None and not plan.get("human") and not plan.get("needs_you"):
                    entry["needsYouDone"] = True
                    entry["approvalWhy"] = "policy cleared: the current merge policy no longer asks for a human"
                elif cross_review_allowed(plan):
                    # #605: marker duyệt chéo chỉ tính khi request ghim đúng scope của plan hiện tại; không --config = chỉ `done`.
                    crossed = github.check(request["pr"], head=request["head"], scope=scope_for(plan),
                                           issue=entry["number"], cross_review_ok=True)
                    if crossed["approved"]:
                        entry["needsYouDone"] = True
                        entry["approvalWhy"] = crossed["why"]
            except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError):
                entry["approvalWhy"] = "approval evidence could not be verified"
        print(json.dumps(graph))
        return
    if not args.pr or not args.head or not args.plan:
        ap.error("check requires --pr, --head and --plan")
    try:
        plan = json.loads(args.plan)
        result = GitHub(args.repo, args.repo_path).check(args.pr, args.head, scope_for(plan), approved_head=args.approved_head,
                                         cross_review_ok=cross_review_allowed(plan))
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError):
        result = {"approved": False, "why": "approval evidence could not be verified"}
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except github_read.ReadHalted as error:
        print(f"GitHub read halt: {error}", file=sys.stderr)
        sys.exit(github_read.HALTED)
