#!/usr/bin/env bash
# backup_conflict.sh — Safe Isolation for Existing Project Collisions (X_old Protection)
# Preserves user's existing skills, rules, commands, hooks, and configs without overwriting.

# Output language helper L "<vi>" "<en>" (DEVKIT_LANG) — see scripts/i18n.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/i18n.sh"

# resolve_link_target <link> — absolute target of a symlink (relative targets are
# resolved against the link's own directory). Links may be relative since the
# devkit's self-install writes portable relative links.
resolve_link_target() {
  local link="$1" t dir
  t="$(readlink "$link" || true)"
  case "$t" in
    /*) printf '%s' "$t" ;;
    "") printf '' ;;
    *)
      dir="$(cd "$(dirname "$link")" 2>/dev/null && cd "$(dirname "$t")" 2>/dev/null && pwd -P)" || dir=""
      [ -n "$dir" ] && printf '%s/%s' "$dir" "$(basename "$t")" || printf '%s' "$t"
      ;;
  esac
}

# link_is_devkit_owned <link> <devkit_root>
link_is_devkit_owned() {
  local link="$1" root="$2" t root_p
  [ -L "$link" ] && [ -n "$root" ] || return 1
  t="$(resolve_link_target "$link")"
  root_p="$(cd "$root" 2>/dev/null && pwd -P)" || root_p="$root"
  [[ "$t" == "$root_p"/* || "$t" == "$root"/* || "$t" == "$root_p" || "$t" == "$root" ]]
}

has_user_content() {
  local dir="$1"
  local devkit_root="${2:-}"

  [ -d "$dir" ] || return 1
  [ -L "$dir" ] && return 1

  local count
  count="$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | xargs)"
  [ "$count" -eq 0 ] && return 1

  if [ -n "$devkit_root" ]; then
    local non_devkit=0 item
    while IFS= read -r item; do
      [ -e "$item" ] || [ -L "$item" ] || continue
      if [ -L "$item" ]; then
        if ! link_is_devkit_owned "$item" "$devkit_root"; then
          non_devkit=1
          break
        fi
      elif ! is_unmodified_devkit_copy "$item"; then
        non_devkit=1
        break
      fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1)
    [ "$non_devkit" -eq 1 ] && return 0
    return 1
  fi

  return 0
}

# devkit_mv <src> <dest> [<moved dir> <its new place>] — mv, then re-point relative
# symlinks so they still reach what they reached before: the moved entry itself when it
# is a link, and links inside a moved folder that point outside it (links within the
# folder move with it). A link like .claude/commands/fix.md -> ../../.agents/skills/x/SKILL.md
# moved to .agents/local/commands/ would otherwise dangle. When a whole folder moves
# entry by entry (devkit_local_absorb_dir), pass it and its destination: a link to a
# sibling entry then stays pointing at that sibling's new place.
devkit_mv() {
  local src="$1" dest="$2" src_real scope="${3:-}" scope_new="${4:-}"
  src_real="$(cd "$(dirname "$src")" 2>/dev/null && pwd -P)/$(basename "$src")"
  [ -n "$scope" ] && scope="$(cd "$scope" 2>/dev/null && pwd -P)"
  mv "$src" "$dest" || return 1
  [ -L "$dest" ] || [ -d "$dest" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  [ -n "$scope_new" ] && scope_new="$(cd "$scope_new" 2>/dev/null && pwd -P)"
  python3 - "$src_real" "$dest" "$scope" "$scope_new" <<'PY' || true
import os, sys
old = sys.argv[1]
new = os.path.join(os.path.realpath(os.path.dirname(sys.argv[2])), os.path.basename(sys.argv[2]))
scope_old = sys.argv[3] or old             # everything under it moved together
scope_new = sys.argv[4] or new

def fix(link):
    t = os.readlink(link)
    if os.path.isabs(t):
        return
    rel = os.path.relpath(link, new)
    was = old if rel == "." else os.path.join(old, rel)
    target = os.path.normpath(os.path.join(os.path.dirname(was), t))
    if target == scope_old or target.startswith(scope_old + os.sep):
        target = os.path.join(scope_new, os.path.relpath(target, scope_old))  # moved along
    nt = os.path.relpath(target, os.path.dirname(link))
    if nt != t:
        os.unlink(link)
        os.symlink(nt, link)

if os.path.islink(new):
    fix(new)
elif os.path.isdir(new):
    for root, dirs, files in os.walk(new):
        for n in dirs + files:
            if os.path.islink(os.path.join(root, n)):
                fix(os.path.join(root, n))
PY
}

backup_conflict() {
  local target="$1"
  local devkit_root="${2:-}"

  [ -e "$target" ] || [ -L "$target" ] || return 0

  # If it is a symlink pointing into devkit_root, it is our own managed link -> safe to replace
  if link_is_devkit_owned "$target" "$devkit_root"; then
    return 0
  fi

  # Determine backup path (X_old)
  local parent_dir
  parent_dir="$(dirname "$target")"
  local base_name
  base_name="$(basename "$target")"

  local backup_name
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    # Directory: skills -> skills_old, rules -> rules_old
    backup_name="${base_name}_old"
  else
    # File: CLAUDE.md -> CLAUDE_old.md, or .cursorrules -> .cursorrules_old
    if [[ "$base_name" == *.* ]] && [[ "$base_name" != .* ]]; then
      local name_no_ext="${base_name%.*}"
      local ext="${base_name##*.}"
      backup_name="${name_no_ext}_old.${ext}"
    else
      backup_name="${base_name}_old"
    fi
  fi

  # Item-by-item install dirs (.claude/commands, .claude/agents, .claude/hooks,
  # .agents/skills) are loaded by the agent as a whole: a `fix_old.md` left there would
  # become a junk `/fix_old` command. The project's item that shares a DevKit name goes
  # to the project tier instead (.agents/local/<kind>/<name>, see devkit_local_slot):
  # DevKit is the core, the project's version is kept for the team to re-apply.
  local backup_dir="$parent_dir" slot
  slot="$(devkit_local_slot "$target")"
  if [ -n "$slot" ]; then
    backup_dir="$(dirname "$slot")"
    devkit_local_init "$(dirname "$backup_dir")" || return 1
    mkdir -p "$backup_dir" || return 1
    backup_name="$base_name"
  fi

  local backup_path="$backup_dir/$backup_name"

  # If X_old already exists, don't overwrite it! Append a timestamp, then a counter —
  # two backups inside the same second must never clobber (or nest into) each other.
  if [ -e "$backup_path" ] || [ -L "$backup_path" ]; then
    local ts stem ext="" n=1 candidate
    ts="$(date +%Y%m%d_%H%M%S)"
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      stem="${backup_path}_${ts}"
    elif [[ "$backup_name" == *.* ]] && [[ "$backup_name" != .* ]]; then
      stem="${backup_dir}/${backup_name%.*}_${ts}"
      ext=".${backup_name##*.}"
    else
      stem="${backup_path}_${ts}"
    fi
    candidate="${stem}${ext}"
    while [ -e "$candidate" ] || [ -L "$candidate" ]; do
      n=$((n + 1))
      candidate="${stem}_${n}${ext}"
    done
    backup_path="$candidate"
  fi

  # Move conflicting folder/file to backup path — abort loudly if the move fails,
  # otherwise the caller would go on to replace the user's data.
  if ! devkit_mv "$target" "$backup_path"; then
    echo "ERROR: [X_old Protection] could not move '$target' to '$backup_path' — nothing replaced." >&2
    return 1
  fi

  # Colored user-friendly notification
  local YELLOW='\033[1;33m'
  local CYAN='\033[0;36m'
  local GREEN='\033[0;32m'
  local RESET='\033[0m'

  echo -e "${YELLOW}  ⚠️ [X_old Protection] $(L "Phát hiện xung đột dự án cũ:" "conflict with an existing project item:")${RESET} ${CYAN}${base_name}${RESET}"
  if [ -n "$slot" ]; then
    local shown="$DEVKIT_LOCAL_DIR/${backup_path#*/$DEVKIT_LOCAL_DIR/}"
    echo -e "     ➔ ${GREEN}$(L "ĐÃ CHUYỂN VÀO TẦNG DỰ ÁN:" "MOVED TO THE PROJECT TIER:")${RESET} ${CYAN}${shown}${RESET} $(L "— DevKit là core; bản của bạn giữ nguyên ở đây để tự áp lại (đổi tên để dùng song song)." "— DevKit is the core; yours is kept here to re-apply (rename it to use both).")"
  else
    local shown="$(basename "$backup_path")"
    echo -e "     ➔ ${GREEN}$(L "ĐÃ ĐỔI TÊN THÀNH:" "RENAMED TO:")${RESET} ${CYAN}${shown}${RESET} $(L "để bạn tự merge theo ý mình (Không ghi đè làm mất mã nguồn)!" "so you can merge it yourself (nothing was overwritten).")"
  fi

  # Record to a session backup ledger next to the conflicting item
  local ledger_dir="$backup_dir"
  [ -d "$ledger_dir" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') | $target -> $backup_path" >> "$ledger_dir/.devkit_backups.log" 2>/dev/null || true

  return 0
}

