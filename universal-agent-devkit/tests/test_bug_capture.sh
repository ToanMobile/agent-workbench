#!/usr/bin/env bash
# Regression test: a new bug reaches the regression checklist by itself.
#  - `agent-kit bugs add "<title>"` → one row: OPEN (not fixed) / NEEDS_TEST (fixed, no
#    test), never PASS; deduplicated on normalized title + module; prints the BUG id.
#    `bugs link <id> <test>` resolves the test to the matrix suite that runs it (NOT_RUN
#    until a real gate run); `bugs drop <id>` removes a bug row, never a test row.
#  - a bug prompt (UserPromptSubmit, BUG_FIX) registers a REPORTED row — first line as
#    title, deduplicated against open rows — and says so in the injected context.
#    REPORTED rows are shown apart and are not counted as bugs until confirmed/linked.
#    No checklist in the project → nothing is written. "sửa README" is not a bug.
#  - Stop: a proven fix ("đã fix" + RED→GREEN) while a bug row this session touched has
#    no test linked holds the stop ONCE with the `bugs link` command, merged with the
#    lesson reminder into a single block.
#  - SessionStart counts REPORTED / OPEN / NEEDS_TEST.
#  - Agent and harness prompts are not bug reports (Grok, 2026-09-25, OfficeReader: its
#    reviewer and plan-writer sub-agent prompts became REPORTED rows): a role-play /
#    system-style opening ("You are a …", "Bạn là …"), a long instruction block, a
#    prompt carrying a tool / JSON schema register nothing — under any agent; a real bug
#    prompt is recorded whichever agent (Grok, Codex, Gemini, Cursor) ran the hook
#    (GROK_HOOK_EVENT / camelCase Grok payload / DEVKIT_AGENT). A long
#    pasted crash log (Vietnamese) and an English report quoting a JSON body still do.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
PROMPT_HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"
STOP_GATE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
SESSION_HOOK="$DEVKIT_DIR/hooks/session_context.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset PROMPT_CONTEXT BUG_CAPTURE GROK_HOOK_EVENT GROK_HOOK_NAME GROK_SESSION_ID GROK_WORKSPACE_ROOT DEVKIT_AGENT

