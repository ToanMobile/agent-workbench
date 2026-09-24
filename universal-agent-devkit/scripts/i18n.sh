#!/usr/bin/env bash
# i18n.sh — EN/VI output language for the DevKit shell installer and adapters.
# Sourced, not executed. Same resolution order as scripts/devkit_i18n.py:
#   --lang  >  $DEVKIT_LANG  >  "lang" in <project>/.agents/active-profile.json  >  vi
# Usage:
#   DEVKIT_LANG="$(devkit_resolve_lang "$CLI_LANG" "$TARGET_DIR")"; export DEVKIT_LANG
#   echo "$(L "Thông điệp tiếng Việt" "English message")"

devkit_lang_normalize() { # <value> → en | vi | "" (unsupported)
  local v
  v="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  v="${v%%[._-]*}"
  case "$v" in en|vi) printf '%s' "$v" ;; *) printf '' ;; esac
}

devkit_resolve_lang() { # <cli-lang> <project-dir>
  local l
  l="$(devkit_lang_normalize "${1:-}")"
  [ -n "$l" ] || l="$(devkit_lang_normalize "${DEVKIT_LANG:-}")"
  if [ -z "$l" ] && [ -n "${2:-}" ]; then
    local pf="$2/.agents/active-profile.json"      # before DevKit 1.3: <project>/.active-profile.json
    [ -f "$pf" ] || pf="$2/.active-profile.json"
    [ -f "$pf" ] && l="$(devkit_lang_normalize "$(sed -n 's/.*"lang"[[:space:]]*:[[:space:]]*"\([A-Za-z_.-]*\)".*/\1/p' "$pf" | head -n 1)")"
  fi
  printf '%s' "${l:-vi}"
}

# L <vietnamese> <english> — print the message for $DEVKIT_LANG (no trailing newline).
L() {
  if [ "${DEVKIT_LANG:-vi}" = "en" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}
