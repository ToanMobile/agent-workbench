#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py must report only what it actually ran.
# - clean tree            -> exit 3, never PASS
# - impacted, dry-run     -> exit 2 (UNVERIFIED), never PASS
# - --run-tests, `false`  -> exit 1 (REJECT)
# - --run-tests, `true`   -> exit 0 (PASS)
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
check() { # name expected actual [output] [forbidden-substring]
  local name="$1" expected="$2" actual="$3" out="${4:-}" forbid="${5:-}"
  if [ "$actual" != "$expected" ]; then
    echo "✖ $name: exit $actual, expected $expected"; FAILS=$((FAILS + 1)); return
  fi
  if [ -n "$forbid" ] && printf '%s' "$out" | grep -q -- "$forbid"; then
    echo "✖ $name: output contains forbidden '$forbid'"; FAILS=$((FAILS + 1)); return
  fi
  echo "✔ $name"
}

make_repo() { # $1 = regression command
  rm -rf "$TMP/repo" && mkdir -p "$TMP/repo/src"
  cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  cat > matrix.json <<JSON
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"$1"}]}]}
JSON
  git add -A && git commit -qm init
}

run_gate() {
  CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" "$@" 2>&1
}

make_repo "true"
out="$(run_gate --run-tests)"; check "clean tree is not PASS" 3 $? "$out" "PASS —"

echo "fun ok() = 2" > src/Core.kt
out="$(run_gate)"; check "dry-run default is UNVERIFIED" 2 $? "$out" "\[x\] PASS"
out="$(run_gate --dry-run --run-tests)"; check "--dry-run overrides --run-tests" 2 $? "$out" "\[x\] PASS"
out="$(run_gate --run-tests)"; check "passing regression command -> PASS" 0 $? "$out"
grep -q 'REG-1.*`PASS`' "$TMP/repo/.git/postfix-gate/last_report.md" \
  && echo "✔ report records real PASS" || { echo "✖ report missing REG-1 PASS"; FAILS=$((FAILS + 1)); }

make_repo "exit 7"
echo "fun ok() = 3" > src/Core.kt
out="$(run_gate --run-tests)"; check "failing regression command -> REJECT" 1 $? "$out" "\[x\] PASS"
printf '%s' "$out" | grep -q 'exit=7' \
  && echo "✔ real exit code reported" || { echo "✖ exit code 7 not reported"; FAILS=$((FAILS + 1)); }

# --- Changed-file discovery must not let content escape the scans -----------------
make_repo "true"
# Fake secrets are assembled at runtime so this file itself never matches the scanner.
mkdir -p newdir && printf '%s = "%s"\n' "api_""key" "ABCDEFGHIJKLMNOP" > newdir/secret.py
out="$(run_gate --run-tests --allow-no-tests)"; check "secret inside an untracked dir -> REJECT" 1 $? "$out"

make_repo "true"
printf '// ... existing code ...\n' > "src/sp ace.kt"
out="$(run_gate --run-tests --allow-no-tests)"; check "placeholder in a file name with a space -> REJECT" 1 $? "$out"

make_repo "true"
git mv src/Core.kt src/Renamed.kt && printf '// ... existing code ...\n' >> src/Renamed.kt
out="$(run_gate --run-tests --allow-no-tests)"; check "placeholder in a renamed file -> REJECT" 1 $? "$out"

# --- No regression coverage is not a PASS -------------------------------------------
make_repo "true"
echo "x" > other.txt
out="$(CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests 2>&1)"; check "no matrix -> UNVERIFIED" 2 $? "$out"
out="$(run_gate --run-tests)"; check "no matching regression test -> UNVERIFIED" 2 $? "$out"
out="$(run_gate --run-tests --allow-no-tests)"; check "--allow-no-tests accepts it" 0 $? "$out"
[ -z "$(git status --porcelain -- templates)" ] && echo "✔ report is not written into the audited tree" \
  || { echo "✖ report written into the working tree"; FAILS=$((FAILS + 1)); }

