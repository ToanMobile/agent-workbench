#!/usr/bin/env bash
# Lượt `--scoped` mặc định KHÔNG fail-fast: mọi suite đã chọn đều chạy, mọi suite đỏ lộ ra trong MỘT lượt
# (PR #977 tốn 4 lượt gate 25–30 phút vì fail-fast #647 chỉ lộ một suite đỏ mỗi lượt).
#   a. --scoped: REG-A và REG-B cùng FAIL trong một lượt, REG-C vẫn chạy, không "Không chạy", exit 1 (đỏ vẫn đỏ)
#   b. --scoped --fail-fast: hành vi cũ — REG-A FAIL, REG-B/REG-C UNTESTED "Không chạy", exit 1
#   c. lượt không --scoped (biên nhận task, Stop hook): vẫn fail-fast như #647
# test_gate_fail_fast.sh giữ phần --tree / --no-fail-fast. bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S \
      DEVKIT_GATE_MERGE_CHECK DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID DEVKIT_SLOT_PRIORITY POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # khoá slot riêng (không đụng gate thật của máy)
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ORIGIN="$TMP/origin.git"; REPO="$TMP/repo"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  mkdir -p src templates .agents
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf 'ran\n.agents/evidence/\n.agents/regression_checklist.md\n.agents/CHECKLIST.md\n.claude/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[
  {"id":"REG-A","name":"first red","command":"echo a >> ran; exit 1"},
  {"id":"REG-B","name":"second red","command":"echo b >> ran; exit 1"},
  {"id":"REG-C","name":"green","command":"echo c >> ran"}]}]}
JSON
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
echo "def ok(): return 2" > "$REPO/src/core.py"   # diff chưa commit: luật Core được chọn

gate() { CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --no-checklist --run-tests --no-cache --json "$@" >"$TMP/gate" 2>&1; }
show() { tail -c 600 "$TMP/gate" | tr '\n' ' '; }
# statuses: "REG-A=FAIL REG-B=… REG-C=…" từ dòng JSON cuối của --json
statuses() { python3 - "$TMP/gate" <<'PY'
import json, sys
d = None
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if line.startswith("{"):
        try:
            d = json.loads(line)
        except ValueError:
            pass
st = {t.get("id"): t.get("status") for t in (d or {}).get("regression_tests", [])}
print(" ".join("%s=%s" % (k, st.get(k)) for k in ("REG-A", "REG-B", "REG-C")))
PY
}
reset_run() { rm -rf "$REPO/.agents/evidence" "$REPO/ran" "$(git -C "$REPO" rev-parse --absolute-git-dir)/postfix-gate"; }
# tên suite đã chạy, mỗi tên một lần, đã sắp (suite FAIL có thể được chạy lại một lần)
ran() { [ -f "$REPO/ran" ] && sort -u "$REPO/ran" | tr '\n' ' '; }

# a. --scoped mặc định: cả hai suite đỏ lộ ra trong một lượt
reset_run
gate --scoped; rc=$?; st="$(statuses)"
[ "$rc" = 1 ] && ok "a: --scoped đỏ vẫn exit 1" || fail "a: rc $rc (want 1) $(show)"
[ "$st" = "REG-A=FAIL REG-B=FAIL REG-C=PASS" ] && ok "a: --scoped lộ cả REG-A và REG-B FAIL trong một lượt ($st)" \
  || fail "a: statuses '$st' (want REG-A=FAIL REG-B=FAIL REG-C=PASS) ran='$(ran)' $(show)"
grep -q "Không chạy\|Not run: an earlier" "$TMP/gate" && fail "a: --scoped vẫn dừng ở suite đỏ đầu $(show)" \
  || ok "a: --scoped không dừng ở suite đỏ đầu"
[ "$(ran)" = "a b c " ] && ok "a: cả ba suite đã chạy" || fail "a: ran='$(ran)' (want 'a b c ')"

# b. --scoped --fail-fast: hành vi cũ
reset_run
gate --scoped --fail-fast; rc=$?; st="$(statuses)"
[ "$rc" = 1 ] && ok "b: --scoped --fail-fast exit 1" || fail "b: rc $rc (want 1) $(show)"
[ "$st" = "REG-A=FAIL REG-B=UNTESTED REG-C=UNTESTED" ] && grep -q "Không chạy\|Not run: an earlier" "$TMP/gate" \
  && ok "b: --fail-fast dừng sau REG-A ($st)" || fail "b: statuses '$st' ran='$(ran)' $(show)"
[ "$(ran)" = "a " ] && ok "b: chỉ REG-A chạy" || fail "b: ran='$(ran)' (want 'a ')"

# c. lượt không --scoped (biên nhận task / Stop hook): mặc định cũ #647 giữ nguyên
reset_run
gate; rc=$?; st="$(statuses)"
[ "$rc" = 1 ] && [ "$st" = "REG-A=FAIL REG-B=UNTESTED REG-C=UNTESTED" ] \
  && ok "c: lượt không --scoped vẫn fail-fast ($st)" || fail "c: rc $rc statuses '$st' ran='$(ran)' $(show)"

# d. lane_lock (#849): --fail-fast chỉ làm lượt ngắn hơn, nên `--scoped --fail-fast` vẫn là việc nhẹ (không chờ ngưỡng tải)
python3 -I - "$DEVKIT_DIR/bin" <<'PY' && ok "d: lane_lock nhận --scoped --fail-fast là việc nhẹ" || fail "d: lane_lock coi --fail-fast là việc nặng"
import sys; sys.path.insert(0, sys.argv[1]); import lane_lock as m
sys.exit(0 if m.gate_call(["python3", sys.argv[1] + "/post-fix-gate.py", "--run-tests", "--scoped", "--fail-fast"]) else 1)
PY

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_scoped_no_fail_fast: PASS"; exit 0; }
echo "test_gate_scoped_no_fail_fast: FAIL ($FAILS)"
exit 1
