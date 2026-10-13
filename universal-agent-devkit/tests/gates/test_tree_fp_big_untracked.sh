#!/usr/bin/env bash
# bin/tree_fp.py, big untracked files (2026-10-13, /devkit-audit plan item 5, gate overhead): GeelyEx2 keeps 319 MB of untracked,
# not ignored recordings in artifacts/videos (121 files), and tree_fingerprint's `git add -A` into a throw-away index hashed all of
# them on every call: 6.5-7.3 s per fingerprint (measured), taken twice per --full run. An untracked file of 8 MiB or more
# (the bound devkit_harness.tree_fingerprint already uses) now enters the fingerprint by path, size and mtime_ns, without reading
# its content; everything else is hashed by content as before. A content change of such a file that keeps its size and its
# mtime is not seen (accepted ceiling: a writer always moves mtime). Switch: TREE_FP_BIG_MB=0 hashes every file's content.
# The deterministic witness of "not read": a big untracked file the user cannot read. The old code fails (git add: permission
# denied -> empty fingerprint, the gate prints the error); the new one never opens it.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TFP="${TFP_SCRIPT:-$DEVKIT_DIR/bin/tree_fp.py}"
TMP="$(mktemp -d)"
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R/src" "$R/media"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
printf 'fun ok() = 1\n' > "$R/src/Core.kt"
git -C "$R" add -A && git -C "$R" commit -qm init
fp() { python3 -I "$TFP" "$R"; }
python3 -c 'import os,sys; open(sys.argv[1],"wb").write(os.urandom(9 << 20))' "$R/media/big.mp4"    # 9 MiB, untracked
python3 -c 'import os,sys; open(sys.argv[1],"wb").write(os.urandom(64 << 10))' "$R/media/small.bin"  # 64 KiB, untracked
BASE="$(fp)"
[ -n "$BASE" ] && ok "fingerprint with a 9 MiB untracked file" || { bad "no fingerprint at all"; exit 1; }

# 1. the big file's content is not read
chmod 000 "$R/media/big.mp4"
NOREAD="$(fp)"
chmod 644 "$R/media/big.mp4"
[ -n "$NOREAD" ] && ok "a big untracked file nobody can read: fingerprint still taken (content not read)" \
  || bad "a big untracked file nobody can read: empty fingerprint (its content was read)"
[ "$NOREAD" = "$BASE" ] && ok "... and the same value (path, size, mtime unchanged)" || bad "unreadable big file moved the fingerprint"

# 2. what still moves the fingerprint
python3 -c 'import sys; open(sys.argv[1],"ab").write(b"x")' "$R/media/big.mp4"
A="$(fp)"; [ -n "$A" ] && [ "$A" != "$BASE" ] && ok "big file grew: fingerprint moves" || bad "big file grew, fingerprint did not move"
touch -t 202001010000 "$R/media/big.mp4"
B="$(fp)"; [ "$B" != "$A" ] && ok "big file mtime changed: fingerprint moves" || bad "big file mtime change not seen"
mv "$R/media/big.mp4" "$R/media/big2.mp4"
C="$(fp)"; [ "$C" != "$B" ] && ok "big file renamed: fingerprint moves" || bad "big file rename not seen"
rm -f "$R/media/big2.mp4"
D="$(fp)"; [ "$D" != "$C" ] && ok "big file deleted: fingerprint moves" || bad "big file deletion not seen"
python3 -c 'import sys; d=bytearray(open(sys.argv[1],"rb").read()); d[0]^=1; open(sys.argv[1],"wb").write(bytes(d))' "$R/media/small.bin"
touch -r "$R/src/Core.kt" "$R/media/small.bin"
E="$(fp)"; [ "$E" != "$D" ] && ok "small untracked file: a same-size edit is seen by content" || bad "small file content edit not seen"
printf 'fun ok() = 2\n' > "$R/src/Core.kt"
F="$(fp)"; [ "$F" != "$E" ] && ok "tracked source edit: fingerprint moves" || bad "tracked edit not seen"

# 3. the switch reads every file again
python3 -c 'import os,sys; open(sys.argv[1],"wb").write(os.urandom(9 << 20))' "$R/media/big.mp4"
chmod 000 "$R/media/big.mp4"
OFF="$(TREE_FP_BIG_MB=0 python3 -I "$TFP" "$R")"
chmod 644 "$R/media/big.mp4"
[ -z "$OFF" ] && ok "TREE_FP_BIG_MB=0: the big file is read again (unreadable -> no fingerprint, as before)" || bad "TREE_FP_BIG_MB=0 ignored"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
