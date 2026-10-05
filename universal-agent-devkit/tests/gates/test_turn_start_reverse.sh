#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test_turn_start_reverse.sh — devkit_harness.turn_start looks in the TAIL of the transcript.
#
# Every Stop hook asks "when did this turn start?" (the last real user prompt). The answer used to come
# from a forward scan of the WHOLE transcript (84 MiB = ~90 ms, per hook, per stop). The last prompt is
# near the end: turn_start now reads the last _TAIL_BYTES once and, if the prompt is not there (a very long
# turn, or none at all), the untouched forward scan answers. The answer must stay the one the forward scan
# gave (one deliberate exception, B), so this holds:
#   A. the I/O bound itself: on a 60 MB transcript turn_start reads the tail in a few reads, not the file.
#      Bytes and read() calls are counted at the file-descriptor level, so they do not depend on the load
#      of the machine; a loose wall-clock margin (3x, best of 5) is only a sanity check on top and can
#      still be disturbed by a very busy machine;
#   B. equality with the forward scan (a copy of the old function lives in this test) on generated
#      transcripts: every prompt/notification/meta/tool-result shape, CRLF, lone CR, mixed endings, no
#      final newline, a truncated last line, blank lines, invalid UTF-8, BOM, NUL, bad JSON, bad or
#      non-string timestamps, out-of-order timestamps, no prompt at all, an empty, missing or directory
#      path, with tails of 16..4096 bytes, and EVERY tail size from 1 byte to the file size on small
#      CR/CRLF/mixed files (a line, a CRLF or a lone CR cut by the window edge at every offset).
#      THE DELIBERATE EXCEPTION: a malformed user line (message not an object) BEFORE the last prompt
#      crashed the old scan (AttributeError, and a hook crash is exit 0 = nothing checked); the tail read
#      never reaches it and returns the right answer. One AFTER the last prompt is met by both: same
#      exception;
#   C. the live fallback: the last prompt farther back than the tail (a 3 MB turn), and a session with
#      only peer messages (no human prompt), still answer as the forward scan does; a huge line before
#      the prompt is not read;
#   D. the hook decisions that read the boundary through proof_gate.sh: a push of this turn blocks, a push
#      before the turn does not, a compaction summary stamped before the pushes still counts them (the old
#      scan counted every line with t >= the summary's stamp), CRLF, a truncated last line, a huge line;
#   E. XONG when start is None (no human prompt: a session fed only by peer messages, or no transcript).
#      The receipt must be younger than 1 h and match the code, whatever Claude Code appends after the
#      gate ran (tool_result, reply, Stop-hook feedback, an image Read, a skill load, a task-notification):
#      it cannot be compared with the transcript, which always grows after the receipt. Before: NameError on
#      `tp`/`time` -> python exit 1 -> the shell wrapper's exit 0 = the XONG went through unchecked;
#   F. the loop guard of a session with no turn start: [block, block, release] per HOUR, the state key is
#      `<session>@h<bucket>`, never the constant `<session>@0` (one budget spent once, then every later
#      XONG passed); with a turn start the key is unchanged (per turn);
#   G. a receipt of the wrong shape ([1], "x", 7, time null / "later" / NaN / Infinity / true) crashed the
#      hook (exit 0 = allowed); it is "receipt hỏng" and blocks.
# Usage: bash tests/gates/test_turn_start_reverse.sh   Exit 0 = all hold. bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/turnrev.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

python3 - "$DEVKIT_DIR/hooks" "$TMP" <<'PY'
import builtins, datetime, io, json, os, random, subprocess, sys, time

hooks, tmp = sys.argv[1], sys.argv[2]
sys.dont_write_bytecode = True
sys.path.insert(0, hooks)
import devkit_harness as H

FAILS = 0
def check(cond, msg, detail=""):
    global FAILS
    if cond:
        print("✔ " + msg)
    else:
        FAILS += 1
        print("✖ " + msg + ((" :: " + detail) if detail else ""))

def ref_turn_start(tp):
    """The forward scan every hook ran before turn_start read backwards (verbatim)."""
    last = None
    try:
        with open(tp, encoding="utf-8", errors="replace") as f:
            for raw in f:
                if '"user"' not in raw:
                    continue
                try:
                    e = json.loads(raw)
                except ValueError:
                    continue
                if H.is_user_prompt(e) and e.get("timestamp"):
                    last = e["timestamp"]
    except OSError:
        return None
    try:
        return datetime.datetime.fromisoformat(last.replace("Z", "+00:00")).timestamp() if last else None
    except ValueError:
        return None

def tolerant_turn_start(tp):
    """What the old scan MEANS (the last real prompt) with a malformed line skipped instead of crashing it."""
    last = None
    try:
        with open(tp, encoding="utf-8", errors="replace") as f:
            for raw in f:
                if '"user"' not in raw:
                    continue
                try:
                    e = json.loads(raw)
                    if H.is_user_prompt(e) and e.get("timestamp"):
                        last = e["timestamp"]
                except Exception:  # noqa: BLE001
                    continue
    except OSError:
        return None
    try:
        return datetime.datetime.fromisoformat(last.replace("Z", "+00:00")).timestamp() if last else None
    except ValueError:
        return None

