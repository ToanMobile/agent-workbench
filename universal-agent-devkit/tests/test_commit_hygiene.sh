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
try_commit -m "fix: stop the double play" -m "Bug: ANY-1" && ok "Bug: <id> passes when the project has no guards/checklist" || fail "Bug id blocked: $(cat "$TMP/out")"
echo "fun ok() = 39" > src/main/A.kt && git add -A
try_commit -m "fix: stop the crash on launch" -m "Bug: app crashes on start" && fail "prose after Bug: accepted as an id" \
  || { grep -q "id" "$TMP/out" && ok "prose after Bug: (no id) is blocked even without guards/checklist" || fail "no id reason: $(cat "$TMP/out")"; }
git reset -q
# A vague subject on a code change says nothing (Goods 2026-09-25: "fix." and "no message"
# committed the half-done R5/R6 work that turned 33 checklist rows red).
n=40
for subj in "fix." "no message" "update" "wip" "fix: x"; do
  n=$((n + 1)); echo "fun ok() = $n" > src/main/A.kt && git add -A
  try_commit -m "$subj" && fail "vague subject '$subj' on a code change committed" \
    || { grep -q "<type>" "$TMP/out" && ok "vague subject '$subj' on a code change is blocked, format named" || fail "no format hint for '$subj': $(cat "$TMP/out")"; }
  git reset -q
done
n=$((n + 1)); echo "fun ok() = $n" > src/main/A.kt && git add -A
try_commit -m "Fix crash on open" && fail "a plain 'Fix …' subject passed without Bug:/No-Guard:" \
  || { grep -q "Bug:" "$TMP/out" && ok "a plain 'Fix crash on open' is a fix: needs Bug:/No-Guard:" || fail "no trailer hint: $(cat "$TMP/out")"; }
git reset -q
# Real subjects that must pass (review 2026-09-26): GeelyEx2's release script, its own types,
# git's own defaults, a BOM from an editor.
for subj in "Release artifacts (dev): 1.0.67 schema and tables" "data(voice): tune the number grammar" \
            "tools(vhal): read the door lock property" "Initial commit" "Squashed commit of the following:" \
            "$(printf '\xef\xbb\xbf')feat: add the export button"; do
  n=$((n + 1)); echo "fun ok() = $n" > src/main/A.kt && git add -A
  try_commit -m "$subj" && ok "real subject '${subj:0:40}' passes" || fail "real subject '${subj:0:40}' blocked: $(tail -1 "$TMP/out")"
done
n=$((n + 1)); echo "fun ok() = $n" > src/main/A.kt && git add -A
try_commit -m "Merge branch 'feature'" && ok "a merge commit subject passes" || fail "merge subject blocked: $(cat "$TMP/out")"
n=$((n + 1)); echo "fun ok() = $n" > src/main/A.kt && git add -A
try_commit -m "refactor(player): split the queue from the view" && ok "a conventional subject with a real description passes" || fail "conventional subject blocked: $(cat "$TMP/out")"
echo "# notes $n" > NOTES.md && git add -A
try_commit -m "update" && ok "a vague subject with no code change passes (docs only)" || fail "docs-only vague subject blocked: $(cat "$TMP/out")"
echo "fun ok() = 5" > src/main/A.kt && git add -A
try_commit -m "feat: new screen" && ok "a feat commit needs no trailer" || fail "feat blocked"
echo "fun t() = 1" > src/test/ATest.kt; echo "# doc" > README.md; git add -A
try_commit -m "fix: test and docs only" && ok "a fix touching only tests/docs needs no trailer" || fail "tests-only fix blocked: $(cat "$TMP/out")"

mkdir -p .agents/local && printf '%s\n' '{"guards":[{"id":"LIC-0926","title":"t"}]}' > .agents/local/guards.json
git add -A && git commit -qm "chore: guards" --no-verify
echo "fun ok() = 6" > src/main/A.kt && git add -A
try_commit -m "fix: guard the license check" -m "Bug: NOPE-1" && fail "unknown bug id committed" \
  || { grep -q "NOPE-1" "$TMP/out" && ok "an id that is no guard/bug of the project is blocked" || fail "unknown id message: $(cat "$TMP/out")"; }
