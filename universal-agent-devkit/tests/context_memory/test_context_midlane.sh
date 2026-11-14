#!/usr/bin/env bash
# Test hồi quy #857: cảnh báo bối cảnh lớn GIỮA lượt cho lane headless `claude -p`.
# Lane headless chỉ gửi MỘT prompt lúc đầu, nên context_note (scripts/context/enrich_context.py) chạy ở UserPromptSubmit
# không chạy lại trong lane dù bối cảnh lên 400–500k token. Test chạy MỌI hook PostToolUse mà hooks/hooks.json đăng ký
# cho tool Bash (như Claude Code làm) trên transcript giả: một prompt đầu, usage các lượt sau tăng dần. Chỉ tính
# hookSpecificOutput.additionalContext: stdout thường của hook PostToolUse không tới model.
#  1. ngưỡng mặc định 250 000: dưới ngưỡng im; vượt ngưỡng cảnh báo đúng 1 lần mỗi bậc (250k, 500k), nhắc ghi
#     handoff ≤ 3 KB rồi kết thúc lượt.
#  2. CONTEXT_WARN_TOKENS=0: im. Lệnh của subagent (agent_id): im.
#  3. chỉ đọc 256 KB cuối transcript.
#  4. transcript không đọc được / payload hỏng: exit 0, không stdout, có log stderr (fail-open, không chặn tool).
#  5. ngân sách CPU của hook giữa lượt ≤ 150 ms (trung vị 5 lần, như prompt hook trong test_budgets.sh).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa kế GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
unset PROMPT_CONTEXT CONTEXT_WARN_TOKENS

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/lane"; mkdir -p "$P/.agents"; git -C "$P" init -q
TR="$P/tr.jsonl"

turn() {  # turn <file> <tokens>: một lượt assistant với usage = <tokens> (cache read) như transcript Claude Code
  python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"id":"m"+sys.argv[1],"role":"assistant",
  "usage":{"input_tokens":10,"cache_read_input_tokens":int(sys.argv[1]),"cache_creation_input_tokens":0,"output_tokens":5},
  "content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":"ls"}}]}}))' "$2" >> "$1"
}

post() {  # post <transcript> [json-ghi-đè-payload] [env K=V…]: chạy mọi hook PostToolUse hooks.json gắn cho Bash.
  # In mỗi additionalContext một dòng; "STDERR <dòng>" cho stderr; "RC <n> <lệnh>" khi hook thoát khác 0.
  local tr="$1" extra="${2:-}"; shift 2 2>/dev/null || shift $#
  env ${1+"$@"} python3 - "$DEVKIT_DIR" "$P" "$tr" "$extra" <<'PY'
import json, os, re, subprocess, sys
kit, proj, tr, extra = sys.argv[1:5]
payload = {"session_id": "s-lane-857", "transcript_path": tr, "cwd": proj, "hook_event_name": "PostToolUse",
           "tool_name": "Bash", "tool_input": {"command": "ls"},
           "tool_response": {"stdout": "", "stderr": "", "interrupted": False}}
payload.update(json.loads(extra or "{}"))
data = payload.pop("__raw__", None) or json.dumps(payload)
env = dict(os.environ, CLAUDE_PLUGIN_ROOT=kit, CLAUDE_PROJECT_DIR=proj)
for g in json.load(open(os.path.join(kit, "hooks", "hooks.json")))["hooks"].get("PostToolUse", []):
    m = g.get("matcher") or ""
    if m not in ("", "*") and not re.fullmatch(m, "Bash"):
        continue
    for h in g.get("hooks", []):
        r = subprocess.run(["bash", "-c", h["command"]], input=data, capture_output=True, text=True, env=env, cwd=proj,
                           timeout=60)
        if r.returncode != 0:
            print(f"RC {r.returncode} {h['command']}")
        for line in r.stdout.splitlines():
            try:
                ctx = json.loads(line)["hookSpecificOutput"]["additionalContext"]
            except (ValueError, KeyError, TypeError):
                continue
            print(" ".join(str(ctx).split()))
        for line in r.stderr.splitlines():
            print("STDERR " + line)
PY
}
warns() { printf '%s\n' "$1" | grep -v '^STDERR ' | grep -c 'Context phiên'; }

