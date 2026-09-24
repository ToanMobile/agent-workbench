#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# or_ported_contract_test.sh — contract points ported from the OfficeReader hook
# harness (the project these DevKit hooks were derived from), for the protections
# the port lost. An audit ran OfficeReader's own 249-point harness against the
# DevKit hooks (212/249) and traced the failures to four hooks:
#
#   G1 bash_write_ledger.sh — the start/end Bash-window ledger was replaced by an
#      unwired JSONL log, so no gate could attribute a shell write to a session.
#   G2 review_gate.sh — after the anti-loop release, every later Stop stayed
#      released until a review ran: one stuck episode disarmed the gate for the
#      rest of the session (OfficeReader measured 34 suppressed Stops in a row).
#   G3 security_gate.sh — bare CLEARTEXT under re.I flagged camelCase `clearText`.
#   G6 testsourceset_gate.sh — (a) Kotlin written from Bash whose path never shows
#      in the transcript fell out of scope; (b) a session that wrote no Kotlin was
#      blocked by another session's broken module.
#
# Each REGRESSION case below fails on the pre-fix hook and passes on the fixed one.
# GUARD cases pass on both: they prove the fix did not weaken real detection (they
# are marked "guard" in their name). Expectations come from each hook's documented
# contract (its header), not from observing the current code.
#
# ISOLATION: every case runs against a fresh temp sandbox (CLAUDE_PROJECT_DIR); the
# real repo's .claude/audit-gate is never touched. Fake ./gradlew only, no network.
#
# Usage: bash hooks/tests/or_ported_contract_test.sh
#        OR_PORTED_HOOKS_DIR=/path/to/other/hooks bash …   (run against another copy)
# Exit 0 = every contract point holds. Exit 1 = at least one deviation.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOKS="${OR_PORTED_HOOKS_DIR:-$(cd "${HERE}/.." && pwd)}"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/orported.XXXXXX")"
trap 'rm -rf "${SANDBOX}"' EXIT
mkdir -p "${SANDBOX}/.claude/audit-gate"
TAB="$(printf '\t')"

PASS=0; FAIL=0; FAILED_CASES=""

# run_case <name> <hook.sh> <expected_exit> <stdin-json> [ENV=VAL ...]
run_case() {
  name="$1"; hook="$2"; want="$3"; payload="$4"; shift 4
  out="$(printf '%s' "${payload}" | env CLAUDE_PROJECT_DIR="${SANDBOX}" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 "$@" \
        bash "${HOOKS}/${hook}" 2>&1)"
  got=$?
  if [ "${got}" -eq "${want}" ]; then
    PASS=$((PASS + 1))
    printf '  ok   %-60s exit=%s\n' "${name}" "${got}"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES}
  ✗ ${name}
      hook=${hook} want exit=${want}, got=${got}
      output: $(printf '%s' "${out}" | head -3 | tr '\n' ' ')"
    printf '  FAIL %-60s want=%s got=%s\n' "${name}" "${want}" "${got}"
  fi
}

# assert_file <name> <file> <grep-ere> <yes|no>. A "no" against a MISSING file
# fails: it would stay green with the hook deleted.
assert_file() {
  name="$1"; f="$2"; pat="$3"; want="$4"
  if [ ! -f "${f}" ]; then r=1
  elif [ "${want}" = "yes" ]; then grep -Eq "${pat}" "${f}" 2>/dev/null; r=$?; else
    grep -Eq "${pat}" "${f}" 2>/dev/null && r=1 || r=0; fi
  if [ "${r}" -eq 0 ]; then
    PASS=$((PASS + 1)); printf '  ok   %-60s (file)\n' "${name}"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES}
  ✗ ${name}
      file=${f} want ${want} match: ${pat}"
    printf '  FAIL %-60s (file want=%s)\n' "${name}" "${want}"
  fi
}

# check <name> <0|1 result>
check() {
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); printf '  ok   %-60s\n' "$1"
  else FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES}
  ✗ $1"; printf '  FAIL %-60s\n' "$1"; fi
}