DEVKIT_MANIFEST=".devkit-copy"

_devkit_manifest() { # <dir> — sorted "sha  path" list of every file except the manifest
  local sum=shasum
  command -v shasum >/dev/null 2>&1 || sum=sha1sum
  (cd "$1" && find . -type f ! -name "$DEVKIT_MANIFEST" -exec "$sum" {} + 2>/dev/null | LC_ALL=C sort -k2)
}

# is_unmodified_devkit_copy <dir> — a copy-mode install the user has not edited since.
is_unmodified_devkit_copy() {
  local dir="$1"
  [ -d "$dir" ] && [ ! -L "$dir" ] && [ -f "$dir/$DEVKIT_MANIFEST" ] || return 1
  [ "$(_devkit_manifest "$dir")" = "$(cat "$dir/$DEVKIT_MANIFEST")" ]
}

# Per-directory ledger of single FILES the devkit copied (copy mode): "sha  name" lines.
# Lets an upgrade tell "devkit file the user never touched" (replace silently) from
# "file the user edited" (preserve as *_old) — comparing against the NEW devkit source
# with cmp would flag every file the devkit itself changed.
DEVKIT_FILE_LEDGER=".devkit-files"

_devkit_sha() {
  if command -v shasum >/dev/null 2>&1; then shasum "$1" | cut -d' ' -f1; else sha1sum "$1" | cut -d' ' -f1; fi
}

# forget_devkit_file <dst> — drop <dst> from its directory ledger
forget_devkit_file() {
  local dst="$1" ledger name tmp
  ledger="$(dirname "$dst")/$DEVKIT_FILE_LEDGER"
  name="$(basename "$dst")"
  [ -f "$ledger" ] || return 0
  tmp="$(mktemp "${ledger}.XXXXXX")" || return 0
  awk -v n="$name" '{ line=$0; sub(/^[^ ]+  /, "", line); if (line != n) print }' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
  [ -s "$ledger" ] || rm -f "$ledger"
}

# record_devkit_file <dst> — remember the hash of a file the devkit just copied
record_devkit_file() {
  local dst="$1"
  forget_devkit_file "$dst"
  printf '%s  %s\n' "$(_devkit_sha "$dst")" "$(basename "$dst")" >> "$(dirname "$dst")/$DEVKIT_FILE_LEDGER"
}

# is_recorded_devkit_file <dst> — a devkit-copied file whose content is unchanged since
is_recorded_devkit_file() {
  local dst="$1" ledger name want
  [ -f "$dst" ] && [ ! -L "$dst" ] || return 1
  ledger="$(dirname "$dst")/$DEVKIT_FILE_LEDGER"
  name="$(basename "$dst")"
  [ -f "$ledger" ] || return 1
  want="$(awk -v n="$name" '{ line=$0; sub(/^[^ ]+  /, "", line); if (line == n) { split($0, a, " "); print a[1] } }' "$ledger" | tail -n 1)"
  [ -n "$want" ] && [ "$want" = "$(_devkit_sha "$dst")" ]
}

# is_foreign_project_dir <dir> — a real directory that belongs to the PROJECT itself
# (e.g. a CLI's own commands/ holding build.js): it has files that are neither devkit
# links nor a devkit copy (no .devkit-copy manifest). The installer must leave such a
# directory exactly where it is — renaming it to *_old would break the project's build.
is_foreign_project_dir() {
  local dir="$1"
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  [ -f "$dir/$DEVKIT_MANIFEST" ] && return 1
  has_user_content "$dir" "${DEVKIT_ROOT:-}"
}

