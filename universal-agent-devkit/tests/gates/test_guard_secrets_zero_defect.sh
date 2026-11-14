#!/usr/bin/env bash
# Zero-defect oracle for hooks/guard-secrets.py (PreToolUse Bash|Read|Grep), three root causes found by the 2026-11-14 review:
#  C3a  the hook's secret-name list was narrower than the gate's FORBIDDEN_SECRET_FILES: `.env.production.local`, `.envrc`,
#       `local.properties`, `google-services.json`, keystores, `.netrc`, `.git-credentials`... could be read (fail open);
#  C3d  a command that only NAMES a secret file and never reads its content (`test -f`, `ls`, `git rm --cached`, a grep PATTERN,
#       a line appended to .gitignore) was refused (false block); each allowed form has a "still denied" control beside it;
#  C3e  `grep -r KEY .` prints the content of a dotenv file in the tree although the command names no secret file.
# Two-way: every family has cases that must be denied and cases that must pass. Only the hook runs here, never the command.
# GUARD overrides the hook under test. bash 3.2 compatible. Payloads live in this file: the session's own guard refuses a Bash
# command that names a secret file.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="${GUARD:-$DEVKIT_DIR/hooks/guard-secrets.py}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
LOG="$TMP/results.log"; : > "$LOG"
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"              # default cwd of a case: a directory with nothing in it
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
[ -f "$GUARD" ] || { echo "✖ $GUARD does not exist"; exit 1; }

# verdict <tool> <value> [cwd] -> deny | allow | error | crash
#   error = the hook's own fail-closed "internal hook error" deny (a broken hook must not count as a correct deny);
#   crash = non-zero exit, or nothing on stdout with something on stderr (must not count as a correct allow).
verdict() {
  python3 - "$GUARD" "$1" "$2" "${3:-$EMPTY}" <<'PY'
import json, subprocess, sys
guard, tool, value, cwd = sys.argv[1:5]
if tool == "Grep":   # value = <path>||<glob>; an empty path = the tool's default (cwd)
    path, _, glob = value.partition("||")
    ti = {"pattern": "KEY"}
    if path:
        ti["path"] = path
    if glob:
        ti["glob"] = glob
else:
    ti = {{"Bash": "command", "Read": "file_path"}[tool]: value}
payload = {"session_id": "s", "hook_event_name": "PreToolUse", "cwd": cwd, "tool_name": tool, "tool_input": ti}
p = subprocess.run([sys.executable, guard], input=json.dumps(payload), capture_output=True, text=True, timeout=30, cwd=cwd)
if p.returncode != 0 or (not p.stdout.strip() and p.stderr.strip()):
    print("crash")
elif "internal hook error" in p.stdout:
    print("error")
elif '"permissionDecision": "deny"' in p.stdout:
    print("deny")
else:
    print("allow")
PY
}

# expect <group> <allow|deny> <tool> <value> [cwd] [note]
expect() {
  local got; got="$(verdict "$3" "$4" "${5:-}")"
  local label="$1 want $2: $3: $4${6:+  ($6)}"
  if [ "$got" = "$2" ]; then echo "✔ $label"; echo "$1 $2 ok" >> "$LOG"
  else echo "✖ $label: got $got"; echo "$1 $2 FAIL" >> "$LOG"; FAILS=$((FAILS + 1)); fi
}

# ---------------------------------------------------------------------------------------------------------------------
# C3a: every secret file name the gate forbids is refused by the hook too, through Bash (cat / head / source) and Read / Grep.
# Lines: <name as typed in a shell><TAB><absolute path for the Read / Grep tool>
while IFS="$(printf '\t')" read -r name abs; do
  [ -n "$name" ] || continue
  expect C3a deny Bash "cat $name"
  expect C3a deny Bash "head -5 $name"
  expect C3a deny Bash "source $name"
  expect C3a deny Read "$abs"
  expect C3a deny Grep "$abs"
