#!/usr/bin/env bash
# #1248: profile ios stands alone (no merged mobile profile) and carries performance, quality and UI/UX.
# Oracle for: old iOS rules kept, new sections present, numeric budgets pinned and sourced, every named
# skill/agent/council exists in the kit and is not excluded, and NO Android wording anywhere in profiles/ios
# except a short explicit set of pointer lines (blockquote lines tagged [Android], at most 3).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
P=profiles/ios
R=$P/rules/ios-rules.md
D=$P/DESIGN.md
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILS=0
ok()   { echo "ok: $1"; }
fail() { echo "FAIL: $1" >&2; FAILS=$((FAILS + 1)); }
has()  { grep -qF -- "$2" "$1" && ok "$3" || fail "$3 (missing: $2)"; }
LABEL='mặc định đề xuất của dự án, cần đo trên máy thật'

# scope: text of the sections added by #1248
sed -n '/^## 6\. Quy tắc chung/,$p' $R > $T/rules-new.md
sed -n '/^# Đặc tả iOS/,$p' $D > $T/design-new.md

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
for t in '[weak self]' 'weak var delegate' 'autoreleasepool' '@MainActor' 'withTaskGroup' 'Task.isCancelled' 'DateFormatter' \
         '.disabled(isLoading)' 'leaks -atExit' '.safeAreaInset(edge: .bottom)' 'presentationDetents' 'Mandatory 4 trạng thái' 'taste-mobile-app'; do
  has $R "$t" "old rule: $t"
done

# 3. new sections and terms, scoped to the new text
for h in '## 6. Quy tắc chung' '## 7. Hiệu năng iOS' '## 8. Chất lượng' '## 9. UI/UX & Accessibility' '## 10. Bộ công cụ theo tình huống'; do
  has $T/rules-new.md "$h" "section: $h"
done
for t in MetricKit 'Animation Hitches' 'XCTHitchMetric' 'XCTApplicationLaunchMetric' 'XCTMemoryMetric' 'thermalState' \
         'Swift Testing' 'swiftlint --strict' 'strict-concurrency=complete' 'performAccessibilityAudit' 'Cách nghiệm thu' \
         'accessibilityReduceMotion' 'Dynamic Type' 'VoiceOver' 'máy thật' 'Ngưỡng chặn PASS'; do
  has $T/rules-new.md "$t" "new rule term: $t"
done
for t in 'Dynamic Type' 'VoiceOver' 'Dark Mode' 'Reduce Motion' 'Haptic' 'Zero-Slop' 'systemBackground' 'Spacing' '44'; do
  has $T/design-new.md "$t" "DESIGN.md term: $t"
done
# OS availability and re-check labels (item 5)
for t in 'XCTHitchMetric` (Xcode 15+' 'performAccessibilityAudit()` (iOS 17' 'ContentUnavailableView` (iOS 17+' 'AccessibilityNotification` (iOS 17+' \
         '.sensoryFeedback` (iOS 17+' 'kiểm lại tài liệu hiện hành' 'fallback'; do
  has $T/rules-new.md "$t" "availability: $t"
done
# hitch bands and thermal label
has $T/rules-new.md '5–10' "hitch band warning"
has $T/rules-new.md '> 10 ms' "hitch band critical"
grep -F '.serious' $T/rules-new.md | grep -qF "$LABEL" && ok "thermal .serious line carries the proposal label" || fail "thermal .serious line lacks the proposal label"

