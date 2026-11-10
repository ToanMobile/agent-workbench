#!/usr/bin/env bash
# Test #812 (create_task.py): (1) `Refs #721, #722, #723` ⇒ cả 3 thẻ đang chạy; `Closes #7` trong code span/fence không tính;
# (2) closingIssuesReferences của repo khác không loại thẻ cùng số của repo này; (3) lần đọc kiểm sau khi ghi chỉ cần body, không
# coi PR vừa liên kết là ghi hỏng (không sinh thẻ trùng); (4) AC mặc định dùng --scoped, không --full. Offline, bash 3.2.
# gh giả (đầu PATH): như test_create_task_pr_mention.sh, thêm FAKE_LINKED_AFTER_EDIT (PR chỉ liên kết sau khi thẻ bị ghi).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset SB_MAX_BATCH_CARDS SB_MAX_BATCH_AC SB_MAX_CARD_AC FAKE_PRS FAKE_LINKED FAKE_LINKED_AFTER_EDIT

mkdir -p "$TMP/bin" "$TMP/repo" "$TMP/gh"
export FAKE_LOG="$TMP/calls.jsonl" FAKE_ITEMS="$TMP/items.json" FAKE_DIR="$TMP/gh"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
d = os.environ["FAKE_DIR"]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
def arg(name):
    return a[a.index(name) + 1] if name in a else None
def items():
    return json.load(open(os.environ["FAKE_ITEMS"]))["items"] if os.path.exists(os.environ["FAKE_ITEMS"]) else []
if a[:2] == ["issue", "create"]:
    nf = os.path.join(d, "next")
    n = int(open(nf).read()) if os.path.exists(nf) else 99
    open(nf, "w").write(str(n + 1))
    open(os.path.join(d, "issue%d.body" % n), "w").write(arg("--body"))
    print("https://github.com/ToanMobile/agent-workbench/issues/%d" % n); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_1"})); sys.exit(0)
if a[:2] == ["project", "item-list"]:
    print(json.dumps({"items": items()})); sys.exit(0)
if a[:2] == ["pr", "list"]:
    print(os.environ.get("FAKE_PRS", "[]")); sys.exit(0)
if a[:2] == ["issue", "view"]:
    n = a[2]
    p = os.path.join(d, "issue%s.body" % n)
    body = open(p).read() if os.path.exists(p) else next(
        (i["content"]["body"] for i in items() if str(i["content"]["number"]) == n), None)
    if body is None:
        sys.stderr.write("fake gh: no issue %s\n" % n); sys.exit(1)
    linked_now = n in os.environ.get("FAKE_LINKED", "").split(",") or (
        n in os.environ.get("FAKE_LINKED_AFTER_EDIT", "").split(",") and os.path.exists(p))
    linked = [{"number": 730, "url": "https://github.com/ToanMobile/agent-workbench/pull/730"}] if linked_now else []
    print(json.dumps({"body": body, "state": "OPEN", "closedByPullRequestsReferences": linked})); sys.exit(0)
if a[:2] == ["issue", "edit"]:
    if "--body" in a:
        open(os.path.join(d, "issue%s.body" % a[2]), "w").write(arg("--body"))
    sys.exit(0)
if a[:2] in (["project", "item-edit"], ["label", "create"]):
    sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"

