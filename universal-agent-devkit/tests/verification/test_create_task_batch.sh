#!/usr/bin/env bash
# Test: createTask (scripts/governance/create_task.py) GOM việc vào thẻ Backlog đang có thay vì mở thẻ mới.
# 23/10: mỗi việc nhỏ thành một thẻ → mỗi thẻ một PR, một merge-gate, một lần gate --full chạy đè nhau
# (load 112 trên 12 lõi). Bây giờ: thẻ mới cùng loại (bug/feature/qa) tự nhập vào thẻ Backlog hợp nhất
# (trùng file nhiều nhất, hòa thì thẻ mới nhất); mở thẻ riêng chỉ khi --new-card "<lý do>", thẻ cần người,
# khác loại, không có thẻ Backlog, thẻ đã đủ MAX_BATCH việc, --from-file hoặc gh không đọc được board.
# gh giả (đầu PATH): item-list trả FAKE_ITEMS, mọi lệnh ghi vào calls.jsonl. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/bin" "$TMP/repo"
export FAKE_LOG="$TMP/calls.jsonl" FAKE_ITEMS="$TMP/items.json" FAKE_EDITED="$TMP/edited.txt"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
if a[:2] == ["issue", "create"]:
    print("https://github.com/ToanMobile/agent-workbench/issues/99"); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_1"})); sys.exit(0)
if a[:2] == ["issue", "edit"] and os.environ.get("FAKE_EDIT_FAIL"):
    sys.stderr.write("fake gh: edit refused\n"); sys.exit(1)
if a[:2] == ["issue", "edit"]:
    open(os.environ["FAKE_EDITED"], "w").write(a[a.index("--body") + 1])
if a[:2] == ["issue", "view"]:
    ed, vb = os.environ["FAKE_EDITED"], os.environ.get("FAKE_VIEW_BODY", "")
    if os.path.exists(ed) and not os.environ.get("FAKE_VIEW_STALE"):
        body = open(ed).read()
    elif vb and os.path.exists(vb):
        body = open(vb).read()
    else:
        body = next((i["content"]["body"] for i in json.load(open(os.environ["FAKE_ITEMS"]))["items"]
                     if str(i["content"]["number"]) == a[2]), "")
    print(json.dumps({"body": body, "state": "CLOSED" if os.environ.get("FAKE_VIEW_CLOSED") else "OPEN"})); sys.exit(0)
if a[:2] in (["project", "item-edit"], ["label", "create"], ["issue", "edit"]):
    sys.exit(0)
if a[:2] == ["project", "item-list"] and os.environ.get("FAKE_SLEEP"):
    import time; time.sleep(float(os.environ["FAKE_SLEEP"]))
if a[:2] == ["project", "item-list"] and os.path.exists(os.environ["FAKE_ITEMS"]):
    sys.stdout.write(open(os.environ["FAKE_ITEMS"]).read()); sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"