P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo "def total(): return 1" > src/cart.py
echo "def test_total(): pass" > tests/test_cart.py
cat > .agents/regression_matrix.active.json <<'JSON'
{"rules":[{"component":"Cart","watch_files":["src/*.py","tests/*.py"],
 "mandatory_regression_tests":[{"id":"REG-CART","name":"cart","command":"python3 -m pytest tests"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
row() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$P')); it=d['items'].get(sys.argv[1])
print('MISSING' if it is None else r.effective_status(d, it)+' '+','.join(it.get('tests',[])))" "$1"; }
nbugs() { python3 -c "import json;print(len([i for i in json.load(open('$P/.agents/regression_status.json'))['items'].values() if i.get('kind')=='bug']))"; }
bug_id() { printf '%s' "$1" | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1; }

# ── bugs add ─────────────────────────────────────────────────────────────────
out="$(bash "$KIT" bugs add "Tổng giỏ hàng sai khi có mã giảm giá" --severity P1 --module cart 2>&1)"; rc=$?
B1="$(bug_id "$out")"
[ $rc = 0 ] && [ -n "$B1" ] && [ "$(row "$B1")" = "OPEN " ] && ok "bugs add: new unfixed bug → OPEN, id printed ($B1)" \
  || fail "bugs add: rc=$rc out=$out row=$(row "${B1:-x}")"
out="$(bash "$KIT" bugs add "  tổng giỏ hàng SAI khi có mã giảm giá! " --module cart 2>&1)"
[ "$(bug_id "$out")" = "$B1" ] && [ "$(nbugs)" = 1 ] && ok "bugs add: same title (case/space/punct) + module → same id, no duplicate" \
  || fail "dedupe: $out (bugs=$(nbugs))"
out="$(bash "$KIT" bugs add "Tổng giỏ hàng sai khi có mã giảm giá" --module checkout 2>&1)"
[ "$(bug_id "$out")" != "$B1" ] && [ "$(nbugs)" = 2 ] && ok "bugs add: same title, other module → its own row" || fail "module dedupe: $out"
B2="$(bug_id "$out")"
out="$(bash "$KIT" bugs add "Mất lịch sử khi xoay màn hình" --fixed 2>&1)"; B3="$(bug_id "$out")"
[ "$(row "$B3")" = "NEEDS_TEST " ] && ok "bugs add --fixed with no test → NEEDS_TEST" || fail "B3: $(row "$B3")"
out="$(bash "$KIT" bugs add "Làm tròn tiền sai" --fixed --test tests/test_cart.py 2>&1)"; B4="$(bug_id "$out")"
[ "$(row "$B4")" = "NOT_RUN REG-CART" ] && ok "bugs add --test <file> resolves to the matrix suite → NOT_RUN, never PASS" || fail "B4: $(row "$B4") $out"
bash "$KIT" bugs add "" >/dev/null 2>&1 && fail "empty title accepted" || ok "bugs add: empty title refused"

# ── bugs link / drop ─────────────────────────────────────────────────────────
bash "$KIT" bugs link "$B1" test_cart >/dev/null 2>&1
[ "$(row "$B1")" = "NOT_RUN REG-CART" ] && ok "bugs link <id> <test module name> → REG-CART, fixed, NOT_RUN" || fail "link B1: $(row "$B1")"
out="$(bash "$KIT" bugs link "$B3" NoSuchTest 2>&1)"
[ "$(row "$B3")" = "NOT_IN_MATRIX " ] && printf '%s' "$out" | grep -q "NoSuchTest" && ok "bugs link to a test the gate never runs → NOT_IN_MATRIX, said so" \
  || fail "link outside: $(row "$B3") $out"
bash "$KIT" bugs link BUG-nope REG-CART >/dev/null 2>&1 && fail "link of unknown id accepted" || ok "bugs link: unknown id → error"
bash "$KIT" bugs drop REG-CART >/dev/null 2>&1; [ "$(row REG-CART)" != MISSING ] && ok "bugs drop refuses a test row" || fail "test row dropped"
bash "$KIT" bugs drop "$B2" >/dev/null 2>&1; [ "$(row "$B2")" = MISSING ] && ok "bugs drop removes the bug row" || fail "drop: $(row "$B2")"
grep -q "$B2" .agents/regression_checklist.md && fail "dropped row still in the view" || ok "view regenerated after drop"

# ── prompt hook: REPORTED rows ───────────────────────────────────────────────
hook() { python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": sys.argv[2]}))' "$1" "$2" 2>/dev/null \
          | CLAUDE_PROJECT_DIR="${3:-$P}" bash "$PROMPT_HOOK" 2>&1; }
before="$(nbugs)"
out="$(hook "PlayerPrefs bị xóa khi chạy test
log: prefs rỗng sau EditMode" s1)"
R1="$(bug_id "$out")"
[ -n "$R1" ] && printf '%s' "$out" | grep -q "Bug đã ghi vào checklist: $R1" && [ "$(row "$R1")" = "REPORTED " ] \
  && ok "bug prompt → REPORTED row + 'Bug đã ghi vào checklist: $R1' in the context" || fail "prompt capture: $out / $(row "${R1:-x}")"
printf '%s' "$out" | grep -q "bugs link $R1" && ok "injected line carries the bugs link command" || fail "no link command: $out"
python3 -c "import json;it=json.load(open('.agents/regression_status.json'))['items']['$R1'];assert it['title']=='PlayerPrefs bị xóa khi chạy test', it['title'];assert 's1' in it.get('sessions',[])" 2>/dev/null \
  && ok "title = first line of the prompt; session recorded" || fail "title/session: $(python3 -c "import json;print(json.load(open('.agents/regression_status.json'))['items'].get('$R1'))")"
out="$(hook "PlayerPrefs bị xóa khi chạy test" s2)"
[ "$(bug_id "$out")" = "$R1" ] && [ "$(nbugs)" = $((before + 1)) ] && ok "same bug prompt again → same REPORTED row, no duplicate" || fail "prompt dedupe: $out"
out="$(hook "sửa README cho rõ phần cài đặt" s1)"
[ "$(nbugs)" = $((before + 1)) ] && ok "'sửa README' (edit, no defect) registers nothing" || fail "README prompt registered a bug"
out="$(hook "<cross-session-message from=x>
fix bug crash login</cross-session-message>" s1)"
[ "$(nbugs)" = $((before + 1)) ] && ok "a wrapped peer/system message is not a bug report" || fail "wrapped message registered"
PROMPT_CONTEXT=0 hook "App crash khi mở file PDF" s1 >/dev/null; BUG_CAPTURE=0 hook "App crash khi mở file PDF" s1 >/dev/null
[ "$(nbugs)" = $((before + 1)) ] && ok "PROMPT_CONTEXT=0 / BUG_CAPTURE=0 write nothing" || fail "escape hatch ignored"
E="$TMP/empty"; mkdir -p "$E/.agents" && ( cd "$E" && git init -q . )
hook "App crash khi mở file PDF" s1 "$E" >/dev/null
[ ! -f "$E/.agents/regression_status.json" ] && ok "no checklist/matrix in the project → nothing created" || fail "checklist created from nothing"
grep -q "Bug không có test hồi quy nào chặn tái phát: 1" .agents/regression_checklist.md \
  && ok "REPORTED is not counted as a bug without a test (gap count 1)" || fail "gap: $(grep 'Bug không' .agents/regression_checklist.md)"
grep -q "REPORTED" .agents/regression_checklist.md && grep -q "$R1" .agents/regression_checklist.md \
  && ok "view shows REPORTED rows in their own section" || fail "REPORTED not in view"
out="$(bash "$KIT" bugs add "PlayerPrefs bị xoá bởi test EditMode" --id "$R1" --module game 2>&1)"
[ "$(bug_id "$out")" = "$R1" ] && [ "$(row "$R1")" = "OPEN " ] && ok "bugs add --id <REPORTED> confirms that row (→ OPEN), no new row" || fail "confirm: $out $(row "$R1")"

# ── prompt hook: agent / harness prompts are not bug reports ─────────────────
# raw_hook <payload-json> [ENV=VAL …] — the prompt hook with a hand-made payload.
raw_hook() { p="$1"; shift; printf '%s' "$p" | env CLAUDE_PROJECT_DIR="$P" "$@" bash "$PROMPT_HOOK" 2>&1; }
payload() { python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": sys.argv[2]}))' "$1" "$2"; }
nothing() { # <name> <output> — no new bug row, no "Bug đã ghi" line
  if [ "$(nbugs)" = "$n0" ] && ! printf '%s' "$2" | grep -q "Bug đã ghi"; then ok "$1"; else fail "$1: registered ($(nbugs) vs $n0): $(printf '%s' "$2" | grep 'Bug đã ghi')"; fi; }
n0="$(nbugs)"
out="$(hook "You are a hostile code reviewer. Do NOT edit any file. Read the diff and list every bug, crash and failing test you can find." h1)"
nothing "role-play 'You are a hostile code reviewer…' (Grok reviewer sub-agent) → no row" "$out"
out="$(hook "You are the Goal Plan Writer for the xAI Grok Build harness.
Write a plan that fixes the crash in the reader and makes the failing tests pass." h1)"
nothing "'You are the Goal Plan Writer for the xAI Grok Build harness' → no row" "$out"
out="$(hook "Bạn là reviewer khó tính. Không sửa file nào, chỉ liệt kê lỗi và crash trong diff." h1)"
nothing "Vietnamese role-play 'Bạn là reviewer…' → no row" "$out"
out="$(hook 'Fix the crash in the login screen.
Tools you can call:
{"name": "read_file", "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}' h1)"
nothing "prompt carrying a tool / JSON schema → no row" "$out"
BLOCK="# Task: audit the reader module for crashes"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  BLOCK="$BLOCK
- Rule $i: you must not edit files outside the reader module; do not run gradle; never skip a failing test; always report a bug with its file and line."
done
out="$(hook "$BLOCK
## Output format
Respond only with a JSON list of findings." h1)"
nothing "long instruction block (rules, MUST/NEVER, output format) → no row" "$out"
out="$(raw_hook "$(payload "You are a hostile code reviewer. Do NOT edit any file. List every crash in the diff." h2)" GROK_HOOK_EVENT=user_prompt_submit GROK_SESSION_ID=01a0d2a9-3bf8-7711-b7d8-abda89a93260)"
nothing "Grok sub-agent prompt ('You are …') under Grok → no row" "$out"
# A user's real bug report is recorded under EVERY agent (the user, 2026-09-25: "bug thì phải tự
# động ghi nhận"). Only the prompt's content — role-play, schema, instruction block — drops it.
landed() { # <name> <output> — a new REPORTED row
  id="$(bug_id "$2")"; if [ -n "$id" ] && [ "$(row "$id")" = "REPORTED " ]; then ok "$1"; else fail "$1: not recorded: $2"; fi; }
out="$(raw_hook "$(payload "App crash khi mở file PDF có mật khẩu" h2)" GROK_HOOK_EVENT=user_prompt_submit GROK_SESSION_ID=01a0d2a9-3bf8-7711-b7d8-abda89a93260)"
landed "a real bug prompt under Grok (GROK_HOOK_EVENT) → REPORTED row" "$out"
out="$(raw_hook '{"hookEventName":"user_prompt_submit","hook_event_name":"UserPromptSubmit","sessionId":"01a0d2a9-3bf8","session_id":"01a0d2a9-3bf8","workspaceRoot":"/x","prompt":"App văng khi xoay màn hình ở trang cài đặt"}')"
landed "a real bug prompt in a Grok-shaped payload → REPORTED row" "$out"
out="$(raw_hook "$(payload "Lỗi: nút Lưu không phản hồi sau khi đổi ngôn ngữ" h2)" DEVKIT_AGENT=gemini)"
landed "a real bug prompt bridged from Gemini/Antigravity (DEVKIT_AGENT) → REPORTED row" "$out"
# A user's report that merely starts with "You are …" / "Bạn là …" is still a report: only a
# role ASSIGNMENT ("You are a/an/the <role>", "Bạn là một <vai>") is a harness prompt (review 2026-09-25).
i=0
for p in "You are right, but the app still crashes when opening a PDF" \
         "You're wrong, the login bug is still there: crash on submit" \
         "Bạn là dev Android thì xem giúp: app bị crash khi mở file PDF có mật khẩu" \
         "As an expert, fix the crash in login" \
         "Your task is to fix the crash on the login screen"; do
  i=$((i + 1)); out="$(raw_hook "$(payload "$p (case $i)" h4)")"
  landed "user report opening '${p%% *} …' → REPORTED row" "$out"
done
n0="$(nbugs)"
out="$(hook "You are a senior Android reviewer. Do not edit files; list every crash in the diff." h4)"
nothing "'You are a senior … reviewer' (role assignment) still → no row" "$out"
out="$(hook "Bạn là một reviewer khó tính. Không sửa file, chỉ liệt kê lỗi crash." h4)"
nothing "'Bạn là một reviewer …' (role assignment) still → no row" "$out"
n0="$(nbugs)"
# A task about KNOWN bugs is not a report (2026-09-25, GeelyEx2/OfficeReader/workbench: each of these
# became a REPORTED row): "bug" as a counted set or the object of a task, or inside a path / command.
i=0
for p in "có viết test cho 4 bug critical đi" "duyệt, commit merge push và link bug luôn đi" \
         "viết test cho các bug còn lại luôn đi" \
         "gửi check list báo cáo tổng số bugs và số lượng đã fix xong, chưa xong và đang đợi test" \
         "chạy /geely-fixbugs để audit, review check lấy all bug fix luôn đi" \
         "Audit, review docs/plan/telemetry-bat-5-bug.md, docs/plan/ra-xe-test-5-bug-21-09.md" \
         "gom lại hết chưa? sao còn docs/plan/telemetry-bat-5-bug.md" \
         "tôi đang hỏi chất lượng dev kit ko hỏi vấn đề của project đó bị gì 3 repo đó là tham khảo để cải thiện chất lượng dev kit thôi" \
         "đồng ý xoá 20 dòng không phải bug" \
         "đảm bảo các bugs tôi đã test trên xe ko bị lại đúng ko?"; do
  i=$((i + 1)); out="$(hook "$p" "m$i")"
  nothing "task about known bugs '${p:0:40}…' → no row" "$out"
done
# …while a report that also says "bug" still lands.
i=0
for p in "fix bug crash khi mở file PDF có mật khẩu" "bug: nút Lưu không phản hồi sau khi đổi ngôn ngữ" \
         "hiện bấm next, prev trên vô lăng vẫn chưa được, audit thêm bug" \
         "check event open file fail fix cho tôi" \
         "audit nguyên nhân hiển thị pin không đúng? bugs/img.png" \
         "đây có 1 lớp đằng sau đè bên dưới bugs/Screenshot_1789454146.png" \
         "audit bugs/bug.mp4 tính năng hé cửa nhưng khi mở cửa thì không thấy hé, hé quá chậm" \
         "app crash/văng khi mở PDF" "App crash.Fix giúp em" "login fail/timeout liên tục" \
         "fix 2 crash bugs in checkout" "layout lệch, xem 2 ảnh bugs/a.png" "layout lệch (bugs/img.png)" \
         "màn cài đặt lệch bugs/Screenshot 2026-09-25 at 10.23.45.png" \
         "log báo xe bị gì?" "app ko mở được, bị treo ở màn chờ" \
         "app bị crash khi mở PDF, không phải lỗi mạng" "Không phải lỗi mạng đâu, app bị treo ở màn chờ" \
         "màn hình đen khi vào CarPlay, ko phải bug cũ"; do
  i=$((i + 1)); out="$(raw_hook "$(payload "$p" "r$i")")"
  landed "report '${p:0:40}…' → REPORTED row" "$out"
done
n0="$(nbugs)"

# …and real reports still land, however long or however they quote JSON.
TRACE="App văng khi mở file DOCX có bảng lồng nhau
Các bước: mở app → chọn file bang-long-nhau.docx → văng ngay.
FATAL EXCEPTION: main
java.lang.IndexOutOfBoundsException: Index 3 out of bounds for length 3"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  TRACE="$TRACE
	at com.techlead.lib.office.wp.view.TableLayout.measureCell$i(TableLayout.kt:$((100 + i)))"
done
out="$(hook "$TRACE" h3)"; RV="$(bug_id "$out")"
[ -n "$RV" ] && [ "$(row "$RV")" = "REPORTED " ] && printf '%s' "$out" | grep -q "Bug đã ghi vào checklist: $RV" \
  && ok "long Vietnamese crash report with a pasted stack trace → REPORTED row" || fail "long VI report dropped: $out"
out="$(hook 'Bug: checkout crashes when the coupon is empty
Request body: {"coupon": "", "items": [1, 2]}
Response: {"error": "NullPointerException at CouponService.apply"}' h3)"; RE="$(bug_id "$out")"
[ -n "$RE" ] && [ "$(row "$RE")" = "REPORTED " ] && ok "English bug report quoting a JSON body → REPORTED row" || fail "EN report with JSON dropped: $out"
out="$(hook "Crash: the 'You are offline' banner never hides after reconnecting" h3)"; RO="$(bug_id "$out")"
[ -n "$RO" ] && ok "'You are …' quoted inside a real report (not the opening) → REPORTED row" || fail "quoted 'You are' dropped: $out"

# ── SessionStart counts ──────────────────────────────────────────────────────
R2="$(bug_id "$(hook "Nút lưu không hoạt động trên tablet" s3)")"
out="$(echo '{}' | CLAUDE_PROJECT_DIR="$P" bash "$SESSION_HOOK" 2>&1)"
printf '%s' "$out" | grep -q "REPORTED" && printf '%s' "$out" | grep -q "OPEN" && printf '%s' "$out" | grep -q "NEEDS_TEST\|NOT_IN_MATRIX" \
  && ok "SessionStart shows REPORTED / OPEN / NEEDS_TEST counts" || fail "session: $out"

# ── Stop: proven fix, touched bug row without a test → remind once ───────────
transcript() {
  python3 - "$1" "$P/src/cart.py" <<'PY'
import json, sys
out, src = sys.argv[1], sys.argv[2]
steps = [("Bash", {"command": "python3 -m pytest tests"}, "FAILED tests/test_cart.py::test_total\n1 failed", True),
         ("Edit", {"file_path": src, "old_string": "1", "new_string": "2"}, "ok", False),
         ("Bash", {"command": "python3 -m pytest tests"}, "1 passed in 0.01s", False)]
lines = []
for i, (name, inp, res, err) in enumerate(steps):
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": name, "input": inp}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": res, "is_error": err}]}}))
open(out, "w").write("\n".join(lines) + "\n")
PY
}
stop() { python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "transcript_path": sys.argv[2], "last_assistant_message": "Đã fix lỗi nút lưu, test RED→GREEN."}))' "$1" "$P/tr.jsonl" \
          | CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER="${2:-0}" bash "$STOP_GATE" 2>&1 >/dev/null; }
