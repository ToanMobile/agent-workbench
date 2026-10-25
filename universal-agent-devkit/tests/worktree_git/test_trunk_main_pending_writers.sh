#!/usr/bin/env bash
# Hồi quy (review 8a1b4c95, 25/10): các người ghi TỰ ĐỘNG khác của checklist ở main trunk mode và với sổ chờ
# (<git common dir>/postfix-gate/pending_rows.json, tests/worktree_git/test_trunk_main_reported_pending.sh):
#   - auto-link (hooks/test_evidence_gate.sh) và red_proof (scripts/testing/red_proof.py keep_proof) save() lại cả load_view - kể cả
#     mọi dòng chờ: main trunk mode bẩn lại, worktree kiểu nightly (DEVKIT_WORKTREE_CHECKLIST=1) đổ cả sổ vào file track của nó;
#   - Stop gate bỏ qua dòng chờ khi file track thiếu; ở worktree liên kết nó phải thấy dòng chờ của phiên;
#   - SessionStart (hooks/session_context.sh: mark_stale / auto_close_reported) và hộp thư (enrich_context.watch_inbox) vẫn ghi file
#     track của main; số đếm SessionStart không thấy dòng chờ;
#   - 52-53 dòng REPORTED đang bẩn trong main thật (bản cũ ghi thẳng): migrate-pending đưa chúng vào sổ chờ, kiểm, rồi mới trả hai
#     file về HEAD (agent-kit checklist migrate-pending; SessionStart tự chạy ở main trunk mode). Dòng người làm sổ không giữ được: từ chối.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"; PROMPT_HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"; STOP_GATE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
SESSION_HOOK="$DEVKIT_DIR/hooks/session_context.sh"; PROOF="$DEVKIT_DIR/scripts/testing/red_proof.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset PROMPT_CONTEXT BUG_CAPTURE DEVKIT_WORKTREE_CHECKLIST WORKTREE_TRUNK_MODE CLAUDE_PROJECT_DIR AUTO_LINK INBOX_WATCH STALE_RERUN
export HOME="$TMP/home" SESSION_FETCH=0 VACUITY_REVERT=0; mkdir -p "$HOME"

# mk_calc <dir> [no-status]: dự án calc (add trừ thay vì cộng), ma trận REG-CALC, checklist track (trừ khi no-status); trunk mode mặc định
mk_calc() {
  mkdir -p "$1/src" "$1/tests" "$1/.agents" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  printf 'def add(a, b):\n    return a - b\n' > src/calc.py
  cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[{"component":"Calc","watch_files":["src/*.py","tests/*.py"],
 "mandatory_regression_tests":[{"id":"REG-CALC","name":"calc","command":"python3 -m unittest discover -s tests"}]}]}
