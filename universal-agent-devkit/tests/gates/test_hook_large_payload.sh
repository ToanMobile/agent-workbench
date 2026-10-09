#!/usr/bin/env bash
# A hook payload bigger than the OS limit for ONE environment variable (Linux: 128 KiB per string; macOS: ARG_MAX ≈ 1 MiB
# for args + env together) must not switch a hook off (audit 2026-10-09, finding C1). The hooks handed the whole JSON to
# python in an env var (PG_INPUT="${INPUT}" python3 …): past the limit exec fails ("Argument list too long", rc 126) and the
# hook exits 0 — a blind Write of a big file passed precode_gate, a Write into the main checkout from a worktree session
# passed worktree_guard, a claim comment in a big .go file passed comment_claim_guard, churn_guard stayed quiet, and
# read_ledger dropped a big Read so precode_gate then BLOCKED the edit of the file just read. The Stop hooks with the same
# pattern failed open the same way. Every payload here is above 1.2 MB so the test is red on macOS too.
#   1. PreToolUse / PostToolUse: each decision with a big payload equals the one with a small payload (block stays block,
#      the read reaches the ledger);
#   2. Stop hooks: rc and stderr with a big last_assistant_message equal those with the same message unpadded, and two that
#      block (claim_check, test_evidence_gate) still block;
#   3. ratchet: no hook below passes the payload to python through an environment variable.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="${LP_HOOKS:-$DEVKIT_DIR/hooks}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

R="$TMP/repo"
mkdir -p "$R/src"
git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
for f in Big.kt Seen.kt Churn.kt; do printf 'class X\n' > "$R/src/$f"; done
printf 'package main\n' > "$R/src/big.go"
git -C "$R" add -A && git -C "$R" commit -qm init
: > "$TMP/empty.jsonl"

# worktree fixture: a session that STARTED in the linked worktree W writes into the main checkout M
M="$TMP/main"
mkdir -p "$M/src" && printf 'x\n' > "$M/src/a.kt"
git -C "$M" init -q . && git -C "$M" config user.email t@t && git -C "$M" config user.name t && git -C "$M" config commit.gpgsign false
git -C "$M" add -A && git -C "$M" commit -qm init && git -C "$M" worktree add -q --detach "$TMP/wt"
W="$TMP/wt"

# gen <out> <kind> <size> [args…]: a realistic Claude Code payload; size 0 = small, else padded to <size> bytes
gen() {
  python3 -I - "$@" <<'PY'
import json, sys
out, kind, size, args = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
def pad(head, unit):
    if not size:
        return head
    return head + unit * ((size - len(head)) // len(unit) + 1)
base = {"session_id": args[0], "transcript_path": args[1], "cwd": args[2]}
if kind == "write":           # args: sid tp cwd file
    d = dict(base, hook_event_name="PreToolUse", tool_name="Write",
             tool_input={"file_path": args[3], "content": pad("class Big {\n", "    val x = 1\n") + "}\n"})
elif kind == "goclaim":       # args: sid tp cwd file
    d = dict(base, hook_event_name="PostToolUse", tool_name="Write",
             tool_input={"file_path": args[3], "content": pad("package main\n// covered by FooTest\nfunc f() {}\n", "var x = 1\n")},
             tool_response={"type": "create", "filePath": args[3]})
elif kind == "edit":          # args: sid tp cwd file
    d = dict(base, hook_event_name="PostToolUse", tool_name="Edit",
             tool_input={"file_path": args[3], "old_string": "class X", "new_string": pad("class X {", "\n    val y = 2")},
             tool_response={"filePath": args[3]})
elif kind == "smalledit":     # args: sid tp cwd file
    d = dict(base, hook_event_name="PreToolUse", tool_name="Edit",
             tool_input={"file_path": args[3], "old_string": "class X", "new_string": "class Y"})
elif kind == "read":          # args: sid tp cwd file
    body = pad("class X\n", "// line of a long generated file\n")
    d = dict(base, hook_event_name="PostToolUse", tool_name="Read", tool_input={"file_path": args[3]},
             tool_response={"type": "text", "file": {"filePath": args[3], "content": body,
                            "numLines": body.count("\n"), "startLine": 1, "totalLines": body.count("\n")}})
elif kind == "stop":          # args: sid tp cwd message
    d = dict(base, hook_event_name="Stop", stop_hook_active=False, last_assistant_message=pad(args[3], " lorem ipsum dolor"))
json.dump(d, open(out, "w"), ensure_ascii=False)
PY
}
BIG=1300000
# run <hook> <payload file> [VAR=val…]: rc in $RC, stderr in $ERR
run() {
  local h="$1" p="$2"; shift 2
  ( cd "$TMP" && env CLAUDE_PROJECT_DIR="$R" "$@" bash "$HOOKS/$h" < "$p" > "$TMP/out" 2> "$TMP/err" )
  RC=$?
  ERR="$(cat "$TMP/err")"
}
toolong() { case "$ERR" in *"rgument list too long"*) echo " (python could not start: Argument list too long)" ;; esac; }