def outcome(fn, path):
    try:
        return ("ok", fn(path))
    except Exception as e:  # noqa: BLE001 — an exception is part of the contract being compared
        return ("raise", type(e).__name__)

# ── a counting open(): bytes that really come from the file descriptor ──────────────────────
class CountRaw(io.RawIOBase):
    def __init__(self, raw, box):
        self.raw, self.box = raw, box
    def readable(self): return True
    def seekable(self): return self.raw.seekable()
    def readinto(self, b):
        n = self.raw.readinto(b)
        self.box[0] += n or 0
        self.box[1] += 1
        return n
    def seek(self, off, whence=0): return self.raw.seek(off, whence)
    def tell(self): return self.raw.tell()
    def fileno(self): return self.raw.fileno()
    def close(self):
        self.raw.close()
        super().close()

def bytes_read(fn, path):
    box = [0, 0]      # bytes, read() calls on the descriptor (the last count is bytes_read.calls)
    real = builtins.open
    def counting(p, mode="r", buffering=-1, encoding=None, errors=None, newline=None, **kw):
        buf = io.BufferedReader(CountRaw(io.FileIO(p, "r"), box), 8192)
        return buf if "b" in mode else io.TextIOWrapper(buf, encoding=encoding or "utf-8", errors=errors, newline=newline)
    builtins.open = counting
    try:
        result = outcome(fn, path)
    finally:
        builtins.open = real
    bytes_read.calls = box[1]
    return box[0], result

# ── transcript lines ────────────────────────────────────────────────────────────────────────
BASE = datetime.datetime(2026, 10, 4, 8, 0, 0, tzinfo=datetime.timezone.utc)
def stamp(sec):
    return (BASE + datetime.timedelta(seconds=sec)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
def jl(obj):
    return json.dumps(obj, ensure_ascii=False).encode("utf-8")
def prompt(sec, text="sửa lỗi X"):
    return jl({"type": "user", "timestamp": stamp(sec), "message": {"role": "user", "content": text}})
def assistant(sec, text="ok", cmd=None, tid="tu-1"):
    c = [{"type": "text", "text": text}] if cmd is None else [{"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": cmd}}]
    return jl({"type": "assistant", "timestamp": stamp(sec), "message": {"role": "assistant", "content": c}})
def tool_result(sec, tid="tu-1", text="done"):
    return jl({"type": "user", "timestamp": stamp(sec), "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": text}]}})

def gen_lines(rng, n, big=False):
    out, t = [], 0
    for _ in range(n):
        t += rng.choice((1, 1, 2, 5, -3))   # now and then out of order: "last in file", not "latest stamp"
        k = rng.randrange(19)
        if k == 0:   out.append(prompt(t))
        elif k == 1: out.append(jl({"type": "user", "timestamp": stamp(t), "message": {"content": [{"type": "text", "text": "list prompt"}]}}))
        elif k == 2: out.append(tool_result(t))
        elif k == 3: out.append(jl({"type": "user", "isMeta": True, "timestamp": stamp(t), "message": {"content": "meta"}}))
        elif k == 4: out.append(jl({"type": "user", "timestamp": stamp(t), "origin": {"kind": rng.choice(("task-notification", "peer", "auto-continuation", "human"))}, "message": {"content": "x"}}))
        elif k == 5: out.append(jl({"type": "user", "timestamp": stamp(t), "message": {"content": "<task-notification>done</task-notification>"}}))
        elif k == 6: out.append(assistant(t, "Tôi đã sửa xong — ✅"))
        elif k == 7: out.append(jl({"type": "user", "message": {"content": "no timestamp"}}))
        elif k == 8: out.append(jl({"type": "user", "timestamp": "not-a-date", "message": {"content": "bad stamp"}}))
        elif k == 9: out.append(b'{"type": "user", "timestamp": "' + stamp(t).encode() + b'", "message": {"content": "cut off')
        elif k == 10: out.append(b"")
        elif k == 11: out.append(b'{"type":"user","timestamp":"' + stamp(t).encode() + b'","message":{"content":"bad \xff\xfe bytes \xe2\x82"}}')
        elif k == 12: out.append(b'["user", 1, 2]')
        elif k == 13: out.append(jl({"type": "user", "timestamp": 12345 if rng.randrange(8) == 0 else stamp(t), "message": {"content": "numeric stamp"}}))
        elif k == 14: out.append(jl({"type": "system", "subtype": "compact_boundary", "timestamp": stamp(t)}))
        elif k == 15: out.append(assistant(t, "x" * (20000 if big else 30)))
        elif k == 17: out.append(jl({"type": "user", "timestamp": stamp(t), "message": rng.choice(("not an object", [1, 2], 7, True))}))
        elif k == 18:   # a message nested deeply inside a list: truthy and not an object
            nest = "x"
            for _ in range(200):
                nest = [nest]
            out.append(jl({"type": "user", "timestamp": stamp(t), "message": nest}))
        else:        out.append(jl({"type": "user", "timestamp": stamp(t), "message": {"content": "p" * (5000 if big else 3)}}))
    return out

