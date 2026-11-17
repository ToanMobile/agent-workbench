#!/usr/bin/env bash
# test_profile_web_1249.sh — profile web (#1249): performance, quality, UI/UX and the toolkit section exist,
# the old rules survive, and every skill / agent / council the profile names exists in the kit.
# Red means a section was dropped, an old rule was weakened, or the profile names something that is not shipped.
# Usage: bash tests/verification/test_profile_web_1249.sh   (needs python3)
set -u
DK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$DK" || exit 2
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

python3 - "$DK" <<'PY'
import json, os, re, sys

ROOT = sys.argv[1]
FAILS = 0
def check(ok, name):
    global FAILS
    print(("ok: " if ok else "FAIL: ") + name)
    if not ok:
        FAILS += 1
def read(p):
    with open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return f.read()

W = os.path.join("profiles", "web")
prof = json.load(open(os.path.join(ROOT, W, "profile.json"), encoding="utf-8"))

# 1. profile.json paths and councils resolve
check(os.path.isfile(os.path.join(ROOT, prof["rules_file"])), "rules_file resolves")
check(os.path.isfile(os.path.join(ROOT, prof["regression_matrix"])), "regression_matrix resolves")
missing = [c for c in prof["active_councils"] if not os.path.isfile(os.path.join(ROOT, "agents", "councils", c))]
check(not missing, "every active council exists %s" % (missing or ""))
check("07-performance-anr.md" in prof["active_councils"], "council 07-performance-anr stays active")
check("taste-mobile-app" in prof["exclude_skills"], "taste-mobile-app stays excluded from web")

rules = read(prof["rules_file"])
design = read(os.path.join(W, "DESIGN.md"))

# 2. old rules survive (key phrases from the 47-line original)
OLD_RULES = ["## 1. Solo-Dev", "## 2. Paired Executable Oracle", "## 3. TypeScript", "## 4. Bảo mật trình duyệt",
             "## 5. Hiệu năng & Core Web Vitals", "## 6. Chống Spam", "## 7. Accessibility (WCAG 2.2 AA)",
             "## 8. Kiến trúc feature-based", "## 9. Chuẩn Thiết Kế Giao Diện",
             "LCP ≤ 2.5s, INP ≤ 200ms, CLS ≤ 0.1", "Vùng bấm ≥ 44×44px, tương phản ≥ 4.5:1", "AbortController",
             "`HttpOnly; Secure`", "Zero-Slop bắt buộc", "tabular-nums", "65–75ch", "no-floating-promises"]
gone = [k for k in OLD_RULES if k not in rules]
check(not gone, "old rule keys present in web-rules.md %s" % (gone or ""))
OLD_DESIGN = ["## 1. Color Tokens", "`--color-primary`", "## 2. Typography", "## 3. Spacing & Layout", "## 4. Accessibility (WCAG 2.2 AA)",
              "## 5. Motion & Media", "`prefers-reduced-motion`", "AVIF/WebP", "Thang 4px", "aria-describedby"]
gone = [k for k in OLD_DESIGN if k not in design]
check(not gone, "old DESIGN.md keys present %s" % (gone or ""))

# 3. new sections present
for n, title in ((10, "Hiệu năng"), (11, "Chất lượng"), (12, "UI/UX"), (13, "Bộ công cụ")):
    check(re.search(r"^## %d\. .*%s" % (n, title), rules, re.M) is not None, "web-rules.md has section %d (%s)" % (n, title))
check("Cách nghiệm thu" in rules, "web-rules.md has 'Cách nghiệm thu'")
for term in ("Lighthouse", "Playwright", "axe", "RUM", "visual regression", "toHaveScreenshot", "prefers-reduced-motion",
             "prefers-color-scheme", "WCAG 2.2", "4.5:1", "Zero-Slop", "flaky", "web.dev"):
    check(term in rules, "web-rules.md mentions %s" % term)
for n in range(6, 13):
    check(re.search(r"^## %d\. " % n, design, re.M) is not None, "DESIGN.md has section %d" % n)
for term in ("clamp(", "`--focus-ring`", "touch-action", "role=\"alert\"", "color-scheme", "--duration-base", "--color-border-strong"):
    check(term in design, "DESIGN.md mentions %s" % term)
