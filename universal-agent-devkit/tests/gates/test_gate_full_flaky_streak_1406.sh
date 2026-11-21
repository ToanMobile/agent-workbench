#!/usr/bin/env bash
# Regression #1406 (Oracle 3): thẻ flaky của gate-full đêm (nhóm b / không tái hiện khi chạy lại ở đỉnh)
# không được đóng chỉ sau 1 đêm xanh; chỉ tự đóng khi đủ N=3 đêm xanh liên tiếp (sau lúc mở thẻ) HOẶC có commit/PR sửa liên kết.
# Offline; gh và git giả. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
KIT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$KIT/bin" python3 - <<'PY'
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.environ["BIN"])
import gate_full as g

calls = []
LIST = []

real_sh = g.sh

def fake_sh(cmd, cwd=None, timeout=None, env=None, shell=False):
    calls.append(cmd)
    if cmd[:3] == ["gh", "issue", "list"]:
        return 0, json.dumps(LIST)
    if cmd[:3] == ["gh", "pr", "list"]:
        return 0, "[]"
    if isinstance(cmd, list) and cmd and cmd[0] == "gh":
        return 0, ""
    return real_sh(cmd, cwd=cwd, timeout=timeout, env=env, shell=shell)

g.sh = fake_sh
g.shutil.which = lambda name: "/usr/bin/" + name
os.environ.pop("DEVKIT_GATE_FULL_CMD", None)

class Run:
    def __init__(self, started=None):
        self.info = {"passed": ["REG-FLAKY-01"], "red": [], "group_b": [], "suspect": "", "card": "", "ref": "origin/main", "sha": "a" * 40}
        self.started = started or dt.datetime(2026, 11, 19, 0, 0)
        self.log_path = "/tmp/gate-full.log"
        self.lines = []
    def log(self, m):
        self.lines.append(m)

FLAKY_BODY = (
    "## Problem\nLượt --full đêm đỏ: REG-FLAKY-01. Mọi suite đỏ đều nhóm b (thời gian thực / môi trường: REG-FLAKY-01). "
    "Commit nghi vấn: - (không tái hiện khi chạy lại ở đỉnh: flaky?).\n"
    "## Risk\n🟡 Medium — nhóm b (thời gian thực / môi trường), chưa chứng minh main đỏ\n"
)

fails = 0
def check(ok, msg):
    global fails
    print(("✔ " if ok else "✖ ") + msg)
    fails += 0 if ok else 1

def closed_nums():
    return [c[3] for c in calls if c[:3] == ["gh", "issue", "close"]]

def write_hist(pg, rows):
    nightly = os.path.join(pg, "nightly")
    os.makedirs(nightly, exist_ok=True)
    with open(os.path.join(nightly, "history.jsonl"), "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")

