#!/usr/bin/env bash
# Regression test: `agent-kit clean` — removes only the hooks' own leftovers in
# .claude/audit-gate older than --days, trims oversized logs, is a dry-run by default,
# and never touches code, .agents/ or .gitignore.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en HOME="$TMP/home"
mkdir -p "$HOME"

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
OLD=202001010000

P="$TMP/p"; A="$P/.claude/audit-gate"
mkdir -p "$A/restore-backup/20200101-000000" "$A/restore-backup/NEW" "$A/adb-safe-exec" "$P/.agents" "$P/src"
printf '*\n' > "$A/.gitignore"
echo old > "$A/regression_gate.log";             touch -t $OLD "$A/regression_gate.log"
echo old > "$A/failcycle_s1.json";                touch -t $OLD "$A/failcycle_s1.json"
echo old > "$A/restore-backup/20200101-000000/cart.js"; touch -t $OLD "$A/restore-backup/20200101-000000/cart.js"
echo new > "$A/restore-backup/NEW/cart.js"
echo old > "$A/adb-safe-exec/20200101-1.log";     touch -t $OLD "$A/adb-safe-exec/20200101-1.log"
echo new > "$A/review_gate.log"
python3 -c "import sys; open(sys.argv[1],'w').write(''.join(f'line {i}\n' for i in range(700000)))" "$A/claim_check.log"
echo lesson > "$P/.agents/instincts.md";          touch -t $OLD "$P/.agents/instincts.md"
echo code > "$P/src/app.js";                      touch -t $OLD "$P/src/app.js"
mkdir -p "$HOME/.universal-agent-devkit.old-20200101-000000"; echo x > "$HOME/.universal-agent-devkit.old-20200101-000000/f"
touch -t $OLD "$HOME/.universal-agent-devkit.old-20200101-000000/f"

snap() { (cd "$P" && find . -type f | LC_ALL=C sort | while read -r f; do echo "$f $(cksum < "$f")"; done); }
before="$(snap)"
out="$(bash "$KIT" clean "$P" 2>&1)"
[ "$(snap)" = "$before" ] && printf '%s' "$out" | grep -q "would remove" && ok "dry-run lists, changes nothing" || fail "dry-run changed files"

bash "$KIT" clean "$P" --apply >/dev/null 2>&1
[ ! -e "$A/regression_gate.log" ] && [ ! -e "$A/failcycle_s1.json" ] && [ ! -e "$A/restore-backup/20200101-000000" ] \
  && [ ! -e "$A/adb-safe-exec/20200101-1.log" ] && ok "--apply removes old logs, state, restore backups, adb evidence" || fail "old items left"
[ -f "$A/review_gate.log" ] && [ -f "$A/restore-backup/NEW/cart.js" ] && ok "recent items are kept" || fail "recent items removed"
[ -f "$A/.gitignore" ] && [ -f "$P/.agents/instincts.md" ] && [ -f "$P/src/app.js" ] \
  && ok ".gitignore, .agents/ and code are never touched (even when old)" || fail "touched protected files"
[ "$(wc -l < "$A/claim_check.log" | xargs)" = 2000 ] && tail -1 "$A/claim_check.log" | grep -q "line 699999" \
  && ok "log over 5 MB trimmed to its last 2000 lines" || fail "big log not trimmed ($(wc -l < "$A/claim_check.log"))"
[ -d "$HOME/.universal-agent-devkit.old-20200101-000000" ] && ok "old DevKit installs kept without --old-installs" || fail "old install removed"
bash "$KIT" clean "$P" --apply --old-installs >/dev/null 2>&1
[ ! -e "$HOME/.universal-agent-devkit.old-20200101-000000" ] && ok "--old-installs removes an old quick-install copy" || fail "old install kept"
bash "$KIT" clean "$P" --days=0 --apply >/dev/null 2>&1
[ "$(ls -A "$A")" = ".gitignore" ] && ok "--days=0 empties audit-gate except .gitignore" || fail "--days=0 left: $(ls -A "$A" | tr '\n' ' ')"
bash "$KIT" clean "$P" --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown option → exit 2" || fail "unknown option accepted"

if [ "$FAILS" -ne 0 ]; then echo "clean: $FAILS FAILED"; exit 1; fi
echo "clean: all checks passed"