# tool_use transcript line helpers (python3 for correct JSON escaping)
tu_edit() { python3 -c 'import json,sys; print(json.dumps({"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":sys.argv[1]}}]}}))' "$1"; }
tu_bash() { python3 -c 'import json,sys; i={"command":sys.argv[1]}
if len(sys.argv) > 2: i["run_in_background"] = True
print(json.dumps({"message":{"content":[{"type":"tool_use","name":"Bash","input":i}]}}))' "$@"; }
tu_agent() { python3 -c 'import json,sys; print(json.dumps({"message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":sys.argv[1],"prompt":"do it"}}]}}))' "$1"; }

# mk_tr <out> <Edit|Write> <path> <text>  (same shape as hook_contract_test.sh)
mk_tr() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, sys
out, tool, path, text = sys.argv[1:5]
key = "content" if tool == "Write" else "new_string"
with open(out, "w") as fh:
    fh.write(json.dumps({"message": {"content": [
        {"type": "tool_use", "name": tool, "input": {"file_path": path, key: text}}]}}) + "\n")
PY
}

echo "or_ported_contract_test.sh — hooks: ${HOOKS}"
echo

# ═════════════════════════════════════════════════════════════════════════════
# G1 — bash_write_ledger.sh
# ═════════════════════════════════════════════════════════════════════════════
echo "G1 bash_write_ledger.sh"
BL_LEDGER="${SANDBOX}/.claude/audit-gate/bash_write_ledger.tsv"
rm -f "${BL_LEDGER}"
bl_payload() { printf '{"session_id":"bl-1","transcript_path":"/x.jsonl","cwd":"/y","hook_event_name":"%s","tool_name":"Bash","tool_input":{"command":"echo hi"%s},"tool_use_id":"tu-1"}' "$1" "$2"; }

run_case "guard: ledger PreToolUse exits 0" bash_write_ledger.sh 0 "$(bl_payload PreToolUse '')"
assert_file "ledger records a start row (<sid>\\t start\\t <s.mmm>\\t <id>)" "${BL_LEDGER}" "^bl-1${TAB}start${TAB}[0-9]+\\.[0-9]{3}${TAB}tu-1\$" yes
run_case "guard: ledger PostToolUse exits 0" bash_write_ledger.sh 0 "$(bl_payload PostToolUse '')"
assert_file "ledger records an end row" "${BL_LEDGER}" "^bl-1${TAB}end${TAB}[0-9]+\\.[0-9]{3}${TAB}tu-1\$" yes
assert_file "every ledger row is session-scoped" "${BL_LEDGER}" "^bl-1${TAB}" yes

# A backgrounded command must NOT close its window (it is still writing).
rm -f "${BL_LEDGER}"
run_case "guard: ledger PreToolUse exits 0 (background)" bash_write_ledger.sh 0 \
  "$(bl_payload PreToolUse ',"run_in_background":true')"
run_case "guard: ledger PostToolUse exits 0 (background)" bash_write_ledger.sh 0 \
  "$(bl_payload PostToolUse ',"run_in_background":true')"
assert_file "background command writes no end row" "${BL_LEDGER}" "${TAB}end${TAB}" no

# Key-looking text INSIDE the command must not be read as a field: this Read-named,
# background-claiming command is a foreground Bash call and must get its end row.
rm -f "${BL_LEDGER}"
bl_tricky() { printf '{"session_id":"bl-3","hook_event_name":"%s","tool_name":"Bash","tool_input":{"command":"echo \\"tool_name\\":\\"Read\\" \\"run_in_background\\":true \\"session_id\\":\\"evil\\""},"tool_use_id":"tu-3"}' "$1"; }
run_case "guard: ledger: key text inside the command (Pre)" bash_write_ledger.sh 0 "$(bl_tricky PreToolUse)"
run_case "guard: ledger: key text inside the command (Post)" bash_write_ledger.sh 0 "$(bl_tricky PostToolUse)"
assert_file "command text cannot fake tool/session/background" "${BL_LEDGER}" "^bl-3${TAB}end${TAB}" yes

