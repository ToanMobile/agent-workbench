#!/usr/bin/env bash
# #632 B: verdict_seal.verify only accepts a seal signed by the trusted public key, for the exact head and tree.
# Cases: RFC 8032 vector, valid seal, seal signed by another key, no seal, payload head != file head, tree mismatch (head
# rewritten in another repo), verdict fail is not a pass, test-key override ignored outside a test fixture / outside tmp,
# seal mode off when no key is installed.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
mkdir -p "$TMP/repo" && cd "$TMP/repo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo a > f && git add f && git commit -qm c1
BASE="$(git rev-parse HEAD)"
echo b > f && git commit -qam c2
HEAD_SHA="$(git rev-parse HEAD)"
export DEVKIT_VERDICT_SEAL_PUB="$TMP/seal.pub"
python3 - "$DEVKIT_DIR/bin" "$TMP" "$HEAD_SHA" "$BASE" <<'PY'
import base64, json, os, subprocess, sys
sys.path.insert(0, sys.argv[1]); import verdict_seal as vs
tmp, head, base = sys.argv[2:5]
fails = []
def check(name, cond):
    print(("✔ " if cond else "✖ ") + name); cond or fails.append(name)

# RFC 8032 §7.1 test 1
seed = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
pub = vs.public_key(seed)
sig = vs.sign(seed, b"")
check("rfc8032 pub", pub.hex() == "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
check("rfc8032 sig", sig.hex() == "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
check("rfc8032 verify", vs.ed25519_verify(pub, b"", sig))
check("rfc8032 tampered", not vs.ed25519_verify(pub, b"x", sig))

good, evil = b"\x01" * 32, b"\x02" * 32
open(os.path.join(tmp, "seal.pub"), "w").write(base64.b64encode(vs.public_key(good)).decode())
repo = os.path.join(tmp, "repo")
tree = subprocess.run(["git", "-C", repo, "rev-parse", head + "^{tree}"], capture_output=True, text=True).stdout.strip()

def write(key, **over):
    p = {"v": 1, "head": head, "tree": tree, "base": base, "edited": ["f"], "verdict": "pass", "ts": "t", "nonce": "n", "attempts": 1}
    p.update(over)
    s = json.dumps(p, sort_keys=True, separators=(",", ":"))
    os.makedirs(os.path.dirname(vs.seal_path(head)), exist_ok=True)
    json.dump({"payload": s, "sig": base64.b64encode(vs.sign(key, s.encode())).decode()}, open(vs.seal_path(head), "w"))

check("no seal -> None", vs.verify(repo, head, test_fixture=True) is None)
write(good)
got = vs.sealed_pass(repo, head, test_fixture=True)
check("valid seal -> payload with signed base", bool(got) and got["base"] == base and got["edited"] == ["f"])
check("override ignored without test fixture", vs.verify(repo, head, test_fixture=False) is None)
write(evil)
check("seal signed by another key -> None", vs.verify(repo, head, test_fixture=True) is None)
write(good, head="0" * 40)
check("payload head != head -> None", vs.verify(repo, head, test_fixture=True) is None)
write(good, tree="1" * 40)
check("tree mismatch -> None", vs.verify(repo, head, test_fixture=True) is None)
write(good, verdict="fail")
check("fail seal is not a pass", vs.verify(repo, head, test_fixture=True) is not None and vs.sealed_pass(repo, head, test_fixture=True) is None)
write(good, attempts=4)
check("pass past MAX_ATTEMPTS -> not a pass", vs.sealed_pass(repo, head, test_fixture=True) is None)
write(good, attempts=None)
check("attempts missing -> None", vs.verify(repo, head, test_fixture=True) is None)
write(good)
d = json.load(open(vs.seal_path(head))); d["payload"] = d["payload"].replace('"base":"' + base, '"base":"' + head)
json.dump(d, open(vs.seal_path(head), "w"))
check("payload edited after signing -> None", vs.verify(repo, head, test_fixture=True) is None)

# override outside tmp roots is ignored; with no root-owned key installed seal mode is off
os.environ["DEVKIT_VERDICT_SEAL_PUB"] = os.path.join(os.environ["HOME"].replace(tmp, "/Users/nobody-x"), "seal.pub")
check("override outside tmp ignored (fixture: mode off)", vs.trusted_pubkey(test_fixture=True) == (False, None))
del os.environ["DEVKIT_VERDICT_SEAL_PUB"]
check("no override: mode follows root-owned key file", vs.seal_mode() == os.path.lexists(vs.PUBKEY_PATH))
# review P3: non-canonical point (x = 0 with sign 1) is rejected (RFC 8032 §5.1.3)
check("non-canonical point rejected", vs._decompress(int.to_bytes((vs._P - 1) | (1 << 255), 32, "little")) is None)
# review P3: anchor in a dir macOS keeps root-owned; an absent key under a user-writable ancestor is NOT "off"
check("anchor under /private/etc", vs.PUBKEY_PATH.startswith("/private/etc/"))
saved = vs.PUBKEY_PATH
vs.PUBKEY_PATH = os.path.join(tmp, "nodir", "verdict-seal.pub")
check("absent key under user-writable ancestor: on, unreadable", vs.trusted_pubkey(test_fixture=False) == (True, None))
vs.PUBKEY_PATH = saved
check("fixture_repo: tmp repo yes", vs.fixture_repo(repo))
check("fixture_repo: the kit's own repo no", not vs.fixture_repo(os.path.dirname(os.path.dirname(sys.argv[1]))))
# review R1: a caller-set TMPDIR (parent of the real repo) must not turn the real repo, its pm home or a key into a "fixture"
import tempfile
real = os.path.realpath(os.path.dirname(os.path.dirname(sys.argv[1])))
parent = os.path.dirname(real)
os.environ["TMPDIR"] = parent; tempfile.tempdir = None
check("TMPDIR=parent of real repo: fixture_repo still no", not vs.fixture_repo(real))
os.environ["DEVKIT_VERDICT_SEAL_PUB"] = os.path.join(real, "evil.pub")
check("TMPDIR=parent of real repo: key override still ignored", vs.trusted_pubkey(test_fixture=True) == (False, None))
del os.environ["DEVKIT_VERDICT_SEAL_PUB"]
sys.path.insert(0, sys.argv[1]); import push_gate as pg
os.environ["DEVKIT_PM_HOME_TEST"] = "1"; os.environ["ANTIGRAVITY_PM_STATE_HOME"] = os.path.join(real, ".pm-evil")
check("TMPDIR=parent of real repo: pm home not a test fixture", not pg.pm_home_test_fixture())
os.environ["ANTIGRAVITY_PM_STATE_HOME"] = os.path.join(tmp, "pm")
print("ALL OK" if not fails else f"FAILS={len(fails)}")
sys.exit(1 if fails else 0)
PY
