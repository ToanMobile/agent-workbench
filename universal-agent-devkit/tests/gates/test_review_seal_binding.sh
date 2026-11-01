#!/usr/bin/env bash
# A signed review verdict answers only for the code state it was made for (2/2 review of #742, 31/10/2026, r14d):
#   BUG-REV-7b0abde38e (F12) `--status` checked the seal, then read the verdict in a second open and never compared the summary's
#     code_hash with the code being asked about: a signed PASS copied into another run dir answered PASS there
#   BUG-REV-76e3be1a9d (F1, fanout side) the "nothing to review" summary carried no meta.code_hash at all
#   BUG-REV-738b4fa129 (F4, signer side) review_sign.py signed any file it was pointed at
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
F="$DK/bin/review-fanout.sh"; S="$DK/bin/review_sign.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"; mkdir -p "$HOME"   # the seal key of this test only
unset REVIEW_SKIP_REVIEWERS REVIEW_CLAUDE_MODEL REVIEW_GROK_MODEL REVIEW_AGY_MODEL
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && echo x > README && git add -A && git commit -qm i)
COMMON="$P/.git"

# 1. nothing to review: the sealed PASS names the code state it answers for
H1="$(bash "$F" --repo "$P" --base HEAD --hash)"
bash "$F" --repo "$P" --base HEAD >/dev/null 2>&1
R1="$COMMON/review-fanout/$H1"
got="$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("meta") or {}).get("code_hash",""))' "$R1/summary.json" 2>/dev/null)"
[ "$got" = "$H1" ] && ok "nothing-to-review summary carries meta.code_hash" || fail "nothing-to-review summary has code_hash '$got' (want $H1)"
st="$(bash "$F" --repo "$P" --base HEAD --status | awk '{print $1}')"
[ "$st" = PASS ] && ok "its own code state: --status PASS" || fail "own state: --status $st"

# 2. the same sealed PASS copied into the run dir of another code state is no verdict there
echo 'def f(): return 1' > "$P/app.py"
H2="$(bash "$F" --repo "$P" --base HEAD --hash)"
[ "$H2" != "$H1" ] || fail "fixture: the change did not move the hash"
mkdir -p "$COMMON/review-fanout/$H2"; cp "$R1/summary.json" "$R1/summary.json.sig" "$R1/summary.md" "$COMMON/review-fanout/$H2/"
st="$(bash "$F" --repo "$P" --base HEAD --status | awk '{print $1}')"; rc=$?
[ "$st" != PASS ] && ok "a sealed PASS of another code state is no verdict (--status $st)" || fail "copied PASS answered PASS for another code state"
# an old-format sealed summary (no meta at all) copied in: no verdict either
python3 - "$S" "$COMMON/review-fanout/$H2/summary.json" <<'PY'
import importlib.util, json, sys
sp = importlib.util.spec_from_file_location("rs", sys.argv[1]); rs = importlib.util.module_from_spec(sp); sp.loader.exec_module(rs)
p = sys.argv[2]
data = json.dumps({"verdict": "PASS", "reasons": [], "note": "nothing to review"}).encode()
open(p, "wb").write(data)
open(p + ".sig", "w").write(rs._mac(rs.load_key(create=True), data) + "\n")
PY
st="$(bash "$F" --repo "$P" --base HEAD --status | awk '{print $1}')"
[ "$st" != PASS ] && ok "a sealed summary with no code_hash is no verdict (--status $st)" || fail "summary without code_hash answered PASS"

# 3. the signer seals only a review run's own summary: <git dir>/review-fanout/<code_hash>/summary.json whose meta.code_hash is that dir
mkdir -p "$TMP/x"; printf '{"verdict":"PASS","meta":{"code_hash":"%s"}}' "$H2" > "$TMP/x/summary.json"
python3 "$S" sign "$TMP/x/summary.json" >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && [ ! -e "$TMP/x/summary.json.sig" ] && ok "sign refuses a summary outside review-fanout/<hash>/" || fail "signed an arbitrary file (rc=$rc)"
D="$COMMON/review-fanout/$H2"; rm -f "$D/summary.json.sig"
printf '{"verdict":"PASS","meta":{"code_hash":"%s"}}' "$H1" > "$D/summary.json"
python3 "$S" sign "$D/summary.json" >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && [ ! -e "$D/summary.json.sig" ] && ok "sign refuses a summary whose code_hash is not its run dir" || fail "signed a mismatched code_hash (rc=$rc)"
printf '{"verdict":"PASS","meta":{"code_hash":"%s"}}' "$H2" > "$D/summary.json"
python3 "$S" sign "$D/summary.json" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -s "$D/summary.json.sig" ] && ok "control: a run's own summary is sealed" || fail "control sign failed rc=$rc"
st="$(bash "$F" --repo "$P" --base HEAD --status | awk '{print $1}')"
[ "$st" = PASS ] && ok "control: its own sealed PASS answers --status PASS" || fail "control --status $st"
# the merge gate verifies a COPY of the summary: the seal still checks out away from the run dir
cp "$D/summary.json" "$D/summary.json.sig" "$TMP/x/"
out="$(bash "$F" --verify-summary "$TMP/x/summary.json")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "PASS $H2" ] && ok "--verify-summary on a copy: 'PASS <code_hash>'" || fail "--verify-summary rc=$rc out=$out"
[ "$FAILS" = 0 ] && { echo "review seal binding: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
