#!/usr/bin/env bash
# install.sh — Universal Multi-Agent & Multi-Model DevKit Installer
set -euo pipefail

# Called through a link (~/.local/bin/agent-kit, agent-install) the folder holding the
# link is not the DevKit: follow the links to the real file first (bash 3.2: no readlink -f).
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  LINK="$(readlink "$SELF")"
  case "$LINK" in /*) SELF="$LINK" ;; *) SELF="$(dirname "$SELF")/$LINK" ;; esac
done
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
DEVKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

TARGET_DIR="$PWD"
DOMAIN="auto"
AGENTS="ask"
PROFILE="ask"
MODE="symlink"
LANGUAGE=""   # output language; resolved below: --lang > $DEVKIT_LANG > project .active-profile.json > vi
ASSUME_YES=0
GITHOOKS=1    # install the git pre-commit gate in git projects (--no-githooks to skip)

PROFILES_AVAILABLE="$(cd "$DEVKIT_ROOT/profiles" && for d in */; do [ -f "$d/profile.json" ] && printf '%s ' "${d%/}"; done)"
PROFILES_AVAILABLE="${PROFILES_AVAILABLE% }"

show_help() {
  cat << HELP_EOF
Universal Multi-Agent & Multi-Model DevKit Installer

Supports 4 core coding agents & LLMs:
  - Claude Code (Anthropic)
  - OpenAI Codex / ChatGPT Canvas
  - Google Antigravity & Gemini CLI
  - Cursor IDE

Usage:
  ./install.sh [OPTIONS]

Options:
  -t, --target <path>     Target project directory (default: current directory)
  -d, --domain <name>     Project domain: auto | android | ios | web | backend | general (default: auto)
  -p, --profile <name>    Domain profile: ${PROFILES_AVAILABLE// / | } | none
                          (default: ask; with -y: detected from the domain)
  -a, --agents <list>     Comma-separated agents or 'all'
                          Supported: claude, codex, gemini, cursor, all
  -m, --mode <mode>       Install mode: symlink | copy (default: symlink)
                          symlink = absolute links into this DevKit checkout (single machine);
                          copy    = real files (use this if the project is committed for a team/CI)
  -l, --lang <code>       Output language of the installer, profile and gate: en | vi
                          (default: \$DEVKIT_LANG, then the project's saved language, then vi)
  -s, --skip-existing     Keep project hooks/commands/agents/skills that share a DevKit name
      --no-githooks       Do not install the git pre-commit gate (installed by default in git
                          projects: every commit, also outside the agent, is statically checked)
  -y, --yes               Non-interactive: all agents, profile from the detected domain
  -h, --help              Show this help message

Examples:
  # Interactive setup (choose agents from list):
  ./install.sh

  # Quick zero-config setup for ALL agents:
  ./install.sh -y

  # Setup specifically for Cursor and Claude only:
  ./install.sh -t /path/to/my-project -a claude,cursor
HELP_EOF
}

die_usage() { # <message> — invalid CLI usage: explain and exit 2 without touching anything
  echo "install.sh: $1" >&2
  echo "Run './install.sh --help' for usage." >&2
  exit 2
}

need_value() { # <flag> <remaining-argc> — option given without its value
  [ "$2" -ge 2 ] || die_usage "option '$1' requires a value"
}

# normalize_profile <name> — canonical profile dir name, "none", or "" when unknown
normalize_profile() {
  local p
  p="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | xargs)"
  case "$p" in
    1|automotive|car|xehoi) p="automotive" ;;
    2|android|mobile) p="android" ;;
    3|game|unity|blender) p="game" ;;
    4|universal|general|default) p="universal" ;;
    5|voice|voice-assistant|audio) p="voice-assistant" ;;
    6|ios|swift|swiftui|apple) p="ios" ;;
    7|web|frontend|react|nextjs) p="web" ;;
    8|backend|server|api) p="backend" ;;
    none|ask|auto) printf '%s' "$p"; return 0 ;;
  esac
  if [ -f "$DEVKIT_ROOT/profiles/$p/profile.json" ]; then printf '%s' "$p"; else printf ''; fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--target)
      need_value "$1" $#; TARGET_DIR="$2"; shift 2 ;;
    --target=*)
      TARGET_DIR="${1#*=}"; shift ;;
    -d|--domain)
      need_value "$1" $#; DOMAIN="$2"; shift 2 ;;
    --domain=*)
      DOMAIN="${1#*=}"; shift ;;
    -p|--profile)
      need_value "$1" $#; PROFILE="$2"; shift 2 ;;
    --profile=*)
      PROFILE="${1#*=}"; shift ;;
    -a|--agents)
      need_value "$1" $#; AGENTS="$2"; shift 2 ;;
    --agents=*)
      AGENTS="${1#*=}"; shift ;;
    -m|--mode)
      need_value "$1" $#; MODE="$2"; shift 2 ;;
    --mode=*)
      MODE="${1#*=}"; shift ;;
    -l|--lang|--language)
      need_value "$1" $#; LANGUAGE="$2"; shift 2 ;;
    --lang=*|--language=*)
      LANGUAGE="${1#*=}"; shift ;;
    -s|--skip-existing)
      SKIP_EXISTING=1; shift ;;
    -y|--yes)
      ASSUME_YES=1; shift ;;
    --no-githooks)
      GITHOOKS=0; shift ;;
    -h|--help)
      show_help; exit 0 ;;
    *)
      die_usage "unknown option: $1" ;;
  esac
