#!/usr/bin/env bash
# Test hồi quy #644 lane C: biên nhận scoped (<git dir>/postfix-gate/scoped_pass.json + <git common dir>/postfix-gate/scoped_receipts/<fp>.json,
# `"scope":"scoped"`, lượt gate chỉ chạy test liên quan diff) được push_gate và proof_gate nhận NHƯ biên nhận --full, với cùng mọi kiểm tra:
#   a  scoped_pass.json đúng cây + dòng runs.jsonl mode scoped: push qua, XONG qua; mục scoped_receipts/ cứu XONG ở main (trunk mode)
#   b  sửa 1 byte file tracked sau biên nhận: cả hai từ chối
#   c  scope "task" (hay thiếu scope) trong scoped_pass.json: từ chối
#   d  thiếu dòng run-log mode scoped (chỉ có dòng impacted / full): push từ chối
#   e  biên nhận --full cũ vẫn chạy y như trước (đối chứng harness: cùng hàm dựng, chỉ khác tên file và mode)
#   f  biên nhận --full hợp lệ nhưng của head cũ hơn + scoped phủ commit mới: push qua (full không phủ thì thử scoped)
#   g  scoped hợp lệ nhưng head không còn trong lịch sử: push chỉ docs vẫn qua như khi không có file scoped
#   i  base của biên nhận scoped chưa có trên upstream (commit chưa push): push chặn; base trên upstream: push qua
#   j  worktree finish chép biên nhận phủ HEAD của main (head là tổ tiên), không phải biên nhận mới nhất mà head lạc lịch sử
#   h  proof_gate merged_evidence (a): scoped_pass.json của worktree anh em sạch cùng cây cứu XONG ở main; scope task thì không
# Biên nhận dựng tay bằng mk() (trường theo write_full_pass_receipt, bin/post-fix-gate.py), dấu vân tay bằng bin/tree_fp.py.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
PG="$DEVKIT_DIR/bin/push_gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"; TR="$TMP/transcript.jsonl"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && mkdir -p src .agents
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json   # backend: XONG không cần ảnh, chỉ xét cổng
  printf '.claude/audit-gate/\n' > .gitignore
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
  echo "def ok(): return 2" > src/core.py && git commit -qam "edit 2" ) || exit 1   # commit code chưa push: cần biên nhận
GITDIR="$(git -C "$REPO" rev-parse --absolute-git-dir)"
COMMON="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)"
FULL="$GITDIR/postfix-gate/full_pass.json"; SCOPED="$GITDIR/postfix-gate/scoped_pass.json"
SSTORE="$COMMON/postfix-gate/scoped_receipts"; RUNLOG="$COMMON/postfix-gate/runs.jsonl"

# mk <đích> <scope: full | scoped | task | none> [rev]: biên nhận exit 0 đúng các trường write_full_pass_receipt ghi; rev khác HEAD = biên nhận
# của commit đó (dấu vân tay = tree_fp.commit_fingerprint). Đích "store" = scoped_receipts/<fp>.json. In dấu vân tay.
mk() { python3 - "$DEVKIT_DIR/bin" "${MKREPO:-$REPO}" "$@" <<'PY'
import json, os, subprocess, sys, time
sys.path.insert(0, sys.argv[1]); import tree_fp
repo, dest, scope = sys.argv[2], sys.argv[3], sys.argv[4]
rev = sys.argv[5] if len(sys.argv) > 5 else "HEAD"
git = lambda *a: subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True).stdout.strip()
head = git("rev-parse", rev)
fp = tree_fp.tree_fingerprint(repo) if rev == "HEAD" else tree_fp.commit_fingerprint(repo, head)
now = time.time()
d = {"time": now, "exit": 0, "project": os.path.realpath(repo), "fingerprint": fp, "tested_at": now, "result_format": 2,
     "gate_sha": "0" * 64, "matrix_sha": "0" * 64, "local_sha": "0" * 64, "local_regen": [], "head": head, "dirty": {}, "links": {},
     "tests": [{"id": "REG-1", "status": "PASS", "log": None, "duration": 0.1, "ran_at": now}]}
if scope != "full":
    if scope != "none":
        d["scope"] = scope
    d.update({"scoped_tests": ["tests/test_core.sh"], "reasons": ["diff src/core.py"], "base": git("rev-parse", os.environ.get("MKBASE") or "origin/main"),
              "tree": git("rev-parse", rev + "^{tree}")})
