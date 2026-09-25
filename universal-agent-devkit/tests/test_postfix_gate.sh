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
mkdir -p Packages && printf '{"dependencies":{"com.unity.ugui":"2.0.0"}}\n' > Packages/manifest.json
git add -A && git commit -qm unity
printf '{"dependencies":{"com.unity.ugui":"2.0.1","com.unity.addressables":"2.2.2"}}\n' > Packages/manifest.json
expect_in "unity: newly added package named" "Packages/manifest.json: new dependency com.unity.addressables" "$(DEVKIT_LANG=en gate_nomatrix)"
expect_not_in "unity: version bump is not a new dependency" "new dependency com.unity.ugui" "$(DEVKIT_LANG=en gate_nomatrix)"
printf 'fun ok() = 1 // ponytail: global lock\nfun two() = 2 // ponytail: O(n^2) scan, index it past 1k rows\n' > src/Core.kt
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "debt marker without trigger -> warning only" 0 $? "$out"
expect_in "marker without an upgrade trigger is flagged with its line" "src/Core.kt:1: \`ponytail:\` marker names no upgrade trigger" "$out"
expect_not_in "marker with a trigger passes" "src/Core.kt:2:" "$out"

# --- New-dependency advisory for every manifest kind, and in --json ---------------------
make_repo "true"
mkdir -p ios app
printf 'requests==2.31.0\n' > requirements.txt
printf "platform :ios, '15.0'\npod 'Alamofire', '5.8.0'\n" > ios/Podfile
printf '// swift-tools-version:5.9\nlet package = Package(name: "A", dependencies: [\n  .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.0.0"),\n])\n' > Package.swift
printf 'name: app\ndependencies:\n  http: ^1.1.0\ndev_dependencies:\n  lints: ^3.0.0\nflutter:\n  uses-material-design: true\n' > app/pubspec.yaml
printf '[package]\nname = "a"\n\n[dependencies]\nserde = "1.0"\n' > Cargo.toml
printf '[project]\nname = "p"\ndependencies = ["click>=8"]\n' > pyproject.toml
printf '<project><dependencies><dependency><groupId>org.slf4j</groupId><artifactId>slf4j-api</artifactId><version>2.0.9</version></dependency></dependencies></project>\n' > pom.xml
git add -A && git commit -qm manifests
printf 'requests==2.32.0\nhttpx[http2]==0.27.0\n# comment\n-r base.txt\n' > requirements.txt
printf "platform :ios, '15.0'\npod 'Alamofire', '5.9.0'\npod 'SnapKit', '5.7.1'\n" > ios/Podfile
printf '// swift-tools-version:5.9\nlet package = Package(name: "A", dependencies: [\n  .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.0"),\n  .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),\n])\n' > Package.swift
printf 'name: app\ndependencies:\n  http: ^1.2.0\n  provider: ^6.1.0\ndev_dependencies:\n  lints: ^3.0.0\nflutter:\n  uses-material-design: true\n' > app/pubspec.yaml
printf '[package]\nname = "a"\n\n[dependencies]\nserde = "1.0"\ntokio = { version = "1.38" }\n' > Cargo.toml
printf '[project]\nname = "p"\ndependencies = ["click>=8", "rich[jupyter]>=13"]\n' > pyproject.toml
printf '<project><dependencies><dependency><groupId>org.slf4j</groupId><artifactId>slf4j-api</artifactId><version>2.0.13</version></dependency><dependency><groupId>com.google.guava</groupId><artifactId>guava</artifactId><version>33.2.1-jre</version></dependency></dependencies></project>\n' > pom.xml
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "new deps in every manifest -> warning only, PASS" 0 $? "$out"
for want in "requirements.txt: new dependency httpx" "ios/Podfile: new dependency SnapKit" \
            "Package.swift: new dependency swift-collections" "app/pubspec.yaml: new dependency provider" \
            "Cargo.toml: new dependency tokio" "pyproject.toml: new dependency rich" \
            "pom.xml: new dependency com.google.guava:guava"; do
  expect_in "advisory: $want" "$want" "$out"
done
for bumped in "new dependency requests" "new dependency Alamofire" "new dependency swift-algorithms" \
              "new dependency http," "new dependency serde" "new dependency click" "new dependency org.slf4j"; do
  expect_not_in "version bump is not new: $bumped" "$bumped" "$out"
done
adv="$(DEVKIT_LANG=en gate_nomatrix --json | tail -n 1 | python3 -c 'import json,sys; print(len([a for a in json.load(sys.stdin).get("advisories", []) if "new dependency" in a]))')"
[ "$adv" = 7 ] && echo "✔ --json carries the 7 advisories" || { echo "✖ --json advisories: '$adv'"; FAILS=$((FAILS + 1)); }

