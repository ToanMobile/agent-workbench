#!/usr/bin/env bash
# proof-capture.py device lock: one adb capture per SERIAL at a time (flock on a per-serial file in a
# machine-wide private dir), a bounded wait, exit 75 when the holder lives on, and NO effect on which
# device is chosen or on the denylist. Fake adb/emulator shims only: no real device is ever touched, every
# path is a temp dir, HOME is a fake one (so the real denylist and the real lock dir are never read).
#
# Env (tests only): PROOF_CAPTURE_CMD = another copy of proof-capture.py (the mutation runs use it),
#                   LOCK_TEST_ONLY   = comma list of case ids (T1,T7,...) to run just those (T5 also runs T5b/T5c; =T5 only T5),
#                   LOCK_TEST_PY     = interpreter for the whole test (e.g. /usr/bin/python3 = 3.9).
# Overlap is judged by event ORDER in the shim log (S = first device call after the lock, E = end of the
# screencap), never by absolute seconds: SESE = serialised, SSEE = overlapped.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CMD="${PROOF_CAPTURE_CMD:-$DEVKIT_DIR/bin/proof-capture.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"${LOCK_TEST_PY:-python3}" - "$TMP" "$CMD" <<'PY'
import contextlib, hashlib, importlib.util, os, re, signal, stat, struct, subprocess, sys, time, zlib

TMP, CMD = sys.argv[1], sys.argv[2]
ONLY = [x for x in os.environ.get("LOCK_TEST_ONLY", "").split(",") if x]
FAILS = []
PROCS = []
SYS_PY39 = "/usr/bin/python3" if os.path.exists("/usr/bin/python3") else None
UNIT = "thiết-bị:5555"            # \w matches these letters: reaches the lock through `adb devices`
LONG = "L" * 300
MOD = None


def ok(msg):
    print("✔ " + msg)


def fail(msg):
    print("✖ " + msg)
    FAILS.append(msg)


def check(cond, msg, detail=""):
    if cond:
        ok(msg)
    else:
        fail(msg + (" :: " + str(detail)[:700] if detail else ""))


def png_bytes():
    w = h = 120
    raw = b"".join(b"\0" + os.urandom(w * 3) for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 0)) + chunk(b"IEND", b""))


ADB = r'''#!/usr/bin/env python3
import hashlib, os, subprocess, sys, time
state = os.environ["FAKE_STATE"]
tag = os.environ.get("TAG", "-")
def log(kind, *rest):
    with open(os.path.join(state, "events.log"), "a") as f:
        f.write(" ".join([kind, tag, str(os.getpid()), repr(time.time())] + list(rest)) + "\n")
def mark(s):
    return os.path.join(state, "in-" + hashlib.md5(s.encode("utf-8")).hexdigest())
args = sys.argv[1:]
with open(os.path.join(state, "adb.log"), "a") as f:
    f.write(" ".join(args) + "\n")
if args[:1] == ["devices"]:
    log("D", "-")
    # FAKE_STALE_FIRST_DEVICES: this capture's FIRST `adb devices` answers as if the emulator were not up yet
    # (and, with FAKE_STALE_WAIT_FILE, only returns once that file exists): the answer is stale on arrival.
    first = os.path.join(state, "stale-used-" + tag)
    stale = bool(os.environ.get("FAKE_STALE_FIRST_DEVICES")) and not os.path.exists(first)
    if stale:
        open(first, "w").close()
    print("List of devices attached")
    for s in os.environ.get("FAKE_DEVICES", "").split(","):
        if s:
            print(s + "\tdevice")
    if not stale:  # `booted` = emulator-5554 (tests that boot nothing), `booted-<port>` = what the emulator shim started
        up = ["5554"] if os.path.exists(os.path.join(state, "booted")) else []
        up += [n[len("booted-"):] for n in sorted(os.listdir(state)) if n.startswith("booted-")]
        for port in up:
            print("emulator-" + port + "\tdevice")
    sys.stdout.flush()
    waitfile = os.environ.get("FAKE_STALE_WAIT_FILE")
    if stale and waitfile:
        end = time.time() + 60
        while not os.path.exists(waitfile) and time.time() < end:
            time.sleep(0.05)
    sys.exit(0)
if args[:1] == ["connect"]:
    sys.exit(0)
if args[:1] == ["-s"] and len(args) >= 3:
    serial, rest = args[1], args[2:]
    if rest[:2] == ["emu", "avd"]:
        print("PhoneConnect"); print("OK"); sys.exit(0)
    if rest[:3] == ["shell", "getprop", "sys.boot_completed"]:
        print(1); sys.exit(0)
    if rest[:2] == ["shell", "dumpsys"]:
        log("S", serial)
        print("  mWakefulness=" + os.environ.get("FAKE_WAKE", "Awake"))
        sys.exit(0)
    if rest[:1] == ["exec-out"]:
        peer = os.environ.get("FAKE_RENDEZVOUS")
        open(mark(serial), "w").close()
        if os.environ.get("FAKE_AFTER_PEER"):
            # hold the device until ANOTHER capture has resolved its device (its `adb devices`), then a grace
            # period: an unlocked peer reaches the device inside it (overlap), a locked one is waiting.
            def peer_seen():
                try:
                    return any(l.startswith("D ") and l.split(" ")[1] != tag for l in open(os.path.join(state, "events.log")).read().splitlines())
                except OSError:
                    return False
            end = time.time() + 25
            while not peer_seen() and time.time() < end:
                time.sleep(0.05)
            time.sleep(float(os.environ.get("FAKE_GRACE", "2.0")))
        elif peer:
            end = time.time() + 25
            while not os.path.exists(mark(peer)) and time.time() < end:
                time.sleep(0.05)
            log("R", serial, "ok" if os.path.exists(mark(peer)) else "timeout")
        else:
            time.sleep(float(os.environ.get("FAKE_HOLD", "1.2")))
        if os.environ.get("FAKE_DAEMON"):
            p = subprocess.Popen(["sleep", "100"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True, close_fds=False)
            with open(os.path.join(state, "daemons"), "a") as f:
                f.write(str(p.pid) + "\n")
        log("E", serial)
        sys.stdout.buffer.write(b"not a png" if os.environ.get("FAKE_BADPNG") else open(os.path.join(state, "shot.png"), "rb").read())
        sys.exit(0)
sys.exit(1)
'''
EMU = '''#!/bin/sh
if [ "$1" = "-list-avds" ]; then [ -n "${FAKE_AVDS-PhoneConnect}" ] && echo "${FAKE_AVDS-PhoneConnect}"; exit 0; fi
port=5554; prev=
for a in "$@"; do [ "$prev" = "-port" ] && port="$a"; prev="$a"; done
echo start >> "$FAKE_STATE/emu-starts"
if [ -n "${FAKE_EMU_DAEMON-}" ]; then sleep 100 >/dev/null 2>&1 & echo $! >> "$FAKE_STATE/daemons"; fi
sleep 0.4
[ -n "${FAKE_NOBOOT-}" ] || touch "$FAKE_STATE/booted-$port"
exit 0
'''


