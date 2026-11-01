#!/usr/bin/env bash
# Test hồi quy cho nhánh `gh pr merge` thất bại trong .claude/bin/super-board-merge-gate.sh:
# - Ca A (open): PR vẫn OPEN đúng head sau các lần đọc lại → exit 4, không ghi halt.json, chỉ gọi merge đúng 1 lần.
# - Ca B (merged_late): lần đọc lại thứ 2 trả MERGED → exit 0, không halt.
# - Ca C (fail): đọc lại lỗi HTTP 502 cả 3 lần → github-read ghi halt.json và gate exit != 0 (không fail-open).
# - Ca D (moved): head đổi trong lúc chạy gate → exit 6, không halt.
# - Ca E (closed): PR ở trạng thái CLOSED đúng head → ghi halt.json và exit != 0 như cũ.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergegate-call-failed.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

# card_branch <N> <file>: nhánh issue-<N>-x thêm đúng một dòng vào <file>, đã push; ghi diff + metadata cho gh giả.
card_branch() {
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  echo "$1" > "$W/issue-$1-build/$2"
  git -C "$W/issue-$1-build" add "$2"; git -C "$W/issue-$1-build" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$TMP/pr$1.meta"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
# gh giả: `pr merge` ghi vào merge.calls và lỗi GraphQL tạm thời (exit 1); `pr view ... state,mergeCommit,headRefOid`
# trả theo FAKE_POST chỉ sau khi merge.calls đã tồn tại (lần đọc đầu gate luôn OPEN đúng head).
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*)
    if [ ! -s "$FAKE_DIR/merge.calls" ]; then
      printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head"
      exit 0
    fi
    cnt=$(( $(cat "$FAKE_DIR/post.reads" 2>/dev/null || echo 0) + 1 ))
    echo "$cnt" > "$FAKE_DIR/post.reads"
    case "${FAKE_POST:-open}" in
      open)
        printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
      merged_late)
        if [ "$cnt" -ge 2 ]; then
          printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$head" "$head"
        else
          printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head"
        fi ;;
      fail)
        echo "HTTP 502: Bad Gateway" >&2
        exit 1 ;;
      moved)
        printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"0000000000000000000000000000000000000000"}\n' ;;
      closed)
        printf '{"state":"CLOSED","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
      *)
        echo "fake gh: unexpected FAKE_POST=${FAKE_POST:-}" >&2; exit 1 ;;
    esac ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*)
    echo "$*" >> "$FAKE_DIR/merge.calls"
    echo "GraphQL: Something went wrong while executing your query" >&2
    exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_MERGE_RECHECK_DELAY_S=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}' > "$CFG"

# ── A. FAKE_POST=open: OPEN đúng head sau mọi lần đọc lại → exit 4, không có halt.json, merge gọi đúng 1 lần.
rm -f "$TMP/halt.json" "$TMP/merge.calls" "$TMP/post.reads"
card_branch 11 b
H11=$(cat "$TMP/pr11.head")
git -C "$R" worktree add -q --detach "$W/issue-11-review" "$H11"
( cd "$W/issue-11-review" && FAKE_POST=open bash "$GATE" --config "$CFG" --pr 11 --expect-head "$H11" ) >"$TMP/gate11.log" 2>&1; rc=$?
[ "$rc" -eq 4 ] && ok "A (open): gate exits 4 when PR stays OPEN at verified head" || fail "A (open): expected exit 4, got $rc: $(tail -5 "$TMP/gate11.log")"
[ ! -e "$TMP/halt.json" ] && ok "A (open): no halt.json written" || fail "A (open): halt.json was written: $(cat "$TMP/halt.json")"
merge_calls=$(wc -l < "$TMP/merge.calls" 2>/dev/null | tr -d ' ')
[ "${merge_calls:-0}" -eq 1 ] && ok "A (open): gh pr merge called exactly once" || fail "A (open): expected 1 merge call, got ${merge_calls:-0}"
grep -q "nothing was merged" "$TMP/gate11.log" && ok "A (open): log confirms nothing was merged" || fail "A (open): missing 'nothing was merged' in log: $(tail -5 "$TMP/gate11.log")"

