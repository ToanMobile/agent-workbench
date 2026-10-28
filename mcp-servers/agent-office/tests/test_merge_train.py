"""#562: Agent Office đọc merge-train.state để không báo "Mất tín hiệu" khi merge train đang chạy gate.

Có pid sống -> runner stale thành 'merging', repo có `train`, thẻ Review trong train mang mergeTag gate, thẻ đã vào hàng đợi mà chưa vào train
mang 'wait'. pid chết (file mồ côi) hoặc file hỏng -> hành vi cũ: 'stale', không train, không nhãn."""
import os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402

SHA = "a" * 40


def dead_pid():
    p = subprocess.Popen([sys.executable, "-c", "pass"])
    p.wait()
    return p.pid


class RepoFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = self.tmp.name
        self.repo = os.path.join(self.root, "Demo")
        self.sb = os.path.join(self.repo, ".git", "super-board")
        os.makedirs(self.sb)

    def write_state(self, text):
        with open(os.path.join(self.sb, "merge-train.state"), "w") as f:
            f.write(text)

    def train_state(self, pid, step="gate"):
        return (f"pid {pid}\nstarted_at {int(server.now()) - 720}\nstep {step}\n"
                f"pr 550 {SHA} issue-532-x\npr 552 {SHA} issue-538-y\n")


class ReadMergeTrain(RepoFixture):
    def test_live_pid_gives_train_with_cards(self):
        self.write_state(self.train_state(os.getpid()))
        t = server.read_merge_train(self.repo)
        self.assertEqual(t["cards"], [532, 538])
        self.assertEqual(t["step"], "gate")
        self.assertEqual([x["pr"] for x in t["prs"]], [550, 552])

    def test_dead_pid_is_ignored(self):
        self.write_state(self.train_state(dead_pid()))
        self.assertIsNone(server.read_merge_train(self.repo))

    def test_missing_corrupt_or_pidless_file_is_ignored(self):
        self.assertIsNone(server.read_merge_train(self.repo))
        self.write_state("not a state file\n")
        self.assertIsNone(server.read_merge_train(self.repo))
        self.write_state(f"started_at 1\nstep gate\npr 1 {SHA} issue-1-x\n")
        self.assertIsNone(server.read_merge_train(self.repo))

    def test_queued_cards_skip_rows_without_ref(self):
        with open(os.path.join(self.sb, "merge-queue.labeled"), "w") as f:
            f.write(f"550 {SHA} 1 issue-532-x\n560 {SHA} 2 issue-540-w\n570 {SHA} 3\n")
        self.assertEqual(server.read_merge_train(self.repo), None)
        self.assertEqual(server.read_queued_cards(self.repo), {532, 540})

    def test_reader_does_not_hold_the_train_lock(self):
        import fcntl
        lock = os.path.join(self.sb, "merge-train.lock")
        with open(lock, "w") as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.write_state(self.train_state(os.getpid()))
            server.read_merge_train(self.repo)
            fcntl.flock(held, fcntl.LOCK_UN)
        with open(lock, "w") as f:  # khoá lấy lại được ngay: reader không giữ gì
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                got = True
            except OSError:
                got = False
        self.assertTrue(got)


class BuildStateMerging(RepoFixture):
    def build(self):
        t_now = server.now()
        cfg = {"root": self.root, "repos": ["Demo"], "github": {"owner": "o"}, "activeMinutes": 10, "githubSeconds": 60}
        tick = {"time": "10:00:00", "at": t_now - 1500, "counts": {}, "lanes": {}, "waiting": 0}
        item = lambda n, st: {"id": f"i{n}", "number": n, "title": f"t{n}", "repo": "Demo", "repoFull": "o/Demo", "status": st,
                              "state": "OPEN", "labels": [], "assignees": [], "fields": {}, "updatedAt": t_now}
        project = {"columns": [{"name": "Review", "kind": "review"}, {"name": "Ready", "kind": "ready"}],
                   "items": [item(532, "Review"), item(540, "Review"), item(999, "Review"), item(532 + 1, "Ready")]}
        st = server.build_state(cfg, project, {"ok": True}, [], {"ok": True}, [("Demo", "/x.log", [tick], None, t_now)],
                                server.LocalScanner(cfg))
        return st, {i["number"]: i for i in st["items"]}, st["repos"][0]

    def test_live_train_replaces_stale_and_tags_cards(self):
        self.write_state(self.train_state(os.getpid()))
        with open(os.path.join(self.sb, "merge-queue.labeled"), "w") as f:
            f.write(f"550 {SHA} 1 issue-532-x\n560 {SHA} 2 issue-540-w\n")
        st, items, repo = self.build()
        self.assertEqual(repo["runner"]["state"], "merging")
        self.assertEqual(repo["train"]["cards"], [532, 538])
        self.assertEqual(items[532]["mergeTag"], "gate")
        self.assertEqual(items[540]["mergeTag"], "wait")
        self.assertNotIn("mergeTag", items[999])
        self.assertNotIn("mergeTag", items[533])

    def test_orphan_state_keeps_old_behaviour(self):
        self.write_state(self.train_state(dead_pid()))
        st, items, repo = self.build()
        self.assertEqual(repo["runner"]["state"], "stale")
        self.assertIsNone(repo["train"])
        self.assertNotIn("mergeTag", items[532])


if __name__ == "__main__":
    unittest.main()