class World:
    """One fake machine: HOME, lock dir (NOT created: production must), shim log, adb + emulator shims."""
    def __init__(self, name):
        self.root = os.path.join(TMP, name)
        self.home = os.path.join(self.root, "home")
        self.locks = os.path.join(self.root, "locks")
        self.state = os.path.join(self.root, "state")
        for d in (self.home, self.state):
            os.makedirs(d)
        self.adb = os.path.join(self.root, "adb")
        self.emu = os.path.join(self.root, "emu")
        for path, body in ((self.adb, ADB), (self.emu, EMU)):
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, 0o755)
        with open(os.path.join(self.state, "shot.png"), "wb") as f:
            f.write(png_bytes())
        self.n = 0

    def project(self, serial=None, avd=None, deny=None, dirname=None):
        self.n += 1
        d = os.path.join(self.root, dirname or ("proj%d" % self.n))
        os.makedirs(d)
        prov = {"type": "adb"}
        if serial:
            prov["serial"] = serial
        if avd:
            prov["avd"] = avd
        import json
        with open(os.path.join(d, ".antigravity-pm.json"), "w") as f:
            json.dump({"proof": {"defaultProvider": "d", "providers": {"d": prov}}}, f)
        if deny:
            with open(os.path.join(d, ".adb-denylist"), "w") as f:
                f.write(deny + "\n")
        return d

    def launch(self, proj, tag, devices, hold=None, wait=None, args=(), env=None, py=None, override=True,
               daemon=False, rendezvous=None, drop=(), session=None, after_peer=False):
        e = {k: v for k, v in os.environ.items() if k not in (
            "ADB_DENY_SERIALS", "PROOF_DEVICE_LOCK", "PROOF_DEVICE_LOCK_WAIT", "PROOF_DEVICE_LOCK_DIR",
            "CLAUDE_CODE_SESSION_ID", "DEVKIT_SESSION_ID", "CLAUDE_SESSION_ID", "ANDROID_SERIAL",
            "PROOF_DEVICE_LOCK_HELD", "PROOF_DEVICE_LOCK_HELD_PID", "PROOF_DEVICE_LOCK_HELD_AVD")}
        e.update(HOME=self.home, FAKE_STATE=self.state, TAG=tag, FAKE_DEVICES=",".join(devices),
                 PYTHONUTF8="1", PYTHONDONTWRITEBYTECODE="1")
        if override:
            e["PROOF_DEVICE_LOCK_DIR"] = self.locks
        if hold is not None:
            e["FAKE_HOLD"] = str(hold)
        if wait is not None:
            e["PROOF_DEVICE_LOCK_WAIT"] = str(wait)
        if daemon:
            e["FAKE_DAEMON"] = "1"
        if rendezvous:
            e["FAKE_RENDEZVOUS"] = rendezvous
        if after_peer:
            e["FAKE_AFTER_PEER"] = "1"
        if session:
            e["DEVKIT_SESSION_ID"] = session
        e.update(env or {})
        for k in drop:
            e.pop(k, None)
        cmd = [py or sys.executable, CMD, "--project", proj, "--adb", self.adb, "--emulator", self.emu,
               "--connect-timeout", "1", "--boot-timeout", "40"] + list(args)
        p = subprocess.Popen(cmd, env=e, cwd=proj, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
                             start_new_session=True,
                             preexec_fn=lambda: signal.signal(signal.SIGINT, signal.default_int_handler))
        p.t0 = time.monotonic()
        p.tag = tag
        p.proj = proj
        PROCS.append(p)
        return p

    def events(self):
        out = []
        try:
            lines = open(os.path.join(self.state, "events.log")).read().splitlines()
        except OSError:
            return out
        for ln in lines:
            f = ln.split(" ")
            if len(f) >= 5:
                out.append({"kind": f[0], "tag": f[1], "pid": f[2], "t": float(f[3]), "serial": f[4], "rest": f[5:]})
        return out

    def seq(self, serial):
        """(overlapping pairs, 'SESE'-style order, per-tag intervals) for one serial."""
        ev = sorted((e for e in self.events() if e["serial"] == serial and e["kind"] in ("S", "E")), key=lambda e: e["t"])
        iv = {}
        for e in ev:
            iv.setdefault(e["tag"], {})[e["kind"]] = e["t"]
        tags = sorted(iv)
        n = 0
        for i in range(len(tags)):
            for j in range(i + 1, len(tags)):
                a, b = iv[tags[i]], iv[tags[j]]
                if len(a) == 2 and len(b) == 2 and a["S"] < b["E"] and b["S"] < a["E"]:
                    n += 1
        return n, "".join(e["kind"] for e in ev), iv

    def has_event(self, kind, tag, serial=None):
        return any(e["kind"] == kind and e["tag"] == tag and (serial is None or e["serial"] == serial) for e in self.events())

    def lock_files(self):
        try:
            return sorted(os.listdir(self.locks))
        except OSError:
            return []


def wait_for(cond, timeout=25.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.05)
    return False


def finish(p, timeout=90):
    try:
        out, err = p.communicate(timeout=timeout)
        rc = p.returncode
    except subprocess.TimeoutExpired:
        with contextlib.suppress(OSError):
            os.killpg(p.pid, signal.SIGKILL)
        out, err = p.communicate()
        rc = "TIMEOUT"
    p.elapsed = time.monotonic() - p.t0
    return rc, out, err


def pngs(proj):
    d = os.path.join(proj, "reports")
    return sorted(x for x in os.listdir(d) if x.startswith("proof-")) if os.path.isdir(d) else []


def reap_all():
    for p in PROCS:
        with contextlib.suppress(OSError):
            os.killpg(p.pid, signal.SIGKILL)
        with contextlib.suppress(Exception):
            p.communicate(timeout=5)
    for d, _dirs, files in os.walk(TMP):
        if "daemons" in files:
            for pid in open(os.path.join(d, "daemons")).read().split():
                with contextlib.suppress(OSError, ValueError):
                    os.kill(int(pid), signal.SIGKILL)
    PROCS.clear()


def load():
    global MOD
    if MOD is None:
        spec = importlib.util.spec_from_file_location("proof_capture_under_test", CMD)
        MOD = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(MOD)
    return MOD