# ── 1. PreToolUse / PostToolUse ──────────────────────────────────────────────────────────────────────────────────────
gen "$TMP/p.json" write "$BIG" s1 "$TMP/empty.jsonl" "$R" "$R/src/Big.kt"
[ "$(wc -c < "$TMP/p.json")" -gt 1200000 ] || fail "payload generator: under 1.2 MB"
run precode_gate.sh "$TMP/p.json"
[ "$RC" = 2 ] && ok "precode_gate: blind Write of 1.3 MB into an unread file is blocked" \
  || fail "precode_gate: blind Write of 1.3 MB into an unread file rc=$RC (want 2)$(toolong)"

gen "$TMP/p.json" smalledit 0 s2 "$TMP/empty.jsonl" "$R" "$R/src/Seen.kt"
run precode_gate.sh "$TMP/p.json"
[ "$RC" = 2 ] || fail "fixture: an edit of Seen.kt before any Read should be blocked (rc=$RC)"
gen "$TMP/r.json" read "$BIG" s2 "$TMP/empty.jsonl" "$R" "$R/src/Seen.kt"
run read_ledger.sh "$TMP/r.json"
run precode_gate.sh "$TMP/p.json"
[ "$RC" = 0 ] && ok "read_ledger: a 1.3 MB Read reaches the ledger, the next edit of that file passes precode_gate" \
  || fail "read_ledger: a 1.3 MB Read was not recorded, precode_gate rc=$RC on the next edit (want 0)"

python3 -I -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({"type":"user","cwd":sys.argv[2],"sessionId":"w1","message":{"role":"user","content":"go"}})+"\n")' \
  "$TMP/wt.jsonl" "$W"
gen "$TMP/p.json" write 0 w1 "$TMP/wt.jsonl" "$W" "$M/src/a.kt"
( cd "$W" && env CLAUDE_PROJECT_DIR="$W" bash "$HOOKS/worktree_guard.sh" < "$TMP/p.json" > /dev/null 2>&1 ); RC=$?
[ "$RC" = 2 ] || fail "fixture: a small Write into the main checkout from the worktree session should be blocked (rc=$RC)"
gen "$TMP/p.json" write "$BIG" w1 "$TMP/wt.jsonl" "$W" "$M/src/a.kt"
( cd "$W" && env CLAUDE_PROJECT_DIR="$W" bash "$HOOKS/worktree_guard.sh" < "$TMP/p.json" > /dev/null 2> "$TMP/err" ); RC=$?
ERR="$(cat "$TMP/err")"
[ "$RC" = 2 ] && ok "worktree_guard: a 1.3 MB Write into the main checkout from a worktree session is blocked" \
  || fail "worktree_guard: a 1.3 MB Write into the main checkout rc=$RC (want 2)$(toolong)"

