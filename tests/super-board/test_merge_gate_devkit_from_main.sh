#!/usr/bin/env bash
# 19/10 (Goods #48, NFH #61, OfficeReader #127/#153/#159, card OfficeReader #74): merge gate chạy từ worktree của Reviewer
# (repo.path "."), nơi `.agents/devkit` bị git ignore và không có. Bước cài DevKit vào scratch chỉ tìm install.sh trong "."
# nên không cài gì, scratch thiếu `.agents/devkit/bin/post-fix-gate.py`, verify exit 2 và PR đã review xong thành thẻ Blocked.
# Luật: DevKit của main checkout được cài vào scratch khi worktree Reviewer không có nó. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-devkitmain-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/issue-5-review"; KIT="$TMP/kit"
# DevKit giả: install.sh tạo link .agents/devkit trong đích như bản thật; post-fix-gate.py in dấu rồi đỏ để gate dừng trước merge
mkdir -p "$KIT/bin"
cat > "$KIT/bin/install.sh" <<'SH'
#!/usr/bin/env bash
kit="$(cd "$(dirname "$0")/.." && pwd)"; echo "$*" > "$kit/install-args"
[ -f "$kit/install-fails" ] && { echo "fake install: boom"; exit 3; }
t=""; while [ $# -gt 0 ]; do case "$1" in -t) t="$2"; shift 2 ;; *) shift ;; esac; done
mkdir -p "$t/.agents" && ln -sfn "$kit" "$t/.agents/devkit"
SH
printf 'import sys\nprint("FAKE-GATE-R" "AN")\nsys.exit(1)\n' > "$KIT/bin/post-fix-gate.py"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n.agents/devkit\n' > "$R/.gitignore"
mkdir -p "$R/.claude/super-board/configs" && echo '{}' > "$R/.claude/super-board/configs/x.json"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
mkdir -p "$R/.agents" && ln -s "$KIT" "$R/.agents/devkit"   # chỉ main checkout có DevKit (bị ignore)
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x                 # worktree Reviewer: không có .agents/devkit
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
echo "$H" > "$TMP/pr5.head"

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
  *" pr merge "*) echo "fake gh: must not merge on a red verify" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["python3 .agents/devkit/bin/post-fix-gate.py --run-tests"]}\n' > "$CFG"
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate.log" 2>&1; rc=$?
grep -q "FAKE-GATE-RAN" "$TMP/gate.log" \
  && ok "scratch có DevKit của main checkout: post-fix-gate.py chạy được" \
  || fail "post-fix-gate.py không chạy trong scratch: $(grep -m1 -E "Errno 2|can't open" "$TMP/gate.log")"
! grep -q "can't open file" "$TMP/gate.log" && ok "không còn lỗi 'can't open file … post-fix-gate.py'" || fail "vẫn thiếu post-fix-gate.py trong scratch"
[ "$rc" -eq 11 ] && ok "verify đỏ do chính gate (nhánh không chậm hơn base): exit 11" || fail "gate exit $rc (want 11): $(tail -5 "$TMP/gate.log")"
grep -q -- "--no-githooks" "$KIT/install-args" && ok "cài vào scratch với --no-githooks (không ghi hook git dùng chung)" \
  || fail "install.sh gọi thiếu --no-githooks: $(cat "$KIT/install-args")"

# Installer có nhưng hỏng: lỗi môi trường → exit 9 kèm log cài đặt, không phải exit 11 làm thẻ Blocked (OCR 19/10)
touch "$KIT/install-fails"
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate3.log" 2>&1; rc=$?
[ "$rc" -eq 9 ] && grep -q "install into the scratch tree failed (exit 3)" "$TMP/gate3.log" && grep -q "fake install: boom" "$TMP/gate3.log" \
  && ok "installer hỏng: exit 9, báo exit của installer và dòng log của nó" \
  || fail "installer hỏng: gate exit $rc (want 9 + log): $(tail -3 "$TMP/gate3.log")"
rm -f "$KIT/install-fails"

# Không DevKit nào để cài (repo lẫn main checkout đều không có): exit 9, không phải exit 11
rm -f "$R/.agents/devkit"
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate2.log" 2>&1; rc=$?
[ "$rc" -eq 9 ] && grep -q "verification-readiness" "$TMP/gate2.log" \
  && ok "không có DevKit nào: exit 9 (verification-readiness), không exit 11" \
  || fail "không có DevKit nào: gate exit $rc (want 9): $(tail -3 "$TMP/gate2.log")"
echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_devkit_from_main: PASS"; exit 0; } || { echo "test_merge_gate_devkit_from_main: FAIL ($FAILS)"; exit 1; }
