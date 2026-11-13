#!/usr/bin/env bash
# #688: in trunk mode bin/session_lock.py refused writes into main's git dir (`<main>/.git/postfix-gate/archive/...`, gate state) as
# "main is merge-only": `git check-ignore` exits 1 for paths under .git/, so they read as main content. The git dir / common dir is no
# merge content for gate state: writes under <git dir>/postfix-gate/ pass; git's own state and the guards' switches there (config with
# devkit.trunkMode, the shared-checkout flag, refs, hooks, info/exclude) and tracked (or new, not ignored) files of main stay blocked.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
M="$TMP/main"; W="$M/.claude/worktrees/s1"
mkdir -p "$M/src" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
printf '/.claude/worktrees/\n' > "$M/.gitignore"
echo a > "$M/src/a.py" && echo r > "$M/README.md" && git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" worktree add -q --detach "$W" HEAD
mkdir -p "$M/.git/postfix-gate/archive"
git -C "$M" config devkit.trunkMode true

python3 - "$DEVKIT_DIR" "$M" "$W" <<'PY'
import sys
dk, m, w = sys.argv[1:4]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
main, sw = sl.trunk_main(m)
assert main and sw, "trunk mode not seen"
E = lambda p: ("Edit", {"file_path": p}, "")
B = lambda c: ("Bash", {"command": c}, c)
cases = [   # (want, label, cwd, (tool, input, command))
    (False, "cp x into <main>/.git/postfix-gate/archive/", m, B(f"cp /tmp/x {m}/.git/postfix-gate/archive/runs.jsonl")),
    (False, "redirect into <main>/.git/postfix-gate/archive/ (relative, from main)", m, B("echo x > .git/postfix-gate/archive/y")),
    (False, "cp into main's git dir from a worktree", w, B(f"cp /tmp/x {m}/.git/postfix-gate/archive/y")),
    (False, "Write a new file in <main>/.git/postfix-gate/", m, E(f"{m}/.git/postfix-gate/state.json")),
    # review PR #1161: git's own state and the guards' switches in the git dir stay merge-only (fail closed): only gate state passes
    (True, "Write <main>/.git/config (devkit.trunkMode lives there)", m, E(f"{m}/.git/config")),
    (True, "touch the lock off-switch in <main>/.git/", m, B(f"touch {m}/.git/{sl.ALLOW_FLAG}")),
    (True, "redirect into <main>/.git/refs/heads/main (moves main)", m, B(f"echo 0 > {m}/.git/refs/heads/main")),
    (True, "Write <main>/.git/hooks/pre-commit", m, E(f"{m}/.git/hooks/pre-commit")),
    (True, "Write <main>/.git/info/exclude (hides main content)", m, E(f"{m}/.git/info/exclude")),
    (True, "Write under <main>/.git/worktrees/ (another checkout's HEAD)", m, E(f"{m}/.git/worktrees/s1/HEAD")),
    (True, "Edit a tracked file of main (still blocked)", m, E(f"{m}/src/a.py")),
    (True, "cp onto a tracked file of main (still blocked)", m, B(f"cp /tmp/x {m}/README.md")),
    (True, "Write a new, not ignored file in main (still blocked)", m, E(f"{m}/.gitx/new.md")),
]
fails = 0
for want, label, cwd, (tool, ti, cmd) in cases:
    got = bool(sl.trunk_write(tool, ti, cmd, cwd, main, sw))
    print(("✔ " if got == want else "✖ ") + f"{label}: write-into-main={got} (want {want})")
    fails += got != want
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" -eq 0 ] && echo "PASS test_session_lock_gitdir_write" || echo "FAIL test_session_lock_gitdir_write"
exit "$rc"
