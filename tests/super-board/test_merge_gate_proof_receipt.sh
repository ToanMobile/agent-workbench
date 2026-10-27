#!/usr/bin/env bash
# Test đầu-cuối: super-board-merge-gate.sh THẬT (gh giả, offline) ghi biên nhận merge vào <git common dir>/postfix-gate/merge_receipts, và
# hooks/proof_gate.sh đọc đúng biên nhận đó (27/10: lượt làm đúng luật — gate impacted, PR gộp qua merge gate chạy nền ghi output vào file,
# push `git push -u origin X 2>&1 | tail -4` — vẫn bị chặn XONG với lời đòi --full).
#   1 gate gộp PR từ worktree của phiên (output ra file), biên nhận có pr / head / base / verified_tree / squash / session; worktree bị gỡ,
#     main kéo về origin, còn file bẩn của phiên khác: proof_gate cho qua
#   1b cùng lượt, Stop của phiên khác: chặn
#   2 gate chạy không có id phiên trong môi trường: biên nhận không có session, proof_gate chặn
#   3 kho biên nhận không ghi được: gate vẫn exit 0 và vẫn gộp (biên nhận không bao giờ làm hỏng merge)
#   4 phản hồi gh pr merge mất, GitHub xác nhận MERGED: biên nhận vẫn ghi, squash được fetch về, phiên ở worktree tại H: cho qua
# Schema biên nhận đi giữa hai file này: ca chặn dựng tay ở universal-agent-devkit/tests/gates/test_proof_gate_merge_receipt.sh.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
HOOK="$ROOT/universal-agent-devkit/hooks/proof_gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
unset WORKTREE_TRUNK_MODE CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID DEVKIT_SESSION_ID SB_MERGE_QUEUE SB_BOARD_WORKER SB_MERGE_CALLER
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-proof-receipt.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; TR="$TMP/transcript.jsonl"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
mkdir -p "$R/.agents" "$R/docs"
printf '.claude/\n' > "$R/.gitignore"
echo '{"profile":"backend"}' > "$R/.agents/active-profile.json"   # backend: proof_gate chỉ xét cổng, không cần ảnh
echo a > "$R/a"; git -C "$R" add .gitignore a .agents; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main
git -C "$R" merge-tree --write-tree HEAD HEAD >/dev/null 2>&1 || { echo "skip: git < 2.38 has no merge-tree --write-tree"; exit 0; }
STORE="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)/postfix-gate/merge_receipts"

# gh giả: `pr merge` mô phỏng SQUASH phía server như GitHub (commit mới cùng cây gộp, cha là main, dựng ngay trong repo origin: máy này chỉ
# có nó sau một lần fetch) và nhớ sha; `--json mergeCommit` trả sha đó. FAKE_LOST=1: gộp xong nhưng phản hồi mất (exit 1), pr_state = MERGED.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*)
    if [ -n "${FAKE_LOST:-}" ] && [ -s "$FAKE_DIR/pr$n.squash" ]; then
      printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$(cat "$FAKE_DIR/pr$n.squash")" "$head"
    else printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head"; fi ;;
  *" pr view "*"--json mergeCommit "*) cat "$FAKE_DIR/pr$n.squash" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) o=$(git --git-dir="$FAKE_ORIGIN" rev-parse main) \
                    && tree=$(git --git-dir="$FAKE_ORIGIN" merge-tree --write-tree "$o" "$head") \
                    && sq=$(git --git-dir="$FAKE_ORIGIN" -c user.name=github -c user.email=gh@example.invalid commit-tree "$tree" -p "$o" -m "squash #$n (#$n)") \
                    && git --git-dir="$FAKE_ORIGIN" update-ref refs/heads/main "$sq" "$o" && echo "$sq" > "$FAKE_DIR/pr$n.squash" \
                    && if [ -n "${FAKE_LOST:-}" ]; then echo "HTTP 502: response lost" >&2; exit 1; fi && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_ORIGIN="$O"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_MERGE_RECHECK_DELAY_S=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}' > "$CFG"

