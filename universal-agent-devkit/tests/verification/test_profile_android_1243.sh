#!/usr/bin/env bash
# #1243: profiles/android keeps every old rule and gains the common rules, performance, quality,
# UI/UX and toolkit sections (Android only). No merged `mobile` profile. Structural checks only.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
P=profiles/android
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }

[ ! -e profiles/mobile ] || fail "profiles/mobile must not exist (owner decision 17/11: android and ios stay separate)"
[ -f "$P/profile.json" ] || fail "$P/profile.json missing"
python3 -I - "$P/profile.json" <<'PY' || exit 1
import json, os, sys
d = json.load(open(sys.argv[1]))
assert d["id"] == "android", "id is %r" % d["id"]
for k in ("name", "description", "description_en"):
    assert d.get(k), "missing " + k
for k in ("rules_file", "regression_matrix"):
    assert os.path.isfile(d[k]), "%s -> %s does not exist" % (k, d[k])
assert d["rules_file"] == "profiles/android/rules/android-rules.md"
assert d["regression_matrix"] == "profiles/android/regression_matrix.json"
councils = d["active_councils"]
assert len(councils) == 9 and len(set(councils)) == 9, "expected 9 distinct councils, got %d" % len(councils)
for c in councils:
    assert os.path.isfile("agents/councils/" + c), "council %s does not resolve" % c
assert "06-game-unity-blender.md" not in councils, "game council does not belong to android"
assert len(d["essential_mcps"]) == len(set(d["essential_mcps"])), "duplicate mcp"
cfg = json.load(open("mcp_config.json"))
servers = cfg.get("mcpServers", cfg)
for m in ("codebase-memory-mcp", "context7", "android-code-search", "android-skills", "mobile-mcp"):
    assert m in d["essential_mcps"], m
for m in d["essential_mcps"]:
    assert m in servers, "mcp %s not in mcp_config.json" % m
for e in (".kt", ".kts", ".java"):
    assert e in d["source_extensions"], e
for e in (".swift", ".m", ".mm"):
    assert e not in d["source_extensions"], "android must not carry " + e
for s in ("android-real-device-qa", "compose-recomp-audit"):
    assert s not in d["exclude_skills"], s
assert "android-principal-architect" not in d["exclude_agents"]
m = json.load(open(d["regression_matrix"]))
assert m["rules"], "matrix empty"
PY
ok "profile.json parses, id android, 9 councils and paths resolve, no profiles/mobile"

R="$P/rules/android-rules.md"
[ -f "$R" ] || fail "$R missing"
[ "$(readlink "$P/RULES.md" 2>/dev/null)" = "rules/android-rules.md" ] || fail "RULES.md symlink wrong"
need() { grep -qF -- "$1" "$R" || fail "android rules lost: $1"; }
need 'Disable ngay lập tức'
need 'PendingIntent.FLAG_IMMUTABLE'
need 'SAXNotRecognizedException'
need 'Không `runBlocking` trên main'
need 'fallbackToDestructiveMigration'
need 'consumerProguardFiles'
need 'takePersistableUriPermission'
need 'collectAsStateWithLifecycle'
need 'Mandatory 4 trạng thái'
need 'wiring_pin.py scan'
ok "10 old android rule phrases survive"

for n in 17 18 19 20 21; do
  grep -qE "^## $n\. " "$R" || fail "rules missing section $n"
done
grep -qE '^## 17\. Quy tắc chung' "$R" || fail "§17 Quy tắc chung missing"
grep -qE '^## 18\. Hiệu năng' "$R" || fail "§18 Hiệu năng missing"
grep -qE '^## 19\. Chất lượng' "$R" || fail "§19 Chất lượng missing"
grep -qE '^## 20\. UI/UX' "$R" || fail "§20 UI/UX missing"
grep -qE '^## 21\. Bộ công cụ theo tình huống' "$R" || fail "§21 Bộ công cụ missing"
need 'Tách biệt phân tầng'
need 'The Dependency Rule'
need 'mock lỏng lẻo (`assert True`)'
need 'Soát kỹ `git diff`'
need 'Không spam request liên tục'
need 'Macrobenchmark'
need 'Perfetto'
need 'Baseline Profile'
need 'TransactionTooLargeException'
need 'Surviving Mutant'
need 'ktlintCheck'
need 'detekt'
need 'Material 3'
need 'TalkBack'
need 'ANIMATOR_DURATION_SCALE'
need 'Cách nghiệm thu'
grep -qF 'mặc định đề xuất của dự án, cần đo trên máy thật' "$R" || fail "numbers not labelled as project proposals"
ok "common, performance, quality, UI/UX, toolkit sections and key checks present"

D="$P/DESIGN.md"
[ -f "$D" ] || fail "$D missing"
for h in 'Vùng chạm' 'Typography' 'Chuyển động' 'Trạng thái' 'Dark mode' 'Accessibility' 'Material 3' 'Zero-Slop' 'Haptic' 'Chống spam'; do
  grep -qiE "^## .*$h" "$D" || fail "DESIGN.md missing a '## ... $h' section"
done
grep -qE 'Bộ công cụ theo tình huống' "$D" || fail "DESIGN.md has no pointer to rules section 21"
[ -f "$P/instincts.md" ] || fail "instincts.md missing"
grep -q 'INSTINCT-AND-14' "$P/instincts.md" || fail "android instincts lost"
ok "DESIGN.md sections present"

# toolkit section: every `skill:x` / `agent:x` / `council:x` must exist in the kit
python3 -I - "$R" <<'PY' || exit 1
import os, re, sys
t = open(sys.argv[1], encoding="utf-8").read()
sec = t.split("## 21. Bộ công cụ theo tình huống", 1)[1]
refs = re.findall(r"`(skill|agent|council):([A-Za-z0-9_-]+)`", sec)
assert refs, "section 21 names no skill/agent/council"
path = {"skill": "skills/%s/SKILL.md", "agent": "agents/%s.md", "council": "agents/councils/%s.md"}
for k, n in refs:
    assert os.path.isfile(path[k] % n), "section 21 names %s:%s which is not in the kit" % (k, n)
names = {n for _, n in refs}
for n in ("compose-recomp-audit", "android-real-device-qa", "taste-mobile-app", "ui-ux-pro-max", "impeccable",
          "qa-visual", "tdd-workflow", "qc", "verification-before-completion", "real-device-ui-auditor",
          "test-architect-seti", "mobile-release-auditor", "principal-code-reviewer", "security-checklist",
          "07-performance-anr"):
    assert n in names, "section 21 does not mention " + n
# no skill/agent the profile excludes may be recommended
import json
d = json.load(open("profiles/android/profile.json"))
for n in names:
    assert n not in d["exclude_skills"] and n not in d["exclude_agents"], "excluded but recommended: " + n
PY
ok "section 21 present, every named skill/agent/council exists and is not excluded"

# android files carry no iOS-only guidance
if grep -rniE 'swiftui|voiceover|metrickit|xctest|xcodebuild|dynamic type|apple hig|uikit|instruments|swiftlint|\bios\b' \
   "$P/rules/android-rules.md" "$P/DESIGN.md" "$P/instincts.md" "$P/profile.json" >/dev/null 2>&1; then
  grep -rniE 'swiftui|voiceover|metrickit|xctest|xcodebuild|dynamic type|apple hig|uikit|instruments|swiftlint|\bios\b' \
   "$P/rules/android-rules.md" "$P/DESIGN.md" "$P/instincts.md" "$P/profile.json" | cut -c1-160 >&2
  fail "android profile mentions iOS-only guidance"
fi
ok "no iOS-only guidance in android profile"
echo "PASS"
