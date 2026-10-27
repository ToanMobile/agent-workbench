#!/usr/bin/env bash
# Test ĐỎ cho đợt tăng tốc gate (#472, mục 1) — XFAIL: mặc định in SKIP và thoát 0 để main không đỏ; GATE_SPEED_NEXT=1 chạy thật.
# Ngoài điểm gộp (repo không nằm trong .integrate-scratch-* / .merge-scratch-* / .train-scratch-*):
#   --full, --force-full, POSTFIX_GATE_FULL=1, --tree HEAD bị từ chối: exit khác 0 và KHÔNG suite nào chạy;
#   --record-lesson và CI=true không kéo theo lượt full: bị từ chối như trên, hoặc lượt chạy ghi mode "impacted" trong runs.jsonl.
# Trong .merge-scratch-* / .integrate-scratch-* / .train-scratch-*: --full vẫn chạy suite (không được chặn nhầm điểm gộp).
# Bỏ dòng skip khi #472 xong và test XANH.
if [ "${GATE_SPEED_NEXT:-0}" != 1 ]; then echo "SKIP (xfail #472): --full ngoài điểm gộp chưa bị từ chối — GATE_SPEED_NEXT=1 để chạy thật"; exit 0; fi
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL CI DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE DEVKIT_PER_TEST_CACHE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$HOME" "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# make_repo <thư mục>: repo một suite; suite ghi một dòng vào <thư mục>.ran khi chạy; src/Core.kt đổi chưa commit
make_repo() {
  local r="$1"
  mkdir -p "$r/src" && git -C "$r" init -q -b main . && git -C "$r" config user.email t@t && git -C "$r" config user.name t
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> %s.ran"}]}]}\n' "$r" > "$r/matrix.json"
  echo 'fun ok()=1' > "$r/src/Core.kt"
  git -C "$r" add -A && git -C "$r" commit -qm init
  echo 'fun ok()=2' > "$r/src/Core.kt"
}
# gate <repo> [args]: RC + OUT; chạy từ trong repo
gate() {
  local r="$1"; shift
  OUT="$(cd "$r" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$r" python3 "$GATE" --matrix "$r/matrix.json" --run-tests --no-checklist "$@" 2>&1)"; RC=$?
}
# tree_repo <thư mục>: như make_repo, ma trận commit ở .agents/ (--tree không nhận --matrix), cây sạch, HEAD đã có trên origin (bare cục bộ)
tree_repo() {
  local r="$1"; make_repo "$r"; mkdir -p "$r/.agents"; cp "$r/matrix.json" "$r/.agents/regression_matrix.active.json"
  git -C "$r" add -A && git -C "$r" commit -qm clean
  git init -q --bare "$r.origin.git" && git -C "$r" remote add origin "$r.origin.git" && git -C "$r" push -q -u origin main
}
last_mode() { tail -n 1 "$1/.git/postfix-gate/runs.jsonl" 2>/dev/null | python3 -c 'import json,sys; print(json.loads(sys.stdin.read() or "{}").get("mode",""))' 2>/dev/null; }

i=0
for args in "--full" "--force-full" "ENV:POSTFIX_GATE_FULL=1"; do
  i=$((i + 1)); R="$TMP/work$i"; make_repo "$R"
  case "$args" in
    ENV:*) ( export "${args#ENV:}"; gate "$R"; echo "$RC" > "$TMP/rc" ); RC="$(cat "$TMP/rc")" ;;
    *) gate "$R" $args ;;
  esac
  if [ "$RC" != 0 ] && [ ! -f "$R.ran" ]; then ok "$args ngoài điểm gộp: từ chối, không chạy suite"
  else fail "$args ngoài điểm gộp vẫn chạy (rc=$RC, suite chạy: $([ -f "$R.ran" ] && echo có || echo không))"; fi
done

R="$TMP/work-tree"; tree_repo "$R"
OUT="$(cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --no-checklist --tree HEAD 2>&1)"; RC=$?
if [ "$RC" != 0 ] && [ ! -f "$R.ran" ]; then ok "--tree HEAD ngoài điểm gộp: từ chối"
else fail "--tree HEAD ngoài điểm gộp vẫn chạy (rc=$RC, suite chạy: $([ -f "$R.ran" ] && echo có || echo không))"; fi
# đối chứng: cùng cây ở điểm gộp thì --tree chạy suite (ca trên không đỏ/xanh vì lỗi tham số)
mkdir -p "$TMP/wt"; R="$TMP/wt/.integrate-scratch-tree"; tree_repo "$R"
OUT="$(cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --no-checklist --tree HEAD 2>&1)"; RC=$?
if [ -f "$R.ran" ]; then ok "--tree HEAD ở .integrate-scratch-*: chạy suite"; else fail "--tree HEAD ở điểm gộp không chạy suite (rc=$RC): $(printf '%s' "$OUT" | tail -2)"; fi

R="$TMP/work-lesson"; make_repo "$R"
gate "$R" --record-lesson "bài học thử"
m="$(last_mode "$R")"
if { [ "$RC" != 0 ] && [ ! -f "$R.ran" ]; } || [ "$m" = impacted ]; then ok "--record-lesson không kéo theo lượt full (mode=$m)"
else fail "--record-lesson ngoài điểm gộp chạy full (mode=$m, rc=$RC)"; fi

R="$TMP/work-ci"; make_repo "$R"
( export CI=true; gate "$R"; echo "$RC" > "$TMP/rc" ); RC="$(cat "$TMP/rc")"
m="$(last_mode "$R")"
if { [ "$RC" != 0 ] && [ ! -f "$R.ran" ]; } || [ "$m" = impacted ]; then ok "CI=true không kéo theo lượt full (mode=$m)"
else fail "CI=true ngoài điểm gộp chạy full (mode=$m, rc=$RC)"; fi

for d in .merge-scratch-abc .integrate-scratch-abc .train-scratch-abc; do
  mkdir -p "$TMP/wt"; R="$TMP/wt/$d"; make_repo "$R"
  gate "$R" --full
  if [ -f "$R.ran" ]; then ok "$d: --full vẫn chạy suite"; else fail "$d: --full bị chặn nhầm ở điểm gộp (rc=$RC): $(printf '%s' "$OUT" | tail -3)"; fi
done

[ "$FAILS" = 0 ] && echo "PASS" || echo "FAIL: $FAILS"
exit $(( FAILS > 0 ))
