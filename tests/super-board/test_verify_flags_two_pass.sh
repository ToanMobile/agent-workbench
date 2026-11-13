#!/usr/bin/env bash
# #975: merge gate (super-board-merge-gate.sh) và merge train (super-board-merge-train.sh) chèn cờ verify HAI lượt:
#   cmd=$(sb_verify_inject_flags "$cmd" "$BASE"); run_cmd=$(sb_verify_inject_flags "$cmd" "$BASE" json)
# test_verify_flags_arg_span.sh và test_merge_gate_verify_flags.sh chỉ kiểm lượt một (dòng "verify:"), nên lỗi ở lượt hai (thiếu --json,
# --json sau &&, --scoped lặp, --diff bị bỏ) vẫn xanh. Ba ca hai lượt cũ của test_verify_cmd_same_as_gate.sh (bản app) chạy lại ở đây,
# qua script THẬT: post-fix-gate.py giả ghi argv nó nhận được (= lệnh run_cmd mà gate/train thực sự chạy) rồi thoát 1 để dừng trước merge.
#   c1  --scoped --run-tests        ⇒ --scoped --run-tests --diff origin/main --json
#   c2  --run-tests && true         ⇒ --json --diff origin/main --scoped --run-tests (cờ trước &&)
#   c3  --full --run-tests          ⇒ --full --run-tests --diff origin/main --json
# Khung gate như test_merge_gate_verify_flags.sh, khung train như test_merge_train_guard_retry.sh. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-vf-two-pass.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n.agents/devkit\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main

card_branch() {  # card_branch <n>: nhánh issue-<n>-x một commit trên origin/main, đã push; tệp prN.* cho gh giả
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  printf '%s\n' "$1" > "$W/issue-$1-build/f$1"
  git -C "$W/issue-$1-build" add "f$1"; git -C "$W/issue-$1-build" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff origin/main "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$1" > "$TMP/pr$1.meta"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head" 2>/dev/null)
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "fake gh: must not merge" >&2; exit 1 ;;
  *" issue list "*) echo 0 ;;
  *" issue create "*) echo "https://example.invalid/issues/900" ;;
  *" pr comment "*) ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
# Train gọi merge gate --preflight trước verify: bọc gate thật, preflight luôn ok (như test_merge_train_guard_retry.sh)
mkdir -p "$TMP/sbbin"
for f in "$ROOT"/.claude/bin/*; do ln -s "$f" "$TMP/sbbin/$(basename "$f")"; done
rm -f "$TMP/sbbin/super-board-merge-gate.sh"
cat > "$TMP/sbbin/super-board-merge-gate.sh" <<SH
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = --preflight ]; then echo "preflight: ok"; exit 0; fi
done
exec bash "$ROOT/.claude/bin/super-board-merge-gate.sh" "\$@"
SH
chmod +x "$TMP/sbbin/super-board-merge-gate.sh"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
TRAIN="$TMP/sbbin/super-board-merge-train.sh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_CALLER SB_MERGE_QUEUE

# post-fix-gate.py giả ở đường dẫn TUYỆT ĐỐI: ghi argv (mỗi lần chạy một dòng) rồi thoát 1 — gate/train dừng ở verify đỏ, không merge.
# Không nằm dưới .agents/devkit/: train kiểm sẵn sàng (scratch phải có kit) khi lệnh chỉ tới .agents/devkit/bin/post-fix-gate.py.
G="$TMP/pfg/post-fix-gate.py"
mkdir -p "$(dirname "$G")"
printf 'import sys\nwith open("%s", "a") as f:\n    f.write(" ".join(sys.argv[1:]) + "\\n")\nsys.exit(1)\n' "$TMP/argv" > "$G"

i=0
mkcfg() {  # mkcfg <verify command>: in đường dẫn config mới
  i=$((i + 1))
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[sys.argv[1]]}))' "$1" > "$TMP/cfg$i.json"
  echo "$TMP/cfg$i.json"
}
first_argv() { head -1 "$TMP/argv" 2>/dev/null; }

card_branch 5
H5=$(cat "$TMP/pr5.head")
git -C "$R" worktree add -q --detach "$W/review" origin/main

# want_gate <tên ca> <verify trong config> <argv post-fix-gate mong đợi ở lượt verify đầu>
want_gate() {
  local cfg; cfg=$(mkcfg "$2"); rm -f "$TMP/argv"
  ( cd "$W/issue-5-build" && bash "$GATE" --config "$cfg" --pr 5 --expect-head "$H5" ) >"$TMP/gate$i.log" 2>&1
  if [ "$(first_argv)" = "$3" ]; then ok "gate $1: $2"; else fail "gate $1: for [$2] want argv [$3] got [$(first_argv)] (log: $(tail -3 "$TMP/gate$i.log" | tr '\n' ';'))"; fi
}
# want_train: như want_gate qua merge train (train nối thêm --no-fail-fast vào cuối run_cmd)
n=10
want_train() {
  local cfg; cfg=$(mkcfg "$2"); rm -f "$TMP/argv"; n=$((n + 1)); card_branch "$n"
  ( cd "$W/review" && bash "$TRAIN" --config "$cfg" --prs "$n" ) >"$TMP/train$i.log" 2>&1
  if [ "$(first_argv)" = "$3" ]; then ok "train $1: $2"; else fail "train $1: for [$2] want argv [$3] got [$(first_argv)] (log: $(tail -3 "$TMP/train$i.log" | tr '\n' ';'))"; fi
}

want_gate c1 "python3 $G --scoped --run-tests" "--scoped --run-tests --diff origin/main --json"
want_gate c2 "python3 $G --run-tests && true" "--json --diff origin/main --scoped --run-tests"
want_gate c3 "python3 $G --full --run-tests" "--full --run-tests --diff origin/main --json"

want_train c1 "python3 $G --scoped --run-tests" "--scoped --run-tests --diff origin/main --json --no-fail-fast"
want_train c2 "python3 $G --run-tests && true" "--json --diff origin/main --scoped --run-tests"
want_train c3 "python3 $G --full --run-tests" "--full --run-tests --diff origin/main --json --no-fail-fast"

echo
[ "$FAILS" -eq 0 ] && { echo "test_verify_flags_two_pass: PASS"; exit 0; } || { echo "test_verify_flags_two_pass: FAIL ($FAILS)"; exit 1; }