try_commit -m "fix: guard the license check" -m "Bug: LIC-0926" && ok "a guard id from guards.json passes" || fail "guard id blocked: $(cat "$TMP/out")"

# ── a project's own commit-msg is kept ──────────────────────────────────────────
new_repo
bash "$KIT" githooks uninstall >/dev/null 2>&1
HOOKS="$(git rev-parse --path-format=absolute --git-path hooks)"
printf '#!/bin/sh\n# project hook\nexit 0\n' > "$HOOKS/commit-msg" && chmod +x "$HOOKS/commit-msg"
bash "$KIT" githooks install >/dev/null 2>&1
grep -q "project hook" "$HOOKS/commit-msg" && ok "the project's own commit-msg is not overwritten" || fail "project commit-msg clobbered"
[ -x "$HOOKS/pre-commit" ] && ok "pre-commit still installed next to it" || fail "pre-commit missing"
# …but the DevKit rule is chained into it (GeelyEx2 2026-09-26: its own .githooks/commit-msg
# meant the rule never ran). The line calls <repo>/.agents/devkit, so a tracked hook works on
# every clone and does nothing where the DevKit is not installed.
mkdir -p .agents && ln -sfn "$DEVKIT_DIR" .agents/devkit
grep -q "universal-agent-devkit-chain" "$HOOKS/commit-msg" && ok "the DevKit rule is chained into the project's commit-msg" \
  || fail "no chain line: $(cat "$HOOKS/commit-msg")"
[ "$(sed -n 2p "$HOOKS/commit-msg" | grep -c universal-agent-devkit-chain)" = 1 ] && ok "  … right after the #! line" || fail "chain not on line 2"
! grep -q "/Volumes/\|$DEVKIT_DIR" "$HOOKS/commit-msg" && ok "  … with no machine-specific path" || fail "absolute path in the chain line"
echo "fun ok() = 90" > src/main/A.kt && git add -A
try_commit -m "fix." && fail "vague subject passed the chained hook" || ok "  … and it runs: a vague code subject is blocked"
git reset -q
bash "$KIT" githooks install >/dev/null 2>&1
[ "$(grep -c universal-agent-devkit-chain "$HOOKS/commit-msg")" = 1 ] && ok "re-install does not chain twice" || fail "chained twice"
bash "$KIT" githooks status 2>&1 | grep -q "commit-msg" && ok "githooks status reports commit-msg" || fail "status silent on commit-msg"
bash "$KIT" githooks uninstall >/dev/null 2>&1
grep -q "project hook" "$HOOKS/commit-msg" && ! grep -q "universal-agent-devkit-chain" "$HOOKS/commit-msg" \
  && ok "uninstall removes only the chain line, keeps the project's hook" || fail "uninstall: $(cat "$HOOKS/commit-msg" 2>&1)"
# A hooks dir entry that is a symlink to a tracked hook: the tracked file gets the line, the link stays.
bash "$KIT" githooks uninstall >/dev/null 2>&1
mkdir -p tracked-hooks && printf '#!/bin/sh\n# tracked project hook\nexit 0\n' > tracked-hooks/commit-msg && chmod 775 tracked-hooks/commit-msg
rm -f "$HOOKS/commit-msg" && ln -s "$PWD/tracked-hooks/commit-msg" "$HOOKS/commit-msg"
bash "$KIT" githooks install >/dev/null 2>&1
[ -L "$HOOKS/commit-msg" ] && grep -q "universal-agent-devkit-chain" tracked-hooks/commit-msg \
  && ok "a symlinked hook: the link stays, its target gets the chain line" || fail "symlink replaced or target not chained"
[ "$(stat -f %Lp tracked-hooks/commit-msg 2>/dev/null || stat -c %a tracked-hooks/commit-msg)" = 775 ] \
  && ok "  … and keeps its mode" || fail "mode changed"
bash "$KIT" githooks uninstall >/dev/null 2>&1
[ -L "$HOOKS/commit-msg" ] && ! grep -q "universal-agent-devkit-chain" tracked-hooks/commit-msg \
  && ok "  … uninstall removes the line from the target" || fail "uninstall on a symlinked hook"
rm -f "$HOOKS/commit-msg"

[ "$FAILS" -eq 0 ] && echo "✅ test_commit_hygiene: all passed" || { echo "❌ test_commit_hygiene: $FAILS failed"; exit 1; }
