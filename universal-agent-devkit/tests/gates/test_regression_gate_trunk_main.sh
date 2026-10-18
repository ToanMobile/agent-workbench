#!/usr/bin/env bash
# K12 (18/10, Neighbours/OfficeReader): hooks/regression_gate.sh ở MAIN checkout trong trunk mode đòi "chạy post-fix-gate --full" trong khi
# bin/session_lock.py cấm chạy gate (và mọi lần ghi) ở main: vòng lặp không lối ra, và Stop của phiên ở main còn chạy lại suite nặng (Unity)
# trên main cho thứ đã qua gate gộp. Luật:
#   1 trunk mode, phiên (có session_id) dừng ở main, main bẩn vì thứ không phải của nó: không chạy suite, không chặn, log nói vì sao
#   2 trunk mode tắt: như cũ (suite đỏ chặn Stop)
#   3 payload không có session_id / transcript Claude (Grok / agent bắc cầu): như cũ, vẫn gate
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/repo"
stop() { printf '%s' "$1" | env -u WORKTREE_TRUNK_MODE REGRESSION_GATE_MAX_SESSION_BLOCKS=99 CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
N=0; change() { N=$((N + 1)); echo "fun ok() = $N" > src/Core.kt; }

mkdir -p "$REPO/src" "$REPO/templates" && cd "$REPO" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo "fun ok() = 0" > src/Core.kt
cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core flow","command":"sh result.sh"}]}]}
JSON
echo 'touch ran.marker; exit 1' > result.sh
printf 'ran.marker\n.claude/\n' > .gitignore
git add -A && git commit -qm init

# 2 (đối chứng trước) trunk mode tắt, CÙNG payload với ca 1 (transcript Claude + XONG): suite đỏ chặn — chỉ trunk mode khác (OCR 18/10)
git config devkit.trunkMode false
printf '%s\n' '{"type":"user","timestamp":"2026-10-18T00:00:00Z","message":{"role":"user","content":"go"}}' > "$TMP/t.jsonl"
change; rm -f ran.marker; stop "{\"session_id\":\"s-1\",\"hook_event_name\":\"Stop\",\"transcript_path\":\"$TMP/t.jsonl\",\"last_assistant_message\":\"XONG\\nđã sửa\"}"; rc=$?
[ "$rc" = 2 ] && [ -e ran.marker ] && ok "trunk mode off: the failing suite runs and blocks (rc 2)" || fail "trunk off: rc $rc (want 2)"

# 1 trunk mode bật, phiên Claude Code (có transcript) ở main: không chạy, không chặn
git config devkit.trunkMode true
printf '%s\n' '{"type":"user","timestamp":"2026-10-18T00:00:00Z","message":{"role":"user","content":"go"}}' > "$TMP/t.jsonl"
change; rm -f ran.marker; stop "{\"session_id\":\"s-1\",\"hook_event_name\":\"Stop\",\"transcript_path\":\"$TMP/t.jsonl\",\"last_assistant_message\":\"XONG\\nđã sửa\"}"; rc=$?   # lượt bàn giao: không lọt nhánh "đang làm dở"
[ "$rc" = 0 ] && [ ! -e ran.marker ] && ok "trunk mode, Stop at main: no suite run on main, not held (rc 0)" \
  || fail "trunk main: rc $rc (want 0), suite ran: $( [ -e ran.marker ] && echo yes || echo no); err=$(head -c 300 "$TMP/err")"
grep -q "trunk mode" .claude/audit-gate/regression_gate.log 2>/dev/null && ok "  … the log says why" || fail "no log line for the trunk-mode skip"

# 3 không có session_id: vẫn gate như cũ
change; rm -f ran.marker; stop '{"hook_event_name":"Stop"}'; rc=$?
[ "$rc" = 2 ] && [ -e ran.marker ] && ok "no session id (bridged agent): still gated, the suite ran (rc 2)" || fail "no session id: rc $rc (want 2)"

# 4 có session_id nhưng KHÔNG có transcript Claude (Grok gửi session_id): vẫn gate (OCR 18/10: nhánh `degraded` phải có test)
change; rm -f ran.marker; stop '{"session_id":"s-1","hook_event_name":"Stop","last_assistant_message":"XONG"}'; rc=$?
[ "$rc" = 2 ] && [ -e ran.marker ] && ok "session id but no Claude transcript (degraded): still gated (rc 2)" || fail "degraded with session id: rc $rc (want 2)"

# 5 trunk mode, phiên Claude ở WORKTREE của chính nó (không phải main): vẫn gate (chỉ main được bỏ qua)
git checkout -q -- src/Core.kt
git worktree add -q --detach "$REPO/.claude/worktrees/w5" HEAD
mkdir -p .claude/audit-gate/session_worktree && printf '%s\n' "$REPO/.claude/worktrees/w5" > .claude/audit-gate/session_worktree/s-5
echo "fun ok() = 55" > "$REPO/.claude/worktrees/w5/src/Core.kt"; rm -f "$REPO/.claude/worktrees/w5/ran.marker"
stop "{\"session_id\":\"s-5\",\"hook_event_name\":\"Stop\",\"cwd\":\"$REPO/.claude/worktrees/w5\",\"transcript_path\":\"$TMP/t.jsonl\",\"last_assistant_message\":\"XONG\"}"; rc=$?
[ "$rc" = 2 ] && [ -e "$REPO/.claude/worktrees/w5/ran.marker" ] && ok "trunk mode, Stop in the session's own worktree: still gated there (rc 2)" \
  || fail "own worktree in trunk mode skipped (rc $rc, ran: $( [ -e "$REPO/.claude/worktrees/w5/ran.marker" ] && echo yes || echo no)): $(head -c 300 "$TMP/err")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_regression_gate_trunk_main: PASS"; exit 0; } || { echo "test_regression_gate_trunk_main: FAIL ($FAILS)"; exit 1; }
