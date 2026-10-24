#!/usr/bin/env bash
# Regression (issue #365): `agent-kit worktree remove` must not be held by an uncommitted diff that lives ONLY in
# tests/lib/test_durations.txt (a start-order hint, no work). Any other uncommitted change still holds the removal.
# Everything runs in a scratch repo (never the real one). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

for K in sub root; do
  R="$TMP/$K"; mkdir -p "$R" && G "$R" init -q -b main . || exit 1
  if [ "$K" = sub ]; then D="universal-agent-devkit/tests/lib/test_durations.txt"; else D="tests/lib/test_durations.txt"; fi
  mkdir -p "$R/$(dirname "$D")"; printf '3 tests/gates/test_old.sh\n' > "$R/$D"; echo a > "$R/a.txt"
  G "$R" add -A && G "$R" commit -qm init
  # 1) only the durations file differs: the removal goes through
  ( cd "$R" && bash "$KIT" worktree add "../$K-w1" >/dev/null 2>&1 ) || fail "[$K] add w1"
  printf '9 tests/gates/test_new.sh\n' >> "$TMP/$K-w1/$D"
  ( cd "$R" && bash "$KIT" worktree remove "../$K-w1" >"$TMP/$K-w1.out" 2>&1 ); rc=$?
  [ "$rc" = 0 ] && [ ! -d "$TMP/$K-w1" ] && ok "[$K] diff only in test_durations.txt: remove goes through" || { fail "[$K] durations-only diff held the removal (rc=$rc)"; cat "$TMP/$K-w1.out"; }
  # 2) the durations file AND real work: still refused, and the work is named
  ( cd "$R" && bash "$KIT" worktree add "../$K-w2" >/dev/null 2>&1 ) || fail "[$K] add w2"
  printf '9 tests/gates/test_new.sh\n' >> "$TMP/$K-w2/$D"; echo real >> "$TMP/$K-w2/a.txt"
  ( cd "$R" && bash "$KIT" worktree remove "../$K-w2" >"$TMP/$K-w2.out" 2>&1 ); rc=$?
  [ "$rc" = 1 ] && [ -d "$TMP/$K-w2" ] && grep -q "a.txt" "$TMP/$K-w2.out" && ! grep -q "test_durations" "$TMP/$K-w2.out" \
    && ok "[$K] real work next to the durations file: still refused, only the work is listed" || { fail "[$K] real work not held (rc=$rc)"; cat "$TMP/$K-w2.out"; }
  # 3) finish uses the same rule as remove (#365): the durations file alone is no work (finish used to refuse it as uncommitted work)
  ( cd "$R" && bash "$KIT" worktree add "../$K-w3" >/dev/null 2>&1 ) || fail "[$K] add w3"
  printf '9 tests/gates/test_new.sh\n' >> "$TMP/$K-w3/$D"
  ( cd "$R" && bash "$KIT" worktree finish "../$K-w3" >"$TMP/$K-w3.out" 2>&1 ); rc=$?
  [ "$rc" = 0 ] && [ ! -d "$TMP/$K-w3" ] && ok "[$K] finish with a diff only in test_durations.txt: goes through" || { fail "[$K] finish refused a durations-only diff (rc=$rc)"; cat "$TMP/$K-w3.out"; }
  # 4) only the kit's own file is the hint: the same file name under another folder is real work and still holds the removal
  mkdir -p "$R/other/tests/lib"; printf '1 x\n' > "$R/other/tests/lib/test_durations.txt"; G "$R" add -A && G "$R" commit -qm other
  ( cd "$R" && bash "$KIT" worktree add "../$K-w4" >/dev/null 2>&1 ) || fail "[$K] add w4"
  printf '2 y\n' >> "$TMP/$K-w4/other/tests/lib/test_durations.txt"
  ( cd "$R" && bash "$KIT" worktree remove "../$K-w4" >"$TMP/$K-w4.out" 2>&1 ); rc=$?
  [ "$rc" = 1 ] && [ -d "$TMP/$K-w4" ] && grep -q "other/tests/lib/test_durations.txt" "$TMP/$K-w4.out" \
    && ok "[$K] a test_durations.txt outside the kit's tests/lib is real work: still refused" || { fail "[$K] foreign test_durations.txt not held (rc=$rc)"; cat "$TMP/$K-w4.out"; }
done
[ "$FAILS" = 0 ] && { echo "remove_durations: all passed"; exit 0; } || { echo "remove_durations: $FAILS FAILED"; exit 1; }