# devkit_ln <src> <dst> — symlink; relative when dst lives inside the devkit itself
# (self-install), so the committed links work on every clone.
devkit_ln() {
  local src="$1" dst="$2" root_p dst_dir src_p
  root_p="$(cd "${DEVKIT_ROOT:-/nonexistent}" 2>/dev/null && pwd -P)" || root_p=""
  dst_dir="$(cd "$(dirname "$dst")" && pwd -P)"
  if [ -n "$root_p" ] && [[ "$dst_dir/" == "$root_p/"* ]]; then
    src_p="$(cd "$(dirname "$src")" && pwd -P)/$(basename "$src")"
    src="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$src_p" "$dst_dir")"
  fi
  ln -sfn "$src" "$dst"
}

# ---- Project tier (.agents/local) ------------------------------------------------
# DevKit is the core. When a project item shares a DevKit name, the DevKit version is
# installed and the project's version moves to .agents/local/<kind>/<name>: outside
# every directory an agent loads, never written by the installer afterwards, and meant
# to be committed (unlike *_old). Project items there whose name is free are linked
# into the agent dirs (devkit_link_local), so the team's own additions keep working.
DEVKIT_LOCAL_DIR=".agents/local"

# devkit_local_slot <path> — project-tier location for an item of an item-by-item
# install dir (.claude/{commands,agents,hooks}/<name>, .agents/skills/<name>); "" else.
devkit_local_slot() {
  local parent parent_p root_p
  parent="$(dirname "$1")"
  case "$parent" in
    */.claude/commands|*/.claude/agents|*/.claude/hooks|*/.agents/skills)
      printf '%s/%s/%s/%s' "$(dirname "$(dirname "$parent")")" "$DEVKIT_LOCAL_DIR" "$(basename "$parent")" "$(basename "$1")"
      return ;;
  esac
  # An item inside the project's own root rules/ skills/ commands/ (a source-code dir
  # the DevKit items were placed into, see devkit_place_into_dir).
  case "$(basename "$parent")" in rules|skills|commands) ;; *) printf ''; return ;; esac
  if [ -n "${TARGET_DIR:-}" ]; then
    parent_p="$(cd "$(dirname "$parent")" 2>/dev/null && pwd -P)"
    root_p="$(cd "$TARGET_DIR" 2>/dev/null && pwd -P)"
    if [ -n "$root_p" ] && [ "$parent_p" = "$root_p" ]; then
      printf '%s/%s/%s/%s' "$TARGET_DIR" "$DEVKIT_LOCAL_DIR" "$(basename "$parent")" "$(basename "$1")"
      return
    fi
  fi
  printf ''
}

# _devkit_owned_entry <path> — installed by the DevKit (link, recorded file, copy dir)
_devkit_owned_entry() {
  link_is_devkit_owned "$1" "${DEVKIT_ROOT:-}" || is_recorded_devkit_file "$1" || is_unmodified_devkit_copy "$1"
}

# devkit_is_agent_content_dir <dir> <rules|skills|commands> — the project's root dir holds
# only agent material (so it can move to the project tier without breaking any build):
#   rules/    every file is .md / .mdc / .markdown / .txt
#   commands/ every entry is a .md/.mdc file, or a folder of them (namespaced commands)
#   skills/   every entry is a skill folder with SKILL.md, or a .md file
# Anything else (commands/build.js, rules/no-foo.js …) is the project's source code.
devkit_is_agent_content_dir() {
  local dir="$1" kind="$2" e name
  for e in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    name="$(basename "$e")"
    case "$name" in .DS_Store|.gitkeep|"$DEVKIT_MANIFEST"|"$DEVKIT_FILE_LEDGER"|.devkit_backups.log) continue ;; esac
    _devkit_owned_entry "$e" && continue
    case "$kind" in
      rules)
        [ -z "$(find "$e" -type f ! -name '.*' 2>/dev/null | grep -viE '\.(md|mdc|markdown|txt)$' | head -n 1)" ] || return 1 ;;
      commands)
        if [ -d "$e" ]; then
          [ -z "$(find "$e" -type f ! -name '.*' 2>/dev/null | grep -viE '\.(md|mdc)$' | head -n 1)" ] || return 1
        else
          case "$name" in *.md|*.mdc) ;; *) return 1 ;; esac
        fi ;;
      skills)
        if [ -d "$e" ]; then [ -f "$e/SKILL.md" ] || return 1
        else case "$name" in *.md) ;; *) return 1 ;; esac
        fi ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# devkit_local_absorb_dir <project root dir> <kind> — move the project's own agent
# material from <project>/<kind>/ into the project tier .agents/local/<kind>/ entry by
# entry (DevKit-installed entries are just dropped), leaving <kind>/ free for the DevKit.
devkit_local_absorb_dir() {
  local dir="$1" kind="$2" dest_dir e name dest base n ledger
  dest_dir="$TARGET_DIR/$DEVKIT_LOCAL_DIR/$kind"
  devkit_local_init "$TARGET_DIR/$DEVKIT_LOCAL_DIR" || return 1
  mkdir -p "$dest_dir" || return 1
  ledger="$dest_dir/.devkit_backups.log"
  for e in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    name="$(basename "$e")"
    case "$name" in "$DEVKIT_MANIFEST"|"$DEVKIT_FILE_LEDGER") rm -f "$e"; continue ;; esac
    if _devkit_owned_entry "$e"; then rm -rf "$e"; continue; fi
    dest="$dest_dir/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      base="${dest}_$(date +%Y%m%d_%H%M%S)"; dest="$base"; n=1
      while [ -e "$dest" ] || [ -L "$dest" ]; do n=$((n + 1)); dest="${base}_$n"; done
    fi
    devkit_mv "$e" "$dest" "$dir" "$dest_dir" || { echo "ERROR: could not move '$e' to '$dest' — nothing replaced." >&2; return 1; }
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $e -> $dest" >> "$ledger"
  done
  rmdir "$dir" || { echo "ERROR: '$dir' is not empty after moving its content — nothing replaced." >&2; return 1; }
  echo "  ⚠️ [Project tier] $kind/ → $DEVKIT_LOCAL_DIR/$kind/ — $(L "DevKit là core; bản của bạn ở đây để tự áp lại" "DevKit is the core; yours is kept there to re-apply")"
}

