#!/usr/bin/env bash
# Test: createTask (scripts/governance/create_task.py) đánh dấu thẻ "cần người" ngay lúc tạo.
# 19/10: ~25 thẻ chỉ người làm được (máy thật, playtest, store, secret, quyết định) được tạo không có dấu gì,
# rồi bị kéo nhầm sang Ready. Bây giờ: `--needs-you "<việc>"` (hoặc AC khớp cụm "chỉ người làm được" khi không
# truyền cờ) thêm mục `## Cần người` lên đầu body và gọi .claude/bin/super-board-needs-you.py mark (nhãn + comment).
# Repo chưa có helper: vẫn gắn nhãn needs-you lúc tạo issue + cảnh báo, không crash.
# gh giả (đầu PATH) + helper giả ghi từng lệnh vào calls.jsonl để test đọc lại. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/bin" "$TMP/repo/.claude/bin"
export FAKE_LOG="$TMP/calls.jsonl"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
if a[:2] == ["issue", "create"]:
    print("https://github.com/ToanMobile/agent-workbench/issues/123"); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_1"})); sys.exit(0)
if a[:2] in (["project", "item-edit"], ["label", "create"]):
    sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cat > "$TMP/helper.py" <<'PY'
#!/usr/bin/env python3
import json, os, sys
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"helper": sys.argv[1:]}, ensure_ascii=False) + "\n")
print("needs-you o/r#123: label created · needs-you added · comment created")
sys.exit(int(os.environ.get("FAKE_HELPER_RC", "0")))
PY
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"

with_helper() { cp "$TMP/helper.py" "$TMP/repo/.claude/bin/super-board-needs-you.py"; chmod +x "$TMP/repo/.claude/bin/super-board-needs-you.py"; }
no_helper() { rm -f "$TMP/repo/.claude/bin/super-board-needs-you.py"; }
run() { : > "$FAKE_LOG"; (cd "$TMP/repo" && python3 "$CT" "$@") >"$TMP/out" 2>&1; echo $?; }
q() { python3 - "$1" <<'PY'
import json, os, sys
calls = [json.loads(l) for l in open(os.environ["FAKE_LOG"]) if l.strip()]
create = next((c["gh"] for c in calls if c.get("gh", [])[:2] == ["issue", "create"]), [])
body = create[create.index("--body") + 1] if "--body" in create else ""
labels = [create[i + 1] for i, x in enumerate(create) if x == "--label"]
helper = next((c["helper"] for c in calls if "helper" in c), None)
label_create = [c["gh"] for c in calls if c.get("gh", [])[:2] == ["label", "create"]]
print(eval(sys.argv[1]))
PY
}

ACTION="Cắm Pixel 7 thật, mở file DOCX 20 MB và chụp màn hình kết quả"
DEVICE_AC="- [ ] Mở DOCX 20 MB trên thiết bị thật không crash
- [ ] Unit test parser pass"

