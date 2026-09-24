#!/usr/bin/env bash
# Regression test: what each platform actually receives from `install.sh`.
#   - Codex / Cursor never expand `@path` (Codex: raw AGENTS.md, codex-rs agents_md.rs;
#     Cursor: AGENTS.md is plain markdown, `@file` works in .cursor/rules/*.mdc only), so
#     every non-Claude block carries a plain "read these files first" instruction.
#   - AGENTS.md is the only instruction file: Gemini CLI reads it through context.fileName
#     (a GEMINI.md of the project's own is folded into it), and refuses imports whose real
#     path is outside the project — every DevKit link — so the DevKit folder is added to its
#     workspace (.gemini/settings.json includeDirectories) and the block imports only real
#     files (.agents/context/).
#   - Cursor gets an always-applied .cursor/rules/universal-agent-devkit.mdc.
#   - Profiles filter MCP servers (essential_mcps + the universal ones) and subagents
#     (exclude_agents); a server whose binary is not on PATH is never added.
#   - A project with its own design system gets a pointer DESIGN.md, not the token table.
#   - Deprecated command stubs stay while the plugin version is below 1.2.0.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset CLAUDE_PROJECT_DIR TARGET_DIR DEVKIT_PROFILE DEVKIT_SKILLS_ALLOWED DEVKIT_AGENTS_EXCLUDED DEVKIT_MCPS_ALLOWED

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
install() { bash "$DEVKIT_DIR/bin/install.sh" -t "$1" -y --no-githooks "${@:2}" > "$TMP/out" 2>&1 || { fail "install exited non-zero"; tail -5 "$TMP/out"; }; }
newproj() { local p="$TMP/$1"; rm -rf "$p"; mkdir -p "$p"; (cd "$p" && git init -q); printf '%s' "$p"; }
block() { sed -n '/universal-agent-devkit:start/,/universal-agent-devkit:end/p' "$1"; }
unresolved() { # <project> <file> — @-paths of the DevKit block that do not exist
  block "$1/$2" | grep -o '@[^ `)]*' | sed 's/^@//' | while read -r f; do [ -e "$1/$f" ] || echo "$f"; done; }
servers() { python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1])).get("mcpServers", {}))))' "$1" 2>/dev/null; }
READ_HINT='open each path after the @'

# --- Codex: the project's own AGENTS.md ---------------------------------------------------
X="$(newproj codex)"; printf '# Our rules\n- keep\n' > "$X/AGENTS.md"
install "$X" -a codex -p android
block "$X/AGENTS.md" | grep -q "$READ_HINT" \
  && ok "codex: AGENTS.md block tells a non-Claude agent to open the listed files" || fail "codex: no read instruction: $(block "$X/AGENTS.md" | sed -n 2,3p)"
block "$X/AGENTS.md" | grep -q '@.agents/context/essentials.md' && block "$X/AGENTS.md" | grep -q '@.agents/context/profile-rules.md' \
  && block "$X/AGENTS.md" | grep -q '.agents/devkit/AGENTS.md' && grep -q '^# Our rules' "$X/AGENTS.md" \
  && ok "codex: essentials and profile rules listed by path, master on demand, own text kept" || fail "codex: master/profile rules not listed"
[ -z "$(unresolved "$X" AGENTS.md)" ] && ok "codex: every listed path exists" || fail "codex unresolved: $(unresolved "$X" AGENTS.md | tr '\n' ' ')"

