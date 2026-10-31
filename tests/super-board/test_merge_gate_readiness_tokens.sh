#!/usr/bin/env bash
# 19/10 (issue #98, 2 điểm OCR mức thấp của PR #97): bước kiểm "scratch không có post-fix-gate.py" của merge gate (exit 9,
# verification-readiness) chỉ nhận đường dẫn đứng sau một dấu cách. Lệnh verify viết `python3 "./.agents/…"`, `cd x &&./…` hay
# `bash -c ".agents/…"` lọt qua, verify chạy rồi đỏ vì thiếu file và thẻ bị đẩy về Build (exit 11) dù PR không sai gì. Dòng exit 9
# lại mang tiền tố "[merge-gate #N] ", trong khi super-board-codex-lane.sh đòi detail bắt đầu đúng "verification-readiness:".
# Luật: nhận đường dẫn tương đối gốc scratch ở ranh giới token (đầu lệnh, dấu cách, ngoặc kép/đơn, ( ; & | =), có hay không "./";
# đường dẫn tuyệt đối hay ../ vẫn chạy như cũ; dòng exit 9 bắt đầu bằng "verification-readiness:". Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-readiness-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/issue-5-review"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n.agents/devkit\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x                 # không DevKit nào: scratch sẽ thiếu post-fix-gate.py
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
echo "$H" > "$TMP/pr5.head"
# post-fix-gate giả ở đường dẫn TUYỆT ĐỐI: chạy như cũ (không phải exit 9), in dấu rồi đỏ để gate dừng trước merge
mkdir -p "$TMP/abs/.agents/devkit/bin"
printf 'import sys\nprint("ABS-GATE-R" "AN")\nsys.exit(1)\n' > "$TMP/abs/.agents/devkit/bin/post-fix-gate.py"

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
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

i=0
gate_with() {  # gate_with <verify command>: chạy gate với đúng một lệnh verify; log ở $TMP/g$i.log, mã thoát ở $rc
  i=$((i + 1))
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[sys.argv[1]]}))' "$1" > "$TMP/cfg$i.json"
  ( cd "$WT" && bash "$GATE" --config "$TMP/cfg$i.json" --pr 5 --expect-head "$H" ) >"$TMP/g$i.log" 2>&1; rc=$?
}
for cmd in 'python3 .agents/devkit/bin/post-fix-gate.py --run-tests' \
           'python3 "./.agents/devkit/bin/post-fix-gate.py" --run-tests' \
           "python3 '.agents/devkit/bin/post-fix-gate.py' --run-tests" \
           'cd . &&./universal-agent-devkit/bin/post-fix-gate.py --run-tests' \
           'bash -c ".agents/devkit/bin/post-fix-gate.py --run-tests"' \
           'true;python3 universal-agent-devkit/bin/post-fix-gate.py' \
           'python3 .agents/devkit/bin/post-fix-gate.py>verify.log' \
           '{ .agents/devkit/bin/post-fix-gate.py; }'; do
  gate_with "$cmd"
  if [ "$rc" -eq 9 ] && grep -q '^verification-readiness: ' "$TMP/g$i.log"; then
    ok "exit 9 with a line starting 'verification-readiness:' for: $cmd"
  else
    fail "want exit 9 + '^verification-readiness:' for: $cmd (got exit $rc): $(grep -a -m1 -E 'verification-readiness|FAILED|verify' "$TMP/g$i.log")"
  fi
done
gate_with "python3 $TMP/abs/.agents/devkit/bin/post-fix-gate.py --run-tests"
[ "$rc" -ne 9 ] && grep -q "ABS-GATE-RAN" "$TMP/g$i.log" && ok "an absolute path still runs as written (exit $rc, not 9)" \
  || fail "absolute path treated as missing from the scratch (exit $rc)"
gate_with 'python3 ../x/.agents/devkit/bin/post-fix-gate.py --run-tests'
# verify thật sự chạy rồi đỏ (exit 11 + dòng FAILED), không phải gate hỏng vì lý do khác trước bước readiness (OCR)
[ "$rc" -eq 11 ] && grep -q 'FAILED: python3 ../x/' "$TMP/g$i.log" && ok "a ../ path is not taken for the scratch's own post-fix-gate.py: verify ran (exit 11)" \
  || fail "a ../ path: want the verify to run and fail with exit 11 (got exit $rc)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_readiness_tokens: PASS"; exit 0; } || { echo "test_merge_gate_readiness_tokens: FAIL ($FAILS)"; exit 1; }
