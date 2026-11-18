#!/usr/bin/env bash
# #1250: profile backend has performance, quality, API/DX UX and a toolset + acceptance section, keeps every older
# key rule, names only skills / agents / councils that exist in the kit (and are not excluded by profile.json), keeps the
# always-loaded part small (details live in on-demand blocks) and does not contradict itself about 503 vs the 5xx SLI.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
P=profiles/backend
RULES=$P/rules/backend-rules.md
LOADED_BUDGET=11000   # bytes of the always-loaded split (measured 10860 when written)
FAILS=0
fail() { echo "FAIL: $1" >&2; FAILS=$((FAILS + 1)); }
ok() { echo "ok: $1"; }

python3 -I - "$DK" "$LOADED_BUDGET" <<'PY' || FAILS=$((FAILS + 1))
import json, os, re, sys
d, budget = sys.argv[1], int(sys.argv[2])
sys.path.insert(0, os.path.join(d, "scripts", "governance"))
import context_sync as cs
p = os.path.join(d, "profiles", "backend")
j = json.load(open(os.path.join(p, "profile.json"), encoding="utf-8"))
rules = open(os.path.join(p, "rules", "backend-rules.md"), encoding="utf-8").read()
design = open(os.path.join(p, "DESIGN.md"), encoding="utf-8").read()
errs = []
def need(cond, msg):
    if not cond:
        errs.append(msg)

# profile.json paths
for k in ("regression_matrix", "rules_file"):
    need(os.path.isfile(os.path.join(d, j[k])), k + " does not resolve")
for c in j["active_councils"]:
    need(os.path.isfile(os.path.join(d, "agents", "councils", c)), "council " + c)
need(os.path.isfile(os.path.join(p, "RULES.md")), "RULES.md does not resolve")

def section(text, n):
    m = re.search(r"^## %s\. .*$" % n, text, re.M)
    if not m:
        errs.append("missing heading ## %s." % n)
        return ""
    nxt = re.search(r"^## \d+\. ", text[m.end():], re.M)
    return text[m.start(): m.end() + nxt.start()] if nxt else text[m.start():]

# older key rules, each inside its own old section
OLD = {1: ["Tự commit/push khi xong"], 2: ["Paired Executable Oracle"], 3: ["Không đổi/xoá field hay đổi kiểu"],
       4: ["Migration chỉ tiến", "cấm nối chuỗi SQL"], 5: ["Tránh N+1 query", "Không nuốt lỗi"], 6: ["Endpoint health/readiness riêng"],
       7: ["chống IDOR", "169.254.169.254", "không phân giải DNS lần hai", "socket.getaddrinfo"], 8: ["Hexagonal / DDD"],
       9: ["AppError extends Error", "unhandledRejection"], 10: ["ParentBased(AlwaysOn)", "ERROR ≥ 17"]}
for n, needles in OLD.items():
    s = section(rules, n)
    for x in needles:
        need(x in s, "old rule missing in section %d: %s" % (n, x))

# loaded vs on-demand split
loaded, blocks = cs.split_rules(rules)
titles = [t for t, _b in blocks]
body = {t: b for t, b in blocks}
need(len(blocks) >= 4, "expected at least 4 on-demand blocks, got %d" % len(blocks))
def block_with(prefix):
    return next((t for t in titles if t.startswith(prefix)), None)
for pre in ("§11", "§12", "§13", "§14"):
    need(block_with(pre) is not None, "no on-demand block for " + pre)
need(len(loaded.encode()) <= budget, "loaded size %d > budget %d" % (len(loaded.encode()), budget))
l11, l12, l14 = section(loaded, 11), section(loaded, 12), section(loaded, 14)
for x in ("p50/p95/p99", "EXPLAIN", "N+1", "Pool kết nối", "Backpressure", "nhanh hơn", "event loop"):
    need(x in l11, "loaded §11 lacks: " + x)
for x in ("migration test", "xác định", "RED", "số test > 0", "sàn 80%"):
    need(x in l12, "loaded §12 lacks: " + x)
for i in "12345":
    need(re.search(r"^%s\. " % i, l14, re.M) is not None, "loaded §14 acceptance step %s missing" % i)
