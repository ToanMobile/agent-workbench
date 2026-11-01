#!/usr/bin/env bash
# Test #731 (2): pick_batch_lead (create_task.py) đọc lại body thẻ trưởng ngay trước khi nhận thành viên đợt, nhưng chỉ kiểm lại marker
# và Blocked by. Board trả body cũ (🟢, 2 AC) trong khi phiên song song vừa gom vào thẻ trưởng (merge_body nâng Risk lên 🔴, thêm AC):
# thẻ mới vẫn vào đợt của thẻ trưởng High, hoặc đợt vượt SB_MAX_BATCH_AC. Bây giờ: Risk và số AC tính trên body đọc lại.
# gh giả (đầu PATH): item-list trả FAKE_ITEMS (body cũ), issue view #7 trả FAKE_FRESH (body tươi). Tương thích bash 3.2. Offline.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset SB_MAX_BATCH_CARDS SB_MAX_BATCH_AC SB_MAX_CARD_AC

mkdir -p "$TMP/bin" "$TMP/repo" "$TMP/gh"
export FAKE_LOG="$TMP/calls.jsonl" FAKE_ITEMS="$TMP/items.json" FAKE_DIR="$TMP/gh" FAKE_FRESH="$TMP/fresh7.md"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
d = os.environ["FAKE_DIR"]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
def arg(name):
    return a[a.index(name) + 1] if name in a else None
def items():
    return json.load(open(os.environ["FAKE_ITEMS"]))["items"]
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
if a[:2] == ["issue", "view"]:
    n = a[2]
    fresh = os.environ["FAKE_FRESH"]
    if n == "7" and os.path.exists(fresh):
        body = open(fresh).read()
    else:
        body = next((i["content"]["body"] for i in items() if str(i["content"]["number"]) == n), None)
    if body is None:
        sys.stderr.write("fake gh: no issue %s\n" % n); sys.exit(1)
    print(json.dumps({"body": body, "state": "OPEN"})); sys.exit(0)
if a[:2] in (["project", "item-edit"], ["label", "create"], ["issue", "edit"]):
    sys.exit(0)
if a[:2] == ["pr", "list"]:
    print("[]"); sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"

# Board (body cũ) của thẻ trưởng #7: 2 AC, 🟢, Blocked by - None. Thẻ mới khác scope (gate) nên không gom, chỉ xét đợt.
python3 - <<'PY'
import json, os
body = "## Problem\nx\n\n## Acceptance Criteria\n- [ ] trưởng a\n- [ ] trưởng b\n\n## Risk\n🟢\n\n## Blocked by\n- None.\n"
open(os.environ["FAKE_ITEMS"], "w").write(json.dumps({"items": [{"status": "Backlog", "labels": ["feature"],
    "content": {"type": "Issue", "repository": "ToanMobile/agent-workbench", "number": 7,
                "title": "✨ [feature] hooks: thẻ 7", "body": body}}]}))
PY
# fresh <số AC> <dòng Risk>: body tươi của #7 như sau merge_body của phiên song song.
fresh() { python3 - "$1" "$2" <<'PY'
import os, sys
n, risk = int(sys.argv[1]), sys.argv[2]
ac = "\n".join("- [ ] ac %d" % i for i in range(n))
open(os.environ["FAKE_FRESH"], "w").write("## Problem\nx\n\n## Acceptance Criteria\n%s\n\n## Risk\n%s\n\n## Blocked by\n- None.\n\n"
                                          "## Gộp thêm: việc song song\n### Problem\np\n" % (ac, risk))
PY
}
run() { : > "$FAKE_LOG"; rm -f "$FAKE_DIR"/*; (cd "$TMP/repo" && python3 "$CT" "$@") >"$TMP/out" 2>&1; echo $?; }
called() { python3 - "$1" "$2" <<'PY'
import json, os, sys
print(sum(1 for l in open(os.environ["FAKE_LOG"]) if json.loads(l).get("gh", [])[:2] == sys.argv[1:3]))
PY
}
marker_of() { sed -n 's/.*<!-- sb:batch-of #\([0-9]*\) -->.*/\1/p' "$FAKE_DIR/issue$1.body" 2>/dev/null | head -1; }
A=(--title "✨ [feature] gate: việc gate" --problem "vấn đề gate" --fix "sửa gate" --ac "- [ ] AC-gate")

# F1 — đối chứng: body tươi như board (2 AC, 🟢) ⇒ vào đợt #7.
fresh 2 "🟢 **Low**"
rc=$(run "${A[@]}")
[ "$rc" = 0 ] && [ "$(marker_of 99)" = 7 ] && grep -q "3/16 AC" "$TMP/out" \
  && ok "F1 body tươi như board → vào đợt #7 (3/16 AC)" || fail "F1 rc=$rc marker=$(marker_of 99): $(tail -3 "$TMP/out")"

# F2 — body tươi đã thành 🔴 High (gom song song nâng Risk) ⇒ thẻ mới đứng riêng, không nhãn waiting-on.
fresh 2 "🔴 **High** · đụng auth"
rc=$(run "${A[@]}")
[ "$rc" = 0 ] && [ "$(called issue create)" = 1 ] && [ -z "$(marker_of 99)" ] && ! grep -q 'waiting-on' "$FAKE_LOG" \
  && ok "F2 thẻ trưởng tươi 🔴 High → thẻ riêng" || fail "F2 rc=$rc marker=$(marker_of 99): $(tail -3 "$TMP/out")"
fresh 2 "**High** · đụng auth"
rc=$(run "${A[@]}")
[ "$rc" = 0 ] && [ -z "$(marker_of 99)" ] && ok "F2b High viết chữ (không emoji) trong body tươi → thẻ riêng" || fail "F2b marker=$(marker_of 99)"

# F3 — body tươi có 16 AC: 16 + 1 mới = 17 > SB_MAX_BATCH_AC (mặc định 16) ⇒ thẻ riêng (board cũ chỉ thấy 2 + 1 = 3).
fresh 16 "🟢 **Low**"
rc=$(run "${A[@]}")
[ "$rc" = 0 ] && [ "$(called issue create)" = 1 ] && [ -z "$(marker_of 99)" ] \
  && ok "F3 AC tươi 16 + 1 > 16 → thẻ riêng" || fail "F3 rc=$rc marker=$(marker_of 99): $(tail -3 "$TMP/out")"
fresh 4 "🟢 **Low**"
rc=$(SB_MAX_BATCH_AC=4 run "${A[@]}")
[ "$rc" = 0 ] && [ -z "$(marker_of 99)" ] && ok "F3b SB_MAX_BATCH_AC=4: AC tươi 4 + 1 > 4 → thẻ riêng" || fail "F3b marker=$(marker_of 99)"

# F4 — biên: body tươi 15 AC + 1 = 16 = trần ⇒ vẫn vào đợt; tổng in ra là tổng tươi.
fresh 15 "🟡 **Medium**"
rc=$(run "${A[@]}")
[ "$rc" = 0 ] && [ "$(marker_of 99)" = 7 ] && grep -q "16/16 AC" "$TMP/out" \
  && ok "F4 AC tươi 15 + 1 = 16 → vào đợt, in 16/16 AC" || fail "F4 rc=$rc marker=$(marker_of 99): $(tail -3 "$TMP/out")"

[ "$FAILS" -eq 0 ] && { echo "✅ test_card_batch_fresh_lead: all passed"; exit 0; }
echo "❌ test_card_batch_fresh_lead: $FAILS failed"; exit 1
