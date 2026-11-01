#!/usr/bin/env bash
# A sealed review PASS answers only for the reviewer executables that made it (review of #742 at 14108864, BUG-REV 2ff4519b9f, r23c):
#   the code hash names the models and the skip list but not the reviewers' binaries, so a run with fake reviewers
#   (REVIEW_CLAUDE_BIN / REVIEW_GROK_BIN / REVIEW_AGY_CLI / ANTIGRAVITY_PM_AGY, or another claude / grok / ocr / node first on PATH,
#   or REVIEW_DEEP_LINES raised so a big diff reviews light) landed in the same run dir and its PASS, sealed with the real key,
#   answered --status for the real reviewers.
# Stub reviewers (no LLM, no network): the stubs of test_review_fanout_e2e.sh, sourced from it. $STUB plays the run's reviewers,
# $STUB2 a second copy of the same stubs at another place (the "other" executables). DK_BIN overrides the bin dir (RED run).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${DK_BIN:-$DEVKIT_DIR/bin}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"; mkdir -p "$HOME"   # the seal key of this test only
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
STUB="$TMP/stub"; mkdir -p "$STUB"
sed -n '/^# ocr stub/,/^chmod +x "\$STUB\/ocr"/p' "$DEVKIT_DIR/tests/gates/test_review_fanout_e2e.sh" > "$TMP/stubs.sh"
grep -q '^chmod +x' "$TMP/stubs.sh" || { echo "✖ fixture: stub block not found in test_review_fanout_e2e.sh"; exit 1; }
. "$TMP/stubs.sh"
STUB2="$TMP/stub2"; cp -R "$STUB" "$STUB2"
NODE="$(command -v node)" || { echo "✖ fixture: node not found (the Antigravity stub is a node script)"; exit 1; }
N="$TMP/n"; O="$TMP/o"; X="$TMP/extra"; mkdir -p "$N" "$O" "$X"
ln -s "$NODE" "$N/node"; cp "$STUB/ocr" "$O/ocr"            # another node / another ocr first on PATH
printf '#!/bin/sh\nexit 0\n' > "$TMP/agy"; chmod +x "$TMP/agy"  # an ANTIGRAVITY_PM_AGY binary
unset REVIEW_CLAUDE_MODEL REVIEW_GROK_MODEL REVIEW_AGY_MODEL REVIEW_SKIP_REVIEWERS REVIEW_DEEP_LINES REVIEW_REGRESSION_STATUS ANTIGRAVITY_PM_AGY
export STUB_DIR="$STUB" PATH="$STUB:$PATH" REVIEW_CLAUDE_BIN="$STUB/claude" REVIEW_AGY_CLI="$STUB/agy.js" REVIEW_TIMEOUT_AGY=40 \
  REVIEW_GROK_BIN="$STUB/grok"
F="$BIN/review-fanout.sh"
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q -b main && git config user.email t@t && git config user.name t && echo x > README && git add -A && git commit -qm i)
printf 'def f():\n    return 1\n' > "$P/app.py"
s() { bash "$F" --repo "$P" --base HEAD "$@" --status 2>/dev/null | awk '{print $1}'; }

bash "$F" --repo "$P" --base HEAD > "$TMP/out1" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "fixture: the stub reviewers pass the change" || { fail "fixture: review rc=$rc"; tail -20 "$TMP/out1"; }
H1="$(bash "$F" --repo "$P" --base HEAD --hash)"
st="$(s)"; [ "$st" = PASS ] && ok "control: the same reviewer executables: --status PASS" || fail "control --status $st"

# the PASS does not answer for other reviewer executables (one swap at a time)
for v in "REVIEW_CLAUDE_BIN=$STUB2/claude" "REVIEW_GROK_BIN=$STUB2/grok" "REVIEW_AGY_CLI=$STUB2/agy.js" "ANTIGRAVITY_PM_AGY=$TMP/agy" \
         "PATH=$N:$PATH" "PATH=$O:$PATH" "REVIEW_DEEP_LINES=100000"; do
  st="$(env "$v" bash "$F" --repo "$P" --base HEAD --status 2>/dev/null | awk '{print $1}')"
  l="${v%%:*}"   # PATH: its first entry
  [ "$st" != PASS ] && ok "${l%%=*} → ${l#*=}: the sealed PASS is no verdict (--status $st)" \
    || fail "${l%%=*} → ${l#*=}: a PASS made by other reviewer executables answered PASS"
