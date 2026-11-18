#!/usr/bin/env bash
# Hồi quy #251 (gate_masked_conditions_clean): post-fix-gate.py --json xuất `"matrix_problem": null` khi ma trận sạch.
# Toán tử `//` của jq thay cả `null` lẫn `false`, nên `(.matrix_problem // "x") == ""` biến `null` thành `"x"` → luôn false,
# làm `red_only_on_base` không bao giờ chạy khi một suite đã đỏ sẵn trên origin/<base>.
#   Ca 1: matrix_problem = null + suite REG-S1 đỏ cả trên cây gộp lẫn trên origin/main → mở thẻ bug, cho PR merge (exit 0).
#   Ca 2: thiếu trường matrix_problem trong JSON → fail-closed (exit 11, không merge).
#   Ca 3: matrix_problem = "bad" → fail-closed (exit 11, không merge).
#   Ca 4: matrix_problem = null nhưng REG-S1 xanh trên origin/main (do PR làm hỏng) → fail-closed (exit 11, không merge).
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-redonbase-null.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/feat-x"; KIT="$TMP/kit"

mkdir -p "$KIT/bin"
cat > "$KIT/bin/install.sh" <<'SH'
#!/usr/bin/env bash
kit="$(cd "$(dirname "$0")/.." && pwd)"
t=""; while [ $# -gt 0 ]; do case "$1" in -t) t="$2"; shift 2 ;; *) shift ;; esac; done
mkdir -p "$t/.agents" && ln -sfn "$kit" "$t/.agents/devkit"
SH
chmod +x "$KIT/bin/install.sh"

cat > "$KIT/bin/post-fix-gate.py" <<'PY'
import json, os, sys
mode = os.environ.get("FAKE_PFG_MODE", "null_clean")
print("    [ ] FAIL | REG-S1          : fake suite")
print("  KẾT LUẬN CỔNG POST-FIX AUDIT: REJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT")
print("  • Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log): đạt")
payload = {
    "verdict": "REJECT",
    "exit_code": 1,
    "accepted": False,
    "files": ["b"],
    "unreadable": [],
    "regression_tests": [{"id": "REG-S1", "status": "FAIL"}],
    "matrix_problem": None,
    "tests_touched": [],
    "uncovered": [],
    "orphan_tests": [],
    "busy": False,
    "budget_exhausted": False,
}
if mode == "missing_key":
    del payload["matrix_problem"]
elif mode == "bad_matrix":
    payload["matrix_problem"] = "corrupt matrix"
if "--json" in sys.argv:
    print(json.dumps(payload))
sys.exit(1)
PY

git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n.agents/devkit\n' > "$R/.gitignore"
mkdir -p "$R/.claude/super-board/configs" "$R/.agents"
echo '{}' > "$R/.claude/super-board/configs/x.json"
cat > "$R/.agents/regression_matrix.active.json" <<'JSON'
{
  "components": [
    {
      "component": "S1",
      "watch_files": ["*"],
      "mandatory_regression_tests": [
        {
          "id": "REG-S1",
          "name": "Fake base suite",
          "command": "bash suite.sh"
        }
      ]
    }
  ]
}
JSON
# Trên main: suite.sh đọc FAKE_BASE_GREEN để giả lập đỏ sẵn trên main (mặc định) hoặc xanh trên main (Ca 4)
cat > "$R/suite.sh" <<'SH'
#!/usr/bin/env bash
[ "${FAKE_BASE_GREEN:-0}" = "1" ] && exit 0
exit 1
SH
chmod +x "$R/suite.sh"
echo a > "$R/a"
git -C "$R" add -A; git -C "$R" commit -qm init
ln -s "$KIT" "$R/.agents/devkit"
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main

git -C "$R" branch -q --no-track feat-x main
git -C "$R" worktree add -q "$WT" feat-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm "feat b"
git -C "$R" push -q origin feat-x
H=$(git -C "$R" rev-parse feat-x)
git -C "$R" diff origin/main feat-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"b","additions":1,"deletions":0}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1,"comments":[],"author":{"login":"t"}}' > "$TMP/pr5.meta"
echo "$H" > "$TMP/pr5.head"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr${n:-5}.head" 2>/dev/null || echo "")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "feat-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"mergeable"*) echo "MERGEABLE" ;;
  *" pr view "*"mergeCommit"*) echo "" ;;
  *" pr view "*"closingIssuesReferences"*) echo "" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr${n:-5}.meta" ;;
  *" pr view "*"title"*) echo "feat b" ;;
  *" pr view "*"body"*) echo "" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr${n:-5}.diff" ;;
  *" pr checks "*) echo "no checks reported" >&2; exit 1 ;;
  *" issue list "*) echo "0" ;;
  *" issue create "*) echo "$*" >> "$FAKE_DIR/issue.calls"; echo "https://example.invalid/issues/99" ;;
  *" pr merge "*) echo "$*" >> "$FAKE_DIR/merge.calls"; exit 0 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["python3 .agents/devkit/bin/post-fix-gate.py --run-tests --brief"]}\n' > "$CFG"

