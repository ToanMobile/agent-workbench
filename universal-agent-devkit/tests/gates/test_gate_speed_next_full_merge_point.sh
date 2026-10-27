#!/usr/bin/env bash
# Test hồi quy #472 mục A (bớt --full): push lên trunk / release/* chỉ đi qua `agent-kit integrate` (điểm gộp chạy --full MỘT lần trong
# scratch rồi tự push). Push trực tiếp qua hook block-dangerous-git bị từ chối với lời chỉ đường "agent-kit integrate", không bảo chạy
# --full, và không vòng lặp (push không gửi gì mới thì cho qua). Biên nhận --full do agent tự chạy không mở được trunk; env (CI,
# POSTFIX_GATE_FULL, POSTFIX_GATE_FORCE_FULL) cũng không. Nhánh PR giữ nguyên. Đối chứng: integrate vẫn push được; CI=true,
# --record-lesson, POSTFIX_GATE_FORCE_FULL vẫn chạy full ở post-fix-gate; POSTFIX_GATE_FULL đặt toàn cục không lọt vào lượt gate
# của Stop hook (lượt Stop là impacted, không bị chặn).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL CI DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE DEVKIT_PER_TEST_CACHE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
HOOK="$DEVKIT_DIR/hooks/block-dangerous-git.sh"
STOP_HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
INTEGRATE="$DEVKIT_DIR/scripts/git/integrate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$HOME" "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# hook <repo> <lệnh>: RC + ERR của block-dangerous-git cho một lệnh Bash chạy trong <repo>
hook() {
  ERR="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$2" "$1" \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1 >/dev/null)"; RC=$?
}
# refused <tên>: RC 2, lời chỉ "agent-kit integrate", không có "--full" (không bảo chạy lại gate --full: vòng lặp cũ)
refused() {
  if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'agent-kit integrate' && ! printf '%s' "$ERR" | grep -q -- '--full'; then ok "$1"
  else fail "$1 (rc=$RC): $(printf '%s' "$ERR" | tail -c 400)"; fi
}
allowed() { if [ "$RC" = 0 ]; then ok "$1"; else fail "$1 (rc=$RC): $(printf '%s' "$ERR" | tail -c 400)"; fi; }
fullgate() { (cd "$1" && CLAUDE_PROJECT_DIR="$1" FLAKY_RETRY=0 VACUITY_REVERT=0 python3 "$GATE" --run-tests --full --brief --no-checklist "${@:2}" >/dev/null 2>&1); }

# repo <thư mục>: ma trận một suite (ghi một dòng vào <thư mục>.ran khi chạy), origin bare, HEAD đã trên origin, một commit chờ
repo() {
  local r="$1"
  git init -q --bare -b main "$r.origin.git"
  mkdir -p "$r/src" "$r/.agents" && git -C "$r" init -q -b main . && git -C "$r" config user.email t@t && git -C "$r" config user.name t
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> %s.ran"}]}]}\n' "$r" \
    > "$r/.agents/regression_matrix.active.json"
  printf '.claude/\n.agents/regression_checklist.md\n.agents/regression_status.json\n' > "$r/.gitignore"
  echo 'fun ok()=1' > "$r/src/Core.kt"
  git -C "$r" add -A && git -C "$r" commit -qm init
  git -C "$r" remote add origin "$r.origin.git" && git -C "$r" push -q -u origin main 2>/dev/null
  git -C "$r" remote set-head origin main >/dev/null 2>&1
  echo 'fun ok()=2' > "$r/src/Core.kt" && git -C "$r" commit -qam fix
}

# ── 1. push trực tiếp lên trunk qua hook: từ chối dù có biên nhận --full hợp lệ ─────────────────────────────────────────────
R="$TMP/r1"; repo "$R"
fullgate "$R" --diff origin/main
[ -f "$R/.git/postfix-gate/full_pass.json" ] || fail "đối chứng: gate --full không ghi biên nhận (ca dưới vô nghĩa)"
hook "$R" "git push origin main";               refused "trunk main, có biên nhận --full: từ chối, chỉ agent-kit integrate"
hook "$R" "git push";                           refused "git push trần ở main: từ chối"
hook "$R" "git push origin HEAD:refs/heads/main"; refused "HEAD:refs/heads/main: từ chối"
git -C "$R" branch -q release/1.0
hook "$R" "git push origin release/1.0";        refused "release/1.0: từ chối"
hook "$R" "git -c color.ui=never push origin main"; refused "đích không rõ (-c): từ chối (fail closed)"
hook "$R" "git push --all origin";              refused "--all mang commit trunk mới: từ chối"
git -C "$R" tag v9
hook "$R" "git push origin v9";                 refused "tag mang commit remote chưa có: từ chối"
for e in CI=true POSTFIX_GATE_FULL=1 POSTFIX_GATE_FORCE_FULL=1; do
  ( export "$e"; hook "$R" "git push origin main"; printf '%s\n%s' "$RC" "$ERR" > "$TMP/envout" )
  RC="$(head -1 "$TMP/envout")"; ERR="$(tail -n +2 "$TMP/envout")"
  refused "$e trong env của hook không mở được trunk"