# --- Proof block judges only this turn's images; older ones are references, never findings ---
mkpng() { python3 -c 'import os,sys,zlib,struct
def c(t,d): return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
open(sys.argv[1],"wb").write(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",1,1,8,2,0,0,0))+c(b"IDAT",os.urandom(20000))+c(b"IEND",b""))' "$1"; }
make_repo "true"; mkdir -p reports
mkpng reports/proof-old-a.png; git add reports && git commit -qm proofs && git rm -q reports/proof-old-a.png
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "deleted tracked proof image -> not judged" 0 $? "$out" "zero-byte proof image"
make_repo "true"; mkdir -p reports
mkpng reports/proof-old-1.png; cp reports/proof-old-1.png reports/proof-old-2.png
touch -t 202609200000 reports/proof-old-1.png reports/proof-old-2.png
mkpng reports/proof-new.png; echo "fun ok() = 2" > src/Core.kt
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "two OLD duplicate proofs do not block a later turn" 0 $? "$out" "identical bytes"
cp reports/proof-old-1.png reports/proof-new2.png
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "a NEW proof identical to an old one -> REJECT" 1 $? "$out"
expect_in "the new duplicate is named" "reports/proof-new2.png: identical bytes" "$out"
make_repo "true"; mkdir -p reports; printf 'reports/\n' > .gitignore; git add .gitignore && git commit -qm ign
mkpng reports/proof-a.png; cp reports/proof-a.png reports/proof-b.png; echo "fun ok() = 2" > src/Core.kt
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "fresh duplicate proofs in a git-ignored reports/ -> REJECT" 1 $? "$out"
make_repo "true"; mkdir -p reports; printf 'reports/\n' > .gitignore
rm reports/proof-new2.png; : > reports/proof-empty.png
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "a NEW zero-byte proof -> REJECT" 1 $? "$out"

# --- Documentation-only change: nothing a regression test could catch, so no test is required ---
make_repo "true"
mkdir -p docs && echo "# notes" > docs/NOTES.md && echo "readme" > README.md
out="$(run_gate --run-tests --full)"; check "docs-only change, no matching test -> PASS" 0 $? "$out"
echo "fun other() = 1" > src/Other.kt
out="$(run_gate --run-tests --full)"; check "docs + unmatched code -> still UNVERIFIED" 2 $? "$out"
make_repo "true"
mkdir -p docs && echo "x = 1" > docs/conf.py
out="$(run_gate --run-tests --full)"; check "code under docs/ is not documentation -> UNVERIFIED" 2 $? "$out"

# Review 2026-09-25: manifest parsers name packages, never groups / URL schemes / tag order.
make_repo "true"
printf '[project]\nname = "p"\ndependencies = ["requests>=2"]\n' > pyproject.toml
printf 'Foo_Bar==1.0\n' > requirements.txt
printf '<project><dependencies></dependencies></project>\n' > pom.xml
git add -A && git commit -qm m2
printf '[project]\nname = "p"\ndependencies = ["requests>=2"]\n[project.optional-dependencies]\ndocs = ["sphinx>=7"]\n' > pyproject.toml
printf 'foo-bar==1.0\ngit+https://github.com/org/lib.git#egg=vcslib\n-e git+https://github.com/org/ed.git#egg=edlib\n' > requirements.txt
printf '<project><dependencies><dependency><!-- n --><artifactId>guava</artifactId><groupId>com.google.guava</groupId></dependency></dependencies></project>\n' > pom.xml
out="$(DEVKIT_LANG=en gate_nomatrix)"
expect_in "pyproject: optional group member named" "pyproject.toml: new dependency sphinx" "$out"
expect_not_in "pyproject: group name is not a package" "new dependency docs" "$out"
expect_in "pip: VCS egg named" "vcslib" "$out"
expect_in "pip: editable egg named" "edlib" "$out"
expect_not_in "pip: URL scheme is not a package" "new dependency edlib, git" "$out"
expect_not_in "pip: Foo_Bar -> foo-bar is a rename, not new" "foo-bar" "$out"
expect_in "pom: any child order" "pom.xml: new dependency com.google.guava:guava" "$out"

# --- Vacuous-test audit judges test SOURCE, not a script that writes one as a fixture -----
make_repo "true"
mkdir -p src/test/kotlin tests
printf 'import org.junit.Test\nclass FooTest {\n    @Test fun a() {}\n}\n' > src/test/kotlin/FooTest.kt
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "Kotlin @Test with no assertion -> REJECT" 1 $? "$out"
expect_in "vacuous Kotlin test named" "Vacuous test at line 3" "$out"
rm src/test/kotlin/FooTest.kt
printf '#!/bin/sh\nprintf %s "class T {\\n    @Test fun a() {}\\n}" > "$TMP/T.kt"\n' "'" > tests/test_fixture.sh
out="$(DEVKIT_LANG=en gate_nomatrix)"; check "@Test inside a shell fixture -> not a vacuous test" 0 $? "$out" "Vacuous test"

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

# --- An existing test edited by ANOTHER session (or a person) must not block this one ----
# 2026-09-25: session X edited two existing tests; session Y, which never touched them, got
# "UNVERIFIED — existing test edited" on every Stop until X committed. The block binds to the
# session that made the edit (--session/--transcript: its Edit/Write calls, its write-shaped
# Bash commands, its bash_write_ledger windows). Someone else's edit: a warning, not a block.
# No session info, or no way to tell: today's block (the "existing test edited" check above).
# fake_session <sid> <transcript> [edit-path [tool]] — a transcript that started 10 min ago, with one
# harmless Bash call and optionally a <tool> call (default Edit) on <edit-path>; for tool=Bash,
# <edit-path> is the command.
fake_session() {
  python3 - "$@" <<'PY'
import json, sys, time
sid, tp = sys.argv[1], sys.argv[2]
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))
now = time.time()
recs = [{"type": "user", "sessionId": sid, "timestamp": iso(now - 600), "message": {"role": "user", "content": "fix it"}},
        {"type": "assistant", "sessionId": sid, "timestamp": iso(now - 590), "message": {"content": [
            {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "git status"}}]}}]