# A non-Bash tool must not open a window. The ledger is NOT cleared first: "no bl-2
# row" is read from a file that demonstrably exists.
run_case "guard: ledger ignores non-Bash tools (exit 0)" bash_write_ledger.sh 0 \
  '{"session_id":"bl-2","tool_name":"Read","tool_use_id":"tu-9","hook_event_name":"PreToolUse","tool_input":{"file_path":"/tmp/x.kt"}}'
assert_file "non-Bash tool writes no ledger row" "${BL_LEDGER}" '^bl-2' no

# Escape hatch: the call writes nothing (row count unchanged).
before="$(wc -l < "${BL_LEDGER}" 2>/dev/null | tr -d ' ')"
run_case "guard: ledger escape hatch BASH_WRITE_LEDGER=0 exits 0" bash_write_ledger.sh 0 \
  "$(bl_payload PreToolUse '')" BASH_WRITE_LEDGER=0
after="$(wc -l < "${BL_LEDGER}" 2>/dev/null | tr -d ' ')"
[ -n "${before}" ] && [ "${before}" = "${after}" ]; check "ledger escape hatch writes no row" $?

# No command text at all is stored, so a secret in a command can never land here.
run_case "guard: ledger: command with a secret exits 0" bash_write_ledger.sh 0 \
  '{"session_id":"bl-4","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"export GH_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz0123"},"tool_use_id":"tu-4"}'
assert_file "ledger row exists for the secret command" "${BL_LEDGER}" "^bl-4${TAB}start" yes
assert_file "ledger never stores command text" "${BL_LEDGER}" 'ghp_|GH_TOKEN|echo' no

# Wired on PreToolUse:Bash AND PostToolUse:Bash in the plugin registry.
python3 - "${HOOKS}/hooks.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))["hooks"]
except Exception:
    sys.exit(1)
def wired(ev):
    return any(m.get("matcher") == "Bash" and
               any("bash_write_ledger.sh" in h.get("command", "") for h in m.get("hooks", []))
               for m in d.get(ev, []))
sys.exit(0 if wired("PreToolUse") and wired("PostToolUse") else 1)
PY
check "hooks.json wires the ledger on Pre+PostToolUse Bash" $?
echo

# ═════════════════════════════════════════════════════════════════════════════
# G2 — review_gate.sh: the anti-loop release is PER EPISODE, not per session
# ═════════════════════════════════════════════════════════════════════════════
echo "G2 review_gate.sh"
GITSB="${SANDBOX}/gitrepo"
mkdir -p "${GITSB}"
( cd "${GITSB}" && git init -q 2>/dev/null ) || true
printf 'class RgOne\n'   > "${GITSB}/RgOne.kt"
printf 'class RgTwo\n'   > "${GITSB}/RgTwo.kt"
printf 'class RgThree\n' > "${GITSB}/RgThree.kt"