gen "$TMP/p.json" goclaim "$BIG" s3 "$TMP/empty.jsonl" "$R" "$R/src/big.go"
run comment_claim_guard.sh "$TMP/p.json"
[ "$RC" = 2 ] && ok "comment_claim_guard: a claim comment in a 1.3 MB .go file warns" \
  || fail "comment_claim_guard: a claim comment in a 1.3 MB .go file rc=$RC (want 2)$(toolong)"

python3 -I -c '
import json, sys
e = {"type": "tool_use", "name": "Edit", "input": {"file_path": sys.argv[2], "old_string": "a", "new_string": "b"}}
open(sys.argv[1], "w").write("".join(json.dumps({"message": {"id": "m%d" % i, "content": [dict(e, id="t%d" % i)]}}) + "\n" for i in range(3)))
' "$TMP/churn.jsonl" "$R/src/Churn.kt"
gen "$TMP/p.json" edit "$BIG" s4 "$TMP/churn.jsonl" "$R" "$R/src/Churn.kt"
run churn_guard.sh "$TMP/p.json"
[ "$RC" = 2 ] && ok "churn_guard: the 3rd blind edit warns with a 1.3 MB new_string" \
  || fail "churn_guard: the 3rd blind edit with a 1.3 MB new_string rc=$RC (want 2)$(toolong)"

# ── 2. Stop hooks: big == small ──────────────────────────────────────────────────────────────────────────────────────
# hook|message|rc the small payload must give ("" = whatever it gives, then big must equal it)
for c in "claim_check.sh|Lỗi nằm ở Ghost.kt:4211 trong nhánh cleanup.|2" \
         "test_evidence_gate.sh|Đã chạy targeted test, 12/12 test pass.|2" \
         "review_gate.sh|Đã đọc qua module.|" "security_gate.sh|Đã đọc qua module.|" "proof_gate.sh|Đã đọc qua module.|" \
         "foreign_repo_gate.sh|Đã đọc qua module.|" "worktree_merge_gate.sh|Đã đọc qua module.|"; do
  IFS='|' read -r h msg want <<< "$c"
  gen "$TMP/s.json" stop 0 "small-$h" "$TMP/empty.jsonl" "$R" "$msg"
  gen "$TMP/b.json" stop "$BIG" "big-$h" "$TMP/empty.jsonl" "$R" "$msg"
  run "$h" "$TMP/s.json"; RC_S=$RC; ERR_S="$(printf '%s' "$ERR" | sed 's/small-/X-/g')"
  run "$h" "$TMP/b.json"; ERR_B="$(printf '%s' "$ERR" | sed 's/big-/X-/g')"
  if [ -n "$want" ] && [ "$RC_S" != "$want" ]; then
    fail "fixture: $h small payload rc=$RC_S (want $want)"
  elif [ "$RC" = "$RC_S" ] && [ "$ERR_B" = "$ERR_S" ]; then
    ok "$h: a 1.3 MB Stop payload gives the same decision as the small one (rc $RC)"
  else
    fail "$h: 1.3 MB Stop payload rc=$RC vs small rc=$RC_S$(toolong)"
  fi
done

# ── 3. ratchet: no payload in an environment variable ────────────────────────────────────────────────────────────────
for h in precode_gate.sh worktree_guard.sh comment_claim_guard.sh churn_guard.sh read_ledger.sh claim_check.sh review_gate.sh \
         security_gate.sh test_evidence_gate.sh testsourceset_gate.sh proof_gate.sh foreign_repo_gate.sh worktree_merge_gate.sh \
         prompt_context.sh; do
  hit="$(grep -nE '(^|[[:space:](])[A-Z_]+="\$\{?(INPUT|PAYLOAD)\}?"[[:space:]]' "$HOOKS/$h" | head -1)"
  [ -z "$hit" ] && ok "ratchet: $h passes no payload through the environment" \
    || fail "ratchet: $h passes the payload in an env var: $hit"
done

[ "$FAILS" -eq 0 ] && echo "✅ test_hook_large_payload: all passed" || { echo "❌ test_hook_large_payload: $FAILS failed"; exit 1; }