# --- Monorepo: project is a subdirectory of the git repo ----------------------------
make_repo "true"
mkdir -p sub/src && printf '// ... existing code ...\n' > sub/src/Core.kt
out="$(CLAUDE_PROJECT_DIR="$TMP/repo/sub" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --allow-no-tests 2>&1)"
check "placeholder in a monorepo subdir -> REJECT" 1 $? "$out"

# --- Timeout kills the whole process tree -------------------------------------------
make_repo "sleep 30 & echo \$! > $TMP/child.pid; wait"
echo "fun ok() = 9" > src/Core.kt
out="$(run_gate --run-tests --timeout 2)"; check "timeout -> REJECT" 1 $? "$out"
sleep 1
if kill -0 "$(cat "$TMP/child.pid" 2>/dev/null)" 2>/dev/null; then
  echo "✖ timed-out test left a child process running"; FAILS=$((FAILS + 1)); kill "$(cat "$TMP/child.pid")"
else echo "✔ timed-out test's child process was killed"; fi

expect_in() { # name substring output
  if printf '%s' "$3" | grep -q -- "$2"; then echo "✔ $1"; else echo "✖ $1: missing '$2'"; FAILS=$((FAILS + 1)); fi
}
expect_not_in() { # name substring output
  if printf '%s' "$3" | grep -q -- "$2"; then echo "✖ $1: contains '$2'"; FAILS=$((FAILS + 1)); else echo "✔ $1"; fi
}
gate_nomatrix() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests --allow-no-tests "$@" 2>&1; }

# --- G-1: the audited change must not be able to rewrite its own regression command -
make_repo "exit 1"
echo "fun ok() = 2" > src/Core.kt
sed -i.bak 's/exit 1/true/' matrix.json && rm -f matrix.json.bak
out="$(run_gate --run-tests)"; rc=$?
[ "$rc" -ne 0 ] && echo "✔ matrix edited in the same change is not PASS (exit $rc)" \
  || { echo "✖ matrix edited in the same change -> PASS"; FAILS=$((FAILS + 1)); }
expect_in "matrix tampering is reported" "bị sửa so với HEAD" "$out"

make_repo "true"
mkdir -p templates && cat > templates/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
echo "fun ok() = 2" > src/Core.kt
out="$(CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests 2>&1)"
check "uncommitted default matrix -> UNVERIFIED" 2 $? "$out" "PASS —"

make_repo "true"
mkdir -p src/test && echo "assert(true)" > src/test/CoreTest.kt && git add -A && git commit -qm t
echo "fun ok() = 2" > src/Core.kt && echo "// weakened" > src/test/CoreTest.kt
out="$(run_gate --run-tests)"; check "existing test edited in the change -> UNVERIFIED" 2 $? "$out" "PASS —"
make_repo "true"
echo "fun ok() = 2" > src/Core.kt && mkdir -p src/test && echo "assert(ok() == 2)" > src/test/NewTest.kt
out="$(run_gate --run-tests)"; check "new RED test file is allowed -> PASS" 0 $? "$out"

# --- G-2: whitelisting is by exact template suffix, not by directory name ----------
make_repo "true"
mkdir -p app/sample-app && echo x > app/sample-app/release.jks
out="$(gate_nomatrix)"; check "sample-app/release.jks -> REJECT" 1 $? "$out"
make_repo "true"
mkdir -p templates/prod && echo x > templates/prod/server.key
out="$(gate_nomatrix)"; check "templates/prod/server.key -> REJECT" 1 $? "$out"
make_repo "true"
printf 'API_KEY=changeme\n' > .env.example
out="$(gate_nomatrix)"; check ".env.example with a placeholder -> PASS" 0 $? "$out"

