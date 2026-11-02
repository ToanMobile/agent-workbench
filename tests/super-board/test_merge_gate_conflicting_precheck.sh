#!/usr/bin/env bash
# 02/11 (#881, #883, #885): .gitattributes gộp test_durations.txt bằng merge=union và ma trận bằng merge=devkit-matrix; driver chỉ có
# ở local. Merge gate gộp base vào scratch thấy sạch, verify xanh 30–35 phút, rồi `gh pr merge` bị GitHub từ chối "Pull Request has
# merge conflicts" (exit 4): verify phí, khoá merge bị giữ cả nửa giờ.
# Hành vi mong đợi (mỗi ý có assert bên dưới): sau khi lấy khoá và TRƯỚC verify, gate đọc `mergeable` của PR. CONFLICTING ⇒ thoát
# 14 (ca 1 kiểm file verify-ran và merge-args vắng), câu báo nói cách sửa (gộp origin/<base> vào nhánh, push, chạy lại với
# --expect-head mới). MERGEABLE, UNKNOWN rồi MERGEABLE, UNKNOWN mãi (đọc lại có giới hạn) và lỗi đọc: verify chạy, merge như trước.
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-conflicting-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export SB_GITHUB_RETRY_DELAY=0 SB_MERGEABLE_POLL_S=0

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
head=$(cat "$FAKE_DIR/pr61.head")
case " $* " in
  *" pr view "*"--json mergeable"*)
    echo x >> "$FAKE_DIR/mergeable-calls"
    [ -f "$FAKE_DIR/mergeable-fail" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    n=$(wc -l < "$FAKE_DIR/mergeable-calls" | tr -d ' ')
    v=$(sed -n "${n}p" "$FAKE_DIR/mergeable.seq"); [ -n "$v" ] || v=$(tail -1 "$FAKE_DIR/mergeable.seq")
    echo "$v" ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-61-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr61.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr61.diff" ;;
  *" pr merge "*)
    echo "$*" > "$FAKE_DIR/merge-args"
    # GitHub thật: PR CONFLICTING thì merge bị từ chối dù gate gộp local sạch.
    if [ "$(tail -1 "$FAKE_DIR/mergeable.seq")" = CONFLICTING ]; then
      echo "GraphQL: Pull Request has merge conflicts (mergePullRequest)" >&2; exit 1
    fi
    echo "merged #61" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH"

# case <tên> <dòng mergeable…>: fixture mới mỗi ca (biên nhận verified-tree của ca trước không được làm verify bị bỏ ở ca sau).
# Nhánh PR chậm hơn base, gộp local sạch (như union/ma trận gộp bằng driver), GitHub trả mergeable theo từng dòng của mergeable.seq.
run_case() {
  local name="$1"; shift
  local D="$TMP/$name"; mkdir -p "$D"
  export FAKE_DIR="$D" SB_GITHUB_HALT_FILE="$D/halt.json"
  printf '%s\n' "$@" > "$D/mergeable.seq"
  local O="$D/origin.git" R="$D/repo" WT="$D/repo/.claude/worktrees/review-x"
  git init -q --bare -b main "$O"
  git init -q -b main "$R"
  git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
  printf '/.claude/worktrees/\n' > "$R/.gitignore"
  mkdir -p "$R/.agents"; echo '[]' > "$R/.agents/regression_matrix.active.json"
  echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
  git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
  git -C "$R" branch -q --no-track issue-61-x main
  git -C "$R" worktree add -q "$WT" issue-61-x
  echo 61 > "$WT/f61"; git -C "$WT" add f61; git -C "$WT" commit -qm card61
  git -C "$R" push -q origin issue-61-x
  X=$(git -C "$R" rev-parse issue-61-x); echo "$X" > "$D/pr61.head"
  git -C "$R" diff "$X~1" "$X" > "$D/pr61.diff"
  printf '{"files":[{"path":"f61"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$D/pr61.meta"
  echo b > "$R/b"; git -C "$R" add b; git -C "$R" commit -qm main-moves; git -C "$R" push -q origin main
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"verify_commands":[sys.argv[1]]}))' \
    "echo ran > $D/verify-ran" > "$D/cfg.json"
  ( cd "$WT" && bash "$GATE" --config "$D/cfg.json" --pr 61 --expect-head "$X" ${GATE_EXTRA:-} ) >"$D/gate.log" 2>&1; RC=$?
  ORIGIN_HEAD=$(git -C "$O" rev-parse issue-61-x)
  READS=0; [ ! -f "$D/mergeable-calls" ] || READS=$(wc -l < "$D/mergeable-calls" | tr -d ' ')
  DIR="$D"
}

# 1) CONFLICTING: thoát 14 ngay sau khoá, không verify, không merge, câu báo nói cách sửa
run_case conflicting CONFLICTING
[ "$RC" -eq 14 ] && ok "CONFLICTING: gate exits 14" || fail "CONFLICTING: gate exit $RC, want 14: $(grep 'merge-gate' "$DIR/gate.log" | tail -3)"
[ ! -e "$DIR/verify-ran" ] && ok "CONFLICTING: verify did not run" || fail "CONFLICTING: verify ran (30 min wasted inside the lock)"
[ ! -e "$DIR/merge-args" ] && ok "CONFLICTING: gh pr merge not called" || fail "CONFLICTING: gh pr merge was called: $(cat "$DIR/merge-args")"
grep -q "git merge --no-edit origin/main" "$DIR/gate.log" && grep -q -- "--expect-head" "$DIR/gate.log" \
  && ok "CONFLICTING: message says merge origin/main into the branch, push, rerun with the new --expect-head" \
  || fail "CONFLICTING: message lacks the fix: $(grep 'merge-gate' "$DIR/gate.log" | tail -3)"