# devkit_place_into_dir <devkit dir> <project dir> <mode> — the project's root dir is its
# source code and must stay: place every DevKit item inside it one by one, so every
# DevKit path (rules/core-rules.md, skills/qc/SKILL.md, …) resolves. A project file with
# a DevKit name moves to the project tier (devkit_local_slot); the rest is untouched.
devkit_place_into_dir() {
  local src="$1" dst="$2" mode="$3" item
  for item in "$src"/*; do
    [ -e "$item" ] || continue
    devkit_place "$item" "$dst/$(basename "$item")" "$mode" || return 1
  done
}

# devkit_local_init <project>/.agents/local — create it with a README the first time.
devkit_local_init() {
  local dir="$1"
  [ -d "$dir" ] && return 0
  mkdir -p "$dir" || return 1
  _devkit_local_readme > "$dir/README.md"
}

# _devkit_local_readme [v1] — the README a new project tier gets; "v1" prints the text
# written before rules/ were imported, so prune still recognises an untouched old copy.
_devkit_local_readme() {
  cat <<'README_EOF'
# .agents/local — project tier

Your own skills, commands, agents, hooks and rules. Universal Agent DevKit never
writes into this folder after moving an item here; commit it with the project.

- An item here whose name the DevKit does NOT use is linked into the agent folders
  (`skills/` → `.agents/skills/`, `commands/` → `.claude/commands/`, `agents/` →
  `.claude/agents/`, `hooks/` → `.claude/hooks/`) on every `agent-kit init`.
- An item with the same name as a DevKit item is kept here but NOT active — the
  DevKit version wins. Re-apply your changes on top of it, or rename yours to use both.
README_EOF
  if [ "${1:-}" = v1 ]; then
    printf '%s\n' '- `rules/` and dated copies (`name_YYYYMMDD_HHMMSS…`) are reference only, never linked.'
  else
    cat <<'README_EOF'
- `rules/` files are listed as @-imports in the DevKit block of `CLAUDE.md`, `AGENTS.md`
  (a project's own one), `GEMINI.md`, `.cursorrules` on every `agent-kit init`: they add
  to the DevKit rules, and the DevKit rule wins where they contradict it.
- Dated copies (`name_YYYYMMDD_HHMMSS…`) are reference only, never linked or imported.
README_EOF
  fi
  printf '%s\n' '- `agent-kit list-old` shows what is active and what is shadowed.'
}

# devkit_local_rule_files <project> — the project's own rule files kept in the project
# tier (.agents/local/rules/), relative to <project>, sorted. Dated copies
# (name_YYYYMMDD_HHMMSS…) are older versions kept for reference and are left out.
devkit_local_rule_files() {
  local dir="$1/$DEVKIT_LOCAL_DIR/rules"
  [ -d "$dir" ] || return 0
  # Files and links to files (a rule may be a link to a shared file); one import per
  # real file — real files win over links to them; dated backup copies are skipped.
  (cd "$1" && python3 - "$DEVKIT_LOCAL_DIR/rules" <<'PY'
import os, re, sys
root = sys.argv[1]
found = []
for d, dirs, files in os.walk(root, followlinks=False):
    dirs[:] = sorted(x for x in dirs if not x.startswith("."))
    for f in files:
        p = os.path.join(d, f)
        if f.startswith(".") or not re.search(r"\.(md|mdc|markdown|txt)$", f, re.I) \
                or re.search(r"_\d{8}_\d{6}", p) or not os.path.isfile(p):
            continue
        found.append((os.path.islink(p), p))
seen, out = set(), []
for _, p in sorted(found):
    r = os.path.realpath(p)
    if r not in seen:
        seen.add(r)
        out.append(p)
print("\n".join(sorted(out)))
PY
  )
}

# devkit_master_ref <project root> — the path an agent file uses to reach the DevKit
# master rules: AGENTS.md while that file is (or is about to be) the DevKit's own.
# A project that keeps its own AGENTS.md gets the master linked at
# .agents/devkit/AGENTS.md instead — `@AGENTS.md` there would import only the
# project's file, and §5–§8 of the master would never reach the agent.
devkit_master_ref() {
  local root="$1" a="$1/AGENTS.md"
  if { [ ! -e "$a" ] && [ ! -L "$a" ]; } || link_is_devkit_owned "$a" "$DEVKIT_ROOT" \
      || is_recorded_devkit_file "$a" || cmp -s "$a" "$DEVKIT_ROOT/AGENTS.md"; then
    echo "AGENTS.md"
    return 0
  fi
  devkit_place "$DEVKIT_ROOT/AGENTS.md" "$root/.agents/devkit/AGENTS.md" "${MODE:-symlink}" >/dev/null || return 1
  echo ".agents/devkit/AGENTS.md"
}

# devkit_merge_block <template block> <agent file> — inject the DevKit block into an
# agent file: the master rules (devkit_master_ref), the active profile's rules when a
# profile is being installed (DEVKIT_PROFILE, set by install.sh; the stable
# .agents/active-profile/RULES.md follows `agent-kit profile` switches), and the
# project tier's own rules (.agents/local/rules) as @-imports.
devkit_merge_block() {
  local tpl="$1" dst="$2" root rules block rc master
  root="$(cd "$(dirname "$dst")" 2>/dev/null && pwd -P)"
  rules="$(devkit_local_rule_files "$root")"
  master="$(devkit_master_ref "$root")" || master="AGENTS.md"
  block="$(mktemp "${TMPDIR:-/tmp}/devkit_block.XXXXXX")" || return 1
  {
    sed "s|@AGENTS\.md|@$master|" "$tpl" | awk -v prof="${DEVKIT_PROFILE:-}" '
      { print }
      /Active Domain Profile:/ && prof != "" && prof != "none" && prof != "ask" {
        print "- Domain Profile Rules: @.agents/active-profile/RULES.md"
      }'
    if [ -n "$rules" ]; then
      printf '\n## Project rules (%s/rules — project tier)\n' "$DEVKIT_LOCAL_DIR"
      printf 'Read these before editing code: this project'"'"'s own rules on top of the DevKit. Where one contradicts `%s` §6 or `rules/core-rules.md`, the DevKit rule wins — tell the user about the conflict.\n' "$master"
      printf '%s\n' "$rules" | sed 's/^/- @/'
    fi
  } > "$block"
  python3 "$DEVKIT_ROOT/scripts/merge_markdown.py" "$block" "$dst" "universal-agent-devkit"
  rc=$?
  rm -f "$block"
  return $rc
}

# devkit_local_prune <project> — after restore-old --apply: drop project-tier ledgers
# whose backups were all put back, the untouched README, then empty folders. Anything
# the team still keeps in .agents/local stays.
devkit_local_prune() {
  local root="$1" dir ledger line backup left d
  dir="$root/$DEVKIT_LOCAL_DIR"
  [ -d "$dir" ] || return 0
  # Links devkit_link_local made to project-tier items that were just put back.
  for d in .agents/skills .claude/commands .claude/agents .claude/hooks; do
    [ -d "$root/$d" ] || continue
    for line in "$root/$d"/*; do
      [ -L "$line" ] && [ ! -e "$line" ] || continue
      case "$(readlink "$line")" in *"$DEVKIT_LOCAL_DIR"/*) rm -f "$line" ;; esac
    done
    rmdir "$root/$d" 2>/dev/null
  done
  while IFS= read -r ledger; do
    left=0
    while IFS= read -r line || [ -n "$line" ]; do
      backup="${line#* -> }"
      [ "$backup" != "$line" ] && { [ -e "$backup" ] || [ -L "$backup" ]; } && left=1
    done < "$ledger"
    [ "$left" -eq 0 ] && rm -f "$ledger"
  done < <(find "$dir" -name .devkit_backups.log 2>/dev/null)
  find "$dir" -depth -mindepth 1 -type d -empty -exec rmdir {} \; 2>/dev/null
  if [ -z "$(find "$dir" -mindepth 1 ! -name README.md 2>/dev/null | head -n 1)" ] \
     && { [ ! -e "$dir/README.md" ] || cmp -s "$dir/README.md" <(_devkit_local_readme) \
          || cmp -s "$dir/README.md" <(_devkit_local_readme v1); }; then
    rm -f "$dir/README.md"
    rmdir "$dir" 2>/dev/null
    rmdir "$root/.agents" 2>/dev/null
  fi
  return 0
}

# devkit_is_local_link <link> — a symlink into this project's .agents/local. Needs
# TARGET_DIR, which install.sh and every adapter (all devkit_place callers) set.
devkit_is_local_link() {
  local t local_p
  [ -L "$1" ] && [ -n "${TARGET_DIR:-}" ] || return 1
  local_p="$(cd "$TARGET_DIR/$DEVKIT_LOCAL_DIR" 2>/dev/null && pwd -P)" || return 1
  t="$(resolve_link_target "$1")"
  [[ "$t" == "$local_p"/* ]]
}

# devkit_copy_keep_edits <edited devkit copy dir> <dest> — move only the files the
# team changed or added (compared with the .devkit-copy manifest) to <dest>, so the
# project tier holds the team's edits, not a stale copy of the whole DevKit dir.
# One ledger line per file (restore-old can put them back after an uninstall).
devkit_copy_keep_edits() {
  local dir="$1" dest="$2" rel n=1 ledger base
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    base="${dest}_$(date +%Y%m%d_%H%M%S)"   # an earlier kept edit is never overwritten
    dest="$base"
    while [ -e "$dest" ] || [ -L "$dest" ]; do n=$((n + 1)); dest="${base}_$n"; done
  fi
  # The ledger lives in the kind folder (.agents/local/<kind>/): for an item
  # (.agents/local/skills/fixbugs) that is its parent, for a root dir
  # (.agents/local/rules) the kept folder is the kind folder itself.
  ledger="$(dirname "$dest")/.devkit_backups.log"
  case "$(basename "$(dirname "$dest")")" in local) ledger="$dest/.devkit_backups.log" ;; esac
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rel="${rel#./}"
    mkdir -p "$dest/$(dirname "$rel")" || return 1
    devkit_mv "$dir/$rel" "$dest/$rel" || { echo "ERROR: could not keep '$dir/$rel' in '$dest' — nothing replaced." >&2; return 1; }
    mkdir -p "$(dirname "$ledger")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $dir/$rel -> $dest/$rel" >> "$ledger"
    echo "  ⚠️ [Project tier] $(L "Giữ phần bạn sửa:" "kept your edit:") ${DEVKIT_LOCAL_DIR}/${dest#*/$DEVKIT_LOCAL_DIR/}/$rel"
  done < <(LC_ALL=C comm -13 <(LC_ALL=C sort "$dir/$DEVKIT_MANIFEST") <(_devkit_manifest "$dir" | LC_ALL=C sort) | sed 's/^[^ ]*  //')
  return 0
}

