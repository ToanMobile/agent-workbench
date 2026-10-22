"""ai-factory.sh stop must kill only its own tunnel/server, never another program that reused a stale PID."""
import os, shutil, socket, subprocess, sys, tempfile, time, unittest

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SCRIPT = os.environ.get("AI_FACTORY_SCRIPT") or os.path.join(REPO, "ai-factory.sh")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class StopKillsOnlyItsOwn(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        root, self.home = os.path.join(self.tmp, "repo"), os.path.join(self.tmp, "home")
        # A fake repo around a copy of the script: the boards command is a stub, so no real runner is touched.
        os.makedirs(os.path.join(root, "universal-agent-devkit/scripts/governance"))
        os.makedirs(os.path.join(root, "mcp-servers/agent-office"))
        os.makedirs(os.path.join(self.home, ".agent-office"))
        shutil.copy(SCRIPT, os.path.join(root, "ai-factory.sh"))
        with open(os.path.join(root, "universal-agent-devkit/scripts/governance/super_board_all.py"), "w") as f:
            f.write("print('stub boards')\n")
        with open(os.path.join(root, "mcp-servers/agent-office/config.json"), "w") as f:
            f.write('{"port": %d}\n' % free_port())
        self.script = os.path.join(root, "ai-factory.sh")
        self.state = os.path.join(self.home, ".agent-office")
        self.procs = []

    def tearDown(self):
        for p in self.procs:
            if p.poll() is None:
                p.kill()
                p.wait(5)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def spawn(self, name):
        """A long sleep whose command line carries name (a copied /bin/sleep is killed by macOS at once)."""
        p = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", name])
        self.procs.append(p)
        return p

    def stop(self):
        env = dict(os.environ, HOME=self.home)
        return subprocess.run(["bash", self.script, "stop"], env=env, capture_output=True, text=True, timeout=30)

    def test_stale_pid_of_another_program_is_left_alone(self):
        other = self.spawn("Xcode-helper")  # e.g. after a reboot the old tunnel PID now belongs to this
        for name in ("tunnel.pid", "server.pid"):
            with open(os.path.join(self.state, name), "w") as f:
                f.write(str(other.pid))
        r = self.stop()
        self.assertEqual(r.returncode, 0, r.stderr)
        time.sleep(0.3)
        self.assertIsNone(other.poll(), "ai-factory stop killed an unrelated program")
        self.assertFalse(os.path.exists(os.path.join(self.state, "tunnel.pid")))  # the stale record is still dropped

    def test_own_tunnel_is_stopped(self):
        tunnel = self.spawn("cloudflared")
        with open(os.path.join(self.state, "tunnel.pid"), "w") as f:
            f.write(str(tunnel.pid))
        with open(os.path.join(self.state, "remote-key"), "w") as f:
            f.write("k" * 43)
        r = self.stop()
        self.assertEqual(r.returncode, 0, r.stderr)
        tunnel.wait(5)
        self.assertFalse(os.path.exists(os.path.join(self.state, "remote-key")))  # the key dies with the tunnel


if __name__ == "__main__":
    unittest.main()
