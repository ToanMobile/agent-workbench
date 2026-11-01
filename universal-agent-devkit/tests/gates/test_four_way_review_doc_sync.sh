#!/usr/bin/env bash
# rules/four-way-review.md nói đúng điều code làm (review của #742 tại 14108864, BUG-REV-52106c990f):
#   tài liệu còn ghi Grok có run_terminal_cmd trong --tools (code chặn nó ở GROK_DENY) và còn ghi trần REVIEW_MAX_TOKENS /
#   REVIEW_MAX_USD làm FAIL (review-merge.py không còn đọc hai biến đó). Agent đọc luật theo tài liệu thì làm sai so với gate.
# DOC=<đường dẫn> thay file tài liệu (chạy ĐỎ trên bản cũ).
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOC="${DOC:-$DEVKIT_DIR/rules/four-way-review.md}"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$DOC" ] || { echo "✖ fixture: $DOC không có"; exit 1; }

out=$(python3 -I - "$DEVKIT_DIR/bin" "$DOC" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1])
import review_runner as rr
doc = open(sys.argv[2], encoding="utf-8").read()
code_tools = set(rr.GROK_TOOLS.split(","))
deny = set(rr.GROK_DENY.split(","))
rows = [l for l in doc.splitlines() if l.startswith("| **Grok**")]
m = re.search(r"--tools\s+([a-z_,]+)", rows[0]) if rows else None
doc_tools = set(m.group(1).split(",")) if m else None
print("grok_row", "yes" if rows else "no")
print("grok_tools_equal", "yes" if doc_tools == code_tools else f"no doc={sorted(doc_tools or [])} code={sorted(code_tools)}")
print("grok_denied_in_doc_tools", ",".join(sorted((doc_tools or set()) & deny)) or "none")
merge = open(sys.argv[1] + "/review-merge.py", encoding="utf-8").read()
stale = [v for v in ("REVIEW_MAX_TOKENS", "REVIEW_MAX_USD") if v in doc and v not in merge]
print("stale_cost_caps", ",".join(stale) or "none")
PY
) || { echo "✖ fixture: python lỗi"; exit 1; }

case "$out" in *"grok_row yes"*) ok "tài liệu có dòng Grok";; *) fail "tài liệu không có dòng | **Grok** |";; esac
case "$out" in *"grok_tools_equal yes"*) ok "--tools của Grok trong tài liệu = GROK_TOOLS của review_runner.py";;
  *) fail "--tools của Grok lệch code: $(printf '%s\n' "$out" | grep '^grok_tools_equal')";; esac
case "$out" in *"grok_denied_in_doc_tools none"*) ok "tài liệu không cho Grok công cụ nằm trong GROK_DENY";;
  *) fail "tài liệu cho Grok công cụ code chặn: $(printf '%s\n' "$out" | grep '^grok_denied_in_doc_tools')";; esac
case "$out" in *"stale_cost_caps none"*) ok "tài liệu không nêu trần chi phí review-merge.py không đọc";;
  *) fail "tài liệu còn trần chi phí code đã bỏ: $(printf '%s\n' "$out" | grep '^stale_cost_caps')";; esac

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; }
echo "$FAILS failed"; exit 1
