#!/usr/bin/env bash
# Test hồi quy #722 (30/10 21:35 và 23:17, phiên điều phối 3d8ac3bb): gate exit 0 trong worktree, PR squash vào main, main = squash,
# kho chung có biên nhận --full exit 0 TRONG LƯỢT cho đúng fp của commit HEAD. Vậy mà proof_gate vẫn giữ Stop, và lời khuyên "chạy
# post-fix-gate" thì session_lock (trunk mode) cấm ở main. Gốc: main có file untracked của người khác từ trước phiên, và một subagent
# của phiên từng chạy `grep … <file đó>` (chỉ đọc); untouched_by_session coi mọi lệnh shell nhắc tên là "đã đụng" trên cả phiên, nên
# cửa tree-store (2) / merge-receipt / merged-evidence đều đóng. Sửa: ở main trunk mode, file THƯỜNG của chính main (không qua checkout
# con), cùng thiết bị, có ctime + mtime trước lúc phiên bắt đầu (kernel đặt ctime khi ghi / đổi tên / link / touch -t) thì lời nhắc tên
# trong shell không làm nó thành của phiên; công cụ sửa file vẫn tính như cũ. Lời khuyên ở main trunk mode: gate `--tree HEAD` trong một
# worktree tạm sạch (cả .claude/settings.json). Mỗi ca chặn chỉ khác một ca cho qua đúng một biến.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID DEVKIT_SESSION_ID   # trunk mode mặc định bật; N8 tự tắt bằng git config

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"; GH="$TMP/github"; TR="$TMP/sess.jsonl"; SUB="$TMP/sess/subagents/agent-x.jsonl"
LOG="$REPO/.claude/audit-gate/proof_gate.log"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src templates docs .agents .claude
  printf '[ -z "$FAIL_SUITE" ]\n' > result.sh && echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: không cần ảnh, chỉ xét cổng
  echo '{"hooks": {}}' > .claude/settings.json                  # C3b: bản kit sửa cục bộ trong worktree (#691)
  echo "ghi chú" > docs/notes.md && echo "sẽ bị xoá" > docs/gone.md
  printf '.claude/audit-gate/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
git clone -q "$ORIGIN" "$GH" 2>/dev/null && git -C "$GH" config user.email gh@gh && git -C "$GH" config user.name github || exit 1

now_iso() { python3 -c 'import datetime,sys; print((datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(seconds=float(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%S.%fZ"))' "${1:-0}"; }
# session_start [future|notime]: phiên MỚI (transcript và subagents làm lại), lời nhắc người dùng = bây giờ = lúc phiên bắt đầu.
# future: dòng đầu (không phải user) mang giờ +1 h; notime: 201 dòng đầu không có timestamp.
session_start() {
  rm -rf "$TMP/sess" "$TR"; mkdir -p "$(dirname "$SUB")"; : > "$TR"
  case "${1:-}" in
    future) printf '{"type":"system","timestamp":"%s","content":"x"}\n' "$(now_iso 3600)" >> "$TR" ;;
    notime) for _ in $(seq 1 201); do echo '{"type":"summary","summary":"s"}' >> "$TR"; done ;;
  esac
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"gộp PR rồi giao"}}\n' "$(now_iso)" >> "$TR"; sleep 1; }
# tool_use NAME INPUT_JSON [FILE]: một tool_use của phiên (mặc định transcript chính), giờ hiện tại.
tool_use() { python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"isSidechain":sys.argv[3]!=sys.argv[4],"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu%d" % sum(1 for _ in open(sys.argv[3])),"name":sys.argv[1],"input":json.loads(sys.argv[2])}]}}))' \
  "$1" "$2" "${3:-$TR}" "$TR" >> "${3:-$TR}.new" && cat "${3:-$TR}.new" >> "${3:-$TR}" && rm -f "${3:-$TR}.new"; }
bash_use() { tool_use Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1")" "${2:-$TR}"; }
# sub_read CMD: lệnh Bash CHỈ ĐỌC của một subagent của phiên (như a87c9c72 lúc 09:53 30/10)
sub_read() { : >> "$SUB"; bash_use "$1" "$SUB"; }
wt_new() { WT="$TMP/wt-$1"; git -C "$REPO" worktree add -q --detach "$WT" HEAD; }
wt_edit() { echo "def ok(): return $1" > "$WT/src/core.py"; tool_use Write "{\"file_path\": \"$WT/src/core.py\", \"content\": \"x\"}"
            git -C "$WT" commit -qam "edit $1"; }
