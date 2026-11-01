#!/usr/bin/env bash
# Hồi quy #742 (review P0 13bcd39b20): PR migration luôn vào machine gate với category "migration", nhưng policy không đọc
# merge_policy.machine_gate.categories.migration.verify_commands, nên test bổ sung riêng cho migration không bao giờ vào
# require.verify_commands và PR chỉ có test đó dừng ở exit 9 của merge gate. Chỉ gọi super-board-merge-policy.py trên file cục bộ.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
: > "$TMP/empty.diff"
echo '{"labels":[],"body":"","files":[{"path":"supabase/migrations/2026_add_col.sql","additions":3,"deletions":0}]}' > "$TMP/mig.json"
echo '{"labels":[],"body":"","files":[{"path":"src/app.ts","additions":3,"deletions":0}]}' > "$TMP/app.json"
tests_of() {   # tests_of <cfg> <meta> → require.verify_commands, one per line
  python3 "$POLICY" --config "$1" --meta "$2" --diff "$TMP/empty.diff" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["require"]["verify_commands"]))'
}

echo '{"merge_policy":{"machine_gate":{"categories":{"migration":{"verify_commands":["npm run test:migrations"]}}}}}' > "$TMP/c1.json"
[ "$(tests_of "$TMP/c1.json" "$TMP/mig.json")" = "npm run test:migrations" ] \
  && ok "migration PR: categories.migration.verify_commands is required" || fail "migration verify_commands missing: [$(tests_of "$TMP/c1.json" "$TMP/mig.json")]"
[ -z "$(tests_of "$TMP/c1.json" "$TMP/app.json")" ] \
  && ok "PR without migrations: the migration-only test is not added" || fail "non-migration PR got [$(tests_of "$TMP/c1.json" "$TMP/app.json")]"

echo '{"merge_policy":{"machine_gate":{"verify_commands":["bash t/all.sh"],"categories":{"migration":{"verify_commands":["bash t/mig.sh","bash t/all.sh"]}}}}}' > "$TMP/c2.json"
[ "$(tests_of "$TMP/c2.json" "$TMP/mig.json" | tr '\n' '|')" = "bash t/all.sh|bash t/mig.sh|" ] \
  && ok "global + migration tests, de-duplicated in order" || fail "global + migration: [$(tests_of "$TMP/c2.json" "$TMP/mig.json" | tr '\n' '|')]"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
