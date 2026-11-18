#!/usr/bin/env bash
# Test: create_task.py không tạo thẻ tràn lan (#1333).
# 19/11 một phiên tạo 15 thẻ, nhiều thẻ cùng gốc: (a) --from-file --title (đường agent dùng) bỏ qua bước gom;
# (b) --new-card "<lý do bất kỳ>" không giới hạn. Bây giờ: chỉ --from-file --ticket (backlog soạn sẵn) bỏ gom;
# mỗi CLAUDE_CODE_SESSION_ID được 1 lần --new-card trong 12 giờ (sổ ở .agents/local/state/ của repo, tự git-ignore),
# lần sau exit 64 kèm gợi ý gom; không có session id thì không áp. gh giả ghi mọi lệnh vào calls.jsonl. Bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset CLAUDE_CODE_SESSION_ID

mkdir -p "$TMP/bin" "$TMP/repo"
export FAKE_LOG="$TMP/calls.jsonl" FAKE_ITEMS="$TMP/items.json"
# Một thẻ Backlog loại bug nhắc create_task.py: thẻ bug mới cùng chủ đề đủ điều kiện gom vào đây.
cat > "$TMP/items.json" <<'JSON'
{"items": [{"status": "Backlog", "labels": ["bug"], "content": {"type": "Issue", "repository": "ToanMobile/agent-workbench", "number": 7, "title": "🐛 [bug] create_task: thẻ cũ", "body": "## Problem\nx create_task.py\n\n## Acceptance Criteria\n- [ ] cũ\n\n## Risk\n🟢\n"}}]}
JSON
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
if a[:2] == ["issue", "create"]:
    print("https://github.com/ToanMobile/agent-workbench/issues/1"); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_1"})); sys.exit(0)
if a[:2] in (["project", "item-edit"], ["label", "create"]):
    sys.exit(0)
if a[:2] == ["project", "item-list"]:
    print(open(os.environ["FAKE_ITEMS"]).read()); sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"

run() { : > "$FAKE_LOG"; (cd "$TMP/repo" && python3 "$CT" "$@") >"$TMP/out" 2>&1; echo $?; }
created() { grep -c '"issue", "create"' "$FAKE_LOG" | tr -d ' '; }

cat > "$TMP/card.md" <<'MD'
## Problem
Lỗi thật FOLDCAP-MARKER create_task.py.

## Acceptance Criteria
- [ ] Test đỏ rồi xanh

## Risk
🟢 Low
MD
cat > "$TMP/backlog.md" <<'MD'
### TICKET-1: 🐛 [bug] create_task: soạn sẵn

## Problem
Ticket soạn sẵn create_task.py TICKET-MARKER.

## Risk
🟢 Low
MD
BUGTITLE="🐛 [bug] create_task: đọc file làm body"

# 1. (a) --from-file --title không --ticket: đi qua bước gom như thẻ thường → gom vào #7.
rc=$(run --dry-run --from-file "$TMP/card.md" --title "$BUGTITLE")
[ "$rc" = "0" ] && grep -q "Sẽ gom" "$TMP/out" && grep -q "#7" "$TMP/out" \
  && ok "1 --from-file --title được gom vào thẻ chưa chạy #7" || fail "1 rc=$rc: $(cat "$TMP/out")"

# 2. --from-file --ticket (backlog soạn sẵn) vẫn KHÔNG gom.
rc=$(run --dry-run --from-file "$TMP/backlog.md" --ticket 1)
[ "$rc" = "0" ] && ! grep -q "Sẽ gom" "$TMP/out" && grep -q "TICKET-MARKER" "$TMP/out" \
  && ok "2 --from-file --ticket không gom" || fail "2 rc=$rc: $(cat "$TMP/out")"

NEWARGS=(--title "🐛 [bug] create_task: việc độc lập" --problem "x create_task.py" --ac "- [ ] y")
# 3. (b) cùng session: lần --new-card đầu tạo thẻ; lần thứ hai kỳ vọng exit 64, log gh có 0 lệnh issue create (assert 3b), có gợi ý gom (3c).
export CLAUDE_CODE_SESSION_ID="sess-A"
rc=$(run --new-card "lý do 1" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(created)" = "1" ] && ok "3a lần --new-card đầu của phiên tạo thẻ" || fail "3a rc=$rc: $(cat "$TMP/out")"
rc=$(run --new-card "lý do 2" "${NEWARGS[@]}")
[ "$rc" = "64" ] && [ "$(created)" = "0" ] && ok "3b lần --new-card thứ hai cùng phiên → exit 64, không tạo" \
  || fail "3b rc=$rc create=$(created): $(cat "$TMP/out")"
grep -q "gom" "$TMP/out" && grep -q "#1" "$TMP/out" && ok "3c thông báo gợi ý gom vào thẻ đã tạo #1" || fail "3c: $(cat "$TMP/out")"
# 3d. --dry-run không ghi sổ: phiên mới chạy thử --new-card hai lần rồi tạo thật vẫn được.
export CLAUDE_CODE_SESSION_ID="sess-D"
rc1=$(run --dry-run --new-card "thử" "${NEWARGS[@]}"); rc2=$(run --dry-run --new-card "thử" "${NEWARGS[@]}")
rc=$(run --new-card "thật" "${NEWARGS[@]}")
[ "$rc1" = "0" ] && [ "$rc2" = "0" ] && [ "$rc" = "0" ] && [ "$(created)" = "1" ] && ok "3d --dry-run không tính vào hạn mức" \
  || fail "3d rc1=$rc1 rc2=$rc2 rc=$rc"

# 4. Phiên khác không bị chặn bởi sổ của sess-A.
export CLAUDE_CODE_SESSION_ID="sess-B"
rc=$(run --new-card "lý do" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(created)" = "1" ] && ok "4 phiên khác vẫn được --new-card" || fail "4 rc=$rc: $(cat "$TMP/out")"

# 5. Lần ghi sổ quá 12 giờ không tính: sửa mốc của sess-B lùi 13 giờ → lại được.
LEDGER="$TMP/repo/.agents/local/state/create_task_new_card.json"
[ -f "$LEDGER" ] && ok "5a sổ nằm ở .agents/local/state/ của repo" || fail "5a không thấy sổ $LEDGER"
python3 - "$LEDGER" <<'PY'
import json, sys, time
p = sys.argv[1]; d = json.load(open(p))
d["sess-B"]["ts"] = time.time() - 13 * 3600
json.dump(d, open(p, "w"))
PY
rc=$(run --new-card "lý do" "${NEWARGS[@]}")
[ "$rc" = "0" ] && [ "$(created)" = "1" ] && ok "5b mốc cũ hơn 12 giờ không chặn" || fail "5b rc=$rc: $(cat "$TMP/out")"

# 6. Không có session id: không áp hạn mức (script/CI gọi nhiều lần).
unset CLAUDE_CODE_SESSION_ID
rc1=$(run --new-card "a" "${NEWARGS[@]}"); rc2=$(run --new-card "b" "${NEWARGS[@]}")
[ "$rc1" = "0" ] && [ "$rc2" = "0" ] && ok "6 không session id → không chặn" || fail "6 rc1=$rc1 rc2=$rc2"

# 7. Sổ không làm bẩn cây git của repo đích.
[ -z "$(cd "$TMP/repo" && git status --porcelain)" ] && ok "7 sổ được git-ignore" \
  || fail "7 cây bẩn: $(cd "$TMP/repo" && git status --porcelain)"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