def same_serial(label, serial, py=None, args=(), env=None, expect_serialised=True, devices=None):
    """A holds the device (long screencap); B is launched once A is inside it. Returns the world."""
    w = World("same-" + re.sub(r"\W", "", label))
    a_proj, b_proj = w.project(serial), w.project(serial)
    devs = devices or [serial]
    a = w.launch(a_proj, "A", devs, after_peer=True, args=args, env=env, py=py, session="SID-A")
    if not wait_for(lambda: w.has_event("S", "A", serial)):
        finish(a)
        fail(label + ": A never reached the device")
        return w
    b = w.launch(b_proj, "B", devs, hold=0.2, args=args, env=env, py=py)
    ra, _, era = finish(a)
    rb, _, erb = finish(b)
    n, seq, _ = w.seq(serial)
    if expect_serialised:
        check(n == 0 and seq == "SESE" and ra == 0 and rb == 0 and pngs(a_proj) and pngs(b_proj),
              label + ": same serial is serialised, both captures succeed (SESE, 0 overlaps)",
              "overlaps=%s order=%s rcs=%s,%s a=%s b=%s" % (n, seq, ra, rb, era[-200:], erb[-200:]))
        check(str(a.pid) in erb, label + ": the waiter is told who holds it (holder pid in its stderr)", erb[-300:])
    else:
        check(n == 1 and seq == "SSEE" and ra == 0 and rb == 0, label + ": captures overlap (lock off)",
              "overlaps=%s order=%s" % (n, seq))
    return w


# ---------------------------------------------------------------- cases
def T1():
    same_serial("T1 phone serial", "RFCWA1KQT1Y")
    reap_all()


def T1b():
    # Python 3.9 (the macOS system python) and a serial with non-ASCII letters
    if SYS_PY39:
        same_serial("T1b py3.9 + unicode serial", UNIT, py=SYS_PY39)
    else:
        ok("T1b skipped: no /usr/bin/python3")
    reap_all()


def T2():
    w = World("diff")
    sa, sb = "RFCWA1KQT1Y", "emulator-5554"
    pa, pb = w.project(sa), w.project(sb)
    a = w.launch(pa, "A", [sa, sb], rendezvous=sb)
    b = w.launch(pb, "B", [sa, sb], rendezvous=sa)
    ra, _, ea = finish(a)
    rb, _, eb = finish(b)
    rdv = [e for e in w.events() if e["kind"] == "R"]
    check(ra == 0 and rb == 0 and len(rdv) == 2 and all(e["rest"] == ["ok"] for e in rdv),
          "T2 different serials (phone vs emulator-5554) run in parallel: each saw the other inside its screencap",
          "rcs=%s,%s rdv=%s a=%s b=%s" % (ra, rb, [e["rest"] for e in rdv], ea[-200:], eb[-200:]))
    check(len(w.lock_files()) == 2, "T2 one lock file per serial, none shared", w.lock_files())
    reap_all()


def T3():
    """SIGKILLed holder: the kernel drops the flock, the next capture does not wait for the timeout."""
    w = World("kill")
    s = "RFCWA1KQT1Y"
    pa, pb = w.project(s), w.project(s)
    a = w.launch(pa, "A", [s], hold=120)
    if not wait_for(lambda: w.has_event("S", "A", s)):
        finish(a)
        return fail("T3: A never reached the device")
    os.kill(a.pid, signal.SIGKILL)
    a.wait(timeout=10)
    b = w.launch(pb, "B", [s], hold=0.2, wait=120)
    rb, _, eb = finish(b, 100)
    check(rb == 0 and b.elapsed < 60 and pngs(pb), "T3 SIGKILLed holder releases the lock at once (B done well before the 120 s wait)",
          "rc=%s elapsed=%.1f err=%s" % (rb, b.elapsed, eb[-300:]))
    try:
        ident = __import__("json").loads(open(os.path.join(w.locks, w.lock_files()[0])).read())
        check(ident.get("pid") == b.pid, "T3 the lock file now carries B's identity (B really took the lock)", ident)
    except (OSError, ValueError, IndexError) as exc:
        fail("T3 lock identity unreadable: %r %s" % (exc, w.lock_files()))
    reap_all()


def T4():
    """A long-lived child of adb (the adb server, an emulator) must not inherit the lock."""
    w = World("daemon")
    s = "RFCWA1KQT1Y"
    pa, pb = w.project(s), w.project(s)
    a = w.launch(pa, "A", [s], hold=0.2, daemon=True)
    ra, _, ea = finish(a)
    live = [p for p in open(os.path.join(w.state, "daemons")).read().split()] if os.path.exists(os.path.join(w.state, "daemons")) else []
    b = w.launch(pb, "B", [s], hold=0.2, wait=120)
    rb, _, eb = finish(b, 100)
    check(ra == 0 and rb == 0 and live and b.elapsed < 60,
          "T4 a surviving child of adb does not keep the lock (B not blocked by the daemon)",
          "rcs=%s,%s daemons=%s elapsed=%.1f %s" % (ra, rb, live, b.elapsed, eb[-200:]))
    reap_all()


def T4b():
    """Same for the emulator process boot_avd starts detached (and whatever it leaves running)."""
    w = World("emudaemon")
    pa, pb = w.project(avd="PhoneConnect"), w.project(avd="PhoneConnect")
    a = w.launch(pa, "A", [], hold=0.2, env={"FAKE_EMU_DAEMON": "1"})
    ra, _, ea = finish(a, 120)
    b = w.launch(pb, "B", [], hold=0.2, wait=120)
    rb, _, eb = finish(b, 100)
    live = open(os.path.join(w.state, "daemons")).read().split() if os.path.exists(os.path.join(w.state, "daemons")) else []
    check(ra == 0 and rb == 0 and live and b.elapsed < 60,
          "T4b a process left running by the emulator start does not keep the lock", "rcs=%s,%s daemons=%s elapsed=%.1f %s" % (ra, rb, live, b.elapsed, eb[-200:]))
    reap_all()