JSON
  printf '.claude/\n.agents/regression_journal/\n.agents/evidence/\n.agents/context/\ntr.jsonl\n' > .gitignore   # .agents/context/: git-ignore như installer (context_sync)
  touch tests/.gitkeep
  [ "${2:-}" = no-status ] || python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r; r.save(pathlib.Path(sys.argv[2]), {'version': 1, 'items': {}}, stale=False)" "$DEVKIT_DIR/bin" "$1"
  git add -A && git commit -qm init
}
dirty() { git -C "$1" status --porcelain --untracked-files=all -- .agents; }
prompt() {  # prompt <checkout> <phiên> <text>
  python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": sys.argv[2], "transcript_path": sys.argv[3]}))' "$3" "$2" "$TMP/tr-prompt.jsonl" \
    | CLAUDE_PROJECT_DIR="$1" bash "$PROMPT_HOOK" 2>/dev/null; }
bug_id() { printf '%s' "$1" | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1; }
view() {  # view <checkout> <id> <khoá>
  python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
v = r.load_view(pathlib.Path(sys.argv[2]))['items'].get(sys.argv[3]); print('MISSING' if v is None else v.get(sys.argv[4]))" \
    "$DEVKIT_DIR/bin" "$1" "$2" "$3" 2>/dev/null; }
tracked_ids() { python3 -c "import json, sys; print(' '.join(sorted(json.load(open(sys.argv[1] + '/.agents/regression_status.json'))['items'])))" "$1" 2>/dev/null; }
pending() { python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
print(' '.join(sorted(r.read_pending(pathlib.Path(sys.argv[2])))))" "$DEVKIT_DIR/bin" "$1" 2>/dev/null; }
transcript() {  # transcript <dir>: viết test, chạy ĐỎ có tên test, sửa src, chạy XANH (test thật sự được viết ra)
  python3 - "$1" <<'PY'
import json, sys
P = sys.argv[1]
open(f"{P}/tests/test_calc.py", "w").write(
    "import os, sys, unittest\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))\nimport calc\n"
    "class TestAdd(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(calc.add(2, 2), 4)\n")
steps = [("Write", {"file_path": f"{P}/tests/test_calc.py", "content": "x"}, "ok", False),
         ("Bash", {"command": "python3 -m unittest discover -s tests"}, "FAIL: test_add (test_calc.TestAdd.test_add)\nFAILED (failures=1)", True),
         ("Edit", {"file_path": f"{P}/src/calc.py", "old_string": "-", "new_string": "+"}, "ok", False),
         ("Bash", {"command": "python3 -m unittest discover -s tests"}, "Ran 1 test\n\nOK", False)]
lines = []
for i, (name, inp, res, err) in enumerate(steps):
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": name, "input": inp}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": res, "is_error": err}]}}))
open(f"{P}/tr.jsonl", "w").write("\n".join(lines) + "\n")
PY
}
stop() {  # stop <checkout> <phiên>: Stop của phiên tuyên bố đã fix có ĐỎ→XANH (không chạy RED-proof nền)
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "transcript_path": sys.argv[2], "last_assistant_message": "Đã fix lỗi add, test RED→GREEN."}))' "$2" "$1/tr.jsonl" \
    | CLAUDE_PROJECT_DIR="$1" LESSON_REMINDER=0 RED_PROOF=0 bash "$STOP_GATE" >/dev/null 2>&1; }

# ── 1. auto-link ở main trunk mode: vào sổ chờ, không save() cả view vào file track ─────────────────────────────────────────
P="$TMP/main"; mk_calc "$P"
B1="$(bug_id "$(prompt "$P" s1 "App bị crash khi cộng hai số")")"; B2="$(bug_id "$(prompt "$P" s2 "Màn hình kết quả bị trắng khi chia cho 0")")"
[ -n "$B1" ] && [ -n "$B2" ] && [ -z "$(dirty "$P")" ] || fail "1: dựng: B1='$B1' B2='$B2' dirty='$(dirty "$P")'"
transcript "$P"; stop "$P" s1
[ -z "$(dirty "$P")" ] && [ "$(view "$P" "$B1" linked_by)" = auto ] && [ "$(tracked_ids "$P")" = "" ] \
  && ok "1: auto-link ở main trunk mode: dòng chờ được link trong sổ chờ, file track của main không đổi (không kéo theo $B2)" \
  || fail "1: dirty='$(dirty "$P")' linked_by='$(view "$P" "$B1" linked_by)' tracked='$(tracked_ids "$P")'"

# ── 2. red_proof --pending ở main trunk mode: không ghi file track (dòng chờ N/A, dòng đã link: vào sổ chờ) ──────────────────
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
[ -z "$(dirty "$P")" ] && [ "$(tracked_ids "$P")" = "" ] && ok "2: red_proof --pending ở main trunk mode không ghi dòng chờ vào file track" \
  || fail "2: red_proof ghi main: dirty='$(dirty "$P")' tracked='$(tracked_ids "$P")'"

