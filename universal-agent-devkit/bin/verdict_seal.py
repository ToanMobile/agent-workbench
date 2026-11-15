#!/usr/bin/env python3
"""Verdict seal of an Antigravity audit (#632 B): verify a seal signed by the owner's Keychain key, or request one.

A seal is `<pm home>/seals/<head>.json` = {"payload": "<canonical JSON>", "sig": "<base64 Ed25519 signature of payload>"}.
The payload {v, head, tree, base, edited, verdict, ts, nonce} is built and signed by `verdict-seal-audit`, which runs as the
uid `_devkitseal` (sudoers entry, root-owned script): it clones the repo, computes base/edited itself, runs agy and has the
Swift signer (Keychain key of `_devkitseal`) sign the result. The agent's uid cannot read that key, so it cannot forge a seal.

Seal mode is ON only when the trusted public key exists: /usr/local/etc/devkit/verdict-seal.pub, owned by root, not group/other
writable, every parent dir root-owned and not group/other writable. No environment variable turns it off. Tests may point at
another key with DEVKIT_VERDICT_SEAL_PUB only when the caller says it runs a test fixture (push_gate.pm_home_test_fixture()) AND
that key sits under a system temp dir.

Verification is pure Python (RFC 8032 Ed25519 over hashlib.sha512): no `cryptography`, no openssl (LibreSSL on macOS has no Ed25519).
"""
import base64
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile

PUBKEY_PATH = "/usr/local/etc/devkit/verdict-seal.pub"
AUDIT_ENTRY = "/usr/local/libexec/devkit/verdict-seal-audit"
SEAL_USER = "_devkitseal"
TEST_TMP_ROOTS = ("/tmp", "/private/tmp", "/var/folders", "/private/var/folders")
SHA40 = re.compile(r"[0-9a-f]{40}")
MAX_SEAL_BYTES = 1_000_000