# ── 1. lane headless: một prompt đầu, bối cảnh lớn dần giữa lượt ────────────────
printf '%s\n' '{"type":"user","message":{"role":"user","content":"Bạn là lane rX: làm thẻ #1"}}' > "$TR"
turn "$TR" 20000
o0="$(printf '{"session_id":"s-lane-857","transcript_path":"%s","cwd":"%s","prompt":"Bạn là lane rX: sửa lỗi nút thanh toán bấm hai lần"}' "$TR" "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/prompt_context.sh" 2>/dev/null)"
printf '%s' "$o0" | grep -q 'Context phiên' && fail "prompt đầu của lane (20k) đã cảnh báo bối cảnh" \
  || ok "prompt đầu của lane (20k): không cảnh báo bối cảnh"
turn "$TR" 200000; o1="$(post "$TR")"                     # dưới 250k (mặc định cũ 160k sẽ cảnh báo ở đây)
turn "$TR" 260000; o2="$(post "$TR")"; o3="$(post "$TR")"  # bậc 1, rồi một tool khác cùng lượt
turn "$TR" 300000; o4="$(post "$TR")"                     # vẫn bậc 1
turn "$TR" 510000; o5="$(post "$TR")"; o6="$(post "$TR")"  # bậc 2
w="$(warns "$o1")/$(warns "$o2")/$(warns "$o3")/$(warns "$o4")/$(warns "$o5")/$(warns "$o6")"
if [ "$w" = "0/1/0/0/1/0" ]; then ok "giữa lượt: 200k im, 260k cảnh báo 1 lần, 300k im, 510k cảnh báo 1 lần (mặc định 250000)"
else fail "giữa lượt: số cảnh báo theo bước 200k/260k/260k/300k/510k/510k = $w (cần 0/1/0/0/1/0)"; fi
printf '%s' "$o2" | grep 'Context phiên' | grep -q '260' && printf '%s' "$o2" | grep 'Context phiên' | grep -q 'handoff' \
  && printf '%s' "$o2" | grep 'Context phiên' | grep -q '3 KB' && printf '%s' "$o2" | grep 'Context phiên' | grep -q 'kết thúc lượt' \
  && ok "nội dung: số token + ghi handoff ≤ 3 KB rồi kết thúc lượt" || fail "nội dung cảnh báo thiếu: $(printf '%s' "$o2" | grep -v '^STDERR' | head -3)"
rcs="$(printf '%s\n' "$o1" "$o2" "$o5" | grep -c '^RC ')"
[ "$rcs" = 0 ] && ok "mọi hook PostToolUse thoát 0" || fail "hook PostToolUse thoát khác 0: $(printf '%s\n' "$o1" "$o2" "$o5" | grep '^RC ' | head -3)"

# ── 2. tắt và subagent ──────────────────────────────────────────────────────────
TR2="$P/tr2.jsonl"; turn "$TR2" 600000
o="$(post "$TR2" '{"session_id":"s-off"}' CONTEXT_WARN_TOKENS=0)"
[ "$(warns "$o")" = 0 ] && ok "CONTEXT_WARN_TOKENS=0: im ở 600k" || fail "CONTEXT_WARN_TOKENS=0 vẫn cảnh báo"
o="$(post "$TR2" '{"session_id":"s-sub","agent_id":"a1","agent_type":"general-purpose"}')"
[ "$(warns "$o")" = 0 ] && ok "lệnh của subagent (agent_id): im" || fail "subagent nhận cảnh báo bối cảnh của phiên chính"
o="$(post "$TR2" '{"session_id":"s-env"}' CONTEXT_WARN_TOKENS=700000)"
[ "$(warns "$o")" = 0 ] && ok "CONTEXT_WARN_TOKENS=700000 ghi đè mặc định: 600k im" || fail "CONTEXT_WARN_TOKENS không ghi đè mặc định"