done
st="$(env "REVIEW_CLAUDE_BIN=$STUB2/claude" bash "$F" --repo "$P" --base HEAD --status 2>/dev/null | awk '{print $1}')"
[ "$st" = NONE ] && ok "other executables: --status says NONE (the review still has to run), not UNSIGNED or FAIL" || fail "other executables: --status $st"

# what does not change the reviewers keeps the verdict (no needless re-review)
[ "$(REVIEW_CLAUDE_BIN="$STUB2/claude" bash "$F" --repo "$P" --base HEAD --hash)" = "$H1" ] \
  && ok "the code hash is unchanged by the reviewer executables (hash-stable)" || fail "the code hash moved with REVIEW_CLAUDE_BIN"
st="$(PATH="$PATH:$X" s)"; [ "$st" = PASS ] && ok "an unrelated PATH entry: still PASS" || fail "unrelated PATH entry: --status $st"
st="$(REVIEW_TIMEOUT_CLAUDE=2400 REVIEW_DEEP_LINES=50 s)"; [ "$st" = PASS ] && ok "a timeout, the default REVIEW_DEEP_LINES: still PASS" \
  || fail "timeout / default deep lines: --status $st"
st="$(env -u REVIEW_CLAUDE_BIN bash "$F" --repo "$P" --base HEAD --status 2>/dev/null | awk '{print $1}')"
[ "$st" = PASS ] && ok "the same claude found on PATH instead of REVIEW_CLAUDE_BIN: still PASS" || fail "same claude via PATH: --status $st"

# a run with the other executables is not answered from the foreign PASS: it reviews again, and that PASS is its own
REVIEW_CLAUDE_BIN="$STUB2/claude" bash "$F" --repo "$P" --base HEAD > "$TMP/out2" 2>&1; rc=$?
[ "$rc" = 0 ] && ! grep -q '(cached:' "$TMP/out2" && ok "other executables: the review runs again (no cached foreign PASS)" \
  || fail "other executables: rc=$rc $(grep -c '(cached:' "$TMP/out2") cached line(s)"
st="$(REVIEW_CLAUDE_BIN="$STUB2/claude" s)"; [ "$st" = PASS ] && ok "...and its PASS answers for them" || fail "re-review --status $st"
st="$(s)"; [ "$st" != PASS ] && ok "...and no longer for the first executables (--status $st)" || fail "re-review PASS answered the first executables"

# a reviewer the run skipped is not part of it: its binary does not matter, the others still do
bash "$F" --repo "$P" --base HEAD --skip grok > "$TMP/out3" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "fixture: reduced run (--skip grok) passes" || { fail "fixture: reduced run rc=$rc"; tail -10 "$TMP/out3"; }
st="$(REVIEW_GROK_BIN="$STUB2/grok" s --skip grok)"; [ "$st" = PASS_REDUCED ] && ok "skipped grok: another grok binary keeps PASS_REDUCED" \
  || fail "skipped grok binary changed the reduced verdict: $st"
st="$(REVIEW_CLAUDE_BIN="$STUB2/claude" s --skip grok)"; [ "$st" != PASS_REDUCED ] && ok "reduced run: another claude is no verdict (--status $st)" \
  || fail "reduced PASS answered for another claude"

# a FAIL stays a FAIL whoever asks (it never lets anything through)
echo p1 > "$STUB/claude.mode"; printf 'def g(items):\n    return items[0]\n' > "$P/app.py"
bash "$F" --repo "$P" --base HEAD > "$TMP/out4" 2>&1; rc=$?
[ "$rc" = 1 ] && ok "fixture: cited P1 → FAIL" || { fail "fixture: P1 run rc=$rc"; tail -10 "$TMP/out4"; }
st="$(REVIEW_CLAUDE_BIN="$STUB2/claude" s)"; [ "$st" = FAIL ] && ok "a FAIL answers FAIL for other executables too" || fail "FAIL hidden: --status $st"
[ "$FAILS" = 0 ] && { echo "review runtime binding: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
