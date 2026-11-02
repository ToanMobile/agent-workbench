#!/usr/bin/env bash
# #528: suite_env() bỏ năm biến của worker board, và clean_git_env.sh gỡ cùng năm biến.
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
CLEAN="$DEVKIT_DIR/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

probe() {
  env "$@" python3 - "$GATE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("post_fix_gate", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print("\n".join(sorted(mod.suite_env())))
PY
}

kept="$(probe SB_BOARD_WORKER=1 SB_MERGE_CALLER=train SB_MERGE_QUEUE=1 SB_REPO_PATH=/tmp/board SB_GITHUB_READ_STRICT=1 DEVKIT_PROBE_KEEP=1)" \
  || { echo "✖ could not import $GATE"; exit 1; }
printf '%s\n' "$kept" | grep -qx DEVKIT_PROBE_KEEP || { echo "✖ suite_env probe returned nothing"; exit 1; }
for v in SB_BOARD_WORKER SB_MERGE_CALLER SB_MERGE_QUEUE SB_REPO_PATH SB_GITHUB_READ_STRICT; do
  printf '%s\n' "$kept" | grep -qx "$v" && fail "suite_env keeps $v" || ok "suite_env drops $v"
done

left="$(env SB_BOARD_WORKER=1 SB_MERGE_CALLER=train SB_MERGE_QUEUE=1 SB_REPO_PATH=/tmp/board SB_GITHUB_READ_STRICT=1 \
  bash -c '. "$1"
for v in SB_BOARD_WORKER SB_MERGE_CALLER SB_MERGE_QUEUE SB_REPO_PATH SB_GITHUB_READ_STRICT; do
  eval "cur=\${$v-unset}"
  printf "%s=%s\n" "$v" "$cur"
done' _ "$CLEAN")" || { echo "✖ could not source $CLEAN"; exit 1; }
for v in SB_BOARD_WORKER SB_MERGE_CALLER SB_MERGE_QUEUE SB_REPO_PATH SB_GITHUB_READ_STRICT; do
  printf '%s\n' "$left" | grep -qx "$v=unset" && ok "clean_git_env unsets $v" || fail "clean_git_env keeps $v ($(printf '%s\n' "$left" | grep "^$v="))"
done

echo
[ "$FAILS" -eq 0 ] && { echo "test_suite_env_worker_vars: PASS"; exit 0; }
echo "test_suite_env_worker_vars: FAIL ($FAILS)"
exit 1
