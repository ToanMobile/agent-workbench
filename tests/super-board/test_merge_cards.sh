#!/usr/bin/env bash
# super-board-merge-cards.py: chép AC nguyên văn vào thẻ giữ, đóng thẻ nguồn (not planned).
# Lần chạy sau không nhân đôi mục AC. PR mở head issue-<n>- → exit 3 và không ghi.
# gh giả, offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/.claude/bin/super-board-merge-cards.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-merge-cards.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export FAKE_STATE="$TMP/state.json" FAKE_LOG="$TMP/calls.jsonl" FAKE_PRS="$TMP/prs.json"
printf '%s\n' '[]' > "$FAKE_PRS"
python3 - <<'PY'
import json, os
keeper = """## Problem
giữ

## Acceptance Criteria
- [ ] AC giữ

## Fix
sửa giữ

## Risk
🟢
"""
src = """## Problem
nguồn tám

## Acceptance Criteria
- [ ] AC tám nguyên văn

## Fix
sửa tám

## Risk
🟢
"""
src9 = """## Problem
nguồn chín

## Acceptance Criteria
- [ ] AC chín nguyên văn

## Fix
sửa chín
"""
json.dump({"issues": {
    "7": {"title": "thẻ giữ", "body": keeper, "state": "OPEN"},
    "8": {"title": "thẻ tám", "body": src, "state": "OPEN"},
    "9": {"title": "thẻ chín", "body": src9, "state": "OPEN"},
}}, open(os.environ["FAKE_STATE"], "w"))
PY
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps(a, ensure_ascii=False) + "\n")
state = json.load(open(os.environ["FAKE_STATE"]))
def save():
    json.dump(state, open(os.environ["FAKE_STATE"], "w"))
if a[:2] == ["pr", "list"]:
    print(open(os.environ["FAKE_PRS"]).read()); sys.exit(0)
if a[:2] == ["issue", "view"]:
    iss = state["issues"][a[2]]
    print(json.dumps({"title": iss["title"], "body": iss["body"], "state": iss["state"]}))
    sys.exit(0)
if a[:2] == ["issue", "edit"]:
    state["issues"][a[2]]["body"] = a[a.index("--body") + 1]
    save(); sys.exit(0)
if a[:2] == ["issue", "comment"]:
    sys.exit(0)
if a[:2] == ["issue", "close"]:
    state["issues"][a[2]]["state"] = "CLOSED"
    save(); sys.exit(0)
sys.stderr.write("unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
: > "$FAKE_LOG"
python3 "$SCRIPT" --repo ToanMobile/Synthetic --into 7 --absorb 8,9 >"$TMP/out.json" 2>"$TMP/err"
rc=$?
body=$(python3 -c 'import json,os; print(json.load(open(os.environ["FAKE_STATE"]))["issues"]["7"]["body"])')
[ "$rc" = 0 ] && printf '%s\n' "$body" | grep -qxF -- "- [ ] AC tám nguyên văn" \
  && printf '%s\n' "$body" | grep -qxF -- "- [ ] AC chín nguyên văn" \
  && printf '%s\n' "$body" | grep -qxF -- "- [ ] AC giữ" \
  && printf '%s\n' "$body" | grep -qF '<!-- sb:gom #8 -->' \
  && printf '%s\n' "$body" | grep -qF '<!-- sb:gom #9 -->' \
  && ! printf '%s\n' "$body" | grep -qF 'xem thẻ' \
  && ok "AC #8 và #9 chép nguyên văn vào #7" || fail "fold rc=$rc body không đủ AC ($(head -c 200 "$TMP/err"))"
python3 - <<'PY' && ok "đóng #8 và #9, reason not planned" || fail "close: $(cat "$FAKE_LOG")"
import json, os
calls = [json.loads(l) for l in open(os.environ["FAKE_LOG"])]
closed = [c for c in calls if c[:2] == ["issue", "close"]]
nums = sorted(c[2] for c in closed)
reasons = [c[c.index("--reason") + 1] for c in closed if "--reason" in c]
raise SystemExit(0 if nums == ["8", "9"] and reasons == ["not planned", "not planned"] else 1)
PY
edits=$(python3 -c 'import json,os; print(sum(1 for l in open(os.environ["FAKE_LOG"]) if json.loads(l)[:2]==["issue","edit"]))')
: > "$FAKE_LOG"
python3 "$SCRIPT" --repo ToanMobile/Synthetic --into 7 --absorb 8,9 >"$TMP/out2.json" 2>"$TMP/err2"
rc2=$?
edits2=$(python3 -c 'import json,os; print(sum(1 for l in open(os.environ["FAKE_LOG"]) if json.loads(l)[:2]==["issue","edit"]))')
count=$(printf '%s\n' "$body" | grep -c 'AC tám nguyên văn')
body2=$(python3 -c 'import json,os; print(json.load(open(os.environ["FAKE_STATE"]))["issues"]["7"]["body"])')
count2=$(printf '%s\n' "$body2" | grep -c 'AC tám nguyên văn')
[ "$rc2" = 0 ] && [ "$edits2" = 0 ] && [ "$count2" = "$count" ] && [ "$count" = 1 ] \
  && ok "lần hai: không sửa body, AC không nhân đôi (lần một edit=$edits)" || fail "lần hai rc=$rc2 edits=$edits2 count=$count2"
printf '%s\n' '[{"headRefName":"issue-8-wip"}]' > "$FAKE_PRS"
# mở lại #8 để chứng minh exit 3 không đóng
python3 - <<'PY'
import json, os
s = json.load(open(os.environ["FAKE_STATE"]))
s["issues"]["8"]["state"] = "OPEN"
json.dump(s, open(os.environ["FAKE_STATE"], "w"))
PY
before=$(python3 -c 'import json,os; print(json.load(open(os.environ["FAKE_STATE"]))["issues"]["7"]["body"])')
: > "$FAKE_LOG"
python3 "$SCRIPT" --repo ToanMobile/Synthetic --into 7 --absorb 8 >"$TMP/out3.json" 2>"$TMP/err3"
rc3=$?
after=$(python3 -c 'import json,os; print(json.load(open(os.environ["FAKE_STATE"]))["issues"]["7"]["body"])')
state8=$(python3 -c 'import json,os; print(json.load(open(os.environ["FAKE_STATE"]))["issues"]["8"]["state"])')
writes=$(python3 -c 'import json,os; print(sum(1 for l in open(os.environ["FAKE_LOG"]) if json.loads(l)[:2] in (["issue","edit"],["issue","close"],["issue","comment"])))')
[ "$rc3" = 3 ] && [ "$before" = "$after" ] && [ "$state8" = OPEN ] && [ "$writes" = 0 ] \
  && ok "PR issue-8-* đang mở: exit 3, không ghi" || fail "started rc=$rc3 state8=$state8 writes=$writes"
[ "$FAILS" -eq 0 ] && { echo PASS; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
