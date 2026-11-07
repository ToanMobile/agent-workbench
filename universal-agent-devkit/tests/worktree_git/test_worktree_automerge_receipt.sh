#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 1): `worktree automerge` (đường Stop hook) KHÔNG chạy suite nào. Có ma trận gate:
#   1  không biên nhận ⇒ needs_gate (exit 4), main và worktree không đổi, suite không chạy
#   2  biên nhận scoped của đúng cây (agent tự chạy gate trong worktree), main là tổ tiên ⇒ fast-forward main, không chạy suite
#   3  main đi tiếp (không còn là tổ tiên) ⇒ needs_gate, không gộp main vào worktree
#   4  sửa worktree sau lượt gate (biên nhận không còn khớp cây) ⇒ needs_gate
#   5  `worktree finish` vẫn chạy gate (--scoped)
#   6  repo không ma trận ⇒ automerge gộp như cũ
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_SESSION_ID \
      CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_SLOT_PRIORITY CLAUDE_PROJECT_DIR DEVKIT_GATE_CACHE_MAX_S
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export GIT_CONFIG_GLOBAL=/dev/null
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GATE_COUNT="$TMP/count"

repo() {   # repo <name> [nomatrix]
  local p="$TMP/$1"; mkdir -p "$p/.agents" && G "$p" init -q -b main . && G "$p" config user.email t@t && G "$p" config user.name t
  printf 'greet() { echo ok; }\n' > "$p/lib.sh"
  printf '. ./lib.sh\ngreet\n' > "$p/app.sh"
  printf 'echo run >> "$GATE_COUNT"\nfor f in app*.sh; do [ "$(bash "$f" 2>/dev/null)" = ok ] || { echo "FAIL $f"; exit 1; }; done\necho ok\n' > "$p/check.sh"
  echo '{"profile":"backend"}' > "$p/.agents/active-profile.json"
  [ "${2:-}" = nomatrix ] || printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"apps","command":"bash check.sh"}]}]}\n' \
    > "$p/.agents/regression_matrix.active.json"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n.agents/evidence/\n.agents/regression_journal/\n.claude/\n' > "$p/.gitignore"
  G "$p" add -A && G "$p" commit -qm base
}
wtadd() { (cd "$TMP/$1" && python3 "$WT" add "$TMP/$1-w" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1-w"; }
work() { printf '. ./lib.sh\ngreet\n' > "$TMP/$1-w/app2.sh" && G "$TMP/$1-w" add app2.sh && G "$TMP/$1-w" commit -qm "app2"; }
am() { (cd "$TMP/$1" && python3 "$WT" automerge "$TMP/$1-w" --keep > "$TMP/out" 2>&1); AM=$?; }
st() { python3 -c 'import json,sys; print(json.loads([l for l in open(sys.argv[1]) if l.startswith("{")][-1]).get("status"))' "$TMP/out" 2>/dev/null; }
runs() { [ -f "$GATE_COUNT" ] && wc -l < "$GATE_COUNT" | tr -d ' ' || echo 0; }

# 1
repo a; wtadd a; work a
M0="$(G "$TMP/a" rev-parse HEAD)"; W0="$(G "$TMP/a-w" rev-parse HEAD)"; rm -f "$GATE_COUNT"
am a
[ "$AM" = 4 ] && [ "$(st)" = needs_gate ] && grep -q "worktree finish" "$TMP/out" && ok "1. không biên nhận ⇒ needs_gate exit 4, nêu worktree finish" \
  || fail "1. rc=$AM status=$(st) $(tail -3 "$TMP/out")"
[ "$(G "$TMP/a" rev-parse HEAD)" = "$M0" ] && [ "$(G "$TMP/a-w" rev-parse HEAD)" = "$W0" ] && [ "$(runs)" = 0 ] \
  && ok "1. main, worktree không đổi; không suite nào chạy" || fail "1. main/worktree đổi hoặc suite chạy ($(runs))"

# 2
( cd "$TMP/a-w" && python3 "$GATE" --run-tests --scoped --brief ) > "$TMP/gout" 2>&1; g=$?
[ "$g" = 0 ] && [ "$(runs)" = 1 ] || { fail "2. gate của agent rc=$g runs=$(runs)"; tail -15 "$TMP/gout"; }
am a
[ "$AM" = 0 ] && [ "$(st)" = merged ] && [ "$(G "$TMP/a" rev-parse HEAD)" = "$W0" ] && [ "$(runs)" = 1 ] \
  && ok "2. biên nhận scoped của cây ⇒ fast-forward main, không chạy suite" || fail "2. rc=$AM status=$(st) runs=$(runs) $(tail -3 "$TMP/out")"

# 3
repo b; wtadd b; work b
( cd "$TMP/b-w" && python3 "$GATE" --run-tests --scoped --brief ) > "$TMP/gout" 2>&1
echo note > "$TMP/b/notes.txt" && G "$TMP/b" add notes.txt && G "$TMP/b" commit -qm "main moves"
M1="$(G "$TMP/b" rev-parse HEAD)"; W1="$(G "$TMP/b-w" rev-parse HEAD)"; rm -f "$GATE_COUNT"
am b
[ "$AM" = 4 ] && [ "$(G "$TMP/b" rev-parse HEAD)" = "$M1" ] && [ "$(G "$TMP/b-w" rev-parse HEAD)" = "$W1" ] && [ "$(runs)" = 0 ] \
  && ok "3. main đi tiếp ⇒ needs_gate, không gộp main vào worktree, không suite" || fail "3. rc=$AM status=$(st) runs=$(runs)"

# 4
repo c; wtadd c; work c
( cd "$TMP/c-w" && python3 "$GATE" --run-tests --scoped --brief ) > "$TMP/gout" 2>&1
printf '. ./lib.sh\ngreet\n# later\n' > "$TMP/c-w/app2.sh" && G "$TMP/c-w" commit -qam later
M2="$(G "$TMP/c" rev-parse HEAD)"; rm -f "$GATE_COUNT"
am c
[ "$AM" = 4 ] && [ "$(G "$TMP/c" rev-parse HEAD)" = "$M2" ] && [ "$(runs)" = 0 ] && ok "4. cây đổi sau gate ⇒ needs_gate" || fail "4. rc=$AM status=$(st)"

# 5
rm -f "$GATE_COUNT"
(cd "$TMP/c" && python3 "$WT" finish "$TMP/c-w" > "$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(runs)" -ge 1 ] && [ -f "$TMP/c/app2.sh" ] && ok "5. finish vẫn chạy gate rồi gộp" || fail "5. rc=$rc runs=$(runs) $(tail -3 "$TMP/out")"

# 6
repo d nomatrix; wtadd d; work d
am d
[ "$AM" = 0 ] && [ "$(st)" = merged ] && [ -f "$TMP/d/app2.sh" ] && ok "6. không ma trận ⇒ gộp như cũ" || fail "6. rc=$AM status=$(st) $(tail -3 "$TMP/out")"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
