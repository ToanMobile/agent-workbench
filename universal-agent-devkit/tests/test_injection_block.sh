#!/usr/bin/env bash
# Regression test: the DevKit block injected into CLAUDE.md / AGENTS.md reaches the
# DevKit master rules and the active profile's rules, whatever the project already had:
#   - no AGENTS.md: the DevKit's AGENTS.md is installed and imported as @AGENTS.md
#   - its own AGENTS.md: the master is linked at .agents/devkit/AGENTS.md and imported
#     from there (@AGENTS.md would import the project's file only)
#   - CLAUDE.md -> AGENTS.md link: AGENTS_old.md is made, one block in the one file
#   - the profile rules import follows `agent-kit profile` switches
# and every @-import of the block resolves.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset CLAUDE_PROJECT_DIR TARGET_DIR DEVKIT_PROFILE

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
install() { bash "$DEVKIT_DIR/bin/install.sh" -t "$1" -a claude -y --no-githooks "${@:2}" > "$TMP/out" 2>&1 || { fail "install exited non-zero"; tail -5 "$TMP/out"; }; }
block() { sed -n '/universal-agent-devkit:start/,/universal-agent-devkit:end/p' "$1"; }
unresolved() { # <project> <file> — @-imports of the DevKit block that do not resolve
  block "$1/$2" | grep -o '@[^ `)]*' | sed 's/^@//' | while read -r f; do [ -e "$1/$f" ] || echo "$f"; done; }

# --- no AGENTS.md, profile android ---------------------------------------------------
A="$TMP/a"; mkdir -p "$A" && (cd "$A" && git init -q)
install "$A" -p android
block "$A/CLAUDE.md" | grep -q '@AGENTS.md$' && ok "no AGENTS.md: the DevKit AGENTS.md is imported as @AGENTS.md" || fail "master import: $(block "$A/CLAUDE.md" | grep SSOT)"
block "$A/CLAUDE.md" | grep -q '@.agents/active-profile/RULES.md' && head -1 "$A/.agents/active-profile/RULES.md" | grep -qi android \
  && ok "profile rules imported through .agents/active-profile/RULES.md (android)" || fail "profile rules import missing"
[ -z "$(unresolved "$A" CLAUDE.md)" ] && ok "every @-import in CLAUDE.md resolves" || fail "unresolved: $(unresolved "$A" CLAUDE.md | tr '\n' ' ')"
cmp -s "$A/DESIGN.md" "$DEVKIT_DIR/profiles/android/DESIGN.md" && ok "DESIGN.md is the android profile's, not the generic template" || fail "profile DESIGN.md not used"
! grep -q 'INSTINCT-V0' "$A/.agents/instincts.md" && ok "the new instincts.md carries no voice-assistant traps" || fail "voice traps seeded into an android project"

# --- the project's own AGENTS.md, CLAUDE.md links to it -------------------------------
B="$TMP/b"; mkdir -p "$B" && (cd "$B" && git init -q)
printf '# Our rules\n\n## 6. Ours\n- keep\n' > "$B/AGENTS.md"; ln -s AGENTS.md "$B/CLAUDE.md"
install "$B" -p web
[ "$(cat "$B/AGENTS_old.md" 2>/dev/null)" = "$(printf '# Our rules\n\n## 6. Ours\n- keep')" ] \
  && ok "CLAUDE.md -> AGENTS.md: the original AGENTS.md is kept as AGENTS_old.md" || fail "AGENTS_old.md missing or wrong"
[ "$(grep -c 'universal-agent-devkit:start' "$B/AGENTS.md")" = 1 ] && grep -q '^## 6. Ours' "$B/AGENTS.md" \
  && ok "one DevKit block in the shared file, the project's content kept" || fail "blocks: $(grep -c 'universal-agent-devkit:start' "$B/AGENTS.md")"
block "$B/AGENTS.md" | grep -q '@.agents/devkit/AGENTS.md' && cmp -s "$B/.agents/devkit/AGENTS.md" "$DEVKIT_DIR/AGENTS.md" \
  && ok "own AGENTS.md: the master is linked at .agents/devkit/AGENTS.md and imported from there" || fail "master not reachable"
