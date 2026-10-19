#!/usr/bin/env bash
# Test: super-board-needs-you.py đánh dấu "cần người" lên thẻ bằng một lệnh, chạy lại không sinh thêm gì.
# 19/10: ~25 thẻ chỉ người làm được (máy thật, playtest, store, secret, quyết định) bị kéo nhầm sang Ready vì
# trên thẻ không có gì báo "cần bạn". Helper gắn nhãn `needs-you` (gộp `human-gated` vào đó) + MỘT comment
# "🙋 Cần bạn: … · xong thì …" có marker ẩn, và bật trường Labels trên view board để nhãn hiện ngay trên thẻ.
# Comment không được mang dòng máy đọc (`Reason tag: 🙋`, `blocked-by:`, `approval-request:`): approval.py coi
# comment như thế là yêu cầu duyệt merge mới, deps.sh đọc `blocked-by:` cuối cùng — đánh dấu sẽ làm hỏng hai luồng đó.
# gh giả trên PATH giữ trạng thái trong một file JSON, nên lần chạy thứ hai thấy đúng những gì lần đầu đã ghi.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT/.claude/bin/super-board-needs-you.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export FAKE_GH_STATE="$TMP/state.json"

cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
"""gh giả: chỉ hiểu đúng các lệnh helper dùng; lệnh lạ thì thoát 99 để test đỏ rõ ràng."""
import json, os, re, sys

path = os.environ["FAKE_GH_STATE"]
state = json.load(open(path))
args = sys.argv[1:]
state["calls"].append(args)


def save():
    json.dump(state, open(path, "w"), ensure_ascii=False)


def out(value):
    save()
    print(json.dumps(value, ensure_ascii=False))
    sys.exit(0)


def field(name):
    for i, a in enumerate(args):
        if a in ("-f", "-F", "--raw-field", "--field") and args[i + 1].startswith(name + "="):
            return args[i + 1][len(name) + 1:]
    return None


if args[:1] != ["api"]:
    save(); sys.exit(99)
method = "GET"
if "-X" in args:
    method = args[args.index("-X") + 1]
elif any(a in ("-f", "-F") for a in args) and "graphql" not in args:
    method = "POST"
route = next(a for a in args[1:] if not a.startswith("-") and a not in (method,) and "=" not in a)

if route == "graphql":
    body = json.loads(sys.stdin.read()) if "--input" in args else {"query": field("query") or "", "variables": {}}
    q, var = body["query"], body["variables"]
    state["calls"][-1] = args + [q]  # query đi qua stdin: giữ lại để test đếm được số lần gọi mutation
    proj = state["project"]
    if "updateProjectV2View" in q:
        view = next(v for v in proj["views"] if v["id"] == var["view"])
        if not isinstance(var["ids"], list):
            save(); sys.stderr.write("fake gh: ids must be a JSON list\n"); sys.exit(1)
        if not state.get("ignore_view_update"):
            view["visible"] = var["ids"]
        out({"data": {"updateProjectV2View": {"projectV2View": {"id": view["id"]}}}})
    names = {f["id"]: f["name"] for f in proj["fields"]}
    node = {"id": proj["id"],
            "fields": {"nodes": [{"id": f["id"], "name": f["name"], "dataType": f["dataType"]} for f in proj["fields"]]},
            "views": {"nodes": [{"id": v["id"], "name": v["name"], "layout": v["layout"],
                                 "fields": {"nodes": [{"id": i, "name": names[i]} for i in v["visible"]]}}
                                for v in proj["views"]]}}
    out({"data": {"repositoryOwner": {"projectV2": node}}})

m = re.fullmatch(r"repos/[^/]+/[^/]+/labels/([^/]+)", route)
if m:
    name = m.group(1)
    if method == "GET":
        if name not in state["labels"]:
            save(); sys.stderr.write("gh: Not Found (HTTP 404)\n"); sys.exit(1)
        out(state["labels"][name])
    if method == "PATCH":
        state["labels"][name].update({"color": field("color"), "description": field("description")})
        out(state["labels"][name])