# items <json-list-of-cards>: mỗi thẻ {n,status,label,body}
items() { python3 - "$1" <<'PY'
import json, os, sys
out = []
for c in json.loads(sys.argv[1]):
    out.append({"status": c.get("status", "Backlog"), "labels": c.get("labels") or [c.get("label", "feature")],
                "content": {"type": "Issue", "repository": c.get("repo", "ToanMobile/agent-workbench"), "number": c["n"], "title": c.get("title", "thẻ %d" % c["n"]),
                            "body": c.get("body", "## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n🟢\n")}})
open(os.environ["FAKE_ITEMS"], "w").write(json.dumps({"items": out}))
PY
}
run() { : > "$FAKE_LOG"; rm -f "$FAKE_EDITED"; (cd "$TMP/repo" && python3 "$CT" "$@") >"$TMP/out" 2>&1; echo $?; }
called() { python3 - "$1" "$2" <<'PY'
import json, os, sys
want = sys.argv[1:3]
print(sum(1 for l in open(os.environ["FAKE_LOG"]) if json.loads(l).get("gh", [])[:2] == want))
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
edited_body() { python3 - <<'PY'
import json, os
for l in open(os.environ["FAKE_LOG"]):
    a = json.loads(l).get("gh", [])
    if a[:2] == ["issue", "edit"]:
        print(a[a.index("--body") + 1]); break
PY
}
NEWARGS=(--title "✨ [feature] hooks: thêm việc B" --problem "vấn đề B" --fix "sửa B" --ac "- [ ] AC-MỚI-B")

# 1. Có một thẻ Backlog cùng loại → nhập vào đó, không mở issue mới.
items '[{"n":7}]'
rc=$(run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(edited)" = "7" ] && [ "$(called issue create)" = "0" ] && ok "1 nhập vào #7, không tạo issue" || fail "1 rc=$rc edit=$(edited) create=$(called issue create)"
body="$(edited_body)"
case "$body" in *"## Gộp thêm: "*"thêm việc B"*) ok "1b có mục Gộp thêm mang tiêu đề việc mới" ;; *) fail "1b thiếu mục Gộp thêm" ;; esac
case "$body" in *"vấn đề B"*"sửa B"*) ok "1c Problem + Fix của việc mới nằm trong thẻ" ;; *) fail "1c thiếu Problem/Fix" ;; esac
# AC mới phải nằm TRONG mục ## Acceptance Criteria của thẻ (lane đọc mục đó), trước ## Risk.
python3 - "$body" <<'PY' && ok "1d AC mới nằm trong mục Acceptance Criteria" || fail "1d AC mới không nằm trong mục AC"
import re, sys
b = sys.argv[1]
m = re.search(r"## Acceptance Criteria\n(.*?)\n## ", b, re.S)
sys.exit(0 if m and "AC-MỚI-B" in m.group(1) and "- [ ] cũ" in m.group(1) else 1)
PY

# 2. Nhiều thẻ Backlog: ưu tiên thẻ trùng file nhiều nhất.
items '[{"n":7},{"n":8,"body":"## Problem\nsửa universal-agent-devkit/bin/post-fix-gate.py\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n🟢\n"},{"n":9}]'
rc=$(run --title "✨ [feature] gate: việc C" --problem "đụng universal-agent-devkit/bin/post-fix-gate.py" --ac "- [ ] C")
[ "$rc" = "0" ] && [ "$(edited)" = "8" ] && ok "2 trùng file → nhập vào #8" || fail "2 rc=$rc edit=$(edited)"