# ── 3. worktree kiểu nightly (DEVKIT_WORKTREE_CHECKLIST=1): red_proof không đổ sổ chờ vào file track của worktree ─────────────
#    dựng: HEAD có một bug track chưa có test (N/A của nó ghi vào file track) và một dòng chờ mới chưa có N/A (vẫn ở sổ chờ)
python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
p = pathlib.Path(sys.argv[2]); d = r.load(p)
d['items']['BUG-20260101-t'] = {'id': 'BUG-20260101-t', 'kind': 'bug', 'title': 'Track', 'component': 'calc', 'tests': [], 'state': 'confirmed', 'fixed': False, 'created_at': '2026-01-01 00:00:00', 'last': None, 'history': []}
r.save(p, d, stale=False)" "$DEVKIT_DIR/bin" "$P" && git -C "$P" add -A .agents && git -C "$P" commit -qm "tracked bug" || fail "3: dựng dòng track"
B3="$(bug_id "$(prompt "$P" s3 "Ô nhập bị crash khi dán chữ dài")")"
W="$TMP/main-wt"; git -C "$P" worktree add -q --detach "$W" >/dev/null 2>&1 || fail "3: worktree add"
DEVKIT_WORKTREE_CHECKLIST=1 python3 "$PROOF" "$W" --pending --wait >/dev/null 2>&1
na3="$(python3 -c "import json, sys; print((json.load(open(sys.argv[1] + '/.agents/regression_status.json'))['items']['BUG-20260101-t'].get('red_proof') or {}).get('status'))" "$W" 2>/dev/null)"
[ -n "$B3" ] && [ "$(tracked_ids "$W")" = "BUG-20260101-t" ] && [ "$na3" = N/A ] && [ "$(view "$W" "$B3" state)" = reported ] \
  && ok "3: red_proof ở worktree ghi checklist (DEVKIT_WORKTREE_CHECKLIST=1): dòng track nhận N/A, không dòng chờ nào vào file track của nó" \
  || fail "3: B3='$B3' file track của worktree có: '$(tracked_ids "$W")' N/A='$na3' B3 view='$(view "$W" "${B3:-x}" state)'"

# ── 4. Stop gate với dòng chờ: worktree liên kết thấy dòng của phiên (auto-link vào trạng thái riêng của worktree) ──────────────
B4="$(bug_id "$(prompt "$P" s4 "Nút chia bị crash khi số âm")")"
W4="$TMP/main-wt4"; git -C "$P" worktree add -q --detach "$W4" >/dev/null 2>&1 || fail "4: worktree add"
t4="$(tracked_ids "$W4")"; transcript "$W4"; stop "$W4" s4
[ "$(view "$W4" "$B4" linked_by)" = auto ] && [ "$(tracked_ids "$W4")" = "$t4" ] && [ -z "$(dirty "$P")" ] \
  && ok "4: Stop ở worktree liên kết thấy dòng chờ của phiên: auto-link giữ ở trạng thái của worktree, file track không đổi, main sạch" \
  || fail "4: linked_by='$(view "$W4" "$B4" linked_by)' tracked='$(tracked_ids "$W4")' main='$(dirty "$P")'"

# ── 5. Stop gate khi file track CHƯA có (dự án chỉ có ma trận): vẫn thấy dòng chờ ──────────────────────────────────────────
N="$TMP/nostatus"; mk_calc "$N" no-status
B5="$(bug_id "$(prompt "$N" s5 "App bị crash khi cộng hai số")")"
transcript "$N"; stop "$N" s5
[ -n "$B5" ] && [ "$(view "$N" "$B5" linked_by)" = auto ] && [ ! -e "$N/.agents/regression_status.json" ] \
  && ok "5: file track chưa có: Stop vẫn thấy dòng chờ của phiên và link nó (trong sổ chờ, không tạo file track)" \
  || fail "5: id='$B5' linked_by='$(view "$N" "${B5:-x}" linked_by)' status file=$([ -e "$N/.agents/regression_status.json" ] && echo có || echo không)"