if re.fullmatch(r"repos/[^/]+/[^/]+/labels", route) and method == "POST":
    state["labels"][field("name")] = {"name": field("name"), "color": field("color"), "description": field("description")}
    out(state["labels"][field("name")])

m = re.fullmatch(r"repos/[^/]+/[^/]+/issues/(\d+)", route)
if m and method == "GET" and state.get("garbage"):
    save(); print("<html>proxy error</html>"); sys.exit(0)
if m and method == "GET":
    issue = state["issues"][m.group(1)]
    out({"number": int(m.group(1)), "state": "open", "labels": [{"name": n} for n in issue["labels"]]})
m = re.fullmatch(r"repos/[^/]+/[^/]+/issues/(\d+)/labels", route)
if m and method == "POST":
    issue = state["issues"][m.group(1)]
    name = field("labels[]")
    if name not in issue["labels"]:
        issue["labels"].append(name)
    out([{"name": n} for n in issue["labels"]])
m = re.fullmatch(r"repos/[^/]+/[^/]+/issues/(\d+)/labels/([^/]+)", route)
if m and method == "DELETE" and state.get("delete_404"):
    save(); sys.stderr.write("gh: Label does not exist (HTTP 404)\n"); sys.exit(1)
if m and method == "DELETE":
    state["issues"][m.group(1)]["labels"].remove(m.group(2))
    out([])
m = re.fullmatch(r"repos/[^/]+/[^/]+/issues/(\d+)/comments", route)
if m and method == "GET":
    out([state["issues"][m.group(1)]["comments"]])
if m and method == "POST":
    state["next_id"] += 1
    c = {"id": state["next_id"], "body": field("body"), "user": {"login": "bot"}}
    state["issues"][m.group(1)]["comments"].append(c)
    out(c)
m = re.fullmatch(r"repos/[^/]+/[^/]+/issues/comments/(\d+)", route)
if m and method == "PATCH":
    for issue in state["issues"].values():
        for c in issue["comments"]:
            if c["id"] == int(m.group(1)):
                c["body"] = field("body")
                out(c)
save(); sys.stderr.write("fake gh: unexpected %r\n" % (args,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

reset_state() {  # $1 = labels JSON of issue 7, $2 = extra comments JSON
  python3 - "$1" "$2" <<'PY'
import json, os, sys
state = {
    "calls": [], "next_id": 100,
    "labels": {"needs-you": {"name": "needs-you", "color": "ededed", "description": ""}},
    "issues": {"7": {"labels": json.loads(sys.argv[1]), "comments": json.loads(sys.argv[2])}},
    "project": {"id": "PVT_1",
                "fields": [{"id": "F_T", "name": "Title", "dataType": "TITLE"},
                           {"id": "F_S", "name": "Status", "dataType": "SINGLE_SELECT"},
                           {"id": "F_L", "name": "Labels", "dataType": "LABELS"}],
                "views": [{"id": "V_B", "name": "Board", "layout": "BOARD_LAYOUT", "visible": ["F_T", "F_S"]},
                          {"id": "V_T", "name": "Backlog", "layout": "TABLE_LAYOUT", "visible": ["F_T", "F_S"]}]},
}
json.dump(state, open(os.environ["FAKE_GH_STATE"], "w"))
PY
}
q() { python3 -c "import json,os,sys; s=json.load(open(os.environ['FAKE_GH_STATE'])); print(eval(sys.argv[1]))" "$1"; }
writes() { q "len([c for c in s['calls'] if '-X' in c or any(a in ('-f','-F') for a in c) and 'graphql' not in c])"; }

ACTION="Cắm Pixel 7 thật, chạy luồng mở file DOCX và chụp màn hình kết quả"
OLD='[{"id": 5, "body": "[builder] [blocker] 🛑 blocked\nReason tag: 🧑 human\nblocked-by: -", "user": {"login": "bot"}}]'

# 1. Đánh dấu lần đầu: nhãn chuẩn hoá màu, human-gated gộp vào needs-you, một comment có marker.
reset_state '["bug", "human-gated"]' "$OLD"
python3 "$HELPER" mark --repo o/r --issue 7 --action "$ACTION" >"$TMP/out1" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "mark exits 0" || fail "mark exit $rc: $(cat "$TMP/out1")"
[ "$(q "sorted(s['issues']['7']['labels'])")" = "['bug', 'needs-you']" ] \
  && ok "needs-you added, legacy human-gated migrated away" || fail "labels: $(q "s['issues']['7']['labels']")"
[ "$(q "s['labels']['needs-you']['color']")" = "D93F0B" ] && ok "label normalised to one colour D93F0B" \
  || fail "label colour: $(q "s['labels']['needs-you']")"
BODY="$(q "[c['body'] for c in s['issues']['7']['comments'] if c['id'] > 100][0]")"
case "$BODY" in
  *"<!-- super-board:needs-you -->"*"🙋 Cần bạn: $ACTION · xong thì "*) ok "comment carries the marker and the exact action" ;;
  *) fail "comment body: $BODY" ;;