transcript "$P/tr.jsonl"
err="$(stop s3)"; rc=$?
[ $rc = 2 ] && printf '%s' "$err" | grep -q "bugs link $R2" && printf '%s' "$err" | grep -q "bugs drop $R2" \
  && ok "Stop: proven fix + this session's bug row unlinked → held once with bugs link / drop commands" || fail "stop remind: rc=$rc $err"
err="$(stop s3)"; rc=$?
[ $rc = 0 ] && ok "Stop: the reminder is not repeated in the same session" || fail "repeated: rc=$rc $err"
bash "$KIT" bugs link "$R1" REG-CART >/dev/null 2>&1
err="$(stop s2)"; rc=$?
[ $rc = 0 ] && ok "Stop: a session whose bug rows all have a linked test is not held" || fail "s2: rc=$rc $err"
err="$(stop s6)"; rc=$?
[ $rc = 0 ] && ok "Stop: a session that touched no bug row is not held" || fail "s6: rc=$rc $err"
hook "App bị văng khi mở tab cài đặt" s5 >/dev/null
err="$(stop s5 1)"; rc=$?
[ $rc = 2 ] && printf '%s' "$err" | grep -q "BÀI HỌC" && printf '%s' "$err" | grep -q "bugs link" \
  && ok "Stop: lesson + bug-link reminders merged into ONE block" || fail "merge: rc=$rc $err"