if dest == "store":
    dest = os.path.join(git("rev-parse", "--path-format=absolute", "--git-common-dir"), "postfix-gate", "scoped_receipts", fp + ".json")
os.makedirs(os.path.dirname(dest), exist_ok=True)
json.dump(d, open(dest, "w"))
print(fp)
PY
}
# logline <mode>: dòng runs.jsonl của lượt vừa ghi biên nhận (như _log_gate_run)
logline() { python3 -c 'import json,os,sys,time; print(json.dumps({"v":1,"epoch":int(time.time()),"project":os.path.basename(os.path.realpath(sys.argv[1]))[:64],
  "mode":sys.argv[2],"exit":0,"verdict":"PASS","fp":""}))' "${MKREPO:-$REPO}" "$1" >> "$RUNLOG"; }
reset() { rm -rf "$FULL" "$SCOPED" "$SSTORE" "$RUNLOG"; mkdir -p "$GITDIR/postfix-gate"; }
push() { PUSH_OUT="$(python3 "$PG" "$REPO" 2>&1)"; PUSH_RC=$?; }

turn_start() { python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X rồi giao"}}))' > "$TR"; sleep 1; }
REPORT="1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0."
stop() {   # hook Stop với XONG, xét $REPO
  rm -f "$REPO/.claude/audit-gate/proof_gate.state" "$REPO/.claude/audit-gate/proof_gate.log"
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-scoped","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã giao. Gate exit 0, ảnh: không cần — backend
$REPORT" | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
why() { echo "rc=$1 err=$(grep -m1 'Cổng:' "$TMP/err" || head -2 "$TMP/err" | tr '\n' ' ')"; }
plog() { grep -q "$1" "$REPO/.claude/audit-gate/proof_gate.log" 2>/dev/null; }
trunk() { git -C "$REPO" config devkit.trunkMode "$1"; }

# tiền đề: dấu vân tay dựng tay = cái push_gate dựng lại từ head (cây sạch, dirty rỗng)
pre="$(python3 - "$DEVKIT_DIR/bin" "$REPO" <<'PY'
import subprocess, sys
sys.path.insert(0, sys.argv[1]); import push_gate, tree_fp
r = sys.argv[2]; head = subprocess.run(["git", "-C", r, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
print("OK" if tree_fp.tree_fingerprint(r) == push_gate.tested_fingerprint(r, r, head, {}, "HEAD") else "DIFF")
PY
)"
[ "$pre" = OK ] || { echo "setup: tree_fingerprint khác tested_fingerprint ($pre)"; exit 1; }
turn_start
trunk false   # các đường cứu theo kho cây (trunk mode) tắt, trừ ca kho scoped

# ── e. đối chứng: biên nhận --full cũ chạy như trước ──
reset; push; [ "$PUSH_RC" = 2 ] || fail "e tiền đề: không biên nhận mà push qua"
mk "$FULL" full >/dev/null; logline full
push; rc=$PUSH_RC; [ "$rc" = 0 ] && ok "e push_gate nhận biên nhận --full + dòng mode full" || fail "e push_gate từ chối biên nhận --full ($rc: $PUSH_OUT)"
stop; rc=$?; [ "$rc" = 0 ] && ok "e proof_gate nhận biên nhận --full" || fail "e proof_gate chặn biên nhận --full ($(why $rc))"
reset; mk "$FULL" full >/dev/null; logline scoped
push; rc=$PUSH_RC; [ "$rc" = 2 ] && ok "e2 biên nhận --full với chỉ dòng mode scoped: push bị chặn" || fail "e2 dòng mode scoped mở được biên nhận --full"

# ── a. biên nhận scoped đúng cây + dòng mode scoped ──
reset; mk "$SCOPED" scoped >/dev/null; logline scoped
push; rc=$PUSH_RC; [ "$rc" = 0 ] && ok "a push_gate nhận scoped_pass.json + dòng mode scoped" || fail "a push_gate từ chối biên nhận scoped ($rc: $PUSH_OUT)"
stop; rc=$?
[ "$rc" = 0 ] && plog "scoped-receipt" && ok "a proof_gate nhận scoped_pass.json (log scoped-receipt)" \
  || fail "a proof_gate không nhận biên nhận scoped ($(why $rc))"
# kho theo cây: main, trunk mode bật, chỉ còn mục scoped_receipts/<fp>.json
reset; trunk true
stop; rc=$?; [ "$rc" = 2 ] || fail "a-store đối chứng: không biên nhận nào mà XONG qua ($(why $rc))"
mk store scoped >/dev/null
stop; rc=$?
[ "$rc" = 0 ] && plog "scoped-receipt" && ok "a-store proof_gate nhận mục scoped_receipts/ ở main (trunk mode)" \
  || fail "a-store proof_gate không nhận mục scoped_receipts/ ($(why $rc))"
reset; mk store scoped >/dev/null
f="$(ls "$SSTORE"/*.json)"; python3 -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); r["scope"]="task"; json.dump(r,open(p,"w"))' "$f"
stop; rc=$?; [ "$rc" = 2 ] && ok "a-store mục scoped_receipts/ mang scope task: XONG bị chặn" || fail "a-store nhận mục scope task ($(why $rc))"
trunk false

# ── c. scope task / thiếu scope trong scoped_pass.json ──
reset; mk "$SCOPED" task >/dev/null; logline scoped
push; rc=$PUSH_RC; [ "$rc" = 2 ] && ok "c push_gate từ chối scoped_pass.json scope task" || fail "c push_gate nhận scope task"
stop; rc=$?; [ "$rc" = 2 ] && ok "c proof_gate từ chối scoped_pass.json scope task" || fail "c proof_gate nhận scope task ($(why $rc))"
reset; mk "$SCOPED" none >/dev/null; logline scoped
push; rc=$PUSH_RC; [ "$rc" = 2 ] && ok "c2 push_gate từ chối scoped_pass.json thiếu scope" || fail "c2 push_gate nhận scoped_pass.json thiếu scope"
reset; mk "$FULL" scoped >/dev/null; logline scoped; logline full
push; rc=$PUSH_RC; [ "$rc" = 2 ] && ok "c3 full_pass.json mang scope scoped vẫn bị từ chối (đúng file, đúng scope)" || fail "c3 full_pass.json scope scoped lọt"

# ── d. thiếu dòng run-log mode scoped ──
reset; mk "$SCOPED" scoped >/dev/null; logline impacted
push; rc=$PUSH_RC; [ "$rc" = 2 ] && ok "d push_gate từ chối biên nhận scoped chỉ có dòng impacted" || fail "d push_gate nhận scoped thiếu dòng mode scoped"
logline full
push; rc=$PUSH_RC; [ "$rc" = 2 ] && ok "d2 dòng mode full không mở biên nhận scoped" || fail "d2 dòng mode full mở biên nhận scoped"

# ── hai lý do: full hỏng + scoped hỏng ──
reset; mk "$FULL" full >/dev/null; python3 -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); r["fingerprint"]="f"*24; json.dump(r,open(p,"w"))' "$FULL"
mk "$SCOPED" task >/dev/null; logline full; logline scoped
push; rc=$PUSH_RC
case "$PUSH_OUT" in *fingerprint*scoped*task*|*scoped*task*fingerprint*) [ "$rc" = 2 ] && ok "thông báo chặn nêu cả lý do full lẫn scoped" || fail "hai biên nhận hỏng mà push qua" ;;
  *) fail "thông báo chặn thiếu một trong hai lý do (rc=$rc): $PUSH_OUT" ;; esac

