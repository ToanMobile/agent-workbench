#!/usr/bin/env python3
"""AAF Studio backend: read-only aaf.db reader, safe streams/diff/proof, CLI wrapper, and isolated :4318 remote handler."""
from __future__ import annotations

import base64
import fcntl
import glob
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import shutil
import signal
import sqlite3
import stat
import subprocess
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler
from urllib.parse import parse_qs, parse_qsl, quote, urlparse

AAF_DATA_DIR = os.path.expanduser(os.environ.get("AAF_DATA_DIR") or "~/.local/share/autofactory")
AAF_DB_PATH = os.path.join(AAF_DATA_DIR, "aaf.db")
AAF_STREAMS_DIR = os.path.join(AAF_DATA_DIR, "streams")
AAF_THROTTLE_DIR = os.path.join(AAF_DATA_DIR, "throttle")
AGENT_OFFICE_DIR = os.path.expanduser(os.environ.get("AGENT_OFFICE_DIR") or "~/.agent-office")
SUPERVISOR_STATE_PATH = os.path.join(AGENT_OFFICE_DIR, "supervisor-state.json")
TELEGRAM_ENV_PATH = os.path.join(AGENT_OFFICE_DIR, "telegram.env")

ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9_-]{8,80}$")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
HOST_RE = re.compile(r"\[([^\]]+)\](?::\d+)?|([^:\[\]@\s]+)(?::\d+)?")

# Extra redaction patterns on top of server.redact(): Telegram bot tokens (bare & /bot URL)
_TG_TOKEN_RE = re.compile(r"(?:/bot|\b)\d{8,12}:[A-Za-z0-9_-]{30,}\b")
_GENERIC_SECRET_RE = re.compile(
    "|".join(
        [
            r"gh[pousr]_[A-Za-z0-9]{20,}",
            r"github_pat_[A-Za-z0-9_]{20,}",
            r"(?<![\w-])sk-[A-Za-z0-9_-]{16,}",
            r"\bAKIA[0-9A-Z]{16}\b",
            r"\bxox[abposr]-[A-Za-z0-9-]{10,}",
            r"\beyJ[\w-]{5,}\.eyJ[\w-]{5,}\.[\w-]+",
            r"-----BEGIN[^-]*PRIVATE KEY-----[\s\S]*?(?:-----END[^-]*-----|$)",
            r"(?i:bearer)\s+[A-Za-z0-9._~+/=-]{8,}",
        ]
    )
)

REMOTE_CC_ACTIONS = frozenset(
    {"refresh", "switch", "rotate", "limit", "unfreeze", "balance", "cooldown", "repo_assign"}
)
ALLOWED_PRIORITIES = frozenset({"P0", "P1", "P2", "P3"})
AGENT_CMD_MARKERS = ("claude", "codex", "gemini", "aaf")

_ASK_SEMAPHORE = threading.Semaphore(1)
_MAX_STREAM_BYTES = 64 * 1024
_MAX_STREAM_LINES = 200
_MAX_DIFF_BYTES = 200 * 1024
_MAX_PROOF_BYTES = 10 * 1024 * 1024
_MAX_REMOTE_BODY = 65_536

REMOTE_STUDIO_CSP = (
    "default-src 'self'; "
    "script-src 'self' 'unsafe-inline' https://telegram.org; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob:; "
    "connect-src 'self'; "
    "frame-ancestors 'self' https://web.telegram.org https://*.telegram.org;"
)
LOCAL_STUDIO_CSP = "frame-ancestors 'none'"


_LOG = logging.getLogger("aaf_studio")


def log_warn(ctx: str, exc: BaseException) -> None:
    """Log non-fatal recoverable errors with redacted context instead of silent pass."""
    _LOG.debug("[aaf-studio:%s] %s", ctx, redact_aaf(str(exc)))


def redact_aaf(text: str) -> str:
    """Mask Telegram bot tokens and common API credentials before returning or sending output."""
    if not text:
        return ""
    out = _TG_TOKEN_RE.sub("***", str(text))
    try:
        import server as _srv  # local sibling when running in agent-office

        out = _srv.redact(out)
    except Exception:  # noqa: BLE001 — standalone import fallback
        out = _GENERIC_SECRET_RE.sub("***", out)
    return _TG_TOKEN_RE.sub("***", out)


def find_aaf_bin() -> str:
    found = shutil.which("aaf")
    if found:
        return found
    for cand in (
        os.path.expanduser("~/.cargo/bin/aaf"),
        os.path.expanduser("~/.local/bin/aaf"),
        "/opt/homebrew/bin/aaf",
        "/usr/local/bin/aaf",
    ):
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return "aaf"


def host_name(header: str | None) -> str:
    m = HOST_RE.fullmatch((header or "").strip().lower())
    return (m.group(1) or m.group(2)) if m else ""


def parse_env_file(path: str) -> tuple[dict[str, str], str | None]:
    """Read key=value env file safely; returns (env_dict, warning_or_error)."""
    if not os.path.isfile(path):
        return {}, "missing"
    try:
        st = os.stat(path)
        if st.st_mode & 0o077:
            return {}, f"insecure_permissions:{oct(st.st_mode & 0o777)}"
    except OSError as exc:
        return {}, str(exc)
    out: dict[str, str] = {}
    try:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                out[k.strip()] = v.strip().strip('"').strip("'")
    except OSError as exc:
        return {}, str(exc)
    return out, None


def load_telegram_env(path: str = TELEGRAM_ENV_PATH) -> tuple[str, int, list[int], str | None]:
    env, err = parse_env_file(path)
    if err:
        return "", 0, [], err
    token = (env.get("TELEGRAM_BOT_TOKEN") or "").strip()
    owner_raw = (env.get("TELEGRAM_OWNER_ID") or env.get("TELEGRAM_CHAT_ID") or "").strip()
    if not token or not owner_raw:
        return "", 0, [], "missing_token_or_owner"
    try:
        owner_id = int(owner_raw)
    except ValueError:
        return "", 0, [], "invalid_owner_id"
    chat_ids = {owner_id}
    raw_chats = (env.get("TELEGRAM_ALLOWED_CHAT_IDS") or env.get("TELEGRAM_CHAT_ID") or "").strip()
    for part in raw_chats.split(","):
        part = part.strip()
        if part:
            try:
                chat_ids.add(int(part))
            except ValueError as exc:
                log_warn("telegram_chat_id", exc)
    return token, owner_id, sorted(chat_ids), None


# ==================== TELEGRAM INITDATA HMAC & SESSION TOKENS ====================


def verify_telegram_init_data(
    raw: str,
    bot_token: str,
    owner_id: int,
    *,
    max_age: int = 300,
    max_future_skew: int = 60,
    now_ts: float | None = None,
) -> tuple[bool, str, dict | None]:
    """Verify Telegram WebApp initData HMAC-SHA256 strictly per Telegram spec + anti-pollution."""
    if not raw or not bot_token or not owner_id:
        return False, "missing auth", None
    if len(raw) > 8192 or any(ord(c) < 32 for c in raw):
        return False, "malformed initData", None

    pairs = parse_qsl(raw, keep_blank_values=True, strict_parsing=False)
    if not pairs:
        return False, "empty initData", None

    seen: set[str] = set()
    kv: dict[str, str] = {}
    for k, v in pairs:
        if k in seen:
            return False, "duplicate key", None
        seen.add(k)
        kv[k] = v

    given_hash = kv.get("hash", "")
    if not HEX64_RE.fullmatch(given_hash):
        return False, "invalid hash format", None

    data_check_string = "\n".join(f"{k}={v}" for k, v in sorted(kv.items()) if k != "hash")
    secret_key = hmac.new(b"WebAppData", bot_token.encode("utf-8"), hashlib.sha256).digest()
    expected = hmac.new(secret_key, data_check_string.encode("utf-8"), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, given_hash):
        return False, "invalid signature", None

    auth_date_raw = kv.get("auth_date", "")
    if not auth_date_raw.isdigit():
        return False, "invalid auth_date", None
    auth_date = int(auth_date_raw)
    now = int(time.time() if now_ts is None else now_ts)
    if now - auth_date > max_age:
        return False, "initData expired", None
    if auth_date - now > max_future_skew:
        return False, "initData future skew", None

    try:
        user = json.loads(kv.get("user") or "{}")
    except ValueError:
        return False, "invalid user json", None
    if not isinstance(user, dict) or type(user.get("id")) is not int:
        return False, "missing user id", None
    if user["id"] != int(owner_id):
        return False, "unauthorized user", None
    return True, "", user