# ── 6. SessionStart ở main trunk mode: không ghi file track (auto_close), số đếm có dòng chờ ─────────────────────────────────
S="$TMP/session"; mk_calc "$S"
python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
p = pathlib.Path(sys.argv[2]); d = r.load(p)
d['items']['BUG-20260101-old'] = {'id': 'BUG-20260101-old', 'kind': 'bug', 'title': 'Cũ', 'component': '-', 'tests': [], 'state': 'reported',
  'created_at': '2026-01-01 00:00:00', 'touched_at': '2026-01-01 00:00:00', 'last': None, 'history': []}
r.save(p, d, stale=False)" "$DEVKIT_DIR/bin" "$S" && git -C "$S" add -A .agents && git -C "$S" commit -qm "old reported row" || fail "6: dựng"
prompt "$S" s6 "App bị crash khi cộng hai số" >/dev/null; prompt "$S" s6 "Màn hình kết quả bị trắng khi chia cho 0" >/dev/null
out6="$(echo '{}' | CLAUDE_PROJECT_DIR="$S" bash "$SESSION_HOOK" 2>&1)"
[ -z "$(dirty "$S")" ] && ok "6: SessionStart ở main trunk mode không ghi file track (auto_close của dòng cũ không làm main bẩn)" \
  || fail "6: SessionStart ghi main: $(dirty "$S" | tr '\n' ' ')"
printf '%s' "$out6" | grep -q "2 REPORTED" && ok "6b: số đếm SessionStart có các dòng REPORTED đang chờ (2)" || fail "6b: không thấy '2 REPORTED': $(printf '%s' "$out6" | grep -o '[0-9]* REPORTED' | head -1)"

# ── 7. hộp thư ở main trunk mode: liệt kê mục mới một lần, khoá "đã thấy" vào sổ chờ, main sạch ────────────────────────────
I="$TMP/inbox"; mk_calc "$I"
printf '# Hộp thư\n\n- [ ] Xuất hoá đơn PDF\n' > "$I/.agents/INBOX.md" && git -C "$I" add -A .agents && git -C "$I" commit -qm inbox
o1="$(prompt "$I" s7 "xem giúp tình hình dự án thế nào")"; o2="$(prompt "$I" s7b "xem giúp tình hình dự án thế nào")"   # phiên khác: không phải dedupe_session giấu nó
printf '%s' "$o1" | grep -q "Xuất hoá đơn PDF" && ! printf '%s' "$o2" | grep -q "Xuất hoá đơn PDF" && [ -z "$(dirty "$I")" ] \
  && ok "7: hộp thư ở main trunk mode: mục mới nêu một lần, lần sau không lặp, main sạch" \
  || fail "7: lần 1 nêu=$(printf '%s' "$o1" | grep -c 'Xuất hoá đơn') lần 2 nêu=$(printf '%s' "$o2" | grep -c 'Xuất hoá đơn') dirty='$(dirty "$I")'"

