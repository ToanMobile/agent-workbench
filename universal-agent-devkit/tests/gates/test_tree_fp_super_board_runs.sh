#!/usr/bin/env bash
# bin/tree_fp.py, QA evidence in docs/super-board/runs/ (audit 2026-10-22, agent-workbench#248): worker-qa-223 passed the gate on
# 5ec28e0a, then the QA lane committed its summary under docs/super-board/runs/ (66d4631c). The fingerprint moved, the push gate found
# no receipt for the new tree and ran --full again (~2h45 for QA #223). Those run notes are evidence like reports/ and .agents/evidence,
# not code (the board config's size_exclude agrees): tree_fp.EXCLUDE now names the folder. Only that folder: a sibling whose name merely
# starts with "runs" and the rest of docs/super-board/ (PROJECT.md, pre-flight.md) still count.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TFP="${TFP_SCRIPT:-$DEVKIT_DIR/bin/tree_fp.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
S="docs/super-board"
mkdir -p "$R/src" "$R/$S/runs" "$R/$S/runsX"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
printf 'fun ok() = 1\n' > "$R/src/Core.kt"
printf 'project\n' > "$R/$S/PROJECT.md"
printf 'run one\n' > "$R/$S/runs/2026-10-20.md"
printf 'sibling\n' > "$R/$S/runsX/s.md"
git -C "$R" add -A && git -C "$R" commit -qm init
fp() { python3 -I "$TFP" "$R"; }
cfp() { python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.commit_fingerprint(sys.argv[2]))" "$(dirname "$TFP")" "$R"; }
BASE="$(fp)"; CBASE="$(cfp)"
[ -n "$BASE" ] && [ -n "$CBASE" ] || { bad "no fingerprint"; exit 1; }

# 1. run notes: new untracked, tracked edit -> the working-tree fingerprint does not move
printf 'run two\n' > "$R/$S/runs/2026-10-21.md"
[ "$(fp)" = "$BASE" ] && ok "new untracked run note: fingerprint unchanged" || bad "a new docs/super-board/runs note moved the fingerprint"
printf 'run one, edited\n' > "$R/$S/runs/2026-10-20.md"
[ "$(fp)" = "$BASE" ] && ok "tracked run note edited: fingerprint unchanged" || bad "an edited docs/super-board/runs note moved the fingerprint"
# 2. the QA lane's commit of that evidence: neither fingerprint moves (the receipt of the gated tree still matches)
git -C "$R" add -A && git -C "$R" commit -qm "qa evidence"
[ "$(fp)" = "$BASE" ] && ok "run notes committed: working-tree fingerprint unchanged" || bad "committing run notes moved the fingerprint"
[ "$(cfp)" = "$CBASE" ] && ok "run notes committed: commit fingerprint unchanged" || bad "committing run notes moved commit_fingerprint"

# 3. everything else still counts
printf 'project, changed\n' > "$R/$S/PROJECT.md"
[ "$(fp)" != "$BASE" ] && ok "docs/super-board/PROJECT.md changed: fingerprint moves" || bad "PROJECT.md change did not move the fingerprint (too wide)"
git -C "$R" restore -- "$S/PROJECT.md"
printf 'sibling, changed\n' > "$R/$S/runsX/s.md"
[ "$(fp)" != "$BASE" ] && ok "folder named runsX changed: fingerprint moves (prefix is a whole path part)" || bad "runsX change did not move the fingerprint"
git -C "$R" restore -- "$S/runsX/s.md"
printf 'fun ok() = 22\n' > "$R/src/Core.kt"
[ "$(fp)" != "$BASE" ] && ok "source file changed: fingerprint moves" || bad "a source change did not move the fingerprint"
git -C "$R" commit -qam "code change"
[ "$(cfp)" != "$CBASE" ] && ok "source committed: commit fingerprint moves" || bad "a committed source change did not move commit_fingerprint"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