err="$(stop s5 1)"; rc=$?
[ $rc = 0 ] && ok "Stop: merged reminder not repeated" || fail "merged repeated: rc=$rc $err"

# A bug the session touched only through `agent-kit bugs add` in the shell (no prompt row).
out="$(bash "$KIT" bugs add "Đồng bộ bị trùng đơn" --module sync 2>&1)"; B5="$(bug_id "$out")"
python3 - "$P/tr.jsonl" "$out" <<'PY'
import json, sys
path, out = sys.argv[1], sys.argv[2]
use = {"type": "tool_use", "id": "tk", "name": "Bash", "input": {"command": 'agent-kit bugs add "Đồng bộ bị trùng đơn" --module sync'}}
res = {"type": "tool_result", "tool_use_id": "tk", "content": out, "is_error": False}
lines = [json.dumps({"message": {"content": [use]}}), json.dumps({"message": {"content": [res]}})]
old = open(path).read()
open(path, "w").write("\n".join(lines) + "\n" + old)
PY
err="$(stop s7)"; rc=$?
[ $rc = 2 ] && printf '%s' "$err" | grep -q "bugs link $B5" && ok "Stop: a bug added from the shell this session (id in the output) is reminded too" \
  || fail "shell-touched: rc=$rc $err"
transcript "$P/tr.jsonl"

