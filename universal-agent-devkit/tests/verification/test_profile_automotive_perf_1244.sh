#!/usr/bin/env bash
# #1244: automotive profile has an IVI performance section and council, registered and in sync.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
P=profiles/automotive
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }

for f in "$P/RULES.md" "$P/rules/automotive-rules.md"; do
  grep -q 'Hiệu năng IVI' "$f" || fail "$f missing heading 'Hiệu năng IVI'"
done
ok "heading in RULES.md and automotive-rules.md"

[ -f "$P/councils/03-automotive-performance.md" ] || fail "council file missing"

python3 - "$P" "$DK" <<'PY' || exit 1
import json, os, sys
p, dk = sys.argv[1], sys.argv[2]
d = json.load(open(os.path.join(p, "profile.json")))
c = d["active_councils"]
assert "03-automotive-performance.md" in c, "council not in active_councils"
prev = ["01-automotive-hardware.md", "02-architecture-blast-radius.md", "03-zero-defect-tdd.md",
        "04-deterministic-ocr-review.md", "05-security-vulnerability.md", "07-performance-anr.md",
        "08-tiered-memory-governance.md", "02-automotive-compliance.md"]
for n in prev:
    assert n in c, "lost previous council " + n
for n in c:
    ok = os.path.isfile(os.path.join(p, "councils", n)) or os.path.isfile(os.path.join(dk, "agents", "councils", n))
    assert ok, "council does not resolve to a file: " + n
PY
ok "profile.json parses, keeps 8 old councils, all councils resolve"

# extract the section text
sec=$(awk '/^## [0-9]+\. Hiệu năng IVI/{f=1;next} /^## [0-9]+\./{f=0} f' "$P/RULES.md")
[ -n "$sec" ] || fail "section body empty"
chk() { printf '%s' "$sec" | grep -qiE "$2" || fail "section lacks: $1"; }
chk "launch/boot" 'khởi động app|launch|boot'
chk "key latency" 'phím vô lăng'
chk "frame/jank" 'jank'
chk "ANR/main thread" 'ANR'
chk "memory leak" 'rò rỉ'
chk "VHAL rate" 'sample ?rate|tần suất'
chk "CAN" 'CAN'
chk "thermal/CPU" 'thermal|nhiệt'
chk "real-vehicle evidence" 'xe thật'
ok "section covers all required topics"

# sync: the section text is identical in both files
a=$(awk '/^## [0-9]+\. Hiệu năng IVI/{f=1} f' "$P/RULES.md")
b=$(awk '/^## [0-9]+\. Hiệu năng IVI/{f=1} f' "$P/rules/automotive-rules.md")
[ "$a" = "$b" ] || fail "RULES.md and automotive-rules.md section differ"
ok "files in sync"
echo "PASS"
