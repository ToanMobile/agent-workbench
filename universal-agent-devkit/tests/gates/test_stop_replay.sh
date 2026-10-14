#!/usr/bin/env bash
# scripts/governance/stop_replay.py: the replay of Stop-hook blocks on real transcripts (docs/workflow-improvements.md I.0 W2 d).
# The transcripts are the user's real conversations, so what the tool PRINTS is a contract: no token, e-mail, other person's home
# folder or long id may reach the report (text or --json), and the tool only READS (no transcript is touched, no temp folder is left).
# Also the counting rules: a Stop is counted once (a resumed session copies it), by its own timestamp; an entry of hookErrors that is
# no block ("non-blocking status code") is not a block; a reply with the report under other labels is WRONG without the sandbox run
# and "fixed-since" when the hook of this checkout accepts it; a reply with no report stays "correct".
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$DEVKIT_DIR/scripts/governance/stop_replay.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

ROOT="$TMP/projects"; PD="$ROOT/-Volumes-Data-Toan-demo"; mkdir -p "$PD"
TOKEN="sk-""ABCDEF1234567890abcdef"; EMAIL="jane.doe@example.com"; HOME_OF_OTHER="/Users/janedoe/secret"; UUID="0a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d"
cat > "$TMP/make.py" <<'PY'
import datetime, json, sys
out, token, email, home, uid = sys.argv[1:6]
now = datetime.datetime.now(datetime.timezone.utc)
def at(sec):
    return (now - datetime.timedelta(seconds=sec)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
HOOK = lambda n: 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/%s.sh"' % n
def summary(uuid, ts, errors, hooks=("proof_gate", "regression_gate")):
    return {"type": "system", "subtype": "stop_hook_summary", "uuid": uuid, "timestamp": ts, "hookInfos": [{"command": HOOK(h)} for h in hooks],
            "hookErrors": errors, "preventedContinuation": False}
BLOCK = "[%s]: ⛔ PROOF-GATE: lượt này đã git push (bàn giao) nhưng thiếu:\n- Báo cáo 4 mục (thiếu 3) — dán vào cuối:\n1. Đã fix gì: …" % HOOK("proof_gate")
# the same Stop the hook wrote the report for under other labels ("Nguy cơ mới"), with secrets in the head of the reply
WRONGISH = ("Đã push. Token %s mail %s file %s id %s\n1. Đã fix gì: lỗi X.\n2. Chặn bug cũ: REG-1 PASS.\n3. Nguy cơ mới: đã rà caller.\n"
            "4. An toàn mã nguồn: không secret." % (token, email, home, uid))
def turn(t0, reply, uuid, errors):
    return [
        {"type": "user", "timestamp": at(t0), "message": {"role": "user", "content": "đẩy lên origin"}},
        {"type": "assistant", "timestamp": at(t0 - 1), "message": {"role": "assistant", "content": [
            {"type": "tool_use", "id": "p%d" % t0, "name": "Bash", "input": {"command": "git push origin main"}}]}},
        {"type": "user", "timestamp": at(t0 - 2), "message": {"role": "user", "content": [
            {"type": "tool_result", "tool_use_id": "p%d" % t0, "content": "   86f7ddc..a94c071  main -> main"}]}},
        {"type": "assistant", "timestamp": at(t0 - 3), "message": {"role": "assistant", "content": [{"type": "text", "text": reply}]}},
        summary(uuid, at(t0 - 4), errors),
    ]
rows = []
rows += turn(500, WRONGISH, "stop-wrongish", [BLOCK])                       # block 1: report present under other labels
rows += turn(400, "Đã push lên origin/main.", "stop-noreport", [BLOCK])     # block 2: no report at all
rows += [summary("stop-clean", at(300), [])]                                  # a Stop that passed
rows += [summary("stop-nonblock", at(290), ["[%s]: Failed with non-blocking status code: 1" % HOOK("regression_gate")])]   # no block
# the real shape of a non-block entry has no bracket at all (276 real Stop summaries, principal-code-reviewer 14/10)
rows += [summary("stop-nonblock2", at(280), ["Failed with non-blocking status code: bash: .claude/hooks/session-stop.sh: No such file"])]
rows += [summary("stop-old", at(40 * 86400), [BLOCK])]                        # 40 days old: outside the window although the file is new
with open(out, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
python3 "$TMP/make.py" "$PD/aaaa.jsonl" "$TOKEN" "$EMAIL" "$HOME_OF_OTHER" "$UUID"
# a resumed session copies the first Stop: the same uuid in a second transcript
head -n 5 "$PD/aaaa.jsonl" > "$PD/bbbb.jsonl"
SUB="$PD/aaaa/subagents"; mkdir -p "$SUB"; cp "$PD/aaaa.jsonl" "$SUB/agent-x.jsonl"   # a subagent transcript is not a session
digest() { python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:16])'; }
BEFORE="$(cat "$PD"/*.jsonl | digest)"
[ -n "$BEFORE" ] || { echo "no digest"; exit 1; }
export TMPDIR="$TMP/tmpdir"; mkdir -p "$TMPDIR"

run() { python3 "$TOOL" --root "$ROOT" --days 7 "$@"; }

# 1. counting, and the sandbox run: the report under other labels is accepted by the hook of this checkout (fixed-since), the bare reply stays correct
OUT="$(run --examples 3)"
echo "$OUT" | grep -E '^proof_gate +demo ' | grep -qE ' 2 +1 +0 +1 +0 ' && ok "2 blocks: 1 correct, 1 fixed-since, 0 wrong, 0 unknown (the old Stop, the non-block and the copy are not counted)" \
  || { fail "counting/verdicts wrong: $(echo "$OUT" | grep -E '^proof_gate' )"; }
echo "$OUT" | grep -qE '^demo +[0-9]+ ' && echo "$OUT" | grep -E '^demo ' | grep -qE '^demo +5 +' && ok "5 Stops (two blocked Stops, one clean, two with a non-block entry)" || fail "Stops count: $(echo "$OUT" | grep -E '^demo ')"

# 1b. a kill switch or a knob in the caller's shell never reaches the hooks of the sandbox (PROOF_GATE=0 makes proof_gate exit 0 with no
#     message: every block would read as "accepted now" = fixed-since)
OUT="$(PROOF_GATE=0 TEST_EVIDENCE_GATE=0 PROOF_MIN_BYTES=1 run --examples 3)"
echo "$OUT" | grep -E '^proof_gate +demo ' | grep -qE ' 2 +1 +0 +1 +0 ' && ok "PROOF_GATE=0 in the caller's environment changes no verdict" \
  || fail "the caller's switches reached the sandbox: $(echo "$OUT" | grep -E '^proof_gate')"

# 2. without the sandbox the same reply is WRONG, and its masked head is printed
OUT="$(run --no-replay --examples 3)"
echo "$OUT" | grep -E '^proof_gate +demo ' | grep -qE ' 2 +1 +1 +0 +0 ' && ok "--no-replay: the report under other labels is WRONG" || fail "--no-replay verdicts: $(echo "$OUT" | grep -E '^proof_gate')"
echo "$OUT" | grep -q 'report-label-variant' && ok "the class is named" || fail "class missing"

# 3. nothing secret in the text or JSON output
for mode in "--examples 5" "--no-replay --examples 5" "--json" "--no-replay --json"; do
  OUT="$(run $mode)"
  for secret in "$TOKEN" "$EMAIL" "janedoe" "$UUID" "ABCDEF1234567890"; do
    case "$OUT" in *"$secret"*) fail "leaked '$secret' with: $mode" ;; esac
  done
