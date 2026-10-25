#!/usr/bin/env bash
# Issue #226 gap 7: biên nhận verify theo cây gộp. Hành vi kiểm:
#   - verify xanh ghi biên nhận khoá theo tree SHA của cây gộp + bộ lệnh verify; lượt gate sau trên đúng cây và đúng lệnh bỏ verify.
#   - base đổi (cây gộp khác) hoặc bộ lệnh đổi: verify chạy lại đủ.
#   - verify đỏ không ghi biên nhận: lần sau vẫn verify.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-verified-tree-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.agents"
echo '[]' > "$R/.agents/regression_matrix.active.json"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x

mkpr() {
  local n="$1" h
  git -C "$R" branch -q --no-track "issue-$n-x" main
  git -C "$WT" checkout -q "issue-$n-x"
  echo "$n" > "$WT/f$n"; git -C "$WT" add "f$n"; git -C "$WT" commit -qm "card$n"
  git -C "$R" push -q origin "issue-$n-x"
  h=$(git -C "$R" rev-parse "issue-$n-x")
  git -C "$R" diff "$h~1" "$h" > "$TMP/pr$n.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$n" > "$TMP/pr$n.meta"
  echo "$h" > "$TMP/pr$n.head"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"--json body"*) jq -r '.body // ""' "$FAKE_DIR/pr$n.meta" ;;   # the pre-merge recheck of a card branch without AC (W8)
  *" pr view "*"--json title"*) echo "fix: t" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

# gate giả: mỗi lần chạy thêm một dòng vào $TMP/runs-<tag>; exit theo file $TMP/verify-rc (mặc định 0)
mkdir -p "$TMP/g"
cat > "$TMP/g/post-fix-gate.py" <<PY
import os, sys
open("$TMP/runs", "a").write("run\n")
sys.exit(int(open("$TMP/verify-rc").read()) if os.path.exists("$TMP/verify-rc") else 0)
PY

runs() { grep -c run "$TMP/runs" 2>/dev/null || echo 0; }
gate() {  # $1 = PR, $2 = lệnh verify; ghi GATE_RC
  local n="$1" cfg="$TMP/cfg$1.json"
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"project":{"owner":"o","number":1},"verify_commands":[sys.argv[1]]}))' "$2" > "$cfg"
  ( cd "$WT" && bash "$GATE" --config "$cfg" --pr "$n" --expect-head "$(cat "$TMP/pr$n.head")" ) >"$TMP/gate$n.log" 2>&1
  GATE_RC=$?
}
CMD="python3 $TMP/g/post-fix-gate.py"

mkpr 41
gate 41 "$CMD"; A=$(runs)
[ "$GATE_RC" -eq 0 ] && [ "$A" -eq 1 ] && ok "first merge gate verifies once (rc=0, runs=1)" || fail "first run (rc=$GATE_RC runs=$A, want 0 and 1): $(tail -3 "$TMP/gate41.log")"

gate 41 "$CMD"; B=$(runs)
[ "$GATE_RC" -eq 0 ] && [ "$B" -eq 1 ] && grep -q "already verified" "$TMP/gate41.log" \
  && ok "same merged tree and same commands: verify skipped (runs stays 1)" \
  || fail "second run on the same tree (rc=$GATE_RC runs=$B, want 0 and 1): $(tail -3 "$TMP/gate41.log")"

gate 41 "$CMD --brief"; C=$(runs)
[ "$GATE_RC" -eq 0 ] && [ "$C" -eq 2 ] \
  && ok "another verify command set: verified again (runs=2)" \
  || fail "changed commands (rc=$GATE_RC runs=$C, want 0 and 2): $(tail -3 "$TMP/gate41.log")"

# base đổi: cây gộp khác → verify lại
git -C "$R" checkout -q main 2>/dev/null; echo b > "$R/b"; git -C "$R" add b; git -C "$R" commit -qm "base moves"; git -C "$R" push -q origin main
gate 41 "$CMD"; D=$(runs)
[ "$GATE_RC" -eq 0 ] && [ "$D" -eq 3 ] \
  && ok "base moved (merged tree changed): verified again (runs=3)" \
  || fail "base moved (rc=$GATE_RC runs=$D, want 0 and 3): $(tail -3 "$TMP/gate41.log")"

