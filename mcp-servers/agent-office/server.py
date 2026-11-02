#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Agent Office: xưởng 3D theo dõi GitHub Project và các agent super-board đang chạy.

    python3 server.py            # mở http://127.0.0.1:4317
    python3 server.py --demo     # dữ liệu mẫu, không cần gh
    python3 server.py --open     # tự mở trình duyệt

Chỉ dùng thư viện chuẩn Python 3.8+. Nguồn dữ liệu:
  1. GitHub Project v2 (qua `gh api graphql`, dùng tài khoản gh đã đăng nhập)
  2. Transcript Claude Code trong ~/.claude/projects (agent đang nói gì, chạy lệnh gì)
  3. Dòng "[RUNNER] ... tick" của super-board (trong transcript, manifest hoặc file log)
"""
from __future__ import annotations

import argparse
import glob
import gzip
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time

try:
    import fcntl  # chỉ dùng để dò khoá việc nặng cho bảng chỉ số; máy không có fcntl thì bảng báo 0 khoá
except ImportError:  # pragma: no cover - Windows
    fcntl = None
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import gate_full_runner  # cùng thư mục: nút "Chạy gate full" (hàng đợi, khoá toàn máy, lệnh lấy từ plist lịch đêm)
import inbox_hook  # cùng thư mục: hook hộp thư lệnh, cờ --settings và system prompt dùng chung với runner

HERE = os.path.dirname(os.path.abspath(__file__))
WEB_DIR = os.path.join(HERE, "web")

DEFAULTS = {
    "github": {
        "owner": "ToanMobile",
        "ownerType": "user",
        "project": 1,
        "view": 2,
        "maxItems": 600,
        "includeArchived": False,
    },
    "root": "/Volumes/Data/Toan",
    "repos": ["agent-workbench", "GeelyEx2", "OfficeReader", "Goods-Triple", "Idle-Plaza"],
    "repoPaths": {},
    "claudeProjectsDir": "~/.claude/projects",
    "runnerLogGlobs": ["~/.agent-office/logs/*.log"],
    "activeMinutes": 10,
    "lookbackMinutes": 240,
    "githubSeconds": 30,
    "localSeconds": 3,
    "host": "127.0.0.1",
    "allowedHosts": ["ai-factory.test", "ai-factory.localhost"],
    "port": 4317,
    "eventsFile": "~/.agent-office/events.jsonl",
    "macNotify": True,
}

NO_STATUS = "Chưa có trạng thái"
BACKFILL_PER_POLL = 5   # thẻ chưa có Status được đặt Backlog mỗi lần đọc board (mỗi lần ghi là một lệnh gh)
MOVE_ALL_MAX = 100      # thẻ tối đa cho một lần "chuyển tất cả"

KIND_RULES = [
    ("blocked", r"block|chặn|stuck|on hold"),
    ("done", r"done|xong|closed|merged|hoàn thành|shipped|released"),
    ("review", r"review|duyệt"),
    ("qa", r"\bqa\b|test|kiểm thử|verify"),
    ("building", r"build|progress|doing|đang làm|\bdev\b|wip|implement"),
    ("ready", r"ready|todo|to do|sẵn sàng|next|selected"),
    ("backlog", r"backlog|idea|inbox|triage|\bnew\b|chưa có"),
]
LANE_KIND = {"b": "building", "q": "qa", "r": "review"}
LANE_LABEL = {"b": "Build", "q": "QA", "r": "Review"}
LANE_KEY_OF = {"build": "b", "building": "b", "qa": "q", "test": "q", "review": "r"}

TICK_RE = re.compile(
    r"\[RUNNER\]\s*\[(\d{1,2}:\d{2}:\d{2})\]\s*tick\s*[\u2013\u2014-]\s*(.*?)waiting_on_you\s*=\s*(\d+)", re.S
)
COUNT_RE = re.compile(r"([A-Za-z][A-Za-z _]*?)\s*=\s*(\d+)")  # cho phép tên cột có dấu cách, vd "In Progress"
LANE_RE = re.compile(r"\b([a-z])_idle\s*=\s*(\d)\s*\(\s*#?\s*([^)\s]*)\s*\)")
TOKENS_RE = re.compile(r"<total_tokens>\s*(\d+)\s*tokens left", re.I)
FINISH_RE = re.compile(r"exiting cleanly|super-board run finished", re.I)
MANIFEST_RE = re.compile(r"manifest:\s*(\S+\.md)")
ISSUE_LANE_RE = re.compile(r"issue[-_](\d+)[-_](build|qa|review|test)\b", re.I)
ISSUE_PATH_RE = re.compile(r"issue[-_/]?(\d+)", re.I)
HASH_RE = re.compile(r"#(\d{1,6})\b")


# ----------------------------------------------------------------- helpers
def now() -> float:
    return time.time()


def expand(p: str) -> str:
    return os.path.abspath(os.path.expanduser(p)) if p else p


def deep_merge(base: dict, extra: dict) -> dict:
    out = dict(base)
    for k, v in (extra or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def parse_iso(s):
    if not s or not isinstance(s, str):
        return None
    s = s.strip().replace("Z", "+00:00")
    m = re.match(r"^(.*?T\d{2}:\d{2}:\d{2})(\.\d+)?(.*)$", s)
    if m:  # chuẩn hoá phần thập phân về 6 chữ số cho Python < 3.11
        frac = (m.group(2) or "")[1:7].ljust(6, "0") if m.group(2) else ""
        s = m.group(1) + ("." + frac if frac else "") + (m.group(3) or "")
    try:
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    except ValueError:
        return None


def column_kind(name: str) -> str:
    low = (name or "").lower()
    for kind, pat in KIND_RULES:
        if re.search(pat, low):
            return kind
    return "other"


def encode_path(p: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", p)


def tail_text(path: str, limit: int) -> str:
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        if size > limit:
            f.seek(size - limit)
            f.readline()
        return f.read().decode("utf-8", errors="replace")


def iter_strings(o):
    if isinstance(o, str):
        yield o
    elif isinstance(o, dict):
        for v in o.values():
            yield from iter_strings(v)
    elif isinstance(o, list):
        for v in o:
            yield from iter_strings(v)


def tick_epoch(time_s: str, ref_ts: float) -> float:
    """Tick chỉ có HH:MM:SS; ghép với ngày của mốc tham chiếu (giờ máy)."""
    ref = datetime.fromtimestamp(ref_ts)
    h, m, s = (int(x) for x in time_s.split(":"))
    dt = ref.replace(hour=h, minute=m, second=s, microsecond=0)
    if dt.timestamp() > ref_ts + 120:
        dt -= timedelta(days=1)
    return dt.timestamp()


def parse_ticks(text: str, ref_ts: float):
    ticks = []
    for m in TICK_RE.finditer(text):
        time_s, middle, waiting = m.groups()
        before, _, lanes_part = middle.partition("lanes:")
        counts = {}
        for k, v in COUNT_RE.findall(before):
            counts[k.strip()] = int(v)
        lanes = {}
        for key, idle, card in LANE_RE.findall(lanes_part or middle):
            lanes[key] = {"idle": idle == "1", "card": card if card and card != "_" else None}
        ticks.append({
            "time": time_s, "at": tick_epoch(time_s, ref_ts), "counts": counts,
            "lanes": lanes, "waiting": int(waiting), "pos": m.end(),
        })
    return ticks


# Bounded repeats and a left boundary keep the key-name branch linear on long \w runs.
_KEY = r"(?<![\w-])[\w-]{0,30}?(?:token|secret|passw(?:or)?d|pwd|api[_-]?key|key|auth|credential|private)[\w-]{0,30}"
SECRET_RE = re.compile("|".join([
    r"gh[pousr]_[A-Za-z0-9]{20,}", r"github_pat_[A-Za-z0-9_]{20,}", r"(?<![\w-])sk-[A-Za-z0-9_-]{16,}",
    r"\bAKIA[0-9A-Z]{16}\b", r"\bxox[abposr]-[A-Za-z0-9-]{10,}", r"\beyJ[\w-]{5,}\.eyJ[\w-]{5,}\.[\w-]+",
    r"-----BEGIN[^-]*PRIVATE KEY-----[\s\S]*?(?:-----END[^-]*-----|$)",
    r"(?i:authorization:?\s*basic)\s+\S+", r"(?i:bearer)\s+[A-Za-z0-9._~+/=-]{8,}",
    r"(?i:--?(?:token|password|passwd|api-key|secret|pass))[\s=]+(?:\"[^\"]*\"|'[^']*'|\S+)",
    r"(?i:" + _KEY + r")[\"']?\s*[=:]\s*(?:\"[^\"]*\"|'[^']*'|[^\s\"']{8,})",
    r"(?<=://)[^/\s:@]+:[^@\s]+(?=@)",
]))


def redact(text: str) -> str:
    """Transcripts hold whatever the user typed; never serve credentials from /api/state."""
    return SECRET_RE.sub("***", text)


def tool_summary(name, inp) -> str:
    if not isinstance(inp, dict):
        return ""
    for key in ("command", "file_path", "notebook_path", "path", "pattern", "url", "query", "description", "prompt"):
        v = inp.get(key)
        if isinstance(v, str) and v.strip():
            return redact(v.strip())[:600]  # redact first: a secret straddling the cut must still match
    try:
        return redact(json.dumps(inp, ensure_ascii=False))[:300]
    except (TypeError, ValueError):
        return ""


def find_gh():
    gh = shutil.which("gh")
    if gh:
        return gh
    for c in ("/opt/homebrew/bin/gh", "/usr/local/bin/gh"):
        if os.path.exists(c):
            return c
    return None


# ----------------------------------------------------------------- GitHub
FIELD_FRAG = """
      ... on ProjectV2SingleSelectField { id name dataType options { id name color } }
      ... on ProjectV2Field { id name dataType }
      ... on ProjectV2IterationField { id name dataType }
"""
FC = "field { ... on ProjectV2FieldCommon { name } }"
PROJECT_QUERY = """
query($login: String!, $number: Int!, $cursor: String%VIEWVAR%) {
  %OWNER%(login: $login) {
    projectV2(number: $number) {
      id title url
      %VIEWBLOCK%
      fields(first: 50) { nodes { %FIELD% } }
      items(first: 100, after: $cursor) {
        totalCount
        pageInfo { hasNextPage endCursor }
        nodes {
          id isArchived type updatedAt
          fieldValues(first: 40) { nodes {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name %FC% }
            ... on ProjectV2ItemFieldTextValue { text %FC% }
            ... on ProjectV2ItemFieldNumberValue { number %FC% }
            ... on ProjectV2ItemFieldDateValue { date %FC% }
            ... on ProjectV2ItemFieldIterationValue { title %FC% }
          } }
          content {
            __typename
            ... on Issue { id number title url state updatedAt repository { name nameWithOwner }
              assignees(first: 6) { nodes { login } } labels(first: 12) { nodes { name color } } comments(last: 1) { nodes { body createdAt author { login } } } }
            ... on PullRequest { id number title url state isDraft updatedAt repository { name nameWithOwner }
              assignees(first: 6) { nodes { login } } labels(first: 12) { nodes { name color } } comments(last: 1) { nodes { body createdAt author { login } } } }
            ... on DraftIssue { id title updatedAt }
          }
        }
      }
    }
  }
}
"""
VIEW_BLOCK = """view(number: $view) { name layout filter
        verticalGroupByFields(first: 3) { nodes { %FIELD% } }
        groupByFields(first: 3) { nodes { %FIELD% } } }"""


def models_version(web_dir=WEB_DIR) -> str:
    """Fingerprint of web/models (name, size, mtime of each file): the page appends it to model URLs so a rebuilt
    GLB is never served from the browser's one-day cache, even when a copy keeps the old mtime."""
    d = os.path.join(web_dir, "models")
    try:
        h = hashlib.sha1()
        for f in sorted(os.listdir(d)):
            st = os.stat(os.path.join(d, f))
            h.update(f"{f}|{st.st_size}|{st.st_mtime_ns}\n".encode())
        return h.hexdigest()[:12]
    except OSError as e:
        warn("models_version", e)
        return "0"


def fill_models_version(page: bytes, version: str) -> bytes:
    return page.replace(b"__MODELS_V__", version.encode())


def gzip_ok(accept_encoding) -> bool:
    """Trình duyệt nhận gzip không (Accept-Encoding: gzip, không phải gzip;q=0)."""
    for part in (accept_encoding or "").lower().split(","):
        name, _, q = part.strip().partition(";")
        if name.strip() in ("gzip", "*"):
            q = q.strip()
            return not (q.startswith("q=") and q[2:].strip() in ("0", "0.0", "0.00", "0.000"))
    return False


class GzipCache:
    """Bản gzip của /api/state: nén một lần cho mỗi lần dựng (state_bytes mới), mọi lần hỏi sau dùng lại.
    /api/state thật ~400 KB JSON mỗi 3 giây (điện thoại qua tunnel tải chừng ấy mỗi lần); nén còn ~1/4."""
    MIN = 1024

    def __init__(self):
        self._src, self._gz = None, None
        self.lock = threading.Lock()

    def get(self, body: bytes) -> bytes:
        with self.lock:
            if self._src is body:
                return self._gz
        gz = gzip.compress(body, compresslevel=6, mtime=0)  # nén ngoài khoá: hai lần hỏi cùng lúc cùng lắm nén hai lần
        with self.lock:
            self._src, self._gz = body, gz
        return gz


def warn(context, err) -> None:
    print(f"[agent-office] {context}: {err}", file=sys.stderr, flush=True)


class GhError(RuntimeError):
    pass


def gh_graphql(query: str, variables: dict) -> dict:
    gh = find_gh()
    if not gh:
        raise GhError("NO_GH")
    args = [gh, "api", "graphql", "-f", "query=" + query]
    for k, v in variables.items():
        if v is None:
            continue
        args += (["-F", f"{k}={v}"] if isinstance(v, int) else ["-f", f"{k}={v}"])
    p = subprocess.run(args, capture_output=True, text=True, timeout=90)
    data = None
    try:
        data = json.loads(p.stdout) if p.stdout.strip() else None
    except ValueError:
        data = None
    if data and data.get("errors"):
        raise GhError("; ".join(e.get("message", "") for e in data["errors"])[:600])
    if p.returncode != 0 or not data:
        raise GhError((p.stderr or p.stdout or "gh lỗi không rõ").strip()[:600])
    return data.get("data") or {}


def fetch_project(gcfg: dict) -> dict:
    owner_field = "organization" if str(gcfg.get("ownerType", "user")).lower().startswith("org") else "user"
    base = (PROJECT_QUERY.replace("%OWNER%", owner_field).replace("%FC%", FC))
    use_view = gcfg.get("view") is not None
    items_raw, cursor, proj = [], None, None
    max_items = int(gcfg.get("maxItems", 600))
    while True:
        q = base.replace("%VIEWVAR%", ", $view: Int!" if use_view else "")
        q = q.replace("%VIEWBLOCK%", VIEW_BLOCK if use_view else "").replace("%FIELD%", FIELD_FRAG)
        variables = {"login": str(gcfg["owner"]), "number": int(gcfg["project"]), "cursor": cursor}
        if use_view:
            variables["view"] = int(gcfg["view"])
        try:
            data = gh_graphql(q, variables)
        except GhError as e:
            if use_view and cursor is None and "view" in str(e).lower():
                use_view = False
                continue
            raise
        p = (data.get(owner_field) or {}).get("projectV2")
        if not p:
            raise GhError(f"Không thấy project #{gcfg['project']} của {gcfg['owner']}.")
        if proj is None:
            proj = p
        conn = p["items"]
        items_raw += [n for n in conn["nodes"] if n]
        if conn["pageInfo"]["hasNextPage"] and len(items_raw) < max_items:
            cursor = conn["pageInfo"]["endCursor"]
        else:
            break
    return normalize_project(proj, items_raw, gcfg)


def fetch_projects(gcfg: dict) -> dict:
    """Read every Project in gcfg["projects"] (default: just gcfg["project"]); one failing board keeps the others."""
    numbers = gcfg.get("projects") or [gcfg["project"]]

    def one(n):
        try:
            return fetch_project({**gcfg, "project": n}), None
        except GhError as e:
            warn(f"project #{n}", e)
            return None, f"#{n}: {e}"

    with ThreadPoolExecutor(max_workers=len(numbers)) as pool:  # one gh process per Project, ~2.5 s each
        results = list(pool.map(one, numbers))  # map keeps the configured order
    parts = [p for p, _ in results if p]
    errors = [e for _, e in results if e]
    if not parts:
        raise GhError("; ".join(errors))
    return merge_projects(parts, errors)


def board_fingerprint(parts: list) -> str:
    """Changes only when a card moves, is edited or gets a new comment."""
    h = hashlib.sha1()
    for p in parts:
        for i in p["items"]:
            h.update(f"{i['id']}|{i['status']}|{i.get('updatedAt')}|{(i.get('lastComment') or {}).get('at')}\n".encode())
    return h.hexdigest()


def poll_interval(base: float, unchanged: int) -> float:
    """An idle board is read half as often (the GraphQL budget is shared with the super-board runners)."""
    return base * 2 if unchanged >= 3 else base


def merge_projects(parts: list, errors: list) -> dict:
    first = parts[0]
    columns, fields = [], {}
    for p in parts:
        for c in p["columns"]:
            if all(c["name"] != x["name"] for x in columns):
                columns.append(c)
        for f in p["selectFields"]:
            mf = fields.setdefault(f["name"], {"id": f["id"], "name": f["name"], "options": []})
            for o in f["options"]:
                if all(o["name"] != x["name"] for x in mf["options"]):
                    mf["options"].append(o)
    merged = dict(first)
    merged.update(
        columns=columns, selectFields=list(fields.values()), items=[i for p in parts for i in p["items"]],
        parts={p["id"]: {k: p.get(k) for k in ("id", "statusFieldId", "statusField", "selectFields", "title")} for p in parts},
        partialErrors=errors,
        title=first.get("title") if len(parts) == 1 else f"{len(parts)} Project",
    )
    merged["totalCount"] = len(merged["items"])
    return merged


def last_comment(c: dict):
    nodes = [x for x in ((c.get("comments") or {}).get("nodes") or []) if x]
    if not nodes:
        return None
    x = nodes[-1]
    return {"body": (x.get("body") or "")[:1500], "author": (x.get("author") or {}).get("login"), "at": parse_iso(x.get("createdAt"))}


