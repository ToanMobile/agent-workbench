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

# Escape hatch, never blocks.
SESSION_CONTEXT=0 bash "$HOOK" </dev/null; [ $? = 0 ] && ok "SESSION_CONTEXT=0 exits 0" || fail "escape hatch"

if [ "$FAILS" -ne 0 ]; then echo "session context: $FAILS FAILED"; exit 1; fi
echo "session context: all checks passed"
