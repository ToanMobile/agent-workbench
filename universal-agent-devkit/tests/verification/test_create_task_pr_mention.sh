#!/usr/bin/env bash
# Test #735 + #731 AC1: createTask không gom (và không lập đợt) vào thẻ đang chạy khi PR mở của nó không theo mẫu nhánh issue-<N>-.
# 31/10: PR #730 chạy #721 #722 #723 trên nhánh fix-stop-hold-fixture-now; create_task chỉ coi Ready là "đã chạy" khi có PR mở head
# `issue-<N>-`, nên đã gom 3 dòng AC chưa tick + mục "Gộp thêm" vào #723 (hoàn tác tay). Bây giờ:
# - Ready: thẻ có PR mở nhắc nó (body Closes/Fixes/Resolves/Refs #N, hoặc closingIssuesReferences) là đang chạy — cùng một lệnh
#   `gh pr list` như trước (thêm trường body, closingIssuesReferences), không thêm lệnh mạng.
# - Backlog (không đọc PR khi chỉ có Backlog — test_create_task_batch ca 38): lần đọc lại thẻ đích ngay trước khi ghi (`gh issue view`,
#   đã có) mang thêm closedByPullRequestsReferences; thẻ có PR sắp đóng nó thì không gom, không làm thẻ trưởng.
# - Thẻ không PR nào nhắc: gom như cũ.
# gh giả (đầu PATH): item-list trả FAKE_ITEMS, pr list trả FAKE_PRS, issue view đánh dấu PR liên kết cho số trong FAKE_LINKED.
# Tương thích bash 3.2. Offline.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset SB_MAX_BATCH_CARDS SB_MAX_BATCH_AC SB_MAX_CARD_AC FAKE_PRS FAKE_LINKED

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
    linked = [{"number": 730, "url": "https://github.com/ToanMobile/agent-workbench/pull/730"}] \
        if n in os.environ.get("FAKE_LINKED", "").split(",") else []
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

# items <json-list>: mỗi thẻ {n, status, title, body}; body mặc định: 1 AC, Risk 🟢, Blocked by - None.
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
marker_of() { sed -n 's/.*<!-- sb:batch-of #\([0-9]*\) -->.*/\1/p' "$FAKE_DIR/issue$1.body" 2>/dev/null | head -1; }
SAME=(--title "✨ [feature] hooks: thêm việc B" --problem "vấn đề B" --fix "sửa B" --ac "- [ ] AC-MỚI-B")   # cùng scope → gom
OTHER=(--title "✨ [feature] gate: việc gate" --problem "vấn đề gate" --fix "sửa gate" --ac "- [ ] AC-gate")  # khác scope → đợt
# alone <tên ca>: thẻ mới đứng riêng — không gom vào thẻ nào, không marker đợt.
alone() {
  if [ "$rc" = 0 ] && [ "$(edited)" = NONE ] && [ "$(called issue create)" = 1 ] && [ -z "$(marker_of 99)" ]; then ok "$1"
  else fail "$1: rc=$rc edit=$(edited) create=$(called issue create) marker=$(marker_of 99) $(tail -3 "$TMP/out")"; fi
}

# P1 — ca #735: Ready #7 có PR mở nhánh tên tuỳ ý, body 'Closes #7' ⇒ việc mới KHÔNG gom vào #7 (và không lập đợt #7).
items '[{"n":7,"status":"Ready"}]'
export FAKE_PRS='[{"headRefName":"fix-stop-hold-fixture-now","body":"Tóm tắt\n\nCloses #7\n","closingIssuesReferences":[]}]'
rc=$(run "${SAME[@]}"); alone "P1 Ready #7 có PR nhánh tuỳ ý 'Closes #7' → không gom, thẻ riêng"
[ "$(called pr list)" = 1 ] && ok "P1b vẫn đúng một lệnh gh pr list (không thêm lệnh mạng)" || fail "P1b pr list=$(called pr list)"
rc=$(run "${OTHER[@]}"); alone "P1c khác scope: Ready #7 đang chạy không thành thẻ trưởng đợt"

