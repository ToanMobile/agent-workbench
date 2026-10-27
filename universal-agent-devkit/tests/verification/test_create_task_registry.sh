#!/usr/bin/env bash
# Test: createTask (scripts/governance/create_task.py) chọn đúng repo và đúng cột Backlog của board.
# 22/10: (a) origin có dấu chấm (Humans-vs.-UFOs) bị cắt thành None nên rơi về agent-workbench, repo này cũng không
# có trong registry; (b) ID cột Backlog cứng trong registry đã cũ nên thẻ mới tạo có cột trống mà script vẫn in
# THÀNH CÔNG. Bây giờ: slug chấp nhận dấu chấm, Humans có board #6, ID Backlog đọc từ `gh project field-list`
# lúc chạy, và lỗi gán cột làm script thoát khác 0.
# gh giả (đầu PATH) ghi từng lệnh vào calls.jsonl. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/bin" "$TMP/repo"
export FAKE_LOG="$TMP/calls.jsonl"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
if a[:2] == ["issue", "create"]:
    print("https://github.com/ToanMobile/x/issues/1"); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({} if os.environ.get("FAKE_ITEMADD_NOID") else {"id": "PVTI_1"})); sys.exit(0)
if a[:2] == ["project", "view"]:
    print(json.dumps({"id": "PVT_FROM_VIEW"})); sys.exit(0)
if a[:2] == ["project", "field-list"]:
    if os.environ.get("FAKE_FIELDLIST_BODY"):
        print(os.environ["FAKE_FIELDLIST_BODY"]); sys.exit(0)
    if os.environ.get("FAKE_FIELDLIST_RC"):
        sys.stderr.write("fake gh: field-list failed\n"); sys.exit(int(os.environ["FAKE_FIELDLIST_RC"]))
    print(json.dumps({"fields": [{"id": "FIELD_STATUS", "name": "Status",
          "options": [{"id": "OPT_NEEDS", "name": "Needs You"}, {"id": "OPT_BACKLOG", "name": "Backlog"}]}]}))
    sys.exit(0)
if a[:2] == ["project", "item-edit"]:
    sys.exit(int(os.environ.get("FAKE_EDIT_RC", "0")))
if a[:2] == ["label", "create"]:
    sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"

run() { : > "$FAKE_LOG"; (cd "$TMP/repo" && python3 "$CT" "$@") >"$TMP/out" 2>&1; echo $?; }
call_arg() { python3 - "$1" "$2" <<'PY'
import json, os, sys
verb, flag = sys.argv[1], sys.argv[2]
for l in open(os.environ["FAKE_LOG"]):
    a = json.loads(l).get("gh", [])
    if " ".join(a[:2]) == verb:
        if flag == "@2":
            print(a[2]); sys.exit(0)
        if flag in a:
            print(a[a.index(flag) + 1]); sys.exit(0)
print("NONE")
PY
}

HUMANS_SSH="git@github.com:ToanMobile/Humans-vs.-UFOs.git"

# 1. Origin có dấu chấm: repo đích là Humans-vs.-UFOs, board #6 (không rơi về agent-workbench / #1).
git -C "$TMP/repo" remote set-url origin "$HUMANS_SSH"
rc=$(run --title "🐛 [bug] ufo: màn thua treo" --problem "x" --ac "- [ ] y")
[ "$rc" = "0" ] && ok "1a origin có dấu chấm → exit 0" || fail "1a exit $rc"
[ "$(call_arg "issue create" --repo x)" = "ToanMobile/Humans-vs.-UFOs" ] && ok "1b issue tạo ở Humans-vs.-UFOs" || fail "1b tạo ở $(call_arg "issue create" --repo x)"
[ "$(call_arg "project item-add" @2 x)" = "6" ] && ok "1c đẩy vào Project #6" || fail "1c board $(call_arg "project item-add" @2 x)"
git -C "$TMP/repo" remote set-url origin https://github.com/ToanMobile/agent-workbench.git

# 2. --repo Humans từ checkout khác → Project #6.
rc=$(run --repo ToanMobile/Humans-vs.-UFOs --title "🐛 [bug] ufo: màn thua treo" --problem "x" --ac "- [ ] y")
[ "$rc" = "0" ] && [ "$(call_arg "project item-add" @2 x)" = "6" ] && ok "2 --repo Humans → Project #6" || fail "2 exit $rc, board $(call_arg "project item-add" @2 x)"

# 3. Tiêu đề nêu Humans-vs.-UFOs mà không --repo, từ checkout agent-workbench → từ chối.
rc=$(run --title "🔧 [chore] Humans-vs.-UFOs: dọn nhánh" --problem "x" --ac "- [ ] y")
[ "$rc" = "64" ] && ok "3 nêu Humans-vs.-UFOs, không --repo → exit 64" || fail "3 exit $rc (want 64)"

# 4. ID cột Backlog và ID trường Status lấy từ `gh project field-list` lúc chạy.
rc=$(run --title "🐛 [bug] runner: kẹt" --problem "x" --ac "- [ ] y")
[ "$(call_arg "project item-edit" --single-select-option-id x)" = "OPT_BACKLOG" ] && ok "4 dùng option Backlog đọc từ field-list" || fail "4 option $(call_arg "project item-edit" --single-select-option-id x)"
[ "$(call_arg "project item-edit" --field-id x)" = "FIELD_STATUS" ] && ok "4b field id lấy từ field-list" || fail "4b field $(call_arg "project item-edit" --field-id x)"