# ── 8. migrate-pending: main đang bẩn vì bản cũ ghi thẳng dòng REPORTED: chuyển vào sổ chờ, kiểm, rồi trả hai file về HEAD ────
old_hook() {  # old_hook <dir>: như prompt hook bản cũ: thêm 2 dòng REPORTED, mở lại dòng 💤 HEAD có, một khoá hộp thư, đếm reported_total
  python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
p = pathlib.Path(sys.argv[2]); d = r.load(p)
for t in ('Lỗi một khi lưu', 'Lỗi hai khi mở'):
    r.register_bug(d, t, state='reported', session='s0', open_only=True)
it = d['items']['BUG-20260101-z']; it.update({'state': 'reported', 'fixed': None}); r.touch_session(it, 's0')
d.setdefault('inbox', {})['k1'] = {'text': 'Mục', 'seen_at': '2026-10-24 10:00:00', 'req': None}
r.save(p, d, stale=False)" "$DEVKIT_DIR/bin" "$1"; }
mk_old() {  # mk_old <dir>: HEAD có một bug đã xác nhận (link REG-CALC) và một dòng 💤
  mk_calc "$1"
  python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
p = pathlib.Path(sys.argv[2]); d = r.load(p)
d['items']['BUG-20260101-c'] = {'id': 'BUG-20260101-c', 'kind': 'bug', 'title': 'Đã xác nhận', 'component': 'calc', 'tests': ['REG-CALC'], 'state': 'confirmed', 'fixed': True, 'created_at': '2026-01-01 00:00:00', 'last': None, 'history': []}
d['items']['BUG-20260101-z'] = {'id': 'BUG-20260101-z', 'kind': 'bug', 'title': 'Ngủ', 'component': '-', 'tests': [], 'state': 'auto_closed', 'created_at': '2026-01-01 00:00:00', 'touched_at': '2026-01-01 00:00:00', 'last': None, 'history': []}
r.save(p, d, stale=False)" "$DEVKIT_DIR/bin" "$1" && git -C "$1" add -A .agents && git -C "$1" commit -qm "rows" || fail "8: dựng $1"
}
M="$TMP/migrate"; mk_old "$M"; old_hook "$M"
before8="$(python3 -c "import json, sys; d = json.load(open(sys.argv[1] + '/.agents/regression_status.json')); print(' '.join(sorted(k for k, v in d['items'].items() if v.get('state') == 'reported')))" "$M")"
[ -n "$(dirty "$M")" ] || fail "8: dựng: main phải bẩn như bản cũ để lại"
( cd "$M" && bash "$KIT" checklist migrate-pending >/dev/null 2>&1 ); rc8=$?
after8="$(python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
d = r.load_view(pathlib.Path(sys.argv[2])); print(' '.join(sorted(k for k, v in d['items'].items() if v.get('state') == 'reported')))" "$DEVKIT_DIR/bin" "$M" 2>/dev/null)"
inbox8="$(python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
print(' '.join(sorted(r.load_view(pathlib.Path(sys.argv[2])).get('inbox', {}))))" "$DEVKIT_DIR/bin" "$M" 2>/dev/null)"
[ "$rc8" = 0 ] && [ -z "$(dirty "$M")" ] && [ -n "$before8" ] && [ "$after8" = "$before8" ] && [ "$inbox8" = k1 ] \
  && ok "8: migrate-pending: 3 dòng REPORTED (2 mới + 1 mở lại) và khoá hộp thư vào sổ chờ, view y như trước, main về HEAD (sạch)" \
  || fail "8: rc=$rc8 dirty='$(dirty "$M")' trước='$before8' sau='$after8' inbox='$inbox8'"
( cd "$M" && bash "$KIT" checklist check >/dev/null 2>&1 ) && ok "8b: sau migrate không có cảnh báo rollback checklist" || fail "8b: checklist check báo rollback sau migrate"

# 8c. dòng người làm mà sổ chờ không giữ được (bug đã xác nhận ở HEAD bị sửa link ở main): từ chối, không đụng file, không mất gì
M2="$TMP/migrate-refuse"; mk_old "$M2"; old_hook "$M2"
python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
p = pathlib.Path(sys.argv[2]); d = r.load(p); d['items']['BUG-20260101-c']['tests'].append('REG-OTHER'); r.save(p, d, stale=False)" "$DEVKIT_DIR/bin" "$M2"
sum_before="$(shasum < "$M2/.agents/regression_status.json")"
out8c="$( cd "$M2" && bash "$KIT" checklist migrate-pending 2>&1 )"; rc8c=$?
[ "$rc8c" != 0 ] && printf '%s' "$out8c" | grep -q "BUG-20260101-c" && [ "$(shasum < "$M2/.agents/regression_status.json")" = "$sum_before" ] && [ -z "$(pending "$M2")" ] \
  && ok "8c: migrate-pending từ chối khi một dòng người làm không giữ được ở sổ chờ (nêu tên), file và sổ không đổi" \
  || fail "8c: rc=$rc8c out='$out8c' pending='$(pending "$M2")'"

# 8e. một RED-proof thật (PROVEN) chỉ có ở file đang bẩn trên dòng đã xác nhận: không bỏ im lặng, từ chối
M4="$TMP/migrate-proof"; mk_old "$M4"; old_hook "$M4"
python3 -c "import sys, time, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
p = pathlib.Path(sys.argv[2]); d = r.load(p); d['items']['BUG-20260101-c']['red_proof'] = {'status': 'PROVEN', 'ts': time.time()}; r.save(p, d, stale=False)" "$DEVKIT_DIR/bin" "$M4"
out8e="$( cd "$M4" && bash "$KIT" checklist migrate-pending 2>&1 )"; rc8e=$?
[ "$rc8e" != 0 ] && printf '%s' "$out8e" | grep -q "BUG-20260101-c" && [ -n "$(dirty "$M4")" ] \
  && ok "8e: migrate-pending từ chối khi file bẩn giữ một RED-proof thật mà sổ chờ không giữ được, main để nguyên" || fail "8e: rc=$rc8e out='$out8e'"

# 8f. finish / automerge đang giữ khoá gộp của main (devkit-automerge-main.lock): migrate không chen vào giữa, để nguyên, bảo chạy lại
M5="$TMP/migrate-locked"; mk_old "$M5"; old_hook "$M5"
LOCKF="$(git -C "$M5" rev-parse --absolute-git-dir)/devkit-automerge-main.lock"
python3 -c "import fcntl, sys, time; fh = open(sys.argv[1], 'a'); fcntl.flock(fh, fcntl.LOCK_EX); open(sys.argv[2], 'w').close(); time.sleep(8)" "$LOCKF" "$TMP/locked.flag" &
LPID=$!; i=0; while [ ! -e "$TMP/locked.flag" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
sum5="$(shasum < "$M5/.agents/regression_status.json")"
out8f="$( cd "$M5" && DEVKIT_MIGRATE_LOCK_WAIT_S=1 bash "$KIT" checklist migrate-pending 2>&1 )"; rc8f=$?
kill "$LPID" 2>/dev/null; wait "$LPID" 2>/dev/null
[ "$rc8f" != 0 ] && printf '%s' "$out8f" | grep -q "đang được gộp" && [ "$(shasum < "$M5/.agents/regression_status.json")" = "$sum5" ] && [ -z "$(pending "$M5")" ] \
  && ok "8f: khoá gộp của main đang bị giữ: migrate-pending không đọc HEAD / ghi file, bảo chạy lại" || fail "8f: rc=$rc8f out='$out8f'"

# 8d. SessionStart ở main trunk mode tự chạy migrate
M3="$TMP/migrate-session"; mk_old "$M3"; old_hook "$M3"
out8d="$(echo '{}' | CLAUDE_PROJECT_DIR="$M3" bash "$SESSION_HOOK" 2>&1)"
[ -z "$(dirty "$M3")" ] && [ "$(view "$M3" BUG-20260101-z state)" = reported ] && printf '%s' "$out8d" | grep -q "sổ chờ" \
  && ok "8d: SessionStart ở main trunk mode tự chuyển dòng chưa commit vào sổ chờ và trả main về HEAD" \
  || fail "8d: dirty='$(dirty "$M3")' z='$(view "$M3" BUG-20260101-z state)' out='$(printf '%s' "$out8d" | grep -i 'checklist' | head -2)'"

echo
[ "$FAILS" = 0 ] && { echo "test_trunk_main_pending_writers: PASS"; exit 0; }
echo "test_trunk_main_pending_writers: $FAILS FAIL"; exit 1