def T5():
    """Holder lives on: bounded wait, exit 75, message names holder/since/knob; then SIGTERM releases."""
    w = World("busy")
    s = "RFCWA1KQT1Y"
    pa = w.project(s, dirname="holder-proj")
    pb, pc = w.project(s), w.project(s)
    a = w.launch(pa, "A", [s], hold=120, session="SID-HOLDER-1")
    if not wait_for(lambda: w.has_event("S", "A", s)):
        finish(a)
        return fail("T5: A never reached the device")
    b = w.launch(pb, "B", [s], wait=2)
    rb, _, eb = finish(b, 60)
    check(rb == 75, "T5 wait expired with the holder alive: exit code 75", "rc=%s err=%s" % (rb, eb[-300:]))
    check(str(a.pid) in eb and "SID-HOLDER-1" in eb and "holder-proj" in eb and re.search(r"\d{4}-\d{2}-\d{2}", eb)
          and "PROOF_DEVICE_LOCK_WAIT" in eb and s in eb,
          "T5 message names holder pid, session, cwd, since-when, serial and the env knob", eb[-400:])
    check(not w.has_event("S", "B") and not pngs(pb), "T5 the timed-out capture never touched the device and wrote no PNG")
    b0 = w.launch(w.project(s), "B0", [s], wait=0)
    rb0, _, _ = finish(b0, 60)
    check(rb0 == 75 and b0.elapsed < 30, "T5 wait=0 fails at once with 75", "rc=%s %.1f" % (rb0, b0.elapsed))
    bp = w.launch(w.project(s), "BP", [s], wait=1, args=("--plan-only",))
    rbp, obp, ebp = finish(bp, 60)
    check(rbp == 0 and '"action": "screencap"' in obp and "Cho khoa" not in ebp and bp.elapsed < 30,
          "T5 --plan-only never takes or waits for the lock", "rc=%s out=%s err=%s" % (rbp, obp, ebp[-200:]))
    a.send_signal(signal.SIGTERM)
    a.wait(timeout=10)
    c = w.launch(pc, "C", [s], hold=0.2, wait=120)
    rc_, _, ec = finish(c, 100)
    check(rc_ == 0 and c.elapsed < 60, "T5 SIGTERM of the holder releases the lock", "rc=%s %.1f %s" % (rc_, c.elapsed, ec[-200:]))
    reap_all()


def T5b():
    """Holder identity is data from another process: control characters never reach the terminal."""
    w = World("ansi")
    s = "RFCWA1KQT1Y"
    pa = w.project(s, dirname="evil\x1b[31mred\nline")
    a = w.launch(pa, "A", [s], hold=120)
    if not wait_for(lambda: w.has_event("S", "A", s)):
        finish(a)
        return fail("T5b: A never reached the device")
    b = w.launch(w.project(s), "B", [s], wait=1)
    rb, _, eb = finish(b, 60)
    check(rb == 75 and "\x1b" not in eb and "evil" in eb, "T5b control characters in the holder cwd are not echoed", repr(eb[-300:]))
    reap_all()


def T5c():
    """The identity in the lock file is only for the message: garbage in it never breaks the wait."""
    import pathlib
    s = "RFCWA1KQT1Y"
    for label, content in (("not json", b"\x00\xff garbage {"), ("json list", b"[1, 2]"), ("nan start", b'{"pid": 7, "started": NaN, "cwd": 5}'),
                           ("huge start", b'{"pid": 7, "started": 1e999}'), ("empty", b"")):
        w = World("garbage-" + label.replace(" ", ""))
        os.makedirs(w.locks, mode=0o700)
        path = str(load().lock_path(pathlib.Path(w.locks), "serial", s))
        holder = subprocess.Popen([sys.executable, "-I", "-c",
            "import fcntl,os,sys,time\nfd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT,0o600)\nfcntl.flock(fd,fcntl.LOCK_EX)\n"
            "os.write(fd,sys.stdin.buffer.read())\nprint('held',flush=True)\ntime.sleep(60)", path],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=False, start_new_session=True)
        PROCS.append(holder)
        holder.stdin.write(content)
        holder.stdin.close()
        holder.stdout.readline()
        b = w.launch(w.project(s), "B", [s], wait=1)
        rb, _, eb = finish(b, 60)
        check(rb == 75 and "Traceback" not in eb and "dang duoc phien khac" in eb,
              "T5c unreadable holder identity (%s): still a clean exit 75 with a message" % label, "rc=%s err=%s" % (rb, eb[-300:]))
        with contextlib.suppress(OSError):
            os.killpg(holder.pid, signal.SIGKILL)


def T6():
    """Ctrl-C on the holder releases the lock; Ctrl-C on a waiter exits promptly."""
    w = World("sigint")
    s = "RFCWA1KQT1Y"
    pa = w.project(s)
    a = w.launch(pa, "A", [s], hold=120)
    if not wait_for(lambda: w.has_event("S", "A", s)):
        finish(a)
        return fail("T6: A never reached the device")
    waiter = w.launch(w.project(s), "W", [s], wait=120)
    time.sleep(1.5)
    waiter.send_signal(signal.SIGINT)
    rw, _, ew = finish(waiter, 30)
    check(rw != 0 and rw != "TIMEOUT" and not w.has_event("S", "W"), "T6 Ctrl-C on a waiting capture ends it, device untouched", "rc=%s %s" % (rw, ew[-200:]))
    a.send_signal(signal.SIGINT)
    finish(a, 30)
    b = w.launch(w.project(s), "B", [s], hold=0.2, wait=120)
    rb, _, eb = finish(b, 100)
    check(rb == 0 and b.elapsed < 60, "T6 Ctrl-C on the holder releases the lock", "rc=%s %.1f %s" % (rb, b.elapsed, eb[-200:]))
    reap_all()


def T7():
    """The denylist decides first: a denied serial never gets (or even creates) a lock."""
    s = "RFCWA1KQT1Y"
    # (a) declared + denied + online, no AVD: the old refusal, exit 1, no lock dir content
    w = World("deny-a")
    p = w.project(s, deny=s)
    r = w.launch(p, "D", [s], env={"FAKE_AVDS": ""})
    rc, out, err = finish(r, 60)
    check(rc == 1 and "denylist" in err and out == "" and w.lock_files() == [] and not w.has_event("S", "D"),
          "T7a denied declared serial: exit 1 + denylist message, lock dir untouched, device untouched",
          "rc=%s err=%s locks=%s" % (rc, err[-200:], w.lock_files()))
    # (b) env denylist + a single online device that is denied: nothing to capture
    w = World("deny-b")
    p = w.project()
    r = w.launch(p, "D", [s], env={"ADB_DENY_SERIALS": s, "FAKE_AVDS": ""})
    rc, out, err = finish(r, 60)
    check(rc == 1 and out == "" and w.lock_files() == [] and not w.has_event("S", "D"),
          "T7b only online device is denied (ADB_DENY_SERIALS): exit 1, lock dir untouched", "rc=%s err=%s locks=%s" % (rc, err[-200:], w.lock_files()))
    # (c) denied serial with a declared AVD: boots the AVD; the DENIED serial has no lock file
    w = World("deny-c")
    p = w.project(s, avd="PhoneConnect", deny=s)
    r = w.launch(p, "D", [s])
    rc, out, err = finish(r, 90)
    names = w.lock_files()
    try:
        denied_file = os.path.basename(str(load().lock_path(__import__("pathlib").Path(w.locks), "serial", s)))
    except Exception as exc:
        denied_file = "?" + repr(exc)
    check(rc == 0 and "serial: emulator-5554" in out and denied_file not in names and not w.has_event("S", "D", s),
          "T7c denied serial + AVD: the AVD is captured, the denied serial never gets a lock file",
          "rc=%s out=%s err=%s locks=%s denied=%s" % (rc, out, err[-200:], names, denied_file))
    reap_all()


