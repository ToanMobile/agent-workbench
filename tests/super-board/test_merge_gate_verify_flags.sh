#!/usr/bin/env bash
# 21/10 (issue #102): merge gate nối ` --diff origin/<base> --force-full` vào CUỐI lệnh verify có chữ post-fix-gate.py. Lệnh ghép
# (`… post-fix-gate.py --run-tests && npm test`, `bash -c '… post-fix-gate.py --run-tests'`) làm cờ rơi sang lệnh khác / thành
# tham số của bash: post-fix-gate chạy không --force-full và không --diff.
# Luật: cờ chèn ngay sau token post-fix-gate.py (cùng ranh giới token với bước kiểm exit 9); lệnh một lệnh như cũ (cờ ở cuối);
# lệnh không tách được token thì để nguyên. Mẫu dựng từ test_merge_gate_readiness_tokens.sh.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-verify-flags-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/issue-5-review"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n.agents/devkit\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
echo "$H" > "$TMP/pr5.head"
# post-fix-gate giả ở đường dẫn TUYỆT ĐỐI: chạy như cũ, đỏ để gate dừng trước merge
mkdir -p "$TMP/abs/.agents/devkit/bin"
printf 'import sys\nsys.exit(1)\n' > "$TMP/abs/.agents/devkit/bin/post-fix-gate.py"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "fake gh: must not merge" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

i=0
gate_with() {  # gate_with <verify command>: log ở $TMP/g$i.log; $VLINE = lệnh verify sau khi gate chèn cờ (dòng "verify:")
  i=$((i + 1))
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[sys.argv[1]]}))' "$1" > "$TMP/cfg$i.json"
  ( cd "$WT" && bash "$GATE" --config "$TMP/cfg$i.json" --pr 5 --expect-head "$H" ) >"$TMP/g$i.log" 2>&1
  VLINE=$(grep -a -m1 'verify: ' "$TMP/g$i.log" | sed 's/^.*verify: //')
}
G="$TMP/abs/.agents/devkit/bin/post-fix-gate.py"
FL='--diff origin/main --force-full'
want() {  # want <verify command> <expected command after flag insertion>
  gate_with "$1"
  if [ "$VLINE" = "$2" ]; then ok "flags placed for: $1"; else fail "for: $1 want [$2] got [$VLINE]"; fi
}
want "python3 $G --run-tests && true" "python3 $G $FL --run-tests && true"
want "bash -c 'python3 $G --run-tests'" "bash -c 'python3 $G $FL --run-tests'"
want "python3 $G --run-tests" "python3 $G --run-tests $FL"
want "python3 $G --force-full --run-tests && true" "python3 $G --diff origin/main --force-full --run-tests && true"
want "true;python3 $G>v.log" "true;python3 $G $FL>v.log"
# chữ post-fix-gate.py không tách được thành token: để nguyên, không nối cờ vào lệnh khác
want "echo post-fix-gate.pyx && true" "echo post-fix-gate.pyx && true"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_verify_flags: PASS"; exit 0; } || { echo "test_merge_gate_verify_flags: FAIL ($FAILS)"; exit 1; }
