#!/usr/bin/env bash
# Regression test: hooks/review_gate.sh does not count a symlink (a DevKit hook link such
# as .claude/hooks/devkit_profile.py) as uncommitted code needing review — a real
# untracked source file still does.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P/.claude/hooks"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm i)
stop() { printf '{"session_id":"s","transcript_path":"/dev/null","hook_event_name":"Stop"}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>&1; }
ln -s "$DEVKIT_DIR/hooks/devkit_profile.py" "$P/.claude/hooks/devkit_profile.py"
stop; [ $? = 0 ] && grep -q "no uncommitted code" "$P/.claude/audit-gate/review_gate.log" \
  && ok "a DevKit hook link is not uncommitted code" || fail "symlink counted as code to review"
echo "def f(): return 1" > "$P/app.py"
stop; rc=$?
grep -q "no uncommitted code" <(tail -1 "$P/.claude/audit-gate/review_gate.log") && fail "untracked source not seen (rc=$rc)" \
  || ok "a real untracked source file is still seen"
if [ "$FAILS" -ne 0 ]; then echo "review gate: $FAILS FAILED"; exit 1; fi
echo "review gate: all checks passed"