def T7d():
    """The denylist also outranks the AVD fallback: a denied emulator that already runs the AVD is never reused,
    never even asked, never locked; the AVD is booted on a port that is not denied."""
    import pathlib
    d, nxt = "emulator-5554", "emulator-5556"
    cases = (("avd only", {"avd": "PhoneConnect"}, d, nxt, [d]), ("declared serial is the denied one + avd", {"serial": d, "avd": "PhoneConnect"}, d, nxt, [d]),
             ("next port denied too (not running)", {"avd": "PhoneConnect"}, d + "," + nxt, "emulator-5558", [d]))
    for label, prov, deny, want, devices in cases:
        w = World("deny-avd-" + re.sub(r"\W", "", label)[:12])
        p = w.project(prov.get("serial"), avd=prov["avd"], deny=deny.replace(",", "\n"))
        rc, out, err = finish(w.launch(p, "R", devices), 90)
        calls = open(os.path.join(w.state, "adb.log")).read().splitlines() if os.path.exists(os.path.join(w.state, "adb.log")) else []
        touched = sorted({l.split()[1] for l in calls if l.startswith("-s ")})
        names = w.lock_files()
        denied_files = {os.path.basename(str(load().lock_path(pathlib.Path(w.locks), "serial", x))) for x in deny.split(",")}
        check(rc == 0 and out.startswith("serial: %s\n" % want) and not (set(touched) & set(deny.split(","))) and not (set(names) & denied_files),
              "T7d %s: the AVD is booted on %s, no adb call and no lock file for a denied serial" % (label, want),
              "rc=%s out=%r err=%s touched=%s locks=%d" % (rc, out, err[-200:], touched, len(names)))
    # the post-boot check itself (boot_avd mocked to hand back a denied serial): refused, no serial lock file
    w = World("deny-post")
    m = load()
    os.environ["PROOF_DEVICE_LOCK_DIR"] = w.locks
    real = m.boot_avd
    m.boot_avd = lambda *a, **k: "emulator-5554"
    try:
        args = type("A", (), {"adb": w.adb, "port": 5554, "boot_timeout": 5})()
        plan = {"action": "boot", "avd": "PhoneConnect", "devices": [], "denied": ["emulator-5554"]}
        try:
            with contextlib.ExitStack() as locks:
                m.locked_device(locks, args, plan, w.emu, True)
            refused = None
        except SystemExit as exc:
            refused = str(exc)
    finally:
        m.boot_avd = real
    denied_file = os.path.basename(str(m.lock_path(pathlib.Path(w.locks), "serial", "emulator-5554")))
    check(refused and "denylist" in refused and denied_file not in w.lock_files(),
          "T7d boot_avd handing back a denied serial: refused (denylist), no lock file for it", "refused=%r locks=%s" % (refused, w.lock_files()))
    reap_all()


def T8():
    s = "RFCWA1KQT1Y"
    w = same_serial("T8a --no-device-lock", s, args=("--no-device-lock",), expect_serialised=False)
    check(w.lock_files() == [], "T8a kill switch flag: no lock file created", w.lock_files())
    reap_all()
    w = same_serial("T8b PROOF_DEVICE_LOCK=0", s, env={"PROOF_DEVICE_LOCK": "0"}, expect_serialised=False)
    check(w.lock_files() == [], "T8b kill switch env: no lock file created", w.lock_files())
    reap_all()


def T9():
    """Odd serials: the file name is a hash, whatever the serial looks like."""
    for label, serial in (("unicode", UNIT), ("300 chars", LONG), ("dots/colons", "dev.ice-1_2:3.4")):
        w = World("odd-" + re.sub(r"\W", "", label))
        p = w.project(serial)
        rc, out, err = finish(w.launch(p, "O", [serial]), 60)
        names = w.lock_files()
        check(rc == 0 and len(names) == 1 and re.match(r"^[0-9a-f]{32}\.lock$", names[0]) and "serial: " + serial in out,
              "T9 serial %s: captured, lock file name is a plain hash" % label, "rc=%s names=%s err=%s" % (rc, names, err[-200:]))
    reap_all()


def T10():
    """A second hold of the same lock in ONE process is not supported (flock is per open file): it must be a
    bounded failure (DeviceLockBusy / exit 75), never a hang, and must not disturb the outer hold."""
    import pathlib
    w = World("nested")
    m = load()
    os.environ["PROOF_DEVICE_LOCK_DIR"] = w.locks
    probe = ("import fcntl,os,sys\nfd=os.open(sys.argv[1],os.O_RDWR)\n"
             "try:\n fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);print('free')\n"
             "except OSError:\n print('busy')\n")
    def probe_state(name="S1"):
        path = str(m.lock_path(pathlib.Path(w.locks), "serial", name))
        return subprocess.run([sys.executable, "-I", "-c", probe, path], capture_output=True, text=True, timeout=30).stdout.strip()
    t0 = time.monotonic()
    busy = False
    with m.device_lock("serial", "S1", 3):
        try:
            with m.device_lock("serial", "S1", 1):
                pass
        except m.DeviceLockBusy:
            busy = True
        inner_s = time.monotonic() - t0
        still = probe_state()
    after = probe_state()
    check(busy and inner_s < 30 and still == "busy" and after == "free",
          "T10 same-process second hold of one lock: bounded DeviceLockBusy, the outer hold survives, free after it",
          "busy=%s inner=%.1f still=%s after=%s" % (busy, inner_s, still, after))
    for exc_type, exc in ((SystemExit, SystemExit("refused")), (KeyboardInterrupt, KeyboardInterrupt()), (RuntimeError, RuntimeError("boom"))):
        try:
            with m.device_lock("serial", "S2", 3):
                raise exc
        except exc_type:
            pass
        check(probe_state("S2") == "free", "T10 lock is released when the block ends with %s" % exc_type.__name__, probe_state("S2"))
    # a whole nested main(): screencap() re-enters main() for the same serial -> the inner one exits 75, bounded
    s = "RFCWA1KQT1Y"
    proj = w.project(s)
    env_keys = {"HOME": w.home, "FAKE_STATE": w.state, "TAG": "N", "FAKE_DEVICES": s, "FAKE_HOLD": "0.1",
                "PROOF_DEVICE_LOCK_WAIT": "2", "PROOF_DEVICE_LOCK_DIR": w.locks}
    saved = {k: os.environ.get(k) for k in env_keys}
    os.environ.update(env_keys)
    argv = ["--project", proj, "--adb", w.adb, "--emulator", w.emu, "--connect-timeout", "1"]
    real, depth, inner_rc = m.screencap, [0], []
    def nested(adb, serial, dest, timeout_s):
        if depth[0] == 0:
            depth[0] = 1
            with contextlib.redirect_stdout(open(os.devnull, "w")), contextlib.redirect_stderr(open(os.devnull, "w")):
                inner_rc.append(m.main(argv))
        return real(adb, serial, dest, timeout_s)
    m.screencap = nested
    try:
        with contextlib.redirect_stdout(open(os.devnull, "w")):
            rc = m.main(argv)
    finally:
        m.screencap = real
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    check(rc == 0 and inner_rc == [75], "T10 nested main() for the same serial in one process: the inner one exits 75 (bounded), the outer succeeds", "rc=%s inner=%s" % (rc, inner_rc))
    reap_all()


