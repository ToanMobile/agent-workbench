#!/usr/bin/env bash
# super-board-merge-gate.sh and the signed review verdict (2/2 review of #742, 31/10/2026, r14d):
#   BUG-REV-76e3be1a9d (F1) the gate accepted a sealed summary that names no code_hash (the old "nothing to review" shape): copied into
#     the PR head's run dir it merged an unreviewed PR
#   BUG-REV-37b922ce04 (F7) a machine-gated PR with a light review was voided forever: nothing ever produced a deep review of that
#     head; now the gate marks the head deep-heads/<sha>, every later review of it runs deep (its own code hash), the gate asks for that
# The fixture (repo, PRs 5 and 7, fake gh, gate(), verdict(), hash_of()) is the head of test_merge_gate_review_ci_hardening.sh up to its
# first case, read from that file (never edited here). SB_GATE_UNDER_TEST overrides the gate (RED run: the previous commit's copy).
set -u
HERE_T="$(cd "$(dirname "$0")" && pwd)"
FIX="$(mktemp "${TMPDIR:-/tmp}/sb-binding-fixture.XXXXXX")"
sed -n '1,/^# ── R1/p' "$HERE_T/test_merge_gate_review_ci_hardening.sh" > "$FIX"
grep -q '^gate() {' "$FIX" && grep -q '^verdict() {' "$FIX" || { echo "✖ fixture: gate()/verdict() not found in the hardening test"; rm -f "$FIX"; exit 1; }
. "$FIX"; rm -f "$FIX"
[ -n "${SB_GATE_UNDER_TEST:-}" ] && cp "$SB_GATE_UNDER_TEST" "$GATE"
[ -n "${DK_BIN:-}" ] && { rm -f "$WB/universal-agent-devkit"; ln -s "$(cd "$DK_BIN/.." && pwd -P)" "$WB/universal-agent-devkit"; DK="$DK_BIN"; }
DEEP="$COMMON/review-fanout/deep-heads"

# F1: a sealed summary with no meta.code_hash in the PR head's run dir is no verdict for that head
clear_verdicts; rm -rf "$DEEP"
h=$(hash_of "$H5"); run="$COMMON/review-fanout/$h"; mkdir -p "$run"
python3 - "$DK/review_sign.py" "$run/summary.json" <<'PY'
import importlib.util, json, sys
sp = importlib.util.spec_from_file_location("rs", sys.argv[1]); rs = importlib.util.module_from_spec(sp); sp.loader.exec_module(rs)
data = json.dumps({"verdict": "PASS", "reasons": [], "note": "nothing to review"}).encode()
open(sys.argv[2], "wb").write(data)
open(sys.argv[2] + ".sig", "w").write(rs._mac(rs.load_key(create=True), data) + "\n")
PY
gate 5 "$GATE" --
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && ok "F1 sealed summary without code_hash: exit 6, no merge" || fail "F1 no code_hash: $(why)"
# control: the same head with a sealed PASS that names its code state merges
clear_verdicts; verdict "$H5" "" PASS light ok pass sign
gate 5 "$GATE" --
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && ok "F1 control: sealed PASS naming the head's code state merges" || fail "F1 control: $(why)"

# F7: machine-gated PR (auth path), light PASS → the head is marked deep, the next review of it is deep, then it merges
clear_verdicts; rm -rf "$DEEP"
H7_LIGHT=$(hash_of "$H7")
verdict "$H7" "" PASS light ok pass sign
gate 7 "$GATE" --
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && ok "F7 gated PR + light PASS: exit 6, no merge" || fail "F7 light: $(why)"
[ -e "$DEEP/$H7" ] && ok "F7 the gate marked the head for a deep review" || fail "F7 no deep-heads marker for $H7"
grep -q -- '--depth deep' "$TMP/err" && ok "F7 the void reason names --depth deep" || fail "F7 reason: $(tail -2 "$TMP/err" | tr '\n' ' ')"
H7_DEEP=$(hash_of "$H7")
[ "$H7_DEEP" != "$H7_LIGHT" ] && ok "F7 a review of the marked head is another code state (forced deep)" || fail "F7 marker did not change the hash"
mb7=$(git -C "$R" merge-base "$H7" origin/main)
d=$(cd "$W/hash-$H7-full" && bash "$DK/review-fanout.sh" --repo "$W/hash-$H7-full" --base "$mb7" --depth deep --hash)
[ "$d" = "$H7_DEEP" ] && ok "F7 --depth deep and the marker name the same code state" || fail "F7 --depth deep hash $d != $H7_DEEP"
verdict "$H7" "" PASS deep ok pass sign
gate 7 "$GATE" --
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && [ -e "$TMP/extra" ] && ok "F7 deep PASS of the marked head: merged" || fail "F7 deep merge: $(why)"
# a light summary planted under the forced-deep hash is still not enough
clear_verdicts; verdict "$H7" "" PASS light ok pass sign
gate 7 "$GATE" --
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && ok "F7 light summary under the forced hash: exit 6" || fail "F7 light under forced: $(why)"
# an ungated PR never gets a marker
clear_verdicts; verdict "$H5" "" PASS light ok pass sign
gate 5 "$GATE" --
[ "$RC" -eq 0 ] && [ ! -e "$DEEP/$H5" ] && ok "F7 ungated PR: light PASS merges, no marker" || fail "F7 ungated: $(why) marker=$(ls "$DEEP" 2>/dev/null)"
if [ "$FAILS" -eq 0 ]; then echo "merge gate review binding: all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
