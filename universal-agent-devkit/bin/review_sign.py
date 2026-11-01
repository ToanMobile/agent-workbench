#!/usr/bin/env python3
"""HMAC-SHA256 seal for review-fanout summaries (audit 31/10/2026: an agent could write summary.json {"verdict":"PASS"} itself).

The key lives OUTSIDE every repo: ~/.config/agent-workbench/review.key (created on first use, mode 600, the folder 700). Only
bin/review-merge.py (and review-fanout.sh's "nothing to review" path) sign; `review-fanout.sh --status` accepts a verdict only
when <summary.json>.sig matches the summary bytes. Unsigned, unreadable or mismatched = not a verdict.

  review_sign.py sign FILE      write FILE.sig — only for a review run's own summary: FILE is <...>/review-fanout/<H>/summary.json
                                and its meta.code_hash is H (r14d, BUG-REV-738b4fa129: it sealed any file it was pointed at), in
                                the review-fanout folder of meta.repo's git common dir (r23c: not /tmp/review-fanout/<H>)
  review_sign.py verify FILE    exit 0 when FILE.sig matches, 1 otherwise
A seal binds the code state it names: load_verified(FILE, H) reads the bytes ONCE, checks the MAC on them and returns the summary only
when its meta.code_hash is H (BUG-REV-7b0abde38e / 76e3be1a9d: a sealed PASS copied into another run dir, or one with no code_hash,
answered PASS there). Same uid, no privilege separation: the key is kept out of an agent's tool calls by hooks/guard-review-tamper.py
and hooks/guard-secrets.py, not by the OS.
"""
import hashlib
import hmac
import json
import os
import re
import secrets
import stat
import subprocess
import sys


def key_path():
    return os.path.join(os.path.expanduser("~"), ".config", "agent-workbench", "review.key")


def load_key(create=False):
    p = key_path()
    try:
        fd = os.open(p, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, "rb") as fh:
            st = os.fstat(fh.fileno())
            if not stat.S_ISREG(st.st_mode) or st.st_mode & 0o077 or st.st_uid != os.getuid():
                raise PermissionError(f"{p}: must be a regular file of this user with mode 600")
            key = fh.read(4096).strip()
            if len(key) < 32:
                raise ValueError(f"{p}: key too short")
            return key
    except FileNotFoundError:
        if not create:
            return None
    os.makedirs(os.path.dirname(p), mode=0o700, exist_ok=True)
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as fh:
        fh.write(secrets.token_hex(32).encode())
    return load_key(create=False)


def _mac(key, data):
    return hmac.new(key, b"review-fanout-summary-v1\0" + data, hashlib.sha256).hexdigest()


def _code_hash(data):
    try:
        d = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return None
    meta = d.get("meta") if isinstance(d, dict) else None
    h = meta.get("code_hash") if isinstance(meta, dict) else None
    return h if isinstance(h, str) and re.fullmatch(r"[0-9a-f]{64}", h) else None


def _fanout_dir(repo):
    """realpath of <git common dir of repo>/review-fanout, or None. GIT_* of the caller is dropped: GIT_DIR=<another git dir> must
    not move the answer."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    try:
        r = subprocess.run(["git", "-C", repo, "rev-parse", "--git-common-dir"], capture_output=True, text=True, timeout=15, env=env)
    except (OSError, subprocess.SubprocessError):
        return None
    common = r.stdout.strip()
    if r.returncode != 0 or not common:
        return None
    return os.path.realpath(os.path.join(repo, common, "review-fanout"))


def sign(path):
    real = os.path.realpath(path)
    run = os.path.dirname(real)
    if os.path.basename(real) != "summary.json" or os.path.basename(os.path.dirname(run)) != "review-fanout":
        raise ValueError(f"{path}: only a review run's summary.json (<git dir>/review-fanout/<code hash>/summary.json) is sealed")
    with open(real, "rb") as fh:
        data = fh.read()
    if _code_hash(data) != os.path.basename(run):
        raise ValueError(f"{path}: meta.code_hash is not its run directory {os.path.basename(run)[:12]} — not sealed")
    # the run dir must be the one review-fanout.sh keeps for that repo (r23c, BUG-REV 8ec050fad4): <git common dir of meta.repo>/
    # review-fanout, or — a summary that names no repo — of the git dir holding it; /tmp/review-fanout/<H> is never sealed
    try:
        meta = json.loads(data.decode("utf-8"))["meta"]
        repo = meta.get("repo") if isinstance(meta, dict) else None
        cdir = meta.get("common_dir") if isinstance(meta, dict) else None
    except (UnicodeDecodeError, ValueError, KeyError, TypeError, AttributeError):
        repo, cdir = None, None
    home = _fanout_dir(repo if isinstance(repo, str) and repo else os.path.dirname(os.path.dirname(run)))
    if home is None or os.path.dirname(run) != home:
        raise ValueError(f"{path}: not in the review-fanout folder of {repo or 'a git dir'} ({home or 'no git common dir'}) — not sealed")
    if cdir is not None and (not isinstance(cdir, str) or not cdir or os.path.join(os.path.realpath(cdir), "review-fanout") != home):
        raise ValueError(f"{path}: meta.common_dir ({cdir!r}) does not match {home} — not sealed")
    key = load_key(create=True)
    path = real
    tmp = path + ".sig.tmp"
    with open(tmp, "w") as fh:
        fh.write(_mac(key, data) + "\n")
    os.replace(tmp, path + ".sig")


def _sealed_bytes(path):
    """The file's bytes when FILE.sig matches them (one read), else None."""
    try:
        key = load_key(create=False)
        if not key:
            return None
        with open(path, "rb") as fh:
            data = fh.read()
        with open(path + ".sig") as fh:
            sig = fh.read().strip()
        return data if hmac.compare_digest(sig, _mac(key, data)) else None
    except (OSError, ValueError):
        return None


def verify(path):
    return _sealed_bytes(path) is not None


def load_verified(path, code_hash):
    """The summary dict when it is sealed, names code_hash, and — when meta.common_dir is set — sits in that common dir (bytes read once)."""
    data = _sealed_bytes(path)
    if data is None or not code_hash or _code_hash(data) != code_hash:
        return None
    d = json.loads(data.decode("utf-8"))
    meta = d.get("meta") if isinstance(d, dict) and isinstance(d.get("meta"), dict) else {}
    cdir = meta.get("common_dir")
    if cdir is not None:
        if not isinstance(cdir, str) or not cdir:
            return None
        if os.path.join(os.path.realpath(cdir), "review-fanout") != os.path.dirname(os.path.dirname(os.path.realpath(path))):
            return None
    return d


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("sign", "verify"):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    if sys.argv[1] == "sign":
        try:
            sign(sys.argv[2])
        except (OSError, ValueError) as e:
            print(f"review_sign: {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)
    sys.exit(0 if verify(sys.argv[2]) else 1)
