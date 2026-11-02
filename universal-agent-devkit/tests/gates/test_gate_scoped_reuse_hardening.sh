#!/usr/bin/env bash
# Test hồi quy (#803, follow-up #785): lượt --scoped mượn biên nhận scoped (<git common dir>/postfix-gate/scoped_receipts/<fp>.json)
# ở một worktree mới không được dùng lại PASS mà chạy thật suite khi:
#   0. tiền đề: mục store hợp lệ ⇒ scratch mới mượn được REG-K (0 lần chạy), để các ca dưới phân biệt được;
#   1. SuiteCache đã void suite đó sau PASS trong biên nhận (TIMEOUT / FAIL chập chờn ở nơi khác: void.json) — như hit() đã xét;
#   2. PASS của suite trong biên nhận cũ hơn DEVKIT_GATE_CACHE_MAX_S theo ran_at của chính nó (tested_at của biên nhận còn mới);
#   3. khoá nội dung của runner (run_impacted.sh --list) không tính được: sc.keys trả (None, None) ⇒ không mượn (như nhánh ngoại lệ);
#   4. DEVKIT_GATE_CACHE_MAX_S không hữu hạn (nan / inf) hoặc ≤ 0 ⇒ không mượn (reuse_miss_reason=ttl).
# Tương thích bash 3.2, chỉ dùng Python stdlib.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE CI \
      DEVKIT_SLOT_PRIORITY DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_PER_TEST_CACHE

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export DEVKIT_SENTINEL_MAX_S=999999999

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
cnt()  { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }

ORIGIN="$TMP/origin.git"
R="$TMP/repo"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$R" 2>/dev/null || exit 1
(
  cd "$R" || exit 1
  git config user.email t@t && git config user.name t && git config commit.gpgsign false
  mkdir -p src tests kit/tests/g .agents
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.claude/\n' > .gitignore
  bash "$DEVKIT_DIR/bin/install.sh" -t "$R" -a claude -y --no-githooks >/dev/null 2>&1 || true
  echo '{"profile":"backend"}' > .agents/active-profile.json
  echo 'a = 1' > src/a.py
  echo 'k = 1' > src/k.py
  printf '#!/usr/bin/env bash\ngrep -q = src/a.py\n' > tests/test_a.sh
  printf '#!/usr/bin/env bash\ngrep -q = src/k.py\n' > kit/tests/g/test_k.sh
  cat > kit/tests/run_impacted.sh <<SH
#!/usr/bin/env bash
# devkit-selection-list: --list in danh sách test chọn, không chạy gì
if [ "\${1-}" = --list ]; then [ -f '$TMP/list_fail' ] && exit 3; echo tests/g/test_k.sh; exit 0; fi
echo run >> '$TMP/count.K'
SH
  chmod +x tests/test_a.sh kit/tests/g/test_k.sh kit/tests/run_impacted.sh
  python3 - "$R/.agents/regression_matrix.active.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
json.dump({"project": "t", "rules": [
    {"component": "A", "watch_files": ["src/a.py"],
     "mandatory_regression_tests": [{"id": "REG-A", "name": "a", "command": f"echo run >> '{tmp}/count.A'; bash tests/test_a.sh"}]},
    {"component": "K", "watch_files": ["src/k.py", "kit/*"],
     "mandatory_regression_tests": [{"id": "REG-K", "name": "kit", "command": "bash kit/tests/run_impacted.sh"}]},
]}, open(path, "w"))
PY
  git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
) || exit 1
git -C "$R" checkout -q -b feat
echo 'a = 2' > "$R/src/a.py"
echo 'k = 2' > "$R/src/k.py"
git -C "$R" commit -qam "edit a and k"
git -C "$R" checkout -q main

COMMON="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)"
SSTORE="$COMMON/postfix-gate/scoped_receipts"
SCACHE="$COMMON/postfix-gate/suite_cache"
RUNLOG="$COMMON/postfix-gate/runs.jsonl"

run_scoped() {
  local wt="$1"; shift
  OUT="$(cd "$wt" && CLAUDE_PROJECT_DIR="$wt" python3 "$GATE" --diff origin/main --run-tests --scoped --no-checklist "$@" 2>&1)"
  RC=$?
}
add_wt() { git -C "$R" worktree add -q --detach "$TMP/$1" feat || { echo "✖ setup worktree $1"; exit 1; }; }
rm_wt()  { git -C "$R" worktree remove --force "$TMP/$1" 2>/dev/null || rm -rf "$TMP/$1"; }
last_field() { tail -1 "$RUNLOG" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get(sys.argv[1]) or "")' "$1"; }
# scratch mới (tên thư mục chưa từng chạy gate) chạy --scoped; KDELTA = số lần REG-K chạy thật
scratch() {
  local name="$1"; shift
  add_wt "$name"
  local k0 a0; k0="$(cnt K)"; a0="$(cnt A)"
  run_scoped "$TMP/$name" "$@"
  KDELTA=$(( $(cnt K) - k0 )); ADELTA=$(( $(cnt A) - a0 )); MISS="$(last_field reuse_miss_reason)"; REUSED="$(last_field reused_scoped)"
  rm_wt "$name"
}