# 4. numeric budgets pinned, each budget row sourced; mutation self-check
check_numbers() {  # $1 = rules file; prints failures, returns 1 on any
  local f=$1 bad=0 s
  s=$(sed -n '/^## 6\. Quy tắc chung/,$p' "$f")
  for pat in 'Dưới 5 ms mỗi giây là "tốt"' '250 ms' '16,6 ms/khung' '8,3 ms/khung' '≥ 58 FPS' '≥ 115 FPS' '400 ms' '≥ 44×44 pt' '5–10' '> 10 ms'; do
    printf '%s' "$s" | grep -qF -- "$pat" || { echo "missing number: $pat"; bad=1; }
  done
  # each numeric row of the 7.1 table must carry a source tag or the exact label
  sed -n '/^### 7\.1/,/^### 7\.2/p' "$f" | grep '^| ' | grep -vE '^\| (Chỉ số|---)' | while IFS= read -r row; do
    echo "$row" | grep -qE "mặc định đề xuất của dự án, cần đo trên máy thật|Phép tính|Apple|council|DevKit essentials" || echo "unsourced row: $row"
  done > "$T/unsourced.txt"
  [ -s "$T/unsourced.txt" ] && { cat "$T/unsourced.txt"; bad=1; }
  # the 400 ms launch and 10-loop leak rows must carry the exact label
  grep -F 'Khởi động nguội' "$f" | grep -qF "$LABEL" || { echo "launch row lacks label"; bad=1; }
  return $bad
}
check_numbers $R >$T/cn.out 2>&1 && ok "numeric budgets pinned and every budget row sourced" || fail "numeric budgets: $(cat $T/cn.out)"
sed 's/dưới 5 ms/dưới 9 ms/; s/Dưới 5 ms mỗi giây/Dưới 9 ms mỗi giây/' $R > $T/mut1.md
check_numbers $T/mut1.md >/dev/null 2>&1 && fail "mutation (hitch 5 -> 9) was not detected" || ok "mutation hitch 5->9 detected"
sed 's/250 ms/300 ms/g' $R > $T/mut2.md
check_numbers $T/mut2.md >/dev/null 2>&1 && fail "mutation (hang 250 -> 300) was not detected" || ok "mutation hang 250->300 detected"
sed 's/mặc định đề xuất của dự án, cần đo trên máy thật/xxx/' $R > $T/mut3.md
check_numbers $T/mut3.md >/dev/null 2>&1 && fail "mutation (label removed) was not detected" || ok "mutation label removed detected"
sed 's/| Phép tính từ tần số quét |/| (không nguồn) |/' $R > $T/mut4.md
check_numbers $T/mut4.md >/dev/null 2>&1 && fail "mutation (source removed) was not detected" || ok "mutation source removed detected"

# 5. every skill/agent/council named (backtick prefix form or prose form) exists and is not excluded
{ grep -ohE '`(skill|agent|council):[A-Za-z0-9_-]+`' $R $D | tr -d '`'
  grep -ohE '\b(skill|agent|council) `[A-Za-z0-9_-]+`' $R $D | sed -E 's/ `/:/; s/`//'; } | sort -u > $T/refs.txt
[ -s $T/refs.txt ] && ok "toolkit references found ($(wc -l < $T/refs.txt | tr -d ' '))" || fail "no toolkit references"
while IFS= read -r r; do
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
done < $T/refs.txt
for need in taste-mobile-app ui-ux-pro-max impeccable tdd-workflow qc verification-before-completion observability-instrumentation security-checklist open-code-review; do
  grep -qF "\`skill:$need\`" $R || fail "toolkit misses skill:$need"
done
for need in test-architect-seti real-device-ui-auditor mobile-release-auditor principal-code-reviewer; do
  grep -qF "\`agent:$need\`" $R || fail "toolkit misses agent:$need"
done
grep -qF '`council:07-performance-anr`' $R || fail "toolkit misses council:07-performance-anr"
ok "toolkit coverage checked"

# 6. no Android wording anywhere in profiles/ios prose (all .md files, all lines; profile.json exclude lists name Android-only skills on purpose) except <= 3 tagged pointer lines
ANDROID='[Aa]ndroid|Jetpack|Compose|Gradle|\badb\b|Kotlin|Hilt|\bRoom\b|logcat|TalkBack|Perfetto|Macrobenchmark|\bdp\b|\bsp\b|\\text\{(dp|sp)\}|Material Design|LeakCanary|ProGuard|\bR8\b|Binder|runBlocking|Thread\.sleep|Vector Drawable'
hits=$(grep -rnE "$ANDROID" $P --include='*.md' | grep -v 'instincts.md:.*INSTINCT' || true)
bad=$(printf '%s\n' "$hits" | grep -v '^$' | grep -vE '^[^:]+:[0-9]+:> .*\[Android\]' || true)
[ -z "$bad" ] && ok "no Android wording outside tagged pointer lines" || fail "Android wording in profiles/ios: $bad"
n=$(printf '%s\n' "$hits" | grep -cE ':[0-9]+:> .*\[Android\]')
[ "$n" -le 3 ] && ok "Android pointer lines: $n (max 3)" || fail "too many Android pointer lines: $n"

[ $FAILS -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$FAILS FAILED" >&2; exit 1; }