with tempfile.TemporaryDirectory() as tmp:
    pg = os.path.join(tmp, "pg")
    # 1) 1 đêm xanh, chưa có commit sửa liên kết -> KHÔNG đóng
    LIST[:] = [{"number": 77, "title": g.CARD_PREFIX + " 2026-11-18: REG-FLAKY-01 đỏ",
                "labels": [{"name": "bug"}], "body": FLAKY_BODY, "createdAt": "2026-11-18T00:05:00Z"}]
    write_hist(pg, [])
    calls.clear()
    g.close_proven_cards(Run(dt.datetime(2026, 11, 19, 0, 0)), "o/r", "a" * 40, pg=pg)
    check("77" not in closed_nums(), "1: thẻ flaky 1 đêm xanh không tự đóng")

    # 2) Đủ 2 đêm xanh trước đó sau createdAt + đêm nay (thứ 3 liên tiếp) -> ĐÓNG
    write_hist(pg, [
        {"at": "2026-11-18T00:10:00", "result": "red-env", "red": ["REG-FLAKY-01"], "passed": []},
        {"at": "2026-11-19T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]},
        {"at": "2026-11-20T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]},
    ])
    calls.clear()
    g.close_proven_cards(Run(dt.datetime(2026, 11, 21, 0, 0)), "o/r", "a" * 40, pg=pg)
    check("77" in closed_nums(), "2: thẻ flaky đủ 3 đêm xanh liên tiếp sau khi mở thẻ thì tự đóng")

    # 3) 2 đêm xanh TRƯỚC createdAt + 1 đêm xanh SAU createdAt -> chỉ tính 1, KHÔNG đóng
    LIST[:] = [{"number": 78, "title": g.CARD_PREFIX + " 2026-11-18: REG-FLAKY-01 đỏ",
                "labels": [{"name": "bug"}], "body": FLAKY_BODY, "createdAt": "2026-11-20T00:05:00Z"}]
    write_hist(pg, [
        {"at": "2026-11-18T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]},
        {"at": "2026-11-19T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]},
    ])
    calls.clear()
    g.close_proven_cards(Run(dt.datetime(2026, 11, 21, 0, 0)), "o/r", "a" * 40, pg=pg)
    check("78" not in closed_nums(), "3: đêm xanh trước ngày mở thẻ không cộng dồn; mới 1 đêm sau mở thẻ không đóng")

    # 4) Chuỗi bị ngắt bởi 1 đêm đỏ (green, green, red, green + hiện tại = 2) -> KHÔNG đóng
    LIST[:] = [{"number": 79, "title": g.CARD_PREFIX + " 2026-11-18: REG-FLAKY-01 đỏ",
                "labels": [{"name": "bug"}], "body": FLAKY_BODY, "createdAt": "2026-11-17T00:05:00Z"}]
    write_hist(pg, [
        {"at": "2026-11-17T01:00:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]},
        {"at": "2026-11-18T01:00:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]},
        {"at": "2026-11-19T01:00:00", "result": "red-env", "red": ["REG-FLAKY-01"], "passed": []},
        {"at": "2026-11-20T01:00:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]},
    ])
    calls.clear()
    g.close_proven_cards(Run(dt.datetime(2026, 11, 21, 0, 0)), "o/r", "a" * 40, pg=pg)
    check("79" not in closed_nums(), "4: chuỗi bị ngắt bởi đêm đỏ không đóng sớm")

    # 5) Có commit sửa liên kết (#80) -> mới 1 đêm xanh vẫn ĐÓNG ngay
    repo = os.path.join(tmp, "repo")
    subprocess.run(["git", "init", "-q", "-b", "main", repo], check=True)
    subprocess.run(["git", "-C", repo, "config", "user.email", "t@example.invalid"], check=True)
    subprocess.run(["git", "-C", repo, "config", "user.name", "t"], check=True)
    with open(os.path.join(repo, "f"), "w") as fh:
        fh.write("1\n")
    subprocess.run(["git", "-C", repo, "add", "f"], check=True)
    subprocess.run(["git", "-C", repo, "commit", "-qm", "init"], check=True)
    with open(os.path.join(repo, "f"), "w") as fh:
        fh.write("2\n")
    subprocess.run(["git", "-C", repo, "add", "f"], check=True)
    subprocess.run(["git", "-C", repo, "commit", "-qm", "fix flaky test (#80)"], check=True)
    subprocess.run(["git", "-C", repo, "update-ref", "refs/remotes/origin/main", "HEAD"], check=True)

    LIST[:] = [{"number": 80, "title": g.CARD_PREFIX + " 2026-11-18: REG-FLAKY-01 đỏ",
                "labels": [{"name": "bug"}], "body": FLAKY_BODY, "createdAt": "2026-11-18T00:05:00Z"}]
    write_hist(pg, [])
    calls.clear()
    g.close_proven_cards(Run(dt.datetime(2026, 11, 21, 0, 0)), "o/r", "a" * 40, pg=pg, repo=repo)
    check("80" in closed_nums(), "5: có commit sửa liên kết (#80) thì 1 đêm xanh đóng ngay")

    # 6) history_row ghi trường `passed` khi result in (green, red, red-env)
    r = Run(dt.datetime(2026, 11, 21, 0, 0))
    r.info["result"] = "green"
    r.info["passed"] = ["REG-FLAKY-01"]
    pg2 = os.path.join(tmp, "pg2")
    g.history_row(pg2, r)
    with open(os.path.join(pg2, "nightly", "history.jsonl"), encoding="utf-8") as fh:
        row = json.loads(fh.read().splitlines()[-1])
    check(row.get("passed") == ["REG-FLAKY-01"], "6: history_row lưu danh sách passed để tính chuỗi đêm xanh")

sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" -eq 0 ] && echo "✅ test_gate_full_flaky_streak_1406: all passed" || echo "❌ test_gate_full_flaky_streak_1406: failed"
exit "$rc"
