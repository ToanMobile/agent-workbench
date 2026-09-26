#!/usr/bin/env bash
# Regression test: commit hygiene (GeelyEx2 2026-09-26).
#  - pre-commit blocks a staged file over the size limit and video / archive / package
#    binaries (commit c4769097 swept in bugs/bug.mp4, 14 MB); DEVKIT_ALLOW_LARGE=1 lets it pass
#  - commit-msg: a fix commit that changes source code names the bug it fixes
#    (`Bug: <id>`, checked against guards.json / the checklist when they exist) or says why
#    there is none (`No-Guard: <reason>`); ~12 car bugs were fixed on 25-26/09 with 0 guards
#  - the installer never overwrites a project's own commit-msg hook
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset CLAUDE_PROJECT_DIR TARGET_DIR DEVKIT_PRECOMMIT DEVKIT_ALLOW_LARGE
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_repo() {
  rm -rf "$TMP/repo" && mkdir -p "$TMP/repo/src/main" "$TMP/repo/src/test" && cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/main/A.kt && git add -A && git commit -qm init --no-verify
  bash "$KIT" githooks install >/dev/null 2>&1
}
commits() { git rev-list --count HEAD; }
try_commit() { local n; n="$(commits)"; git commit -q "$@" > "$TMP/out" 2>&1; [ "$(commits)" != "$n" ]; }

# ── pre-commit: large files and media binaries ─────────────────────────────────
new_repo
head -c 6000000 /dev/urandom > big.bin && git add big.bin
try_commit -m "chore: data" && fail "6 MB file committed" || { grep -qi "MB" "$TMP/out" && ok "a 6 MB staged file is blocked" || fail "no size reason: $(cat "$TMP/out")"; }
git rm -q --cached big.bin && rm -f big.bin
head -c 20000 /dev/urandom > clip.mp4 && git add clip.mp4
try_commit -m "chore: clip" && fail "mp4 committed" || ok "a video file is blocked whatever its size"
DEVKIT_ALLOW_LARGE=1 try_commit -m "chore: clip (asked)" && ok "DEVKIT_ALLOW_LARGE=1 lets it pass" || fail "allow-large still blocked: $(cat "$TMP/out")"
echo "fun ok() = 2" > src/main/A.kt && git add -A
try_commit -m "feat: small change" && ok "a normal small change is not affected" || fail "small change blocked: $(cat "$TMP/out")"
# A malformed limit falls back to 5 MB instead of crashing every gate run (review 2026-09-26).
echo "fun ok() = 21" > src/main/A.kt && git add -A
DEVKIT_MAX_STAGED_MB=5MB try_commit -m "feat: another change" && ok "DEVKIT_MAX_STAGED_MB=5MB does not crash the gate" \
  || fail "bad DEVKIT_MAX_STAGED_MB blocked a small change: $(tail -2 "$TMP/out")"
head -c 6000000 /dev/urandom > big.bin && git add big.bin
DEVKIT_MAX_STAGED_MB=5MB try_commit -m "chore: data" && fail "6 MB file committed with a bad limit" \
  || { grep -qi "5 MB" "$TMP/out" && ok "  … and still blocks 6 MB at the default limit" || fail "no size reason: $(tail -2 "$TMP/out")"; }
git rm -q --cached big.bin && rm -f big.bin

# ── commit-msg: fix commits that change source code ─────────────────────────────
HOOKS="$(git rev-parse --path-format=absolute --git-path hooks)"
[ -x "$HOOKS/commit-msg" ] && grep -q 'universal-agent-devkit:githook' "$HOOKS/commit-msg" && ok "install writes a marked commit-msg hook" \
  || fail "commit-msg hook missing"
echo "fun ok() = 3" > src/main/A.kt && git add -A
try_commit -m "fix(player): stop double play" && fail "fix without Bug/No-Guard committed" \
  || { grep -q "Bug:" "$TMP/out" && grep -q "No-Guard:" "$TMP/out" && ok "fix commit of source code without a trailer is blocked, both trailers named" || fail "message: $(cat "$TMP/out")"; }
try_commit -m "fix(player): stop double play" -m "No-Guard: logging only" && ok "No-Guard: <reason> passes" || fail "No-Guard blocked: $(cat "$TMP/out")"
echo "fun ok() = 4" > src/main/A.kt && git add -A
try_commit -m "fix: x" -m "Bug: ANY-1" && ok "Bug: <id> passes when the project has no guards/checklist" || fail "Bug id blocked: $(cat "$TMP/out")"
echo "fun ok() = 5" > src/main/A.kt && git add -A
try_commit -m "feat: new screen" && ok "a feat commit needs no trailer" || fail "feat blocked"
echo "fun t() = 1" > src/test/ATest.kt; echo "# doc" > README.md; git add -A
try_commit -m "fix: test and docs only" && ok "a fix touching only tests/docs needs no trailer" || fail "tests-only fix blocked: $(cat "$TMP/out")"

mkdir -p .agents/local && printf '%s\n' '{"guards":[{"id":"LIC-0926","title":"t"}]}' > .agents/local/guards.json
git add -A && git commit -qm "chore: guards" --no-verify
echo "fun ok() = 6" > src/main/A.kt && git add -A
try_commit -m "fix: y" -m "Bug: NOPE-1" && fail "unknown bug id committed" \
  || { grep -q "NOPE-1" "$TMP/out" && ok "an id that is no guard/bug of the project is blocked" || fail "unknown id message: $(cat "$TMP/out")"; }
try_commit -m "fix: y" -m "Bug: LIC-0926" && ok "a guard id from guards.json passes" || fail "guard id blocked: $(cat "$TMP/out")"

# ── a project's own commit-msg is kept ──────────────────────────────────────────
new_repo
bash "$KIT" githooks uninstall >/dev/null 2>&1
HOOKS="$(git rev-parse --path-format=absolute --git-path hooks)"
printf '#!/bin/sh\n# project hook\nexit 0\n' > "$HOOKS/commit-msg" && chmod +x "$HOOKS/commit-msg"
bash "$KIT" githooks install >/dev/null 2>&1
grep -q "project hook" "$HOOKS/commit-msg" && ok "the project's own commit-msg is not overwritten" || fail "project commit-msg clobbered"
[ -x "$HOOKS/pre-commit" ] && ok "pre-commit still installed next to it" || fail "pre-commit missing"

[ "$FAILS" -eq 0 ] && echo "✅ test_commit_hygiene: all passed" || { echo "❌ test_commit_hygiene: $FAILS failed"; exit 1; }