def join(rng, lines, style):
    out = b""
    for i, ln in enumerate(lines):
        last = i == len(lines) - 1
        end = {"lf": b"\n", "crlf": b"\r\n", "cr": b"\r", "mixed": rng.choice((b"\n", b"\r\n", b"\r", b"\n\n"))}[style]
        out += ln + (b"" if last and rng.randrange(3) == 0 else end)
    if out and rng.randrange(5) == 0:
        out = out[:rng.randrange(max(len(out) - 40, 1), len(out) + 1)]   # a truncated last line
    return out

def write(name, data):
    p = os.path.join(tmp, name)
    with open(p, "wb") as f:
        f.write(data)
    return p

DEFAULT_TAIL = getattr(H, "_TAIL_BYTES", None)
def set_tail(n):
    if hasattr(H, "_TAIL_BYTES"):
        H._TAIL_BYTES = DEFAULT_TAIL if n is None else n

# ── A. the I/O bound ────────────────────────────────────────────────────────────────────────
rng = random.Random(7)
line = assistant(1, "y" * 3900)
p60 = os.path.join(tmp, "big60.jsonl")
with open(p60, "wb") as f:
    n = 0
    while f.tell() < 60 * 2**20 - 300 * 1024:
        n += 1
        f.write((prompt(n, "an older prompt") if n % 400 == 0 else line) + b"\n")
    f.write(prompt(n + 1, "the last prompt") + b"\n")
    for i in range(40):
        f.write(line + b"\n")
size = os.path.getsize(p60)
expect = ref_turn_start(p60)
got_bytes, got = bytes_read(H.turn_start, p60)
got_calls = bytes_read.calls
ref_bytes, _ = bytes_read(ref_turn_start, p60)
ref_calls = bytes_read.calls
check(ref_bytes >= size * 0.95 and ref_calls > 1000, "counter sanity: the forward scan reads the whole %d MB file (%d reads)" % (size // 2**20, ref_calls), "read %d" % ref_bytes)
check(got == ("ok", expect), "60 MB transcript: same turn start as the forward scan", repr((got, expect)))
check(got_bytes < size // 20 and got_calls < 50, "60 MB transcript: turn_start reads the tail in a few reads, not the file",
      "read %d of %d bytes in %d reads" % (got_bytes, size, got_calls))
def best(fn, runs=5):
    r = []
    for _ in range(runs):
        t0 = time.perf_counter(); fn(p60); r.append(time.perf_counter() - t0)
    return min(r)
new_t, old_t = best(H.turn_start), best(ref_turn_start)
check(new_t * 3 < old_t, "60 MB transcript: turn_start faster than the forward scan (loose sanity margin: 3x, best of 5)",
      "new %.2f ms, forward %.2f ms" % (new_t * 1000, old_t * 1000))

# ── B. equality with the forward scan ──────────────────────────────────────────────────────
rng = random.Random(20261004)
styles = ("lf", "crlf", "cr", "mixed")
bad = []
cases = deliberate = 0
def compare(pth, tail, data):
    global deliberate
    a, b = outcome(H.turn_start, pth), outcome(ref_turn_start, pth)
    if a == b:
        return
    if b[0] == "raise" and a == outcome(tolerant_turn_start, pth):
        deliberate += 1          # the old scan crashed on a malformed line before the last prompt; the answer is the right one
    else:
        bad.append((tail, a, b, data[-200:]))
for tail, count, nmax, big in ((None, 220, 40, True), (16, 60, 8, False), (64, 80, 12, False), (200, 80, 14, False),
                               (1000, 80, 14, False), (4096, 80, 20, False)):
    set_tail(tail)
    for i in range(count):
        data = join(rng, gen_lines(rng, rng.randrange(0, nmax + 1), big), styles[i % 4])
        extra = rng.randrange(8)
        if extra == 0:
            data = b"\xef\xbb\xbf" + data           # a BOM
        elif extra == 1 and data:
            k = rng.randrange(len(data)); data = data[:k] + b"\x00" + data[k:]   # a NUL byte
        pth = write("c%d.jsonl" % cases, data)
        cases += 1
        compare(pth, tail, data)
set_tail(None)
check(not bad, "%d generated transcripts (all endings, BOM, NUL, junk lines, tails of 16..4096 bytes): same answer as the forward scan" % cases,
      repr(bad[:2]))
check(deliberate > 0, "…and the generator does hit the one deliberate exception: %d transcripts where a malformed line before the last prompt "
      "crashed the old scan and turn_start returns the right answer" % deliberate)
# every window size on small files: a line, a CRLF or a lone CR cut by the window edge at every offset
bad, sweeps = [], 0
for style in ("crlf", "cr", "mixed", "lf"):
    for seed in range(6):
        data = join(random.Random(seed * 7 + len(style)), [prompt(1, "first"), assistant(2), prompt(3, "second"), assistant(4, "é" * 5), tool_result(5), assistant(6)], style)
        pth = write("sweep.jsonl", data)
        if seed == 5:
            # a valid user prompt glued behind other JSON on ONE line: the line as a whole is invalid (the forward scan
            # skips it) but a window that starts at the glued prompt would parse it, unless the cut first line is dropped
            data = join(random.Random(seed), [prompt(1, "first"), assistant(2), b'{"a": 1}' + prompt(3, "glued"), assistant(4)], style)
            pth = write("sweep.jsonl", data)
        for tail in range(1, len(data) + 3):
            set_tail(tail)
            sweeps += 1
            a, b = outcome(H.turn_start, pth), outcome(ref_turn_start, pth)
            if a != b:
                bad.append((style, seed, tail, a, b))
set_tail(None)
check(not bad, "%d (file, tail size) pairs, every window offset on CR / CRLF / mixed / LF files: same answer as the forward scan" % sweeps, repr(bad[:2]))
for what, pth in (("empty file", write("empty.jsonl", b"")), ("missing path", os.path.join(tmp, "nope.jsonl")), ("a directory", tmp),
                  ("no prompt at all", write("noprompt.jsonl", b"\n".join(assistant(i) for i in range(30)) + b"\n")),
                  ("only a bad stamp", write("badstamp.jsonl", prompt(1) + b"\n" + jl({"type": "user", "timestamp": "nope", "message": {"content": "x"}}) + b"\n"))):
    a, b = outcome(H.turn_start, pth), outcome(ref_turn_start, pth)
    check(a == b, "%s: same answer as the forward scan (%r)" % (what, a), repr((a, b)))
# bytes.splitlines must split where text mode does (\n, \r\n, a lone \r; not \v \f \x1c-\x1e or \x85)
bad = []
alphabet = [b"a", b"\n", b"\r", b"\x0b", b"\x0c", b"\x1c", b"\x1d", b"\x1e", b"\x85", b"\xc2\x85", " ".encode(), b"\xff", "é".encode()]
for _ in range(3000):
    data = b"".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 60)))
    pth = write("soup.bin", data)
    with open(pth, encoding="utf-8", errors="replace") as f:
        want = [x[:-1] if x.endswith("\n") else x for x in f]
    got = [x.decode("utf-8", "replace") for x in data.splitlines()]
    if [x for x in got if x] != [x for x in want if x]:
        bad.append((data, got, want))
