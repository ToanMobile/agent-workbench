#!/usr/bin/env python3
"""Quét hậu kiểm bảng super-board (#1406):
  1. Thẻ đóng `completed` còn AC `- [ ]` chưa tick và không có PR merged liên kết -> mở lại,
     gắn nhãn `ac-open`, comment lý do (nhắc tách con phải đóng `not_planned`), chuyển `Done` -> `Ready`.
  2. PR đã merge vào base trong 7 ngày qua không có biên nhận merge gate (`merge_receipts/`) ->
     cảnh báo MỘT lần lên thẻ liên kết (marker `<!-- sb-ungated-merge:PR#<P> -->`) và ghi tổng hợp theo ngày.
     Chỉ ghi nhận, không chặn.

  super-board-audit-sweep.py sweep --config <cfg> [--items FILE] [--days 7] [--dry-run]

Exit: 0 xong · 64 tham số sai · 69 ghi hỏng · 79 đọc hỏng.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None  # type: ignore

OK, USAGE, WRITE_FAILED, READ_FAILED = 0, 64, 69, 79
GH_TIMEOUT = 30
HERE = os.path.dirname(os.path.abspath(__file__))

# Quy tắc tách AC giống hệt super-board-ac-check.py để tránh lệch phân loại (INSTINCT-015).
AC_HEADING = re.compile(r"^##[ \t]+(?:Acceptance Criteria|AC)(?!\w)", re.I)
AC_ITEM = re.compile(r"^(?:[-*]|[0-9]{1,2}[.)])[ \t]+\S")
CHECKBOX = re.compile(r"^(?:[-*]|[0-9]{1,2}[.)])[ \t]*\[([ xX])\][ \t]*(.*)$")
# Cùng quy ước với CARD_FROM_BRANCH của super-board-ac-check.py (#1406 R4): `issue-<N>` có hoặc không hậu tố, có thể có tiền tố thư mục.
BRANCH_CARD_RE = re.compile(r"(?:^|/)issue-(\d+)(?:\D|$)")
FALLBACK_PR_LIMIT = 1000   # trần kết quả của GitHub search
UNGATED_MARKER_FMT = "<!-- sb-ungated-merge:PR#{pr} -->"
REOPEN_MARKER = "<!-- sb-sweep:reopen-ac-open -->"

ITEMS_QUERY = """
query($owner:String!, $number:Int!, $after:String) {
  repositoryOwner(login:$owner) {
    ... on ProjectV2Owner {
      projectV2(number:$number) {
        items(first:100, after:$after) {
          pageInfo { endCursor hasNextPage }
          nodes {
            id
            content { ... on Issue { number title repository{nameWithOwner} labels(first:20){nodes{name}} } }
            fieldValues(first:8) {
              nodes { ... on ProjectV2ItemFieldSingleSelectValue {
                name field { ... on ProjectV2SingleSelectField { name } } } }
            }
          }
        }
      }
    }
  }
}
"""


def run(cmd: list[str], cwd: str | None = None, timeout: int = GH_TIMEOUT) -> subprocess.CompletedProcess[str]:
    """Chạy lệnh ngoài với timeout tường minh, không nuốt lỗi spawn."""
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return subprocess.CompletedProcess(cmd, 127, "", str(exc))


def gh_cmd() -> list[str]:
    return shlex.split(os.environ.get("SB_GH") or "gh")


def card_cmd() -> list[str]:
    path = os.environ.get("SB_CARD") or os.path.join(HERE, "super-board-card.sh")
    return ["bash", path] if path.endswith(".sh") else [path]


def load_config(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return data if isinstance(data, dict) else {}


def repo_slug(cfg: dict, repo_path: str) -> str:
    remote = ((cfg.get("repo") or {}).get("remote")) or ""
    if not remote:
        r = run(["git", "remote", "get-url", "origin"], cwd=repo_path)
        remote = r.stdout.strip() if r.returncode == 0 else ""
    m = re.search(r"github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?$", remote.strip())
    return m.group(1) if m else ""


def resolve_repo_path(cfg: dict, config_path: str) -> str:
    p = (cfg.get("repo") or {}).get("path") or ""
    if isinstance(p, str) and os.path.isabs(p) and os.path.isdir(p):
        return p
    cfg_abs = os.path.abspath(config_path)
    guess = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(cfg_abs))))
    if os.path.isdir(os.path.join(guess, ".git")) or os.path.isfile(os.path.join(guess, ".git")):
        return guess
    return os.getcwd()


def git_common_dir(repo_path: str) -> str:
    r = run(["git", "-C", repo_path, "rev-parse", "--path-format=absolute", "--git-common-dir"])
    return r.stdout.strip() if r.returncode == 0 else ""


def unticked_acs(body: str) -> list[str]:
    """Trích các dòng `- [ ] ...` dưới heading Acceptance Criteria/AC cuối cùng (bỏ code fence)."""
    lines = (body or "").splitlines()
    heads = [i for i, ln in enumerate(lines) if AC_HEADING.match(ln)]
    if not heads:
        return []
    out: list[str] = []
    fence = False
    for ln in lines[heads[-1] + 1:]:
        if ln.lstrip().startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        if ln.startswith("## "):
            break
        if AC_ITEM.match(ln):
            m = CHECKBOX.match(ln.strip())
            if m and m.group(1) == " ":
                out.append(m.group(2).strip())
    return out


def label_names(raw_labels) -> set[str]:
    out: set[str] = set()
    for lb in raw_labels or []:
        name = lb.get("name") if isinstance(lb, dict) else lb
        if isinstance(name, str) and name:
            out.add(name.lower())
    return out


def parse_ts(text: str) -> dt.datetime | None:
    if not text:
        return None
    try:
        d = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
        return d if d.tzinfo else d.replace(tzinfo=dt.timezone.utc)
    except ValueError:
        return None


def tz_object(tz_name: str) -> dt.tzinfo:
    if tz_name and ZoneInfo is not None:
        try:
            return ZoneInfo(tz_name)
        except (KeyError, ValueError, OSError):
            pass
    return dt.timezone.utc


def valid_receipts(receipts_dir: str) -> list[dict]:
    """Đọc các file biên nhận merge gate hợp lệ trong thư mục merge_receipts."""
    out: list[dict] = []
    if not receipts_dir or not os.path.isdir(receipts_dir):
        return out
    try:
        names = sorted(os.listdir(receipts_dir))
    except OSError:
        return out
    for name in names:
        if not name.endswith(".json") or name.startswith("."):
            continue
        try:
            with open(os.path.join(receipts_dir, name), encoding="utf-8") as fh:
                rec = json.load(fh)
            if isinstance(rec, dict) and isinstance(rec.get("pr"), int):
                out.append(rec)
        except (OSError, ValueError):
            continue
    return out


def has_merge_receipt(pr: dict, receipts: list[dict]) -> bool:
    num = pr.get("number")
    head = pr.get("headRefOid") or ""
    squash = ((pr.get("mergeCommit") or {}).get("oid")) or ""
    for rec in receipts:
        if rec.get("pr") != num:
            continue
        if head and rec.get("head") == head:
            return True
        if squash and rec.get("squash") == squash:
            return True
    return False


def fetch_board_items(cfg: dict, slug: str, repo_path: str) -> dict[int, dict]:
    """Đọc thẻ trên ProjectV2 bằng một query GraphQL rút gọn khi không có --items."""
    proj = cfg.get("project") or {}
    owner, number = proj.get("owner"), proj.get("number")
    if not owner or not number:
        return {}
    gh = gh_cmd()
    home = slug.lower()
    items_by_num: dict[int, dict] = {}
    after: str | None = None
    for _ in range(20):
        cmd = gh + ["api", "graphql", "-f", f"query={ITEMS_QUERY}", "-F", f"owner={owner}", "-F", f"number={int(number)}"]
        if after:
            cmd += ["-F", f"after={after}"]
        r = run(cmd, cwd=repo_path)
        if r.returncode != 0:
            raise RuntimeError(f"graphql project items failed: {r.stderr.strip()[:200]}")
        payload = json.loads(r.stdout)
        if isinstance(payload, dict) and payload.get("errors"):
            raise RuntimeError(f"graphql errors: {str(payload['errors'])[:200]}")
        sec = (((payload.get("data") or {}).get("repositoryOwner") or {}).get("projectV2") or {}).get("items") or {}
        for node in sec.get("nodes") or []:
            c = node.get("content") or {}
            num = c.get("number")
            if not isinstance(num, int):
                continue
            card_repo = ((c.get("repository") or {}).get("nameWithOwner") or "").lower()
            if home and card_repo and card_repo != home:
                continue
            status = "Backlog"
            for fv in ((node.get("fieldValues") or {}).get("nodes") or []):
                if fv and (fv.get("field") or {}).get("name") == "Status":
                    status = fv.get("name") or "Backlog"
                    break
            items_by_num[num] = {
                "number": num,
                "status": status,
                "labels": [l["name"] for l in ((c.get("labels") or {}).get("nodes") or []) if l.get("name")],
            }
        pi = sec.get("pageInfo") or {}
        if not pi.get("hasNextPage") or not pi.get("endCursor"):
            break
        after = pi["endCursor"]
    return items_by_num


def parse_items_file(path: str, home: str = "") -> dict[int, dict]:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    home = home.lower()
    out: dict[int, dict] = {}
    for it in data.get("items") or []:
        c = it.get("content") or {}
        if c.get("type") != "Issue" or not isinstance(c.get("number"), int):
            continue
        # Thẻ của repo khác nằm chung board (#1406 R4): lọc như fetch_board_items. `repository` là "owner/repo"
        # (super-board-card.sh items), URL, hoặc object {nameWithOwner}; thiếu trường thì giữ thẻ.
        card_repo = c.get("repository")
        if isinstance(card_repo, dict):
            card_repo = card_repo.get("nameWithOwner")
        card_repo = re.sub(r"^.*github\.com[:/]", "", card_repo if isinstance(card_repo, str) else "").removesuffix(".git").strip("/").lower()
        if home and card_repo and card_repo != home:
            continue
        lbs = []
        for x in (it.get("labels") or []) + (c.get("labels") or []):
            name = x.get("name") if isinstance(x, dict) else x
            if isinstance(name, str) and name:
                lbs.append(name)
        out[int(c["number"])] = {
            "number": int(c["number"]),
            "status": it.get("status") or "Backlog",
            "labels": lbs,
        }
    return out


def atomic_write_json(path: str, obj) -> None:
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp_audit.", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(obj, fh, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def load_warned_ledger(path: str) -> set[str]:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, list):
            return {str(x) for x in data}
    except (OSError, ValueError):
        pass
    return set()


def issue_has_marker(gh: list[str], slug: str, issue_num: int, marker: str, repo_path: str) -> bool | None:
    """True nếu comment đã có marker, False nếu chưa, None nếu đọc GitHub lỗi."""
    r = run(gh + ["api", f"repos/{slug}/issues/{issue_num}/comments", "--paginate", "--slurp"], cwd=repo_path)
    if r.returncode != 0:
        return None
    try:
        pages = json.loads(r.stdout)
    except ValueError:
        return None
    for page in pages if isinstance(pages, list) else []:
        for c in page if isinstance(page, list) else []:
            if isinstance(c, dict) and marker in (c.get("body") or ""):
                return True
    return False


def post_comment(gh: list[str], slug: str, issue_num: int, body: str, repo_path: str) -> bool:
    """Ghi comment qua file tạm (--body-file) để tránh lỗi shell/kích thước."""
    fd, tmp = tempfile.mkstemp(prefix="sb_cmt_")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(body)
        r = run(gh + ["issue", "comment", str(issue_num), "--repo", slug, "--body-file", tmp], cwd=repo_path)
        return r.returncode == 0
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def linked_issues_of_pr(pr: dict) -> list[int]:
    nums: set[int] = set()
    for ref in pr.get("closingIssuesReferences") or []:
        if isinstance(ref, dict) and isinstance(ref.get("number"), int):
            nums.add(int(ref["number"]))
    m = BRANCH_CARD_RE.search(pr.get("headRefName") or "")
    if m:
        nums.add(int(m.group(1)))
    return sorted(nums)


def sweep(args: argparse.Namespace) -> int:
    try:
        cfg = load_config(args.config)
    except (OSError, ValueError) as exc:
        print(f"audit-sweep: cannot load config {args.config}: {exc}", file=sys.stderr)
        return USAGE

    repo_path = resolve_repo_path(cfg, args.config)
    slug = repo_slug(cfg, repo_path)
    if not slug:
        print("audit-sweep: repo remote missing", file=sys.stderr)
        return USAGE

    base = cfg.get("base_branch") or "main"
    tz = tz_object(cfg.get("timezone") or "UTC")
    gh = gh_cmd()

    try:
        board = parse_items_file(args.items, slug) if args.items else fetch_board_items(cfg, slug, repo_path)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"audit-sweep: cannot read board items: {exc}", file=sys.stderr)
        return READ_FAILED

    # 1 lần đọc danh sách PR merged gần nhất dùng chung cho cả Phần 1 (kiểm PR liên kết) và Phần 2 (ngoài gate).
    pr_limit = max(200, int(args.issue_limit))
    pr_fields = "number,title,headRefName,headRefOid,baseRefName,mergeCommit,mergedAt,closingIssuesReferences,url"
    r_pr = run(gh + ["pr", "list", "--repo", slug, "--state", "merged", "--base", base, "--limit", str(pr_limit), "--json", pr_fields],
               cwd=repo_path)
    if r_pr.returncode != 0:
        print(f"audit-sweep: gh pr list failed: {r_pr.stderr.strip()[:200]}", file=sys.stderr)
        return READ_FAILED
    try:
        merged_prs = json.loads(r_pr.stdout)
        if not isinstance(merged_prs, list):
            raise ValueError("not a list")
    except ValueError:
        print("audit-sweep: gh pr list invalid JSON", file=sys.stderr)
        return READ_FAILED

    issue_fields = "number,title,stateReason,body,labels,closedAt,closedByPullRequestsReferences"
    r_iss = run(gh + ["issue", "list", "--repo", slug, "--state", "closed", "--search", "sort:updated-desc",
                      "--limit", str(args.issue_limit), "--json", issue_fields], cwd=repo_path)
    if r_iss.returncode != 0:
        print(f"audit-sweep: gh issue list failed: {r_iss.stderr.strip()[:200]}", file=sys.stderr)
        return READ_FAILED
    try:
        closed_issues = json.loads(r_iss.stdout)
        if not isinstance(closed_issues, list):
            raise ValueError("not a list")
    except ValueError:
        print("audit-sweep: gh issue list invalid JSON", file=sys.stderr)
        return READ_FAILED

    # Map số thẻ -> danh sách PR merged có liên kết (closingIssuesReferences hoặc nhánh issue-<N>-).
    merged_prs_by_issue: dict[int, list[int]] = {}
    for pr in merged_prs:
        if not isinstance(pr, dict) or not isinstance(pr.get("number"), int):
            continue
        for inum in linked_issues_of_pr(pr):
            merged_prs_by_issue.setdefault(inum, []).append(int(pr["number"]))

    # ── Phần 1: Thẻ đóng COMPLETED còn AC `- [ ]` chưa tick và không có PR merged liên kết ──
    reopened: list[int] = []
    moved_ready: list[int] = []
    label_ensured = False
    write_err = False

    for iss in closed_issues:
        if not isinstance(iss, dict):
            continue
        num = iss.get("number")
        if not isinstance(num, int) or num not in board:
            continue
        if iss.get("stateReason") != "COMPLETED":
            continue
        card_info = board[num]
        lbs = label_names(iss.get("labels")) | label_names(card_info.get("labels"))
        has_ac_open = "ac-open" in lbs
        unticked = unticked_acs(iss.get("body") or "")
        has_closed_by_pr = bool(iss.get("closedByPullRequestsReferences")) or bool(merged_prs_by_issue.get(num))
        # Nếu bulk PR list chưa thấy PR cho thẻ, kiểm trực tiếp nhánh issue-<N>- trước khi mở lại để tránh cắt đuôi khi >200 PR.
        if not has_ac_open and unticked and not has_closed_by_pr:
            # `head:issue-<N>` của GitHub search khớp theo tiền tố (issue-14 trả cả issue-1405…, mới nhất trước, #1416 review): đọc tới
            # trần 1000 của search, lọc đúng số thẻ bằng BRANCH_CARD_RE; chạm trần mà chưa thấy thì không chứng minh được là không có PR.
            r_one = run(gh + ["pr", "list", "--repo", slug, "--state", "merged", "--base", base,
                              "--search", f"head:issue-{num}", "--limit", str(FALLBACK_PR_LIMIT), "--json", "number,headRefName"],
                        cwd=repo_path)
            if r_one.returncode != 0:
                print(f"audit-sweep: fallback gh pr list for #{num} failed; skipping reopen", file=sys.stderr)
                continue
            try:
                one_prs = json.loads(r_one.stdout)
                if any(isinstance(p, dict) and (m_one := BRANCH_CARD_RE.search(p.get("headRefName") or ""))
                       and int(m_one.group(1)) == num for p in one_prs):
                    has_closed_by_pr = True
                elif isinstance(one_prs, list) and len(one_prs) >= FALLBACK_PR_LIMIT:
                    print(f"audit-sweep: fallback search for #{num} hit --limit {FALLBACK_PR_LIMIT} without its branch; skipping reopen",
                          file=sys.stderr)
                    continue
            except (ValueError, TypeError):
                print(f"audit-sweep: fallback gh pr list invalid JSON for #{num}; skipping reopen", file=sys.stderr)
                continue

        # Mở lại nếu: (a) mang nhãn ac-open mà đóng COMPLETED (kể cả đang ở Done),
        # hoặc (b) body còn AC `- [ ]` chưa tick và không có PR merged liên kết.
        if not has_ac_open and not (unticked and not has_closed_by_pr):
            continue

        if args.dry_run:
            reopened.append(num)
            if card_info.get("status") == "Done":
                moved_ready.append(num)
            continue

        if not has_ac_open:
            if not label_ensured:
                run(gh + ["label", "create", "ac-open", "--repo", slug, "--color", "FBCA04",
                          "--description", "PR merged, acceptance criteria not all proven"], cwd=repo_path)
                label_ensured = True
            ed = run(gh + ["issue", "edit", str(num), "--repo", slug, "--add-label", "ac-open"], cwd=repo_path)
            if ed.returncode != 0:
                print(f"audit-sweep: failed to label ac-open on #{num}: {ed.stderr.strip()[:200]}", file=sys.stderr)
                write_err = True
                continue

        # Chuyển Done -> Ready TRƯỚC khi reopen để nếu move hỏng thì thẻ vẫn CLOSED (lượt sau quét lại, không kẹt OPEN ở Done).
        if card_info.get("status") == "Done":
            mv = run(card_cmd() + ["--config", args.config, "move", str(num), "Ready"], cwd=repo_path)
            if mv.returncode == 0:
                moved_ready.append(num)
            else:
                print(f"audit-sweep: failed to move #{num} Done -> Ready: {mv.stderr.strip()[:200]}", file=sys.stderr)
                write_err = True
                continue

        re = run(gh + ["issue", "reopen", str(num), "--repo", slug], cwd=repo_path)
        if re.returncode != 0:
            print(f"audit-sweep: failed to reopen #{num}: {re.stderr.strip()[:200]}", file=sys.stderr)
            write_err = True
            continue

        reopened.append(num)
        preview = "\n".join(f"- [ ] {x}" for x in unticked[:5])
        if len(unticked) > 5:
            preview += f"\n- ... (+{len(unticked) - 5} mục khác)"
        reason_line = (
            f"kiểm tra thẻ đóng `completed` còn {len(unticked)} mục AC `- [ ]` chưa tick và không có PR merged liên kết"
            if unticked else
            "thẻ mang nhãn `ac-open` (còn tiêu chí chưa chứng minh) nhưng bị đóng `completed`"
        )
        cmt = (
            f"{REOPEN_MARKER}\n"
            f"[orchestrator] [report] ↩️ mở lại thẻ · gắn `ac-open`\n"
            f"Did: {reason_line}\n"
            f"❌ Not done:\n{preview or '- [ ] AC chưa được chứng minh đủ'}\n"
            f"Next: chứng minh đủ AC qua PR, hoặc nếu tách thẻ con thì đóng `not_planned` kèm danh sách thẻ con"
        )
        if not post_comment(gh, slug, num, cmt, repo_path):
            print(f"audit-sweep: reopened #{num} but comment failed", file=sys.stderr)

    # Phòng ngừa: thẻ đã OPEN mang nhãn ac-open nhưng còn sót ở Done -> đưa về Ready (xác nhận state == OPEN vì closed_issues chỉ lấy 200 thẻ mới nhất)
    closed_nums = {iss.get("number") for iss in closed_issues if isinstance(iss, dict)}
    for num, card_info in board.items():
        if card_info.get("status") != "Done" or num in closed_nums or num in moved_ready:
            continue
        if "ac-open" not in label_names(card_info.get("labels")):
            continue
        r_st = run(gh + ["issue", "view", str(num), "--repo", slug, "--json", "state", "-q", ".state"], cwd=repo_path)
        if r_st.returncode != 0 or r_st.stdout.strip() != "OPEN":
            continue
        if args.dry_run:
            moved_ready.append(num)
            continue
        mv = run(card_cmd() + ["--config", args.config, "move", str(num), "Ready"], cwd=repo_path)
        if mv.returncode == 0:
            moved_ready.append(num)
        else:
            print(f"audit-sweep: failed to move open ac-open #{num} Done -> Ready: {mv.stderr.strip()[:200]}", file=sys.stderr)
            write_err = True

    # ── Phần 2: PR vào trunk trong N ngày qua không có biên nhận merge gate ──
    common = git_common_dir(repo_path)
    receipts_dir = os.path.join(common, "postfix-gate", "merge_receipts") if common else ""
    receipts = valid_receipts(receipts_dir)
    ledger_path = os.path.join(common, "super-board", "ungated-merges-warned.json") if common else ""
    warned_ledger = load_warned_ledger(ledger_path) if ledger_path else set()
    ledger_changed = False

    now = dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(days=args.days)

    ungated_by_date: dict[str, int] = {}
    ungated_prs: list[dict] = []
    warned_issues: list[int] = []

    for pr in merged_prs:
        if not isinstance(pr, dict) or not isinstance(pr.get("number"), int):
            continue
        if (pr.get("baseRefName") or base) != base:
            continue
        m_dt = parse_ts(pr.get("mergedAt") or "")
        if m_dt is None or m_dt < cutoff:
            continue
        if has_merge_receipt(pr, receipts):
            continue

        local_dt = m_dt.astimezone(tz)
        day_key = local_dt.strftime("%Y-%m-%d")
        ungated_by_date[day_key] = ungated_by_date.get(day_key, 0) + 1
        pr_num = int(pr["number"])
        head_oid = pr.get("headRefOid") or ""
        issues = linked_issues_of_pr(pr)
        ungated_prs.append({
            "pr": pr_num,
            "date": day_key,
            "mergedAt": pr.get("mergedAt"),
            "headRefName": pr.get("headRefName") or "",
            "issues": issues,
        })

        marker = UNGATED_MARKER_FMT.format(pr=pr_num)
        for inum in issues:
            key = f"{pr_num}:{head_oid}:{inum}"
            if key in warned_ledger:
                continue
            has_m = issue_has_marker(gh, slug, inum, marker, repo_path)
            if has_m is None:
                continue
            if has_m:
                warned_ledger.add(key)
                ledger_changed = True
                continue
            if args.dry_run:
                warned_issues.append(inum)
                continue
            cmt = (
                f"{marker}\n"
                f"[orchestrator] [report] ⚠️ merge ngoài gate · PR #{pr_num}\n"
                f"Did: sweep phát hiện PR #{pr_num} (`{pr.get('headRefName') or '-'}`, merge lúc {local_dt.strftime('%Y-%m-%d %H:%M')}) vào `{base}` không có biên nhận merge gate\n"
                f"Next: chỉ ghi nhận vào báo cáo board theo ngày (không chặn quyền merge của chủ repo)"
            )
            if post_comment(gh, slug, inum, cmt, repo_path):
                warned_issues.append(inum)
                warned_ledger.add(key)
                ledger_changed = True
            else:
                print(f"audit-sweep: failed to warn #{inum} for PR #{pr_num}", file=sys.stderr)
                write_err = True

    if ledger_changed and ledger_path and not args.dry_run:
        atomic_write_json(ledger_path, sorted(warned_ledger))

    summary_obj = {
        "checked_at": now.isoformat(timespec="seconds"),
        "window_days": args.days,
        "base": base,
        "reopened": reopened,
        "moved_ready": moved_ready,
        "ungated_total_7d": len(ungated_prs),
        "ungated_by_date": dict(sorted(ungated_by_date.items())),
        "ungated_prs": ungated_prs,
        "warned_issues": warned_issues,
    }
    if common and not args.dry_run:
        atomic_write_json(os.path.join(common, "super-board", "ungated-merges.json"), summary_obj)

    print(json.dumps(summary_obj, ensure_ascii=False))
    return WRITE_FAILED if write_err else OK


def main() -> int:
    ap = argparse.ArgumentParser(description="Quét hậu kiểm thẻ đóng completed và PR merge ngoài gate")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("sweep")
    sp.add_argument("--config", required=True)
    sp.add_argument("--items")
    sp.add_argument("--days", type=int, default=7)
    sp.add_argument("--issue-limit", type=int, default=200)
    sp.add_argument("--dry-run", action="store_true")
    try:
        args = ap.parse_args()
    except SystemExit as exc:
        return USAGE if exc.code else OK
    return sweep(args)


if __name__ == "__main__":
    sys.exit(main())
