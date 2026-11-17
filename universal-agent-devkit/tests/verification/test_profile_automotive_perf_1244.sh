#!/usr/bin/env bash
# #1244: automotive profile has an IVI performance section and council, registered, with sourced budgets.
# Optional env: AUTO_PERF_RULES / AUTO_PERF_COUNCIL point at scratch copies (used to prove the test goes RED).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
P=profiles/automotive
RULES="${AUTO_PERF_RULES:-$P/rules/automotive-rules.md}"
COUNCIL="${AUTO_PERF_COUNCIL:-$P/councils/03-automotive-performance.md}"
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }

# RULES.md is a symlink to the rules file: that is what keeps them in sync.
[ -L "$P/RULES.md" ] && [ "$(readlink "$P/RULES.md")" = "rules/automotive-rules.md" ] \
  || fail "RULES.md must be a symlink to rules/automotive-rules.md"
grep -q 'Hiệu năng IVI' "$P/RULES.md" || fail "RULES.md missing heading 'Hiệu năng IVI'"
ok "RULES.md symlinks the rules file and carries the heading"

[ -f "$COUNCIL" ] || fail "council file missing"

python3 - "$P" "$DK" <<'PY' || exit 1
import json, os, sys
p, dk = sys.argv[1], sys.argv[2]
c = json.load(open(os.path.join(p, "profile.json")))["active_councils"]
assert "03-automotive-performance.md" in c, "council not in active_councils"
prev = ["01-automotive-hardware.md", "02-architecture-blast-radius.md", "03-zero-defect-tdd.md",
        "04-deterministic-ocr-review.md", "05-security-vulnerability.md", "07-performance-anr.md",
        "08-tiered-memory-governance.md", "02-automotive-compliance.md"]
for n in prev:
    assert n in c, "lost previous council " + n
for n in c:
    assert os.path.isfile(os.path.join(p, "councils", n)) or os.path.isfile(os.path.join(dk, "agents", "councils", n)), "unresolved council " + n
PY
ok "profile.json parses, keeps 8 old councils, all councils resolve"

sec=$(awk '/^## [0-9]+\. Hiệu năng IVI/{f=1;next} /^## [0-9]+\./{f=0} f' "$RULES")
[ -n "$sec" ] || fail "section body empty"
chk() { printf '%s' "$sec" | grep -qE -- "$2" || fail "section lacks: $1"; }
chk "launch/boot" 'khởi động app|boot IVI'
chk "key latency" 'phím vô lăng'
chk "frame/jank" 'jank'
chk "ANR/main thread" 'ANR'
chk "memory leak" 'rò rỉ'
chk "VHAL rate" 'sample rate'
chk "CAN" 'CAN'
chk "thermal/CPU" 'nhiệt'
chk "real-vehicle evidence" 'xe thật'
chk "no polling" 'CẤM poll'
ok "section covers all required topics"

# numbers and their source tags
chk "cold start 5 s tagged" 'cold start ≥ 5 s, warm ≥ 2 s, hot ≥ 1\.5 s \*\*\[AOSP/Android vitals\]\*\*'
chk "ANR 5 s / 10 s tagged" '5 s là ANR, broadcast foreground 10 s \*\*\[AOSP/Android vitals\]\*\*'
chk "ANR inference proposed" 'dư địa lớn \*\*\[đề xuất\]\*\*'
chk "jank council 07" 'jank ≤ 5% và ≥ 58 FPS \(60 Hz\) \*\*\[council 07\]\*\*'
chk "frozen frame tagged" '> 700 ms \*\*\[AOSP/Android vitals\]\*\*'
chk "CAN rate tagged" '100–500 Hz \*\*\[council A2 Agent 47'
chk "debounce 80 ms leading-edge" 'leading-edge.*≥ 80 ms'
chk "100 ms starts at key event" '≤ 100 ms.*từ thời điểm sự kiện phím tới.*không phải sau debounce'
chk "am start repeat proposed" 'lặp ≥ 3 lượt \*\*\[đề xuất\]\*\*'
chk "long drive proposed" '≥ 1 chu kỳ lái dài \*\*\[đề xuất\]\*\*'
chk "VHAL API 28 listener" 'API 28.*registerListener\(CarPropertyEventListener'
chk "VHAL API 30 callback" 'registerCallback\(CarPropertyEventCallback.*Android 11 \(API 30\)'
chk "VHAL SDK_INT guard" 'guard `Build\.VERSION\.SDK_INT`'
chk "min/max sample rate" 'getMinSampleRate\(\)`/`getMaxSampleRate\(\)'
chk "direct boot" 'LOCKED_BOOT_COMPLETED.*directBootAware'
chk "multi-user unlock" 'đa người dùng.*mở khoá'
chk "DESIGN.md referenced" 'DESIGN\.md'
chk "unmeasured label" 'CHƯA ĐO TRÊN XE'
ok "numeric budgets carry the right tags"

# agent ids named by the section exist
for id in $(printf '%s' "$sec" | grep -oE '`(ivi|automotive|can)-[a-z-]+auditor`' | tr -d '`' | sort -u); do
  grep -rqF "\`$id\`" "$COUNCIL" "$P/councils" 2>/dev/null || fail "agent id not defined in a council: $id"
done
for n in 51 52 53 54 55; do
  grep -q "^## Agent $n: " "$COUNCIL" || fail "council 03 lacks Agent $n"
done
for id in ivi-launch-boot-auditor ivi-key-latency-frame-auditor ivi-anr-memory-auditor ivi-vhal-can-rate-auditor ivi-thermal-io-evidence-auditor; do
  printf '%s' "$sec" | grep -qF "\`$id\`" || fail "section does not name $id"
done
ok "council agents 51-55 exist and section agent ids resolve"

# council 03 mirrors the fixes
grep -q 'registerListener(CarPropertyEventListener' "$COUNCIL" || fail "council Agent 54 lacks API 28 registerListener"
grep -q '\[council 07\]' "$COUNCIL" || fail "council Agent 52 lacks [council 07]"
grep -q 'cold ≥ 5 s, warm ≥ 2 s, hot ≥ 1.5 s \*\*\[AOSP/Android vitals\]\*\*' "$COUNCIL" || fail "council Agent 51 start thresholds untagged"
grep -q '100–500 Hz \*\*\[council A2 Agent 47\]\*\*' "$COUNCIL" || fail "council Agent 54 CAN rate untagged"
ok "council 03 carries the same tags"
echo "PASS"
