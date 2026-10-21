#!/usr/bin/env bash
# Regression test (issue #29): profiles/game scripts survive bad CLI input.
#   a. unity-bot-marathon.sh: --help prints usage and exits 0; a non-numeric level spec is
#      rejected before any arithmetic (no unbound variable, no command substitution).
#   b. unity-batch.sh: a value-taking flag with no value exits 2 instead of looping forever.
#   c. validate-assets.sh: a rename from Assets/ to outside Assets/ keeps the NUL stream in step.
# No Unity needed: every case stops before an Editor would start.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MARATHON="$DEVKIT_DIR/profiles/game/scripts/unity-bot-marathon.sh"
BATCH="$DEVKIT_DIR/profiles/game/scripts/unity-batch.sh"
VALIDATE="$DEVKIT_DIR/profiles/game/hooks/validate-assets.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# run_capped <seconds> <outfile> cmd… — kill a hang so the test itself cannot hang; rc 124 = killed
run_capped() {
  local secs="$1" out="$2" pid watcher rc; shift 2
  "$@" >"$out" 2>&1 </dev/null & pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) & watcher=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  [ "$rc" -eq 137 ] && rc=124
  return "$rc"
}

PROJ="$TMP/proj"; mkdir -p "$PROJ"

# ---- a. marathon ----
run_capped 10 "$TMP/a1" env BOT_METHOD=X.Y.Z UNITY_PROJECT="$PROJ" bash "$MARATHON" --help; rc=$?
if [ "$rc" -eq 0 ] && grep -qi "usage" "$TMP/a1" && ! grep -qi "unbound" "$TMP/a1"; then ok "marathon --help prints usage, exit 0"; else fail "marathon --help rc=$rc: $(head -c 200 "$TMP/a1")"; fi

run_capped 10 "$TMP/a2" env BOT_METHOD=X.Y.Z UNITY_PROJECT="$PROJ" bash "$MARATHON" 'a[$(touch '"$TMP"'/pwned)]-1'; rc=$?
if [ "$rc" -eq 2 ] && [ ! -e "$TMP/pwned" ]; then ok "marathon rejects an injected level spec, runs nothing"; else fail "marathon injection rc=$rc pwned=$([ -e "$TMP/pwned" ] && echo yes || echo no)"; fi

# ---- b. batch ----
run_capped 10 "$TMP/b1" env UNITY_PROJECT="$PROJ" bash "$BATCH" editmode --filter; rc=$?
if [ "$rc" -eq 2 ] && grep -q "filter" "$TMP/b1"; then ok "batch --filter without a value exits 2"; else fail "batch --filter rc=$rc (124 = infinite loop): $(head -c 200 "$TMP/b1")"; fi

# ---- c. validate-assets ----
REPO="$TMP/repo"; mkdir -p "$REPO/Assets" "$REPO/ProjectSettings" "$REPO/Art"
git -C "$REPO" init -q && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
echo a > "$REPO/Assets/hero.txt"; echo b > "$REPO/Assets/ok.png"; : > "$REPO/Assets/ok.png.meta"; : > "$REPO/Assets/hero.txt.meta"
echo v > "$REPO/ProjectSettings/ProjectVersion.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init
git -C "$REPO" mv Assets/hero.txt Art/hero.txt
git -C "$REPO" mv Assets/hero.txt.meta Art/hero.txt.meta
echo x > "$REPO/Assets/new.md"   # rogue file listed AFTER the renames: a desynced stream misses it
git -C "$REPO" add -A
run_capped 10 "$TMP/c1" env CLAUDE_PROJECT_DIR="$REPO" bash "$VALIDATE"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "new.md" "$TMP/c1"; then ok "rename out of Assets/ keeps the scan in step (rogue file after it still caught)"; else fail "validate-assets rc=$rc: $(head -c 300 "$TMP/c1")"; fi

exit "$FAILS"