# ── 3. chỉ đọc 256 KB cuối ──────────────────────────────────────────────────────
TR3="$P/tr3.jsonl"; turn "$TR3" 900000
python3 -c 'import json,sys
with open(sys.argv[1], "a") as fh:
    for i in range(400):
        fh.write(json.dumps({"type":"user","message":{"role":"user","content":"x" * 1000}}) + "\n")' "$TR3"
o="$(post "$TR3" '{"session_id":"s-tail"}')"
[ "$(wc -c < "$TR3")" -gt 300000 ] && [ "$(warns "$o")" = 0 ] && ok "usage 900k nằm ngoài 256 KB cuối: không đọc tới, im" \
  || fail "đọc quá 256 KB cuối transcript ($(wc -c < "$TR3") B, cảnh báo=$(warns "$o"))"

# ── 4. lỗi đọc: không chặn tool, có log ─────────────────────────────────────────
TR4="$P/tr4.jsonl"; turn "$TR4" 600000; chmod 000 "$TR4"
o="$(post "$TR4" '{"session_id":"s-unread"}')"
[ "$(warns "$o")" = 0 ] && ! printf '%s' "$o" | grep -q '^RC ' && printf '%s' "$o" | grep '^STDERR' | grep -q 'transcript' \
  && ok "transcript không đọc được: exit 0, im, log stderr" || fail "transcript không đọc được: $(printf '%s' "$o" | head -3)"
o="$(post "$P/khong-co.jsonl" '{"session_id":"s-missing"}')"
[ "$(warns "$o")" = 0 ] && ! printf '%s' "$o" | grep -q '^RC ' && printf '%s' "$o" | grep '^STDERR' | grep -q 'transcript' \
  && ok "transcript không tồn tại: exit 0, im, log stderr" || fail "transcript không tồn tại: $(printf '%s' "$o" | head -3)"