# --- G-3: common secret shapes -------------------------------------------------------
secret_case() { # name file content
  make_repo "true"; mkdir -p "$(dirname "$2")"; printf '%s\n' "$3" > "$2"
  out="$(gate_nomatrix)"; check "$1 -> REJECT" 1 $? "$out"
}
secret_case "base64 password" src/Conf.kt "val password = \"Zx9/Qw+Er7Ty==\""
secret_case "AWS access key" src/Aws.kt "val id = \"AKI""AABCDEFGHIJKLMNOP\""
secret_case "GitHub token" src/Gh.kt "val ghToken = \"gh""p_abcdefghijklmnopqrstuvwxyz0123456789AB\""
secret_case "unquoted password in .properties" gradle.properties "pass""word = hunter2hunter2"
secret_case "secrets.env file" secrets.env "X=1"
make_repo "true"
printf '#!/bin/sh\n. ./.env\n' > run.sh
out="$(gate_nomatrix)"; check "sourcing ./.env in a script is not a secret" 0 $? "$out"
make_repo "true"
printf 'db.password=${DB_PASSWORD}\n' > app.properties
out="$(gate_nomatrix)"; check "env-var reference in .properties is not a secret" 0 $? "$out"

# --- G-4: "test" as a substring must not skip the scans ------------------------------
make_repo "true"
mkdir -p src/latest && printf 'fun f() { try { g() } catch (e: Exception) {} }\n' > src/latest/Foo.kt
out="$(gate_nomatrix)"; check "src/latest/Foo.kt is scanned -> REJECT" 1 $? "$out"
make_repo "true"
mkdir -p src/test && printf 'fun f() { try { g() } catch (e: Exception) {} }\n' > src/test/FooTest.kt
out="$(gate_nomatrix)"; check "src/test/FooTest.kt is a test -> PASS" 0 $? "$out"

# --- G-5: monorepo subproject uses its own paths and scope -------------------------
make_repo "true"
mkdir -p sub/src && echo "fun a() = 1" > sub/src/Core.kt
cat > sub/matrix.json <<'JSON'
{"project":"sub","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-S","name":"sub","command":"true"}]}]}
JSON
git add -A && git commit -qm sub
echo "fun a() = 2" > sub/src/Core.kt
out="$(CLAUDE_PROJECT_DIR="$TMP/repo/sub" python3 "$GATE" --matrix "$TMP/repo/sub/matrix.json" --run-tests 2>&1)"
check "monorepo subproject matches its matrix -> PASS" 0 $? "$out"
git checkout -q -- sub && echo "outside" > other.txt
out="$(CLAUDE_PROJECT_DIR="$TMP/repo/sub" python3 "$GATE" --run-tests 2>&1)"
check "change outside the subproject is out of scope" 3 $? "$out"

# --- G-6: no adb is "not verified", never "device online" ---------------------------
make_repo "true"
mkdir -p "$TMP/bin" app/android && ln -sf "$(command -v python3)" "$TMP/bin/python3" && ln -sf "$(command -v git)" "$TMP/bin/git"
echo "fun a() = 1" > app/android/A.kt
out="$(PATH="$TMP/bin" gate_nomatrix)"
expect_not_in "no adb -> no 'device online' claim" "có thiết bị online" "$out"
expect_in "no adb -> reported as not verified" "KHÔNG xác minh được" "$out"

# --- G-8: proof images of other projects' sessions are not counted -----------------
make_repo "true"
echo "fun ok() = 2" > src/Core.kt
BR="$TMP/brain" && rm -rf "$BR" && mkdir -p "$BR/other" "$BR/mine"
echo "work in /somewhere/else" > "$BR/other/walkthrough.md"; : > "$BR/other/a.png"; : > "$BR/other/b.png"
out="$(POSTFIX_GATE_BRAIN_DIR="$BR" run_gate --run-tests)"
expect_in "other project's images are ignored" "0 ảnh" "$out"
expect_in "no session of this project -> not verified" "không có phiên nào" "$out"
echo "edited $(cd "$TMP/repo" && pwd -P)/src/Core.kt" > "$BR/mine/walkthrough.md"; echo img > "$BR/mine/p.png"
out="$(POSTFIX_GATE_BRAIN_DIR="$BR" run_gate --run-tests)"
expect_in "this project's session images are counted" "1 ảnh" "$out"
touch -t 202001010000 "$BR/mine/walkthrough.md" "$BR/mine/p.png" "$BR/mine"
out="$(POSTFIX_GATE_BRAIN_DIR="$BR" run_gate --run-tests)"
expect_in "a session untouched for over 7 days is not counted" "0 ảnh" "$out"
out="$(POSTFIX_GATE_BRAIN_DIR="$BR" POSTFIX_GATE_BRAIN_DAYS=100000 run_gate --run-tests)"
expect_in "POSTFIX_GATE_BRAIN_DAYS widens the window" "1 ảnh" "$out"

