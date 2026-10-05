#!/usr/bin/env bash
# Regression (DevKit speed, item 0a): the proof-image scan hashed EVERY old PNG with pure-Python dhash
# (0.6-0.9 s each, 97-135 s per gate run in the three app repos) even when the change was docs-only.
# Old images are references only: they matter solely when a fresh image has to be compared with them.
#   A. no fresh image + 45 old PNGs  -> same verdict as before, but ZERO dhash calls (and fast)
#   B. fresh + references            -> same findings and the same warning text as before (dup, zero-byte, similar)
#   C. dhash cache keyed by the sha256 of the BYTES: warm run does no dhash; file in <git-common-dir>/postfix-gate/
#   D. cache trust: only an entry of the current algorithm version for the same bytes is believed;
#      corrupt / other-version / malformed entries are ignored and rebuilt; a changed file never reuses old bits
#   E. Pillow fast path == pure-Python path on every PNG shape, including the ones that give no hash,
#      and the Pillow decoder really ran (no vacuous pass through the fallback)
#   F. through the real gate CLI: duplicates still block, and the cache file appears next to the receipt
# Counting dhash calls is the discriminating check; the time bound is deliberately generous (shared machine).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

DEVKIT_DIR="$DEVKIT_DIR" TMP="$TMP" DEVKIT_LANG=en python3 - <<'PY'
import contextlib, hashlib, importlib.util, io, json, os, random, re, stat, struct, subprocess, sys, time, zlib

DEVKIT = os.environ["DEVKIT_DIR"]
TMP = os.environ["TMP"]
FAILS = 0


def check(name, cond, detail=""):
    global FAILS
    if cond:
        print("✔ " + name)
    else:
        FAILS += 1
        print("✖ " + name + (" — " + str(detail) if detail else ""))


def chunk(tag, data, crc=None):
    c = zlib.crc32(tag + data) & 0xFFFFFFFF if crc is None else crc
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", c)


SIG = b"\x89PNG\r\n\x1a\n"
BPP = {0: 1, 2: 3, 6: 4}


def png(w, h, color=2, seed=1, filt=4, level=6, bit=8, interlace=0, raw=None, ihdr=None, idat_parts=None, tail=b"", iend=True):
    """A PNG whose scanlines use PNG filter `filt` (a list is cycled); the bytes are arbitrary because any
    byte string is a valid filtered image: both decoders must agree on what it decodes to."""
    bpp = BPP.get(color, 4)
    stride = w * bpp
    if raw is None:
        rng = random.Random(seed)
        fl = filt if isinstance(filt, list) else [filt]
        raw = b"".join(bytes([fl[y % len(fl)]]) + rng.randbytes(stride) for y in range(h))
    z = zlib.compress(raw, level)
    parts = idat_parts(z) if idat_parts else [chunk(b"IDAT", z)]
    head = ihdr if ihdr is not None else chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, bit, color, 0, 0, interlace))
    return SIG + head + b"".join(parts) + (chunk(b"IEND", b"") if iend else b"") + tail


# ── load the gate and the hash module the way the gate does ──────────────────────────────────────────
proj0 = os.path.join(TMP, "load")
os.makedirs(proj0)
os.environ["CLAUDE_PROJECT_DIR"] = proj0
spec = importlib.util.spec_from_file_location("pfg", DEVKIT + "/bin/post-fix-gate.py")
pfg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pfg)
pfg._scripts_on_path()
import proof_phash as ph  # noqa: E402

ORIG_DHASH = ph.dhash
CALLS = []


def counting(data, *a, **k):
    CALLS.append(len(data))
    return ORIG_DHASH(data, *a, **k)


ph.dhash = counting
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def git(cwd, *args):
    return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, check=True).stdout.strip()


def make_repo(name):
    d = os.path.join(TMP, name)
    os.makedirs(d + "/reports")
    git(d, "init", "-q", ".")
    git(d, "config", "user.email", "t@t")
    git(d, "config", "user.name", "t")
    open(d + "/README.md", "w").write("x\n")
    git(d, "add", "-A")
    git(d, "commit", "-qm", "init")
    return os.path.realpath(d)