# card <N>: worktree của phiên ở .claude/worktrees/card-N (như EnterWorktree), nhánh issue-N-x một commit, đã push; gh giả biết nó.
card() {
  local wt="$R/.claude/worktrees/card-$1"
  git -C "$R" fetch -q origin && git -C "$R" worktree add -q -b "issue-$1-x" "$wt" origin/main || return 1
  echo "$1" > "$wt/f$1"; git -C "$wt" add "f$1"; git -C "$wt" commit -qm "card $1"
  git -C "$wt" push -q -u origin "issue-$1-x" || return 1
  git -C "$wt" rev-parse HEAD > "$TMP/pr$1.head"
  git -C "$wt" diff origin/main HEAD > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$1" > "$TMP/pr$1.meta"
}
# gate <N> [session]: chạy merge gate từ worktree của thẻ, output vào file (như lượt chạy nền 27/10). Exit của gate.
gate() { ( cd "$R/.claude/worktrees/card-$1" && env ${2:+CLAUDE_CODE_SESSION_ID="$2"} bash "$GATE" --config "$CFG" --pr "$1" \
           --expect-head "$(cat "$TMP/pr$1.head")" --standalone ) >"$TMP/gate$1.log" 2>&1; }
# exit_worktree <N>: ExitWorktree remove (nếu bước dọn của gate chưa gỡ), rồi main kéo về origin.
exit_worktree() { git -C "$R" worktree remove --force "$R/.claude/worktrees/card-$1" 2>/dev/null; git -C "$R" pull -q --ff-only origin main; }

# Lượt mới: mốc lượt lùi 2 s, nên biên nhận của ca trước (vài giây trước) còn "trong lượt"; xoá kho để mỗi ca chỉ thấy biên nhận của nó.
turn_start() { rm -rf "$STORE"; python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"làm thẻ rồi gộp"}}))' > "$TR"; sleep 1; }
bash_cmd() { python3 -c 'import datetime,json,sys
t=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
n=sum(1 for _ in open(sys.argv[3]))
print(json.dumps({"type":"assistant","timestamp":t,"cwd":sys.argv[5],"message":{"role":"assistant","content":[
  {"type":"tool_use","id":"tu%d" % n,"name":"Bash","input":{"command":sys.argv[1]}}]}}))
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":[
  {"type":"tool_result","tool_use_id":"tu%d" % n,"content":sys.argv[2],"is_error":sys.argv[4] == "err"}]}}))' "$1" "$2" "$TR" "${3:-}" "$R" >> "$TR.new" \
  && cat "$TR.new" >> "$TR" && rm -f "$TR.new"; }
incident_cmds() {
  bash_cmd "git push -u origin issue-$1-x 2>&1 | tail -4" "branch 'issue-$1-x' set up to track 'origin/issue-$1-x'." \
    && bash_cmd "git push origin --delete issue-old-x" "BLOCKED by block-dangerous-git" err \
    && bash_cmd ".claude/bin/super-board-merge-gate.sh --config c.json --pr $1 --expect-head $(cat "$TMP/pr$1.head") --standalone > $TMP/bg$1.log 2>&1; echo \"exit=\$?\" >> $TMP/bg$1.log" \
                "Command running in background with ID: b$1"
}
stop() {   # Stop với XONG; $1 = session của Stop, $2 = cây xét (mặc định main checkout)
  rm -f "${2:-$R}/.claude/audit-gate/proof_gate.state"
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":False}))' "$TR" "XONG
Đã gộp PR qua merge gate. Gate exit 0, ảnh: không cần — backend
1. Đã fix: lỗi X, RED→GREEN.
2. Chặn bug cũ: REG-1 PASS.
3. Nguy cơ bug mới: đã rà caller.
4. An toàn mã nguồn: secret 0." "$1" \
    | PROOF_GATE_ALLOW_LOCAL_ORIGIN=1 CLAUDE_PROJECT_DIR="${2:-$R}" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
why() { echo "rc=$1 err=$(head -3 "$TMP/err" | tr '\n' ' ')"; }

# ── 1. lượt thật: gate gộp từ worktree (output ra file), worktree gỡ, main về origin, file bẩn của phiên khác ở main.
turn_start; card 7 && incident_cmds 7 || fail "1: setup"
gate 7 s-m; rc=$?
[ "$rc" -eq 0 ] && grep -q "merged $(cat "$TMP/pr7.head")" "$TMP/gate7.log" && ok "1: gate merged PR #7 (exit 0)" || fail "1: gate exit $rc: $(tail -5 "$TMP/gate7.log")"
exit_worktree 7; echo wip > "$R/docs/foreign.md"
RF="$STORE/7-$(cat "$TMP/pr7.head").json"
python3 - "$RF" "$(cat "$TMP/pr7.head")" "$(git -C "$R" rev-parse origin/main)" <<'PY' && ok "1: receipt holds pr, head, base, verified_tree, squash, session" || fail "1: receipt missing or wrong: $(cat "$RF" 2>&1 | head -c 400)"
import json, re, sys, time
r = json.load(open(sys.argv[1])); h, sq = sys.argv[2], sys.argv[3]
assert r["pr"] == 7 and r["head"] == h and r["session"] == "s-m" and r["squash"] == sq, r
assert all(re.fullmatch(r"[0-9a-f]{40}", r[k]) for k in ("base", "verified_tree")), r
assert abs(time.time() - r["time"]) < 600, r
PY
[ "$(git -C "$R" rev-parse "$(cat "$TMP/pr7.head" 2>/dev/null)^{tree}" 2>/dev/null)" = "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verified_tree"])' "$RF" 2>/dev/null)" ] \
  && ok "1: verified_tree = the tree the gate verified (PR not behind: tree of its head)" || fail "1: verified_tree is not the head's tree"