gate() { local d="$1"; shift; CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --run-tests --no-checklist "$@" >"$TMP/gate" 2>&1; }
# land N: GitHub squash pr-N vào main, main local đồng bộ (pull --ff-only), worktree bị gỡ
land() { ( cd "$GH" && git fetch -q origin && git checkout -q main && git reset -q --hard origin/main \
           && git merge -q --squash "origin/pr-$1" >/dev/null 2>&1 && git commit -qm "squash pr $1 (#$1)" && git push -q origin main ) \
         && git -C "$REPO" pull -q --ff-only origin main && git -C "$REPO" worktree remove --force "$WT"; }
# pr_flow N: worktree → sửa → gate --full exit 0 → push → squash → main đồng bộ → gỡ worktree
pr_flow() { wt_new "p$1" && wt_edit "$1" && gate "$WT" --full --diff HEAD~1 && git -C "$WT" push -q origin "HEAD:refs/heads/pr-$1" && land "$1"; }
# gate_head: lời khuyên mới — worktree tạm ở HEAD main, `--tree HEAD`, gỡ
gate_head() { local w="$TMP/wt-head" g; git -C "$REPO" worktree add -q --detach "$w" HEAD || return 1
              gate "$w" --tree HEAD; g=$?; git -C "$REPO" worktree remove --force "$w"; return $g; }
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
stop() {
  rm -f "$REPO/.claude/audit-gate/proof_gate.state" "$LOG"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-t","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã gộp. Gate exit 0, ảnh: không cần — backend
$REPORT" | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
blocked() { [ "$1" = 2 ] && grep -q "Cổng:" "$TMP/err"; }
why() { echo "rc=$1 err=$(grep -m1 'Cổng:' "$TMP/err" || head -2 "$TMP/err" | tr '\n' ' ')"; }

# File của người khác ở main, có từ TRƯỚC phiên (như docs/audit/devkit-audit-20261028.md và .agents/local/hold-545/ của sự cố).
mkdir -p "$REPO/docs/audit" "$REPO/.agents/local/hold"
echo "settings: báo cáo cũ" > "$REPO/docs/audit/old.md"; echo "patch cũ" > "$REPO/.agents/local/hold/x.patch"
sleep 3

# C1. Sự cố: subagent đọc file bẩn cũ bằng grep; PR gate --full trong worktree rồi squash; main = squash: cho qua qua tree-store (2).
session_start; sub_read "grep -n settings docs/audit/old.md | head -30"
pr_flow 11 || fail "C1 setup: pr_flow ($(tail -3 "$TMP/gate" | tr '\n' ' '))"; stop; rc=$?
[ "$rc" = 0 ] && ok "C1 old foreign untracked files named by a read-only shell command: XONG allowed" || fail "C1 blocked ($(why $rc))"
grep -Eq 'tree-receipt head=[0-9a-f]+ fp=[0-9a-f]+ foreign=\.agents/local/hold/x\.patch,docs/audit/old\.md' "$LOG" 2>/dev/null \
  && ok "C1b allowed through tree-store (2), foreign paths logged in sorted order" || fail "C1b no tree-receipt foreign= log line"

# Thêm bẩn cũ: một file tracked riêng bị sửa (PR không đụng), một nested repo, một symlink — đều trước phiên kế tiếp.
echo "sửa cục bộ" >> "$REPO/docs/notes.md"
mkdir -p "$REPO/nested-repo" && git -C "$REPO/nested-repo" init -q && echo n > "$REPO/nested-repo/f.txt" \
  && git -C "$REPO/nested-repo" add -A && git -C "$REPO/nested-repo" -c user.email=n@n -c user.name=n commit -qm n || fail "setup nested repo"
ln -s docs/notes.md "$REPO/old-link"
sleep 3

# C2. Như C1, cộng file tracked cũ bị sửa mà lệnh chỉ đọc của subagent nhắc tên: cho qua.
session_start; sub_read "grep -n settings docs/audit/old.md; wc -l docs/notes.md"
pr_flow 12 || fail "C2 setup: pr_flow ($(tail -3 "$TMP/gate" | tr '\n' ' '))"; stop; rc=$?
[ "$rc" = 0 ] && ok "C2 + an old modified tracked file named by a read-only shell command: XONG allowed" || fail "C2 blocked ($(why $rc))"
grep -q 'foreign=\.agents/local/hold/x\.patch,docs/audit/old\.md,docs/notes\.md' "$LOG" 2>/dev/null \
  && ok "C2b the tracked file is among the logged foreign paths" || fail "C2b no foreign= line with docs/notes.md"

# C3a. Không PR. Chưa gate: chặn, lời khuyên nêu trunk mode + --tree HEAD. Theo lời khuyên (worktree sạch ở HEAD, --tree HEAD): cho qua.
session_start; sub_read "grep -n settings docs/audit/old.md"; stop; rc=$?
blocked "$rc" && grep -q -- "--tree HEAD" "$TMP/err" && grep -q "trunk mode" "$TMP/err" \
  && ok "C3a before the gate: blocked, advice names trunk mode and --tree HEAD" || fail "C3a advice missing ($(why $rc))"
gate_head || fail "C3a setup: --tree HEAD exit $? ($(tail -3 "$TMP/gate" | tr '\n' ' '))"; stop; rc=$?
[ "$rc" = 0 ] && ok "C3a following the advice in a clean worktree at HEAD: XONG allowed" || fail "C3a blocked after the advised gate ($(why $rc))"

# C3b. Worktree ở HEAD có .claude/settings.json sửa cục bộ: --tree HEAD từ chối (exit 2, không biên nhận: vẫn chặn); trả lại settings.json
# như lời khuyên nói: exit 0, cho qua.
session_start; sub_read "grep -n settings docs/audit/old.md"
W="$TMP/wt-c3b"; git -C "$REPO" worktree add -q --detach "$W" HEAD && echo '{"hooks": {"Stop": []}}' > "$W/.claude/settings.json"
gate "$W" --tree HEAD; g=$?
[ "$g" = 2 ] && grep -q "settings.json" "$TMP/gate" && ok "C3b --tree HEAD refuses a kit-edited settings.json (exit 2)" || fail "C3b setup: --tree exit $g, want 2"
stop; rc=$?; blocked "$rc" && ok "C3b no receipt from the refused run: blocked" || fail "C3b accepted without a receipt ($(why $rc))"
git -C "$W" checkout -q -- .claude/settings.json && gate "$W" --tree HEAD || fail "C3b setup: --tree after restore exit $?"
git -C "$REPO" worktree remove --force "$W"; stop; rc=$?
[ "$rc" = 0 ] && ok "C3b settings.json restored, --tree HEAD exit 0: XONG allowed" || fail "C3b blocked after the advised gate ($(why $rc))"

# N1. File bẩn tạo SAU khi phiên bắt đầu, lệnh shell của phiên nhắc tên: chặn (luật cũ).
session_start; sub_read "grep -n settings docs/audit/old.md"; echo f > "$REPO/docs/fresh.md"; bash_use "cat docs/fresh.md"
gate_head || fail "N1 setup"; stop; rc=$?; rm -f "$REPO/docs/fresh.md"
blocked "$rc" && ok "N1 a file created after the session start, named by its shell: blocked" || fail "N1 accepted ($(why $rc))"
# N1b(i). Nested repo cũ (thư mục, không phải file thường), lệnh shell nhắc tên: chặn.
session_start; sub_read "grep -n settings docs/audit/old.md"; bash_use "git -C nested-repo log -1; ls nested-repo/"
gate_head || fail "N1b(i) setup"; stop; rc=$?
blocked "$rc" && ok "N1b(i) an old nested repo directory named by the shell: blocked" || fail "N1b(i) accepted ($(why $rc))"
# N1b(ii). Symlink cũ, lệnh shell nhắc tên: chặn.
session_start; sub_read "grep -n settings docs/audit/old.md"; bash_use "readlink old-link"
gate_head || fail "N1b(ii) setup"; stop; rc=$?
blocked "$rc" && ok "N1b(ii) an old symlink named by the shell: blocked" || fail "N1b(ii) accepted ($(why $rc))"
# N1b(iii). Dòng đầu transcript mang giờ tương lai; file tạo trong phiên, lệnh shell nhắc tên: chặn.
session_start future; sub_read "grep -n settings docs/audit/old.md"; echo f > "$REPO/docs/fresh3.md"; bash_use "cat docs/fresh3.md"
gate_head || fail "N1b(iii) setup"; stop; rc=$?; rm -f "$REPO/docs/fresh3.md"
blocked "$rc" && ok "N1b(iii) a future first timestamp does not age a new file: blocked" || fail "N1b(iii) accepted ($(why $rc))"
# N3. Công cụ sửa file nêu đúng file cũ (file không đổi, ctime cũ): chặn.
session_start; sub_read "grep -n settings docs/audit/old.md"
tool_use Edit "{\"file_path\": \"$REPO/docs/audit/old.md\", \"old_string\": \"a\", \"new_string\": \"b\"}"
gate_head || fail "N3 setup"; stop; rc=$?
blocked "$rc" && ok "N3 an edit tool naming the old file: blocked" || fail "N3 accepted ($(why $rc))"
# N4. File tracked bị xoá ở main (không lstat được), lệnh shell nhắc tên: chặn.
session_start; sub_read "grep -n settings docs/audit/old.md"; rm -f "$REPO/docs/gone.md"; bash_use "cat docs/gone.md"
gate_head || fail "N4 setup"; stop; rc=$?; git -C "$REPO" checkout -q -- docs/gone.md
blocked "$rc" && ok "N4 a deleted tracked file named by the shell: blocked" || fail "N4 accepted ($(why $rc))"
# N5. Không gate trong lượt: chặn.
session_start; sub_read "grep -n settings docs/audit/old.md"; stop; rc=$?
blocked "$rc" && ok "N5 no gate: blocked" || fail "N5 accepted ($(why $rc))"
# N6. Gate ở lượt TRƯỚC: chặn.
gate_head || fail "N6 setup"; sleep 1; session_start; sub_read "grep -n settings docs/audit/old.md"; stop; rc=$?
blocked "$rc" && ok "N6 receipt from before the turn: blocked" || fail "N6 accepted ($(why $rc))"
# N8. Trunk mode tắt: chặn.
git -C "$REPO" config devkit.trunkMode false
session_start; sub_read "grep -n settings docs/audit/old.md"; gate_head || fail "N8 setup"; stop; rc=$?
git -C "$REPO" config --unset devkit.trunkMode
blocked "$rc" && ok "N8 trunk mode off: blocked" || fail "N8 accepted ($(why $rc))"
# N9. 200 dòng đầu transcript không có timestamp (không biết lúc phiên bắt đầu): chặn.
session_start notime; sub_read "grep -n settings docs/audit/old.md"; gate_head || fail "N9 setup"; stop; rc=$?
blocked "$rc" && ok "N9 no session start in the first 200 lines: blocked" || fail "N9 accepted ($(why $rc))"

# N10. Bản cài copy-mode (chỉ proof_gate.sh + devkit_harness.py, như test_hook_python_isolation.sh): XONG thiếu biên nhận ở main trunk
# mode vẫn exit 2 (không bao giờ crash thành exit 0 vì thiếu session_worktree.py).
CP="$TMP/cp"; mkdir -p "$CP/.claude/hooks" "$CP/.agents/devkit" && git -C "$CP" init -q && echo a > "$CP/a.txt" \
  && git -C "$CP" add -A && git -C "$CP" -c user.email=c@c -c user.name=c commit -qm i && echo b > "$CP/a.txt" \
  && cp "$DEVKIT_DIR/hooks/proof_gate.sh" "$DEVKIT_DIR/hooks/devkit_harness.py" "$CP/.claude/hooks/" \
  && cp -R "$DEVKIT_DIR/bin" "$CP/.agents/devkit/bin" || fail "N10 setup"
session_start
python3 -c 'import json,sys; print(json.dumps({"session_id":"s-c","hook_event_name":"Stop","transcript_path":sys.argv[1],
  "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
$REPORT" | CLAUDE_PROJECT_DIR="$CP" bash "$CP/.claude/hooks/proof_gate.sh" >"$TMP/out" 2>"$TMP/err"; rc=$?
blocked "$rc" && ok "N10 copy-mode install without session_worktree.py: still exit 2" || fail "N10 copy-mode not blocked ($(why $rc))"

# N2. File cũ bị `touch -t` trong phiên (mtime cũ, ctime mới), lệnh shell nhắc tên: chặn. (Sau ca này old.md không còn "cũ".)
session_start; sub_read "grep -n settings docs/audit/old.md"; touch -t 202001010000 "$REPO/docs/audit/old.md"
bash_use "touch -t 202001010000 docs/audit/old.md"; gate_head || fail "N2 setup"; stop; rc=$?
blocked "$rc" && ok "N2 old file re-dated with touch -t in the session: blocked" || fail "N2 accepted ($(why $rc))"
# N7. Main có commit sau cây đã gate: chặn. (Ca cuối: main đi trước origin.)
session_start; sub_read "wc -l docs/notes.md"; gate_head || fail "N7 setup"
echo z > "$REPO/docs/local.md" && git -C "$REPO" add docs/local.md && git -C "$REPO" commit -qm local; stop; rc=$?
blocked "$rc" && ok "N7 main moved past the gated tree: blocked" || fail "N7 accepted ($(why $rc))"

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
