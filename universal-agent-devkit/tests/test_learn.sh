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

# A link into the DevKit must not receive a project's lesson.
mkdir -p "$TMP/linked/.agents" && ln -s "$DEVKIT_DIR/templates/instincts.template.md" "$TMP/linked/.agents/instincts.md"
sum="$(cksum < "$DEVKIT_DIR/templates/instincts.template.md")"
out="$(CLAUDE_PROJECT_DIR="$TMP/linked" bash "$KIT" learn "Should not land" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && [ "$(cksum < "$DEVKIT_DIR/templates/instincts.template.md")" = "$sum" ] \
  && ok "link into the DevKit refused, template unchanged" || fail "wrote through a DevKit link (rc=$rc)"

if [ "$FAILS" -ne 0 ]; then
  echo "learn: $FAILS FAILED"; exit 1
fi
echo "learn: all checks passed"
