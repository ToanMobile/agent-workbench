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
            self.assertEqual(os.path.realpath(ccs), os.path.realpath(os.path.join(HERE, "..", "cc-switcher-mcp", "bin", "cc-switcher-mcp.js")))
            self.assertTrue(os.path.isfile(ccs), ccs)


if __name__ == "__main__":
    unittest.main()