done
# nhánh PR giữ nguyên (đối chứng)
git -C "$R" branch -q feat/x
hook "$R" "git push origin feat/x";             allowed "nhánh PR feat/x: vẫn cho, không cần biên nhận"

# ── 2. không vòng lặp: nội dung đã trên origin (integrate đã push) thì push tay cho qua ─────────────────────────────────────
git -C "$R" push -q origin main 2>/dev/null     # (ngoài hook: như integrate tự push)
rm -f "$R/.git/postfix-gate/full_pass.json"
hook "$R" "git push origin main";               allowed "main đã bằng origin, không biên nhận: cho (không vòng lặp)"
hook "$R" "git push";                           allowed "git push trần, không gì mới: cho"
hook "$R" "git push origin v9";                 allowed "tag của commit origin đã có: cho"
# bẫy fail-open: commit đã lên origin nhưng chỉ ở nhánh PR (chưa gate) — "remote đã có commit" không được là "không gì mới" cho main
echo 'fun ok()=3' > "$R/src/Core.kt" && git -C "$R" commit -qam "PR code, never gated"
git -C "$R" branch -qf feat/x && git -C "$R" push -q origin feat/x 2>/dev/null
hook "$R" "git push origin main";               refused "commit chỉ có trên nhánh PR của origin, push main: từ chối"
hook "$R" "git push origin feat/x:main";        refused "feat/x:main (local main chứa feat/x): từ chối"

# ── 3. worktree tự đặt tên .integrate-scratch-* + --full trong đó: hook vẫn từ chối (không giả được integrate) ──────────────
R="$TMP/r3"; repo "$R"
mkdir -p "$R/.claude/worktrees" && git -C "$R" worktree add -q --detach "$R/.claude/worktrees/.integrate-scratch-fake" HEAD 2>/dev/null
fullgate "$R/.claude/worktrees/.integrate-scratch-fake" --diff refs/remotes/origin/main
hook "$R" "git push origin main";               refused "biên nhận của worktree .integrate-scratch-* tự dựng: hook vẫn từ chối"

# ── 4. integrate push được (đường thật: scripts/git/integrate.py) ────────────────────────────────────────────────────────────
git -C "$R" worktree remove --force "$R/.claude/worktrees/.integrate-scratch-fake" 2>/dev/null
want="$(git -C "$R" rev-parse HEAD)"
OUT="$(cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 python3 "$INTEGRATE" "$R" 2>&1)"; RC=$?
got="$(git -C "$R.origin.git" rev-parse main 2>/dev/null)"
if [ "$RC" = 0 ] && [ "$got" = "$want" ] && [ -f "$R.ran" ]; then ok "agent-kit integrate: gate --full trong scratch rồi push được"
else fail "integrate không push (rc=$RC, origin=$got, muốn $want): $(printf '%s' "$OUT" | tail -5)"; fi

# ── 5. post-fix-gate: CI=true, POSTFIX_GATE_FORCE_FULL=1, --record-lesson vẫn chạy full (đối chứng, không đổi) ────────────────
last_mode() { tail -n 1 "$1/.git/postfix-gate/runs.jsonl" 2>/dev/null | python3 -c 'import json,sys; print(json.loads(sys.stdin.read() or "{}").get("mode",""))' 2>/dev/null; }
for c in CI=true POSTFIX_GATE_FORCE_FULL=1 LESSON; do
  R="$TMP/g-${c%%=*}"; repo "$R"; echo 'fun ok()=7' > "$R/src/Core.kt"
  if [ "$c" = LESSON ]; then (cd "$R" && CLAUDE_PROJECT_DIR="$R" FLAKY_RETRY=0 VACUITY_REVERT=0 python3 "$GATE" --run-tests --brief --no-checklist --record-lesson "bài học thử" >/dev/null 2>&1)
  else (export "$c"; cd "$R" && CLAUDE_PROJECT_DIR="$R" FLAKY_RETRY=0 VACUITY_REVERT=0 python3 "$GATE" --run-tests --brief --no-checklist >/dev/null 2>&1); fi
  m="$(last_mode "$R")"
  if [ "$m" = full ] && [ -f "$R.ran" ]; then ok "$c: post-fix-gate vẫn chạy full (mode=$m)"; else fail "$c: post-fix-gate không chạy full (mode=$m)"; fi
done