# --- G-9: --diff cannot smuggle git options ------------------------------------------
make_repo "true"
echo "fun ok() = 2" > src/Core.kt
out="$(run_gate --run-tests "--diff=--output=$TMP/pwned")"; check "--diff=--output=... is refused" 2 $? "$out"
[ ! -e "$TMP/pwned" ] && echo "✔ git did not write the injected output file" \
  || { echo "✖ --diff option injection wrote a file"; FAILS=$((FAILS + 1)); }

# --- G-10: lessons are recorded only after a PASS, escaped ---------------------------
make_repo "exit 1"
echo "fun ok() = 2" > src/Core.kt
run_gate --run-tests --record-lesson "bad" >/dev/null 2>&1
[ ! -e .agents/instincts.md ] && echo "✔ REJECT does not record a lesson" \
  || { echo "✖ lesson recorded on REJECT"; FAILS=$((FAILS + 1)); }
make_repo "true"
echo "fun ok() = 2" > src/Core.kt
run_gate --run-tests --record-lesson "$(printf 'x\n# injected heading\n- item')" >/dev/null 2>&1
if [ -f .agents/instincts.md ] && ! grep -q '^# injected' .agents/instincts.md && ! grep -q '^- item' .agents/instincts.md \
   && grep -q 'INSTINCT-001\] x # injected heading - item$' .agents/instincts.md; then
  echo "✔ lesson recorded after PASS, folded to one line (no injected heading/item)"
else echo "✖ lesson missing or not escaped"; FAILS=$((FAILS + 1)); fi

# --- O6: devkit-installed links are not user changes nor "unreadable" --------------
make_repo "true"
mkdir -p .claude/hooks .agents/skills
ln -s "$DEVKIT_DIR/hooks/claim_check.sh" .claude/hooks/claim_check.sh
ln -s "$DEVKIT_DIR/skills/qc" .agents/skills/qc
ln -s "$DEVKIT_DIR/rules" rules
out="$(gate_nomatrix)"; check "only devkit links -> nothing to audit" 3 $? "$out"
echo "fun ok() = 2" > src/Core.kt
out="$(gate_nomatrix)"; check "devkit links + real change -> PASS" 0 $? "$out" "không đọc được"

# --- Dependency check: floating versions and http:// sources -----------------------
# http:// is assembled at runtime so this file itself never looks like a manifest.
H="http"
make_repo "true"
printf 'dependencies {\n  implementation "com.squareup.okhttp3:okhttp:4.+"\n}\n' > build.gradle
out="$(gate_nomatrix)"; check "Gradle dynamic version 4.+ -> REJECT" 1 $? "$out"
expect_in "finding quotes the declaration" "okhttp:4.+" "$out"

make_repo "true"
printf 'dependencies { implementation "androidx.core:core-ktx:1.13.1" }\n' > build.gradle
printf 'publishing { pom { licenses { license { url = "%s://www.apache.org/licenses/LICENSE-2.0.txt" } } } }\n' "$H" >> build.gradle
printf 'repositories { maven { url "%s://localhost:8081/repo" } }\n' "$H" >> build.gradle
out="$(gate_nomatrix)"; check "pinned version, license URL, loopback repo -> not rejected" 0 $? "$out"

make_repo "true"
printf 'repositories {\n  maven { url "%s://repo.example.com/maven2" }\n}\n' "$H" > settings.gradle
out="$(gate_nomatrix)"; check "Gradle repository over http:// -> REJECT" 1 $? "$out"