def normalize_project(p: dict, items_raw: list, gcfg: dict) -> dict:
    fields = [f for f in ((p.get("fields") or {}).get("nodes") or []) if f and f.get("name")]
    view = p.get("view") or None
    status_field = None
    if view:
        for key in ("verticalGroupByFields", "groupByFields"):
            for f in ((view.get(key) or {}).get("nodes") or []):
                if f and f.get("options"):
                    status_field = f
                    break
            if status_field:
                break
    if not status_field:
        status_field = next((f for f in fields if f["name"].lower() == "status" and f.get("options")), None)
    if not status_field:
        status_field = next((f for f in fields if f.get("options")), None)
    status_name = status_field["name"] if status_field else None
    columns = [
        {"name": o["name"], "kind": column_kind(o["name"]), "ghColor": o.get("color"), "optionId": o.get("id")}
        for o in ((status_field or {}).get("options") or [])
    ]
    skip_fields = {"Title", "Assignees", "Labels", "Repository", "Linked pull requests", "Reviewers", "Milestone"}
    if status_name:
        skip_fields.add(status_name)
    items = []
    for n in items_raw:
        if n.get("isArchived") and not gcfg.get("includeArchived"):
            continue
        c = n.get("content") or {}
        fv = {}
        for v in ((n.get("fieldValues") or {}).get("nodes") or []):
            if not v:
                continue
            fname = (v.get("field") or {}).get("name")
            if not fname:
                continue
            val = v.get("name") or v.get("text") or v.get("title") or v.get("date")
            if val is None and v.get("number") is not None:
                val = v["number"]
            if val is not None:
                fv[fname] = val
        repo = (c.get("repository") or {}).get("name") or "Nháp"
        items.append({
            "id": n["id"],
            "contentId": c.get("id"),
            "number": str(c["number"]) if c.get("number") is not None else None,
            "title": c.get("title") or "(không có tiêu đề)",
            "url": c.get("url"),
            "type": c.get("__typename") or n.get("type"),
            "state": c.get("state"),
            "isDraft": bool(c.get("isDraft")),
            "repo": repo,
            "repoFull": (c.get("repository") or {}).get("nameWithOwner"),
            "status": fv.get(status_name) if status_name else None,
            "assignees": [a["login"] for a in ((c.get("assignees") or {}).get("nodes") or []) if a],
            "labels": [{"name": l["name"], "color": l.get("color")} for l in ((c.get("labels") or {}).get("nodes") or []) if l],
            "fields": {k: v for k, v in fv.items() if k not in skip_fields},
            "updatedAt": parse_iso(c.get("updatedAt") or n.get("updatedAt")),
            "lastComment": last_comment(c),
            "pid": p.get("id"),
        })
    if any(not it["status"] for it in items):
        columns.insert(0, {"name": NO_STATUS, "kind": "backlog", "ghColor": "GRAY", "noStatus": True})
        for it in items:
            if not it["status"]:
                it["status"] = NO_STATUS
    select_fields = [
        {"id": f.get("id"), "name": f["name"],
         "options": [{"id": o.get("id"), "name": o["name"], "color": o.get("color")} for o in f["options"]]}
        for f in fields if f.get("options")
    ]
    return {
        "id": p.get("id"),
        "statusFieldId": (status_field or {}).get("id"),
        "selectFields": select_fields,
        "title": p.get("title"),
        "url": p.get("url"),
        "viewName": (view or {}).get("name"),
        "viewLayout": (view or {}).get("layout"),
        "viewFilter": (view or {}).get("filter"),
        "statusField": status_name,
        "columns": columns,
        "items": items,
        "totalCount": len(items),
    }


# ----------------------------------------------------------------- local scanning
class LocalScanner:
    TAIL = 600_000

    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.cache = {}  # path -> (mtime, size, parsed)
        self.acct_cache = {}  # log worker -> {"pos", "ino", "cur", "sids"}: tài khoản theo session id (session_accounts)
        # liệt kê transcript tăng dần (jsonl_files): thư mục -> (mtime_ns, thư mục con, file .jsonl); file đã cũ quá cửa sổ lookback
        self.dir_cache, self.cold, self.last_full = {}, set(), None

    FULL_EVERY = 30.0  # giây: chu kỳ quét đầy đủ (liệt kê lại mọi thư mục, stat cả file cũ)

    def _list_dir(self, path: str, full: bool):
        """(stat, thư mục con, file *.jsonl) của một thư mục. mtime thư mục chỉ đổi khi thêm/xoá/đổi tên mục bên trong,
        nên thư mục không đổi mtime thì dùng lại danh sách lần trước (ghi nối vào file không cần liệt kê lại)."""
        try:
            st = os.stat(path)
        except OSError:
            self.dir_cache.pop(path, None)
            return None, [], []
        hit = self.dir_cache.get(path)
        if hit and not full and hit[0] == st.st_mtime_ns:
            return st, hit[1], hit[2]
        subs, files = [], []
        try:
            with os.scandir(path) as it:
                for e in it:
                    if e.name.startswith("."):
                        continue  # như glob "**": bỏ mục ẩn
                    try:
                        if e.is_dir():
                            subs.append(e.path)
                        elif e.name.endswith(".jsonl"):
                            files.append(e.path)
                    except OSError:
                        continue
        except OSError:
            return st, [], []
        self.dir_cache[path] = (st.st_mtime_ns, subs, files)
        return st, subs, files

    def jsonl_files(self, top: str, cutoff: float, full: bool, visited: set):
        """[(path, mtime)] mọi *.jsonl dưới top (như glob top/**/*.jsonl). Giữa hai lần quét đầy đủ chỉ stat thư mục (biết file
        mới) và file còn trong cửa sổ lookback; file đã cũ hơn cutoff ở lần trước chỉ được stat lại ở lần quét đầy đủ, nên phiên
        cũ được resume hiện lại trễ tối đa FULL_EVERY giây. ~/.claude/projects thật: ~5000 file / ~3500 thư mục, mỗi 3 giây."""
        out, stack, inos = [], [top], set()
        while stack:
            d = stack.pop()
            st, subs, files = self._list_dir(d, full)
            if st is None or (st.st_dev, st.st_ino) in inos:
                continue  # link vòng
            inos.add((st.st_dev, st.st_ino)); visited.add(d)
            stack.extend(subs)
            for p in files:
                if not full and p in self.cold:
                    continue
                try:
                    m = os.stat(p).st_mtime
                except OSError:
                    self.cold.discard(p)
                    continue
                if m < cutoff:
                    self.cold.add(p)
                else:
                    self.cold.discard(p)
                    out.append((p, m))
        return out

    def repo_paths(self, names):
        root = expand(self.cfg["root"])
        out = {}
        overrides = {k.lower(): expand(v) for k, v in (self.cfg.get("repoPaths") or {}).items()}
        for name in names:
            if name.lower() in overrides:
                out[name] = overrides[name.lower()]
                continue
            nested = os.path.join(root, name, name)
            flat = os.path.join(root, name)
            if os.path.isdir(os.path.join(nested, ".git")):
                out[name] = nested
            else:
                out[name] = flat
        return out

    # ---- transcripts
    def parse_session(self, path: str):
        st = os.stat(path)
        hit = self.cache.get(path)
        if hit and hit[0] == st.st_mtime and hit[1] == st.st_size:
            return hit[2]
        s = {
            "id": os.path.basename(path)[:-6], "file": path, "cwd": None, "branch": None,
            "lastTs": None, "texts": [], "tools": [], "ticks": [], "tokensLeft": None,
            "finishedAt": None, "manifest": None, "subagent": "/subagents/" in path,
        }
        try:
            raw = tail_text(path, self.TAIL)
        except OSError:
            return None
        for line in raw.splitlines():
            if not line.strip():
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if not isinstance(e, dict):
                continue
            ts = parse_iso(e.get("timestamp"))
            if e.get("cwd"):
                s["cwd"] = e["cwd"]
            if e.get("gitBranch"):
                s["branch"] = e["gitBranch"]
            if e.get("sessionId") and not s["subagent"]:
                s["id"] = e["sessionId"]
            if ts:
                s["lastTs"] = max(s["lastTs"] or 0, ts)
            msg = e.get("message") if isinstance(e.get("message"), dict) else {}
            content = msg.get("content")
            if e.get("type") == "assistant" and isinstance(content, list):
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "text" and (b.get("text") or "").strip():
                        s["texts"].append({"ts": ts, "text": redact(b["text"].strip())[:1500]})
                    elif b.get("type") == "tool_use":
                        s["tools"].append({"ts": ts, "name": b.get("name") or "Tool",
                                           "summary": tool_summary(b.get("name"), b.get("input"))})
            if "[RUNNER]" in line or "total_tokens" in line or "exiting cleanly" in line or "manifest:" in line:
                ref = ts or st.st_mtime
                for text in iter_strings(e):
                    if "[RUNNER]" in text:
                        for t in parse_ticks(text, ref):
                            t.pop("pos", None)
                            s["ticks"].append(t)
                    if "total_tokens" in text:
                        found = TOKENS_RE.findall(text)
                        if found:
                            s["tokensLeft"] = int(found[-1])
                    if FINISH_RE.search(text):
                        s["finishedAt"] = ref
                    mm = MANIFEST_RE.findall(text)
                    if mm:
                        s["manifest"] = mm[-1]
        s["lastTs"] = s["lastTs"] or st.st_mtime
        s["texts"] = s["texts"][-8:]
        s["tools"] = s["tools"][-20:]
        s["ticks"] = s["ticks"][-200:]
        self.cache[path] = (st.st_mtime, st.st_size, s)
        return s

    def scan_sessions(self):
        base = expand(self.cfg["claudeProjectsDir"])
        info = {"dir": base, "ok": os.path.isdir(base), "files": 0}
        if not info["ok"]:
            return [], info
        prefix = encode_path(expand(self.cfg["root"])) if self.cfg.get("root") else ""
        cutoff = now() - float(self.cfg["lookbackMinutes"]) * 60
        sessions = []
        seen = set()
        mono = time.monotonic()
        full = self.last_full is None or mono - self.last_full >= self.FULL_EVERY
        if full:
            self.last_full, self.cold = mono, set()
        visited = set()
        for d in os.scandir(base):
            if not d.is_dir() or (prefix and not d.name.startswith(prefix)):
                continue
            for path, _mtime in self.jsonl_files(d.path, cutoff, full, visited):
                seen.add(path)
                s = self.parse_session(path)
                if s:
                    s = dict(s)
                    s["projectDir"] = d.name
                    sessions.append(s)
        for p in list(self.cache):
            if p not in seen and p.endswith(".jsonl"):
                self.cache.pop(p, None)
        if full:  # thư mục đã xoá / đổi tên: bỏ khỏi bộ nhớ đệm
            self.dir_cache = {k: v for k, v in self.dir_cache.items() if k in visited}
        info["files"] = len(sessions)
        return sessions, info

    # ---- runner logs / manifests
    def scan_files_for_ticks(self, repo_paths: dict):
        results = []  # (repoName|None, path, ticks, finishedAt, mtime)
        paths = set()
        for g in self.cfg.get("runnerLogGlobs") or []:
            for p in glob.glob(expand(g), recursive=True):
                paths.add(p)
        for name, rp in repo_paths.items():
            mds = glob.glob(os.path.join(rp, "docs", "super-board", "runs", "*.md"))
            if mds:
                paths.add(max(mds, key=os.path.getmtime))
        for p in paths:
            try:
                mtime = os.path.getmtime(p)
                if mtime < now() - float(self.cfg["lookbackMinutes"]) * 60 * 6:
                    continue
                text = tail_text(p, 300_000)
            except OSError:
                continue
            ticks = parse_ticks(text, mtime)
            fin = None
            last_pos = ticks[-1]["pos"] if ticks else 0
            for m in FINISH_RE.finditer(text):
                if m.start() >= last_pos:
                    fin = mtime
            for t in ticks:
                t.pop("pos", None)
            repo = None
            ap = os.path.abspath(p)
            for name, rp in sorted(repo_paths.items(), key=lambda kv: -len(kv[1])):
                if ap.startswith(rp + os.sep):
                    repo = name
                    break
            if repo is None:
                low = os.path.basename(p).lower()
                for name in sorted(repo_paths, key=len, reverse=True):
                    if name.lower() in low:
                        repo = name
                        break
            if ticks or fin:
                results.append((repo, p, ticks, fin, mtime))
        return results

    def session_accounts(self, repo_paths: dict, max_age_days: float = 7) -> dict:
        """session id → {account, configDir} từ dòng `account_pool: engine=… account=<tên> config_dir=<thư mục>` của log worker
        super-board (cùng log find_worker_session đọc). Đọc tiếp từ chỗ dừng lần trước (log đang ghi không bị đọc lại từ đầu);
        chỉ giữ tên hồ sơ đã lọc và tên thư mục, không giữ dòng log nào."""
        cache = self.acct_cache
        cutoff, seen, out = now() - max_age_days * 86400, set(), {}
        for rp in repo_paths.values():
            for p in glob.glob(os.path.join(rp, WORKER_LOG_GLOB)):
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                if st.st_mtime < cutoff:
                    continue
                seen.add(p)
                c = cache.get(p)
                if c is None or c["ino"] != st.st_ino or st.st_size < c["pos"]:
                    c = cache[p] = {"pos": 0, "ino": st.st_ino, "cur": None, "sids": {}}
                if st.st_size > c["pos"]:
                    try:
                        with open(p, "rb") as f:
                            f.seek(c["pos"])
                            chunk = f.read(min(st.st_size - c["pos"], 64 * 1024 * 1024))
                    except OSError as e:
                        warn("đọc log worker " + p, e)
                        chunk = b""
                    end = chunk.rfind(b"\n") + 1  # chỉ dòng đã ghi trọn; phần dở đọc lại lần sau
                    for raw in chunk[:end].split(b"\n"):
                        if raw.startswith(b"=== dispatch"):
                            c["cur"] = None
                        elif raw.startswith(b"account_pool:"):
                            m = POOL_LINE_RE.match(raw.decode("utf-8", "replace"))
                            if m:
                                acc = safe_account(m.group(1))
                                cdir = account_of_config_dir(m.group(2))[1]
                                c["cur"] = {"account": acc, "configDir": cdir} if (acc or cdir) else None
                        elif c["cur"] and b"session_id" in raw:
                            for m in SECTION_SID_RE.finditer(raw.decode("utf-8", "replace")):
                                c["sids"].setdefault(m.group(1) or m.group(2), c["cur"])
                    c["pos"] += end
                out.update(c["sids"])
        for p in list(cache):
            if p not in seen:
                cache.pop(p, None)
        return out

    def newest_manifest(self, repo_path: str):
        mds = glob.glob(os.path.join(repo_path, "docs", "super-board", "runs", "*.md"))
        if not mds:
            return None
        p = max(mds, key=os.path.getmtime)
        return {"path": os.path.relpath(p, repo_path), "mtime": os.path.getmtime(p)}


def repo_for_cwd(cwd: str, repo_paths: dict, root: str):
    if not cwd:
        return None
    ap = os.path.abspath(cwd)
    for name, rp in sorted(repo_paths.items(), key=lambda kv: -len(kv[1])):
        if ap == rp or ap.startswith(rp + os.sep):
            return name
    for name, rp in repo_paths.items():  # trường hợp root/Name/Name
        parent = os.path.dirname(rp)
        if os.path.basename(parent) == name and (ap == parent or ap.startswith(parent + os.sep)):
            return name
    if root and (ap + os.sep).startswith(root + os.sep):
        rest = os.path.relpath(ap, root).split(os.sep)
        if rest and rest[0] not in (".", ".."):
            return rest[0]
    return None


def repo_for_projectdir(dirname: str, repo_paths: dict):
    for name, rp in sorted(repo_paths.items(), key=lambda kv: -len(kv[1])):
        enc = encode_path(rp)
        if dirname == enc or dirname.startswith(enc + "-"):
            return name
    return None


# ----------------------------------------------------------------- state assembly
def session_hints(s: dict):
    """Lane/issue từ thư mục làm việc, nhánh git, hoặc lệnh gần nhất."""
    path_issue, path_lane = None, None
    hay = " ".join(x for x in (s.get("cwd"), s.get("branch")) if x)
    m = ISSUE_LANE_RE.search(hay)
    if m:
        path_issue, path_lane = m.group(1), m.group(2).lower()
    elif ISSUE_PATH_RE.search(hay):
        path_issue = ISSUE_PATH_RE.search(hay).group(1)
    tool_issue, tool_lane = None, None
    for t in reversed(s.get("tools") or []):
        m = ISSUE_LANE_RE.search(t.get("summary") or "")
        if m:
            tool_issue, tool_lane = m.group(1), m.group(2).lower()
            break
    mentions = []
    for entry in reversed(s.get("texts") or []):
        for n in HASH_RE.findall(entry["text"]):
            if n not in mentions:
                mentions.append(n)
        if len(mentions) > 12:
            break
    return path_issue, path_lane, tool_issue, tool_lane, mentions


# Tài khoản Claude của phiên (góc phải trên): chỉ tên hồ sơ và tên thư mục cấu hình, không bao giờ đường dẫn đầy đủ hay giá trị token
ACCOUNT_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
CONFIG_DIR_RE = re.compile(r"^\.claude(?:-([A-Za-z0-9][A-Za-z0-9._-]{0,63}))?$")


def safe_account(name):
    """Tên hồ sơ của account pool (finos, finos_team, max…); chuỗi lạ (có dấu cách, =, /, quá dài) thì None, không đưa ra API."""
    return name if isinstance(name, str) and ACCOUNT_NAME_RE.match(name) else None


def account_of_config_dir(path):
    """config_dir → (tên hồ sơ, tên thư mục): ~/.claude-finos → ("finos", ".claude-finos"); ~/.claude → (None, ".claude")
    (tài khoản mặc định, không có tên); thư mục không theo mẫu .claude[-tên] → (None, None)."""
    if not isinstance(path, str) or not path:
        return None, None
    base = os.path.basename(path.rstrip("/\\"))
    m = CONFIG_DIR_RE.match(base)
    if not m:
        return None, None
    return m.group(1), base


def session_account(s: dict, accounts=None):
    """{account, configDir} của một phiên. Phiên worker: dòng `account_pool:` trong log worker (accounts: sid → info).
    Phiên không có dòng đó (điều phối, gõ tay): đoán từ thư mục cấu hình chứa transcript (~/.claude-finos/projects/… → finos)."""
    hit = (accounts or {}).get(s.get("id")) if not s.get("subagent") else None
    if hit:
        return {"account": hit.get("account"), "configDir": hit.get("configDir")}
    if s.get("account") or s.get("configDir"):  # demo / phiên đã gắn sẵn
        acc = safe_account(s.get("account"))
        cdir = account_of_config_dir(s.get("configDir"))[1]
        return {"account": acc, "configDir": cdir}
    for part in reversed(os.path.dirname(s.get("file") or "").split(os.sep)):
        acc, cdir = account_of_config_dir(part)
        if cdir:
            return {"account": acc, "configDir": cdir}
    return {"account": None, "configDir": None}


def slim_session(s: dict, tokens_fallback=None, accounts=None):
    out = {
        "id": s["id"], "cwd": s.get("cwd"), "branch": s.get("branch"), "lastTs": s.get("lastTs"),
        "texts": (s.get("texts") or [])[-6:], "tools": (s.get("tools") or [])[-14:],
        "tokensLeft": s.get("tokensLeft") or tokens_fallback, "subagent": s.get("subagent", False),
    }
    out.update(session_account(s, accounts))
    return out


