#!/usr/bin/env bash
# Regression (19/11): `worktree.py remove` / `discard` keep a fallback copy under refs/devkit/discarded/<label>-<stamp>-<pid> (_keep_ref). The label came from the
# worktree folder name with only [^A-Za-z0-9._-] replaced, so a dot-named scratch folder (the merge gate's `.merge-scratch-keep-pr1373-…`) gave a ref component
# that starts with a dot, which git refuses (`update_ref failed`): the worktree could be neither removed nor discarded. A label with `..` is refused the same way.
# _keep_ref must always produce a valid ref (git check-ref-format) that points at the kept commit.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/main" && cd "$TMP/main" || exit 1
git init -q . && git config user.email t@t && git config user.name t
git commit -q --allow-empty -m init
TREE="$(git mktree </dev/null)"

check_label() {   # check_label <label> <what>
  local out rc
  out="$(python3 -I - "$WT" "$TMP/main" "$TREE" "$1" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("wt", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m._keep_ref(sys.argv[2], sys.argv[4], sys.argv[3], [], "keep"))
PY
)"; rc=$?
  if [ "$rc" -eq 0 ] && git check-ref-format "$out" && git rev-parse --verify -q "$out" >/dev/null; then ok "$2: valid ref $out"
  else fail "$2: rc=$rc out=$(printf '%s' "$out" | tail -1 | cut -c1-160)"; fi
}

check_label "plain-name" "plain folder name"
check_label ".merge-scratch-keep-pr1373-20261119-205509" "dot-named scratch folder"
check_label "a..b" "label with .."
check_label "..hidden" "label starting with .."
check_label "." "label that is a single dot"
check_label "-leading-dash" "label with a leading dash"

echo
[ "$FAILS" -eq 0 ] && { echo "test_keep_ref_dot_name: PASS"; exit 0; } || { echo "test_keep_ref_dot_name: FAIL ($FAILS)"; exit 1; }