done <<'EOF'
.env.production.local	/repo/.env.production.local
.env.development.local	/repo/.env.development.local
.env.test.local	/repo/.env.test.local
.env.backup	/repo/.env.backup
.env.prod.local	/repo/.env.prod.local
.env.uat	/repo/.env.uat
.envrc	/repo/.envrc
.dev.vars	/repo/.dev.vars
local.properties	/repo/local.properties
app/google-services.json	/repo/app/google-services.json
GoogleService-Info.plist	/repo/ios/GoogleService-Info.plist
keystore.properties	/repo/keystore.properties
release.jks	/repo/release.jks
x.keystore	/repo/x.keystore
cert.p12	/repo/cert.p12
server.key	/repo/server.key
~/.netrc	/home/u/.netrc
~/.git-credentials	/home/u/.git-credentials
.git-credentials	/repo/.git-credentials
secrets.json	/repo/secrets.json
secrets.yaml	/repo/secrets.yaml
EOF

# C3a controls: the example files (how an agent learns which keys exist), a public key and a plain file stay readable.
while IFS="$(printf '\t')" read -r name abs; do
  [ -n "$name" ] || continue
  expect C3a allow Bash "cat $name"
  expect C3a allow Read "$abs"
  expect C3a allow Grep "$abs"
done <<'EOF'
.env.example	/repo/.env.example
.env.sample	/repo/.env.sample
.env.template	/repo/.env.template
id_ed25519.pub	/home/u/.ssh/id_ed25519.pub
README.md	/repo/README.md
EOF

# ---------------------------------------------------------------------------------------------------------------------
# C3d: a command that names a secret file without reading its content passes; the same shape with a read stays denied.
# Lines: <allow|deny><TAB><command>, taken literally (quoted heredoc: no shell expansion of the payload).
while IFS="$(printf '\t')" read -r want cmd; do
  [ -n "$want" ] || continue
  expect C3d "$want" Bash "$cmd"
done <<'EOF'
allow	test -f .env && echo present
allow	[ -f .env ] || cp .env.example .env
allow	ls -la .env
allow	git rm --cached .env
allow	git check-ignore -v .env
allow	echo '.env' >> .gitignore
allow	rg -n '\.env' src/
allow	grep -n "SECRET\|\.env" hooks/security_gate.sh
allow	rg "id_rsa" docs/
deny	test -f .env && cat .env
deny	ls .env; cat .env
deny	grep KEY .env
deny	git rm --cached .env && cat .env
deny	echo x >> .gitignore; source .env
deny	cp .env /tmp/x
deny	rg KEY .env.local
EOF

# ---------------------------------------------------------------------------------------------------------------------
# C3e: a recursive grep over a tree that holds a secret file prints that file, although the command names none.
WITH="$TMP/with_secret"; NONE="$TMP/no_secret"
mkdir -p "$WITH/src" "$NONE/src"
: > "$WITH/.env"                                   # empty: the fixture holds no key-like content
printf 'fun main() {}\n' > "$WITH/src/a.kt"
printf 'fun main() {}\n' > "$NONE/src/a.kt"
printf '# readme\n' > "$NONE/README.md"

expect C3e deny  Bash 'grep -rn API_KEY .'                  "$WITH" 'cwd holds a dotenv file'
expect C3e deny  Bash 'grep -R KEY .'                       "$WITH" 'cwd holds a dotenv file'
expect C3e allow Bash 'grep -rn API_KEY src/'               "$WITH" 'src/ holds no secret file'
expect C3e allow Bash "grep -rn --exclude='.env*' KEY ."    "$WITH" 'secret files excluded'
expect C3e allow Bash 'git grep KEY'                        "$WITH" 'git grep reads tracked files only'
expect C3e allow Bash 'grep -rn KEY .'                      "$NONE" 'cwd holds no secret file'

