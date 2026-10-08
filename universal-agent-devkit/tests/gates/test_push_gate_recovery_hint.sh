#!/usr/bin/env bash
# Regression (OfficeReader 2026-10-08, ~1 h): in a clone whose HEAD was DETACHED the gate passed on the detached tip, but
# `git push origin main` was refused with only "lần gate PASS gần nhất (X) không nằm trong lịch sử của main": no repo, no word
# about the detached HEAD, no hint that the LOCAL main branch was simply stale. Nothing could pass until someone worked out
# `git switch main && git merge --ff-only <sha>`. bin/push_gate.py now names the repo and where HEAD is and, when a stale local
# branch is the cause (it is an ancestor of HEAD, and the gated commit is in HEAD's history), prints that exact command.
#   1. detached HEAD, stale local main: the reason names the repo, says HEAD is detached and prints the fast-forward command
#   2. running the printed command makes the same push pass (the hint is real, not decoration)
#   3. HEAD on another branch (not detached): the same command, and it says which branch
#   4. the tested commit squashed away on the pushed branch itself: no fast-forward command (it would be wrong), the repo and
#      the "run the gate again" advice are still there
#   5. the same on a DETACHED HEAD above a stale local main: fast-forwarding main would not help (the tested commit is still not in
#      its history), so no such command either
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; PG="$DEVKIT_DIR/bin/push_gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"

mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
git init -q . && git symbolic-ref HEAD refs/heads/main && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
run_gate() { CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --full --brief >/dev/null 2>&1; }
push_check() { OUT="$(python3 "$PG" "$R" "$1" 2>&1)"; RC=$?; }

# 1 + 2: the clone is on a detached HEAD; local main stays at the first commit
git checkout -q --detach
echo "fun ok() = 2" > src/Core.kt; git commit -qam "work on the detached HEAD"
echo "fun ok() = 3" > src/Core.kt; run_gate; git commit -qam "the tested content"
TIP="$(git rev-parse HEAD)"
push_check main
[ "$RC" = 2 ] && ok "1: push of the stale local main is refused (exit 2)" || bad "1: expected exit 2, got $RC: $OUT"
case "$OUT" in *"$R"*) ok "  … the reason names the repository" ;; *) bad "  … the repository is not named: $OUT" ;; esac
case "$OUT" in *[Dd]etached*) ok "  … it says HEAD is detached" ;; *) bad "  … detached HEAD not mentioned: $OUT" ;; esac
case "$OUT" in *"git switch main && git merge --ff-only $TIP"*) ok "  … it prints the fast-forward command with the full sha" ;; *) bad "  … no recovery command for $TIP: $OUT" ;; esac
CMD="$(printf '%s\n' "$OUT" | sed -n 's/.*`\(cd .* && git switch main && git merge --ff-only [0-9a-f]*\)`.*/\1/p' | head -1)"
if [ -n "$CMD" ]; then
  (eval "$CMD") >/dev/null 2>&1; E=$?
  push_check main
  [ "$E" = 0 ] && [ "$RC" = 0 ] && ok "2: running the printed command makes the same push pass" || bad "2: after the printed command exit was $RC (command exit $E): $OUT"
else
  bad "2: could not extract the printed command"
fi

# 3: HEAD on another branch, local main stale
cd "$R" && git checkout -q -b work main
echo "fun ok() = 4" > src/Core.kt; git commit -qam "more work"
echo "fun ok() = 5" > src/Core.kt; run_gate; git commit -qam "tested again"
TIP2="$(git rev-parse HEAD)"
push_check main
[ "$RC" = 2 ] && ok "3: push of the stale main from another branch is refused" || bad "3: expected exit 2, got $RC: $OUT"
case "$OUT" in *"nhánh work"*) ok "  … it says which branch HEAD is on" ;; *) bad "  … branch work not named: $OUT" ;; esac
case "$OUT" in *"git switch main && git merge --ff-only $TIP2"*) ok "  … and prints the same command" ;; *) bad "  … no recovery command for $TIP2: $OUT" ;; esac

# 4: the commit the gate tested is squashed away on the pushed branch itself - a fast-forward would be the wrong advice
git checkout -q main && git merge -q --ff-only work
echo "fun ok() = 6" > src/Core.kt; git commit -qam "first of two"
echo "fun ok() = 7" > src/Core.kt; run_gate; git commit -qam "second of two"
git reset -q --soft HEAD~2 && git commit -qm "squashed after the gate"
push_check main
[ "$RC" = 2 ] && ok "4: a squash after the gate is refused" || bad "4: expected exit 2, got $RC: $OUT"
case "$OUT" in *"git merge --ff-only"*) bad "  … it must NOT print a fast-forward command here: $OUT" ;; *) ok "  … no fast-forward command" ;; esac
case "$OUT" in *"$R"*"post-fix-gate.py --run-tests --full"*) ok "  … repo named and the gate command still advised" ;; *) bad "  … repo or gate advice missing: $OUT" ;; esac

# 5: detached HEAD above a stale main, the tested commit squashed away
git checkout -q --detach
echo "fun ok() = 8" > src/Core.kt; git commit -qam "p1"
echo "fun ok() = 9" > src/Core.kt; run_gate; git commit -qam "p2"
git reset -q --soft HEAD~2 && git commit -qm "squashed on the detached HEAD"
push_check main
[ "$RC" = 2 ] && ok "5: detached HEAD, stale main, tested commit squashed away: refused" || bad "5: expected exit 2, got $RC: $OUT"
case "$OUT" in *"git merge --ff-only"*) bad "  … a fast-forward would not help here, yet it is advised: $OUT" ;; *) ok "  … no fast-forward command" ;; esac
case "$OUT" in *[Dd]etached*"post-fix-gate.py --run-tests --full"*) ok "  … says detached and advises running the gate again" ;; *) bad "  … detached note or gate advice missing: $OUT" ;; esac

# 6: HEAD went on after the gate (an UNTESTED code commit above the tested one): fast-forwarding main is only half the way - the hint must
# not promise that no new gate is needed
git checkout -q main; git checkout -q --detach
echo "fun ok() = 20" > src/Core.kt; git commit -qam "c1"
echo "fun ok() = 21" > src/Core.kt; run_gate; git commit -qam "c2 tested"
echo "fun ok() = 22" > src/Core.kt; git commit -qam "c3 code added after the gate"
push_check main
[ "$RC" = 2 ] && ok "6: HEAD ahead of the tested commit: refused" || bad "6: expected exit 2, got $RC: $OUT"
case "$OUT" in *"không cần chạy lại gate"*) bad "  … it promises no new gate is needed, but the later commit changed code: $OUT" ;; *) ok "  … it does not promise that no new gate is needed" ;; esac
case "$OUT" in *"post-fix-gate.py --run-tests --full"*) ok "  … it tells to run the gate on the code that will be pushed" ;; *) bad "  … gate advice missing: $OUT" ;; esac

[ "$FAILS" -eq 0 ] && echo "push gate recovery hint: all checks passed" || { echo "push gate recovery hint: $FAILS FAILED"; exit 1; }
