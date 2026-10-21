#!/usr/bin/env python3
"""super-board-notify: missing token does not deliver; approve pointer is 16 hex; limited notices debounce."""
from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NOTIFY = ROOT / ".claude" / "bin" / "super-board-notify.py"
HEAD = "a" * 40


def load():
    spec = importlib.util.spec_from_file_location("super_board_notify_under_test", NOTIFY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    fails = 0

    def check(cond, label, detail=""):
        nonlocal fails
        if cond:
            print("✔", label)
        else:
            print("✖", label, detail)
            fails += 1

    notify = load()
    calls = []

    def record(token, method, body):
        calls.append((method, body))

    def boom(token, method, body):
        raise AssertionError("deliver opened a socket")

    with tempfile.TemporaryDirectory() as raw:
        tmp = Path(raw)
        empty = tmp / "empty.env"
        empty.write_text("", encoding="utf-8")
        os.environ["SB_TELEGRAM_ENV"] = str(empty)
        os.environ.pop("SB_NOTIFY_SKIP", None)
        notify.deliver = boom
        rc = notify.main(["send", "--card", "PR #1", "--text", "merged"])
        check(rc == 0 and calls == [], "missing token exits 0 and does not deliver")

        full = tmp / "bot.env"
        full.write_text("TELEGRAM_BOT_TOKEN=test-token\nTELEGRAM_CHAT_ID=4242\n", encoding="utf-8")
        os.environ["SB_TELEGRAM_ENV"] = str(full)
        os.environ["SB_APPROVALS_DIR"] = str(tmp / "approvals")
        notify.deliver = record
        rc = notify.main(["approve-button", "--repo", "owner/repo", "--pr", "9", "--head", HEAD, "--source", "9", "--card", "PR #9"])
        files = list((tmp / "approvals").glob("*.json"))
        callback = ""
        if calls:
            buttons = calls[-1][1]["reply_markup"]["inline_keyboard"][0]
            callback = buttons[0]["callback_data"]
        check(rc == 0 and len(files) == 1, "approve-button writes one pointer file", "rc=%s files=%s" % (rc, len(files)))
        pointer = json.loads(files[0].read_text(encoding="utf-8")) if files else {}
        check(
            pointer.get("repo") == "owner/repo" and pointer.get("pr") == 9 and pointer.get("head") == HEAD and pointer.get("source") == 9,
            "pointer stores repo, pr, head and source",
            str({k: pointer.get(k) for k in ("repo", "pr", "head", "source")}),
        )
        check(callback.startswith("sb:ap:") and len(callback) == 22 and callback[6:] == files[0].stem, "callback_data is sb:ap: plus 16 hex", callback)

        # #148: tin phải nói việc gì, của project nào, không chỉ mã PR + sha.
        calls.clear()
        notify.main(["send", "--card", "PR #9", "--repo", "owner/my-app", "--title", "🐛 [fix] login: sửa lỗi đăng nhập", "--text", "đã merge " + HEAD])
        sent = calls[-1][1]["text"] if calls else ""
        check("sửa lỗi đăng nhập" in sent and "my-app" in sent, "send nêu tiêu đề và tên project", sent)
        check(HEAD not in sent, "send không in sha 40 ký tự", sent)
        calls.clear()
        notify.main(["approve-button", "--repo", "owner/my-app", "--pr", "9", "--head", HEAD, "--source", "9", "--card", "PR #9", "--title", "✨ [feat] export csv"])
        sent = calls[-1][1]["text"] if calls else ""
        check("export csv" in sent and "my-app" in sent, "approve-button nêu tiêu đề và tên project", sent)

        def down(token, method, body):
            raise OSError("network down")

        notify.deliver = down
        rc = notify.main(["send", "--card", "PR #9", "--text", "merged deadbeef"])
        check(rc == 0, "network error still exits 0")

        calls.clear()
        notify.deliver = record
        state = tmp / "state"
        os.environ["SB_NOTIFY_NOW"] = "1000"
        notify.main(["accounts-limited", "--accounts", "finos,grok", "--state-dir", str(state), "--card", "board"])
        notify.main(["accounts-limited", "--accounts", "grok,finos", "--state-dir", str(state), "--card", "board"])
        check(len(calls) == 1, "same limited set inside one hour sends once", "sent=%s" % len(calls))
        os.environ["SB_NOTIFY_NOW"] = "5000"
        notify.main(["accounts-limited", "--accounts", "finos", "--state-dir", str(state), "--card", "board"])
        check(len(calls) == 2, "a changed limited set sends again", "sent=%s" % len(calls))
        os.environ["SB_NOTIFY_NOW"] = "8601"
        notify.main(["accounts-limited", "--accounts", "finos", "--state-dir", str(state), "--card", "board"])
        check(len(calls) == 3, "the same set sends again after one hour", "sent=%s" % len(calls))

        calls.clear()
        os.environ["SB_NOTIFY_NOW"] = "20000"
        state_fail = tmp / "state-fail"

        def down_count(token, method, body):
            calls.append(("fail", method))
            raise OSError("network down")

        notify.deliver = down_count
        notify.main(["accounts-limited", "--accounts", "finos", "--state-dir", str(state_fail), "--card", "board"])
        notify.main(["accounts-limited", "--accounts", "finos", "--state-dir", str(state_fail), "--card", "board"])
        check(len(calls) == 2, "a failed limited send is tried again", "sent=%s" % len(calls))
        check(not (state_fail / "accounts-limited.json").exists(), "a failed limited send does not write the debounce file")

        calls.clear()
        notify.deliver = record
        notify.main(["runaway", "--card", "lib", "--text", "RUNAWAY daemon: no card reached Done"])
        notify.main(["runaway", "--card", "board", "--text", "RUNAWAY halt: no card reached Done"])
        notify.main(["send", "--card", "lib", "--text", "test spam"])
        os.environ["SB_LIB_ONLY"] = "1"
        try:
            notify.main(["send", "--card", "board", "--text", "lib mode spam"])
        finally:
            os.environ.pop("SB_LIB_ONLY", None)
        check(len(calls) == 0, "runaway, card=lib and SB_LIB_ONLY=1 never spam Telegram", "sent=%s" % len(calls))

    if fails:
        print("test_notify: FAIL (%s)" % fails)
        return 1
    print("test_notify: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