# C3e, stage 2: rg that searches hidden / ignored files, an absolute target, includes, a nested secret, the entry cap, and
# what .gitignore hides from a search that honours it.
NEST="$TMP/nested"; BIG="$TMP/big"; GITI="$TMP/git_ignored"; GITN="$TMP/git_not_ignored"
mkdir -p "$NEST/app" "$BIG" "$GITI/src" "$GITN/src"
: > "$NEST/app/google-services.json"
python3 -c 'import sys
for i in range(2100): open("%s/f%04d.txt" % (sys.argv[1], i), "w").close()' "$BIG"
for r in "$GITI" "$GITN"; do git -C "$r" init -q . ; : > "$r/.env"; printf 'x\n' > "$r/src/a.kt"; done
printf '.env\n' > "$GITI/.gitignore"

expect C3e deny  Bash 'rg --hidden KEY'                     "$WITH" 'rg reads hidden files'
expect C3e deny  Bash 'rg -uu KEY .'                        "$WITH" 'rg reads hidden + ignored files'
expect C3e deny  Bash 'rg --no-ignore --hidden KEY'         "$WITH"
expect C3e deny  Bash "grep -rn KEY $WITH"                  "$EMPTY" 'absolute target holds a dotenv file'
expect C3e deny  Bash 'grep -r KEY .'                       "$NEST" 'secret one directory down'
expect C3e deny  Bash 'grep -r KEY .'                       "$BIG"  'over the entry cap: not judged safe'
expect C3e deny  Bash 'grep -r KEY .'                       "$GITI" 'grep does not honour .gitignore'
expect C3e deny  Bash 'rg --hidden --no-ignore KEY'         "$GITI" 'rg told to skip .gitignore'
expect C3e deny  Bash 'rg --hidden KEY'                     "$GITN" 'dotenv file not ignored'
expect C3e deny  Bash "cd $WITH && grep -rn KEY ."          "$EMPTY" 'cd into a tree that holds a dotenv file'
expect C3e deny  Bash 'cd app; grep -rn KEY .'              "$NEST" 'relative cd'
expect C3e deny  Bash 'grep -r KEY *'                       "$NEST" 'glob target: its directory is checked'
expect C3e allow Bash "cd $NONE && grep -rn KEY ."          "$WITH" 'cd into a tree with no secret file'
expect C3e allow Bash 'rg KEY'                            "$WITH" 'plain rg skips hidden files'
expect C3e allow Bash "rg --hidden -g '!.env*' KEY"         "$WITH" 'secret files excluded'
expect C3e allow Bash "grep -rn --include='*.kt' KEY ."     "$WITH" 'only *.kt is read'
expect C3e allow Bash 'rg --hidden KEY'                     "$GITI" 'rg honours .gitignore'
expect C3e allow Bash 'rg --hidden KEY src/'                "$GITN" 'src/ holds no secret file'

# ---------------------------------------------------------------------------------------------------------------------
# C3g: the Grep tool on a DIRECTORY that holds a secret file (Antigravity T0479). Value = <path>||<glob>, empty path = cwd.
expect C3g deny  Grep "$WITH||"            "$EMPTY" 'path holds a dotenv file'
expect C3g deny  Grep "||"                 "$WITH"  'no path: cwd holds a dotenv file'
expect C3g deny  Grep "$WITH||*"           "$EMPTY" 'glob * still reads it'
expect C3g deny  Grep "$NEST||"            "$EMPTY" 'secret one directory down'
expect C3g deny  Grep "$GITN||"            "$EMPTY" 'dotenv file not ignored'
expect C3g deny  Grep "$WITH||.env*"       "$EMPTY" 'glob names the secret'
expect C3g allow Grep "$WITH||*.kt"        "$EMPTY" 'glob reads only *.kt'
expect C3g allow Grep "$WITH||!.env*"      "$EMPTY" 'glob excludes the secret'
expect C3g allow Grep "$WITH/src||"        "$EMPTY" 'src/ holds no secret file'
expect C3g allow Grep "$NONE||"            "$EMPTY" 'no secret file'
expect C3g allow Grep "||"                 "$NONE"  'no path: cwd holds no secret file'
expect C3g allow Grep "$GITI||"            "$EMPTY" 'the tool honours .gitignore'