make_repo "true"
printf '{"name":"t","version":"1.0.0","dependencies":{"a":"^1.2.3"},"peerDependencies":{"react":"*"}}\n' > package.json
out="$(gate_nomatrix)"; check "caret range and peer * -> not rejected" 0 $? "$out"
printf '{"name":"t","version":"1.0.0","dependencies":{"a":"latest"}}\n' > package.json
out="$(gate_nomatrix)"; check "npm dependency \"latest\" -> REJECT" 1 $? "$out"

make_repo "true"
mkdir -p gradle && printf '[versions]\nkotlin = "2.0.0"\ncompose = "1.+"\n' > gradle/libs.versions.toml
out="$(gate_nomatrix)"; check "version catalog 1.+ -> REJECT" 1 $? "$out"

make_repo "true"
printf 'requests==2.31.0\n--index-url %s://pypi.internal/simple\n' "$H" > requirements.txt
out="$(gate_nomatrix)"; check "pip index over http:// -> REJECT" 1 $? "$out"

make_repo "true"
mkdir -p src/test && printf '{"dependencies":{"a":"latest"}}\n' > src/test/package.json
out="$(gate_nomatrix)"; check "manifest under a test dir is a fixture, not scanned" 0 $? "$out"

# --- Lazy-senior advisories (core-rules §4): warn, never block ---------------------
make_repo "true"
printf 'dependencies { implementation "androidx.core:core-ktx:1.13.1" }\n' > build.gradle
printf '{"name":"t","dependencies":{"a":"1.0.0"}}\n' > package.json
git add -A && git commit -qm deps
printf 'dependencies {\n  implementation "androidx.core:core-ktx:1.15.0"\n  implementation "com.jakewharton.timber:timber:5.0.1"\n}\n' > build.gradle
printf '{"name":"t","dependencies":{"a":"1.0.1","left-pad":"1.3.0"}}\n' > package.json
out="$(gate_nomatrix)"; check "new dependency -> warning only, still PASS" 0 $? "$out"
expect_in "gradle: newly added coordinate named" "new dependency com.jakewharton.timber:timber" "$(DEVKIT_LANG=en gate_nomatrix)"
expect_in "npm: newly added package named" "package.json: new dependency left-pad" "$(DEVKIT_LANG=en gate_nomatrix)"
expect_not_in "version bump is not a new dependency" "new dependency androidx.core" "$(DEVKIT_LANG=en gate_nomatrix)"
printf 'fun ok() = 1 // ponytail: global lock\nfun two() = 2 // ponytail: O(n^2) scan, index it past 1k rows\n' > src/Core.kt
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "debt marker without trigger -> warning only" 0 $? "$out"
expect_in "marker without an upgrade trigger is flagged with its line" "src/Core.kt:1: \`ponytail:\` marker names no upgrade trigger" "$out"
expect_not_in "marker with a trigger passes" "src/Core.kt:2:" "$out"

# --- mobile findings: local.properties, SwiftPM branch pins, plist secrets -----------
make_repo "true"
printf 'sdk.dir=/Users/dev/Library/Android/sdk\n' > local.properties
out="$(gate_nomatrix)"; check "local.properties (core-rules §1) -> REJECT" 1 $? "$out"
make_repo "true"
printf 'let package = Package(name: "A", dependencies: [.package(url: "https://github.com/x/y", branch: "main")])\n' > Package.swift
out="$(gate_nomatrix)"; check "SwiftPM dependency on a branch -> REJECT" 1 $? "$out"
make_repo "true"
printf 'let package = Package(name: "A", dependencies: [.package(url: "https://github.com/x/y", from: "5.8.0")])\n' > Package.swift
out="$(gate_nomatrix)"; check "SwiftPM from: version range -> not rejected" 0 $? "$out"
make_repo "true"
printf '<plist><dict>\n<key>API_KEY</key>\n<string>%s</string>\n</dict></plist>\n' "live""VALUE1234567890" > Info.plist
out="$(gate_nomatrix)"; check "API key in Info.plist -> REJECT" 1 $? "$out"
make_repo "true"
printf '<plist><dict>\n<key>API_KEY</key>\n<string>$(API_KEY)</string>\n</dict></plist>\n' > Info.plist
out="$(gate_nomatrix)"; check "plist build-setting reference \$(API_KEY) -> not rejected" 0 $? "$out"

