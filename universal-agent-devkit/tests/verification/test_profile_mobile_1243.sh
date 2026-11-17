#!/usr/bin/env bash
# #1243: profiles/mobile merges android + ios + universal, keeps every rule, adds the
# performance / quality / UI-UX sections. Structural checks only (no device needed).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
P=profiles/mobile
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }

[ -f "$P/profile.json" ] || fail "$P/profile.json missing"
python3 -I - "$P/profile.json" <<'PY' || exit 1
import json, os, sys
d = json.load(open(sys.argv[1]))
assert d["id"] == "mobile", "id is %r" % d["id"]
for k in ("name", "name_en", "description", "description_en"):
    assert d.get(k), "missing " + k
for k in ("rules_file", "regression_matrix"):
    assert os.path.isfile(d[k]), "%s -> %s does not exist" % (k, d[k])
assert d["rules_file"] == "profiles/mobile/rules/mobile-rules.md"
assert d["regression_matrix"] == "profiles/mobile/regression_matrix.json"
for c in d["active_councils"]:
    assert os.path.isfile("agents/councils/" + c), "council %s does not resolve" % c
assert len(d["active_councils"]) == len(set(d["active_councils"])), "duplicate council"
assert len(d["essential_mcps"]) == len(set(d["essential_mcps"])), "duplicate mcp"
for m in ("codebase-memory-mcp", "context7", "mobile-mcp"):
    assert m in d["essential_mcps"], m
for e in (".kt", ".swift", ".java", ".m", ".mm"):
    assert e in d["source_extensions"], e
# an entry needed by one platform must not be excluded: ios needs the Swift side, android the Compose/R8 side
for s in ("android-real-device-qa", "compose-recomp-audit", "deploy"):
    assert s not in d["exclude_skills"], s
assert "android-principal-architect" not in d["exclude_agents"]
m = json.load(open(d["regression_matrix"]))
assert m["rules"], "matrix empty"
PY
ok "profile.json parses, id mobile, paths and councils resolve"

R="$P/rules/mobile-rules.md"
[ -f "$R" ] || fail "$R missing"
[ "$(readlink "$P/RULES.md" 2>/dev/null)" = "rules/mobile-rules.md" ] || [ -f "$P/RULES.md" ] || fail "RULES.md missing"
need() { grep -qF -- "$1" "$R" || fail "merged rules lost: $1"; }
# 10 android
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
# 5 ios
need 'weak var delegate'
need 'autoreleasepool'
need 'leaks -atExit'
need 'presentationDetents'
need 'Task.isCancelled'
# 5 universal
need 'Tách biệt phân tầng'
need 'The Dependency Rule'
need 'Cấm mock lỏng lẻo'
need 'Soát kỹ `git diff`'
need 'Không spam request liên tục'
ok "20 distinctive rule phrases (10 android, 5 ios, 5 universal) survive"

for h in 'Hiệu năng' 'Chất lượng' 'UI/UX'; do
  grep -qiE "^## .*$h" "$R" || fail "rules missing a '## ... $h' section"
done
grep -qE '^## .*Accessibility' "$R" || fail "rules missing an Accessibility heading"
D="$P/DESIGN.md"
[ -f "$D" ] || fail "$D missing"
for h in 'Hiệu năng' 'UI/UX' 'Accessibility' 'Dark mode' 'Chuyển động' 'Trạng thái'; do
  grep -qiE "^## .*$h" "$D" || fail "DESIGN.md missing a '## ... $h' section"
done
[ -f "$P/instincts.md" ] || fail "instincts.md missing"
grep -q 'INSTINCT-IOS-05' "$P/instincts.md" || fail "ios instincts lost"
ok "new sections present in RULES and DESIGN"

# section 22: situation -> kit tool map; every `skill:x` / `agent:x` / `council:x` must exist in the kit
grep -qE '^## 22\. Bộ công cụ theo tình huống' "$R" || fail "rules missing '## 22. Bộ công cụ theo tình huống'"
python3 -I - "$R" <<'PY' || exit 1
import os, re, sys
t = open(sys.argv[1], encoding="utf-8").read()
sec = t.split("## 22. Bộ công cụ theo tình huống", 1)[1]
refs = re.findall(r"`(skill|agent|council):([A-Za-z0-9_-]+)`", sec)
assert refs, "section 22 names no skill/agent/council"
path = {"skill": "skills/%s/SKILL.md", "agent": "agents/%s.md", "council": "agents/councils/%s.md"}
for k, n in refs:
    assert os.path.isfile(path[k] % n), "section 22 names %s:%s which is not in the kit" % (k, n)
names = {n for _, n in refs}
for n in ("compose-recomp-audit", "android-real-device-qa", "qa-visual", "tdd-workflow", "qc",
          "verification-before-completion", "real-device-ui-auditor", "test-architect-seti",
          "mobile-release-auditor", "principal-code-reviewer", "07-performance-anr"):
    assert n in names, "section 22 does not mention " + n
assert "Instruments" in sec and "MetricKit" in sec, "iOS equivalent of the Android-only tools not stated"
PY
ok "section 22 present, every named skill/agent/council exists"
grep -qE 'Bộ công cụ theo tình huống' "$P/DESIGN.md" || fail "DESIGN.md has no pointer to rules section 22"
echo "PASS"