need("CHƯA ĐO" in l14 and "Cách nghiệm thu" in l14, "loaded §14 lacks the CHƯA ĐO rule")
need("profile-reference.md" in l11, "loaded §11 does not say where the on-demand SLO table lives")
LAB = "mặc định đề xuất của dự án, cần đo thật"
need(LAB in l11 and LAB in l12, "the proposal label must stay in the loaded text")
# details that must NOT be loaded (token cost) but must exist in a block
b11 = body.get(block_with("§11") or "", "")
for x in ("constant-arrival-rate", "43,2 phút", "hyperthread", "HikariCP", "coordinated omission", "Little"):
    need(x in b11 and x not in loaded, "§11 detail %r should live only in the on-demand block" % x)
b12 = body.get(block_with("§12") or "", "")
for x in ("Testcontainers", "Pact", "Stryker", "feature flag"):
    need(x in b12 and x not in loaded, "§12 detail %r should live only in the on-demand block" % x)

# SLO table: every row with a number carries the label
rows = [l for l in rules.split("\n") if re.match(r"\|.*\b\d+ ?(ms|s)\b.*\|", l)]
need(rows and all(LAB in l for l in rows), "SLO proposal rows missing the label (rows=%d)" % len(rows))

# no 503-vs-5xx contradiction: 503 counts in the error SLI, 429 does not, said in both rules and DESIGN
need("kể cả 503" in l11 and "SLI" in l11, "loaded §11 must say 503 counts in the error SLI")
need(not re.search(r"503[^.\n]{0,60}không (vào|tính)[^.\n]{0,40}5xx", rules + design), "text still says 503 is outside the 5xx SLI")
need(re.search(r"^\| .*503.*SLI", design, re.M) is not None, "DESIGN §2 status table lacks the 503 row")
need("503" in section(design, 8) and "SLI" in section(design, 8), "DESIGN §8 must restate 503 in the SLI")
need("RFC 6585" in design and "RFC 6585" in rules, "Retry-After must cite RFC 9110 / RFC 6585")
for x in ("rollback", "vật lý", "TỔNG", "tương tự"):
    need(x in rules, "factual fix missing: " + x)

# toolset names exist in the kit and none is excluded
sect = section(rules, 14)
named = re.findall(r"\b(skill|agent|council) `([^`]+)`", sect)
paths = {"skill": lambda n: os.path.join(d, "skills", n, "SKILL.md"), "agent": lambda n: os.path.join(d, "agents", n + ".md"),
         "council": lambda n: os.path.join(d, "agents", "councils", n + ".md")}
bad = [(k, n) for k, n in named if not os.path.isfile(paths[k](n))]
bad += [(k, n + " (excluded)") for k, n in named if (k == "skill" and n in j["exclude_skills"]) or
        (k == "agent" and n in j["exclude_agents"]) or (k == "council" and n + ".md" not in j["active_councils"])]
need("07-performance-anr" in {n for _k, n in named}, "council 07 not named in section 14")
missing = sorted({"observability-instrumentation", "security-checklist", "tdd-workflow", "qc", "verification-before-completion",
                  "deep-module-design", "ui-ux-pro-max", "database-reliability-auditor", "security-penetration-auditor",
                  "test-architect-seti", "principal-code-reviewer", "07-performance-anr"} - {n for _k, n in named})
need(not bad and not missing, "toolset names: bad=%s not named=%s" % (bad, missing))

# DESIGN additions, each in its own section
s7, s8 = section(design, 7), section(design, 8)
for x in ("Server-Timing", "OpenAPI", "--dry-run", "Sunset"):
    need(x in s7, "DESIGN §7 lacks " + x)
need("p95" in s8, "DESIGN §8 lacks the per-route p95 rule")

if errs:
    for e in errs:
        print("FAIL: " + e, file=sys.stderr)
    sys.exit(1)
print("ok: backend profile #1250 (loaded %d B <= %d, %d blocks, %d toolset names)" % (len(loaded.encode()), budget, len(blocks), len(named)))
PY

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed" >&2; exit 1; }
ok "profile backend #1250"
