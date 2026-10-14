#!/usr/bin/env bash
# A JSON-escaped payload cwd must name the same project as a plain one (docs/issues-bugs.md A.4). With CLAUDE_PROJECT_DIR
# unset, 15 hooks took the project from the payload cwd with RX_CWD='"cwd"…"([^"\\]*)"': a cwd holding `"` or `\` (sent as
# \" and \\), or a host that writes non-ASCII escaped (é as backslash-u00e9, Python's json.dumps default), did not match, the hook
# fell back to "." = the PROCESS cwd and judged / logged into that project instead. worktree_guard read the session's first
# transcript cwd the same way: a session that started in a linked worktree whose path holds é was not seen as one, and its
# Write into the main checkout passed.
# Each hook runs with CLAUDE_PROJECT_DIR unset and its process cwd in ANOTHER git repo O:
#   A. payload cwd = R1 (…/café, sent as caf + backslash-u00e9) or R2 (…/b\s"q, sent as b\\s\"q) → state lands in that repo's
#      .claude/audit-gate, nothing in O/.claude;
#   B. worktree_guard: a session that started in a linked worktree (…/wt-café, …/wt-b\s"q) writes into the main checkout → blocked;
#   C. static: every RX_CWD in hooks/*.sh is the escape-aware pattern and is followed by the same one-step decode.
#   PCE_HOOKS=<hooks dir>  run against another copy of the hooks (e.g. the unpatched kit: RED)
#   PCE_BASH=/bin/bash     run the hooks under macOS bash 3.2
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="${PCE_HOOKS:-$DEVKIT_DIR/hooks}"
SH="${PCE_BASH:-bash}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset CLAUDE_PROJECT_DIR

mkrepo() {   # mkrepo <dir>: a git repo with one committed file, src/A.kt dirty
  mkdir -p "$1/src"
  git -C "$1" init -q . && git -C "$1" config user.email t@t && git -C "$1" config user.name t && git -C "$1" config commit.gpgsign false
  printf 'class A\n' > "$1/src/A.kt"
  git -C "$1" add -A && git -C "$1" commit -qm init && printf 'class A2\n' > "$1/src/A.kt"
}
X="$TMP/x"; O="$TMP/o"
R1="$X/café"
R2="$X/b\\s\"q"
mkrepo "$O"; mkrepo "$R1"; mkrepo "$R2"

# transcript <out> <cwd>: one user record; json.dumps escapes é as backslash-u00e9, " as \" and \ as \\
transcript() {
  python3 -I -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({"type":"user","cwd":sys.argv[2],"sessionId":"s1","message":{"role":"user","content":"go"}})+"\n")' "$1" "$2"
}
# payload <transcript> <cwd> <event> <tool> <tool_input json> [extra json fields]
payload() {
  python3 -I -c 'import json,sys; d={"session_id":"s1","transcript_path":sys.argv[1],"cwd":sys.argv[2],"hook_event_name":sys.argv[3]}
if sys.argv[4]: d.update(tool_name=sys.argv[4], tool_input=json.loads(sys.argv[5]))
d.update(json.loads(sys.argv[6] if len(sys.argv) > 6 else "{}")); print(json.dumps(d))' "$@" > "$TMP/in.json"
}
# run <hook> [VAR=val…]: process cwd O, CLAUDE_PROJECT_DIR unset; rc in $RC
run() { local h="$1"; shift; ( cd "$O" && env -u CLAUDE_PROJECT_DIR "$@" "$SH" "$HOOKS/$h" < "$TMP/in.json" > /dev/null 2>&1 ); RC=$?; }
clean() { rm -rf "$O/.claude" "$X/.claude" "$R1/.claude" "$R2/.claude"; }
# expect <label> <repo> <file that must exist under <repo>/.claude/audit-gate, or "*" = may or may not>
expect() {
  local label="$1" repo="$2" want="$3" bad=""
  [ -e "$O/.claude" ] && bad="$bad O/.claude (the process cwd's project)"
  [ -e "$X/.claude" ] && bad="$bad X/.claude"
  [ "$want" = "*" ] || [ -e "$repo/.claude/audit-gate/$want" ] || bad="$bad (no <payload repo>/.claude/audit-gate/$want)"
  [ -z "$bad" ] && ok "$label" || fail "$label:$bad"
  clean
}

# the fixture really sends escaped JSON (a generator that stops escaping would turn this test green on the old regex)
transcript "$TMP/tr1.jsonl" "$R1"; transcript "$TMP/tr2.jsonl" "$R2"
payload "$TMP/tr1.jsonl" "$R1" Stop ""
E9="caf$(printf '\134')u00e9"   # \134 = a backslash: the 6-char JSON escape of é, built at run time
case "$(cat "$TMP/in.json")" in *"\"cwd\": \"$X/$E9\""*) ok "fixture: the payload cwd of R1 is sent as $E9" ;;
  *) fail "fixture: R1 cwd not escaped: $(cat "$TMP/in.json")" ;; esac
payload "$TMP/tr2.jsonl" "$R2" Stop ""
case "$(cat "$TMP/in.json")" in *'b\\s\"q'*) ok 'fixture: the payload cwd of R2 is sent as b\\s\"q' ;;
  *) fail "fixture: R2 cwd not escaped: $(cat "$TMP/in.json")" ;; esac

# ── A. every hook that reads RX_CWD: (hook | event | tool | tool_input (@R@ = the repo) | file it must create | extra | env)
NOEXTRA='{}'
for n in 1 2; do
  if [ "$n" = 1 ]; then R="$R1"; else R="$R2"; fi
  while IFS='|' read -r h ev tool inp want extra envs; do
    [ -n "$h" ] || continue
    inp="$(python3 -I -c 'import json,sys; print(sys.argv[1].replace("@R@", json.dumps(sys.argv[2])[1:-1]))' "$inp" "$R")"
    payload "$TMP/tr$n.jsonl" "$R" "$ev" "$tool" "$inp" "${extra:-$NOEXTRA}"; run "$h" $envs
    expect "$h: escaped payload cwd R$n → state in R$n, not in the process cwd's repo (rc $RC)" "$R" "$want"
  done <<'EOF'
precode_gate.sh|PreToolUse|Edit|{"file_path":"@R@/src/A.kt","old_string":"a","new_string":"b"}|precode_gate.log||
read_ledger.sh|PostToolUse|Read|{"file_path":"@R@/src/A.kt"}|read_ledger.tsv||
churn_guard.sh|PostToolUse|Edit|{"file_path":"@R@/src/A.kt","old_string":"a","new_string":"b"}|churn_guard.log||
comment_claim_guard.sh|PostToolUse|Write|{"file_path":"@R@/src/A.kt","content":"// plain\nclass A"}|comment_claim_guard.log||
worktree_guard.sh|PreToolUse|Bash|{"command":"ls"}|wg_scan||
claim_check.sh|Stop|||claim_check.log|{"last_assistant_message":"Lỗi nằm ở Ghost.kt:4211."}|
review_gate.sh|Stop|||review_gate.log|{"last_assistant_message":"xong"}|
hardware_safety_gate.sh|PreToolUse|Bash|{"command":"adb reboot"}|hardware_safety_gate.log||HARDWARE_OVERRIDE=1
bash_write_ledger.sh|PostToolUse|Bash|{"command":"echo hi > a.txt"}|bash_write_ledger.tsv|{"tool_use_id":"tu1"}|
security_gate.sh|Stop|||.gitignore|{"last_assistant_message":"xong"}|
proof_gate.sh|Stop|||.gitignore|{"last_assistant_message":"XONG"}|
regression_gate.sh|Stop|||.gitignore|{"last_assistant_message":"XONG"}|
test_evidence_gate.sh|Stop|||.gitignore|{"last_assistant_message":"da fix, test pass"}|
review_timing_guard.sh|PostToolUse|Edit|{"file_path":"@R@/src/A.kt","old_string":"a","new_string":"b"}|.gitignore||
prompt_context.sh|UserPromptSubmit|||*|{"prompt":"fix the crash in the login flow please, it throws NPE"}|
EOF
done

# ── B. worktree_guard: the session started in a linked worktree whose path is escaped in the transcript ──────────────────
M="$TMP/main"
mkrepo "$M"
git -C "$M" commit -qam two
for wt in "$TMP/wt-café" "$TMP/wt-b\\s\"q"; do
  git -C "$M" worktree add -q --detach "$wt" || { fail "fixture: git worktree add $wt"; continue; }
  transcript "$TMP/wt.jsonl" "$wt"
  payload "$TMP/wt.jsonl" "$wt" PreToolUse Write "$(python3 -I -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"content":"class Z\n"}))' "$M/src/A.kt")"
  ( cd "$wt" && env CLAUDE_PROJECT_DIR="$wt" "$SH" "$HOOKS/worktree_guard.sh" < "$TMP/in.json" > /dev/null 2>&1 ); RC=$?
  [ "$RC" = 2 ] && ok "worktree_guard: a session started in ${wt##*/} (escaped in the transcript) writing into the main checkout is blocked" \
    || fail "worktree_guard: a session started in ${wt##*/} (escaped in the transcript) wrote into the main checkout, rc=$RC (want 2)"
  rm -rf "$wt/.claude"
done

# ── C. static: one pattern and one decode for every RX_CWD in the hooks ──────────────────────────────────────────────────
python3 -I - "$HOOKS" <<'PY' || FAILS=$((FAILS + 1))
import glob, os, sys
RX = r"""RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'"""
DECODE = r"""python3 -I -c 'import json,sys; sys.stdout.buffer.write(json.loads("\"%s\"" % sys.argv[1]).encode())'"""
bad, sites = [], 0
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*.sh"))):
    lines = open(path, encoding="utf-8").read().splitlines()
    for i, line in enumerate(lines):
        if "RX_CWD=" not in line:
            continue
        sites += 1
        where = "%s:%d" % (os.path.basename(path), i + 1)
        if line.strip().split("   #")[0].strip() != RX:
            bad.append(where + ": RX_CWD is not the escape-aware pattern: " + line.strip()[:100])
        if not any(DECODE in l for l in lines[i + 1:i + 4]):
            bad.append(where + ": no JSON decode of the matched cwd within 3 lines")
if sites < 16:
    bad.append("only %d RX_CWD sites found (expected 16): the scan has gone blind" % sites)
for b in bad:
    print("✖ static: " + b)
print(("✔ static: %d RX_CWD sites, one escape-aware pattern, each decoded" % sites) if not bad else "")
sys.exit(1 if bad else 0)
PY

[ "$FAILS" -eq 0 ] && echo "✅ test_hook_payload_cwd_escaped: all passed" || { echo "❌ test_hook_payload_cwd_escaped: $FAILS failed"; exit 1; }
