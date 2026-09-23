#!/usr/bin/env bash
# Regression test: `agent-kit learn` — next [INSTINCT-NNN] id, duplicate titles
# refused, Markdown escaped, never written into the shared DevKit.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset TARGET_DIR

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/proj" && cd "$TMP/proj" || exit 1
git init -q .
export CLAUDE_PROJECT_DIR="$TMP/proj"
F=.agents/instincts.md

bash "$KIT" learn "Token refresh race" --cause "two refreshes in flight" --rule "single-flight mutex" >/dev/null
[ -f "$F" ] && grep -q '^### \[INSTINCT-010\]' "$F" && ok "missing file created from the template" || fail "template not used"
grep -q '^### \[INSTINCT-011\] Token refresh race$' "$F" && ok "next id after the template's 010 is 011" || fail "wrong id"
grep -q 'single-flight mutex' "$F" && ok "rule recorded" || fail "rule missing"

out="$(bash "$KIT" learn "  token REFRESH   race " 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'INSTINCT-011' && ok "duplicate title refused, existing id named" \
  || fail "duplicate not refused (rc=$rc)"
bash "$KIT" learn "Token refresh race" --force >/dev/null && grep -q '^### \[INSTINCT-012\]' "$F" \
  && ok "--force adds it anyway" || fail "--force ignored"

before="$(wc -c < "$F")"
bash "$KIT" learn "Dry one" --dry-run | grep -q 'INSTINCT-013' && [ "$(wc -c < "$F")" = "$before" ] \
  && ok "--dry-run prints, writes nothing" || fail "--dry-run wrote or printed wrong id"

bash "$KIT" learn "$(printf 'x\n# injected\n- item')" >/dev/null
! grep -q '^# injected' "$F" && ! grep -q '^- item' "$F" && ok "Markdown in the title is escaped" || fail "Markdown injected"

printf '### [INSTINCT-V07] a\n### [INSTINCT-BE-01] b\n' > "$TMP/v.md"
bash "$KIT" learn "Numbered next" --file "$TMP/v.md" >/dev/null
grep -q '^### \[INSTINCT-001\] Numbered next' "$TMP/v.md" && ok "named families (V07, BE-01) do not shift numbering" || fail "family ids counted"

out="$(bash "$KIT" learn "" 2>&1)"; [ $? -eq 2 ] && ok "empty title -> usage error" || fail "empty title accepted"
bash "$KIT" learn 'Speed gate AUTO_WINDOW_MAX_KMH' --cause 'set in `VoiceSettings.kt` <!-- hide' >/dev/null
grep -q 'AUTO_WINDOW_MAX_KMH$' "$F" && grep -q 'set in `VoiceSettings.kt`' "$F" && ! grep -q '<!-- hide' "$F" \
  && ok "identifiers and inline code kept verbatim; '<' escaped (no HTML comment)" || fail "escaping: $(grep -A3 AUTO_WINDOW "$F" | head -3)"

# --check is a shell command: rendered as inline code, unescaped (pasteable), one line;
# a backtick in it gets a longer fence, a newline cannot start a Markdown line.
CHK='grep -rn "x" src | wc -l && ! test -f *.bak'
bash "$KIT" learn "Check pasteable" --check "$CHK" >/dev/null
line="$(grep -A6 '\] Check pasteable$' "$F" | grep '^- \*\*Check:\*\*')"
[ "$line" = "- **Check:** \`$CHK\`" ] && ok "--check rendered as inline code, unescaped" || fail "--check not pasteable: $line"
bash "$KIT" learn "Check backtick" --check "$(printf 'echo `date`\n# injected-check')" >/dev/null
line="$(grep -A6 '\] Check backtick$' "$F" | grep '^- \*\*Check:\*\*')"
[ "$line" = '- **Check:** ``echo `date` # injected-check``' ] && ! grep -q '^# injected-check' "$F" \
  && ok "backtick in --check gets a longer fence, newline folded" || fail "--check fence/injection: $line"
bash "$KIT" learn "Check edge" --check '`x`' >/dev/null
line="$(grep -A6 '\] Check edge$' "$F" | grep '^- \*\*Check:\*\*')"
[ "$line" = '- **Check:** `` `x` ``' ] && ok "backtick at the edge of --check padded inside the fence" || fail "--check edge: $line"

# A link into the DevKit must not receive a project's lesson.
mkdir -p "$TMP/linked/.agents" && ln -s "$DEVKIT_DIR/templates/instincts.template.md" "$TMP/linked/.agents/instincts.md"
sum="$(cksum < "$DEVKIT_DIR/templates/instincts.template.md")"
out="$(CLAUDE_PROJECT_DIR="$TMP/linked" bash "$KIT" learn "Should not land" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && [ "$(cksum < "$DEVKIT_DIR/templates/instincts.template.md")" = "$sum" ] \
  && ok "link into the DevKit refused, template unchanged" || fail "wrote through a DevKit link (rc=$rc)"

# --from-json: bulk import of classified memory — only INSTINCT items of this project,
# with date and source, re-runnable without duplicates.
J="$TMP/mem.json"
cat > "$J" <<JSON
[{"project": "$TMP/proj", "source": "mem/a.md", "verdict": "INSTINCT", "title": "Imported trap A",
  "cause": "race on resume", "rule": "single-flight", "found_on": "2026-08-01"},
 {"project": "$TMP/proj", "source": "mem/b.md", "verdict": "PROJECT_STATE", "title": "Roadmap"},
 {"project": "$TMP/other", "source": "mem/c.md", "verdict": "INSTINCT", "title": "Other project trap"},
 {"project": "$TMP/proj", "source": "mem/d.md", "verdict": "INSTINCT", "title": "Imported trap D", "found_on": "yesterday"}]
JSON
before="$(wc -c < "$F")"
out="$(bash "$KIT" learn --from-json "$J" --dry-run 2>&1)"
[ "$(wc -c < "$F")" = "$before" ] && printf '%s' "$out" | grep -q "added 2 (dry-run)" \
  && ok "--from-json --dry-run: counts, writes nothing" || fail "--from-json dry-run: $out"
out="$(bash "$KIT" learn --from-json "$J" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q '\] Imported trap A$' "$F" && grep -q '\] Imported trap D$' "$F" \
  && ! grep -q 'Roadmap\|Other project trap' "$F" \
  && ok "--from-json adds only this project's INSTINCT items" || fail "--from-json import (rc=$rc): $out"
grep -A6 '\] Imported trap A$' "$F" | grep -q "2026-08-01" && grep -A6 '\] Imported trap A$' "$F" | grep -q "mem/a.md" \
  && ok "--from-json keeps the memory's date and source" || fail "date/source missing"
grep -A2 '\] Imported trap D$' "$F" | grep -q "yesterday" && fail "invalid date written" || ok "--from-json ignores a date that is not YYYY-MM-DD"
before="$(wc -c < "$F")"
out="$(bash "$KIT" learn --from-json "$J" 2>&1)"
[ "$(wc -c < "$F")" = "$before" ] && printf '%s' "$out" | grep -q "already there 2" \
  && ok "--from-json re-run adds nothing (titles already recorded)" || fail "re-run duplicated: $out"
bash "$KIT" learn "T" --from-json "$J" >/dev/null 2>&1; [ $? = 2 ] && ok "title + --from-json → usage error" || fail "both accepted"

if [ "$FAILS" -ne 0 ]; then
  echo "learn: $FAILS FAILED"; exit 1
fi
echo "learn: all checks passed"