# every number-bearing budget row carries a source or the proposal label
LABEL = "mặc định đề xuất của dự án, cần đo thật"
sec10 = rules.split("## 10.", 1)[1].split("## 11.", 1)[0] if "## 10." in rules else ""
rows = [l for l in sec10.splitlines() if l.startswith("| ") and re.search(r"≤ \d|≥ \d|> \d", l) and "Chỉ số" not in l]
bad = [l[:60] for l in rows if LABEL not in l and "web.dev" not in l]
check(rows and not bad, "section 10 budget rows each carry a source or the proposal label %s" % (bad or ""))

# 4. every skill / agent / council the profile names exists, and is not excluded
body = rules + "\n" + design
skills = {d for d in os.listdir(os.path.join(ROOT, "skills")) if os.path.isfile(os.path.join(ROOT, "skills", d, "SKILL.md"))}
agents = {f[:-3] for f in os.listdir(os.path.join(ROOT, "agents")) if f.endswith(".md")}
councils = set(os.listdir(os.path.join(ROOT, "agents", "councils")))
NEED_SKILLS = ["qa-visual", "ui-ux-pro-max", "impeccable", "qc", "tdd-workflow", "verification-before-completion",
               "security-checklist", "observability-instrumentation"]
NEED_AGENTS = ["real-device-ui-auditor", "test-architect-seti", "principal-code-reviewer"]
check(all(s in skills for s in NEED_SKILLS), "required skills exist in the kit")
check(all(a in agents for a in NEED_AGENTS), "required agents exist in the kit")
named = [s for s in NEED_SKILLS + NEED_AGENTS if ("`%s`" % s) not in rules]
check(not named, "web-rules.md names each required skill/agent in backticks %s" % (named or ""))
check("07-performance-anr.md" in rules and "07-performance-anr.md" in councils, "council 07 named and exists")
# any backticked skill-like token that matches a kit skill/agent dir must not be excluded; unknown `*-audit`-style names are caught below
excluded = set(prof["exclude_skills"]) | set(prof["exclude_agents"])
used_excluded = sorted(n for n in (skills | agents) if n in excluded and ("`%s`" % n) in body)
check(not used_excluded, "no excluded skill/agent is referenced %s" % (used_excluded or ""))
# a skill/agent referenced in the toolkit table must exist: every `name` in section 13's table first column set
sec13 = rules.split("## 13.", 1)[1] if "## 13." in rules else ""
tokens = set(re.findall(r"`([a-z][a-z0-9-]+)`", sec13))
known_words = {"audit", "optimize", "shape", "critique", "adapt", "polish", "detect", "onboard", "harden", "search", "nextjs",
               "react", "vue", "svelte", "html-tailwind", "package"}
unknown = sorted(t for t in tokens if t not in skills | agents | known_words and "-" in t and not t.startswith("qa.") and t not in ("--a11y",))
check(not unknown, "section 13 names no unknown hyphenated tool %s" % (unknown or ""))
refs = ["skills/tdd-workflow/references/testing-practices.md", "skills/deep-module-design/references/architecture-web.md"]
check(all(os.path.isfile(os.path.join(ROOT, r)) for r in refs), "referenced skill reference files exist")
check("references/testing-practices.md" in rules, "web-rules.md points to tdd-workflow testing-practices")
check(os.path.isfile(os.path.join(ROOT, "skills", "ui-ux-pro-max", "scripts", "search.py")), "ui-ux-pro-max search.py exists")

# 5. regression matrix keeps only real tests (no new unverified entries)
m = json.load(open(os.path.join(ROOT, prof["regression_matrix"]), encoding="utf-8"))
ids = [t["id"] for r in m["rules"] for t in r["mandatory_regression_tests"]]
check(ids == ["REG-WEB-01", "REG-WEB-02"], "regression matrix still has exactly REG-WEB-01/02 %s" % ids)

print("profile_web_1249: %s" % ("all checks passed" if not FAILS else "%d FAILED" % FAILS))
sys.exit(1 if FAILS else 0)
PY
