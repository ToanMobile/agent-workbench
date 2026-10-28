#!/bin/bash
# hooks/instincts_file_context.py (#555): a Read/Edit of a file matching an instinct's `glob` line injects that entry once per session; never blocks.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_ROOT/hooks/instincts_file_context.py"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
ERRORS=0
fail() { echo "FAIL: $1"; ERRORS=$((ERRORS+1)); }

mkdir -p "$D/.agents" "$D/src/api"
cat > "$D/.agents/instincts.md" <<'MD'
# Instincts

---

## 1. Active

### [INSTINCT-001] Trap With Glob
- **Symptom:** api handlers swallow errors
- **glob:** `src/api/**`, `*.sql`

---

### [INSTINCT-002] Trap Without Glob
- **Symptom:** never surfaced by file

---

### [INSTINCT-003] Other Glob Trap
- **Symptom:** docs trap
- **glob:** docs/*.md
MD
export CLAUDE_PROJECT_DIR="$D"
run() { # $1 session, $2 tool, $3 file
  printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" "$3" | python3 -I "$HOOK"
}

echo "--- matching Read injects exactly that entry ---"
OUT=$(run s1 Read "$D/src/api/users.py"); RC=$?
[ $RC -eq 0 ] || fail "exit $RC on a match"
echo "$OUT" | python3 -c 'import sys,json; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"]=="PreToolUse"; c=d["additionalContext"]; assert "INSTINCT-001" in c and "swallow errors" in c; assert "INSTINCT-002" not in c and "INSTINCT-003" not in c' 2>/dev/null || fail "context lacks INSTINCT-001 only: $OUT"

echo "--- second Read in the same session is silent ---"
OUT=$(run s1 Read "$D/src/api/other.py"); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] || fail "re-injected in the same session (rc=$RC): $OUT"

echo "--- a new session injects again; Edit and a second glob work ---"
OUT=$(run s2 Edit "$D/db/schema.sql")
echo "$OUT" | grep -q "INSTINCT-001" || fail "new session / *.sql glob: $OUT"

echo "--- no glob match: silent exit 0 ---"
OUT=$(run s3 Read "$D/README.md"); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] || fail "non-matching file spoke (rc=$RC): $OUT"

echo "--- an entry without glob never fires; a file outside the project is silent ---"
OUT=$(run s4 Read "/etc/hosts"); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] || fail "outside file spoke: $OUT"

echo "--- broken input / missing instincts file never blocks ---"
echo "not json" | python3 -I "$HOOK"; [ $? -eq 0 ] || fail "malformed payload blocked"
rm "$D/.agents/instincts.md"
OUT=$(run s5 Read "$D/src/api/x.py"); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] || fail "missing instincts.md (rc=$RC): $OUT"

echo "--- hook crash is logged and exits 0 ---"
printf '# x\n\n### [INSTINCT-009] T\n- **glob:** `[`\n' > "$D/.agents/instincts.md"
OUT=$(run s6 Read "$D/a.py" 2>"$D/err"); RC=$?
[ $RC -eq 0 ] || fail "bad glob blocked (rc=$RC)"

echo "--- a real crash (undecodable instincts.md) is logged to the .err file and exits 0 ---"
printf '\377\376 not utf8\n' > "$D/.agents/instincts.md"
OUT=$(run s7 Read "$D/a.py" 2>/dev/null); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] || fail "crash blocked or spoke (rc=$RC): $OUT"
grep -q "UnicodeDecodeError" "$D/.claude/audit-gate/instincts_file_context.err" 2>/dev/null || fail "crash not logged to .err"

[ $ERRORS -eq 0 ] && echo "PASS" || { echo "$ERRORS failure(s)"; exit 1; }
