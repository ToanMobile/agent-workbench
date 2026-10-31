#!/usr/bin/env bash
# hooks/review_gate.sh + OpenCodeReview after #742 (31/10/2026): OCR alone is no longer a review. Until #742 a successful OCR run
# after the last edit (the helper's `mode: review` + `report:`, or a plain `ocr review … -o <report>`) passed the Stop; now only the
# signed unanimous 4-way verdict of exactly the current code does (bin/review-fanout.sh, tests/gates/test_review_gate_4way.sh).
# The old cases that said "this OCR run does not count" are true of every OCR run now; the ones that said "it counts" are reversed
# here. The file keeps its old path because post-fix-gate cannot cross-review a deleted existing test (#763).
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

# fake ocr: a review succeeds with a report, delegation works; every call is logged
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<SH
#!/bin/sh
echo "ocr \$*" >> "$TMP/ocr-calls"
case "\$1" in
  review) out=""; while [ \$# -gt 0 ]; do [ "\$1" = -o ] && out="\$2"; shift; done; [ -n "\$out" ] && printf '{"comments":[]}\n' > "\$out"; exit 0 ;;
  delegate) printf '{"schema_version":"1","reviewable_count":1,"reviewable_files":[{"path":"app.py"}]}\n'; exit 0 ;;
esac
exit 9
SH
chmod +x "$TMP/bin/ocr"

TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys, datetime
kind, tr = sys.argv[1], sys.argv[2]
a = sys.argv[3:]
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
if kind == "edit":
    m = {"role": "assistant", "content": [{"type": "tool_use", "id": a[0], "name": "Edit",
                                          "input": {"file_path": a[1], "old_string": "1", "new_string": "2"}}]}
elif kind == "bash":
    m = {"role": "assistant", "content": [{"type": "tool_use", "id": a[0], "name": "Bash", "input": {"command": a[1]}}]}
elif kind == "result":
    m = {"role": "user", "content": [{"type": "tool_result", "tool_use_id": a[0], "is_error": False, "content": a[1]}]}
rec = {"type": m["role"], "timestamp": stamp, "message": m}
with open(tr, "a") as f:
    f.write(json.dumps(rec) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
stop() { printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" \
  | PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$P" ${1:+env "$@"} bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; }
F="$DEVKIT_DIR/bin/review-fanout.sh"
rundir() { echo "$(cd "$P" && git rev-parse --git-common-dir | sed "s|^\.git$|$P/.git|")/review-fanout/$(env -u REVIEW_SKIP_REVIEWERS bash "$F" --repo "$P" --base merge-base --hash)"; }

echo "def f(): return 2" > "$P/app.py"; mkdir -p "$TMP/rep"
: > "$TR"; ev edit e1 "$P/app.py"
stop; rc=$?
[ "$rc" = 2 ] && grep -q "review-fanout.sh" "$TMP/err" && ok "unreviewed edit: blocked, the message names the 4-way review (rc 2)" \
  || fail "unreviewed edit: rc $rc $(tail -3 "$TMP/err" | tr '\n' ' ')"

# reversed by #742: a successful OCR review after the edit no longer passes
printf '{"comments":[]}\n' > "$TMP/rep/ocr-review.json"
ev bash b1 ".agents/devkit/bin/ocr-review"; ev result b1 "$(printf 'mode: review\nreport: %s' "$TMP/rep/ocr-review.json")"
stop; rc=$?
[ "$rc" = 2 ] && ok "ocr-review in review mode with a report after the edit: still blocked (rc 2)" || fail "helper OCR review passed (rc $rc)"
ev bash b2 "ocr review --format json -o $TMP/rep/plain.json"; ev result b2 ''
PATH="$TMP/bin:$PATH" ocr review --format json -o "$TMP/rep/plain.json"
stop; rc=$?
[ "$rc" = 2 ] && ok "a successful plain ocr review -o <report> after the edit: still blocked (rc 2)" || fail "plain OCR review passed (rc $rc)"
stop REVIEW_GATE_REQUIRE_OCR=0; rc=$?
[ "$rc" = 2 ] && ok "REVIEW_GATE_REQUIRE_OCR=0 does not release the gate (rc 2)" || fail "REVIEW_GATE_REQUIRE_OCR=0 released (rc $rc)"
stop REVIEW_GATE_OCR=0; rc=$?
[ "$rc" = 2 ] && ok "REVIEW_GATE_OCR=0 does not release the gate (rc 2)" || fail "REVIEW_GATE_OCR=0 released (rc $rc)"
: > "$TMP/ocr-calls"; stop; rc=$?
[ ! -s "$TMP/ocr-calls" ] && ok "a blocked Stop runs no OCR delegation of its own" || fail "the gate ran ocr: $(cat "$TMP/ocr-calls")"
[ -z "$(git -C "$P" status --porcelain -- . ':!app.py')" ] && ok "repo untouched by the gate" || fail "stray files: $(git -C "$P" status --porcelain)"

# control (the cases above are not vacuous): the signed 4-way PASS of this exact code passes, OCR runs in the transcript or not
d="$(rundir)"; mkdir -p "$d"
printf '{"verdict":"PASS","reasons":[],"meta":{"code_hash":"%s"}}' "${d##*/}" > "$d/summary.json"; printf '# 4-way review: PASS\n' > "$d/summary.md"
python3 "$DEVKIT_DIR/bin/review_sign.py" sign "$d/summary.json"
stop; rc=$?
[ "$rc" = 0 ] && ok "signed 4-way PASS for this exact code: passes (rc 0)" || fail "4-way PASS not honoured rc=$rc $(cat "$TMP/err")"

[ "$FAILS" = 0 ] && echo "review_gate OCR (after #742): all checks passed" || { echo "review_gate OCR: $FAILS failed"; exit 1; }
