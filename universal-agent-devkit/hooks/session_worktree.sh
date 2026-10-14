#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# session_worktree.sh <record | worktree-create | worktree-remove> — the Claude Code hooks of trunk mode (W1 R1/R2 v6,
# docs/workflow-improvements.md I.0). Logic: hooks/session_worktree.py and scripts/git/worktree.py of the kit this file really
# lives in (the .claude/hooks/ entry is a symlink).
#   record           PostToolUse on EnterWorktree|ExitWorktree (every repo): remembers the worktree the session entered, so the gates
#                    check that worktree and not the main checkout (CLAUDE_PROJECT_DIR stays main after EnterWorktree). Never blocks.
#   worktree-create  WorktreeCreate (wired by `agent-kit worktree trunk on`): `worktree.py hook-create` prints the path on the last
#                    stdout line. Configuring this hook REPLACES Claude's own `git worktree add`, so with no python3 or no kit here it
#                    still makes a plain detached worktree at <main>/.claude/worktrees/<name> and prints it: an EnterWorktree or an
#                    isolated subagent must never fail because of the DevKit.
#   worktree-remove  WorktreeRemove (same): `worktree.py hook-remove` removes only what loses no work; cannot judge = exit 1, kept.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
sub="${1:-record}"
SELF="$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null)" || SELF=""
HERE="${SELF:+$(dirname "${SELF}")}"
WT_PY="${HERE:+${HERE}/../scripts/git/worktree.py}"
case "${sub}" in
  record)
    [ -n "${HERE}" ] && [ -f "${HERE}/session_worktree.py" ] && exec python3 -I "${HERE}/session_worktree.py" record
    exit 0 ;;
  worktree-create)
    [ -n "${WT_PY}" ] && [ -f "${WT_PY}" ] && exec python3 -I "${WT_PY}" hook-create
    INPUT="$(cat)"
    RX_NAME='"name"[[:space:]]*:[[:space:]]*"([A-Za-z0-9][A-Za-z0-9._/-]*)"'
    [[ ${INPUT} =~ ${RX_NAME} ]] || { echo "✖ worktree hook: no usable name in the payload" >&2; exit 2; }
    name="${BASH_REMATCH[1]}"
    # an EnterWorktree name is "/"-separated segments (fix/login): one folder, the "/" a "-" (as worktree.py hook-create)
    case "${name}" in *..*|*//*|*/|*/[!A-Za-z0-9]*) echo "✖ worktree hook: not a worktree name: ${name}" >&2; exit 2 ;; esac
    name="${name//\//-}"
    # the repo is where Claude runs the hook (the session's directory): with no python3 there is no JSON decoder for an escaped cwd
    # (no --path-format=absolute: git 2.31; the path is relative to this directory or absolute, and the cd below runs here too)
    common="$(git rev-parse --git-common-dir 2>/dev/null)" || { echo "✖ worktree hook: not in a git repo: ${PWD}" >&2; exit 1; }
    main="$(cd -P "${common}/.." 2>/dev/null && pwd -P)" || exit 1
    wt="${main}/.claude/worktrees/${name}"
    git -C "${main}" worktree add --detach "${wt}" HEAD >&2 || exit 1
    echo "⚠ worktree hook: no python3 / DevKit here — a plain worktree, no DevKit set-up" >&2
    printf '%s\n' "${wt}"
    exit 0 ;;
  worktree-remove)
    [ -n "${WT_PY}" ] && [ -f "${WT_PY}" ] && exec python3 -I "${WT_PY}" hook-remove
    echo "✖ worktree hook: cannot judge the removal here (no python3 / DevKit): the worktree is kept" >&2
    exit 1 ;;
esac
echo "usage: session_worktree.sh record | worktree-create | worktree-remove (got: ${sub:-nothing})" >&2
exit 1   # a mis-wired hook shows up instead of passing in silence (non-blocking for PostToolUse)
