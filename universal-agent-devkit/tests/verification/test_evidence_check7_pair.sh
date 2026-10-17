#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh check 7 (an outcome claim needs a paired RED→GREEN run) judged two honest sessions wrongly
# (issue #4, agent-workbench):
#   (1) check 2 accepts the DevKit gate's PASS ("gate-green") as a green run, check 7 asked for a literal "green" and refused it;
#   (2) an Edit of a TEST file after the RED→GREEN pair moved the "last source edit" marker past the green run (the fix itself did not
#       change), so the pair no longer counted.
# Still blocked: no RED at all, a gate PASS from before the fix, a SOURCE edit after the green run.
# Vòng 2 (review PR #33): (2) đúng cả với bản sửa làm trong thư mục tạm (bản stage); check 2 giữ marker riêng nên claim "test pass"
# sau lần sửa file test chưa chạy lại vẫn bị chặn; fix chỉ sửa file test vẫn được xét theo lần sửa đó như trước.
#   EG_KIT=<devkit dir>   test another copy of the kit (the unpatched one: RED).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${EG_KIT:-$DEVKIT_DIR}"
python3 -I - "$KIT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile

KIT = sys.argv[1]
GATE = os.path.join(KIT, "hooks", "test_evidence_gate.sh")
TMP = tempfile.mkdtemp()
CLEAN = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "CLAUDE_"))}
fails = 0
n = 0
# bước -> (thư mục: project hay thư mục tạm ngoài project, file, old, new)
EDITS = {"edit": ("p", "src/app.py", "return 1", "return 2"), "edit_test": ("p", "tests/test_foo.py", "assert 1", "assert 2"),
         "scratch_edit": ("s", "src/app.py", "return 1", "return 2"),
         "scratch_edit_test": ("s", "tests/test_foo.py", "assert 1", "assert 2")}


def project():
    global n
    n += 1
    p = os.path.join(TMP, "p%d" % n)
    s = os.path.join(TMP, "s%d" % n)      # bản stage trong thư mục tạm, nằm ngoài project nên gate coi là scratch
    for d in ("src", "tests", os.path.join(".claude", "audit-gate")):
        os.makedirs(os.path.join(p, d))
    for root in (p, s):
        os.makedirs(os.path.join(root, "src"), exist_ok=True)
        os.makedirs(os.path.join(root, "tests"), exist_ok=True)
        open(os.path.join(root, "tests", "test_foo.py"), "w").write("def test_a():\n    assert 1\n")
        open(os.path.join(root, "src", "app.py"), "w").write("def f():\n    return 1\n")
    return p, s


