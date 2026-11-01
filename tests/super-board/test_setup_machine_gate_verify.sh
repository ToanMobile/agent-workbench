#!/usr/bin/env bash
# Hồi quy #742 (review P0 13bcd39b20): PR machine-gate (money / auth / schema / migration) cần test bổ sung
# merge_policy.machine_gate.verify_commands; config của repo và config do super-board-setup.py dựng không khai nó, nên mọi
# PR bị gate dừng ở exit 9 (verification-readiness). Kiểm: setup migrate-config thêm test bổ sung mặc định khi thiếu, không
# đụng danh sách đã khai; config agent-workbench.json cho PR auth/migration ra require.verify_commands khác rỗng.
# Chỉ ghi file tạm. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETUP="$ROOT/.claude/bin/super-board-setup.py"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
extra() { python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print("\n".join(((c.get("merge_policy") or {}).get("machine_gate") or {}).get("verify_commands") or []))' "$1"; }

echo '{"base_branch":"main","verify_commands":["make test"],"merge_policy":{"default":"auto"}}' > "$TMP/a.json"
python3 "$SETUP" migrate-config "$TMP/a.json" > "$TMP/a.out" 2>&1
case "$(extra "$TMP/a.json")" in *"post-fix-gate.py --run-tests --brief --no-cache"*)
  grep -q 'machine_gate.verify_commands' "$TMP/a.out" && ok "missing machine_gate.verify_commands: setup adds the uncached DevKit gate run and reports it" \
    || fail "added but not reported: $(cat "$TMP/a.out")" ;;
  *) fail "setup left machine_gate.verify_commands empty: [$(extra "$TMP/a.json")] $(cat "$TMP/a.out")" ;; esac
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verify_commands"])' "$TMP/a.json")" = "['make test']" ] \
  && ok "the project's verify_commands are untouched" || fail "verify_commands changed"

echo '{"base_branch":"main","verify_commands":["make test"],"merge_policy":{"default":"auto","machine_gate":{"verify_commands":["make test-auth"],"categories":{"auth":{"paths":["src/auth/**"]}}}}}' > "$TMP/b.json"
python3 "$SETUP" migrate-config "$TMP/b.json" > "$TMP/b.out" 2>&1
[ "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["merge_policy"]["machine_gate"], sort_keys=True))' "$TMP/b.json")" \
  = '{"categories": {"auth": {"paths": ["src/auth/**"]}}, "verify_commands": ["make test-auth"]}' ] && ! grep -q 'machine_gate' "$TMP/b.out" \
  && ok "declared machine_gate.verify_commands: kept as is, no change reported" || fail "declared list touched: $(cat "$TMP/b.out")"

echo '{"base_branch":"main","verify_commands":["make test"],"merge_policy":{"default":"auto","machine_gate":{"verify_commands":["  "]}}}' > "$TMP/c.json"
python3 "$SETUP" migrate-config "$TMP/c.json" >/dev/null 2>&1
case "$(extra "$TMP/c.json")" in *"--no-cache"*) ok "blank-only machine_gate.verify_commands counts as missing" ;;
  *) fail "blank list kept: [$(extra "$TMP/c.json")]" ;; esac

# config thật của repo: PR auth và PR migration đều có test bổ sung (không exit 9)
: > "$TMP/empty.diff"
for p in server/auth/login.kt supabase/migrations/2026_x.sql; do
  printf '{"labels":[],"body":"","files":[{"path":"%s","additions":1,"deletions":0}]}' "$p" > "$TMP/m.json"
  n=$(python3 "$POLICY" --config "$ROOT/.claude/super-board/configs/agent-workbench.json" --meta "$TMP/m.json" --diff "$TMP/empty.diff" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["require"]["verify_commands"]) if d["machine_gate"] else -1)')
  [ "$n" -gt 0 ] 2>/dev/null && ok "agent-workbench.json: gated PR ($p) gets $n extra test command(s)" || fail "agent-workbench.json: gated PR ($p) has no extra test (n=$n) — exit 9"
done
python3 "$SETUP" migrate-config "$ROOT/.claude/super-board/configs/agent-workbench.json" --dry-run > "$TMP/wb.out" 2>&1
! grep -q 'machine_gate' "$TMP/wb.out" && ok "agent-workbench.json already declares machine_gate.verify_commands (setup has nothing to add)" \
  || fail "setup would still add machine_gate to agent-workbench.json: $(cat "$TMP/wb.out")"
python3 -c 'import json,os,shlex,sys
for c in json.load(open(sys.argv[1]))["merge_policy"]["machine_gate"]["verify_commands"]:
    w = shlex.split(c)
    assert w[0] == "bash" and os.path.isfile(os.path.join(sys.argv[2], w[1])), c' \
  "$ROOT/.claude/super-board/configs/agent-workbench.json" "$ROOT" \
  && ok "every agent-workbench extra test names a script that exists" || fail "an agent-workbench extra test names a missing script"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