done

# Validate everything BEFORE the first write to the project.
case "$MODE" in symlink|copy) ;; *) die_usage "invalid --mode '$MODE' (expected: symlink | copy)" ;; esac
case "$LANGUAGE" in ""|en|vi) ;; *) die_usage "invalid --lang '$LANGUAGE' (expected: en | vi)" ;; esac
case "$DOMAIN" in auto|android|ios|web|backend|game|general) ;; *) die_usage "invalid --domain '$DOMAIN' (expected: auto | android | ios | web | backend | game | general)" ;; esac
if [ "$PROFILE" != "ask" ]; then
  norm="$(normalize_profile "$PROFILE")"
  [ -n "$norm" ] || die_usage "unknown profile '$PROFILE' (available: $PROFILES_AVAILABLE | none)"
  PROFILE="$norm"
fi
if [ "$ASSUME_YES" = 1 ]; then
  [ "$AGENTS" = "ask" ] && AGENTS="all"
  [ "$PROFILE" = "ask" ] && PROFILE="auto"
fi
[ -d "$TARGET_DIR" ] || die_usage "target directory does not exist: $TARGET_DIR"

TARGET_DIR="$(cd "$TARGET_DIR" && pwd -P)"

# Output language, shared with every adapter / agent-config / gate run from here.
source "$DEVKIT_ROOT/scripts/i18n.sh"
DEVKIT_LANG="$(devkit_resolve_lang "$LANGUAGE" "$TARGET_DIR")"
export DEVKIT_LANG
LANGUAGE="$DEVKIT_LANG"

