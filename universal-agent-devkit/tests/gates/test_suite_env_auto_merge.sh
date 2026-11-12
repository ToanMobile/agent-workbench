#!/usr/bin/env bash
# #811: WORKTREE_AUTO_MERGE=0 (công tắc Stop hook của phiên đa lane) không được lọt vào suite:
# suite_env() bỏ nó và clean_git_env.sh gỡ nó. bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
CLEAN="$DEVKIT_DIR/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

kept="$(env WORKTREE_AUTO_MERGE=0 DEVKIT_PROBE_KEEP=1 python3 - "$GATE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("post_fix_gate", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print("\n".join(sorted(mod.suite_env())))
PY
)" || { echo "✖ could not import $GATE"; exit 1; }
printf '%s\n' "$kept" | grep -qx DEVKIT_PROBE_KEEP || { echo "✖ suite_env probe returned nothing"; exit 1; }
printf '%s\n' "$kept" | grep -qx WORKTREE_AUTO_MERGE && fail "suite_env keeps WORKTREE_AUTO_MERGE" || ok "suite_env drops WORKTREE_AUTO_MERGE"

left="$(env WORKTREE_AUTO_MERGE=0 bash -c '. "$1"; echo "${WORKTREE_AUTO_MERGE-unset}"' _ "$CLEAN")" \
  || { echo "✖ could not source $CLEAN"; exit 1; }
[ "$left" = unset ] && ok "clean_git_env unsets WORKTREE_AUTO_MERGE" || fail "clean_git_env keeps WORKTREE_AUTO_MERGE=$left"

echo
[ "$FAILS" -eq 0 ] && { echo "test_suite_env_auto_merge: PASS"; exit 0; }
echo "test_suite_env_auto_merge: FAIL ($FAILS)"
exit 1
