#!/usr/bin/env bash
# hooks/review_gate.sh (31/10/2026): the ONLY review that passes a Stop is the unanimous 4-way review of exactly the current code
# (bin/review-fanout.sh: Claude Code + Alibaba OCR + Antigravity). An agent review or an OCR run alone does not; a FAIL or a running
# review blocks; a code change after a PASS re-arms; there is no anti-loop release and the gate fails closed. With autostart on it
# starts the review in the background itself (stub reviewers here, no LLM).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"   # this test's own summary seal key
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo "def f(): return 1" > app.py && git add -A && git commit -qm i)
P="$(cd "$P" && pwd -P)"
TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys, time, datetime
kind, tr = sys.argv[1], sys.argv[2]
a = sys.argv[3:]
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
if kind == "edit":
    c = {"type": "tool_use", "id": a[0], "name": "Edit", "input": {"file_path": a[1], "old_string": "1", "new_string": "2"}}
elif kind == "agent":
    c = {"type": "tool_use", "id": a[0], "name": "Agent", "input": {"subagent_type": "principal-code-reviewer", "prompt": "review"}}
elif kind == "skill":
    c = {"type": "tool_use", "id": a[0], "name": "Skill", "input": {"skill": "open-code-review"}}
rec = {"type": "assistant", "timestamp": stamp, "message": {"role": "assistant", "content": [c]}}
with open(tr, "a") as f:
    f.write(json.dumps(rec) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
stop() { printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" \
  | CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; }
F="$DEVKIT_DIR/bin/review-fanout.sh"
rundir() { echo "$(cd "$P" && git rev-parse --git-common-dir | sed "s|^\.git$|$P/.git|")/review-fanout/$(env -u REVIEW_SKIP_REVIEWERS bash "$F" --repo "$P" --base merge-base --hash)"; }
verdict() { d="$(rundir)"; mkdir -p "$d"; printf '{"verdict":"%s","reasons":["%s"]}' "$1" "${2:-}" > "$d/summary.json"; printf '# 4-way review: %s\n- %s\n' "$1" "${2:-}" > "$d/summary.md"
  python3 "$DEVKIT_DIR/bin/review_sign.py" sign "$d/summary.json"; }   # a real review seals its summary (bin/review_sign.py)

echo "def f(): return 2" > "$P/app.py"; ev edit e1 "$P/app.py"
stop; rc=$?
[ "$rc" = 2 ] && grep -q "chưa có review 4 bên" "$TMP/err" && ok "edited code, no 4-way review: blocked" || fail "not blocked rc=$rc $(cat "$TMP/err")"
[ ! -d "$(rundir)" ] && ok "REVIEW_GATE_AUTOSTART=0 (tests): no real reviewer started" || fail "autostart ran in a test"
# BUG-REV-review-gate-fanout-child: a reviewer started by review-fanout (REVIEW_FANOUT_CHILD=1) is not gated (no nested review)
printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" \
  | REVIEW_FANOUT_CHILD=1 CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$(rundir)" ] && ok "a review-fanout reviewer's own Stop is not gated" || fail "fanout child gated rc=$rc"
# BUG-REV-review-gate-repo-first: the project the hook resolved wins over a payload cwd in another (clean) repo
O="$TMP/other"; git init -q "$O" && git -C "$O" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"Stop","cwd":"%s"}' "$TR" "$O" \
  | CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && ok "payload cwd in another repo: the project's edited code is still gated" || fail "cwd elsewhere released the gate rc=$rc"
ev agent a1; stop; [ $? = 2 ] && ok "an agent review alone does not pass" || fail "agent review alone passed"
ev skill k1; stop; [ $? = 2 ] && ok "the open-code-review skill alone does not pass" || fail "skill alone passed"
for i in 1 2 3 4 5; do stop; [ $? = 2 ] || { fail "stop $i released (anti-loop release is gone)"; break; }; done; [ "$i" = 5 ] && ok "no release after repeated blocks"

verdict FAIL "antigravity: timeout — no audit"
stop; rc=$?
[ "$rc" = 2 ] && grep -q "KHÔNG PASS" "$TMP/err" && grep -q "antigravity: timeout" "$TMP/err" && ok "4-way FAIL: blocked with the reasons" \
  || fail "FAIL summary not shown rc=$rc"
rm -rf "$(rundir)"; mkdir -p "$(rundir)"; sleep 60 & echo $! > "$(rundir)/pid"
stop; rc=$?; kill %1 2>/dev/null; wait 2>/dev/null
[ "$rc" = 2 ] && grep -q "đang chạy" "$TMP/err" && ok "4-way review running: blocked" || fail "running not blocked rc=$rc"
rm -f "$(rundir)/pid"
verdict PASS
stop; [ $? = 0 ] && ok "unanimous 4-way PASS for this exact code: passes" || fail "PASS not honoured: $(cat "$TMP/err")"
echo "def f(): return 3" > "$P/app.py"; ev edit e2 "$P/app.py"
stop; [ $? = 2 ] && ok "code changed after the PASS: blocked again" || fail "stale PASS reused"

printf 'not json' | CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && ok "unreadable payload: fail-closed (blocked)" || fail "unreadable payload passed rc=$rc"
mkdir -p "$TMP/lone"; cp -R "$DEVKIT_DIR/hooks" "$TMP/lone/hooks"   # the hooks without the kit's bin/
printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" | CLAUDE_PROJECT_DIR="$P" bash "$TMP/lone/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && grep -q "review-fanout.sh" "$TMP/err" && ok "no review-fanout.sh next to the hook: fail-closed (rc 2)" || fail "missing fanout passed rc=$rc"