NOW = time.time()
OLD = NOW - 5 * 86400
os.environ["POSTFIX_PROOF_SINCE"] = str(NOW - 3600)


def put(repo, rel, data, mtime):
    p = os.path.join(repo, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "wb").write(data)
    os.utime(p, (mtime, mtime))
    return p


def run_block(repo, files=("README.md",)):
    os.environ["CLAUDE_PROJECT_DIR"] = repo
    del CALLS[:]
    buf = io.StringIO()
    t0 = time.time()
    with contextlib.redirect_stdout(buf):
        res = pfg.run_proof_block(list(files))
    out = "\n".join(l.strip() for l in ANSI.sub("", buf.getvalue()).splitlines() if l.strip())
    return res, out, len(CALLS), time.time() - t0


def cache_path(repo):
    common = git(repo, "rev-parse", "--git-common-dir")
    return os.path.join(repo, common, "postfix-gate", "proof-hash-cache.json")


# ── A. docs-only change, 45 old PNGs, no fresh image ────────────────────────────────────────────────
try:
    A = make_repo("a")
    for i in range(45):
        put(A, "reports/proof-old-%03d.png" % i, png(400, 800, 2, seed=i, filt=4, level=1), OLD)
    (ok_a, f_a), out_a, n_a, dt_a = run_block(A)
    check("A no fresh image: nothing is judged (True, [])", ok_a is True and f_a == [] and out_a == "", (ok_a, f_a, out_a))
    check("A no fresh image: the 45 old references are not hashed (dhash calls = %d)" % n_a, n_a == 0, n_a)
    check("A no fresh image: fast (%.2f s < 1.5 s; the old code needs seconds)" % dt_a, dt_a < 1.5, dt_a)
except Exception as e:  # noqa: BLE001 - a crash is a failed check, reported with its text
    check("A scenario ran", False, repr(e))

# ── B. fresh images against references: same findings, same warning text ─────────────────────────────
B = None
try:
    B = make_repo("b")
    ref_bytes = {}
    for i in range(12):
        ref_bytes[i] = png(160, 320, 2, seed=100 + i, filt=4)
        put(B, "reports/ref-%03d.png" % i, ref_bytes[i], OLD)
    sim = png(160, 320, 2, seed=103, filt=4, level=1)            # same pixels as ref-003, other bytes
    assert sim != ref_bytes[3]
    put(B, "reports/fresh-dup.png", ref_bytes[7], NOW - 40)      # byte-identical to ref-007
    put(B, "reports/fresh-zero.png", b"", NOW - 30)              # zero byte
    put(B, "reports/fresh-sim.png", sim, NOW - 20)               # >= 98 % similar to ref-003: a warning
    put(B, "reports/fresh-new.png", png(160, 320, 2, seed=999, filt=2), NOW - 10)   # unrelated: silent
    NOHASH = [png(40, 30, 2, seed=5, bit=16), png(40, 30, 3, seed=6)]   # valid PNG files the kit cannot hash (16-bit, palette)
    put(B, "reports/fresh-16bit.png", NOHASH[0], NOW - 5)        # fresh, no hash: judged only by sha256, silent
    put(B, "reports/ref-palette.png", NOHASH[1], OLD)            # reference, no hash: remembered by sha256 only
    (ok_b, f_b), out_b, n_b, _ = run_block(B)
    want_f = [("reports/fresh-dup.png", "reports/fresh-dup.png: identical bytes to reports/ref-007.png"),
              ("reports/fresh-zero.png", "reports/fresh-zero.png: zero-byte proof image")]
    check("B findings: byte-identical and zero-byte still block, in the same order", ok_b is False and f_b == want_f, (ok_b, f_b))
    want_out = ("⚠ reports/fresh-sim.png: ≥98% similar to reports/ref-003.png (same screen) — "
                "for a new state capture another screen; do not delete older proofs")
    check("B warning: a retake of ref-003 warns with the same text and names only ref-003", out_b == want_out, out_b)