block "$B/AGENTS.md" | grep -q '@AGENTS\.md' && fail "a self-import of AGENTS.md is left" || ok "no @AGENTS.md self-import"
block "$B/AGENTS.md" | grep -q 'python3 bin/post-fix-gate.py' && fail "gate command points at bin/ (not installed in projects)" || ok "gate command is one that exists in a project"
[ -z "$(unresolved "$B" AGENTS.md)" ] && ok "every @-import in AGENTS.md resolves" || fail "unresolved: $(unresolved "$B" AGENTS.md | tr '\n' ' ')"
install "$B" -p web
[ "$(grep -c 'universal-agent-devkit:start' "$B/AGENTS.md")" = 1 ] && [ ! -e "$B/AGENTS_old_"* ] 2>/dev/null \
  && ok "re-install: still one block, no second backup" || fail "re-install duplicated"

# --- installed without a profile, then `agent-kit profile` ------------------------------
C="$TMP/c"; mkdir -p "$C" && (cd "$C" && git init -q)
install "$C" -p none
block "$C/CLAUDE.md" | grep -q 'RULES.md' && fail "no profile, but a profile rules import" || ok "-p none: no profile rules import"
python3 "$DEVKIT_DIR/bin/agent-config.py" --profile backend --target "$C" >/dev/null 2>&1
python3 "$DEVKIT_DIR/bin/agent-config.py" --profile ios --target "$C" >/dev/null 2>&1
[ "$(block "$C/CLAUDE.md" | grep -c '@.agents/active-profile/RULES.md')" = 1 ] && head -1 "$C/.agents/active-profile/RULES.md" | grep -qi ios \
  && ok "agent-kit profile adds the import once; it follows the switch (ios)" || fail "profile switch import: $(block "$C/CLAUDE.md" | grep -c RULES)"
[ -z "$(unresolved "$C" CLAUDE.md)" ] && ok "after the switch every @-import resolves" || fail "unresolved: $(unresolved "$C" CLAUDE.md | tr '\n' ' ')"

# --- a project .gitignore that hides .agents/ is reported with the fix ----------------
G="$TMP/g"; mkdir -p "$G" && (cd "$G" && git init -q) && printf '/.agents/\n' > "$G/.gitignore"
install "$G" -p none
grep -q "ignores .agents/instincts.md" "$TMP/out" && grep -q "'/.agents/\*'" "$TMP/out" \
  && ok ".gitignore hiding .agents/: warned, with the /.agents/* fix" || fail "no warning for an ignored .agents/"
grep -qx '/.agents/' "$G/.gitignore" && ok "the project's own ignore rule is left as it was" || fail "project rule edited"
H="$TMP/h"; mkdir -p "$H" && (cd "$H" && git init -q)
install "$H" -p none
grep -q "ignores .agents" "$TMP/out" && fail "warned without an ignore rule" || ok "no warning when .agents/ is not ignored"

# --- symlink mode: DevKit links are machine-local — kept out of git via .git/info/exclude
links_listed="$(cd "$A" && git ls-files -o --exclude-standard -z | xargs -0 -n1 sh -c '[ -L "$0" ] && readlink "$0"' 2>/dev/null | grep -c "$DEVKIT_DIR" || true)"
[ "$links_listed" = 0 ] && grep -q '^/.claude/hooks/precode_gate.sh$' "$A/.git/info/exclude" \
  && ok "symlink mode: no DevKit link shows up as untracked (listed in .git/info/exclude)" || fail "$links_listed DevKit links still untracked"
[ -f "$A/.agents/instincts.md" ] && (cd "$A" && git ls-files -o --exclude-standard | grep -q '^.agents/instincts.md$') \
  && ok "the project's own files (instincts.md) still show up to be committed" || fail "instincts.md hidden"

# --- uninstall takes the master link away --------------------------------------------
python3 "$DEVKIT_DIR/scripts/devkit_uninstall.py" "$B" --apply >/dev/null 2>&1
[ ! -e "$B/.agents/devkit/AGENTS.md" ] && ok "uninstall removes .agents/devkit/AGENTS.md" || fail "master link left after uninstall"

if [ "$FAILS" -ne 0 ]; then echo "injection block: $FAILS FAILED"; exit 1; fi
echo "injection block: all checks passed"