# --- web/backend findings: npm token, credentials in URLs, SSH keys ------------------
make_repo "true"
printf '//registry.npmjs.org/:_authToken=%s\n' "npm_""AbCdEfGhIjKlMnOpQrStUvWx" > .npmrc
out="$(gate_nomatrix)"; check "npm _authToken in .npmrc -> REJECT" 1 $? "$out"
make_repo "true"
printf '//registry.npmjs.org/:_authToken=${NPM_TOKEN}\n' > .npmrc
out="$(gate_nomatrix)"; check ".npmrc token from \${NPM_TOKEN} -> not rejected" 0 $? "$out"
make_repo "true"
printf 'DATABASE_URL = "postgres://admin:%s@db.internal/prod"\n' "S3cret""Pass99" > settings.py
out="$(gate_nomatrix)"; check "password inside a connection URL -> REJECT" 1 $? "$out"
make_repo "true"
printf 'DATABASE_URL = "postgres://app:password@localhost/dev"\n' > settings.py
out="$(gate_nomatrix)"; check "placeholder password in a URL -> not rejected" 0 $? "$out"
make_repo "true"
mkdir -p deploy && echo "key material" > deploy/id_ed25519
out="$(gate_nomatrix)"; check "private SSH key file id_ed25519 -> REJECT" 1 $? "$out"

# --- bare AI / cloud tokens: caught by prefix even in a variable not named key/token ---
rep() { python3 -c 'import sys; print(sys.argv[1] * int(sys.argv[2]), end="")' "$1" "$2"; }
for tok in "hf_$(rep a 34)" "sk-ant-api03-$(rep B 90)" "sk-proj-$(rep c 60)" "sbp_$(rep d 40)" \
           "sk_live_$(rep e 24)" "glpat-$(rep f 20)"; do
  make_repo "true"
  printf 'const client = new Client("%s");\n' "$tok" > client.js
  out="$(gate_nomatrix)"; check "bare token ${tok:0:8}… -> REJECT" 1 $? "$out"
done
make_repo "true"
printf 'const tag = "sk-tiny"; const h = "hf_short";\n' > client.js
out="$(gate_nomatrix)"; check "short look-alikes (sk-tiny, hf_short) -> not rejected" 0 $? "$out"

# --- raw console output: production code rejected, command-line tools exempt ---------
make_repo "true"
mkdir -p src && printf 'console.log("user", user);\n' > src/app.js
out="$(gate_nomatrix)"; check "console.log in production code -> REJECT" 1 $? "$out"
for d in bin cmd/server tools; do
  make_repo "true"
  mkdir -p "$d" && printf 'console.log("done");\n' > "$d/cli.js"
  out="$(gate_nomatrix)"; check "console.log in a CLI under $d/ -> not rejected" 0 $? "$out"
done

# --- a secret already in HEAD is not this change's: warned with file:line, not blocked -----
make_repo "true"
printf 'const anon = "%s";\nconst x = 1;\n' "$(rep() { python3 -c 'import sys; print(sys.argv[1] * int(sys.argv[2]), end="")' "$1" "$2"; }; echo "sk-proj-$(rep k 60)")" > keys.js
git add -A && git commit -qm "old key"
printf 'const x = 2;\n' >> keys.js
out="$(gate_nomatrix)"; check "secret already in HEAD, other line edited -> not rejected" 0 $? "$out"
expect_in "pre-existing secret is still reported, with its line" "keys.js:1" "$out"
git add keys.js; out="$(CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --staged 2>&1)"; rc=$?
[ "$rc" != 1 ] && echo "✔ --staged: a secret already in HEAD does not block the commit (exit $rc)" || { echo "✖ --staged blocked a pre-existing secret"; FAILS=$((FAILS + 1)); }
printf 'const fresh = "%s";\n' "hf_$(python3 -c 'print("q"*34, end="")')" >> keys.js
out="$(gate_nomatrix)"; check "a NEW secret in the same file -> REJECT" 1 $? "$out"
expect_in "the new secret is named with file:line" "keys.js:4" "$out"