except Exception as e:  # noqa: BLE001
    check("B scenario ran", False, repr(e))

# ── C. cache keyed by the sha256 of the bytes ────────────────────────────────────────────────────────
try:
    first = run_block(B)
    second = run_block(B)
    check("C warm run: same verdict, findings and warning as the cold run", first[:2] == second[:2], (first[:2], second[:2]))
    check("C warm run: dhash only for the %d images that have no hash (never cached, cheap); every other image comes from the cache (calls = %d)"
          % (len(NOHASH), second[2]), second[2] == len(NOHASH), second[2])
    cp = cache_path(B)
    data = json.load(open(cp))
    sha3 = hashlib.sha256(ref_bytes[3]).hexdigest()
    true3 = ORIG_DHASH(ref_bytes[3])
    check("C cache file <git-common-dir>/postfix-gate/proof-hash-cache.json holds [version, dhash] under the sha256",
          data.get(sha3) == [ph.ALGO_VERSION, true3], data.get(sha3))
    check("C no temp file left next to the cache",
          [n for n in os.listdir(os.path.dirname(cp)) if n.startswith(".tmp") or n.endswith(".tmp")] == [],
          os.listdir(os.path.dirname(cp)))
    check("C setup: the 16-bit and the palette PNG really have no hash", all(ORIG_DHASH(b) is None for b in NOHASH))
    check("C an image without a hash (16-bit fresh, palette reference) is never cached: its sha256 is not in the file",
          all(hashlib.sha256(b).hexdigest() not in data for b in NOHASH), [k[:12] for k in data if k in {hashlib.sha256(b).hexdigest() for b in NOHASH}])
    check("C every cache entry is [version, int]",
          all(isinstance(v, list) and len(v) == 2 and type(v[1]) is int for v in data.values()), list(data.values())[:3])
except Exception as e:  # noqa: BLE001
    check("C scenario ran", False, repr(e))

# ── D. cache trust ───────────────────────────────────────────────────────────────────────────────────
try:
    cold = ((ok_b, f_b), out_b)   # B ran with no cache at all: the reference every later run must equal
    cp = cache_path(B)
    good = json.load(open(cp))
    sha3 = hashlib.sha256(ref_bytes[3]).hexdigest()
    true3 = ORIG_DHASH(ref_bytes[3])
    flipped = true3 ^ ((1 << 64) - 1)

    def with_cache(content):
        with open(cp, "w") as f:
            f.write(content if isinstance(content, str) else json.dumps(content))
        return run_block(B)

    cur = dict(good)
    cur[sha3] = [ph.ALGO_VERSION, flipped]
    r = with_cache(cur)
    check("D a current-version entry for the same bytes IS trusted (the poisoned bits hide the warning)",
          r[1] == "" and r[0][0] is False, r[1])
    other = dict(good)
    other[sha3] = [ph.ALGO_VERSION + 1, flipped]
    r = with_cache(other)
    check("D an entry of another algorithm version is ignored: result equals the cold run", r[:2] == cold, r[1])
    check("D ...and the cache is rewritten with the right bits",
          json.load(open(cp)).get(sha3) == [ph.ALGO_VERSION, true3], json.load(open(cp)).get(sha3))
    for label, junk in (("garbage bytes", "\x00\x01not json{"), ("a JSON list", "[1, 2, 3]"), ("an empty file", ""),
                        ("string entry", json.dumps({sha3: "x"})),
                        ("negative dhash", json.dumps({sha3: [ph.ALGO_VERSION, -5]})),
                        ("bool dhash", json.dumps({sha3: [ph.ALGO_VERSION, True]})),
                        ("dhash over 64 bits", json.dumps({sha3: [ph.ALGO_VERSION, 1 << 70]})),
                        ("three-element entry", json.dumps({sha3: [ph.ALGO_VERSION, flipped, 0]})),
                        ("null dhash", json.dumps({sha3: [ph.ALGO_VERSION, None]}))):
        r = with_cache(junk)
        check("D corrupt cache (%s): same result as the cold run" % label, r[:2] == cold, r[1])
    try:
        json.load(open(cp))
        valid = True
    except ValueError:
        valid = False
    check("D after a corrupt cache the file is a valid cache again", valid)
    os.remove(cp)
    r = run_block(B)
    check("D no cache file: same result as the cold run, and one is created", r[:2] == cold and os.path.isfile(cp), r[1])

    # keyed by the bytes, never by path or mtime: another picture at ref-003's path must not inherit its bits
    put(B, "reports/ref-003.png", png(160, 320, 2, seed=555, filt=1), OLD)
    r = run_block(B)
    check("D a changed file at the same path and mtime is hashed again: the old warning is gone",
          r[1] == "" and r[2] >= 1, (r[1], r[2]))
    put(B, "reports/ref-003.png", ref_bytes[3], OLD)
    r = run_block(B)
    check("D the same bytes back: the warning is back, from the cache (dhash only for the %d no-hash images)" % len(NOHASH),
          r[1] == want_out and r[2] == len(NOHASH), (r[1], r[2]))
