#!/usr/bin/env bash
# hooks/review_gate.sh — cắt vòng review của một task cỡ PR #977 (04/11) mà không nới kiểm nào:
#  1. (rào hồi quy, luật không đổi ở đây) OCR không có endpoint: `ocr-review` sau lần sửa cuối rơi về spec delegate rồi một agent
#     review sau nó = OCR xong; không agent review sau, --delegate-only, helper sau ||, sửa thêm: vẫn chặn.
#  2. Hành động bàn giao không phải push (gh pr create, agent-kit worktree finish, agent-kit integrate, super-board-merge-gate.sh)
#     trong lượt: reply CHƯA XONG không còn bỏ qua review khi code chưa được review lúc bàn giao (trước: chỉ git push được tính).
#  3. Thông điệp chặn: P0/P1 sửa ngay trong PR; P2/P3 thành thẻ Backlog (createTask); mode delegate không cần agent thứ hai — gọi
#     `ocr-review` TRƯỚC lời gọi Agent (cùng tin nhắn được); không cắt output bằng | tail.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo x > a && git add a && git commit -qm i)
P="$(cd "$P" && pwd -P)"
echo "def f(x): return 1 / x" > "$P/app.py"

# fake ocr (như tests/gates/test_review_gate_ocr.sh): delegate chạy được, `ocr review` báo thiếu endpoint
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
case "$1 $2" in
  "review "*) echo "Error: resolve LLM endpoint: no valid LLM endpoint configured" >&2; exit 1 ;;
  "delegate preview") printf '{"schema_version":"1","reviewable_count":1,"reviewable_files":[{"path":"app.py","status":"added","insertions":1,"deletions":0}]}\n'; exit 0 ;;
  "delegate rule") printf '{"schema_version":"1","groups":[{"group_id":1,"files":["app.py"],"rule":"ZeroDivisionError"}]}\n'; exit 0 ;;
esac
exit 9
SH
chmod +x "$TMP/bin/ocr"
# spec của helper: thư mục --out riêng 0700, spec mới hơn app.py (đặt mtime, không phó cho đồng hồ)
mkdir -p "$TMP/spec"; chmod 700 "$TMP/spec"; echo "# OCR review spec" > "$TMP/spec/ocr-spec.md"
python3 -c 'import os,sys,time; os.utime(sys.argv[1],(time.time()-60,)*2); os.utime(sys.argv[2],(time.time()+5,)*2)' "$P/app.py" "$TMP/spec/ocr-spec.md"
FB="$(printf 'ocr review needs an LLM endpoint (no valid LLM endpoint configured); using OCR delegation mode (no LLM, no key)\nmode: delegate\nspec: %s\nnext: give this spec to a fresh-context reviewer (Agent tool); its findings are the OCR review' "$TMP/spec/ocr-spec.md")"

TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys, time, datetime
kind, tr, at = sys.argv[1], sys.argv[2], float(sys.argv[3]); a = sys.argv[4:]
stamp = datetime.datetime.fromtimestamp(time.time() + at, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
tu = lambda b: {"type": "assistant", "message": {"role": "assistant", "content": [dict(b, type="tool_use")]}}
if kind == "user":
    rec = {"type": "user", "message": {"role": "user", "content": a[0]}}
elif kind == "edit":
    rec = tu({"id": a[0], "name": "Write", "input": {"file_path": a[1], "content": "x"}})
elif kind == "agent":
    rec = tu({"id": a[0], "name": "Agent", "input": {"subagent_type": a[1], "prompt": "review"}})
elif kind == "bash":
    rec = tu({"id": a[0], "name": "Bash", "input": {"command": a[1]}})
else:
    rec = {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": a[0], "is_error": False, "content": a[1]}]}}
rec["timestamp"] = stamp
open(tr, "a").write(json.dumps(rec) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
stop() {   # stop <session> <env…|-> [reply]
  local sid="$1" envs="$2"; shift 2
  python3 -c 'import json,sys; d={"session_id":sys.argv[1],"transcript_path":sys.argv[2],"hook_event_name":"Stop","cwd":sys.argv[3]}
if len(sys.argv) > 4: d["last_assistant_message"] = sys.argv[4]
print(json.dumps(d))' "$sid" "$TR" "$P" "$@" \
    | env PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" ${envs/#-/} bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"
}
expect() { local want="$1" label="$2"; shift 2; stop "$@"; local rc=$?
  [ "$rc" = "$want" ] && ok "$label (rc $rc)" || fail "$label: rc $rc (want $want); log: $(tail -1 "$P/.claude/audit-gate/review_gate.log" 2>/dev/null)"; }
fresh() { : > "$TR"; python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$P/.claude/audit-gate"; }

# ── 1. OCR fallback + agent review sau nó (rào hồi quy) ──
fresh; ev edit -50 t1 "$P/app.py"; ev bash -40 t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"; ev result -39 t3 "$FB"; ev agent -30 t2 principal-code-reviewer
expect 0 "OCR fallback rồi agent review sau lần sửa cuối: OCR xong" s2 -
fresh; ev edit -50 t1 "$P/app.py"; ev bash -40 t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"; ev result -39 t3 "$FB"
expect 2 "  … OCR fallback mà KHÔNG có agent review sau lần sửa cuối: vẫn chặn" s3 -
fresh; ev agent -60 t2 principal-code-reviewer; ev edit -50 t1 "$P/app.py"; ev bash -40 t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"; ev result -39 t3 "$FB"
expect 2 "  … agent review TRƯỚC lần sửa cuối + fallback sau: vẫn chặn" s4 -
fresh; ev edit -50 t1 "$P/app.py"; ev bash -40 t3 ".agents/devkit/bin/ocr-review --delegate-only --out $TMP/spec"; ev result -39 t3 "$FB"; ev agent -30 t2 principal-code-reviewer
expect 2 "  … --delegate-only (không hỏi LLM) không phải fallback: vẫn chặn" s5 -
fresh; ev edit -50 t1 "$P/app.py"; ev bash -40 t3 "true || .agents/devkit/bin/ocr-review --out $TMP/spec"; ev result -39 t3 "$FB"; ev agent -30 t2 principal-code-reviewer
expect 2 "  … helper sau || (không chạy): vẫn chặn" s6 -
fresh; ev edit -50 t1 "$P/app.py"; ev bash -40 t3 ".agents/devkit/bin/ocr-review --out $TMP/spec"; ev result -39 t3 "$FB"; ev agent -30 t2 principal-code-reviewer; ev edit -20 t4 "$P/app.py"
expect 2 "  … sửa thêm sau cả hai: vẫn chặn" s7 -

# ── 2. bàn giao không phải push: reply CHƯA XONG không bỏ qua code chưa review ──
WIP="CHƯA XONG — đang chờ CI và review."
for c in "agent-kit worktree finish $P" "gh pr create --fill --base main" "python3 .agents/devkit/bin/agent-kit integrate" \
         "bash .claude/bin/super-board-merge-gate.sh 12 --head abc" "cd $P && .claude/bin/super-board-merge-gate.sh 12"; do
  fresh; ev user -100 "làm tiếp"; ev edit -50 t1 "$P/app.py"; ev bash -40 h1 "$c"; ev result -39 h1 "ok"
  expect 2 "edit chưa review → '$c' trong lượt, reply CHƯA XONG: chặn" "h-$RANDOM" "REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0" "$WIP"
done
fresh; ev user -100 "làm tiếp"; ev edit -60 t1 "$P/app.py"; ev agent -55 r1 principal-code-reviewer; ev bash -50 h1 "agent-kit worktree finish $P"; ev result -49 h1 ok
ev edit -40 t2 "$P/app.py"
expect 0 "  … edit → review → worktree finish → edit, reply CHƯA XONG: bỏ qua (bàn giao mang code đã review)" h-ok "REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0" "$WIP"
fresh; ev user -100 "làm tiếp"; ev edit -50 t1 "$P/app.py"; ev bash -40 h1 "echo 'gh pr create --fill'; grep -n integrate README"; ev result -39 h1 ok
expect 0 "  … chỉ nhắc tên lệnh (trong chuỗi, grep): không phải bàn giao, reply CHƯA XONG bỏ qua" h-echo "REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0" "$WIP"
fresh; ev user -100 "làm tiếp"; ev edit -50 t1 "$P/app.py"
expect 0 "  … không hành động bàn giao, reply CHƯA XONG: bỏ qua như cũ" h-none "REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0" "$WIP"
expect 2 "  … reply XONG: chặn như cũ" h-xong "REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0" "XONG"
fresh; ev user -200 "cũ"; ev bash -150 h0 "gh pr create --fill"; ev result -149 h0 ok; ev user -100 "làm tiếp"; ev edit -50 t1 "$P/app.py"
expect 0 "  … gh pr create ở lượt TRƯỚC: lượt này không bàn giao, bỏ qua" h-prev "REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0" "$WIP"

# ── 3. thông điệp chặn ──
fresh; ev edit -50 t1 "$P/app.py"
stop m1 "REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0"
grep -q 'P0/P1' "$TMP/err" && grep -q 'P2/P3' "$TMP/err" && grep -q 'Backlog' "$TMP/err" && grep -q 'createTask' "$TMP/err" \
  && ok "thông điệp chặn: P0/P1 sửa trong PR, P2/P3 thành thẻ Backlog (createTask)" || fail "thông điệp chặn thiếu P0/P1 / P2/P3 / Backlog / createTask: $(tr '\n' ' ' < "$TMP/err")"
grep -q 'delegate' "$TMP/err" && grep -q 'không cần giao spec' "$TMP/err" \
  && ok "thông điệp chặn: mode delegate không cần agent thứ hai" || fail "thông điệp chặn thiếu câu mode delegate: $(tr '\n' ' ' < "$TMP/err")"
fresh; ev edit -50 t1 "$P/app.py"; ev agent -40 t2 principal-code-reviewer
stop m2 -; rc=$?
[ "$rc" = 2 ] && grep -q 'ocr-review' "$TMP/err" && grep -q 'không cần' "$TMP/err" && grep -q 'TRƯỚC lời gọi Agent' "$TMP/err" \
  && grep -q '| tail' "$TMP/err" && grep -q 'P2/P3' "$TMP/err" && ! grep -q 'giao spec đó cho một reviewer agent SAU' "$TMP/err" \
  && ok "thông điệp thiếu OCR: OCR trước Agent trong cùng tin nhắn, không agent thứ hai, không cắt output, P2/P3 Backlog" \
  || fail "thông điệp thiếu OCR (rc $rc): $(tr '\n' ' ' < "$TMP/err")"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