# ── f. biên nhận --full hợp lệ của head cũ (không phủ commit mới) + scoped phủ HEAD ──
reset; mk "$FULL" full HEAD~1 >/dev/null; logline full
push; rc=$PUSH_RC; [ "$rc" = 2 ] || fail "f tiền đề: biên nhận --full của HEAD~1 lại phủ commit mới"
mk "$SCOPED" scoped >/dev/null; logline scoped
push; rc=$PUSH_RC; [ "$rc" = 0 ] && ok "f full cũ không phủ, scoped phủ HEAD: push qua" || fail "f push_gate không thử scoped khi full không phủ ($rc: $PUSH_OUT)"
stop; rc=$?; [ "$rc" = 0 ] && ok "f proof_gate: full cũ lệch cây, scoped khớp: XONG qua" || fail "f proof_gate chặn ($(why $rc))"

# ── g. scoped hợp lệ nhưng cũ (head không còn trong lịch sử) không bỏ lối docs-only của nhánh không biên nhận ──
reset; mk "$SCOPED" scoped >/dev/null; logline scoped
EDIT2="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" reset -q --hard origin/main && echo "# notes" > "$REPO/NOTES.md" && git -C "$REPO" add NOTES.md && git -C "$REPO" commit -qm "docs"
push; rc=$PUSH_RC; [ "$rc" = 0 ] && ok "g scoped cũ có mặt, push chỉ docs: vẫn qua như khi không có file scoped" || fail "g file scoped cũ chặn push docs-only ($rc: $PUSH_OUT)"
git -C "$REPO" reset -q --hard "$EDIT2"

