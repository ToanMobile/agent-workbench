"""Workload theo agent: gom `ps` thành nhóm (Claude, Antigravity, Gate/test...) và tải CPU/RAM từng nhóm."""
import os, sys, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402

PS = """\
  PID  PCPU   RSS     ELAPSED COMMAND
  100  40.0  204800  00:10:00 /Users/a/Library/Application Support/Claude/claude-code/2.1/claude.app/Contents/MacOS/claude --output-format stream-json
  101  10.5  102400  00:05:00 claude -p task
  102  30.0   51200  01:00:00 /Applications/Antigravity.app/Contents/MacOS/Electron
  103  25.0   10240  00:00:05 /usr/bin/python3 /repo/universal-agent-devkit/bin/post-fix-gate.py --run-tests --full
  104  12.0    2048  01:10:41 /bin/bash /tmp/claude-501/ab/run.sh
  105  90.0   99999  02:00:00 /Applications/Brave Browser.app/Contents/MacOS/Brave Browser
  106   1.0    1024  00:00:01 /usr/bin/grep -rn claude foo
"""


# Fake credentials (prove the redaction), joined at run time: no literal in the source looks like a real key to a secret scanner.
FAKE_KEY = "sk" + "-" + "test" + "0" * 4 + "fake"
FAKE_TOKEN = "tok" + "en=" + "fixture" + "0" * 6
FAKE_TOKEN2 = "tok" + "en=" + "fixture" + "1" * 6