# --- every static layer: a finding already in HEAD warns; only added code can REJECT -----
make_repo "true"
mkdir -p app && printf 'class A {\n  fun f() { try { g() } catch (e: Exception) {} }\n  fun h() = 1\n}\n' > app/A.kt
git add -A && git commit -qm legacy
sed -i.bak 's/fun h() = 1/fun h() = 2/' app/A.kt && rm -f app/A.kt.bak
out="$(gate_nomatrix)"; check "empty catch already in HEAD, other line edited -> not rejected" 0 $? "$out"
expect_in "legacy empty catch still reported with its line" "app/A.kt:2" "$out"
git add app/A.kt; out="$(CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --staged 2>&1)"; rc=$?
[ "$rc" != 1 ] && echo "✔ --staged: a legacy empty catch does not block the commit (exit $rc)" || { echo "✖ --staged blocked a legacy catch"; FAILS=$((FAILS + 1)); }
expect_in "--staged: the legacy empty catch is shown as a warning with file:line" "app/A.kt:2" "$out"
printf 'fun k() { try { g() } catch (e: Exception) {} }\n' >> app/A.kt
out="$(gate_nomatrix)"; check "a second, identical empty catch added -> REJECT" 1 $? "$out"
make_repo "true"
mkdir -p app && printf 'fun m() {\n  println("x")\n}\n' > app/B.kt && git add -A && git commit -qm legacy
printf 'fun n() {\n  System.out.println("y")\n}\n' >> app/B.kt
out="$(gate_nomatrix)"; check "a new raw log line in a touched file -> REJECT" 1 $? "$out"

# --- untested_exit: a test that cannot run here is UNTESTED (exit 4), never PASS/REJECT --
untested_repo() { # $1 = command, $2 = untested_exit JSON fragment
  make_repo "true"
  cat > matrix.json <<JSON
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-U","name":"unity","command":"$1"$2}]}]}
JSON
  git add -A && git commit -qm m && echo "fun ok() = 5" > src/Core.kt
}
untested_repo "exit 2" ', "untested_exit": 2'
out="$(run_gate --run-tests)"; check "command exits with its untested_exit -> UNTESTED (exit 4)" 4 $? "$out" "PASS —"
printf '%s' "$out" | grep -q "UNTESTED" && echo "✔ UNTESTED named in the verdict" || { echo "✖ UNTESTED not named"; FAILS=$((FAILS + 1)); }
untested_repo "exit 2" ''
out="$(run_gate --run-tests)"; check "exit 2 without untested_exit is a failing test -> REJECT" 1 $? "$out"
untested_repo "exit 1" ', "untested_exit": 2'
out="$(run_gate --run-tests)"; check "a real failure is still REJECT when untested_exit is set" 1 $? "$out"

# --- UNCOVERED follows the profile's source_extensions; docs/ .agents/ .claude/ are not code
make_repo "true"
mkdir -p .agents/active-profile && echo '{"source_extensions": [".kt", ".java"]}' > .agents/active-profile/profile.json
git add -A && git commit -qm profile
echo "fun ok() = 2" > src/Core.kt; echo "fun other() = 1" > src/Other.kt
mkdir -p docs/evidence .agents/local/workflows app/src/main/res/layout
echo "<testsuite/>" > docs/evidence/T_RED_1.xml; echo "export const x = 1;" > .agents/local/workflows/audit.js
echo "<LinearLayout/>" > app/src/main/res/layout/main.xml
out="$(run_gate --run-tests --json)"
unc="$(printf '%s\n' "$out" | tail -n 1 | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)["uncovered"]))')"
[ "$unc" = "src/Other.kt" ] && echo "✔ UNCOVERED: only the profile's source file (not docs/ XML, .agents/ JS, res XML)" \
  || { echo "✖ UNCOVERED list: '$unc'"; FAILS=$((FAILS + 1)); }