# ---- Ed25519 (RFC 8032 §5.1), verification + signing (signing is used by tests only; trust is the pubkey) ----
_P = 2 ** 255 - 19
_L = 2 ** 252 + 27742317777372353535851937790883648493
_D = -121665 * pow(121666, _P - 2, _P) % _P
_I = pow(2, (_P - 1) // 4, _P)


def _inv(x):
    return pow(x, _P - 2, _P)


def _add(a, b):
    x1, y1, z1, t1 = a
    x2, y2, z2, t2 = b
    A = (y1 - x1) * (y2 - x2) % _P
    B = (y1 + x1) * (y2 + x2) % _P
    C = t1 * 2 * _D * t2 % _P
    Dd = z1 * 2 * z2 % _P
    E, F, G, H = B - A, Dd - C, Dd + C, B + A
    return (E * F % _P, G * H % _P, F * G % _P, E * H % _P)


def _mul(s, pt):
    q = (0, 1, 1, 0)
    while s > 0:
        if s & 1:
            q = _add(q, pt)
        pt = _add(pt, pt)
        s >>= 1
    return q


def _equal(a, b):
    x1, y1, z1, _ = a
    x2, y2, z2, _ = b
    return (x1 * z2 - x2 * z1) % _P == 0 and (y1 * z2 - y2 * z1) % _P == 0


def _recover_x(y, sign):
    if y >= _P:
        return None
    x2 = (y * y - 1) * _inv(_D * y * y + 1)
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P != 0:
        x = x * _I % _P
    if (x * x - x2) % _P != 0:
        return None
    if (x & 1) != sign:
        x = _P - x
    return x


_GY = 4 * _inv(5) % _P
_G = (_recover_x(_GY, 0), _GY, 1, _recover_x(_GY, 0) * _GY % _P)


def _compress(pt):
    x, y, z, _ = pt
    zi = _inv(z)
    x, y = x * zi % _P, y * zi % _P
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def _decompress(s):
    if len(s) != 32:
        return None
    y = int.from_bytes(s, "little")
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _recover_x(y, sign)
    return None if x is None else (x, y, 1, x * y % _P)


def _h(m):
    return int.from_bytes(hashlib.sha512(m).digest(), "little")


def _secret_expand(seed):
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little")
    a &= (1 << 254) - 8
    a |= 1 << 254
    return a, h[32:]


def public_key(seed):
    """32-byte public key of a 32-byte seed (tests)."""
    a, _ = _secret_expand(seed)
    return _compress(_mul(a, _G))


def sign(seed, msg):
    """64-byte Ed25519 signature (tests; the real signer is the Swift binary in Keychain's custody)."""
    a, prefix = _secret_expand(seed)
    A = _compress(_mul(a, _G))
    r = _h(prefix + msg) % _L
    R = _compress(_mul(r, _G))
    k = _h(R + A + msg) % _L
    return R + int.to_bytes((r + k * a) % _L, 32, "little")


def ed25519_verify(pub, msg, sig):
    if len(pub) != 32 or len(sig) != 64:
        return False
    A = _decompress(pub)
    R = _decompress(sig[:32])
    if A is None or R is None:
        return False
    s = int.from_bytes(sig[32:], "little")
    if s >= _L:
        return False
    k = _h(sig[:32] + pub + msg) % _L
    return _equal(_mul(s, _G), _add(R, _mul(k, A)))


# ---- trust anchor ----
def _under_tmp(path):
    real = os.path.realpath(path)
    roots = {os.path.realpath(r) for r in (tempfile.gettempdir(), *TEST_TMP_ROOTS)}
    return any(real.startswith(r.rstrip(os.sep) + os.sep) for r in roots if r and r != os.sep)


def _root_owned_chain(path):
    """True when `path` and every parent dir are owned by root and not writable by group/other (no symlink tricks: lstat)."""
    p = path
    while True:
        try:
            st = os.lstat(p)
        except OSError:
            return False
        if stat.S_ISLNK(st.st_mode) or st.st_uid != 0 or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            return False
        parent = os.path.dirname(p)
        if parent == p:
            return True
        p = parent


def _read_pub(path):
    try:
        with open(path, encoding="ascii") as f:
            raw = base64.b64decode(f.read().strip(), validate=True)
    except (OSError, ValueError):
        return None
    return raw if len(raw) == 32 else None


def trusted_pubkey(test_fixture=False):
    """(mode_on, pubkey bytes|None). mode_on False → seal mode off (key not installed): callers keep today's behaviour.
    mode_on True with None → installed but unreadable/corrupt: callers must refuse every audit (fail closed)."""
    override = os.environ.get("DEVKIT_VERDICT_SEAL_PUB")
    if override and test_fixture and _under_tmp(override):
        return True, _read_pub(override)
    if not os.path.lexists(PUBKEY_PATH):
        return False, None
    if not _root_owned_chain(PUBKEY_PATH):
        return True, None
    return True, _read_pub(PUBKEY_PATH)


def seal_mode(test_fixture=False):
    return trusted_pubkey(test_fixture)[0]


# ---- seals ----
def pm_state_home():
    return os.path.expanduser(os.environ.get("ANTIGRAVITY_PM_STATE_HOME") or os.path.join("~", ".antigravity-pm"))


def seal_path(head):
    return os.path.join(pm_state_home(), "seals", f"{head}.json")


def _git(top, *args):
    r = subprocess.run(["git", "-C", top, *args], capture_output=True, text=True, timeout=30)
    return r.returncode, r.stdout.strip()


def verify(top, head, test_fixture=False):
    """Signed payload (dict) of the seal of `head` when it is valid for repo `top`; None otherwise (also when seal mode is off).
    Valid = Ed25519 signature of the trusted pubkey over payload, v == 1, payload.head == head, payload.tree == tree(head) in top,
    base a sha40, edited a list of str, verdict in (pass, fail)."""
    if not isinstance(head, str) or not SHA40.fullmatch(head):
        return None
    on, pub = trusted_pubkey(test_fixture)
    if not on or pub is None:
        return None
    try:
        path = seal_path(head)
        st = os.stat(path)
        if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_SEAL_BYTES:
            return None
        with open(path, encoding="utf-8") as f:
            seal = json.load(f)
        payload_s, sig = seal["payload"], base64.b64decode(seal["sig"], validate=True)
        if not isinstance(payload_s, str) or not ed25519_verify(pub, payload_s.encode("utf-8"), sig):
            return None
        payload = json.loads(payload_s)
        if not isinstance(payload, dict) or payload.get("v") != 1 or payload.get("head") != head:
            return None
        base, edited = payload.get("base"), payload.get("edited")
        if not isinstance(base, str) or not SHA40.fullmatch(base) or not isinstance(edited, list) \
                or not all(isinstance(e, str) for e in edited) or payload.get("verdict") not in ("pass", "fail"):
            return None
        rc, tree = _git(top, "rev-parse", "--verify", "-q", head + "^{tree}")
        if rc != 0 or not isinstance(payload.get("tree"), str) or tree != payload["tree"]:
            return None
        return payload
    except (OSError, ValueError, KeyError, TypeError, RecursionError, subprocess.SubprocessError):
        return None


def sealed_pass(top, head, test_fixture=False):
    """Payload of a valid PASS seal of `head`, or None."""
    p = verify(top, head, test_fixture)
    return p if p and p["verdict"] == "pass" else None


def request(repo, head):
    """Run the owner-installed audit entry as _devkitseal (sudo -n, no password) and store its seal; exit code of the run."""
    if not SHA40.fullmatch(head or ""):
        print("verdict-seal: --head must be a sha40", file=sys.stderr)
        return 2
    if not os.path.isfile(AUDIT_ENTRY):
        print(f"verdict-seal: {AUDIT_ENTRY} not installed (owner one-time setup: docs/verdict-seal-setup.md)", file=sys.stderr)
        return 3
    r = subprocess.run(["sudo", "-n", "-u", SEAL_USER, AUDIT_ENTRY, "--repo", os.path.realpath(repo), "--head", head],
                       capture_output=True, text=True, timeout=1800)
    if r.returncode != 0:
        print(f"verdict-seal: audit run failed (exit {r.returncode}): {r.stderr.strip()[-2000:]}", file=sys.stderr)
        return r.returncode or 1
    try:
        seal = json.loads(r.stdout)
        if not isinstance(seal.get("payload"), str) or not isinstance(seal.get("sig"), str):
            raise ValueError("seal shape")
    except (ValueError, AttributeError) as e:
        print(f"verdict-seal: audit run printed no seal ({e})", file=sys.stderr)
        return 1
    path = seal_path(head)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + f".tmp{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(seal, f)
    os.replace(tmp, path)
    verdict = json.loads(seal["payload"]).get("verdict")
    print(f"verdict-seal: {head[:12]} sealed, verdict {verdict} → {path}")
    return 0 if verdict == "pass" else 4


def main(argv):
    import argparse  # noqa: PLC0415
    ap = argparse.ArgumentParser(prog="verdict_seal.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("verify", help="exit 0 when head has a valid PASS seal")
    v.add_argument("--repo", default=".")
    v.add_argument("--head", required=True)
    q = sub.add_parser("request", help="run the sealed audit (as _devkitseal) and store the seal")
    q.add_argument("--repo", default=".")
    q.add_argument("--head", required=True)
    sub.add_parser("status", help="print whether seal mode is on")
    a = ap.parse_args(argv)
    if a.cmd == "status":
        on, pub = trusted_pubkey()
        print("seal mode: " + ("off (no trusted pubkey)" if not on else "on" if pub else "on, pubkey UNREADABLE (all audits refused)"))
        return 0
    if a.cmd == "verify":
        p = sealed_pass(a.repo, a.head)
        print(json.dumps(p) if p else "verdict-seal: no valid pass seal", file=sys.stdout if p else sys.stderr)
        return 0 if p else 1
    return request(a.repo, a.head)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
