#!/usr/bin/env bash
# Regression (DevKit speed, OfficeReader): the secret scan of the post-fix gate decoded every changed file as text and ran
# its 21 regexes over it, binary assets included: one 13.4 MB document_scanner.tflite cost 2.9 s of the 4.0 s scan (and
# so of every gate run in a dirty tree); a Unity project changes far larger binaries. Random bytes can also look like a
# token and block the gate. A changed file whose first 8 KB hold a NUL byte is binary: its CONTENT is not scanned; its
# NAME still is (keystores, provisioning files, id_ed25519 ...).
#   1. a text file with a token is still rejected (the scan itself is unchanged)
#   2. a binary file (NUL in the first 8 KB) that contains a token-looking string is not rejected
#   3. a binary file with a forbidden NAME (.jks) is still rejected
#   4. a text file whose only NUL byte lies past the first 8 KB is still scanned (the window is the sniff, not the file)
#   5. a 25 MB binary changes the gate's run time by under 3 s compared with no binary (it used to add ~5 s)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"
TOKEN="sk_live_$(python3 -c 'print("e" * 24, end="")')"

make_repo() {
  rm -rf "$R" && mkdir -p "$R/src" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  git add -A && git commit -qm init
}
run_gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --lang en --run-tests --allow-no-tests 2>&1)"; RC=$?; }

make_repo
printf 'const client = new Client("%s");\n' "$TOKEN" > client.js
run_gate
[ "$RC" = 1 ] && ok "1: a token in a text file is still rejected" || { bad "1: text token not rejected (exit $RC)"; printf '%s\n' "$OUT" | tail -8; }

make_repo
python3 -c 'import sys; sys.stdout.buffer.write(b"TFL3 model header, text first " + b"\x00\x01\x02" + b"\x00" * 64 + sys.argv[1].encode() + b"\x00\xff" * 32)' "$TOKEN" > model.tflite
run_gate
[ "$RC" = 0 ] && ok "2: a token-looking string inside a binary file is not a finding" || { bad "2: binary content was scanned and rejected (exit $RC)"; printf '%s\n' "$OUT" | tail -8; }

make_repo
python3 -c 'import sys; sys.stdout.buffer.write(b"\x00\x01\x02keystore" + b"\x00" * 64)' > release.jks
run_gate
[ "$RC" = 1 ] && ok "3: a binary file with a forbidden name (.jks) is still rejected by name" || { bad "3: forbidden binary name accepted (exit $RC)"; printf '%s\n' "$OUT" | tail -8; }

make_repo
python3 -c 'import sys; sys.stdout.buffer.write(b"// pad\n" * 2000 + sys.argv[1].encode() + b"\n\x00\n")' "const c = \"$TOKEN\";" > late_nul.js
run_gate
[ "$RC" = 1 ] && ok "4: a NUL past the first 8 KB does not hide a token in a text file" || { bad "4: late NUL made the file look binary (exit $RC)"; printf '%s\n' "$OUT" | tail -8; }

python3 -c 'import os,sys; sys.stdout.buffer.write(b"\x00" + os.urandom(25 * 1024 * 1024))' > big.tflite
s=$(python3 -c 'import time; print(time.time())'); run_gate; e=$(python3 -c 'import time; print(time.time())')
with=$(python3 -c "print(round($e - $s, 1))")
make_repo
echo "// edit" >> src/Core.kt
s=$(python3 -c 'import time; print(time.time())'); run_gate; e=$(python3 -c 'import time; print(time.time())')
without=$(python3 -c "print(round($e - $s, 1))")
if python3 -c "import sys; sys.exit(0 if $with - $without < 3.0 else 1)"; then ok "5: a 25 MB binary adds ${with}s - ${without}s < 3 s to the gate"
else bad "5: a 25 MB binary adds $with - $without s to the gate (it is still being scanned)"; fi

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "binary skip: $FAILS FAILED"; exit 1; fi
echo "binary skip: all checks passed"
