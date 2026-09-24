# Tab completion for agent-kit (bash; zsh through bashcompinit).
# Load it with one line in ~/.bashrc or ~/.zshrc:
#   eval "$(agent-kit completion bash)"      # or: eval "$(agent-kit completion zsh)"
# or source this file directly from a DevKit checkout.

if [ -z "${_AGENT_KIT_ROOT:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
  _AGENT_KIT_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
fi

_agent_kit_profiles() {
  local p
  for p in "${_AGENT_KIT_ROOT:-}"/profiles/*/profile.json; do
    [ -f "${p}" ] && basename "$(dirname "${p}")"
  done
}

_agent_kit() {
  local cur prev cmd words
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  cmd="${COMP_WORDS[1]:-}"
  COMPREPLY=()

  if [ "${COMP_CWORD}" -eq 1 ]; then
    words="init install-global profile health gate githooks bugs learn clean matrix worktree
           index-memory test sync list commands list-old restore-old uninstall completion help"
    COMPREPLY=( $(compgen -W "${words}" -- "${cur}") )
    return 0
  fi

  case "${cmd}" in
    profile)
      COMPREPLY=( $(compgen -W "$(_agent_kit_profiles) --help" -- "${cur}") ) ;;
    githooks|git-hooks)
      [ "${COMP_CWORD}" -eq 2 ] && COMPREPLY=( $(compgen -W "install uninstall status" -- "${cur}") ) \
        || COMPREPLY=( $(compgen -d -- "${cur}") ) ;;
    worktree|wt)
      if [ "${COMP_CWORD}" -eq 2 ]; then
        COMPREPLY=( $(compgen -W "add diff remove list" -- "${cur}") )
      elif [ "${COMP_WORDS[2]}" = "add" ] && [[ "${cur}" == -* ]]; then
        COMPREPLY=( $(compgen -W "--base= --profile= --no-init" -- "${cur}") )
      else
        COMPREPLY=( $(compgen -d -- "${cur}") )
      fi ;;
    init|setup)
      case "${prev}" in
        -p|--profile) COMPREPLY=( $(compgen -W "$(_agent_kit_profiles)" -- "${cur}") ); return 0 ;;
        -a|--agents) COMPREPLY=( $(compgen -W "all claude codex gemini cursor" -- "${cur}") ); return 0 ;;
        -m|--mode) COMPREPLY=( $(compgen -W "symlink copy" -- "${cur}") ); return 0 ;;
      esac
      [[ "${cur}" == -* ]] && COMPREPLY=( $(compgen -W "-y -p -a -m -s --lang=en --lang=vi --no-githooks --help" -- "${cur}") ) \
        || COMPREPLY=( $(compgen -d -- "${cur}") ) ;;
    gate|postfix|postfix-gate|audit-gate)
      COMPREPLY=( $(compgen -W "--run-tests --staged --json --dry-run --allow-no-tests --timeout --matrix --diff --record-lesson" -- "${cur}") ) ;;
    clean)
      [[ "${cur}" == -* ]] && COMPREPLY=( $(compgen -W "--days= --apply --old-installs" -- "${cur}") ) \
        || COMPREPLY=( $(compgen -d -- "${cur}") ) ;;
    learn)
      COMPREPLY=( $(compgen -W "--cause --rule --symptom --check --file --force --dry-run --from-json" -- "${cur}") ) ;;
    matrix)
      COMPREPLY=( $(compgen -W "--write" -- "${cur}") ) ;;
    restore-old|restore|uninstall|remove)
      [[ "${cur}" == -* ]] && COMPREPLY=( $(compgen -W "--apply" -- "${cur}") ) \
        || COMPREPLY=( $(compgen -d -- "${cur}") ) ;;
    completion)
      COMPREPLY=( $(compgen -W "bash zsh" -- "${cur}") ) ;;
    bugs)
      [ "${COMP_CWORD}" -eq 2 ] && COMPREPLY=( $(compgen -W "import show" -- "${cur}") ) \
        || COMPREPLY=( $(compgen -f -- "${cur}") ) ;;
    *)
      COMPREPLY=( $(compgen -f -- "${cur}") ) ;;
  esac
  return 0
}
complete -F _agent_kit agent-kit
