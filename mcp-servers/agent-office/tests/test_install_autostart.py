"""Autostart must not run code from the (disposable) worktree it was installed from."""
import os, plistlib, stat, subprocess, tempfile, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class InstallAutostart(unittest.TestCase):
    def test_plist_points_at_stable_copy(self):
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
            script = plist["ProgramArguments"][1]
            app_dir = os.path.join(home, ".agent-office", "app")
            self.assertTrue(script.startswith(app_dir + os.sep), script)
            self.assertTrue(os.path.isfile(script))
            self.assertTrue(os.path.isfile(os.path.join(app_dir, "config.json")))
            self.assertTrue(os.path.isdir(os.path.join(app_dir, "web")))
            self.assertEqual(plist["WorkingDirectory"], app_dir)
            self.assertEqual(plist["KeepAlive"], {"SuccessfulExit": False})


if __name__ == "__main__":
    unittest.main()
