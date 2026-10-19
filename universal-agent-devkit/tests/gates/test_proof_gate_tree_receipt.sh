#!/usr/bin/env bash
# Test hồi quy #105 (19/10): phiên làm trong worktree, gate --full exit 0 ở đó, giao bằng `worktree finish` hoặc PR squash, worktree bị
# gỡ. proof_gate xét main (trunk mode cấm chạy gate ở main) mà biên nhận của worktree nằm trong git dir riêng của nó, mất theo worktree;
# full_pass.json duy nhất của main thì cũ ("lần exit 0 là từ trước lượt này") hoặc bị finish của phiên khác ghi đè ("code đã đổi").
# Sửa: post-fix-gate ghi thêm biên nhận --full exit 0 theo cây vào git COMMON dir (tree_receipts/), proof_gate nhận biên nhận của lượt
# có cây = cây phiên đã giao. Mỗi ca chặn chỉ khác ca cho qua đúng một biến.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE   # trunk mode mặc định bật; ca N8 tự tắt nó bằng git config

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"; GH="$TMP/github"; TR="$TMP/transcript.jsonl"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src templates docs .agents
  printf '[ -n "$UNTESTED" ] && exit 3\n[ -z "$FAIL_SUITE" ]\n' > result.sh && echo "def ok(): return 1" > src/core.py   # cùng nội dung: suite đỏ / UNTESTED
  echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: không cần ảnh, chỉ xét cổng
  printf '.claude/audit-gate/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh","untested_exit":3}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
git clone -q "$ORIGIN" "$GH" 2>/dev/null && git -C "$GH" config user.email gh@gh && git -C "$GH" config user.name github || exit 1
MAIN_RECEIPT="$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
STORE="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/postfix-gate/tree_receipts"

turn_start() { python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X rồi giao"}}))' > "$TR"; sleep 1; }
tool_use() { python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"assistant","timestamp":t,"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu1","name":sys.argv[1],"input":json.loads(sys.argv[2])}]}}))' "$1" "$2" >> "$TR"; }
# main_receipt old|foreign: full_pass.json của main như 19/10 — từ lượt trước (NFH, GeelyEx2), hoặc biên nhận một finish của phiên KHÁC
# vừa chép sang main cho cây khác (#104, "code đã đổi").
main_receipt() { mkdir -p "$(dirname "$MAIN_RECEIPT")"; python3 - "$MAIN_RECEIPT" "$1" "$REPO" <<'PY'
import json, sys, time
p, kind, repo = sys.argv[1:]
json.dump({"exit": 0, "time": time.time() - (7200 if kind == "old" else 0), "fingerprint": "0123456789abcdef01234567",
           "project": repo, "head": "0" * 40, "dirty": {}, "carried_from": "/other/.claude/worktrees/x"}, open(p, "w"))
PY
}
wt_new() { WT="$TMP/wt-$1"; git -C "$REPO" worktree add -q --detach "$WT" HEAD; }
# wt_edit N: phiên sửa src/core.py TRONG worktree của nó (Write ghi vào transcript) rồi commit
wt_edit() { echo "def ok(): return $1" > "$WT/src/core.py"; tool_use Write "{\"file_path\": \"$WT/src/core.py\", \"content\": \"x\"}"
            git -C "$WT" commit -qam "edit $1"; }