check(not bad, "3000 byte soups (\\v, \\f, \\x1c-\\x1e, \\x85, U+2028, lone \\r): bytes.splitlines splits where text mode does", repr(bad[:1]))

# ── C. long lines and the live fallback ──────────────────────────────────────────────────────────
HUGE = 5 * 2**20
small = [assistant(i) for i in range(50)]
for what, lines in (("huge tool result AFTER the prompt", small + [prompt(100)] + [tool_result(101, text="z" * HUGE)] + [assistant(102)]),
                    ("huge line BEFORE the prompt", [assistant(1, "w" * HUGE)] + small + [prompt(200)] + [assistant(201), assistant(202)]),
                    ("huge prompt itself", small + [prompt(300, "q" * HUGE)] + [assistant(301)])):
    pth = write("huge.jsonl", b"\n".join(lines) + b"\n")
    a, b = outcome(H.turn_start, pth), outcome(ref_turn_start, pth)
    check(a == b and a[0] == "ok" and a[1] is not None, "%s: same answer as the forward scan" % what, repr((a, b)))
nbytes, _ = bytes_read(H.turn_start, write("huge2.jsonl", b"\n".join([assistant(1, "w" * HUGE)] + small + [prompt(200), assistant(201)]) + b"\n"))
check(nbytes <= 2 * (1 << 19), "a huge line before the prompt is not read (read %d bytes)" % nbytes)
# the last prompt farther back than the tail: the forward scan answers (and reads the file)
far = write("far.jsonl", b"\n".join([prompt(1, "early")] + [tool_result(2 + i, text="z" * 100000) for i in range(30)] + [assistant(40)]) + b"\n")
nb, got = bytes_read(H.turn_start, far)
check(got == outcome(ref_turn_start, far) and got[1] is not None and nb > 2 * (1 << 19),
      "the last prompt 3 MB from the end (beyond the tail): the live fallback finds it, as the forward scan does (read %d bytes)" % nb, repr(got))
