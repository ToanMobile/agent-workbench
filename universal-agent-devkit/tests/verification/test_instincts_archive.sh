#!/bin/bash
# instincts.py archive / duplicates (#554): dry-run default, --apply moves verbatim, keep flag, cross-repo duplicates.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D"
ERRORS=0
fail() { echo "FAIL: $1"; ERRORS=$((ERRORS+1)); }

NOW=$(date +%s)
iso() { python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime($NOW - int(sys.argv[1])*86400)))" "$1"; }
day() { python3 -c "import time,sys; print(time.strftime('%Y-%m-%d', time.localtime($NOW - int(sys.argv[1])*86400)))" "$1"; }

mk_repo() { # $1 dir, rest: "ID|Title|found-days-ago|extra-line"
  local dir=$1; shift
  mkdir -p "$dir/.agents"
  printf '# Instincts\n\n---\n\n## 1. Active\n' > "$dir/.agents/instincts.md"
  local row
  for row in "$@"; do
    IFS='|' read -r id title age extra <<< "$row"
    {
      printf '\n### [INSTINCT-%s] %s\n- **Found on:** %s\n- **Symptom:** s %s\n' "$id" "$title" "$(day "$age")" "$id"
      [ -n "$extra" ] && printf -- '- **keep:** %s\n' "$extra"
      printf '\n---\n'
    } >> "$dir/.agents/instincts.md"
  done
}

# A: 001 surfaced recently, 002 never surfaced, 003 never surfaced but keep, 004 never surfaced but young
mk_repo A "001|Seen Trap|90|" "002|Stale Trap|90|" "003|Rare But Deadly|90|rare severe" "004|Young Trap|2|"
mkdir -p A/.claude/audit-gate
{
  echo "{\"ts\": \"$(iso 60)\", \"session\": \"s\", \"prompt_sha1\": \"x\", \"instinct_ids\": [], \"instinct_refs\": []}"
  echo "{\"ts\": \"$(iso 3)\", \"session\": \"s\", \"prompt_sha1\": \"y\", \"instinct_ids\": [\"INSTINCT-001\", \"INSTINCT-002\"], \"instinct_refs\": [{\"id\": \"INSTINCT-001\", \"file\": \".agents/instincts.md\", \"line\": 9}, {\"id\": \"INSTINCT-002\", \"file\": \"profiles/android/instincts.md\", \"line\": 9}]}"
} > A/.claude/audit-gate/surfaced.jsonl
export CLAUDE_PROJECT_DIR="$D/A"
cp A/.agents/instincts.md before.md

echo "--- dry-run lists the stale entry, writes nothing ---"
OUT=$(python3 -I "$DEVKIT_ROOT/bin/instincts.py" archive --days 30 2>&1); RC=$?
[ $RC -eq 0 ] || fail "dry-run exit $RC: $OUT"
echo "$OUT" | grep -q "INSTINCT-002" || fail "dry-run does not list INSTINCT-002 (id surfaced only from another file counts as unseen)"
for kept in 001 003 004; do echo "$OUT" | grep -q "INSTINCT-$kept" && fail "dry-run lists INSTINCT-$kept"; done
cmp -s before.md A/.agents/instincts.md || fail "dry-run modified instincts.md"
[ -e A/.agents/instincts-archive.md ] && fail "dry-run created the archive"

echo "--- --apply moves verbatim, keeps flagged/young/seen ---"
BLOCK=$(awk '/^### \[INSTINCT-002\]/{p=1} p&&/^---$/{exit} p' before.md)
python3 -I "$DEVKIT_ROOT/bin/instincts.py" archive --days 30 --apply >/dev/null 2>&1 || fail "--apply exit non-zero"
grep -q "INSTINCT-002" A/.agents/instincts.md && fail "INSTINCT-002 still in instincts.md"
grep -qF -- "$BLOCK" A/.agents/instincts-archive.md || fail "archive does not hold INSTINCT-002 verbatim"
for kept in 001 003 004; do grep -q "\[INSTINCT-$kept\]" A/.agents/instincts.md || fail "INSTINCT-$kept lost"; done
grep -q "INSTINCT-003" A/.agents/instincts-archive.md && fail "keep-flagged entry archived"
perl -0777 -ne 'exit(!/---\s*\n\s*---/)' A/.agents/instincts.md && fail "double separator left in instincts.md"

echo "--- second --apply is a no-op ---"
cp A/.agents/instincts.md once.md
python3 -I "$DEVKIT_ROOT/bin/instincts.py" archive --days 30 --apply >/dev/null 2>&1
cmp -s once.md A/.agents/instincts.md || fail "second --apply changed instincts.md"