# autostart on, stub reviewers: the gate starts the review, a later Stop passes once all 4 said pass
STUB="$TMP/stub"; mkdir -p "$STUB"
printf '#!/usr/bin/env bash\nout=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done\n[ -n "$out" ] && printf %s > "$out"\n' \
  "'"'{"status":"completed","comments":[],"manifest":{"coverage":{"completed":["a"],"failed":[]}},"summary":{"total_tokens":1}}'"'" > "$STUB/ocr"
printf '#!/usr/bin/env bash\ncat >/dev/null\necho %s\n' "'"'{"type":"result","is_error":false,"result":"{\"verdict\":\"pass\",\"findings\":[]}","total_cost_usd":0,"usage":{"input_tokens":1,"output_tokens":1},"modelUsage":{"claude-opus-4-5":{"outputTokens":1}}}'"'" > "$STUB/claude"
printf '#!/usr/bin/env bash\necho %s\n' "'"'{"text":"{\"verdict\":\"pass\",\"findings\":[]}","usage":{"total_tokens":1},"modelUsage":{"grok-4.7":{"outputTokens":1}}}'"'" > "$STUB/grok"
# the gate strips REVIEW_*_BIN / REVIEW_AGY_CLI (BUG-REV-gate-env-allowlist): the stubs are found on PATH; `node` is stubbed for
# the Antigravity runner (it runs `node <pm-review-audit.js> … --out F --model M`)
cat > "$STUB/node" <<'SH'
#!/usr/bin/env bash
out=""; m=""; while [ $# -gt 0 ]; do case "$1" in --out) out="$2" ;; --model) m="$2" ;; esac; shift; done
printf '{"reviewer":"antigravity","status":"ok","verdict":"pass","findings":[],"model":"%s"}' "$m" > "$out"
SH
chmod +x "$STUB/ocr" "$STUB/claude" "$STUB/grok" "$STUB/node"
unset REVIEW_CLAUDE_MODEL REVIEW_GROK_MODEL REVIEW_AGY_MODEL
export PATH="$STUB:$PATH"
# inherited overrides the gate must NOT pass on: a skip list, a fake reviewer binary
export REVIEW_SKIP_REVIEWERS=grok,ocr REVIEW_CLAUDE_BIN=/nonexistent/claude REVIEW_AGY_CLI=/nonexistent/agy.js
REVIEW_GATE_AUTOSTART=1 stop; rc=$?
[ "$rc" = 2 ] && grep -q "Khởi động ở nền: review-fanout: started" "$TMP/err" && ok "autostart: the gate started the 4-way review and blocked" \
  || fail "autostart did not start rc=$rc $(cat "$TMP/err")"
for _ in $(seq 1 60); do [ -f "$(rundir)/summary.json" ] && break; sleep 0.5; done
REVIEW_GATE_AUTOSTART=1 stop; rc=$?
[ "$rc" = 0 ] && ok "after the background review PASSED, the Stop passes" || fail "background PASS not honoured rc=$rc $(cat "$TMP/err"; cat "$(rundir)/fanout.log" 2>/dev/null | tail -5)"
python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); sys.exit(0 if not m.get("reduced") and "grok" in m["required"] else 1)' "$(rundir)/meta.json" \
  && ok "inherited REVIEW_SKIP_REVIEWERS / REVIEW_*_BIN do not reach the gate's review (full 4-way, real binaries)" || fail "gate review was reduced: $(cat "$(rundir)/meta.json")"
unset REVIEW_SKIP_REVIEWERS REVIEW_CLAUDE_BIN REVIEW_AGY_CLI
# BUG-REV-review-summary-hmac: a summary.json the agent wrote itself is no verdict
printf '{"verdict":"PASS","reasons":[]}' > "$(rundir)/summary.json"; rm -f "$(rundir)/summary.json.sig"
stop; [ $? = 2 ] && ok "an unsigned hand-written PASS does not pass the gate" || fail "unsigned PASS honoured"

# BUG-REV-review-gate-machinery-scope: a CI workflow or an extension-less hook is code for the gate
Q="$TMP/q"; mkdir -p "$Q/.github/workflows" "$Q/hooks"
(cd "$Q" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo "on: push" > .github/workflows/ci.yml && printf '#!/bin/sh\nexit 0\n' > hooks/pre-push && git add -A && git commit -qm i)
for f in .github/workflows/ci.yml hooks/pre-push; do
  git -C "$Q" checkout -q -- .; echo "# edit" >> "$Q/$f"; rm -f "$TMP/q.jsonl"; python3 "$TMP/ev.py" edit "$TMP/q.jsonl" q1 "$Q/$f"
  printf '{"session_id":"s2","transcript_path":"%s","hook_event_name":"Stop"}' "$TMP/q.jsonl" \
    | CLAUDE_PROJECT_DIR="$Q" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; rc=$?
  [ "$rc" = 2 ] && ok "an edit to $f needs the review" || fail "$f edit not gated rc=$rc $(cat "$TMP/err")"
done

if [ "$FAILS" -ne 0 ]; then echo "review gate 4-way: $FAILS FAILED"; exit 1; fi
echo "review gate 4-way: all checks passed"