# devkit_link_local <project> <kind> <install dir, relative to project> — link the
# project's own items from .agents/local/<kind>/ into the agent dir when the name is
# free. A DevKit item of the same name wins and is reported. Relative links: the
# project tier is committed, so the links must work on every clone. Idempotent.
devkit_link_local() {
  local project="$1" kind="$2" rel="$3" item name dst want up="" d
  [ -d "$project/$DEVKIT_LOCAL_DIR/$kind" ] || return 0
  [ "$project" = "${DEVKIT_ROOT:-}" ] && return 0
  d="$rel"
  while [ -n "$d" ] && [ "$d" != "." ]; do up="../$up"; d="$(dirname "$d")"; done
  mkdir -p "$project/$rel"
  for item in "$project/$DEVKIT_LOCAL_DIR/$kind"/*; do
    [ -e "$item" ] || continue
    name="$(basename "$item")"
    case "$name" in *_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]*) continue ;; esac
    dst="$project/$rel/$name"
    want="${up}${DEVKIT_LOCAL_DIR}/$kind/$name"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$want" ]; then
      continue
    elif link_is_devkit_owned "$dst" "${DEVKIT_ROOT:-}" || is_unmodified_devkit_copy "$dst" || is_recorded_devkit_file "$dst"; then
      echo "  - $(L "Tầng dự án" "Project tier"): $kind/$name — $(L "bản DevKit đang dùng; bản của bạn ở" "DevKit version active; yours is at") $DEVKIT_LOCAL_DIR/$kind/$name $(L "(đổi tên để dùng song song)" "(rename it to use both)")"
    elif [ -e "$dst" ] || [ -L "$dst" ]; then
      echo "  - $(L "Tầng dự án" "Project tier"): $kind/$name — $(L "$rel/$name đã có file khác, không link" "$rel/$name holds another file, not linked")"
    else
      ln -s "$want" "$dst" && echo "  - $(L "Tầng dự án: đã link" "Project tier: linked") $rel/$name → $DEVKIT_LOCAL_DIR/$kind/$name"
    fi
  done
}

# devkit_place <src> <dst> <symlink|copy> — idempotent install of one devkit item.
# Replaces our own links, unmodified copies, identical files, empty dirs and dirs
# holding only devkit links; anything else the user owns is moved to *_old first.
# Never writes *through* an existing symlink (cp into a link would modify the devkit).
# devkit_link_local_skill_commands <project> — Claude Code reaches a skill through a
# command linked to its SKILL.md (as it does the DevKit's). A project-tier skill with no
# command of its own gets .claude/commands/<name>.md -> ../../.agents/local/skills/<name>/SKILL.md,
# unless a command of that name exists (the DevKit's wins, the project's is its own).
devkit_link_local_skill_commands() {
  local project="$1" skill name dst want
  [ -d "$project/$DEVKIT_LOCAL_DIR/skills" ] || return 0
  [ "$project" = "${DEVKIT_ROOT:-}" ] && return 0
  mkdir -p "$project/.claude/commands"
  for skill in "$project/$DEVKIT_LOCAL_DIR/skills"/*/; do
    skill="${skill%/}"; name="$(basename "$skill")"
    [ -f "$skill/SKILL.md" ] || continue
    case "$name" in *_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]*) continue ;; esac
    [ -e "$project/$DEVKIT_LOCAL_DIR/commands/$name.md" ] && continue
    dst="$project/.claude/commands/$name.md"
    want="../../$DEVKIT_LOCAL_DIR/skills/$name/SKILL.md"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$want" ]; then
      continue
    elif [ -e "$dst" ] || [ -L "$dst" ]; then
      echo "  - $(L "Tầng dự án" "Project tier"): skill $name — $(L "đã có lệnh /$name khác, không link" "a /$name command already exists, not linked")"
    else
      ln -s "$want" "$dst" && echo "  - $(L "Tầng dự án: skill → lệnh" "Project tier: skill → command") /$name"
    fi
  done
}

