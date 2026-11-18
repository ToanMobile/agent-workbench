#!/usr/bin/env bash
# #1301: review_gate giữ Stop sau MỌI lần sửa → head PR không đứng yên (12 vòng, 9 head ở #1298/PR #1299).
# Trần: sau 2 vòng review sạch (chỉ P2/P3) hook thả Stop kèm một dòng handoff; vòng đầu, P0/P1, file nhạy cảm vẫn giữ.
#  C1. sửa, 2 vòng review sạch, sửa tiếp, chưa review lại → thả (rc 0) + dòng handoff "lane QA / merge gate".
#  C2. vòng 2 còn P1 → vẫn giữ (rc 2).
#  C3. chưa có vòng review nào → giữ (rc 2).
#  C4. file chạm auth (auth.py) sau 2 vòng sạch → vẫn giữ (rc 2).
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i)
echo "def f(x): return 1 / x" > "$P/app.py"
mkdir -p "$TMP/bin"   # không có `ocr`: chỉ review agent
TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys
kind, tr = sys.argv[1], sys.argv[2]
a = sys.argv[3:]
wr = lambda o: open(tr, "a").write(json.dumps(o) + "\n")
tu = lambda b: {"type": "assistant", "message": {"role": "assistant", "content": [dict(b, type="tool_use")]}}
if kind == "edit":
    wr(tu({"id": a[0], "name": "Write", "input": {"file_path": a[1], "content": "x"}}))
else:  # review <id> <text> [error]
    wr(tu({"id": a[0], "name": "Agent", "input": {"subagent_type": "principal-code-reviewer", "prompt": "review"}}))
    res = {"type": "tool_result", "tool_use_id": a[0], "content": a[1]}
    if len(a) > 2:
        res["is_error"] = True
    wr({"type": "user", "message": {"role": "user", "content": [res]}})
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
stop() { printf '{"session_id":"s-%s","transcript_path":"%s","hook_event_name":"Stop"}' "$1" "$TR" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" REVIEW_GATE_MAX_ATTEMPTS=9 bash "$DEVKIT_DIR/hooks/review_gate.sh" >"$TMP/out" 2>"$TMP/err"; }
CLEAN="Findings: P2 đặt tên biến; P3 comment. Không có P0/P1."

: > "$TR"; ev edit e1 "$P/app.py"; ev review r1 "$CLEAN"; ev edit e2 "$P/app.py"; ev review r2 "$CLEAN"; ev edit e3 "$P/app.py"
stop c1; rc=$?
if [ "$rc" = 0 ] && grep -q 'lane QA / merge gate' "$TMP/err"; then ok "C1. 2 vòng sạch rồi sửa tiếp: thả + handoff"
else fail "C1. rc $rc: $(head -3 "$TMP/err" | tr '\n' '|')"; fi

: > "$TR"; ev edit e1 "$P/app.py"; ev review r1 "$CLEAN"; ev edit e2 "$P/app.py"; ev review r2 "P1: chia cho 0 khi x=0 (app.py:1)"; ev edit e3 "$P/app.py"
stop c2; rc=$?
[ "$rc" = 2 ] && ok "C2. còn P1: vẫn giữ" || fail "C2. rc $rc"

: > "$TR"; ev edit e1 "$P/app.py"
stop c3; rc=$?
[ "$rc" = 2 ] && ok "C3. chưa review: vẫn giữ" || fail "C3. rc $rc"

: > "$TR"; echo "def g(x): return x" > "$P/auth.py"; ev edit e1 "$P/auth.py"; ev review r1 "$CLEAN"; ev edit e2 "$P/auth.py"; ev review r2 "$CLEAN"; ev edit e3 "$P/auth.py"
stop c4; rc=$?
[ "$rc" = 2 ] && ok "C4. file auth: vẫn giữ" || fail "C4. rc $rc"

rm -f "$P/auth.py"   # C4 để lại file nhạy cảm: không để nó che kết quả của C5/C6
# C5. dòng P0/P1 thật có chữ "không"/"no"/"clean" trong mô tả lỗi vẫn là P0/P1 (reviewer bounce 18/11).
n=0
for sev in "P1: không kiểm tra x=0 (app.py:1)" "P0: no auth check on endpoint" "P1: SQL injection, input not clean" "P1: no P0 handling for empty input (a.py:3)" "P1: thiếu kiểm tra, không có P0 nào khác" "P0: auth bypass; không P1" "P1: x=0 P0 path"; do
  n=$((n + 1))
  : > "$TR"; ev edit e1 "$P/app.py"; ev review r1 "$CLEAN"; ev edit e2 "$P/app.py"; ev review r2 "$sev"; ev edit e3 "$P/app.py"
  stop c5$n; rc=$?
  [ "$rc" = 2 ] && ok "C5.$n. '$sev' vẫn giữ" || fail "C5.$n. rc $rc cho '$sev'"
done

# C6. phủ định đúng nhãn vẫn tính là sạch.
for neg in "Không có P0/P1." "No P0 or P1 found." "0 P1, 0 P0"; do
  : > "$TR"; ev edit e1 "$P/app.py"; ev review r1 "$neg"; ev edit e2 "$P/app.py"; ev review r2 "$neg"; ev edit e3 "$P/app.py"
  stop "c6$((n += 1))"; rc=$?
  [ "$rc" = 0 ] && ok "C6. '$neg' tính là sạch" || fail "C6. rc $rc cho '$neg'"
done

# C7. review lỗi / rỗng / chạy nền không phải vòng sạch: hai kết quả hỏng không thả Stop (R3, reviewer bounce 18/11).
: > "$TR"; ev edit e1 "$P/app.py"; ev review r1 "429 rate limit" err; ev edit e2 "$P/app.py"; ev review r2 "429 rate limit" err; ev edit e3 "$P/app.py"
stop c71; rc=$?; [ "$rc" = 2 ] && ok "C7.1 hai review is_error: vẫn giữ" || fail "C7.1 rc $rc"
: > "$TR"; ev edit e1 "$P/app.py"; ev review r1 ""; ev edit e2 "$P/app.py"; ev review r2 "  "; ev edit e3 "$P/app.py"
stop c72; rc=$?; [ "$rc" = 2 ] && ok "C7.2 hai review rỗng: vẫn giữ" || fail "C7.2 rc $rc"
: > "$TR"; ev edit e1 "$P/app.py"; ev review r1 "Async agent launched successfully. agentId: a1"; ev edit e2 "$P/app.py"; ev review r2 "Async agent launched successfully. agentId: a2"; ev edit e3 "$P/app.py"
stop c73; rc=$?; [ "$rc" = 2 ] && ok "C7.3 hai review chạy nền: vẫn giữ" || fail "C7.3 rc $rc"
: > "$TR"; ev edit e1 "$P/app.py"; ev review r1 "$CLEAN"; ev edit e2 "$P/app.py"; ev review r2 "boom" err; ev edit e3 "$P/app.py"
stop c74; rc=$?; [ "$rc" = 2 ] && ok "C7.4 1 sạch + 1 lỗi: chưa đủ 2 vòng, giữ" || fail "C7.4 rc $rc"

[ "$FAILS" = 0 ] && { echo "test_review_gate_round_cap: PASS"; exit 0; }
echo "test_review_gate_round_cap: FAIL ($FAILS)"; exit 1