stop s-m; rc=$?
[ "$rc" -eq 0 ] && ok "1: proof_gate accepts the gate's receipt: XONG allowed" || fail "1: proof_gate blocked ($(why $rc))"
grep -q "merge-receipt pr=7" "$R/.claude/audit-gate/proof_gate.log" 2>/dev/null && ok "1: logged as merge-receipt" || fail "1: no merge-receipt log line"
# ── 1b. cùng lượt, Stop của phiên khác: biên nhận không phải của nó, chặn.
stop s-other; rc=$?
[ "$rc" -eq 2 ] && grep -q "Cổng:" "$TMP/err" && ok "1b: another session's Stop: blocked" || fail "1b: foreign session accepted ($(why $rc))"
rm -f "$R/docs/foreign.md"

# ── 2. gate chạy không có id phiên: biên nhận session rỗng, chặn.
turn_start; card 8 && incident_cmds 8 || fail "2: setup"
gate 8; rc=$?
[ "$rc" -eq 0 ] && ok "2: gate merged PR #8 without a session id (exit 0)" || fail "2: gate exit $rc: $(tail -5 "$TMP/gate8.log")"
exit_worktree 8
stop s-m; rc=$?
[ "$rc" -eq 2 ] && grep -q "Cổng:" "$TMP/err" && ok "2: receipt without a session id: blocked" || fail "2: session-less receipt accepted ($(why $rc))"

# ── 3. kho biên nhận không ghi được (postfix-gate là một file): gate vẫn gộp, exit 0.
turn_start; card 9 || fail "3: setup"
GD="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)"; rm -rf "$GD/postfix-gate"; : > "$GD/postfix-gate"
gate 9 s-m; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$R" ls-remote origin refs/heads/main | cut -f1)" = "$(cat "$TMP/pr9.squash" 2>/dev/null)" ] \
  && ok "3: unwritable receipt store: gate still merged (exit 0)" || fail "3: gate exit $rc: $(tail -5 "$TMP/gate9.log")"
rm -f "$GD/postfix-gate"

# ── 4 (plan review T0062). gh pr merge mất phản hồi, GitHub xác nhận MERGED: gate ghi biên nhận (squash lấy từ pr_state) và lấy squash về;
#    phiên vẫn ở worktree tại H (không kéo main): proof_gate cho qua.
turn_start; card 10 && incident_cmds 10 || fail "4: setup"
FAKE_LOST=1 gate 10 s-m; rc=$?
[ "$rc" -eq 0 ] && grep -q "merge response was lost" "$TMP/gate10.log" && ok "4: lost merge response, GitHub confirms: gate exit 0" \
  || fail "4: gate exit $rc: $(tail -5 "$TMP/gate10.log")"
python3 - "$STORE/10-$(cat "$TMP/pr10.head").json" "$(cat "$TMP/pr10.squash" 2>/dev/null)" <<'PY' && ok "4: receipt carries the squash from pr_state" || fail "4: receipt missing or squash wrong"
import json, sys
r = json.load(open(sys.argv[1])); assert r["squash"] == sys.argv[2] and r["session"] == "s-m", r
PY
git -C "$R" cat-file -e "$(cat "$TMP/pr10.squash" 2>/dev/null)^{commit}" 2>/dev/null && ok "4: the squash was fetched into the shared object store" || fail "4: squash not fetched"
stop s-m "$R/.claude/worktrees/card-10"; rc=$?
[ "$rc" -eq 0 ] && ok "4: worktree at H after a lost merge response: XONG allowed" || fail "4: proof_gate blocked ($(why $rc))"
git -C "$R" worktree remove --force "$R/.claude/worktrees/card-10" 2>/dev/null

if [ "$FAILS" -ne 0 ]; then echo "merge gate proof receipt: $FAILS FAILED"; exit 1; fi
echo "merge gate proof receipt: all checks passed"
