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

# 8. --from-file --title có ## Risk 🔴 hoặc ## Blocked by trong file không bị gom (chưa có cờ CLI --risk/--blocked-by).
cat > "$TMP/high.md" <<'MD'
## Problem
Lỗi rủi ro cao create_task.py.

## Acceptance Criteria
- [ ] A

## Risk
🔴 High — không gom
MD
cat > "$TMP/blocked.md" <<'MD'
## Problem
Lỗi bị chặn create_task.py.

## Acceptance Criteria
- [ ] A

## Risk
🟢 Low

## Blocked by
- #99 — đang chờ
MD
rc=$(run --dry-run --from-file "$TMP/high.md" --title "$BUGTITLE")
[ "$rc" = "0" ] && ! grep -q "Sẽ gom" "$TMP/out" && ok "8a --from-file --title rủi ro 🔴 trong file không gom" || fail "8a rc=$rc: $(cat "$TMP/out")"
rc=$(run --dry-run --from-file "$TMP/blocked.md" --title "$BUGTITLE")
[ "$rc" = "0" ] && ! grep -q "Sẽ gom" "$TMP/out" && ok "8b --from-file --title có Blocked by trong file không gom" || fail "8b rc=$rc: $(cat "$TMP/out")"

# 9. #1333 review R4: cờ CLI --risk 🟢 không được che mục ## Risk 🔴 của file (body là nguồn duy nhất).
rc=$(run --dry-run --from-file "$TMP/high.md" --risk "🟢 Low" --title "$BUGTITLE")
[ "$rc" = "0" ] && ! grep -q "Sẽ gom" "$TMP/out" && ok "9 --risk CLI không che Risk 🔴 trong file" || fail "9 rc=$rc: $(cat "$TMP/out")"

# 10. R3: sổ chứa bản ghi ts sai kiểu (null, chuỗi): create_task thoát 0, ghi phiên vào sổ, file tạm có tên riêng mỗi lần.
mkdir -p "$TMP/repo/.agents/local/state"
printf '{"old":{"ts":null,"url":"x"},"old2":{"ts":"abc","url":"y"}}' > "$TMP/repo/.agents/local/state/create_task_new_card.json"
rc=$(CLAUDE_CODE_SESSION_ID=sess-r3 run --new-card "việc riêng" "${NEWARGS[@]}")
[ "$rc" = "0" ] && ! grep -q "TypeError" "$TMP/out" && ok "10a ts hỏng kiểu trong sổ không gây lỗi" || fail "10a rc=$rc: $(cat "$TMP/out")"
grep -q '"sess-r3"' "$TMP/repo/.agents/local/state/create_task_new_card.json" && ok "10b phiên được ghi vào sổ" || fail "10b sổ không có phiên"
[ -e "$TMP/repo/.agents/local/state/create_task_new_card.tmp" ] && fail "10c còn file .tmp cố định" || ok "10c không dùng tên .tmp cố định"

# 11. R1: caller tự động không mang CLAUDE_CODE_SESSION_ID xuống create_task.py.
cat > "$TMP/probe.py" <<'PY'
import importlib.util, os, subprocess, sys, types
kit = sys.argv[1]
def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, kit + "/" + rel); m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m; spec.loader.exec_module(m); return m
seen = {}
def fake_run(cmd, **kw):
    seen["env"] = kw.get("env")
    return types.SimpleNamespace(returncode=0, stdout="https://github.com/o/r/issues/5", stderr="")
inc = load("devkit_incident_t", "scripts/governance/devkit_incident.py")
subprocess.run = fake_run
try:
    inc.card_args = lambda fp, i: []
    inc.create_card("abcd", {})
except Exception:
    pass
env = seen.get("env")
print("incident", "ok" if env is not None and "CLAUDE_CODE_SESSION_ID" not in env else "leak")
gf = load("gate_full_t", "bin/gate_full.py")
inside = gf._no_session(lambda: os.environ.get("CLAUDE_CODE_SESSION_ID"))
print("gate_full", "ok" if inside is None and os.environ.get("CLAUDE_CODE_SESSION_ID") == "sess-r1" else "leak")
PY
out=$(CLAUDE_CODE_SESSION_ID=sess-r1 python3 "$TMP/probe.py" "$DEVKIT_DIR" 2>&1)
echo "$out" | grep -q "^incident ok" && ok "11a devkit_incident không truyền id phiên" || fail "11a: $out"
echo "$out" | grep -q "^gate_full ok" && ok "11b gate_full không truyền id phiên" || fail "11b: $out"

# 12. R2: clean_git_env.sh và suite_env() của post-fix-gate gỡ CLAUDE_CODE_SESSION_ID.
[ -z "$(CLAUDE_CODE_SESSION_ID=x bash -c '. "$1/tests/lib/clean_git_env.sh"; echo ${CLAUDE_CODE_SESSION_ID:-}' _ "$DEVKIT_DIR")" ] \
  && ok "12a clean_git_env.sh gỡ id phiên" || fail "12a clean_git_env.sh giữ id phiên"
grep -q '"CLAUDE_CODE_SESSION_ID",  # #1333' "$DEVKIT_DIR/bin/post-fix-gate.py" \
  && ok "12b suite_env() gỡ id phiên" || fail "12b suite_env() chưa gỡ id phiên"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