esac
case "$BODY" in
  *"Reason tag:"*|*"blocked-by:"*|*"approval-request:"*) fail "comment carries a machine line approval/deps would read: $BODY" ;;
  *) ok "comment carries no Reason tag / blocked-by / approval-request line" ;;
esac
[ "$(q "s['issues']['7']['comments'][0]['body']")" = "$(printf '[builder] [blocker] 🛑 blocked\nReason tag: 🧑 human\nblocked-by: -')" ] \
  && ok "the lane's Block comment is left untouched" || fail "Block comment was changed"

# 2. Chạy lại y hệt: không ghi gì thêm (idempotent), vẫn một comment.
python3 - <<'PY'
import json, os
p = os.environ["FAKE_GH_STATE"]; s = json.load(open(p)); s["calls"] = []; json.dump(s, open(p, "w"))
PY
python3 "$HELPER" mark --repo o/r --issue 7 --action "$ACTION" >"$TMP/out2" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(writes)" = 0 ] && ok "second identical mark writes nothing" \
  || fail "second mark rc=$rc writes=$(writes): $(q "s['calls']")"
[ "$(q "len([c for c in s['issues']['7']['comments'] if 'super-board:needs-you' in c['body']])")" = 1 ] \
  && ok "still exactly one needs-you comment" || fail "duplicate needs-you comments"

# 3. Việc khác: sửa đúng comment cũ (PATCH), không đăng comment thứ hai.
python3 "$HELPER" mark --repo o/r --issue 7 --action "Đặt secret PLAY_JSON trên repo" --next "comment done" >"$TMP/out3" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(q "len([c for c in s['issues']['7']['comments'] if 'super-board:needs-you' in c['body']])")" = 1 ] \
  && [ "$(q "[c['body'] for c in s['issues']['7']['comments'] if c['id'] > 100][0].endswith('Đặt secret PLAY_JSON trên repo · xong thì comment done')")" = True ] \
  && ok "a new action edits the same comment in place" || fail "action change: $(q "s['issues']['7']['comments']")"

# 4. Dòng máy đọc trong action/next bị từ chối (exit 64), không ghi gì.
python3 - <<'PY'
import json, os
p = os.environ["FAKE_GH_STATE"]; s = json.load(open(p)); s["calls"] = []; json.dump(s, open(p, "w"))
PY
python3 "$HELPER" mark --repo o/r --issue 7 --action "blocked-by: -" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && [ "$(writes)" = 0 ] && ok "action with a blocked-by: line is refused (64)" || fail "machine line accepted rc=$rc"
python3 "$HELPER" mark --repo o/r --issue 7 --action "ok" --next "Reason tag: 🙋" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && [ "$(writes)" = 0 ] && ok "next with a Reason tag line is refused (64)" || fail "Reason tag accepted rc=$rc writes=$(writes)"

# 5. --dry-run: đọc, in kế hoạch, không ghi.
reset_state '["human-gated"]' '[]'
python3 "$HELPER" mark --repo o/r --issue 7 --action "$ACTION" --dry-run >"$TMP/out5" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(writes)" = 0 ] && grep -q "dry-run" "$TMP/out5" && ok "dry-run reads and prints, writes nothing" \
  || fail "dry-run rc=$rc writes=$(writes): $(cat "$TMP/out5")"