# 5. Lỗi gán cột: thoát khác 0, không in THÀNH CÔNG.
: > "$FAKE_LOG"
(cd "$TMP/repo" && FAKE_EDIT_RC=1 python3 "$CT" --title "🐛 [bug] runner: kẹt" --problem "x" --ac "- [ ] y") >"$TMP/out" 2>&1; rc=$?
[ "$rc" = "3" ] && ok "5a item-edit lỗi → exit 3" || fail "5a exit $rc (want 3)"
grep -q "THÀNH CÔNG" "$TMP/out" && fail "5b vẫn in THÀNH CÔNG khi gán cột lỗi" || ok "5b không in THÀNH CÔNG khi gán cột lỗi"

# 6. Từ checkout Humans, thẻ nêu chính Humans-vs.-UFOs là thẻ của repo này: không bị coi là "repo khác".
git -C "$TMP/repo" remote set-url origin "$HUMANS_SSH"
rc=$(run --title "🐛 [bug] Humans-vs.-UFOs: màn thua treo" --problem "x" --ac "- [ ] y")
[ "$rc" = "0" ] && [ "$(call_arg "project item-add" @2 x)" = "6" ] && ok "6 Humans nêu chính nó → exit 0, Project #6" || fail "6 exit $rc, board $(call_arg "project item-add" @2 x)"
git -C "$TMP/repo" remote set-url origin https://github.com/ToanMobile/agent-workbench.git

# 7. gh project field-list lỗi: dùng ID trong registry, ID cột Backlog của Project #1 và Project #5 phải là ID thật hiện nay.
: > "$FAKE_LOG"
(cd "$TMP/repo" && FAKE_FIELDLIST_RC=1 python3 "$CT" --title "🐛 [bug] runner: kẹt" --problem "x" --ac "- [ ] y") >"$TMP/out" 2>&1; rc=$?
[ "$rc" = "0" ] && ok "7a field-list lỗi vẫn tạo được thẻ (exit 0)" || fail "7a exit $rc"
[ "$(call_arg "project item-edit" --single-select-option-id x)" = "81f934af" ] && ok "7b dự phòng dùng ID Backlog thật của Project #1" || fail "7b option $(call_arg "project item-edit" --single-select-option-id x)"
grep -q "dự phòng" "$TMP/out" && ok "7c có cảnh báo khi dùng ID dự phòng" || fail "7c thiếu cảnh báo dùng ID dự phòng"
: > "$FAKE_LOG"
(cd "$TMP/repo" && FAKE_FIELDLIST_RC=1 python3 "$CT" --repo ToanMobile/Idle-Plaza-3D --title "🐛 [bug] plaza: kẹt" --problem "x" --ac "- [ ] y") >"$TMP/out" 2>&1; rc=$?
[ "$rc" = "0" ] && [ "$(call_arg "project item-add" @2 x)" = "5" ] && [ "$(call_arg "project item-edit" --single-select-option-id x)" = "5eaaa6e6" ] \
  && ok "7d Idle-Plaza-3D gắn đúng Project #5 và ID Backlog dự phòng 5eaaa6e6" \
  || fail "7d exit $rc, board $(call_arg "project item-add" @2 x), opt $(call_arg "project item-edit" --single-select-option-id x)"

# 8. item-add không trả id thì thẻ chưa có cột: exit 3 và có lỗi, không im lặng.
: > "$FAKE_LOG"
(cd "$TMP/repo" && FAKE_ITEMADD_NOID=1 python3 "$CT" --title "🐛 [bug] runner: kẹt" --problem "x" --ac "- [ ] y") >"$TMP/out" 2>&1; rc=$?
[ "$rc" = "3" ] && ok "8 item-add không có id → exit 3" || fail "8 exit $rc (want 3)"

# 9. field-list trả JSON hợp lệ nhưng sai hình dạng: dùng ID dự phòng, không văng traceback.
: > "$FAKE_LOG"
(cd "$TMP/repo" && FAKE_FIELDLIST_BODY='{"fields": null}' python3 "$CT" --title "🐛 [bug] runner: kẹt" --problem "x" --ac "- [ ] y") >"$TMP/out" 2>&1; rc=$?
[ "$rc" = "0" ] && ! grep -q "Traceback" "$TMP/out" && ok "9 JSON sai hình dạng → dự phòng, không traceback" || fail "9 exit $rc: $(tail -2 "$TMP/out")"

# 10. Repo ngoài registry tìm board qua .claude/super-board/configs: project id đọc từ `gh project view`, không để trống.
mkdir -p "$TMP/repo/.claude/super-board/configs"
echo '{"project": {"number": 9, "title": "Ngoai registry"}}' > "$TMP/repo/.claude/super-board/configs/x.json"
: > "$FAKE_LOG"
(cd "$TMP/repo" && python3 "$CT" --repo ToanMobile/NgoaiRegistry --title "🐛 [bug] runner: kẹt" --problem "x" --ac "- [ ] y") >"$TMP/out" 2>&1; rc=$?
[ "$rc" = "0" ] && [ "$(call_arg "project item-edit" --project-id x)" = "PVT_FROM_VIEW" ] && ok "10 project id đọc từ gh project view" || fail "10 exit $rc, project-id $(call_arg "project item-edit" --project-id x)"

# 11. dry-run dừng trước bước tra project id (gh project view chỉ chạy khi tạo thẻ thật).
: > "$FAKE_LOG"
(cd "$TMP/repo" && python3 "$CT" --dry-run --repo ToanMobile/NgoaiRegistry --title "🐛 [bug] runner: kẹt" --problem "x" --ac "- [ ] y") >"$TMP/out" 2>&1; rc=$?
[ "$rc" = "0" ] && ! grep -q '"project", "view"' "$FAKE_LOG" && ok "11 dry-run không gọi gh project view" || fail "11 exit $rc, log: $(grep -c 'project", "view' "$FAKE_LOG") lệnh view"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
