#!/usr/bin/env bash
# hooks/review_gate.sh REVIEW_GATE_OCR=full after #742 (31/10/2026): the switch no longer starts a background OpenCodeReview and an
# OCR report can no longer pass a Stop (Stop 3 of the old flow: findings shown to the session = the review). Only the signed
# unanimous 4-way verdict of exactly the current code passes (bin/review-fanout.sh, tests/gates/test_review_gate_4way.sh).
# The file keeps its old path because post-fix-gate cannot cross-review a deleted existing test (#763).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*, REVIEW_GATE_AUTOSTART=0
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"   # this test's own summary seal key
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo "def f(): return 1" > app.py && git add -A && git commit -qm i)
P="$(cd "$P" && pwd -P)"

# fake ocr / ocr-review: every call is logged, a review writes a report with one finding
mkdir -p "$TMP/bin"
for n in ocr ocr-review; do
  cat > "$TMP/bin/$n" <<SH
#!/bin/sh
echo "$n \$*" >> "$TMP/ocr-calls"
out=""; while [ \$# -gt 0 ]; do case "\$1" in -o|--out) out="\$2" ;; esac; shift; done
[ -n "\$out" ] && mkdir -p "\$out" 2>/dev/null; [ -d "\$out" ] && printf '{"comments":[{"path":"app.py","line":1,"severity":"high","message":"x"}]}\n' > "\$out/ocr-review.json"
exit 0
SH
  chmod +x "$TMP/bin/$n"
done

TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys, datetime
tr, tid, path = sys.argv[1:4]
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
c = {"type": "tool_use", "id": tid, "name": "Edit", "input": {"file_path": path, "old_string": "1", "new_string": "2"}}
with open(tr, "a") as f:
    f.write(json.dumps({"type": "assistant", "timestamp": stamp, "message": {"role": "assistant", "content": [c]}}) + "\n")
PY
stop() { printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop"}' "$1" "$TR" \
  | PATH="$TMP/bin:$PATH" REVIEW_GATE_OCR=full CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; }
F="$DEVKIT_DIR/bin/review-fanout.sh"
rundir() { echo "$(cd "$P" && git rev-parse --git-common-dir | sed "s|^\.git$|$P/.git|")/review-fanout/$(env -u REVIEW_SKIP_REVIEWERS bash "$F" --repo "$P" --base merge-base --hash)"; }

echo "def f(): return 2" > "$P/app.py"; : > "$TR"; python3 "$TMP/ev.py" "$TR" e1 "$P/app.py"
: > "$TMP/ocr-calls"
for s in 1 2 3; do
  stop s1; rc=$?
  [ "$rc" = 2 ] || { fail "REVIEW_GATE_OCR=full, stop $s: rc $rc (the old flow passed at stop 3)"; break; }
done
[ "$rc" = 2 ] && ok "REVIEW_GATE_OCR=full: stops 1-3 of the old flow all block (rc 2)"
stop s2; rc=$?
[ "$rc" = 2 ] && ok "REVIEW_GATE_OCR=full, a second session: blocked (rc 2)" || fail "second session passed (rc $rc)"
grep -q "review-fanout.sh" "$TMP/err" && ok "the block message names the 4-way review" || fail "no 4-way review in the message: $(tail -3 "$TMP/err" | tr '\n' ' ')"
sleep 1
[ ! -s "$TMP/ocr-calls" ] && ok "no OCR review started in the background" || fail "the gate started ocr: $(cat "$TMP/ocr-calls")"
[ -z "$(ls -d "$P/.git/ocr-review/full-"* 2>/dev/null)" ] && ok "no <git dir>/ocr-review/full-* run folder" || fail "full run folder made: $(ls -d "$P/.git/ocr-review/full-"*)"
[ -z "$(git -C "$P" status --porcelain -- . ':!app.py')" ] && ok "repo untouched by the gate" || fail "stray files: $(git -C "$P" status --porcelain)"

# control (the blocks above are not vacuous): the signed 4-way PASS of this exact code passes with the switch on
d="$(rundir)"; mkdir -p "$d"
printf '{"verdict":"PASS","reasons":[],"meta":{"code_hash":"%s"}}' "${d##*/}" > "$d/summary.json"; printf '# 4-way review: PASS\n' > "$d/summary.md"
python3 "$DEVKIT_DIR/bin/review_sign.py" sign "$d/summary.json"
stop s1; rc=$?
[ "$rc" = 0 ] && ok "REVIEW_GATE_OCR=full, signed 4-way PASS for this exact code: passes (rc 0)" || fail "4-way PASS not honoured rc=$rc $(cat "$TMP/err")"

[ "$FAILS" = 0 ] && echo "review_gate OCR full (after #742): all checks passed" || { echo "review_gate OCR full: $FAILS failed"; exit 1; }
