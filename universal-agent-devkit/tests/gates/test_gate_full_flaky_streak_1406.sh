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
PR_LIST = []      # (#1406 R3) PR merged mà gh giả trả về; rỗng = như cũ
PR_NEEDS = None   # None: mọi truy vấn gh pr list thấy PR_LIST; hàm(cmd) -> bool: chỉ truy vấn khớp mới thấy
ISSUE_LIST_RC = 0
CLOSE_RC = 0

real_sh = g.sh

def fake_sh(cmd, cwd=None, timeout=None, env=None, shell=False):
    calls.append(cmd)
    if cmd[:3] == ["gh", "issue", "list"]:
        return ISSUE_LIST_RC, json.dumps(LIST) if ISSUE_LIST_RC == 0 else "boom"
    if cmd[:3] == ["gh", "pr", "list"]:
        return 0, json.dumps(PR_LIST if (PR_NEEDS is None or PR_NEEDS(cmd)) else [])
    if cmd[:3] == ["gh", "issue", "close"]:
        return CLOSE_RC, ""
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

    # 5) Có commit sửa liên kết (#80 ở subject, #81 ở commit body) -> mới 1 đêm xanh vẫn ĐÓNG ngay
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
    with open(os.path.join(repo, "f"), "w") as fh:
        fh.write("3\n")
    subprocess.run(["git", "-C", repo, "add", "f"], check=True)
    subprocess.run(["git", "-C", repo, "commit", "-qm", "fix suite (#999)", "-m", "Closes #81"], check=True)
    subprocess.run(["git", "-C", repo, "update-ref", "refs/remotes/origin/main", "HEAD"], check=True)

    LIST[:] = [{"number": 80, "title": g.CARD_PREFIX + " 2026-11-18: REG-FLAKY-01 đỏ",
                "labels": [{"name": "bug"}], "body": FLAKY_BODY, "createdAt": "2026-11-18T00:05:00Z"},
               {"number": 81, "title": g.CARD_PREFIX + " 2026-11-18: REG-FLAKY-01 đỏ",
                "labels": [{"name": "bug"}], "body": FLAKY_BODY, "createdAt": "2026-11-18T00:05:00Z"}]
    write_hist(pg, [])
    calls.clear()
    g.close_proven_cards(Run(dt.datetime(2026, 11, 21, 0, 0)), "o/r", "a" * 40, pg=pg, repo=repo)
    check("80" in closed_nums() and "81" in closed_nums(),
          "5: có commit sửa liên kết (#80 ở subject, #81 ở body) thì 1 đêm xanh đóng ngay")

    # 5b) Dòng JSON hỏng trong history.jsonl không làm mất lịch sử hợp lệ; dòng thiếu `at` dừng đếm tại cut
    nightly_dir = os.path.join(pg, "nightly")
    os.makedirs(nightly_dir, exist_ok=True)
    with open(os.path.join(nightly_dir, "history.jsonl"), "w", encoding="utf-8") as fh:
        fh.write('{"at": "2026-11-18T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]}\n')
        fh.write('{"at": "", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]}\n')
        fh.write('{corrupt_json\n')
        fh.write('{"at": "2026-11-19T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]}\n')
        fh.write('{"at": "2026-11-20T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]}\n')
    check(g._consecutive_pass_streak(pg, "REG-FLAKY-01", "2026-11-17T00:00:00Z") == 3,
          "5b: dòng JSON hỏng bỏ qua, dòng thiếu `at` dừng chuỗi an toàn (streak=3)")

    # 5c) Thẻ P1 thường có chữ 'flaky' trong subject commit nghi vấn không bị nhận nhầm thành thẻ flaky
    normal_p1 = {
        "number": 82,
        "title": g.CARD_PREFIX + " 2026-11-18: REG-REAL-01 đỏ",
        "labels": [{"name": "bug"}],
        "body": "## Problem\nCommit nghi vấn: abc fix flaky test.\n## Risk\n🔴 High — main đỏ\n",
    }
    check(not g._is_flaky_card(normal_p1),
          "5c: thẻ P1 thường nhắc chữ 'flaky' trong subject commit không bị nhận nhầm là flaky")

    # 6) history_row ghi trường `passed` khi result in (green, red, red-env)
    r = Run(dt.datetime(2026, 11, 21, 0, 0))
    r.info["result"] = "green"
    r.info["passed"] = ["REG-FLAKY-01"]
    pg2 = os.path.join(tmp, "pg2")
    g.history_row(pg2, r)
    with open(os.path.join(pg2, "nightly", "history.jsonl"), encoding="utf-8") as fh:
        row = json.loads(fh.read().splitlines()[-1])
    check(row.get("passed") == ["REG-FLAKY-01"], "6: history_row lưu danh sách passed để tính chuỗi đêm xanh")

    # 7) (#1406 R1) close_proven_cards báo cho cmd_run biết còn thẻ PASS chưa đóng được ⇒ cmd_run không ghi last_full_green_sha
    #    (đầu-cuối ở test_gate_full_flaky_streak_skip_1406.sh)
    LIST[:] = [{"number": 90, "title": g.CARD_PREFIX + " 2026-11-18: REG-FLAKY-01 đỏ",
                "labels": [{"name": "bug"}], "body": FLAKY_BODY, "createdAt": "2026-11-18T00:05:00Z"}]
    write_hist(pg, [])
    calls.clear()
    held = g.close_proven_cards(Run(dt.datetime(2026, 11, 19, 0, 0)), "o/r", "a" * 40, pg=pg)
    check(held is True and "90" not in closed_nums(), "7a: thẻ flaky chuỗi 1/3 giữ mở ⇒ trả True (còn thẻ chờ lượt sau)")
    write_hist(pg, [{"at": "2026-11-19T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]}])
    calls.clear()
    held = g.close_proven_cards(Run(dt.datetime(2026, 11, 20, 0, 0)), "o/r", "a" * 40, pg=pg)
    check(held is True and "90" not in closed_nums(), "7b: thẻ flaky chuỗi 2/3 giữ mở ⇒ trả True")
    write_hist(pg, [{"at": "2026-11-19T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]},
                    {"at": "2026-11-20T00:10:00", "result": "green", "red": [], "passed": ["REG-FLAKY-01"]}])
    calls.clear()
    held = g.close_proven_cards(Run(dt.datetime(2026, 11, 21, 0, 0)), "o/r", "a" * 40, pg=pg)
    check(held is False and "90" in closed_nums(), "7c: chuỗi 3/3 đóng thẻ ⇒ trả False (ghi mốc xanh như cũ)")
    LIST[:] = []
    check(g.close_proven_cards(Run(), "o/r", "a" * 40, pg=pg) is False, "7d: không có thẻ mở ⇒ trả False")
    LIST[:] = [{"number": 91, "title": g.CARD_PREFIX + " 2026-11-18: REG-OTHER-01 đỏ",
                "labels": [{"name": "bug"}], "body": FLAKY_BODY, "createdAt": "2026-11-18T00:05:00Z"}]
    check(g.close_proven_cards(Run(), "o/r", "a" * 40, pg=pg) is False,
          "7e: thẻ flaky của suite KHÔNG PASS ở lượt này không tính là giữ mở ⇒ trả False")
    # thẻ thường (không flaky) đóng lỗi / danh sách thẻ không đọc được: log hứa "lượt sau thử lại" ⇒ cũng phải trả True
    LIST[:] = [{"number": 92, "title": g.CARD_PREFIX + " 2026-11-18: REG-FLAKY-01 đỏ", "labels": [{"name": "bug"}],
                "body": "## Risk\n🔴 High — main đỏ\n", "createdAt": "2026-11-18T00:05:00Z"}]
    CLOSE_RC = 1
    check(g.close_proven_cards(Run(), "o/r", "a" * 40, pg=pg) is True, "7f: gh issue close lỗi ⇒ trả True (lượt sau thử lại)")
    CLOSE_RC = 0
    ISSUE_LIST_RC = 1
    check(g.close_proven_cards(Run(), "o/r", "a" * 40, pg=pg) is True, "7g: gh issue list lỗi ⇒ trả True (lượt sau thử lại)")
    ISSUE_LIST_RC = 0
    os.environ["DEVKIT_GATE_FULL_CMD"] = "true"
    check(g.close_proven_cards(Run(), "o/r", "a" * 40, pg=pg) is False, "7h: lệnh gate thay thế (không xét thẻ) ⇒ trả False")
    os.environ.pop("DEVKIT_GATE_FULL_CMD", None)

    # 8) (#1406 R3) PR merged trên nhánh issue-<N>-… KHÔNG nhắc `#<N>` ở tiêu đề/nội dung: truy vấn `--search "#<N>"` không thấy,
    #    vẫn phải nhận là commit/PR sửa liên kết
    def no_hash_search(n):
        def needs(cmd):
            q = cmd[cmd.index("--search") + 1] if "--search" in cmd else ""
            return ("#%d" % n) not in q
        return needs
    item = {"number": 93, "createdAt": "2026-11-18T00:05:00Z"}
    PR_NEEDS = no_hash_search(93)
    PR_LIST[:] = [{"number": 500, "headRefName": "issue-93-fix-flaky", "mergedAt": "2026-11-19T03:00:00Z", "closingIssuesReferences": []}]
    check(g._has_linked_fix("", "o/r", 93, item["createdAt"], item, "origin/main") is True,
          "8a: PR merged trên nhánh issue-93-… không nhắc #93 vẫn là PR sửa liên kết")
    PR_LIST[:] = [{"number": 501, "headRefName": "claude/issue-93", "mergedAt": "2026-11-19T03:00:00Z", "closingIssuesReferences": []}]
    check(g._has_linked_fix("", "o/r", 93, item["createdAt"], item, "origin/main") is True,
          "8b: nhánh có tiền tố thư mục và không có hậu tố (claude/issue-93) cũng khớp, cùng quy ước CARD_FROM_BRANCH")
    PR_LIST[:] = [{"number": 502, "headRefName": "issue-931-other", "mergedAt": "2026-11-19T03:00:00Z", "closingIssuesReferences": []},
                  {"number": 503, "headRefName": "reissue-93-x", "mergedAt": "2026-11-19T03:00:00Z", "closingIssuesReferences": []}]
    check(g._has_linked_fix("", "o/r", 93, item["createdAt"], item, "origin/main") is False,
          "8c: nhánh của thẻ khác (issue-931-…, reissue-93-…) không bị nhận nhầm")
    PR_LIST[:] = [{"number": 504, "headRefName": "issue-93-old", "mergedAt": "2026-11-17T03:00:00Z", "closingIssuesReferences": []}]
    check(g._has_linked_fix("", "o/r", 93, item["createdAt"], item, "origin/main") is False,
          "8d: PR nhánh issue-93-… merge TRƯỚC lúc mở thẻ không tính")
    PR_LIST[:] = [{"number": 505, "headRefName": "fix-x", "mergedAt": "2026-11-19T03:00:00Z", "closingIssuesReferences": [{"number": 93}]}]
    check(g._has_linked_fix("", "o/r", 93, item["createdAt"], item, "origin/main") is True,
          "8e: PR merged gần đây có closingIssuesReferences #93 (không nhắc #93 trong search) vẫn khớp")
    # đầu-cuối: thẻ flaky 1 đêm xanh + PR nhánh issue-94-… ⇒ đóng ngay
    PR_NEEDS = no_hash_search(94)
    PR_LIST[:] = [{"number": 506, "headRefName": "issue-94-fix", "mergedAt": "2026-11-19T03:00:00Z", "closingIssuesReferences": []}]
    LIST[:] = [{"number": 94, "title": g.CARD_PREFIX + " 2026-11-18: REG-FLAKY-01 đỏ",
                "labels": [{"name": "bug"}], "body": FLAKY_BODY, "createdAt": "2026-11-18T00:05:00Z"}]
    write_hist(pg, [])
    calls.clear()
    held = g.close_proven_cards(Run(dt.datetime(2026, 11, 20, 0, 0)), "o/r", "a" * 40, pg=pg)
    check("94" in closed_nums() and held is False, "8f: thẻ flaky 1 đêm xanh có PR nhánh issue-94-… (không nhắc #94) thì đóng ngay")
    PR_NEEDS = None
    PR_LIST[:] = []

sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" -eq 0 ] && echo "✅ test_gate_full_flaky_streak_1406: all passed" || echo "❌ test_gate_full_flaky_streak_1406: failed"
exit "$rc"