# --- Gemini: reads AGENTS.md (context.fileName), DevKit folder in the workspace ----------
G="$(newproj gemini)"
install "$G" -a gemini -p android
[ ! -e "$G/GEMINI.md" ] && [ -f "$G/AGENTS.md" ] && [ ! -L "$G/AGENTS.md" ] && ok "gemini: no GEMINI.md, a project AGENTS.md instead" || fail "gemini: GEMINI.md generated or no AGENTS.md"
gemini_names() { python3 -c 'import json,sys; n=json.load(open(sys.argv[1])).get("context",{}).get("fileName"); print(" ".join(n if isinstance(n,list) else [n or ""]))' "$1" 2>/dev/null; }
[ "$(gemini_names "$G/.gemini/settings.json" | cut -d' ' -f1)" = "AGENTS.md" ] && ok "gemini: context.fileName reads AGENTS.md" || fail "gemini: context.fileName is '$(gemini_names "$G/.gemini/settings.json")'"
block "$G/AGENTS.md" | grep -q '@.agents/context/essentials.md' && block "$G/AGENTS.md" | grep -q '@.agents/context/profile-rules.md' \
  && block "$G/AGENTS.md" | grep -q "$READ_HINT" \
  && ok "gemini: AGENTS.md imports essentials and profile rules, with the read-by-path fallback" || fail "gemini: block: $(block "$G/AGENTS.md" | tr '\n' '|' | cut -c1-300)"
[ -z "$(unresolved "$G" AGENTS.md)" ] && ok "gemini: every import path exists" || fail "gemini unresolved: $(unresolved "$G" AGENTS.md | tr '\n' ' ')"
python3 - "$G/.gemini/settings.json" "$DEVKIT_DIR" <<'PY_EOF' && ok "gemini: symlink mode adds the DevKit folder to context.includeDirectories" || fail "gemini: DevKit folder not in includeDirectories"
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if sys.argv[2] in d.get("context", {}).get("includeDirectories", []) else 1)
PY_EOF
install "$G" -a gemini -p android
[ "$(grep -c 'universal-agent-devkit:start' "$G/AGENTS.md")" = 1 ] && [ ! -e "$G/GEMINI_old.md" ] && [ ! -e "$G/.gemini/settings_old.json" ] \
  && ok "gemini: re-install keeps one block and makes no backup" || fail "gemini: re-install duplicated or backed up"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["context"]; l=c["includeDirectories"]; f=c["fileName"]; sys.exit(0 if len(l)==len(set(l)) and len(f)==len(set(f)) else 1)' "$G/.gemini/settings.json" \
  && ok "gemini: includeDirectories / fileName not duplicated on re-install" || fail "gemini: includeDirectories or fileName duplicated"
GC="$(newproj gemini-copy)"
install "$GC" -a gemini -p android -m copy
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(1 if d.get("context",{}).get("includeDirectories") else 0)' "$GC/.gemini/settings.json" 2>/dev/null \
  && [ "$(gemini_names "$GC/.gemini/settings.json")" = "AGENTS.md" ] \
  && ok "gemini: copy mode writes no machine path into .gemini/settings.json, still reads AGENTS.md" || fail "gemini: copy mode settings wrong"
GO="$(newproj gemini-own)"; printf '# Our Gemini notes\n' > "$GO/GEMINI.md"
install "$GO" -a gemini -p none
[ ! -e "$GO/GEMINI.md" ] && grep -q '^# Our Gemini notes' "$GO/AGENTS.md" && [ -f "$GO/GEMINI_old.md" ] && block "$GO/AGENTS.md" | grep -q "$READ_HINT" \
  && ok "gemini: an existing GEMINI.md is folded into AGENTS.md, backed up once" || fail "gemini: own GEMINI.md mishandled"
install "$GO" -a gemini -p none
[ "$(grep -c '^# Our Gemini notes' "$GO/AGENTS.md")" = 1 ] && ok "gemini: re-install does not fold twice" || fail "gemini: folded twice"

# --- Cursor: always-applied project rule ------------------------------------------------
C="$(newproj cursor)"; printf 'legacy rule\n' > "$C/.cursorrules"
install "$C" -a cursor -p web
M="$C/.cursor/rules/universal-agent-devkit.mdc"
[ "$(head -1 "$M" 2>/dev/null)" = "---" ] && sed -n '2,/^---$/p' "$M" | grep -qx 'alwaysApply: true' \
  && ok "cursor: .cursor/rules/universal-agent-devkit.mdc is always applied" || fail "cursor: no always-applied .mdc rule"