# ---------------------------------------------------------------------------------------------------------------------
# C3d, stage 2 (plan v2): the limits of every exemption, and text that only mentions a name (C3t).
while IFS="$(printf '\t')" read -r group want cmd; do
  [ -n "$group" ] || continue
  expect "$group" "$want" Bash "$cmd"
done <<'EOF'
C3d	allow	if [ -f .env ]; then echo yes; fi
C3d	allow	stat .env
C3d	allow	git status --short .env
C3d	allow	git ls-files .env
C3d	allow	git -C sub check-ignore .env
C3d	allow	cp -n .env.example .env
C3d	allow	grep -rn --exclude=.env KEY src/
C3d	allow	grep -n -e '\.env' -e 'id_rsa' README.md
C3d	allow	rg -n '\.env' src/ 2>/dev/null
C3d	deny	cp .env .env.bak
C3d	deny	cp .env.example .env && cat .env
C3d	deny	cp -t /tmp .env.example .env
C3d	deny	grep "\.env" .env
C3d	deny	grep -f .env x
C3d	deny	grep -r --include='.env*' KEY .
C3d	deny	grep <.env KEY
C3d	deny	grep -e KEY .env
C3d	deny	rg KEY --glob '.env'
C3d	deny	git diff .env
C3d	deny	git show HEAD:.env
C3d	deny	git log -p -- .env
C3d	deny	git rm .env
C3d	deny	git -c alias.status='!cat .env' status
C3d	deny	ls $(cat .env)
C3d	deny	ls `cat .env`
C3d	deny	ls <(cat .env)
C3d	deny	ls < .env
C3d	deny	ls <.env
C3d	deny	ls .env | xargs cat
C3d	deny	ls .env | while read f; do cat "$f"; done
C3d	deny	ls .env; cat $_
C3d	deny	test -f .env && cat "$_"
C3d	deny	echo .env | xargs cat
C3d	deny	[ -f .env ] && . .env
C3d	deny	grep {.,.env}
C3d	deny	grep -e {.,.env}
C3d	deny	rg {.,.env}
C3d	deny	grep --exclude {x,KEY} .env
C3d	deny	grep .env* x
C3d	deny	git status -v .env
C3d	deny	ls .env | /usr/bin/xargs cat
C3d	deny	ls .env | sh
C3t	allow	echo "Copy .env.example to .env"
C3t	allow	printf '%s\n' 'never commit .env or id_rsa'
C3t	allow	gh pr create --title "fix: env" --body "Reads .env.example when .env is missing"
C3t	allow	rg "API_URL" --glob '!.env' src/
C3t	allow	bash -c "git commit -m 'chore: ignore .env'"
C3t	allow	bash -c 'test -f .env && echo present'
C3t	deny	echo x; cat .env
C3t	deny	gh pr create --body "$(cat .env)"
C3t	deny	gh pr create --title x --body-file .env
C3t	deny	echo "cat .env" | bash
C3t	deny	echo "cat .env" | sh
C3t	deny	echo "cat .env" 2>&1 | python3
C3t	deny	echo "cat .env" > x.sh; bash x.sh
C3t	deny	echo "cat .env" > x.sh; ./x.sh
C3t	deny	printf 'print(open(".env").read())' > x.py; python3 x.py
C3t	allow	echo '.env.local' >> .gitignore; echo "ignored .env.local" > /dev/null
C3t	deny	bash -c "cat .env"
C3t	deny	bash -c "echo hi; cat .env"
C3t	deny	bash -c "$(cat .env)"
EOF