# Interactive Agent Selection Menu if not specified via CLI
if [ "$AGENTS" = "ask" ]; then
  echo "================================================================="
  echo "  🤖 Universal AI Agent DevKit — $(L "Bước 1/2: Chọn AI Coding Tools" "Step 1/2: choose AI coding tools")"
  echo "================================================================="
  echo "  [1] 🤖 Claude Code          (AGENTS.md, .claude/commands/, hooks, .mcp.json)"
  echo "  [2] 🧠 OpenAI Codex         (AGENTS.md SSOT)"
  echo "  [3] ✨ Google Gemini / AGY  (AGENTS.md, .agents/skills, mcp_config.json)"
  echo "  [4] ⚡ Cursor IDE           (AGENTS.md SSOT)"
  echo "  [A] 🌟 All Agents           ($(L "Cấu hình toàn bộ 4 nền tảng" "configure all 4 tools"))"
  echo "-----------------------------------------------------------------"
  user_choice="A"
  if [ -t 0 ]; then
    read -r -p "$(L "Chọn AI Tools (ví dụ: 1,2 hoặc A cho tất cả)" "Choose AI tools (e.g. 1,2 or A for all)") [Default: A]: " input_choice || input_choice=""
    user_choice="${input_choice:-A}"
  elif (exec 3</dev/tty) 2>/dev/null; then
    read -r -p "$(L "Chọn AI Tools (ví dụ: 1,2 hoặc A cho tất cả)" "Choose AI tools (e.g. 1,2 or A for all)") [Default: A]: " input_choice < /dev/tty || input_choice=""
    user_choice="${input_choice:-A}"
  fi

  if [[ "$user_choice" =~ ^[aA]$ ]] || [ "$user_choice" = "all" ]; then
    AGENTS="all"
  else
    selected_agents=()
    IFS=',' read -ra CHOICES <<< "$user_choice"
    for c in "${CHOICES[@]}"; do
      c_trim="$(echo "$c" | xargs)"
      case "$c_trim" in
        1|claude) selected_agents+=("claude") ;;
        2|codex|chatgpt|openai) selected_agents+=("codex") ;;
        3|gemini|antigravity) selected_agents+=("gemini") ;;
        4|cursor) selected_agents+=("cursor") ;;
      esac
    done
    if [ ${#selected_agents[@]} -eq 0 ]; then
      AGENTS="all"
    else
      AGENTS="$(IFS=','; echo "${selected_agents[*]}")"
    fi
  fi
fi

# Interactive Project Profile Selection Menu if not specified via CLI
if [ "$PROFILE" = "ask" ]; then
  echo
  echo "================================================================="
  echo "  🎯 Universal AI Agent DevKit — $(L "Bước 2/2: Chọn Profile Dự Án" "Step 2/2: choose the project profile")"
  echo "================================================================="
  echo "  [1] 🚗 $(L "Xe hơi" "Automotive") (Automotive: AAOS / IVI / Flyme Auto / CAN bus)"
  echo "  [2] 📱 Android (Mobile App / Jetpack Compose / Clean Arch)"
  echo "  [3] 🎮 Game (Unity 6 / Blender 3D / Shaders & Assets)"
  echo "  [4] 🌐 Universal / General ($(L "Mặc định đa nền tảng" "default, any stack"))"
  echo "  [5] 🎙️ $(L "Trợ lý Giọng nói" "Voice Assistant") (Voice Assistant: Edge AI / Audio / AEC / VAD)"
  echo "  [6] 🍏 iOS (Swift 6 / SwiftUI / Swift Concurrency / XCTest)"
  echo "  [7] 🕸️ Web (Frontend / Full-Stack JS / TypeScript)"
  echo "  [8] 🗄️ Backend (API / Services / Python · Go · Rust · Node)"
  echo "-----------------------------------------------------------------"
  user_profile="4"
  if [ -t 0 ]; then
    read -r -p "$(L "Chọn Profile dự án (1=Xe hơi, 2=Android, 3=Game, 4=Universal, 5=Voice, 6=iOS, 7=Web, 8=Backend)" "Choose the project profile (1=Automotive, 2=Android, 3=Game, 4=Universal, 5=Voice, 6=iOS, 7=Web, 8=Backend)") [Default: 4]: " input_prof || input_prof=""
    user_profile="${input_prof:-4}"
  elif (exec 3</dev/tty) 2>/dev/null; then
    read -r -p "$(L "Chọn Profile dự án (1=Xe hơi, 2=Android, 3=Game, 4=Universal, 5=Voice, 6=iOS, 7=Web, 8=Backend)" "Choose the project profile (1=Automotive, 2=Android, 3=Game, 4=Universal, 5=Voice, 6=iOS, 7=Web, 8=Backend)") [Default: 4]: " input_prof < /dev/tty || input_prof=""
    user_profile="${input_prof:-4}"
  fi

  PROFILE="$(normalize_profile "$user_profile")"
  case "$PROFILE" in ""|ask|auto) PROFILE="universal" ;; esac
fi

# Smart Auto-Detection of Project Domain
# A Unity project first (Rider/VS drop *.sln/*.csproj into it). A monorepo with nothing
# at its root is judged by its first-level folders (CarConnect/gradlew, PCConnect/go.mod …).
domain_marker_dirs() { printf '%s\n' "$TARGET_DIR"; for d in "$TARGET_DIR"/*/; do [ -d "$d" ] && printf '%s\n' "${d%/}"; done; }
if [ "$DOMAIN" = "auto" ] && [ -d "$TARGET_DIR/Assets" ] && [ -f "$TARGET_DIR/ProjectSettings/ProjectVersion.txt" ]; then
  DOMAIN="game"
fi
if [ "$DOMAIN" = "auto" ]; then
  root_has() { for f in "$@"; do [ -e "$TARGET_DIR/$f" ] && return 0; done; return 1; }
  if ! root_has build.gradle build.gradle.kts settings.gradle settings.gradle.kts AndroidManifest.xml Package.swift \
       package.json pyproject.toml requirements.txt go.mod Cargo.toml && ! compgen -G "$TARGET_DIR/*.xcodeproj" >/dev/null 2>&1; then
    while IFS= read -r d; do
      [ "$d" = "$TARGET_DIR" ] && continue
      if [ -f "$d/settings.gradle" ] || [ -f "$d/settings.gradle.kts" ] || [ -f "$d/gradlew" ]; then DOMAIN="android"; break; fi
    done < <(domain_marker_dirs)
  fi
fi
if [ "$DOMAIN" = "auto" ]; then
  if [ -f "$TARGET_DIR/build.gradle" ] || [ -f "$TARGET_DIR/build.gradle.kts" ] || [ -f "$TARGET_DIR/settings.gradle" ] || [ -f "$TARGET_DIR/settings.gradle.kts" ] || [ -f "$TARGET_DIR/AndroidManifest.xml" ]; then
    DOMAIN="android"
  elif [ -f "$TARGET_DIR/Package.swift" ] || compgen -G "$TARGET_DIR/*.xcodeproj" > /dev/null 2>&1 || compgen -G "$TARGET_DIR/*.xcworkspace" > /dev/null 2>&1; then
    DOMAIN="ios"
  elif [ -f "$TARGET_DIR/next.config.js" ] || [ -f "$TARGET_DIR/next.config.ts" ] || [ -f "$TARGET_DIR/vite.config.ts" ] || [ -f "$TARGET_DIR/package.json" ]; then
    DOMAIN="web"
  elif [ -f "$TARGET_DIR/pyproject.toml" ] || [ -f "$TARGET_DIR/requirements.txt" ] || [ -f "$TARGET_DIR/go.mod" ] || [ -f "$TARGET_DIR/Cargo.toml" ]; then
    DOMAIN="backend"
  else
    DOMAIN="general"
  fi
fi

# -y without -p: pick the profile matching the detected domain
if [ "$PROFILE" = "auto" ]; then
  case "$DOMAIN" in
    android) PROFILE="android" ;;
    ios) PROFILE="ios" ;;
    web) PROFILE="web" ;;
    backend) PROFILE="backend" ;;
    game) PROFILE="game" ;;
    *) PROFILE="universal" ;;
  esac
fi

echo
echo "================================================================="
echo "  🚀 Universal Multi-Agent & Multi-Model DevKit Installer"
echo "  Target Project:  $TARGET_DIR"
echo "  Domain Detected: $DOMAIN"
echo "  Selected Agents: $AGENTS"
echo "  Language Mode:   $LANGUAGE"
echo "  Link Mode:       $MODE"
echo "  Profile:         $PROFILE"
echo "================================================================="
echo

# 1. The devkit's own commands/ is committed as-is. Installing into a project must
#    never rewrite files inside the devkit checkout (run `agent-kit sync` when
#    developing the devkit itself).

# 2. Source X_old Conflict Protection Helper
source "$DEVKIT_ROOT/scripts/backup_conflict.sh"

# 3. Setup Project Rules, Skills & Commands with X_old Protection
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  echo "  🛡️  [X_old Protection] $(L "Kiểm tra xung đột tài nguyên dự án..." "checking for conflicts with project files...")"
  placed=()
  for item in rules skills commands; do
    if is_foreign_project_dir "$TARGET_DIR/$item"; then
      if devkit_is_agent_content_dir "$TARGET_DIR/$item" "$item"; then
        # The project's own agent material: DevKit is the core, theirs goes to the
        # project tier (.agents/local/<item>/) and is linked back where names are free.
        devkit_local_absorb_dir "$TARGET_DIR/$item" "$item" || exit 1
      else
        # The project's source code (e.g. a CLI's commands/build.js): moving it would
        # break the build. Keep it and place every DevKit item inside, so every DevKit
        # path resolves; a same-named project file goes to the project tier.
        echo "  ⚠️  $item/ $(L "là source code của dự án — giữ nguyên, đặt từng item DevKit vào trong" "is the project's source code — kept; DevKit items placed inside it")" >&2
        devkit_place_into_dir "$DEVKIT_ROOT/$item" "$TARGET_DIR/$item" "$MODE" || exit 1
        placed+=("$item/")
        continue
      fi
    fi
    devkit_place "$DEVKIT_ROOT/$item" "$TARGET_DIR/$item" "$MODE"
    placed+=("$item/")
  done
  if [ ${#placed[@]} -gt 0 ]; then
    echo "  - Initialized ${placed[*]}"
  fi
  if [ "$MODE" = "symlink" ] && [ -e "$TARGET_DIR/.git" ]; then
    echo "  ⚠️  Symlink mode writes ABSOLUTE links into $DEVKIT_ROOT." >&2
    echo "      Teammates and CI will get broken links if you commit them —" >&2
    echo "      re-run with '-m copy' for a committed team setup, or keep the links untracked." >&2
  fi
fi

# 3b. Skills allowed by the profile (P1-5): adapters place only these into
#     .agents/skills and .claude/commands. Empty = every skill (no profile / self-install).
DEVKIT_SKILLS_ALLOWED=""
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  if ! DEVKIT_SKILLS_ALLOWED="$(python3 "$DEVKIT_ROOT/scripts/profile_skills.py" "${PROFILE:-none}" | tr '\n' ' ')"; then
    echo "✖ profiles/$PROFILE/profile.json lists an unknown skill — fix it before installing." >&2
    exit 1
  fi
  if [ "$PROFILE" != "none" ]; then
    skipped=""
    for d in "$DEVKIT_ROOT/skills"/*/; do
      d="$(basename "$d")"
      [[ " $DEVKIT_SKILLS_ALLOWED " == *" $d "* ]] || skipped="$skipped$d "
    done
    [ -n "$skipped" ] && echo "  - $(L "Profile '$PROFILE' bỏ qua skill không liên quan" "Profile '$PROFILE' skips unrelated skills"): ${skipped% }"
  fi
fi
export DEVKIT_SKILLS_ALLOWED

# 3c. Subagents and MCP servers of the profile: "exclude_agents" (agents/<name>.md) are
#     not linked into .claude/agents; the MCP servers are the profile's "essential_mcps"
#     plus the generic ones (the universal profile's). Empty = everything (no profile).
DEVKIT_AGENTS_EXCLUDED=""
DEVKIT_MCPS_ALLOWED=""
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ] && [ -f "$DEVKIT_ROOT/profiles/$PROFILE/profile.json" ]; then
  if ! filters="$(python3 - "$DEVKIT_ROOT" "$PROFILE" <<'PY'
import json, os, sys
root, pid = sys.argv[1:3]
meta = lambda p: json.load(open(os.path.join(root, "profiles", p, "profile.json"), encoding="utf-8"))
m = meta(pid)
agents = m.get("exclude_agents") or []
unknown = [a for a in agents if not os.path.exists(os.path.join(root, "agents", a + ".md"))]
for a in unknown:
    print(f"profiles/{pid}/profile.json: unknown agent '{a}' in exclude_agents", file=sys.stderr)
mcps = []
if "essential_mcps" in m:
    for s in m["essential_mcps"] + meta("universal").get("essential_mcps", []):
        if s not in mcps:
            mcps.append(s)
print(" ".join(agents))
print(" ".join(mcps))
sys.exit(1 if unknown else 0)
PY
)"; then
    echo "✖ profiles/$PROFILE/profile.json lists an unknown agent — fix it before installing." >&2
    exit 1
  fi
  DEVKIT_AGENTS_EXCLUDED="$(printf '%s\n' "$filters" | sed -n 1p)"
  DEVKIT_MCPS_ALLOWED="$(printf '%s\n' "$filters" | sed -n 2p)"
  [ -n "$DEVKIT_AGENTS_EXCLUDED" ] && echo "  - $(L "Profile '$PROFILE' bỏ qua subagent không liên quan" "Profile '$PROFILE' skips unrelated subagents"): $DEVKIT_AGENTS_EXCLUDED"