HEAVY_LOCK_DIR = os.path.join(os.path.expanduser("~"), ".claude", "super-board", "locks")  # khoá việc nặng của DevKit (heavy_slot)
# T0052: ngưỡng tải gate mặc định = hold_load của nguồn sức chứa chung universal-agent-devkit/bin/capacity.py (8 × lõi, cùng ngưỡng
# heavy_slot.load_max: việc bắt buộc chỉ chờ trên mức này)
CAPACITY_PY = os.path.join(os.path.dirname(os.path.dirname(HERE)), "universal-agent-devkit", "bin", "capacity.py")
_CAPACITY: list = []   # [module capacity hoặc None]: nạp một lần


def _capacity():
    """bin/capacity.py nạp một lần qua importlib; None khi thiếu hay hỏng (bảng chỉ số dùng 100 như cũ)."""
    if not _CAPACITY:
        mod = None
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("devkit_capacity", CAPACITY_PY)
            if spec is not None and spec.loader is not None:
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
        except Exception as exc:  # noqa: BLE001 - capacity.py hỏng kiểu gì (cả lỗi runtime lúc nạp) cũng không làm chết bảng chỉ số
            warn(f"không nạp được {CAPACITY_PY}, ngưỡng tải hiển thị 100", repr(exc))
            mod = None
        _CAPACITY.append(mod)
    return _CAPACITY[0]


def _default_load_max() -> float:
    """capacity hold_load; capacity vắng, hàm thiếu (file 0 byte), ném lỗi hay trả ngoài (0, inf) — inf ra "Infinity" làm hỏng JSON cả
    trang — thì 100 (Antigravity audit 23/10)."""
    cap = _capacity()
    if cap is None:
        return 100.0
    try:
        value = cap.hold_load()
        if isinstance(value, (int, float)) and not isinstance(value, bool) and 0 < value < float("inf"):
            return float(value)
        why = f"hold_load trả {value!r}"
    except Exception as exc:  # noqa: BLE001 - capacity.py hỏng kiểu gì cũng không làm chết bảng chỉ số
        why = repr(exc)
    if len(_CAPACITY) < 2:  # một dòng cho cả tiến trình: bảng chỉ số gọi host_stats mỗi lần làm mới
        _CAPACITY.append("warned")
        warn(f"{CAPACITY_PY} hỏng, ngưỡng tải hiển thị 100", why)
    return 100.0


def host_stats(lock_dir: str = "", workload: bool = True) -> dict:
    """Sức khoẻ máy cho bảng chỉ số: tải 1/5/15 phút, số nhân, ngưỡng tải gate, số khoá việc nặng đang giữ. Chỉ đọc, rất rẻ."""
    try:
        load = [round(float(x), 2) for x in os.getloadavg()]
    except (OSError, AttributeError):  # Windows không có getloadavg
        load = [0.0, 0.0, 0.0]
    lock_dir = lock_dir or os.environ.get("SB_HEAVY_SLOT_DIR", "").strip() or HEAVY_LOCK_DIR  # cùng chỗ với heavy_slot.slot_dir()
    # DEVKIT_SLOT_LOAD_MAX thắng; rỗng/rác/≤ 0 thì capacity hold_load (12 lõi: 96), không có capacity thì 100 — cùng luật heavy_slot.load_max
    try:
        load_max = float(os.environ.get("DEVKIT_SLOT_LOAD_MAX") or 0)
    except ValueError:
        load_max = 0.0
    if not 0 < load_max < float("inf"):  # nan/inf/âm: inf sẽ ra "Infinity" làm hỏng JSON của cả trang
        load_max = _default_load_max()
    return {"load": load, "cpus": os.cpu_count() or 1, "loadMax": load_max, "slotsHeld": _held_locks(lock_dir), "workload": agent_workload() if workload else {"groups": [], "top": [], "tasks": []}}


_AGENT_GROUPS = (  # (id, nhãn, dấu hiệu trong argv0 hoặc đường dẫn script): khớp đầu tiên thắng
    ("claude", "Claude", ("claude",)),
    ("antigravity", "Antigravity", ("antigravity", "agy")),
    ("grok", "Grok", ("grok",)),
    ("gemini", "Gemini", ("gemini",)),
    ("codex", "Codex", ("codex",)),
    ("gate", "Gate · test · benchmark", ("post-fix-gate", "run_impacted", "run.sh", "pytest", "heavy_slot")),
)
_NOT_AGENT = {"grep", "rg", "ps", "awk", "sed", "tail", "head", "cat", "find", "sleep"}  # nhắc tên agent trong đối số, không phải agent


def _group_of(command: str):
    parts = command.split()
    if not parts:
        return None
    a0 = os.path.basename(parts[0]).lower()
    if a0 in _NOT_AGENT:
        return None
    app = re.search(r"/([^/]+)\.app/Contents/", command)  # app đóng gói (kể cả Resources/bin/language_server): tên .app ngoài cùng
    app_name = app.group(1).lower() if app else ""
    interp = re.fullmatch(r"python[\d.]*|bash|sh|zsh|node", a0) is not None
    if interp or app_name == "python":  # trình thông dịch (kể cả Homebrew Python.app): xét script nó chạy, không xét chính nó
        args = parts[1:] if interp else command.split(".app/Contents/MacOS/", 1)[-1].split()[1:]
        head = [os.path.basename(x).lower() for x in args[:2] if not x.startswith("-")]
    elif app_name:
        head = [app_name]
    else:
        head = [a0]  # chương trình thường: chỉ tên chương trình; đối số (vd. CLAUDE.md) không làm nó thành agent
    script_run = interp or app_name == "python"  # script tên "setup_claude.sh" không phải agent Claude: script chỉ vào nhóm gate/test
    for gid, _label, keys in _AGENT_GROUPS:
        if script_run and gid != "gate":
            if not any(os.path.splitext(h)[0] in keys for h in head):  # CLI viết bằng node/python: script tên đúng agent (gemini, agy)
                continue
        if any(re.search(r"(?<![a-z0-9])" + re.escape(k) + r"(?![a-z0-9])", h) for k in keys for h in head):  # nguyên từ: "agy" không khớp "legacy"
            return gid
    return None


def workload_from_ps(text: str, top_n: int = 8) -> dict:
    """Gom đầu ra `ps -Ao pid=,pcpu=,rss=,etime=,command=` thành tải từng nhóm agent + các tiến trình nặng nhất."""
    labels = {gid: label for gid, label, _ in _AGENT_GROUPS}
    groups: dict = {}
    procs = []
    total = other_cpu = 0.0
    others: dict = {}
    for line in text.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5 or not parts[0].isdigit():
            continue
        try:
            pid, cpu, rss = int(parts[0]), float(parts[1]), int(parts[2])
        except ValueError:
            continue
        total += cpu
        gid = _group_of(parts[4])
        if gid is None:  # ngoài agent (trình duyệt, WindowServer...): chỉ cộng vào tổng và nhóm theo tên để biết ai nặng
            if cpu >= 1.0:
                m = re.search(r"/([^/]+)\.app/Contents/", parts[4])  # app khác: gọi theo tên app (Brave Browser), không theo vai trò (GPU...)
                name = m.group(1) if m else _prog_name(parts[4])
                others[name] = round(others.get(name, 0.0) + cpu, 1)
            other_cpu += cpu
            continue
        g = groups.setdefault(gid, {"id": gid, "label": labels[gid], "count": 0, "cpu": 0.0, "rssMb": 0})
        g["count"] += 1
        g["cpu"] = round(g["cpu"] + cpu, 1)
        g["rssMb"] += round(rss / 1024)
        procs.append({"pid": pid, "group": gid, "cpu": cpu, "rssMb": round(rss / 1024), "etime": parts[3], "cmd": redact(parts[4])[:110], "cmdFull": parts[4]})
    procs.sort(key=lambda p: -p["cpu"])
    top_others = [{"label": k, "cpu": v} for k, v in sorted(others.items(), key=lambda kv: -kv[1])[:4]]
    return {"groups": sorted(groups.values(), key=lambda g: -g["cpu"]), "top": procs[:top_n],
            "totalCpu": round(total, 1), "otherCpu": round(other_cpu, 1), "others": top_others}


def script_note(command: str, cwd: str = "") -> str:
    """Dòng chú thích đầu tiên (`# ...`) của script mà tiến trình đang chạy: cho biết tiến trình đó làm việc gì."""
    parts = command.split()
    if not parts or not (os.path.basename(parts[0]).lower().startswith(("python", "bash", "sh", "zsh", "node"))):
        return ""
    script = next((p for p in parts[1:4] if not p.startswith("-")), "")
    if script and not os.path.isabs(script):
        script = os.path.join(cwd, script) if cwd else ""  # đường dẫn tương đối tính theo cwd của TIẾN TRÌNH, không theo cwd của server
    if not script or not os.path.isfile(script):
        return ""
    try:
        with open(script, encoding="utf-8", errors="replace") as f:
            for _ in range(8):
                line = f.readline().strip()
                if line.startswith("#") and not line.startswith("#!"):
                    return redact(line.lstrip("# ").strip())[:160]
    except OSError:
        return ""
    return ""


def where_from_cwd(cwd: str) -> str:
    """Thư mục làm việc → "repo" hoặc "repo · worktree tên" (worktree của phiên/thẻ nằm dưới <repo>/.claude/worktrees/)."""
    if not cwd or cwd == os.sep:
        return ""
    m = re.match(r"(.*?)/\.claude/worktrees/([^/]+)", cwd)
    if m:
        return f"{os.path.basename(m.group(1))} · worktree {m.group(2)}"
    d = cwd
    while d and d != os.sep:
        if os.path.exists(os.path.join(d, ".git")):
            return os.path.basename(d)
        d = os.path.dirname(d)
    return os.path.basename(cwd.rstrip("/")) or cwd


_TEMP_PREFIXES = ("/tmp/", "/private/tmp/", "/var/folders/", "/private/var/")


def resolve_where(pid: int, cwds: dict, ppids: dict, depth: int = 8) -> str:
    """Nơi làm việc của tiến trình; cwd là thư mục tạm (gate/test chạy trong repo giả) thì leo lên tiến trình cha cho tới khi gặp
    thư mục thật. Rỗng nếu không tổ tiên nào có."""
    seen = set()
    while pid and pid not in seen and depth > 0:
        seen.add(pid)
        cwd = cwds.get(pid, "")
        if cwd and cwd != os.sep and not (cwd + os.sep).startswith(_TEMP_PREFIXES):
            return where_from_cwd(cwd)
        pid, depth = ppids.get(pid, 0), depth - 1
    return ""


def proc_ppids() -> dict:
    """pid → ppid của mọi tiến trình (một lần ps); lỗi thì rỗng."""
    try:
        out = subprocess.run(["ps", "-Ao", "pid=,ppid="], capture_output=True, timeout=5, check=True, env=_PS_ENV()).stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError) as exc:
        warn("không đọc được cây tiến trình (ps ppid)", repr(exc))
        return {}
    res = {}
    for line in out.splitlines():
        a = line.split()
        if len(a) == 2 and a[0].isdigit() and a[1].isdigit():
            res[int(a[0])] = int(a[1])
    return res


def proc_cwds(pids: list) -> dict:
    """pid → thư mục làm việc, một lần lsof cho cả nhóm; lỗi thì rỗng (workload vẫn hiện, chỉ thiếu chỗ làm việc)."""
    if not pids:
        return {}
    try:
        out = subprocess.run(["lsof", "-a", "-d", "cwd", "-Fpn", "-p", ",".join(str(p) for p in pids)],
                             capture_output=True, timeout=5).stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError) as exc:
        warn("không đọc được thư mục làm việc của tiến trình (lsof)", repr(exc))
        return {}
    res, cur = {}, None
    for line in out.splitlines():
        if line.startswith("p") and line[1:].isdigit():
            cur = int(line[1:])
        elif line.startswith("n") and cur is not None:
            res[cur] = line[1:]
    return res


def _prog_name(command: str) -> str:
    """Tên dễ đọc của chương trình: script mà trình thông dịch chạy, hay tên .app, hay tên lệnh."""
    t = re.search(r"--type=([\w-]+)", command) if ".app/Contents/" in command else None  # Electron/Chromium: một app chạy nhiều tiến trình vai trò khác nhau
    if t:
        sub = re.search(r"--utility-sub-type=([\w.]+)", command)
        if t.group(1) == "utility" and sub:
            s = sub.group(1).lower()
            return "Dịch vụ mạng" if "network" in s else "Âm thanh" if "audio" in s else "Camera" if "video" in s else "Dịch vụ " + s.split(".")[0]
        return {"renderer": "Giao diện cửa sổ (renderer)", "gpu-process": "Đồ hoạ (GPU)", "utility": "Dịch vụ phụ"}.get(t.group(1), t.group(1))
    parts = command.split()
    a0 = os.path.basename(parts[0]) if parts else ""
    if a0 == "language_server":
        return "language_server (AI backend)"
    if len(parts) == 1 and re.search(r"/Applications/[^/]+\.app/Contents/MacOS/", command):
        return "Cửa sổ chính"
    if re.fullmatch(r"python[\d.]*|bash|sh|zsh|node", a0.lower()):
        script = next((x for x in parts[1:3] if not x.startswith("-")), "")
        if parts[1:2] in (["-c"], ["-e"]):  # mã inline: không dùng làm nhãn
            return a0
        return redact(os.path.basename(script)) or a0
    app = re.search(r"/([^/]+)\.app/Contents/MacOS/", command)
    helper = re.search(r"/([^/]+)\.app/Contents/MacOS/[^/]+ (\S+\.(?:c?js|mjs|py))", command)  # helper Electron chạy một file script
    if helper:
        return os.path.basename(helper.group(2))
    if app and app.group(1).lower() == "python":
        rest = command.split(".app/Contents/MacOS/", 1)[-1].split()[1:]
        return os.path.basename(next((x for x in rest[:2] if not x.startswith("-")), "")) or "python"
    return (app.group(1) if app else a0).lower() or "?"


def build_tasks(procs: list) -> list:
    """Gộp tiến trình thành "việc": cùng chú thích/script + cùng nơi làm việc là một dòng (7 vòng lặp run.sh = 1 benchmark)."""
    tasks: dict = {}
    for p in procs:
        label = p.get("note") or _prog_name(p["cmdFull"])
        key = (p["group"], label, p.get("where", ""))
        t = tasks.setdefault(key, {"label": label, "group": p["group"], "where": p.get("where", ""), "count": 0, "cpu": 0.0, "rssMb": 0, "etime": p["etime"]})
        t["count"] += 1
        t["cpu"] = round(t["cpu"] + p["cpu"], 1)
        t["rssMb"] += p["rssMb"]
        if (len(p["etime"]), p["etime"]) > (len(t["etime"]), t["etime"]):
            t["etime"] = p["etime"]  # chạy lâu nhất trong nhóm = mốc bắt đầu của việc
    return sorted(tasks.values(), key=lambda t: -t["cpu"])


_WORKLOAD_CACHE: list = [0.0, {"groups": [], "top": [], "tasks": []}]  # [lúc đo, kết quả]: ps tốn ~50 ms, đo 30 s một lần


_LAST_VIEW = [0.0]  # lúc gần nhất có trang MỞ (tab đang hiện) hỏi /api/state?view=1
VIEW_GRACE = 45.0   # quá ngần này không ai xem thì thôi đo ps


def viewing() -> bool:
    return time.time() - _LAST_VIEW[0] <= VIEW_GRACE


def mark_viewed() -> bool:
    """Ghi nhận có người xem; True nếu vừa chuyển từ không ai xem sang có người xem (cần đánh thức vòng đọc nền)."""
    was = viewing()
    _LAST_VIEW[0] = time.time()
    return not was


def loop_wait(base: float, floor: float, mult: float) -> float:
    """Nhịp nghỉ của vòng đọc nền: có người xem thì nhịp gốc; không ai xem thì chậm đi (≥ floor, hoặc base × mult nếu lớn hơn).
    Không dừng hẳn: thông báo Mac "cần bạn duyệt" và việc giao lệnh cho agent vẫn chạy trong lúc tab đóng."""
    return base if viewing() else max(floor, base * mult)


_WORKLOAD_LOCK = threading.Lock()


def _PS_ENV() -> dict:
    return {**os.environ, "LC_ALL": "C"}  # ps in số thập phân bằng dấu chấm dù locale máy là gì


def agent_workload(ttl: float = 30.0) -> dict:
    now = time.time()
    if not viewing():  # không ai đang xem (tab ẩn / đóng): giữ số cũ, không chạy ps
        return _WORKLOAD_CACHE[1]
    if now - _WORKLOAD_CACHE[0] < ttl:
        return _WORKLOAD_CACHE[1]
    if not _WORKLOAD_LOCK.acquire(blocking=False):  # vòng khác đang đo: dùng số hiện có, không đo trùng
        return _WORKLOAD_CACHE[1]
    try:
        out = subprocess.run(["ps", "-Ao", "pid=,pcpu=,rss=,etime=,command="], capture_output=True, timeout=5, check=True, env=_PS_ENV()).stdout.decode("utf-8", "replace")  # argv không UTF-8 không được làm chết vòng đọc
        wl = workload_from_ps(out, top_n=200)  # đủ cả nhóm agent để gộp theo việc (vài chục tiến trình)
        ppids = proc_ppids()
        wanted = set()  # chính tiến trình + tổ tiên (tối đa 8 đời) để tìm nơi làm việc thật
        for p in wl["top"]:
            q, n = p["pid"], 0
            while q and q not in wanted and n < 8:
                wanted.add(q)
                q, n = ppids.get(q, 0), n + 1
        cwds = proc_cwds(sorted(wanted))
        notes: dict = {}  # cùng script thì chỉ đọc chú thích một lần
        for p in wl["top"]:
            p["where"] = resolve_where(p["pid"], cwds, ppids)
            key = (p["cmdFull"], cwds.get(p["pid"], ""))
            if key not in notes:
                notes[key] = script_note(p["cmdFull"], cwds.get(p["pid"], ""))
            p["note"] = notes[key]
        per_group: dict = {}
        wl["tasks"] = [t for t in build_tasks(wl["top"]) if per_group.setdefault(t["group"], []).append(1) or len(per_group[t["group"]]) <= 5]  # mỗi nhóm 5 việc nặng nhất
        wl["top"] = []  # danh sách tiến trình thô không còn cần cho giao diện
        _WORKLOAD_CACHE[1] = wl
    except (OSError, subprocess.SubprocessError) as exc:
        warn("không đo được workload theo agent (ps)", repr(exc))
    finally:
        _WORKLOAD_LOCK.release()
    _WORKLOAD_CACHE[0] = now
    return _WORKLOAD_CACHE[1]


_LOCK_CACHE: dict = {}  # thư mục -> (lúc đo, số khoá): dò 15 s một lần để ít va với heavy_slot


