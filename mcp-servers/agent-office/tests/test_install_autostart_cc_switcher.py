"""Autostart truyền đường dẫn cc-switcher-mcp ở repo thật cho trang /cc-switcher (bản chép ở ~/.agent-office/app không có nó)."""
import os, plistlib, stat, subprocess, tempfile, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class InstallAutostartCcSwitcher(unittest.TestCase):
    def test_plist_points_cc_switcher_at_repo(self):
        with tempfile.TemporaryDirectory() as home:
            stub = os.path.join(home, "bin")
            os.makedirs(stub)
            p = os.path.join(stub, "launchctl")  # never touch the real launchd
            with open(p, "w") as f:
                f.write("#!/bin/sh\nexit 0\n")
            os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC)
            env = dict(os.environ, HOME=home, PATH=stub + os.pathsep + os.environ["PATH"])
            r = subprocess.run(["bash", os.path.join(HERE, "install-autostart.sh")], env=env,
                               capture_output=True, text=True, timeout=30)
            self.assertEqual(r.returncode, 0, r.stderr)
            with open(os.path.join(home, "Library/LaunchAgents/com.toanmobile.agent-office.plist"), "rb") as f:
                plist = plistlib.load(f)
            # trang /cc-switcher gọi cc-switcher-mcp ở repo thật, không phải bản chép
            ccs = plist["EnvironmentVariables"].get("AGENT_OFFICE_CC_SWITCHER", "")
            # in a linked worktree the script points at the main checkout (#900), else at the sibling dir of this tree
            rel = os.path.join("mcp-servers", "cc-switcher-mcp", "bin", "cc-switcher-mcp.js")
            common = subprocess.run(["git", "-C", HERE, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                    capture_output=True, text=True).stdout.strip()
            main_ccs = os.path.join(os.path.dirname(common), rel) if common else ""
            want = main_ccs if main_ccs and os.path.isfile(main_ccs) else os.path.join(HERE, "..", "cc-switcher-mcp", "bin", "cc-switcher-mcp.js")
            self.assertEqual(os.path.realpath(ccs), os.path.realpath(want))
            self.assertTrue(os.path.isfile(ccs), ccs)

    def test_run_from_linked_worktree_points_at_main_checkout(self):
        # #900: a path taken from the worktree it ran in went 503 once that worktree was removed
        git = lambda cwd, *a: subprocess.run(["git", "-C", cwd, "-c", "user.email=t@t", "-c", "user.name=t", *a],
                                              check=True, capture_output=True, text=True)
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            main, home = os.path.join(tmp, "main"), os.path.join(tmp, "home")
            ao = os.path.join(main, "mcp-servers", "agent-office")
            os.makedirs(os.path.join(ao, "web"))
            os.makedirs(os.path.join(main, "mcp-servers", "cc-switcher-mcp", "bin"))
            for n in ("server.py", "inbox_hook.py", "gate_full_runner.py", "config.json", "install-autostart.sh"):
                with open(os.path.join(HERE, n), "rb") as f, open(os.path.join(ao, n), "wb") as g:
                    g.write(f.read())
            open(os.path.join(main, "mcp-servers", "cc-switcher-mcp", "bin", "cc-switcher-mcp.js"), "w").write("//\n")
            open(os.path.join(ao, "web", "index.html"), "w").write("<html></html>")
            subprocess.run(["git", "init", "-q", main], check=True)
            git(main, "add", "-A"); git(main, "commit", "-qm", "x")
            wt = os.path.join(tmp, "wt")
            git(main, "worktree", "add", "-q", "-b", "side", wt)
            stub = os.path.join(tmp, "bin"); os.makedirs(stub)
            p = os.path.join(stub, "launchctl")
            open(p, "w").write("#!/bin/sh\nexit 0\n"); os.chmod(p, 0o755)
            env = dict(os.environ, HOME=home, PATH=stub + os.pathsep + os.environ["PATH"])
            r = subprocess.run(["bash", os.path.join(wt, "mcp-servers", "agent-office", "install-autostart.sh")], env=env,
                               capture_output=True, text=True, timeout=30)
            self.assertEqual(r.returncode, 0, r.stderr)
            with open(os.path.join(home, "Library/LaunchAgents/com.toanmobile.agent-office.plist"), "rb") as f:
                ccs = plistlib.load(f)["EnvironmentVariables"]["AGENT_OFFICE_CC_SWITCHER"]
            self.assertEqual(os.path.realpath(ccs), os.path.join(main, "mcp-servers", "cc-switcher-mcp", "bin", "cc-switcher-mcp.js"))


if __name__ == "__main__":
    unittest.main()