# ── B. FAKE_POST=merged_late: lần đọc lại thứ 2 trả MERGED → exit 0, không halt.
rm -f "$TMP/halt.json" "$TMP/merge.calls" "$TMP/post.reads"
card_branch 12 c
H12=$(cat "$TMP/pr12.head")
git -C "$R" worktree add -q --detach "$W/issue-12-review" "$H12"
( cd "$W/issue-12-review" && FAKE_POST=merged_late bash "$GATE" --config "$CFG" --pr 12 --expect-head "$H12" ) >"$TMP/gate12.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "B (merged_late): gate exits 0 when second re-read sees MERGED" || fail "B (merged_late): expected exit 0, got $rc: $(tail -5 "$TMP/gate12.log")"
[ ! -e "$TMP/halt.json" ] && ok "B (merged_late): no halt.json written" || fail "B (merged_late): halt.json was written: $(cat "$TMP/halt.json")"
[ "$(cat "$TMP/post.reads" 2>/dev/null || echo 0)" -eq 2 ] && ok "B (merged_late): stopped on the 2nd post-merge read" || fail "B (merged_late): unexpected post.reads=$(cat "$TMP/post.reads" 2>/dev/null)"

# ── C. FAKE_POST=fail: đọc lại lỗi HTTP 502 → github-read halt sau 3 lần → có halt.json, exit != 0.
rm -f "$TMP/halt.json" "$TMP/merge.calls" "$TMP/post.reads"
card_branch 13 d
H13=$(cat "$TMP/pr13.head")
git -C "$R" worktree add -q --detach "$W/issue-13-review" "$H13"
( cd "$W/issue-13-review" && FAKE_POST=fail bash "$GATE" --config "$CFG" --pr 13 --expect-head "$H13" ) >"$TMP/gate13.log" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "C (fail): gate exits non-zero ($rc) when post-merge read fails" || fail "C (fail): expected non-zero exit, got 0"
[ -s "$TMP/halt.json" ] && ok "C (fail): halt.json written after 3 failed reads (no fail-open)" || fail "C (fail): missing halt.json"

# ── D. FAKE_POST=moved: head đổi → exit 6, không halt.
rm -f "$TMP/halt.json" "$TMP/merge.calls" "$TMP/post.reads"
card_branch 14 e
H14=$(cat "$TMP/pr14.head")
git -C "$R" worktree add -q --detach "$W/issue-14-review" "$H14"
( cd "$W/issue-14-review" && FAKE_POST=moved bash "$GATE" --config "$CFG" --pr 14 --expect-head "$H14" ) >"$TMP/gate14.log" 2>&1; rc=$?
[ "$rc" -eq 6 ] && ok "D (moved): gate exits 6 when PR head moved" || fail "D (moved): expected exit 6, got $rc: $(tail -5 "$TMP/gate14.log")"
[ ! -e "$TMP/halt.json" ] && ok "D (moved): no halt.json written" || fail "D (moved): halt.json was written: $(cat "$TMP/halt.json")"

# ── E. FAKE_POST=closed: state=CLOSED đúng head → halt như cũ (exit != 0, có halt.json).
rm -f "$TMP/halt.json" "$TMP/merge.calls" "$TMP/post.reads"
card_branch 15 f
H15=$(cat "$TMP/pr15.head")
git -C "$R" worktree add -q --detach "$W/issue-15-review" "$H15"
( cd "$W/issue-15-review" && FAKE_POST=closed bash "$GATE" --config "$CFG" --pr 15 --expect-head "$H15" ) >"$TMP/gate15.log" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "E (closed): gate exits non-zero ($rc) when PR is CLOSED" || fail "E (closed): expected non-zero exit, got 0"
[ -s "$TMP/halt.json" ] && ok "E (closed): halt.json written for CLOSED state" || fail "E (closed): missing halt.json"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_merge_call_failed: all passed" || { echo "❌ test_merge_gate_merge_call_failed: $FAILS failed"; exit 1; }
