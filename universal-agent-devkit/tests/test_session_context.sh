#!/usr/bin/env bash
# Regression test: hooks/session_context.sh (SessionStart) reports the regression
# matrix state the Stop gate will really see — adopted or sample, trusted (committed,
# or byte-identical to a DevKit/generated matrix) or not — instead of calling any
# .agents/regression_matrix.active.json "active".
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_context.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
ctx() { printf '{"session_id":"sc","hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>/dev/null; }
repo() { mkdir -p "$TMP/$1/src" "$TMP/$1/.agents" && cd "$TMP/$1" && git init -q . && git config user.email t@t \
  && git config user.name t && echo "fun ok() = 1" > src/Core.kt; }
own_matrix() { cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
}

# No matrix at all.
repo none && git add -A && git commit -qm init
out="$(ctx "$TMP/none")"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "ma trận hồi quy: chưa có" && printf '%s' "$out" | grep -q "KHÔNG chạy test hồi quy" \
  && ok "no matrix: says no regression test runs at stop" || fail "no matrix: $out"

# Committed, adopted matrix: trusted — tests run at stop.
repo trusted && own_matrix && git add -A && git commit -qm init
out="$(ctx "$TMP/trusted")"
printf '%s' "$out" | grep -q "được gate tin — test hồi quy chạy khi dừng" && ! printf '%s' "$out" | grep -q "KHÔNG chạy test" \
  && ok "committed matrix: trusted, tests run at stop" || fail "committed matrix: $out"

# Uncommitted matrix: the gate does not trust it — say so, and name the cure.
repo uncommitted && git add -A && git commit -qm init && own_matrix
out="$(ctx "$TMP/uncommitted")"
printf '%s' "$out" | grep -q "CHƯA được gate tin" && printf '%s' "$out" | grep -q "commit .agents/regression_matrix.active.json" \
  && ! printf '%s' "$out" | grep -q "chạy khi dừng\b\|khi dừng: test hồi quy theo ma trận" \
  && ok "uncommitted matrix: reported untrusted, cure = commit it" || fail "uncommitted matrix: $out"

# Committed matrix edited in the working tree: not trusted either.
cd "$TMP/trusted" && sed -i.bak 's/"true"/"true; true"/' .agents/regression_matrix.active.json && rm -f .agents/regression_matrix.active.json.bak
out="$(ctx "$TMP/trusted")"
printf '%s' "$out" | grep -q "CHƯA được gate tin" && ok "edited committed matrix: reported untrusted" || fail "edited matrix: $out"

# A DevKit sample matrix (Unity: no runner detected): the Stop gate is off.
repo sample && cp "$DEVKIT_DIR/templates/regression_matrix.json" .agents/regression_matrix.active.json && git add -A && git commit -qm init
out="$(ctx "$TMP/sample")"
printf '%s' "$out" | grep -q "ma trận MẪU" && printf '%s' "$out" | grep -q "KHÔNG chạy test hồi quy" \
  && ok "sample matrix: reported as a sample, gate off" || fail "sample matrix: $out"

# One developer, one branch (2026-09-26, GeelyEx2: local main 2 commits behind origin, stray branches
# and worktrees left behind): session start fetches, then names a branch behind/ahead of its upstream,
# leftover worktrees and extra local branches, each with the command that fixes it.
git init -q --bare -b main "$TMP/origin.git"
repo drift && git add -A && git commit -qm init && git branch -M main && git remote add origin "$TMP/origin.git" \
  && git push -q -u origin main 2>/dev/null
git clone -q -b main "$TMP/origin.git" "$TMP/other" 2>/dev/null && git -C "$TMP/other" -c user.email=t@t -c user.name=t commit -q --allow-empty -m remote1 \
  && git -C "$TMP/other" push -q origin HEAD:main 2>/dev/null
cd "$TMP/drift" && git branch feat/done && git branch release/1.0 && git worktree add -q "$TMP/drift-wt" -b feat/wt 2>/dev/null
out="$(ctx "$TMP/drift")"
printf '%s' "$out" | grep -q "main sau origin/main 1 commit" && printf '%s' "$out" | grep -q "git pull --ff-only" \
  && ok "drift: behind upstream after a fetch, cure = pull --ff-only" || fail "drift behind: $out"
printf '%s' "$out" | grep -q "git branch -d feat/done" && ! printf '%s' "$out" | grep -q "release/1.0" \
  && ok "drift: merged extra branch named with branch -d, release/* left alone" || fail "drift branches: $out"
printf '%s' "$out" | grep -q "drift-wt" && ok "drift: leftover worktree named" || fail "drift worktree: $out"
git commit -q --allow-empty -m local1
out="$(ctx "$TMP/drift")"
printf '%s' "$out" | grep -q "trước 1, sau 1" && printf '%s' "$out" | grep -q "git pull --no-rebase" \
  && ok "drift: diverged, cure = pull --no-rebase then push" || fail "drift diverged: $out"
out="$(ctx "$TMP/trusted")"
! printf '%s' "$out" | grep -q "1 dev, 1 nhánh" && ok "one clean branch: no branch line" || fail "clean repo: $out"

# An unreachable ssh remote (review 2026-09-26): the fetch never prompts, is bounded, and leaves no
# orphan ssh behind when its timeout fires.
repo unreach && git add -A && git commit -qm init && git branch -M main \
  && git remote add origin ssh://git@10.255.255.1/unreach.git && git update-ref refs/remotes/origin/main HEAD \
  && git branch -q -u origin/main
start=$(date +%s); ctx "$TMP/unreach" >/dev/null; secs=$(( $(date +%s) - start ))
if pgrep -f "10.255.255.1" >/dev/null; then orphan=yes; pkill -f "10.255.255.1"; else orphan=no; fi
[ "$orphan" = no ] && [ "$secs" -le 8 ] && ok "unreachable remote: bounded fetch, no orphan ssh (${secs}s)" \
  || fail "unreachable remote: orphan=$orphan secs=$secs"

# The fetch keeps the user's own ssh command (core.sshCommand: a custom key) and adds BatchMode to it.
printf '#!/bin/sh\necho "$@" >> "%s/ssh-args"\nexit 255\n' "$TMP" > "$TMP/fake-ssh" && chmod +x "$TMP/fake-ssh"
repo ownssh && git add -A && git commit -qm init && git branch -M main \
  && git remote add origin ssh://git@example.invalid/own.git && git update-ref refs/remotes/origin/main HEAD \
  && git branch -q -u origin/main && git config core.sshCommand "$TMP/fake-ssh"
ctx "$TMP/ownssh" >/dev/null
grep -q "BatchMode=yes" "$TMP/ssh-args" 2>/dev/null && ok "fetch: user's core.sshCommand kept, BatchMode added" \
  || fail "fetch ssh: $(cat "$TMP/ssh-args" 2>/dev/null || echo 'core.sshCommand not used')"

# Escape hatch, never blocks.
SESSION_CONTEXT=0 bash "$HOOK" </dev/null; [ $? = 0 ] && ok "SESSION_CONTEXT=0 exits 0" || fail "escape hatch"

if [ "$FAILS" -ne 0 ]; then echo "session context: $FAILS FAILED"; exit 1; fi
echo "session context: all checks passed"