class SessionManager:
    """Ephemeral HMAC-signed session tokens (per-process key, default 4h TTL)."""

    def __init__(self, ttl_sec: int = 14400):
        self._secret = secrets.token_bytes(32)
        self.ttl_sec = ttl_sec

    def mint(self, owner_id: int, now_ts: float | None = None) -> str:
        exp = int((time.time() if now_ts is None else now_ts) + self.ttl_sec)
        nonce = secrets.token_hex(8)
        payload = f"{int(owner_id)}.{exp}.{nonce}".encode("utf-8")
        sig = hmac.new(self._secret, payload, hashlib.sha256).hexdigest()
        return base64.urlsafe_b64encode(payload).decode("ascii") + "." + sig

    def verify(self, token: str, owner_id: int, now_ts: float | None = None) -> bool:
        if not token or "." not in token or len(token) > 512:
            return False
        b64, _, given_sig = token.partition(".")
        if not HEX64_RE.fullmatch(given_sig):
            return False
        try:
            payload = base64.urlsafe_b64decode(b64.encode("ascii"))
        except Exception:  # noqa: BLE001
            return False
        expected = hmac.new(self._secret, payload, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, given_sig):
            return False
        try:
            uid_s, exp_s, _ = payload.decode("utf-8").split(".", 2)
            uid = int(uid_s)
            exp = int(exp_s)
        except ValueError:
            return False
        now = int(time.time() if now_ts is None else now_ts)
        return uid == int(owner_id) and exp >= now


class RateLimiter:
    """Simple per-bucket sliding-window rate limiter."""

    def __init__(self, limit: int, window_sec: float = 60.0):
        self.limit = limit
        self.window_sec = window_sec
        self._lock = threading.Lock()
        self._hits: dict[str, deque[float]] = {}

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        with self._lock:
            q = self._hits.setdefault(key, deque())
            while q and now - q[0] > self.window_sec:
                q.popleft()
            if len(q) >= self.limit:
                return False
            q.append(now)
            return True


# ==================== READ-ONLY AAF.DB & THROTTLE & MANUAL SESSIONS ====================


def _connect_ro(db_path: str) -> sqlite3.Connection | None:
    if not db_path or not os.path.isfile(db_path):
        return None
    uri = f"file:{quote(os.path.abspath(db_path))}?mode=ro"
    con = sqlite3.connect(uri, uri=True, timeout=2.0)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout = 2000")
    con.execute("PRAGMA query_only = ON")
    return con


def _table_columns(con: sqlite3.Connection, table: str) -> set[str]:
    try:
        return {r[1] for r in con.execute(f"PRAGMA table_info({table})").fetchall()}
    except sqlite3.Error:
        return set()


def _is_lock_file_active(path: str, info: dict[str, str]) -> bool:
    """Detect whether a throttle heavy.*.lock file is actively held (non-blocking flock probe + live pgid fallback)."""
    try:
        st = os.stat(path)
    except OSError:
        return False
    if st.st_size == 0:
        return False
    # Non-blocking shared lock probe: if writer holds LOCK_EX, LOCK_SH|LOCK_NB raises BlockingIOError immediately
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return False
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
            fcntl.flock(fd, fcntl.LOCK_UN)
            # Not flock-locked: check if pgid is genuinely alive (some versions use metadata without flock)
            pgid_s = info.get("pgid") or ""
            if pgid_s.isdigit():
                pgid = int(pgid_s)
                if pgid > 1:
                    try:
                        os.kill(-pgid, 0)
                        return True
                    except PermissionError:
                        return True
                    except OSError:
                        return False
            return False
        except BlockingIOError:
            return True
    finally:
        os.close(fd)


def read_throttle_slots(throttle_dir: str = AAF_THROTTLE_DIR, max_slots: int = 3) -> dict:
    held: list[dict] = []
    if os.path.isdir(throttle_dir):
        for name in sorted(os.listdir(throttle_dir)):
            if not (name.startswith("heavy.") and name.endswith(".lock")):
                continue
            p = os.path.join(throttle_dir, name)
            info: dict[str, str] = {"file": name}
            try:
                with open(p, encoding="utf-8", errors="replace") as f:
                    for line in f.read().splitlines()[:12]:
                        if "=" in line:
                            k, _, v = line.partition("=")
                            info[k.strip()] = v.strip()
            except OSError:
                continue
            if _is_lock_file_active(p, info):
                held.append(info)
    return {"held": len(held), "max": max_slots, "locks": held}


def read_supervisor_state(path: str = SUPERVISOR_STATE_PATH) -> dict:
    default = {"enabled": False, "updatedAt": 0, "repos": {}}
    if not os.path.isfile(path):
        return default
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return {
                "enabled": bool(data.get("enabled", False)),
                "updatedAt": int(data.get("updatedAt") or 0),
                "repos": data.get("repos") if isinstance(data.get("repos"), dict) else {},
            }
    except (OSError, ValueError) as exc:
        log_warn("supervisor_state_read", exc)
    return default


def write_supervisor_state(enabled: bool, path: str = SUPERVISOR_STATE_PATH, repos: dict | None = None) -> dict:
    cur = read_supervisor_state(path)
    cur["enabled"] = bool(enabled)
    cur["updatedAt"] = int(time.time())
    if repos is not None:
        cur["repos"] = repos
    parent = os.path.dirname(path)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    tmp = f"{path}.{os.getpid()}.{secrets.token_hex(4)}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(cur, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError as exc:
            log_warn("supervisor_tmp_cleanup", exc)
        raise
    return cur


def _resolve_repo_name(repo_root: str, repo_paths: dict[str, str]) -> str:
    if not repo_root:
        return "unknown"
    rr = os.path.realpath(repo_root)
    for name, pth in repo_paths.items():
        if not pth:
            continue
        rp = os.path.realpath(pth)
        if rr == rp or rr.startswith(rp + os.sep) or rp.startswith(rr + os.sep):
            return name
    return os.path.basename(rr.rstrip(os.sep)) or repo_root