except Exception as e:  # noqa: BLE001
    check("D scenario ran", False, repr(e))

# ── D2. a flat screen hashes to 0: a valid value, not "no hash" (0 is falsy; the cache must still serve it) ───────
try:
    G = make_repo("g")
    flat_raw = b"".join(b"\x00" + bytes([10]) * 16 for _ in range(16))
    put(G, "reports/ref-flat.png", png(16, 16, 0, raw=flat_raw, level=9), OLD)
    put(G, "reports/fresh-flat.png", png(16, 16, 0, raw=flat_raw, level=0), NOW - 10)
    want_flat = ("⚠ reports/fresh-flat.png: ≥98% similar to reports/ref-flat.png (same screen) — "
                 "for a new state capture another screen; do not delete older proofs")
    r1 = run_block(G)
    r2 = run_block(G)
    check("D2 a flat retake warns against the flat reference (dhash 0), cold", r1[0] == (True, []) and r1[1] == want_flat, r1[1])
    check("D2 ...and warm, from the cache, with no dhash call", r2[:2] == r1[:2] and r2[2] == 0, (r2[1], r2[2]))
    check("D2 the flat hash is stored as [version, 0]", 0 in [v[1] for v in json.load(open(cache_path(G))).values()])
except Exception as e:  # noqa: BLE001
    check("D2 scenario ran", False, repr(e))

# ── D3. a FIFO (any non-regular file) at the cache path must not hang the gate: hard time limit, no `timeout` binary ──
CHILD_GATE = r"""
import contextlib, importlib.util, io, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1] + "/bin/post-fix-gate.py")
pfg = importlib.util.module_from_spec(spec); spec.loader.exec_module(pfg)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    res = pfg.run_proof_block(["README.md"])
print(repr(res)); print(buf.getvalue())
"""
CHILD_SAVE = r"""
import os, sys
sys.path.insert(0, sys.argv[1] + "/scripts/testing")
import proof_phash as ph
path = sys.argv[2]
cache = ph.HashCache(path)      # nothing at the path yet: the load is fine
os.mkfifo(path)                 # a FIFO appears before save() merges what another gate wrote
cache.get(open(sys.argv[3], "rb").read())
cache.save()
print("saved", os.path.isfile(path))
"""


def child(code, args, repo=None, limit=60):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=repo or TMP)
    try:
        r = subprocess.run([sys.executable, "-c", code, DEVKIT] + args, capture_output=True, text=True, timeout=limit, env=env)
    except subprocess.TimeoutExpired:
        return "TIMEOUT (> %d s)" % limit
    return ANSI.sub("", r.stdout) + r.stderr