# P2 — 'Refs #7' (PR #730 dạng: một PR chạy nhiều thẻ) cũng là đang chạy; từ khoá Fixes:/resolved cũng vậy.
for body in 'Refs #7' 'Fixes: #7' 'resolved ToanMobile/agent-workbench#7'; do
  export FAKE_PRS="[{\"headRefName\":\"misc-branch\",\"body\":\"x\\n$body\\n\"}]"
  rc=$(run "${SAME[@]}"); alone "P2 Ready #7, PR body '$body' → không gom"
done

# P3 — PR liên kết thẻ qua closingIssuesReferences (body không nhắc) ⇒ đang chạy.
export FAKE_PRS='[{"headRefName":"misc-branch","body":"không nhắc số","closingIssuesReferences":[{"number":7,"repository":{"name":"agent-workbench","owner":{"login":"ToanMobile"}}}]}]'
rc=$(run "${SAME[@]}"); alone "P3 Ready #7 trong closingIssuesReferences của PR mở → không gom"

# P4 — hai Ready cùng scope; PR mở chỉ nhắc #9 (số lớn, lẽ ra được chọn) ⇒ gom vào #7 chưa chạy.
items '[{"n":7,"status":"Ready"},{"n":9,"status":"Ready"}]'
export FAKE_PRS='[{"headRefName":"fix-other","body":"Fixes #9"}]'
rc=$(run "${SAME[@]}")
[ "$rc" = 0 ] && [ "$(edited)" = 7 ] && [ "$(called issue create)" = 0 ] \
  && ok "P4 PR nhắc #9 → bỏ #9, gom vào Ready #7" || fail "P4 rc=$rc edit=$(edited) create=$(called issue create)"

# P5 — thẻ Ready không PR nào nhắc (PR mở khác: Closes #50, chữ '#7' không đứng sau từ khoá) vẫn gom như cũ.
items '[{"n":7,"status":"Ready"}]'
export FAKE_PRS='[{"headRefName":"fix-other","body":"Closes #50\nxem thêm #7","closingIssuesReferences":[{"number":50}]}]'
rc=$(run "${SAME[@]}")
[ "$rc" = 0 ] && [ "$(edited)" = 7 ] && [ "$(called issue create)" = 0 ] && ok "P5 Ready #7 không PR nào nhắc → gom như cũ" \
  || fail "P5 rc=$rc edit=$(edited) create=$(called issue create)"
unset FAKE_PRS

# P6 — #731 AC1: thẻ BACKLOG #7 có PR mở 'Closes #7' (GitHub liên kết: closedByPullRequestsReferences khi đọc lại thẻ) ⇒ không gom,
#      không lập đợt; P6b đếm lệnh gh pr list = 0 khi chỉ có Backlog (cùng luật ca 38 của test_create_task_batch.sh).
items '[{"n":7}]'
export FAKE_LINKED=7
rc=$(run "${SAME[@]}"); alone "P6 Backlog #7 có PR mở sắp đóng nó → không gom"
[ "$(called pr list)" = 0 ] && ok "P6b chỉ Backlog: không gọi gh pr list" || fail "P6b pr list=$(called pr list)"
rc=$(run "${OTHER[@]}"); alone "P6c khác scope: Backlog #7 có PR mở không thành thẻ trưởng đợt"
unset FAKE_LINKED

# P7 — Backlog #7 không PR nào liên kết: gom như cũ, đúng hai lần đọc thẻ (trước + sau khi ghi), không thêm lệnh.
items '[{"n":7}]'
rc=$(run "${SAME[@]}")
[ "$rc" = 0 ] && [ "$(edited)" = 7 ] && [ "$(called issue create)" = 0 ] && [ "$(called issue view)" = 2 ] && [ "$(called pr list)" = 0 ] \
  && ok "P7 Backlog #7 không PR liên kết → gom như cũ, 2 lần issue view, 0 pr list" \
  || fail "P7 rc=$rc edit=$(edited) create=$(called issue create) view=$(called issue view) pr=$(called pr list)"
rc=$(run "${OTHER[@]}")
[ "$rc" = 0 ] && [ "$(marker_of 99)" = 7 ] && ok "P7b khác scope, Backlog #7 không PR → đợt #7 như cũ" || fail "P7b rc=$rc marker=$(marker_of 99)"

if [ "$FAILS" -eq 0 ]; then echo "test_create_task_pr_mention: all passed"; exit 0; else echo "test_create_task_pr_mention: $FAILS failed"; exit 1; fi