items() { python3 - "$1" <<'PY'
import json, os, sys
out = []
for c in json.loads(sys.argv[1]):
    out.append({"status": c.get("status", "Backlog"), "labels": c.get("labels") or ["feature"],
                "content": {"type": "Issue", "repository": "ToanMobile/agent-workbench", "number": c["n"],
                            "title": c.get("title", "✨ [feature] hooks: thẻ %d" % c["n"]),
                            "body": c.get("body", "## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n🟢\n\n## Blocked by\n- None.\n")}})
open(os.environ["FAKE_ITEMS"], "w").write(json.dumps({"items": out}))
PY
}
run() { : > "$FAKE_LOG"; rm -f "$FAKE_DIR"/*; (cd "$TMP/repo" && python3 "$CT" "$@") >"$TMP/out" 2>&1; echo $?; }
called() { python3 - "$1" "$2" <<'PY'
import json, os, sys
print(sum(1 for l in open(os.environ["FAKE_LOG"]) if json.loads(l).get("gh", [])[:2] == sys.argv[1:3]))
PY
}
edited() { python3 - <<'PY'
import json, os
for l in open(os.environ["FAKE_LOG"]):
    a = json.loads(l).get("gh", [])
    if a[:2] == ["issue", "edit"]:
        print(a[2]); break
else:
    print("NONE")
PY
}
SAME=(--title "✨ [feature] hooks: thêm việc B" --problem "vấn đề B" --fix "sửa B" --ac "- [ ] AC-MỚI-B")   # cùng scope → gom
alone() {
  if [ "$rc" = 0 ] && [ "$(edited)" = NONE ] && [ "$(called issue create)" = 1 ]; then ok "$1"
  else fail "$1: rc=$rc edit=$(edited) create=$(called issue create) $(tail -3 "$TMP/out")"; fi
}
folded() {   # folded <tên ca> — thẻ #7 nhận việc mới, không tạo thẻ
  if [ "$rc" = 0 ] && [ "$(edited)" = 7 ] && [ "$(called issue create)" = 0 ]; then ok "$1"
  else fail "$1: rc=$rc edit=$(edited) create=$(called issue create) $(tail -3 "$TMP/out")"; fi
}

# Q1 — Refs #721, #722, #723: cả ba đang chạy; #723 (số lớn nhất) không được gom vào.
items '[{"n":723,"status":"Ready"}]'
export FAKE_PRS='[{"headRefName":"misc","body":"Refs #721, #722, #723\n"}]'
rc=$(run "${SAME[@]}"); alone "Q1 'Refs #721, #722, #723' → #723 đang chạy, không gom"
export FAKE_PRS='[{"headRefName":"misc","body":"Closes #721 and #723"}]'
rc=$(run "${SAME[@]}"); alone "Q1b 'Closes #721 and #723' → #723 đang chạy, không gom"

# Q2 — #7 chỉ nằm trong code span / code fence: không phải từ khoá thật ⇒ #7 chưa chạy, gom như cũ.
items '[{"n":7,"status":"Ready"}]'
export FAKE_PRS='[{"headRefName":"misc","body":"ví dụ `Closes #7` trong code"}]'
rc=$(run "${SAME[@]}"); folded "Q2 code span 'Closes #7' không tính → gom vào #7"
export FAKE_PRS='[{"headRefName":"misc","body":"mẫu:\n```\nCloses #7\n```\nhết"}]'
rc=$(run "${SAME[@]}"); folded "Q2b code fence 'Closes #7' không tính → gom vào #7"

# Q3 — closingIssuesReferences trỏ #7 của repo KHÁC: không loại #7 của repo này; cùng repo (hoa thường tuỳ ý) thì loại.
export FAKE_PRS='[{"headRefName":"misc","body":"x","closingIssuesReferences":[{"number":7,"repository":{"name":"other","owner":{"login":"someone"}}}]}]'
rc=$(run "${SAME[@]}"); folded "Q3 closingIssuesReferences #7 của repo khác → vẫn gom vào #7"
export FAKE_PRS='[{"headRefName":"misc","body":"x","closingIssuesReferences":[{"number":7,"repository":{"name":"Agent-Workbench","owner":{"login":"toanmobile"}}}]}]'
rc=$(run "${SAME[@]}"); alone "Q3b closingIssuesReferences #7 cùng repo → đang chạy, không gom"
unset FAKE_PRS

# Q4 — Backlog #7: PR liên kết thẻ ngay SAU khi ghi: lần ghi vẫn thành công, không sinh thẻ trùng.
items '[{"n":7}]'
export FAKE_LINKED_AFTER_EDIT=7
rc=$(run "${SAME[@]}"); folded "Q4 PR liên kết sau khi ghi → không tạo thẻ trùng"
unset FAKE_LINKED_AFTER_EDIT

# Q5 — AC mặc định (không --ac) dùng --scoped, cấm --full cho từng task.
items '[]'
rc=$(run --title "✨ [feature] hooks: việc C" --problem "p" --fix "f")
if grep -q 'run-tests --scoped --brief' "$FAKE_DIR/issue99.body" 2>/dev/null && ! grep -q -- '--full' "$FAKE_DIR/issue99.body"; then ok "Q5 AC mặc định dùng --scoped"
else fail "Q5 rc=$rc $(grep -n 'post-fix-gate' "$FAKE_DIR/issue99.body" 2>/dev/null)"; fi

if [ "$FAILS" -eq 0 ]; then echo "test_create_task_pr_mention_812: all passed"; exit 0; else echo "test_create_task_pr_mention_812: $FAILS failed"; exit 1; fi