# ── 6. Stop hook: POSTFIX_GATE_FULL=1 toàn cục không biến lượt gate của Stop thành full, Stop không bị chặn ───────────────────
# (gate xoá POSTFIX_GATE_FULL khỏi env của suite, nên phân biệt bằng `mode` của dòng runs.jsonl lượt Stop ghi; đối chứng: không env)
for e in NONE POSTFIX_GATE_FULL=1; do
  R="$TMP/stop-${e%%=*}"; mkdir -p "$R/src" "$R/templates"
  git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> %s.ran"}]}]}\n' "$R" > "$R/templates/regression_matrix.json"
  echo 'fun ok()=1' > "$R/src/Core.kt" && git -C "$R" add -A && git -C "$R" commit -qm init
  echo 'fun ok()=2' > "$R/src/Core.kt"
  printf '{"session_id":"s-1","hook_event_name":"Stop"}' | (cd "$R" || exit 1; [ "$e" = NONE ] || export "$e"
    WORKTREE_TRUNK_MODE=0 CLAUDE_PROJECT_DIR="$R" bash "$STOP_HOOK" >"$TMP/stop.out" 2>"$TMP/stop.err"); RC=$?
  m="$(last_mode "$R")"
  if [ "$RC" = 0 ] && [ -f "$R.ran" ] && [ -n "$m" ] && [ "$m" != full ]; then ok "Stop hook ($e): suite chạy, mode=$m (không full), Stop không bị chặn"
  else fail "Stop hook ($e): rc=$RC, suite chạy: $([ -f "$R.ran" ] && echo có || echo không), mode='$m': $(tail -c 300 "$TMP/stop.err")"; fi
done

# ── 6b. như mục 6 nhưng trunk mode BẬT (repo thật): phiên trong worktree, main chỉ để gộp ─────────────────────────────────────
for e in NONE POSTFIX_GATE_FULL=1; do
  R="$TMP/trunk-${e%%=*}"; mkdir -p "$R/src" "$R/templates"
  git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> %s.ran"}]}]}\n' "$R" > "$R/templates/regression_matrix.json"
  printf '.claude/\n' > "$R/.gitignore"
  echo 'fun ok()=1' > "$R/src/Core.kt" && git -C "$R" add -A && git -C "$R" commit -qm init
  W="$R/.claude/worktrees/wt"; git -C "$R" worktree add -q --detach "$W" HEAD 2>/dev/null
  echo 'fun ok()=2' > "$W/src/Core.kt"
  printf '{"session_id":"s-1","hook_event_name":"Stop"}' | (cd "$W" || exit 1; [ "$e" = NONE ] || export "$e"
    WORKTREE_TRUNK_MODE=1 CLAUDE_PROJECT_DIR="$W" bash "$STOP_HOOK" >"$TMP/stop.out" 2>"$TMP/stop.err"); RC=$?
  m="$(last_mode "$W")"; [ -n "$m" ] || m="$(last_mode "$R")"
  if [ "$RC" = 0 ] && [ -f "$R.ran" ] && [ -n "$m" ] && [ "$m" != full ]; then ok "Stop hook trunk mode ($e): suite chạy, mode=$m (không full), Stop không bị chặn"
  else fail "Stop hook trunk mode ($e): rc=$RC, suite chạy: $([ -f "$R.ran" ] && echo có || echo không), mode='$m': $(tail -c 300 "$TMP/stop.err")"; fi
done

# ── 7. argv của chế độ chặt (gọi thẳng push_gate): main = origin nên đúng dạng thì cho; mọi dạng lệch phải từ chối ─────────
R="$TMP/argv"; repo "$R"; git -C "$R" push -q origin main 2>/dev/null
PG="$DEVKIT_DIR/bin/push_gate.py"
pg() { python3 "$PG" "$R" "$@" >/dev/null 2>&1; echo $?; }
[ "$(pg HEAD --dst origin main --via-hook origin)" = 0 ] && ok "argv: đúng dạng, không gì mới: cho (đối chứng)" || fail "argv: đúng dạng bị từ chối"
[ "$(pg HEAD --dst origin main --via-hook)" = 2 ] && ok "argv: --via-hook thiếu giá trị: từ chối" || fail "argv: --via-hook thiếu giá trị lọt"
[ "$(pg HEAD --dst origin main --via-hook origin --via-hook origin)" = 2 ] && ok "argv: hai --via-hook: từ chối" || fail "argv: hai --via-hook lọt"
git -C "$R" remote add other "$R.origin.git"
[ "$(pg HEAD --dst other main --via-hook origin)" = 2 ] && ok "argv: remote của --dst khác --via-hook: từ chối" || fail "argv: --dst lệch remote lọt"
# repo không có ma trận hồi quy: push_gate chưa áp, như luật cũ
rm "$R/.agents/regression_matrix.active.json"; echo 'fun ok()=9' > "$R/src/Core.kt" && git -C "$R" commit -qam nomatrix
[ "$(pg HEAD --dst origin main --via-hook origin)" = 0 ] && ok "repo không ma trận: cho, như cũ" || fail "repo không ma trận bị từ chối"

[ "$FAILS" = 0 ] && echo "PASS" || echo "FAIL: $FAILS"
exit $(( FAILS > 0 ))