class WorkloadTest(unittest.TestCase):
    def test_groups_and_totals(self):
        w = server.workload_from_ps(PS)
        g = {x["id"]: x for x in w["groups"]}
        self.assertEqual(g["claude"]["count"], 2)
        self.assertAlmostEqual(g["claude"]["cpu"], 50.5)
        self.assertEqual(g["claude"]["rssMb"], 300)
        self.assertEqual(g["antigravity"]["count"], 1)
        self.assertEqual(g["gate"]["count"], 2)  # post-fix-gate + run.sh benchmark
        self.assertEqual(sorted(g), ["antigravity", "claude", "gate"])  # grep nhắc tên claude, Brave không phải agent
        self.assertAlmostEqual(w["totalCpu"], 208.5)  # tổng CPU cả máy (mọi tiến trình), không chỉ agent
        self.assertAlmostEqual(w["otherCpu"], 91.0)   # Brave 90 + grep 1: ngoài agent
        self.assertEqual(w["others"][0]["label"], "Brave Browser")
        self.assertEqual(w["others"][0]["cpu"], 90.0)
        self.assertEqual(w["top"][0]["pid"], 100)  # xếp theo CPU giảm dần, chỉ tiến trình thuộc nhóm
        self.assertEqual(w["top"][0]["group"], "claude")

    def setUp(self):  # test sửa biến toàn cục của module: trả lại nguyên trạng để test khác không chạy ps thật
        saved = (list(server._WORKLOAD_CACHE), list(server._LAST_VIEW))
        def restore():
            server._WORKLOAD_CACHE[:] = saved[0]
            server._LAST_VIEW[:] = saved[1]
        self.addCleanup(restore)

    def test_classification_false_positives_and_homebrew_python(self):
        for cmd in ("/usr/libexec/legacyd --x", "/usr/bin/pagyd", "/opt/bin/xshc", "/bin/bash /x/setup_claude.sh --target y", "less /x/CLAUDE.md", "vim claude.md", "shasum claude.txt", "/usr/bin/grep -rn claude foo"):
            self.assertIsNone(server._group_of(cmd), cmd)  # đối số nhắc tên agent không biến chương trình thành agent
        brew = "/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python /repo/bin/post-fix-gate.py --run-tests"
        self.assertEqual(server._group_of(brew), "gate")  # python3 mặc định của máy này
        self.assertIsNone(server._group_of("/opt/homebrew/bin/python3 /repo/server.py --demo"))

    def test_non_utf8_argv_does_not_raise(self):
        from unittest import mock
        server._LAST_VIEW[0] = 0.0
        server.mark_viewed()
        server._WORKLOAD_CACHE[0] = 0.0
        bad = (PS + "  107  5.0  1024  00:00:01 claude \xff\xfe\n").encode("latin-1")  # byte không phải UTF-8
        with mock.patch.object(server.subprocess, "run") as run:
            run.return_value.stdout = bad
            server.agent_workload()  # không được ném UnicodeDecodeError (làm chết vòng đọc nền)

    def test_no_ps_when_nobody_viewing(self):
        from unittest import mock
        server._WORKLOAD_CACHE[0] = 0.0
        server._LAST_VIEW[0] = 0.0
        with mock.patch.object(server.subprocess, "run") as run:
            run.return_value.stdout = PS.encode()
            ps_calls = lambda: sum(1 for c in run.call_args_list if c.args[0][0] == "ps" and "pid=,pcpu=" in c.args[0][2])  # chỉ lần đo tải chính, không tính ps cây tiến trình
            server.agent_workload()
            self.assertEqual(ps_calls(), 0)  # chưa ai xem: không chạy ps
            server.mark_viewed()
            server.agent_workload()
            self.assertEqual(ps_calls(), 1)
            server.agent_workload()  # trong 30 s dùng cache
            self.assertEqual(ps_calls(), 1)

    def test_build_tasks_merges_processes_of_one_task(self):
        note = "AB/BA: A = main, B = PR head"
        procs = [
            {"pid": i, "group": "gate", "cpu": 10.0, "rssMb": 2, "etime": "01:44:19", "cmdFull": "/bin/bash /tmp/ab/run.sh", "where": "agent-workbench", "note": note}
            for i in range(7)
        ] + [
            {"pid": 50, "group": "claude", "cpu": 40.0, "rssMb": 200, "etime": "00:10:00", "cmdFull": "/x/claude.app/Contents/MacOS/claude --output-format", "where": "agent-workbench · worktree issue-380-build", "note": ""},
        ]
        tasks = server.build_tasks(procs)
        self.assertEqual(len(tasks), 2)  # 7 tiến trình run.sh gộp thành MỘT việc
        ab = next(t for t in tasks if t["group"] == "gate")
        self.assertEqual((ab["count"], ab["cpu"], ab["label"]), (7, 70.0, note))
        self.assertEqual(ab["where"], "agent-workbench")
        self.assertEqual(ab["etime"], "01:44:19")
        cl = next(t for t in tasks if t["group"] == "claude")
        self.assertEqual(cl["label"], "claude")  # không có chú thích: tên chương trình
        self.assertEqual(tasks[0]["group"], "gate")  # 70% > 40%: xếp theo CPU giảm dần

    def test_electron_process_roles_get_readable_names(self):
        base = "/Applications/Antigravity.app/Contents"
        cases = {
            base + "/MacOS/Antigravity": "Cửa sổ chính",
            base + "/Frameworks/Antigravity Helper (Renderer).app/Contents/MacOS/Antigravity Helper (Renderer) --type=renderer --user-data-dir=/Users/a/Library/Application Support/Antigravity": "Giao diện cửa sổ (renderer)",
            base + "/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper --type=gpu-process --user-data-dir=/x": "Đồ hoạ (GPU)",
            base + "/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper --type=utility --utility-sub-type=network.mojom.NetworkService": "Dịch vụ mạng",
            base + "/Resources/bin/language_server --standalone --override_ide_name antigravity": "language_server (AI backend)",
            base + "/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper sidecars/x/dist/mcp_entry.cjs": "mcp_entry.cjs",
        }
        for cmd, want in cases.items():
            self.assertEqual(server._prog_name(cmd), want, cmd)
        self.assertEqual(server.where_from_cwd("/"), "")  # thư mục gốc không cho biết gì

    def test_resolve_where_climbs_to_parent_when_cwd_is_temp(self):
        repo = "/Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-377-build"
        cwds = {10: "/private/var/folders/xx/T/tmp.abc/repo", 11: "/tmp/claude-501/ab/clone-B-2", 12: repo, 13: "/"}
        ppids = {10: 11, 11: 12, 12: 1, 13: 1}
        self.assertEqual(server.resolve_where(10, cwds, ppids), "agent-workbench · worktree issue-377-build")  # gate test chạy trong thư mục tạm → lấy nơi của tiến trình cha
        self.assertEqual(server.resolve_where(12, cwds, ppids), "agent-workbench · worktree issue-377-build")
        self.assertEqual(server.resolve_where(13, cwds, ppids), "")  # không tổ tiên nào có nơi làm việc thật
        self.assertEqual(server.resolve_where(99, {}, {}), "")

    def test_review_findings_class(self):
        import json
        from unittest import mock
        # script tương đối: đọc theo cwd của TIẾN TRÌNH, không theo cwd của server
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "job.sh"), "w") as f:
                f.write("#!/bin/bash\n# việc của tiến trình\n")
            self.assertEqual(server.script_note("/bin/bash job.sh", cwd=d), "việc của tiến trình")
        self.assertEqual(server.script_note("/bin/bash job.sh"), "")
        # CLI viết bằng node: script tên đúng agent vẫn vào nhóm của nó; script setup_* thì không
        self.assertEqual(server._group_of("node /opt/homebrew/bin/gemini --yolo"), "gemini")
        self.assertEqual(server._group_of("node /opt/homebrew/lib/agy --conversation x"), "antigravity")
        self.assertIsNone(server._group_of("/bin/bash /x/setup_claude.sh"))
        # nhãn không lộ mảnh code inline và --type= chỉ tính với app đóng gói
        self.assertNotIn("token", server._prog_name("python3 -c " + FAKE_TOKEN2 + " print(1)"))
        self.assertNotEqual(server._prog_name("node x.js --type=module"), "module")
        # payload cuối: không có argv đầy đủ, không có danh sách tiến trình thô, mỗi nhóm ≤ 5 việc
        # 9 script gate khác tên nhau → 9 "việc" khác nhau, đủ để vượt giới hạn 5 mỗi nhóm
        scripts = [("python3", "post-fix-gate.py"), ("bash", "post-fix-gate.sh"), ("node", "post-fix-gate.js"), ("python3", "run_impacted.py"),
                   ("bash", "run_impacted.sh"), ("node", "run_impacted.js"), ("python3", "heavy_slot.py"), ("bash", "heavy_slot.sh"), ("node", "heavy_slot.js")]
        lines = ["  PID  PCPU   RSS  ELAPSED COMMAND"] + [
            ("  %d  5.0  1024  00:01:00 /usr/bin/%s /tmp/x/%s --settings {\"secret\":\"" + FAKE_KEY + "\"}") % (200 + i, interp, name)
            for i, (interp, name) in enumerate(scripts)
        ]
        server._LAST_VIEW[0] = 0.0
        server.mark_viewed()
        server._WORKLOAD_CACHE[0] = 0.0
        def fake(args, **kw):
            r = mock.Mock()
            r.stdout = ("\n".join(lines) if "pcpu=" in args[2] else "").encode() if args[0] == "ps" else b""
            return r
        with mock.patch.object(server.subprocess, "run", side_effect=fake):
            res = server.agent_workload()
        blob = json.dumps(res)
        self.assertNotIn("cmdFull", blob)
        self.assertNotIn(FAKE_KEY[:6], blob)
        self.assertEqual(res["top"], [])
        self.assertEqual(sum(1 for t in res["tasks"] if t["group"] == "gate"), 5)  # 9 việc thật, chỉ giữ 5 nặng nhất

    def test_ps_locale_forced(self):
        from unittest import mock
        server._LAST_VIEW[0] = 0.0
        server.mark_viewed()
        server._WORKLOAD_CACHE[0] = 0.0
        seen = []
        def fake(args, **kw):
            if args[0] == "ps":
                seen.append((args[2], (kw.get("env") or {}).get("LC_ALL")))
            r = mock.Mock(); r.stdout = b""
            return r
        with mock.patch.object(server.subprocess, "run", side_effect=fake):
            server.agent_workload()
        self.assertTrue(any("pcpu=" in a for a, _ in seen))  # lệnh in pcpu có chạy
        self.assertTrue(all(lc == "C" for _, lc in seen), seen)  # MỌI lệnh ps (kể cả lệnh pcpu) ép LC_ALL=C: số thập phân luôn dấu chấm

    def test_demo_host_stats_hides_real_processes(self):
        self.assertEqual(server.host_stats(workload=False)["workload"], {"groups": [], "top": [], "tasks": []})

    def test_idle_interval_slows_background_loops(self):
        server._LAST_VIEW[0] = 0.0
        self.assertFalse(server.viewing())
        self.assertEqual(server.loop_wait(30, floor=300, mult=4), 300)  # GitHub: không ai xem → ≥ 5 phút
        self.assertEqual(server.loop_wait(3, floor=30, mult=6), 30)     # đọc máy: không ai xem → ≥ 30 s
        self.assertEqual(server.loop_wait(600, floor=300, mult=4), 2400)  # nền đã chậm sẵn thì chỉ nhân
        server.mark_viewed()
        self.assertTrue(server.viewing())
        self.assertEqual(server.loop_wait(30, floor=300, mult=4), 30)   # có người xem: nhịp gốc

    def test_script_note_and_where(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
            f.write("#!/bin/bash\n# AB/BA: A = main, B = PR head " + FAKE_TOKEN + "\necho hi\n")
        self.addCleanup(os.unlink, f.name)
        note = server.script_note("/bin/bash " + f.name)
        self.assertTrue(note.startswith("AB/BA: A = main"))
        self.assertNotIn(FAKE_TOKEN.split("=")[1], note)  # redact áp cho ghi chú
        self.assertEqual(server.script_note("/usr/bin/python3 /nonexistent/x.py"), "")
        self.assertEqual(server.script_note("claude -p task"), "")
        w = server.where_from_cwd("/Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-380-build/mcp-servers")
        self.assertEqual(w, "agent-workbench · worktree issue-380-build")
        self.assertEqual(server.where_from_cwd("/Volumes/Data/Toan/agent-workbench"), "agent-workbench")
        self.assertEqual(server.where_from_cwd(""), "")

    def test_garbage_lines_ignored(self):
        w = server.workload_from_ps("garbage\n\n  x y z\n")
        self.assertEqual(w["groups"], [])


if __name__ == "__main__":
    unittest.main()