def scan_manual_claude_sessions(repo_paths: dict[str, str], active_minutes: int = 12) -> list[dict]:
    """Scan all ~/.claude*/projects directories for active manual terminal sessions (read-only)."""
    now = time.time()
    cutoff = now - active_minutes * 60
    results: list[dict] = []
    home = os.path.expanduser("~")
    real_repos = {name: os.path.realpath(p) for name, p in repo_paths.items() if p and os.path.isdir(p)}
    seen_ids: set[str] = set()

    for proj_root in sorted(glob.glob(os.path.join(home, ".claude*", "projects"))):
        if not os.path.isdir(proj_root):
            continue
        acc_dir = os.path.basename(os.path.dirname(proj_root))
        try:
            subdirs = os.listdir(proj_root)
        except OSError:
            continue
        for sub in subdirs:
            sub_path = os.path.join(proj_root, sub)
            if not os.path.isdir(sub_path):
                continue
            try:
                files = [
                    os.path.join(sub_path, fn)
                    for fn in os.listdir(sub_path)
                    if fn.endswith(".jsonl")
                ]
            except OSError:
                continue
            for fp in files:
                try:
                    st = os.stat(fp)
                except OSError:
                    continue
                if st.st_mtime < cutoff:
                    continue
                sid = f"manual-{os.path.splitext(os.path.basename(fp))[0][:12]}"
                if sid in seen_ids:
                    continue
                seen_ids.add(sid)
                cwd = ""
                branch = ""
                title = f"Phiên mở tay Terminal ({acc_dir})"
                try:
                    with open(fp, "rb") as f:
                        head = f.read(8192).decode("utf-8", errors="replace")
                    for line in head.splitlines()[:10]:
                        obj = json.loads(line)
                        if not cwd and isinstance(obj.get("cwd"), str):
                            cwd = obj["cwd"]
                        if not branch and isinstance(obj.get("gitBranch"), str):
                            branch = obj["gitBranch"]
                except (OSError, ValueError) as exc:
                    log_warn("manual_session_head", exc)
                repo_name = _resolve_repo_name(cwd, real_repos) if cwd else "other"
                if repo_name not in real_repos:
                    continue
                mins = max(1, int((now - st.st_mtime) // 60))
                results.append(
                    {
                        "id": sid,
                        "repo": repo_name,
                        "state": "running",
                        "priority": "—",
                        "kind": "manual",
                        "title": redact_aaf(title),
                        "branch": branch or "local",
                        "worktree": os.path.basename(cwd) if cwd else "—",
                        "account": acc_dir,
                        "elapsed": f"{mins}m",
                        "tokens": 0,
                        "blockedReason": "",
                        "isHeadLock": False,
                        "needsPlanApproval": False,
                        "frozen": False,
                        "updatedAt": int(st.st_mtime),
                        "latestRunId": "",
                    }
                )
    return results


def read_studio_state(
    *,
    db_path: str = AAF_DB_PATH,
    repo_paths: dict[str, str] | None = None,
    throttle_dir: str = AAF_THROTTLE_DIR,
    include_manual: bool = True,
    capabilities: dict | None = None,
) -> dict:
    """Build full AAF Studio snapshot from aaf.db + throttle + supervisor + optional manual sessions."""
    repo_paths = repo_paths or {}
    now = time.time()
    slots = read_throttle_slots(throttle_dir)
    sup = read_supervisor_state()
    caps = capabilities or {"allowOAuthLogin": True, "isRemote": False, "canOpenTerminal": True}

    out = {
        "ok": True,
        "ts": int(now * 1000),
        "dbExists": False,
        "summary": {
            "runsTotal": 0,
            "activeRuns": 0,
            "tasksTotal": 0,
            "attentionCount": 0,
            "slotsHeld": slots["held"],
            "slotsMax": slots["max"],
            "autoRunEnabled": sup["enabled"],
        },
        "slots": slots,
        "supervisor": sup,
        "capabilities": caps,
        "repos": [{"id": name, "path": pth} for name, pth in repo_paths.items()],
        "attention": [],
        "tasks": [],
        "aafAccounts": [],
    }

    con = _connect_ro(db_path)
    if con is None:
        if include_manual and repo_paths:
            out["tasks"] = scan_manual_claude_sessions(repo_paths)
        return out

    out["dbExists"] = True
    try:
        # 1. Accounts (with expired cooldown_until filtering)
        acc_cols = _table_columns(con, "accounts")
        acc_by_id: dict[str, str] = {}
        if acc_cols:
            try:
                rows = con.execute("SELECT * FROM accounts ORDER BY id").fetchall()
                for r in rows:
                    d = dict(r)
                    cd = d.get("cooldown_until")
                    in_cd = bool(cd is not None and float(cd) > now)
                    remain_sec = int(float(cd) - now) if in_cd else 0
                    name = d.get("name") or d.get("id") or ""
                    acc_by_id[str(d.get("id") or "")] = name
                    out["aafAccounts"].append(
                        {
                            "id": d.get("id"),
                            "name": name,
                            "provider": d.get("provider") or "",
                            "configDir": d.get("config_dir") or "",
                            "cooldownUntil": cd if in_cd else None,
                            "inCooldown": in_cd,
                            "cooldownRemainSec": remain_sec,
                        }
                    )
            except sqlite3.Error as exc:
                log_warn("db_query", exc)

        # 2. Exact total runs count (never capped by LIMIT)
        run_cols = _table_columns(con, "runs")
        latest_run_by_task: dict[str, dict] = {}
        if run_cols:
            try:
                cnt_row = con.execute("SELECT COUNT(*) AS c FROM runs").fetchone()
                out["summary"]["runsTotal"] = int(cnt_row["c"]) if cnt_row else 0
                active_row = con.execute(
                    "SELECT COUNT(*) AS c FROM runs WHERE status IN ('running','active','gating')"
                ).fetchone()
                out["summary"]["activeRuns"] = int(active_row["c"]) if active_row else 0
                run_rows = con.execute(
                    "SELECT * FROM runs ORDER BY COALESCE(started_at, 0) DESC LIMIT 400"
                ).fetchall()
                for r in run_rows:
                    rd = dict(r)
                    tid = str(rd.get("task_id") or "")
                    if tid and tid not in latest_run_by_task:
                        latest_run_by_task[tid] = rd
            except sqlite3.Error as exc:
                log_warn("db_query", exc)

        # 3. Root budgets (frozen status)
        frozen_roots: set[str] = set()
        budgets_by_root: dict[str, dict] = {}
        if _table_columns(con, "root_budgets"):
            try:
                for r in con.execute("SELECT * FROM root_budgets").fetchall():
                    bd = dict(r)
                    rid = str(bd.get("root_id") or "")
                    budgets_by_root[rid] = bd
                    if bd.get("frozen"):
                        frozen_roots.add(rid)
            except sqlite3.Error as exc:
                log_warn("db_query", exc)

        # 4. Tasks
        if _table_columns(con, "tasks"):
            try:
                trows = con.execute(
                    "SELECT * FROM tasks ORDER BY COALESCE(updated_at, created_at, 0) DESC LIMIT 300"
                ).fetchall()
                # Count subtasks per root_id for parent progress indicator
                sub_counts: dict[str, list[int]] = {}
                for tr in trows:
                    td = dict(tr)
                    root_id = str(td.get("root_id") or td.get("id") or "")
                    if td.get("parent_id"):
                        c = sub_counts.setdefault(root_id, [0, 0])
                        c[1] += 1
                        if str(td.get("state") or "").lower() == "done":
                            c[0] += 1

                for tr in trows:
                    td = dict(tr)
                    tid = str(td.get("id") or "")
                    root_id = str(td.get("root_id") or tid)
                    st_raw = str(td.get("state") or "ready").lower()
                    lrun = latest_run_by_task.get(tid) or {}
                    blocked_reason = redact_aaf(str(td.get("blocked_reason") or ""))
                    is_frozen = root_id in frozen_roots
                    is_head_lock = "head_lock" in blocked_reason.lower()
                    needs_plan = blocked_reason.lower().startswith("plan approval required:")
                    wt_path = str(lrun.get("worktree_path") or "")
                    acc_id = str(lrun.get("account_id") or "")
                    acc_name = acc_by_id.get(acc_id, acc_id or "auto")
                    toks = int(lrun.get("tokens_in") or 0) + int(lrun.get("tokens_out") or 0)
                    started = lrun.get("started_at") or td.get("updated_at") or td.get("created_at") or 0
                    elapsed_s = max(0, int(now - float(started))) if started else 0
                    elapsed = (
                        f"{elapsed_s // 3600}h"
                        if elapsed_s >= 3600
                        else f"{max(1, elapsed_s // 60)}m"
                        if elapsed_s >= 60
                        else f"{elapsed_s}s"
                        if elapsed_s > 0
                        else "—"
                    )
                    try:
                        scope_paths = json.loads(td.get("scope_paths") or "[]")
                        if not isinstance(scope_paths, list):
                            scope_paths = []
                    except ValueError:
                        scope_paths = []
                    parent_label = ""
                    if root_id in sub_counts and sub_counts[root_id][1] > 0:
                        done_n, tot_n = sub_counts[root_id]
                        parent_label = f"Nhóm {root_id} · {done_n}/{tot_n} xong"

                    item = {
                        "id": tid,
                        "repo": _resolve_repo_name(str(td.get("repo_root") or ""), repo_paths),
                        "repoRoot": str(td.get("repo_root") or ""),
                        "parentId": td.get("parent_id"),
                        "rootId": root_id,
                        "parentLabel": parent_label,
                        "state": st_raw,
                        "priority": str(td.get("priority") or "P2"),
                        "kind": "aaf",
                        "title": redact_aaf(str(td.get("title") or tid)),
                        "spec": redact_aaf(str(td.get("spec") or "")),
                        "contextNotes": redact_aaf(str(td.get("context_notes") or "")),
                        "branch": str(lrun.get("branch") or "—"),
                        "worktree": os.path.basename(wt_path) if wt_path else "—",
                        "worktreeExists": bool(wt_path and os.path.isdir(wt_path)),
                        "account": acc_name,
                        "elapsed": elapsed,
                        "tokens": toks,
                        "blockedReason": blocked_reason,
                        "isHeadLock": is_head_lock,
                        "needsPlanApproval": needs_plan,
                        "frozen": is_frozen,
                        "scopePaths": scope_paths,
                        "latestRunId": str(lrun.get("id") or ""),
                        "latestRunStatus": str(lrun.get("status") or ""),
                        "ttyHint": (
                            f'cd "{wt_path}" && aaf approve --reviewer toan'
                            if (is_head_lock and wt_path)
                            else ""
                        ),
                        "updatedAt": int(td.get("updated_at") or td.get("created_at") or 0),
                    }
                    out["tasks"].append(item)
                    if st_raw in ("blocked", "review") or is_frozen:
                        out["attention"].append(item)
            except sqlite3.Error as exc:
                log_warn("db_query", exc)
    finally:
        con.close()

    if include_manual and repo_paths:
        out["tasks"].extend(scan_manual_claude_sessions(repo_paths))

    out["summary"]["tasksTotal"] = len(out["tasks"])
    out["summary"]["attentionCount"] = len(out["attention"])
    return out


# ==================== SAFE STREAMS, DIFF, HANDOVER, PROOF ====================


def _open_no_follow(path: str, allowed_roots: list[str]) -> tuple[int | None, str | None]:
    real_p = os.path.realpath(path)
    ok_root = False
    for root in allowed_roots:
        if not root:
            continue
        rr = os.path.realpath(root)
        if real_p == rr or real_p.startswith(rr + os.sep):
            ok_root = True
            break
    if not ok_root:
        return None, "path outside allowed root"
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        return None, f"cannot open file: {exc.strerror or exc}"
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            os.close(fd)
            return None, "not a regular file"
    except OSError as exc:
        os.close(fd)
        return None, str(exc)
    return fd, None


def read_stream_tail(run_id: str, *, streams_dir: str = AAF_STREAMS_DIR, max_lines: int = _MAX_STREAM_LINES) -> dict:
    if not RUN_ID_RE.fullmatch(run_id or ""):
        return {"ok": False, "error": "invalid run_id", "events": []}
    target = os.path.join(streams_dir, f"{run_id}.jsonl")
    fd, err = _open_no_follow(target, [streams_dir])
    if fd is None:
        return {"ok": False, "error": err or "not found", "events": []}
    try:
        size = os.fstat(fd).st_size
        start = max(0, size - _MAX_STREAM_BYTES)
        if start > 0:
            os.lseek(fd, start, os.SEEK_SET)
        raw = os.read(fd, _MAX_STREAM_BYTES).decode("utf-8", errors="replace")
    finally:
        os.close(fd)

    lines = raw.splitlines()
    if start > 0 and lines:
        lines = lines[1:]  # drop partial first line
    lines = lines[-max_lines:]
    events: list[dict] = []
    for idx, line in enumerate(lines):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if isinstance(obj, dict):
                events.append(json.loads(redact_aaf(json.dumps(obj, ensure_ascii=False))))
            else:
                events.append({"id": f"l{idx}", "kind": "terminal", "title": redact_aaf(str(obj))[:200], "out": ""})
        except ValueError:
            events.append({"id": f"l{idx}", "kind": "terminal", "title": redact_aaf(line)[:200], "out": redact_aaf(line)})
    return {"ok": True, "runId": run_id, "truncated": start > 0, "events": events}


def _allowed_worktree_roots(repo_paths: dict[str, str]) -> list[str]:
    roots = [
        AAF_DATA_DIR,
        os.path.expanduser("~/.cache/autofactory"),
        os.path.expanduser("~/.agent-office"),
    ]
    for p in repo_paths.values():
        if p:
            roots.append(p)
            roots.append(os.path.dirname(os.path.realpath(p)))
    return roots


def read_worktree_diff(worktree_path: str, allowed_roots: list[str]) -> dict:
    if not worktree_path:
        return {"available": False, "reason": "chưa có worktree", "files": [], "patch": "", "truncated": False}
    wt_real = os.path.realpath(worktree_path)
    if not any(wt_real == os.path.realpath(r) or wt_real.startswith(os.path.realpath(r) + os.sep) for r in allowed_roots if r):
        return {"available": False, "reason": "worktree ngoài phạm vi cho phép", "files": [], "patch": "", "truncated": False}
    if not os.path.isdir(wt_real):
        return {"available": False, "reason": "worktree đã được dọn", "files": [], "patch": "", "truncated": False}

    files: list[dict] = []
    try:
        ns = subprocess.run(
            ["git", "-C", wt_real, "diff", "--numstat", "HEAD"],
            capture_output=True,
            text=True,
            timeout=15,
            stdin=subprocess.DEVNULL,
        )
        if ns.returncode == 0:
            for ln in ns.stdout.splitlines():
                parts = ln.split("\t", 2)
                if len(parts) == 3:
                    add = int(parts[0]) if parts[0].isdigit() else 0
                    dl = int(parts[1]) if parts[1].isdigit() else 0
                    files.append({"path": redact_aaf(parts[2]), "add": add, "del": dl})
        df = subprocess.run(
            ["git", "-C", wt_real, "diff", "--no-color", "--no-ext-diff", "HEAD"],
            capture_output=True,
            text=True,
            timeout=15,
            stdin=subprocess.DEVNULL,
        )
        raw_patch = df.stdout if df.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError) as exc:
        return {"available": False, "reason": f"không đọc được git diff: {exc}", "files": [], "patch": "", "truncated": False}

    truncated = len(raw_patch.encode("utf-8")) > _MAX_DIFF_BYTES
    if truncated:
        raw_patch = raw_patch[:_MAX_DIFF_BYTES]
    return {
        "available": True,
        "files": files,
        "patch": redact_aaf(raw_patch),
        "truncated": truncated,
    }


def read_proof_png(png_path: str, allowed_roots: list[str]) -> tuple[bytes | None, str | None]:
    if not png_path or not png_path.lower().endswith(".png"):
        return None, "invalid png extension"
    fd, err = _open_no_follow(png_path, allowed_roots)
    if fd is None:
        return None, err
    try:
        st = os.fstat(fd)
        if st.st_size > _MAX_PROOF_BYTES:
            return None, "proof image too large"
        chunks = []
        rem = _MAX_PROOF_BYTES
        while rem > 0:
            buf = os.read(fd, min(65536, rem))
            if not buf:
                break
            chunks.append(buf)
            rem -= len(buf)
        data = b"".join(chunks)
    finally:
        os.close(fd)
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return None, "invalid png header"
    return data, None


def _run_aaf_json(args: list[str], *, cwd: str | None = None, timeout: int = 20) -> tuple[bool, dict | str]:
    cmd = [find_aaf_bin(), *args]
    try:
        r = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, redact_aaf(str(exc))
    out = (r.stdout or "").strip()
    err = (r.stderr or "").strip()
    if r.returncode != 0:
        return False, redact_aaf(err or out or f"aaf exited {r.returncode}")
    if not out:
        return True, {"ok": True}
    try:
        return True, json.loads(redact_aaf(out))
    except ValueError:
        return True, {"ok": True, "output": redact_aaf(out)}


def read_task_detail(
    task_id: str,
    *,
    db_path: str = AAF_DB_PATH,
    repo_paths: dict[str, str] | None = None,
    streams_dir: str = AAF_STREAMS_DIR,
) -> dict:
    repo_paths = repo_paths or {}
    if not ID_RE.fullmatch(task_id or ""):
        return {"ok": False, "error": "invalid task_id"}
    con = _connect_ro(db_path)
    if con is None:
        return {"ok": False, "error": "aaf.db not found"}
    try:
        trow = con.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not trow:
            return {"ok": False, "error": "task not found"}
        td = dict(trow)
        runs = [
            dict(r)
            for r in con.execute(
                "SELECT * FROM runs WHERE task_id = ? ORDER BY COALESCE(started_at, 0) DESC LIMIT 20",
                (task_id,),
            ).fetchall()
        ]
        events = []
        if _table_columns(con, "events"):
            for er in con.execute(
                "SELECT id, run_id, kind, payload_json, created_at FROM events WHERE task_id = ? ORDER BY id DESC LIMIT 40",
                (task_id,),
            ).fetchall():
                ed = dict(er)
                ed["payload_json"] = redact_aaf(str(ed.get("payload_json") or ""))
                events.append(ed)
    finally:
        con.close()

    latest = runs[0] if runs else {}
    wt_path = str(latest.get("worktree_path") or "")
    allowed_roots = _allowed_worktree_roots(repo_paths)
    stream = (
        read_stream_tail(str(latest.get("id") or ""), streams_dir=streams_dir)
        if latest.get("id")
        else {"ok": True, "events": [], "truncated": False}
    )
    diff = read_worktree_diff(wt_path, allowed_roots)
    repo_root = str(td.get("repo_root") or "")

    ok_ho, ho_data = _run_aaf_json(["handover", task_id, "--format", "json"], cwd=repo_root if os.path.isdir(repo_root) else None, timeout=15)
    handover = ho_data if (ok_ho and isinstance(ho_data, dict)) else {"available": False, "note": ho_data if isinstance(ho_data, str) else ""}

    proof_info: dict = {"available": False, "images": []}
    if wt_path and os.path.isdir(wt_path):
        ok_pf, pf_data = _run_aaf_json(["proof", "show", "--json"], cwd=wt_path, timeout=15)
        if ok_pf and isinstance(pf_data, dict):
            proof_info = {"available": True, "raw": pf_data, "images": []}
            imgs = pf_data.get("images") or pf_data.get("artifacts") or []
            if isinstance(imgs, list):
                for idx, item in enumerate(imgs):
                    if isinstance(item, dict) and item.get("path"):
                        proof_info["images"].append(
                            {
                                "idx": idx,
                                "name": os.path.basename(str(item["path"])),
                                "url": f"/api/aaf/proof-image?task_id={quote(task_id)}&idx={idx}",
                            }
                        )

    blocked_reason = redact_aaf(str(td.get("blocked_reason") or ""))
    is_head_lock = "head_lock" in blocked_reason.lower()
    return {
        "ok": True,
        "task": {
            "id": task_id,
            "repo": _resolve_repo_name(repo_root, repo_paths),
            "title": redact_aaf(str(td.get("title") or "")),
            "spec": redact_aaf(str(td.get("spec") or "")),
            "contextNotes": redact_aaf(str(td.get("context_notes") or "")),
            "state": str(td.get("state") or "").lower(),
            "priority": str(td.get("priority") or "P2"),
            "blockedReason": blocked_reason,
            "isHeadLock": is_head_lock,
            "needsPlanApproval": blocked_reason.lower().startswith("plan approval required:"),
            "ttyHint": f'cd "{wt_path}" && aaf approve --reviewer toan' if (is_head_lock and wt_path) else "",
        },
        "runs": runs,
        "stream": stream,
        "diff": diff,
        "handover": handover,
        "proof": proof_info,
        "events": events,
    }


# ==================== CLAP-SAFE AAF CLI BUILDERS & EMERGENCY STOP ====================


def build_board_add_args(
    *,
    title: str,
    spec: str,
    accept: str,
    priority: str = "P1",
    scope: str = "",
) -> list[str]:
    if not title.strip() or not spec.strip() or not accept.strip():
        raise ValueError("Cần đủ title, spec và accept")
    pri = priority.strip().upper()
    if pri not in ALLOWED_PRIORITIES:
        raise ValueError("Priority chỉ nhận P0..P3")
    args = [
        "board",
        "add",
        "--json",
        f"--title={title.strip()}",
        f"--spec={spec.strip()}",
        f"--accept={accept.strip()}",
        f"--priority={pri}",
    ]
    if scope.strip():
        args.append(f"--scope={scope.strip()}")
    return args


def build_board_steer_args(task_id: str, note: str) -> list[str]:
    if not ID_RE.fullmatch(task_id or ""):
        raise ValueError("task_id không hợp lệ")
    if not (note or "").strip():
        raise ValueError("Cần nhập nội dung steer")
    return ["board", "steer", "--json", "--", task_id, note.strip()]


def build_board_rework_args(task_id: str, reason: str, *, rerun: bool = True) -> list[str]:
    if not ID_RE.fullmatch(task_id or ""):
        raise ValueError("task_id không hợp lệ")
    if not (reason or "").strip():
        raise ValueError("Rework bắt buộc có --reason")
    args = ["board", "rework", "--json", f"--reason={reason.strip()}"]
    if rerun:
        args.append("--rerun")
    args.extend(["--", task_id])
    return args


def can_killpg_safely(
    pgid: int,
    *,
    pgid_members: list[tuple[int, str]],
    allowed_cmds: tuple[str, ...] = AGENT_CMD_MARKERS,
) -> bool:
    """Only allow killpg if pgid > 1, not our own pgid, and EVERY member is an agent/factory process."""
    if pgid <= 1 or pgid == os.getpgrp():
        return False
    my_pid = os.getpid()
    if not pgid_members:
        return False
    for pid, cmd in pgid_members:
        if pid == my_pid:
            return False
        low = (cmd or "").lower()
        if not any(m in low for m in allowed_cmds):
            return False
    return True


def emergency_stop_run(run_id: str, *, db_path: str = AAF_DB_PATH, repo_paths: dict[str, str] | None = None) -> dict:
    """Safely SIGTERM only verified agent processes executing inside the run's DB worktree."""
    if not RUN_ID_RE.fullmatch(run_id or ""):
        return {"ok": False, "error": "run_id không hợp lệ"}
    con = _connect_ro(db_path)
    if con is None:
        return {"ok": False, "error": "Không tìm thấy aaf.db"}
    try:
        row = con.execute("SELECT id, worktree_path, status FROM runs WHERE id = ?", (run_id,)).fetchone()
    finally:
        con.close()
    if not row:
        return {"ok": False, "error": "Không tìm thấy run"}
    if str(row["status"] or "").lower() not in ("running", "active", "gating"):
        return {"ok": False, "error": f"Phiên đang ở trạng thái {row['status']}, không thể dừng"}
    wt = str(row["worktree_path"] or "")
    if not wt:
        return {"ok": False, "error": "Run không có worktree_path"}
    wt_real = os.path.realpath(wt)
    allowed_roots = _allowed_worktree_roots(repo_paths or {})
    if not any(wt_real == os.path.realpath(r) or wt_real.startswith(os.path.realpath(r) + os.sep) for r in allowed_roots if r):
        return {"ok": False, "error": "worktree_path ngoài phạm vi cho phép"}

    # Enumerate candidate agent processes via ps
    try:
        ps = subprocess.run(
            ["ps", "-axww", "-o", "pid=,pgid=,command="],
            capture_output=True,
            text=True,
            timeout=5,
            stdin=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return {"ok": False, "error": f"Không quét được tiến trình: {exc}"}

    my_pid = os.getpid()
    by_pgid: dict[int, list[tuple[int, str]]] = {}
    matched_pids: list[tuple[int, int]] = []
    for ln in ps.stdout.splitlines():
        parts = ln.strip().split(None, 2)
        if len(parts) < 3 or not parts[0].isdigit() or not parts[1].isdigit():
            continue
        pid, pgid, cmd = int(parts[0]), int(parts[1]), parts[2]
        by_pgid.setdefault(pgid, []).append((pid, cmd))
        if pid == my_pid:
            continue
        low = cmd.lower()
        if not any(m in low for m in AGENT_CMD_MARKERS):
            continue
        matched = wt_real in cmd
        if not matched:
            try:
                ls_out = subprocess.run(
                    ["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"],
                    capture_output=True,
                    text=True,
                    timeout=3,
                    stdin=subprocess.DEVNULL,
                ).stdout
                for ll in ls_out.splitlines():
                    if ll.startswith("n"):
                        c_real = os.path.realpath(ll[1:])
                        if c_real == wt_real or c_real.startswith(wt_real + os.sep):
                            matched = True
                            break
            except (OSError, subprocess.SubprocessError) as exc:
                log_warn("lsof_cwd", exc)
        if matched:
            matched_pids.append((pid, pgid))

    if not matched_pids:
        return {"ok": False, "error": "Không tìm thấy tiến trình agent đang chạy trong worktree này"}

    signaled: list[int] = []
    signaled_pgids: set[int] = set()
    for pid, pgid in matched_pids:
        if pgid in signaled_pgids:
            continue
        if can_killpg_safely(pgid, pgid_members=by_pgid.get(pgid, [])):
            try:
                os.killpg(pgid, signal.SIGTERM)
                signaled_pgids.add(pgid)
                signaled.append(pid)
            except OSError as exc:
                log_warn("killpg_signal", exc)
        else:
            try:
                os.kill(pid, signal.SIGTERM)
                signaled.append(pid)
            except OSError as exc:
                log_warn("kill_signal", exc)
    return {"ok": bool(signaled), "signaledPids": signaled, "signaledPgids": sorted(signaled_pgids)}


def execute_aaf_action(
    body: dict,
    *,
    repo_paths: dict[str, str],
    db_path: str = AAF_DB_PATH,
) -> tuple[int, dict]:
    action = str(body.get("action") or "").strip().lower()
    if action == "supervisor_toggle":
        en = bool(body.get("enabled"))
        st = write_supervisor_state(en)
        return 200, {"ok": True, "supervisor": st}

    if action == "add":
        repo = str(body.get("repo") or "").strip()
        rpath = repo_paths.get(repo)
        if not rpath or not os.path.isdir(rpath):
            return 400, {"ok": False, "error": f"Repo không hợp lệ: {repo}"}
        try:
            args = build_board_add_args(
                title=str(body.get("title") or ""),
                spec=str(body.get("spec") or ""),
                accept=str(body.get("accept") or ""),
                priority=str(body.get("priority") or "P1"),
                scope=str(body.get("scope") or ""),
            )
        except ValueError as exc:
            return 400, {"ok": False, "error": str(exc)}
        ok, res = _run_aaf_json(args, cwd=rpath, timeout=25)
        return (200 if ok else 400), (res if isinstance(res, dict) else {"ok": False, "error": res})

    if action == "steer":
        tid = str(body.get("taskId") or "").strip()
        note = str(body.get("note") or "")
        con = _connect_ro(db_path)
        if con is None:
            return 503, {"ok": False, "error": "Không mở được aaf.db"}
        try:
            row = con.execute("SELECT state, repo_root FROM tasks WHERE id = ?", (tid,)).fetchone()
        finally:
            con.close()
        if not row:
            return 404, {"ok": False, "error": "Không tìm thấy task (không thể steer phiên chạy tay)"}
        if str(row["state"] or "").lower() == "done":
            return 400, {"ok": False, "error": "Task đã Done, không thể gửi Steer"}
        try:
            args = build_board_steer_args(tid, note)
        except ValueError as exc:
            return 400, {"ok": False, "error": str(exc)}
        ok, res = _run_aaf_json(args, cwd=str(row["repo_root"] or "") or None, timeout=20)
        return (200 if ok else 400), (res if isinstance(res, dict) else {"ok": False, "error": res})

    if action == "rework":
        tid = str(body.get("taskId") or "").strip()
        reason = str(body.get("reason") or "")
        con = _connect_ro(db_path)
        if con is None:
            return 503, {"ok": False, "error": "Không mở được aaf.db"}
        try:
            row = con.execute("SELECT state, repo_root FROM tasks WHERE id = ?", (tid,)).fetchone()
        finally:
            con.close()
        if not row:
            return 404, {"ok": False, "error": "Không tìm thấy task"}
        if str(row["state"] or "").lower() != "review":
            return 400, {"ok": False, "error": "Chỉ được Rework khi task đang ở trạng thái Review"}
        try:
            args = build_board_rework_args(tid, reason, rerun=bool(body.get("rerun", True)))
        except ValueError as exc:
            return 400, {"ok": False, "error": str(exc)}
        ok, res = _run_aaf_json(args, cwd=str(row["repo_root"] or "") or None, timeout=20)
        return (200 if ok else 400), (res if isinstance(res, dict) else {"ok": False, "error": res})

    if action == "unblock":
        tid = str(body.get("taskId") or "").strip()
        if not ID_RE.fullmatch(tid):
            return 400, {"ok": False, "error": "taskId không hợp lệ"}
        con = _connect_ro(db_path)
        if con is None:
            return 503, {"ok": False, "error": "Không mở được aaf.db"}
        try:
            row = con.execute("SELECT state, repo_root FROM tasks WHERE id = ?", (tid,)).fetchone()
        finally:
            con.close()
        if not row or str(row["state"] or "").lower() != "blocked":
            return 400, {"ok": False, "error": "Chỉ Unblock được task đang ở trạng thái Blocked"}
        ok, res = _run_aaf_json(["board", "unblock", "--json", "--", tid], cwd=str(row["repo_root"] or "") or None, timeout=20)
        return (200 if ok else 400), (res if isinstance(res, dict) else {"ok": False, "error": res})

    if action == "approve_plan":
        tid = str(body.get("taskId") or "").strip()
        if not ID_RE.fullmatch(tid):
            return 400, {"ok": False, "error": "taskId không hợp lệ"}
        con = _connect_ro(db_path)
        if con is None:
            return 503, {"ok": False, "error": "Không mở được aaf.db"}
        try:
            row = con.execute("SELECT blocked_reason, repo_root FROM tasks WHERE id = ?", (tid,)).fetchone()
        finally:
            con.close()
        br = str(row["blocked_reason"] or "") if row else ""
        if not br.lower().startswith("plan approval required:"):
            return 400, {"ok": False, "error": "Task này không ở trạng thái chờ duyệt kế hoạch"}
        ok, res = _run_aaf_json(["board", "approve-plan", "--json", "--", tid], cwd=str(row["repo_root"] or "") or None, timeout=20)
        return (200 if ok else 400), (res if isinstance(res, dict) else {"ok": False, "error": res})

    if action == "unfreeze":
        repo = str(body.get("repo") or "").strip()
        rpath = repo_paths.get(repo)
        if not rpath or not os.path.isdir(rpath):
            return 400, {"ok": False, "error": "Repo không hợp lệ"}
        ok, res = _run_aaf_json(["board", "unfreeze", "--json"], cwd=rpath, timeout=20)
        return (200 if ok else 400), (res if isinstance(res, dict) else {"ok": False, "error": res})

    if action == "stop":
        if not body.get("confirm"):
            return 400, {"ok": False, "error": "Cần xác nhận 2 bước (confirm=true) trước khi dừng phiên"}
        run_id = str(body.get("runId") or "").strip()
        res = emergency_stop_run(run_id, db_path=db_path, repo_paths=repo_paths)
        return (200 if res.get("ok") else 400), res

    return 400, {"ok": False, "error": f"Hành động không hỗ trợ: {action}"}


def run_read_only_ask(repo: str, question: str, *, repo_paths: dict[str, str], timeout: int = 90) -> tuple[int, dict]:
    rpath = repo_paths.get(repo)
    if not rpath or not os.path.isdir(rpath):
        return 400, {"ok": False, "error": f"Repo không hợp lệ: {repo}"}
    q = (question or "").strip()
    if not q or len(q) > 4000:
        return 400, {"ok": False, "error": "Câu hỏi trống hoặc vượt quá 4000 ký tự"}
    if not _ASK_SEMAPHORE.acquire(blocking=False):
        return 429, {"ok": False, "error": "Đang có 1 câu hỏi /btw khác đang chạy, chờ xong rồi thử lại"}
    try:
        claude = shutil.which("claude") or "claude"
        prompt = (
            "Trả lời ngắn gọn bằng tiếng Việt (read-only, không sửa file). "
            "Dẫn rõ tên file và dòng code liên quan.\n\nCâu hỏi:\n" + q
        )
        t0 = time.monotonic()
        r = subprocess.run(
            [
                claude,
                "-p",
                "--permission-mode",
                "plan",
                "--tools",
                "Read,Glob,Grep",
                "--max-turns",
                "5",
                "--no-session-persistence",
                "--",
                prompt,
            ],
            cwd=rpath,
            capture_output=True,
            text=True,
            timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
        elapsed = round(time.monotonic() - t0, 1)
        if r.returncode != 0:
            return 502, {"ok": False, "error": redact_aaf((r.stderr or r.stdout or "claude failed")[:500])}
        return 200, {"ok": True, "repo": repo, "elapsedSec": elapsed, "answer": redact_aaf((r.stdout or "").strip()[:12000])}
    except subprocess.TimeoutExpired:
        return 504, {"ok": False, "error": f"Hỏi nhanh quá hạn {timeout}s"}
    except OSError as exc:
        return 503, {"ok": False, "error": f"Không chạy được claude CLI: {exc}"}
    finally:
        _ASK_SEMAPHORE.release()


def filter_cc_switcher_action(body: dict, *, remote: bool, repo_paths: dict[str, str]) -> tuple[int | None, str | None]:
    """Validate cc-switcher action; on remote (:4318) strictly block login/repo_add/repo_remove."""
    action = str(body.get("action") or "").strip().lower()
    if remote:
        if action not in REMOTE_CC_ACTIONS:
            return 403, f"Thao tác '{action}' chỉ cho phép trên máy Mac (:4317)"
        if action == "repo_assign":
            target_repo = str(body.get("repo") or "").strip()
            allowed_real = {os.path.realpath(p) for p in repo_paths.values() if p}
            if not target_repo or os.path.realpath(target_repo) not in allowed_real:
                return 403, "Đường dẫn repo không nằm trong danh sách cấu hình"
    return None, None


def sync_cooldown_to_aaf(body: dict) -> None:
    """Best-effort sync of cooldown/unfreeze actions to aaf accounts cooldown (ignores Antigravity-only ids)."""
    action = str(body.get("action") or "").strip().lower()
    acc_id = str(body.get("account") or body.get("profile") or "").strip()
    if not acc_id or acc_id.startswith("antigravity"):
        return
    if not ID_RE.fullmatch(acc_id):
        return
    if action == "unfreeze":
        _run_aaf_json(["accounts", "cooldown", "--json", "--clear", "--", acc_id], timeout=10)
    elif action == "limit":
        until = int(time.time() + 5 * 3600)
        _run_aaf_json(["accounts", "cooldown", "--json", "--until", str(until), "--", acc_id], timeout=10)


# ==================== ISOLATED :4318 REMOTE HANDLER (TELEGRAM MINI APP) ====================


def make_remote_handler(
    *,
    cfg: dict,
    bot_token: str,
    owner_id: int,
    db_path: str = AAF_DB_PATH,
    streams_dir: str = AAF_STREAMS_DIR,
    throttle_dir: str = AAF_THROTTLE_DIR,
    web_dir: str = "",
    cc_switcher_fn=None,
    cc_args_fn=None,
):
    """Minimal isolated HTTP handler strictly for port :4318 (Telegram Mini App / Remote PWA)."""
    allowed_hosts = {str(h).lower() for h in (cfg.get("remoteAllowedHosts") or []) if h}
    allowed_hosts.update({"127.0.0.1", "localhost", "::1"})
    repo_paths = _build_repo_paths(cfg)
    sessions = SessionManager(ttl_sec=14400)
    gen_limiter = RateLimiter(limit=120, window_sec=60.0)
    heavy_limiter = RateLimiter(limit=12, window_sec=60.0)
    cc_lock = threading.Lock()
    web_root = os.path.realpath(web_dir or os.path.join(os.path.dirname(os.path.abspath(__file__)), "web"))

    def host_allowed(hdr_host: str | None) -> bool:
        h = host_name(hdr_host)
        if not h:
            return False
        return h in allowed_hosts or h.endswith(".ts.net") or h.endswith(".trycloudflare.com")

    def origin_ok(handler: BaseHTTPRequestHandler) -> bool:
        origin = handler.headers.get("Origin")
        if not origin:
            return True
        oh = host_name(urlparse(origin).netloc)
        hh = host_name(handler.headers.get("Host"))
        return bool(oh and hh and oh == hh)

    def authenticate(handler: BaseHTTPRequestHandler) -> tuple[bool, int, str]:
        if not host_allowed(handler.headers.get("Host")):
            return False, 403, "forbidden host"
        if not origin_ok(handler):
            return False, 403, "forbidden origin"
        if handler.headers.get("X-AAF-Studio") != "1":
            return False, 403, "missing X-AAF-Studio"
        sess = (handler.headers.get("X-AAF-Session") or "").strip()
        if sess and sessions.verify(sess, owner_id):
            return True, 200, ""
        init_raw = (handler.headers.get("X-Telegram-Init-Data") or "").strip()
        if init_raw:
            ok, err, _ = verify_telegram_init_data(init_raw, bot_token, owner_id)
            if ok:
                return True, 200, ""
            return False, 401, err
        return False, 401, "missing credentials"

    class RemoteHandler(BaseHTTPRequestHandler):
        server_version = "AAFStudioRemote/1.0"

        def setup(self):
            super().setup()
            try:
                self.request.settimeout(15.0)
            except OSError as exc:
                log_warn("remote_socket_timeout", exc)

        def log_message(self, *args):
            return None

        def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Cache-Control", "no-store")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _json(self, code: int, obj: dict):
            self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

        def do_GET(self):
            if not host_allowed(self.headers.get("Host")):
                return self._json(403, {"ok": False, "error": "forbidden host"})
            if not gen_limiter.allow(self.client_address[0]):
                return self._json(429, {"ok": False, "error": "rate limited"})

            parsed = urlparse(self.path)
            path = parsed.path

            # Unauthenticated zero-data Studio shell ONLY (Telegram Mini App entry point)
            if path in ("", "/", "/studio", "/studio/"):
                full = os.path.realpath(os.path.join(web_root, "studio.html"))
                if not full.startswith(web_root + os.sep) or not os.path.isfile(full):
                    return self._send(404, b"studio.html not found", "text/plain; charset=utf-8")
                with open(full, "rb") as f:
                    data = f.read()
                return self._send(
                    200,
                    data,
                    "text/html; charset=utf-8",
                    {"Content-Security-Policy": REMOTE_STUDIO_CSP},
                )

            # Strict isolation: ONLY /api/aaf/* routes exist on :4318
            if not path.startswith("/api/aaf/"):
                return self._json(404, {"ok": False, "error": "not found"})

            ok, code, err = authenticate(self)
            if not ok:
                return self._json(code, {"ok": False, "error": err})

            q = parse_qs(parsed.query)
            if path == "/api/aaf/studio":
                state = read_studio_state(
                    db_path=db_path,
                    repo_paths=repo_paths,
                    throttle_dir=throttle_dir,
                    capabilities={"allowOAuthLogin": False, "isRemote": True, "canOpenTerminal": False},
                )
                return self._json(200, state)

            if path == "/api/aaf/task/detail":
                tid = (q.get("id") or [""])[0]
                det = read_task_detail(tid, db_path=db_path, repo_paths=repo_paths, streams_dir=streams_dir)
                return self._json(200 if det.get("ok") else 404, det)

            if path == "/api/aaf/proof-image":
                tid = (q.get("task_id") or [""])[0]
                idx_s = (q.get("idx") or ["0"])[0]
                if not idx_s.isdigit():
                    return self._json(400, {"ok": False, "error": "invalid idx"})
                det = read_task_detail(tid, db_path=db_path, repo_paths=repo_paths, streams_dir=streams_dir)
                raw_pf = (det.get("proof") or {}).get("raw") or {}
                imgs = raw_pf.get("images") or raw_pf.get("artifacts") or []
                idx = int(idx_s)
                if not isinstance(imgs, list) or idx >= len(imgs):
                    return self._json(404, {"ok": False, "error": "proof image not found"})
                p = str((imgs[idx] or {}).get("path") or "")
                data, perr = read_proof_png(p, _allowed_worktree_roots(repo_paths))
                if data is None:
                    return self._json(403, {"ok": False, "error": perr or "invalid proof"})
                return self._send(200, data, "image/png")

            if path == "/api/aaf/accounts":
                if not cc_switcher_fn:
                    return self._json(503, {"ok": False, "error": "cc-switcher unavailable"})
                args = ["--panel-json"] + (["--refresh"] if (q.get("refresh") or [""])[0] == "1" else [])
                sc, res = cc_switcher_fn(args)
                if isinstance(res, dict):
                    res = dict(res)
                    res["capabilities"] = {"allowOAuthLogin": False, "isRemote": True}
                return self._json(sc, res)

            return self._json(404, {"ok": False, "error": "not found"})

        def do_POST(self):
            if not host_allowed(self.headers.get("Host")):
                return self._json(403, {"ok": False, "error": "forbidden host"})
            if not origin_ok(self):
                return self._json(403, {"ok": False, "error": "forbidden origin"})
            if self.headers.get("X-AAF-Studio") != "1":
                return self._json(403, {"ok": False, "error": "missing X-AAF-Studio"})

            parsed = urlparse(self.path)
            path = parsed.path
            if not path.startswith("/api/aaf/"):
                return self._json(404, {"ok": False, "error": "not found"})

            try:
                clen = int(self.headers.get("Content-Length") or "0")
            except ValueError:
                return self._json(400, {"ok": False, "error": "bad Content-Length"})
            if clen < 0 or clen > _MAX_REMOTE_BODY:
                return self._json(413, {"ok": False, "error": "payload too large"})
            try:
                raw_body = self.rfile.read(clen) if clen else b"{}"
                body = json.loads(raw_body or b"{}")
                if not isinstance(body, dict):
                    raise ValueError("object required")
            except ValueError:
                return self._json(400, {"ok": False, "error": "bad json"})

            # Session token exchange endpoint (fresh initData <= 300s -> 4h ephemeral session)
            if path == "/api/aaf/auth":
                if not heavy_limiter.allow("auth:" + self.client_address[0]):
                    return self._json(429, {"ok": False, "error": "too many auth requests"})
                init_raw = (self.headers.get("X-Telegram-Init-Data") or "").strip()
                ok, err, user = verify_telegram_init_data(init_raw, bot_token, owner_id)
                if not ok:
                    return self._json(401, {"ok": False, "error": err})
                tok = sessions.mint(owner_id)
                return self._json(200, {"ok": True, "sessionToken": tok, "expiresIn": sessions.ttl_sec, "user": user})

            ok, code, err = authenticate(self)
            if not ok:
                return self._json(code, {"ok": False, "error": err})

            if path == "/api/aaf/action":
                sc, res = execute_aaf_action(body, repo_paths=repo_paths, db_path=db_path)
                return self._json(sc, res)

            if path == "/api/aaf/ask":
                if not heavy_limiter.allow("ask:" + self.client_address[0]):
                    return self._json(429, {"ok": False, "error": "rate limited"})
                sc, res = run_read_only_ask(
                    str(body.get("repo") or ""),
                    str(body.get("question") or ""),
                    repo_paths=repo_paths,
                )
                return self._json(sc, res)

            if path == "/api/aaf/accounts/action":
                f_code, f_err = filter_cc_switcher_action(body, remote=True, repo_paths=repo_paths)
                if f_code:
                    return self._json(f_code, {"ok": False, "error": f_err})
                if not cc_switcher_fn:
                    return self._json(503, {"ok": False, "error": "cc-switcher unavailable"})
                try:
                    args = cc_args_fn(body) if cc_args_fn else ["--panel-action", str(body.get("action") or "")]
                except ValueError as exc:
                    return self._json(400, {"ok": False, "error": str(exc)})
                if not cc_lock.acquire(timeout=30):
                    return self._json(409, {"ok": False, "error": "Đang có thao tác tài khoản khác"})
                try:
                    sc, res = cc_switcher_fn(args)
                finally:
                    cc_lock.release()
                if sc == 200 and isinstance(res, dict) and res.get("ok"):
                    sync_cooldown_to_aaf(body)
                return self._json(sc, res)

            return self._json(404, {"ok": False, "error": "not found"})

    return RemoteHandler


def _build_repo_paths(cfg: dict) -> dict[str, str]:
    root = os.path.expanduser(str(cfg.get("root") or ""))
    explicit = cfg.get("repoPaths") or {}
    out: dict[str, str] = {}
    for name in cfg.get("repos") or []:
        if name in explicit and explicit[name]:
            out[name] = os.path.expanduser(str(explicit[name]))
        elif root:
            out[name] = os.path.join(root, name)
    for name, p in explicit.items():
        if name not in out and p:
            out[name] = os.path.expanduser(str(p))
    return out
