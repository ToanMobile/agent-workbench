#!/usr/bin/env bash
# Hồi quy 31/10/2026: merge-policy bỏ nhánh "human" cho money / auth / schema / migration. Các PR đó vào `machine_gate` (không vào
# `human`), plan.require đòi review deep + reviewer security + test bổ sung (merge_policy.machine_gate.verify_commands và
# categories.<cat>.verify_commands). Cấu hình cũ always_human cũng thành machine gate. PR thường: không gate, require rỗng.
# verify_commands sai kiểu → rỗng (gate dừng exit 9, fail-closed). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-policy-machine.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cfg() { printf '%s' "$1" > "$TMP/cfg.json"; }
# plan <path> <added line> [labels json] → JSON plan on stdout
plan() {
  printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1,1 +1,2 @@\n ctx\n+%s\n' "$1" "$1" "$1" "$1" "$2" > "$TMP/d.diff"
  printf '{"files":[{"path":"%s","additions":1,"deletions":0}],"labels":%s,"body":"","additions":1,"deletions":0,"changedFiles":1}' \
    "$1" "${3:-[]}" > "$TMP/m.json"
  python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/m.json" --diff "$TMP/d.diff"
}
# q <plan> <python expr over p> → prints result
q() { python3 -c 'import json,sys; p=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$1" "$2"; }

cfg '{"merge_policy":{"default":"auto","machine_gate":{"verify_commands":["npm run test:sensitive"],
      "categories":{"money":{"labels":["billing"],"paths":["**/billing/**"],"keywords":["payment_intent"],"verify_commands":["npm run test:payments"]},
                    "auth":{"paths":["**/auth/**"],"keywords":["jwt.sign"]},
                    "schema":{"keywords":["drop table"]}}}}}'
for c in "money|src/billing/charge.ts|x = 1" "money|app/x.ts|const p = payment_intent.id;" "auth|server/auth/login.kt|x = 1" \
         "auth|app/token.ts|jwt.sign(payload, key)" "schema|db/q.sql|DROP TABLE users;" "migration|supabase/migrations/2026_add.sql|alter table t add c int;"; do
  cat=${c%%|*}; rest=${c#*|}; path=${rest%%|*}; line=${rest#*|}
  P=$(plan "$path" "$line")
  r=$(q "$P" '(p["human"] == [], "'"$cat"'" in [m["category"] for m in p["machine_gate"]], p["require"]["deep_review"], p["require"]["security_reviewer"], "npm run test:sensitive" in p["require"]["verify_commands"])')
  [ "$r" = "(True, True, True, True, True)" ] \
    && ok "$cat ($path): no human route; machine gate requires deep review + security reviewer + extra tests" \
    || fail "$cat ($path): $r — $P"
done
P=$(plan "app/x.ts" "x = 1" '[{"name":"billing"}]')
[ "$(q "$P" 'p["human"] == [] and "npm run test:payments" in p["require"]["verify_commands"] and "npm run test:sensitive" in p["require"]["verify_commands"]')" = True ] \
  && ok "money label: per-category extra test added to the global one" || fail "money label: $P"
P=$(plan "app/plain.ts" "x = 1")
[ "$(q "$P" 'p["human"] == [] and p["machine_gate"] == [] and p["require"] == {"deep_review": False, "security_reviewer": False, "verify_commands": []}')" = True ] \
  && ok "plain PR: no machine gate, no extra requirement" || fail "plain PR: $P"

# Mặc định (không cấu hình): category mặc định vẫn gate, không có test bổ sung → require.verify_commands rỗng (gate exit 9).
cfg '{"merge_policy":{"default":"auto"}}'
P=$(plan "server/auth/login.kt" "x = 1")
[ "$(q "$P" 'p["human"] == [] and [m["category"] for m in p["machine_gate"]] == ["auth"] and p["require"]["verify_commands"] == [] and p["require"]["deep_review"]')" = True ] \
  && ok "defaults: auth path is machine-gated, not human; no extra test configured → empty list (gate fails closed)" || fail "defaults: $P"
P=$(plan "app/pay.ts" "import Stripe from 'stripe';")
[ "$(q "$P" 'p["human"] == [] and "money" in [m["category"] for m in p["machine_gate"]]')" = True ] \
  && ok "defaults: Stripe import is machine-gated money, not human" || fail "defaults money: $P"
P=$(plan "prisma/migrations/1/migration.sql" "create table t (id int);")
[ "$(q "$P" 'p["human"] == [] and "migration" in [m["category"] for m in p["machine_gate"]]')" = True ] \
  && ok "defaults: a migration PR is machine-gated (category migration), never human" || fail "defaults migration: $P"

# Cấu hình cũ always_human → machine gate.
cfg '{"merge_policy":{"default":"auto","always_human":{"money":{"paths":["**/payments/**"]}},"machine_gate":{"verify_commands":["make t"]}}}'
P=$(plan "src/payments/a.ts" "x = 1")
[ "$(q "$P" 'p["human"] == [] and [m["category"] for m in p["machine_gate"]] == ["money"] and p["require"]["verify_commands"] == ["make t"]')" = True ] \
  && ok "legacy always_human config routes to the machine gate, not a human" || fail "legacy always_human: $P"

# verify_commands sai kiểu → rỗng (fail-closed ở gate), không crash, không thành human.
cfg '{"merge_policy":{"default":"auto","machine_gate":{"verify_commands":"npm test"}}}'
P=$(plan "server/auth/x.kt" "x = 1")
[ "$(q "$P" 'p["human"] == [] and p["require"]["verify_commands"] == []')" = True ] \
  && ok "machine_gate.verify_commands that is not a list → no extra test (gate stops with exit 9)" || fail "bad verify_commands: $P"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
