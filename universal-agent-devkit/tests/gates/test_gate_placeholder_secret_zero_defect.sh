#!/usr/bin/env bash
# Regression test: Zero-Defect holes in the static audit of bin/post-fix-gate.py (audit 2026-11-14, three reviewers,
# each case reproduced on a throwaway repo). Two-way: every "must flag" has a "must pass" next to it.
#  C2a  placeholder wordings the patterns missed: `# TODO: implement rest`, `/* TODO: implement rest */`, a block
#       comment with words after the keyword, a JSX `{/* … */}`, `<!-- ... existing code ... -->`, the Unicode
#       ellipsis, `// ... (existing code) ...`, `// rest of implementation unchanged`, `pass  # placeholder`.
#  C2b  files the audit never read: .sh, .gradle.kts, .gradle, .mjs, .rb, .yml, and everything under scripts/.
#  C2c  false blocks: a JS rest element `...remaining` named in a comment; controls: a test file's string literal,
#       a .md about placeholders, ordinary comments holding "rest" / "existing".
#  C3b  `.env.production.local`, `.env.prod.local` (two suffixes) were not forbidden files.
#  C3c  secret assignments the scan missed: `export API_KEY=…` in a script, `os.environ["API_KEY"] = "…"`,
#       `<string name="api_key">…</string>`, `buildConfigField(… "API_KEY", "\"…\"")`, `"Authorization": "Bearer …"`,
#       `DB_PASS = "…"`; controls: the same shapes holding a reference or a placeholder value pass.
#  R5   round 5 (independent review of bc5b7e3c against its parent 5db81236):
#       A1 the rest-element pass is closed: only a comment on the SAME line as code spreading that identifier before it;
#          a comment on its own line is reported whatever the file spreads. A quoted `// ... existing code ...` in a file
#          the parent scan read is reported as the parent did (reverses the v2 pass C2t-06 for production code files).
#       A2 `API_KEY=` with an empty value no longer reads the next line as its value (config files).
#       A3 key names holding `secret` before `key`: SECRET_KEY, secretKey, JWT_SECRET_KEY, client_secret_key.
# Every "secret" below is a fake the fixture writer joins at run time (@F@ tokens): this file holds no value a scan matches.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_SUITE_CACHE=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/repo/src" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf 'def f():\n    return 1\n' > src/core.py
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"All","watch_files":["*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init

# Fixtures: one file per case, so a finding names its case. cases.tsv: id, want (flag|pass), kind, path, title.
#  kind lazy = a "lazy" finding on the file; name = a forbidden-file finding (category secrets, no line);
#  content = a secret found in the text (category secrets, with a line).
python3 - "$TMP/cases.tsv" <<'PY'
import os, sys
piece = "q7Mk2xR"                       # 7 chars: shorter than any quoted-value rule; the fakes exist only at run time
F = (piece * 3)[:20]
F32 = (piece * 5)[:32]
F40 = (piece * 6)[:40]
EL = "…"                           # the Unicode ellipsis
LINE_SLASH = "// ... existing code ...\n"
LINE_HASH = "# ... existing code ...\n"
CASES = [
    # ── controls: what the gate already caught stays caught (the harness sees findings) ──
    ("ctl-lazy-kt", "flag", "lazy", "src/ctl.kt", "control: // ... existing code ... in .kt", "fun ok() = 1\n" + LINE_SLASH),
    ("ctl-lazy-py", "flag", "lazy", "src/ctl.py", "control: # ... existing code ... in .py", "def f():\n    " + LINE_HASH + "    return 1\n"),
    ("ctl-secret-py", "flag", "content", "src/ctl_secret.py", "control: API_KEY = \"<fake>\" in .py", 'API_KEY = "@F@"\n'),
    ("ctl-env-local", "flag", "name", ".env.local", "control: .env.local is a forbidden file", "API_KEY=@F@\n"),
    # ── C2a: wordings ──
    ("C2a-01", "flag", "lazy", "src/a01.py", "# TODO: implement rest (.py)", "def f():\n    # TODO: implement rest\n    return 1\n"),
    ("C2a-02", "flag", "lazy", "src/a02.ts", "/* TODO: implement rest */ (.ts)", "export const a = 1\n/* TODO: implement rest */\n"),
    ("C2a-03", "flag", "lazy", "src/a03.ts", "/* ... existing code ... */", "export const a = 1\n/* ... existing code ... */\n"),
    ("C2a-04", "flag", "lazy", "src/a04.kt", "/* ... existing code here ... */", "fun ok() = 1\n/* ... existing code here ... */\n"),
    ("C2a-05", "flag", "lazy", "src/a05.tsx", "{/* ... existing code ... */} (.tsx)",
     "export const A = () => (\n  <div>\n    {/* ... existing code ... */}\n  </div>\n)\n"),
    ("C2a-06", "flag", "lazy", "res/layout/a06.xml", "<!-- ... existing code ... --> (.xml)", "<a>\n<!-- ... existing code ... -->\n</a>\n"),
    ("C2a-07", "flag", "lazy", "web/a07.html", "<!-- ... existing code ... --> (.html)", "<div>\n<!-- ... existing code ... -->\n</div>\n"),
    ("C2a-08", "flag", "lazy", "src/a08.kt", "// … existing code … (Unicode ellipsis)", "fun ok() = 1\n// " + EL + " existing code " + EL + "\n"),
    ("C2a-09", "flag", "lazy", "src/a09.java", "// ... (existing code) ...", "class A {\n    // ... (existing code) ...\n}\n"),
    ("C2a-10", "flag", "lazy", "src/a10.go", "// rest of implementation unchanged", "package a\n\n// rest of implementation unchanged\n"),
    ("C2a-11", "flag", "lazy", "src/a11.py", "# ... rest of the code ...", "def f():\n    # ... rest of the code ...\n    return 1\n"),
    ("C2a-12", "flag", "lazy", "src/a12.py", "pass  # placeholder", "def f():\n    pass  # placeholder\n"),
    # ── C2b: file kinds and scripts/ ──
    ("C2b-01", "flag", "lazy", "tools/run.sh", "tools/run.sh", "#!/bin/sh\n" + LINE_HASH + "echo ok\n"),
    ("C2b-02", "flag", "lazy", "build.gradle.kts", "build.gradle.kts", "plugins {}\n" + LINE_SLASH),
    ("C2b-03", "flag", "lazy", "app/build.gradle", "app/build.gradle", "android {}\n" + LINE_SLASH),
    ("C2b-04", "flag", "lazy", "a.mjs", "a.mjs", "export const a = 1\n" + LINE_SLASH),
    ("C2b-05", "flag", "lazy", "lib/x.rb", "lib/x.rb", "def f\n  " + LINE_HASH + "end\n"),
    ("C2b-06", "flag", "lazy", "scripts/deploy.py", "scripts/deploy.py (scripts/ dir)", "def f():\n    " + LINE_HASH + "    return 1\n"),
    ("C2b-07", "flag", "lazy", "ci.yml", "ci.yml", "jobs:\n  " + LINE_HASH + "  build: {}\n"),
    # ── C2c: must pass ──
    ("C2c-01", "pass", "lazy", "src/spread.js", "JS rest element named in a comment",
     "export function f(props) {\n  const {a, ...remaining} = props; // ...remaining holds the others\n  return [a, remaining]\n}\n"),
    ("C2c-02", "pass", "lazy", "app/src/test/kotlin/GateTest.kt", "Kotlin string literal in a test file",
     "class GateTest {\n    val sample = \"// ... existing code ...\"\n}\n"),
    ("C2c-03", "pass", "lazy", "docs/placeholders.md", ".md describing placeholders",
     "# Placeholders\n\nNever leave `// ... existing code ...` or `# ... existing code ...` in a diff.\n"),
    ("C2c-04", "pass", "lazy", "src/sorted.kt", "// the rest of the list is sorted", "fun ok() = 1\n// the rest of the list is sorted\n"),
    ("C2c-05", "pass", "lazy", "src/migrate.py", "# existing users are migrated", "def f():\n    # existing users are migrated\n    return 1\n"),
    # ── C3b: env file names ──
    ("C3b-01", "flag", "name", ".env.production.local", ".env.production.local", "API_KEY=@F@\n"),
    ("C3b-02", "flag", "name", ".env.prod.local", ".env.prod.local", "API_KEY=@F@\n"),
    ("C3b-03", "flag", "name", ".env.backup", ".env.backup", "API_KEY=@F@\n"),
    ("C3b-04", "pass", "name", ".env.example", ".env.example (template)", "API_KEY=your-api-key-here\n"),
    # ── C3c: secret shapes ──
    ("C3c-01", "flag", "content", "tools/c1.sh", "export API_KEY=<32 chars> (.sh)", "#!/bin/sh\nexport API_KEY=@F32@\n"),
    ("C3c-02", "flag", "content", "src/c2.py", "os.environ[\"API_KEY\"] = \"<fake>\"", 'import os\nos.environ["API_KEY"] = "@F@"\n'),
    ("C3c-03", "flag", "content", "res/values/c3.xml", "<string name=\"api_key\"><fake></string>",
     '<resources>\n    <string name="api_key">@F@</string>\n</resources>\n'),
    ("C3c-04", "flag", "content", "app/c4.gradle.kts", "buildConfigField(\"String\", \"API_KEY\", …)",
     'android {\n    defaultConfig {\n        buildConfigField("String", "API_KEY", "\\"@F@\\"")\n    }\n}\n'),
    ("C3c-05", "flag", "content", "src/c5.ts", "\"Authorization\": \"Bearer <40 chars>\"",
     'export const headers = {"Authorization": "Bearer @F40@"}\n'),
    ("C3c-06", "flag", "content", "src/c6.py", "DB_PASS = \"<fake>\"", 'DB_PASS = "@F@"\n'),
    ("C3c-07", "pass", "content", "tools/p1.sh", "export API_KEY=\"$API_KEY\"", '#!/bin/sh\nexport API_KEY="$API_KEY"\n'),
    ("C3c-08", "pass", "content", "src/p2.py", "os.environ[\"API_KEY\"] = os.getenv(\"X\")", 'import os\nos.environ["API_KEY"] = os.getenv("X")\n'),
    ("C3c-09", "pass", "content", "tools/p3.sh", "API_KEY=${API_KEY}", "#!/bin/sh\nAPI_KEY=${API_KEY}\n"),
    ("C3c-10", "pass", "content", "src/p4.ts", "\"Authorization\": \"Bearer \" + token",
     'export const headers = (token: string) => ({"Authorization": "Bearer " + token})\n'),
    ("C3c-11", "pass", "content", "res/values/p5.xml", "<string name=\"api_key\">@string/placeholder</string>",
     '<resources>\n    <string name="api_key">@string/placeholder</string>\n</resources>\n'),
    ("C3c-12", "pass", "content", "src/p6.py", "DB_PASS = \"changeme\"", 'DB_PASS = "changeme"\n'),
    # ── v2 (Antigravity T0479): placeholders in test files count; a pattern inside a string literal or a heredoc body does not ──
    ("C2t-01", "flag", "lazy", "tests/test_app.py", "full-line # ... existing code ... in tests/test_app.py",
     "def test_a():\n    " + LINE_HASH + "    assert True\n"),
    ("C2t-02", "flag", "lazy", "src/test/java/FooTest.kt", "full-line // ... existing code ... in src/test/java/FooTest.kt",
     "class FooTest {\n    " + LINE_SLASH + "}\n"),
    ("C2t-03", "pass", "lazy", "tests/test_payload.py", "pattern inside a quoted literal (python test)",
     "SAMPLE = \"# ... existing code ...\"\nOTHER = '# ... existing code ...'\n"),
    ("C2t-04", "pass", "lazy", "web/gen.test.js", "pattern inside backticks / single quotes (js test)",
     "const s = `// ... existing code ...`\nconst t = '// ... existing code ...'\n"),
    ("C2t-05", "pass", "lazy", "tests/test_fixture.sh", "pattern inside a heredoc body and a printf literal (.sh test)",
     "#!/bin/sh\ncat > out.py <<'EOF'\ndef g():\n    " + LINE_HASH + "    return 2\nEOF\n"
     "printf 'def h():\\n    # ... existing code ...\\n' > out2.py\n"),
    ("C2t-06", "flag", "lazy", "src/payload.py", "parent-reported wording inside a quoted literal of a code file the parent scan read",
     "SAMPLE = \"// ... existing code ...\"\n"),
    # ── v2: a secret as the fallback value ──
    ("C3f-01", "flag", "content", "src/d1.py", "os.environ.get(\"API_SECRET\", \"<fake>\")", 'import os\nS = os.environ.get("API_SECRET", "@F@")\n'),
    ("C3f-02", "flag", "content", "src/d2.py", "os.getenv(\"API_KEY\", \"<fake>\")", 'import os\nK = os.getenv("API_KEY", "@F@")\n'),
    ("C3f-03", "flag", "content", "src/d3.ts", "process.env.OPENAI_API_KEY || \"sk-<fake>\"", 'const k = process.env.OPENAI_API_KEY || "sk-@F@"\n'),
    ("C3f-04", "flag", "content", "src/d4.ts", "process.env.OPENAI_API_KEY ?? \"<fake>\"", 'const k = process.env.OPENAI_API_KEY ?? "@F@"\n'),
    ("C3f-05", "flag", "content", "src/d5.ts", "{ ...defaults, apiKey: \"<fake>\" }", 'const cfg = { ...defaults, apiKey: "@F@" }\n'),
    ("C3f-06", "flag", "content", "tools/d6.sh", "curl -H \"Authorization: Bearer ghp_<fake>\"",
     '#!/bin/sh\ncurl -H "Authorization: Bearer ghp_@F@" "$API_URL"\n'),
    ("C3f-07", "pass", "content", "src/e1.py", "os.environ.get(\"API_KEY\", \"\")", 'import os\nK = os.environ.get("API_KEY", "")\n'),
    ("C3f-08", "pass", "content", "src/e2.py", "os.getenv(\"API_KEY\", \"changeme\")", 'import os\nK = os.getenv("API_KEY", "changeme")\n'),
    ("C3f-09", "pass", "content", "src/e3.ts", "process.env.KEY || \"\"", 'const k = process.env.KEY || ""\n'),
    ("C3f-10", "pass", "content", "src/e4.ts", "process.env.KEY || \"your-api-key-here\"", 'const k = process.env.KEY || "your-api-key-here"\n'),
    # ── a fixture value in plain words passes (PLACEHOLDER_VALUE: fake-/forged-/mock- + letters); with digits it is a value ──
    ("C3p-01", "pass", "content", "tools/f1.sh", "export GH_TOKEN=fake-token", "#!/bin/sh\nexport GH_TOKEN=fake-token\n"),
    ("C3p-02", "flag", "content", "tools/f2.sh", "export GH_TOKEN=fake-<digits and letters>", "#!/bin/sh\nexport GH_TOKEN=@FK@\n"),
    ("C3p-03", "flag", "content", "src/f3.py", "API_KEY = \"fake-<digits and letters>\"", 'API_KEY = "@FK@"\n'),
    ("C3p-04", "pass", "content", "app/f4.gradle.kts", "buildConfigField(… \"System.getenv(\\\"API_KEY\\\")\")",
     'android {\n    defaultConfig {\n        buildConfigField("String", "API_KEY", "System.getenv(\\"API_KEY\\")")\n    }\n}\n'),
    # ── round 3: nothing HEAD reported may pass, outside the approved false blocks ──
    ("C2k-01", "flag", "lazy", "src/k01.ts", "// ...rest at the end of the line", "export const a = 1\n// ...rest\n"),
    ("C2k-02", "flag", "lazy", "src/k02.ts", "// ... rest (spaced, no noun)", "export const a = 1\n// ... rest\n"),
    ("C2k-03", "flag", "lazy", "src/k03.py", "# ... existing (no noun)", "def f():\n    # ... existing\n    return 1\n"),
    ("C2k-04", "flag", "lazy", "src/k04.js", "// ...remaining at the end of the line, next to a spread",
     "export function f(props) {\n  const {a, ...remaining} = props; // ...remaining\n  return a\n}\n"),
    ("C2k-05", "flag", "lazy", "src/k05.js", "// ... remaining holds (a space after the dots), next to a spread",
     "export function f(props) {\n  const {a, ...remaining} = props; // ... remaining holds the others\n  return a\n}\n"),
    ("C2k-06", "flag", "lazy", "src/k06.js", "// ...remaining holds the others with no spread in the code",
     "export function f(props) {\n  // ...remaining holds the others\n  return props\n}\n"),
    ("C2k-07", "flag", "lazy", "tools/gen.sh", "heredoc body of a production .sh",
     "#!/bin/sh\ncat > out.py <<'EOF'\ndef g():\n    " + LINE_HASH + "    return 2\nEOF\n"),
    ("C3p-05", "flag", "content", "src/f5.py", "API_KEY = \"fake-token\" (the quoted rule keeps HEAD's answer)", 'API_KEY = "@FT@"\n'),
    ("C3p-06", "pass", "content", "src/f6.py", "os.environ[\"GH_TOKEN\"] = \"fake-token\" (new shape, fixture value)",
     'import os\nos.environ["GH_TOKEN"] = "@FT@"\n'),
    # ── round 4: the remaining variants of the reviewers' lists, closed by meaning group; each group has ordinary comments that pass ──
]
KT = "class V {\n    fun a(): Int {\n        %s\n        return 1\n    }\n}\n"
PYB = "def v():\n    %s\n    return 1\n"
def group(prefix, want, kind, rows):
    for n, (path, title, body) in enumerate(rows, 1):
        CASES.append(("%s-%02d" % (prefix, n), want, kind, path, title, body))
# a. "code left out" wordings, English and Vietnamese
group("C2e", "flag", "lazy", [
    ("src/e01.kt", "// ... code omitted for brevity ...", KT % "// ... code omitted for brevity ..."),
    ("src/e02.ts", "// your code here", KT % "// your code here"),
    ("src/e03.kt", "// ... same as before ...", KT % "// ... same as before ..."),
    ("src/e04.kt", "// (unchanged)", KT % "// (unchanged)"),
    ("src/e05.kt", "// existing code", KT % "// existing code"),
    ("src/e06.py", "# existing code here", PYB % "# existing code here"),
    ("src/e07.kt", "// .. existing code .. (two dots)", KT % "// .. existing code .."),
    ("src/e08.kt", "// ... previous code ...", KT % "// ... previous code ..."),
    ("src/e09.kt", "// implementation omitted", KT % "// implementation omitted"),
    ("src/e10.kt", "// ... other methods unchanged ...", KT % "// ... other methods unchanged ..."),
    ("src/e11.kt", "// ... keep existing code ...", KT % "// ... keep existing code ..."),
    ("src/e12.ts", "// ... the rest ...", KT % "// ... the rest ..."),
    ("src/e13.ts", "// ... more code here ...", KT % "// ... more code here ..."),
    ("src/e14.ts", "// add implementation here", KT % "// add implementation here"),
    ("src/e15.kt", "// [existing code]", KT % "// [existing code]"),
    ("src/e16.kt", "// ... phần còn lại giữ nguyên ...", KT % "// ... phần còn lại giữ nguyên ..."),
    ("src/e17.kt", "// ... code cũ ...", KT % "// ... code cũ ..."),
    ("src/e18.kt", "// giữ nguyên phần còn lại", KT % "// giữ nguyên phần còn lại"),
    ("src/e19.py", "# ... (phần còn lại không đổi)", PYB % "# ... (phần còn lại không đổi)"),
    ("src/e20.py", "...  # rest of the function", PYB % "...  # rest of the function"),
    ("src/e21.kt", "// previous implementation unchanged", KT % "// previous implementation unchanged"),
    ("src/e22.kt", "// code goes here", KT % "// code goes here"),
])
group("C2f", "pass", "lazy", [
    ("src/g01.kt", "// the existing code path is unchanged by this fix", KT % "// the existing code path is unchanged by this fix"),
    ("src/g02.kt", "// same as before the migration: ids stay stable", KT % "// same as before the migration: ids stay stable"),
    ("src/g03.py", "# keeps the previous value when the key is missing", PYB % "# keeps the previous value when the key is missing"),
    ("src/g04.kt", "// giữ nguyên thứ tự phần tử khi sắp xếp", KT % "// giữ nguyên thứ tự phần tử khi sắp xếp"),
    ("src/g05.py", "# omitted fields default to null", PYB % "# omitted fields default to null"),
    ("src/g06.ts", "// your account id goes in the header", KT % "// your account id goes in the header"),
    ("src/g07.py", "x: tuple[int, ...] = (1,)  # ... is typing syntax", PYB % "x: tuple[int, ...] = (1,)  # ... is typing syntax"),
    ("src/g08.kt", "// phần còn lại của danh sách được sắp xếp", KT % "// phần còn lại của danh sách được sắp xếp"),
])
# b. doc blocks
group("C2g", "flag", "lazy", [
    ("src/h01.kt", "/** ... existing code ... */", KT % "/** ... existing code ... */"),
    ("src/h02.kt", "a ' * ... existing code ...' line of a block comment", KT % "/*\n         * ... existing code ...\n         */"),
    ("src/h03.py", "a docstring that is only '... existing code ...'", PYB % '"""... existing code ..."""'),
])
group("C2h", "pass", "lazy", [
    ("src/i01.kt", "/** Returns the remaining retries. */", KT % "/** Returns the remaining retries. */"),
    ("src/i02.kt", " * @param rest the remaining arguments", KT % "/**\n         * @param rest the remaining arguments\n         */"),
])
# c. stubs
group("C2i", "flag", "lazy", [
    ("src/j01.kt", "TODO() (Kotlin)", KT % "TODO()"),
    ("src/j02.kt", "TODO(\"Not yet implemented\")", KT % 'TODO("Not yet implemented")'),
    ("src/j03.rs", "todo!()", "fn a() -> i32 {\n    todo!()\n}\n"),
    ("src/j04.rs", "unimplemented!()", "fn a() -> i32 {\n    unimplemented!()\n}\n"),
    ("src/j05.py", "# TODO: implement (nothing after)", PYB % "# TODO: implement"),
    ("src/j06.kt", "// TODO: Implement remaining cases", KT % "// TODO: Implement remaining cases"),
    ("src/j07.kt", "// FIXME: implement rest", KT % "// FIXME: implement rest"),
    ("src/j08.kt", "// TODO: implement this later", KT % "// TODO: implement this later"),
])
group("C2j", "pass", "lazy", [
    ("src/l01.py", "raise NotImplementedError (abstract method)", "class Base:\n    def run(self):\n        raise NotImplementedError\n"),
    ("src/l02.py", "# TODO: implement retry with backoff for 429", PYB % "# TODO: implement retry with backoff for 429"),
    ("src/l03.kt", "// TODO(#123): handle the tablet layout", KT % "// TODO(#123): handle the tablet layout"),
    ("app/src/test/kotlin/StubTest.kt", "TODO() in a test path", KT % "TODO()"),
])
# d. every changed text file but documents / data
group("C2l", "flag", "lazy", [
    ("web/m01.css", "/* ... existing styles ... */ (.css)", "a { color: red }\n/* ... existing styles ... */\n"),
    ("src/m02.lua", "-- ... existing code ... (.lua)", "local a = 1\n-- ... existing code ...\n"),
    ("Dockerfile", "# ... existing code ... (Dockerfile)", "FROM scratch\n" + LINE_HASH),
    ("Makefile", "# ... existing code ... (Makefile)", "all:\n\ttrue\n" + LINE_HASH),
    ("infra/main.tf", "# ... existing code ... (.tf)", 'resource "x" "y" {}\n' + LINE_HASH),
    ("api/a.proto", "// ... existing code ... (.proto)", 'syntax = "proto3";\n' + LINE_SLASH),
])
group("C2m", "pass", "lazy", [
    ("docs/notes.txt", ".txt naming the pattern", "Never leave\n" + LINE_SLASH),
    ("data/sample.json", ".json holding the pattern", '{"comment": 1}\n' + LINE_SLASH),
    ("docs/guide.rst", ".rst naming the pattern", "Guide\n=====\n\n" + LINE_HASH),
])
# e. more key names (new shapes only), backtick values
group("C3g", "flag", "content", [
    ("src/q01.py", "PASSPHRASE = \"<fake>\"", 'PASSPHRASE = "@F@"\n'),
    ("src/q02.py", "credential = \"<fake>\"", 'credential = "@F@"\n'),
    ("src/q03.ts", "{ apiKey: `<fake>` } (backticks)", "const cfg = { apiKey: `@F@` };\n"),
    ("src/q04.py", "SIGNING_KEY = \"<fake>\"", 'SIGNING_KEY = "@F@"\n'),
    ("src/q05.py", "{\"access_key\": \"<fake>\"}", 'CFG = {"access_key": "@F@"}\n'),
    ("src/q06.py", "WEBHOOK_URL = \"https://…/<32 chars>\"", 'WEBHOOK_URL = "https://ci.internal.test/hook/@F32@"\n'),
])
group("C3h", "pass", "content", [
    ("src/r01.ts", "credentials: \"same-origin\" (fetch option)", 'fetch(url, { credentials: "same-origin" })\n'),
    ("src/r02.py", "PASSPHRASE = os.environ[\"PASSPHRASE\"]", 'import os\nPASSPHRASE = os.environ["PASSPHRASE"]\n'),
    ("src/r03.py", "WEBHOOK_URL = an ordinary endpoint", 'WEBHOOK_URL = "https://app.internal.test/webhooks/stripe"\n'),
    ("src/r04.ts", "apiKey: `${process.env.API_KEY}`", "const cfg = { apiKey: `${process.env.API_KEY}` };\n"),
    ("src/r05.py", "GOOGLE_APPLICATION_CREDENTIALS = a path", 'GOOGLE_APPLICATION_CREDENTIALS = "/etc/app/creds.json"\n'),
])
# f. values recognisable by their form
group("C3i", "flag", "content", [
    ("src/s01.py", "Slack webhook URL", 'SLACK = "@SLACK@"\n'),
    ("src/s02.py", "Telegram bot token", 'TELEGRAM = "@TG@"\n'),
    ("src/s03.py", "auth = (\"admin\", \"<fake>\")", 'auth = ("admin", "@F@")\n'),
    ("src/s04.ts", "auth: [\"admin\", \"<fake>\"]", 'const c = { auth: ["admin", "@F@"] }\n'),
])
group("C3j", "pass", "content", [
    ("src/t01.py", "auth = (\"admin\", os.environ[\"PW\"])", 'import os\nauth = ("admin", os.environ["PW"])\n'),
    ("src/t02.ts", "auth: [\"jwt\", \"session-cookie\"] (a list of schemes)", 'const c = { auth: ["jwt", "session-cookie"] }\n'),
    ("src/t03.py", "auth = (\"user\", \"password\")", 'auth = ("user", "password")\n'),
    ("src/t04.py", "a Slack URL without the secret part", 'DOC = "https://hooks.slack.com/services"\n'),
])
# g. file names
group("C3k", "flag", "name", [
    ("secrets.json", "secrets.json", '{"a": 1}\n'),
    ("config/secrets.yaml", "config/secrets.yaml", "a: 1\n"),
    (".netrc", ".netrc", "machine x login y\n"),
    (".git-credentials", ".git-credentials", "x\n"),
    (".pypirc", ".pypirc", "[pypi]\n"),
    (".dockercfg", ".dockercfg", "{}\n"),
])
group("C3l", "pass", "name", [
    ("secrets.json.example", "secrets.json.example (template)", '{"a": 1}\n'),
    ("src/secrets_manager.py", "src/secrets_manager.py", "def get(name):\n    return name\n"),
])
# R5-A1: the rest-element pass is a same-line rule
JSF = "export function f(p) {\n%s\n  return p\n}\n"
group("C2r", "flag", "lazy", [
    ("src/Card.tsx", "// ...rest of the component unchanged on its own line, the file spreads ...rest",
     "export function Card({title, ...rest}) {\n  // ...rest of the component unchanged\n  return <div {...rest}>{title}</div>\n}\n"),
    ("src/Card2.tsx", "// ...rest of the code on its own line, the file spreads ...rest",
     "export function Card({title, ...rest}) {\n  // ...rest of the code\n  return null\n}\n"),
    ("src/r03.js", "same line, but the code spreads another identifier", JSF % "  const {a, ...other} = p; // ...rest of the code unchanged"),
    ("src/r04.js", "the spread is itself inside a comment", JSF % "  // {a, ...rest} // ...rest of the code unchanged"),
    ("src/r05.js", "the spread is on the previous line", JSF % "  const {a, ...rest} = p;\n  // ...rest of the code unchanged"),
    ("src/r06.js", "the spread is inside a string of that line", JSF % "  const s = \"{a, ...rest}\"; // ...rest of the code unchanged"),
    ("src/r07.ts", "parent-reported wording in backticks (code file the parent scan read)", "export const s = `// ... existing code ...`\n"),
])
group("C2s", "pass", "lazy", [
    ("src/w01.js", "array rest element named on its line", JSF % "  const [head, ...rest] = p; // ...rest holds the tail"),
    ("src/w02.ts", "parameter rest element named on its line", "export function g(a: number, ...remaining: number[]) { // ...remaining is summed below\n  return a\n}\n"),
    ("src/w03.py", "a wording the parent never reported, inside a quoted literal", "HINT = \"# your code here\"\n"),
    ("lib/w04.rb", "quoted literal in a file kind the parent never read", "SAMPLE = \"# ... existing code ...\"\n"),
])
# R5-A2: an empty value is not the next line
group("C3n", "pass", "content", [
    (".env.example", "API_KEY= (empty) then PORT=3000", "API_KEY=\nPORT=3000\n"),
    ("conf/empty.properties", "api_key= (empty) then server.port=8080", "api_key=\nserver.port=8080\n"),
    ("conf/empty.yml", "password: (empty) then a nested key", "db:\n  password:\n  poolSizeMax:\n"),
])
group("C3o", "flag", "content", [
    ("conf/real.properties", "API_KEY=<32 chars> in a .properties", "API_KEY=@F32@\n"),
    ("conf/real.yml", "api_key: <32 chars> in a .yml", "svc:\n  api_key: @F32@\n"),
    ("conf/real.ini", "password = <32 chars> in a .ini (spaces around =)", "[db]\npassword = @F32@\n"),
])
# R5-A3: `secret` before `key`
group("C3q", "flag", "content", [
    ("src/u01.py", "SECRET_KEY = '<30 chars>'", "SECRET_KEY = '@F30@'\n"),
    ("src/u02.ts", "export const secretKey = \"<fake>\"", 'export const secretKey = "@F@"\n'),
    ("src/u03.kt", "const val JWT_SECRET_KEY = \"<fake>\"", 'const val JWT_SECRET_KEY = "@F@"\n'),
    ("src/u04.py", "DJANGO_SECRET_KEY = \"<fake>\"", 'DJANGO_SECRET_KEY = "@F@"\n'),
    ("src/u05.py", "client_secret_key = \"<fake>\"", 'client_secret_key = "@F@"\n'),
    ("conf/u06.yml", "secret_key: <32 chars> in a .yml", "app:\n  secret_key: @F32@\n"),
])
group("C3r", "pass", "content", [
    ("src/v01.py", "SECRET_KEY = os.environ[\"SECRET_KEY\"]", 'import os\nSECRET_KEY = os.environ["SECRET_KEY"]\n'),
    ("src/v02.ts", "secretKey = config.secretKey", "export const secretKey = config.secretKey\n"),
    ("src/v03.py", "SECRET_KEY = \"changeme\"", 'SECRET_KEY = "changeme"\n'),
    ("src/v04.py", "secret_key_name = \"primary\"", 'secret_key_name = "primary"\n'),
    ("src/v05.py", "secret_key_name = \"<fake>\" (the name of a key, not a key)", 'secret_key_name = "@F@"\n'),
])
rows = []
for cid, want, kind, path, title, body in CASES:
    body = body.replace("@F32@", F32).replace("@F30@", F32[:30]).replace("@F40@", F40).replace("@FK@", "fake-" + F).replace("@FT@", "fake-" + "token")
    body = body.replace("@SLACK@", "https://hooks.slack.com/" + "services/T00000000/B00000000/" + F32[:24])
    body = body.replace("@TG@", "1234567890" + ":AA" + F40[:33]).replace("@F@", F)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(body)
    rows.append("\t".join((cid, want, kind, path, title)))
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write("\n".join(rows) + "\n")
PY
git add -A   # "added to the diff": the env files are staged, like `git add .`

OUT="$(CLAUDE_PROJECT_DIR="$PWD" POSTFIX_GATE_FORCE_FULL=1 python3 "$GATE" --matrix "$PWD/matrix.json" --lang en --json --dry-run 2>&1)"
RC=$?
printf '%s\n' "$OUT" | grep '^{' | tail -1 > "$TMP/summary.json"

python3 - "$TMP/cases.tsv" "$TMP/summary.json" "$RC" <<'PY'
import json, sys
cases, summary, rc = sys.argv[1:4]
try:
    with open(summary, encoding="utf-8") as fh:
        d = json.load(fh)
except (OSError, ValueError) as e:
    print(f"✖ the gate printed no JSON summary (exit {rc}): {e}")
    print("❌ test_gate_placeholder_secret_zero_defect: no summary"); sys.exit(1)
audited = set(d.get("files") or [])
hits = {"lazy": set(), "name": set(), "content": set()}
for f in d.get("findings") or []:
    if f.get("category") == "lazy":
        hits["lazy"].add(f.get("file"))
    elif f.get("category") == "secrets":
        hits["name" if f.get("line") is None else "content"].add(f.get("file"))
what = {"lazy": "placeholder", "name": "forbidden file", "content": "secret"}
fails = total = 0
with open(cases, encoding="utf-8") as fh:
    for row in fh.read().splitlines():
        cid, want, kind, path, title = row.split("\t")
        total += 1
        flagged = path in hits[kind]
        if path not in audited:
            fails += 1; print(f"✖ {cid}: {path} is not in the audited files ({title})")
        elif flagged == (want == "flag"):
            print(f"✔ {cid}: {title} — " + (f"reported as a {what[kind]}" if flagged else f"no {what[kind]} finding"))
        else:
            fails += 1
            print(f"✖ {cid}: {title} — " + (f"NOT reported as a {what[kind]} (fail-open)" if want == "flag"
                                             else f"reported as a {what[kind]} (false block)") + f" [{path}]")
if fails:
    print(f"❌ test_gate_placeholder_secret_zero_defect: {fails}/{total} failed (gate exit {rc})"); sys.exit(1)
print(f"✅ test_gate_placeholder_secret_zero_defect: all {total} cases passed")
PY
