#!/usr/bin/env bash
# Regression test (T0497, owner 15/11/2026): the acceptance report has FIVE items, the fifth one names what is still
# open or unchecked, and every number says where it came from ("tự chạy" / "agent báo"). Item 3 counts only an old–new
# comparison that was run ("chưa so — <lý do>" otherwise). The report's line 3 carries the gate exit code (one source:
# essentials step 5), and an independent reviewer's score replaces the self-score (core-rules §18).
# hooks/proof_gate.sh still checks items 1–4 only: that ceiling is written as a `ponytail:` line in core-rules §2.3.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ESS="$DK/rules/essentials.md"
CORE="$DK/rules/core-rules.md"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

python3 - "$ESS" "$CORE" <<'PY' || FAILS=$((FAILS + 1))
import re, sys
ess, core = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
bad = 0
def check(cond, msg):
    global bad
    print(("✔ " if cond else "✖ ") + msg)
    bad += 0 if cond else 1

# (a) essentials step 5: the block from "5. The reply" to the next numbered step / heading
m = re.search(r"^5\. The reply.*?(?=^\S|\Z)", ess, re.S | re.M)
step5 = m.group(0) if m else ""
check(bool(step5), "(a) essentials step 5 found")
for name in ("Đã làm gì", "Đã fix gì", "Chặn bug cũ", "Nguy cơ bug mới", "An toàn mã nguồn", "Còn hở"):
    check(name in step5, f"(a) essentials step 5 names item '{name}'")
check("tự chạy" in step5 and "agent báo" in step5, "(a) essentials step 5 asks for the source tag tự chạy / agent báo")

# (b) core-rules §2.3: from the evidence item to "4. **Commit"
m = re.search(r"3\. \*\*Bằng chứng nghiệm thu.*?(?=^4\. \*\*Commit)", core, re.S | re.M)
s23 = m.group(0) if m else ""
check(bool(s23), "(b) core-rules §2.3 evidence item found")
check(re.search(r"^\s*5\. \*\*Còn hở", s23, re.M) is not None, "(b) §2.3 has item 5 'Còn hở / chưa kiểm'")
check("chưa so" in s23, "(b) §2.3 item 3 allows only a run comparison or 'chưa so — <lý do>'")
check("tự chạy" in s23 and "agent báo" in s23, "(b) §2.3 asks for the source tag on every number")
check("ponytail: hook proof_gate chỉ kiểm mục 1–4" in s23, "(b) §2.3 carries the ponytail line for the hook ceiling")

# (c) core-rules §13 line 3 carries the gate exit code
m = re.search(r"^## 13\..*?(?=^## 14\.)", core, re.S | re.M)
s13 = m.group(0) if m else ""
line3 = next((l for l in s13.splitlines() if "Dòng 3" in l), "")
check("mã thoát gate" in line3, "(c) §13 line 3 names the gate exit code")
check("Dòng 3 — Bước tiếp theo:" not in s13, "(c) §13 no longer has a bare 'Dòng 3 — Bước tiếp theo:'")

# (d) no four-item wording left in core-rules
for old in ("báo cáo nghiệm thu 4 mục", "4 mục kỹ thuật", "nghiệm thu 4 mục"):
    check(old not in core.lower(), f"(d) core-rules has no '{old}'")

# (e) §18 score: an independent reviewer's score is the one recorded
m = re.search(r"^## 18\..*?(?=^## 19\.|\Z)", core, re.S | re.M)
s18 = m.group(0) if m else ""
check("điểm tự chấm không thay" in s18, "(e) §18 says the self-score cannot replace the reviewer's score")
check("chuẩn vàng bị trừ" in s18, "(e) §18 asks to name the golden standards docked")
sys.exit(1 if bad else 0)
PY

[ "$FAILS" -eq 0 ] && { echo "✅ test_report_template_five_items"; exit 0; }
echo "❌ test_report_template_five_items: $FAILS failure(s)"; exit 1