# --- --staged: static checks on the index, never PASS --------------------------------
gate_staged() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --staged "$@" 2>&1; }
make_repo "true"
out="$(gate_staged)"; check "--staged with nothing staged -> nothing to audit" 3 $? "$out"
echo "fun ok() = 2" > src/Core.kt && git add src/Core.kt
out="$(gate_staged)"; check "--staged clean -> UNVERIFIED (tests not run), never PASS" 2 $? "$out" "PASS —"
printf '%s = "%s"\n' "api_""key" "ABCDEFGHIJKLMNOP" > src/Leak.kt && git add src/Leak.kt && rm src/Leak.kt
out="$(gate_staged)"; check "--staged: secret staged then deleted from the working tree -> REJECT" 1 $? "$out"
git rm -q --cached src/Leak.kt
printf '// ... existing code ...\n' > src/Core.kt
out="$(gate_staged)"; check "--staged: unstaged placeholder is not what gets committed" 2 $? "$out"
out="$(gate_staged --run-tests)"; check "--staged refuses --run-tests" 2 $? "$out"
out="$(gate_staged --json)"; expect_in "--staged --json reports mode" '"mode": "staged"' "$out"

# --- --json "findings": file:line an agent can act on without parsing the log --------
# jq-free: python reads the last stdout line (the JSON) and prints what the case needs.
json_findings() { printf '%s\n' "$1" | tail -n 1 | python3 -c 'import json,sys
for f in json.load(sys.stdin).get("findings", []):
    print("%s|%s|%s|%s|%s" % (f["category"], f["file"], f["line"], f["rule"], f["snippet"]))'; }
make_repo "true"
printf 'dependencies {\n  implementation "com.squareup.okhttp3:okhttp:4.+"\n}\n' > build.gradle
out="$(gate_nomatrix --json)"; check "floating dep with --json -> REJECT" 1 $? "$out"
expect_in "--json finding carries category, file and line" 'dependencies|build.gradle|2|' "$(json_findings "$out")"
expect_in "--json finding quotes the offending line" 'implementation "com.squareup.okhttp3:okhttp:4.+"' "$(json_findings "$out")"
make_repo "true"
printf 'plugins { id "java" }\n\ndependencies {\n  implementation "a:b:1.0.0"\n}\n' > build.gradle && git add build.gradle && git commit -qm gradle
printf 'dependencies { implementation "com.squareup.okhttp3:okhttp:4.+" }\n' >> build.gradle
out="$(gate_nomatrix --json)"; expect_in "--json line is file-absolute in an edited, committed file" 'dependencies|build.gradle|6|' "$(json_findings "$out")"
make_repo "true"
printf '{\n  "name": "t",\n  "dependencies": {\n    "a": "latest"\n  }\n}\n' > package.json
out="$(gate_nomatrix --json)"; expect_in "--json package.json finding points at the dependency's line" 'dependencies|package.json|4|' "$(json_findings "$out")"
make_repo "true"
printf 'val x = 1\n%s = "%s"\n' "api_""key" "ABCDEFGHIJKLMNOP" > src/Leak.kt && git add src/Leak.kt
out="$(gate_staged --json)"; check "--staged --json with a secret -> REJECT" 1 $? "$out"
expect_in "--json secret finding has its line" 'secrets|src/Leak.kt|2|' "$(json_findings "$out")"
expect_not_in "--json never echoes the secret value" "ABCDEFGHIJKLMNOP" "$(printf '%s\n' "$out" | tail -n 1)"

if [ "$FAILS" -ne 0 ]; then
  echo "post-fix-gate: $FAILS FAILED"; exit 1
fi
echo "post-fix-gate: all checks passed"