devkit_place() {
  local src="$1" dst="$2" mode="$3" parent_p root_p target_p
  # Guard: a symlinked project dir (e.g. .claude/commands -> DEVKIT/commands) or a
  # symlinked alias of the devkit would make every rm/ln below act on the devkit
  # itself. Compare PHYSICAL paths and refuse instead of destroying the source.
  mkdir -p "$(dirname "$dst")"
  parent_p="$(cd "$(dirname "$dst")" && pwd -P)"
  root_p="$(cd "${DEVKIT_ROOT:-/nonexistent}" 2>/dev/null && pwd -P)" || root_p=""
  target_p="$(cd "${TARGET_DIR:-.}" 2>/dev/null && pwd -P)" || target_p=""
  if [ -n "$root_p" ] && [[ "$parent_p/" == "$root_p/"* ]] && [ "$target_p" != "$root_p" ]; then
    echo "ERROR: '$dst' resolves into the DevKit itself ($parent_p)." >&2
    echo "       Replace that symlinked directory in the project with a real directory and re-run." >&2
    return 1
  fi
  if [ -e "$dst" ] && [ "$(cd "$(dirname "$src")" && pwd -P)/$(basename "$src")" = "$parent_p/$(basename "$dst")" ]; then
    return 0 # dst IS src — nothing to place
  fi
  if [ -L "$dst" ]; then
    if link_is_devkit_owned "$dst" "${DEVKIT_ROOT:-}"; then
      rm -f "$dst"
    elif devkit_is_local_link "$dst"; then
      # A project-tier item linked here earlier; the DevKit now has one of that name.
      # Its content stays in .agents/local — only the link goes.
      rm -f "$dst"
      echo "  - $(L "Tầng dự án: DevKit giờ có" "Project tier: the DevKit now provides") $(basename "$dst") — $(L "bản của bạn vẫn ở .agents/local, không còn active" "yours stays in .agents/local, no longer active")"
    else
      backup_conflict "$dst" "${DEVKIT_ROOT:-}"
    fi
  elif [ -d "$dst" ]; then
    local keep_to=""
    if [ -f "$dst/$DEVKIT_MANIFEST" ]; then
      keep_to="$(devkit_local_slot "$dst")"
      if [ -z "$keep_to" ] && [ -n "${TARGET_DIR:-}" ] && [ "$parent_p" = "$target_p" ]; then
        keep_to="$TARGET_DIR/$DEVKIT_LOCAL_DIR/$(basename "$dst")"   # root rules/ skills/ commands/
      fi
    fi
    if is_unmodified_devkit_copy "$dst" || ! has_user_content "$dst" "${DEVKIT_ROOT:-}"; then
      rm -rf "$dst"
    elif [ -n "$keep_to" ]; then
      # An edited DevKit copy: keep the team's edits in the project tier, then refresh.
      devkit_local_init "${keep_to%%/"$DEVKIT_LOCAL_DIR"/*}/$DEVKIT_LOCAL_DIR" || return 1
      devkit_copy_keep_edits "$dst" "$keep_to" || return 1
      rm -rf "$dst"
    else
      backup_conflict "$dst" "${DEVKIT_ROOT:-}"
    fi
  elif [ -e "$dst" ]; then
    if cmp -s "$src" "$dst" || is_recorded_devkit_file "$dst"; then
      rm -f "$dst"
    else
      backup_conflict "$dst" "${DEVKIT_ROOT:-}" || return 1
    fi
  fi
  mkdir -p "$(dirname "$dst")"
  if [ "$mode" = "symlink" ]; then
    devkit_ln "$src" "$dst"
    forget_devkit_file "$dst"
  else
    cp -RL "$src" "$dst"
    if [ -d "$dst" ]; then _devkit_manifest "$dst" > "$dst/$DEVKIT_MANIFEST"; else record_devkit_file "$dst"; fi
  fi
}