o="$(post "$TR2" '{"__raw__":"{không phải json"}')"
[ "$(warns "$o")" = 0 ] && ! printf '%s' "$o" | grep -q '^RC ' \
  && ok "payload hỏng: exit 0, không cảnh báo" || fail "payload hỏng: $(printf '%s' "$o" | head -3)"

# ── 5. ngân sách CPU ────────────────────────────────────────────────────────────
TR5="$P/tr5.jsonl"; turn "$TR5" 100000
python3 -c 'import json,sys
with open(sys.argv[1], "a") as fh:
    for i in range(1000):
        fh.write(json.dumps({"type":"user","message":{"role":"user","content":"y" * 1000}}) + "\n")' "$TR5"
turn "$TR5" 120000
printf '{"session_id":"s-budget","transcript_path":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash"}' "$TR5" "$P" > "$TMP/budget.json"
cmd="$(python3 -c 'import json,sys
for g in json.load(open(sys.argv[1]))["hooks"].get("PostToolUse", []):
    for h in g.get("hooks", []):
        if "--midlane" in h["command"]:
            print(h["command"]); raise SystemExit' "$DEVKIT_DIR/hooks/hooks.json")"
if [ -z "$cmd" ]; then fail "ngân sách CPU: hooks.json không đăng ký hook giữa lượt"
else
  set -- $(CLAUDE_PLUGIN_ROOT="$DEVKIT_DIR" CLAUDE_PROJECT_DIR="$P" python3 - "$cmd" "$TMP/budget.json" <<'PY'
import os, resource, statistics, subprocess, sys
cpu, wall = [], []
for i in range(5):
    data = open(sys.argv[2], "rb").read()
    r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
    import time; t = time.perf_counter()
    subprocess.run(["bash", "-c", sys.argv[1]], input=data, capture_output=True)
    wall.append((time.perf_counter() - t) * 1000)
    r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu.append((r1.ru_utime + r1.ru_stime - r0.ru_utime - r0.ru_stime) * 1000)
print(int(statistics.median(cpu)), int(statistics.median(wall)))
PY
)
  [ "${1:-999}" -le 150 ] && [ "${2:-9999}" -le 750 ] && ok "hook giữa lượt (transcript 1 MB): ${1} ms CPU (≤ 150), ${2} ms wall (≤ 750)" \
    || fail "hook giữa lượt: ${1:-?} ms CPU (ngân sách 150), ${2:-?} ms wall (trần 750)"
fi

# ── 6. không ghi bytecode vào cây kit (kit link vào repo app, #813) ───────────────
# TMPDIR tương đối: prompt_context.sh không đặt PYTHONPYCACHEPREFIX; Claude Code không xuất PYTHONDONTWRITEBYTECODE ở đây.
# #1183: hook chạy từ bản sao riêng của kit (hook tìm kit theo đường dẫn thật của chính nó) và chỉ quét bản sao: quét kit thật
# thì `python3 -I` của test chạy song song (-I bỏ qua PYTHONPYCACHEPREFIX) ghi .pyc vào scripts/ làm ca này đỏ oan trên CI.
K6="$TMP/kit6"; mkdir -p "$K6"
cp -R "$DEVKIT_DIR/hooks" "$DEVKIT_DIR/scripts" "$DEVKIT_DIR/bin" "$K6/"
find "$K6" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
TR6="$P/tr6.jsonl"; turn "$TR6" 10000
printf '{"session_id":"s-pyc","transcript_path":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash"}' "$TR6" "$P" \
  | env -u PYTHONDONTWRITEBYTECODE -u PYTHONPYCACHEPREFIX TMPDIR=rel-tmp CLAUDE_PROJECT_DIR="$P" \
    bash "$K6/hooks/prompt_context.sh" --midlane >/dev/null 2>&1
new_pyc="$(find "$K6/scripts" -name '*.pyc' 2>/dev/null | head -3)"
[ -z "$new_pyc" ] && ok "không có prefix pycache: không ghi .pyc vào cây kit" || fail "hook giữa lượt ghi bytecode vào cây kit: $new_pyc"

# ── 7. transcript là thư mục: không mở, log stderr (review PR #878) ─────────────
o="$(post "$P" '{"session_id":"s-dir"}')"
[ "$(warns "$o")" = 0 ] && ! printf '%s' "$o" | grep -q '^RC ' && printf '%s' "$o" | grep '^STDERR' | grep -q 'transcript' \
  && ok "transcript là thư mục: exit 0, im, log stderr" || fail "transcript là thư mục: $(printf '%s' "$o" | head -3)"

# ── 8. json.py cài sẵn ở cwd không được nạp (review PR #878, như tests/gates/test_hook_python_isolation.sh) ──
printf 'open(%s, "w").write("x")\n' "'$TMP/shadow-loaded'" > "$P/json.py"
printf '{"session_id":"s-shadow","transcript_path":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash"}' "$TR2" "$P" \
  | ( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/prompt_context.sh" --midlane >"$TMP/shadow.out" 2>&1 )
rm -f "$P/json.py"
[ ! -e "$TMP/shadow-loaded" ] && grep -q 'Context phiên' "$TMP/shadow.out" \
  && ok "json.py ở cwd không được nạp, cảnh báo vẫn ra" || fail "hook giữa lượt nạp json.py từ cwd ($(head -c 200 "$TMP/shadow.out"))"

[ "$FAILS" -eq 0 ] && echo "✅ test_context_midlane: all passed" || { echo "❌ test_context_midlane: $FAILS failed"; exit 1; }
