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

# 3. new sections present (term and number greps run on the new sections only, from their headings)
new_rules = rules[rules.index("\n## 10. "):] if "\n## 10. " in rules else ""
new_design = design[design.index("\n## 6. "):] if "\n## 6. " in design else ""
for n, title in ((10, "Hiệu năng"), (11, "Chất lượng"), (12, "UI/UX"), (13, "Bộ công cụ")):
    check(re.search(r"^## %d\. .*%s" % (n, title), rules, re.M) is not None, "web-rules.md has section %d (%s)" % (n, title))
check("Cách nghiệm thu" in new_rules, "web-rules.md has 'Cách nghiệm thu'")
for term in ("Lighthouse", "Playwright", "axe", "RUM", "visual regression", "toHaveScreenshot", "prefers-reduced-motion",
             "prefers-color-scheme", "WCAG 2.2", "4.5:1", "Zero-Slop", "flaky", "web.dev"):
    check(term in new_rules, "web-rules.md sections 10-13 mention %s" % term)
for n in range(6, 13):
    check(re.search(r"^## %d\. " % n, design, re.M) is not None, "DESIGN.md has section %d" % n)
for term in ("clamp(", "`--focus-ring`", "touch-action", "role=\"alert\"", "color-scheme", "--duration-base", "--color-border-strong"):
    check(term in new_design, "DESIGN.md sections 6-12 mention %s" % term)
# key numbers: a wrong value must fail (web.dev thresholds, long task, WCAG success criteria)
for pat, what in ((r"\| LCP \| tốt ≤ 2\.5s, kém > 4s", "LCP 2.5s/4s"), (r"\| INP \| tốt ≤ 200ms, kém > 500ms", "INP 200/500ms"),
                  (r"\| CLS \| tốt ≤ 0\.1, kém > 0\.25", "CLS 0.1/0.25"), (r"Tác vụ dài[^|]*\| > 50ms", "long task 50ms"),
                  (r"SC 1\.4\.3\)", "SC 1.4.3"), (r"SC 1\.4\.11\)", "SC 1.4.11"), (r"SC 1\.4\.10 Reflow", "SC 1.4.10"),
                  (r"SC 1\.4\.4\)", "SC 1.4.4"), (r"SC 2\.4\.7\)", "SC 2.4.7"), (r"SC 2\.4\.11,", "SC 2.4.11"),
                  (r"SC 2\.5\.7\)", "SC 2.5.7"), (r"SC 2\.5\.8\)", "SC 2.5.8"), (r"SC 2\.5\.5 \(AAA\)", "SC 2.5.5 AAA"),
                  (r"SC 3\.3\.8,", "SC 3.3.8"), (r"SC 2\.2\.2\)", "SC 2.2.2"), (r"SC 2\.3\.1\)", "SC 2.3.1"),
                  (r"≥ 5 cặp", "5 A/B pairs"), (r"range > 20% median", "20% range"), (r"24×24 CSS px", "24x24 target"),
                  (r"≥ 18pt hoặc ≥ 14pt đậm", "large text"), (r"wcag2a`, `wcag2aa`, `wcag21aa`, `wcag22aa", "axe tags"),
                  (r"Lighthouse chế độ navigation \(mặc định\) không đo INP", "Lighthouse INP wording")):
    check(re.search(pat, new_rules) is not None, "web-rules.md pins %s" % what)
check("tốt ≤ 2.5s" in rules, "§5 original LCP number still 2.5s")
check("320 CSS px" in new_design and "SC 2.5.8" in new_design, "DESIGN.md pins 320 CSS px reflow and SC 2.5.8")
# DESIGN.md sections 6-10 carry the exact proposal label at their head
LAB = "mặc định đề xuất của dự án, cần đo thật"
for n in range(6, 11):
    m = re.search(r"^## %d\. .*\n(.*)\n" % n, new_design, re.M)
    check(m is not None and LAB in m.group(1), "DESIGN.md section %d opens with the proposal label" % n)
# contrast ratios claimed in DESIGN.md are recomputed here (WCAG relative luminance)
def _lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return .2126 * c[0] + .7152 * c[1] + .0722 * c[2]
def ratio(a, b):
    hi, lo = sorted((_lum(a), _lum(b)), reverse=True)
    return (hi + .05) / (lo + .05)
for fg, bg, want in (("#059669", "#FFFFFF", 3.77), ("#047857", "#FFFFFF", 5.48), ("#64748B", "#FFFFFF", 4.76), ("#64748B", "#F8FAFC", 4.55),
                     ("#6B7280", "#0B0F17", 3.97), ("#6B7280", "#111827", 3.67), ("#DC2626", "#FFFFFF", 4.83), ("#DC2626", "#F8FAFC", 4.62),
                     ("#B45309", "#FFFFFF", 5.02), ("#B45309", "#F8FAFC", 4.80)):
    got = ratio(fg, bg)
    check(abs(got - want) < 0.006 and ("%.2f" % want) in design.replace("4.8:1", "4.80:1"),
          "contrast %s on %s is %.2f and DESIGN.md states %.2f" % (fg, bg, got, want))
for fg, bg in (("#DC2626", "#F8FAFC"), ("#F87171", "#0B0F17"), ("#F87171", "#111827"), ("#FBBF24", "#0B0F17"), ("#FBBF24", "#111827")):
    check(ratio(fg, bg) >= 4.5, "text colour %s on %s is >= 4.5:1" % (fg, bg))
check(ratio("#6B7280", "#111827") >= 3 and ratio("#64748B", "#F8FAFC") >= 3, "border-strong >= 3:1 on both surfaces")
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
# every backticked lowercase word in section 13 must be a kit skill/agent, an impeccable verb listed in its SKILL.md, or an explicit stack name
sec13 = rules.split("## 13.", 1)[1] if "## 13." in rules else ""
imp = read("skills/impeccable/SKILL.md")
verbs = set(re.findall(r"^\| `([a-z]+)(?: \[|`)", imp, re.M))
STACKS = {"react", "nextjs", "vue", "svelte", "html-tailwind"}
CLI = {"detect"}  # script subcommand, documented in impeccable SKILL.md (checked below)
check("scripts/impeccable detect <path>" in imp, "impeccable SKILL.md documents the detect subcommand")
tokens = set(re.findall(r"`([a-z][a-z0-9-]*)`", sec13))
unknown = sorted(t for t in tokens if t not in skills | agents | verbs | STACKS | CLI)
check(not unknown, "section 13 names only kit skills/agents, impeccable verbs and listed stacks %s" % (unknown or ""))
check({"audit", "optimize", "shape", "critique", "adapt", "polish"} <= verbs, "impeccable SKILL.md lists the verbs section 13 uses")
check(os.path.isfile(os.path.join(ROOT, "skills", "impeccable", "scripts", "impeccable")), "impeccable scripts/impeccable exists")
check(".agents/skills/impeccable/scripts/impeccable detect" in new_rules and "`impeccable detect" not in new_rules,
      "impeccable detect is written as the scripts/impeccable command")
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