echo "--- add after --apply never reuses an archived id (R1) ---"
mk_repo H "001|Seen Trap|90|" "002|Stale Trap|90|" "003|Top Stale Trap|90|"
mkdir -p H/.claude/audit-gate
{
  echo "{\"ts\": \"$(iso 60)\", \"session\": \"s\", \"prompt_sha1\": \"x\", \"instinct_ids\": [], \"instinct_refs\": []}"
  echo "{\"ts\": \"$(iso 3)\", \"session\": \"s\", \"prompt_sha1\": \"y\", \"instinct_ids\": [\"INSTINCT-001\"], \"instinct_refs\": [{\"id\": \"INSTINCT-001\", \"file\": \".agents/instincts.md\", \"line\": 9}]}"
} > H/.claude/audit-gate/surfaced.jsonl
CLAUDE_PROJECT_DIR="$D/H" python3 -I "$DEVKIT_ROOT/bin/instincts.py" archive --days 30 --apply >/dev/null 2>&1 || fail "H --apply exit non-zero"
grep -q "INSTINCT-003" H/.agents/instincts-archive.md || fail "H: INSTINCT-003 not archived (setup)"
OUT=$(CLAUDE_PROJECT_DIR="$D/H" python3 -I "$DEVKIT_ROOT/bin/instincts.py" add "Fresh Lesson After Archive" 2>&1) || fail "H add exit non-zero: $OUT"
grep -q "INSTINCT-003\] Fresh" H/.agents/instincts.md && fail "add reused archived id INSTINCT-003"
grep -q "INSTINCT-004\] Fresh Lesson" H/.agents/instincts.md || fail "add did not issue INSTINCT-004"

echo "--- enrich_context still loads instincts.md, not the archive (AC3) ---"
OUT=$(CLAUDE_PROJECT_DIR="$D/H" python3 -I "$DEVKIT_ROOT/scripts/context/enrich_context.py" "Seen Trap" 2>&1)
echo "$OUT" | grep -q "INSTINCT-001" || fail "enrich_context lost INSTINCT-001 from instincts.md after archive"
echo "$OUT" | grep -q "Top Stale Trap" && fail "enrich_context surfaced an archived entry"

echo "--- #620: entry edited while archive waits for the lock is archived with its NEW text ---"
mk_repo L "001|Seen Trap|90|" "002|Stale Trap|90|"
mkdir -p L/.claude/audit-gate
{
  echo "{\"ts\": \"$(iso 60)\", \"session\": \"s\", \"prompt_sha1\": \"x\", \"instinct_ids\": [], \"instinct_refs\": []}"
  echo "{\"ts\": \"$(iso 3)\", \"session\": \"s\", \"prompt_sha1\": \"y\", \"instinct_ids\": [\"INSTINCT-001\"], \"instinct_refs\": [{\"id\": \"INSTINCT-001\", \"file\": \".agents/instincts.md\", \"line\": 9}]}"
} > L/.claude/audit-gate/surfaced.jsonl
rm -f L/held
python3 -I - "$D/L/.agents/instincts.md" "$D/L/held" <<'PY' &
import fcntl, sys, time
path, flag = sys.argv[1], sys.argv[2]
with open(path, "r+", encoding="utf-8") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(flag, "w").close()
    time.sleep(2)
    t = f.read().replace("s 002", "EDITED-UNDER-LOCK 002")
    f.seek(0); f.truncate(); f.write(t)
PY
HOLDER=$!
for _ in $(seq 1 50); do [ -e L/held ] && break; sleep 0.1; done
CLAUDE_PROJECT_DIR="$D/L" python3 -I "$DEVKIT_ROOT/bin/instincts.py" archive --days 30 --apply >/dev/null 2>&1 || fail "L --apply exit non-zero"
wait $HOLDER
grep -q "EDITED-UNDER-LOCK" L/.agents/instincts-archive.md 2>/dev/null || fail "archive holds the stale pre-edit text of INSTINCT-002"

echo "--- log younger than N days: refuse ---"
mkdir -p Y/.agents Y/.claude/audit-gate
cp A/.agents/instincts.md Y/.agents/instincts.md
echo "{\"ts\": \"$(iso 1)\", \"session\": \"s\", \"prompt_sha1\": \"x\", \"instinct_ids\": [], \"instinct_refs\": []}" > Y/.claude/audit-gate/surfaced.jsonl
CLAUDE_PROJECT_DIR="$D/Y" python3 -I "$DEVKIT_ROOT/bin/instincts.py" archive --days 30 >/dev/null 2>&1
[ $? -eq 2 ] || fail "short log must exit 2"

echo "--- duplicates across 3 repos ---"
mk_repo R1 "001|Shared Trap|1|" "002|Only R1|1|"
mk_repo R2 "007|shared  trap|1|" "008|Only R2|1|"
mk_repo R3 "003|Both R2 R3|1|" "004|Only R3|1|"
mk_repo R2b "001|Both R2 R3|1|"
OUT=$(python3 -I "$DEVKIT_ROOT/bin/instincts.py" duplicates R1 R2 R3 2>&1); RC=$?
[ $RC -eq 0 ] || fail "duplicates exit $RC"
echo "$OUT" | grep -qi "shared trap" || fail "Shared Trap (R1+R2, case/space-insensitive) not reported"
echo "$OUT" | grep -q "Only R" && fail "single-repo title reported"
OUT=$(python3 -I "$DEVKIT_ROOT/bin/instincts.py" duplicates R3 R2b 2>&1)
echo "$OUT" | grep -q "Both R2 R3" || fail "Both R2 R3 not reported"

if [ "$ERRORS" -ne 0 ]; then echo "$ERRORS failure(s)"; exit 1; fi
echo "PASS"
