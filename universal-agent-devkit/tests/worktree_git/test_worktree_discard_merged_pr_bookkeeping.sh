#!/usr/bin/env bash
# #862 (#1043): `worktree discard` of a squash-merged PR whose content sits at another place in the file than in the trunk (GeelyEx2:
# INSTINCT-178 inserted elsewhere) was refused as "commits the trunk lacks", and the regenerated bookkeeping (.agents/CHECKLIST.md) counted
# as unsaved work. discard now accepts a PR MERGED into the trunk at exactly the worktree HEAD (the evidence prune-branch uses) and
# ignores regenerated bookkeeping.
#   m1 PR merged at exactly HEAD (gh), content placed elsewhere in trunk: removed, backup ref kept
#   m2 (neg) gh reports a merged PR at ANOTHER head: refused, worktree kept
#   m3 (neg) no gh answer: refused
#   b1 HEAD in trunk + regenerated .agents/CHECKLIST.md dirty: removed
#   b2 (neg) HEAD in trunk + a real edited file next to it: refused
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
git init -q --bare -b main "$TMP/origin.git"
R="$TMP/rd"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
G "$R" config devkit.trunkMode true; G "$R" remote add origin "$TMP/origin.git"
printf 'a\nb\nc\nd\ne\nf\n' > i.md; mkdir -p .agents; echo base > .agents/CHECKLIST.md
G "$R" add -A && G "$R" commit -qm init && G "$R" push -q origin main
mk() { bash "$KIT" worktree add "../$1" >/dev/null 2>&1 || fail "add $1"; }
mk w-pr; mk w-neg; mk w-nogh; mk w-bk; mk w-bk2
for w in w-pr w-neg w-nogh; do
  G "$TMP/$w" checkout -q --detach; printf 'a\nb\nNEW\nc\nd\ne\nf\n' > "$TMP/$w/i.md"; G "$TMP/$w" commit -qam pr
done
# the squash on origin puts NEW elsewhere
git clone -q "$TMP/origin.git" "$TMP/pr" && printf 'a\nb\nc\nd\ne\nNEW\nf\n' > "$TMP/pr/i.md" && G "$TMP/pr" commit -qam "squash (#7)" && G "$TMP/pr" push -q origin main && G "$R" fetch -q origin
G "$R" merge -q --ff-only origin/main
# gh shim: GH_MODE=ok -> merged PR at HEAD $GH_OID ; other -> merged PR at a different oid ; none -> empty list
mkdir -p "$TMP/bin"; cat > "$TMP/bin/gh" <<'SH'
#!/bin/sh
case "${GH_MODE:-none}" in
  ok) echo "[{\"number\":7,\"headRefOid\":\"$GH_OID\",\"baseRefName\":\"main\",\"isCrossRepository\":false}]" ;;
  other) echo '[{"number":8,"headRefOid":"0000000000000000000000000000000000000001","baseRefName":"main","isCrossRepository":false}]' ;;
  *) echo '[]' ;;
esac
SH
chmod +x "$TMP/bin/gh"; export PATH="$TMP/bin:$PATH"

H="$(G "$TMP/w-pr" rev-parse HEAD)"
GH_MODE=ok GH_OID="$H" bash "$KIT" worktree discard ../w-pr >"$TMP/m1" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-pr" ] && [ -n "$(G "$R" for-each-ref 'refs/devkit/discarded/*')" ] && ok "m1: PR merged at exactly HEAD: discarded, backup ref kept" || fail "m1 (rc=$rc): $(cat "$TMP/m1")"
GH_MODE=other bash "$KIT" worktree discard ../w-neg >"$TMP/m2" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-neg" ] && ok "m2: merged PR at another head: refused" || fail "m2 (rc=$rc): $(cat "$TMP/m2")"
GH_MODE=none bash "$KIT" worktree discard ../w-nogh >"$TMP/m3" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-nogh" ] && ok "m3: no merged PR: refused" || fail "m3 (rc=$rc): $(cat "$TMP/m3")"

echo regenerated > "$TMP/w-bk/.agents/CHECKLIST.md"
GH_MODE=none bash "$KIT" worktree discard ../w-bk >"$TMP/b1" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/w-bk" ] && ok "b1: regenerated CHECKLIST.md is not unsaved work" || fail "b1 (rc=$rc): $(cat "$TMP/b1")"
echo regenerated > "$TMP/w-bk2/.agents/CHECKLIST.md"; echo mine > "$TMP/w-bk2/real.txt"
GH_MODE=none bash "$KIT" worktree discard ../w-bk2 >"$TMP/b2" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -e "$TMP/w-bk2" ] && ok "b2: a real edited file still refuses" || fail "b2 (rc=$rc): $(cat "$TMP/b2")"
[ "$FAILS" = 0 ]