# Never a PASS without a real gate run after the link: a suite that passed BEFORE the bug
# was added does not make the new bug PASS; post-fix-gate --record-lesson (just ran it) does.
python3 - "$P" "$DEVKIT_DIR" <<'PY'
import sys, pathlib
sys.path.insert(0, sys.argv[2] + "/bin"); import regression_checklist as r
p = pathlib.Path(sys.argv[1]); d = r.load(p)
r.record_results(d, [{"id": "REG-CART", "status": "PASS"}], task=None, commit=None); r.save(p, d)
PY
out="$(bash "$KIT" bugs add "Thuế tính hai lần" --fixed --test REG-CART 2>&1)"; B6="$(bug_id "$out")"
[ "$(row "$B6")" = "NOT_RUN REG-CART" ] && ok "bugs add --test after an earlier green run → NOT_RUN, not PASS" || fail "B6: $(row "$B6")"
n6="$(nbugs)"
python3 - "$P" "$DEVKIT_DIR" <<'PY'
import sys, pathlib
sys.path.insert(0, sys.argv[2] + "/bin"); import regression_checklist as r
p = pathlib.Path(sys.argv[1]); d = r.load(p)
bid = r.add_bug(d, "Thuế tính hai lần", cause=None, task="T1", test_ids=["REG-CART"])
assert bid == r.find_bug(d, "Thuế tính hai lần"), bid
r.save(p, d)
PY
[ "$(row "$B6")" = "NOT_RUN REG-CART" ] && [ "$(nbugs)" = "$n6" ] \
  && ok "--record-lesson with the same title reuses that row (no duplicate)" || fail "record-lesson dedupe: $(row "$B6")"
[ "$(python3 - "$P" "$DEVKIT_DIR" <<'PY'
import sys, pathlib
sys.path.insert(0, sys.argv[2] + "/bin"); import regression_checklist as r
d = r.load(pathlib.Path(sys.argv[1]))
r.record_results(d, [{"id": "REG-CART", "status": "PASS"}], task=None, commit=None)
bid = r.add_bug(d, "Làm tròn phí ship sai", cause=None, task="T2", test_ids=["REG-CART"])
print(r.effective_status(d, d["items"][bid]))
PY
)" = UNPROVEN ] && ok "post-fix-gate path (test just ran green, then --record-lesson) keeps the real green run (UNPROVEN until RED-proof, not NOT_RUN)" || fail "record-lesson result lost"

bash "$KIT" bugs bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown bugs action → exit 2" || fail "bad action accepted"

[ "$FAILS" -eq 0 ] && echo "✅ test_bug_capture: all passed" || { echo "❌ test_bug_capture: $FAILS failed"; exit 1; }