# a session with only peer messages: no human prompt anywhere, the tail finds none, the forward scan says None
peer_only = write("peeronly.jsonl", b"\n".join([jl({"type": "user", "isMeta": True, "origin": {"kind": "peer"}, "timestamp": stamp(1), "message": {"role": "user", "content": "Another Claude session sent a message: x"}}),
                                                 assistant(2), tool_result(3), assistant(4)]) + b"\n")
check(outcome(H.turn_start, peer_only) == outcome(ref_turn_start, peer_only) == ("ok", None), "only peer messages, no human prompt: None, as the forward scan says")

# ── D. the decisions proof_gate.sh draws from the boundary ─────────────────────────────────
HOOK = os.path.join(hooks, "proof_gate.sh")
repo = os.path.join(tmp, "repo")
os.makedirs(repo)
NOW = datetime.datetime.now(datetime.timezone.utc)
def ts(sec):
    return (NOW + datetime.timedelta(seconds=sec)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
def U(sec, content="sửa lỗi X", **kw):
    d = {"type": "user", "timestamp": ts(sec), "message": {"role": "user", "content": content}}
    d.update(kw)
    return jl(d)
def A(sec, cmd, tid):
    return jl({"type": "assistant", "timestamp": ts(sec), "message": {"role": "assistant", "content": [{"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": cmd}}]}})
def R(sec, tid, text="   86f7ddc..a94c071  main -> main"):
    return jl({"type": "user", "timestamp": ts(sec), "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": text}]}})
def filler(sec, n=30):
    return [jl({"type": "assistant", "timestamp": ts(sec + i * 0.01), "message": {"role": "assistant", "content": [{"type": "text", "text": "f" * 3000}]}}) for i in range(n)]
sess = [0]
def hook(lines, eol=b"\n", tail=b"", reply="Đã push."):
    sess[0] += 1
    pth = write("hook%d.jsonl" % sess[0], eol.join(lines) + eol + tail)
    payload = json.dumps({"session_id": "s%d" % sess[0], "transcript_path": pth, "last_assistant_message": reply})
    r = subprocess.run(["bash", HOOK], input=payload, capture_output=True, text=True, timeout=60,
                       env=dict(os.environ, CLAUDE_PROJECT_DIR=repo))
    return r.returncode
PUSH = "git push origin main"
cases = [
    ("a push of this turn, after a long history: blocks (report missing)", 2,
     filler(-900) + [U(-500, "older prompt")] + filler(-499) + [U(-10), A(-9, PUSH, "p1"), R(-8, "p1")], {}),
    ("a push before this turn's prompt: not counted", 0,
     filler(-900) + [U(-500, "older prompt"), A(-499, PUSH, "p0"), R(-498, "p0")] + filler(-400) + [U(-10), A(-9, "ls", "l1"), R(-8, "l1")], {}),
    ("a compaction summary stamped before the pushes still counts them (old scan: every line with t >= stamp)", 2,
     [U(-100, "real prompt"), A(-95, PUSH, "p2"), R(-94, "p2"), jl({"type": "system", "subtype": "compact_boundary", "timestamp": ts(-90)}),
      U(-98, "This session is being continued from a previous conversation...", isCompactSummary=True)], {}),
    ("a task notification inside the turn is not its start: the push before it counts", 2,
     [U(-100), A(-95, PUSH, "p3"), R(-94, "p3"), U(-60, "<task-notification>bg done</task-notification>")], {}),
    ("CRLF transcript, push in the turn: blocks", 2, filler(-300) + [U(-10), A(-9, PUSH, "p4"), R(-8, "p4")], {"eol": b"\r\n"}),
    ("truncated last line after a push: still blocks, no crash", 2,
     filler(-300) + [U(-10), A(-9, PUSH, "p5"), R(-8, "p5")], {"tail": b'{"type":"assistant","timestamp":"' + ts(-7).encode() + b'","message":{"conte'}),
    ("truncated last line, no push: allowed", 0, filler(-300) + [U(-10), A(-9, "ls", "l2")], {"tail": b'{"type":"assistant","time'}),
    ("a 5 MB tool result between prompt and push: push still seen", 2,
     filler(-300) + [U(-10), A(-9, "cat big", "b1"), R(-8, "b1", "z" * HUGE), A(-7, PUSH, "p6"), R(-6, "p6")], {}),
    ("a 5 MB line before the prompt, no push in the turn: allowed", 0,
     [A(-400, "cat big", "b2"), R(-399, "b2", "z" * HUGE), U(-10), A(-9, "ls", "l3")], {}),
    ("no user prompt at all: nothing to be 'after' it, allowed", 0, filler(-300), {}),
]
for what, want, lines, kw in cases:
    rc = hook(lines, **kw)
    check(rc == want, "hook: " + what, "exit %s, wanted %s" % (rc, want))

# ── E. XONG when start is None ──────────────────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(hooks), "bin"))
import tree_fp
repo2 = os.path.join(tmp, "repo2")
os.makedirs(os.path.join(repo2, ".agents"))
def git(*a):
    subprocess.run(["git", "-C", repo2, "-c", "user.email=t@t", "-c", "user.name=t", *a], check=True, capture_output=True)