done
OUT="$(run --no-replay --examples 3)"
case "$OUT" in *"<token>"*"<email>"*) ok "the example shows the masks (<token>, <email>)" ;; *) fail "masks not in the example: $OUT" ;; esac
python3 - "$TOOL" <<'PY' && ok "mask(): token, e-mail, other person's home, uuid and blob are replaced" || fail "mask() leaks"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("stop_replay", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
s = m.mask("a ghp_abcdefghijklmnop1234 b token=hunter2 c bob@corp.io d /Users/bob/x e /home/amy/y f 0a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d g " + "A" * 40
           + " export DB_PASSWORD=pw0rdA SONATYPE_TOKEN=abcd1234efgh OPENAI_API_KEY=abc123 Authorization: Bearer abc123def456ghi mật khẩu: Pa55word!"
           # the key words are joined here so that no line of this file looks like a secret to the kit's own static scan
           + ' {"pass' + 'word": "Hunter2pw"} PGPASS' + 'WORD=pgsecret1 --pass' + 'word cliSecret1 Authorization: Basic dXNlcjpwYXNz PASS=passEq1 mysql -phunterFour'
           + " curl -u admin:curlSecret1 Cookie: sid=cookieVal12345 glp" + "at-abcdefghijklmnopqrst", 1600)
bad = [w for w in ("ghp_", "hunter2", "bob@", "/Users/bob", "/home/amy", "0a1b2c3d", "A" * 40, "pw0rdA", "abcd1234efgh", "abc123", "Pa55word",
                   "Hunter2pw", "pgsecret1", "cliSecret1", "dXNlcjpwYXNz", "passEq1", "hunterFour", "curlSecret1", "cookieVal12345",
                   "glpat-abcdefgh") if w in s]
fine = m.mask("the token is fine") == "the token is fine"
sys.exit(1 if bad or not fine else 0)
PY
# the report oracle: the rule's own labels and the variants are a report; residual risk and "Hành vi cũ / mới" are not the items
python3 - "$TOOL" <<'PY' && ok "structured_report(): label variants yes; residual risk / 'Hành vi cũ, mới' / no colon no" || fail "structured_report() too wide or too narrow"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("stop_replay", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
f = m.structured_report
ok = (f("1. Đã fix gì: a\n2. Chặn bug cũ: b\n3. Nguy cơ mới: c\n4. An toàn mã nguồn: d") and f("1. Đã làm gì: a\n2. Chặn lỗi cũ: b\n3. Nguy cơ lỗi mới: c\n4. An toàn mã: d")
      and not f("1. Đã fix gì: a\n2. Chặn bug cũ: b\n3. Rủi ro còn lại: không có lỗi mới\n4. An toàn mã nguồn: d")
      and not f("1. Đã thay đổi: p\n2. Hành vi cũ: x\n3. Hành vi mới: y\n4. An toàn: z")
      and not f("1. Đã fix gì a\n2. Chặn bug cũ b\n3. Nguy cơ mới c\n4. An toàn mã nguồn d"))
sys.exit(0 if ok else 1)
PY
# a hookErrors entry that is no block ("non-blocking status code") never becomes a block row of its hook
OUT="$(run --no-replay)"
echo "$OUT" | grep -qE '^regression_gate ' && fail "a non-block entry was counted as a regression_gate block" || ok "non-block hookErrors entries are no blocks (no regression_gate row)"
# the oracle's copies of the hook's mention rules must not drift from the hook (they are copies on purpose: the before/after comparison)
python3 - "$TOOL" <<'PY' && ok "the oracle's quote span and naming words equal the hook's" || fail "stop_replay.py's copy of QUOTED_SPAN / OUTCOME_MENTION_WORD differs from hooks/test_evidence_gate.sh"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("stop_replay", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
a, b = m.hook_regex("test_evidence_gate", "QUOTED_SPAN"), m.hook_regex("test_evidence_gate", "OUTCOME_MENTION_WORD")
sys.exit(0 if a is not None and b is not None and a.pattern == m._QUOTE_SPAN.pattern and b.pattern == m._NAMES_A_QUOTE.pattern else 1)
PY

# 3b. the test_evidence_gate and review_gate classifiers: a second project with a framed quote, a bare quote, a plain claim (CHECK 7) and
#     a code edit with no review after it; the second block of the framed one follows the first in the same turn (chain)
PD2="$ROOT/-Volumes-Data-Toan-demo2"; mkdir -p "$PD2"
cat > "$TMP/make2.py" <<'PY'
import datetime, json, sys
out = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc)
at = lambda sec: (now - datetime.timedelta(seconds=sec)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
HOOK = lambda n: 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/%s.sh"' % n
def summary(uuid, ts, errors):
    return {"type": "system", "subtype": "stop_hook_summary", "uuid": uuid, "timestamp": ts, "hookInfos": [], "hookErrors": errors}
C7 = ["[%s]: ⛔ CHECK 7 (fix có tác dụng thật): claim OUTCOME ('đã fix'/'hết bug') nhưng phiên này không có bằng chứng" % HOOK("test_evidence_gate")]
REV = ["[%s]: ⛔ REVIEW-GATE: thay đổi code chưa được review bằng CONTEXT SẠCH." % HOOK("review_gate")]
prompt = lambda t: {"type": "user", "timestamp": at(t), "message": {"role": "user", "content": "làm đi"}}
text = lambda t, s: {"type": "assistant", "timestamp": at(t), "message": {"role": "assistant", "content": [{"type": "text", "text": s}]}}
edit = lambda t: {"type": "assistant", "timestamp": at(t), "message": {"role": "assistant", "content": [
    {"type": "tool_use", "id": "e%d" % t, "name": "Edit", "input": {"file_path": "/work/app/Main.kt", "old_string": "a", "new_string": "b"}}]}}
rows = [prompt(900), text(899, 'Hook chặn vì câu của tôi có chữ "đã xử lý" trong phần giải thích.'), summary("a1", at(898), C7),
        summary("a2", at(897), C7), summary("a3", at(896), []),
        prompt(800), text(799, 'Kết quả: "đã fix".'), summary("b1", at(798), C7),
        prompt(700), text(699, "Mình đã fix lỗi tràn bộ nhớ."), summary("c1", at(698), C7),
        prompt(600), edit(599), text(598, "Đã sửa."), summary("d1", at(597), REV)]
with open(out, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
python3 "$TMP/make2.py" "$PD2/cccc.jsonl"
OUT="$(run --no-replay --hook test_evidence_gate --hook review_gate)"
for want in 'test_evidence_gate +wrong +quoted-outcome-mention +2$' 'test_evidence_gate +unknown +quoted-outcome-bare +1$' 'test_evidence_gate +unknown +outcome-proof +1$' \
            'review_gate +correct +no-review-after-edit +1$'; do
  echo "$OUT" | grep -qE "$want" && ok "verdict class: $want" || fail "missing verdict class '$want' in: $(echo "$OUT" | grep -E '^  ')"
done
OUT="$(run --hook test_evidence_gate --hook review_gate)"
echo "$OUT" | grep -qE 'test_evidence_gate +fixed-since +quoted-outcome-mention +2$' && ok "with the sandbox the hook of this checkout reads the framed quote as a mention (fixed-since)" \
  || fail "framed quote not fixed-since: $(echo "$OUT" | grep -E '^  ')"
run --no-replay --json --hook test_evidence_gate | python3 -c '
import json, sys
rows = [r for r in json.load(sys.stdin)["rows"] if r["repo"] == "demo2"]
sys.exit(0 if rows and rows[0]["chain"] == 1 else 1)' && ok "chain: the first block was followed by a block of the same hook, the others were not" || fail "chain count wrong"
python3 - "$TOOL" <<'PY' && ok "quoted_outcome(): named quote = framed, bare quote = bare, unquoted = None; the hook's OUTCOME regex is readable" || fail "quoted_outcome() or hook_regex(OUTCOME)"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("stop_replay", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
rx = m.hook_regex("test_evidence_gate", "OUTCOME")
ok = (rx is not None and m.quoted_outcome('Có chữ "đã fix" ở đây.', rx) == "framed" and m.quoted_outcome('Kết quả: "đã fix".', rx) == "bare"
      and m.quoted_outcome("Mình đã fix lỗi X.", rx) is None and m.quoted_outcome('Theo mẫu báo cáo lỗi crash "đã khắc phục".', rx) == "bare")
sys.exit(0 if ok else 1)
PY

# 4. read-only, and no sandbox folder left behind
AFTER="$(cat "$PD"/*.jsonl | digest)"
[ "$BEFORE" = "$AFTER" ] && ok "the transcripts are untouched" || fail "a transcript changed"
LEFT="$(ls "$TMPDIR" | grep -c 'stop-replay-' || true)"
[ "$LEFT" = 0 ] && ok "no sandbox folder left in TMPDIR" || fail "$LEFT sandbox folder(s) left"

# 5. a missing root is an empty report, never a crash
OUT="$(python3 "$TOOL" --root "$TMP/none" 2>&1)"; RC=$?
[ "$RC" = 0 ] && echo "$OUT" | grep -q "0 Stops" && ok "no transcripts: exit 0, 0 Stops" || fail "empty root: rc $RC $OUT"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