# 3. Không trùng file → vẫn gom, vào thẻ Backlog cùng loại MỚI NHẤT (số lớn nhất).
items '[{"n":7},{"n":9},{"n":8}]'
rc=$(run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(edited)" = "9" ] && ok "3 không trùng file → thẻ mới nhất #9" || fail "3 rc=$rc edit=$(edited)"

# 4. --new-card "<lý do>" → mở thẻ riêng.
items '[{"n":7}]'
rc=$(run --new-card "việc độc lập cần PR riêng" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "4 --new-card → tạo issue riêng" || fail "4 rc=$rc create=$(called issue create)"
rc=$(run --new-card "" "${NEWARGS[@]}")
[ "$rc" = "64" ] && [ "$(called issue create)" = "0" ] && ok "4b --new-card rỗng (không lý do) → exit 64" || fail "4b rc=$rc"

# 5. Khác loại (bug vs feature) → không nhập; QA/bug có đường chạy khác nhau trên board.
items '[{"n":7,"label":"feature"}]'
rc=$(run --title "🐛 [bug] hooks: lỗi Z" --problem "z" --ac "- [ ] z")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "5 bug không nhập vào thẻ feature" || fail "5 rc=$rc create=$(called issue create)"

# 6. Thẻ đã Building/Review/Done không nhận thêm việc.
items '[{"n":7,"status":"Building"},{"n":8,"status":"Review"},{"n":9,"status":"Done"}]'
rc=$(run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "6 không nhập vào thẻ đã chạy" || fail "6 rc=$rc create=$(called issue create)"

# 7. Backlog trống → tạo mới như cũ.
items '[]'
rc=$(run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "7 Backlog trống → tạo mới" || fail "7 rc=$rc"

# 8. Thẻ cần người không nhập (nhập vào là chặn lane build của thẻ kia).
items '[{"n":7}]'
rc=$(run --needs-you "Cắm máy thật" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "8 --needs-you → thẻ riêng" || fail "8 rc=$rc create=$(called issue create)"

# 9. Trần MAX_BATCH = 6 việc/thẻ tính cả việc gốc: thẻ đã đủ thì việc kế mở thẻ mới (PR > 400 dòng phải người duyệt).
big="## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n🟢\n"
for i in 1 2 3 4 5; do big="$big\n## Gộp thêm: việc $i\nx\n"; done
items "[{\"n\":7,\"body\":\"$big\"}]"
rc=$(run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && ok "9 thẻ đủ 6 việc (gốc + 5 gộp) → thẻ mới" || fail "9 rc=$rc create=$(called issue create)"
big4="## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n🟢\n"
for i in 1 2 3 4; do big4="$big4\n## Gộp thêm: việc $i\nx\n"; done
items "[{\"n\":7,\"body\":\"$big4\"}]"
rc=$(run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(edited)" = "7" ] && ok "9b thẻ 5 việc (gốc + 4 gộp) còn nhận thêm" || fail "9b rc=$rc edit=$(edited)"

# 10. gh không đọc được board → tạo thẻ như cũ (không chặn tạo việc vì lỗi mạng), có cảnh báo.
rm -f "$FAKE_ITEMS"
rc=$(run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && ok "10a board không đọc được → vẫn tạo" || fail "10a rc=$rc create=$(called issue create)"
grep -q "không đọc được board" "$TMP/out" && ok "10b có cảnh báo không gom được" || fail "10b không cảnh báo"

# 11. --dry-run: báo sẽ nhập vào thẻ nào, không ghi gì.
items '[{"n":7}]'
rc=$(run --dry-run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(edited)" = "NONE" ] && [ "$(called issue create)" = "0" ] && grep -q "#7" "$TMP/out" && ok "11 dry-run báo #7, không ghi" || fail "11 rc=$rc"

# 12. --from-file --ticket: ticket có chủ đích trong file → tạo như cũ.
cat > "$TMP/backlog.md" <<'MD'
### TICKET-1: ⚡ [perf] context: cắt byte nạp đầu phiên

## Problem
Đo vượt trần.
MD
items '[{"n":7}]'
rc=$(run --from-file "$TMP/backlog.md" --ticket 1)
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "12 --from-file --ticket không bị gom" || fail "12 rc=$rc"

# 13. Câu tóm tắt nhanh cũng gom.
items '[{"n":7}]'
rc=$(run "thêm log cho review_gate")
[ "$rc" = "0" ] && [ "$(edited)" = "7" ] && ok "13 tóm tắt nhanh cũng gom" || fail "13 rc=$rc edit=$(edited)"

# 14. Thẻ Backlog đang chờ người (nhãn needs-you) không nhận thêm việc của lane.
python3 - <<'PY'
import json, os
open(os.environ["FAKE_ITEMS"], "w").write(json.dumps({"items": [{"status": "Backlog", "labels": ["feature", "needs-you"],
    "content": {"type": "Issue", "repository": "ToanMobile/agent-workbench", "number": 7, "title": "chờ người", "body": "## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n"}}]}))
PY
rc=$(run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "14 thẻ needs-you không nhận thêm việc" || fail "14 rc=$rc"

# 15. Thẻ Backlog của repo KHÁC trên cùng board không được nhận (gh issue edit sẽ ghi đè nhầm issue cùng số).
items '[{"n":7,"repo":"ToanMobile/OfficeReader"}]'
rc=$(run "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "15 thẻ repo khác → không gom" || fail "15 rc=$rc"

# 16. Việc có --blocked-by hoặc rủi ro khác 🟢 không gom (blocker/rủi ro không tách được khỏi thẻ chứa).
items '[{"n":7}]'
rc=$(run --blocked-by "- #123 — chờ" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "16a --blocked-by → thẻ riêng" || fail "16a rc=$rc"
rc=$(run --risk "🔴 **High** · đụng auth" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "16b rủi ro cao → thẻ riêng" || fail "16b rc=$rc"
rc=$(run --risk "🟢 **Low** · cục bộ" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(edited)" = "7" ] && ok "16c rủi ro 🟢 vẫn gom" || fail "16c rc=$rc"
# 24/10 (người dùng: "gom task … hiện không hoạt động"): gần như mọi thẻ ghi 🟡 Medium nên trước đây không bao giờ gom.
# Chỉ 🔴 High mới tách thẻ riêng; 🟡 gom như 🟢.
rc=$(run --risk "🟡 **Medium** · chạm gate" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(edited)" = "7" ] && [ "$(called issue create)" = "0" ] && ok "16d rủi ro 🟡 cũng gom" || fail "16d rc=$rc edited=$(edited)"
edited_body | grep -q "🟡" && ok "16d thẻ gom mang theo rủi ro 🟡 của việc mới (không còn ghi 🟢 sai)" || fail "16d body không có 🟡"
edited_body | awk '/^## Risk/{f=1;next} /^## /{f=0} f' | grep -q "🟡" \
  && ok "16d mục ## Risk chính của thẻ được nâng lên 🟡 (preflight đọc mục này)" || fail "16d ## Risk chính vẫn không có 🟡"
edited_body | awk '/^## Risk/{f=1;next} /^## /{f=0} f' | grep -q "🟢" \
  && ok "16d rủi ro cũ của thẻ vẫn được giữ lại trong ## Risk" || fail "16d rủi ro cũ (🟢) bị xoá khỏi ## Risk"
rc=$(run --risk "**High** · đụng auth" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && [ "$(edited)" = "NONE" ] && ok "16e High viết không emoji → thẻ riêng" || fail "16e rc=$rc"
rc=$(run --risk "🟡 **Medium** · nâng cao độ phủ test, high traffic path" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(edited)" = "7" ] && ok "16f chữ cao/high trong mô tả của thẻ 🟡 không biến nó thành High" || fail "16f rc=$rc edited=$(edited)"
# Thẻ đích ghi "High" bằng chữ (không emoji): gom một việc 🟡 không được hạ ## Risk của thẻ xuống.
items '[{"n":7,"body":"## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n**High** · đụng auth\n"}]'
rc=$(run --risk "🟡 **Medium** · chạm gate" "${NEWARGS[@]}")
edited_body | awk '/^## Risk/{f=1;next} /^## /{f=0} f' | grep -v '^\s*$' | head -1 | grep -q "^\*\*High\*\*" \
  && ok "16g thẻ ghi High bằng chữ không bị hạ xuống 🟡" || fail "16g ## Risk của thẻ bị đổi: $(edited_body | awk '/^## Risk/{f=1;next} /^## /{f=0} f' | head -2)"
items '[{"n":7}]'

# 17. gh issue edit lỗi → việc KHÔNG mất: cảnh báo và tạo thẻ mới.
items '[{"n":7}]'
export FAKE_EDIT_FAIL=1
rc=$(run "${NEWARGS[@]}")
unset FAKE_EDIT_FAIL
[ "$rc" = "0" ] && [ "$(called issue edit)" = "1" ] && [ "$(called issue create)" = "1" ] && ok "17 edit lỗi → vẫn tạo thẻ mới" || fail "17 rc=$rc edit=$(called issue edit) create=$(called issue create)"

# 18. Gom lần hai: mục Gộp thêm cũ giữ nguyên, AC mới vào mục AC gốc (không dưới mục Gộp thêm cuối).
python3 - <<'PY'
import json, os
body = ("## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n🟢\n\n## Blocked by\n- None.\n\n"
        "## Gộp thêm: việc A\n### Problem\nPA\n### Fix\nFA\n")
open(os.environ["FAKE_ITEMS"], "w").write(json.dumps({"items": [{"status": "Backlog", "labels": ["feature"],
    "content": {"type": "Issue", "repository": "ToanMobile/agent-workbench", "number": 7, "title": "t", "body": body}}]}))
PY
rc=$(run "${NEWARGS[@]}")
body="$(edited_body)"
python3 - "$body" <<'PY' && ok "18 gom lần hai: AC vào mục gốc, mục Gộp thêm cũ còn nguyên" || fail "18 gom lần hai sai"
import re, sys
b = sys.argv[1]
ac = re.search(r"## Acceptance Criteria\n(.*?)\n## ", b, re.S)
good = bool(ac and "AC-MỚI-B" in ac.group(1) and "- [ ] cũ" in ac.group(1)
            and b.count("## Gộp thêm: ") == 2 and "PA" in b and "FA" in b
            and b.index("## Gộp thêm: việc A") < b.rindex("## Gộp thêm: "))
sys.exit(0 if good else 1)
PY
case "$body" in *"- [ ] [hooks] AC-MỚI-B"*) ok "18b dòng AC mới mang tên việc ([hooks])" ;; *) fail "18b AC thiếu tên việc" ;; esac

# 19. Thẻ cũ không có mục Acceptance Criteria → mục được tạo, AC mới nằm trong đó.
python3 - <<'PY'
import json, os
open(os.environ["FAKE_ITEMS"], "w").write(json.dumps({"items": [{"status": "Backlog", "labels": ["feature"],
    "content": {"type": "Issue", "repository": "ToanMobile/agent-workbench", "number": 7, "title": "t", "body": "## Problem\nx\n"}}]}))
PY
rc=$(run "${NEWARGS[@]}")
body="$(edited_body)"
python3 - "$body" <<'PY' && ok "19 thẻ không có mục AC → tạo mục AC chứa AC mới" || fail "19 sai: thiếu mục AC"
import re, sys
m = re.search(r"## Acceptance Criteria\n(.*?)(\n## |\Z)", sys.argv[1], re.S)
sys.exit(0 if m and "AC-MỚI-B" in m.group(1) else 1)
PY

# 20. gh treo quá hạn (#305) → coi như lỗi: cảnh báo, tạo thẻ mới, không treo.
items '[{"n":7}]'
export FAKE_SLEEP=5 CREATE_TASK_GH_TIMEOUT_S=1
rc=$(run "${NEWARGS[@]}")
unset FAKE_SLEEP CREATE_TASK_GH_TIMEOUT_S
[ "$rc" = "0" ] && [ "$(called issue create)" = "1" ] && grep -q "quá 1s" "$TMP/out" && ok "20 gh treo → hết hạn, tạo thẻ mới" || fail "20 rc=$rc"

# 21. Lost update (review P1): body đọc LẠI ngay trước khi ghi; việc người vừa sửa trong thẻ không bị đè.
printf '%s' $'## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n- [ ] NGƯỜI-VỪA-THÊM\n\n## Risk\n🟢\n' > "$TMP/fresh.md"
items '[{"n":7}]'
export FAKE_VIEW_BODY="$TMP/fresh.md"
rc=$(run "${NEWARGS[@]}")
unset FAKE_VIEW_BODY
case "$(edited_body)" in *"NGƯỜI-VỪA-THÊM"*"AC-MỚI-B"*) ok "21 gom trên body đọc lại (giữ phần người vừa sửa)" ;; *) fail "21 body ghi đè phần mới nhất" ;; esac

# 22. Thẻ đã đóng khi đọc lại → không gom, tạo thẻ mới.
items '[{"n":7}]'
export FAKE_VIEW_CLOSED=1
rc=$(run "${NEWARGS[@]}")
unset FAKE_VIEW_CLOSED
[ "$rc" = "0" ] && [ "$(edited)" = "NONE" ] && [ "$(called issue create)" = "1" ] && ok "22 thẻ đã đóng → thẻ mới" || fail "22 rc=$rc"

# 23. Ghi xong đọc lại không thấy mục Gộp thêm (bị phiên khác đè) → việc không mất: tạo thẻ mới.
items '[{"n":7}]'
export FAKE_VIEW_STALE=1
rc=$(run "${NEWARGS[@]}")
unset FAKE_VIEW_STALE
[ "$rc" = "0" ] && [ "$(called issue edit)" = "1" ] && [ "$(called issue create)" = "1" ] && ok "23 ghi bị đè → tạo thẻ mới" || fail "23 rc=$rc edit=$(called issue edit) create=$(called issue create)"

# 24. "Cùng loại" = cùng bug/feature/qa; nhãn khác (priority:high) không làm hai loại khớp, nhãn thừa của việc mới → thẻ riêng.
items '[{"n":7,"labels":["bug","priority:high"]}]'
rc=$(run --labels qa priority:high --title "🔍 [qa] hooks: kiểm Z" --problem z --ac "- [ ] z")
[ "$rc" = "0" ] && [ "$(edited)" = "NONE" ] && [ "$(called issue create)" = "1" ] && ok "24a qa không gom vào bug dù chung priority:high" || fail "24a rc=$rc"
items '[{"n":7,"labels":["bug"]}]'
rc=$(run --labels bug needs-device --title "🐛 [bug] hooks: lỗi Y" --problem y --ac "- [ ] y")
[ "$rc" = "0" ] && [ "$(edited)" = "NONE" ] && [ "$(called issue create)" = "1" ] && ok "24b nhãn thừa needs-device → thẻ riêng" || fail "24b rc=$rc"

# 25. Thẻ đích phải là thẻ runner build được: Blocked by đúng "- None.", không nhãn human-gated/wontfix/loop:halted.
items '[{"n":7,"body":"## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Blocked by\n- Không. Nên làm sau T0052.\n"}]'
rc=$(run "${NEWARGS[@]}")
[ "$(edited)" = "NONE" ] && [ "$(called issue create)" = "1" ] && ok "25a Blocked by văn xuôi → không chọn" || fail "25a rc=$rc"
items '[{"n":7,"body":"## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Blocked by\n- #12 — chờ\n"}]'
rc=$(run "${NEWARGS[@]}")
[ "$(edited)" = "NONE" ] && [ "$(called issue create)" = "1" ] && ok "25b còn blocker #12 → không chọn" || fail "25b rc=$rc"
items '[{"n":7,"body":"## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Blocked by\n- None.\n"}]'
rc=$(run "${NEWARGS[@]}")
[ "$(edited)" = "7" ] && ok "25c Blocked by - None. → chọn" || fail "25c rc=$rc"
for lbl in human-gated wontfix loop:halted; do
  items "[{\"n\":7,\"labels\":[\"feature\",\"$lbl\"]}]"
  rc=$(run "${NEWARGS[@]}")
  [ "$(edited)" = "NONE" ] && [ "$(called issue create)" = "1" ] && ok "25d nhãn $lbl → không chọn" || fail "25d $lbl rc=$rc"
done

# 26. Tên phạm vi có dấu \ không làm script chết (re.sub), AC mang tên đúng.
items '[{"n":7}]'
rc=$(run --title '✨ [feature] scripts\gov: việc B' --problem b --ac "- [ ] AC-B")
[ "$rc" = "0" ] && [ "$(edited)" = "7" ] && case "$(edited_body)" in *'[scripts\gov] AC-B'*) ok "26 tên phạm vi có dấu \\ gom được" ;; *) fail "26 AC sai" ;; esac || fail "26 rc=$rc"

# 27. Heading "## Acceptance criteria" (khác hoa thường) vẫn nhận ra: một mục AC, AC mới trong đó.
items '[{"n":7,"body":"## Problem\nx\n\n## Acceptance criteria\n- [ ] cũ\n\n## Risk\n🟢\n"}]'
rc=$(run "${NEWARGS[@]}")
body="$(edited_body)"
python3 - "$body" <<'PY' && ok "27 heading AC khác hoa thường: một mục AC chứa cả hai" || fail "27 sai"
import re, sys
b = sys.argv[1]
heads = re.findall(r"(?im)^##\s+acceptance criteria\s*$", b)
m = re.search(r"(?is)## Acceptance criteria\n(.*?)\n## ", b)
sys.exit(0 if len(heads) == 1 and m and "- [ ] cũ" in m.group(1) and "AC-MỚI-B" in m.group(1) else 1)
PY

# 28. Board dài hơn số item đọc được → cảnh báo bị cắt (thẻ mới nhất nằm cuối, dễ bị bỏ).
python3 - <<'PY'
import json, os
open(os.environ["FAKE_ITEMS"], "w").write(json.dumps({"totalCount": 900, "items": [{"status": "Backlog", "labels": ["feature"],
    "content": {"type": "Issue", "repository": "ToanMobile/agent-workbench", "number": 7, "title": "t", "body": "## Problem\nx\n\n## Acceptance Criteria\n- [ ] cũ\n"}}]}))
PY
rc=$(run "${NEWARGS[@]}")
grep -q "bị cắt" "$TMP/out" && ok "28 board vượt giới hạn đọc → cảnh báo" || fail "28 thiếu cảnh báo cắt"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
