#!/usr/bin/env python3
"""Đóng thẻ `session` của phiên chat đã chết (#1193).

  super-board-session-sweep.py sweep --config C [--items FILE]

hooks/session_card.sh đặt mỗi task chat một thẻ nhãn `session` ở Building; PR của phiên đóng nó bằng `Closes #N`. Phiên chết
không PR thì thẻ kẹt mãi (sweep_closed_cards chỉ chuyển thẻ có issue đã ĐÓNG). Helper này đóng issue đó (completed + một
comment lý do); sweep_closed_cards của runner đưa nó về Done ở tick kế.

Thẻ bị đóng chỉ khi đủ cả bốn: nhãn `session`, chưa Done, KHÔNG có PR mở nào `Closes #N`, và phiên đã chết = marker
`<!-- sb:session SID -->` trong body, không tiến trình nào mang SID trong dòng lệnh, và hoạt động cuối (mtime transcript
`<claude dir>/projects/*/SID.jsonl`; không thấy transcript thì `updatedAt` của issue) cách đây hơn SB_SESSION_DEAD_HOURS (6) giờ.
Không đọc được gì (issue, danh sách PR) thì không đóng gì: exit 79.

--items FILE: board đã đọc sẵn (JSON của `super-board-card.sh items`), runner truyền cache.
Env: SB_GH (mặc định gh), SB_SESSION_DEAD_HOURS, SB_SESSION_TRANSCRIPT_GLOBS (danh sách glob cách nhau bằng `:`, `{sid}` được
thay; mặc định ~/.claude*/projects/*/{sid}.jsonl), SB_SESSION_PGREP (mặc định pgrep).
Exit: 0 xong · 64 tham số sai · 69 ghi hỏng · 79 đọc hỏng. In {"closed":[N],"kept":[[N,lý do]]}.
"""
import argparse
import datetime
import glob
import json
import os
import re
import shlex
import subprocess
import sys

OK, USAGE, WRITE_FAILED, READ_FAILED = 0, 64, 69, 79
GH_TIMEOUT = 30
SID_RE = re.compile(r"<!--\s*sb:session\s+([A-Za-z0-9][A-Za-z0-9._-]*)\s*-->")
CLOSES_RE = r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+#{n}\b"


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=GH_TIMEOUT)
    except (OSError, subprocess.SubprocessError) as exc:
        return subprocess.CompletedProcess(cmd, 127, "", str(exc))


def gh_cmd():
    return shlex.split(os.environ.get("SB_GH") or "gh")


def repo_slug(config):
    with open(config, encoding="utf-8") as fh:
        remote = (json.load(fh).get("repo") or {}).get("remote") or ""
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", remote)
    return m.group(1) if m else ""


def label_names(item):
    content = item.get("content") or {}
    raw = (item.get("labels") or []) + (content.get("labels") or [])
    return {(x.get("name") if isinstance(x, dict) else x) for x in raw}


def session_cards(items):
    for it in items.get("items", []):
        content = it.get("content") or {}
        if content.get("type") == "Issue" and it.get("status") != "Done" and "session" in label_names(it):
            yield int(content["number"])


def transcript_mtime(sid):
    globs = os.environ.get("SB_SESSION_TRANSCRIPT_GLOBS") or os.path.expanduser("~/.claude*/projects/*/{sid}.jsonl")
    times = []
    for pat in globs.split(":"):
        for path in glob.glob(pat.replace("{sid}", sid)):
            try:
                times.append(os.path.getmtime(path))
            except OSError:
                pass
    return max(times) if times else None


def process_alive(sid):
    pg = shlex.split(os.environ.get("SB_SESSION_PGREP") or "pgrep")
    return run(pg + ["-f", sid]).returncode == 0


def parse_ts(text):
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()


def sweep(args):
    slug = repo_slug(args.config)
    if not slug:
        print("session-sweep: no repo remote in config", file=sys.stderr)
        return USAGE
    with open(args.items, encoding="utf-8") if args.items else sys.stdin as fh:
        numbers = list(session_cards(json.load(fh)))
    out = {"closed": [], "kept": []}
    if not numbers:
        print(json.dumps(out))
        return OK
    gh = gh_cmd()
    hours = float(os.environ.get("SB_SESSION_DEAD_HOURS") or 6)
    now = datetime.datetime.now(datetime.timezone.utc).timestamp()
    r = run(gh + ["pr", "list", "--repo", slug, "--state", "open", "--limit", "200", "--json", "number,body"])
    if r.returncode != 0:
        print(f"session-sweep: gh pr list failed: {r.stderr.strip()[:200]}", file=sys.stderr)
        return READ_FAILED
    try:
        open_prs = json.loads(r.stdout)
    except ValueError:
        print("session-sweep: gh pr list returned no JSON", file=sys.stderr)
        return READ_FAILED
    rc = OK
    for n in numbers:
        r = run(gh + ["issue", "view", str(n), "--repo", slug, "--json", "body,updatedAt,state"])
        try:
            issue = json.loads(r.stdout) if r.returncode == 0 else None
        except ValueError:
            issue = None
        if not isinstance(issue, dict):
            print(f"session-sweep: gh issue view #{n} unreadable", file=sys.stderr)
            rc = READ_FAILED
            continue
        m = SID_RE.search(issue.get("body") or "")
        if issue.get("state") != "OPEN" or not m:
            out["kept"].append([n, "closed or no session marker"])
            continue
        sid = m.group(1)
        if any(re.search(CLOSES_RE.format(n=n), p.get("body") or "", re.I) for p in open_prs):
            out["kept"].append([n, "open PR closes it"])
            continue
        if process_alive(sid):
            out["kept"].append([n, "session process alive"])
            continue
        try:
            last = transcript_mtime(sid) or parse_ts(issue["updatedAt"])
        except (KeyError, ValueError):
            out["kept"].append([n, "no activity time"])
            continue
        idle_h = (now - last) / 3600
        if idle_h <= hours:
            out["kept"].append([n, f"idle {idle_h:.1f} h <= {hours:g} h"])
            continue
        body = (f"[orchestrator] [report] 🧹 session ended · closing\nDid: session {sid[:8]} idle {idle_h:.1f} h "
                f"(> {hours:g} h), no live process, no open PR with `Closes #{n}`\n✅ Done: issue closed, sweep moves the card to Done\nNext: -")
        w = run(gh + ["issue", "close", str(n), "--repo", slug, "--reason", "completed", "--comment", body])
        if w.returncode != 0:
            print(f"session-sweep: gh issue close #{n} failed: {w.stderr.strip()[:200]}", file=sys.stderr)
            rc = WRITE_FAILED
            continue
        out["closed"].append(n)
    print(json.dumps(out))
    return rc


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("sweep")
    sp.add_argument("--config", required=True)
    sp.add_argument("--items")
    try:
        args = ap.parse_args()
    except SystemExit as exc:
        return USAGE if exc.code else OK
    return sweep(args)


if __name__ == "__main__":
    sys.exit(main())