# devkit_install_agents_md <target_dir> <symlink|copy> — shared by every adapter.
#   absent / devkit link / unmodified devkit copy -> (re)placed per mode
#   the project's OWN AGENTS.md                    -> kept, backed up once as AGENTS_old.md,
#                                                     DevKit block injected between markers
#   a foreign symlink (dotfile manager)            -> left alone
devkit_install_agents_md() {
  local target="$1" mode="$2" dst src marker="universal-agent-devkit"
  dst="$target/AGENTS.md"
  src="$DEVKIT_ROOT/AGENTS.md"
  [ "$target" = "$DEVKIT_ROOT" ] && return 0
  if [ -L "$dst" ] && ! link_is_devkit_owned "$dst" "$DEVKIT_ROOT"; then
    echo "  - AGENTS.md is a symlink you manage — left untouched"
    return 0
  fi
  if [ -f "$dst" ] && [ ! -L "$dst" ] && ! cmp -s "$src" "$dst" && ! is_recorded_devkit_file "$dst"; then
    if [ ! -e "$target/AGENTS_old.md" ] && ! grep -q "$marker" "$dst" 2>/dev/null; then
      cp "$dst" "$target/AGENTS_old.md"
      echo "  - Preserved original AGENTS.md as AGENTS_old.md"
    fi
    devkit_merge_block "$DEVKIT_ROOT/templates/agents_injection_block.md" "$dst"
    echo "  - Injected DevKit standards into existing AGENTS.md (Preserved custom architecture)"
    return 0
  fi
  devkit_place "$src" "$dst" "$mode" || return 1
  if [ "$mode" = "symlink" ]; then
    echo "  - AGENTS.md linked to DevKit SSOT"
  else
    echo "  - AGENTS.md copied from DevKit SSOT"
  fi
}

# ---- Profile skill filter (P1-5) -------------------------------------------------
# DEVKIT_SKILLS_ALLOWED: space-separated skill names the active profile installs
# (set by install.sh from scripts/profile_skills.py). Unset/empty = every skill.

# devkit_skill_allowed <skill-name>
devkit_skill_allowed() {
  [ -n "${DEVKIT_SKILLS_ALLOWED:-}" ] || return 0
  case " $DEVKIT_SKILLS_ALLOWED " in *" $1 "*) return 0 ;; esac
  return 1
}

# devkit_command_skill <devkit command file> — the skill a command resolves to
# (commands/*.md are link chains ending at skills/<name>/SKILL.md); "" when none.
devkit_command_skill() {
  local f="$1" n=0 t
  while [ -L "$f" ] && [ "$n" -lt 10 ]; do
    t="$(resolve_link_target "$f")"
    [ -n "$t" ] || break
    f="$t"; n=$((n + 1))
  done
  case "$f" in
    */skills/*/SKILL.md) f="${f%/SKILL.md}"; printf '%s' "${f##*/}" ;;
    *) printf '' ;;
  esac
}

# devkit_command_allowed <devkit command file>
devkit_command_allowed() {
  local skill
  skill="$(devkit_command_skill "$1")"
  [ -z "$skill" ] || devkit_skill_allowed "$skill"
}

# devkit_remove_filtered <dst> — remove a DevKit item the profile no longer installs.
# Only our own links / unmodified copies go; anything the user edited stays.
devkit_remove_filtered() {
  local dst="$1"
  if [ -L "$dst" ]; then
    link_is_devkit_owned "$dst" "${DEVKIT_ROOT:-}" && rm -f "$dst"
  elif [ -d "$dst" ]; then
    is_unmodified_devkit_copy "$dst" && rm -rf "$dst"
  elif [ -f "$dst" ]; then
    if is_recorded_devkit_file "$dst"; then rm -f "$dst"; forget_devkit_file "$dst"; fi
  fi
  return 0
}

backup_dir_if_user_content() {
  local dir="$1"
  local devkit_root="${2:-}"
  if has_user_content "$dir" "$devkit_root"; then
    backup_conflict "$dir" "$devkit_root"
  fi
}

backup_file_if_user_content() {
  local file="$1"
  local marker="${2:-universal-agent-devkit}"
  [ -f "$file" ] || return 0
  [ -L "$file" ] && return 0
  if ! grep -q "$marker" "$file" 2>/dev/null; then
    backup_conflict "$file" ""
  fi
}

list_old_backups() {
  local root_dir="${1:-$PWD}"
  echo "================================================================="
  echo "  🔍 $(L "Danh Sách Các Mục Đã Được Bảo Vệ (*_old) Trong Dự Án:" "Protected items (*_old) in this project:")"
  echo "  $(L "Thư mục kiểm tra:" "Checked directory:") $root_dir"
  echo "================================================================="
  local found=0 item
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    found=1
    local rel_path="${item#$root_dir/}"
    if [ -d "$item" ]; then
      echo "  📁 [$(L "Thư mục cũ" "old dir")] $rel_path"
    else
      echo "  📄 [$(L "Tập tin cũ" "old file")]  $rel_path"
    fi
  done < <(find "$root_dir" -maxdepth 3 \( -name "*_old" -o -name "*_old.*" -o -name "*_old_*" \) 2>/dev/null | grep -v "/\.git/")

  if [ "$found" -eq 0 ]; then
    echo "  ✔ $(L "Không có mục *_old nào (Dự án sạch hoặc chưa phát sinh xung đột)." "No *_old items (clean project, no conflicts so far).")"
  else
    echo "-----------------------------------------------------------------"
    echo "  👉 $(L "Lời khuyên: Bạn có thể xem lại mã nguồn trong các mục *_old" "Tip: review the *_old items")"
    echo "     $(L "và chủ động copy/merge các kỹ năng, quy tắc riêng vào thư mục mới." "and copy/merge your own skills and rules into the new directories.")"
    echo "================================================================="
  fi
  list_local_tier "$root_dir"
}

