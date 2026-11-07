#!/usr/bin/env bash
# Gate speed v26 (lane D2): lượt có kết luận STALE (PASS dùng lại theo khoá không còn đứng vững, exit 4, exit_reason "stale") KHÔNG để lại
# outcome nào cho cây đó (<git dir>/postfix-gate/outcomes/<fp>.json): Stop hook không thấy biên nhận, không thấy outcome ⇒ chặn, bảo chạy lại.
#   s1. (tiền đề) lượt hai: REG-K dùng lại theo khoá, launcher ghi FAIL lên khoá ngay sau lần tra ⇒ STALE, exit 4
#   s2. outcome cũ của đúng cây đó (một lượt env trước) bị bỏ; không outcome mới nào
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE CI FLAKY_RETRY WORKTREE_TRUNK_MODE \
      DEVKIT_SCOPED_TESTS DEVKIT_GATE_MERGE_CHECK POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
export DEVKIT_SENTINEL_MAX_S=999999999
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1; mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/r"; mkdir -p "$R/src"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t || exit 1
echo 'a = 1' > "$R/src/a.py"; echo 'k = 1' > "$R/src/k.py"
printf '{"project":"t","rules":[{"component":"A","watch_files":["src/a.py"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"true"}]},{"component":"K","watch_files":["src/k.py"],"mandatory_regression_tests":[{"id":"REG-K","name":"k","command":"echo run >> %s/count"}]}]}\n' "$TMP" > "$R/matrix.json"
printf '.claude/\n' > "$R/.gitignore"
git -C "$R" add -A && git -C "$R" commit -qm init

# launcher: lần hit() đầu tiên của REG-K trả PASS rồi ghi FAIL lên khoá (như một lượt khác vừa FAIL) ⇒ recheck lật nó STALE
cat > "$TMP/launch.py" <<'PY'
import importlib.util, os, sys
gate = sys.argv[1]
sys.path.insert(0, os.path.dirname(gate))
import suite_cache
real_hit, fired = suite_cache.SuiteCache.hit, []
def hit(self, key, test, now=None):
    rec = real_hit(self, key, test, now)
    if rec and test.get("id") == "REG-K" and not fired:
        fired.append(1)
        self.record(key, test, "FAIL", {"why": "stale test: another run FAILED this key"})
    return rec
suite_cache.SuiteCache.hit = hit
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg_stale", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg_stale"] = m
spec.loader.exec_module(m)
sys.exit(m.main())
PY

echo 'a = 2' > "$R/src/a.py"
( cd "$R" && FLAKY_RETRY=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --full --no-checklist >"$TMP/out1" 2>&1 ); r1=$?
[ "$r1" = 0 ] || { fail "tiền đề: lượt đầu exit $r1"; tail -5 "$TMP/out1"; }

echo 'a = 3' > "$R/src/a.py"
OUT="$(python3 - "$DEVKIT_DIR/bin" "$R" <<'PY'
import json, os, sys, time
sys.path.insert(0, sys.argv[1]); import tree_fp
r = sys.argv[2]
fp = tree_fp.tree_fingerprint(r)
p = os.path.join(os.path.dirname(tree_fp.receipt_path(r)), "outcomes", fp + ".json")
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump({"exit": 1, "reason": "env", "lines": ["lượt env cũ"], "base": "", "at": time.time()}, open(p, "w"))
print(os.path.dirname(p))
PY
)"
( cd "$R" && FLAKY_RETRY=0 CLAUDE_PROJECT_DIR="$R" python3 "$TMP/launch.py" "$GATE" --matrix "$R/matrix.json" --run-tests --full \
  --no-checklist >"$TMP/out2" 2>&1 ); rc=$?
if [ "$rc" = 4 ] && LC_ALL=C grep -aq "REG-K" "$TMP/out2" && LC_ALL=C grep -aqE "không còn đứng vững|no longer stands" "$TMP/out2"; then
  ok "s1. (tiền đề) PASS dùng lại theo khoá bị lật STALE: exit 4"
else fail "s1. exit $rc (mong 4, STALE REG-K)"; LC_ALL=C grep -aE "REG-K|KẾT LUẬN" "$TMP/out2" | tail -3; fi
left="$(ls "$OUT" 2>/dev/null | tr '\n' ' ')"
[ -z "$left" ] && ok "s2. STALE: không còn outcome nào cho cây (Stop hook chặn)" || fail "s2. còn outcome sau STALE: $left"

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_stale_no_outcome: PASS"; exit 0; }
echo "test_gate_stale_no_outcome: FAIL ($FAILS)"; exit 1