# ── h. merged_evidence (a): scoped_pass.json của worktree anh em (trunk mode, main không biên nhận, kho cây trống) ──
reset; trunk true
WT="$TMP/wt"; git -C "$REPO" worktree add -q --detach "$WT" HEAD || exit 1
WSCOPED="$(git -C "$WT" rev-parse --absolute-git-dir)/postfix-gate/scoped_pass.json"
stop; rc=$?; [ "$rc" = 2 ] || fail "h đối chứng: worktree không biên nhận mà XONG qua ($(why $rc))"
MKREPO="$WT" mk "$WSCOPED" scoped >/dev/null
stop; rc=$?
[ "$rc" = 0 ] && plog "worktree-receipt scoped" && ok "h merged_evidence (a) nhận scoped_pass.json của worktree anh em" \
  || fail "h merged_evidence (a) không nhận scoped_pass.json của worktree ($(why $rc))"
MKREPO="$WT" mk "$WSCOPED" task >/dev/null
stop; rc=$?; [ "$rc" = 2 ] && ok "h scoped_pass.json của worktree mang scope task: XONG bị chặn" || fail "h nhận scope task của worktree ($(why $rc))"
git -C "$REPO" worktree remove --force "$WT"; trunk false

# ── b. sửa 1 byte file tracked sau biên nhận scoped ──
reset; mk "$SCOPED" scoped >/dev/null; logline scoped
printf 'def ok(): return 3\n' > "$REPO/src/core.py"
stop; rc=$?; [ "$rc" = 2 ] && ok "b proof_gate chặn: file tracked đổi sau biên nhận scoped" || fail "b proof_gate nhận cây đã đổi ($(why $rc))"
git -C "$REPO" commit -qam "edit 3 sau gate"
push; rc=$PUSH_RC; [ "$rc" = 2 ] && ok "b push_gate chặn: commit sau biên nhận scoped" || fail "b push_gate cho push commit chưa gate"
trunk true; mk store scoped HEAD~1 >/dev/null
stop; rc=$?; [ "$rc" = 2 ] && ok "b proof_gate (trunk mode, kho scoped của cây cũ) vẫn chặn" || fail "b kho scoped của cây cũ cứu XONG ($(why $rc))"

# ── i. base của biên nhận scoped phải có trên đích push (biên nhận chỉ chứng minh base..cây) ──
trunk false; reset
[ "$(git -C "$REPO" rev-list --count origin/main..HEAD)" = 2 ] || fail "i tiền đề: không có 2 commit chưa push"
MKBASE="$(git -C "$REPO" rev-parse HEAD~1)" mk "$SCOPED" scoped >/dev/null; logline scoped
push; rc=$PUSH_RC
case "$PUSH_OUT" in *upstream*|*đích*) [ "$rc" = 2 ] && ok "i base là commit chưa push: push chặn, nêu lý do" || fail "i base chưa push mà push qua ($rc)" ;;
  *) fail "i base chưa push: rc=$rc, thông báo không nêu đích: $PUSH_OUT" ;; esac
reset; mk "$SCOPED" scoped >/dev/null; logline scoped
push; rc=$PUSH_RC; [ "$rc" = 0 ] && ok "i base trên upstream (origin/main): push qua" || fail "i base trên upstream mà push chặn ($rc: $PUSH_OUT)"
# i2. nhánh PR có upstream riêng, gộp origin/main (đã đi tiếp) vào nhánh rồi gate --diff origin/main: base = đỉnh origin/main, chưa có trên
#     @{u} (origin/feat) nhưng đã có trên remote ⇒ push qua
I2HEAD="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q -b feat && git -C "$REPO" push -q -u origin feat 2>/dev/null
git clone -q "$ORIGIN" "$TMP/other" 2>/dev/null && git -C "$TMP/other" config user.email t@t && git -C "$TMP/other" config user.name t
echo "def o(): return 1" > "$TMP/other/src/other.py" && git -C "$TMP/other" add src/other.py &&git -C "$TMP/other" commit -qm "main đi tiếp" && git -C "$TMP/other" push -q origin main 2>/dev/null
git -C "$REPO" fetch -q origin && git -C "$REPO" merge -q --no-edit origin/main
reset; MKBASE="$(git -C "$REPO" rev-parse origin/main)" mk "$SCOPED" scoped >/dev/null; logline scoped
push; rc=$PUSH_RC; [ "$rc" = 0 ] && ok "i2 nhánh PR gộp origin/main: base trên origin/main (không trên @{u}) ⇒ push qua" \
  || fail "i2 base trên origin/main mà push chặn ($rc: $PUSH_OUT)"
