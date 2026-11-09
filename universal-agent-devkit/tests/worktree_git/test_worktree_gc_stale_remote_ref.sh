#!/usr/bin/env bash
# `agent-kit worktree gc --merged` must delete a squash-merged local branch whose remote branch GitHub already deleted
# ("delete branch on merge"). Root cause (agent-workbench 2026-11-08): nobody ran `fetch --prune`, so the stale
# refs/remotes/origin/<branch> stayed; _remote_ref() read it as "a remote still has the branch" and gc kept every
# finished branch forever (52 local / 122 remote-tracking refs reported as "unmerged").
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export WORKTREE_GC_MIN_AGE_S=0

mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\ncase " $* " in *" pr list "*) echo "[]" ;; *) exit 1 ;; esac\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"; export PATH="$TMP/bin:$PATH"

O="$TMP/origin.git"; git init -q --bare -b main "$O"
R="$TMP/repo"; mkdir -p "$R" && G "$R" init -q -b main .
echo base > "$R/a.txt"; G "$R" add -A && G "$R" commit -qm init
G "$R" remote add origin "$O" && G "$R" push -q -u origin main 2>/dev/null
mkdir -p "$R/.claude/worktrees"

# a PR branch: published, squash-merged into main, then deleted on origin by GitHub
G "$R" checkout -q -b feat-squashed
echo one > "$R/b.txt"; G "$R" add -A && G "$R" commit -qm one
echo two >> "$R/b.txt"; G "$R" add -A && G "$R" commit -qm two
G "$R" push -q origin feat-squashed 2>/dev/null
G "$R" checkout -q main
G "$R" merge --squash -q feat-squashed 2>/dev/null; G "$R" commit -qm "squash (#1)"; G "$R" push -q origin main 2>/dev/null
git --git-dir="$O" branch -D feat-squashed >/dev/null     # GitHub's delete-branch-on-merge

# a PR branch still alive on origin with work the trunk lacks: must stay
G "$R" checkout -q -b feat-live main
echo live > "$R/c.txt"; G "$R" add -A && G "$R" commit -qm live
G "$R" push -q origin feat-live 2>/dev/null
G "$R" checkout -q main

G "$R" show-ref --verify --quiet refs/remotes/origin/feat-squashed && ok "setup: the stale remote-tracking ref exists" || fail "setup: no stale ref"

cd "$R" || exit 1   # BEFORE gc: it acts on the repository it runs in
python3 "$WT" gc --merged >"$TMP/gc.out" 2>&1 </dev/null || true

G "$R" show-ref --verify --quiet refs/heads/feat-squashed \
  && fail "squash-merged branch kept because of a stale remote-tracking ref: $(tail -5 "$TMP/gc.out")" \
  || ok "squash-merged branch with its remote branch gone on origin is deleted"
G "$R" show-ref --verify --quiet refs/remotes/origin/feat-squashed \
  && fail "stale remote-tracking ref not pruned" || ok "the stale remote-tracking ref is pruned"
G "$R" show-ref --verify --quiet refs/heads/feat-live && ok "a branch still on origin with unmerged work is kept" || fail "live branch deleted"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_gc_stale_remote_ref: all passed" || { echo "❌ test_worktree_gc_stale_remote_ref: $FAILS failed"; exit 1; }