def T11a():
    if os.geteuid() == 0:
        return ok("T11a skipped: root ignores directory modes")
    w = World("rodir")
    ro = os.path.join(w.root, "ro")
    os.makedirs(ro)
    os.chmod(ro, 0o500)
    w.locks = os.path.join(ro, "locks")
    s = "RFCWA1KQT1Y"
    p = w.project(s)
    rc, out, err = finish(w.launch(p, "R", [s]), 60)
    check(rc == 0 and pngs(p) and "serial: " + s in out and "khoa" in err and "khong khoa" in err,
          "T11a read-only lock dir: capture still succeeds WITHOUT the lock and warns on stderr (deliberate fail-open for the lock only)",
          "rc=%s err=%s" % (rc, err[-300:]))
    os.chmod(ro, 0o700)


def T11b():
    w = World("filedir")
    open(w.locks, "w").close()
    s = "RFCWA1KQT1Y"
    p = w.project(s)
    rc, out, err = finish(w.launch(p, "R", [s]), 60)
    check(rc == 0 and pngs(p) and "khong khoa" in err, "T11b lock dir path is a regular file: proceeds unlocked + warning", "rc=%s err=%s" % (rc, err[-300:]))


def T11c():
    w = World("symdir")
    real = os.path.join(w.root, "real-locks")
    os.makedirs(real, mode=0o700)
    os.symlink(real, w.locks)
    s = "RFCWA1KQT1Y"
    a_proj, b_proj = w.project(s), w.project(s)
    a = w.launch(a_proj, "A", [s], after_peer=True)
    if not wait_for(lambda: w.has_event("S", "A", s)):
        finish(a)
        return fail("T11c: A never reached the device")
    b = w.launch(b_proj, "B", [s], hold=0.2)
    ra, _, _ = finish(a)
    rb, _, _ = finish(b)
    n, seq, _ = w.seq(s)
    check(ra == 0 and rb == 0 and n == 0 and seq == "SESE" and len(os.listdir(real)) == 1,
          "T11c symlinked lock dir (dotfile managers) is followed and still serialises", "n=%s seq=%s files=%s" % (n, seq, os.listdir(real)))
    reap_all()


def T11d():
    w = World("symworld")
    evil = os.path.join(w.root, "worldwritable")
    os.makedirs(evil)
    os.chmod(evil, 0o777)
    os.symlink(evil, w.locks)
    s = "RFCWA1KQT1Y"
    p = w.project(s)
    rc, out, err = finish(w.launch(p, "R", [s]), 60)
    check(rc == 0 and pngs(p) and os.listdir(evil) == [] and "khong khoa" in err,
          "T11d lock dir writable by others (files could be swapped): not trusted, proceeds unlocked + warning, nothing created there",
          "rc=%s files=%s err=%s" % (rc, os.listdir(evil), err[-300:]))


def T11e():
    w = World("symfile")
    os.makedirs(w.locks, mode=0o700)
    s = "RFCWA1KQT1Y"
    victim = os.path.join(w.root, "victim.txt")
    with open(victim, "w") as f:
        f.write("precious")
    os.symlink(victim, os.path.join(w.locks, os.path.basename(str(load().lock_path(__import__("pathlib").Path(w.locks), "serial", s)))))
    p = w.project(s)
    rc, out, err = finish(w.launch(p, "R", [s]), 60)
    check(rc == 0 and pngs(p) and open(victim).read() == "precious" and "khong khoa" in err,
          "T11e lock file is a symlink: never followed (victim file untouched), proceeds unlocked + warning", "rc=%s err=%s" % (rc, err[-300:]))


def T11i():
    w = World("hardlink")
    os.makedirs(w.locks, mode=0o700)
    s = "RFCWA1KQT1Y"
    victim = os.path.join(w.root, "victim.txt")
    with open(victim, "w") as f:
        f.write("precious")
    os.link(victim, str(load().lock_path(__import__("pathlib").Path(w.locks), "serial", s)))
    p = w.project(s)
    rc, out, err = finish(w.launch(p, "R", [s]), 60)
    check(rc == 0 and pngs(p) and open(victim).read() == "precious" and "khong khoa" in err,
          "T11i lock file with a second hard link: not used (the other name is never truncated), proceeds unlocked + warning", "rc=%s err=%s" % (rc, err[-300:]))


def T11f():
    w = World("fifo")
    os.makedirs(w.locks, mode=0o700)
    s = "RFCWA1KQT1Y"
    os.mkfifo(os.path.join(w.locks, os.path.basename(str(load().lock_path(__import__("pathlib").Path(w.locks), "serial", s)))))
    p = w.project(s)
    rc, out, err = finish(w.launch(p, "R", [s]), 40)
    check(rc == 0 and pngs(p) and "khong khoa" in err, "T11f lock file is a FIFO: no hang, proceeds unlocked + warning", "rc=%s err=%s" % (rc, err[-300:]))


def T11g():
    """Eight captures race to create the (nested, not yet existing) lock dir."""
    w = World("race")
    w.locks = os.path.join(w.root, "a", "b", "locks")
    serials = ["RACE%d" % i for i in range(8)]
    ps = [w.launch(w.project(s), "R%d" % i, serials, hold=0.1) for i, s in enumerate(serials)]
    rcs = [finish(p, 100)[0] for p in ps]
    mode = stat.S_IMODE(os.stat(w.locks).st_mode) if os.path.isdir(w.locks) else None
    names = w.lock_files()
    fmodes = {stat.S_IMODE(os.stat(os.path.join(w.locks, n)).st_mode) for n in names}
    check(rcs == [0] * 8 and len(names) == 8 and mode == 0o700 and fmodes == {0o600},
          "T11g eight racing creators of the lock dir all succeed; dir 0700, 8 lock files 0600", "rcs=%s mode=%s names=%d fmodes=%s" % (rcs, oct(mode or 0), len(names), fmodes))
    reap_all()


