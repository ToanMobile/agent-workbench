#!/usr/bin/env bash
# #1250: profile backend has performance, quality, API/DX UX and a toolset + acceptance section, keeps every older
# key rule, and names only skills / agents / councils that exist in the kit (and are not excluded by profile.json).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
P=profiles/backend
RULES=$P/rules/backend-rules.md
FAILS=0
fail() { echo "FAIL: $1" >&2; FAILS=$((FAILS + 1)); }
ok() { echo "ok: $1"; }
has() { grep -qF -- "$2" "$1" || fail "$3"; }

python3 - "$DK" <<'PY' || FAILS=$((FAILS + 1))
import json, os, re, sys
d = sys.argv[1]
p = os.path.join(d, "profiles", "backend")
j = json.load(open(os.path.join(p, "profile.json"), encoding="utf-8"))
bad = []
for k in ("regression_matrix", "rules_file"):
    if not os.path.isfile(os.path.join(d, j[k])):
        bad.append(k + " -> " + j[k])
for c in j["active_councils"]:
    if not os.path.isfile(os.path.join(d, "agents", "councils", c)):
        bad.append("council " + c)
if not os.path.isfile(os.path.join(p, "RULES.md")):
    bad.append("RULES.md does not resolve")
if bad:
    print("FAIL: profile.json paths: %s" % bad, file=sys.stderr)
    sys.exit(1)
print("ok: profile.json paths and councils resolve")

# every skill / agent / council named in the toolset section exists and is not excluded by the profile
rules = open(os.path.join(p, "rules", "backend-rules.md"), encoding="utf-8").read()
m = re.search(r"^## 14\..*", rules, re.M)
if not m:
    print("FAIL: section 14 (Bộ công cụ và cách nghiệm thu) is missing", file=sys.stderr)
    sys.exit(1)
sect = rules[m.start():]
named = re.findall(r"\b(skill|agent|council) `([^`]+)`", sect)
paths = {"skill": lambda n: os.path.join(d, "skills", n, "SKILL.md"),
         "agent": lambda n: os.path.join(d, "agents", n + ".md"),
         "council": lambda n: os.path.join(d, "agents", "councils", n + ".md")}
bad = [(k, n) for k, n in named if not os.path.isfile(paths[k](n))]
bad += [(k, n + " (excluded by profile.json)") for k, n in named
        if (k == "skill" and n in j["exclude_skills"]) or (k == "agent" and n in j["exclude_agents"])
        or (k == "council" and n + ".md" not in j["active_councils"])]
need = {"observability-instrumentation", "security-checklist", "tdd-workflow", "qc", "verification-before-completion",
        "deep-module-design", "ui-ux-pro-max", "database-reliability-auditor", "security-penetration-auditor",
        "test-architect-seti", "principal-code-reviewer", "07-performance-anr"}
missing = sorted(need - {n for _k, n in named})
if bad or missing:
    print("FAIL: toolset names: nonexistent/excluded=%s not named=%s" % (bad, missing), file=sys.stderr)
    sys.exit(1)
print("ok: %d toolset names exist in the kit and none is excluded" % len(named))
PY

# older key rules (one needle per old section; the full line-by-line diff is checked against origin/main by the author)
for n in 'Tự commit/push khi xong' 'Paired Executable Oracle' 'Không đổi/xoá field hay đổi kiểu' 'Migration chỉ tiến' \
         'cấm nối chuỗi SQL' 'Tránh N+1 query' 'Không nuốt lỗi' 'Endpoint health/readiness riêng' 'chống IDOR' \
         '169.254.169.254' 'không phân giải DNS lần hai' 'socket.getaddrinfo' 'Hexagonal / DDD' 'AppError extends Error' \
         'unhandledRejection' 'ParentBased(AlwaysOn)' 'ERROR ≥ 17'; do
  has $RULES "$n" "old rule missing: $n"
done
[ "$FAILS" -eq 0 ] && ok "older key rules checked"

# new sections
for h in '## 11. Hiệu năng' '## 12. Chất lượng' '## 13. UI/UX cho backend' '## 14. Bộ công cụ và cách nghiệm thu'; do
  has $RULES "$h" "rules section missing: $h"
done
for n in 'p50/p95/p99' 'EXPLAIN' 'Backpressure' 'k6' 'Gatling' 'môi trường giống production' 'migration test' 'contract test' \
         'mutation' 'canary' 'OpenAPI' 'Retry-After' 'Cách nghiệm thu' 'mặc định đề xuất của dự án, cần đo thật'; do
  has $RULES "$n" "rules text missing: $n"
done
has $P/DESIGN.md '## 7.' "DESIGN.md section 7 (API UX / DX) missing"
has $P/DESIGN.md '## 8.' "DESIGN.md section 8 (performance conventions) missing"
for n in 'Server-Timing' 'OpenAPI' '--dry-run' 'Sunset'; do has $P/DESIGN.md "$n" "DESIGN.md missing: $n"; done
[ "$FAILS" -eq 0 ] && ok "new sections and DESIGN.md additions checked"

# no number is left unlabeled in the proposed SLO table: each table row carries the project label.
# (the on-demand blocks staying free of MUST-pattern lines is pinned by tests/context_memory/test_profile_split.sh)
python3 - "$DK/$RULES" <<'PY' || FAILS=$((FAILS + 1))
import re, sys
rows = [l for l in open(sys.argv[1], encoding="utf-8").read().split("\n") if re.match(r"\|.*\b\d+ ?(ms|s)\b.*\|", l)]
lab = "mặc định đề xuất của dự án, cần đo thật"
bad = [l[:60] for l in rows if lab not in l]
if not rows or bad:
    print("FAIL: SLO proposal rows missing the label: %s (rows=%d)" % (bad, len(rows)), file=sys.stderr)
    sys.exit(1)
print("ok: %d SLO proposal rows all carry the label" % len(rows))
PY

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed" >&2; exit 1; }
ok "profile backend #1250"