# ---------------------------------------------------------------------------------------------------------------------
# C3x: one list of names (INSTINCT-015). Every file name bin/post-fix-gate.py forbids to commit (FORBIDDEN_SECRET_FILES,
# ENV_FILE_PATTERN, read from that file) is refused by the hook when read; every gate pattern has a sample here, so a pattern
# added to the gate turns this red until the hook knows it.
python3 - "$DEVKIT_DIR/bin/post-fix-gate.py" > "$TMP/gate_names.txt" 2> "$TMP/gate_names.err" <<'PY'
import ast, re, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
ns = {"re": re}
for node in tree.body:
    if isinstance(node, ast.Assign) and any(getattr(t, "id", "") in ("ENV_FILE_PATTERN", "FORBIDDEN_SECRET_FILES") for t in node.targets):
        exec(compile(ast.Module([node], []), "gate", "exec"), ns)
pats = [p for p, _label in ns["FORBIDDEN_SECRET_FILES"]]
samples = ["a.keystore", "a.jks", "a.p12", "a.pfx", "a.mobileprovision", "app/google-services.json",
           "ios/GoogleService-Info.plist", "a.pem", "a.key", "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
           "local.properties", "keystore.properties", ".env", ".env.ci", "prod.env", "config/.env.production",
           ".env.production.local", "deploy/staging.env", "secrets.json", "config/secrets.yml", "k8s/secrets.yaml",
           ".netrc", ".git-credentials", ".pypirc", ".dockercfg"]
for p in pats:
    if not any(re.search(p, s, re.I) for s in samples):
        sys.exit("gate pattern without a sample in this test: " + p)
for s in samples:
    if any(re.search(p, s, re.I) for p in pats):
        print(s)
PY
if [ -s "$TMP/gate_names.txt" ]; then
  while IFS= read -r name; do
    expect C3x deny Bash "cat $name"
    expect C3x deny Read "/repo/$name"
  done < "$TMP/gate_names.txt"
else
  echo "✖ C3x: could not read the gate's forbidden names: $(cat "$TMP/gate_names.err")"; echo "C3x deny FAIL" >> "$LOG"; FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------------------------------------------------
# C3r: credential stores in the home directory and a glob that can spell the dotenv name (reviewer A, round 1 residual).
# gradle.properties is an ordinary build file: it stays readable.
while IFS="$(printf '\t')" read -r want tool value; do
  [ -n "$want" ] || continue
  expect C3r "$want" "$tool" "$value"
done <<'EOF'
deny	Bash	cat .e*
deny	Bash	cat .en?
deny	Bash	cat ~/.docker/config.json
deny	Bash	cat ~/.kube/config
deny	Bash	cat ~/.pypirc
deny	Bash	cat ~/.config/gh/hosts.yml
deny	Bash	cat ~/.aws/credentials
deny	Bash	cat ~/.ssh/id_*
deny	Bash	cat ~/.dockercfg
deny	Read	/home/u/.docker/config.json
deny	Read	/home/u/.kube/config
deny	Read	/home/u/.pypirc
deny	Read	/home/u/.config/gh/hosts.yml
deny	Read	/home/u/.aws/credentials
deny	Read	/home/u/.ssh/id_ed25519
allow	Bash	cat gradle.properties
allow	Read	/repo/gradle.properties
allow	Bash	cat ~/.ssh/id_*.pub
allow	Bash	cat config.json
allow	Bash	cat .github/workflows/hosts.yml
allow	Bash	cat .eslint*
allow	Read	/repo/docker/config.json
EOF

# ---------------------------------------------------------------------------------------------------------------------
echo "---- summary (group / wanted verdict: passed of total)"
for g in C3a C3d C3e C3g C3t C3x C3r; do
  for w in deny allow; do
    total="$(grep -c "^$g $w " "$LOG")"; good="$(grep -c "^$g $w ok$" "$LOG")"
    echo "$g want $w: $good/$total"
  done
done
if [ "$FAILS" -ne 0 ]; then echo "❌ test_guard_secrets_zero_defect: $FAILS failed"; exit 1; fi
echo "✅ test_guard_secrets_zero_defect: all passed"