# 1. Cờ --needs-you: mục "## Cần người" đứng đầu body, helper được gọi đúng repo/issue/action/next.
with_helper
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "$DEVICE_AC" --needs-you "$ACTION" --needs-you-next "comment done")
[ "$rc" = 0 ] && ok "explicit --needs-you exits 0" || fail "rc=$rc: $(cat "$TMP/out")"
[ "$(A="$ACTION" q 'body.startswith("## Cần người\n🙋 Cần bạn: " + os.environ["A"] + " · xong thì comment done\n")')" = True ] \
  && ok "body opens with the ## Cần người section and the exact action" || fail "body: $(q 'body[:200]')"
[ "$(q '"## Blocked by\n- None." in body')" = True ] && ok "## Blocked by stays parseable after the new section" || fail "Blocked by section lost"
[ "$(q 'helper')" = "['mark', '--repo', 'ToanMobile/agent-workbench', '--issue', '123', '--action', '$ACTION', '--next', 'comment done']" ] \
  && ok "helper marks the new issue (label + comment)" || fail "helper call: $(q 'helper')"
[ "$(q 'labels')" = "['bug']" ] && ok "type label still auto-detected (needs-you comes from the helper)" || fail "labels: $(q 'labels')"

# 2. Không có cờ, MỌI dòng AC chỉ người làm được: phát hiện từ AC, đánh dấu với dòng AC đầu tiên.
HUMAN_AC="- [ ] Mở DOCX 20 MB trên thiết bị thật không crash
- [ ] Chạy playtest với 5 người chơi thật"
rc=$(run --title "🧪 [test] viewer: DOCX lớn trên máy thật" --problem "Chưa đo." --ac "$HUMAN_AC")
[ "$rc" = 0 ] && [ "$(q 'helper is not None and "Mở DOCX 20 MB trên thiết bị thật không crash" in helper[helper.index("--action") + 1]')" = True ] \
  && [ "$(q 'body.startswith("## Cần người\n")')" = True ] \
  && [ "$(q 'helper[helper.index("--next") + 1]')" = "dán bằng chứng vào issue rồi đóng issue" ] \
  && ok "AC that only a person can do is detected and marked (next: close the issue)" || fail "rc=$rc helper=$(q 'helper') out=$(cat "$TMP/out")"

# 2b. AC trộn (lane còn phần code + một dòng cần máy thật): KHÔNG đánh dấu (bước kế là của lane), chỉ in gợi ý.
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "$DEVICE_AC")
[ "$rc" = 0 ] && [ "$(q 'helper')" = None ] && [ "$(q '"## Cần người" in body')" = False ] && grep -q "QA/Review" "$TMP/out" \
  && ok "mixed AC (lane work first) is not marked, a hint is printed" || fail "mixed rc=$rc helper=$(q 'helper') out=$(cat "$TMP/out")"

# 3. AC chỉ nhắc tới secret theo kiểu code ("không log secret"): không đánh dấu.
rc=$(run --title "🔒 [security] log: che token" --problem "Lộ." --ac "- [ ] Không log secret hay token trong logcat
- [ ] Unit test che PII pass")
[ "$rc" = 0 ] && [ "$(q 'helper')" = None ] && [ "$(q '"## Cần người" in body')" = False ] \
  && ok "code-only AC mentioning secrets is not marked" || fail "false mark: helper=$(q 'helper') body=$(q 'body[:120]')"

# 4. --no-needs-you tắt phần phát hiện.
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "$DEVICE_AC" --no-needs-you)
[ "$rc" = 0 ] && [ "$(q 'helper')" = None ] && ok "--no-needs-you skips detection" || fail "--no-needs-you ignored: $(q 'helper')"

# 5. Repo chưa có helper: nhãn được tạo/giữ rồi gắn lúc tạo issue, có cảnh báo, exit 0.
no_helper
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "$DEVICE_AC" --needs-you "$ACTION")
[ "$rc" = 0 ] && [ "$(q '"needs-you" in labels and len(label_create) == 1')" = True ] && grep -q "super-board-needs-you.py" "$TMP/out" \
  && ok "no helper: label ensured and set at create, warning printed" || fail "fallback rc=$rc labels=$(q 'labels') out=$(cat "$TMP/out")"

# 6. --dry-run: calls.jsonl phải rỗng, bản xem trước có mục Cần người.
with_helper
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "$DEVICE_AC" --needs-you "$ACTION" --dry-run)
[ "$rc" = 0 ] && [ ! -s "$FAKE_LOG" ] && grep -q "## Cần người" "$TMP/out" && ok "dry-run calls nothing and previews the section" \
  || fail "dry-run rc=$rc log=$(cat "$FAKE_LOG")"

# 7. Helper lỗi: issue đã tạo nhưng exit 3 để người gọi biết thẻ chưa được đánh dấu.
rc=$(FAKE_HELPER_RC=1 run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "$DEVICE_AC" --needs-you "$ACTION")
[ "$rc" = 3 ] && ok "a failed mark exits 3" || fail "helper failure rc=$rc: $(cat "$TMP/out")"

# 8. Text cần người mang dòng máy đọc: từ chối (64) TRƯỚC khi tạo issue, calls.jsonl rỗng (không để lại issue thừa).
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "$DEVICE_AC" --needs-you "Cắm máy thật blocked-by: -")
[ "$rc" = 64 ] && [ ! -s "$FAKE_LOG" ] && ok "a needs-you text with a machine line is refused before the issue exists" \
  || fail "machine line rc=$rc log=$(cat "$FAKE_LOG")"

# 9. AC khớp nhưng chứa <!-- …-->: không đánh dấu tự động, có cảnh báo, issue vẫn được tạo.
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "- [ ] Mở DOCX trên thiết bị thật <!-- ghi chú -->")
[ "$rc" = 0 ] && [ "$(q 'helper')" = None ] && [ "$(q 'bool(create)')" = True ] && grep -q "\-\-needs-you" "$TMP/out" \
  && ok "an auto-detected AC line with a machine marker is skipped with a warning" || fail "auto skip rc=$rc helper=$(q 'helper') out=$(cat "$TMP/out")"

# 11. --needs-you không kèm --needs-you-next: bước sau mặc định "kéo thẻ về Ready" (có thể còn phần của lane).
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "$DEVICE_AC" --needs-you "$ACTION")
[ "$rc" = 0 ] && [ "$(q 'helper[helper.index("--next") + 1]')" = "gỡ nhãn needs-you rồi kéo thẻ về Ready" ] \
  && ok "explicit --needs-you defaults next to back-to-Ready" || fail "explicit default next: $(q 'helper')"
# 12. Thẻ tự đánh dấu mà có --needs-you-next: giá trị người gọi đưa thắng mặc định "đóng issue".
rc=$(run --title "🧪 [test] viewer: DOCX lớn trên máy thật" --problem "Chưa đo." --ac "$HUMAN_AC" --needs-you-next "comment kết quả đo")
[ "$rc" = 0 ] && [ "$(q 'helper[helper.index("--next") + 1]')" = "comment kết quả đo" ] \
  && ok "an explicit --needs-you-next wins on an auto-marked card" || fail "auto next override: $(q 'helper')"

