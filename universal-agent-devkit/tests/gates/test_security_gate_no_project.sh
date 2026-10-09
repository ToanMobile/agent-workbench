#!/usr/bin/env bash
# hooks/security_gate.sh outside a git tree with CLAUDE_PROJECT_DIR unset (2026-10-09 follow-up; fresh-context review). The hook stopped
# looking for a project and exited 0 BEFORE its python3 check, so a box without python3 passed a gate that fails CLOSED there
# ("cần python3 để kiểm tra — chặn để an toàn", exit 2; exit 0 only on the Stop loop-guard pass or with SECURITY_GATE=0).
# Nothing is written outside a git tree (tests/gates/test_hook_log_dir.sh); the fail-closed rule stays.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${SG_HOOK:-$DEVKIT_DIR/hooks/security_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
mkdir -p "$TMP/nopy" "$TMP/n" "$TMP/x"
for t in git date cat mkdir dirname; do ln -s "$(command -v $t)" "$TMP/nopy/$t" 2>/dev/null; done   # PATH with no python3
payload() { printf '{"session_id":"s","transcript_path":"","cwd":"%s","hook_event_name":"Stop"%s}' "$TMP/n" "${1:-}" > "$TMP/in.json"; }
run() { ( cd "$TMP/x" && env -u CLAUDE_PROJECT_DIR "$@" /bin/bash "$HOOK" < "$TMP/in.json" > "$TMP/out" 2> "$TMP/err" ); RC=$?; }

payload; run PATH="$TMP/nopy"
[ "$RC" = 2 ] && grep -q "cần python3" "$TMP/err" && ok "no project, no python3: blocked (exit 2) as before" || fail "no python3: rc=$RC $(head -c 200 "$TMP/err")"
payload ',"stop_hook_active":true'; run PATH="$TMP/nopy"
[ "$RC" = 0 ] && ok "  … passes on the Stop loop-guard pass" || fail "loop-guard pass: rc=$RC"
payload; run PATH="$TMP/nopy" SECURITY_GATE=0
[ "$RC" = 0 ] && ok "  … and with SECURITY_GATE=0" || fail "SECURITY_GATE=0: rc=$RC"
payload; run
[ "$RC" = 0 ] && ok "no project, python3 present: nothing to guard (exit 0)" || fail "with python3: rc=$RC $(head -c 200 "$TMP/err")"
[ -e "$TMP/x/.claude" ] || [ -e "$TMP/n/.claude" ] && fail "a .claude directory was created outside a project" || ok "  … and nothing is created outside a project"

[ "$FAILS" -eq 0 ] && echo "✅ test_security_gate_no_project: all passed" || { echo "❌ test_security_gate_no_project: $FAILS failed"; exit 1; }
