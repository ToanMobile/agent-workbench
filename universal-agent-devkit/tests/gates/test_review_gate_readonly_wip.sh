#!/usr/bin/env bash
# issue #2: review_gate.sh blamed a session for a dirty file because a READ-ONLY command named it (`git diff src/foo.py`, `grep`, `dotnet test`)
# inside a Bash window that is open for 2 h (43 auto-releases, 10 wrongful blocks); and a mid-work reply with no status line and no outcome
# claim was forced through the review gate. Now: a command whose every segment only reads is not an edit; an open window is 300 s; a reply
# without XONG / an outcome claim is work in progress (same rule as regression_gate: status_optional).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P/scripts"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo "def f(): return 1" > scripts/app.py && git add -A && git commit -qm i)
P="$(cd "$P" && pwd -P)"
TR="$TMP/t.jsonl"
cat > "$TMP/ev.py" <<'PY'
import json, sys, time, datetime
kind, tr, at = sys.argv[1], sys.argv[2], float(sys.argv[3]); a = sys.argv[4:]
stamp = datetime.datetime.fromtimestamp(time.time() + at, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
if kind == "user":
    rec = {"type": "user", "message": {"role": "user", "content": a[0]}}
elif kind == "bash":
    rec = {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": a[0], "name": "Bash", "input": {"command": a[1]}}]}}
else:
    rec = {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": a[0], "content": "ok"}]}}
rec["timestamp"] = stamp
open(tr, "a").write(json.dumps(rec) + "\n")
PY
ev() { python3 "$TMP/ev.py" "$1" "$TR" "${@:2}"; }
setmtime() { python3 -c 'import os, sys, time; t = time.time() + float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$2"; }
stop() {   # stop [last_assistant_message]
  python3 -c 'import json,sys; d={"session_id":"s","transcript_path":sys.argv[1],"hook_event_name":"Stop"}
if len(sys.argv) > 2: d["last_assistant_message"] = sys.argv[2]
print(json.dumps(d))' "$TR" "$@" \
    | REVIEW_GATE_OCR=0 REVIEW_GATE_REQUIRE_OCR=0 CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"
}
reset() { : > "$TR"; python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$P/.claude/audit-gate"; git -C "$P" reset -q --hard; }
change() { echo "def f(): return $1" > "$P/scripts/app.py"; setmtime "$P/scripts/app.py" "$2"; }
expect() { local want="$1" label="$2"; shift 2; stop "$@"; local rc=$?
  [ "$rc" = "$want" ] && ok "$label" || fail "$label: rc $rc (want $want), log: $(tail -1 "$P/.claude/audit-gate/review_gate.log" 2>/dev/null)"; }

# 1. a read-only command that names the dirty file, running while it changed (another session's save) is not this session's edit
for c in "git diff scripts/app.py" "git -C . log -p -- scripts/app.py" "grep -n f scripts/app.py" "cat scripts/app.py | head -5" "git status --short scripts/app.py"; do
  reset; ev bash -100 r1 "$c"; change 2 -99; ev result -98 r1
  expect 0 "read-only, names the file while it changed: not an edit ($c)"
done
# ... a writing command still is
reset; ev bash -100 r2 "sed -i '' s/1/3/ scripts/app.py"; change 3 -99; ev result -98 r2
expect 2 "sed -i naming the file: still an edit"
reset; ev bash -100 r3 "git diff scripts/app.py > /tmp/x; sed -i '' s/1/3/ scripts/app.py"; change 3 -99; ev result -98 r3
expect 2 "a read-only segment next to a writing one: still an edit"

# 2. an open window (no result) ends 300 s after its start, not 2 h
reset; ev bash -3600 r4 "python3 tools/regen.py scripts/app.py"; change 4 -60
expect 0 "an open run started 1 h ago: a change now is not its own"
reset; ev bash -200 r5 "python3 tools/regen.py scripts/app.py"; change 5 -60
expect 2 "an open run started 200 s ago: a change within 300 s is its own"

# 3. a mid-work reply with no status line and no outcome claim is work in progress (the review is asked at the handover)
reset; ev user -300 "go"; ev bash -100 r6 "python3 - <<'EOF'
open('scripts/app.py', 'w').write('x')
EOF"; change 6 -99; ev result -98 r6
expect 2 "no reply text: the gate holds"
expect 0 "a reply with no status line and no outcome claim: work in progress, no review asked" "Đang xem file scripts/app.py, bước tiếp theo là chạy test."
expect 2 "a reply claiming an outcome: the gate holds" "Đã fix xong lỗi, test pass."

if [ "$FAILS" -ne 0 ]; then echo "review gate readonly/wip: $FAILS FAILED"; exit 1; fi
echo "review gate readonly/wip: all checks passed"