# 13. --needs-you-next rỗng là lỗi của người gọi (64), không lặng lẽ lấy mặc định; calls.jsonl rỗng.
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "$DEVICE_AC" --needs-you "$ACTION" --needs-you-next "")
[ "$rc" = 64 ] && [ ! -s "$FAKE_LOG" ] && ok "an empty --needs-you-next is refused before anything is created" \
  || fail "empty next rc=$rc log=$(cat "$FAKE_LOG")"

# 10. Tạo nhanh từ một câu tóm tắt: một dòng không tách được phần code của lane với bước của người, nên không tự đánh dấu.
rc=$(run "fix lỗi crash trên thiết bị thật")
[ "$rc" = 0 ] && [ "$(q 'helper')" = None ] && [ "$(q '"## Cần người" in body')" = False ] && grep -q "\-\-needs-you" "$TMP/out" \
  && ok "a one-line summary is never auto-marked, a hint is printed" || fail "summary rc=$rc helper=$(q 'helper') out=$(cat "$TMP/out")"

# 14. #233: AC là văn xuôi (không gạch đầu dòng) -> từ chối (65) TRƯỚC khi tạo issue, nêu lý do.
with_helper
rc=$(run --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Crash." --ac "Không quá 2% tổng số")
[ "$rc" = 65 ] && [ ! -s "$FAKE_LOG" ] && grep -q "Acceptance Criteria" "$TMP/out" \
  && ok "prose AC is refused (65) before anything is created, reason printed" || fail "prose AC rc=$rc log=$(cat "$FAKE_LOG") out=$(cat "$TMP/out")"

# 15. #233: body nhắc repo khác trong registry (ToanMobile/GeelyEx2) khi --repo là agent-workbench -> không tạo issue, không vào Project #1.
rc=$(run --repo ToanMobile/agent-workbench --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Lỗi nằm ở ToanMobile/GeelyEx2, file app/Foo.kt." --ac "- [ ] Test pass")
[ "$rc" = 65 ] && [ ! -s "$FAKE_LOG" ] && grep -q "GeelyEx2" "$TMP/out" \
  && ok "body naming another board's repo is refused, nothing created or added to Project #1" || fail "foreign repo rc=$rc log=$(cat "$FAKE_LOG") out=$(cat "$TMP/out")"
# 15b. --no-repo-check cho phép (ticket cố ý nhắc repo khác).
rc=$(run --repo ToanMobile/agent-workbench --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Port sang ToanMobile/GeelyEx2." --ac "- [ ] Test pass" --no-repo-check)
[ "$rc" = 0 ] && [ "$(q 'bool(create)')" = True ] && ok "--no-repo-check lets a deliberate cross-repo mention through" || fail "no-repo-check rc=$rc out=$(cat "$TMP/out")"
# 15c. Tên repo của chính board không bị coi là repo khác.
rc=$(run --repo ToanMobile/agent-workbench --title "🐛 [bug] viewer: crash DOCX lớn" --problem "Xem ToanMobile/agent-workbench#12." --ac "- [ ] Test pass")
[ "$rc" = 0 ] && ok "mentioning the board's own repo is fine" || fail "own repo rc=$rc out=$(cat "$TMP/out")"

# 16. #233: AC cần dữ liệu ngoài ("prompt thật") -> thẻ có nhãn needs-you (mọi dòng AC là việc của người).
rc=$(run --title "🧪 [test] router: đo tỉ lệ đúng" --problem "Chưa đo." --ac "- [ ] Chạy ≥100 prompt thật, tỉ lệ đúng ≥ 95%")
[ "$rc" = 0 ] && [ "$(q 'helper is not None and "prompt thật" in helper[helper.index("--action") + 1]')" = True ] \
  && ok "an AC that needs real prompts marks the card needs-you" || fail "prompt thật rc=$rc helper=$(q 'helper') out=$(cat "$TMP/out")"

# 17. --check-body: cùng kiểm tra cho runner (body stdin) -> mỗi lý do một dòng, exit 65; body sạch -> exit 0, im lặng.
GOODBODY=$'## Acceptance Criteria\n- [ ] test đỏ rồi xanh\n'
out=$(printf '%s' "$GOODBODY" | python3 "$CT" --check-body --repo ToanMobile/agent-workbench 2>&1); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "--check-body: clean body exits 0 silently" || fail "check-body clean rc=$rc out=$out"
out=$(printf '%s' $'## Problem\nToanMobile/Goods-Triple-Shelf-Match-3D\n## Acceptance Criteria\nprose only\n' | python3 "$CT" --check-body --repo ToanMobile/agent-workbench 2>&1); rc=$?
[ "$rc" = 65 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ] && ok "--check-body: one reason line per problem, exit 65" || fail "check-body bad rc=$rc out=$out"

[ "$FAILS" -eq 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