def T11h():
    """TMPDIR is irrelevant (unset or bogus); with no override the dir lives under HOME/.config."""
    s = "RFCWA1KQT1Y"
    w = World("tmpdir")
    pa, pb = w.project(s), w.project(s)
    a = w.launch(pa, "A", [s], after_peer=True, drop=("TMPDIR",))
    if not wait_for(lambda: w.has_event("S", "A", s)):
        finish(a)
        return fail("T11h: A never reached the device")
    b = w.launch(pb, "B", [s], hold=0.2, env={"TMPDIR": "/nonexistent/odd tmp"})
    ra, _, _ = finish(a)
    rb, _, _ = finish(b)
    n, seq, _ = w.seq(s)
    check(ra == 0 and rb == 0 and n == 0 and seq == "SESE", "T11h TMPDIR unset in one capture and bogus in the other: still one lock, serialised", "n=%s seq=%s" % (n, seq))
    reap_all()
    w = World("homedir")
    p = w.project(s)
    rc, out, err = finish(w.launch(p, "H", [s], override=False), 60)
    d = os.path.join(w.home, ".config", "universal-agent-devkit", "device-locks")
    check(rc == 0 and os.path.isdir(d) and stat.S_IMODE(os.stat(d).st_mode) == 0o700 and len(os.listdir(d)) == 1 and err == "",
          "T11h default lock dir is $HOME/.config/universal-agent-devkit/device-locks (0700), no stderr noise",
          "rc=%s dir=%s err=%s" % (rc, os.path.isdir(d), err[-200:]))
    w = World("homefile")
    homefile = os.path.join(w.root, "homefile")
    open(homefile, "w").close()
    p = w.project(s)
    rc, out, err = finish(w.launch(p, "H", [s], override=False, env={"HOME": homefile}), 60)
    check(rc == 0 and pngs(p) and "khong khoa" in err, "T11h unusable HOME: proceeds unlocked + warning, no crash", "rc=%s err=%s" % (rc, err[-300:]))
    reap_all()


def T12():
    """No contention: stdout/stderr/exit are exactly what the tool printed before the lock existed (this same
    assertion passes on the pristine dadd7be binary: `PROOF_CAPTURE_CMD=<pristine copy>`)."""
    s = "RFCWA1KQT1Y"
    w = World("same-out")
    p = w.project(s)
    rc, out, err = finish(w.launch(p, "X", [s], hold=0.1), 60)
    want = "serial: %s\nfile: %s/reports/proof-" % (s, os.path.realpath(p))
    check(rc == 0 and out.startswith(want) and re.fullmatch(r"\d{8}-\d{6}\.png\n", out[len(want):]) and err == "",
          "T12 uncontended run: exactly `serial:`/`file:` on stdout, nothing on stderr, exit 0 (the pre-lock contract)", "rc=%s out=%r err=%r" % (rc, out, err))
    reap_all()


def T13():
    """Two captures that both have to boot the same AVD: the second must find it booted, not start another."""
    w = World("boot")
    pa, pb = w.project(avd="PhoneConnect"), w.project(avd="PhoneConnect")
    a = w.launch(pa, "A", [])
    if not wait_for(lambda: os.path.exists(os.path.join(w.state, "emu-starts"))):
        finish(a)
        return fail("T13: the first capture never started the emulator")
    b = w.launch(pb, "B", [])
    ra, oa, ea = finish(a, 120)
    rb, ob, eb = finish(b, 120)
    starts = len(open(os.path.join(w.state, "emu-starts")).read().split())
    n, seq, _ = w.seq("emulator-5554")
    check(ra == 0 and rb == 0 and starts == 1 and n == 0 and pngs(pa) and pngs(pb),
          "T13 same AVD booted once; the second capture waits, re-reads adb devices and uses it (serialised on emulator-5554)",
          "rcs=%s,%s starts=%d overlaps=%s order=%s a=%s b=%s" % (ra, rb, starts, n, seq, ea[-200:], eb[-200:]))
    reap_all()


def T13b():
    """The device list a capture resolved can be stale WITHOUT it ever waiting: B resolved before the emulator
    existed, A booted and finished, B then takes the free AVD lock. It must re-read adb devices, not boot twice."""
    w = World("boot-stale")
    pa, pb = w.project(avd="PhoneConnect"), w.project(avd="PhoneConnect")
    a = w.launch(pa, "A", [])
    if not wait_for(lambda: os.path.exists(os.path.join(w.state, "emu-starts"))):
        finish(a)
        return fail("T13b: the first capture never started the emulator")
    done = os.path.join(w.state, "a-done")
    b = w.launch(pb, "B", [], env={"FAKE_STALE_FIRST_DEVICES": "1", "FAKE_STALE_WAIT_FILE": done})
    ra, _, ea = finish(a, 120)
    open(done, "w").close()
    rb, ob, eb = finish(b, 120)
    starts = len(open(os.path.join(w.state, "emu-starts")).read().split())
    check(ra == 0 and rb == 0 and starts == 1 and "Cho khoa" not in eb and pngs(pb),
          "T13b B never waited, yet used the emulator A booted (adb devices re-read after the AVD lock): one emulator start",
          "rcs=%s,%s starts=%d b=%s" % (ra, rb, starts, eb[-300:]))
    reap_all()


def T17():
    """One wait budget over both locks (AVD, then serial): time spent on the first is not given again to the second."""
    import pathlib
    import select
    w = World("budget")
    os.makedirs(w.locks, mode=0o700)
    m = load()
    code = ("import fcntl,os,sys,time\nfd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT,0o600)\nfcntl.flock(fd,fcntl.LOCK_EX)\n"
            "print('held',flush=True)\ntime.sleep(120)")
    holders = []
    for key in (("avd", "PhoneConnect"), ("serial", "emulator-5554")):
        h = subprocess.Popen([sys.executable, "-I", "-c", code, str(m.lock_path(pathlib.Path(w.locks), *key))],
                             stdout=subprocess.PIPE, text=True, start_new_session=True)
        PROCS.append(h)
        h.stdout.readline()
        holders.append(h)
    open(os.path.join(w.state, "booted"), "w").close()   # the emulator is up: boot_avd will just return it
    b = w.launch(w.project(avd="PhoneConnect"), "B", [], wait=8, env={"FAKE_STALE_FIRST_DEVICES": "1"})
    lines, end = [], time.monotonic() + 40
    while time.monotonic() < end and not any("AVD PhoneConnect" in l for l in lines):
        if select.select([b.stderr], [], [], 1.0)[0]:
            ln = b.stderr.readline()
            if not ln:
                break
            lines.append(ln)
    time.sleep(2.5)                       # B has now waited at least 2.5 s on the AVD lock
    os.killpg(holders[0].pid, signal.SIGKILL)
    rest = b.stderr.read()
    rb = b.wait(timeout=60)
    text = "".join(lines) + rest
    mm = re.findall(r"serial emulator-5554: .*?Cho toi da (\d+) giay", text)
    check(rb == 75 and len(mm) == 1 and 1 <= int(mm[0]) <= 6,
          "T17 after 2.5 s spent on the AVD lock only the rest of the 8 s budget is left for the serial lock (not 8 again)",
          "rc=%s announced=%s text=%s" % (rb, mm, text[-500:]))
    reap_all()


