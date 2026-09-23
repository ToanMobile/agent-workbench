#!/usr/bin/env bash
# Regression test: scripts/matrix_detect.py — a regression matrix generated from the
# project's own test runner replaces the illustrative sample matrices, is trusted by the
# post-fix gate only while byte-identical to a fresh generation, and is enforced by the
# Stop-time regression gate.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MD="$DEVKIT_DIR/scripts/matrix_detect.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset CLAUDE_PROJECT_DIR TARGET_DIR DEVKIT_SOURCE_EXTS

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
proj() { rm -rf "$TMP/$1"; mkdir -p "$TMP/$1"; printf '%s' "$TMP/$1"; }
cmds() { python3 "$MD" "$1" 2>/dev/null | python3 -c 'import json,sys
try: print(" | ".join(t["command"] for t in json.load(sys.stdin)["rules"][0]["mandatory_regression_tests"]))
except Exception: print("none")'; }

# --- detection per ecosystem ------------------------------------------------------
P="$(proj android)"; touch "$P/gradlew"; mkdir -p "$P/app"; echo 'plugins { id("com.android.application") }' > "$P/app/build.gradle.kts"
[ "$(cmds "$P")" = "./gradlew testDebugUnitTest" ] && ok "Android Gradle → ./gradlew testDebugUnitTest" || fail "android: $(cmds "$P")"
P="$(proj jvm)"; touch "$P/gradlew" "$P/build.gradle"
[ "$(cmds "$P")" = "./gradlew test" ] && ok "plain Gradle → ./gradlew test" || fail "jvm: $(cmds "$P")"
P="$(proj swift)"; touch "$P/Package.swift"
[ "$(cmds "$P")" = "swift test" ] && ok "Swift package → swift test" || fail "swift: $(cmds "$P")"
P="$(proj pnpm)"; echo '{"scripts":{"test":"vitest run"}}' > "$P/package.json"; touch "$P/pnpm-lock.yaml"
[ "$(cmds "$P")" = "pnpm test" ] && ok "package.json + pnpm lockfile → pnpm test" || fail "pnpm: $(cmds "$P")"
P="$(proj npmdefault)"; echo '{"scripts":{"test":"echo \"Error: no test specified\" && exit 1"}}' > "$P/package.json"
[ "$(cmds "$P")" = "none" ] && ok "npm's placeholder test script is not a runner" || fail "npm default: $(cmds "$P")"
P="$(proj py)"; mkdir -p "$P/tests"; touch "$P/tests/test_core.py"
[ "$(cmds "$P")" = "python3 -m pytest -q" ] && ok "tests/test_*.py → pytest" || fail "pytest: $(cmds "$P")"
P="$(proj multi)"; touch "$P/go.mod" "$P/Cargo.toml"
[ "$(cmds "$P")" = "go test ./... | cargo test" ] && ok "go + cargo → both suites" || fail "multi: $(cmds "$P")"
# Unity: Assets/ + ProjectSettings/ProjectVersion.txt → EditMode tests through the profile
# script. Rider/VS generate *.sln/*.csproj inside a Unity project and `dotnet test` does not
# run Unity tests, so the .NET runner must not fire there.
P="$(proj unity)"; mkdir -p "$P/Assets" "$P/ProjectSettings" "$P/scripts" "$P/Tools"
echo 'm_EditorVersion: 6000.0.0f1' > "$P/ProjectSettings/ProjectVersion.txt"
touch "$P/Game.sln" "$P/Assembly-CSharp.csproj" "$P/Tools/Tools.csproj" "$P/scripts/unity-test.sh"
[ "$(cmds "$P")" = "bash .agents/active-profile/scripts/unity-batch.sh editmode" ] \
  && ok "Unity project (with IDE .sln/.csproj) → unity-batch.sh editmode, not dotnet test" || fail "unity: $(cmds "$P")"
P="$(proj dotnet)"; touch "$P/App.sln"
[ "$(cmds "$P")" = "dotnet test" ] && ok "plain .NET solution → dotnet test" || fail "dotnet: $(cmds "$P")"
# Android via version-catalog aliases, convention plugins, or a module manifest.
P="$(proj alias)"; touch "$P/gradlew"; mkdir -p "$P/app"; echo 'plugins { alias(libs.plugins.android.application) }' > "$P/app/build.gradle.kts"
[ "$(cmds "$P")" = "./gradlew testDebugUnitTest" ] && ok "Android via version-catalog alias → testDebugUnitTest" || fail "alias: $(cmds "$P")"
P="$(proj convention)"; touch "$P/gradlew"; mkdir -p "$P/core/common"; echo 'include(":core:common")' > "$P/settings.gradle.kts"
echo 'plugins { id("acme.android.library") }' > "$P/core/common/build.gradle.kts"
[ "$(cmds "$P")" = "./gradlew testDebugUnitTest" ] && ok "Android via a convention plugin id in a nested module → testDebugUnitTest" || fail "convention: $(cmds "$P")"
P="$(proj manifest)"; touch "$P/gradlew"; mkdir -p "$P/app/src/main"; echo 'plugins { id("acme.app") }' > "$P/app/build.gradle.kts"
touch "$P/app/src/main/AndroidManifest.xml"
[ "$(cmds "$P")" = "./gradlew testDebugUnitTest" ] && ok "Android via <module>/src/main/AndroidManifest.xml → testDebugUnitTest" || fail "manifest: $(cmds "$P")"
# A module whose testBuildType is not debug has no testDebugUnitTest: the root
# `./gradlew testDebugUnitTest` would skip it silently, so its own task is named.
P="$(proj testbuildtype)"; touch "$P/gradlew"; mkdir -p "$P/app/src/test" "$P/feature/home/src/test" "$P/bench/src/main" "$P/lib/src/test"
printf 'include(":app")\ninclude(":feature:home", ":bench")\ninclude ":lib"\n' > "$P/settings.gradle.kts"
printf 'plugins { alias(libs.plugins.android.application) }\nandroid {\n    testBuildType = "release"\n}\n' > "$P/app/build.gradle.kts"
printf "plugins { id 'acme.android.library' }\nandroid {\n    testBuildType 'qa'\n}\n" > "$P/feature/home/build.gradle"
printf 'plugins { alias(libs.plugins.android.library) }\nandroid { testBuildType = "release" }\n' > "$P/bench/build.gradle.kts"
printf 'plugins { alias(libs.plugins.android.library) }\n// testBuildType = "release" was tried and reverted\n' > "$P/lib/build.gradle.kts"
[ "$(cmds "$P")" = "./gradlew testDebugUnitTest :app:testReleaseUnitTest :feature:home:testQaUnitTest" ] \
  && ok "testBuildType release/qa → :<module>:test<X>UnitTest next to testDebugUnitTest (no src/test or a comment → none)" || fail "testBuildType: $(cmds "$P")"
# Never emit a task that may not exist: flavors → the module's `test` (every variant has
# its own test<Flavor><Type>UnitTest), Kotlin Multiplatform → no testDebugUnitTest/test at
# all, so its host/JVM test task or allTests.
P="$(proj flavors)"; touch "$P/gradlew"; mkdir -p "$P/app" "$P/overlay/wl"
printf 'include(":app")\ninclude(":overlay:wl")\n' > "$P/settings.gradle.kts"
printf 'plugins { alias(libs.plugins.android.application) }\nandroid {\n    flavorDimensions += "install"\n    productFlavors { create("system") { dimension = "install" } }\n}\n' > "$P/app/build.gradle.kts"
echo 'plugins { alias(libs.plugins.android.application) }' > "$P/overlay/wl/build.gradle.kts"
[ "$(cmds "$P")" = "./gradlew testDebugUnitTest :app:test" ] && ok "productFlavors → :app:test (testDebugUnitTest does not exist there)" || fail "flavors: $(cmds "$P")"
P="$(proj flavoronly)"; touch "$P/gradlew"; printf 'plugins { id("com.android.application") }\nandroid { productFlavors { free {} } }\n' > "$P/build.gradle"
[ "$(cmds "$P")" = "./gradlew test" ] && ok "single-project flavored app → ./gradlew test" || fail "flavor only: $(cmds "$P")"
P="$(proj kmp)"; touch "$P/gradlew"; mkdir -p "$P/src/commonMain"
printf '// com.android.library + kotlin.multiplatform are blocked from AGP 9\nplugins {\n    alias(libs.plugins.kotlin.multiplatform)\n    alias(libs.plugins.android.kmp.library)\n}\nkotlin {\n    android { namespace = "x" }\n    iosSimulatorArm64()\n}\n' > "$P/build.gradle.kts"
[ "$(cmds "$P")" = "./gradlew allTests" ] && ok "KMP library (no host test, no jvm target) → ./gradlew allTests" || fail "kmp: $(cmds "$P")"
P="$(proj kmphost)"; touch "$P/gradlew"; mkdir -p "$P/app" "$P/composeUi"; printf 'include(":app")\ninclude(":composeUi")\n' > "$P/settings.gradle.kts"
echo 'plugins { alias(libs.plugins.android.application) }' > "$P/app/build.gradle.kts"
printf 'plugins {\n    id("org.jetbrains.kotlin.multiplatform")\n    id("com.android.kotlin.multiplatform.library")\n}\nkotlin {\n    android {\n        withHostTest { }\n    }\n    jvm()\n}\n' > "$P/composeUi/build.gradle.kts"
[ "$(cmds "$P")" = "./gradlew testDebugUnitTest :composeUi:testAndroidHostTest :composeUi:jvmTest" ] \
  && ok "KMP module with withHostTest + jvm() → :composeUi:testAndroidHostTest :composeUi:jvmTest" || fail "kmp host: $(cmds "$P")"
P="$(proj composemp)"; touch "$P/gradlew"; mkdir -p "$P/app" "$P/buildSrc"; printf 'include(":app")\n' > "$P/settings.gradle.kts"
printf 'plugins {\n    alias(libs.plugins.android.application)\n    alias(libs.plugins.compose.multiplatform)\n}\n' > "$P/app/build.gradle.kts"
echo 'plugins { `kotlin-dsl` }' > "$P/buildSrc/build.gradle.kts"
[ "$(cmds "$P")" = "./gradlew testDebugUnitTest" ] && ok "Android app with the Compose Multiplatform plugin is not KMP (no :app:allTests)" || fail "compose mp: $(cmds "$P")"
P="$(proj noandroidmod)"; touch "$P/gradlew"; mkdir -p "$P/core"; echo 'include(":core")' > "$P/settings.gradle.kts"
echo 'plugins { alias(libs.plugins.android.library) apply false }' > "$P/build.gradle.kts"; echo 'plugins { kotlin("jvm") }' > "$P/core/build.gradle.kts"
[ "$(cmds "$P")" = "./gradlew test" ] && ok "Android plugins only declared (apply false), no Android module → ./gradlew test" || fail "no android module: $(cmds "$P")"
for d in unity testbuildtype; do
  python3 "$MD" "$TMP/$d" > "$TMP/$d.1"; python3 "$MD" "$TMP/$d" > "$TMP/$d.2"
  cmp -s "$TMP/$d.1" "$TMP/$d.2" && ok "$d: generation is byte-identical across runs" || fail "$d: generation not deterministic"
done
P="$(proj empty)"
python3 "$MD" "$P" >/dev/null; [ $? = 3 ] && ok "no runner → exit 3, nothing generated" || fail "empty project"

# --- agent-kit profile writes the generated matrix instead of the sample ----------
P="$(proj app)"; (cd "$P" && git init -q . && git config user.email t@t && git config user.name t)
printf '#!/bin/sh\n[ -f fail ] && exit 1\nexit 0\n' > "$P/gradlew"; chmod +x "$P/gradlew"
mkdir -p "$P/app/src/main"; echo 'plugins { id("com.android.library") }' > "$P/app/build.gradle.kts"
echo "class Core" > "$P/app/src/main/Core.kt"
(cd "$P" && git add -A && git commit -qm init)
python3 "$DEVKIT_DIR/bin/agent-config.py" --profile android --target "$P" >"$TMP/out" 2>&1
M="$P/.agents/regression_matrix.active.json"
grep -q '"./gradlew testDebugUnitTest"' "$M" 2>/dev/null && grep -q "generated_by" "$M" \
  && ok "profile android: matrix generated from the project's runner (not the sample)" || { fail "matrix not generated"; cat "$TMP/out"; }
P2="$(proj web)"; echo '{"scripts":{"test":"jest"}}' > "$P2/package.json"
python3 "$DEVKIT_DIR/bin/agent-config.py" --profile web --target "$P2" >/dev/null 2>&1
cmp -s "$P2/.agents/regression_matrix.active.json" "$DEVKIT_DIR/profiles/web/regression_matrix.json" \
  && ok "profile web keeps its enforce_as_is sample (it auto-detects the runner itself)" || fail "web sample replaced"

# --- post-fix gate: trusted while byte-identical, not once edited ------------------
echo "class Core { val x = 1 }" > "$P/app/src/main/Core.kt"
out="$(CLAUDE_PROJECT_DIR="$P" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --no-checklist 2>&1)"; rc=$?
[ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q "cannot be trusted" \
  && ok "uncommitted generated matrix is trusted; its suite runs → PASS" || fail "generated matrix not trusted (rc=$rc)"
cp "$M" "$TMP/m.bak"; sed -i.x 's#./gradlew testDebugUnitTest#true#' "$M" && rm -f "$M.x"
out="$(CLAUDE_PROJECT_DIR="$P" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --no-checklist 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "cannot be trusted" \
  && ok "edited matrix (command → true) is not trusted → UNVERIFIED" || fail "edited matrix trusted (rc=$rc)"
cp "$TMP/m.bak" "$M"

# --- the Stop-time regression gate enforces it ---------------------------------------
touch "$P/fail"
out="$(printf '{"session_id":"md1","hook_event_name":"Stop"}' | CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/regression_gate.sh" 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "REG-AUTO-01" && ok "regression gate blocks the stop while the project's suite fails" \
  || fail "regression gate did not enforce the generated matrix (rc=$rc)"
rm -f "$P/fail"

# --- uninstall removes an unchanged generated matrix -------------------------------
python3 "$DEVKIT_DIR/scripts/devkit_uninstall.py" "$P" --apply >/dev/null 2>&1
[ ! -e "$M" ] && ok "uninstall removes the unchanged generated matrix" || fail "generated matrix left behind"

# --- monorepo: first-level modules with their own runner -------------------------------
rules() { python3 "$MD" "$1" 2>/dev/null | python3 -c 'import json,sys
try: print(" | ".join(r["component"] + "=" + ";".join(t["command"] for t in r["mandatory_regression_tests"]) for r in json.load(sys.stdin)["rules"]))
except Exception: print("none")'; }
P="$(proj mono)"; mkdir -p "$P/CarConnect/app/src/test" "$P/PhoneConnect/src/test" "$P/PCConnect" "$P/node_modules/x"
touch "$P/CarConnect/gradlew" "$P/PhoneConnect/gradlew" "$P/node_modules/x/go.mod"
echo 'plugins { id("com.android.application") }' > "$P/CarConnect/app/build.gradle.kts"; echo 'module pc' > "$P/PCConnect/go.mod"
[ "$(rules "$P")" = "CarConnect=cd CarConnect && ./gradlew testDebugUnitTest | PCConnect=cd PCConnect && go test ./... | PhoneConnect=cd PhoneConnect && ./gradlew test" ] \
  && ok "monorepo root: one rule per module (cd <module> && runner), node_modules skipped" || fail "monorepo: $(rules "$P")"
P="$(proj pnpmws)"; echo '{"scripts":{"test":"vitest run"}}' > "$P/package.json"; touch "$P/pnpm-lock.yaml"
printf 'packages:\n  - "packages/*"\n' > "$P/pnpm-workspace.yaml"; mkdir -p "$P/web"; echo '{"scripts":{"test":"vitest run"}}' > "$P/web/package.json"
[ "$(rules "$P")" = "ProjectTestSuite=pnpm test" ] && ok "pnpm workspace: the root runner covers its packages (no duplicate)" || fail "pnpm ws: $(rules "$P")"
P="$(proj cargows)"; printf '[workspace]\nmembers = ["core"]\n' > "$P/Cargo.toml"; mkdir -p "$P/core"; printf '[package]\nname="core"\n' > "$P/core/Cargo.toml"
[ "$(rules "$P")" = "ProjectTestSuite=cargo test" ] && ok "Cargo workspace: the root runner covers its members" || fail "cargo ws: $(rules "$P")"

# A composite build (includeBuild("../shared")) consumed by two modules: a change in
# shared/ must also run the consumers' suites, not only shared's own.
watch() { python3 "$MD" "$1" 2>/dev/null | python3 -c 'import json,sys
try: print(" ".join(w for r in json.load(sys.stdin)["rules"] if r["component"] == sys.argv[1] for w in r["watch_files"]))
except Exception: print("none")' "$2"; }
P="$(proj composite)"; mkdir -p "$P/CarConnect/app/src/test" "$P/PhoneConnect/app/src/test" "$P/shared" "$P/Tools/src/test"
touch "$P/CarConnect/gradlew" "$P/PhoneConnect/gradlew" "$P/shared/gradlew" "$P/Tools/gradlew"
printf 'include(":app")\nincludeBuild("../shared")\n' > "$P/CarConnect/settings.gradle.kts"
printf "include ':app'\nincludeBuild '../shared'\n" > "$P/PhoneConnect/settings.gradle"
printf '// includeBuild("../PhoneConnect")\ninclude(":x")\n' > "$P/Tools/settings.gradle.kts"
w="$(watch "$P" CarConnect)"; w2="$(watch "$P" PhoneConnect)"; w3="$(watch "$P" Tools)"
case "$w" in *"CarConnect/*.kt"*"shared/*.kt"*) ok "includeBuild(\"../shared\"): the consumer rule also watches shared/" ;; *) fail "composite consumer: $w" ;; esac
case "$w2" in *"shared/*.kt"*) ok "Groovy includeBuild '../shared' is followed too" ;; *) fail "groovy composite consumer: $w2" ;; esac
[ -z "$(watch "$P" shared)" ] && ok "shared/ has no test sources: no rule of its own (zero tests would pass green)" \
  || fail "test-less shared/ got its own rule"