git("init", "-q", ".")
with open(os.path.join(repo2, ".agents", "active-profile.json"), "w") as fh:
    fh.write('{"profile":"backend"}')          # backend: no image needed, so only the gate half is under test
with open(os.path.join(repo2, ".gitignore"), "w") as fh:
    fh.write(".claude/audit-gate/\n")
with open(os.path.join(repo2, "f.txt"), "w") as fh:
    fh.write("x\n")
git("add", "-A")
git("commit", "-q", "-m", "init")
good_fp = tree_fp.tree_fingerprint(repo2)
os.makedirs(os.path.join(repo2, ".git", "postfix-gate"), exist_ok=True)
RECEIPT = os.path.join(repo2, ".git", "postfix-gate", "full_pass.json")
GUARD_STATE = os.path.join(repo2, ".claude", "audit-gate", "proof_gate.state")
REPORT4 = ("1. Đã fix: lỗi X, RED→GREEN.\n2. Chặn bug cũ: REG-1 PASS.\n3. Nguy cơ bug mới: đã rà caller.\n"
           "4. An toàn mã nguồn: secret 0, placeholder 0.")
XONG = "XONG\nĐã sửa lỗi X.\nGate exit 0 · ảnh: không cần (profile backend)\n" + REPORT4
def iso(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
def put_receipt(age=0.0, fp=None, raw=None):
    with open(RECEIPT, "w") as fh:
        fh.write(raw if raw is not None else json.dumps({"exit": 0, "time": time.time() - age, "fingerprint": fp or good_fp}))
def drop_receipt():
    if os.path.exists(RECEIPT):
        os.unlink(RECEIPT)
# The shapes Claude Code really writes (measured on ~/.claude/projects transcripts, 2026-10-04):
def peer(t, text="do the task", content=None):      # a peer message: type=user, isMeta AND origin.kind=peer
    return jl({"type": "user", "isMeta": True, "origin": {"kind": "peer"}, "timestamp": iso(t),
               "message": {"role": "user", "content": content if content is not None else "Another Claude session sent a message: " + text}})
def human(t, text="sửa lỗi X"):
    return jl({"type": "user", "timestamp": iso(t), "origin": {"kind": "human"}, "message": {"role": "user", "content": text}})
def feedback(t, text="Stop hook feedback:\n[proof_gate]: blocked"):   # a Stop hook's block: type=user, isMeta, no origin
    return jl({"type": "user", "isMeta": True, "timestamp": iso(t), "message": {"role": "user", "content": text}})
def notif(t, kind="task-notification", text="<task-notification>\n<task-id>b1</task-id> done</task-notification>"):   # a finished background task
    return jl({"type": "user", "origin": {"kind": kind}, "timestamp": iso(t), "message": {"role": "user", "content": text}})
def notif_text_only(t):                               # the same text with no origin
    return jl({"type": "user", "timestamp": iso(t), "message": {"role": "user", "content": "<task-notification>\n<task-id>b1</task-id> done</task-notification>"}})
def img_meta(t):                                      # a Read of a PNG
    return jl({"type": "user", "isMeta": True, "timestamp": iso(t), "message": {"role": "user", "content": [
        {"type": "text", "text": "[Image: original 1080x2408, displayed at 897x2000. Multiply coordinates by 1.20 to map to original image.]"}]}})
def skill_meta(t):                                    # a skill load
    return jl({"type": "user", "isMeta": True, "timestamp": iso(t), "message": {"role": "user", "content": "Base directory for this skill: /x/skills/y\n..."}})
def queued(t):                                        # a prompt the user typed mid-turn: an attachment, NOT a user entry
    return jl({"type": "attachment", "timestamp": iso(t), "attachment": {"type": "queued_command", "prompt": "also do Y", "commandMode": "prompt"}})
def gate_call(t, background=False):
    inp = {"command": "python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief"}
    if background:
        inp["run_in_background"] = True
    return jl({"type": "assistant", "timestamp": iso(t), "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "g1", "name": "Bash", "input": inp}]}})
def read_call(t):
    return jl({"type": "assistant", "timestamp": iso(t), "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "r1", "name": "Read", "input": {"file_path": "reports/proof-x.png"}}]}})
def assistant_at(t, text=None):
    return jl({"type": "assistant", "timestamp": iso(t), "message": {"role": "assistant", "content": [{"type": "text", "text": text or "ok"}]}})
def result_at(t, tid="g1", text="exit 0"):
    return jl({"type": "user", "timestamp": iso(t), "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": text}]}})
def append(pth, *lines):
    with open(pth, "ab") as fh:
        fh.write(b"\n".join(lines) + b"\n")
def stop(pth, reply=XONG, session="e"):
    payload = {"session_id": session, "last_assistant_message": reply}
    if pth:
        payload["transcript_path"] = pth
    r = subprocess.run(["bash", HOOK], input=json.dumps(payload), capture_output=True, text=True, timeout=60,
                       env=dict(os.environ, CLAUDE_PROJECT_DIR=repo2))
    return r.returncode, r.stderr, r.stdout
def clean(err):
    return "Traceback" not in err and "Error" not in err
nt = [0]
def newpath():
    nt[0] += 1
    return os.path.join(tmp, "peer%d.jsonl" % nt[0])

# E1: the gate ran (receipt written), THEN Claude Code appends what it always appends; every shape of it, none may void the receipt
now = time.time()
SHAPES = (
    ("tool_result and reply", lambda t: [result_at(t + 1), assistant_at(t + 2, XONG)]),
    ("another Stop hook's feedback (isMeta) and a second reply [rv5 t1]", lambda t: [result_at(t + 1), assistant_at(t + 2, XONG), feedback(t + 3, "Stop hook feedback:\n[test_evidence_gate]: blocked"), assistant_at(t + 9, XONG)]),
    ("a background gate's task-notification [rv5 t3a]", lambda t: [notif(t + 1), assistant_at(t + 2, XONG)]),
    ("a Read of the proof image ([Image: ...] isMeta) [rv5 t3b]", lambda t: [result_at(t + 1), read_call(t + 2), result_at(t + 3, "r1", "png"), img_meta(t + 3), assistant_at(t + 4, XONG)]),
    ("skill load, bare <task-notification> text, image, feedback [rv5 t5-like]", lambda t: [result_at(t + 1), skill_meta(t + 2), notif_text_only(t + 3), img_meta(t + 4), feedback(t + 5), assistant_at(t + 6, XONG)]),
    ("a queued_command attachment", lambda t: [queued(t + 1), result_at(t + 2), assistant_at(t + 3, XONG)]),
)
for first_name, first in (("peer message", lambda t: peer(t)), ("a bare assistant start", lambda t: assistant_at(t, "starting"))):
    for what, after in SHAPES:
        pth = newpath(); drop_receipt()
        t0 = time.time() - 300
        append(pth, first(t0), gate_call(t0 + 10))
        put_receipt(100.0)                                   # the gate finished 100 s ago ...
        append(pth, *after(time.time() - 90))                # ... and the transcript kept growing after it
        rc, err, out = stop(pth, session="e1-%d" % nt[0])
        check(rc == 0 and clean(err) and not out.strip(), "%s, valid receipt, then %s: allowed" % (first_name, what),
              "exit %s stderr=%r stdout=%r" % (rc, err[-160:], out[-80:]))
# E2: the code changed after the receipt
pth = newpath(); t0 = time.time() - 60
append(pth, peer(t0), gate_call(t0 + 5))
put_receipt(0.0, fp="0" * 20)
append(pth, result_at(time.time()), assistant_at(time.time(), XONG))
rc, err, _ = stop(pth, session="e2")
check(rc == 2 and "code đã đổi" in err and clean(err), "peer-only turn, code changed after the receipt: blocked, reason named", "exit %s stderr=%r" % (rc, err[-200:]))
# E3: a receipt older than the 1 h window
pth = newpath(); t0 = time.time() - 60
put_receipt(7200.0)
append(pth, peer(t0), assistant_at(t0 + 5, XONG))
rc, err, _ = stop(pth, session="e3")
check(rc == 2 and "từ trước lượt này" in err and clean(err), "receipt 2 h old: blocked", "exit %s stderr=%r" % (rc, err[-200:]))
# E4: the same without a transcript, and with one that has no user entry (a session id of its own per case)
for i, (what, age, tr, want) in enumerate((("no transcript, receipt 2 h old: blocked", 7200, False, 2), ("no transcript, receipt 1 min old: allowed", 60, False, 0),
                                           ("assistant-only transcript, receipt 2 h old: blocked", 7200, True, 2), ("assistant-only transcript, receipt 10 s old: allowed", 10, True, 0))):
    pth = None
    if tr:
        pth = newpath(); append(pth, assistant_at(time.time() - 5, "hi"))
    put_receipt(age)
    rc, err, _ = stop(pth, session="e4-%d" % i)
    check(rc == want and clean(err) and (want == 0 or "từ trước lượt này" in err), "start is None: " + what, "exit %s stderr=%r" % (rc, err[-200:]))
# E5: start is NOT None: unchanged, the receipt must be newer than that prompt (a 100 s old receipt before a 30 s old prompt)
hp0 = write("e5_human.jsonl", jl({"type": "user", "timestamp": iso(time.time() - 30), "message": {"role": "user", "content": "sửa lỗi X"}}) + b"\n")
put_receipt(100.0)
rc, err, _ = stop(hp0, session="e5")
check(rc == 2 and "từ trước lượt này" in err and clean(err), "start known: a receipt older than the human prompt is still blocked (policy unchanged)", "exit %s stderr=%r" % (rc, err[-200:]))

# ── F. the loop guard of a session with no turn start ──────────────────────────────────────
def state():
    try:
        with open(GUARD_STATE) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}
for session, with_tr in (("f-none", False), ("f-peer", True)):
    drop_receipt()
    pth = None
    if with_tr:
        pth = newpath(); t0 = time.time() - 600; append(pth, peer(t0), assistant_at(t0 + 1, XONG))
    h0 = int(time.time() // 3600)
    row = []
    for i in range(4):
        rc, err, out = stop(pth, session=session)
        row.append("release" if rc == 0 and "systemMessage" in out else rc)
        if rc == 2 and pth:       # what Claude Code writes after a block: the hook's feedback (isMeta), then the model answers again
            append(pth, feedback(time.time() - 5, "Stop hook feedback:\n" + err[:60]), assistant_at(time.time() - 4, XONG))
    h1 = int(time.time() // 3600)
    keys = sorted(k for k in state() if k.startswith(session + "@"))
    check(row == [2, 2, "release", "release"] and any(keys == ["%s@h%d" % (session, h)] for h in (h0, h1)),
          "F no turn start (%s): [block, block, release] and the key is %s@h<hour>, not %s@0" % ("peer-only transcript" if with_tr else "no transcript", session, session),
          "row %r keys %r" % (row, keys))
# a spent legacy `@0` key no longer shuts the gate
for session, with_tr in (("f0-none", False), ("f0-assistant", True)):
    drop_receipt()
    st = state(); st[session + "@0"] = 9
    os.makedirs(os.path.dirname(GUARD_STATE), exist_ok=True)
    with open(GUARD_STATE, "w") as fh:
        json.dump(st, fh)
    pth = None
    if with_tr:
        pth = newpath(); append(pth, assistant_at(time.time() - 5, "hi"))
    rc, err, out = stop(pth, session=session)
    check(rc == 2, "F a spent %s@0 key (the old constant) does not let a later XONG through" % session, "exit %s stdout=%r" % (rc, out[-80:]))
# with a turn start the key is the prompt's own timestamp: a fresh budget for every prompt, unchanged
drop_receipt()
pth = newpath(); rows = []
for turn in range(3):
    tt = time.time() - 900 + 100 * turn
    append(pth, human(tt), assistant_at(tt + 1, XONG))
    row = []
    for i in range(3):
        rc, err, out = stop(pth, session="f-human")
        row.append("release" if rc == 0 and "systemMessage" in out else rc)
        if rc == 2:
            append(pth, feedback(tt + 2 + 10 * i), assistant_at(tt + 8 + 10 * i, XONG))
    rows.append(row)
check(rows == [[2, 2, "release"]] * 3 and all(k.startswith("f-human@") and "@h" not in k for k in state() if k.startswith("f-human")),
      "F start known: [block, block, release] per prompt, key = the prompt's timestamp (unchanged)", repr((rows, [k for k in state() if k.startswith("f-human")])))

# ── G. a receipt of the wrong shape blocks, it does not crash the hook ─────────────────────
hp = write("g_human.jsonl", jl({"type": "user", "timestamp": iso(time.time() - 30), "message": {"role": "user", "content": "sửa lỗi X"}}) + b"\n")
for i, raw in enumerate(('{"exit":0,"time":null,"fingerprint":"x"}', '[1]', '"later"', '7', '{"exit":0,"time":"later","fingerprint":"x"}',
                         '{"exit":0,"time":NaN,"fingerprint":"x"}', '{"exit":0,"time":Infinity,"fingerprint":"x"}', '{"exit":0,"time":-Infinity,"fingerprint":"x"}',
                         '{"exit":0,"time":true,"fingerprint":"x"}')):
    put_receipt(raw=raw)
    rc, err, _ = stop(hp, session="g%d" % i)
    check(rc == 2 and "receipt hỏng" in err and clean(err), "receipt %s: blocked as corrupt, no crash" % raw, "exit %s stderr=%r" % (rc, err[-200:]))
# an integer too large for a float must not crash a finiteness test (math.isfinite raises OverflowError on it)
put_receipt(raw='{"exit":0,"time":1' + "0" * 400 + ',"fingerprint":"x"}')
rc, err, _ = stop(hp, session="g-huge")
check(rc == 2 and clean(err), "receipt time a 400-digit integer: no crash (blocked here by the fingerprint)", "exit %s stderr=%r" % (rc, err[-200:]))
put_receipt(0.0)
rc, err, _ = stop(hp, session="g-ok")
check(rc == 0 and clean(err), "control: the same human-prompt transcript with a valid receipt is allowed", "exit %s stderr=%r" % (rc, err[-200:]))

print("turn_start reverse: %s" % ("%d FAILED" % FAILS if FAILS else "all checks passed"))
sys.exit(1 if FAILS else 0)
PY