# list_local_tier <project> — the project tier and whether each item is active.
list_local_tier() {
  local root_dir="${1:-$PWD}" kind rel item name dst state
  [ -d "$root_dir/$DEVKIT_LOCAL_DIR" ] || return 0
  echo "  📦 $(L "Tầng dự án" "Project tier") ($DEVKIT_LOCAL_DIR — $(L "DevKit là core; commit thư mục này" "DevKit is the core; commit this folder")):"
  for kind in skills commands agents hooks rules; do
    case "$kind" in
      skills) rel=".agents/skills" ;; commands) rel=".claude/commands" ;;
      agents) rel=".claude/agents" ;; hooks) rel=".claude/hooks" ;; *) rel="" ;;
    esac
    for item in "$root_dir/$DEVKIT_LOCAL_DIR/$kind"/*; do
      [ -e "$item" ] || continue
      name="$(basename "$item")"
      dst="$root_dir/$rel/$name"
      if [ -z "$rel" ]; then
        # rules/ are not linked anywhere: the DevKit block of the agent files @-imports
        # them (a link to a rule imported under its real name counts as that one).
        if cat "$root_dir/CLAUDE.md" "$root_dir/AGENTS.md" "$root_dir/CODEX.md" 2>/dev/null \
            | grep -o "@$DEVKIT_LOCAL_DIR/rules/[^ ]*" | sed 's/^@//' | while read -r imp; do
                python3 -c 'import os,sys; a,b=(os.path.realpath(x) for x in sys.argv[1:3]); sys.exit(0 if a==b or a.startswith(b+os.sep) else 1)' \
                  "$root_dir/$imp" "$item" && echo yes; done | grep -q yes; then
          state="$(L "đang dùng (@ trong CLAUDE.md/AGENTS.md)" "active (@-imported in CLAUDE.md/AGENTS.md)")"
        elif printf '%s' "$name" | grep -qE '_[0-9]{8}_[0-9]{6}'; then
          state="$(L "bản lưu có ngày (không import)" "dated copy (not imported)")"
        else
          state="$(L "chưa import (chạy lại agent-kit init)" "not imported yet (re-run agent-kit init)")"
        fi
      elif [ -L "$dst" ] && [ "$(resolve_link_target "$dst")" = "$(cd "$(dirname "$item")" && pwd -P)/$name" ]; then
        state="$(L "đang dùng" "active")"
      elif [ -e "$dst" ] || [ -L "$dst" ]; then
        state="$(L "bị che — bản DevKit cùng tên đang dùng" "shadowed — the DevKit item of that name is active")"
      else
        state="$(L "chưa link (chạy lại agent-kit init)" "not linked yet (re-run agent-kit init)")"
      fi
      echo "     - $kind/$name: $state"
    done
  done
  echo "================================================================="
}

# restore_old_backups <project_dir> [--apply]
# Puts *_old backups recorded in .devkit_backups.log ledgers back in place. Dry-run by
# default. A backup is restored only when its original location is now empty, a symlink
# into the DevKit, a devkit-copied file the user never edited (.devkit-files) or an
# unmodified devkit copy directory (.devkit-copy). Anything else at that location holds
# content that is not the DevKit's, so it is reported and left alone — merge by hand.
# When one location was backed up several times, the OLDEST backup (the user's original)
# is the one restored; later ones are listed and kept.
restore_old_backups() {
  local root_dir="${1:-$PWD}" apply=0 root_p
  [ "${2:-}" = "--apply" ] && apply=1
  root_p="$(cd "$root_dir" 2>/dev/null && pwd -P)" || { echo "restore-old: no such directory: $root_dir" >&2; return 2; }
  local seen_file restored=0 would=0 skipped=0 ledger line target backup rest
  seen_file="$(mktemp "${TMPDIR:-/tmp}/devkit-restore.XXXXXX")" || return 1
  echo "restore-old: ${root_p} ($([ "$apply" -eq 1 ] && echo apply || echo 'dry-run — add --apply to restore'))"
  while IFS= read -r ledger; do
    [ -n "$ledger" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      rest="${line#* | }"
      [ "$rest" != "$line" ] || continue
      target="${rest%% -> *}"
      backup="${rest#* -> }"
      [ "$target" != "$rest" ] && [ -n "$backup" ] || continue
      case "$target" in "$root_p"/*) ;; *) continue ;; esac
      case "$backup" in "$root_p"/*) ;; *) continue ;; esac
      if grep -qxF -- "$target" "$seen_file"; then
        [ -e "$backup" ] || [ -L "$backup" ] && echo "  kept     ${backup#$root_p/} (a later backup of ${target#$root_p/})"
        continue
      fi
      [ -e "$backup" ] || [ -L "$backup" ] || continue
      printf '%s\n' "$target" >> "$seen_file"
      local free=0
      if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        free=1
      elif link_is_devkit_owned "$target" "${DEVKIT_ROOT:-}"; then
        free=1
      elif is_recorded_devkit_file "$target" || is_unmodified_devkit_copy "$target"; then
        free=1
      fi
      if [ "$free" -ne 1 ]; then
        echo "  SKIP     ${target#$root_p/} — holds content that is not the DevKit's; merge ${backup#$root_p/} by hand"
        skipped=$((skipped + 1))
        continue
      fi
      if [ "$apply" -ne 1 ]; then
        echo "  would    ${backup#$root_p/} -> ${target#$root_p/}"
        would=$((would + 1))
        continue
      fi
      if [ -L "$target" ] || [ -f "$target" ]; then
        rm -f "$target" && forget_devkit_file "$target"
      elif [ -d "$target" ]; then
        rm -rf "$target"
      fi
      # `agent-kit uninstall` removes install dirs left empty (.claude/commands, ...):
      # recreate the parent so the backup can go back.
      if mkdir -p "$(dirname "$target")" && devkit_mv "$backup" "$target"; then
        echo "  restored ${backup#$root_p/} -> ${target#$root_p/}"
        restored=$((restored + 1))
      else
        echo "ERROR: could not move '$backup' back to '$target'" >&2
        rm -f "$seen_file"
        return 1
      fi
    done < "$ledger"
  done < <(find "$root_p" -maxdepth 4 -name .devkit_backups.log -not -path '*/.git/*' 2>/dev/null | LC_ALL=C sort)
  rm -f "$seen_file"
  [ "$apply" -eq 1 ] && devkit_local_prune "$root_p"
  if [ "$apply" -eq 1 ]; then
    echo "restore-old: ${restored} restored, ${skipped} skipped"
  else
    echo "restore-old: ${would} would be restored, ${skipped} skipped"
  fi
  [ "$skipped" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"
  case "$cmd" in
    list|list-old)
      list_old_backups "${2:-$PWD}"
      ;;
    restore|restore-old)
      restore_old_backups "${2:-$PWD}" "${3:-}"
      ;;
    *)
      if [ $# -ge 1 ]; then
        backup_conflict "$1" "${2:-}"
      else
        echo "Usage: $0 <target_path> [devkit_root] | $0 list [project_dir] | $0 restore [project_dir] [--apply]"
        exit 1
      fi
      ;;
  esac
fi