fi
export DEVKIT_AGENTS_EXCLUDED DEVKIT_MCPS_ALLOWED

# 4. Configure selected agents
IFS=',' read -ra AGENT_LIST <<< "$AGENTS"
export SKIP_EXISTING="${SKIP_EXISTING:-0}"
# The injected blocks import the profile's rules (.agents/active-profile/RULES.md) when
# a profile is being installed; it is activated in step 6, after the adapters.
export DEVKIT_PROFILE="$PROFILE"

configure_agent() {
  local ag="$1"
  case "$ag" in
    claude)
      echo "  🤖 [Claude Code]"
      bash "$DEVKIT_ROOT/adapters/setup_claude.sh" "$TARGET_DIR" "$MODE" "$LANGUAGE"
      ;;
    codex|chatgpt|openai)
      echo "  🧠 [OpenAI Codex / ChatGPT]"
      bash "$DEVKIT_ROOT/adapters/setup_codex.sh" "$TARGET_DIR" "$MODE" "$LANGUAGE" "$DOMAIN"
      ;;
    gemini|antigravity)
      echo "  ✨ [Google Antigravity / Gemini]"
      bash "$DEVKIT_ROOT/adapters/setup_gemini.sh" "$TARGET_DIR" "$MODE" "$LANGUAGE"
      ;;
    cursor)
      echo "  ⚡ [Cursor IDE]"
      bash "$DEVKIT_ROOT/adapters/setup_cursor.sh" "$TARGET_DIR" "$MODE" "$LANGUAGE" "$DOMAIN"
      ;;
    all)
      configure_agent "claude"
      configure_agent "codex"
      configure_agent "gemini"
      configure_agent "cursor"
      ;;
    *)
      echo "  ⚠️ Unknown agent: $ag (skipping)"
      ;;
  esac
}