def transcript(p, s, steps):
    lines = []
    for i, st in enumerate(steps):
        uid = "tu%d" % i
        if st[0] == "bash":
            use = {"type": "tool_use", "id": uid, "name": "Bash", "input": {"command": st[1]}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": st[2], "is_error": bool(st[3]) if len(st) > 3 else False}
        else:
            where, path, old, new = EDITS[st[0]]
            use = {"type": "tool_use", "id": uid, "name": "Edit",
                   "input": {"file_path": os.path.join(p if where == "p" else s, path), "old_string": old, "new_string": new}}
            res = {"type": "tool_result", "tool_use_id": uid, "content": "ok"}
        lines.append(json.dumps({"message": {"content": [use]}}))
        lines.append(json.dumps({"message": {"content": [res]}}))
    path = os.path.join(p, "tr.jsonl")
    open(path, "w").write("\n".join(lines) + "\n")
    return path


def case(name, steps, want, sub=None, msg="Đã fix lỗi X."):
    global fails
    p, s = project()
    payload = json.dumps({"session_id": "c7p-" + os.path.basename(p), "transcript_path": transcript(p, s, steps), "last_assistant_message": msg})
    env = dict(CLEAN, CLAUDE_PROJECT_DIR=p, LESSON_REMINDER="0")
    r = subprocess.run(["bash", GATE], input=payload, capture_output=True, text=True, env=env)
    ok = r.returncode == want and (sub is None or sub in r.stderr)
    print(("✔ " if ok else "✖ ") + name + ("" if ok else "  — want exit %d%s, got %d: %s" % (
        want, " + '%s'" % sub if sub else "", r.returncode, " ".join(l for l in r.stderr.splitlines() if l.strip())[:200])))
    if not ok:
        fails += 1


GATE_CMD = 'python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief'
G_PASS = "  KẾT LUẬN CỔNG POST-FIX AUDIT: PASS — ĐỦ ĐIỀU KIỆN NGHIỆM THU & BÀN GIAO\n  • Test hồi quy đạt: 6/6\nGATE EXIT=0"
RED = ["bash", "pytest tests/test_foo.py", "FAILED tests/test_foo.py::test_a - assert 2\n1 failed", True]
GREEN = ["bash", "pytest tests/test_foo.py", "1 passed"]
E, TE, SE, STE = ["edit"], ["edit_test"], ["scratch_edit"], ["scratch_edit_test"]
PASS_CLAIM = "Tất cả 1/1 test pass."

# control: the plain pair is accepted today
case("control: RED, fix, GREEN", [RED, E, GREEN], 0)
# (1) the DevKit gate's PASS is the green half of the pair
case("RED runner, fix, then the gate PASS: the pair holds", [RED, E, ["bash", GATE_CMD, G_PASS]], 0)
# (2) editing a test after the pair does not void it
case("RED, fix, GREEN, then a test file is edited: the pair holds", [RED, E, GREEN, TE], 0)
case("RED, fix, gate PASS, then a test file is edited: the pair holds", [RED, E, ["bash", GATE_CMD, G_PASS], TE], 0)
case("temp dir: RED, fix, GREEN, then a test file is edited: the pair holds", [RED, SE, GREEN, STE], 0)
# AC2 nói "sửa hoặc commit": lệnh git commit file test vừa sửa cũng không làm mất cặp (QA vòng 2)
COMMIT = ["bash", "git commit -m '🧪 [test] ghim test_foo' -- tests/test_foo.py",
          "[issue-4 1a2b3c4] 🧪 [test] ghim test_foo\n 1 file changed, 1 insertion(+)"]
case("RED, fix, GREEN, then a test file is edited and committed: the pair holds", [RED, E, GREEN, TE, COMMIT], 0)
# fix chỉ sửa file test (test flaky, conftest) được xét theo lần sửa đó, như trên main
case("RED, only a test file is edited, GREEN: the pair holds", [RED, TE, GREEN], 0)
# một file .py probe trong scratchpad không chiếm marker khi project có lần sửa (project xét trước thư mục tạm)
case("scratch probe, RED, only a test file is edited, GREEN: the pair holds", [SE, RED, TE, GREEN], 0)
case("RED, only a test file is edited, GREEN, then a scratch probe: the pair holds", [RED, TE, GREEN, SE], 0)

# still blocked
case("no RED at all: blocked", [E, GREEN], 2, "CHECK 7")
case("RED, fix, GREEN, then a SOURCE edit: blocked", [RED, E, GREEN, E], 2, "CHECK 7")
case("temp dir: RED, fix, GREEN, then a SOURCE edit: blocked", [RED, SE, GREEN, SE], 2, "CHECK 7")
case("the gate PASS ran BEFORE the fix: blocked", [RED, ["bash", GATE_CMD, G_PASS], E], 2, "CHECK 7")
# ĐỎ chỉ có sau bản sửa (sửa test cho đỏ rồi trả lại, hay chỉnh test tới khi xanh) không phải bằng chứng; main từng cho qua
case("fix, test broken for a RED, test restored, GREEN: blocked", [E, TE, RED, TE, GREEN], 2, "CHECK 7")
case("fix, then RED, then only a test edit, GREEN: blocked", [E, RED, TE, GREEN], 2, "CHECK 7")
# bản sửa ở thư mục tạm rồi sửa file test trong project: không phân biệt được với file probe, nên chặn như trên main
case("scratch edit, GREEN, then only a PROJECT test edit: blocked", [RED, SE, GREEN, TE], 2, "CHECK 7")
# check 2 giữ marker riêng: claim "test pass" cũng cần một lần chạy sau lần sửa file test cuối
case("check 2: fix, GREEN, test edit, then 'test pass' with no new run: blocked", [E, GREEN, TE], 2, "TEST-EVIDENCE", msg=PASS_CLAIM)
case("check 2: RED, fix, GREEN, test edit, then 'test pass' with no new run: blocked", [RED, E, GREEN, TE], 2, "TEST-EVIDENCE",
     msg=PASS_CLAIM)
case("check 2: test edit, RED, fix, GREEN, then 'test pass': allowed", [TE, RED, E, GREEN], 0, msg=PASS_CLAIM)

shutil.rmtree(TMP, ignore_errors=True)
print("")
print("test_evidence_check7_pair: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY
