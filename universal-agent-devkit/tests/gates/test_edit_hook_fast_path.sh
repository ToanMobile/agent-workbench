#!/usr/bin/env bash
# Edit/Write/Read hooks started python on every call, ~30–40 ms each, also for files they never judge (audit 2026-10-09,
# finding C7). precode_gate and read_ledger judge only source files (their SRC_EXT), comment_claim_guard only the comment
# languages (devkit_profile.SLASH_COMMENT_EXTS + its # languages): a bash check now exits 0 before python when no path
# value in the payload can be one of those — decision-neutral, since python exits 0 there without a decision or a log line.
#   1. a non-source path: rc 0 and python NOT started (a python3 shim on PATH logs each start);
#   2. a source path, also one spelled with a JSON escape (A.kt): python starts and decides as before;
#   3. ratchet: the bash extension lists equal the python ones (SRC_EXT, SLASH_COMMENT_EXTS + the # languages).
# churn_guard has no such path: it judges every file type from the transcript.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="${FP_HOOKS:-$DEVKIT_DIR/hooks}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REAL_PY="$(command -v python3)" || { echo "skip: python3 missing"; exit 0; }

mkdir -p "$TMP/bin" "$TMP/repo/src"
printf '#!/bin/sh\necho start >> "%s/py.log"\nexec "%s" "$@"\n' "$TMP" "$REAL_PY" > "$TMP/bin/python3"
chmod +x "$TMP/bin/python3"
R="$TMP/repo"
git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
for f in README.md build.gradle conf.json A.kt b.go; do printf 'x\n' > "$R/src/$f"; done
git -C "$R" add -A && git -C "$R" commit -qm init
: > "$TMP/empty.jsonl"

# run <hook> <event> <tool> <file_path as it goes in the JSON> [new_string]: rc in $RC, "1" in $PY when python started
run() {
  local h="$1" ev="$2" tool="$3" fp="$4" ns="${5:-x}"
  : > "$TMP/py.log"
  if [ "$tool" = Read ]; then
    printf '{"session_id":"s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","tool_name":"Read","tool_input":{"file_path":"%s"},"tool_response":{"type":"text","file":{"filePath":"%s","content":"x\\n"}}}' \
      "$TMP/empty.jsonl" "$R" "$ev" "$fp" "$fp" > "$TMP/in.json"
  else
    printf '{"session_id":"s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","tool_name":"%s","tool_input":{"file_path":"%s","old_string":"x","new_string":"%s"}}' \
      "$TMP/empty.jsonl" "$R" "$ev" "$tool" "$fp" "$ns" > "$TMP/in.json"
  fi
  ( cd "$R" && PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/$h" < "$TMP/in.json" > /dev/null 2>&1 )
  RC=$?
  PY=$([ -s "$TMP/py.log" ] && echo 1 || echo 0)
}

# 1. paths the hook never judges: no python
for f in README.md build.gradle conf.json; do
  run precode_gate.sh PreToolUse Edit "$R/src/$f"
  [ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "precode_gate: $f allowed without python" || fail "precode_gate: $f rc=$RC python=$PY (want 0/0)"
  run read_ledger.sh PostToolUse Read "$R/src/$f"
  [ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "read_ledger: $f skipped without python" || fail "read_ledger: $f rc=$RC python=$PY (want 0/0)"
  run comment_claim_guard.sh PostToolUse Edit "$R/src/$f" '// covered by FooTest'
  [ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "comment_claim_guard: $f skipped without python" || fail "comment_claim_guard: $f rc=$RC python=$PY (want 0/0)"
done

# 2. source paths: python decides, as before
run precode_gate.sh PreToolUse Edit "$R/src/A.kt"
[ "$RC" = 2 ] && [ "$PY" = 1 ] && ok "precode_gate: blind edit of A.kt still blocked by python" || fail "precode_gate: A.kt rc=$RC python=$PY (want 2/1)"
run precode_gate.sh PreToolUse Edit "$R/src/A\\u002ekt"
[ "$RC" = 2 ] && [ "$PY" = 1 ] && ok "precode_gate: A\\u002ekt (JSON escape) still reaches python and is blocked" \
  || fail "precode_gate: A\\u002ekt rc=$RC python=$PY (want 2/1)"
run comment_claim_guard.sh PostToolUse Edit "$R/src/b.go" '// covered by FooTest'
[ "$RC" = 2 ] && [ "$PY" = 1 ] && ok "comment_claim_guard: claim in b.go still warns" || fail "comment_claim_guard: b.go rc=$RC python=$PY (want 2/1)"
run comment_claim_guard.sh PostToolUse Write "$R/scripts/x.sh" '# covered by FooTest'
[ "$RC" = 2 ] && [ "$PY" = 1 ] && ok "comment_claim_guard: claim in x.sh still warns" || fail "comment_claim_guard: x.sh rc=$RC python=$PY (want 2/1)"
run read_ledger.sh PostToolUse Read "$R/src/A.kt"
grep -q "A.kt" "$R/.claude/audit-gate/read_ledger.tsv" 2>/dev/null && [ "$PY" = 1 ] && ok "read_ledger: A.kt still recorded" \
  || fail "read_ledger: A.kt not recorded (python=$PY)"
run precode_gate.sh PreToolUse Edit "$R/src/A.kt"
[ "$RC" = 0 ] && ok "precode_gate: A.kt passes after the Read" || fail "precode_gate: A.kt after the Read rc=$RC (want 0)"

# 3. ratchet: the bash lists are the python ones
"$REAL_PY" -I - "$HOOKS" <<'PY' || FAILS=$((FAILS + 1))
import os, re, sys
hooks = sys.argv[1]
def bash_exts(f, var):
    m = re.search(var + r"""='\\\.\(([a-z|]+)\)""", open(os.path.join(hooks, f)).read())
    return set("." + e for e in m.group(1).split("|")) if m else None
def py_src(f):
    m = re.search(r"SRC_EXT = \(([^)]*)\)", open(os.path.join(hooks, f)).read())
    return set(re.findall(r'"(\.[a-z]+)"', m.group(1)))
sys.path.insert(0, hooks)
from devkit_profile import SLASH_COMMENT_EXTS
cc = open(os.path.join(hooks, "comment_claim_guard.sh")).read()
hash_exts = set(re.findall(r'"(\.[a-z]+)"', "".join(re.findall(r"HASH_(?:SOURCE|SCRIPT)_EXTS = \(([^)]*)\)", cc))))
bad = 0
for f, var, want in (("precode_gate.sh", "PG_SRC", py_src("precode_gate.sh")), ("read_ledger.sh", "RL_SRC", py_src("read_ledger.sh")),
                     ("comment_claim_guard.sh", "CC_EXT", set(SLASH_COMMENT_EXTS) | hash_exts)):
    got = bash_exts(f, var)
    if got == want:
        print("✔ ratchet: %s %s = the python list (%d extensions)" % (f, var, len(want)))
    else:
        bad = 1
        print("✖ ratchet: %s %s differs from python: missing %s, extra %s" % (f, var, sorted(want - (got or set())), sorted((got or set()) - want)))
sys.exit(bad)
PY

[ "$FAILS" -eq 0 ] && echo "✅ test_edit_hook_fast_path: all passed" || { echo "❌ test_edit_hook_fast_path: $FAILS failed"; exit 1; }