if len(sys.argv) > 3:
    tool = sys.argv[4] if len(sys.argv) > 4 else "Edit"
    inp = ({"command": sys.argv[3]} if tool == "Bash"
           else {"file_path": sys.argv[3], "old_string": "a", "new_string": "b"})
    recs.append({"type": "assistant", "sessionId": sid, "timestamp": iso(now - 580), "message": {"content": [
        {"type": "tool_use", "id": "t2", "name": tool, "input": inp}]}})
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in recs))
PY
}
# ledger_window <sid> <tool-use-id> <start> <end> — offsets in seconds from now (negative = past)
ledger_window() {
  mkdir -p .claude/audit-gate
  python3 -c 'import sys,time; n=time.time(); s,t,a,b=sys.argv[1:]
print("%s\tstart\t%.3f\t%s\n%s\tend\t%.3f\t%s" % (s, n+float(a), t, s, n+float(b), t))' "$@" >> .claude/audit-gate/bash_write_ledger.tsv
}
set_mtime() { python3 -c 'import os,sys,time; t=time.time()+float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$2"; }
existing_test_repo() {
  make_repo "true"
  mkdir -p src/test && echo "assert(true)" > src/test/CoreTest.kt && git add -A && git commit -qm t
  echo "fun ok() = 2" > src/Core.kt && echo "// weakened" > src/test/CoreTest.kt
}

existing_test_repo   # the edit happened inside ANOTHER session's Bash window; this one has its own windows
set_mtime src/test/CoreTest.kt -300; ledger_window s-other b1 -305 -295; ledger_window s-me m1 -590 -589
fake_session s-me "$TMP/me.jsonl"
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "existing test edited by another session -> not blocked (PASS)" 0 $? "$out"
expect_in "…but warned, naming the file" "src/test/CoreTest.kt" "$out"
json="$(run_gate --run-tests --json --session s-me --transcript "$TMP/me.jsonl" | tail -1)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["tests_touched"] == [] and d["tests_touched_other"] == ["src/test/CoreTest.kt"], d' "$json" 2>/dev/null \
  && echo "✔ --json: tests_touched empty, tests_touched_other names it" || { echo "✖ json: $(printf '%s' "$json" | cut -c1-300)"; FAILS=$((FAILS + 1)); }

existing_test_repo   # changed during this session, outside every Bash window, and no other session's
# window holds it: a person — or this session through a path the gate cannot see (a detached
# process, a write tool it does not know). Not evidence of "other": blocked (fail closed).
set_mtime src/test/CoreTest.kt -120; ledger_window s-me m1 -590 -589
fake_session s-me "$TMP/me.jsonl"
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "existing test changed during the session outside every window, no other session -> UNVERIFIED" 2 $? "$out" "PASS —"

existing_test_repo   # this session edited it with a write-capable MCP tool (no Edit/Write, no Bash window)
set_mtime src/test/CoreTest.kt -120; ledger_window s-me m1 -590 -589
fake_session s-me "$TMP/me.jsonl" "$TMP/repo/src/test/CoreTest.kt" mcp__jetbrains__replace_text_in_file
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "existing test edited by this session via an MCP write tool -> UNVERIFIED" 2 $? "$out" "PASS —"

existing_test_repo   # …even when another session's window holds the mtime: an unknown tool = cannot tell
set_mtime src/test/CoreTest.kt -300; ledger_window s-other b1 -305 -295; ledger_window s-me m1 -590 -589
fake_session s-me "$TMP/me.jsonl" "$TMP/repo/src/test/CoreTest.kt" mcp__jetbrains__replace_text_in_file
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "unknown (MCP write) tool in the session -> attribution off, UNVERIFIED" 2 $? "$out" "PASS —"

existing_test_repo   # a read-only MCP tool does not switch attribution off
set_mtime src/test/CoreTest.kt -300; ledger_window s-other b1 -305 -295; ledger_window s-me m1 -590 -589
fake_session s-me "$TMP/me.jsonl" "$TMP/repo/src/test/CoreTest.kt" mcp__codebase-memory-mcp__search_code
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "read-only MCP tool + another session's window -> still a warning (PASS)" 0 $? "$out"

existing_test_repo   # this session wrote it, then backdated it with touch -t (mtime before the session)
set_mtime src/test/CoreTest.kt -3600; ledger_window s-me m1 -590 -589
fake_session s-me "$TMP/me.jsonl" "touch -t 202001010000 src/test/CoreTest.kt" Bash
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "touch -t by this session after writing the test -> UNVERIFIED" 2 $? "$out" "PASS —"

existing_test_repo   # the same edit made by THIS session (Edit tool) -> block
fake_session s-me "$TMP/me.jsonl" "$TMP/repo/src/test/CoreTest.kt"
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "existing test edited by this session (Edit) -> UNVERIFIED" 2 $? "$out" "PASS —"
expect_in "…the verdict names the edited test" "src/test/CoreTest.kt" "$out"

existing_test_repo   # this session wrote it from a Bash window (sed -i, a script) -> block
set_mtime src/test/CoreTest.kt -200; ledger_window s-other b1 -400 -100; ledger_window s-me m1 -205 -195
fake_session s-me "$TMP/me.jsonl"
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "existing test written inside this session's (narrowest) Bash window -> UNVERIFIED" 2 $? "$out" "PASS —"
expect_in "…the verdict names the edited test" "src/test/CoreTest.kt" "$out"

existing_test_repo   # this session's Bash calls are in no ledger (hook not wired): cannot tell -> block
set_mtime src/test/CoreTest.kt -120
fake_session s-me "$TMP/me.jsonl"
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "attribution impossible (Bash calls, no ledger) -> today's UNVERIFIED" 2 $? "$out" "PASS —"
expect_in "…the verdict names the edited test" "src/test/CoreTest.kt" "$out"

existing_test_repo   # edited before this session's first prompt: never this session's edit
set_mtime src/test/CoreTest.kt -3600
fake_session s-me "$TMP/me.jsonl"
out="$(run_gate --run-tests --session s-me --transcript "$TMP/me.jsonl")"
check "existing test edited before this session started -> warning, not a block" 0 $? "$out"

existing_test_repo   # a missing transcript: today's behaviour
out="$(run_gate --run-tests --session s-me --transcript "$TMP/nope.jsonl")"
check "unreadable transcript -> today's UNVERIFIED" 2 $? "$out" "PASS —"
expect_in "…the verdict names the edited test" "src/test/CoreTest.kt" "$out"

# --- Another run holds the project's test-run lock: BUSY, said as such -----------------
# A BUSY run is UNTESTED (exit 4) but not "missing tool/device" — the Stop hook must tell it
# apart (summary "busy") to say the right cause and not cache it for the tree.
make_repo "true"
echo "fun ok() = 2" > src/Core.kt
python3 - "$TMP/repo" "$TMP" <<'PY2' &
import fcntl, os, sys, time
p, tmp = sys.argv[1], sys.argv[2]
os.makedirs(p + "/.claude/audit-gate", exist_ok=True)
with open(p + "/.claude/audit-gate/test_run.lock", "w") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(tmp + "/busy_held", "w").close()
    time.sleep(60)
PY2
busy_holder=$!
for _ in $(seq 1 50); do [ -f "$TMP/busy_held" ] && break; sleep 0.1; done
json="$(TEST_RUN_LOCK_WAIT_S=1 run_gate --run-tests --json | tail -1)"; rc=$?
kill "$busy_holder" 2>/dev/null; wait "$busy_holder" 2>/dev/null
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); v=d["verdict"]
assert d["exit_code"] == 4 and d.get("busy") is True, d
assert "thiếu công cụ" not in v and "missing tool" not in v, v' "$json" 2>/dev/null \
  && echo "✔ lock held by another run -> exit 4, summary busy=true, verdict does not blame a missing tool" \
  || { echo "✖ busy summary: $(printf '%s' "$json" | cut -c1-300)"; FAILS=$((FAILS + 1)); }

if [ "$FAILS" -ne 0 ]; then
  echo "post-fix-gate: $FAILS FAILED"; exit 1
fi
echo "post-fix-gate: all checks passed"