block "$M" | grep -q '@.agents/context/essentials.md' && block "$M" | grep -q '@.agents/context/profile-rules.md' && [ -z "$(unresolved "$C" .cursor/rules/universal-agent-devkit.mdc)" ] \
  && ok "cursor: the rule includes essentials and profile rules, every path exists" || fail "cursor: .mdc block: $(block "$M" | tr '\n' '|' | cut -c1-200)"
block "$C/.cursorrules" | grep -q "$READ_HINT" && ok "cursor: .cursorrules block carries the read instruction" || fail "cursor: .cursorrules block has @-imports only"
install "$C" -a cursor -p web
[ "$(grep -c '^alwaysApply' "$M")" = 1 ] && [ "$(grep -c 'universal-agent-devkit:start' "$M")" = 1 ] \
  && ok "cursor: re-install keeps one front matter and one block" || fail "cursor: re-install duplicated the .mdc content"

# --- Game project: no Android MCPs, no Android subagent -----------------------------------
U="$(newproj game)"; mkdir -p "$U/Assets" "$U/ProjectSettings" "$U/.claude/agents"
echo "m_EditorVersion: 6000.0.1f1" > "$U/ProjectSettings/ProjectVersion.txt"
python3 - "$DEVKIT_DIR/mcp/.mcp.json" "$U/.mcp.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))                                 # an older install: every DevKit server
d["mcpServers"]["android-skills"]["args"].append("--mine")       # ... one the user edited
d["mcpServers"]["my-own"] = {"command": "my-own-mcp"}            # ... and one of the user's
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
cp "$DEVKIT_DIR/mcp/mcp_config.json" "$U/mcp_config.json"
ln -s "$DEVKIT_DIR/agents/android-principal-architect.md" "$U/.claude/agents/android-principal-architect.md"
install "$U" -a claude,gemini
grep -q 'Profile:.*game' "$TMP/out" || fail "game: profile not detected"
got="$(servers "$U/.mcp.json")"
case " $got " in *" android-code-search "*|*" replicant-mcp "*|*" play-store "*) fail "game: Android MCPs left in .mcp.json: $got" ;;
  *) ok "game: the unmodified Android MCP entries are removed from .mcp.json" ;; esac
case " $got " in *" android-skills "*) case " $got " in *" my-own "*) ok "game: the user's own and user-edited MCP entries are kept" ;; *) fail "game: user MCP lost: $got" ;; esac ;;
  *) fail "game: the user-edited android-skills entry was removed: $got" ;; esac
case " $got " in *" context7 "*) ok "game: generic MCPs (context7) installed" ;; *) fail "game: context7 missing: $got" ;; esac
got="$(servers "$U/mcp_config.json")"
case " $got " in *" android-code-search "*|*" android-skills "*|*" replicant-mcp "*) fail "game: Android MCPs in mcp_config.json: $got" ;;
  *) ok "game: mcp_config.json (Gemini) filtered the same way" ;; esac
[ ! -e "$U/.claude/agents/android-principal-architect.md" ] && [ ! -L "$U/.claude/agents/android-principal-architect.md" ] \
  && ok "game: android-principal-architect is not linked (exclude_agents)" || fail "game: android-principal-architect linked"
[ -L "$U/.claude/agents/principal-code-reviewer.md" ] && ok "game: other subagents still linked" || fail "game: principal-code-reviewer missing"
A="$(newproj android)"; mkdir -p "$A/app"; touch "$A/settings.gradle.kts"
install "$A" -a claude
[ -L "$A/.claude/agents/android-principal-architect.md" ] && ok "android: android-principal-architect linked" || fail "android: android-principal-architect missing"
got="$(servers "$A/.mcp.json")"
case " $got " in *" android-code-search "*) ok "android: Android MCPs installed" ;; *) fail "android: Android MCPs missing: $got" ;; esac