try:
    H = make_repo("h")
    hb = {}
    for i in range(6):
        hb[i] = png(160, 320, 2, seed=300 + i, filt=4)
        put(H, "reports/ref-%03d.png" % i, hb[i], OLD)
    put(H, "reports/fresh-dup.png", hb[2], NOW - 20)
    put(H, "reports/fresh-sim.png", png(160, 320, 2, seed=304, filt=4, level=1), NOW - 10)
    cold_h = child(CHILD_GATE, [], H)
    check("D3 setup: the child gate run gives the findings and the warning", "identical bytes to reports/ref-002.png" in cold_h and "similar to reports/ref-004.png" in cold_h, cold_h[:300])
    cph = cache_path(H)
    os.remove(cph)
    os.mkfifo(cph)
    got = child(CHILD_GATE, [], H)
    check("D3 a FIFO at the cache path: the gate neither hangs nor changes its decision (same as cold)", got == cold_h, got[:300])
    check("D3 ...and it leaves a regular, valid cache behind", stat.S_ISREG(os.lstat(cph).st_mode) and isinstance(json.load(open(cph)), dict), os.lstat(cph).st_mode)
    one = os.path.join(TMP, "one.png")
    open(one, "wb").write(png(40, 30, 2, seed=1))
    cps = os.path.join(TMP, "save-cache.json")
    got = child(CHILD_SAVE, [cps, one])
    check("D3 a FIFO that appears before save() merges: save() does not hang and writes the cache", got.strip() == "saved True", got[:300])
except Exception as e:  # noqa: BLE001
    check("D3 scenario ran", False, repr(e))

