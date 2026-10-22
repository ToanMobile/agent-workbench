#!/usr/bin/env python3
"""One super-board Telegram notice. A missing token exits 0 and opens no socket.

The approval file is a pointer (repo, pr, head, source). It is not authorization.
The button's callback_data is sb:ap: plus 16 hex (22 bytes). Network errors do not
fail the caller: this process still exits 0.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import time
import urllib.error
import urllib.request
from pathlib import Path

SHA = re.compile(r"[0-9a-f]{40}\Z")
SHA_IN_TEXT = re.compile(r"\b[0-9a-f]{40}\b")
REPO = re.compile(r"[^/\s]+/[^/\s]+\Z")


def telegram_env_path() -> Path:
    override = os.environ.get("SB_TELEGRAM_ENV")
    if override:
        return Path(override)
    return Path.home() / ".cc-switch" / "telegram.env"


def load_telegram() -> tuple[str, str]:
    """Return (token, chat). Empty when the file or the keys are missing. Never prints the token."""
    path = telegram_env_path()
    forced = bool(os.environ.get("SB_TELEGRAM_ENV"))
    token = "" if forced else os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat = "" if forced else os.environ.get("TELEGRAM_CHAT_ID", "")
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        text = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip().strip('"').strip("'")
        if key == "TELEGRAM_BOT_TOKEN" and value:
            token = value
        elif key == "TELEGRAM_CHAT_ID" and value:
            chat = value
    return token, chat


def approvals_dir() -> Path:
    override = os.environ.get("SB_APPROVALS_DIR")
    if override:
        return Path(override)
    return Path.home() / ".claude" / "super-board" / "approvals"


def now_s() -> float:
    raw = os.environ.get("SB_NOTIFY_NOW")
    if raw:
        try:
            return float(raw)
        except ValueError:
            pass
    return time.time()


def deliver(token: str, method: str, body: dict) -> None:
    """POST one Bot API method. Tests replace this. The token is not logged."""
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        "https://api.telegram.org/bot%s/%s" % (token, method),
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


def safe_deliver(token: str, method: str, body: dict) -> bool:
    try:
        deliver(token, method, body)
    except (OSError, urllib.error.URLError, TimeoutError, ValueError):
        return False
    return True


def send_text(token: str, chat: str, text: str) -> bool:
    return safe_deliver(token, "sendMessage", {"chat_id": chat, "text": text})


def describe(card: str, repo: str, title: str, text: str = "") -> str:
    """Tin đọc được: việc gì (tiêu đề), của project nào. Thiếu title thì giữ dạng cũ card + text."""
    title = " ".join((title or "").split())
    if not title:
        return ("%s\n%s" % (card, text)).strip()
    project = (repo or "").rsplit("/", 1)[-1]
    head = ("%s — %s" % (text, title)) if text else title
    tail = " · ".join(p for p in (project and "Project: %s" % project, card) if p)
    return ("%s\n%s" % (head, tail)).strip()


def accounts_key(raw: str) -> str:
    parts = sorted({p.strip() for p in (raw or "").split(",") if p.strip()})
    return ",".join(parts) or "all"


def limited_should_send(state_dir: Path, accounts: str, now: float, interval: float = 3600.0) -> bool:
    """Resend only when the limited set changes or an hour has passed."""
    state_dir.mkdir(parents=True, exist_ok=True)
    path = state_dir / "accounts-limited.json"
    key = accounts_key(accounts)
    prev: dict = {}
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            prev = loaded
    except (OSError, ValueError):
        prev = {}
    changed = prev.get("accounts") != key
    try:
        last = float(prev.get("at") or 0)
    except (TypeError, ValueError):
        last = 0.0
    if not changed and now - last < interval:
        return False
    return True


def mark_limited_sent(state_dir: Path, accounts: str, now: float) -> None:
    """Ghi mốc chỉ sau khi gửi thành công. Gửi lỗi thì lần sau vẫn được gửi."""
    state_dir.mkdir(parents=True, exist_ok=True)
    path = state_dir / "accounts-limited.json"
    path.write_text(json.dumps({"accounts": accounts_key(accounts), "at": now}), encoding="utf-8")


def write_approval(repo: str, pr: int, head: str, source: int) -> str:
    directory = approvals_dir()
    directory.mkdir(parents=True, exist_ok=True)
    token = secrets.token_hex(8)
    payload = {"repo": repo, "pr": int(pr), "head": head, "source": int(source)}
    (directory / ("%s.json" % token)).write_text(json.dumps(payload), encoding="utf-8")
    return token


def run(args: argparse.Namespace) -> int:
    if os.environ.get("SB_NOTIFY_SKIP") == "1" or os.environ.get("SB_LIB_ONLY") == "1":
        return 0
    card = (args.card or "").strip()
    if card == "lib" or args.cmd == "runaway":
        return 0
    # Chặn bắn Telegram thật khi chạy từ thư mục tạm của test (/tmp, /var/folders) trừ khi test truyền SB_TELEGRAM_ENV tường minh.
    if not os.environ.get("SB_TELEGRAM_ENV"):
        cwd = os.path.realpath(os.getcwd())
        if cwd.startswith(("/tmp/", "/var/folders/", "/private/tmp/", "/private/var/folders/")):
            return 0
    token, chat = load_telegram()
    if not token or not chat:
        return 0
    if args.cmd == "send":
        text = SHA_IN_TEXT.sub(lambda m: m.group(0)[:7], args.text or "") if args.title else (args.text or "")
        body = describe(card, args.repo, args.title, text)
        if body:
            send_text(token, chat, body)
        return 0
    if args.cmd == "accounts-limited":
        state = Path(args.state_dir) if args.state_dir else Path.home() / ".claude" / "super-board"
        if not limited_should_send(state, args.accounts or "all", now_s()):
            return 0
        if send_text(token, chat, "%s\nevery worker account is at its limit: %s" % (card or "super-board", accounts_key(args.accounts or "all"))):
            mark_limited_sent(state, args.accounts or "all", now_s())
        return 0
    if args.cmd == "approve-button":
        if not args.repo or not REPO.fullmatch(args.repo) or not SHA.fullmatch(args.head or "") or args.pr < 1 or args.source < 1:
            return 0
        pointer = write_approval(args.repo, args.pr, args.head, args.source)
        callback = "sb:ap:%s" % pointer
        send_text_with_button = {
            "chat_id": chat,
            "text": describe(card or ("PR #%s" % args.pr), args.repo, args.title, "cần bạn duyệt")
            if args.title
            else "%s\nneeds you — approve comments done on the same source" % (card or ("PR #%s" % args.pr)),
            "reply_markup": {"inline_keyboard": [[{"text": "Approve", "callback_data": callback}]]},
        }
        safe_deliver(token, "sendMessage", send_text_with_button)
        return 0
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Send one super-board Telegram notice")
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name in ("send", "runaway"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--text", default="")
        cmd.add_argument("--card", default="")
        cmd.add_argument("--repo", default="")
        cmd.add_argument("--title", default="")
    limited = sub.add_parser("accounts-limited")
    limited.add_argument("--accounts", default="all")
    limited.add_argument("--state-dir", default="")
    limited.add_argument("--card", default="")
    approve = sub.add_parser("approve-button")
    approve.add_argument("--repo", default="")
    approve.add_argument("--pr", type=int, default=0)
    approve.add_argument("--head", default="")
    approve.add_argument("--source", type=int, default=0)
    approve.add_argument("--card", default="")
    approve.add_argument("--title", default="")
    try:
        return run(parser.parse_args(argv))
    except (OSError, urllib.error.URLError, TimeoutError, ValueError):
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