def _held_locks(lock_dir: str, ttl: float = 15.0) -> int:
    """Số khoá việc nặng đang bị giữ. Thử LOCK_SH không chờ rồi nhả ngay; trong khe đó một worker xin đúng slot ấy sẽ chờ
    thêm một nhịp poll của heavy_slot. ponytail: dò bằng flock, đổi sang đọc trạng thái do heavy_slot ghi ra khi nó có."""
    now = time.time()
    hit = _LOCK_CACHE.get(lock_dir)
    if hit and now - hit[0] < ttl:
        return hit[1]
    held = 0
    try:
        names = [n for n in os.listdir(lock_dir) if n.endswith(".lock") and n.startswith(("heavy", "unity"))]  # pool việc nặng; light/cpu không tính
    except OSError:
        names = []
    for n in names if fcntl else []:  # file khoá còn nằm trên đĩa sau khi nhả: thử khoá không chờ để biết khoá nào đang thật sự bị giữ
        try:
            with open(os.path.join(lock_dir, n), "rb") as f:
                try:
                    fcntl.flock(f, fcntl.LOCK_SH | fcntl.LOCK_NB)  # khoá chia sẻ chỉ va với người đang giữ độc quyền, nhả ngay
                    fcntl.flock(f, fcntl.LOCK_UN)
                except BlockingIOError:
                    held += 1
        except OSError:
            continue
    _LOCK_CACHE[lock_dir] = (now, held)
    return held


def tally_moves(prev: dict, cur: dict, kinds: dict, tally: dict) -> dict:
    """Cộng dồn số lượt thẻ đổi cột, số thẻ vào cột xong và vào cột bị chặn giữa hai lần đọc (thẻ mới xuất hiện không tính)."""
    out = dict(tally)
    for iid, status in cur.items():
        ps = prev.get(iid)
        if not ps or ps == status:
            continue
        out["moves"] = out.get("moves", 0) + 1
        kd = kinds.get(status) or column_kind(status)
        if kd == "done":
            out["done"] = out.get("done", 0) + 1
        elif kd == "blocked":
            out["blocked"] = out.get("blocked", 0) + 1
    return out


BRANCH_CARD_RE = re.compile(r"^issue-(\d+)-")


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # tiến trình có thật nhưng của người khác
    except OSError:
        return False
    return True


def _parse_train_state(lines):
    """Một file state train: (pid, started_at, step, prs)."""
    pid = started = None
    step = "gate"
    prs = []
    for line in lines:
        parts = line.split()
        if len(parts) < 2:
            continue
        if parts[0] == "pid" and parts[1].isdigit():
            pid = int(parts[1])
        elif parts[0] == "started_at" and parts[1].isdigit():
            started = int(parts[1])
        elif parts[0] == "step":
            step = parts[1]
        elif parts[0] == "pr" and parts[1].isdigit():
            m = BRANCH_CARD_RE.match(parts[3]) if len(parts) > 3 else None
            prs.append({"pr": int(parts[1]), "card": int(m.group(1)) if m else None})
    return pid, started, step, prs


def read_merge_train(repo_path: str, alive=_pid_alive):
    """Train merge đang chạy của repo từ `<repo>/.git/super-board/merge-train.<pid>.state` (#676; trước đó `merge-train.state`, #562),
    hoặc None.

    Mỗi train ghi `pid`, `started_at`, `step` (gate | merge) và mỗi PR một dòng `pr <N> <sha> <ref>`, rồi xoá file khi thoát. #676: một
    train mỗi PR, nhiều train cùng lúc — các train sống gộp thành một: PR/thẻ của mọi train, `startedAt` sớm nhất, step `merge` khi có
    train đang merge, pid của train sớm nhất. File thiếu, hỏng, pid chết (train bị SIGKILL để lại file mồ côi) thì bỏ qua. Chỉ ĐỌC file.
    ponytail: pid bị tái dùng bởi tiến trình khác giữ file mồ côi sống; hàng đợi merge kiểm thêm lệnh của pid, thêm vào đây khi gặp."""
    sb = os.path.join(repo_path, ".git", "super-board")
    try:
        names = sorted(n for n in os.listdir(sb) if n.startswith("merge-train.") and n.endswith(".state"))
    except OSError:
        return None
    live = []
    for name in names:
        try:
            with open(os.path.join(sb, name), encoding="utf-8", errors="replace") as f:
                pid, started, step, prs = _parse_train_state(f.read().splitlines())
        except OSError:
            continue
        if pid is None or started is None or not prs or not alive(pid):
            continue
        live.append((started, pid, step, prs))
    if not live:
        return None
    live.sort(key=lambda t: (t[0], t[1]))
    prs_all = [x for t in live for x in t[3]]
    return {"pid": live[0][1], "startedAt": live[0][0], "step": "merge" if any(t[2] == "merge" for t in live) else "gate",
            "prs": prs_all, "cards": [x["card"] for x in prs_all if x["card"] is not None]}