[ ! -e "$DIR/repo/.claude/worktrees/review-x/.claude/super-board/inflight/merge.lock" ] && ok "CONFLICTING: merge lock released" \
  || fail "CONFLICTING: merge lock left behind"
[ "$ORIGIN_HEAD" = "$X" ] && ok "CONFLICTING: PR branch on origin unchanged (#570)" || fail "CONFLICTING: PR branch moved ${X:0:8} -> ${ORIGIN_HEAD:0:8}"
ls -d "$DIR"/repo/.claude/worktrees/.merge-scratch-* >/dev/null 2>&1 && fail "CONFLICTING: scratch dir left behind: $(ls -d "$DIR"/repo/.claude/worktrees/.merge-scratch-*)" \
  || ok "CONFLICTING: no .merge-scratch-* left behind"

# 2) MERGEABLE: như cũ
run_case mergeable MERGEABLE
[ "$RC" -eq 0 ] && [ -e "$DIR/verify-ran" ] && grep -q -- "--match-head-commit $X" "$DIR/merge-args" 2>/dev/null \
  && ok "MERGEABLE: verify ran and merged at the pinned head (exit 0)" \
  || fail "MERGEABLE: gate exit $RC, verify-ran=$([ -e "$DIR/verify-ran" ] && echo y || echo n): $(grep 'merge-gate' "$DIR/gate.log" | tail -3)"

# 3) UNKNOWN rồi MERGEABLE: đọc lại, rồi như cũ
run_case unknown_then_mergeable UNKNOWN MERGEABLE
[ "$RC" -eq 0 ] && [ -e "$DIR/verify-ran" ] && [ -e "$DIR/merge-args" ] && [ "$READS" -ge 2 ] \
  && ok "UNKNOWN then MERGEABLE: re-read ($READS reads), verify ran, merged" \
  || fail "UNKNOWN then MERGEABLE: gate exit $RC, reads $READS: $(grep 'merge-gate' "$DIR/gate.log" | tail -3)"

# 4) UNKNOWN rồi CONFLICTING: đọc lại thấy CONFLICTING ⇒ 14, không verify
run_case unknown_then_conflicting UNKNOWN CONFLICTING
[ "$RC" -eq 14 ] && [ ! -e "$DIR/verify-ran" ] && ok "UNKNOWN then CONFLICTING: exit 14 after re-read, no verify" \
  || fail "UNKNOWN then CONFLICTING: gate exit $RC, reads $READS"

# 5) UNKNOWN mãi: đọc lại có giới hạn rồi đi tiếp như cũ (GitHub tự từ chối nếu thật sự xung đột)
run_case unknown_forever UNKNOWN
[ "$RC" -eq 0 ] && [ -e "$DIR/verify-ran" ] && [ "$READS" -eq 4 ] \
  && ok "UNKNOWN forever: bounded re-reads ($READS), then verify + merge as before" \
  || fail "UNKNOWN forever: gate exit $RC, reads $READS"

# 5b) --preflight (train gọi cho từng PR trước verify_set của đợt): CONFLICTING ⇒ 14, không in "preflight: ok"; MERGEABLE ⇒ ok
GATE_EXTRA=--preflight run_case preflight_conflicting CONFLICTING
[ "$RC" -eq 14 ] && ! grep -q '^preflight: ok' "$DIR/gate.log" && [ ! -e "$DIR/verify-ran" ] \
  && ok "--preflight CONFLICTING: exit 14 before the train builds a tree" || fail "--preflight CONFLICTING: gate exit $RC: $(tail -3 "$DIR/gate.log")"
GATE_EXTRA=--preflight run_case preflight_mergeable MERGEABLE
[ "$RC" -eq 0 ] && grep -q '^preflight: ok' "$DIR/gate.log" && ok "--preflight MERGEABLE: preflight: ok" \
  || fail "--preflight MERGEABLE: gate exit $RC: $(tail -3 "$DIR/gate.log")"

# 6) Đọc mergeable lỗi (mạng, gh cũ): không thêm lối hỏng mới, đi tiếp như cũ
mkdir -p "$TMP/read_error"; : > "$TMP/read_error/mergeable-fail"
run_case read_error MERGEABLE
[ "$RC" -eq 0 ] && [ -e "$DIR/verify-ran" ] && [ -e "$DIR/merge-args" ] && [ ! -e "$DIR/halt.json" ] \
  && ok "mergeable read error: no halt, verify + merge as before" \
  || fail "mergeable read error: gate exit $RC, halt=$([ -e "$DIR/halt.json" ] && echo y || echo n): $(grep 'merge-gate' "$DIR/gate.log" | tail -3)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_conflicting_precheck: PASS"; exit 0; } || { echo "test_merge_gate_conflicting_precheck: FAIL ($FAILS)"; exit 1; }
