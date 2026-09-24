#!/usr/bin/env bash
# Regression test: the V2 dashboard .agents/CHECKLIST.md (regression_checklist.md is a link to it).
#  - one HUD line: "An toàn X% (PASS/confirmed rows)" — REPORTED rows are not in the count;
#    "ma trận chờ duyệt: có" while the matrix has uncommitted changes
#  - 🚨 alert zone FIRST: every row that needs work, each with one "việc cần làm" sentence
#  - modules (matrix component): tests + REQs with the run signature (duration · exit · commit ·
#    log); a module at 100% PASS is folded in <details>
#  - bug ledger: ID | description | protecting test | status | evidence
#  - archive: a bug PASS for ≥ 30 days and ≥ 30 commits since its link moves to
#    .agents/archive/BUG_ARCHIVE.md (view only — still checked); back in the alert zone when red
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; KIT="$DEVKIT_DIR/bin/agent-kit"; RC="$DEVKIT_DIR/bin/regression_checklist.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src/a" "$P/src/b" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo 1 > src/a/x.txt; echo 1 > src/b/y.txt
cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[
 {"component":"Ký số","watch_files":["src/a/*"],"mandatory_regression_tests":[
   {"id":"REG-A1","name":"a1","command":"true"},{"id":"REG-A2","name":"a2","command":"true"}]},
 {"component":"Đọc file","watch_files":["src/b/*"],"mandatory_regression_tests":[{"id":"REG-B","name":"b","command":"false"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
echo 2 > src/a/x.txt; echo 2 > src/b/y.txt
python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
git add -A && git commit -qm ran
bash "$KIT" bugs add "Chữ ký sai định dạng" --fixed --module "Ký số" >/dev/null 2>&1
bash "$KIT" req add "Ký nhiều file" --module "Ký số" --criterion "ký 2 file → 2 chữ ký" >/dev/null 2>&1
python3 -c 'import json,sys; print(json.dumps({"prompt": "App bị crash khi mở file PDF", "session_id": "v"}))' \
  | bash "$DEVKIT_DIR/hooks/prompt_context.sh" >/dev/null 2>&1
python3 "$RC" render >/dev/null
V="$P/.agents/CHECKLIST.md"

[ -f "$V" ] && [ -L "$P/.agents/regression_checklist.md" ] && [ "$(readlink "$P/.agents/regression_checklist.md")" = CHECKLIST.md ] \
  && ok "CHECKLIST.md is the view; regression_checklist.md links to it (one file)" || fail "files: $(ls -la "$P/.agents")"
hud="$(grep -m1 "An toàn" "$V")"
# confirmed rows: 3 tests + 1 bug + 1 REQ = 5 (REPORTED not counted); PASS: REG-A1, REG-A2
printf '%s' "$hud" | grep -q "An toàn 40% (2/5)" && ok "HUD: safe % over confirmed rows, REPORTED excluded ($hud)" || fail "HUD: $hud"
alert="$(grep -n "🚨" "$V" | head -1 | cut -d: -f1)"; mod="$(grep -n "^## 🧩" "$V" | head -1 | cut -d: -f1)"
[ -n "$alert" ] && [ -n "$mod" ] && [ "$alert" -lt "$mod" ] && ok "alert zone comes before the modules" || fail "order: alert=$alert mod=$mod"
sed -n "${alert},${mod}p" "$V" > "$TMP/alert"
grep -q "REG-B" "$TMP/alert" && grep -q "Việc cần làm" "$TMP/alert" && ok "a FAIL is in the alert zone with what to do" || fail "alert: $(cat "$TMP/alert")"
grep -q "Chữ ký sai định dạng" "$TMP/alert" && grep -q "Ký nhiều file" "$TMP/alert" && ok "bug / REQ without a test are in the alert zone" || fail "alert gaps"
grep -q "<details><summary>.*Ký số" "$V" && fail "module with gaps folded" || ok "a module with open work is not folded"
grep -q "| ✅ PASS | REG-A1 |" "$V" && grep -q "exit 0" "$V" && grep -q "evidence/REG-A1" "$V" \
  && ok "test rows carry the run signature (duration · exit · commit · log)" || fail "signature: $(grep REG-A1 "$V")"
grep -q "Sổ tay bug" "$V" && grep -q "Bằng chứng" "$V" && ok "bug ledger with an evidence column" || fail "ledger"

# fold a module once it is 100% PASS
python3 - "$P" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_matrix.active.json"; d = json.load(open(p))
d["rules"][1]["mandatory_regression_tests"][0]["command"] = "true"; json.dump(d, open(p, "w"))
PY
git -C "$P" commit -qam "fix B"; echo 3 > src/b/y.txt
python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
python3 "$RC" render >/dev/null
grep -q "<details><summary>.*Đọc file" "$V" && ok "a module at 100% PASS is folded in <details>" || fail "fold: $(grep -n 'Đọc file' "$V")"

echo "{\"x\":1}" > /dev/null; python3 - "$P" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_matrix.active.json"; d = json.load(open(p)); d["note"] = "edit"; json.dump(d, open(p, "w"))
PY
python3 "$RC" render >/dev/null
grep -m1 "An toàn" "$V" | grep -q "ma trận chờ duyệt: có" && ok "HUD says the matrix waits for review (uncommitted change)" || fail "matrix pending: $(grep -m1 'An toàn' "$V")"
git -C "$P" checkout -q .agents/regression_matrix.active.json

# archive: PASS, proven, linked ≥ 30 days and ≥ 30 commits ago
BUG="$(python3 -c "import json;print([k for k,v in json.load(open('.agents/regression_status.json'))['items'].items() if v.get('kind')=='bug' and v.get('state')!='reported'][0])")"
bash "$KIT" bugs link "$BUG" REG-A1 >/dev/null 2>&1
python3 - "$P" "$BUG" <<'PY'
import json, sys, time
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p)); it = d["items"][sys.argv[2]]
old = time.time() - 31 * 86400
it.update({"linked_ts": old, "linked_at": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(old)), "red_proof": {"status": "PROVEN"}})
json.dump(d, open(p, "w"))
PY
for i in $(seq 1 30); do git -C "$P" commit -q --allow-empty -m "c$i"; done
echo 4 > src/a/x.txt; python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1; git -C "$P" commit -qam run2
python3 "$RC" render >/dev/null
A="$P/.agents/archive/BUG_ARCHIVE.md"
[ -f "$A" ] && grep -q "$BUG" "$A" && ! grep -q "| $BUG |" "$V" && ok "stable bug (≥30 days, ≥30 commits, PASS) → archive view, out of the ledger" \
  || fail "archive: $(cat "$A" 2>/dev/null | tail -3) / $(grep "$BUG" "$V")"
python3 - "$P" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_matrix.active.json"; d = json.load(open(p))
d["rules"][0]["mandatory_regression_tests"][0]["command"] = "false"; json.dump(d, open(p, "w"))
PY
git -C "$P" commit -qam "break A1"; echo 5 > src/a/x.txt
FLAKY_RETRY=0 python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
python3 "$RC" render >/dev/null
alert="$(grep -n "🚨" "$V" | head -1 | cut -d: -f1)"; mod="$(grep -n "^## 🧩" "$V" | head -1 | cut -d: -f1)"
sed -n "${alert},${mod}p" "$V" | grep -q "$BUG" && ok "archived bug whose test turns red is back in the alert zone" || fail "unarchive: $(grep -n "$BUG" "$V")"

[ "$FAILS" -eq 0 ] && echo "✅ test_checklist_view: all passed" || { echo "❌ test_checklist_view: $FAILS failed"; exit 1; }