# ── E. Pillow path == pure path ──────────────────────────────────────────────────────────────────────
try:
    ph.dhash = ORIG_DHASH
    try:
        import PIL.Image as PI
        have_pil = True
    except ImportError:
        have_pil = False
    pil_calls = []
    if have_pil:
        orig_fb = PI.frombytes

        def spy(*a, **k):
            r = orig_fb(*a, **k)
            pil_calls.append(1)   # counted only when Pillow really decoded
            return r

        PI.frombytes = spy

    cases = []   # (name, bytes, expect_hash)
    plain = 0
    for color, cname in ((0, "gray"), (2, "rgb"), (6, "rgba")):
        for f in range(5):
            cases.append(("%s filter %d" % (cname, f), png(37, 23, color, seed=color * 10 + f, filt=f), True))
        cases.append(("%s mixed filters" % cname, png(64, 41, color, seed=7, filt=[0, 1, 2, 3, 4, 4, 3, 2]), True))
        cases.append(("%s 1x1" % cname, png(1, 1, color, seed=3, filt=0), True))
        cases.append(("%s 9x8" % cname, png(9, 8, color, seed=4, filt=4), True))
        cases.append(("%s 5x3 (fewer pixels than sample points)" % cname, png(5, 3, color, seed=5, filt=1), True))
        cases.append(("%s stored (level 0)" % cname, png(30, 30, color, seed=6, filt=2, level=0), True))
    plain = len(cases)
    w, h = 30, 20
    base_raw = b"".join(bytes([4]) + random.Random(9).randbytes(w * 3) for _ in range(h))
    zraw = zlib.compress(base_raw)
    cases += [
        ("palette", png(10, 10, 3), False),
        ("gray+alpha", png(10, 10, 4), False),
        ("16-bit rgb", png(10, 10, 2, bit=16), False),
        ("interlaced", png(10, 10, 2, interlace=1), False),
        ("width 0", png(10, 10, 2, ihdr=chunk(b"IHDR", struct.pack(">IIBBBBB", 0, 10, 8, 2, 0, 0, 0))), False),
        ("no IHDR", SIG + chunk(b"IDAT", zraw) + chunk(b"IEND", b""), False),
        ("garbage after the signature", SIG + os.urandom(300), False),
        ("not a png", b"hello world", False),
        ("empty", b"", False),
        ("signature only", SIG, False),
        ("truncated file", png(w, h, 2, raw=base_raw)[:60], False),
        ("truncated IDAT", png(w, h, 2, raw=base_raw)[:len(png(w, h, 2, raw=base_raw)) // 2], False),
        ("corrupt zlib", png(w, h, 2, idat_parts=lambda z: [chunk(b"IDAT", z[:2] + b"\xff" * 40 + z[42:])]), False),
        ("adler32 cut off", png(w, h, 2, idat_parts=lambda z: [chunk(b"IDAT", z[:-4])]), False),
        ("adler32 wrong", png(w, h, 2, idat_parts=lambda z: [chunk(b"IDAT", z[:-4] + b"\0\0\0\0")]), False),
        ("raw has fewer rows", png(w, h, 2, raw=base_raw[:len(base_raw) - (w * 3 + 1) * 2]), False),
        ("raw cut inside the last row", png(w, h, 2, raw=base_raw[:-5]), False),
        ("filter byte 5 in the last row", png(w, h, 2, raw=base_raw[:-(w * 3 + 1)] + b"\x05" + base_raw[-(w * 3):]), False),
        ("filter byte 5 in the middle", png(w, h, 2, raw=base_raw[:(w * 3 + 1) * 7] + b"\x05" + base_raw[(w * 3 + 1) * 7 + 1:]), False),
        ("empty IDAT", png(w, h, 2, idat_parts=lambda z: [chunk(b"IDAT", b"")]), False),
        ("no IDAT", png(w, h, 2, idat_parts=lambda z: []), False),
        # accepted by the old decoder, so the fast path must give the same hash
        ("raw has extra rows", png(w, h, 2, raw=base_raw + b"\x01" + b"\xaa" * (w * 3)), True),
        ("trailing bytes after the zlib stream", png(w, h, 2, idat_parts=lambda z: [chunk(b"IDAT", z + b"trailing junk")]), True),
        ("bad IDAT crc", png(w, h, 2, idat_parts=lambda z: [chunk(b"IDAT", z, crc=0x12345678)]), True),
        ("IDAT split in 3 with an ancillary chunk between", png(w, h, 2, idat_parts=lambda z: [
            chunk(b"IDAT", z[:20]), chunk(b"tEXt", b"k\0v"), chunk(b"IDAT", z[20:50]), chunk(b"IDAT", z[50:])]), True),
        ("IDAT split byte by byte at the start", png(w, h, 2, idat_parts=lambda z: [chunk(b"IDAT", z[:1]), chunk(b"IDAT", z[1:2]), chunk(b"IDAT", z[2:])]), True),
        ("trailing bytes after IEND", png(w, h, 2, raw=base_raw, tail=b"extra" * 10), True),
        ("no IEND", png(w, h, 2, raw=base_raw, iend=False), True),
        ("two IHDRs: the last one wins (a decoy 5x5 first)", png(w, h, 2, raw=base_raw,
            ihdr=chunk(b"IHDR", struct.pack(">IIBBBBB", 5, 5, 8, 2, 0, 0, 0)),
            idat_parts=lambda z: [chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)), chunk(b"IDAT", z)]), True),
        ("two IHDRs: a valid one first, a decoy 5x5 last (stream no longer fits)", png(w, h, 2, raw=base_raw,
            idat_parts=lambda z: [chunk(b"IHDR", struct.pack(">IIBBBBB", 5, 5, 8, 2, 0, 0, 0)), chunk(b"IDAT", z)]), False),
        ("tRNS and gAMA chunks", png(w, h, 2, raw=base_raw, idat_parts=lambda z: [
            chunk(b"gAMA", struct.pack(">I", 45455)), chunk(b"tRNS", b"\0\0\0\0\0\0"), chunk(b"IDAT", z)]), True),
        ("large dims, tiny payload (decompression-bomb shape)", png(40000, 40000, 2, raw=b"\x00" * 100), False),
    ]
    bad = []
    del pil_calls[:]
    plain_calls = None
    for i, (name, data, expect) in enumerate(cases):
        if i == plain:
            plain_calls = len(pil_calls)   # decodes by Pillow so far = the plain shapes only (damaged-but-accepted ones come after)
        fast = ph.dhash(data)
        pure = ph.dhash(data, fast=False)
        if fast != pure:
            bad.append((name, fast, pure))
        elif (pure is not None) != expect:
            bad.append((name + " [expectation]", fast, pure))
    check("E Pillow path == pure path on %d synthetic PNGs (types x filters, rejects, damaged streams)" % len(cases), not bad, bad)
    if have_pil:
        check("E Pillow decoded each of the %d plain shapes itself (%s decodes before the damaged cases: none fell back to pure)" % (plain, plain_calls),
              plain_calls == plain, plain_calls)
    else:
        print("note: Pillow missing here, the fast path is untested (fallback only)")
    fuzz_bad = []
    rng = random.Random(2026)
    for i in range(60):
        color = rng.choice((0, 2, 6))
        data = bytearray(png(rng.randint(1, 40), rng.randint(1, 30), color, seed=i, filt=[rng.randint(0, 4) for _ in range(5)]))
        for _ in range(rng.randint(1, 3)):
            data[rng.randrange(8, len(data))] = rng.randrange(256)
        if rng.random() < 0.3:
            del data[rng.randrange(8, len(data)):]
        data = bytes(data)
        if ph.dhash(data) != ph.dhash(data, fast=False):
            fuzz_bad.append(i)
    check("E 60 randomly damaged PNGs: Pillow path == pure path", not fuzz_bad, fuzz_bad)
    if have_pil:
        PI.frombytes = orig_fb
        # a PIL that raises must fall back to the pure path, not to "no hash"
        def boom(*a, **k):
            raise ValueError("boom")
        PI.frombytes = boom
        ok_png = png(37, 23, 6, seed=1, filt=4)
        got = ph.dhash(ok_png)
        check("E a Pillow exception falls back to the pure-Python result", got is not None and got == ph.dhash(ok_png, fast=False), got)
        PI.frombytes = orig_fb
    jpg_free = ph.dhash(b"\xff\xd8\xff\xe0 not really a jpeg")
    check("E a non-decodable JPEG still gives no hash", jpg_free is None, jpg_free)