case "$w3" in *"PhoneConnect/"*) fail "commented includeBuild followed: $w3" ;; *) ok "a commented-out includeBuild is ignored" ;; esac

# The regression gate runs only the suite of the module that changed.
P="$(proj monogate)"; (cd "$P" && git init -q . && git config user.email t@t && git config user.name t)
mkdir -p "$P/CarConnect/app/src/main" "$P/CarConnect/app/src/test" "$P/PCConnect"
printf '#!/bin/sh\necho "CarConnect Gradle ran"; exit 1\n' > "$P/CarConnect/gradlew"; chmod +x "$P/CarConnect/gradlew"
echo 'plugins { id("com.android.application") }' > "$P/CarConnect/app/build.gradle.kts"
echo "class Main" > "$P/CarConnect/app/src/main/Main.kt"
printf 'module pc\n\ngo 1.21\n' > "$P/PCConnect/go.mod"
printf 'package pc\n\nfunc Add(a, b int) int { return a + b }\n' > "$P/PCConnect/calc.go"
printf 'package pc\n\nimport "testing"\n\nfunc TestAdd(t *testing.T) { if Add(1, 2) != 3 { t.Fatal("bad") } }\n' > "$P/PCConnect/calc_test.go"
python3 "$DEVKIT_DIR/bin/agent-config.py" --profile android --target "$P" >/dev/null 2>&1
(cd "$P" && git add -A && git commit -qm init)
gate() { printf '{"session_id":"%s","hook_event_name":"Stop"}' "$1" | CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/regression_gate.sh" 2>&1; }
printf 'package pc\n\n// Add sums.\nfunc Add(a, b int) int { return a + b }\n' > "$P/PCConnect/calc.go"
out="$(gate mono1)"; rc=$?
[ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q CarConnect && ok "change in PCConnect/: only its go test runs (CarConnect's failing Gradle is not run)" \
  || fail "PCConnect change ran other modules (rc=$rc): $out"
(cd "$P" && git checkout -q -- .)
echo "class Main { val x = 1 }" > "$P/CarConnect/app/src/main/Main.kt"
out="$(gate mono2)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "REG-AUTO-CARCONNECT-01" && ok "change in CarConnect/: its Gradle suite runs and its failure blocks" \
  || fail "CarConnect change not enforced (rc=$rc)"
P2="$(proj webmono)"; mkdir -p "$P2/site" "$P2/api"; echo '{"scripts":{"test":"jest"}}' > "$P2/site/package.json"; echo 'module api' > "$P2/api/go.mod"
python3 "$DEVKIT_DIR/bin/agent-config.py" --profile web --target "$P2" >/dev/null 2>&1
grep -q '"cd site && npm test"' "$P2/.agents/regression_matrix.active.json" 2>/dev/null \
  && ok "profile web on a monorepo root (no root package.json): per-module matrix, not the root-only sample" || fail "web monorepo got the sample"

if [ "$FAILS" -ne 0 ]; then
  echo "matrix detect: $FAILS FAILED"; exit 1
fi
echo "matrix detect: all checks passed"
