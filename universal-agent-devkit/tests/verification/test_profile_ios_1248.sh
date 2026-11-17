#!/usr/bin/env bash
# #1248: profile ios stands alone (no merged mobile profile) and carries performance, quality and UI/UX.
# Oracle for: old iOS rules kept, new sections present, every named skill/agent/council exists in the kit
# and is not excluded by the profile, no Android-only guidance beyond a pointer, numbers carry a label.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
P=profiles/ios
R=$P/rules/ios-rules.md
D=$P/DESIGN.md
FAILS=0
ok()   { echo "ok: $1"; }
fail() { echo "FAIL: $1" >&2; FAILS=$((FAILS + 1)); }
has()  { grep -qF -- "$2" "$1" && ok "$3" || fail "$3 (missing: $2)"; }

# 1. profile.json paths, councils, MCPs resolve
python3 - "$DK" <<'PY' && ok "profile.json paths/councils/mcps resolve" || fail "profile.json references do not resolve"
import json, os, sys
dk = sys.argv[1]
p = json.load(open(os.path.join(dk, "profiles/ios/profile.json")))
bad = []
for k in ("rules_file", "regression_matrix"):
    if not os.path.isfile(os.path.join(dk, p[k])):
        bad.append(p[k])
for c in p["active_councils"]:
    if not os.path.isfile(os.path.join(dk, "agents/councils", c)):
        bad.append(c)
mcps = json.load(open(os.path.join(dk, "mcp_config.json"))).get("mcpServers", {})
for m in p["essential_mcps"]:
    if m not in mcps:
        bad.append("mcp:" + m)
if "07-performance-anr.md" not in p["active_councils"]:
    bad.append("council 07 not active")
print(bad, file=sys.stderr) if bad else None
sys.exit(1 if bad else 0)
PY
[ -L $P/RULES.md ] && [ "$(readlink $P/RULES.md)" = "rules/ios-rules.md" ] && ok "RULES.md symlink intact" || fail "RULES.md symlink"

# 2. old iOS rules still there
has $R '[weak self]' "old: weak self"
has $R 'weak var delegate' "old: weak delegate"
has $R 'autoreleasepool' "old: autoreleasepool"
has $R '@MainActor' "old: MainActor"
has $R 'withTaskGroup' "old: structured concurrency"
has $R 'Task.isCancelled' "old: cancellation"
has $R 'DateFormatter' "old: cached formatters"
has $R '.disabled(isLoading)' "old: disable on first tap"
has $R 'leaks -atExit' "old: leaks CLI"
has $R '.safeAreaInset(edge: .bottom)' "old: safe area inset"
has $R 'presentationDetents' "old: sheet detents"
has $R 'Mandatory 4 trạng thái' "old: 4 states"
has $R 'taste-mobile-app' "old: taste-mobile-app"

# 3. new sections present
for h in '## 6. Quy tắc chung' '## 7. Hiệu năng iOS' '## 8. Chất lượng' '## 9. UI/UX & Accessibility' '## 10. Bộ công cụ theo tình huống'; do
  has $R "$h" "section: $h"
done
for t in MetricKit 'Animation Hitches' 'XCTHitchMetric' 'XCTApplicationLaunchMetric' 'XCTMemoryMetric' 'thermalState' \
         'Swift Testing' 'swiftlint --strict' 'strict-concurrency=complete' 'performAccessibilityAudit' 'Cách nghiệm thu' \
         'accessibilityReduceMotion' 'Dynamic Type' 'VoiceOver' 'máy thật'; do
  has $R "$t" "new rule term: $t"
done
for t in 'Dynamic Type' 'VoiceOver' 'Dark Mode' 'Reduce Motion' 'Haptic' 'Zero-Slop' 'systemBackground' 'Spacing' '44'; do
  has $D "$t" "DESIGN.md term: $t"
done

# 4. numbers carry a source or the proposal label
n=$(grep -cF 'mặc định đề xuất của dự án, cần đo trên máy thật' $R)
[ "$n" -ge 5 ] && ok "proposal label used ($n)" || fail "proposal label used only $n times"
for t in '250 ms' '16,6 ms' '8,3 ms'; do has $R "$t" "budget present: $t"; done

# 5. every skill:/agent:/council: named exists in the kit and is not excluded by the profile
refs=$(grep -ohE '`(skill|agent|council):[A-Za-z0-9_-]+`' $R | tr -d '`' | sort -u)
[ -n "$refs" ] && ok "toolkit references found" || fail "no skill:/agent:/council: references in §10"
for r in $refs; do
  kind=${r%%:*}; name=${r#*:}
  case $kind in
    skill)   [ -f skills/$name/SKILL.md ] || fail "skill $name does not exist" ;;
    agent)   [ -f agents/$name.md ] || fail "agent $name does not exist" ;;
    council) ls agents/councils/${name}*.md >/dev/null 2>&1 || fail "council $name does not exist" ;;
  esac
  python3 - "$P/profile.json" "$kind" "$name" <<'PY' || fail "$r is excluded by profile.json but referenced"
import json, sys
p = json.load(open(sys.argv[1])); kind, name = sys.argv[2], sys.argv[3]
ex = p.get("exclude_skills", []) if kind == "skill" else p.get("exclude_agents", []) if kind == "agent" else []
sys.exit(1 if name in ex else 0)
PY
done
for need in taste-mobile-app ui-ux-pro-max impeccable tdd-workflow qc verification-before-completion observability-instrumentation security-checklist open-code-review; do
  grep -qF "\`skill:$need\`" $R || fail "toolkit misses skill:$need"
done
for need in test-architect-seti real-device-ui-auditor mobile-release-auditor principal-code-reviewer; do
  grep -qF "\`agent:$need\`" $R || fail "toolkit misses agent:$need"
done
grep -qF '`council:07-performance-anr`' $R || fail "toolkit misses council:07-performance-anr"
ok "toolkit coverage checked"

# 6. no Android-only guidance outside the single pointer line (rules and DESIGN.md)
# DESIGN.md keeps the shared kit table (sections 1-5, dp/sp) untouched; only the iOS part (from its marker) is scanned.
sed -n '/^# Đặc tả iOS/,$p' $D > "${TMPDIR:-/tmp}/ios-design-part.$$"
for f in $R "${TMPDIR:-/tmp}/ios-design-part.$$"; do
  bad=$(grep -nE 'Jetpack|Compose|Gradle|\badb\b|Kotlin|Hilt|Room\b|logcat|TalkBack|Perfetto|Macrobenchmark|\bdp\b|\bsp\b|Material|LeakCanary|ProGuard|R8\b' $f | grep -vE 'chỉ Android|Android-only|bảng chung' || true)
  [ -z "$bad" ] && ok "no Android clutter in $f" || fail "Android-only content in $f: $bad"
done
rm -f "${TMPDIR:-/tmp}/ios-design-part.$$"
[ "$(grep -cE 'chỉ Android|Android-only' $R)" -le 3 ] && ok "Android pointer is brief" || fail "too many Android pointers"

[ $FAILS -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$FAILS FAILED" >&2; exit 1; }