# ── PR gate ở wt-a: REG-A + REG-K chạy thật, ghi mục store của cây feat
git -C "$R" worktree add -q "$TMP/wt-a" feat
run_scoped "$TMP/wt-a"
[ "$RC" = 0 ] || { fail "tiền đề: PR gate wt-a rc=$RC"; printf '%s\n' "$OUT" | tail -15; exit 1; }
FP="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.tree_fingerprint(sys.argv[2]))' "$DEVKIT_DIR/bin" "$TMP/wt-a")"
SF="$SSTORE/$FP.json"
[ -f "$SF" ] || { fail "tiền đề: thiếu mục store $SF"; exit 1; }
rm_wt wt-a
cp -p "$SF" "$TMP/store.keep"
restore_store() { mkdir -p "$SSTORE" && cp -p "$TMP/store.keep" "$SF"; }

# ── 0. tiền đề: mục store hợp lệ ⇒ scratch mới mượn REG-K
scratch wt-h0
if [ "$RC" = 0 ] && [ "$KDELTA" = 0 ] && [ "$REUSED" = "$FP" ]; then
  ok "0. tiền đề: scratch mới mượn biên nhận scoped, REG-K không chạy lại (reused_scoped=$FP)"
else
  fail "0. tiền đề: rc=$RC K+=$KDELTA reused='$REUSED' miss='$MISS' (mong 0, 0, $FP)"; printf '%s\n' "$OUT" | tail -15; exit 1
fi

# ── 1. void.json của SuiteCache ghi REG-K sau PASS trong biên nhận ⇒ không mượn REG-K
restore_store
python3 - "$SCACHE/void.json" <<'PY'
import json, os, sys, time
p = sys.argv[1]
os.makedirs(os.path.dirname(p), exist_ok=True)
d = {}
try:
    d = json.load(open(p))
except (OSError, ValueError):
    pass
d["REG-K"] = time.time()
json.dump(d, open(p, "w"))
PY
scratch wt-h1
rm -f "$SCACHE/void.json"
# chỉ REG-K bị loại khỏi lần mượn: biên nhận vẫn được mượn (reused_scoped) và REG-A không chạy lại
if [ "$RC" = 0 ] && [ "$KDELTA" = 1 ] && [ "$ADELTA" = 0 ] && [ "$REUSED" = "$FP" ]; then
  ok "1. REG-K bị void sau PASS trong biên nhận ⇒ scratch chạy thật REG-K"
else
  fail "1. mượn PASS đã bị void: rc=$RC K+=$KDELTA A+=$ADELTA reused='$REUSED' (mong 0, 1, 0, $FP)"; printf '%s\n' "$OUT" | tail -15
fi

# ── 2. ran_at của REG-K trong biên nhận cũ hơn DEVKIT_GATE_CACHE_MAX_S (tested_at vẫn mới) ⇒ không mượn REG-K
restore_store
python3 - "$SF" <<'PY'
import json, os, sys, time
p = sys.argv[1]
d = json.load(open(p))
for x in d["tests"]:
    if x.get("id") == "REG-K":
        x["ran_at"] = time.time() - 30000   # > 21600 s mặc định
open(p + ".tmp", "w").write(json.dumps(d)); os.replace(p + ".tmp", p)
PY
scratch wt-h2
if [ "$RC" = 0 ] && [ "$KDELTA" = 1 ] && [ "$ADELTA" = 0 ] && [ "$REUSED" = "$FP" ]; then
  ok "2. PASS của REG-K cũ hơn hạn theo ran_at ⇒ scratch chạy thật REG-K"
else
  fail "2. mượn PASS quá hạn theo ran_at: rc=$RC K+=$KDELTA A+=$ADELTA reused='$REUSED' (mong 0, 1, 0, $FP)"; printf '%s\n' "$OUT" | tail -15
fi

# ── 3. run_impacted.sh --list lỗi ⇒ khoá REG-K không tính được ⇒ không mượn REG-K
restore_store
touch "$TMP/list_fail"
scratch wt-h3
rm -f "$TMP/list_fail"
if [ "$RC" = 0 ] && [ "$KDELTA" = 1 ] && [ "$ADELTA" = 0 ] && [ "$REUSED" = "$FP" ]; then
  ok "3. khoá nội dung của runner không tính được ⇒ không mượn REG-K, REG-K chạy thật, REG-A vẫn mượn"
else
  fail "3. mượn PASS khi khoá không tính được: rc=$RC K+=$KDELTA A+=$ADELTA reused='$REUSED' (mong 0, 1, 0, $FP)"; printf '%s\n' "$OUT" | tail -15
fi

# ── 4. DEVKIT_GATE_CACHE_MAX_S không hữu hạn hoặc ≤ 0 ⇒ không mượn (ttl)
n=0
for v in nan inf 0 -5; do
  n=$((n + 1))
  restore_store
  export DEVKIT_GATE_CACHE_MAX_S="$v"
  scratch "wt-h4-$n"
  unset DEVKIT_GATE_CACHE_MAX_S
  if [ "$KDELTA" = 1 ] && [ "$MISS" = "ttl" ]; then
    ok "4. DEVKIT_GATE_CACHE_MAX_S=$v ⇒ không mượn biên nhận (ttl), REG-K chạy thật"
  else
    fail "4. DEVKIT_GATE_CACHE_MAX_S=$v: rc=$RC K+=$KDELTA miss='$MISS' (mong 1, ttl)"
  fi
done

echo
[ "$FAILS" = 0 ] && { echo "PASS: test_gate_scoped_reuse_hardening"; exit 0; }
echo "FAIL: test_gate_scoped_reuse_hardening ($FAILS)"; exit 1
