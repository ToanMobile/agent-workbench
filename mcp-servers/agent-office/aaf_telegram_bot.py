#!/usr/bin/env python3
"""Standalone AAF Telegram Bot (dedicated token in ~/.agent-office/telegram.env, zero 409 conflict with cc-switcher)."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import html
import json
import os
import secrets
import signal
import sys
import time
import urllib.error
import urllib.request

import aaf_hub

CC_SWITCH_ENV = os.path.expanduser("~/.cc-switch/telegram.env")
BOT_LOCK_PATH = os.path.join(aaf_hub.AGENT_OFFICE_DIR, "aaf-telegram-bot.lock")
BOT_STATE_PATH = os.path.join(aaf_hub.AGENT_OFFICE_DIR, "telegram-state.json")
INBOX_IMAGES_DIR = os.path.join(aaf_hub.AGENT_OFFICE_DIR, "inbox-images")

PIN_DEBOUNCE_SEC = 15.0
MAX_TEXT_LEN = 3900
MAX_IMAGE_BYTES = 5 * 1024 * 1024

REPO_ALIASES = {
    "geely": "GeelyEx2",
    "ex2": "GeelyEx2",
    "or": "OfficeReader",
    "office": "OfficeReader",
    "goods": "Goods-Triple-Shelf-Match-3D",
    "shelf": "Goods-Triple-Shelf-Match-3D",
    "idle": "Idle-Plaza-3D",
    "plaza": "Idle-Plaza-3D",
    "ufo": "Humans-vs.-UFOs",
    "humans": "Humans-vs.-UFOs",
    "workbench": "agent-workbench",
    "aw": "agent-workbench",
}


def token_conflicts_with_cc_switcher(bot_token: str, *, cc_env_path: str = CC_SWITCH_ENV) -> bool:
    """Compare sha256(token) against ~/.cc-switch/telegram.env so 409 Conflict is structurally impossible."""
    if not bot_token or not os.path.isfile(cc_env_path):
        return False
    cc_tok = ""
    try:
        with open(cc_env_path, encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if line.startswith("TELEGRAM_BOT_TOKEN="):
                    cc_tok = line.partition("=")[2].strip().strip('"').strip("'")
                    break
    except OSError:
        return False
    if not cc_tok:
        return False
    h1 = hashlib.sha256(bot_token.encode("utf-8")).hexdigest()
    h2 = hashlib.sha256(cc_tok.encode("utf-8")).hexdigest()
    return h1 == h2


def parse_repo_prompt(text: str, repos: list[str]) -> tuple[str | None, str]:
    """Parse `geely: prompt` / `or: prompt` or exact repo prefix; returns (repo_or_None, cleaned_prompt)."""
    s = (text or "").strip()
    if ":" in s:
        prefix, _, rest = s.partition(":")
        key = prefix.strip().lower()
        if rest.strip():
            if key in REPO_ALIASES and REPO_ALIASES[key] in repos:
                return REPO_ALIASES[key], rest.strip()
            for r in repos:
                if r.lower() == key or r.lower().startswith(key):
                    return r, rest.strip()
    return None, s


def is_authorized_update(update: dict, *, owner_id: int, allowed_chats: set[int]) -> bool:
    """Require BOTH from.id == owner_id AND chat.id in allowed_chats for message & callback_query."""
    if "message" in update and isinstance(update["message"], dict):
        m = update["message"]
        uid = (m.get("from") or {}).get("id")
        cid = (m.get("chat") or {}).get("id")
        return uid == owner_id and cid in allowed_chats
    if "callback_query" in update and isinstance(update["callback_query"], dict):
        cb = update["callback_query"]
        uid = (cb.get("from") or {}).get("id")
        cid = ((cb.get("message") or {}).get("chat") or {}).get("id")
        return uid == owner_id and cid in allowed_chats
    return False


def text_hash(text: str) -> str:
    return hashlib.sha256((text or "").encode("utf-8")).hexdigest()


def should_edit_pinned(text: str, *, last_hash: str, last_edit_ts: float, now_ts: float) -> bool:
    if (now_ts - last_edit_ts) < PIN_DEBOUNCE_SEC:
        return False
    return text_hash(text) != last_hash


def format_safe_html(text: str, max_len: int = MAX_TEXT_LEN) -> str:
    return html.escape(aaf_hub.redact_aaf(text or ""))[:max_len]


def load_bot_state(path: str = BOT_STATE_PATH) -> dict:
    default = {"last_update_id": 0, "pinned_message_id": 0, "last_pinned_hash": "", "sent_alerts": {}}
    if not os.path.isfile(path):
        return default
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            default.update(data)
    except (OSError, ValueError) as exc:
        aaf_hub.log_warn("bot_state_load", exc)
    return default


def save_bot_state(state: dict, path: str = BOT_STATE_PATH) -> None:
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = f"{path}.{os.getpid()}.{secrets.token_hex(4)}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError as exc:
            aaf_hub.log_warn("bot_tmp_cleanup", exc)
        raise


def prune_inbox_images(inbox_dir: str = INBOX_IMAGES_DIR, max_age_sec: int = 86400) -> None:
    if not os.path.isdir(inbox_dir):
        return
    cutoff = time.time() - max_age_sec
    for fn in os.listdir(inbox_dir):
        fp = os.path.join(inbox_dir, fn)
        try:
            if os.path.isfile(fp) and os.stat(fp).st_mtime < cutoff:
                os.unlink(fp)
        except OSError as exc:
            aaf_hub.log_warn("inbox_prune", exc)


class TelegramClient:
    """Minimal stdlib Telegram Bot API client (never logs raw URL with token; honors 429 Retry-After)."""

    def __init__(self, token: str):
        self._token = token
        self._retry_until = 0.0

    def call(self, method: str, payload: dict | None = None, *, timeout: int = 35) -> tuple[bool, dict, int]:
        wait = self._retry_until - time.monotonic()
        if wait > 0:
            time.sleep(min(wait, 30.0))
        url = f"https://api.telegram.org/bot{self._token}/{method}"
        body = json.dumps(payload or {}, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8", errors="replace") or "{}")
                return bool(data.get("ok")), data, resp.status
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
            try:
                data = json.loads(raw or "{}")
            except ValueError:
                data = {"ok": False, "description": raw[:200]}
            if exc.code == 429:
                ra = int(((data.get("parameters") or {}).get("retry_after")) or 10)
                self._retry_until = time.monotonic() + min(ra, 120)
            return False, data, exc.code
        except Exception as exc:  # noqa: BLE001 — network outage must never leak token URL
            return False, {"ok": False, "description": aaf_hub.redact_aaf(str(exc))}, 0

    def download_file_safe(self, file_id: str, inbox_dir: str = INBOX_IMAGES_DIR) -> str | None:
        ok, data, _ = self.call("getFile", {"file_id": file_id}, timeout=15)
        if not ok:
            return None
        fpath = str(((data.get("result") or {}).get("file_path")) or "")
        fsize = int(((data.get("result") or {}).get("file_size")) or 0)
        if not fpath or fsize > MAX_IMAGE_BYTES:
            return None
        os.makedirs(inbox_dir, mode=0o700, exist_ok=True)
        os.chmod(inbox_dir, 0o700)
        url = f"https://api.telegram.org/file/bot{self._token}/{fpath}"
        try:
            with urllib.request.urlopen(url, timeout=20) as resp:
                blob = resp.read(MAX_IMAGE_BYTES + 1)
            if len(blob) > MAX_IMAGE_BYTES:
                return None
            out_path = os.path.join(inbox_dir, secrets.token_hex(12) + ".jpg")
            fd = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(blob)
            return out_path
        except Exception:  # noqa: BLE001
            return None


def _render_status_html(studio: dict) -> str:
    s = studio.get("summary") or {}
    lines = [
        f"<b>AAF Studio · Mac Online</b>",
        f"Slots: <code>{s.get('slotsHeld', 0)}/{s.get('slotsMax', 3)}</code> · Active: <code>{s.get('activeRuns', 0)}</code> · Tự chạy: <b>{'BẬT' if s.get('autoRunEnabled') else 'TẮT'}</b>",
    ]
    att = studio.get("attention") or []
    if att:
        lines.append(f"\n<b>Cần xử lý ({len(att)}):</b>")
        for t in att[:6]:
            lines.append(f"• <b>{format_safe_html(t.get('repo', ''))}</b> <code>{format_safe_html(t.get('id', ''))}</code> [{format_safe_html(t.get('state', ''))}]: {format_safe_html(t.get('title', ''), 90)}")
    running = [t for t in (studio.get("tasks") or []) if t.get("state") == "running"]
    if running:
        lines.append(f"\n<b>Đang chạy ({len(running)}):</b>")
        for t in running[:6]:
            lines.append(f"• <b>{format_safe_html(t.get('repo', ''))}</b> <code>{format_safe_html(t.get('id', ''))}</code>: {format_safe_html(t.get('title', ''), 80)}")
    return "\n".join(lines)[:MAX_TEXT_LEN]


def run_bot(cfg_path: str) -> int:
    token, owner_id, allowed_list, err = aaf_hub.load_telegram_env()
    if err or not token or not owner_id:
        print(f"[aaf-bot] Chưa cấu hình ~/.agent-office/telegram.env ({err}). Thoát an toàn.", flush=True)
        return 1
    if token_conflicts_with_cc_switcher(token):
        print("[aaf-bot] LỖI NGHIÊM TRỌNG: Bot token trùng với ~/.cc-switch/telegram.env (sẽ gây 409 Conflict). Hãy tạo Bot riêng cho AAF!", flush=True)
        return 2

    os.makedirs(os.path.dirname(BOT_LOCK_PATH), mode=0o700, exist_ok=True)
    lock_fd = os.open(BOT_LOCK_PATH, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(lock_fd)
        print("[aaf-bot] Đã có 1 tiến trình aaf_telegram_bot đang chạy.", flush=True)
        return 0

    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)
    repo_paths = aaf_hub._build_repo_paths(cfg)
    repos = list(repo_paths.keys())
    allowed_chats = set(allowed_list)
    client = TelegramClient(token)
    bstate = load_bot_state()
    pending_prompts: dict[str, str] = {}
    last_pin_ts = 0.0
    conflict_backoff = 30.0
    stopping = False

    def _on_sig(signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, _on_sig)
    signal.signal(signal.SIGINT, _on_sig)

    try:
        while not stopping:
            prune_inbox_images()
            ok, res, code = client.call(
                "getUpdates",
                {"offset": int(bstate.get("last_update_id", 0)) + 1, "timeout": 20, "allowed_updates": ["message", "callback_query"]},
                timeout=30,
            )
            if code == 409:
                print(f"[aaf-bot] 409 Conflict — tạm nghỉ {int(conflict_backoff)}s", flush=True)
                time.sleep(conflict_backoff)
                conflict_backoff = min(120.0, conflict_backoff * 1.5)
                continue
            conflict_backoff = 30.0

            if ok:
                for upd in res.get("result") or []:
                    uid = int(upd.get("update_id") or 0)
                    if uid > int(bstate.get("last_update_id", 0)):
                        bstate["last_update_id"] = uid
                    if not is_authorized_update(upd, owner_id=owner_id, allowed_chats=allowed_chats):
                        continue

                    if "callback_query" in upd:
                        cb = upd["callback_query"]
                        client.call("answerCallbackQuery", {"callback_query_id": cb["id"]})
                        cdata = str(cb.get("data") or "")
                        chat_id = ((cb.get("message") or {}).get("chat") or {}).get("id")
                        if cdata.startswith("pick:"):
                            _, pkey, rname = cdata.split(":", 2)
                            prompt = pending_prompts.pop(pkey, "")
                            if prompt and rname in repo_paths:
                                sc, out = aaf_hub.execute_aaf_action(
                                    {"action": "add", "repo": rname, "title": prompt[:96], "spec": prompt, "accept": "Test ĐỎ→XANH và aaf gate CLEAR"},
                                    repo_paths=repo_paths,
                                )
                                msg = f"Đã giao vào <b>{format_safe_html(rname)}</b>" if sc == 200 else f"Lỗi: {format_safe_html(str(out.get('error', '')))}"
                                client.call("sendMessage", {"chat_id": chat_id, "text": msg, "parse_mode": "HTML"})
                        continue

                    msg = upd.get("message") or {}
                    chat_id = (msg.get("chat") or {}).get("id")
                    text = (msg.get("text") or msg.get("caption") or "").strip()
                    img_note = ""
                    if msg.get("photo"):
                        fid = msg["photo"][-1].get("file_id")
                        if fid:
                            saved = client.download_file_safe(fid)
                            if saved:
                                img_note = f"\n[Ảnh đính kèm: {saved}]"
                    if not text:
                        continue

                    if text == "/status":
                        st = aaf_hub.read_studio_state(repo_paths=repo_paths, include_manual=False)
                        client.call("sendMessage", {"chat_id": chat_id, "text": _render_status_html(st), "parse_mode": "HTML"})
                    elif text.startswith("/autorun"):
                        en = "on" in text.lower() or "bat" in text.lower() or "bật" in text.lower()
                        aaf_hub.write_supervisor_state(en)
                        client.call("sendMessage", {"chat_id": chat_id, "text": f"Supervisor tự chạy: <b>{'BẬT' if en else 'TẮT'}</b>", "parse_mode": "HTML"})
                    elif text.startswith("/ask "):
                        rname, q = parse_repo_prompt(text[5:].strip(), repos)
                        if not rname:
                            parts = text[5:].strip().split(None, 1)
                            rname = parts[0] if parts and parts[0] in repo_paths else (repos[0] if repos else "")
                            q = parts[1] if len(parts) > 1 else ""
                        sc, ans = aaf_hub.run_read_only_ask(rname, q + img_note, repo_paths=repo_paths)
                        reply = format_safe_html(ans.get("answer") if sc == 200 else str(ans.get("error", "")))
                        client.call("sendMessage", {"chat_id": chat_id, "text": f"<b>/ask {format_safe_html(rname)}</b>\n{reply}", "parse_mode": "HTML"})
                    else:
                        clean = text[5:].strip() if text.startswith("/add ") else text
                        rname, body = parse_repo_prompt(clean, repos)
                        if rname:
                            sc, out = aaf_hub.execute_aaf_action(
                                {"action": "add", "repo": rname, "title": body[:96], "spec": body + img_note, "accept": "Test ĐỎ→XANH và aaf gate CLEAR"},
                                repo_paths=repo_paths,
                            )
                            reply = f"Đã tạo task trong <b>{format_safe_html(rname)}</b>" if sc == 200 else f"Lỗi: {format_safe_html(str(out.get('error', '')))}"
                            client.call("sendMessage", {"chat_id": chat_id, "text": reply, "parse_mode": "HTML"})
                        else:
                            pkey = secrets.token_hex(4)
                            pending_prompts[pkey] = body + img_note
                            kb = [[{"text": r, "callback_data": f"pick:{pkey}:{r}"} for r in repos[i : i + 2]] for i in range(0, len(repos), 2)]
                            client.call(
                                "sendMessage",
                                {
                                    "chat_id": chat_id,
                                    "text": "Chọn repo để giao prompt này:",
                                    "reply_markup": {"inline_keyboard": kb},
                                },
                            )
                save_bot_state(bstate)

            # Live pinned status update (debounced >= 15s + hash dedup) + proactive alerts
            studio = aaf_hub.read_studio_state(repo_paths=repo_paths, include_manual=False)
            pin_text = _render_status_html(studio)
            now_t = time.monotonic()
            if should_edit_pinned(pin_text, last_hash=bstate.get("last_pinned_hash", ""), last_edit_ts=last_pin_ts, now_ts=now_t):
                pin_id = int(bstate.get("pinned_message_id") or 0)
                if pin_id:
                    e_ok, e_res, e_code = client.call(
                        "editMessageText",
                        {"chat_id": owner_id, "message_id": pin_id, "text": pin_text, "parse_mode": "HTML"},
                    )
                    desc = str(e_res.get("description") or "").lower()
                    if e_ok or "not modified" in desc:
                        bstate["last_pinned_hash"] = text_hash(pin_text)
                        last_pin_ts = now_t
                    elif e_code == 400 and "not found" in desc:
                        bstate["pinned_message_id"] = 0
                if not bstate.get("pinned_message_id"):
                    s_ok, s_res, _ = client.call("sendMessage", {"chat_id": owner_id, "text": pin_text, "parse_mode": "HTML"})
                    if s_ok:
                        mid = int(((s_res.get("result") or {}).get("message_id")) or 0)
                        if mid:
                            bstate["pinned_message_id"] = mid
                            bstate["last_pinned_hash"] = text_hash(pin_text)
                            last_pin_ts = now_t
                            client.call("pinChatMessage", {"chat_id": owner_id, "message_id": mid, "disable_notification": True})
                save_bot_state(bstate)
    finally:
        save_bot_state(bstate)
        os.close(lock_fd)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="AAF Standalone Telegram Bot")
    ap.add_argument("--config", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json"))
    args = ap.parse_args()
    return run_bot(args.config)


if __name__ == "__main__":
    sys.exit(main())
