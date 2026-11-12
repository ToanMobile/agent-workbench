#!/usr/bin/env bash
# #862: a git-IGNORED file under .agents/local/ over 32 MB (a red-patch) that main holds with the SAME bytes must not hold a
# worktree back (`_same_bytes` threw on the 32 MB read limit, so the identical copy counted as "only the worktree has it").
#   1 identical 33 MB file in main and worktree: `worktree remove` removes the worktree
#   2 same size, one byte different: still refused, the file stays
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

R="$TMP/m"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
echo a > a.txt; G "$R" add -A && G "$R" commit -qm init
mkdir -p "$R/.agents/local/red-patches"
echo ".agents/local/" >> "$R/.git/info/exclude"
python3 -c "open('$R/.agents/local/red-patches/BIG.patch','wb').write(b'x'*33_000_000)"
bash "$KIT" worktree add ../w1 >/dev/null 2>&1 || fail "add w1"
cp "$R/.agents/local/red-patches/BIG.patch" "$TMP/w1/.agents/local/red-patches/BIG.patch" 2>/dev/null || {
  mkdir -p "$TMP/w1/.agents/local/red-patches"; cp "$R/.agents/local/red-patches/BIG.patch" "$TMP/w1/.agents/local/red-patches/"; }
bash "$KIT" worktree remove ../w1 >"$TMP/o1" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/w1" ] && ok "1: identical >32 MB ignored file: worktree removed" || fail "1 (rc=$rc): $(cat "$TMP/o1")"

bash "$KIT" worktree add ../w2 >/dev/null 2>&1 || fail "add w2"
mkdir -p "$TMP/w2/.agents/local/red-patches"
python3 -c "open('$TMP/w2/.agents/local/red-patches/BIG.patch','wb').write(b'x'*32_999_999+b'y')"
bash "$KIT" worktree remove ../w2 >"$TMP/o2" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -f "$TMP/w2/.agents/local/red-patches/BIG.patch" ] && ok "2: one differing byte: refused, file kept" || fail "2 (rc=$rc): $(cat "$TMP/o2")"

[ "$FAILS" = 0 ]
