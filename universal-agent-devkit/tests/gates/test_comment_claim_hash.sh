#!/usr/bin/env bash
# hooks/comment_claim_guard.sh read only //-comment languages, so a claim comment in Python (the backend profile's main
# language), Ruby, shell or YAML was never checked (audit 2026-10-09, finding C4): `# covered by test_x` in a .py exited 0
# while the same text after // in a .go exited 2. Full-line # comments are now read for .py / .rb when the active profile
# lists them (like the // languages) and for .sh / .bash / .zsh / .yaml / .yml always; a shebang, a `# -*- coding` line and
# tool markers (`# type:`, `# noqa`, `# pragma:`, `# pylint:`, `# shellcheck disable=…`) are not comments to judge.
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
mkdir -p "$R/app" "$R/scripts" "$R/.github/workflows"
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

# claims in # comments warn
check 2 ".py Write: '# covered by test_orders'"          app/orders.py Write '# covered by test_orders\ndef total(xs):\n    return sum(xs)\n'
check 2 ".py Edit: '# never called anywhere else'"       app/orders.py Edit  '    # never called anywhere else\n    return 0'
check 2 ".py: Vietnamese 'đã test' claim"                app/util.py   Write '#!/usr/bin/env python3\n# hàm này đã được test ở chỗ khác\nX = 1\n'
check 2 ".rb: '# only used by the importer'"             app/job.rb    Write '# only used by the importer\nclass Job; end\n'
check 2 ".sh: '# already tested on macOS'"               scripts/run.sh Write '#!/usr/bin/env bash\n# already tested on macOS\necho hi\n'
check 2 ".yml: '# covered by the nightly job'"           .github/workflows/ci.yml Write 'on: push\n# covered by the nightly job\njobs: {}\n'
check 2 ".sh under a profile without .sh (always read)"  scripts/run.sh Write '# không dùng ở đâu nữa\necho hi\n' DEVKIT_SOURCE_EXTS=.kt
# no false positives: shebang, coding line, tool markers, plain comments, claim words outside a comment
check 0 ".py: shebang, coding line, type/noqa/pragma/pylint markers" app/clean.py Write \
  '#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\n# type: ignore\n# noqa: E501\n# pragma: no cover\n# pylint: disable=invalid-name\n# Sum the order lines.\nX = 1\n'
check 0 ".sh: shebang + shellcheck directive + plain comment" scripts/ok.sh Write \
  '#!/bin/bash\n# shellcheck disable=SC2086\n# Build the bundle, then sign it.\necho ok\n'
check 0 ".py: claim words in a string, not a comment"   app/msg.py    Write 'MSG = "covered by test_orders"\n'
check 0 ".py when the profile has no .py (gated like //)" app/orders.py Write '# covered by test_orders\nX = 1\n' DEVKIT_SOURCE_EXTS=.kt
check 0 ".md is not code"                                 notes.md      Write '# covered by test_orders\n'
# the // languages are unchanged
check 2 ".go: '// covered by FooTest' (control)"          app/main.go   Write 'package main\n// covered by FooTest\nfunc f() {}\n'
check 0 ".go: '# covered by' is not a Go comment"         app/main.go   Write 'package main\n# covered by FooTest\n'

[ "$FAILS" -eq 0 ] && echo "✅ test_comment_claim_hash: all passed" || { echo "❌ test_comment_claim_hash: $FAILS failed"; exit 1; }