git -C "$REPO" checkout -q main 2>/dev/null; git -C "$REPO" reset -q --hard "$I2HEAD"; rm -rf "$TMP/other"

# ── k. M2: suite dùng lại theo khoá chính xác vào biên nhận scoped là UNTESTED / KEYED: push nhận (không FAIL), XONG cùng lượt nhận,
#       XONG lượt sau thì không (biên nhận lượt trước đòi mọi suite PASS — không nới)
keyed() { python3 -c 'import json,sys,time; p=sys.argv[1]; r=json.load(open(p))
if sys.argv[3:] != ["nokey"]: r["tests"].append({"id":"REG-K","status":"UNTESTED","label":"KEYED","mode":"cached"})
d=float(sys.argv[2]); r["time"]-=d; r["tested_at"]-=d; json.dump(r,open(p,"w"))' "$SCOPED" "$@"; }
# "lượt trước" tính theo mốc đầu lượt: đặt lại mốc ngay đây, không thì máy tải cao (file chạy > 30 s) làm `keyed 30` vẫn rơi vào lượt này
turn_start; reset; mk "$SCOPED" scoped >/dev/null; keyed 30 nokey; logline scoped
stop; rc=$?; [ "$rc" = 0 ] || fail "k đối chứng: biên nhận scoped lượt trước, mọi suite PASS mà XONG bị chặn ($(why $rc))"
reset; mk "$SCOPED" scoped >/dev/null; keyed 0; logline scoped
push; rc=$PUSH_RC; [ "$rc" = 0 ] && ok "k push_gate nhận biên nhận scoped có suite UNTESTED/KEYED" || fail "k push_gate từ chối suite KEYED ($rc: $PUSH_OUT)"
stop; rc=$?; [ "$rc" = 0 ] && ok "k proof_gate cùng lượt nhận biên nhận scoped có suite KEYED" || fail "k proof_gate cùng lượt chặn ($(why $rc))"
turn_start; reset; mk "$SCOPED" scoped >/dev/null; keyed 30; logline scoped
stop; rc=$?; [ "$rc" = 2 ] && ok "k proof_gate: biên nhận scoped từ lượt trước có suite KEYED bị chặn (không nới)" || fail "k proof_gate nhận KEYED của lượt trước ($(why $rc))"

# ── j. _carry_gate_receipt: full (cũ hơn) phủ HEAD của main, scoped (mới hơn) có head lạc lịch sử ⇒ chép full ──
reset
WTJ="$TMP/wtj"; git -C "$REPO" worktree add -q --detach "$WTJ" HEAD || exit 1
WGD="$(git -C "$WTJ" rev-parse --absolute-git-dir)/postfix-gate"
MKREPO="$WTJ" mk "$WGD/full_pass.json" full >/dev/null; MKREPO="$WTJ" logline full
git -C "$WTJ" commit -q --allow-empty -m "lạc lịch sử" && OFF="$(git -C "$WTJ" rev-parse HEAD)" && git -C "$WTJ" checkout -q --detach HEAD~1
sleep 1; MKREPO="$WTJ" mk "$WGD/scoped_pass.json" scoped "$OFF" >/dev/null; MKREPO="$WTJ" logline scoped
note="$(python3 - "$DEVKIT_DIR/scripts/git/worktree.py" "$REPO" "$WTJ" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("wt_carry", sys.argv[1]); m = importlib.util.module_from_spec(spec)
sys.modules["wt_carry"] = m; spec.loader.exec_module(m)
print(m._carry_gate_receipt(sys.argv[2], sys.argv[3]))
PY
)"
if [ -f "$FULL" ] && [ ! -e "$SCOPED" ] && grep -q carried_from "$FULL"; then ok "j carry chép biên nhận phủ HEAD (full), không chép scoped mới hơn lạc lịch sử"
else fail "j carry chọn sai biên nhận: full=$([ -f "$FULL" ] && echo có || echo không) scoped=$([ -e "$SCOPED" ] && echo có || echo không) ($note)"; fi
git -C "$REPO" worktree remove --force "$WTJ"; reset

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