except Exception as e:  # noqa: BLE001
    check("E scenario ran", False, repr(e))

print("PYFAILS=%d" % FAILS)
sys.exit(1 if FAILS else 0)
PY
[ $? -eq 0 ] && ok "in-process checks A-E" || fail "in-process checks A-E"

# ── F. through the real gate CLI ────────────────────────────────────────────────────────────────────────
R="$TMP/cli"; mkdir -p "$R/src" "$R/reports" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
git add -A && git commit -qm init
python3 - "$R" <<'PY'
import os, random, struct, sys, time, zlib
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
def png(seed):
    raw = b"".join(b"\x04" + random.Random(seed * 1000 + y).randbytes(120) for y in range(60))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 40, 60, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
r = sys.argv[1] + "/reports/"
for i in range(5):
    open(r + "old-%d.png" % i, "wb").write(png(i)); os.utime(r + "old-%d.png" % i, (time.time() - 5 * 86400,) * 2)
open(r + "proof-new.png", "wb").write(png(77))
open(r + "proof-new2.png", "wb").write(png(77))
PY
echo "fun ok() = 2" > src/Core.kt
out="$(DEVKIT_LANG=en CLAUDE_PROJECT_DIR="$R" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --allow-no-tests 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "identical bytes" \
  && ok "F two fresh identical proofs still REJECT through the CLI (exit $rc)" || fail "F duplicate proofs: exit $rc"
CACHE="$(cd "$R" && git rev-parse --git-common-dir)/postfix-gate/proof-hash-cache.json"
python3 - "$R/$CACHE" <<'PY' && ok "F the gate wrote a valid proof-hash cache in the git dir (5 old + 1 distinct fresh image)" || fail "F no valid cache at $CACHE"
import json, sys
d = json.load(open(sys.argv[1]))
assert len(d) == 6 and all(len(k) == 64 and isinstance(v, list) and len(v) == 2 for k, v in d.items()), d
PY
[ -z "$(find "$R" -name 'proof-hash-cache.json' -not -path '*/.git/*')" ] && ok "F the cache is not inside the audited tree" || fail "F the cache leaked into the tree"

echo
[ "$FAILS" -eq 0 ] && echo "ALL PASS" || echo "FAILURES: $FAILS"
exit "$FAILS"
