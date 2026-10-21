#!/usr/bin/env bash
# Regression test (issues-bugs A.4, workflow-improvements II.A item 3 #8): a FIFO planted at a state file an agent can write made a
# plain open() block for ever — a read, or a write-open with no reader. A Stop hook killed by its timeout lets the Stop through,
# so a hang is also a bypass. Every reader/writer below must come back within FIFO_BOUND seconds and treat the FIFO as
# "no usable state" (the verdict an absent file gives), never crash and never hang:
#   bin/post-fix-gate.py   cached_full_pass (receipt), write_full_pass_receipt (receipt read of a partial run), check_anti_false_green
#                          (proof-sha-cache.json), acquire_test_run_lock (test_run.lock, opened for append), split_user_approved
#                          (a *.jsonl in a transcript folder), run_proof_block (an image in a proof folder), and the real CLI with a
#                          FIFO at every one of its state files (receipt, caches, lock, last_report.md, last_output.log)
#   hooks/proof_gate.sh    .claude/audit-gate/.gitignore (bash redirect), proof_gate.log, proof_gate.state, turn_class_<sid>.json,
#                          the receipt, a reports/*.png compared as a byte twin
#   bin/push_gate.py       the receipt
# Each case runs in its own process group (a hang in one never hides another), all at once, killed at the bound.
#   FIFO_KIT=<devkit dir>  test another copy of the kit (the unfixed one: RED)     FIFO_BOUND=<s>  bound per case (default 20; CLI 120)
# bash 3.2 compatible; python3 stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${FIFO_KIT:-$DEVKIT_DIR}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
python3 -I - "$KIT" "$TMP" <<'PYEND'
import datetime, json, os, signal, stat, struct, subprocess, sys, time, zlib

KIT, TMP = sys.argv[1], sys.argv[2]
PY = sys.executable
GATE = os.path.join(KIT, "bin", "post-fix-gate.py")
HOOK = os.path.join(KIT, "hooks", "proof_gate.sh")
PUSH = os.path.join(KIT, "bin", "push_gate.py")
BOUND = float(os.environ.get("FIFO_BOUND") or 20)
CLI_BOUND = max(BOUND, 120.0)
HOME = os.path.join(TMP, "home")   # never the real ~/.claude/projects or ~/.gemini
os.makedirs(HOME)
fails = 0


def ok(msg):
    print("✔ " + msg, flush=True)


def bad(msg):
    global fails
    fails += 1
    print("✖ " + msg, flush=True)


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=60).stdout.decode("utf-8", "replace").strip()


