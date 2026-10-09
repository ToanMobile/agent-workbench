#!/usr/bin/env bash
# hooks/comment_claim_guard.sh read only FULL-LINE comments (2026-10-09 follow-up, plan docs/plans/audit-2026-10-09-followup.md
# step 3 item 3): a claim written in a Python docstring, or after code on the same line, exited 0 while the same words in a
# full-line comment exit 2 (the cases below spell them out). Python docstrings (a string statement that starts a line with triple
# quotes) and trailing comments (a # or // outside any
# string literal, after code) are now read like full-line comments. A # or // inside a string, a plain trailing comment, a tool
# marker and a triple-quoted string that is data (assigned) stay clean.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${CC_HOOK:-$DEVKIT_DIR/hooks/comment_claim_guard.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

R="$TMP/repo"
mkdir -p "$R/app" "$R/scripts"
git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
: > "$TMP/empty.jsonl"

# check <want rc> <label> <file> <tool: Write|Edit> <text, \n = newline> [VAR=val…]
check() {
  local want="$1" label="$2" file="$3" tool="$4" text="$5"; shift 5
  python3 -I -c '
import json, sys
tool, f, text = sys.argv[1], sys.argv[2], sys.argv[3].replace("\\n", "\n")
inp = {"file_path": f, "content": text} if tool == "Write" else {"file_path": f, "old_string": "pass", "new_string": text}
print(json.dumps({"session_id": "s", "transcript_path": sys.argv[4], "cwd": sys.argv[5], "hook_event_name": "PostToolUse",
                  "tool_name": tool, "tool_input": inp, "tool_response": {"filePath": f}}))' "$tool" "$R/$file" "$text" "$TMP/empty.jsonl" "$R" \
    > "$TMP/in.json"
  ( cd "$R" && env CLAUDE_PROJECT_DIR="$R" "$@" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  [ "$rc" = "$want" ] && ok "rc $rc: $label" || fail "rc $rc (want $want): $label — $(head -c 160 "$TMP/err" | tr '\n' ' ')"
}

# claims in docstrings warn
check 2 ".py: one-line docstring 'Covered by test_orders'"        app/orders.py Write 'def total(xs):\n    """Covered by test_orders."""\n    return sum(xs)\n'
check 2 ".py: multi-line docstring, claim on the 3rd line"        app/orders.py Write 'def total(xs):\n    """\n    Sum of the order lines.\n    Never called outside the importer.\n    """\n    return sum(xs)\n'
check 2 ".py: module docstring on line 1"                         app/mod.py    Write '"""Not used anywhere else."""\nX = 1\n'
check 2 ".py: single-quote docstring, Vietnamese claim"           app/util.py   Write "def f():\n    '''hàm này đã được test ở chỗ khác'''\n    return 1\n"
check 2 ".py Edit: docstring inside the edited text"              app/orders.py Edit  '    """covered by OrdersTest"""\n    return 0'
# claims after code warn
check 2 ".py: trailing '# covered by test_orders'"                app/orders.py Write 'x = compute()  # covered by test_orders\n'
check 2 ".kt: trailing '// already tested in OrdersTest'"         app/Orders.kt Write 'val a = 1 // already tested in OrdersTest\n'
check 2 ".go: trailing '// never called elsewhere'"               app/main.go   Write 'package main\nvar x = f() // never called elsewhere\n'
check 2 ".sh: trailing '# not used anywhere else'"                scripts/run.sh Write 'echo hi  # not used anywhere else\n'
check 2 ".py: a string, then a trailing claim"                    app/orders.py Write 'MSG = "plain"  # covered by test_orders\n'

# clean: nothing to judge
check 0 ".py: docstring without a claim"                          app/orders.py Write 'def total(xs):\n    """Sum the order lines."""\n    return sum(xs)\n'
check 0 ".py: a claim in an ASSIGNED triple-quoted string (data)" app/sql.py    Write 'SQL = """\ncovered by test_orders\n"""\n'
check 0 ".py: '#' inside a string is not a comment"               app/msg.py    Write 'MSG = "covered by # test_orders"\n'
check 0 ".go: '//' inside a string is not a comment"              app/main.go   Write 'package main\nvar u = "http://x.y/never called"\n'
check 0 ".go: plain trailing comment"                             app/main.go   Write 'package main\nvar x = f() // keep in sync with the proto\n'
check 0 ".py: trailing tool marker"                               app/orders.py Write 'import os  # noqa: F401 covered by the linter config\nx = 1  # type: ignore\n'
check 0 ".py: a URL with // after code"                           app/msg.py    Write 'URL = "http://example.com/never called"\n'
check 0 ".py when the profile has no .py (gated like //)"         app/orders.py Write 'def f():\n    """covered by test_orders"""\n' DEVKIT_SOURCE_EXTS=.kt
check 0 ".md is not code"                                         notes.md      Write 'x  # covered by test_orders\n'
# the full-line forms are unchanged
check 2 ".py: full-line '# covered by' (control)"                 app/orders.py Write '# covered by test_orders\nX = 1\n'
check 2 ".go: full-line '// covered by' (control)"                app/main.go   Write 'package main\n// covered by FooTest\nfunc f() {}\n'

[ "$FAILS" -eq 0 ] && echo "✅ test_comment_claim_docstring_trailing: all passed" || { echo "❌ test_comment_claim_docstring_trailing: $FAILS failed"; exit 1; }