# Ca 2: thiếu trường matrix_problem → fail-closed (exit 11, không merge)
rm -f "$TMP/merge.calls" "$TMP/issue.calls"
( cd "$WT" && FAKE_PFG_MODE=missing_key bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/ca2.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && [ ! -e "$TMP/merge.calls" ] \
  && ok "Ca 2: thiếu matrix_problem trong JSON → fail-closed (exit 11, không merge)" \
  || fail "Ca 2: exit=$rc, merge.calls=$(cat "$TMP/merge.calls" 2>/dev/null): $(tail -5 "$TMP/ca2.log")"

# Ca 3: matrix_problem = "corrupt matrix" → fail-closed (exit 11, không merge)
rm -f "$TMP/merge.calls" "$TMP/issue.calls"
( cd "$WT" && FAKE_PFG_MODE=bad_matrix bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/ca3.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && [ ! -e "$TMP/merge.calls" ] \
  && ok "Ca 3: matrix_problem khác rỗng → fail-closed (exit 11, không merge)" \
  || fail "Ca 3: exit=$rc: $(tail -5 "$TMP/ca3.log")"

# Ca 4: matrix_problem = null nhưng REG-S1 xanh trên origin/main (do PR làm đỏ) → exit 11, không merge
rm -f "$TMP/merge.calls" "$TMP/issue.calls"
( cd "$WT" && FAKE_PFG_MODE=null_clean FAKE_BASE_GREEN=1 bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/ca4.log" 2>&1; rc=$?
[ "$rc" -eq 11 ] && [ ! -e "$TMP/merge.calls" ] && grep -q "REG-S1 is green on origin/main: the PR broke it" "$TMP/ca4.log" \
  && ok "Ca 4: REG-S1 xanh trên origin/main → bắt đúng lỗi của PR (exit 11, không merge)" \
  || fail "Ca 4: exit=$rc: $(tail -6 "$TMP/ca4.log")"

# Ca 1 (RED trước sửa, GREEN sau sửa): matrix_problem = null + REG-S1 đỏ sẵn trên origin/main → mở thẻ bug + merge PR (exit 0)
rm -f "$TMP/merge.calls" "$TMP/issue.calls"
( cd "$WT" && FAKE_PFG_MODE=null_clean FAKE_BASE_GREEN=0 bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/ca1.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -s "$TMP/merge.calls" ] && [ -s "$TMP/issue.calls" ] \
  && grep -q "REG-S1 is red on origin/main too: not this PR's fault" "$TMP/ca1.log" \
  && ok "Ca 1: matrix_problem = null + REG-S1 đỏ sẵn trên origin/main → mở thẻ bug và cho phép merge (exit 0)" \
  || fail "Ca 1: exit=$rc (want 0 + merge + issue): $(tail -8 "$TMP/ca1.log")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_red_on_base_null_matrix: PASS"; exit 0; } || { echo "test_merge_gate_red_on_base_null_matrix: FAIL ($FAILS)"; exit 1; }