def put(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def fifo(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    os.mkfifo(path)


def is_fifo(path):
    try:
        return stat.S_ISFIFO(os.lstat(path).st_mode)
    except OSError:
        return False


MATRIX = {"project": "t", "rules": [{"component": "Core", "watch_files": ["src/*"],
                                     "mandatory_regression_tests": [{"id": "REG-1", "name": "core", "command": "sh ok.sh"}]}]}


def make_repo(name, profile="android"):
    """A committed repo with a matrix (gate + push_gate path), then src/Core.kt edited."""
    root = os.path.join(TMP, name, "repo")
    os.makedirs(root)
    git(root, "init", "-q", ".")
    git(root, "config", "user.email", "t@t")
    git(root, "config", "user.name", "t")
    put(root + "/src/Core.kt", "fun ok() = 1\n")
    put(root + "/ok.sh", "exit 0\n")
    put(root + "/.gitignore", ".claude/audit-gate/\n")
    put(root + "/.agents/active-profile.json", json.dumps({"profile": profile}))
    put(root + "/.agents/regression_matrix.active.json", json.dumps(MATRIX))
    git(root, "add", "-A")
    git(root, "commit", "-qm", "init")
    put(root + "/src/Core.kt", "fun ok() = 2\n")
    return root


def receipt(root):
    return os.path.join(git(root, "rev-parse", "--absolute-git-dir"), "postfix-gate", "full_pass.json")


def env_for(root, extra=None):
    drop = ("CI", "POSTFIX_GATE_FULL", "POSTFIX_GATE_FORCE_FULL", "DEVKIT_GATE_CACHE", "DEVKIT_SESSION_ID", "CLAUDE_CODE_SESSION_ID",
            "CLAUDE_SESSION_ID", "GATE_TOTAL_BUDGET_S", "TEST_RUN_LOCK_WAIT_S", "FLAKY_RETRY", "DEVKIT_TRANSCRIPTS_DIR",
            "PROOF_GATE", "PROOF_BEFORE", "DEVKIT_AUTO_APPROVE_TESTS")
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") and k not in drop}
    env.update({"CLAUDE_PROJECT_DIR": root, "HOME": HOME, "DEVKIT_LANG": "en", "VACUITY_REVERT": "0", "FLAKY_RETRY": "0",
                "TEST_RUN_LOCK_WAIT_S": "2"})
    env.update(extra or {})
    return env


# One process per case, imported the way the other gate tests do (by path); prints one JSON line.
PROBE = os.path.join(TMP, "probe.py")
put(PROBE, r'''import importlib.util, json, os, stat, sys
kit, case, root = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("pfg", os.path.join(kit, "bin", "post-fix-gate.py"))
pfg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pfg)
if case == "cached_full_pass":
    out = pfg.cached_full_pass(root, os.path.join(root, ".agents", "regression_matrix.active.json"))
elif case == "write_receipt":
    pfg.write_full_pass_receipt(root, 2, partial=True, tests=[])
    out = "returned"
elif case == "sha_cache":
    out = list(pfg.check_anti_false_green(False))[:2]
elif case == "lock":
    fh, held = pfg.acquire_test_run_lock(root)
    out = [fh is None, held]
elif case == "approval":
    out = list(pfg.split_user_approved(["ok.sh"], None))
elif case == "proof_block":
    out = list(pfg.run_proof_block([]))
print(json.dumps({"out": out}, default=str))
''')

cases = []   # [label, Popen, deadline, check(rc, out, err) -> (good, detail)]


def start(label, cmd, root, check, env_extra=None, stdin=None, bound=None):
    p = subprocess.Popen(cmd, cwd=root, env=env_for(root, env_extra), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, start_new_session=True)
    if stdin is not None:
        try:
            p.stdin.write(stdin)
        except BrokenPipeError:
            pass
    p.stdin.close()
    cases.append([label, p, time.monotonic() + (bound or BOUND), check])


def probe(case, root, check, env_extra=None):
    start("gate %s" % case, [PY, "-I", PROBE, KIT, case, root], root, check, env_extra)


def out_of(stdout):
    lines = [l for l in stdout.decode("utf-8", "replace").splitlines() if l.startswith('{"out"')]
    return json.loads(lines[-1])["out"] if lines else "<no result line>"


# ── bin/post-fix-gate.py, one function per case ─────────────────────────────────────────────────────────────────────────────
r = make_repo("cached")
fifo(receipt(r))
probe("cached_full_pass", r, lambda rc, o, e: (rc == 0 and out_of(o) is None, "receipt FIFO -> no reusable PASS (None)"))

r = make_repo("partial")
fifo(receipt(r))
RECEIPT_PARTIAL = receipt(r)
probe("write_receipt", r, lambda rc, o, e: (rc == 0 and out_of(o) == "returned" and not is_fifo(RECEIPT_PARTIAL),
                                            "partial run, receipt FIFO -> dropped like a receipt of other code"))

r = make_repo("shacache")
fifo(os.path.join(r, ".git", "postfix-gate", "proof-sha-cache.json"))
probe("sha_cache", r, lambda rc, o, e: (rc == 0 and out_of(o) == [True, []], "proof-sha-cache FIFO -> cold cache, no finding"))

r = make_repo("lock")
fifo(os.path.join(r, ".claude", "audit-gate", "test_run.lock"))
put(r + "/.claude/audit-gate/.gitignore", "*\n")
probe("lock", r, lambda rc, o, e: (rc == 0 and out_of(o) == [True, True], "test_run.lock FIFO -> (None, True): runs unlocked, as an unmakeable lock"))

r = make_repo("approval")
tx = os.path.join(TMP, "approval", "transcripts")
time.sleep(0.05)
fifo(os.path.join(tx, "planted.jsonl"))   # newer than ok.sh: a candidate transcript
probe("approval", r, lambda rc, o, e: (rc == 0 and out_of(o) == [["ok.sh"], []], "transcript *.jsonl FIFO -> skipped, test stays unapproved"),
      {"DEVKIT_TRANSCRIPTS_DIR": tx})

r = make_repo("proofblock")
fifo(os.path.join(r, "reports", "proof-20260101-000000.png"))   # fresh mtime, in a proof folder
probe("proof_block", r, lambda rc, o, e: (rc == 0 and out_of(o) == [True, []], "proof-folder image FIFO -> skipped, no finding"))

# ── the real gate CLI: a FIFO at every state file of one run; same exit code as the same run with none of them ─────────────────
def cli(name, plant):
    root = make_repo(name)
    if plant:
        gd = os.path.join(root, ".git", "postfix-gate")
        for n in ("full_pass.json", "proof-sha-cache.json", "proof-hash-cache.json", "last_report.md", "last_output.log"):
            fifo(os.path.join(gd, n))
        fifo(os.path.join(root, ".claude", "audit-gate", "test_run.lock"))
        put(root + "/.claude/audit-gate/.gitignore", "*\n")
    start("gate CLI%s" % (" (FIFOs planted)" if plant else " (control, no FIFO)"),
          [PY, GATE, "--run-tests", "--full", "--brief", "--no-checklist", "--lang", "en",
           "--matrix", os.path.join(root, ".agents", "regression_matrix.active.json")], root,
          (lambda rc, o, e: (rc is not None and b"Traceback" not in o + e, "finished, no traceback (rc %s)" % rc)), bound=CLI_BOUND)
    return cases[-1]


cli_fifo, cli_ctrl = cli("cli", True), cli("cli-ctrl", False)

# ── hooks/proof_gate.sh ───────────────────────────────────────────────────────────────────────────────────────────────────────
REPORT = "\n1. Đã fix: X\n2. Chặn bug cũ: Y\n3. Nguy cơ bug mới: Z\n4. An toàn mã nguồn: ok"


def png(path, size=20000):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", os.urandom(size)) + chunk(b"IEND", b""))


def stop(label, root, reply, check):
    tr = os.path.join(os.path.dirname(root), "transcript.jsonl")
    t = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=5)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    put(tr, json.dumps({"type": "user", "timestamp": t, "message": {"role": "user", "content": "fix X"}}) + "\n")
    payload = json.dumps({"session_id": "s-fifo", "hook_event_name": "Stop", "transcript_path": tr,
                          "last_assistant_message": reply + REPORT, "stop_hook_active": False}).encode()
    start("proof_gate " + label, ["bash", HOOK], root, check, stdin=payload)


AUDIT = lambda root, n: os.path.join(root, ".claude", "audit-gate", n)

r = make_repo("pg-gitignore")
fifo(AUDIT(r, ".gitignore"))
stop(".gitignore FIFO", r, "CHƯA XONG", lambda rc, o, e: (rc == 0, "not XONG -> allowed (exit 0)"))

for label, name in (("proof_gate.log FIFO", "proof_gate.log"), ("proof_gate.state FIFO", "proof_gate.state"),
                    ("turn_class FIFO", "turn_class_s-fifo.json")):
    r = make_repo("pg-" + name.replace(".", "-").replace("_", "-"))
    put(AUDIT(r, ".gitignore"), "*\n")
    fifo(AUDIT(r, name))
    stop(label, r, "XONG", lambda rc, o, e: (rc == 2, "XONG without a gate receipt -> still blocked (exit 2)"))

r = make_repo("pg-receipt")
fifo(receipt(r))
stop("receipt FIFO", r, "XONG", lambda rc, o, e: (rc == 2 and b"exit 0" in e, "receipt FIFO -> no exit 0 -> blocked (exit 2)"))

r = make_repo("pg-twin")
stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
png(os.path.join(r, "reports", "proof-%s.png" % stamp))
fifo(os.path.join(r, "reports", "zz-planted.png"))
stop("reports/*.png twin FIFO", r, "XONG\nreports/proof-%s.png" % stamp,
     lambda rc, o, e: (rc == 2 and "ẢNH".encode() not in e and b"exit 0" in e,
                       "FIFO is no twin: the cited PNG is accepted, blocked only for the missing receipt"))

# ── bin/push_gate.py ──────────────────────────────────────────────────────────────────────────────────────────────────────────
r = make_repo("push")
fifo(receipt(r))
start("push_gate receipt FIFO", [PY, PUSH, r], r, lambda rc, o, e: (rc == 2, "no usable receipt -> push refused (exit 2)"))

# ── collect: every case bounded, its process group killed on the bound ─────────────────────────────────────────────────────────
results = {}
for label, p, deadline, check in cases:
    try:
        out, err = p.communicate(timeout=max(deadline - time.monotonic(), 0.1))
        rc = p.returncode
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, err = p.communicate()
        rc = None
    results[label] = rc
    if rc is None:
        bad("%s: HUNG (killed after the bound)" % label)
        continue
    good, what = check(rc, out, err)
    if good:
        ok("%s: %s" % (label, what))
    else:
        tail = (out + err).decode("utf-8", "replace").strip().splitlines()[-6:]
        bad("%s: expected %s; rc %s — %s" % (label, what, rc, " | ".join(tail)))

a, b = results[cli_fifo[0]], results[cli_ctrl[0]]
if a is not None and b is not None:
    if a == b:
        ok("gate CLI: the run with FIFOs exits like the run without them (%s)" % a)
    else:
        bad("gate CLI: exit %s with FIFOs planted, %s without" % (a, b))

print("\nstate FIFO no hang: %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
sys.exit(1 if fails else 0)
PYEND
