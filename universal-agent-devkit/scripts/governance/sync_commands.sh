#!/usr/bin/env bash
# sync_commands.sh — Populate commands/ from skills/ with canonical links and aliases
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR" && while [ ! -f "rules/essentials.md" ] && [ "$PWD" != "/" ]; do cd ..; done && pwd)"
SKILLS_DIR="$ROOT_DIR/skills"
COMMANDS_DIR="$ROOT_DIR/commands"

mkdir -p "$COMMANDS_DIR"

# Skills with no slash command on purpose: the agent picks them from context, nobody types them. The three Sprite Forge
# media skills are also excluded by every profile (2D assets gave way to Blender 3D, 15/10), so their link was only ever
# an untracked file after a sync (audit 25/10). Space-separated skill names.
NO_COMMAND_SKILLS="generate2dmedia generate2dsprite video2dsprite"

# 1. Link each canonical skill
for skill_dir in "$SKILLS_DIR"/*; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  case " $NO_COMMAND_SKILLS " in *" $skill_name "*)
    # The link an older sync made goes (its .claude/commands link then dangles and is swept below); a hand-written file stays.
    if [ -L "$COMMANDS_DIR/${skill_name}.md" ]; then rm -f "$COMMANDS_DIR/${skill_name}.md"; fi
    continue ;;
  esac
  if [ -f "$skill_dir/SKILL.md" ]; then
    if [ -e "$COMMANDS_DIR/${skill_name}.md" ] && [ ! -L "$COMMANDS_DIR/${skill_name}.md" ]; then
      echo "⚠ commands/${skill_name}.md is a hand-written command — left untouched." >&2
      continue
    fi
    ln -sfn "../skills/${skill_name}/SKILL.md" "$COMMANDS_DIR/${skill_name}.md"
  fi
done

# 2. Setup Aliases
ALIASES=(
  "fix:fixbugs"
  "build:deploy"
  "plan:spec-driven-development"
  "scan:security-checklist"
  "tdd:tdd-workflow"
  "verify:verification-before-completion"
  "conflict:merge-conflict-resolver"
  "handoff:session-handoff"
  "graph:codebase-memory"
  "visual:qa-visual"
  "ocr:open-code-review"
  "recomp-audit:compose-recomp-audit"
  "gc-audit:unity-gc-audit"
  "adr:documentation-and-adrs"
  "android-qa:android-real-device-qa"
  "deprecate:deprecation-migration"
  "enrich:context-enricher"
  "grill:grill-plan"
  "logging:observability-instrumentation"
  "module-design:deep-module-design"
  "skill-author:writing-skills"
  "step:incremental-implementation"
  "sandbox:worktree-sandbox"
  # QA ladder (1.1.0): plan-tests -> review-code -> check -> done (+ /audit-gate)
  "plan-tests:qa-review"
  "review-code:open-code-review"
  "check:qc"
  "done:verification-before-completion"
)

# The 1.1.0 renames kept one release as redirect stubs (/review /qa /test /bugs /crashlytics) and are
# removed in 1.2.0: delete a stub an older sync wrote (it carries the marker); a hand-written file stays.
for old_name in review qa test bugs crashlytics; do
  stub_path="$COMMANDS_DIR/${old_name}.md"
  if [ -f "$stub_path" ] && [ ! -L "$stub_path" ] && grep -qF "<!-- devkit:deprecated-alias -->" "$stub_path"; then
    rm -f "$stub_path"
  fi
done

# Aliases of hand-written commands (commands/<target>.md, not a skill).
COMMAND_ALIASES=(
  "postfix-gate:audit-gate"
)

# Clean broken symlinks in commands/
find "$COMMANDS_DIR" -type l ! -exec test -e {} \; -delete

for mapping in "${ALIASES[@]}"; do
  alias_name="${mapping%%:*}"
  target_skill="${mapping##*:}"
  alias_path="$COMMANDS_DIR/${alias_name}.md"
  if [ -f "$SKILLS_DIR/$target_skill/SKILL.md" ]; then
    # Only (re)point our own links. A hand-written command with the alias name is
    # never deleted — and never written through (the links resolve into SKILL.md).
    if [ -e "$alias_path" ] && [ ! -L "$alias_path" ]; then
      echo "⚠ commands/${alias_name}.md is a hand-written command — alias /${alias_name} -> ${target_skill} NOT created." >&2
      continue
    fi
    ln -sfn "../skills/${target_skill}/SKILL.md" "$alias_path"
  fi
done

for mapping in "${COMMAND_ALIASES[@]}"; do
  alias_name="${mapping%%:*}"
  target_cmd="${mapping##*:}"
  alias_path="$COMMANDS_DIR/${alias_name}.md"
  [ -f "$COMMANDS_DIR/${target_cmd}.md" ] || continue
  if [ -e "$alias_path" ] && [ ! -L "$alias_path" ]; then
    echo "⚠ commands/${alias_name}.md is a hand-written command — alias /${alias_name} -> /${target_cmd} NOT created." >&2
    continue
  fi
  ln -sfn "${target_cmd}.md" "$alias_path"
done

# If .claude/commands exists, synchronize commands there as well
CLAUDE_COMMANDS="$ROOT_DIR/.claude/commands"
if [ -d "$CLAUDE_COMMANDS" ]; then
  for cmd_file in "$COMMANDS_DIR"/*; do
    [ -e "$cmd_file" ] || continue
    cmd_name="$(basename "$cmd_file")"
    if [ -e "$CLAUDE_COMMANDS/$cmd_name" ] && [ ! -L "$CLAUDE_COMMANDS/$cmd_name" ]; then
      echo "⚠ .claude/commands/$cmd_name is a hand-written command — left untouched." >&2
      continue
    fi
    ln -sfn "../../commands/$cmd_name" "$CLAUDE_COMMANDS/$cmd_name"
  done
  find "$CLAUDE_COMMANDS" -type l ! -exec test -e {} \; -delete 2>/dev/null || true
fi

echo "Commands synchronized successfully in $COMMANDS_DIR ($(ls -1 "$COMMANDS_DIR" | wc -l | xargs) commands created)."
