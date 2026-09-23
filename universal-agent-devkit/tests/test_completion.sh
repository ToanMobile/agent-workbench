#!/usr/bin/env bash
# Regression test: `agent-kit completion` — the printed script loads in bash, completes
# commands, profiles (read from the DevKit's profiles/), sub-actions and flags; the zsh
# form adds bashcompinit; every command in `agent-kit help` is offered.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# complete <words…> — the candidates for the last word, space-separated and sorted.
complete_words() {
  bash -c '
    eval "$("$0" completion bash)" || exit 3
    COMP_WORDS=("$@"); COMP_CWORD=$(( $# - 1 ))
    _agent_kit
    printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort | tr "\n" " "
  ' "$KIT" "$@"
}

has() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

out="$(complete_words agent-kit "")"
for c in init profile gate githooks worktree clean completion; do has "$c" "$out" || fail "top level misses $c ($out)"; done
has worktree "$out" && ok "top level: commands offered"

# Every command the help lists is completed (help and completion cannot drift apart).
missing=""
for c in $(bash "$KIT" help | sed -n '/^Commands:/,/^Examples:/p' | sed -n 's/^  \([a-z][a-z-]*\).*/\1/p' | sort -u); do
  has "$c" "$out" || missing="$missing $c"
done
[ -z "$missing" ] && ok "every command in 'agent-kit help' is completed" || fail "not completed:$missing"

out="$(complete_words agent-kit profile "")"
has web "$out" && has android "$out" && has universal "$out" && ok "profile: ids read from profiles/" || fail "profiles: $out"
out="$(complete_words agent-kit init . -p "we")"
[ "$out" = "web " ] && ok "init -p completes a profile" || fail "init -p: '$out'"
out="$(complete_words agent-kit worktree "")"
[ "$out" = "add diff list remove " ] && ok "worktree: sub-actions" || fail "worktree: '$out'"
out="$(complete_words agent-kit githooks "st")"
[ "$out" = "status " ] && ok "githooks: sub-actions" || fail "githooks: '$out'"
out="$(complete_words agent-kit clean --a)"
[ "$out" = "--apply " ] && ok "clean: flags" || fail "clean: '$out'"

[ -z "$(bash "$KIT" help 2>&1 >/dev/null)" ] && ok "help prints nothing on stderr (no command run inside its text)" \
  || fail "help wrote to stderr: $(bash "$KIT" help 2>&1 >/dev/null | head -2)"

z="$(bash "$KIT" completion zsh)"
printf '%s\n' "$z" | head -1 | grep -q bashcompinit && printf '%s' "$z" | grep -q "complete -F _agent_kit agent-kit" \
  && ok "zsh form loads bashcompinit first" || fail "zsh form"
bash "$KIT" completion fish >/dev/null 2>&1; [ $? = 2 ] && ok "unknown shell → exit 2" || fail "unknown shell accepted"

if [ "$FAILS" -ne 0 ]; then echo "completion: $FAILS FAILED"; exit 1; fi
echo "completion: all checks passed"