for agent_item in "${AGENT_LIST[@]}"; do
  agent_clean="$(echo "$agent_item" | tr '[:upper:]' '[:lower:]' | xargs)"
  configure_agent "$agent_clean"
done

echo
echo "================================================================="
echo "  ✨ Setup Complete for Selected Agents: [$AGENTS]!"
echo "  No unnecessary agent rules or files were created."
echo "================================================================="

# 5. Setup DESIGN.md & Instincts Memory if not existing in target project
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  # An existing DESIGN.md / instincts.md is the project's own and is never overwritten,
  # so there is nothing to back up — only missing files are created from templates.
  # A design system of the project's own (a design-system module, a design-tokens file)
  # is the source of its tokens: seeding the DevKit's token table (color-primary #0D6EFD …)
  # next to it gives the agent two competing palettes. core-rules §6 still sends the agent
  # to DESIGN.md for tokens, so a short pointer to the real one is written instead.
  own_design=""
  [ -e "$TARGET_DIR/DESIGN.md" ] || own_design="$(find "$TARGET_DIR" -maxdepth 4 \( -name .git -o -name node_modules -o -name build -o -name dist \
      -o -name Library -o -name Temp -o -name Pods -o -name .gradle -o -name .agents -o -name .claude \) -prune -o \
      \( -type d \( -iname '*design-system*' -o -iname '*designsystem*' -o -iname '*design_system*' \
                   -o -iname '*design-tokens*' -o -iname '*design_tokens*' \) \
      -o -type f \( -iname 'design-tokens.*' -o -iname 'design_tokens.*' -o -iname 'tokens.json' -o -iname '*.tokens.json' \) \) \
      -print 2>/dev/null | sed "s|^$TARGET_DIR/||" | awk -F/ 'NF <= 3' | sort | head -3)"
  if [ -e "$TARGET_DIR/DESIGN.md" ]; then
    echo "  - Kept existing DESIGN.md (not modified)"
  elif [ -n "$own_design" ]; then
    DESIGN_TMP="$(mktemp "$TARGET_DIR/.DESIGN.md.XXXXXX")"
    {
      echo "# DESIGN.md — $(L "trỏ tới design system của dự án" "pointer to this project's design system")"
      echo
      echo "$(L "Dự án này có design system riêng. Màu, typography, khoảng cách và component lấy từ đây — không tự đặt giá trị, không dùng bảng token mẫu của DevKit:" "This project has its own design system. Take colors, typography, spacing and components from it — never invent values, and do not use a generic DevKit token table:")"
      echo
      printf '%s\n' "$own_design" | sed 's/.*/- `&`/'
      echo
      echo "$(L "Mức a11y tối thiểu vẫn áp dụng (DevKit \`rules/core-rules.md\` §6): vùng chạm ≥ 48×48dp (≥ 44×44px trên Web)." "The a11y baseline still applies (DevKit \`rules/core-rules.md\` §6): touch targets ≥ 48×48dp (≥ 44×44px on the Web).")"
      echo
      echo "_$(L "Universal Agent DevKit viết tệp này vì tìm thấy các đường dẫn trên. Cứ sửa — installer không bao giờ ghi đè DESIGN.md đã có." "Written by Universal Agent DevKit because it found the paths above. Edit freely — the installer never overwrites an existing DESIGN.md.")_"
    } > "$DESIGN_TMP" || { rm -f "$DESIGN_TMP"; exit 1; }
    chmod 644 "$DESIGN_TMP" && mv "$DESIGN_TMP" "$TARGET_DIR/DESIGN.md"
    echo "  - $(L "Dự án có design system riêng" "The project has its own design system") ($(printf '%s' "$own_design" | tr '\n' ' ' | sed 's/ $//')): $(L "DESIGN.md chỉ trỏ tới nó, không có bảng token DevKit" "DESIGN.md only points at it, no DevKit token table")"
  else
    # The chosen profile's DESIGN.md (game HUD, automotive driver-distraction …) when it
    # ships one; the generic template otherwise.
    DESIGN_SRC="$DEVKIT_ROOT/templates/DESIGN.md"
    case "$PROFILE" in ""|none|ask|auto) ;; *)
      [ -f "$DEVKIT_ROOT/profiles/$PROFILE/DESIGN.md" ] && DESIGN_SRC="$DEVKIT_ROOT/profiles/$PROFILE/DESIGN.md" ;;
    esac
    cp "$DESIGN_SRC" "$TARGET_DIR/DESIGN.md"
    echo "  - Initialized DESIGN.md (Design system & a11y baseline: ${DESIGN_SRC#"$DEVKIT_ROOT"/})"
  fi

  mkdir -p "$TARGET_DIR/.agents"
  if [ -e "$TARGET_DIR/.agents/instincts.md" ]; then
    echo "  - Kept existing .agents/instincts.md (not modified)"
  else
    cp "$DEVKIT_ROOT/templates/instincts.template.md" "$TARGET_DIR/.agents/instincts.md"
    echo "  - Initialized .agents/instincts.md (Failure memory & repository traps)"
  fi

  # Keep local install state and *_old backups out of the project's commits.
  if [ -e "$TARGET_DIR/.git" ] || [ -f "$TARGET_DIR/.gitignore" ]; then
    GI_BLOCK="$(mktemp "${TMPDIR:-/tmp}/devkit-gitignore.XXXXXX")"
    cat > "$GI_BLOCK" <<'GI_EOF'
# Local DevKit install state & *_old conflict backups (review/merge them, don't commit)
.claude/audit-gate/
.agents/regression_matrix.generated.json
.devkit_backups.log
.devkit-files
*_old
*_old.*
*_old_*
GI_EOF
    python3 "$DEVKIT_ROOT/scripts/merge_markdown.py" "$GI_BLOCK" "$TARGET_DIR/.gitignore" "universal-agent-devkit" --comment-style=hash >/dev/null
    rm -f "$GI_BLOCK"
    echo "  - .gitignore: DevKit state and *_old backups excluded"
    # The project's lessons and tier are meant to be committed. A rule of the project's
    # own that ignores the whole .agents/ folder hides them, and git cannot re-include a
    # file below an ignored folder, so say how to fix it instead of editing their rule.
    for keep in .agents/instincts.md .agents/local/README.md; do
      if git -C "$TARGET_DIR" check-ignore -q --no-index "$keep" 2>/dev/null; then
        rule="$(git -C "$TARGET_DIR" check-ignore -v --no-index "$keep" 2>/dev/null | cut -f1)"
        echo "  ⚠️  $(L ".gitignore bỏ qua $keep ($rule) — bài học và tầng dự án sẽ KHÔNG được commit." ".gitignore ignores $keep ($rule) — the project's lessons and tier will NOT be committed.")"
        echo "     $(L "Sửa: đổi dòng đó thành '/.agents/*' rồi thêm '!/.agents/instincts.md' và '!/.agents/local/'." "Fix: change that line to '/.agents/*', then add '!/.agents/instincts.md' and '!/.agents/local/'.")"
        break
      fi
    done
  fi
fi

# 5b. Git pre-commit gate: the post-fix gate's static checks on every commit, also
#     commits made outside the agent. A project's own pre-commit hook is never
#     replaced (githooks.sh prints the line to chain it instead).
if [ "$GITHOOKS" = 1 ] && [ "$TARGET_DIR" != "$DEVKIT_ROOT" ] && git -C "$TARGET_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  bash "$DEVKIT_ROOT/scripts/githooks.sh" install "$TARGET_DIR" 2>&1 | sed 's/^/  /' || true
fi

# 5c. The same gates for the other agents that support hooks (OpenAI Codex, Gemini CLI,
#     Cursor): hooks/agent_bridge.sh + the bridged hooks go to .agents/hooks/, and
#     scripts/agent_hooks.py registers them in .codex/hooks.json, .gemini/settings.json
#     and .cursor/hooks.json (only DevKit-owned entries are ever touched).
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  bridge_platforms=""
  for agent_item in "${AGENT_LIST[@]}"; do
    case "$(echo "$agent_item" | tr '[:upper:]' '[:lower:]' | xargs)" in
      all) bridge_platforms="codex gemini cursor" ;;
      codex|chatgpt|openai) bridge_platforms="$bridge_platforms codex" ;;
      gemini|antigravity) bridge_platforms="$bridge_platforms gemini" ;;
      cursor) bridge_platforms="$bridge_platforms cursor" ;;
    esac
  done
  if [ -n "$bridge_platforms" ]; then
    mkdir -p "$TARGET_DIR/.agents/hooks"
    for h in agent_bridge.sh block-dangerous-git.sh hardware_safety_gate.sh session_context.sh \
             prompt_context.sh regression_gate.sh; do
      devkit_place "$DEVKIT_ROOT/hooks/$h" "$TARGET_DIR/.agents/hooks/$h" "$MODE"
    done
    for p in $bridge_platforms; do
      python3 "$DEVKIT_ROOT/scripts/agent_hooks.py" install "$p" "$TARGET_DIR" || true
    done
  fi
fi

# 6. Activate the domain profile, if one was chosen
if [ -n "$PROFILE" ] && [ "$PROFILE" != "none" ]; then
  if ! python3 "$DEVKIT_ROOT/bin/agent-config.py" --profile "$PROFILE" --target "$TARGET_DIR" --lang "$DEVKIT_LANG"; then
    echo "✖ Activating profile '$PROFILE' failed — the project was set up without a profile." >&2
    exit 1
  fi
fi

# 6b. Symlink mode: the links into this DevKit are absolute paths of THIS machine — never
# committable, yet untracked and unignored they flood `git status` and get committed by
# `git add -A`. List them in the repo's own .git/info/exclude (not shared, not committed;
# rewritten on every init). A clone runs `agent-kit init` to get its own.
if [ "$MODE" = "symlink" ] && [ "$TARGET_DIR" != "$DEVKIT_ROOT" ] && git -C "$TARGET_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  EXCLUDE="$(git -C "$TARGET_DIR" rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null)"
  if [ -n "$EXCLUDE" ]; then
    EX_BLOCK="$(mktemp "${TMPDIR:-/tmp}/devkit-exclude.XXXXXX")"
    python3 - "$TARGET_DIR" "$DEVKIT_ROOT" > "$EX_BLOCK" <<'PY'
import os, subprocess, sys
target, devkit = (os.path.realpath(p) for p in sys.argv[1:3])
tracked = set(subprocess.run(["git", "-C", target, "ls-files", "-z"], capture_output=True, text=True)
              .stdout.split("\0"))
out = []
def visit(path, depth):
    for name in sorted(os.listdir(path)):
        full = os.path.join(path, name)
        rel = os.path.relpath(full, target)
        if os.path.islink(full):
            if os.path.realpath(full).startswith(devkit + os.sep) and rel not in tracked:
                out.append("/" + rel)
        elif os.path.isdir(full) and depth > 0 and name not in (".git", "node_modules", "build", "Library"):
            visit(full, depth - 1)
visit(target, 0)                                    # root: AGENTS.md, rules, skills …
for sub in (".claude", ".agents", "rules", "skills", "commands"):
    if os.path.isdir(os.path.join(target, sub)) and not os.path.islink(os.path.join(target, sub)):
        visit(os.path.join(target, sub), 2)
print("# Machine-local DevKit links (symlink install) — recreated by `agent-kit init`")
print("\n".join(out))
PY
    mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"
    python3 "$DEVKIT_ROOT/scripts/merge_markdown.py" "$EX_BLOCK" "$EXCLUDE" "universal-agent-devkit" --comment-style=hash >/dev/null
    echo "  - $(L "Đã thêm" "Added") $(($(wc -l < "$EX_BLOCK") - 1)) $(L "link DevKit (chỉ máy này) vào .git/info/exclude" "DevKit links (this machine only) to .git/info/exclude")"
    rm -f "$EX_BLOCK"
  fi
fi

# 7. Report *_old backups, if any
if [ "$TARGET_DIR" != "$DEVKIT_ROOT" ]; then
  list_old_backups "$TARGET_DIR"
fi