def T15():
    """Providers that are not adb (a shell command here) never touch the device lock."""
    w = World("shellprov")
    p = os.path.join(w.root, "shellproj")
    os.makedirs(p)
    import json
    cmd = "cp %s {{out}}" % os.path.join(w.state, "shot.png")
    with open(os.path.join(p, ".antigravity-pm.json"), "w") as f:
        json.dump({"proof": {"defaultProvider": "g", "providers": {"g": {"type": "shell", "command": cmd}}}}, f)
    rc, out, err = finish(w.launch(p, "SH", []), 60)
    check(rc == 0 and pngs(p) and not os.path.exists(w.locks) and "Canh bao" not in err,
          "T15 shell provider: captured, lock dir never created", "rc=%s err=%s" % (rc, err[-200:]))


def T16():
    """Every way out of a capture releases the lock: refused screen, bad PNG, AVD that never boots."""
    import pathlib
    probe = ("import fcntl,os,sys\nfd=os.open(sys.argv[1],os.O_RDWR)\n"
             "try:\n fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);print('free')\n"
             "except OSError:\n print('busy')\n")
    s = "RFCWA1KQT1Y"
    for label, env, serial, avd, key in (("screen asleep", {"FAKE_WAKE": "Asleep"}, s, None, ("serial", s)),
                                         ("not a PNG", {"FAKE_BADPNG": "1"}, s, None, ("serial", s)),
                                         ("AVD never boots", {"FAKE_NOBOOT": "1"}, None, "PhoneConnect", ("avd", "PhoneConnect"))):
        w = World("exit-" + label.replace(" ", ""))
        p = w.project(serial, avd=avd)
        rc, out, err = finish(w.launch(p, "X", [s] if serial else [], env=env, args=("--boot-timeout", "2") if avd else ()), 90)
        path = str(load().lock_path(pathlib.Path(w.locks), *key))
        state = subprocess.run([sys.executable, "-I", "-c", probe, path], capture_output=True, text=True, timeout=30).stdout.strip() if os.path.exists(path) else "no lock file"
        check(rc == 1 and state == "free", "T16 capture that ends in a refusal (%s): exit 1 and the lock is free again" % label,
              "rc=%s lock=%s err=%s" % (rc, state, err[-200:]))
    reap_all()


def T14():
    m = load()
    saved = os.environ.get("PROOF_DEVICE_LOCK_WAIT"), os.environ.get("PROOF_DEVICE_LOCK")
    try:
        got = {}
        for raw in ("", "abc", "nan", "inf", "-5", "1e999", "7", "0", "2.5", "999999"):
            os.environ["PROOF_DEVICE_LOCK_WAIT"] = raw
            got[raw] = m.lock_wait_seconds()
        os.environ.pop("PROOF_DEVICE_LOCK_WAIT")
        got["unset"] = m.lock_wait_seconds()
        check(got["unset"] == 300 and got[""] == 300 and got["abc"] == 300 and got["nan"] == 300 and got["inf"] == 300
              and got["-5"] == 300 and got["1e999"] == 300 and got["7"] == 7 and got["0"] == 0 and got["2.5"] == 2.5
              and 0 < got["999999"] <= 3600,
              "T14 PROOF_DEVICE_LOCK_WAIT: default 300 s; garbage/nan/inf/negative fall back to it; capped at 3600 s", got)
        res = {}
        for raw in ("0", "off", "FALSE", "no", " 0 ", "1", "yes", ""):
            os.environ["PROOF_DEVICE_LOCK"] = raw
            res[raw] = m.device_lock_enabled(False)
        os.environ.pop("PROOF_DEVICE_LOCK")
        check(res["0"] is False and res["off"] is False and res["FALSE"] is False and res["no"] is False and res[" 0 "] is False
              and res["1"] is True and res["yes"] is True and res[""] is True and m.device_lock_enabled(False) is True
              and m.device_lock_enabled(True) is False,
              "T14 PROOF_DEVICE_LOCK=0/off/false/no (and --no-device-lock) disable; anything else leaves it on", res)
    finally:
        for k, v in zip(("PROOF_DEVICE_LOCK_WAIT", "PROOF_DEVICE_LOCK"), saved):
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v




CASES = [("T1", T1), ("T1b", T1b), ("T2", T2), ("T3", T3), ("T4", T4), ("T4b", T4b), ("T5", T5), ("T5b", T5b), ("T5c", T5c), ("T6", T6), ("T7", T7), ("T7d", T7d),
         ("T8", T8), ("T9", T9), ("T10", T10), ("T11a", T11a), ("T11b", T11b), ("T11c", T11c), ("T11d", T11d),
         ("T11e", T11e), ("T11f", T11f), ("T11i", T11i), ("T11g", T11g), ("T11h", T11h), ("T12", T12), ("T13", T13), ("T13b", T13b), ("T14", T14), ("T15", T15), ("T16", T16), ("T17", T17)]
try:
    for cid, fn in CASES:
        if ONLY and ("=" + cid) not in ONLY and (cid.rstrip("abcdefgh") not in ONLY or any(x.startswith("=") for x in ONLY)) and cid not in ONLY:
            continue
        try:
            fn()
        except Exception as exc:  # a broken case is a red case, never a crash of the whole file
            import traceback
            fail("%s raised %r %s" % (cid, exc, traceback.format_exc().splitlines()[-3:]))
        finally:
            reap_all()
finally:
    reap_all()
print(("%d failed" % len(FAILS)) if FAILS else "ok")
sys.exit(1 if FAILS else 0)
PY
rc=$?
[ "$rc" = 0 ] && echo "✅ test_proof_capture_lock: all passed" || { echo "❌ test_proof_capture_lock: failed"; exit 1; }
