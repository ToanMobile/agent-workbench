#!/usr/bin/env bash
# hooks/review_timing_guard.sh (critical scan 31/10, BUG-REV-timing-*): the edit that fired the PostToolUse was counted as an
# open burst, so "a new fix opened after an unreviewed one" was always read as mid-burst and the warning never fired; a review
# through bin/review-fanout.sh (the 4-way gate) did not count as a review; MultiEdit was not an edit; a relative file_path was
# resolved against the hook's own cwd.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/review_timing_guard.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/proj"; mkdir -p "$P/src" && git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t
printf 'class A\n' > "$P/src/A.kt"; printf 'class B\n' > "$P/src/B.kt"; git -C "$P" add -A && git -C "$P" commit -qm i
printf 'class A { val x = 1 }\n' > "$P/src/A.kt"; printf 'class B { val y = 2 }\n' > "$P/src/B.kt"   # both differ from HEAD

# transcript <steps…>: e:<tool>:<file> = an edit, b:<cmd> = a Bash call; the LAST step is the edit that fires the hook
mk() {
  python3 - "$TMP/t.jsonl" "$@" <<'PY'
import json, sys
out, steps = sys.argv[1], sys.argv[2:]
with open(out, "w") as f:
    for i, s in enumerate(steps):
        kind, _, rest = s.partition(":")
        if kind == "e":
            tool, _, fp = rest.partition(":")
            c = {"type": "tool_use", "id": f"t{i}", "name": tool, "input": {"file_path": fp, "edits": [] if tool == "MultiEdit" else None}}
        else:
            c = {"type": "tool_use", "id": f"t{i}", "name": "Bash", "input": {"command": rest}}
        f.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [c]}}) + "\n")
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": "ok"}]}}) + "\n")
    print(f"t{len(steps) - 1}")
PY
}
fire() {   # fire <tool_use_id> <file_path as sent>
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":sys.argv[1],"cwd":sys.argv[2],"hook_event_name":"PostToolUse",
    "tool_name":"Edit","tool_use_id":sys.argv[3],"tool_input":{"file_path":sys.argv[4]}}))' "$TMP/t.jsonl" "$P" "$1" "$2" \
    | ( cd "$TMP" && CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null 2>"$TMP/err" ); echo $?
}

id=$(mk "e:Edit:$P/src/A.kt" "b:./gradlew test" "e:Edit:$P/src/B.kt")
[ "$(fire "$id" "$P/src/B.kt")" = 2 ] && grep -q "REVIEW-TIMING" "$TMP/err" && ok "second fix after an unreviewed, tested first fix: warned" || fail "no warning for fix 2"
id=$(mk "e:Edit:$P/src/A.kt" "b:./gradlew test" "e:Edit:src/B.kt")
[ "$(fire "$id" "src/B.kt")" = 2 ] && ok "relative file_path resolved against the session cwd" || fail "relative path not resolved"
id=$(mk "e:MultiEdit:$P/src/A.kt" "b:./gradlew test" "e:Edit:$P/src/B.kt")
[ "$(fire "$id" "$P/src/B.kt")" = 2 ] && ok "a MultiEdit opens a burst" || fail "MultiEdit not counted"
id=$(mk "e:Edit:$P/src/A.kt" "b:./gradlew test" "b:bash .agents/devkit/bin/review-fanout.sh --base main" "e:Edit:$P/src/B.kt")
[ "$(fire "$id" "$P/src/B.kt")" = 0 ] && ok "a review-fanout.sh run counts as the review" || fail "review-fanout not counted as review"
id=$(mk "e:Edit:$P/src/A.kt" "e:Edit:$P/src/B.kt")
[ "$(fire "$id" "$P/src/B.kt")" = 0 ] && ok "control: edits in one burst are not nagged" || fail "mid-burst warned"
id=$(mk "e:Edit:$P/src/B.kt")
[ "$(fire "$id" "$P/src/B.kt")" = 0 ] && ok "control: the first fix is not nagged" || fail "first fix warned"

[ "$FAILS" = 0 ] && { echo "review timing guard bursts: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
