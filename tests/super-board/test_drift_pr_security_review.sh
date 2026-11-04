#!/usr/bin/env bash
# T0247 follow-up: skills-ready requires pr-security-review in the QA lane, so an app repo whose copy lacks
# .claude/skills/pr-security-review/ must show up as drift (missing); a copy that has it must not.
# Only temp dirs; no real app repo is read.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="${SB_TEST_DRIFT:-$ROOT/.claude/bin/super-board-drift.py}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-drift-psr.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
S="$TMP/src"; A="$TMP/app"
mkdir -p "$S/.claude/bin" "$S/.claude/skills/pr-security-review" "$A/.claude/bin"
echo 'echo run' > "$S/.claude/bin/super-board-run.sh"; cp "$S/.claude/bin/super-board-run.sh" "$A/.claude/bin/"
echo '# security' > "$S/.claude/skills/pr-security-review/SKILL.md"
echo 'MIT' > "$S/.claude/skills/pr-security-review/LICENSE"

python3 "$DRIFT" --source "$S" --target "$A" >"$TMP/out.json" 2>"$TMP/err.txt"; rc=$?
if [ "$rc" -eq 1 ] && grep -q '.claude/skills/pr-security-review/SKILL.md' "$TMP/out.json"; then
  ok "copy without pr-security-review is reported missing (exit 1)"
else fail "missing pr-security-review not reported (rc=$rc): $(cat "$TMP/out.json")"; fi

mkdir -p "$A/.claude/skills/pr-security-review"
cp "$S/.claude/skills/pr-security-review/SKILL.md" "$S/.claude/skills/pr-security-review/LICENSE" "$A/.claude/skills/pr-security-review/"
python3 "$DRIFT" --source "$S" --target "$A" >"$TMP/out.json" 2>"$TMP/err.txt"; rc=$?
[ "$rc" -eq 0 ] && grep -q '"drifted": false' "$TMP/out.json" && ok "identical pr-security-review copy is not drift" \
  || fail "identical copy flagged (rc=$rc): $(cat "$TMP/out.json")"

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
