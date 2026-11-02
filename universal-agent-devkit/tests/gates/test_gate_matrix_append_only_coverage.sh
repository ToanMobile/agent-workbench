#!/usr/bin/env bash
# Test hồi quy (P6, gate kẹt và chậm 02/11): PR chỉ NỐI rule vào ma trận ở repo không có [smoke] và không rule nào theo dõi ma trận —
# test của rule mới chạy XANH (matrix_added) nhưng post-fix-gate --run-tests --scoped vẫn exit 2 "no regression test matches the change":
# no_coverage xét impacted_tests chụp TRƯỚC khi nối test của rule mới. Sau P6 (ma trận chỉ-nối không còn kéo test nhắc tên nó) mọi repo
# như vậy đều rơi vào ca này.
#   a. chỉ nối rule B, test của B XANH ⇒ exit 0, REG-B PASS;
#   b. đối chứng: test của rule mới ĐỎ ⇒ REJECT (1);
#   c. đối chứng: đổi file code không rule nào theo dõi, ma trận không đổi ⇒ vẫn exit 2.
# Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${GATE_UNDER_TEST:-$DEVKIT_DIR/bin/post-fix-gate.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
echo "gate: $GATE"

# mk <dir> <exit của test_b.sh> <thay đổi: append|code>: repo không gate-core.txt (không [smoke]), rule A theo dõi src/*; commit "PR"
mk() {
  mkdir -p "$1/src" "$1/lib" "$1/tests" "$1/.agents"
  ( cd "$1" && git init -q -b main . && git config user.email t@t && git config user.name t
    echo "x = 1" > src/a.py && echo "y = 1" > lib/x.py
    printf '#!/bin/sh\ngrep -q "x = 1" src/a.py\n' > tests/test_a.sh
    printf '#!/bin/sh\nexit %s\n' "$2" > tests/test_b.sh
    printf '{"project": "t", "rules": [{"component": "A", "watch_files": ["src/*"], "mandatory_regression_tests": [{"id": "REG-A", "command": "sh tests/test_a.sh"}]}]}\n' \
      > .agents/regression_matrix.active.json
    git add . && git commit -qm base
    if [ "$3" = append ]; then
      python3 -c '
import json; p = ".agents/regression_matrix.active.json"; m = json.load(open(p))
m["rules"].append({"component": "B", "watch_files": ["hooks/*"], "mandatory_regression_tests": [{"id": "REG-B", "command": "sh tests/test_b.sh"}]})
json.dump(m, open(p, "w"), indent=2)'
    else
      echo "y = 2" > lib/x.py
    fi
    git commit -qam pr ) || exit 2
}
gate() {   # gate <dir> → $TMP/out, $RC
  ( cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --lang en --run-tests --scoped --no-cache --diff "$(git rev-parse HEAD~1)" ) >"$TMP/out" 2>&1
  RC=$?
}
tail_out() { grep -E "VERDICT|UNVERIFIED|REJECT" "$TMP/out" | sed 's/\x1b\[[0-9;]*m//g' | tr '\n' ' ' | cut -c1-300; }

mk "$TMP/a" 0 append; gate "$TMP/a"
[ "$RC" = 0 ] && grep -q 'REG-B' "$TMP/out" && ! grep -q 'no regression test matches' "$TMP/out" \
  && ok "a. chỉ nối rule, test mới XANH ⇒ exit 0" || fail "a. chỉ nối rule, test mới XANH ⇒ exit $RC (cần 0): $(tail_out)"
mk "$TMP/b" 1 append; gate "$TMP/b"
[ "$RC" = 1 ] && ok "b. test của rule mới ĐỎ ⇒ REJECT (1)" || fail "b. test mới ĐỎ ⇒ exit $RC (cần 1): $(tail_out)"
mk "$TMP/c" 0 code; gate "$TMP/c"
[ "$RC" = 2 ] && ok "c. đổi code không rule nào theo dõi, ma trận không đổi ⇒ vẫn exit 2" || fail "c. đổi code không test ⇒ exit $RC (cần 2): $(tail_out)"

[ "$FAILS" = 0 ] && echo "PASS test_gate_matrix_append_only_coverage" && exit 0
echo "FAIL test_gate_matrix_append_only_coverage: $FAILS"; exit 1
