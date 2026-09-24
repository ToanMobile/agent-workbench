#!/usr/bin/env bash
# Regression test: requirements (REQ rows) and the user's inbox (.agents/INBOX.md).
#  - `agent-kit req add "<title>" --criterion …` → a REQ row whose acceptance criteria are
#    locked by hash (changing them needs --reason, kept in history); NEEDS_TEST until EVERY
#    criterion has a test; then like a bug: NOT_RUN → UNPROVEN until RED-proof → PASS.
#    `req link <REQ> <n|all> <test>`, `req drop <REQ>`; same title + module → same row.
#  - INBOX.md belongs to the user: the prompt hook never writes a byte to it. Each new
#    `- [ ]` line is put in the context once (with @làm = do it now); `req add --inbox <key>`
#    records it; ticked lines are ignored; the view lists pending items and their REQ.
#  - a feature prompt gets the "ghi REQ trước khi code" line; the view path creates an empty
#    INBOX.md template only when there is none (the hook never does).
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"; GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
PROMPT_HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"; PROOF="$DEVKIT_DIR/scripts/red_proof.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset PROMPT_CONTEXT BUG_CAPTURE INBOX_WATCH

P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
printf 'def total(items):\n    return 0\n' > src/cart.py
cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[{"component":"Cart","watch_files":["src/*.py","tests/*.py"],
 "mandatory_regression_tests":[{"id":"REG-CART","name":"cart","command":"python3 -m unittest discover -s tests"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$P')); print(r.effective_status(d, d['items']['$1']))"; }
rid() { printf '%s' "$1" | grep -o 'REQ-[0-9]*' | head -1; }
hook() { python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": "si"}))' "$1" 2>/dev/null \
         | CLAUDE_PROJECT_DIR="$P" bash "$PROMPT_HOOK" 2>&1; }

# ── REQ rows ────────────────────────────────────────────────────────────────
out="$(bash "$KIT" req add "Tổng giỏ hàng" --module cart --criterion "giỏ rỗng → 0" --criterion "2 món 10+5 → 15" --source "thêm tính tổng giỏ hàng" 2>&1)"
R="$(rid "$out")"
[ -n "$R" ] && [ "$(st "$R")" = NEEDS_TEST ] && ok "req add → $R, NEEDS_TEST (no criterion has a test)" || fail "req add: $out"
[ -n "$R" ] && [ "$(rid "$(bash "$KIT" req add "tổng GIỎ hàng!" --module cart --criterion "giỏ rỗng → 0" --criterion "2 món 10+5 → 15" 2>&1)")" = "$R" ] \
  && ok "same title + module + criteria → same REQ" || fail "req dedupe"
bash "$KIT" req add "Tổng giỏ hàng" --module cart --criterion "chỉ 1 tiêu chí" >/dev/null 2>&1 \
  && fail "criteria changed without --reason accepted" || ok "changing locked criteria without --reason is refused"
bash "$KIT" req add "Tổng giỏ hàng" --module cart --criterion "giỏ rỗng → 0" --criterion "2 món 10+5 → 15" --criterion "số âm bị từ chối" --reason "anh bổ sung" >/dev/null 2>&1
python3 -c "import json;it=json.load(open('.agents/regression_status.json'))['items']['$R'];assert len(it['criteria'])==3 and it['criteria_changes'][0]['reason']=='anh bổ sung'" 2>/dev/null \
  && ok "--reason changes the criteria and keeps the change in history" || fail "criteria change history"
printf 'import os, sys, unittest\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))\nimport cart\nclass TestTotal(unittest.TestCase):\n    def test_empty(self):\n        self.assertEqual(cart.total([]), 0)\n    def test_two(self):\n        self.assertEqual(cart.total([10, 5]), 15)\n    def test_negative(self):\n        with self.assertRaises(ValueError):\n            cart.total([-1])\n' > tests/test_cart.py
bash "$KIT" req link "$R" 1 tests/test_cart.py >/dev/null 2>&1
[ "$(st "$R")" = NEEDS_TEST ] && ok "one of three criteria linked → still NEEDS_TEST" || fail "partial: $(st "$R")"
bash "$KIT" req link "$R" all tests/test_cart.py >/dev/null 2>&1
[ "$(st "$R")" = NOT_RUN ] && ok "every criterion linked → NOT_RUN until a real run" || fail "all linked: $(st "$R")"
printf 'def total(items):\n    if any(i < 0 for i in items):\n        raise ValueError(items)\n    return sum(items)\n' > src/cart.py
python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
[ "$(st "$R")" = UNPROVEN ] && ok "suite green → UNPROVEN until its test is seen RED without the code" || fail "after run: $(st "$R")"
python3 "$PROOF" "$P" --bug "$R" --wait >/dev/null 2>&1
[ "$(st "$R")" = PASS ] && ok "RED-proof (red without the code, green with it) → PASS" || fail "req proof: $(st "$R") $(python3 -c "import json;print(json.load(open('.agents/regression_status.json'))['items']['$R'].get('red_proof'))")"
grep -q "$R" .agents/regression_checklist.md && grep -q "3/3 tiêu chí" .agents/regression_checklist.md && ok "view shows the REQ with its criteria coverage" || fail "view REQ"
R2="$(rid "$(bash "$KIT" req add "Tạm" --criterion "x" 2>&1)")"; bash "$KIT" req drop "$R2" >/dev/null 2>&1
[ -n "$R2" ] && ! grep -q "\"$R2\"" .agents/regression_status.json && ok "req drop removes the row" || fail "drop: '$R2'"

# ── INBOX ───────────────────────────────────────────────────────────────────
rm -f .agents/INBOX.md
hook "sửa README cho rõ phần cài đặt" >/dev/null
[ ! -f .agents/INBOX.md ] && ok "the prompt hook never creates INBOX.md" || fail "hook created INBOX.md"
python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null
[ -f .agents/INBOX.md ] && ok "the view path creates an empty INBOX.md template when there is none" || fail "no template"
printf '# Hộp thư\n\n- [ ] Xuất hoá đơn PDF\n- [ ] Nút huỷ đơn @làm\n- [x] Việc đã xong\n' > .agents/INBOX.md
before="$(shasum .agents/INBOX.md)"
out="$(hook "xem giúp tình hình dự án thế nào")"
printf '%s' "$out" | grep -q "Xuất hoá đơn PDF" && printf '%s' "$out" | grep -q "Nút huỷ đơn" && ! printf '%s' "$out" | grep -q "Việc đã xong" \
  && ok "new inbox lines go into the context (ticked ones ignored)" || fail "inbox inject: $out"
printf '%s' "$out" | grep -q "@làm" && ok "@làm items are flagged to be done now" || fail "@làm: $out"
[ "$(shasum .agents/INBOX.md)" = "$before" ] && ok "INBOX.md unchanged, byte for byte" || fail "INBOX.md modified"
out="$(hook "xem giúp tình hình dự án thế nào")"
printf '%s' "$out" | grep -q "Xuất hoá đơn PDF" && fail "inbox item repeated" || { python3 -c "import json;assert len(json.load(open('.agents/regression_status.json'))['inbox'])==2" && ok "an inbox line is put in the context once (2 seen, recorded)" || fail "seen not recorded"; }
printf -- '- [ ] Đăng nhập bằng Google\n' >> .agents/INBOX.md
out="$(hook "xem giúp tình hình dự án thế nào")"
printf '%s' "$out" | grep -q "Đăng nhập bằng Google" && ! printf '%s' "$out" | grep -q "Xuất hoá đơn" && ok "only the new line on the next prompt" || fail "new line: $out"
KEY="$(python3 -c "import json;d=json.load(open('.agents/regression_status.json'));print([k for k,v in d['inbox'].items() if v['text'].startswith('Xuất')][0])")"
R3="$(rid "$(bash "$KIT" req add "Xuất hoá đơn PDF" --criterion "PDF có mã đơn" --inbox "$KEY" 2>&1)")"
python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null
grep -q "Xuất hoá đơn PDF.*$R3" .agents/regression_checklist.md && ok "view: inbox item → its REQ" || fail "inbox→REQ view"
printf -- '- [ ] Xuất Excel\n' >> .agents/INBOX.md
INBOX_WATCH=0 hook "xem giúp tình hình" | grep -q "Xuất Excel" && fail "INBOX_WATCH=0 still injected" \
  || { hook "xem giúp tình hình" | grep -q "Xuất Excel" && ok "INBOX_WATCH=0 off; back on → the item shows" || fail "item lost after INBOX_WATCH=0"; }

# ── feature prompt → REQ reminder ──────────────────────────────────────────
out="$(hook "thêm tính năng xuất báo cáo doanh thu theo tháng")"
printf '%s' "$out" | grep -q "agent-kit req add" && ok "feature prompt → 'ghi REQ trước khi code' line" || fail "feature: $out"
out="$(hook "App bị crash khi mở báo cáo")"
printf '%s' "$out" | grep -q "agent-kit req add" && fail "bug prompt got the REQ line" || ok "bug prompt does not get the REQ line"

# ── Stop: a REQ this session added whose criteria lack tests is reminded (once) ─
out="$(bash "$KIT" req add "Huỷ đơn" --criterion "đơn chưa giao huỷ được" --criterion "đơn đã giao không huỷ được" 2>&1)"; R4="$(rid "$out")"
python3 - "$P/tr.jsonl" "$P/src/cart.py" "$out" <<'PY'
import json, sys
path, src, out = sys.argv[1:4]
steps = [("Bash", {"command": 'agent-kit req add "Huỷ đơn" --criterion …'}, out, False),
         ("Bash", {"command": "python3 -m unittest discover -s tests"}, "FAILED (failures=1)", True),
         ("Edit", {"file_path": src, "old_string": "0", "new_string": "1"}, "ok", False),
         ("Bash", {"command": "python3 -m unittest discover -s tests"}, "Ran 3 tests\n\nOK", False)]
lines = []
for i, (n, inp, res, err) in enumerate(steps):
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": f"q{i}", "name": n, "input": inp}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": f"q{i}", "content": res, "is_error": err}]}}))
open(path, "w").write("\n".join(lines) + "\n")
PY
err="$(python3 -c 'import json,sys; print(json.dumps({"session_id": "sq", "transcript_path": sys.argv[1], "last_assistant_message": "Đã fix xong, test RED→GREEN."}))' "$P/tr.jsonl" \
       | CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER=0 RED_PROOF=0 bash "$DEVKIT_DIR/hooks/test_evidence_gate.sh" 2>&1 >/dev/null)"; rc=$?
[ $rc = 2 ] && printf '%s' "$err" | grep -q "req link $R4 <1|2>" && ok "Stop: a REQ of this session with untested criteria → reminder with req link" \
  || fail "req reminder: rc=$rc $err"

[ "$FAILS" -eq 0 ] && echo "✅ test_inbox_req: all passed" || { echo "❌ test_inbox_req: $FAILS failed"; exit 1; }
