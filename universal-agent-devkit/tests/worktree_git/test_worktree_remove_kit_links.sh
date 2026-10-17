#!/usr/bin/env bash
# Regression: `agent-kit worktree remove` (scripts/git/worktree.py) refused a worktree whose ONLY uncommitted paths were symlinks
# the DevKit installer/heal made into the main checkout's kit folder (.agents/hooks/<hook> -> <main>/universal-agent-devkit/hooks/<hook>).
# Those links are install state, never work, and main cannot "hold the same bytes" at that path (main has no .agents/hooks), so
# the worktree stayed behind and the user had to delete it by hand (agent-workbench, 2026-10-17: push-release-branch, 7 links).
#   - only kit links uncommitted: removal allowed
#   - kit links + a real uncommitted file: still refused, and the refusal names the real file, not the links
#   - a link to somewhere that is NOT the main checkout's kit folder is not setup: still refused
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

R="$TMP/rk"; mkdir -p "$R/universal-agent-devkit/hooks" && G "$R" init -q -b main . && cd "$R" || exit 1
printf '#!/bin/sh\n' > "$R/universal-agent-devkit/hooks/gate.sh"; printf 'x\n' > "$R/universal-agent-devkit/hooks/norm.py"
printf '1\n' > "$R/f.txt"
G "$R" add -A && G "$R" commit -qm init
wt() { bash "$KIT" worktree add "../rk-$1" >/dev/null 2>&1 || fail "add rk-$1"; }
rm_wt() { bash "$KIT" worktree remove "../rk-$1" >"$TMP/rk-$1.out" 2>&1; return $?; }
kit_links() {   # kit_links <worktree dir>: what heal/init leave behind, absolute links into the main checkout's kit folder
  mkdir -p "$1/.agents/hooks"
  ln -s "$R/universal-agent-devkit/hooks/gate.sh" "$1/.agents/hooks/gate.sh"
  ln -s "$R/universal-agent-devkit/hooks/norm.py" "$1/.agents/hooks/norm.py"
}

wt a; kit_links "$TMP/rk-a"
rm_wt a; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/rk-a" ] && ok "remove: only DevKit links into main's kit folder uncommitted -> allowed" \
  || { fail "kit links only (rc=$rc)"; cat "$TMP/rk-a.out"; }

wt b; kit_links "$TMP/rk-b"; echo "work" > "$TMP/rk-b/real.txt"
rm_wt b; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rk-b" ] && grep -q "real.txt" "$TMP/rk-b.out" && ! grep -q ".agents/hooks" "$TMP/rk-b.out" \
  && ok "remove: kit links + a real uncommitted file -> refused, the message names the file and not the links" \
  || { fail "kit links + real file (rc=$rc)"; cat "$TMP/rk-b.out"; }

wt c; mkdir -p "$TMP/rk-c/.agents/hooks"; ln -s "/etc/hosts" "$TMP/rk-c/.agents/hooks/other.sh"
rm_wt c; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rk-c" ] && grep -q "other.sh" "$TMP/rk-c.out" \
  && ok "remove: a link that does not point into main's kit folder is not setup -> refused" \
  || { fail "foreign link (rc=$rc)"; cat "$TMP/rk-c.out"; }

# A TRACKED file the user replaced by a link into the kit is a type change, not install state: never silently dropped (review 17/10).
wt d; rm -f "$TMP/rk-d/f.txt"; ln -s "$R/universal-agent-devkit/hooks/gate.sh" "$TMP/rk-d/f.txt"
rm_wt d; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rk-d" ] && grep -q "f.txt" "$TMP/rk-d.out" \
  && ok "remove: a tracked file replaced by a kit link is still work -> refused" \
  || { fail "tracked file replaced by a kit link (rc=$rc)"; cat "$TMP/rk-d.out"; }

# Same, when the deletion of the tracked file was STAGED first (`git rm`, then a link at the same path): the path is no longer in the
# index but HEAD still holds it, so it is a type change, never setup (OCR 17/10).
wt i; G "$TMP/rk-i" rm -q f.txt; ln -s "$R/universal-agent-devkit/hooks/gate.sh" "$TMP/rk-i/f.txt"
rm_wt i; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rk-i" ] && grep -q "f.txt" "$TMP/rk-i.out" \
  && ok "remove: a tracked file deleted in the index and replaced by a kit link is still work -> refused" \
  || { fail "git rm + kit link at the same path (rc=$rc)"; cat "$TMP/rk-i.out"; }

# Same rule everywhere (changes_since): `diff` carries no machine-specific link into main, `finish` (the Stop hook's automerge)
# neither stops on "a new symlink" nor leaves the worktree behind.
wt e; kit_links "$TMP/rk-e"
bash "$KIT" worktree diff "../rk-e" >"$TMP/rk-e.diff" 2>&1
! grep -q "120000" "$TMP/rk-e.diff" && ! grep -q "universal-agent-devkit/hooks" "$TMP/rk-e.diff" \
  && ok "diff: kit links are left out of the patch" || { fail "diff carries a kit link"; cat "$TMP/rk-e.diff"; }
bash "$KIT" worktree finish "../rk-e" >"$TMP/rk-e.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/rk-e" ] && ok "finish: only kit links uncommitted -> not refused as 'new symlink', worktree merged and removed" \
  || { fail "finish with kit links only (rc=$rc)"; cat "$TMP/rk-e.out"; }

# "Cannot say = refuse" (review 17/10): when `git ls-files` itself fails or times out (rc 124 / 128), a path must NOT read as untracked
# setup, or a tracked file replaced by a kit link would be hidden and the worktree removed. Only rc 1 (not in the index) is "untracked".
wt h; kit_links "$TMP/rk-h"
UNIT="$(KIT_ROOT="$DEVKIT_DIR" WT="$TMP/rk-h" MAIN="$R" python3 - <<'PY'
import importlib.util, os, types
spec = importlib.util.spec_from_file_location("wtmod", os.path.join(os.environ["KIT_ROOT"], "scripts/git/worktree.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
wt, main, rel = os.environ["WT"], os.environ["MAIN"], ".agents/hooks/gate.sh"
real = m.git
out = {}
for rc in (1, 0, 124, 128):
    # ls-files answers with the rc of the case; ls-tree (HEAD holds nothing at the path) answers rc 0 with no output
    m.git = lambda *a, _rc=rc, **k: types.SimpleNamespace(returncode=(_rc if "ls-files" in a else 0), stdout="", stderr="")
    out[rc] = m._kit_link(wt, main, rel)
m.git = real
print(" ".join(f"{rc}={out[rc]}" for rc in sorted(out)))
PY
)"
[ "$UNIT" = "0=False 1=True 124=False 128=False" ] \
  && ok "_kit_link: only 'not in the index' (rc 1) reads as setup; a failing or timed-out git is treated as work" \
  || fail "_kit_link fail-open on a git error (got: $UNIT)"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_remove_kit_links: all passed" || { echo "❌ test_worktree_remove_kit_links: $FAILS failed"; exit 1; }
