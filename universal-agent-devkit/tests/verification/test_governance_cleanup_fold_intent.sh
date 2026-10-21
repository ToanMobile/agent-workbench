#!/usr/bin/env bash
# Regression test (issue #30): (a) the nightly run cleans old audit-gate files (>7 days), (b) fold_agent_file.py run again on an
# EDITED source replaces its section instead of appending a second copy, (c) antigravity_collab_hint() fires for the intent names
# the classifier really emits (SECURITY, ARCHITECTURE_REFACTOR, DEPRECATION_MIGRATION).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
NIGHTLY="$DEVKIT_DIR/scripts/governance/nightly.py"
FOLD="$DEVKIT_DIR/scripts/governance/fold_agent_file.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export HOME="$TMP/home" DEVKIT_LANG=en NIGHTLY_NOTIFY=0; mkdir -p "$HOME"

# (a) nightly cleans audit-gate: a 10-day-old file goes, a fresh one stays, even when the project has no matrix (run is skipped)
P="$TMP/p"; A="$P/.claude/audit-gate"; mkdir -p "$A" "$P/.agents"
( cd "$P" && git init -q . && git config devkit.trunkMode false )
echo old > "$A/regression_gate.log"; touch -t 202001010000 "$A/regression_gate.log"
echo new > "$A/review_gate.log"
python3 "$NIGHTLY" run "$P" >/dev/null 2>&1
[ ! -e "$A/regression_gate.log" ] && [ -f "$A/review_gate.log" ] && ok "nightly run removes old audit-gate files, keeps fresh ones" || fail "audit-gate: $(ls "$A")"

# (b) fold: same source run twice = no change; edited source = one section, not two
F="$TMP/f"; mkdir -p "$F"
printf 'proj line A\nline B\n' > "$F/CLAUDE.md"
python3 "$FOLD" "$F/CLAUDE.md" "$F/AGENTS.md" >/dev/null; python3 "$FOLD" "$F/CLAUDE.md" "$F/AGENTS.md" >/dev/null
[ "$(grep -c '^line B$' "$F/AGENTS.md")" = 1 ] && ok "fold: same source twice stays one copy" || fail "fold twice"
printf 'proj line A\nline B edited\n' > "$F/CLAUDE.md"
python3 "$FOLD" "$F/CLAUDE.md" "$F/AGENTS.md" >/dev/null
[ "$(grep -c 'proj line A' "$F/AGENTS.md")" = 1 ] && grep -q 'line B edited' "$F/AGENTS.md" && ! grep -q '^line B$' "$F/AGENTS.md" \
  && ok "fold: edited source replaces its section (no duplicate)" || fail "fold edited: $(cat "$F/AGENTS.md")"
SZ=$(wc -c < "$F/AGENTS.md"); python3 "$FOLD" "$F/CLAUDE.md" "$F/AGENTS.md" >/dev/null
[ "$(wc -c < "$F/AGENTS.md")" = "$SZ" ] && ok "fold: re-run does not grow AGENTS.md" || fail "fold grew"

# (c) intent names
python3 -B -I - "$DEVKIT_DIR/scripts/context" <<'PY' && ok "collab hint fires for ARCHITECTURE_REFACTOR / SECURITY / DEPRECATION_MIGRATION" || fail "collab hint silent for a real intent name"
import sys
sys.path.insert(0, sys.argv[1])
import enrich_context as e
for intent in ("ARCHITECTURE_REFACTOR", "SECURITY", "DEPRECATION_MIGRATION"):
    assert e.antigravity_collab_hint("đổi tên một hàm nhỏ trong module", {"detected_intents": [intent]}, "."), intent
assert not e.antigravity_collab_hint("đổi tên một hàm nhỏ trong module", {"detected_intents": ["BUG_FIX"]}, "."), "BUG_FIX must stay silent"
PY

if [ "$FAILS" -ne 0 ]; then echo "governance cleanup/fold/intent: $FAILS FAILED"; exit 1; fi
echo "governance cleanup/fold/intent: all checks passed"