# verify đỏ không ghi biên nhận
mkpr 42
echo 1 > "$TMP/verify-rc"
gate 42 "$CMD"; E1=$(runs)
[ "$GATE_RC" -eq 11 ] && [ "$E1" -eq 4 ] && ok "red verify: exit 11 (runs=4)" || fail "red verify (rc=$GATE_RC runs=$E1, want 11 and 4)"
gate 42 "$CMD"; E2=$(runs)
[ "$GATE_RC" -eq 11 ] && [ "$E2" -eq 5 ] && ok "red verify left no receipt: verifies again (runs=5)" || fail "red again (rc=$GATE_RC runs=$E2, want 11 and 5)"

# R1: QA ghi biên nhận (verify-cmd --record) trên cây gộp sạch → merge gate lần đầu bỏ verify
echo 0 > "$TMP/verify-rc"
mkpr 43
QA="$R/.claude/worktrees/qa-43"; git -C "$R" worktree add -q --detach "$QA" "issue-43-x"
git -C "$QA" merge -q --no-edit origin/main
mkcfg() { python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":"."},"verify_commands":[sys.argv[1]]}))' "$2" > "$1"; }
mkcfg "$TMP/cfgqa.json" "$CMD"
( cd "$QA" && bash "$ROOT/.claude/bin/super-board-verify-cmd.sh" --config "$TMP/cfgqa.json" --record ) >"$TMP/qa.out" 2>&1; QRC=$?
BEFORE=$(runs)   # --record chạy lệnh verify một lần; từ đây merge gate không được chạy thêm
[ "$QRC" -eq 0 ] && grep -q "recorded" "$TMP/qa.out" && ok "QA --record on a clean merged tree writes a receipt" || fail "QA record (rc=$QRC): $(cat "$TMP/qa.out")"
gate 43 "$CMD"; F=$(runs)
[ "$GATE_RC" -eq 0 ] && [ "$F" -eq "$BEFORE" ] && ok "QA recorded this exact tree: merge gate skips verify (runs unchanged)" || fail "gate after QA record (rc=$GATE_RC runs=$F, want 0 and $BEFORE): $(tail -3 "$TMP/gate43.log")"
echo dirty > "$QA/dirty"
( cd "$QA" && bash "$ROOT/.claude/bin/super-board-verify-cmd.sh" --config "$TMP/cfgqa.json" --record ) >/dev/null 2>&1; DRC=$?
[ "$DRC" -eq 65 ] && ok "QA --record refuses a dirty tree (exit 65)" || fail "dirty record (rc=$DRC, want 65)"
rm -f "$QA/dirty"

# R3: khoá dùng lệnh đã chèn cờ (--diff/--force-full) ở cả hai phía: QA ghi → gate bỏ verify
PFG="python3 $TMP/g/post-fix-gate.py --run-tests"
mkpr 44
QB="$R/.claude/worktrees/qa-44"; git -C "$R" worktree add -q --detach "$QB" "issue-44-x"; git -C "$QB" merge -q --no-edit origin/main
mkcfg "$TMP/cfgqb.json" "$PFG"
( cd "$QB" && bash "$ROOT/.claude/bin/super-board-verify-cmd.sh" --config "$TMP/cfgqb.json" --record ) >/dev/null 2>&1
BEFORE=$(runs); gate 44 "$PFG"; G=$(runs)
[ "$GATE_RC" -eq 0 ] && [ "$G" -eq "$BEFORE" ] && ok "key uses the injected commands on both sides: gate skips (runs unchanged)" || fail "injected-flags key (rc=$GATE_RC runs=$G, want 0 and $BEFORE)"

# R5: thông báo đúng nguồn bằng chứng; --record từ chối cây chưa gộp origin/<base> hiện tại; verify_commands rỗng không lỗi bash 3.2
grep -q "merge train proved" "$TMP/gate43.log" && fail "receipt skip is reported as 'merge train proved' (gate43.log)" || ok "receipt skip does not claim the merge train proved it"
mkpr 45
QC="$R/.claude/worktrees/qa-45"; git -C "$R" worktree add -q --detach "$QC" "issue-45-x"
echo c > "$R/c"; git -C "$R" add c; git -C "$R" commit -qm "base moves again"; git -C "$R" push -q origin main
mkcfg "$TMP/cfgqc.json" "$CMD"
( cd "$QC" && bash "$ROOT/.claude/bin/super-board-verify-cmd.sh" --config "$TMP/cfgqc.json" --record ) >"$TMP/qc.out" 2>&1; CRC=$?
[ "$CRC" -eq 65 ] && ok "QA --record refuses a tree that lacks the current origin/<base> (exit 65)" || fail "stale-base record (rc=$CRC, want 65): $(cat "$TMP/qc.out")"
python3 -c 'import json; print(json.dumps({"base_branch":"main","repo":{"path":"."},"verify_commands":[]}))' > "$TMP/cfgempty.json"
( cd "$QC" && git merge -q --no-edit origin/main && /bin/bash "$ROOT/.claude/bin/super-board-verify-cmd.sh" --config "$TMP/cfgempty.json" --record ) >"$TMP/qe.out" 2>&1; ERC=$?
[ "$ERC" -eq 0 ] && ok "QA --record with no verify commands exits 0 without a receipt" || fail "empty-commands record (rc=$ERC, want 0): $(cat "$TMP/qe.out")"

# OCR 24/10: --record chạy lệnh verify và chỉ ghi biên nhận khi tất cả exit 0
mkpr 46
QD="$R/.claude/worktrees/qa-46"; git -C "$R" worktree add -q --detach "$QD" "issue-46-x"; git -C "$QD" merge -q --no-edit origin/main
echo 1 > "$TMP/verify-rc"
mkcfg "$TMP/cfgqd.json" "$CMD"
N0=$(ls "$R/.git/super-board/verified-trees" | wc -l)
( cd "$QD" && bash "$ROOT/.claude/bin/super-board-verify-cmd.sh" --config "$TMP/cfgqd.json" --record ) >"$TMP/qd.out" 2>&1; XRC=$?
N1=$(ls "$R/.git/super-board/verified-trees" | wc -l)
[ "$XRC" -eq 11 ] && [ "$N1" -eq "$N0" ] && ok "--record with a red verify command: exit 11, no receipt" || fail "red record (rc=$XRC receipts $N0->$N1, want 11 and unchanged): $(tail -3 "$TMP/qd.out")"
echo 0 > "$TMP/verify-rc"

# OCR 24/10: đổi module cạnh post-fix-gate.py (suite_cache.py…) đổi khoá; thiếu công cụ sha256 thì không có đường dẫn
K="$TMP/kitrepo"; mkdir -p "$K/.agents/devkit/bin"; git init -q "$K"; echo x > "$K/.agents/devkit/bin/post-fix-gate.py"; echo m1 > "$K/.agents/devkit/bin/suite_cache.py"
. "$ROOT/.claude/bin/super-board-verify-flags.sh"
K1=$(sb_verified_tree_receipt tree1 main "$K" "$CMD"); echo m2 > "$K/.agents/devkit/bin/suite_cache.py"; K2=$(sb_verified_tree_receipt tree1 main "$K" "$CMD")
[ -n "$K1" ] && [ "$K1" != "$K2" ] && ok "editing a kit module next to post-fix-gate.py changes the receipt key" || fail "kit module edit left the key unchanged ($K1 vs $K2)"
NOSHA="$TMP/nosha"; mkdir -p "$NOSHA"; for t in git cut sort dirname; do ln -s "$(command -v $t)" "$NOSHA/$t"; done
K3=$(PATH="$NOSHA" sb_verified_tree_receipt tree1 main "$K" "$CMD"); [ -z "$K3" ] && ok "no sha256 tool: no receipt path (never a bare directory)" || fail "no sha256 tool printed '$K3'"

# OCR 24/10: biên nhận cũ hơn 14 ngày bị dọn khi một verify xanh ghi biên nhận mới
VT="$R/.git/super-board/verified-trees"; : > "$VT/stale-old"; touch -t 202001010000 "$VT/stale-old"
mkpr 47; gate 47 "$CMD"
[ ! -e "$VT/stale-old" ] && ok "a green verify prunes receipts older than 14 days" || fail "stale receipt survived the prune"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_verified_tree: all passed" || { echo "❌ test_merge_gate_verified_tree: $FAILS failed"; exit 1; }