# 6. unmark: gỡ nhãn, comment chuyển sang trạng thái đã xong (marker khác), mark lại thì đăng comment mới.
reset_state '["bug"]' '[]'
python3 "$HELPER" mark --repo o/r --issue 7 --action "$ACTION" >/dev/null 2>&1
python3 "$HELPER" unmark --repo o/r --issue 7 >"$TMP/out6" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(q "s['issues']['7']['labels']")" = "['bug']" ] && ok "unmark removes needs-you" || fail "unmark rc=$rc labels=$(q "s['issues']['7']['labels']")"
[ "$(q "len([c for c in s['issues']['7']['comments'] if c['body'].startswith('<!-- super-board:needs-you -->')])")" = 0 ] \
  && [ "$(q "len([c for c in s['issues']['7']['comments'] if c['body'].startswith('<!-- super-board:needs-you:done -->')])")" = 1 ] \
  && ok "unmark turns the comment into a resolved note" || fail "unmark comment: $(q "s['issues']['7']['comments']")"
python3 "$HELPER" mark --repo o/r --issue 7 --action "Chạy playtest với 5 người chơi thật" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(q "len([c for c in s['issues']['7']['comments'] if c['body'].startswith('<!-- super-board:needs-you -->')])")" = 1 ] \
  && [ "$(q "len([c for c in s['issues']['7']['comments'] if c['body'].startswith('<!-- super-board:needs-you:done -->')])")" = 1 ] \
  && ok "a new mark after unmark posts a fresh comment and keeps the resolved one" || fail "re-mark: rc=$rc $(q "s['issues']['7']['comments']")"

# 6b. gh trả exit 0 nhưng không phải JSON (trang HTML của proxy): exit 1 có thông báo, không traceback.
reset_state '["bug"]' '[]'
python3 - <<'PY'
import json, os
p = os.environ["FAKE_GH_STATE"]; s = json.load(open(p)); s["garbage"] = True; json.dump(s, open(p, "w"))
PY
python3 "$HELPER" mark --repo o/r --issue 7 --action "$ACTION" >"$TMP/out6b" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "non-JSON" "$TMP/out6b" && ! grep -q Traceback "$TMP/out6b" \
  && ok "non-JSON gh output exits 1 with a message" || fail "non-JSON rc=$rc: $(cat "$TMP/out6b")"

# 6c. Repo chưa có nhãn: GET 404 rồi POST tạo nhãn đúng màu D93F0B.
reset_state '[]' '[]'
python3 - <<'PY'
import json, os
p = os.environ["FAKE_GH_STATE"]; s = json.load(open(p)); s["labels"] = {}; json.dump(s, open(p, "w"))
PY
python3 "$HELPER" mark --repo o/r --issue 7 --action "$ACTION" >"$TMP/out6c" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(q "s['labels'].get('needs-you', {}).get('color')")" = "D93F0B" ] && [ "$(q "s['issues']['7']['labels']")" = "['needs-you']" ] \
  && ok "missing label is created with the one colour, then set" || fail "label create rc=$rc: $(cat "$TMP/out6c")"

# 6d. Nhãn human-gated đã bị gỡ giữa chừng (DELETE trả 404): vẫn exit 0.
reset_state '["human-gated"]' '[]'
python3 - <<'PY'
import json, os
p = os.environ["FAKE_GH_STATE"]; s = json.load(open(p)); s["delete_404"] = True; json.dump(s, open(p, "w"))
PY
python3 "$HELPER" mark --repo o/r --issue 7 --action "$ACTION" >"$TMP/out6d" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "a label already removed (404 on DELETE) is the wanted end state" || fail "delete 404 rc=$rc: $(cat "$TMP/out6d")"