def read_queued_cards(repo_path: str) -> set:
    """Số thẻ có PR đang chờ trong hàng đợi merge (`merge-queue.labeled`: `<PR> <head> <epoch> <ref>`; dòng thiếu ref bị bỏ qua)."""
    try:
        with open(os.path.join(repo_path, ".git", "super-board", "merge-queue.labeled"), encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return set()
    out = set()
    for line in lines:
        parts = line.split()
        m = BRANCH_CARD_RE.match(parts[3]) if len(parts) >= 4 else None
        if m:
            out.add(int(m.group(1)))
    return out


def build_state(cfg: dict, project: dict, gh_meta: dict, sessions: list, sess_info: dict,
                file_ticks: list, scanner: LocalScanner, demo: bool = False, manifests=None) -> dict:
    t_now = now()
    root = expand(cfg["root"]) if cfg.get("root") else ""
    columns = list(project.get("columns") or [])
    items = list(project.get("items") or [])

    # danh sách repo: cấu hình, project, phiên agent
    names = []
    for n in (cfg.get("repos") or []):
        if n not in names:
            names.append(n)
    counts_by_repo = {}
    for it in items:
        counts_by_repo[it["repo"]] = counts_by_repo.get(it["repo"], 0) + 1
    for n in sorted(counts_by_repo, key=lambda k: -counts_by_repo[k]):
        if n.lower() not in (x.lower() for x in names):
            names.append(n)
    repo_paths = scanner.repo_paths(names)
    accounts = {} if demo else scanner.session_accounts(repo_paths)

    # gán repo cho từng phiên
    by_repo_sessions = {}
    for s in sessions:
        name = repo_for_cwd(s.get("cwd"), repo_paths, root) or repo_for_projectdir(s.get("projectDir", ""), repo_paths)
        if not name:
            continue
        canon = next((n for n in names if n.lower() == name.lower()), None)
        if canon is None:
            canon = name
            names.append(name)
            repo_paths[name] = os.path.join(root, name)
        by_repo_sessions.setdefault(canon, []).append(s)

    # runner: chọn nguồn tick mới nhất cho mỗi repo
    runner_src = {}
    for name, ss in by_repo_sessions.items():
        for s in ss:
            if s["ticks"]:
                last = s["ticks"][-1]["at"]
                if name not in runner_src or runner_src[name]["last"] < last:
                    runner_src[name] = {"last": last, "ticks": s["ticks"], "finishedAt": s.get("finishedAt"),
                                        "source": "transcript", "manifestHint": s.get("manifest")}
    for repo, path, ticks, fin, mtime in file_ticks:
        if not repo or not ticks:
            continue
        canon = next((n for n in names if n.lower() == repo.lower()), repo)
        last = ticks[-1]["at"]
        if canon not in runner_src or runner_src[canon]["last"] < last:
            runner_src[canon] = {"last": last, "ticks": ticks, "finishedAt": fin, "source": path, "manifestHint": None}

    runner_by_repo = {}
    for name, src in runner_src.items():
        tick = src["ticks"][-1]
        age = t_now - tick["at"]
        fin = src.get("finishedAt")
        if fin and fin >= tick["at"] - 5:
            state = "finished"
        elif age > 300:
            state = "stale"
        else:
            busy = any(not l["idle"] for l in tick["lanes"].values())
            state = "running" if busy else "idle"
        hist = [{"at": t["at"], "time": t["time"], "counts": t["counts"], "waiting": t["waiting"]} for t in src["ticks"][-90:]]
        runner_by_repo[name] = {
            "tick": tick, "history": hist, "state": state, "finishedAt": fin,
            "source": src["source"], "manifestHint": src.get("manifestHint"),
        }

    # merge train (#562): train còn sống thì runner không "mất tín hiệu" (tick đứng vì chờ train), thẻ trong train mang nhãn gate merge,
    # thẻ đã vào hàng đợi mà chưa vào train mang nhãn chờ train. Mọi lỗi đọc file = không có train.
    trains = {}
    merge_tags = {}  # (repo thường, số thẻ) -> "gate" | "merge" | "wait"
    for name in names:
        rp = repo_paths.get(name) or os.path.join(root, name)
        tr = read_merge_train(rp)
        if tr:
            trains[name] = tr
            if name in runner_by_repo and runner_by_repo[name]["state"] == "stale":
                runner_by_repo[name]["state"] = "merging"
        for n in read_queued_cards(rp):
            merge_tags[(name.lower(), n)] = "wait"
        if tr:
            for n in tr["cards"]:
                merge_tags[(name.lower(), n)] = tr["step"]
    if merge_tags:
        items = [dict(it, mergeTag=merge_tags[(it["repo"].lower(), int(it["number"]))])
                 if it.get("status") == "Review" and str(it.get("number") or "").isdigit()
                 and (it["repo"].lower(), int(it["number"])) in merge_tags else it for it in items]

    # chưa đọc được Project: dựng cột tạm từ các cột runner đang đếm
    if not columns and runner_by_repo:
        for rn in runner_by_repo.values():
            for key in rn["tick"]["counts"]:
                if key not in [c["name"] for c in columns]:
                    columns.append({"name": key, "kind": column_kind(key), "ghColor": None, "fromRunner": True})

    # chỉ mục item theo (repo, số)
    item_idx = {}
    for it in items:
        if it["number"]:
            item_idx[(it["repo"].lower(), it["number"])] = it
    col_by_kind = {}
    for c in columns:
        col_by_kind.setdefault(c["kind"], c["name"])

    active_s = float(cfg["activeMinutes"]) * 60
    workers = []
    for name in names:
        rn = runner_by_repo.get(name)
        lanes = {}
        if rn:
            running = rn["state"] in ("running", "idle")
            for key in sorted(rn["tick"]["lanes"]):
                lane = rn["tick"]["lanes"][key]
                card = lane["card"]
                busy = (not lane["idle"]) and running
                if lane["idle"] and not running:
                    continue  # runner đã dừng: không dựng bàn trống cho lane
                it = item_idx.get((name.lower(), card)) if card else None
                column = it["status"] if (it and not lane["idle"]) else col_by_kind.get(LANE_KIND.get(key))
                w = {
                    "id": f"{name}:lane:{key}", "repo": name, "kind": "lane", "laneKey": key,
                    "lane": LANE_LABEL.get(key, key.upper()), "busy": busy,
                    "issue": card if not lane["idle"] else None, "lastCard": card,
                    "column": column, "itemId": it["id"] if (it and not lane["idle"]) else None,
                    "session": None, "status": "working" if busy else "idle",
                }
                lanes[key] = w
                workers.append(w)
        busy_cards = {w["issue"] for w in lanes.values() if w["busy"] and w["issue"]}
        repo_numbers = {k[1] for k in item_idx if k[0] == name.lower()}
        shown_away = 0
        for s in sorted(by_repo_sessions.get(name, []), key=lambda x: -(x["lastTs"] or 0)):
            if not s.get("texts") and not s.get("tools"):
                continue
            p_issue, p_lane, t_issue, t_lane, mentions = session_hints(s)
            issue, source = p_issue, "path" if p_issue else None
            lane_name = p_lane or t_lane
            if not issue and t_issue:
                issue, source = t_issue, "command"
            if not issue:
                for n in mentions:
                    if n in busy_cards:
                        issue, source = n, "mention"
                        break
            if not issue:
                for n in mentions:
                    if n in repo_numbers:
                        issue, source = n, "mention"
                        break
            if not issue and mentions:
                issue, source = mentions[0], "mention"
            active = (t_now - (s["lastTs"] or 0)) <= active_s
            target = None
            for w in lanes.values():
                if w["busy"] and issue and w["issue"] == issue:
                    target = w
                    break
            if target is None and lane_name and LANE_KEY_OF.get(lane_name) in lanes:
                lw = lanes[LANE_KEY_OF[lane_name]]
                if lw["busy"]:
                    target = lw
            if target is not None:
                if target["session"] is None:
                    target["session"] = slim_session(s, accounts=accounts)
                    target["issueSource"] = source
                continue
            if not active:
                if shown_away >= 1:
                    continue
                shown_away += 1
            it = item_idx.get((name.lower(), issue)) if issue else None
            column = it["status"] if it else (col_by_kind.get(LANE_KIND.get(LANE_KEY_OF.get(lane_name or ""), "")) if lane_name else None)
            workers.append({
                "id": f"{name}:s:{s['id']}", "repo": name, "kind": "session",
                "laneKey": LANE_KEY_OF.get(lane_name or ""), "lane": (lane_name or "").capitalize() if lane_name else None,
                "busy": active, "issue": issue, "issueSource": source, "lastCard": issue,
                "column": column, "itemId": it["id"] if it else None,
                "session": slim_session(s, accounts=accounts), "status": "working" if active else "away",
            })

    # tóm tắt repo
    repos = []
    for name in names:
        rp = repo_paths.get(name) or os.path.join(root, name)
        rc = {}
        for it in items:
            if it["repo"].lower() == name.lower():
                rc[it["status"]] = rc.get(it["status"], 0) + 1
        ws = [w for w in workers if w["repo"] == name]
        has_any = rc or ws or name in runner_by_repo or os.path.isdir(rp)
        if not has_any:
            continue
        manifest = (manifests or {}).get(name) if demo else scanner.newest_manifest(rp)
        full = next((it["repoFull"] for it in items if it["repo"].lower() == name.lower() and it.get("repoFull")), None)
        repos.append({
            "name": name, "path": rp, "exists": os.path.isdir(rp) or demo,
            "full": full or f"{cfg['github']['owner']}/{name}",
            "counts": rc, "total": sum(rc.values()),
            "runner": runner_by_repo.get(name), "train": trains.get(name),
            "working": sum(1 for w in ws if w["status"] == "working"),
            "manifest": manifest,
        })
    # repo của project không có item nào trùng tên (vd. "Nháp") vẫn hiện
    known = {r["name"].lower() for r in repos}
    for it in items:
        if it["repo"].lower() not in known:
            known.add(it["repo"].lower())
            rc = {}
            for x in items:
                if x["repo"] == it["repo"]:
                    rc[x["status"]] = rc.get(x["status"], 0) + 1
            repos.append({"name": it["repo"], "path": None, "exists": False, "counts": rc, "full": it.get("repoFull"),
                          "total": sum(rc.values()), "runner": None, "working": 0, "manifest": None})

    # thông báo
    notices = []
    if demo:
        notices.append({"level": "info", "text": "Chế độ demo: số liệu runner lấy từ ảnh chụp lúc 14:44, tên việc là dữ liệu mẫu."})
    if gh_meta.get("error"):
        err = gh_meta["error"]
        if err == "NO_GH":
            notices.append({"level": "error", "text": "Không tìm thấy GitHub CLI nên chưa đọc được Project.", "cmd": "brew install gh && gh auth login"})
        elif re.search(r"scope|read:project|INSUFFICIENT", err, re.I):
            notices.append({"level": "error", "text": "Token gh chưa có quyền với Project (cần quyền project để đọc và sửa).", "cmd": "gh auth refresh -s project"})
        else:
            notices.append({"level": "error", "text": "Lỗi đọc GitHub Project: " + err[:240], "cmd": "gh auth status"})
    if not demo and not sess_info.get("ok"):
        notices.append({"level": "warn", "text": f"Không thấy thư mục transcript {sess_info.get('dir')}. Sửa claudeProjectsDir trong config.json."})
    if not demo and not runner_by_repo:
        notices.append({"level": "info", "text": "Chưa thấy dòng [RUNNER] tick nào. Nếu runner chỉ in ra terminal, ghi thêm ra file log:",
                        "cmd": "<lệnh chạy runner> 2>&1 | tee -a ~/.agent-office/logs/<TênRepo>.log"})

    state = {
        "demo": demo,
        "root": root,
        "project": {
            "title": project.get("title"), "url": project.get("url"), "viewName": project.get("viewName"),
            "viewLayout": project.get("viewLayout"), "viewFilter": project.get("viewFilter"),
            "statusField": project.get("statusField"), "totalCount": len(items),
            "writable": bool(demo or (project.get("id") and project.get("statusFieldId") and gh_meta.get("ok"))),
            "selectFields": project.get("selectFields") or [],
            "ok": gh_meta.get("ok"), "fetchedAt": gh_meta.get("fetchedAt"), "error": gh_meta.get("error"),
        },
        "columns": columns,
        "items": items,
        "repos": repos,
        "workers": workers,
        "notices": notices,
        "sources": {"transcripts": sess_info, "tickFiles": [p for _, p, _, _, _ in file_ticks]},
        "config": {"activeMinutes": cfg["activeMinutes"], "githubSeconds": cfg["githubSeconds"]},
    }
    body = json.dumps(state, ensure_ascii=False, sort_keys=True)
    state["version"] = hashlib.sha1(body.encode("utf-8")).hexdigest()[:12]
    state["generatedAt"] = t_now
    return state


# ----------------------------------------------------------------- demo
def demo_data(cfg: dict):
    """Dựng lại ảnh chụp runner 14:44:50 ngày 21/10; tên việc là dữ liệu mẫu."""
    t0 = (now() // 120) * 120 + 60  # chỉ dời mốc 2 phút/lần để giao diện không dựng lại liên tục
    snap = datetime.fromtimestamp(t0).replace(hour=14, minute=44, second=50)
    shift = t0 - snap.timestamp()

    def at(hms):
        h, m, s = (int(x) for x in hms.split(":"))
        return snap.replace(hour=h, minute=m, second=s).timestamp() + shift

    columns = [{"name": n, "kind": column_kind(n), "ghColor": None} for n in ("Ready", "Building", "QA", "Review", "Blocked", "Done")]
    plan = {
        "agent-workbench": {"Ready": [81, 82, 83], "Building": [74, 78], "QA": [17], "Blocked": [60, 63], "Done": [70, 71, 72, 73]},
        "GeelyEx2": {"Blocked": [41, 35, 36, 37, 38, 39, 40], "Done": [30, 31, 32, 33, 34]},
        "OfficeReader": {"Building": [172], "Review": [87], "Blocked": [150, 151, 152, 153, 154, 155, 156], "Done": [160, 161, 162, 163, 164, 165]},
        "Goods-Triple": {"Blocked": list(range(1, 13))},
        "Neighbours": {"Review": [19, 22, 25], "Blocked": list(range(26, 37)), "Done": [10, 11, 12, 13, 14]},
    }
    known = {("OfficeReader", 87): "Refactor nhóm C D2 (PR #179)"}
    items = []
    for repo, cols in plan.items():
        for col, nums in cols.items():
            for n in nums:
                items.append({
                    "id": f"demo-{repo}-{n}", "number": str(n), "title": known.get((repo, n), f"Việc mẫu {repo} #{n}"),
                    "url": None, "type": "Issue", "state": "CLOSED" if col == "Done" else "OPEN", "isDraft": False,
                    "repo": repo, "repoFull": f"ToanMobile/{repo}", "status": col, "assignees": [], "labels": [],
                    "fields": {}, "updatedAt": t0 - 3600,
                })
    you = {("agent-workbench", "60"): ["npx prisma migrate deploy  # database live"], ("agent-workbench", "63"): [], ("GeelyEx2", "41"): []}
    for it in items:
        steps = you.get((it["repo"], it["number"]))
        if steps is not None:  # thẻ 🙋 mẫu cho khung "Cần bạn duyệt"
            it["labels"] = [{"name": NEEDS_YOU_LABEL, "color": "D93F0B"}]
            it["approval"] = {"steps": steps, "approved": False}
        if it["repo"] == "agent-workbench" and it["number"] == "60":
            it["title"] = "Thêm cột plan vào bảng đơn hàng"
            it["lastComment"] = {"body": "🙋 Cần bạn: chạy migration trên database live (robot không được chạm) · xong thì comment đúng một chữ done trên issue để duyệt", "author": "review-agent", "at": at("13:40:00")}
        if it["repo"] == "GeelyEx2" and it["number"] == "41":
            it["lastComment"] = {"body": "CHƯA XONG: worktree build cũ của #41 còn 2 file sổ sách chưa về main. Hook của người dùng chặn `git checkout --` nên tôi không lách. Theo quy trình, worktree còn thay đổi thì chặn thẻ và nêu lý do. Cần bạn xem 2 file trong .agents/CHECKLIST rồi gỡ chặn.", "author": "build-agent", "at": at("13:57:20")}
    for c in columns:
        c["optionId"] = "opt-" + c["name"]
    prio = [{"id": "p-" + n, "name": n, "color": col} for n, col in (("P0", "RED"), ("P1", "ORANGE"), ("P2", "GRAY"))]
    project = {"id": "demo", "statusFieldId": "demo-status", "statusField": "Status",
               "selectFields": [{"id": "demo-status", "name": "Status", "options": [{"id": c["optionId"], "name": c["name"], "color": None} for c in columns]},
                                {"id": "demo-prio", "name": "Priority", "options": prio}],
               "title": "ToanMobile Project 1 (demo)", "url": "https://github.com/users/ToanMobile/projects/1",
               "viewName": "View 2", "columns": columns, "items": items}

    def tick(hms, r, b, q, rv, bl, lanes, waiting=0):
        lanes_d = {k: {"idle": v[0] == 1, "card": v[1]} for k, v in lanes.items()}
        return {"time": hms, "at": at(hms), "counts": {"Ready": r, "Building": b, "QA": q, "Review": rv, "Blocked": bl},
                "lanes": lanes_d, "waiting": waiting}

    root = expand(cfg["root"])

    def sess(repo_dir, sid, last, texts, tools, ticks=None, tokens=None, finished=None, manifest=None, account=None):
        return {"id": sid, "file": "", "cwd": os.path.join(root, repo_dir), "branch": "main", "lastTs": at(last),
                "account": account, "configDir": "~/.claude-" + account if account else None,
                "texts": [{"ts": at(last) - 60 * (len(texts) - i), "text": x} for i, x in enumerate(texts)],
                "tools": [{"ts": at(last) - 20 * (len(tools) - i), "name": n, "summary": s} for i, (n, s) in enumerate(tools)],
                "ticks": ticks or [], "tokensLeft": tokens, "finishedAt": at(finished) if finished else None,
                "manifest": manifest, "subagent": False, "projectDir": encode_path(os.path.join(root, repo_dir))}

    aw_ticks = [tick(h, 3, 2, 1, 0, 2, {"b": (0, "74"), "q": (0, "17"), "r": (1, None)})
                for h in ("14:39:38", "14:40:11", "14:40:46", "14:41:20", "14:41:54", "14:42:28", "14:43:01", "14:43:36", "14:44:10", "14:44:44")]
    ge_ticks = [tick("13:56:49", 0, 0, 1, 0, 6, {"b": (1, "41"), "q": (1, "41"), "r": (1, None)}),
                tick("13:57:25", 0, 0, 0, 0, 7, {"b": (1, "41"), "q": (1, "41"), "r": (1, None)})]
    or_ticks = [tick("14:44:37", 0, 1, 0, 1, 7, {"b": (0, "172"), "q": (1, None), "r": (0, "87")})]
    gt_ticks = [tick(h, 0, 0, 0, 0, 12, {"b": (1, "1"), "q": (1, None), "r": (1, None)})
                for h in ("14:42:11", "14:42:44", "14:43:18", "14:43:52", "14:44:25")]
    nb_ticks = [tick(h, 0, 0, 0, 3, 11, {"b": (1, "41"), "q": (1, "41"), "r": (0, "19")})
                for h in ("14:42:08", "14:42:41", "14:43:15", "14:43:49", "14:44:23")]

    sessions = [
        sess("agent-workbench", "63413c7c-ec10-401b-9985-fc2720ba1e19", "14:44:44", [
            "Tự xử lý luôn. Kế hoạch: chỉ lấy đúng 4 dòng checklist từ worktree của #41 (không lấy code của PR), đưa vào main GeelyEx2.",
            "Tôi đang đọc phần code kit lo việc gỡ worktree và lưu bản sao dự phòng, để viết bản sửa dùng lại đúng những hàm đã có.",
            "Viết test (thay cho ca wt-k cũ, thêm ca giống #41 và ca dòng do người viết):",
            "ĐỎ đúng như #41: worktree chỉ có sổ sách tự sinh bị từ chối (wt-k, wt-s), còn ca dòng do người viết vẫn bị chặn như mong muốn.",
            "ĐỎ→XANH. Thử ngay với worktree thật của #41 (chỉ đọc), bằng code mới: kit còn chặn gì không?",
        ], [
            ("Bash", "grep -n \"_GENERATED_KEYS\" universal-agent-devkit/scripts/git/worktree.py | head -3"),
            ("Bash", "sed -n 2160,2200p universal-agent-devkit/scripts/git/worktree.py"),
            ("EnterWorktree", ".claude/worktrees/kit-rm-regenerated"),
            ("Read", root + "/agent-workbench/.claude/worktrees/kit-rm-regenerated/universal-agent-devkit/tests/worktree_git/test_worktree_checklist.sh"),
            ("Edit", root + "/agent-workbench/.claude/worktrees/kit-rm-regenerated/universal-agent-devkit/scripts/git/worktree.py"),
            ("Bash", "bash universal-agent-devkit/tests/worktree_git/test_worktree_checklist.sh 2>&1 | grep -E \"^✗|^✓\""),
            ("Bash", "python3 -c \"…\""),
        ], ticks=aw_ticks, tokens=1234567, account="max"),
        sess("GeelyEx2", "8592ef54-f992-46a5-b40e-3572a43ad563", "13:57:25", [
            "Đang xử lý: worktree build cũ của #41 còn 2 file sổ sách chưa về main nên `remove` bị từ chối. Tôi kiểm tra nội dung các file đó.",
            "Hai file đó do gate sinh tự động (dòng \"không sửa tay\", sinh lại được), nhánh không có commit chưa đẩy. Tôi reset chúng.",
            "Hook của người dùng chặn `git checkout --` nên tôi không lách. Theo quy trình, worktree còn thay đổi thì chặn thẻ và nêu lý do.",
            "Hook khớp chuỗi trong heredoc. Tôi ghi file bằng Write, rồi chỉ gọi lệnh gh.",
            "CHƯA XONG: thẻ #41 đã chuyển sang Blocked, chưa chạy QA.",
        ], [
            ("Bash", "cd " + root + "/GeelyEx2/.claude/worktrees/issue-41-build && git diff --stat -- .agents/CHECKLIST"),
            ("Bash", "cd " + root + "/GeelyEx2 && git -C .claude/worktrees/issue-41-build checkout -- .agents/CHECKLIST"),
            ("Write", "/private/tmp/claude-501/-Volumes-Data-Toan-GeelyEx2/8592ef54-f992-46a5-b40e-3572a43ad563/scratchpad/block-41.md"),
            ("Bash", "gh issue comment 41 --body-file /private/tmp/claude-501/…/block-41.md"),
        ], ticks=ge_ticks, tokens=14874653, finished="13:57:25", manifest="docs/super-board/runs/2026-10-21-geelyex2.md", account="finos"),
        sess("OfficeReader/OfficeReader", "issue-87-review", "14:44:37", [
            "Đang review PR #179 (issue #87): chỉ thêm bằng chứng QA, nên tôi đang kiểm tra threads, bằng chứng D2 và đối chiếu với A.",
        ], [
            ("Bash", "git show origin/issue-87-refactor-nhom-c-d2:docs/"),
            ("Bash", "git fetch origin 2>&1|tail -1; agent-kit worktree add .claude/worktrees/issue-87-review --lane=review"),
            ("Bash", "ls -d .claude/worktrees/issue-87-review 2>&1; git worktree list | grep issue-87; gh run view 3938905"),
            ("Bash", "git diff --name-status origin/main...origin/issue-87-refactor-nhom-c-d2"),
            ("Bash", "cd .claude/worktrees/issue-87-review && git diff --name-only"),
        ], ticks=or_ticks, tokens=14887973, account="finos_team"),
        sess("Goods-Triple", "goods-triple-runner", "14:44:25", [], [], ticks=gt_ticks),
        sess("Neighbours", "neighbours-runner", "14:44:23", [], [], ticks=nb_ticks),
    ]
    manifests = {"GeelyEx2": {"path": "docs/super-board/runs/2026-10-21-geelyex2.md", "mtime": at("13:57:25")}}
    return project, sessions, manifests


# ----------------------------------------------------------------- ghi lên GitHub
M_SET = """mutation($p: ID!, $i: ID!, $f: ID!, $o: String!) {
  updateProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f, value: {singleSelectOptionId: $o}}) { projectV2Item { id } } }"""
M_DRAFT = """mutation($p: ID!, $t: String!, $b: String) {
  addProjectV2DraftIssue(input: {projectId: $p, title: $t, body: $b}) { projectItem { id } } }"""
Q_REPO = """query($o: String!, $n: String!) { repository(owner: $o, name: $n) { id } }"""
M_ISSUE = """mutation($r: ID!, $t: String!, $b: String) {
  createIssue(input: {repositoryId: $r, title: $t, body: $b}) { issue { id number url } } }"""
M_ADD = """mutation($p: ID!, $c: ID!) { addProjectV2ItemById(input: {projectId: $p, contentId: $c}) { item { id } } }"""
M_COMMENT = """mutation($s: ID!, $b: String!) { addComment(input: {subjectId: $s, body: $b}) { clientMutationId } }"""
M_ARCHIVE = """mutation($p: ID!, $i: ID!) { archiveProjectV2Item(input: {projectId: $p, itemId: $i}) { item { id } } }"""
Q_COMMENTS = """query($id: ID!) { node(id: $id) { ... on Issue { comments(last: 15) { nodes { body createdAt author { login } } } } } }"""

# Khung "Cần bạn duyệt" (block-template.md, mục 🙋): lệnh chỉ người được chạy là dòng `needs-you: <lệnh>` của merge gate
# hoặc mục checklist "- [ ] Run `<lệnh>`"; chỉ một comment đúng chữ `done` sau yêu cầu mới nhất mới cho wave sau chạy tiếp.
NEEDS_YOU_LABEL = "needs-you"
APPROVE_TEXT = "done"
STEP_GATE_RE = re.compile(r"^[^\n`]*?(?<![\w-])needs-you:[ \t]*(?!done\b)(\S.*?)\s*$", re.I | re.M)
STEP_RUN_RE = re.compile(r"^\s*[-*]\s*\[ \]\s*Run\s+`([^`\n]+)`", re.I | re.M)
REQUEST_RE = re.compile(r"super-board:needs-you|🙋|approval-request:|needs-you:[ \t]*(?!done\b)\S", re.I)
APPROVAL_MAX_FETCH = 20   # thẻ 🙋 đọc comment mỗi lần đọc board (thẻ không đổi dùng lại kết quả cũ)


def approval_info(comments: list) -> dict:
    """Từ comment của issue (cũ trước mới sau): lệnh của yêu cầu 🙋 mới nhất, và đã có `done` sau yêu cầu đó chưa.
    ponytail: chỉ đọc 15 comment cuối, không đọc thân PR; dòng needs-you chỉ nằm trong PR thì không thấy, khi đó thêm bước đọc PR."""
    steps, approved = [], False
    for c in comments:
        body = (c or {}).get("body") or ""
        if body.strip() == APPROVE_TEXT:
            approved = True
            continue
        if not REQUEST_RE.search(body):
            continue
        approved = False  # yêu cầu mới: `done` cũ không còn tính
        found = [m.strip().strip("`").strip() for m in STEP_GATE_RE.findall(body)] + STEP_RUN_RE.findall(body)
        if found:
            steps = list(dict.fromkeys(s for s in found if s))
    return {"steps": steps[:8], "approved": approved}


def friendly(err: str) -> str:
    if err == "NO_GH":
        return "Chưa cài GitHub CLI (gh)."
    if re.search(r"scope", err, re.I):
        return "Token gh thiếu quyền project. Chạy: gh auth refresh -s project"
    return err


# ----------------------------------------------------------------- app
def mac_notify(text: str):
    """Thông báo macOS, chạy được cả khi không mở trang."""
    if sys.platform != "darwin" or not shutil.which("osascript"):
        return
    safe = text.replace("\\", "\\\\").replace('"', '\\"')
    try:
        subprocess.Popen(["osascript", "-e", f'display notification "{safe}" with title "Xưởng agent"'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as exc:
        warn("osascript", exc)


# ---- nhắn lệnh cho agent super-board: hộp thư đọc bằng hook PostToolUse (agent đang chạy) hoặc resume (đã dừng)
MSG_MAX = 4000                 # ký tự mỗi lệnh
MSG_RATE, MSG_WINDOW = 6, 60.0  # tối đa 6 request mỗi phút, tính cả request bị từ chối và lần nhập mã
CODE_TTL, CODE_TRIES = 120.0, 3  # mã xác nhận lệnh từ điện thoại: hạn 2 phút, sai 3 lần thì huỷ
PENDING_MAX = 5                  # lệnh chờ mã cùng lúc: hơn thế là có ai đang bắn thông báo mã lên Mac
MSG_KEEP = 50
WORKER_LOG_GLOB = os.path.join("docs", "super-board", "runs", "*-workers", "worker-*.log")
DISPATCH_RE = re.compile(r"^=== dispatch lane=(\S+) issue=#(\d+)", re.M)
SECTION_SID_RE = re.compile(r'^agent_office: session_id=([0-9a-f-]{36})$|"session_id":"([0-9a-f-]{36})"', re.M)
POOL_CFG_RE = re.compile(r"^account_pool: engine=claude account=\S+ config_dir=(\S+)$", re.M)
POOL_LINE_RE = re.compile(r"^account_pool: engine=\S+ account=(\S+) config_dir=(\S+)\s*$")  # tài khoản của phiên cho góc phải trên
PROC_SID_RE = re.compile(r"--(?:session-id|resume)[ =]([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b")


class RateLimited(ValueError):
    """Quá MSG_RATE lệnh trong MSG_WINDOW giây: handler trả HTTP 429."""


def find_worker_session(sid: str, repo_paths: dict, max_age_days: float = 7):
    """Phiên worker super-board có session id `sid`: repo, thẻ, lane, config_dir, cwd và model lúc giao, lấy từ log worker.
    Chỉ phiên chính của một lần giao (session id đầu tiên sau dòng `=== dispatch`), không phải subagent. Không thấy: None."""
    needle, cutoff = sid.encode(), now() - max_age_days * 86400
    for repo, rp in repo_paths.items():
        logs = []
        for p in glob.glob(os.path.join(rp, WORKER_LOG_GLOB)):
            try:
                if os.path.getmtime(p) >= cutoff:
                    logs.append(p)
            except OSError:
                continue
        for log in logs:
            try:
                with open(log, "rb") as f:
                    data = f.read()
            except OSError as e:
                warn("đọc log worker " + log, e)
                continue
            if needle not in data:
                continue
            text = data.decode("utf-8", "replace")
            heads = list(DISPATCH_RE.finditer(text))
            for i, h in enumerate(heads):
                sec = text[h.start(): heads[i + 1].start() if i + 1 < len(heads) else len(text)]
                m = SECTION_SID_RE.search(sec)
                if not m or (m.group(1) or m.group(2)) != sid:
                    continue
                pool = POOL_CFG_RE.search(sec)
                cwd, model = None, None
                for line in sec.splitlines():
                    if line.startswith('{"type":"system","subtype":"init"'):
                        try:
                            init = json.loads(line)
                            cwd, model = init.get("cwd"), init.get("model")
                        except ValueError as e:  # dòng init hỏng: không có cwd nên _target từ chối resume
                            warn("dòng init trong log worker " + log, e)
                        break
                return {"repo": repo, "repoPath": rp, "log": log, "lane": h.group(1), "issue": h.group(2),
                        "configDir": pool.group(1) if pool else None, "cwd": cwd, "model": model,
                        "hasInbox": bool(m.group(1))}
    return None


def latest_card_session(repo_path: str, issue: str, max_age_days: float = 7):
    """Phiên chính của lần giao gần nhất cho thẻ `issue` (log worker mới nhất của thẻ): đích để nhắn/resume thẻ đã dừng."""
    cutoff, best = now() - max_age_days * 86400, None
    for p in glob.glob(os.path.join(repo_path, "docs", "super-board", "runs", "*-workers", f"worker-*-{issue}.log")):
        try:
            mt = os.path.getmtime(p)
        except OSError:
            continue
        if mt >= cutoff and (best is None or mt > best[0]):
            best = (mt, p)
    if not best:
        return None
    try:
        with open(best[1], "rb") as f:
            text = f.read().decode("utf-8", "replace")
    except OSError as e:
        warn("đọc log worker " + best[1], e)
        return None
    heads = list(DISPATCH_RE.finditer(text))
    if not heads:
        return None
    m = SECTION_SID_RE.search(text, heads[-1].start())
    if not m:
        return None
    return {"sid": m.group(1) or m.group(2), "lane": heads[-1].group(1), "at": best[0]}


def inflight_live(repo_path: str, issue: str) -> bool:
    """Thẻ còn worker của runner (lock .claude/super-board/inflight/<số thẻ>, INFLIGHT_DIR của super-board-run.sh, PID sống),
    lane nào cũng tính. Lock đọc lỗi hoặc PID không đọc được thì coi như còn chạy: không resume (fail closed)."""
    p = os.path.join(repo_path, ".claude", "super-board", "inflight", issue)
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            kv = dict(line.split("=", 1) for line in f.read().splitlines() if "=" in line)
        os.kill(int(kv.get("PID", "").strip()), 0)
        return True
    except FileNotFoundError:
        return False
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # tiến trình có thật nhưng của người khác
    except (OSError, ValueError) as e:
        warn("đọc lock " + p, e)
        return True


def local_request(headers, client_ip: str, allowed: set) -> bool:
    """Chính máy Mac: kết nối từ loopback, Host trong danh sách cho phép, không có header của tunnel. Chỉ tin header thì
    máy khác trong LAN (khi server bind 0.0.0.0) giả được `Host: 127.0.0.1` để thành "từ Mac"."""
    try:
        loop = ipaddress.ip_address(str(client_ip).split("%")[0]).is_loopback
    except ValueError:
        return False
    return loop and host_name(headers.get("Host")) in allowed and not any(headers.get(h) for h in TUNNEL_HEADERS)


def ps_claude_sids() -> set:
    """Session id của mọi tiến trình claude đang chạy với --session-id/--resume. Lỗi thì ném lên (không gửi)."""
    out = subprocess.run(["ps", "-axww", "-o", "command="], capture_output=True, text=True, timeout=5, check=True).stdout
    return {m.group(1) for line in out.splitlines() if "claude" in line for m in PROC_SID_RE.finditer(line)}


def spawn_detached(argv, env, cwd, log):
    with open(log, "ab") as f:
        return subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.STDOUT,
                                start_new_session=True)


ROW_FROM_RUNNER = {"running": "idle", "idle": "idle", "merging": "idle", "stale": "stale", "finished": "stopped"}


class App:
    def __init__(self, cfg: dict, demo: bool):
        self.cfg = cfg
        self.demo = demo
        self.scanner = LocalScanner(cfg)
        self.lock = threading.Lock()
        self.project = {"columns": [], "items": []}
        self.gh_meta = {"ok": None, "error": None, "fetchedAt": None}
        self.sessions, self.sess_info, self.file_ticks = [], {"ok": False}, []
        self.state_bytes = b"{}"
        self.state_gz = GzipCache()
        # demo không mở gate_full.py thật (không lịch, không hàng đợi); test đặt cfg["gateFull"] = thư mục LaunchAgents giả
        self.gatefull = None if demo and not cfg.get("gateFull") else gate_full_runner.GateFull(cfg)
        self.refresh_evt = threading.Event()
        self.wake_evt = threading.Event()  # đánh thức local_loop khi có người xem trở lại (github_loop dùng refresh_evt)
        self.backfilled = set()  # thẻ đã thử đặt Backlog, mỗi thẻ chỉ thử một lần
        self.approvals = {}      # thẻ 🙋: item id -> (updatedAt, approval_info) để không đọc lại comment của thẻ không đổi
        self.prev_needs = None   # thẻ 🙋 chờ duyệt ở lần dựng trước: thẻ mới vào thì báo (toast, thông báo trình duyệt và macOS)
        self.deciding = set()    # thẻ đang gửi Duyệt/Từ chối: bấm lần hai (máy Mac và điện thoại cùng lúc) bị từ chối
        self.demo_manifests = None
        # nhắn lệnh cho agent: lệnh đã gửi (id -> trạng thái), lệnh từ điện thoại chờ mã, resume đang chạy, mốc rate limit
        self.msgs, self.pending, self.resumes, self.msg_times = {}, {}, {}, {}
        self.msg_lock = threading.Lock()  # một lệnh một lúc: hai lần gửi không resume cùng một phiên hai lần
        self._ps_sids, self._spawn = ps_claude_sids, spawn_detached
        # inboxDir khác mặc định chỉ hợp cho test và phiên resume (server truyền AGENT_OFFICE_INBOX); worker của runner
        # không có biến này nên hook của nó luôn đọc ~/.agent-office/inbox
        self.inbox_dir = expand(cfg.get("inboxDir") or "~/.agent-office/inbox")
        self.resume_dir = expand(cfg.get("resumeLogDir") or "~/.agent-office/resume")
        # nhật ký sự kiện: lưu ra file để còn nguyên khi tải lại trang hoặc khởi động lại server
        self.events, self.prev_rows, self.prev_items, self.user_moves = [], None, None, {}
        self.started_at, self.tally = time.time(), {"moves": 0, "done": 0, "blocked": 0}  # thống kê phiên: từ lúc server chạy
        self.events_path = expand(cfg.get("eventsFile") or "") if not demo else ""
        self._load_events()
        if demo:
            self.project, self.sessions, self.demo_manifests = demo_data(cfg)
            self.gh_meta = {"ok": True, "error": None, "fetchedAt": now()}
            self.sess_info = {"ok": True, "dir": "(demo)", "files": len(self.sessions)}

    def rebuild(self):
        host = host_stats(workload=not self.demo)  # ps/lsof chạy ngoài app.lock; demo không lộ tiến trình thật
        with self.lock:
            if self.demo:  # dời mốc thời gian để ảnh chụp luôn "vừa xảy ra"; giữ nguyên project để sửa được
                _, self.sessions, self.demo_manifests = demo_data(self.cfg)
            st = build_state(self.cfg, self.project, self.gh_meta, self.sessions, self.sess_info,
                             self.file_ticks, self.scanner, demo=self.demo, manifests=self.demo_manifests)
            self._diff(st)
            st["events"] = self.events[-120:]
            if self.events:
                st["version"] = hashlib.sha1((st["version"] + self.events[-1]["id"]).encode()).hexdigest()[:12]
            st["messages"] = self.messages_view()
            if st["messages"]:  # lệnh đổi trạng thái (đã đọc, resume xong) thì trang phải vẽ lại ô "Nhắn agent"
                sig = "".join(m["id"] + m["state"] for m in st["messages"])
                st["version"] = hashlib.sha1((st["version"] + sig).encode()).hexdigest()[:12]
            # ngoài mã phiên bản: số đổi liên tục mà không bắt trang dựng lại cảnh
            st["host"] = host
            st["session"] = dict(self.tally, since=self.started_at)
            if self.gatefull:  # ngoài mã phiên bản như host: trạng thái lượt gate-full không bắt dựng lại cảnh
                try:
                    st["gateFull"] = self.gatefull.status(self.gate_repo_paths())
                except Exception as e:  # noqa: BLE001
                    warn("gate-full status", e)
            self.state_bytes = json.dumps(st, ensure_ascii=False).encode("utf-8")

    # ---- nhật ký sự kiện
    def _load_events(self):
        if not self.events_path or not os.path.exists(self.events_path):
            return
        try:
            with open(self.events_path, encoding="utf-8") as f:
                lines = f.readlines()
            for line in lines[-300:]:
                try:
                    self.events.append(json.loads(line))
                except ValueError:
                    continue
            if len(lines) > 2000:  # gọn file, chỉ giữ 300 dòng cuối
                with open(self.events_path, "w", encoding="utf-8") as f:
                    f.writelines(lines[-300:])
        except OSError as exc:
            warn("events trim " + self.events_path, exc)

    def _log_event(self, text, tone, sel, important):
        ev = {"id": "%.3f-%d" % (now(), len(self.events)), "ts": now(), "text": text, "tone": tone, "sel": sel, "important": important}
        self.events.append(ev)
        self.events = self.events[-300:]
        if self.events_path:
            try:
                os.makedirs(os.path.dirname(self.events_path), exist_ok=True)
                with open(self.events_path, "a", encoding="utf-8") as f:
                    f.write(json.dumps(ev, ensure_ascii=False) + "\n")
            except OSError as exc:
                warn("events write " + self.events_path, exc)
        if important and self.cfg.get("macNotify", True) and not self.demo:
            mac_notify(text)
        print(f"[sự kiện] {text}", flush=True)

    def _diff(self, st):
        """So với lần dựng trước để biết: agent bắt đầu/dừng, runner chờ bạn, thẻ chuyển cột."""
        rows = {}
        for r in st["repos"]:
            working = sum(1 for w in st["workers"] if w["repo"] == r["name"] and w["status"] == "working")
            rn = r.get("runner")
            key = "working" if working else ROW_FROM_RUNNER.get(rn["state"] if rn else "", "none")
            rows[r["name"]] = (key, ((rn or {}).get("tick") or {}).get("waiting", 0), working)
        if self.prev_rows is not None:
            for name, (key, wait, working) in rows.items():
                pk, pw = self.prev_rows.get(name, ("none", 0))
                if pk == "none":
                    continue  # mới thấy repo này: lấy làm mốc, không báo
                sel = {"type": "repo", "id": name}
                if key != pk:
                    if key == "working":
                        self._log_event(f"{name} bắt đầu làm ({working} agent)", "running", sel, False)
                    elif key == "stopped":
                        self._log_event(f"{name} đã dừng", "finished", sel, True)
                    elif key == "stale":
                        self._log_event(f"{name} mất tín hiệu runner", "stale", sel, True)
                    elif key == "idle" and pk == "working":
                        self._log_event(f"{name} hết việc, runner đang chờ thẻ mới", "idle", sel, False)
                if wait > pw:
                    self._log_event(f"{name} đang chờ bạn ({wait})", "stale", sel, True)
        self.prev_rows = {k: (v[0], v[1]) for k, v in rows.items()}
        items = {it["id"]: it for it in st["items"]}
        if not items:
            return
        needs = {iid for iid, it in items.items() if self._needs_you(it) and not (it.get("approval") or {}).get("approved")}
        if self.prev_needs is not None:
            for iid in sorted(needs - self.prev_needs, key=lambda k: str(items[k].get("number"))):
                it = items[iid]
                self._log_event(f"#{it.get('number')} {it['repo']} cần bạn duyệt: {it.get('title') or ''}"[:160],
                                "stale", {"type": "approvals"}, True)
        self.prev_needs = needs
        if self.prev_items is not None:
            kinds = {c["name"]: c["kind"] for c in st["columns"]}
            self.tally = tally_moves(self.prev_items, {k: v["status"] for k, v in items.items()}, kinds, self.tally)
            for iid, it in items.items():
                ps = self.prev_items.get(iid)
                if not ps or ps == it["status"]:
                    continue
                label = (f"#{it['number']}" if it.get("number") else "Thẻ nháp") + f" {it['repo']}"
                sel = {"type": "item", "id": iid}
                kd = kinds.get(it["status"]) or column_kind(it["status"])
                if self.user_moves.pop(iid, None) == it["status"]:
                    self._log_event(f"Bạn chuyển {label} sang {it['status']}", "working", sel, False)
                elif kd == "blocked":
                    self._log_event(f"{label} bị chặn", "stale", sel, True)
                elif kd == "done":
                    self._log_event(f"{label} đã xong", "running", sel, False)
                else:
                    self._log_event(f"{label}: {ps} sang {it['status']}", "working", sel, False)
        self.prev_items = {k: v["status"] for k, v in items.items()}

    # ---- thao tác ghi (board thay thế cho GitHub)
    def _item(self, item_id):
        it = next((x for x in self.project.get("items", []) if x["id"] == item_id), None)
        if not it:
            raise ValueError("Không tìm thấy thẻ này, có thể vừa bị xoá trên GitHub.")
        return it

    def _part(self, item):
        """The Project that owns this card (single-project and demo data fall back to self.project)."""
        return (self.project.get("parts") or {}).get(item.get("pid")) or self.project

    def _select(self, field_name, part=None):
        f = next((x for x in ((part or self.project).get("selectFields") or []) if x["name"] == field_name), None)
        if not f:
            raise ValueError(f"Project không có trường chọn '{field_name}'.")
        return f

    def _set(self, item_id, field_name, option_name, part=None):
        if part is None:
            part = next((self._part(x) for x in self.project.get("items", []) if x["id"] == item_id), self.project)
        f = self._select(field_name, part)
        opt = next((o for o in f["options"] if o["name"] == option_name), None)
        if not opt:
            raise ValueError(f"Trường {field_name} không có lựa chọn '{option_name}'.")
        if not self.demo:
            gh_graphql(M_SET, {"p": part["id"], "i": item_id, "f": f["id"], "o": opt["id"]})
        return f, opt

    def _default_status(self, part):
        """Cột mặc định của thẻ mới: Backlog thật của Project đó, không bao giờ để 'Chưa có trạng thái'."""
        f = next((x for x in (part.get("selectFields") or []) if x["name"] == part.get("statusField")), None)
        return next((o["name"] for o in (f or {}).get("options", []) if column_kind(o["name"]) == "backlog"), None)

    def backfill_backlog(self, proj) -> int:
        """Thẻ đang mở vào Project mà chưa có Status (issue tự thêm, createTask) được đặt Backlog trên GitHub.
        Thẻ đã đóng/merge giữ nguyên; mỗi lần đọc board ghi tối đa BACKFILL_PER_POLL thẻ; lỗi GitHub tạm thời thì lần sau thử lại."""
        if self.demo:
            return 0
        done = 0
        for it in proj["items"]:
            if done >= BACKFILL_PER_POLL:
                break
            if it["status"] != NO_STATUS or it["id"] in self.backfilled or it.get("state") not in (None, "OPEN"):
                continue
            part = (proj.get("parts") or {}).get(it.get("pid")) or proj
            name = self._default_status(part)
            if not name:
                self.backfilled.add(it["id"])
                continue
            try:
                self._set(it["id"], part["statusField"], name, part)
            except GhError as e:  # mạng, rate limit: để lần đọc sau thử lại
                warn(f"đặt Backlog cho {it.get('number') or it['id']} (sẽ thử lại)", e)
                continue
            except (ValueError, KeyError) as e:  # Project không có cột đó: thử lại cũng hỏng
                self.backfilled.add(it["id"])
                warn(f"đặt Backlog cho {it.get('number') or it['id']}", e)
                continue
            self.backfilled.add(it["id"])
            done += 1
            with self.lock:
                it["status"] = name
                if getattr(self, "prev_items", None) is not None and it["id"] in self.prev_items:
                    self.prev_items[it["id"]] = name  # việc máy tự làm: không ghi thành sự kiện chuyển cột hay cộng vào tally
        with self.lock:
            if not any(i["status"] == NO_STATUS for i in proj["items"]):
                proj["columns"] = [c for c in proj["columns"] if not c.get("noStatus")]
        return done

    @staticmethod
    def _needs_you(it) -> bool:
        return (column_kind(it.get("status")) == "blocked"
                and any(l.get("name") == NEEDS_YOU_LABEL for l in it.get("labels") or []) and it.get("state") in (None, "OPEN"))

    def fill_approvals(self, proj) -> None:
        """Thẻ 🙋 mang `approval` = {steps, approved} đọc từ comment. Đọc lỗi thì thẻ không có `approval`:
        nút Duyệt khoá (không biết có lệnh nào phải chạy trước) cho tới lần đọc sau."""
        fetched = 0
        for it in proj["items"]:
            if not self._needs_you(it) or it.get("type") != "Issue" or not it.get("contentId"):
                continue
            hit = self.approvals.get(it["id"])
            if hit and hit[0] == it.get("updatedAt"):
                with self.lock:
                    it["approval"] = dict(hit[1])
                continue
            if fetched >= APPROVAL_MAX_FETCH:
                continue
            fetched += 1
            try:
                node = gh_graphql(Q_COMMENTS, {"id": it["contentId"]}).get("node") or {}
            except GhError as e:
                warn(f"đọc bước 🙋 của #{it.get('number')} (sẽ thử lại)", e)
                continue
            info = approval_info(((node.get("comments") or {}).get("nodes")) or [])
            with self.lock:
                self.approvals[it["id"]] = (it.get("updatedAt"), info)
                it["approval"] = dict(info)

    def _comment(self, it, text: str) -> None:
        if not self.demo:
            if not it.get("contentId") or it.get("type") not in ("Issue", "PullRequest"):
                raise ValueError("Bản nháp trên Project không nhận bình luận.")
            gh_graphql(M_COMMENT, {"s": it["contentId"], "b": text[:60000]})
        with self.lock:
            it["lastComment"] = {"body": text[:1500], "author": "bạn", "at": now()}

    def _decide(self, action: str, body: dict) -> dict:
        """Duyệt: comment đúng chữ `done` (không lấy chữ của client). Từ chối: comment lý do, thẻ ở nguyên Blocked.
        gh lỗi thì ném GhError lên (HTTP 502): không ghi là đã duyệt."""
        it = self._item(body["itemId"])
        label = f"#{it.get('number')} {it['repo']}"
        if not self._needs_you(it):
            raise ValueError(f"{label} không còn là thẻ 🙋 chờ duyệt (Blocked, nhãn {NEEDS_YOU_LABEL}).")
        info = it.get("approval")
        if action == "approve":
            if info is None and not self.demo:
                raise ValueError(f"Chưa đọc được các bước của {label} trên GitHub, chờ lần đọc sau rồi duyệt.")
            if (info or {}).get("steps") and body.get("stepsDone") is not True:
                raise ValueError(f"{label} có lệnh phải chạy trên máy: chạy xong rồi tick ô đã chạy xong.")
            text, reason = APPROVE_TEXT, ""
        else:
            reason = " ".join(str(body.get("reason") or "").split())[:2000]
            text = "🚫 Từ chối duyệt qua Agent Office" + (f": {reason}" if reason else "") + ". Thẻ giữ ở Blocked."
        with self.lock:
            if it["id"] in self.deciding:
                raise ValueError(f"{label} đang được gửi, chờ vài giây.")
            self.deciding.add(it["id"])
        sel = {"type": "item", "id": it["id"]}
        try:
            self._comment(it, text)
        except GhError as e:
            with self.lock:
                self._log_event(f"{'Duyệt' if action == 'approve' else 'Từ chối'} {label} lỗi, chưa gửi lên GitHub: {friendly(str(e))}",
                                "stale", sel, False)
            raise
        finally:
            with self.lock:
                self.deciding.discard(it["id"])
        with self.lock:
            if action == "approve":
                if info is not None:
                    info["approved"] = True
                self._log_event(f"Bạn duyệt {label}: đã comment done, wave sau chạy tiếp", "running", sel, False)
            else:
                self._log_event(f"Bạn từ chối {label}" + (f": {reason[:120]}" if reason else ""), "stale", sel, False)
            self.approvals.pop(it["id"], None)  # comment mới đổi updatedAt: lần đọc sau đọc lại
        return {"ok": True}

    # ---- nhắn lệnh cho agent
    def agent_message(self, body: dict, remote: bool) -> dict:
        """POST /api/agent-message. {sessionId, text}: gửi (từ Mac) hoặc chờ mã (qua tunnel). {pendingId, code}: gửi lệnh
        đã chờ mã. Lỗi gì cũng ném lên và không gửi (fail closed): lệnh ở đây là chạy code tuỳ ý trên Mac."""
        with self.msg_lock:
            t = now()
            # điện thoại và Mac đếm riêng: ai có link QR cũng không khoá được người ngồi ở Mac
            src = "remote" if remote else "local"
            times = self.msg_times[src] = [x for x in self.msg_times.get(src, []) if t - x < MSG_WINDOW]
            if len(times) >= MSG_RATE:
                raise RateLimited(f"Gửi quá {MSG_RATE} lệnh một phút, chờ chút rồi gửi lại.")
            times.append(t)
            self.pending = {k: p for k, p in self.pending.items() if p["exp"] > t}
            if body.get("pendingId"):
                sid, text = self._take_pending(str(body["pendingId"]), str(body.get("code") or ""))
                return self._deliver(sid, text, *self._target(sid))
            sid = body.get("sessionId")
            text = str(body.get("text") or "").strip()
            if not text:
                raise ValueError("Lệnh đang trống.")
            if len(text) > MSG_MAX:
                raise ValueError(f"Lệnh dài quá {MSG_MAX} ký tự.")
            mode, info = self._target(sid)
            if remote:
                return self._ask_code(sid, text, info)
            return self._deliver(sid, text, mode, info)

    def card_session(self, repo: str, issue: str):
        if not re.fullmatch(r"\d{1,7}", issue or ""):
            return None
        rp = next((p for name, p in self._repo_paths().items() if name.lower() == (repo or "").lower()), None)
        return latest_card_session(rp, issue) if rp else None

    def _msg_sel(self, repo, issue):
        """Sự kiện của lệnh nhắn trỏ tới thẻ trên Project (bấm là mở thẻ); thẻ không có trên Project thì không trỏ."""
        it = next((x for x in self.project.get("items", []) if str(x.get("number")) == str(issue)
                   and str(x.get("repo", "")).lower() == str(repo).lower()), None)
        return {"type": "item", "id": it["id"]} if it else None

    def _repo_paths(self):
        names = list(self.cfg.get("repos") or []) + sorted({it["repo"] for it in self.project.get("items", [])})
        return self.scanner.repo_paths(names)

    def _target(self, sid):
        """("inbox"|"resume", info) cho một phiên worker super-board; không gửi được thì ValueError kèm lý do."""
        if not isinstance(sid, str) or not inbox_hook.SID_RE.fullmatch(sid):
            raise ValueError("Mã phiên không hợp lệ.")
        info = find_worker_session(sid, self._repo_paths())
        if not info:
            raise ValueError("Chỉ nhắn được cho phiên worker super-board; không thấy phiên này trong log worker 7 ngày qua.")
        try:
            running = self._ps_sids()
        except (OSError, subprocess.SubprocessError) as e:
            raise ValueError(f"Không kiểm được tiến trình agent ({e}), chưa gửi.") from e
        own = self.resumes.get(sid)
        rc = own["proc"].poll() if own else None
        if own and rc is not None:
            self._close_resume(sid, rc)  # resume trước đã xong mà chưa tới nhịp poll: chốt nó trước khi resume tiếp
        own_alive = bool(own and rc is None)
        label = f"#{info['issue']} {info['repo']}"
        if sid in running:
            if info["hasInbox"] or own_alive:
                return "inbox", info
            raise ValueError(f"Phiên của {label} đang chạy nhưng chưa có hộp thư (runner cũ). Chờ nó dừng rồi gửi để resume.")
        if own_alive:
            raise ValueError(f"Đang khởi động lại phiên của {label}, chờ vài giây rồi gửi lại.")
        if inflight_live(info["repoPath"], info["issue"]):
            raise ValueError(f"{label} đang có worker khác chạy; resume lúc này sẽ tách đôi việc. Nhắn worker đang chạy.")
        if not info["cwd"] or not os.path.isdir(info["cwd"]):
            raise ValueError(f"Thư mục làm việc của phiên {label} không còn, không resume được.")
        return "resume", info

    def _ask_code(self, sid, text, info) -> dict:
        if len(self.pending) >= PENDING_MAX:
            raise ValueError(f"Đang có {PENDING_MAX} lệnh chờ mã; nhập mã hoặc chờ 2 phút cho chúng hết hạn.")
        pid, code = secrets.token_urlsafe(12), "%06d" % secrets.randbelow(10 ** 6)
        self.pending[pid] = {"sid": sid, "text": text, "code": code, "exp": now() + CODE_TTL, "tries": 0}
        label = f"#{info['issue']} {info['repo']}"
        mac_notify(f"Mã {code} — lệnh từ điện thoại cho {label}: {redact(text)[:80]}")
        with self.lock:
            self._log_event(f"Lệnh từ điện thoại cho {label} chờ mã xác nhận trên Mac", "idle", self._msg_sel(info["repo"], info["issue"]), False)
        return {"ok": False, "needCode": True, "pendingId": pid, "expiresIn": int(CODE_TTL),
                "error": "Nhập mã 6 số vừa hiện trong thông báo trên Mac."}

    def _take_pending(self, pid, code):
        p = self.pending.get(pid)
        if not p:
            raise ValueError("Mã hết hạn hoặc lệnh đã gửi; gõ lại lệnh.")
        if not hmac.compare_digest(code.strip().encode(), p["code"].encode()):
            p["tries"] += 1
            left = CODE_TRIES - p["tries"]
            if left <= 0:
                self.pending.pop(pid, None)
                raise ValueError("Sai mã 3 lần, lệnh đã huỷ.")
            raise ValueError(f"Sai mã, còn {left} lần.")
        self.pending.pop(pid, None)
        return p["sid"], p["text"]

    def _deliver(self, sid, text, mode, info) -> dict:
        t = now()
        mid = "%013d-%s" % (int(t * 1000), secrets.token_hex(4))
        label = f"#{info['issue']} {info['repo']}"
        preview = redact(text)[:160]
        if mode == "inbox":
            box = os.path.join(self.inbox_dir, sid)
            os.makedirs(box, mode=0o700, exist_ok=True)
            os.chmod(self.inbox_dir, 0o700)
            os.chmod(box, 0o700)
            tmp = os.path.join(box, "." + mid + ".tmp")
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump({"id": mid, "text": text, "ts": t}, f, ensure_ascii=False)
            os.replace(tmp, os.path.join(box, mid + ".json"))
            state, ev = "sent", f"Bạn nhắn {label}: {preview}"
        else:
            nonce = secrets.token_hex(16)
            # tiền tố cố định: lệnh không bao giờ mở đầu bằng "-" nên claude không hiểu nhầm thành cờ
            prompt = "Lệnh mới từ người dùng qua Agent Office (phiên đã dừng nên được mở lại): " + text
            argv = [expand(self.cfg.get("claudeBin") or "~/.local/bin/claude"), "--resume", sid, "-p", prompt]
            if info.get("model"):
                argv += ["--model", info["model"]]
            argv += ["--dangerously-skip-permissions", "--output-format", "stream-json", "--verbose",
                     "--settings", inbox_hook.settings_json(os.path.join(HERE, "inbox_hook.py")),
                     "--append-system-prompt", inbox_hook.system_prompt(nonce)]
            env = dict(os.environ, AGENT_OFFICE_NONCE=nonce, AGENT_OFFICE_INBOX=self.inbox_dir,
                       DEVKIT_ALLOW_BRANCH="1", WORKTREE_MERGE_GATE="0",
                       CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS="0", BASH_DEFAULT_TIMEOUT_MS="3600000",
                       BASH_MAX_TIMEOUT_MS="3600000")
            env.pop("CLAUDE_CONFIG_DIR", None)  # log không ghi config_dir: tài khoản mặc định như runner, không lấy của server
            if info.get("configDir"):
                env["CLAUDE_CONFIG_DIR"] = info["configDir"]
            # launchd chạy server với PATH không có ~/.local/bin (nơi cài claude): phiên resume cần nó cho lệnh con
            local_bin = os.path.expanduser("~/.local/bin")
            if local_bin not in env.get("PATH", "").split(os.pathsep):
                env["PATH"] = local_bin + os.pathsep + env.get("PATH", "")
            os.makedirs(self.resume_dir, mode=0o700, exist_ok=True)
            log = os.path.join(self.resume_dir, f"{sid}-{int(t)}.log")
            # ponytail: runner vẫn có thể giao lại thẻ này trong lúc resume (không sửa logic chọn thẻ); resume chạy nice 10
            # như server. Nâng lên khi thấy hai worker cùng thẻ thật.
            # lệnh cũ còn sót trong hộp thư (server khởi động lại trước khi kịp bỏ) không được giao cho lần resume này
            for stale in glob.glob(os.path.join(self.inbox_dir, sid, "*.json")):
                try:
                    os.unlink(stale)
                except OSError as e:
                    raise ValueError(f"Không dọn được lệnh cũ trong hộp thư ({e}), chưa resume.") from e
            proc = self._spawn(argv, env, info["cwd"], log)
            self.resumes[sid] = {"proc": proc, "mid": mid, "log": log}
            state, ev = "resuming", f"Bạn nhắn {label} (phiên đã dừng, đang resume): {preview}"
        self.msgs[mid] = {"id": mid, "sid": sid, "repo": info["repo"], "issue": info["issue"], "lane": info["lane"],
                          "preview": preview, "state": state, "mode": mode, "ts": t}
        while len(self.msgs) > MSG_KEEP:
            self.msgs.pop(next(iter(self.msgs)))
        with self.lock:
            self._log_event(ev, "running", self._msg_sel(info["repo"], info["issue"]), False)
        return {"ok": True, "id": mid, "mode": mode, "state": state}

    def poll_messages(self):
        """Hook đã đọc (ack) → "read"; phiên dừng trước khi đọc → "unread" và bỏ lệnh; resume xong → "done"/"failed"."""
        with self.msg_lock:
            sent = [m for m in self.msgs.values() if m["state"] == "sent"]
            try:
                running = self._ps_sids() if sent else set()
            except (OSError, subprocess.SubprocessError) as e:
                warn("ps", e)
                running = None
            for m in sent:
                label = f"#{m['issue']} {m['repo']}"
                ack = os.path.join(self.inbox_dir, m["sid"], "acks", m["id"])
                if os.path.exists(ack):
                    m["state"] = "read"
                    try:
                        os.unlink(ack)
                    except OSError as e:
                        warn("xoá ack " + ack, e)
                    with self.lock:
                        self._log_event(f"Agent {label} đã đọc lệnh của bạn", "running", self._msg_sel(m["repo"], m["issue"]), False)
                elif running is not None and m["sid"] not in running:
                    try:
                        os.unlink(os.path.join(self.inbox_dir, m["sid"], m["id"] + ".json"))
                        m["state"] = "unread"
                    except FileNotFoundError:
                        m["state"] = "read"  # file đã mất = hook đã nhận lệnh, chỉ chưa kịp ghi ack trước khi phiên dừng
                    except OSError as e:
                        warn("bỏ lệnh chưa đọc", e)
                        m["state"] = "unread"
                    with self.lock:
                        self._log_event(f"Agent {label} đã nhận lệnh rồi dừng" if m["state"] == "read" else
                                        f"Agent {label} dừng trước khi đọc lệnh; gửi lại để resume",
                                        "running" if m["state"] == "read" else "stale", self._msg_sel(m["repo"], m["issue"]), False)
            for sid, r in list(self.resumes.items()):
                rc = r["proc"].poll()
                if rc is not None:
                    self._close_resume(sid, rc)

    def _close_resume(self, sid, rc):
        """Resume của `sid` đã thoát với mã `rc`: lệnh của nó thành done/failed (gọi trong msg_lock)."""
        r = self.resumes.pop(sid, None)
        m = self.msgs.get(r["mid"]) if r else None
        if m:
            m["state"] = "done" if rc == 0 else "failed"
            with self.lock:
                self._log_event(f"Resume #{m['issue']} {m['repo']} " + ("xong" if rc == 0 else f"lỗi (mã {rc}), xem {r['log']}"),
                                "finished" if rc == 0 else "stale", self._msg_sel(m["repo"], m["issue"]), rc != 0)

    def messages_view(self) -> list:
        keys = ("id", "sid", "repo", "issue", "lane", "preview", "state", "mode", "ts")
        return [{k: m[k] for k in keys} for m in list(self.msgs.values())[-30:]]

    def act(self, action: str, body: dict) -> dict:
        if not self.demo and not (self.project.get("id") and self.gh_meta.get("ok")):
            raise ValueError("Chưa kết nối được GitHub Project nên chưa sửa được.")
        status_field = self.project.get("statusField")
        if action == "set-field":
            it = self._item(body["itemId"])
            status_field = self._part(it).get("statusField") or status_field
            field = body.get("field") or status_field
            f, opt = self._set(it["id"], field, body["option"])
            with self.lock:
                if field == status_field:
                    it["status"] = opt["name"]
                    self.user_moves[it["id"]] = opt["name"]
                else:
                    it.setdefault("fields", {})[field] = opt["name"]
                it["updatedAt"] = now()
            result = {"ok": True}
        elif action == "create":
            title = str(body.get("title") or "").strip()[:256]
            if not title:
                raise ValueError("Cần có tiêu đề.")
            text = str(body.get("body") or "")[:20000]
            repo = str(body.get("repo") or "").strip()
            number, url, content_id, full, typ = None, None, None, None, "DraftIssue"
            owner_item = next((x for x in self.project.get("items", []) if repo and x["repo"] == repo and x.get("pid")), None)
            part = self._part(owner_item) if owner_item else self.project
            status_field = part.get("statusField") or status_field
            if self.demo:
                item_id = "demo-new-%d" % int(now() * 1000)
                if repo:
                    nums = [int(x["number"]) for x in self.project["items"] if x["repo"] == repo and x.get("number")]
                    number, typ = str(max(nums + [0]) + 1), "Issue"
            elif repo:
                full = str(body.get("repoFull") or "")
                if "/" not in full:
                    full = f"{self.cfg['github']['owner']}/{repo}"
                owner, name = full.split("/", 1)
                rid = ((gh_graphql(Q_REPO, {"o": owner, "n": name}).get("repository")) or {}).get("id")
                if not rid:
                    raise ValueError(f"Không tìm thấy repo {full} trên GitHub.")
                issue = gh_graphql(M_ISSUE, {"r": rid, "t": title, "b": text})["createIssue"]["issue"]
                content_id, number, url, typ = issue["id"], str(issue["number"]), issue["url"], "Issue"
                item_id = gh_graphql(M_ADD, {"p": part["id"], "c": content_id})["addProjectV2ItemById"]["item"]["id"]
            else:
                item_id = gh_graphql(M_DRAFT, {"p": part["id"], "t": title, "b": text})["addProjectV2DraftIssue"]["projectItem"]["id"]
            status = body.get("status") or self._default_status(part)
            if status and status_field:
                self._set(item_id, status_field, status, part)
            with self.lock:
                self.project.setdefault("items", []).append({
                    "id": item_id, "contentId": content_id, "number": number, "title": title, "url": url,
                    "type": typ, "state": "OPEN", "isDraft": False, "repo": repo or "Nháp", "repoFull": full,
                    "status": status or NO_STATUS, "assignees": [], "labels": [], "fields": {}, "updatedAt": now(),
                    "pid": part.get("id"),
                })
            result = {"ok": True, "itemId": item_id, "number": number, "url": url}
        elif action == "move-all":
            src, dst = str(body.get("from") or ""), str(body.get("to") or "")
            if not src or not dst or src == dst:
                raise ValueError("Cần cột nguồn và cột đích khác nhau.")
            with self.lock:
                repo = str(body.get("repo") or "")
                todo = [x for x in self.project.get("items", []) if x["status"] == src and (not repo or x["repo"] == repo)]
            remaining = max(0, len(todo) - MOVE_ALL_MAX)
            todo = todo[:MOVE_ALL_MAX]  # một lần bấm không giữ request quá lâu; còn thì bấm lại
            moved, failed = 0, []
            for it in todo:
                part = self._part(it)
                try:
                    self._set(it["id"], part.get("statusField") or status_field, dst, part)
                except GhError as e:
                    failed.append(f"{it.get('number') or it['id']}: {friendly(str(e))}")
                    continue
                except ValueError as e:
                    failed.append(f"{it.get('number') or it['id']}: {e}")
                    continue
                with self.lock:
                    it["status"], it["updatedAt"] = dst, now()
                    self.user_moves[it["id"]] = dst
                moved += 1
            result = {"ok": True, "moved": moved, "failed": failed[:5], "failedCount": len(failed), "remaining": remaining}
        elif action == "comment":
            it = self._item(body["itemId"])
            text = str(body.get("body") or "").strip()
            if not text:
                raise ValueError("Bình luận đang trống.")
            self._comment(it, text)
            result = {"ok": True}
        elif action in ("approve", "reject"):
            result = self._decide(action, body)
        elif action == "archive":
            it = self._item(body["itemId"])
            if not self.demo:
                gh_graphql(M_ARCHIVE, {"p": self._part(it)["id"], "i": it["id"]})
            with self.lock:
                self.project["items"] = [x for x in self.project["items"] if x["id"] != it["id"]]
            result = {"ok": True}
        else:
            raise ValueError("Không có thao tác " + action)
        self.rebuild()
        if not self.demo:
            self.refresh_evt.set()
        return result

    def github_loop(self):
        last_fp, unchanged = None, 0
        while True:
            changed = True  # an error also needs a rebuild, so the notice shows
            try:
                proj = fetch_projects(self.cfg["github"])
                self.fill_approvals(proj)  # trước khi thay board: thẻ 🙋 không mất bước giữa hai lần đọc
                with self.lock:
                    self.project = proj
                    self.gh_meta = {"ok": True, "error": "; ".join(proj.get("partialErrors") or []) or None,
                                    "fetchedAt": now()}
                self.rebuild()  # board hiện ngay, việc ghi Backlog chạy sau
                self.backfill_backlog(proj)
                fp = board_fingerprint([proj])
                unchanged = unchanged + 1 if fp == last_fp else 0
                changed, last_fp = unchanged == 0, fp
                if changed:
                    print(f"[github] {len(proj['items'])} việc, {len(proj['columns'])} cột", flush=True)
            except Exception as e:  # noqa: BLE001
                with self.lock:
                    self.gh_meta = {"ok": False, "error": str(e), "fetchedAt": self.gh_meta.get("fetchedAt")}
                print(f"[github] lỗi: {e}", file=sys.stderr, flush=True)
            if changed:
                self.rebuild()
            # không ai xem thì nghỉ ≥ 5 phút (ngân sách GraphQL dùng chung với runner); tab mở lại đánh thức qua refresh_evt
            if self.refresh_evt.wait(loop_wait(poll_interval(float(self.cfg["githubSeconds"]), unchanged), 300, 4)):
                unchanged = 0  # the user acted or asked for a refresh: back to the base rate
            self.refresh_evt.clear()

    def local_loop(self):
        while True:
            try:
                sessions, info = self.scanner.scan_sessions()
                names = list(self.cfg.get("repos") or []) + sorted({it["repo"] for it in self.project.get("items", [])})
                file_ticks = self.scanner.scan_files_for_ticks(self.scanner.repo_paths(names))
                with self.lock:
                    self.sessions, self.sess_info, self.file_ticks = sessions, info, file_ticks
            except Exception as e:  # noqa: BLE001
                print(f"[local] lỗi: {e}", file=sys.stderr, flush=True)
            try:
                self.poll_messages()
            except Exception as e:  # noqa: BLE001
                print(f"[nhắn] lỗi theo dõi lệnh: {e}", file=sys.stderr, flush=True)
            self.rebuild()
            self.wake_evt.wait(loop_wait(float(self.cfg["localSeconds"]), 30, 6))  # không ai xem: ≥ 30 s
            self.wake_evt.clear()

    def gate_repo_paths(self) -> dict:
        """repo -> MAIN checkout (cùng cách tìm đường như build_state / scanner.repo_paths)."""
        names = list(self.cfg.get("repos") or []) + sorted({it["repo"] for it in self.project.get("items", []) if it.get("repo")})
        return self.scanner.repo_paths(names)

    def gate_full(self, body: dict) -> dict:
        if not self.gatefull:
            raise ValueError("Chế độ demo không chạy gate full.")
        repo = str(body.get("repo") or "").strip()
        if not repo:
            raise ValueError("Cần repo.")
        res = self.gatefull.cancel(repo) if body.get("cancel") else self.gatefull.enqueue(repo, self.gate_repo_paths())
        self.gatefull.tick(self.gate_repo_paths())  # khoá toàn máy rảnh thì chạy ngay, không đợi vòng 5 giây
        self.rebuild()
        return res

    def start(self):
        if self.gatefull:
            threading.Thread(target=self.gatefull.loop, args=(self.gate_repo_paths,), daemon=True).start()
        if self.demo:
            def demo_loop():
                while True:
                    self.rebuild()
                    time.sleep(5)
            threading.Thread(target=demo_loop, daemon=True).start()
            return
        threading.Thread(target=self.github_loop, daemon=True).start()
        threading.Thread(target=self.local_loop, daemon=True).start()


CTYPES = {".html": "text/html; charset=utf-8", ".js": "application/javascript; charset=utf-8",
          ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8",
          ".svg": "image/svg+xml", ".png": "image/png", ".txt": "text/plain; charset=utf-8",
          ".glb": "model/gltf-binary", ".md": "text/plain; charset=utf-8"}


HOST_RE = re.compile(r"\[([^\]]+)\](?::\d+)?|([^:\[\]@\s]+)(?::\d+)?")


def host_name(header) -> str:
    m = HOST_RE.fullmatch((header or "").strip().lower())
    return (m.group(1) or m.group(2)) if m else ""


def host_ok(header, allowed) -> bool:
    """Host header must name this machine: blocks DNS rebinding on reads and writes."""
    return host_name(header) in allowed


# cloudflared adds these to every request it forwards: a request carrying one came from outside this Mac
TUNNEL_HEADERS = ("Cf-Connecting-Ip", "Cf-Ray")
_key_cache = {"path": None, "mtime": None, "key": ""}


def remote_key(path: str) -> str:
    """The per-run secret ai-factory.sh writes; "" (remote access off) while the file is missing."""
    try:
        mtime = os.stat(path).st_mtime
    except OSError:
        return ""
    if _key_cache["path"] != path or _key_cache["mtime"] != mtime:
        try:
            with open(path, encoding="utf-8") as f:
                _key_cache.update(path=path, mtime=mtime, key=f.read().strip())
        except OSError as exc:
            warn("remote key " + path, exc)
            return ""
    return _key_cache["key"]


# Menu "Điện thoại": máy Mac lấy link + QR của quick tunnel để quét bằng điện thoại ở mạng khác, và mở tunnel mới khi
# tunnel cũ đã chết (quick tunnel không sống mãi: sau khi máy ngủ Cloudflare trả "Tunnel not found").
FACTORY_SCRIPT = os.environ.get("AGENT_OFFICE_FACTORY_SCRIPT") or os.path.join(os.path.dirname(os.path.dirname(HERE)), "ai-factory.sh")
TUNNEL_URL_RE = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")


def tunnel_alive(state_dir: str) -> bool:
    """PID trong tunnel.pid còn sống VÀ vẫn là cloudflared (sau khi khởi động lại máy, số PID có thể thuộc chương trình khác)."""
    try:
        with open(os.path.join(state_dir, "tunnel.pid"), encoding="utf-8") as f:
            pid = int(f.read().strip())
    except (OSError, ValueError):
        return False
    try:
        out = subprocess.run(["ps", "-p", str(pid), "-o", "args="], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        warn("ps tunnel", exc)
        return False
    return "cloudflared" in out


def phone_info(state_dir: str, key_file: str) -> dict:
    """{live, url, link, svg}. Tunnel chết, chưa có url hay chưa có key: live=False và KHÔNG trả key."""
    url = ""
    try:
        with open(os.path.join(state_dir, "tunnel.log"), encoding="utf-8", errors="replace") as f:
            url = next((m for m in TUNNEL_URL_RE.findall(f.read()) if not m.startswith("https://api.")), "")
    except FileNotFoundError:
        url = ""   # chưa từng mở tunnel trên máy này: không phải lỗi
    except OSError as exc:
        warn("tunnel log", exc)
    key = remote_key(key_file)
    if not (url and key and tunnel_alive(state_dir)):
        return {"ok": True, "live": False}
    link = f"{url}/#key={key}"
    svg = None
    qr = shutil.which("qrencode")
    if qr:
        try:
            r = subprocess.run([qr, "-t", "SVG", "-m", "2", "-o", "-", link], capture_output=True, text=True, timeout=5)
            svg = r.stdout if r.returncode == 0 and "<svg" in r.stdout else None
        except (OSError, subprocess.SubprocessError) as exc:
            warn("qrencode", exc)
    return {"ok": True, "live": True, "url": url, "link": link, "svg": svg}


def open_phone_tunnel(state_dir: str) -> str:
    """Chạy `ai-factory.sh phone` (tunnel + key mới, không đụng runner). Trả "" khi chạy được, hoặc lý do lỗi cho UI.
    stdout của script có QR chứa key: không log stdout, chỉ log mã thoát."""
    if not os.path.isfile(FACTORY_SCRIPT):
        warn("ai-factory phone", f"không có {FACTORY_SCRIPT}")
        return f"Không tìm thấy ai-factory.sh ({FACTORY_SCRIPT}): cài lại autostart (install-autostart.sh) hoặc chạy ai-factory"
    try:
        r = subprocess.run(["bash", FACTORY_SCRIPT, "phone"], env=dict(os.environ, AGENT_OFFICE_STATE=state_dir),
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=90)
    except (OSError, subprocess.SubprocessError) as exc:
        warn("ai-factory phone", exc)
        return f"ai-factory phone không chạy được: {exc}"
    if r.returncode != 0:
        print(f"[phone] ai-factory phone rc={r.returncode}: {r.stderr.strip()[-300:]}", flush=True)
        return f"ai-factory phone lỗi (mã {r.returncode}): xem ~/.agent-office/tunnel.log"
    return ""


def make_handler(app: App):
    extra = app.cfg.get("allowedHosts") or []
    if isinstance(extra, str):
        extra = [extra]
    bind = str(app.cfg["host"]).lower()
    allowed = {"127.0.0.1", "localhost", "::1", *(str(x).lower() for x in extra)}
    if bind not in ("", "0.0.0.0", "::"):
        allowed.add(bind)
    key_file = os.path.expanduser(os.environ.get("AGENT_OFFICE_KEY_FILE") or "~/.agent-office/remote-key")
    state_dir = os.path.dirname(key_file)
    phone_busy = threading.Lock()   # một lần mở tunnel một lúc: bấm "Tạo mã mới" hai lần không mở hai tunnel

    def from_mac(handler) -> bool:
        """Chính máy Mac, không qua tunnel: link có key không bao giờ đi ra qua tunnel, kể cả khi người gọi có key."""
        return local_request(handler.headers, handler.client_address[0], allowed)

    def refusal(handler, api: bool):
        """None when the request may go on, else the HTTP status that refuses it."""
        headers = handler.headers
        if from_mac(handler):
            return None  # this Mac itself
        host = host_name(headers.get("Host"))
        key = remote_key(key_file)
        if not key or not (host in allowed or host.endswith(".trycloudflare.com")):
            return 403
        if not api:
            return None  # the page and its assets carry no data; the page reads the key from the QR link
        given = headers.get("X-Agent-Office-Key") or ""
        return None if hmac.compare_digest(given.encode(), key.encode()) else 401

    class Handler(BaseHTTPRequestHandler):
        server_version = "AgentOffice/1.0"

        def log_message(self, *args):
            pass

        def send(self, code, body: bytes, ctype: str, headers=None):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(body)))
            # model 3D nặng và không đổi: để trình duyệt giữ một ngày; còn lại luôn lấy mới
            self.send_header("Cache-Control", "max-age=86400" if ctype.startswith("model/") else "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = urlparse(self.path).path
            code = refusal(self, path.startswith("/api/"))
            if code:
                return self.send(code, b'{"ok":false,"error":"forbidden"}', CTYPES[".json"])
            if path == "/api/phone":
                if not from_mac(self):
                    return self.send(403, b'{"ok":false,"error":"forbidden"}', CTYPES[".json"])
                return self.send(200, json.dumps(phone_info(state_dir, key_file)).encode("utf-8"), CTYPES[".json"])
            if path == "/api/state":
                if "view=1" in (urlparse(self.path).query or "").split("&") and mark_viewed():
                    app.wake_evt.set(); app.refresh_evt.set()  # tab vừa mở lại: đọc ngay, không đợi nhịp nền chậm
                with app.lock:
                    body = app.state_bytes
                if len(body) >= GzipCache.MIN and gzip_ok(self.headers.get("Accept-Encoding")):
                    return self.send(200, app.state_gz.get(body), CTYPES[".json"], {"Content-Encoding": "gzip", "Vary": "Accept-Encoding"})
                return self.send(200, body, CTYPES[".json"], {"Vary": "Accept-Encoding"})
            if path == "/api/card-session":  # phiên worker gần nhất của một thẻ: để nhắn / resume thẻ không còn agent cầm
                q = parse_qs(urlparse(self.path).query)
                res = app.card_session((q.get("repo") or [""])[0], (q.get("issue") or [""])[0])
                return self.send(200, json.dumps(res or {}, ensure_ascii=False).encode("utf-8"), CTYPES[".json"])
            if path == "/api/refresh":
                app.refresh_evt.set()
                return self.send(200, b'{"ok":true}', CTYPES[".json"])
            rel = "index.html" if path in ("", "/") else path.lstrip("/")
            if rel.startswith("api/"):
                return self.send(404, b"not found", "text/plain")
            full = os.path.realpath(os.path.join(WEB_DIR, rel))
            if not full.startswith(os.path.realpath(WEB_DIR) + os.sep) or not os.path.isfile(full):
                return self.send(404, b"not found", "text/plain")
            with open(full, "rb") as f:
                data = f.read()
            if rel == "index.html":
                data = fill_models_version(data, models_version())
            return self.send(200, data, CTYPES.get(os.path.splitext(full)[1], "application/octet-stream"))

        def do_POST(self):
            path = urlparse(self.path).path
            if self.headers.get("X-Agent-Office") != "1":
                return self.send(403, b'{"ok":false,"error":"forbidden"}', CTYPES[".json"])
            code = refusal(self, True)
            if code:
                return self.send(code, b'{"ok":false,"error":"forbidden"}', CTYPES[".json"])
            if path == "/api/phone":
                if not from_mac(self):
                    return self.send(403, b'{"ok":false,"error":"forbidden"}', CTYPES[".json"])
                if not phone_busy.acquire(blocking=False):
                    return self.send(409, '{"ok":false,"error":"Đang tạo mã, chờ vài giây"}'.encode("utf-8"), CTYPES[".json"])
                try:
                    err = open_phone_tunnel(state_dir)
                finally:
                    phone_busy.release()
                if err:
                    return self.send(502, json.dumps({"ok": False, "error": err}, ensure_ascii=False).encode("utf-8"), CTYPES[".json"])
                return self.send(200, json.dumps(phone_info(state_dir, key_file)).encode("utf-8"), CTYPES[".json"])
            n = int(self.headers.get("Content-Length") or 0)
            if n > 200_000:
                return self.send(413, b'{"ok":false,"error":"too large"}', CTYPES[".json"])
            try:
                body = json.loads(self.rfile.read(n) or b"{}")
                if not isinstance(body, dict):
                    raise ValueError("body")
            except ValueError:
                return self.send(400, b'{"ok":false,"error":"bad json"}', CTYPES[".json"])
            if path == "/api/agent-message":  # nhắn lệnh cho agent: qua tunnel thì phải có mã xác nhận hiện trên Mac
                try:
                    res, code = app.agent_message(body, remote=not from_mac(self)), 200
                    if res.get("needCode"):
                        code = 202
                except RateLimited as e:
                    res, code = {"ok": False, "error": str(e)}, 429
                except (KeyError, ValueError, TypeError) as e:
                    res, code = {"ok": False, "error": str(e).strip("'\"")}, 400
                except Exception as e:  # noqa: BLE001 — lỗi lạ cũng không gửi, báo rõ cho người gõ
                    warn("agent-message", e)
                    res, code = {"ok": False, "error": f"Lỗi máy chủ, chưa gửi: {e}"}, 500
                print(f"[nhắn] {'ok' if res.get('ok') else res.get('error')}", flush=True)
                return self.send(code, json.dumps(res, ensure_ascii=False).encode("utf-8"), CTYPES[".json"])
            if path == "/api/gate-full":  # chạy / huỷ hàng chờ gate --full: chỉ trên chính máy Mac, qua tunnel (điện thoại) thì từ chối
                if not from_mac(self):
                    return self.send(403, '{"ok":false,"error":"Chạy gate full chỉ bấm được trên máy Mac"}'.encode("utf-8"), CTYPES[".json"])
                try:
                    res, code = app.gate_full(body), 200
                except (KeyError, ValueError, TypeError) as e:
                    res, code = {"ok": False, "error": str(e).strip("'\"")}, 400
                print(f"[gate-full] {body.get('repo')} {'huỷ' if body.get('cancel') else 'chạy'}: {res.get('state') or res.get('error') or 'ok'}", flush=True)
                return self.send(code, json.dumps(res, ensure_ascii=False).encode("utf-8"), CTYPES[".json"])
            action = path[len("/api/"):] if path.startswith("/api/") else ""
            try:
                res, code = app.act(action, body), 200
            except GhError as e:
                res, code = {"ok": False, "error": friendly(str(e))}, 502
            except (KeyError, ValueError, TypeError) as e:
                res, code = {"ok": False, "error": str(e).strip("'\"")}, 400
            print(f"[ghi] {action} {'ok' if res.get('ok') else res.get('error')}", flush=True)
            return self.send(code, json.dumps(res, ensure_ascii=False).encode("utf-8"), CTYPES[".json"])

    return Handler


def run_check(cfg: dict) -> int:
    """Kiểm tra trước khi dùng thật: gh, quyền, Project, transcript, log runner."""
    ok = True
    print("Agent Office: kiểm tra kết nối\n")
    gh = find_gh()
    print(f"[gh]          {gh or 'KHÔNG THẤY. Cài: brew install gh && gh auth login'}")
    if not gh:
        ok = False
    if gh:
        st = subprocess.run([gh, "auth", "status"], capture_output=True, text=True)
        out = st.stdout + st.stderr
        acc = re.findall(r"account\s+(\S+)", out) or re.findall(r"as\s+(\S+)", out)
        scopes = " ".join(re.findall(r"Token scopes:\s*(.+)", out))
        print(f"[tài khoản]   {acc[0] if acc else 'chưa đăng nhập'}")
        has = "'project'" in scopes or '"project"' in scopes or re.search(r"\bproject\b", scopes.replace("read:project", ""))
        print(f"[quyền]       {'có quyền project (đọc và sửa)' if has else 'THIẾU quyền project. Chạy: gh auth refresh -s project'}")
        ok = ok and bool(has)
        try:
            proj = fetch_projects(cfg["github"])
            writable = bool(proj.get("id") and proj.get("statusFieldId"))
            print(f"[Project]     {proj['title']}  ({proj['url']})")
            print(f"[view]        {proj.get('viewName') or 'không đọc được view, dùng trường Status'}")
            print(f"[cột]         {proj.get('statusField')}: " + ", ".join(c['name'] for c in proj['columns']))
            print(f"[việc]        {len(proj['items'])} thẻ, {len({i['repo'] for i in proj['items']})} repo")
            print(f"[sửa được]    {'có' if writable else 'KHÔNG (thiếu id của Project hoặc trường trạng thái)'}")
            ok = ok and writable
        except GhError as e:
            print(f"[Project]     LỖI: {friendly(str(e))}")
            ok = False
    scanner = LocalScanner(cfg)
    sessions, info = scanner.scan_sessions()
    print(f"[transcript]  {info['dir']}: " + (f"{len(sessions)} phiên trong {cfg['lookbackMinutes']} phút gần nhất" if info["ok"] else "KHÔNG THẤY thư mục"))
    names = list(cfg.get("repos") or [])
    paths = scanner.repo_paths(names)
    for n, pth in paths.items():
        print(f"[repo]        {n}: {pth} {'' if os.path.isdir(pth) else '(KHÔNG THẤY thư mục, sửa repoPaths)'}")
    ticks = scanner.scan_files_for_ticks(paths)
    in_sessions = sum(len(x["ticks"]) for x in sessions)
    print(f"[runner]      {in_sessions} tick trong transcript, {sum(len(t[2]) for t in ticks)} tick trong file log/manifest")
    print("\n" + ("Sẵn sàng. Chạy: python3 server.py --open" if ok else "Còn lỗi ở trên, sửa xong rồi chạy lại --check."))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="Agent Office: xưởng 3D cho GitHub Project và agent")
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--port", type=int)
    ap.add_argument("--demo", action="store_true", help="chạy với dữ liệu mẫu")
    ap.add_argument("--open", action="store_true", help="tự mở trình duyệt")
    ap.add_argument("--check", action="store_true", help="kiểm tra gh, Project, transcript rồi thoát")
    args = ap.parse_args()

    user_cfg = {}
    if os.path.exists(args.config):
        with open(args.config, encoding="utf-8") as f:
            user_cfg = json.load(f)
    cfg = deep_merge(DEFAULTS, user_cfg)
    try:  # Agent Office chỉ để xem: nhường CPU cho agent, gate và test đang chạy trên máy
        os.nice(10)
    except (OSError, AttributeError) as e:  # Windows không có os.nice: chạy với ưu tiên thường
        warn("không hạ được ưu tiên tiến trình", e)
    if args.port:
        cfg["port"] = args.port
    if args.check:
        sys.exit(run_check(cfg))

    app = App(cfg, demo=args.demo)
    app.rebuild()
    app.start()
    srv = ThreadingHTTPServer((cfg["host"], int(cfg["port"])), make_handler(app))
    url = f"http://{cfg['host']}:{cfg['port']}/"
    print(f"Agent Office đang chạy: {url}" + ("  (demo)" if args.demo else ""), flush=True)
    if args.open:
        webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        warn("server", "dừng theo Ctrl+C")


if __name__ == "__main__":
    main()
