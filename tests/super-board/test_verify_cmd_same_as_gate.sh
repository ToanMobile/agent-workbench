#!/usr/bin/env bash
# Issue #251 (AC2): QA phải chạy đúng lệnh verify mà merge gate chạy. super-board-verify-cmd.sh in lệnh đã chèn cờ bằng cùng hàm
# sb_verify_inject_flags mà merge gate dùng: so từng lệnh với bảng đúng của test_merge_gate_verify_flags.sh.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CMD="$ROOT/.claude/bin/super-board-verify-cmd.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-verify-cmd-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

G=/x/.agents/devkit/bin/post-fix-gate.py
FL='--diff origin/main --scoped'
want() {  # want <verify command> <expected> [base_branch]
  python3 -c 'import json,sys; print(json.dumps({"base_branch":sys.argv[3],"verify_commands":[sys.argv[1], "  "]}))' "$1" "" "${3:-main}" > "$TMP/c.json"
  got=$(bash "$CMD" --config "$TMP/c.json" 2>&1)
  if [ "$got" = "$2" ]; then ok "QA command for: $1"; else fail "for: $1 want [$2] got [$got]"; fi
}
want "python3 $G --run-tests && true" "python3 $G $FL --run-tests && true"
want "bash -c 'python3 $G --run-tests'" "bash -c 'python3 $G $FL --run-tests'"
want "python3 $G --run-tests" "python3 $G --run-tests $FL"
want "python3 $G --run-tests" "python3 $G --run-tests --diff origin/develop --scoped" develop
want "npm test" "npm test"
bash "$CMD" 2>/dev/null; [ "$?" -eq 64 ] && ok "no --config: usage error (64)" || fail "no --config must exit 64"

echo
[ "$FAILS" -eq 0 ] && { echo "test_verify_cmd_same_as_gate: PASS"; exit 0; } || { echo "test_verify_cmd_same_as_gate: FAIL ($FAILS)"; exit 1; }
