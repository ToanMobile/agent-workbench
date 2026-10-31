#!/usr/bin/env bash
# Hồi quy #747 (quyết định anh Đạt 31/10 16:17): fixture tiền / auth / schema trong test của chính merge-policy
# (tests/super-board/test_merge_policy_*.sh) làm PR #742 bị machine-gate (exit 9). Dòng thêm của đúng các file đó không còn
# kích keyword/pattern; cùng chuỗi đó trong code sản phẩm, trong test khác, hay khi PR có label/path tiền vẫn bị chặn.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-policy-self.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
printf '%s' '{"merge_policy":{"default":"auto"}}' > "$TMP/cfg.json"

# Dòng thêm thật của fixture trong test_merge_policy_machine_gate.sh (tiền, auth, schema, Stripe import).
FIXTURE=$(printf '%s\n' "const p = payment_intent.id;" "jwt.sign(payload, key)" "DROP TABLE users;" "import Stripe from 'stripe';")
# section <path> <added lines> → one file section of a unified git diff, appended to $TMP/d.diff
section() {
  printf 'diff --git a/%s b/%s\nindex 1111111..2222222 100644\n--- a/%s\n+++ b/%s\n@@ -1,1 +1,5 @@\n ctx\n' "$1" "$1" "$1" "$1" >> "$TMP/d.diff"
  printf '%s\n' "$2" | sed 's/^/+/' >> "$TMP/d.diff"
}
# run <labels json> <path>... → JSON plan on stdout (diff already in $TMP/d.diff)
run() {
  labels=$1; shift
  files=""
  for f in "$@"; do files="$files${files:+,}{\"path\":\"$f\",\"additions\":4,\"deletions\":0}"; done
  printf '{"files":[%s],"labels":%s,"body":"","additions":4,"deletions":0,"changedFiles":%s}' "$files" "$labels" "$#" > "$TMP/m.json"
  python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/m.json" --diff "$TMP/d.diff"
}
cats() { python3 -c 'import json,sys; print(",".join(sorted({m["category"] for m in json.loads(sys.argv[1])["machine_gate"]})))' "$1"; }
expect() {  # expect <name> <want categories> <plan>
  got=$(cats "$3")
  [ "$got" = "$2" ] && ok "$1 → [${2}]" || fail "$1: want [${2}] got [${got}] — $3"
}

: > "$TMP/d.diff"; section tests/super-board/test_merge_policy_machine_gate.sh "$FIXTURE"
expect "(i) fixture in the policy's own test does not trigger the machine gate" "" \
  "$(run '[]' tests/super-board/test_merge_policy_machine_gate.sh)"

: > "$TMP/d.diff"; section tests/super-board/test_merge_policy_sql_forms.sh "ALTER TABLE t DROP c;"
expect "(i) pattern fixture in another test_merge_policy_*.sh does not trigger" "" \
  "$(run '[]' tests/super-board/test_merge_policy_sql_forms.sh)"

: > "$TMP/d.diff"; section app/token.ts "$FIXTURE"
expect "(ii) the same strings in product code stay gated" "auth,money,schema" "$(run '[]' app/token.ts)"

: > "$TMP/d.diff"; section tests/super-board/test_merge_policy_machine_gate.sh "$FIXTURE"; section server/login.kt "jwt.sign(payload, key)"
expect "(ii) fixture file + real jwt.sign in product code in one PR → auth gated" "auth" \
  "$(run '[]' tests/super-board/test_merge_policy_machine_gate.sh server/login.kt)"

: > "$TMP/d.diff"; section db/schema.sql "DROP TABLE users;"; section tests/super-board/test_merge_policy_sql_forms.sh "$FIXTURE"
expect "(ii) real DROP TABLE before a fixture file → schema gated" "schema" \
  "$(run '[]' db/schema.sql tests/super-board/test_merge_policy_sql_forms.sh)"

: > "$TMP/d.diff"; section src/pay.ts "const p = payment_intent.id;"
expect "(ii) real payment_intent in product code → money gated" "money" "$(run '[]' src/pay.ts)"

# Phạm vi hẹp: chỉ tests/super-board/test_merge_policy_*.sh ở gốc repo.
: > "$TMP/d.diff"; section tests/super-board/test_login.sh "jwt.sign(payload, key)"
expect "another test under tests/ is still scanned" "auth" "$(run '[]' tests/super-board/test_login.sh)"
: > "$TMP/d.diff"; section src/tests/super-board/test_merge_policy_x.sh "jwt.sign(payload, key)"
expect "same name nested under src/ is still scanned" "auth" "$(run '[]' src/tests/super-board/test_merge_policy_x.sh)"
: > "$TMP/d.diff"; section tests/super-board/test_merge_policy_x.py "jwt.sign(payload, key)"
expect "a non-.sh file with the policy test prefix is still scanned" "auth" "$(run '[]' tests/super-board/test_merge_policy_x.py)"

# Không giả được header file: nội dung luôn có tiền tố "+", nên dòng giống `diff --git`/`+++ b/` trong code vẫn là code.
: > "$TMP/d.diff"
section app/a.ts "$(printf '%s\n' "diff --git a/tests/super-board/test_merge_policy_z.sh b/tests/super-board/test_merge_policy_z.sh" \
  "++ b/tests/super-board/test_merge_policy_z.sh" "jwt.sign(payload, key)")"
expect "a product file faking a diff header for a policy test is still gated" "auth" "$(run '[]' app/a.ts)"

# Đổi tên từ file test policy sang code sản phẩm: đường dẫn mới quyết định.
printf 'diff --git a/tests/super-board/test_merge_policy_a.sh b/app/a.ts\nsimilarity index 90%%\nrename from tests/super-board/test_merge_policy_a.sh\nrename to app/a.ts\n--- a/tests/super-board/test_merge_policy_a.sh\n+++ b/app/a.ts\n@@ -1,1 +1,2 @@\n ctx\n+jwt.sign(payload, key)\n' > "$TMP/d.diff"
expect "a policy test renamed into product code is gated" "auth" "$(run '[]' app/a.ts)"

# Label và path vẫn tính như cũ, kể cả khi PR chỉ đổi fixture.
: > "$TMP/d.diff"; section tests/super-board/test_merge_policy_machine_gate.sh "$FIXTURE"
expect "billing label on a fixture-only PR → money gated" "money" \
  "$(run '[{"name":"billing"}]' tests/super-board/test_merge_policy_machine_gate.sh)"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