mk_rg_tr() { out="$1"; shift; : > "${out}"; for f in "$@"; do tu_edit "$f" >> "${out}"; done; }
RG_TR1="${SANDBOX}/rg-one.jsonl";     mk_rg_tr "${RG_TR1}" "${GITSB}/RgOne.kt"
RG_TR2="${SANDBOX}/rg-two.jsonl";     mk_rg_tr "${RG_TR2}" "${GITSB}/RgOne.kt" "${GITSB}/RgTwo.kt"
RG_AGAIN="${SANDBOX}/rg-again.jsonl"; mk_rg_tr "${RG_AGAIN}" "${GITSB}/RgOne.kt" "${GITSB}/RgOne.kt"
RG_SHORT="${SANDBOX}/rg-short.jsonl"; mk_rg_tr "${RG_SHORT}" "${GITSB}/RgThree.kt"
ATT="${SANDBOX}/.claude/audit-gate"
rg_payload() { printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s","last_assistant_message":"xong"}' "$1" "${GITSB}" "$2"; }

rm -f "${ATT}/review_attempts_rg-rearm.txt"
run_case "guard: unreviewed code blocks (1/3)" review_gate.sh 2 "$(rg_payload rg-rearm "${RG_TR1}")"
run_case "guard: unreviewed code blocks (2/3)" review_gate.sh 2 "$(rg_payload rg-rearm "${RG_TR1}")"
run_case "guard: unreviewed code blocks (3/3)" review_gate.sh 2 "$(rg_payload rg-rearm "${RG_TR1}")"
run_case "guard: 4th attempt releases (anti-loop)" review_gate.sh 0 "$(rg_payload rg-rearm "${RG_TR1}")"
run_case "guard: still released for the SAME episode" review_gate.sh 0 "$(rg_payload rg-rearm "${RG_TR1}")"
run_case "NEW unreviewed file re-arms the gate" review_gate.sh 2 "$(rg_payload rg-rearm "${RG_TR2}")"
rm -f "${ATT}/review_attempts_rg-rearm.txt"

# More edits to a file the release ALREADY covered: only the growing index sees it.
rm -f "${ATT}/review_attempts_rg-same.txt"
for i in 1 2 3; do run_case "guard: same-file: block ${i}/3" review_gate.sh 2 "$(rg_payload rg-same "${RG_TR1}")"; done
run_case "guard: same-file: release" review_gate.sh 0 "$(rg_payload rg-same "${RG_TR1}")"
run_case "MORE edits to an already-released file re-arm" review_gate.sh 2 "$(rg_payload rg-same "${RG_AGAIN}")"
rm -f "${ATT}/review_attempts_rg-same.txt"

# COMPACTION: the transcript is rewritten SHORTER, so the index cannot re-arm; a
# file the release never covered must.
rm -f "${ATT}/review_attempts_rg-compact.txt"
for i in 1 2 3; do run_case "guard: compaction: block ${i}/3" review_gate.sh 2 "$(rg_payload rg-compact "${RG_TR2}")"; done
run_case "guard: compaction: release" review_gate.sh 0 "$(rg_payload rg-compact "${RG_TR2}")"
run_case "post-compaction NEW file re-arms despite lower index" review_gate.sh 2 "$(rg_payload rg-compact "${RG_SHORT}")"
rm -f "${ATT}/review_attempts_rg-compact.txt"

# COMPACTION of the SAME file: neither the index nor the file set moves — only the
# file's mtime. Released for real (no hand-written state), then compacted.
rm -f "${ATT}/review_attempts_rg-mtime.txt"
for i in 1 2 3; do run_case "guard: same-file compaction: block ${i}/3" review_gate.sh 2 "$(rg_payload rg-mtime "${RG_AGAIN}")"; done
run_case "guard: same-file compaction: release" review_gate.sh 0 "$(rg_payload rg-mtime "${RG_AGAIN}")"
run_case "guard: untouched file stays released after compaction" review_gate.sh 0 "$(rg_payload rg-mtime "${RG_TR1}")"
sleep 1; printf 'class RgOne { val x = 1 }\n' > "${GITSB}/RgOne.kt"
run_case "same file rewritten after a release re-arms (mtime)" review_gate.sh 2 "$(rg_payload rg-mtime "${RG_TR1}")"
rm -f "${ATT}/review_attempts_rg-mtime.txt"

# Hand-written released state (OfficeReader's own fixture shape): an untouched file
# stays released, a file touched after the release re-arms.
python3 -c 'import json,sys,time; json.dump({"n":4,"released_at":99,"released_time":time.time()+60,"files":["RgOne.kt"]}, open(sys.argv[1],"w"))' "${ATT}/review_attempts_rg-json.txt"
run_case "a recorded release keeps an untouched file released" review_gate.sh 0 "$(rg_payload rg-json "${RG_TR1}")"
rm -f "${ATT}/review_attempts_rg-json.txt"

# Upgrade path: older attempt-file shapes never crash the gate.
printf '3' > "${ATT}/review_attempts_rg-legacy.txt"
run_case "guard: legacy bare attempt count is honoured" review_gate.sh 0 "$(rg_payload rg-legacy "${RG_TR1}")"
printf '4:99' > "${ATT}/review_attempts_rg-legacy.txt"
run_case "guard: legacy n:idx form re-arms (no file set)" review_gate.sh 2 "$(rg_payload rg-legacy "${RG_TR1}")"
printf 'not json at all' > "${ATT}/review_attempts_rg-legacy.txt"
run_case "guard: corrupt attempt file never crashes the gate" review_gate.sh 2 "$(rg_payload rg-legacy "${RG_TR1}")"
rm -f "${ATT}/review_attempts_rg-legacy.txt"
echo

# ═════════════════════════════════════════════════════════════════════════════
# G3 — security_gate.sh: camelCase clearText is not cleartext traffic
# ═════════════════════════════════════════════════════════════════════════════
echo "G3 security_gate.sh"
mk_tr "${SANDBOX}/sg_fp.jsonl"   Edit "${SANDBOX}/feature/reader/src/main/java/TextSearchViewModel.kt" \
  "private fun clearTextHighlights(view: View) { textView.clearText() }"
mk_tr "${SANDBOX}/sg_spec.jsonl" Edit "${SANDBOX}/core/network/src/main/java/HttpClient.kt" \
  "connectionSpecs(listOf(ConnectionSpec.CLEARTEXT))"
mk_tr "${SANDBOX}/sg_uses.jsonl" Edit "${SANDBOX}/core/network/src/main/java/Config.kt" \
  "val manifestFlag = \"android:usesCleartextTraffic\""
mk_tr "${SANDBOX}/sg_perm.jsonl" Edit "${SANDBOX}/core/network/src/main/java/Nsc.kt" \
  "val xml = \"<domain-config cleartextTrafficPermitted=true>\""
sg() { printf '{"session_id":"%s","transcript_path":"%s","last_assistant_message":"xong"}' "$1" "$2"; }
run_case "camelCase clearText is not a cleartext trigger" security_gate.sh 0 "$(sg sg1 "${SANDBOX}/sg_fp.jsonl")"
run_case "guard: ConnectionSpec.CLEARTEXT still blocked" security_gate.sh 2 "$(sg sg2 "${SANDBOX}/sg_spec.jsonl")"
run_case "guard: usesCleartextTraffic still blocked" security_gate.sh 2 "$(sg sg3 "${SANDBOX}/sg_uses.jsonl")"
run_case "guard: cleartextTrafficPermitted still blocked" security_gate.sh 2 "$(sg sg4 "${SANDBOX}/sg_perm.jsonl")"
echo

# ═════════════════════════════════════════════════════════════════════════════
# G6 — testsourceset_gate.sh: compile what THIS session wrote
# ═════════════════════════════════════════════════════════════════════════════
echo "G6 testsourceset_gate.sh"
TSSB="${SANDBOX}/tsrepo"
mkdir -p "${TSSB}/moda/src/main/java" "${TSSB}/modb/src/main/java" "${TSSB}/.claude/audit-gate"
( cd "${TSSB}" && git init -q 2>/dev/null ) || true
echo "// moda" > "${TSSB}/moda/build.gradle.kts"
echo "// modb" > "${TSSB}/modb/build.gradle.kts"
printf 'class A\n' > "${TSSB}/moda/src/main/java/A.kt"
printf 'class B\n' > "${TSSB}/modb/src/main/java/B.kt"
A_KT="${TSSB}/moda/src/main/java/A.kt"
B_KT="${TSSB}/modb/src/main/java/B.kt"
# Fake gradlew: fails ONLY for :modb (the other session's broken module).
cat > "${TSSB}/gradlew" <<'GW'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    :modb:*) echo "e: file:///x/B.kt:1:1 Cannot access class 'Foo'"; exit 1 ;;
  esac