# --- An MCP binary that is not on PATH is never added -------------------------------------
NOPS=""; IFS=: read -ra dirs <<< "$PATH"
for d in "${dirs[@]}"; do [ -x "$d/play-store-mcp" ] || NOPS="$NOPS${NOPS:+:}$d"; done
N="$(newproj nobin)"
PATH="$NOPS" install "$N" -a claude -p none
got="$(servers "$N/.mcp.json")"
case " $got " in *" play-store "*) fail "play-store added without play-store-mcp on PATH" ;; *) ok "no play-store-mcp on PATH: play-store not added" ;; esac
grep -q 'play-store-mcp' "$TMP/out" && ok "the skipped server is reported" || fail "skipped server not reported"
mkdir -p "$TMP/bin" && printf '#!/bin/sh\n' > "$TMP/bin/play-store-mcp" && chmod +x "$TMP/bin/play-store-mcp"
PATH="$TMP/bin:$NOPS" install "$N" -a claude -p none
case " $(servers "$N/.mcp.json") " in *" play-store "*) ok "play-store-mcp on PATH: play-store added" ;; *) fail "play-store missing with its binary on PATH" ;; esac

# --- DESIGN.md: a project with its own design system -------------------------------------
D="$(newproj designsys)"; mkdir -p "$D/core/design-system/src"; touch "$D/settings.gradle.kts"
install "$D" -a claude
[ -f "$D/DESIGN.md" ] && ! grep -q '#0D6EFD' "$D/DESIGN.md" && grep -q 'core/design-system' "$D/DESIGN.md" \
  && ok "own design system: DESIGN.md points at core/design-system, no DevKit token table" || fail "own design system: $(head -3 "$D/DESIGN.md" 2>/dev/null | tr '\n' '|')"
T="$(newproj tokens)"; mkdir -p "$T/src/styles"; echo '{}' > "$T/src/styles/design-tokens.json"; echo '{}' > "$T/package.json"
install "$T" -a claude
grep -q 'src/styles/design-tokens.json' "$T/DESIGN.md" && ! grep -q '#0D6EFD' "$T/DESIGN.md" \
  && ok "design tokens file: DESIGN.md points at it" || fail "tokens file not detected: $(head -3 "$T/DESIGN.md" | tr '\n' '|')"
W="$(newproj plainweb)"; echo '{}' > "$W/package.json"; mkdir -p "$W/docs"; touch "$W/docs/design-system-notes.md"
install "$W" -a claude
cmp -s "$W/DESIGN.md" "$DEVKIT_DIR/profiles/web/DESIGN.md" && ok "no design system (a doc named design-system is not one): the profile DESIGN.md" || fail "plain project did not get the profile DESIGN.md"

# --- Deprecated stubs stay until 1.2.0 ---------------------------------------------------
ver="$(python3 -c 'import json;print(json.load(open("'"$DEVKIT_DIR"'/.claude-plugin/plugin.json"))["version"])')"
if python3 -c 'import sys; v=tuple(int(x) for x in sys.argv[1].split(".")[:2]); sys.exit(0 if v < (1, 2) else 1)' "$ver"; then
  [ -e "$A/.claude/commands/bugs.md" ] && [ -e "$A/.claude/commands/crashlytics.md" ] \
    && ok "plugin $ver < 1.2.0: deprecated stubs (/bugs, /crashlytics) still linked" || fail "stubs removed before 1.2.0"
else
  [ ! -e "$DEVKIT_DIR/commands/bugs.md" ] && ok "plugin $ver: stubs removed" || fail "plugin $ver >= 1.2.0 still ships the /bugs stub"
fi

if [ "$FAILS" -ne 0 ]; then echo "platform rules: $FAILS FAILED"; exit 1; fi
echo "platform rules: all checks passed"
