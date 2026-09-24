#!/usr/bin/env bash
# Regression: hardware source lint, vacuous-assertion lint, proof dHash,
# hardware-boundary match, bug-tag autolink, stale Unity lockfile removal.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
S="$DEVKIT_DIR/scripts"
B="$DEVKIT_DIR/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

python3 - <<PY
import sys
sys.path[:0] = ["$S", "$B"]
from pathlib import Path
import hardware_source_lint as hw
import assertion_lint as al
import proof_phash as ph
import hardware_boundaries as hb
import regression_checklist as rc
import struct, zlib

bad = hw.findings('ProcessBuilder("su")')
assert bad, "su"
assert not hw.findings('ProcessBuilder("echo")'), "echo"
assert hw.findings('new Socket(host, 5555)')
assert not hw.findings('new Socket(host, 8080)')
assert hw.findings('Runtime.getRuntime().exec("mount -o rw /system")')

kt = '''
class T {
  @Test fun empty() { val x = 1 }
  @Test fun vacuous() { assertTrue(true) }
  @Test fun real() { assertEquals(door, "left") }
  @Ignore @Test fun skipped() { }
}
'''
found = al.findings(kt)
lines = [n for n, _ in found]
assert 3 in lines and 4 in lines, found
assert 5 not in lines and 6 not in lines, found

def png_rows(rows):
    h, w = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")

flat = [[10] * 16 for _ in range(16)]
grad = [[255 if x < 8 else 0 for x in range(16)] for _ in range(16)]
a = ph.dhash(png_rows(flat))
b = ph.dhash(png_rows(flat))
c = ph.dhash(png_rows(grad))
assert a is not None and a == b, a
assert not ph.too_similar(a, c), (a, c, ph.similarity(a, c))
assert ph.too_similar(a, b)

proj = Path("$TMP/proj")
(proj / ".agents/context").mkdir(parents=True)
(proj / ".agents/context/hardware-boundaries.json").write_text(
    '{"boundaries":[{"id":"X","title":"kill","measured":"30s","symptoms":["30 giây"],"rescue":"overlay","watch":["CarConnect/*floater*"]}]}',
    encoding="utf-8")
rows = hb.load(proj)
assert hb.match_text(rows, "task bị xóa sau 30 giây")
assert not hb.match_text(rows, "đổi màu nút")
assert hb.match_paths(rows, ["CarConnect/app/floater/A.kt"])
assert not hb.match_paths(rows, ["PhoneConnect/app/A.kt"])

data = {"items": {"BUG-P1-10": {"id": "BUG-P1-10", "kind": "bug", "title": "speech", "state": "open", "fixed": False}}}
tests = proj / "Assets/_Project/Tests"
tests.mkdir(parents=True)
(tests / "SpeechTests.cs").write_text('public class SpeechTests { [Test] public void Bar() { /* [BUG-P1-10] */ Assert.AreEqual(1, n); } }', encoding="utf-8")
linked = rc.autolink_tags(proj, data)
assert linked == [("BUG-P1-10", "Assets/_Project/Tests/SpeechTests.cs")], linked
assert data["items"]["BUG-P1-10"]["fixed"] is False
assert rc.autolink_tags(proj, data) == []
print("py-ok")
PY
[ $? -eq 0 ] && ok "linters, dHash, boundaries, autolink" || fail "python checks"

bash -n "$DEVKIT_DIR/profiles/game/scripts/unity-batch.sh" && ok "unity-batch.sh syntax" || fail "unity-batch.sh syntax"
python3 -m py_compile "$B/post-fix-gate.py" "$B/regression_checklist.py" "$S/enrich_context.py" \
  && ok "py_compile gate" || fail "py_compile gate"

# Stale lock (dead pid) is removed. Live pid is kept.
ROOTL="$TMP/unity"
mkdir -p "$ROOTL/Temp"
echo 999999 > "$ROOTL/Temp/UnityLockfile"
# shellcheck disable=SC2016
bash -c '
ROOT="$1"
if [ -f "$ROOT/Temp/UnityLockfile" ]; then
  if pgrep -fi -- "projectpath[= ]*$ROOT" >/dev/null 2>&1; then exit 2; fi
  lock_pid="$(head -n 1 "$ROOT/Temp/UnityLockfile" | tr -cd "0-9" | cut -c1-12)"
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then exit 3; fi
  rm -f "$ROOT/Temp/UnityLockfile"
fi
' _ "$ROOTL"
[ ! -f "$ROOTL/Temp/UnityLockfile" ] && ok "dead lock pid removed" || fail "dead lock pid not removed"

echo $$ > "$ROOTL/Temp/UnityLockfile"
bash -c '
ROOT="$1"
lock_pid="$(head -n 1 "$ROOT/Temp/UnityLockfile" | tr -cd "0-9" | cut -c1-12)"
if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then exit 3; fi
rm -f "$ROOT/Temp/UnityLockfile"
exit 0
' _ "$ROOTL"
rc=$?
[ "$rc" -eq 3 ] && [ -f "$ROOTL/Temp/UnityLockfile" ] && ok "live lock pid kept" || fail "live lock pid rc=$rc"

echo
[ "$FAILS" -eq 0 ] && echo "ALL PASS" || echo "FAILURES: $FAILS"
exit "$FAILS"