# 6e. Comment helper viết (và ghi chú ✅ sau unmark) chạy qua đúng regex của super-board-approval.py:
#     không được là block (yêu cầu duyệt merge) và không được là câu `done`.
reset_state '[]' '[]'
python3 "$HELPER" mark --repo o/r --issue 7 --action "$ACTION" >/dev/null 2>&1
ACTIVE="$(q "[c['body'] for c in s['issues']['7']['comments']][-1]")"
python3 "$HELPER" unmark --repo o/r --issue 7 >/dev/null 2>&1
RESOLVED="$(q "[c['body'] for c in s['issues']['7']['comments']][-1]")"
R="$(python3 -B - "$ROOT/.claude/bin/super-board-approval.py" "$ACTIVE" "$RESOLVED" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("approval", sys.argv[1])
approval = importlib.util.module_from_spec(spec); spec.loader.exec_module(approval)
print(any(approval.BLOCK.search(b) or approval.DONE.match(b) for b in sys.argv[2:]))
PY
)"
[ "$R" = False ] && ok "approval.py reads neither comment as a merge request or a done" || fail "approval.py matched the needs-you comment: $R"

# 6f. super-board-deps.sh --from: mục `## Cần người` đầu body không làm hỏng `## Blocked by`; comment needs-you mới hơn
#     không thay dòng `blocked-by:` của Block comment; nhãn làm needsYou = true.
python3 - "$ACTIVE" > "$TMP/issues.json" <<'PY'
import json, sys
note = sys.argv[1]
body = "## Cần người\n🙋 Cần bạn: cắm máy thật · xong thì gỡ nhãn\n\n## Problem\nx\n\n## Acceptance Criteria\n- [ ] y\n\n## Blocked by\n- #5 — z\n"
block = "[builder] [blocker] 🛑 blocked\nReason tag: 🧑 human\nblocked-by: -"
print(json.dumps([
    {"number": 40, "title": "t", "body": body, "state": "OPEN", "labels": {"nodes": [{"name": "needs-you"}]},
     "comments": {"nodes": [{"body": block}, {"body": note}]}},
    {"number": 41, "title": "t", "body": body, "state": "OPEN", "labels": {"nodes": []},
     "comments": {"nodes": [{"body": note}]}},
    {"number": 5, "title": "dep", "body": "## Blocked by\n- None.\n", "state": "OPEN", "labels": {"nodes": []}, "comments": {"nodes": []}},
]))
PY
D="$(bash "$ROOT/.claude/bin/super-board-deps.sh" --from "$TMP/issues.json" 2>&1)"
R="$(printf '%s' "$D" | python3 -c '
import json, sys
d = json.load(sys.stdin)
a, b = d["40"], d["41"]
print(a["humanGated"], a["needsYou"], a["runnable"], b["parseable"], b["blockers"], b["humanGated"], b["needsYou"])' 2>&1)"
[ "$R" = "True True False True [5] False False" ] && ok "deps.sh: Block line still wins, body Blocked by still parses, label sets needsYou" \
  || fail "deps.sh read: $R | $D"

# 7. board: bật Labels trên mọi view rồi đọc lại; lần thứ hai được kiểm bằng số lần gọi updateProjectV2View (phải là 0).
reset_state '[]' '[]'
python3 "$HELPER" board --owner o --project 1 >"$TMP/out7" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(q "[v['visible'] for v in s['project']['views']]")" = "[['F_T', 'F_S', 'F_L'], ['F_T', 'F_S', 'F_L']]" ] \
  && ok "board shows the Labels field on every view" || fail "board rc=$rc: $(cat "$TMP/out7")"
python3 - <<'PY'
import json, os
p = os.environ["FAKE_GH_STATE"]; s = json.load(open(p)); s["calls"] = []; json.dump(s, open(p, "w"))
PY
python3 "$HELPER" board --owner o --project 1 >/dev/null 2>&1
[ "$(q "len([c for c in s['calls'] if 'updateProjectV2View' in ' '.join(c)])")" = 0 ] && ok "board is idempotent" \
  || fail "board re-ran the mutation"
reset_state '[]' '[]'
python3 - <<'PY'
import json, os
p = os.environ["FAKE_GH_STATE"]; s = json.load(open(p)); s["ignore_view_update"] = True; json.dump(s, open(p, "w"))
PY
python3 "$HELPER" board --owner o --project 1 >"$TMP/out8" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "board fails loudly when GitHub ignores the view update (re-read)" || fail "board claimed success: $(cat "$TMP/out8")"

[ "$FAILS" -eq 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