# gate DIR [args]: gate --run-tests --full trong cây đó như một phiên làm (CLAUDE_PROJECT_DIR = cây đó)
gate() { local d="$1"; shift; CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --run-tests --full --no-checklist "$@" >"$TMP/gate" 2>&1; }
# finish: phần cuối của `agent-kit worktree finish`: main fast-forward tới worktree, worktree bị gỡ
finish() { git -C "$REPO" merge -q --ff-only "$(git -C "$WT" rev-parse HEAD)" && git -C "$REPO" worktree remove --force "$WT"; }
# land N: GitHub squash nhánh pr-N vào main, main local đồng bộ như merge gate (pull --ff-only), worktree bị gỡ
land() { ( cd "$GH" && git fetch -q origin && git checkout -q main && git reset -q --hard origin/main \
           && git merge -q --squash "origin/pr-$1" >/dev/null 2>&1 && git commit -qm "squash pr $1 (#$1)" && git push -q origin main ) \
         && git -C "$REPO" pull -q --ff-only origin main && git -C "$REPO" worktree remove --force "$WT"; }
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
stop() {
  rm -f "$REPO/.claude/audit-gate/proof_gate.state"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-t","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã giao. Gate exit 0, ảnh: không cần — backend
$REPORT" | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
blocked() { [ "$1" = 2 ] && grep -q "Cổng:" "$TMP/err"; }
why() { echo "rc=$1 err=$(grep -m1 'Cổng:' "$TMP/err" || head -2 "$TMP/err" | tr '\n' ' ')"; }

# C1. finish: gate --full exit 0 trong worktree, main fast-forward, worktree gỡ; main chỉ có biên nhận cũ: cho qua.
turn_start; main_receipt old; wt_new c1; wt_edit 11; gate "$WT" --diff HEAD~1 || fail "C1 setup: gate exit $?"; finish; stop; rc=$?
[ "$rc" = 0 ] && ok "C1 worktree gated then finished and removed: XONG allowed" || fail "C1 finish blocked ($(why $rc))"
git -C "$REPO" push -q origin main   # main = origin cho các ca PR dưới đây

# C2. PR squash: nhánh pr-21 đẩy lên, GitHub squash, main đồng bộ origin, worktree gỡ; main giữ biên nhận phiên khác: cho qua.
turn_start; main_receipt foreign; wt_new c2; wt_edit 21; gate "$WT" --diff HEAD~1 || fail "C2 setup: gate exit $?"
git -C "$WT" push -q origin HEAD:refs/heads/pr-21 && land 21 || fail "C2 setup: land"; stop; rc=$?
[ "$rc" = 0 ] && ok "C2 squash-merged PR, main synced, worktree removed: XONG allowed" || fail "C2 squash blocked ($(why $rc))"

# C2b. Base đi tiếp trước squash: cây squash khác cây worktree; chỉ biên nhận lần verify của merge gate (scratch: PR merge base) khớp.
turn_start; wt_new c2b; wt_edit 22; gate "$WT" --diff HEAD~1 || fail "C2b setup: gate exit $?"
git -C "$WT" push -q origin HEAD:refs/heads/pr-22
( cd "$GH" && git pull -q origin main && mkdir -p docs && echo "khác" > docs/other.md && git add docs/other.md && git commit -qm "pr khác" && git push -q origin main ) \
  || fail "C2b setup: other PR"
SCR="$TMP/scratch"; git -C "$REPO" fetch -q origin && git -C "$REPO" worktree add -q --detach "$SCR" "$(git -C "$WT" rev-parse HEAD)" \
  && git -C "$SCR" merge -q --no-edit origin/main && { gate "$SCR" --brief --diff origin/main --force-full || fail "C2b setup: verify exit $?"; }
git -C "$REPO" worktree remove --force "$SCR"; land 22 || fail "C2b setup: land"; stop; rc=$?
[ "$rc" = 0 ] && ok "C2b base moved: the merge-gate verify receipt of the squash tree: XONG allowed" || fail "C2b blocked ($(why $rc))"

# C3a. Như C2b, rồi main giữ file chưa track VÀ một file tracked bị sửa, đều của phiên khác (runner của board): cho qua.
echo "# run log của runner" > "$REPO/docs/foreign.md"; echo "# runner" >> "$REPO/docs/other.md"; stop; rc=$?
[ "$rc" = 0 ] && ok "C3a foreign untracked + modified tracked file in main: XONG allowed" || fail "C3a foreign dirty blocked ($(why $rc))"
# N9. Cùng cảnh đó, nhưng chính phiên này đã ghi file bẩn đó ở main: chặn (luật PR #50).
tool_use Write "{\"file_path\": \"$REPO/docs/foreign.md\", \"content\": \"x\"}"; stop; rc=$?
blocked "$rc" && ok "N9 the dirty main file is this session's own: blocked" || fail "N9 own dirty file accepted ($(why $rc))"
# N9b. Như C3a, nhưng một lệnh Bash của phiên nêu đường dẫn tương đối của file tracked bị sửa: chặn.
python3 -c 'import sys; open(sys.argv[1], "w").write(open(sys.argv[1]).read().split("\n",1)[0] + "\n")' "$TR"   # bỏ Write của N9
tool_use Bash '{"command": "echo x >> docs/other.md"}'; stop; rc=$?
blocked "$rc" && ok "N9b a dirty tracked main file named by this session's Bash: blocked" || fail "N9b accepted ($(why $rc))"
rm -f "$REPO/docs/foreign.md"; git -C "$REPO" checkout -q -- docs/other.md

# N14. Như C2b nhưng không có lần verify của merge gate: biên nhận worktree là của cây khác cây squash. Chặn.
turn_start; wt_new n14; wt_edit 151; gate "$WT" --diff HEAD~1 || fail "N14 setup: gate exit $?"
git -C "$WT" push -q origin HEAD:refs/heads/pr-151
( cd "$GH" && git pull -q origin main && echo "khác 14" > docs/other14.md && git add docs/other14.md && git commit -qm "pr khác 14" && git push -q origin main ) \
  || fail "N14 setup: other PR"
land 151 || fail "N14 setup: land"; stop; rc=$?
blocked "$rc" && ok "N14 base moved, no merge-gate verify receipt of the squash tree: blocked" || fail "N14 accepted ($(why $rc))"

# C3b. Sửa → gate trên cây CHƯA commit → commit → finish; main giữ file chưa track của phiên khác: cho qua (dấu vân tay commit HEAD).
turn_start; wt_new c3b; echo "def ok(): return 32" > "$WT/src/core.py"; tool_use Write "{\"file_path\": \"$WT/src/core.py\", \"content\": \"x\"}"
gate "$WT" --diff HEAD || fail "C3b setup: gate exit $?"; git -C "$WT" commit -qam "edit 32"; finish
echo "# run log của runner" > "$REPO/docs/foreign.md"; stop; rc=$?; rm -f "$REPO/docs/foreign.md"
[ "$rc" = 0 ] && ok "C3b gated uncommitted, committed, finished; foreign file in main: XONG allowed" || fail "C3b blocked ($(why $rc))"

# N10. Như C1, rồi main đi tiếp một commit sau cây đã gate (dù của phiên khác): cây giao không còn là cây đã gate. Chặn (gate lại).
turn_start; wt_new n10; wt_edit 33; gate "$WT" --diff HEAD~1 || fail "N10 setup: gate exit $?"; finish
echo "phiên khác" > "$REPO/docs/other3.md" && git -C "$REPO" add docs/other3.md && git -C "$REPO" commit -qm "phiên khác"; stop; rc=$?
blocked "$rc" && ok "N10 main moved past the gated tree: blocked" || fail "N10 accepted a commit after the gated tree ($(why $rc))"

# N11. Phiên này không gate; phiên khác gate + finish cây của nó trong lượt; phiên này sửa qua Bash không nêu đường dẫn, commit, finish: chặn.
turn_start; wt_new n11t; echo T > "$WT/docs/t.md"; git -C "$WT" add docs/t.md && git -C "$WT" commit -qm t
gate "$WT" --diff HEAD~1 || fail "N11 setup: gate exit $?"; finish
wt_new n11; tool_use Bash '{"command": "python3 tools/bump.py && git commit -qam bump"}'
echo "def ok(): return 121" > "$WT/src/core.py"; git -C "$WT" commit -qam bump; finish; stop; rc=$?
blocked "$rc" && ok "N11 no gate of its own, shell-only edit after another session's gated finish: blocked" || fail "N11 accepted ($(why $rc))"

# N12. Gate trên cây CHƯA sửa (= cây đầu lượt), rồi sửa bằng git apply + commit, finish: chặn.
turn_start; wt_new n12; gate "$WT" --diff HEAD~1 || fail "N12 setup: gate exit $?"
printf 'def ok(): return 131\n' > "$WT/src/core.py"; git -C "$WT" diff > "$TMP/n12.patch"; git -C "$WT" checkout -q -- src/core.py
tool_use Bash "{\"command\": \"git apply $TMP/n12.patch && git commit -qam fix\"}"
git -C "$WT" apply "$TMP/n12.patch" && git -C "$WT" commit -qam fix; finish; stop; rc=$?
blocked "$rc" && ok "N12 gate first on the untouched tree, shell edit after: blocked" || fail "N12 accepted ($(why $rc))"

# N13. Gate exit 0, rồi `cd src && printf … > helper.py` (đường dẫn không đủ) + commit, finish: chặn.
turn_start; wt_new n13; wt_edit 141; gate "$WT" --diff HEAD~1 || fail "N13 setup: gate exit $?"
tool_use Bash '{"command": "cd src && printf x > helper.py && git add helper.py && git commit -qm h"}'
echo "def broken(:" > "$WT/src/helper.py"; git -C "$WT" add src/helper.py && git -C "$WT" commit -qm h; finish; stop; rc=$?
blocked "$rc" && ok "N13 a shell edit naming no repo path after the gate: blocked" || fail "N13 accepted ($(why $rc))"

# N1. Không chạy gate nào: chặn.
turn_start; wt_new n1; wt_edit 41; finish; stop; rc=$?
blocked "$rc" && ok "N1 no gate at all: blocked" || fail "N1 accepted without a gate ($(why $rc))"

# N2. Gate exit 0, rồi phiên sửa tiếp trong worktree, commit, finish: cây giao không phải cây đã gate. Chặn.
turn_start; wt_new n2; wt_edit 51; gate "$WT" --diff HEAD~1 || fail "N2 setup: gate exit $?"; wt_edit 52; finish; stop; rc=$?
blocked "$rc" && ok "N2 edited and committed after the gate: blocked" || fail "N2 ungated commit accepted ($(why $rc))"

# N3. Gate không --full (lượt từng phần): không biên nhận, chặn.
turn_start; wt_new n3; wt_edit 61
CLAUDE_PROJECT_DIR="$WT" python3 "$GATE" --run-tests --no-checklist --diff HEAD~1 >"$TMP/gate" 2>&1; finish; stop; rc=$?
blocked "$rc" && ok "N3 gate without --full: blocked" || fail "N3 partial gate accepted ($(why $rc))"

# N4. Gate exit 3 (không có gì để audit: cây sạch, không --diff): chặn.
turn_start; wt_new n4; wt_edit 71; gate "$WT"; g=$?; finish; stop; rc=$?
[ "$g" = 3 ] || fail "N4 setup: gate exit $g, want 3"
blocked "$rc" && ok "N4 gate exit 3: blocked" || fail "N4 exit-3 gate accepted ($(why $rc))"

# N5. Gate exit 0, rồi một lần gate --full TRÊN CÙNG CÂY đỏ (exit 1): phán quyết mới nhất bỏ biên nhận cây đó. Chặn.
turn_start; wt_new n5; wt_edit 81; gate "$WT" --diff HEAD~1 || fail "N5 setup: gate exit $?"
FAIL_SUITE=1 gate "$WT" --diff HEAD~1 --no-cache; g=$?; finish; stop; rc=$?
[ "$g" = 1 ] || fail "N5 setup: failing gate exit $g, want 1"
blocked "$rc" && ok "N5 a later red --full on the same tree: blocked" || fail "N5 stale exit-0 receipt accepted ($(why $rc))"

# N5b. Như N5 nhưng lần sau ra exit 4 (UNTESTED: suite không chạy được trên máy này): không còn là PASS của cây đó. Chặn.
turn_start; wt_new n5b; wt_edit 82; gate "$WT" --diff HEAD~1 || fail "N5b setup: gate exit $?"
UNTESTED=1 gate "$WT" --diff HEAD~1 --no-cache; g=$?; finish; stop; rc=$?
[ "$g" = 4 ] || fail "N5b setup: untested gate exit $g, want 4"
blocked "$rc" && ok "N5b a later UNTESTED --full on the same tree: blocked" || fail "N5b stale exit-0 receipt accepted ($(why $rc))"

# N6b. Biên nhận hợp lệ của cây khác chép sang tên = dấu vân tay cây giao (field fingerprint vẫn của cây kia): chặn. Đối chứng: sửa
# field cho khớp thì qua (kho là file agent ghi được, như full_pass.json; không có chữ ký); thêm exit false (bool, == 0 trong python): chặn.
turn_start; wt_new n6b; wt_edit 92; gate "$WT" --diff HEAD~1 || fail "N6b setup: gate exit $?"; wt_edit 93; finish
FP93="$(python3 "$DEVKIT_DIR/bin/tree_fp.py" "$REPO")"; SRC="$(ls -t "$STORE"/*.json | head -1)"
cp "$SRC" "$STORE/$FP93.json"; stop; rc=$?
blocked "$rc" && ok "N6b a receipt copied onto the delivered tree's name: blocked" || fail "N6b renamed receipt accepted ($(why $rc))"
setf() { python3 -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); r.update(json.loads(sys.argv[2])); json.dump(r,open(p,"w"))' "$STORE/$FP93.json" "$1"; }
setf "{\"fingerprint\": \"$FP93\"}"; stop; rc=$?
[ "$rc" = 0 ] || fail "N6b control: fingerprint fixed should pass ($(why $rc))"
setf '{"exit": false}'; stop; rc=$?
blocked "$rc" && ok "N6b a receipt with exit false: blocked" || fail "N6b exit-false receipt accepted ($(why $rc))"

# N6. Biên nhận trong kho có cây đúng nhưng exit 2: chặn.
turn_start; wt_new n6; wt_edit 91; gate "$WT" --diff HEAD~1 || fail "N6 setup: gate exit $?"; finish
ls "$STORE"/*.json >/dev/null 2>&1 || fail "N6 setup: no store receipt"
for f in "$STORE"/*.json; do [ -f "$f" ] && python3 -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); r["exit"]=2; json.dump(r,open(p,"w"))' "$f"; done
stop; rc=$?
blocked "$rc" && ok "N6 store receipt with exit 2: blocked" || fail "N6 exit-2 receipt accepted ($(why $rc))"

# N7. Gate ở lượt TRƯỚC (biên nhận cũ hơn lời nhắc người dùng), giao ở lượt này: chặn như luật cũ.
wt_new n7; wt_edit 101; gate "$WT" --diff HEAD~1 || fail "N7 setup: gate exit $?"; sleep 5; turn_start; finish; stop; rc=$?
blocked "$rc" && ok "N7 receipt from before this turn: blocked" || fail "N7 earlier-turn receipt accepted ($(why $rc))"

# N8. Trunk mode tắt: luật mới không áp, chặn như cũ.
git -C "$REPO" config devkit.trunkMode false
turn_start; main_receipt old; wt_new n8; wt_edit 111; gate "$WT" --diff HEAD~1 || fail "N8 setup: gate exit $?"; finish; stop; rc=$?
git -C "$REPO" config --unset devkit.trunkMode
blocked "$rc" && ok "N8 trunk mode off: blocked" || fail "N8 accepted outside trunk mode ($(why $rc))"

# T1. commit_fingerprint giữ MỘT hạn chót cho mọi lệnh git của nó (hook quá hạn bị giết = Stop lọt): git chậm 0,4 s/lệnh, hạn 1 s.
TFP="${TFP_DIR:-$DEVKIT_DIR/bin}"; mkdir -p "$TMP/slowbin"
printf '#!%s\nimport os, sys, time\ntime.sleep(0.4)\nos.execv("%s", ["%s"] + sys.argv[1:])\n' "$(command -v python3)" "$(command -v git)" "$(command -v git)" \
  > "$TMP/slowbin/git" && chmod +x "$TMP/slowbin/git"   # ngủ trong chính tiến trình bị giết (sleep con của sh giữ ống thêm 0,4 s)
out=$(PATH="$TMP/slowbin:$PATH" python3 -c 'import subprocess, sys, time; sys.path.insert(0, sys.argv[1]); import tree_fp
t = time.monotonic()
try:
    tree_fp.commit_fingerprint(sys.argv[2], "HEAD", timeout=1.0); r = "returned"
except subprocess.TimeoutExpired:
    r = "timeout"
print(r, round(time.monotonic() - t, 1))' "$TFP" "$REPO" 2>&1)
case "$out" in "timeout 1."*) ok "T1 commit_fingerprint keeps one deadline ($out)" ;;   # sớm hơn hạn (0.x) cũng sai: chặn oan
  *) fail "T1 commit_fingerprint ran past its deadline ($out)" ;; esac

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
