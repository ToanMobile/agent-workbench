#!/usr/bin/env bash
# #742 OCR b266f3d4 (known_patterns.py:156): in `git diff -U0`, an added line whose text starts with "++ " is printed as
# "+++ …" and was read as a new file header: the path switched to that text (or to None for "++ /dev/null") and every later
# added line of the file was matched against the wrong globs or skipped, so a known-bug pattern slipped past the P0 recurring-
# bug scan. A "+++ " line is a header only outside a hunk.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P/.agents"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && echo x > README && git add -A && git commit -qm i)
printf '### [INSTINCT-001] Silent except\n- **Quy tắc phòng ngừa & Cách fix:** log it\n- **detect:** `except:\\s*pass`\n- **detect-glob:** `*.py`\n' > "$P/.agents/instincts.md"
(cd "$P" && git add -A && git commit -qm reg && printf 'v = 1\n' > app.py && git add app.py && git commit -qm app)
BASE="$(git -C "$P" rev-parse HEAD)"
hits() {   # files of the registry findings; a scan error (exit 2, no --out) is a test failure, never a stale file
  rm -f "$TMP/reg.json"
  python3 -I "$DEVKIT_DIR/bin/known_patterns.py" --repo "$P" scan --base "$BASE" --out "$TMP/reg.json" >/dev/null 2>&1
  [ "$?" -le 1 ] && [ -f "$TMP/reg.json" ] || { echo "SCAN-ERROR"; return; }
  python3 -I -c 'import json,sys; print(" ".join(sorted({f.get("file","") for f in json.load(open(sys.argv[1])).get("findings",[])})))' "$TMP/reg.json"
}

# 1. control: the pattern on an added line of a tracked .py file is found
printf 'v = 1\ntry:\n    g()\nexcept: pass\n' > "$P/app.py"
h="$(hits)"; [ "$h" = app.py ] && ok "known pattern on an added line is found" || fail "control: hits='$h'"

# 2. an added line "++ /dev/null" before it does not hide it
printf 'v = 1\ns = """\n++ /dev/null\n"""\ntry:\n    g()\nexcept: pass\n' > "$P/app.py"
h="$(hits)"; [ "$h" = app.py ] && ok "an added '++ /dev/null' line does not hide later lines" || fail "'++ /dev/null' hid the pattern: hits='$h'"

# 3. an added line "++ b/notes.md" does not move later lines to another path (where the *.py glob does not apply)
printf 'v = 1\ns = """\n++ b/notes.md\n"""\ntry:\n    g()\nexcept: pass\n' > "$P/app.py"
h="$(hits)"; [ "$h" = app.py ] && ok "an added '++ b/<path>' line does not switch the path" || fail "'++ b/notes.md' switched the path: hits='$h'"

# 4. two files in one diff: the header of the second file is still read (path switches back to a real header)
printf 'try:\n    g()\nexcept: pass\n' > "$P/z.py"; git -C "$P" add z.py
printf 'v = 1\n++ b/notes.md\n' > "$P/app.py"
h="$(hits)"; [ "$h" = z.py ] && ok "the next real file header is still read" || fail "two-file diff: hits='$h'"

[ "$FAILS" -eq 0 ] && { echo "PASS: test_known_patterns_plus_line"; exit 0; } || { echo "FAIL: $FAILS"; exit 1; }