done
exit 0
GW
chmod +x "${TSSB}/gradlew"
TSLOG="${TSSB}/.claude/audit-gate/testsourceset_gate.log"
BWL="${TSSB}/.claude/audit-gate/bash_write_ledger.tsv"

seed_window() { # <sid> <start-offset-sec> <end-offset-sec|open>
  now=$(date +%s)
  printf '%s\tstart\t%s.000\tt-%s\n' "$1" "$((now + $2))" "$1" >> "${BWL}"
  [ "$3" = "open" ] || printf '%s\tend\t%s.000\tt-%s\n' "$1" "$((now + $3))" "$1" >> "${BWL}"
}
ts_payload() { printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s","last_assistant_message":"xong"}' "$1" "${TSSB}" "$2"; }
ts_run() { # <name> <want> <sid> <transcript>
  rm -f "${TSSB}/.claude/audit-gate/.testsourceset_attempts"*
  run_case "$1" testsourceset_gate.sh "$2" "$(ts_payload "$3" "$4")" CLAUDE_PROJECT_DIR="${TSSB}"
}

TS_A="${SANDBOX}/ts-a.jsonl";       tu_edit "${A_KT}" > "${TS_A}"
TS_B="${SANDBOX}/ts-b.jsonl";       tu_edit "${B_KT}" > "${TS_B}"
TS_BOTH="${SANDBOX}/ts-both.jsonl"; { tu_edit "${A_KT}"; tu_edit "${B_KT}"; } > "${TS_BOTH}"
TS_MD="${SANDBOX}/ts-md.jsonl";     tu_edit "${TSSB}/notes.md" > "${TS_MD}"
TS_NONE="${SANDBOX}/ts-none.jsonl"; tu_edit "${TSSB}/moda/src/main/java/Untouched.kt" > "${TS_NONE}"
TS_EMPTY="${SANDBOX}/ts-empty.jsonl"; : > "${TS_EMPTY}"
# Edit of A.kt + B.kt rewritten by a shell pipeline whose command names no B path.
TS_XARGS="${SANDBOX}/ts-xargs.jsonl"
{ tu_edit "${A_KT}"; tu_bash "find . -name '*.kt' -path '*modb*' | xargs sed -i '' 's/class B/class B2/'"; } > "${TS_XARGS}"
TS_BG="${SANDBOX}/ts-bg.jsonl"
{ tu_edit "${A_KT}"; tu_bash "./scripts/codegen.sh" bg; } > "${TS_BG}"
TS_READ="${SANDBOX}/ts-read.jsonl"
{ tu_bash "cat modb/src/main/java/B.kt 2>/dev/null | head"; tu_edit "${TSSB}/notes.md"; } > "${TS_READ}"
TS_HEREDOC="${SANDBOX}/ts-heredoc.jsonl"
{ tu_edit "${A_KT}"; tu_bash "cat > modb/src/main/java/B.kt <<'EOF'
class B
EOF"; } > "${TS_HEREDOC}"

: > "${BWL}"
ts_run "guard: another session's broken module does not block me" 0 ts1 "${TS_A}"
ts_run "guard: my own module still blocks (P0 teeth)"               2 ts1 "${TS_B}"
ts_run "guard: two edited files keep both modules in scope"         2 ts1 "${TS_BOTH}"
ts_run "guard: no usable transcript → repo-wide fallback blocks"    2 ts1 "${SANDBOX}/does-not-exist.jsonl"
ts_run "guard: empty transcript → repo-wide fallback blocks"        2 ts1 "${TS_EMPTY}"
ts_run "guard: session edited no dirty file → repo-wide fallback"   2 ts1 "${TS_NONE}"
# G6b — a session that wrote no Kotlin has nothing of its own to compile.
: > "${TSLOG}"
ts_run "session wrote no Kotlin → nothing of mine to compile"       0 ts1 "${TS_MD}"
assert_file "…passed because it wrote no Kotlin (not by accident)" "${TSLOG}" 'wrote no Kotlin' yes
# A path this session only READ with a shell command is not a write.
ts_run "a Bash READ of another session's Kotlin does not charge me" 0 ts1 "${TS_READ}"
# A heredoc names its target: still in scope with no ledger at all.
ts_run "guard: heredoc-written Kotlin blocks without a ledger"      2 ts1 "${TS_HEREDOC}"

# G6a — Kotlin written from Bash, attributed by the ledger windows.
: > "${BWL}"; touch "${B_KT}"; seed_window ts1 -5 5
ts_run "xargs sed -i Kotlin (path never in transcript) still blocks" 2 ts1 "${TS_XARGS}"
ts_run "guard: Kotlin written by Bash blocks (OR TS-N1 shape)"      2 ts1 "${TS_MD}"
: > "${BWL}"; seed_window ts1 -30 open; touch "${B_KT}"
ts_run "background write lands in an open window"                   2 ts1 "${TS_BG}"
# Cross-session attribution.
: > "${BWL}"; touch "${B_KT}"; seed_window ts1 -600 -300
ts_run "read-only session is not charged for the write"             0 ts1 "${TS_MD}"
: > "${BWL}"; touch "${B_KT}"; seed_window other -2 2; seed_window ts1 -300 300
ts_run "narrowest window wins across concurrent sessions"           0 ts1 "${TS_MD}"
: > "${BWL}"; touch "${B_KT}"; seed_window ts1 -5 5; seed_window other -5 5
ts_run "equal windows across sessions are attributed to neither"    0 ts1 "${TS_MD}"

# End to end: the ledger hook's own rows feed the gate.
: > "${BWL}"
e2e() { printf '{"session_id":"ts-e2e","hook_event_name":"%s","tool_name":"Bash","tool_input":{"command":"./scripts/regen.sh"},"tool_use_id":"tu-e2e"}' "$1"; }
printf '%s' "$(e2e PreToolUse)"  | CLAUDE_PROJECT_DIR="${TSSB}" bash "${HOOKS}/bash_write_ledger.sh" >/dev/null 2>&1
sleep 1; printf 'class B { }\n' > "${B_KT}"; sleep 1
printf '%s' "$(e2e PostToolUse)" | CLAUDE_PROJECT_DIR="${TSSB}" bash "${HOOKS}/bash_write_ledger.sh" >/dev/null 2>&1
ts_run "e2e: ledger hook window attributes a script-written .kt"   2 ts-e2e "${TS_A}"

# A sub-agent's Edit lives in <transcript>/subagents/*.jsonl, not in the parent.
: > "${BWL}"
TS_SUB="${SANDBOX}/ts-sub.jsonl"; { tu_edit "${A_KT}"; tu_agent general-purpose; } > "${TS_SUB}"
mkdir -p "${SANDBOX}/ts-sub/subagents"; tu_edit "${B_KT}" > "${SANDBOX}/ts-sub/subagents/agent-x1.jsonl"
ts_run "a sub-agent's Kotlin edit is in scope"                       2 ts1 "${TS_SUB}"

# Per-session attempts budget, with ledger attribution.
rm -f "${TSSB}/.claude/audit-gate/.testsourceset_attempts"*
: > "${BWL}"; touch "${B_KT}"; seed_window ts1 -5 5
run_case "guard: session A: block 1" testsourceset_gate.sh 2 "$(ts_payload ts1 "${TS_MD}")" CLAUDE_PROJECT_DIR="${TSSB}"
run_case "guard: session A: block 2" testsourceset_gate.sh 2 "$(ts_payload ts1 "${TS_MD}")" CLAUDE_PROJECT_DIR="${TSSB}"
: > "${BWL}"; seed_window ts2 -5 5; touch "${B_KT}"
run_case "guard: session B still blocks after A burned its budget" testsourceset_gate.sh 2 "$(ts_payload ts2 "${TS_MD}")" CLAUDE_PROJECT_DIR="${TSSB}"
: > "${BWL}"; seed_window ts1 -5 5; touch "${B_KT}"
run_case "guard: session A: released after its own budget" testsourceset_gate.sh 0 "$(ts_payload ts1 "${TS_MD}")" CLAUDE_PROJECT_DIR="${TSSB}"
assert_file "guard: release came from the attempts budget" "${TSLOG}" 'RELEASE' yes
rm -f "${TSSB}/.claude/audit-gate/.testsourceset_attempts"*
echo

# ── report ──────────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────"
echo "contract points: ${PASS} ok, ${FAIL} deviating"
if [ "${FAIL}" -ne 0 ]; then
  echo "${FAILED_CASES}"
  echo
  echo "A deviation means the hook and its documented contract disagree."
  echo "Fix the hook, or fix the contract — do not relax the case."
  exit 1
fi
exit 0
