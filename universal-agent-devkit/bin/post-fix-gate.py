#!/usr/bin/env python3
"""
Post-Fix Audit & Regression Verification Gate CLI Tool
Universal Agent DevKit — Automated Quality & TIA Regression Shield

Audits the working-tree changes after a bug fix:
  - Static checks: secrets, lazy placeholders, dependencies (floating versions,
    http:// sources), perf, swallowed errors, raw logging
  - TIA: maps changed files to regression tests from regression_matrix.json and,
    with --run-tests, executes them and records the real exit code and duration
  - Impacted selection: a matrix test with "impacted_command" runs only the tests the
    change can reach ({gradle_tests}, {gradle_module_tests:<task>}, {unity_filter},
    {pytest_nodes}, {jest_paths}); anything the map cannot vouch for runs the full
    command. `--run-tests` alone (the Stop hook) uses selection and reports
    "PASS (impacted: N tests)"; `--full`, POSTFIX_GATE_FULL=1, CI=true and
    --record-lesson run every command in full — the run required before handover.
  - "covered_by": "<suite id>" on a matrix test: not run when that suite ran its FULL command earlier
    in the same run and passed (shown PASS, label COVERED); any other state runs it as before.
    `--staged` (pre-commit) runs no test at all.
  - Reports only what was actually checked. RED/GREEN oracle receipts, immutable
    guards and OpenCodeReview are listed as "not verified here".

Only the 6 static checks and the regression run (--run-tests) decide the verdict; the
other sections are reminders. Regression commands are read from the base ref, so the
audited change cannot rewrite them. One exception: a change that only ADDS rules to the
matrix (every base rule unchanged, new test ids, no covered_by) runs its own matrix, and
is trusted only when every added test passes in that same run.

--staged (the git pre-commit hook): the 6 static checks only, on the STAGED content —
no regression run, device probe or report. A clean result is exit 2 (tests not run),
never PASS.

Exit codes: 0 PASS, 1 REJECT, 2 UNVERIFIED (tests not run, matrix untrusted, existing
test or suite runner script edited, unreadable file, no coverage, bad --diff, no git on PATH), 3 nothing to audit,
4 UNTESTED (everything else passed, but a test exited with its matrix `untested_exit`
code: it cannot run on this machine — e.g. no Unity Editor), 5 NOT ACCEPTED (`--full` was
asked for but deferred because another session is live: the impacted checks passed, no
receipt written, the last full one left as it is — re-run in the last session or add
--force-full).

100% Standard Library — Zero external dependencies.
"""

import argparse
import calendar
import contextlib
import fnmatch
import hashlib
import json
import math
import os
import re
import shlex
import shutil
import signal
import stat
import statistics
import subprocess
import tempfile
import sys
import threading
import time
from pathlib import Path

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))
for _sub in ("audits", "context", "git", "governance", "linters", "testing"):
    _sub_path = str(_scripts_dir / _sub)
    if _sub_path not in sys.path:
        sys.path.insert(0, _sub_path)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from devkit_i18n import resolve_lang, set_lang, tr  # noqa: E402
from instincts import append_lesson, md_escape  # noqa: E402
# Who edited an existing test: the rule hooks/testsourceset_gate.sh scopes its compile with.
import session_authorship  # noqa: E402


def _L(label):
    """Finding labels are (vi, en) pairs; render them in the active language."""
    return tr(*label) if isinstance(label, tuple) else label

# Machine-readable copy of every static finding, emitted under "findings" by --json, so
# an agent can go straight to file:line instead of parsing the colored log. Each entry:
# category, rule (stable slug of the English label), message, file, line (1-based, or
# None when the check has no position), snippet (the offending line; never for secrets).
FINDINGS = []

def _record(category, rel_file, label, content=None, pos=None, snippet=True):
    en = label[1] if isinstance(label, tuple) else str(label)
    line = text = None
    if content is not None and pos is not None:
        line = content.count("\n", 0, pos) + 1
        start = content.rfind("\n", 0, pos) + 1
        end = content.find("\n", pos)
        text = content[start:end if end != -1 else len(content)].strip()[:200]
    FINDINGS.append({
        "category": category,
        "rule": re.sub(r"[^a-z0-9]+", "-", en.lower()).strip("-")[:60],
        "message": _L(label),
        "file": rel_file,
        "line": line,
        "snippet": text if snippet else None,
    })

# Fix Unicode on Windows consoles if needed
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
CYAN = "\033[96m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"


def unity_suite_compiles(command: str) -> bool:
    """EditMode/PlayMode already compiles the scripts, so a separate compile step is redundant."""
    low = (command or "").lower()
    return "editmode" in low or "playmode" in low


def skip_separate_unity_compile(command: str, unity_will_test: bool) -> bool:
    """Skip a compile-only suite when this same run already has an edit/play suite.

    The command is compile-only when it contains "compile" and the tail after that
    word does not contain "test" (a test filter is not a separate compile).
    """
    cmd = (command or "").lower()
    if not unity_will_test or "compile" not in cmd:
        return False
    return "test" not in cmd.split("compile", 1)[-1]

# Key names whose assigned value is treated as a credential. A prefix is allowed
# (DB_PASSWORD, ghToken), a suffix is not (passwordHint, tokenType).
_SECRET_KEY = r"[\w.\-]*?(?:api[_\-]?key|apikey|access[_\-]?token|auth[_\-]?token|refresh[_\-]?token|token|client[_\-]?secret|secret|password|passwd|pwd|private[_\-]?key|keystore[_\-]?password|key[_\-]?password|signing[_\-]?key[_\-]?password|keystore[_\-]?base64)"

# (pattern, label, value-group or None). Values with a group are checked against
# PLACEHOLDER_VALUE so `password = ${DB_PASSWORD}` or `api_key = "changeme"` pass.
SECRET_PATTERNS = [
    (r"(?i)\b" + _SECRET_KEY + r"[\"']?\s*[:=]\s*[\"']([^\"'\s]{8,})[\"']", "Hardcoded API Key / Secret", 1),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----", "Private Key Block", None),
    (r"\b(AKIA|ASIA)[0-9A-Z]{16}\b", "AWS Access Key ID", None),
    (r"\bgh[pousr]_[A-Za-z0-9]{36,}\b", "GitHub Token", None),
    (r"\bgithub_pat_[A-Za-z0-9_]{22,}\b", "GitHub Fine-grained Token", None),
    (r"\bxox[abprs]-[A-Za-z0-9-]{10,}", "Slack Token", None),
    (r"\bAIza[0-9A-Za-z_\-]{35}\b", "Google API Key", None),
    (r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}", "JSON Web Token", None),
    # AI / cloud API tokens recognisable by their prefix alone — caught even when the
    # variable holding them has no "key"/"token" in its name.
    (r"\bsk-ant-(?:api|admin)\d{2}-[A-Za-z0-9_\-]{40,}", "Anthropic API key", None),
    (r"\bsk-(?:proj|svcacct|admin)-[A-Za-z0-9_\-]{40,}|\bsk-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}\b", "OpenAI API key", None),
    (r"\bhf_[A-Za-z0-9]{34,}\b", "Hugging Face token", None),
    (r"\b(?:sk|rk)_live_[A-Za-z0-9]{24,}\b", "Stripe live secret key", None),
    (r"\bglpat-[A-Za-z0-9_\-]{20,}", "GitLab personal access token", None),
    (r"\bnpm_[A-Za-z0-9]{36}\b", "npm access token", None),
    (r"\bSG\.[A-Za-z0-9_\-]{22}\.[A-Za-z0-9_\-]{43}\b", "SendGrid API key", None),
    (r"\bsbp_[A-Za-z0-9]{40,}\b", "Supabase access token", None),
    (r"\bgsk_[A-Za-z0-9]{50,}\b", "Groq API key", None),
    (r"\br8_[A-Za-z0-9]{37}\b", "Replicate API token", None),
    # Property lists (Info.plist, *.plist): <key>API_KEY</key><string>value</string>.
    # A build-setting reference ($(API_KEY)) is a placeholder, not a secret.
    (r"(?i)<key>[^<]*(?:api[_\-]?key|secret|token|password|passwd|private[_\-]?key)[^<]*</key>\s*<string>([^<\s]{8,})</string>",
     "Hardcoded secret in a property list", 1),
    # npm registry auth: //registry.npmjs.org/:_authToken=… (${NPM_TOKEN} is a placeholder)
    (r"(?m)^\s*//\S+:_(?:authToken|auth|password)\s*=\s*([^\s#]{8,})", "npm registry token (.npmrc)", 1),
    # Credentials inside a connection URL: postgres://user:PASSWORD@host
    (r"\b[a-z][a-z0-9+.\-]*://[^/\s:@\"'`]+:([^/\s@\"'`]{6,})@[\w.\-]", "Credentials in a connection URL", 1),
]

# Unquoted `key = value` only in config-style files, where it is the normal syntax
# (in code an unquoted right-hand side is an expression, not a literal).
CONFIG_SECRET_PATTERN = (r"(?im)^\s*(?:export\s+)?" + _SECRET_KEY + r"\s*[:=]\s*([^\s\"'#]{8,})\s*$",
                         "Hardcoded Secret (config file)", 1)
CONFIG_EXTENSIONS = (".properties", ".env", ".yml", ".yaml", ".ini", ".cfg", ".conf", ".toml")

PLACEHOLDER_VALUE = re.compile(
    r"(?i)^(\$.*|<.*>|\{\{.*|%.*|x{4,}|\*{4,}|your[_\-].*|change[_\-]?me|placeholder|redacted|example.*|dummy.*|none|null|true|false"
    r"|password|passwd|secret|test|testing)$")

# .env files: forbidden to commit, and scanned with the unquoted `KEY=value` rule too.
ENV_FILE_PATTERN = r"(^|/)(\.env(\.[a-zA-Z0-9_-]+)?|[\w.-]+\.env)$"

FORBIDDEN_SECRET_FILES = [
    (r"\.(keystore|jks|p12|pfx|mobileprovision)$", ("Chứng chỉ ký số trần (*.keystore, *.jks, *.p12, *.mobileprovision)", "Raw signing certificate (*.keystore, *.jks, *.p12, *.mobileprovision)")),
    (r"google-services\.json$", ("Tệp cấu hình Firebase/Google Services production (google-services.json)", "Production Firebase/Google Services config (google-services.json)")),
    (r"GoogleService-Info\.plist$", ("Tệp cấu hình Firebase iOS nhạy cảm (GoogleService-Info.plist)", "Sensitive Firebase iOS config (GoogleService-Info.plist)")),
    (r"\.(pem|key)$", ("Khóa mật mã riêng tư trần (*.pem, *.key)", "Raw private key (*.pem, *.key)")),
    (r"(^|/)id_(rsa|dsa|ecdsa|ed25519)$", ("Khoá SSH riêng tư (id_rsa, id_ed25519…)", "Private SSH key (id_rsa, id_ed25519…)")),
    (r"(^|/)(local|keystore)\.properties$", ("Cấu hình cục bộ Android (local.properties / keystore.properties — core-rules §1)",
                                             "Local Android config (local.properties / keystore.properties — core-rules §1)")),
    (ENV_FILE_PATTERN, ("Tệp cấu hình biến môi trường (.env, *.env)", "Environment variable file (.env, *.env)")),
]

# Only an exact template suffix exempts a file (`.env.example`); a directory named
# `sample/` or `templates/` does not.
SAFE_TEMPLATE_SUFFIXES = (".example", ".sample", ".template", ".dist")

LAZY_CODE_PATTERNS = [
    (r"(?i)//\s*\.\.\.\s*(existing|rest|remaining)", "Lazy placeholder (// ... existing code ...)"),
    (r"(?i)/\*\s*\.\.\.\s*(existing|rest|remaining)\s*\*/", "Lazy placeholder (/* ... existing code ... */)"),
    (r"(?i)#\s*\.\.\.\s*(existing|rest|remaining)", "Lazy placeholder (# ... existing code ...)"),
    (r"(?i)//\s*TODO:?\s*implement\s+rest", "Lazy TODO placeholder (// TODO: implement rest)")
]

UI_EXTENSIONS = {".kt", ".java", ".tsx", ".jsx", ".dart", ".vue", ".swift", ".xml"}
CODE_EXTENSIONS = UI_EXTENSIONS | {".py", ".ts", ".js", ".go", ".rs", ".cpp", ".c", ".h", ".cs", ".shader", ".hlsl"}

PERF_ANTIPATTERN_PATTERNS = [
    (r"(?i)\bThread\.sleep\(", ("Chặn luồng đồng bộ (Thread.sleep) trên UI/Main Thread", "Blocking call (Thread.sleep) on the UI/main thread")),
    (r"(?i)\brunBlocking\s*\{", ("Chặn luồng coroutine bằng runBlocking trên Main Thread", "runBlocking blocks the main thread")),
    (r"(?i)static\s+(var\s+|val\s+|[a-zA-Z0-9_<>]+)\s+(mContext|context|activity)\b", ("Rò rỉ bộ nhớ (Static Activity/Context Leak)", "Memory leak (static Activity/Context)")),
    (r"(?i)for\s*\([^)]*in[^)]*list[^)]*\)\s*\{\s*for\s*\([^)]*in[^)]*list[^)]*\)", ("Vòng lặp lồng O(N^2) trên mảng động (Cần dùng Map/Set lookup)", "Nested O(N^2) loop over lists (use a Map/Set lookup)")),
    (r"(?i)\.printStackTrace\(\)", ("In stack trace trực tiếp ra console (Gây nghẽn I/O)", "printStackTrace() to the console (blocking I/O)")),
    (r"(?i)\b(?:IOUtils\.toByteArray|\.readBytes)\s*\(", ("Đọc toàn bộ luồng vào byte[] không giới hạn (Gây tràn bộ nhớ OOM; cần stream/spool nếu > 1MB)", "Unbounded stream read to byte[] (causes heap OOM; stream or spool to temp file for > 1MB)"))
]

RESILIENCE_ANTIPATTERN_PATTERNS = [
    (r"(?s)catch(?:\s*\([^\)]*\))?\s*\{\s*\}", ("Khối catch rỗng nuốt lỗi âm thầm (Empty catch block)", "Empty catch block silently swallows errors")),
    (r"(?m)^\s*except(\s+[a-zA-Z0-9_]+)?:\s*pass\s*$", ("Khối except: pass nuốt lỗi âm thầm", "except: pass silently swallows errors")),
]

LOGGING_ANTIPATTERN_PATTERNS = [
    (r"(?i)\bconsole\.log\(", ("In log chuỗi trần ra console bằng console.log (Cần dùng Structured Logger)", "Raw console.log output (use a structured logger)")),
    (r"(?i)\bSystem\.out\.print(ln)?\(", ("In chuỗi thô ra console bằng System.out.println (Cần dùng Structured Logger)", "Raw System.out.println output (use a structured logger)"))
]

# Dependency manifests. Every rule is anchored to a declaration shape: a bare `+`,
# `*` or `http://` also appears in comments, license URLs and the project's own
# version field, which are not dependencies.
FLOATING_DEP = ("Version dependency thả nổi — build không tái lập được, ghim version cụ thể",
                "Floating dependency version — the build is not reproducible, pin an exact version")
INSECURE_DEP = ("Nguồn dependency qua kết nối không mã hoá (http:// / tắt TLS) — dùng https://",
                "Dependency source over an unencrypted connection (http:// / TLS off) — use https://")
_HTTP = r"http://(?!localhost\b|127\.0\.0\.1\b|\[::1\])[^\s\"'<>)]*"
_DYNAMIC = r"(?:\d[\w.\-]*)?\+|latest\.(?:release|integration|milestone)"
_GRADLE_REPO = r"\b(?:maven|ivy)\s*\{[^{}]*?\b(?:url|setUrl)\s*(?:=\s*|\(\s*)?(?:uri\s*\(\s*)?[\"']" + _HTTP
DEPENDENCY_RULES = {
    "gradle": [
        (r"[\"'][\w.\-]+:[\w.\-]+:(?:" + _DYNAMIC + r")(?:@\w+)?[\"']", FLOATING_DEP),
        (r"\b(?:version|prefer|require|strictly)\s*(?:=|:|\()\s*[\"'](?:" + _DYNAMIC + r")[\"']", FLOATING_DEP),
        (_GRADLE_REPO, INSECURE_DEP),
        (r"\bmaven\s*\(\s*(?:url\s*=\s*)?(?:uri\s*\(\s*)?[\"']" + _HTTP, INSECURE_DEP),
        (r"\b(?:isAllowInsecureProtocol|allowInsecureProtocol)\s*(?:=\s*|\(\s*)?true\b", INSECURE_DEP),
    ],
    "version-catalog": [
        (r"=\s*[\"'](?:" + _DYNAMIC + r")[\"']", FLOATING_DEP),
    ],
    "cargo": [
        (r"(?m)^\s*[\w.\-]+\s*=\s*[\"']\*[\"']", FLOATING_DEP),
        (r"\bversion\s*=\s*[\"']\*[\"']", FLOATING_DEP),
        (r"\b(?:git|registry|index|url)\s*=\s*[\"']" + _HTTP, INSECURE_DEP),
    ],
    "npmrc": [
        (r"(?m)^\s*(?:@[\w.\-]+:)?registry\s*=\s*" + _HTTP, INSECURE_DEP),
        (r"(?m)^\s*strict-ssl\s*=\s*false\b", INSECURE_DEP),
    ],
    "podfile": [
        (r"(?m)^\s*source\s+[\"']" + _HTTP, INSECURE_DEP),
        (r"(?::(?:git|http)\s*=>|\b(?:git|http):)\s*[\"']" + _HTTP, INSECURE_DEP),
    ],
    "pip": [
        (r"(?m)^\s*(?:-i|--index-url|--extra-index-url|-f|--find-links)(?:\s+|\s*=\s*)" + _HTTP, INSECURE_DEP),
        (r"(?m)^\s*--trusted-host\b", INSECURE_DEP),
        (r"@\s*(?:git\+)?" + _HTTP, INSECURE_DEP),
        (r"(?m)^\s*(?:git\+)?" + _HTTP, INSECURE_DEP),
    ],
    "pubspec": [
        (r"(?m)^\s+[\w\-]+\s*:\s*any\s*$", FLOATING_DEP),
        (r"(?m)^\s+url\s*:\s*[\"']?" + _HTTP, INSECURE_DEP),
    ],
    "swiftpm": [
        # `branch:` follows a moving branch head; `from:`/ranges are pinned by Package.resolved.
        (r"\.package\s*\([^)]*\bbranch\s*:\s*\"[^\"]*\"", FLOATING_DEP),
        (r"\.package\s*\([^)]*\burl\s*:\s*\"" + _HTTP, INSECURE_DEP),
    ],
    "maven-pom": [
        (r"<version>\s*(?:LATEST|RELEASE)\s*</version>", FLOATING_DEP),
        (r"<(repository|pluginRepository|snapshotRepository)>(?:(?!</\1>)[\s\S])*?<url>\s*" + _HTTP, INSECURE_DEP),
    ],
}
# npm "*" / "latest" in peerDependencies means "any host version" — normal, not floating.
NPM_PINNED_SECTIONS = ("dependencies", "devDependencies", "optionalDependencies")
NPM_ALL_SECTIONS = NPM_PINNED_SECTIONS + ("peerDependencies", "resolutions", "overrides")
NPM_FLOATING = {"latest", "*", "x", "X", ""}


def dependency_kind(rel_file: str):
    name = rel_file.replace("\\", "/").rsplit("/", 1)[-1]
    if name.endswith((".gradle", ".gradle.kts")):
        return "gradle"
    if name.endswith(".versions.toml"):
        return "version-catalog"
    if name in ("Cargo.toml", "pyproject.toml"):
        return "cargo"  # same `name = "*"` / `git = "http://…"` shapes (Poetry for pyproject)
    if name == "package.json":
        return "package.json"
    if name == ".npmrc":
        return "npmrc"
    if name == "Podfile":
        return "podfile"
    if name.startswith("requirements") and name.endswith(".txt"):
        return "pip"
    if name == "pubspec.yaml":
        return "pubspec"
    if name == "pom.xml":
        return "maven-pom"
    if name == "Package.swift":
        return "swiftpm"
    return None

TEST_DIR_NAMES = {"test", "tests", "__tests__", "androidtest", "unittest", "integrationtest",
                  "testfixtures", "spec", "specs", "mocks", "__mocks__"}
TEST_FILE_RE = re.compile(r"((Test|Tests|Spec)\.(kt|kts|java|swift|scala|groovy|cs|m|mm)$"
                          r"|(_test|_spec)\.\w+$|\.(test|spec)\.\w+$|^test_[^/]*\.py$)")


def is_test_path(rel_file: str) -> bool:
    """A test source is decided by a directory component or a file-name suffix —
    never by the substring "test" (which would skip src/latest/, contest/, …)."""
    parts = rel_file.replace("\\", "/").split("/")
    if any(p.lower() in TEST_DIR_NAMES for p in parts[:-1]):
        return True
    return bool(TEST_FILE_RE.search(parts[-1]))


# Added lines that switch a test off (JUnit/Kotest, NUnit, Go, pytest/unittest, Jest/Mocha, XCTest).
TEST_SKIP_RE = re.compile(r"@Ignore\b|@Disabled\b|\[Ignore\b|\bt\.Skip|\bpytest\.(?:mark\.)?skip|"
                          r"\bunittest\.skip|\b(?:it|test|describe)\.skip\b|\bx(?:it|describe|test)\s*\(|XCTSkip")


# Definitions an appended block can REDEFINE, shadowing the test of that name in the base version (A6, 2026-10-09: an
# appended `def test_sub(self): self.assertIsNotNone(sub)` replaced the real test_sub and passed as append-only).
_PY_TEST_DEF = re.compile(r"^[ \t]*(?:async[ \t]+)?def[ \t]+(test\w*)[ \t]*\(", re.M)   # when the file does not parse
_JVM_TEST_DEF = re.compile(r"@(?:Test|ParameterizedTest|RepeatedTest|TestFactory)\b(?:\([^)\n]*\))?\s*(?:@[\w.]+(?:\([^)\n]*\))?\s*)*"
                           r"(?:(?:public|private|protected|internal|open|override|suspend|final|static)\s+)*"
                           r"(?:fun|void)\s+(`[^`\n]+`|\w+)\s*\(")
_JS_TEST_DEF = re.compile(r"(?<![.\w$])(?:it|test)(?:\.only)?[ \t]*\([ \t]*(?:'([^'\n]*)'|\"([^\"\n]*)\"|`([^`\n]*)`)")
_SH_FUNC_DEF = re.compile(r"^[ \t]*(?:function[ \t]+([A-Za-z_][\w:.-]*)|([A-Za-z_][\w:.-]*)[ \t]*\(\))", re.M)
_DEF_RULES = ((".kt", ".kts", ".java", ".groovy", ".scala"), _JVM_TEST_DEF), \
             ((".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts"), _JS_TEST_DEF), \
             ((".sh", ".bash", ".zsh", ""), _SH_FUNC_DEF)


def _def_counts(rx, text: str) -> dict:
    out = {}
    for m in rx.finditer(text):
        name = next((g for g in m.groups() if g is not None), None)
        if name is not None:
            out[name] = out.get(name, 0) + 1
    return out


def _py_def_counts(text: str):
    """Test definitions per scope (module-level classes and test functions, Class.test_method), or None when the text
    does not parse. Scoped: a new class that reuses another class's method names shadows nothing."""
    import ast  # noqa: PLC0415
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError):
        return None
    out = {}
    for node in tree.body:
        names = []
        if isinstance(node, ast.ClassDef):
            names = [node.name] + [f"{node.name}.{s.name}" for s in node.body
                                   if isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)) and s.name.startswith("test")]
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test"):
            names = [node.name]
        for n in names:
            out[n] = out.get(n, 0) + 1
    return out


_JS_DESCRIBE = re.compile(r"(?<![.\w$])(?:describe|context|suite)(?:\.(?:only|skip))?[ \t]*\([ \t]*(?:'([^'\n]*)'|\"([^\"\n]*)\"|`([^`\n]*)`)")
_JS_CALLBACK_OPEN = re.compile(r"(?:=>|function[^{(]*\([^)]*\))\s*\{")


def _js_block_end(text: str, i: int):
    """Index just past the `}` that closes the `{` at text[i], skipping strings, template literals and comments; None when unbalanced."""
    depth, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in "'\"`":
            q = c
            i += 1
            while i < n and text[i] != q:
                i += 2 if text[i] == "\\" else 1
            i += 1
            continue
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return None


def _js_def_counts(text: str):
    """it/test titles counted per enclosing describe path (the same title in two describe blocks is two tests), or None when the
    describe blocks cannot be delimited (unbalanced braces, an unusual callback): the caller then counts the whole file."""
    scopes = []   # (start, end, title) of every describe callback body, in source order = outermost first
    for m in _JS_DESCRIBE.finditer(text):
        cb = _JS_CALLBACK_OPEN.search(text, m.end())
        if cb is None:
            return None
        end = _js_block_end(text, cb.end() - 1)
        if end is None:
            return None
        scopes.append((cb.end() - 1, end, next(g for g in m.groups() if g is not None)))
    out = {}
    for m in _JS_TEST_DEF.finditer(text):
        name = next((g for g in m.groups() if g is not None), None)
        if name is None:
            continue
        key = "/".join(t for b, e, t in scopes if b < m.start() < e) + "::" + name
        out[key] = out.get(key, 0) + 1
    return out


def redefines_test(repo_path: str, base: str, new: str) -> bool:
    """True when new defines a test of base once more (Python test / class, JUnit @Test fun|void, it|test('title') within the same
    describe path, shell function): the appended copy shadows (or doubles) the existing one."""
    ext = os.path.splitext(repo_path)[1].lower()
    if ext == ".py":
        b, n = _py_def_counts(base), _py_def_counts(new)
        if b is None or n is None:
            b, n = _def_counts(_PY_TEST_DEF, base), _def_counts(_PY_TEST_DEF, new)
    else:
        rx = next((r for exts, r in _DEF_RULES if ext in exts), None)
        if rx is None:
            return False
        b = n = None
        if rx is _JS_TEST_DEF:
            b, n = _js_def_counts(base), _js_def_counts(new)
        if b is None or n is None:
            b, n = _def_counts(rx, base), _def_counts(rx, new)
    return any(cnt > b.get(k, 0) >= 1 for k, cnt in n.items())


# An appended line that can turn a suite runner's exit status green whatever ran before it (A2): `exit 0`, `true` last,
# `|| true`, `set +e`, `sys.exit()`.
_STATUS_NEUTRALIZER = re.compile(r"\bexit\s+0\b|^\s*exit\s*(?:[;#].*)?$|^\s*(?:true|:)\s*(?:[;#].*)?$|\|\|\s*(?:true|:)\s*$|"
                                 r"\bset\s+\+e\b|\bexit\s*\(\s*0?\s*\)")


# A shell runner's exit status is its LAST command's unless `set -e` stops it at the first failure: one command appended at the end
# (`echo done`) makes it exit 0 over a failing check before it (decided with the user, 2026-10-09,
# tests/gates/test_gate_runner_no_errexit.sh: an appended code line is an edit of a shell runner that has no errexit).
# A #! flag (#!/bin/sh -e) is not errexit: the matrix runs a runner as `bash path`, which ignores it.
_ERREXIT = re.compile(r"^[ \t]*set[ \t]+(?:(?:[-+][A-Za-z]+|[-+]o[ \t]+\w+)[ \t]+)*(?:-[A-Za-z]*e[A-Za-z]*|-o[ \t]+errexit)\b", re.M)


def _shell_runner_without_errexit(repo_path: str, base_text: str) -> bool:
    ext = os.path.splitext(repo_path)[1].lower()
    shell = ext in (".sh", ".bash", ".zsh") or (ext == "" and base_text.startswith("#!") and "sh" in base_text.split("\n", 1)[0])
    return shell and not _ERREXIT.search(base_text)


def _git_line_split(data: bytes) -> list:
    """git's line model: a line ends at "\\n"; a last line without one is a different line than the same text with one."""
    parts = data.split(b"\n")
    return [p + b"\n" for p in parts[:-1]] + ([parts[-1]] if parts[-1] else [])


def test_change_is_append_only(base_ref: str, repo_path: str, old_path: str = "", runner: bool = False) -> bool:
    """True when the working tree only ADDS lines to this existing test file (a new test
    appended to it) and none of them is a skip marker. Any removed or changed line — or a
    binary file — keeps the file counted as an edited test. A file equal to
    base_ref is no edit at all: a test added in `--since` commits is in the change, unchanged
    against HEAD (2026-09-28: three new tests blocked the Stop hook as "edited").
    old_path: the file was renamed from it (git mv): compared with it.
    Compared in-process from blobs read in batches, not one `git diff -U0` per file (A12, 2026-10-09): only additions
    exist exactly when every base line is kept in order (a subsequence), which is what git's minimal diff shows; the
    added lines are the same whatever the alignment. An appended definition that redefines an existing test is an edit
    (redefines_test, A6). runner: a suite runner script (A2): an appended _STATUS_NEUTRALIZER line is an edit too, and so is any
    appended code line of a shell runner whose base has no errexit (_shell_runner_without_errexit)."""
    base = blob_at(base_ref, old_path or repo_path)
    new = worktree_bytes(repo_path)
    if new is not None and new == base:
        return True                                   # no edit at all, or a pure move
    if new is None or (base is None and object_info(base_ref, old_path or repo_path) is not None):
        return False                                  # deleted, no longer a regular file, or a directory before
    base = base or b""
    if b"\0" in base[:8000] or b"\0" in new[:8000]:
        return False                                  # git: "Binary files … differ"
    old_lines, i, added = _git_line_split(base), 0, []
    for line in _git_line_split(new):
        if i < len(old_lines) and line == old_lines[i]:
            i += 1
        else:
            added.append(line.decode("utf-8", errors="replace"))
    if i < len(old_lines) or any(TEST_SKIP_RE.search(a) or (runner and _STATUS_NEUTRALIZER.search(a)) for a in added):
        return False
    base_text = base.decode("utf-8", errors="replace")
    if runner and _shell_runner_without_errexit(repo_path, base_text) and any(a.strip() and not a.lstrip().startswith("#") for a in added):
        return False                                  # no set -e: the appended command decides the exit status
    return not redefines_test(repo_path, base_text, new.decode("utf-8", errors="replace"))


def since_test_weakened(since: str, repo_path: str, upstream: str = "", runner: bool = False) -> bool:
    """True when this test existed at `since`, a LOCAL-ONLY commit of `since..HEAD` (one not
    reachable from `upstream`; no upstream → every range commit) touches it, and its change to
    the working tree is not append-only — counted from the latest range commit touching it whose
    message holds a `Test-approved-by:` line (that commit's content was audited), else from
    `since`. A commit already on the remote (a teammate's, pulled in) passed its own push gate.
    runner: a suite runner script (A2), judged by test_change_is_append_only(runner=True)."""
    root = str(get_repo_root())
    if object_info(since, repo_path) is None:
        return False
    local = subprocess.run(["git", "-C", root, "rev-list", "-1", f"{since}..HEAD"]
                           + (["--not", upstream] if upstream else []) + ["--", repo_path],
                           capture_output=True, text=True)
    if local.returncode == 0 and not local.stdout.strip():
        return False                                  # only upstream commits touch it
    res = subprocess.run(["git", "-C", root, "log", "--format=%H", "-E",
                          "--grep=^Test-approved-by:[[:space:]]*[^[:space:]]", f"{since}..HEAD",
                          "--", repo_path], capture_output=True, text=True)
    if res.returncode != 0:
        return True                                   # cannot read the range: fail closed
    # The line counts only as push_gate counts it (2026-10-09): a real trailer whose task has antigravity-pm's audit pass
    # record; a line the agent writes itself is no audit (tests/gates/test_gate_since_test_edit.sh).
    base = since
    for sha in res.stdout.split():                    # newest first
        if _push_gate().approved(root, f"{sha}^!")[0]:
            base = sha
            PM_APPROVAL_USED.append(repo_path)   # lời duyệt dựa vào biên bản antigravity-pm: pm_relaxed() xét chỗ đọc
            break
    return not test_change_is_append_only(base, repo_path, runner=runner)


def _push_gate():
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import push_gate  # noqa: PLC0415 - sibling module in bin/, only when a Test-approved-by commit is in the range
    return push_gate


def split_tests_by_author(paths: list, session, transcript) -> tuple:
    """(blocking, other): the edited existing tests this session made — or cannot be told
    apart — and those another session or a person made (a warning, never a block).

    "Other" needs positive evidence: the file changed inside another session's narrowest Bash
    window, or before this session's first prompt with no write command of this session naming
    it (a deleted file: this session ran no Bash at all). A change during the session outside
    every window is NOT evidence (a detached process, a person: cannot tell) and blocks. Without
    a session, a usable transcript, or with a tool the gate cannot see through (read_only_tool)
    every path stays blocking — fail closed."""
    if not paths or not session or not transcript:
        return list(paths), []
    trace = session_authorship.session_trace(transcript)
    if trace is None:
        return list(paths), []
    edited, bash, started, bash_calls, opaque = trace
    if opaque:
        return list(paths), []
    project = get_project_dir()
    root = Path(os.path.realpath(project))
    # "other" needs both rules (session_authorship.block_owner): an open window of a session that is gone no longer
    # hides a change, but its cut window never takes a file from a wider window of this session
    # The ledger sits where bash_write_ledger.sh writes it, in main; the hook that gates a session's worktree says so (DEVKIT_LEDGER_ROOT).
    ledger = os.environ.get("DEVKIT_LEDGER_ROOT") or project
    old_windows = session_authorship.bash_windows(ledger)
    try:
        windows = session_authorship.bash_windows(ledger, session)
    except Exception as exc:   # the cut rule must never crash the gate (a crash reads as no verdict): the old rule decides
        print(f"post-fix-gate: cut ledger windows unavailable ({exc!r}); the old rule decides", file=sys.stderr)
        windows = old_windows
    named = session_authorship.shell_named(bash)
    owners, undecided = {}, {}   # undecided: realpath -> (path, mtime) changed during the session
    for f in paths:
        full = root / f
        by_me = os.path.realpath(full) in edited or session_authorship.names_path(named, root, f)
        owner = "me" if by_me else None
        if owner is None:
            try:
                st = os.stat(full)
                mt = st.st_mtime
            except OSError:
                mt = None     # deleted: with no Bash and no opaque tool, it cannot be ours
                if bash_calls == 0:
                    owner = "other"
            if mt is not None:
                sid = session_authorship.block_owner(mt, old_windows, windows, session)
                if sid == session:
                    owner = "me"
                elif sid:
                    owner = "other"
                elif sid is None and started and max(mt, st.st_ctime) < started - 1:
                    # Before the first prompt. By ctime too: touch -t / tar / rsync / cp -p set the
                    # mtime back, nothing sets the ctime back. A write verb naming it is by_me above.
                    owner = "other"
                elif started:
                    undecided[os.path.realpath(full)] = (f, mt)
        owners[f] = owner
    if undecided:
        # Another Claude Code session's Edit/Write leaves no Bash window: its own transcript,
        # next to this one, holds the call. Its span must hold the mtime (narrowest wins, as above).
        edits = session_authorship.other_session_edits(transcript, session, undecided, started - 60,
                                                       edited, bash)
        for rp, (f, mt) in undecided.items():
            sid = session_authorship.block_owner(mt, old_windows, windows, session, edits.get(rp, []))
            owners[f] = "other" if sid and sid != session else None
    return ([f for f in paths if owners[f] != "other"], [f for f in paths if owners[f] == "other"])


APPROVE_LABEL = re.compile(r"^\s*(?:duyệt|đồng ý|chấp nhận|approve[ds]?|accept(?:ed)?)\b", re.I)
# Who approved each file split_user_approved returned: "user" (an AskUserQuestion answer) or "cross-review:<reviewer>" (#605: a
# different agent's entry in approved_tests.json). 2026-09-29: the agent's own approval was printed as the user's; 28/10 (#605): the agent
# that edited a test never approves it — --auto-approve-tests, DEVKIT_AUTO_APPROVE_TESTS=1 and an `AUTO-APPROVE:` reply line approve nothing.
APPROVED_BY = {}
CROSS_REVIEW = {}            # path -> (reviewer, task_id) of the accepted cross-review entry
PM_APPROVAL_USED = []        # --since: test whose base moved to a Test-approved-by commit (an antigravity-pm audit record)


def pm_relaxed() -> bool:
    """Audit T0066 vòng 2 (#605): lượt có lời duyệt dựa vào biên bản antigravity-pm (CROSS_REVIEW, mốc --since dời theo trailer) đọc từ
    ANTIGRAVITY_PM_STATE_HOME lạ (không phải ~/.antigravity-pm của user) là nới lỏng: kết luận giữ nguyên (test cần), nhưng không ghi
    biên nhận task / merge gate và full_pass.json không là exit 0 — biên bản ở chỗ lạ agent nào cũng tự dựng được. Lỗi → True."""
    if not CROSS_REVIEW and not PM_APPROVAL_USED:
        return False
    try:
        return bool(_push_gate().pm_home_overridden())
    except (ImportError, AttributeError, OSError) as e:
        print(f"post-fix-gate: không xác định được thư mục antigravity-pm ({type(e).__name__}); coi là nới lỏng", file=sys.stderr)
        return True
APPROVAL_REJECTS = []        # (path, sha256 hiện tại, lý do): mục duyệt bị từ chối, cần duyệt lại
SELF_APPROVAL_REFUSED = []   # paths an --auto-approve-tests / DEVKIT_AUTO_APPROVE_TESTS run asked to approve
CROSS_REVIEW_FIELDS = ("path", "sha256", "reviewer", "author", "task_id", "reason")


def _norm_agent(v):
    return v.strip().casefold()


def _blob_is_audited(top, prefix, project_root, f, head) -> bool:
    """True khi nội dung hiện tại của `f` (đường dẫn so với project_root) đúng bằng blob của nó ở commit `head` (auditedHead).
    File không có ở head, lỗi git → False (fail closed)."""
    cur = subprocess.run(["git", "-C", top, "hash-object", "--", str(Path(project_root) / f)],
                         capture_output=True, text=True, timeout=30)
    if cur.returncode != 0 or not cur.stdout.strip():
        return False
    blob = subprocess.run(["git", "-C", top, "rev-parse", "--verify", "-q", f"{head}:{prefix}{f}"],
                          capture_output=True, text=True, timeout=30)
    return blob.returncode == 0 and blob.stdout.strip() == cur.stdout.strip()


def _branch_base(root, project_root, fallback_head=True) -> str:
    """Base của nhánh cho duyệt chéo: BASE_REF (đã là merge-base khi có --diff, hoặc mốc --since) khi khác HEAD, không thì
    merge-base(nhánh đích, HEAD); không có nhánh đích → "HEAD" (fallback_head) hoặc "". Lỗi git → "" (người gọi không duyệt)."""
    if BASE_REF and BASE_REF != "HEAD":
        return BASE_REF
    trunk_ref, _name = task_trunk(project_root)
    if not trunk_ref:
        return "HEAD" if fallback_head else ""
    mb = subprocess.run(["git", "-C", root, "merge-base", trunk_ref, "HEAD"], capture_output=True, text=True, timeout=30)
    return mb.stdout.strip() if mb.returncode == 0 else ""


def _trailer_cross_review(paths: list, project_root) -> dict:
    """{path: task_id} — nguồn duyệt chéo thứ hai (#605 lane E): commit MỚI NHẤT của nhánh (base..HEAD) chạm file, có trailer
    `Test-approved-by: antigravity <task-id>` mà push_gate.approved công nhận (biên bản audit pass của antigravity-pm, ngoài repo),
    và nội dung hiện tại của file đúng bằng blob ở auditedHead mà PM ghi trong verdicts.audit.notes của task đó (push_gate.audited_head,
    audit T0066: không phải blob ở commit mang trailer; đổi sau audit hoặc thiếu auditedHead → không duyệt). Trailer đi theo commit nên tới được
    scratch worktree của merge gate, nơi .claude/audit-gate/ không được chép. base: BASE_REF (đã là merge-base khi có --diff),
    HEAD → merge-base(nhánh đích, HEAD). Mọi lỗi git → không duyệt (fail closed).
    ponytail: --since trên chính nhánh đích không có range ở đây (base = HEAD) → không duyệt; nối args.since vào nếu cần."""
    if not paths:
        return {}
    try:
        root = str(get_repo_root())
        prefix = get_project_prefix()
        base = _branch_base(root, project_root, fallback_head=False)
        if not base:
            return {}
        # Commit có trailer chốt CẢ cây đã audit, không cần chạm file: audit xong ghi một commit rỗng có trailer là đủ.
        res = subprocess.run(["git", "-C", root, "log", "--format=%H", "-E",
                              "--grep=^Test-approved-by:[[:space:]]*[^[:space:]]", f"{base}..HEAD"],
                             capture_output=True, text=True, timeout=30)
        if res.returncode != 0:
            return {}
        audited = []                                  # (auditedHead, task_id), mới nhất trước, chỉ commit push_gate công nhận
        for sha in res.stdout.split():
            ok, note = _push_gate().approved(root, f"{sha}^!")
            m = re.search(r"antigravity\s+(\S+)", note or "") if ok else None
            # Audit T0066: so với cây PM đã audit (auditedHead ngoài repo), không với commit mang trailer — trailer của task cũ
            # đặt lên commit sửa test mới không duyệt được nội dung mới (replay). Không có auditedHead → không duyệt.
            head = _push_gate().audited_head(root, m.group(1)) if m else None
            # Audit T0066 vòng 2: auditedHead trước base (task cũ audit cây cũ) không duyệt việc chép lùi test về bản yếu đó.
            if head and _push_gate().head_after(root, base, head):
                audited.append((head, m.group(1)))
        out = {}
        for f in paths if audited else []:
            for head, task_id in audited:             # nội dung hiện tại phải đúng bằng blob ở một cây đã audit
                if _blob_is_audited(root, prefix, project_root, f, head):
                    out[f] = task_id
                    break
        return out
    except (OSError, subprocess.SubprocessError, RuntimeError, ImportError) as e:
        print(f"post-fix-gate: trailer Test-approved-by không đọc được ({type(e).__name__}); không duyệt", file=sys.stderr)
        return {}


def split_user_approved(paths: list, transcript, auto_approve: bool = False) -> tuple:
    """(still_blocking, approved): an edited existing test approved by the user's answer or by a CROSS-REVIEW (#605).
    Cross-review: .claude/audit-gate/approved_tests.json = {"approvals": [{path, sha256, reviewer, author, task_id, reason}]},
    written by another agent (Antigravity /giao audit, a reviewer session); accepted when all six are non-empty strings,
    reviewer != author and != DEVKIT_AGENT_ID (case-insensitive), sha256 is the file's current content, and (audit T0066) task_id has
    an antigravity-pm audit pass outside the repo whose notes record `auditedHead: <sha40>` with the file's current blob at that
    commit (push_gate.audited_head) — the file itself is writable by any agent, so it never approves on its own. Anything else in
    that file (legacy list / {path: sha256}, a malformed entry) approves nothing and is listed "cần duyệt lại".
    auto_approve (--auto-approve-tests) and DEVKIT_AUTO_APPROVE_TESTS are self-approval: refused, kept only so old command
    lines parse. User answer: the harness-written `toolUseResult.answers` record. Per file, all three hold:
    the question (header, options) names the file's path or basename, the chosen label
    approves (APPROVE_LABEL), and the file has not changed since that answer. Searched: the
    transcript's folder, else DEVKIT_TRANSCRIPTS_DIR, else ~/.claude/projects/<project>/ (in a linked worktree
    also this session's own transcript in the main checkout's folder, #582) —
    only transcripts written after the oldest of those files changed."""
    if not paths:
        return paths, []
    if auto_approve or os.environ.get("DEVKIT_AUTO_APPROVE_TESTS") == "1":
        SELF_APPROVAL_REFUSED[:] = list(paths)   # #605: tự duyệt bị từ chối, xét tiếp như không có cờ
    root = Path(os.path.realpath(get_project_dir()))
    mtimes = {}
    for f in paths:
        try:
            mtimes[f] = os.stat(root / f).st_mtime
        except OSError:
            pass                                  # deleted: nothing to bind an approval to
    if not mtimes:
        return paths, []
    appr_file = root / ".claude" / "audit-gate" / "approved_tests.json"
    approved_at = {}                              # path -> latest approving answer (epoch s)
    user_at = {}                                  # path -> latest approving answer of the user
    if appr_file.is_file():
        def _cur_sha(f):
            try:
                with open(root / f, "rb") as tfh:
                    return hashlib.sha256(tfh.read()).hexdigest()
            except OSError:
                return ""
        try:
            with open(appr_file, encoding="utf-8") as afh:
                saved = json.load(afh)
        except (OSError, ValueError) as e:
            # fail-closed: file duyệt không đọc được thì không duyệt gì, và nói rõ cho agent
            saved = None
            APPROVAL_REJECTS.extend((f, _cur_sha(f), f"approved_tests.json không đọc được ({type(e).__name__})") for f in mtimes)
        entries = saved.get("approvals") if isinstance(saved, dict) and isinstance(saved.get("approvals"), list) else None
        if entries is None and saved is not None:
            # #534 mục 3 / #576: dạng cũ (list, {path: sha256}) không có nguồn duyệt — agent tự ghi bằng script vẫn PASS
            legacy = saved if isinstance(saved, list) else list(saved) if isinstance(saved, dict) else []
            APPROVAL_REJECTS.extend((f, _cur_sha(f), "dạng cũ không nguồn duyệt") for f in mtimes if f in legacy)
        agent_id = _norm_agent(os.environ.get("DEVKIT_AGENT_ID") or "")
        for e in entries or []:
            f = e.get("path") if isinstance(e, dict) else None
            if not isinstance(f, str) or f not in mtimes:
                continue                          # names no edited test of this run: approves nothing
            if not all(isinstance(e.get(k), str) and e[k].strip() for k in CROSS_REVIEW_FIELDS):
                APPROVAL_REJECTS.append((f, _cur_sha(f), "mục duyệt thiếu trường (" + ", ".join(CROSS_REVIEW_FIELDS) + ")"))
                continue
            reviewer = _norm_agent(e["reviewer"])
            if reviewer == _norm_agent(e["author"]) or (agent_id and reviewer == agent_id):
                APPROVAL_REJECTS.append((f, _cur_sha(f), "reviewer trùng author (tự duyệt)"))
                continue
            cur = _cur_sha(f)
            if not cur or e["sha256"].strip().lower() != cur:
                APPROVAL_REJECTS.append((f, cur, "sha256 lệch nội dung hiện tại"))
                continue
            # Audit T0066: file này agent nào cũng ghi được — mục duyệt chỉ tính khi task_id có biên bản audit pass ngoài repo
            # kèm auditedHead, và nội dung hiện tại đúng bằng blob ở cây đã audit đó.
            try:
                git_top, prefix = str(get_repo_root()), get_project_prefix()
                head = _push_gate().audited_head(git_top, e["task_id"].strip())
                # Audit T0066 vòng 2: base của nhánh phải là tổ tiên của auditedHead (không duyệt chép lùi về cây cũ trước base)
                base = _branch_base(git_top, root) if head else ""
                after = bool(head) and _push_gate().head_after(git_top, base, head)
                audited_ok = after and _blob_is_audited(git_top, prefix, root, f, head)
            except (OSError, subprocess.SubprocessError, RuntimeError, ImportError) as err:
                head, audited_ok, after, base = None, False, False, ""
                print(f"post-fix-gate: không đọc được biên bản audit của {e['task_id'].strip()} ({type(err).__name__}); không duyệt",
                      file=sys.stderr)
            if not head:
                APPROVAL_REJECTS.append((f, cur, f"task {e['task_id'].strip()} không có biên bản audit pass của antigravity-pm "
                                                 "kèm `auditedHead: <sha>`"))
                continue
            if not after:
                APPROVAL_REJECTS.append((f, cur, f"auditedHead {head[:10]} không nằm sau base {base[:10] or '?'} của nhánh (audit cây cũ)"))
                continue
            if not audited_ok:
                APPROVAL_REJECTS.append((f, cur, f"nội dung khác cây đã audit (auditedHead {head[:10]})"))
                continue
            approved_at[f] = max(approved_at.get(f, 0), mtimes[f])   # sha256 gắn nội dung: mtime không quyết định
            CROSS_REVIEW[f] = (e["reviewer"].strip(), e["task_id"].strip())
    for f, tid in _trailer_cross_review([f for f in mtimes if f not in CROSS_REVIEW], root).items():
        approved_at[f] = max(approved_at.get(f, 0), mtimes[f])   # nội dung = blob đã audit: mtime không quyết định
        CROSS_REVIEW[f] = ("antigravity", tid)
    folders = []
    if transcript:
        folders.append(Path(transcript).parent)
    if os.environ.get("DEVKIT_TRANSCRIPTS_DIR"):
        folders.append(Path(os.environ["DEVKIT_TRANSCRIPTS_DIR"]))
    folders.append(Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(root)))
    # #582: worktree có slug riêng, nhưng phiên đã hỏi nằm ở checkout chính. Chỉ nhận ĐÚNG transcript của phiên này
    # (CLAUDE_CODE_SESSION_ID) ở đó, không quét cả thư mục: lời "Duyệt" của phiên khác không được duyệt test của worktree này.
    session_files = []
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if re.fullmatch(r"[A-Za-z0-9-]{8,64}", sid):
        try:
            import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
            if rc.in_linked_worktree(root):
                common = subprocess.run(["git", "-C", str(root), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                        capture_output=True, text=True, timeout=10, env=rc._clean_git_env()).stdout.strip()
                if common and Path(common).name == ".git":
                    main_root = os.path.realpath(str(Path(common).parent))
                    session_files.append(Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", main_root) / (sid + ".jsonl"))
        except (OSError, subprocess.SubprocessError, ImportError):
            pass
    agy_brain = Path.home() / ".gemini" / "antigravity" / "brain"
    if agy_brain.is_dir():
        try:
            folders.extend(agy_brain.glob("*/.system_generated/logs"))
        except OSError:
            pass

    oldest = min(mtimes.values())
    candidates = []
    for fld in folders:
        try:
            candidates.extend(p for p in fld.glob("*.jsonl") if p.stat().st_mtime >= oldest)
        except OSError:
            pass
    for sf in session_files:
        try:
            if sf.is_file() and sf.stat().st_mtime >= oldest and sf not in candidates:
                candidates.append(sf)
        except OSError:
            pass

    for tp in candidates:
        try:
            fh = os.fdopen(_state_fd(tp), encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"answers"' in line and '"toolUseResult"' in line:
                    try:
                        rec = json.loads(line)
                        res = rec.get("toolUseResult") or {}
                        t = calendar.timegm(time.strptime(rec["timestamp"][:19], "%Y-%m-%dT%H:%M:%S"))
                    except (ValueError, KeyError, TypeError, AttributeError):
                        continue
                    if rec.get("type") != "user" or not isinstance(res, dict):
                        continue
                    answers = res.get("answers") or {}
                    for q in res.get("questions") or []:
                        if not isinstance(q, dict):
                            continue
                        label = answers.get(q.get("question"), "")
                        if not isinstance(label, str) or not APPROVE_LABEL.search(label):
                            continue
                        text = json.dumps(q, ensure_ascii=False)
                        for f in mtimes:
                            if f in text or (len(Path(f).name) >= 6 and Path(f).name in text):
                                approved_at[f] = max(approved_at.get(f, 0), t)
                                user_at[f] = max(user_at.get(f, 0), t)
                    continue
    # ponytail: duyệt được nhớ theo (đường dẫn, nội dung) trong phạm vi transcript còn quét được, không gắn với blob HEAD gốc; gắn base blob nếu việc yếu hoá lại test sau khi revert thành vấn đề
    hash_file = root / ".claude" / "audit-gate" / "approved_hashes.json"
    saved_hashes = {}
    if hash_file.is_file():
        try:
            with open(hash_file, "r", encoding="utf-8") as hf:
                saved_hashes = json.load(hf)
                if not isinstance(saved_hashes, dict):
                    saved_hashes = {}
        except Exception:
            saved_hashes = {}

    new_hashes = saved_hashes.copy()
    
    for f in paths:
        if f not in mtimes:
            continue
            
        try:
            with open(root / f, "rb") as content_file:
                file_hash = hashlib.sha256(content_file.read()).hexdigest()
        except OSError:
            continue
            
        if user_at.get(f, 0) >= mtimes[f]:
            new_hashes[f] = file_hash
        elif user_at.get(f, 0) > 0 and saved_hashes.get(f) == file_hash:
            new_hashes[f] = file_hash
            # Exempt from mtime check by updating the approval timestamps
            t_now = mtimes[f] + 1
            approved_at[f] = max(approved_at.get(f, 0), t_now)
            user_at[f] = max(user_at.get(f, 0), t_now)

    for old_f in list(new_hashes.keys()):
        if not (root / old_f).is_file():
            del new_hashes[old_f]

    if new_hashes != saved_hashes:
        try:
            hash_file.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp_path = tempfile.mkstemp(dir=hash_file.parent, prefix='approved_hashes.', suffix='.tmp')
            with os.fdopen(fd, 'w', encoding="utf-8") as th:
                json.dump(new_hashes, th)
            os.replace(tmp_path, hash_file)
        except (OSError, ValueError):
            pass

    ok = [f for f in paths if f in mtimes and approved_at.get(f, 0) >= mtimes[f]]
    APPROVED_BY.update({f: "user" if user_at.get(f, 0) >= mtimes[f] else "cross-review:" + CROSS_REVIEW[f][0] for f in ok})
    return [f for f in paths if f not in ok], ok


def demote_other_session(category, findings: list, session, transcript) -> tuple:
    """(blocking, other) for [(rel, message)] findings: a vacuous test or duplicate proof that
    another session made is a warning for this one, not a block (GeelyEx2 2026-09-27: another
    session's test and PNG REJECTed this session 13 times). Same attribution and fail-closed
    rule as split_tests_by_author: no session info or unknown author -> blocking."""
    if not findings:
        return findings, []
    _mine, other = split_tests_by_author(sorted({f for f, _ in findings}), session, transcript)
    if not other:
        return findings, []
    FINDINGS[:] = [x for x in FINDINGS if not (x["category"] == category and x["file"] in other)]
    return [x for x in findings if x[0] not in other], [x for x in findings if x[0] in other]


def _sha_file(path):
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest() if path else ""
    except OSError:
        return ""


def _state_fd(path, mode="r"):
    """fd of the REGULAR file at path, opened for "r" | "a" | "w" without waiting. The gate's state (.git/postfix-gate/,
    .claude/audit-gate/, proof folders, transcripts) is a path an agent can write: a FIFO planted there blocked a plain open()
    for ever, and a Stop hook killed by its timeout lets the Stop through (issues-bugs A.4). Anything else raises OSError, as a
    missing file does (a FIFO with no reader: ENXIO on a write-open). tests/gates/test_state_fifo_no_hang.sh"""
    import stat as _stat  # noqa: PLC0415
    flags = {"r": os.O_RDONLY, "a": os.O_WRONLY | os.O_CREAT | os.O_APPEND, "w": os.O_WRONLY | os.O_CREAT | os.O_TRUNC}[mode]
    fd = os.open(path, flags | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0), 0o666)
    if not _stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise OSError(f"not a regular file: {path}")
    return fd


# A record or receipt is a few KB: its biggest field is "dirty", the changed files (a name and a sha each). A file past the cap is no record.
# ponytail: a tree with more than ~10k changed files has a receipt over the cap: it is not re-used and the partial writer drops it; raise the cap when seen.
STATE_JSON_MAX = 1 << 20


def _load_state_json(path):
    """json of the gate record / receipt at path; ValueError when it is over STATE_JSON_MAX. json.load of one huge integer is quadratic on
    Python < 3.11 (6 MB took 126 s on 3.9.6) and the file is one anyone can write; the size is read from the open fd, not from a second stat."""
    with os.fdopen(_state_fd(path), encoding="utf-8") as f:
        size = os.fstat(f.fileno()).st_size
        if size > STATE_JSON_MAX:
            raise ValueError(f"{path}: {size} bytes, over {STATE_JSON_MAX}")
        return json.load(f)


# A suite that talks to a device, an emulator or an engine is never reused: its outcome depends
# on state no fingerprint holds (Antigravity review of O1, 2026-09-28). One exception, decided by the user on 2026-10-07
# (Goods: ~30 % of the gate was Unity runs on content that had already passed; a real Unity run was measured NOT to change
# tree_fp): a Unity TEST suite (UNITY_SUITE: unity-batch editmode|playmode; a bare -runTests command stays never re-used) whose command touches no real or
# emulated device (HARD_DEVICE_SUITE) is re-used from a receipt that matched fingerprint, matrix, local config and format,
# when that suite ran less than DEVKIT_UNITY_REUSE_MAX_S ago (default 3600; 0 = never; receipt tests[].ran_at).
# DEVICE_SUITE stays the union of the hard part and the loose Unity match it always had: every other reader is unchanged.
HARD_DEVICE_SUITE = re.compile(r"\badb\b|connected\w*(?:Test|Check)|\bemulator\b|\bsimctl\b|"
                               r"\bxcodebuild\b[^\n]*\btest\b|replicant|-testPlatform[ =]+(?!EditMode\b|PlayMode\b)\w+", re.I)
UNITY_SUITE = re.compile(r"\bunity-batch\b[^\n]*\b(?:editmode|playmode)\b", re.I)
DEVICE_SUITE = re.compile(HARD_DEVICE_SUITE.pattern + r"|unity-batch|-runTests\b", re.I)


_IGNORED_LISTING = {}


def _ignored_files(project_dir, pathspecs):
    """`git ls-files --others --ignored` for these pathspecs, read once per run: the walk costs 1.5 s warm and 3.8 s cold in
    OfficeReader (2026-10-13) and a run asked for it up to 5 times. Only the NAMES are kept: every caller hashes or reads the
    files again. A config created or deleted during the run is missed here; the next run lists afresh and its key differs, so
    the suites run again (never a wrong reuse). DEVKIT_GATE_LISTING_CACHE=0: one walk per call."""
    key = (os.path.realpath(str(project_dir)), tuple(pathspecs))
    cache = os.environ.get("DEVKIT_GATE_LISTING_CACHE", "1") != "0"
    if cache and key in _IGNORED_LISTING:
        return _IGNORED_LISTING[key]
    out = subprocess.run(["git", "-C", str(project_dir), "ls-files", "-z", "--others", "--ignored",
                          "--exclude-standard", "--"] + list(pathspecs), capture_output=True, text=True,
                         errors="surrogateescape").stdout   # a non-UTF-8 name must not disable the reuse (A8)
    files = [r for r in out.split("\0") if r and not r.endswith("/")]
    if cache:
        _IGNORED_LISTING[key] = files
    return files


def local_state_files(project_dir):
    """{path: sha} of the git-ignored files a build or test reads that tree_fp leaves out: the local
    config worktree.py copies (.env*, local.properties, google-services.json, …) and the build
    inputs red_proof furnishes (build_inputs.py). Raises when they cannot be listed.
    A config inside a build cache (build_inputs.SKIP_WALK: Unity Library/, build/, …) is the build's own output, not an input:
    Neighbours #48 (18/10) — a worktree's cloned unity/Library holds Bee/**/Gradle/local.properties, a merge-gate scratch has no
    Library, so the scratch never matched the worktree's receipt."""
    _scripts_on_path()
    from worktree import LOCAL_CONFIG  # noqa: PLC0415
    from build_inputs import SKIP_WALK, build_inputs  # noqa: PLC0415
    pathspecs = []
    for p in LOCAL_CONFIG:
        pathspecs.extend([p, f"**/{p}"])
    files = {r for r in _ignored_files(project_dir, pathspecs)
             if any(fnmatch.fnmatch(os.path.basename(r), p) for p in LOCAL_CONFIG)
             and not SKIP_WALK.intersection(r.split("/")[:-1])}
    files |= set(build_inputs(project_dir))
    return {rel: _sha_file(Path(project_dir) / rel) for rel in files}


def local_state_sha(project_dir, skip=(), files=None):
    """sha of local_state_files (or of files, taken by the caller) without the paths in skip (those the suites rewrote: receipt
    "local_regen"). "?" when they cannot be listed."""
    try:
        files = local_state_files(project_dir) if files is None else files
    except Exception:   # any failure only disables the reuse
        return "?"
    h = hashlib.sha256()
    for rel in sorted(set(files) - set(skip)):
        h.update(os.fsencode(rel) + b"\0" + files[rel].encode() + b"\0")
    return h.hexdigest()


def local_regen(before, after):
    """Paths of local state the suites rewrote, created or deleted (local_state_files before vs after them): build OUTPUTS, whose
    bytes say nothing about what was tested. GeelyEx2 #62 (18/10): the Test task rebuilds the overlay launcher-whitelist.apk that
    red_proof.json declares a build input, with other bytes each run, so a merge-gate scratch (APK copied from main) never matched
    the worktree's receipt. No snapshot before (no suite ran in this run): []. A run whose build left such a file alone (Gradle
    up-to-date) still leaves it out through known_generated."""
    if before is None:
        return []
    return regen_allowed(rel for rel in set(before) | set(after) if before.get(rel) != after.get(rel))


def regen_allowed(paths):
    """The paths of paths that may be left out of local_sha, sorted: never local config or a default build input (LOCAL_CONFIG,
    build_inputs.DEFAULT_INPUTS): a tool that updates one in place (Flutter keeps sdk.dir in local.properties and rewrites its
    flutter.* keys; an IDE sync; a person editing it during the run) changed a real input, and dropping it reused a PASS for another
    sdk.dir (review 18/10, P1). The reader applies it too: a receipt cannot list such a file away. Raises when they cannot be loaded."""
    _scripts_on_path()
    from worktree import LOCAL_CONFIG  # noqa: PLC0415
    from build_inputs import DEFAULT_INPUTS  # noqa: PLC0415
    pats = [q for p in DEFAULT_INPUTS for q in (p, p[3:] if p.startswith("**/") else p)]
    return sorted(rel for rel in paths
                  if not any(fnmatch.fnmatch(os.path.basename(rel), p) for p in LOCAL_CONFIG)
                  and not any(fnmatch.fnmatch(rel, p) for p in pats))


# local_state_files taken right before this run's first suite (None: no suite ran); read by write_full_pass_receipt.
LOCAL_STATE_BEFORE = None
GENERATED_NAME, GENERATED_MAX = "local_generated.json", 256   # in <git-common-dir>/postfix-gate: one list for every checkout of the repo


def _generated_path(receipt):
    """<git-common-dir>/postfix-gate/local_generated.json for receipt <git dir>/postfix-gate/full_pass.json; None outside git (the receipt is
    then under <project>/.agents/: no sibling worktree to lend to, and no file is written into the project)."""
    git_dir = os.path.dirname(os.path.dirname(receipt))
    return None if os.path.basename(git_dir) == ".agents" else os.path.join(_run_log_dir(git_dir), GENERATED_NAME)


GENERATED_TRUST = 2   # real runs that must each have seen a path rewritten before it is left out (not one edit made during one run)


def _generated_counts(receipt):
    """{path: real runs that saw its suites rewrite it}, oldest first; {} when none or unreadable."""
    path = _generated_path(receipt)
    if not path:
        return {}
    try:
        data = _load_state_json(path)
    except (OSError, ValueError, RecursionError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {p: n for p, n in data.items() if isinstance(n, int) and not isinstance(n, bool)}


def known_generated(receipt):
    """Paths that GENERATED_TRUST real runs in checkouts of this repo saw their suites rewrite (local_regen), so that a later run whose build
    left them alone still leaves them out of local_sha. GeelyEx2 #65 (18/10): Gradle was up-to-date, the worktree's overlay APK was still the
    one an earlier run had built, the scratch had main's, this run's local_regen was empty and REG-CAR-01 ran again. A path seen once (a
    person or a tool editing a build input during one run) is not trusted.
    ponytail: a trusted path stays left out for every branch and checkout of the repo (no decay; the GENERATED_MAX newest kept); add a
    last-seen time and expire it when a build output turns back into a real input."""
    return [p for p, n in _generated_counts(receipt).items() if n >= GENERATED_TRUST]


def remember_generated(receipt, paths):
    """Count one more real run for each of paths (moved to the end: newest), keep the GENERATED_MAX newest, write atomically. Two runs at
    once can lose one's count: it is counted again at its next real run."""
    counts = _generated_counts(receipt)
    for p in paths:
        counts[p] = counts.pop(p, 0) + 1
    keep = list(counts)[-GENERATED_MAX:]
    if len(keep) < len(counts):
        log_warn(f"{GENERATED_NAME}: {len(counts) - len(keep)} oldest path(s) dropped (cap {GENERATED_MAX})")
        counts = {p: counts[p] for p in keep}
    target = _generated_path(receipt)
    if not target:
        return
    tmp = None
    try:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".tmp_generated.", dir=os.path.dirname(target))
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(counts, f)
        os.replace(tmp, target)
    except OSError as e:
        log_warn(f"{GENERATED_NAME}: {e}")
        if tmp:
            try:
                os.unlink(tmp)
            except OSError as e2:
                log_warn(f"{GENERATED_NAME}: {e2}")


def snapshot_local_configs(project_dir):
    """Snapshot local config files (.env*, local.properties, google-services.json, config.json)."""
    _scripts_on_path()
    snapshots = {}
    try:
        from worktree import LOCAL_CONFIG
        config_files = list(LOCAL_CONFIG) + ["config.json", "**/config.json"]
        for rel in _ignored_files(project_dir, config_files):
            full = Path(project_dir) / rel
            if full.is_file():
                try:
                    snapshots[full] = full.read_bytes()
                except OSError:
                    pass
    except Exception:
        pass
    return snapshots


def restore_local_configs(snapshots):
    """Restore any local config files that were modified or deleted by tests (prevents GeelyEx2 licenseKey loss / config corruption)."""
    for full, orig_bytes in (snapshots or {}).items():
        try:
            if not full.exists() or full.read_bytes() != orig_bytes:
                full.write_bytes(orig_bytes)
        except OSError:
            pass


@contextlib.contextmanager
def config_sandbox(project_dir):
    """Context manager to snapshot and restore local configs."""
    snaps = snapshot_local_configs(project_dir)
    try:
        yield snaps
    finally:
        restore_local_configs(snaps)


# Một hoặc nhiều cấp dưới tests/ và hooks/tests/: tests/gates/*.sh từng không khớp (chỉ tests/*.sh),
# nên DEVKIT_GATE_DONE bỏ sót và run_impacted chạy lại đúng script ma trận vừa chạy.
_SCRIPT = r"((?:[\w.-]+/)*(?:tests|hooks/tests)/(?:[\w.-]+/)*[\w.-]+\.sh)\b"
RAN_SCRIPT = re.compile(r"(?:^|[;&|(]\s*|\s)(?:ba|z)?sh\s+(?:-\w+\s+)*" + _SCRIPT
                        + r"|(?:^|[;&|(]\s*)\./" + _SCRIPT.replace("(", "(?:", 1).replace("(?:(?:", "((?:", 1))


# Version of how this gate reads suite results. Bump it in any change that alters that reading:
# pass/fail parsing (exit codes, untested_exit, flaky/infra retry, vacuity), what counts as a
# suite run (modes, DEVICE_SUITE, which suites --full adds). A receipt with another value — or
# none, as written before this key existed — is never reused. It replaced the sha of this file
# in the reuse key: projects symlink the live DevKit and its source changed 44 times in 5 days
# (GeelyEx2, 2026-09-28), so the reuse almost never hit. The receipt still records gate_sha.
# ponytail: a forgotten bump reuses a PASS read by old parsing rules; upgrade (hash the parsing
# functions' source) when parsing changes are frequent.
RESULT_FORMAT = 3   # 2 (2026-10-07): a Unity test suite may be re-used (DEVKIT_UNITY_REUSE_MAX_S), receipt tests[].ran_at
# 3 (2026-10-20): cache PASS theo khoá nội dung từng suite (bin/suite_cache.py) và CACHED-FULL
# suite id -> when it really ran (a re-used suite keeps its first stamp). Not a key of the suite dict: that dict is printed by
# --json, whose stdout must stay byte-stable between runs (tests/gates/test_gate_run_log.sh).
SUITE_RAN_AT = {}


_SUITE_CACHE = []


def suite_cache_mod():
    """bin/suite_cache.py (P2), None khi không nạp được: khi đó mọi suite chạy như trước."""
    if not _SUITE_CACHE:
        try:
            sys.path.insert(0, str(Path(__file__).resolve().parent))
            import suite_cache as _sc  # noqa: PLC0415 - sibling module in bin/
            _SUITE_CACHE.append(_sc)
        except Exception as e:   # noqa: BLE001
            log_warn(f"suite_cache: {e!r}")
            _SUITE_CACHE.append(None)
    return _SUITE_CACHE[0]


def suite_cacheable(test):
    """(cache được theo khoá?, lý do) của một mục ma trận — cùng luật cho gate và stale_rerun.run_one."""
    mod = suite_cache_mod()
    if mod is None:
        return False, "không có bin/suite_cache.py"
    return mod.cacheable(test, bool(DEVICE_SUITE.search((test or {}).get("command") or "")))


def suite_keyable(test):
    """Được tính khoá cho suite ĐÃ ĐƯỢC CHỌN (cacheable, hay run_impacted.sh chuẩn của DevKit: theo khoá cả cây + tập chọn). Phần cached-full
    thêm vào vẫn chỉ dùng suite_cacheable: suite chọn theo lịch sử git không vào đó."""
    mod = suite_cache_mod()
    return suite_cacheable(test)[0] or bool(mod is not None and mod.selection_keyable(test or {}))


def suite_cache_for(project_dir, rules, matrix_path, covers):
    """SuiteCache của project_dir dựng y như lượt gate (cùng local_state_sha, RESULT_FORMAT, biến môi trường chọn test): khoá của
    stale_rerun.run_one (nightly) trùng khoá của gate. None khi tắt (DEVKIT_SUITE_CACHE=0) hoặc không dựng được."""
    mod = suite_cache_mod()
    if mod is None or os.environ.get("DEVKIT_SUITE_CACHE", "1") == "0":
        return None
    sc = mod.SuiteCache(project_dir, rules, matrix_path, covers, local_state_sha(project_dir), RESULT_FORMAT, _selection_env())
    return sc if sc.ok else None


def _head_sha(project_dir):
    """HEAD of project_dir, None when git cannot say (then nothing is re-used or recorded under a key that holds it)."""
    try:
        res = subprocess.run(["git", "-C", str(project_dir), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    out = res.stdout.strip()
    return out if res.returncode == 0 and re.fullmatch(r"[0-9a-f]{40,64}", out) else None


def cached_full_pass(project_dir, matrix_arg, fp=None, name=None, path=None):
    """The last full PASS when it still holds for this exact code (O1, 2026-09-28: GeelyEx2 ran
    16 full gates in one session, many on content that had already passed): same tree
    fingerprint, same RESULT_FORMAT, same matrix, tested within DEVKIT_GATE_CACHE_MAX_S (default
    6 h — ignored files, devices and the network can drift). None otherwise. An UNTESTED full run
    (exit 4, its "untested" ids ended with their matrix untested_exit) counts for its PASS suites
    only: reuse_full_pass runs the untested ones again (2026-09-29, GeelyEx2). An UNVERIFIED run (exit 2, no suite
    failed: an edited test waits for review, a code file nothing covers) is kept the same way (2026-10-07).
    fp: the tree fingerprint the caller took a moment ago with nothing run since (A13, 2026-10-09: a --full run took it
    three times); None takes it here.
    name: another record kept next to the receipt under the same keys (BUDGET_RECORD); None = the full-pass receipt itself.
    path: đọc biên nhận ở file này thay cho biên nhận của chính git dir (biên nhận của worktree anh em, sibling_receipts); mọi kiểm
    tra bên dưới vẫn so với project_dir."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sibling = bool(path) and name is None   # trước khi path bị gán biên nhận của chính git dir bên dưới
    # #247: một mục của store theo cây (<common>/postfix-gate/tree_receipts/<fp>.json), không phải full_pass.json của một worktree
    from_store = sibling and os.path.basename(os.path.dirname(path)) == TREE_STORE_DIR
    try:
        import tree_fp  # noqa: PLC0415 - sibling module in bin/
        path = path or tree_fp.receipt_path(project_dir)
        if name:
            path = os.path.join(os.path.dirname(path), name)
        r = _load_state_json(path)
        max_s = float(os.environ.get("DEVKIT_GATE_CACHE_MAX_S", "21600"))
    except (ImportError, OSError, ValueError, TypeError, OverflowError, RecursionError):
        return None   # RecursionError: a forged file nested deeper than json.load can read (it is a RuntimeError, not a ValueError)
    if not isinstance(r, dict) or not isinstance(r.get("tests"), list) or not r["tests"]:
        return None
    # T0061 Pha 1: biên nhận task (`scope` "task", lượt --run-tests không --full) không bao giờ thay biên nhận --full, ở mọi nguồn hàm này
    # đọc (của chính git dir, của worktree anh em, mục store, BUDGET_RECORD); tests/gates/test_task_receipt_doors.sh ca 1
    if r.get("scope", "full") != "full":
        return None
    if r.get("exit") not in (0, 2) and not (r.get("exit") == 4 and r.get("untested") and isinstance(r["untested"], list)):
        return None
    # A time that is not a time (damaged or hand-written record) is no record: this used to raise (float("abc")) outside any try, and the Stop hook
    # lets the Stop through when the gate crashes; NaN / Infinity compared false against the age cap and were read. A time a minute ahead of this
    # clock is a forged or broken one; a few seconds are noise between two processes.
    def _time_ok(v):
        # a comparison of an int or a float with a float never raises (a 401-digit integer is compared exactly), and NaN / inf fail the bound: no
        # float() and no isfinite(), which raise OverflowError on that integer; the bound is far past any epoch
        return not isinstance(v, bool) and isinstance(v, (int, float)) and -1e15 < v < 1e15
    tested, now = r.get("tested_at"), time.time()
    if not _time_ok(tested) or tested > now + 60 or now - tested > max_s:
        return None
    if any(not isinstance(x, dict) or not (x.get("ran_at") is None or _time_ok(x.get("ran_at"))) for x in r["tests"]):
        return None   # reuse_from reads every suite's ran_at as a number
    # reuse_from also hashes every id and every untested entry (a list there raised TypeError, the gate crashed and the Stop hook lets the Stop
    # through when the gate crashes) and prints / stores the other fields: a field of a wrong type is no record, for the receipt and the Stop record
    def _str_or_none(v):
        return v is None or isinstance(v, str)
    if any(not isinstance(x.get("id"), str) or not all(_str_or_none(x.get(k)) for k in ("status", "log", "duration", "full_command")) for x in r["tests"]):
        return None
    if r.get("untested") is not None and not (isinstance(r["untested"], list) and all(isinstance(u, str) for u in r["untested"])):
        return None
    if r.get("result_format") != RESULT_FORMAT or r.get("matrix_sha") != _sha_file(find_matrix_path(matrix_arg)):
        return None
    if r.get("local_sha") in (None, "?"):
        return None
    regen = r.get("local_regen") or []
    if not (isinstance(regen, list) and all(isinstance(p, str) for p in regen)):
        return None
    try:
        regen = regen_allowed(regen)
    except Exception:   # as local_state_sha's "?": no reuse
        return None
    if sibling:
        # Biên nhận của worktree anh em (review 17/10): exit 0, và dòng run-log của chính lượt đã ghi nó phải là full với verdict PASS —
        # suite THẬT SỰ chạy, reused_full_pass False (_sibling_logged_pass). Lượt đã dùng lại (của mình hay của anh em, toàn bộ hay một
        # phần) không cho mượn tiếp: không có dây chuyền mà một FAIL sau đó của worktree gốc (chỉ xoá file của nó) không chặn được.
        # ponytail: một PASS đã từng là exit 2 rồi được dùng lại thành exit 0 (log REUSED) không cho mượn — merge gate chạy đủ như cũ;
        # nới khi đo thấy ca này chiếm phần lớn lượt chạy của merge gate.
        # carried_from: bản chép `worktree finish` đưa sang main — cũng là bản chép, không cho mượn
        if r.get("exit") != 0 or r.get("carried_from") or not isinstance(r.get("project"), str):
            return None
        # Lượt chạy suite thật ghi tested_at ngay lúc ghi biên nhận; lượt dùng lại (một phần hay toàn bộ) giữ tested_at của biên nhận cũ
        # (write_full_pass_receipt tested_at=cache["tested_at"]). Run-log chỉ có epoch làm tròn giây: một PASS thật cùng giây không phân biệt được.
        # "time" lấy trước "tested_at" vài µs trong cùng dict: hiệu hơi âm. _time_ok trước: số nguyên 400 chữ số trừ float là OverflowError.
        # Mục của store theo cây không phải qua hai luật "lượt chạy thật" này (#247): mọi lượt không-PASS trên cây xoá đúng mục đó (cùng khoá
        # fp, _tree_store), nên bản chép dây chuyền (lượt dùng lại ghi đè mục của lượt thật) không thoát khỏi một FAIL; tested_at cũ giữ nguyên
        # qua mỗi lượt dùng lại nên tuổi tối đa vẫn tính từ lần chạy thật. Các kiểm tra còn lại (cây, ma trận, định dạng, local_sha) vẫn áp.
        if not from_store and (not _time_ok(r.get("time")) or not (-1 <= r["time"] - tested < 5)):
            return None
    if name and (not r.get("head") or r.get("head") != _head_sha(project_dir)):
        return None   # a Stop record also names the HEAD it was taken at: a commit (the fingerprint does not see one) is a new state
    if name and r.get("env") != _selection_env():
        return None   # ... and the environment that selects what a "full" suite runs; a record without it (an older one) is not read
    # Both must match: the cheap one first (tree_fp 0.25 s, local_state_sha 0.7-6.4 s), so an edited tree never pays for it.
    fp = fp or tree_fp.tree_fingerprint(project_dir)
    if not fp or r.get("fingerprint") != fp:
        return None
    if sibling and not from_store and not _sibling_logged_pass(path, r):   # sau phép so fingerprint (rẻ): chỉ biên nhận đúng nội dung mới đọc run-log
        return None
    # local_state_sha(project_dir) alone when nothing was rewritten: the one-argument call is the seam tests stub (test_gate_stop_run_record A10)
    return r if r.get("local_sha") == (local_state_sha(project_dir, regen) if regen else local_state_sha(project_dir)) else None


SIBLING_RECEIPTS_MAX = 32


def _run_log_records(logdir):
    """Các dòng của <logdir>/runs.jsonl (4 MiB cuối) theo thứ tự ghi, chỉ dict có "epoch" là int; None khi không đọc được (không có file,
    không phải file thường, lỗi đọc): người gọi coi None là "không biết" và không mượn."""
    try:
        fd = os.open(os.path.join(logdir, RUN_LOG_NAME), os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return None
        n = min(st.st_size, 4 << 20)
        raw = os.pread(fd, n, st.st_size - n)
    except OSError:
        return None
    finally:
        os.close(fd)
    out = []
    for line in raw.splitlines():
        try:
            rec = json.loads(line)
        except (ValueError, RecursionError):   # RecursionError: một dòng lồng quá sâu (file ai cũng ghi được) — bỏ qua, không crash gate
            continue
        if isinstance(rec, dict) and isinstance(rec.get("epoch"), int) and not isinstance(rec.get("epoch"), bool):
            out.append(rec)
    return out


def _ever_gated(project_dir):
    """True khi run-log của repo đã có dòng của thư mục này, hoặc không đọc được run-log (review 17/10, P1): mọi lượt exit ≠ 0 xoá biên nhận
    của chính nó, nên "chưa có biên nhận" không có nghĩa "chưa từng chạy" — một thư mục vừa FAIL không được mượn PASS của anh em. Scratch
    của merge gate (`mktemp -d`, tên mới) chưa có dòng nào. Lượt bị kill / crash trước khi ghi dòng log (dòng log ghi ở cuối main()) vẫn để
    lại .claude/audit-gate/test_run.lock (acquire_test_run_lock tạo trước khi chạy suite): có file đó cũng là đã từng chạy (review 17/10).
    File đó còn do testsourceset_gate.sh, worktree.py (_test_run_lock) và stale_rerun.py tạo (OCR 17/10): một worktree của agent có thể
    bị coi là đã chạy dù chưa — hướng an toàn (chạy suite). Scratch của merge gate không có công cụ nào trong số đó chạy trước gate.
    ponytail: dòng cũ bị xoay vòng khỏi runs.jsonl (RUN_LOG_MAX_BYTES / RUN_LOG_KEEP_*) thì quên; giữ danh sách thư mục đã chạy riêng nếu gặp."""
    if os.path.lexists(os.path.join(str(project_dir), ".claude", "audit-gate", "test_run.lock")):
        return True
    try:
        gd = _git_static(project_dir, "--absolute-git-dir")
    except (ImportError, OSError, subprocess.SubprocessError):
        return True
    recs = _run_log_records(_run_log_dir(os.fsdecode(gd))) if gd is not None else None
    name = os.path.basename(str(project_dir))[:64]
    return recs is None or any(rec.get("project") == name for rec in recs)


def _run_log_fp(value):
    """24 hex, hoặc rỗng. Hai dấu chỉ so khi cả hai đúng dạng này: dòng cũ không có `fp` không bị coi là lệch."""
    return value if isinstance(value, str) and re.fullmatch(r"[0-9a-f]{24}", value) else ""


def _sibling_logged_pass(path, r):
    """True khi dòng run-log ĐẦU TIÊN của project biên nhận r ghi sau thời điểm ghi biên nhận (trong 900 s) là chính lượt đã ghi nó
    (_log_gate_run chạy ngay sau write_full_pass_receipt) và là full / exit 0 / verdict PASS: suite thật sự chạy. Không chỉ "có một dòng
    PASS gần đó" (OCR 17/10: một PASS thật trên nội dung khác ít phút trước sẽ bảo lãnh cho biên nhận của một lượt REUSED). Lỗi đọc = False.
    Hai worktree cùng basename ghi chung tên project: dòng và biên nhận đều có fingerprint mà khác nhau thì không mượn. Dòng cũ không
    có `fp`, hoặc biên nhận không có fingerprint, giữ luật cũ."""
    try:
        t, name = float(r["time"]), os.path.basename(str(r["project"]))[:64]
    except (KeyError, TypeError, ValueError, OverflowError):
        return False
    receipt_fp = _run_log_fp(r.get("fingerprint"))
    for rec in _run_log_records(_run_log_dir(os.path.dirname(os.path.dirname(path)))) or ():   # path = <git dir>/postfix-gate/full_pass.json
        epoch = rec.get("epoch")   # theo thứ tự ghi: dòng đầu tiên của project này từ lúc ghi biên nhận
        if rec.get("project") != name or epoch < int(t):
            continue
        line_fp = _run_log_fp(rec.get("fp"))
        if line_fp and receipt_fp and line_fp != receipt_fp:
            return False   # cùng tên project, khác cây: không bảo lãnh
        return (epoch <= t + 900 and rec.get("mode") == "full" and rec.get("exit") == 0 and not isinstance(rec.get("exit"), bool)
                and rec.get("verdict") == "PASS" and rec.get("reused_full_pass") is False)   # lượt dùng lại một phần cũng log PASS
                # (một suite chạy thật) nhưng mang PASS mượn: không cho mượn tiếp (review + OCR 17/10). Dòng không có field: không mượn.
    return False


TREE_STORE_DIR = "tree_receipts"   # tree_fp.tree_receipt_dir: <git common dir>/postfix-gate/tree_receipts


def tree_store_receipts(project_dir, fp):
    """[<store>/<fp>.json] khi mục store của đúng cây `fp` là file thường (#247: PASS của builder còn đó sau khi worktree của nó bị gỡ,
    full_pass.json đi theo git dir nên sibling_receipts không thấy), [] nếu không. Không đọc nội dung: cached_full_pass kiểm."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import tree_fp  # noqa: PLC0415 - sibling module in bin/
        store = tree_fp.tree_receipt_dir(project_dir)
    except (ImportError, OSError, subprocess.SubprocessError):
        return []
    if not store or not re.fullmatch(r"[0-9a-f]{24}", fp or ""):
        return []
    p = os.path.join(store, fp + ".json")
    try:
        return [p] if stat.S_ISREG(os.lstat(p).st_mode) else []   # chỉ file thường (INSTINCT-040)
    except OSError:
        return []


def sibling_receipts(project_dir):
    """Biên nhận full-pass của main checkout và các worktree KHÁC của cùng repo, mới nhất trước (tối đa SIBLING_RECEIPTS_MAX).
    17/10 (agent-workbench): merge gate super-board chạy gate trong một scratch `git worktree add` — git dir mới, không có biên nhận —
    nên chạy lại mọi suite dù worktree của agent vừa PASS đúng nội dung đó (19 lần/ngày, 154 phút, 0 lần dùng lại). Biên nhận anh em do
    cùng gate ghi vào cùng .git; cached_full_pass vẫn kiểm đủ nội dung, tuổi, ma trận, trạng thái cục bộ trước khi dùng. [] khi git
    không trả lời."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import tree_fp  # noqa: PLC0415 - sibling module in bin/
        own = tree_fp.receipt_path(project_dir)
        common_b = tree_fp.rev_parse_static(project_dir, "--path-format=absolute", "--git-common-dir")
    except (ImportError, OSError, subprocess.SubprocessError):
        return []
    common = os.fsdecode(common_b) if common_b else ""
    if not common:
        return []
    dirs = [common]
    try:
        with os.scandir(os.path.join(common, "worktrees")) as it:
            dirs += [e.path for e in it if e.is_dir(follow_symlinks=False)]
    except OSError:
        pass
    found = []
    for d in dirs:
        p = os.path.join(d, "postfix-gate", tree_fp.RECEIPT)
        if own and os.path.realpath(p) == os.path.realpath(own):
            continue
        try:
            st = os.lstat(p)
        except OSError:
            continue
        if stat.S_ISREG(st.st_mode):   # chỉ file thường: symlink / FIFO không phải biên nhận gate ghi (INSTINCT-040)
            found.append((st.st_mtime_ns, p))
    return [p for _, p in sorted(found, reverse=True)[:SIBLING_RECEIPTS_MAX]]


# Modes that ran a subset of a suite's command, or nothing: never a full PASS — no PASS row in
# the checklist, no full-pass receipt (audit 2026-09-28: a RESOURCE run that ran nothing and a
# PACKAGE subset were both stamped as a full PASS, and a later --full reused them).
PARTIAL_MODES = ("impacted", "resource", "package", "module")


def tree_fp_of(project_dir):
    """The tree fingerprint (bin/tree_fp.py) of project_dir now; "" when it cannot be taken."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import tree_fp  # noqa: PLC0415 - sibling module in bin/
    except ImportError:
        return ""
    return tree_fp.tree_fingerprint(project_dir)


# T0061 Pha 1 — biên nhận task: lượt CLI `--run-tests` (không --full) exit 0 trên worktree / nhánh không phải nhánh đích, đã kiểm trọn
# merge-base(<trunk>, HEAD) → cây hiện tại. Cách ly khỏi biên nhận --full: <git dir>/postfix-gate/task_pass.json và
# <git common dir>/postfix-gate/task_receipts/<fp>.json, {"scope": "task", "fp", "tested_at", "diff_base", "session"}. Chỉ hooks/proof_gate.sh
# đọc nó (XONG trong đúng lượt); mọi cửa đọc biên nhận --full từ chối scope task (tests/gates/test_task_receipt_doors.sh).
TASK_RECEIPT = "task_pass.json"
TASK_STORE_DIR = "task_receipts"


def task_trunk(project_dir):
    """(ref, tên nhánh) của nhánh đích: refs/remotes/origin/HEAD → origin/{main,master,trunk} → refs/heads/{main,master,trunk};
    (None, None) khi không đọc được."""
    def ok(ref):
        return subprocess.run(["git", "-C", str(project_dir), "rev-parse", "--verify", "-q", ref + "^{commit}"],
                              capture_output=True, timeout=30).returncode == 0
    try:
        r = subprocess.run(["git", "-C", str(project_dir), "symbolic-ref", "-q", "refs/remotes/origin/HEAD"],
                           capture_output=True, text=True, timeout=30)
        head = r.stdout.strip()
        if r.returncode == 0 and head.startswith("refs/remotes/origin/") and ok(head):
            return head, head[len("refs/remotes/origin/"):]
        for prefix in ("refs/remotes/origin/", "refs/heads/"):
            for name in ("main", "master", "trunk"):
                if ok(prefix + name):
                    return prefix + name, name
    except (OSError, subprocess.SubprocessError) as e:
        log_warn(f"task receipt: nhánh đích không đọc được ({e})")
    return None, None


def _task_paths(project_dir):
    """(task_pass.json của git dir này, thư mục store dùng chung) — (None, None) ngoài git."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import tree_fp  # noqa: PLC0415 - sibling module in bin/
    own, shared = tree_fp.receipt_path(project_dir), tree_fp.tree_receipt_dir(project_dir)
    if not own or not shared or os.path.basename(os.path.dirname(os.path.dirname(own))) == "audit-gate":   # non-git: không biên nhận task
        return None, None
    return os.path.join(os.path.dirname(own), TASK_RECEIPT), os.path.join(os.path.dirname(shared), TASK_STORE_DIR)


def write_task_receipt(project_dir, fp, diff_base, session):
    """Ghi biên nhận task khi cây vẫn là cây đã kiểm (fp lấy trước khi suite chạy). Lỗi ghi chỉ là cảnh báo: không đổi kết luận."""
    import tree_fp  # noqa: PLC0415 - sibling module in bin/ (_task_paths đã đưa bin/ vào sys.path)
    own, _ = _task_paths(project_dir)
    if not own or not re.fullmatch(r"[0-9a-f]{24}", fp or "") or tree_fp.tree_fingerprint(project_dir) != fp:
        return False
    data = {"scope": "task", "fp": fp, "tested_at": time.time(), "diff_base": diff_base, "session": session}
    try:
        os.makedirs(os.path.dirname(own), exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".tmp_task.", dir=os.path.dirname(own))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(data, f)
            os.replace(tmp, own)
        except OSError:
            with contextlib.suppress(OSError):
                os.remove(tmp)
            raise
    except OSError as e:
        log_warn(f"task receipt ({own}): {e}")
        return False
    _tree_store(tree_fp, project_dir, fp, data, kind=TASK_STORE_DIR)
    return True


def drop_task_receipt(project_dir, fp):
    """Một lượt exit 1 trên cây fp: bỏ mục store của cây đó và task_pass.json của git dir này nếu nó nói về cây đó."""
    try:
        own, _ = _task_paths(project_dir)
    except ImportError:
        return
    if not own or not re.fullmatch(r"[0-9a-f]{24}", fp or ""):
        return
    import tree_fp  # noqa: PLC0415 - sibling module in bin/
    _tree_store(tree_fp, project_dir, fp, None, kind=TASK_STORE_DIR)
    try:
        kept = _load_state_json(own)
    except (OSError, ValueError, RecursionError, OverflowError):
        kept = None
    if isinstance(kept, dict) and kept.get("fp") == fp:
        with contextlib.suppress(FileNotFoundError):
            os.remove(own)


def head_and_dirty(project_dir):
    """(HEAD sha, {path from the repo root: blob sha, or None when deleted}) of every file that
    differs from HEAD: what bin/push_gate.py compares a push against. (None, {}) on a git error."""
    # Paths decoded with surrogateescape, as everywhere else: a non-UTF-8 name crashed text=True here, AFTER the gate
    # printed PASS (A8, 2026-10-09). Such a key reaches the receipt as a \udcXX escape (json's ensure_ascii).
    run = lambda *a: subprocess.run(["git", "-C", str(project_dir), *a], capture_output=True)
    top, head = run("rev-parse", "--show-toplevel"), run("rev-parse", "HEAD")
    if top.returncode or head.returncode:
        return None, {}
    top = os.fsdecode(top.stdout.strip())
    names = sorted({p for args in (("diff", "--name-only", "-z", "HEAD"), ("ls-files", "-o", "--exclude-standard", "-z"))
                    for p in subprocess.run(["git", "-C", top, *args], capture_output=True).stdout
                    .decode("utf-8", errors="surrogateescape").split("\0") if p})
    present = [p for p in names if os.path.isfile(os.path.join(top, p))]
    shas = subprocess.run(["git", "-C", top, "hash-object", "--stdin-paths"], capture_output=True,
                          input="\n".join(present).encode("utf-8", "surrogateescape")).stdout.decode().split() if present else []
    if len(shas) != len(present):
        return None, {}
    dirty = dict.fromkeys(names)
    dirty.update(zip(present, shas))
    return head.stdout.decode().strip(), dirty


def dirty_links(project_dir, dirty):
    """#156: {đường dẫn: blob của CHUỖI link} cho mỗi đường dẫn của `dirty` (từ gốc repo, như trong biên nhận) đang là symlink tới một
    file, đúng cái `git add` của bin/tree_fp.py ghi cho nó (mode 120000). `dirty` giữ blob NỘI DUNG file đích (hash-object đi theo link)
    để push_gate so với file sắp push; push_gate dựng lại dấu vân tay bằng mục này thay vì đoán theo đĩa của checkout nó đang chạy (main
    sau `worktree finish`: file thường đã track, chỗ gate thấy link của DevKit). Link tới thư mục hoặc link treo (`dirty` null: không có
    nội dung để so) không bao giờ vào đây: push_gate dựng nó như file đã xoá và từ chối như trước #156 (review principal, L25c).
    OSError (link đổi giữa chừng): caller không ghi biên nhận."""
    run = lambda *a: subprocess.run(["git", "-C", str(project_dir), *a], capture_output=True)
    top = run("rev-parse", "--show-toplevel") if dirty else None
    if top is None or top.returncode:
        return {}
    top = os.fsdecode(top.stdout.strip())
    texts = {p: os.readlink(os.fsencode(os.path.join(top, p))) for p, sha in dirty.items()
             if sha is not None and os.path.islink(os.path.join(top, p))}
    if not texts:
        return {}
    algo = run("rev-parse", "--show-object-format").stdout.decode().strip()   # repo object-format=sha256 thì blob id là sha256
    algo = algo if algo in ("sha1", "sha256") else "sha1"
    return {p: hashlib.new(algo, b"blob %d\0" % len(t) + t).hexdigest() for p, t in texts.items()}


def _tree_store(tree_fp, project_dir, fp, data=None, create=True, kind=TREE_STORE_DIR):
    """#105 (trunk mode): mirror of the receipt in <git common dir>/postfix-gate/tree_receipts/<fp>.json. A worktree's own receipt goes with
    its git dir when the worktree is removed, so proof_gate finds the full PASS of the tree a session delivered into main (finish, squash
    PR) here. data: the exit-0 receipt; None: drop the entry, any other verdict on that tree. fp None: the tested tree, fingerprinted only when the store holds something. Only the
    entry of that one tree is touched; a write prunes entries older than TREE_RECEIPT_MAX_AGE_S or beyond the TREE_RECEIPT_MAX newest.
    create False (#247, a run that re-used a PASS): only refreshes an entry that is there. A FAIL on the tree removes its entry, and a copy
    carrying a re-used PASS must never put it back (principal review 22/10, P1: wt-b FAILs, wt-c re-runs on its own receipt, a new worktree borrows).
    kind: thư mục anh em dưới <git common dir>/postfix-gate/ (T0061: TASK_STORE_DIR giữ biên nhận task, tách hẳn khỏi tree_receipts)."""
    store = None
    try:
        store = tree_fp.tree_receipt_dir(project_dir)
        if store and kind != TREE_STORE_DIR:
            store = os.path.join(os.path.dirname(store), kind)
        if not store or (data is None and not fp and not (os.path.isdir(store) and any(n.endswith(".json") for n in os.listdir(store)))):
            return
        fp = fp or tree_fp.tree_fingerprint(project_dir)
        if not re.fullmatch(r"[0-9a-f]{24}", fp or ""):
            return
        path = os.path.join(store, fp + ".json")
        if data is None:
            with contextlib.suppress(FileNotFoundError):
                os.remove(path)
            return
        if not create and not os.path.isfile(path):
            return
        os.makedirs(store, exist_ok=True)
        text = json.dumps(data)
        fd, tmp = tempfile.mkstemp(prefix=".tmp_tree.", dir=store)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(text)
            os.replace(tmp, path)
        except OSError:   # full disk…: the prune below only sees *.json, so a temp left here would stay in the shared store
            with contextlib.suppress(OSError):
                os.remove(tmp)
            raise
        now = time.time()
        kept = []
        for e in os.scandir(store):
            if e.name.endswith(".json"):
                with contextlib.suppress(FileNotFoundError):   # another run pruned it between scandir and stat
                    kept.append((e.stat(follow_symlinks=False).st_mtime, e.path))
        for i, (mtime, p) in enumerate(sorted(kept, reverse=True)):
            if i >= tree_fp.TREE_RECEIPT_MAX or now - mtime > tree_fp.TREE_RECEIPT_MAX_AGE_S:
                with contextlib.suppress(FileNotFoundError):   # another run pruned it first
                    os.remove(p)
    except (OSError, ValueError) as e:   # never the gate's verdict: proof_gate then falls back to the worktree's own receipt
        log_warn(f"tree receipt store ({store}): {e}")


def write_full_pass_receipt(project_dir, exit_code, matrix_arg=None, tests=None, tested_at=None, tested_fp=None,
                            untested=None, partial=False, locked=True, keep_same=False, refresh_only=False):
    """After a full regression run: drop the previous receipt, and on exit 0 record
    {time, fingerprint} of the audited code in .git/postfix-gate/full_pass.json (outside the
    tree). hooks/proof_gate.sh accepts an XONG only with a receipt from this turn whose
    fingerprint still matches the code (bin/tree_fp.py). tested_fp is the fingerprint taken
    before the suites ran: code that changed during the run was not the code tested.
    untested: the ids of an UNTESTED exit 4 (untested_exit, never BUSY) — recorded with "exit": 4
    so cached_full_pass reuses the suites that passed (2026-09-29, GeelyEx2: no receipt at all,
    every --full re-ran them); proof_gate and push_gate still accept only "exit": 0.
    An UNVERIFIED exit 2 whose suites all passed or could not run (an edited test waits for review, a code file nothing
    covers) says nothing about the suites: it keeps them reusable the same way, as "exit": 2 (2026-10-07, OfficeReader and
    GeelyEx2: every --full after an exit 2 ran all the suites again). A FULL run records its own results; a PARTIAL run
    (the Stop hook: only a subset ran) turns the receipt of the same code from exit 0 to 2, so XONG and push are refused
    as before while its suites stay reusable; a receipt of other code is dropped.
    locked: the run holds test_run.lock (False: it waited and did not get it, or it never asked: it re-used and ran nothing). A run without the lock
    may only DROP a receipt, never replace it (F1, see the partial branch).
    keep_same (#154): the run is the merge gate of `worktree finish` — its UNVERIFIED exit 2 leaves an exit-0 receipt of the SAME
    content as it is (what the session owes is its own gate's business); a receipt of other content is still dropped.
    refresh_only (#247): the run re-used a PASS — its tree store entry is refreshed when there, never created (see _tree_store)."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import tree_fp  # noqa: PLC0415 - sibling module in bin/
    except ImportError:
        return
    path = tree_fp.receipt_path(project_dir)
    if not path:
        return
    unverified_ok = exit_code == 2 and not any(
        t.get("status") not in ("PASS", "UNTESTED", "BUSY") for t in (tests or []) if t.get("command"))
    if partial and unverified_ok:
        run_fp = tested_fp or tree_fp.tree_fingerprint(project_dir)   # once: the store drop and the receipt below both need it
        if keep_same:
            try:
                kept = _load_state_json(path)
            except (OSError, ValueError, RecursionError, OverflowError):
                kept = None   # unreadable: handled below as before (dropped)
            if run_fp and isinstance(kept, dict) and kept.get("fingerprint") == run_fp and kept.get("exit") == 0:
                return   # #154: the session's --full of this very content stands, and its tree store entry with it
        _tree_store(tree_fp, project_dir, run_fp)   # exit 2 on the tested tree: its exit-0 entry goes, as this receipt below
        try:
            kept = _load_state_json(path)
            same = isinstance(kept, dict) and kept.get("fingerprint") == run_fp
            if same and kept.get("exit") == 0 and not locked:
                # F1: no load-then-replace without the lock. A forced run that holds it and FAILS a suite deletes this file; between this run's load
                # and its replace that deletion would be undone, and the receipt would come back as exit 2 with the failing suite's PASS (which
                # cached_full_pass accepts: the next --full re-used it and wrote an exit-0 receipt). Dropping the file cannot put a PASS back.
                # Dropped, not left alone: this run's verdict (exit 2) contradicts an exit-0 receipt of the same content, and XONG / push read that
                # file, so it must not stay exit 0 whether or not the lock was free (a locked run turns it down to exit 2 below).
                # ponytail: the suites of that receipt are lost to the next --full (it runs them all); take the lock once without waiting here and
                # turn the receipt down under it when that re-run is seen to cost more than the extra step is worth.
                os.remove(path)
            elif same and kept.get("exit") == 0:
                kept.update({"exit": 2, "untested": []})
                text = json.dumps(kept)   # BEFORE the temp file: a value json cannot write (nested too deep) raised here and left .tmp_full_pass.* behind
                fd, tmp = tempfile.mkstemp(prefix=".tmp_full_pass.", dir=os.path.dirname(path))
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(text)
                os.replace(tmp, path)
            elif not same:
                os.remove(path)
        except (OSError, ValueError, RecursionError, OverflowError):   # a forged receipt nested deeper than json can read: dropped, as an unreadable one is
            try:
                os.remove(path)
            except OSError:
                pass
        return
    if exit_code != 0 and not (exit_code == 4 and untested) and not unverified_ok:
        try:
            os.remove(path)
        except OSError:
            pass
        _tree_store(tree_fp, project_dir, tested_fp)
        return
    fingerprint = tree_fp.tree_fingerprint(project_dir)
    if tested_fp is not None and fingerprint != tested_fp:
        log_warn(tr("Code đổi trong lúc chạy test — không ghi biên nhận PASS đầy đủ (XONG sẽ bị proof_gate chặn): chạy lại gate",
                    "Code changed while the suites ran — no full-pass receipt (proof_gate will refuse XONG): run the gate again"))
        if exit_code == 2:   # as before this change: a non-zero run leaves no receipt of the code it did not test
            try:
                os.remove(path)
            except OSError:
                pass
        if exit_code != 0:   # exit 4 too: the tested tree's exit-0 entry does not outlive a verdict that is not a pass
            _tree_store(tree_fp, project_dir, tested_fp)
        return
    if not fingerprint:   # proof_gate never matches an empty one: say why XONG will be refused
        log_warn(tr(f"Không tính được dấu vân tay code — XONG sẽ bị proof_gate chặn: {getattr(tree_fp.tree_fingerprint, 'error', '') or 'git add thất bại'}",
                    f"Code fingerprint unavailable — proof_gate will refuse XONG: {getattr(tree_fp.tree_fingerprint, 'error', '') or 'git add failed'}"))
    if exit_code != 0:   # exit 4 / 2: dropped BEFORE the write below, which may fail and must not leave this tree's exit-0 entry behind
        _tree_store(tree_fp, project_dir, fingerprint)
    try:
        head, dirty = head_and_dirty(project_dir)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        try:
            known = known_generated(path)
            now_files = local_state_files(project_dir) if LOCAL_STATE_BEFORE is not None or known else None
            seen = local_regen(LOCAL_STATE_BEFORE, now_files)
            # only a file rewritten IN PLACE is a build output to remember: one the suites created (made once when missing: a key, a
            # prebuilt) is a real input from then on (review 18/10, P2); it still stays out of THIS receipt (seen)
            rewritten = [p for p in seen if p in LOCAL_STATE_BEFORE and p in now_files]
            if rewritten:
                remember_generated(path, rewritten)
            regen = regen_allowed(set(seen) | set(known))
        except Exception as e:   # no list of rewritten files: local_sha below covers every file, as before
            log_warn(f"local_state_files: {e}")
            now_files, regen = None, []
        local_sha = local_state_sha(project_dir, regen, now_files) if now_files is not None else local_state_sha(project_dir)
        data = {"time": time.time(), "exit": exit_code, "project": str(Path(project_dir).resolve()),
                "fingerprint": fingerprint, "tested_at": tested_at or time.time(),
                "result_format": RESULT_FORMAT,
                "gate_sha": _sha_file(__file__), "matrix_sha": _sha_file(find_matrix_path(matrix_arg)),
                "local_sha": local_sha, "local_regen": regen, "head": head, "dirty": dirty, "links": dirty_links(project_dir, dirty),
                "tests": [{"id": t.get("id"), "status": t.get("status"), "log": t.get("log"),
                           "duration": t.get("duration"), "ran_at": SUITE_RAN_AT.get(t.get("id"))}
                          for t in (tests or []) if t.get("command")]}
        if exit_code != 0:
            # exit 2 names its UNTESTED suites like exit 4 (REG-QC-05 is UNTESTED by design): reuse_full_pass needs every other
            # suite PASS, so without the ids one such suite would cancel the whole reuse
            data["untested"] = sorted(untested or ({t.get("id") or "?" for t in (tests or []) if t.get("command") and t.get("status") == "UNTESTED"}
                                                   if exit_code == 2 else []))
        text = json.dumps(data)   # before the temp file, as above
        fd, tmp = tempfile.mkstemp(prefix=".tmp_full_pass.", dir=os.path.dirname(path))
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
        if exit_code == 0:
            _tree_store(tree_fp, project_dir, fingerprint, data, create=not refresh_only)
    except OSError as e:
        log_err(f"full-pass receipt not written: {e}")


def head_tree(project_dir):
    """The tree object HEAD points at ('' when git cannot say): taken BEFORE a run, it names the tree that run tested."""
    try:
        r = subprocess.run(["git", "-C", str(project_dir), "rev-parse", "HEAD^{tree}"], capture_output=True, text=True, timeout=15)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def mark_merge_gate_receipt(project_dir, diff_ref, tested_tree="", relaxing=()):
    """#319: a --full PASS against origin/<base> on a clean tree that holds it is also the merge gate's verify of this tree: the board's
    super-board-verify-cmd.sh --mark writes the tree receipt under the key the merge gate reads (one key function, not copied here), so a PR runs
    --full once instead of twice. It refuses a dirty tree or a base not in the tree itself; no board config or script = the old behaviour."""
    # OCR 24/10: not a receipt for what this run did not prove: no tree taken before the run, or a run that relaxed a check (`relaxing`: the
    # --allow-no-tests / --allow-orphan-tests / --auto-approve-tests flags it used, DEVKIT_AUTO_APPROVE_TESTS=1 as the last) that the board's
    # verify line does not carry itself — the merge gate runs that line, so a flag it carries relaxes both runs the same way. Since #605
    # --auto-approve-tests approves nothing (self-approval) and this repo's verify line no longer carries it; an edited test reaches the merge
    # gate's scratch only through a committed `Test-approved-by: antigravity <task-id>` trailer.
    # ponytail: a custom --matrix is not compared with the verify command's (it has none); compare when a board's gate line names its matrix.
    if not diff_ref or not diff_ref.startswith("origin/") or not tested_tree:
        return
    root = Path(project_dir)
    script = root / ".claude" / "bin" / "super-board-verify-cmd.sh"
    configs = sorted((root / ".claude" / "super-board" / "configs").glob("*.json"))
    if not script.is_file() or len(configs) != 1:
        return
    try:
        cfg = json.loads(configs[0].read_text(encoding="utf-8"))
        if not isinstance(cfg, dict):   # valid JSON that is not an object (a half-written `[]`, `null`): no board config = the old behaviour
            return
        base = cfg.get("base_branch") or "main"
        if diff_ref != f"origin/{base}":
            return
        # Whole tokens of the line as the shell reads it (a flag inside a `# comment` or glued into a longer word is not carried by it).
        carried = set()
        verify = cfg.get("verify_commands")   # any JSON type can sit here (5, true, a dict): only a list of strings is a verify list
        for c in (verify if isinstance(verify, list) else []):
            if not isinstance(c, str):
                continue
            try:
                carried.update(shlex.split(c, comments=True))
            except ValueError:   # an unbalanced quote: the line cannot be read as the shell does, so it carries nothing
                pass
        if any(flag not in carried for flag in relaxing):
            return
        r = subprocess.run(["bash", str(script), "--config", str(configs[0]), "--mark", "--tree", tested_tree], cwd=str(root),
                           capture_output=True, text=True, timeout=30)
        # #459: a verify-cmd.sh that predates --mark (an app repo not yet ported) rejects it with exit 64 and a usage text that never names --mark:
        # that is "no script that can write a receipt" (the old behaviour), not a fault. A script that knows --mark names it in every 64 message.
        old_script = r.returncode == 64 and "--mark" not in r.stderr
        if r.returncode not in (0, 65) and not old_script:   # 65 = dirty tree / base not merged: the documented "no receipt"
            log_err(f"tree receipt not written (exit {r.returncode}): {r.stderr.strip()[-200:]}")
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        log_err(f"tree receipt not written: {e}")


# What a Stop run that spent GATE_TOTAL_BUDGET_S leaves for the next Stop on the same content (Goods, 2026-10-14: REG-GAME-02 +
# REG-GAME-03 took 901-967 s of a 900 s budget, REG-GAME-04 never started, and the next four Stops on the same fingerprint ran
# both again from the start: 63 min in 72 h). The Stop hook has no --full, so its run is "partial" and never records its own suite
# results (write_full_pass_receipt is for a full run, and a budget cut left even a valid receipt alone on purpose). A record of its
# own, next to the receipt and never in it: proof_gate and push_gate read only full_pass.json, so a budget run can never be a
# handover PASS, and test_busy_keeps_receipt still sees full_pass.json byte for byte. cached_full_pass reads it under the same keys
# (fingerprint, matrix, local state, format, age); reuse_full_pass applies the same per-suite rules (device suites, Unity age).
# ponytail: only a run with no force_reason (the Stop hook; also a --full that was deferred for sibling sessions, which ends
# exit 5 and writes no receipt) reads it, so an acceptance run never rests on a Stop run's results; allow a forced run to read it
# (drop `force_reason` in reuse_full_pass) when the extra handover run is ever seen to cost more than that trust is worth.
# 2026-10-15: not only a budget cut writes it: a Stop that ends exit 2 (an edited test waits for a person) or exit 4 (a suite cannot run here)
# used to record nothing, so after the hook's 300 s reminder window, or in another session, every suite ran again on the same content
# (Neighbours 13/10: 243 s to print the same reminder). It is written by a run that has no force_reason, ended with an exit code other than 0, had
# no FAIL / TIMEOUT suite, started at least one suite itself, and took a tree fingerprint and a HEAD before its suites: that needs the cache on
# (not --no-cache, not DEVKIT_GATE_CACHE=0) and a time budget (GATE_TOTAL_BUDGET_S > 0: the Stop hook passes one, REGRESSION_GATE_BUDGET_S=0 takes
# it away, and a CLI run without the variable records nothing). The record also names the HEAD it was taken at (the fingerprint is blind to a
# commit of the same content) and the selection environment: a record without them, or of another HEAD, is never read. A FAIL still drops it.
# ponytail: a run with a FAILED suite records nothing, so a repeat of such a run re-runs the suites that passed in it; upgrade when the
# FAIL-then-same-content repeat is seen to cost more than the "a FAIL leaves nothing to re-use" rule is worth.
# ponytail: a record is read for up to DEVKIT_GATE_CACHE_MAX_S (6 h, as the receipt), so a suite that starts to fail on UNCHANGED content (a flaky
# test, a service that went away) stays unseen that long after an exit-2 reminder, where the hook's 300 s recheck used to run it again; give the
# record its own, shorter cap when such a miss is seen. An impacted-mode PASS (a suite run on the selected tests only) is never recorded, so a
# repeat of an impacted run still runs those suites (OfficeReader's exit-2 repeats are impacted runs); record the command run and the vacuity
# base to cover them.
BUDGET_RECORD = "budget_pass.json"
# Environment that changes WHICH tests a suite of mode "full" starts without changing its command (tests/run_impacted.sh reads it: 0 = a RED-proof
# sandbox, no commit counts as a change). The record names it and a run with another value does not read the record.
# ponytail: one name; a suite whose selection also reads the upstream or the clock (run_impacted.sh: the last hours of commits) is judged by the
# content and HEAD alone, so a window that moved with the clock only ever narrows; list more names here when a matrix suite reads another one.
SELECTION_ENV = ("DEVKIT_IMPACTED_SINCE",)


def _selection_env():
    return {k: os.environ.get(k) for k in SELECTION_ENV}
# the modes whose PASS means "the suite's FULL command passed on this content" (the same ones a full run's receipt records)
BUDGET_RECORD_MODES = ("full", "cached", "covered", "skip-compile")


def budget_untested_ids(tests):
    """Ids of the suites a budget record must NOT offer as PASS: everything that did not pass its FULL command in this run
    (BUDGET, UNTESTED, FAIL, TIMEOUT, a PASS of an impacted / package / module / resource run or of an unknown mode). The reader
    (reuse_full_pass) runs these again, as it does the "untested" ids of an exit-4 receipt."""
    return sorted({t.get("id") or "?" for t in tests or [] if t.get("command")
                   and not (t.get("status") == "PASS" and t.get("mode") in BUDGET_RECORD_MODES)})


def budget_record_path(project_dir):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import tree_fp  # noqa: PLC0415 - sibling module in bin/
    except ImportError:
        return None
    rp = tree_fp.receipt_path(project_dir)
    return os.path.join(os.path.dirname(rp), BUDGET_RECORD) if rp else None


def _result_file(project_dir, name):
    """The file a run re-uses results from: the full-pass receipt (name None) or the record `name` beside it. None when it cannot be named."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import tree_fp  # noqa: PLC0415 - sibling module in bin/
        rp = tree_fp.receipt_path(project_dir)
    except (ImportError, OSError, TypeError):
        return None
    return (os.path.join(os.path.dirname(rp), name) if name else rp) if rp else None


def _file_stamp(path):
    """(mtime_ns, size, inode, ctime_ns) of a file, None when it is gone or cannot be read: stat only, nothing is opened (a FIFO there must not
    block). mtime and size can be put back by a rewrite; a file moved over it has another inode and ctime, an in-place rewrite another ctime."""
    try:
        st = os.stat(path)
    except (OSError, TypeError, ValueError):
        return None
    return (st.st_mtime_ns, st.st_size, st.st_ino, st.st_ctime_ns)


def drop_budget_record(project_dir):
    """A suite FAILED or TIMED OUT on this content: an earlier record must not offer its older PASS again (never a FAIL item)."""
    path = budget_record_path(project_dir)
    try:
        if path:
            os.remove(path)
    except FileNotFoundError:
        pass
    except OSError as e:
        log_warn(tr(f"Không xoá được {BUDGET_RECORD}: {e}", f"Could not remove {BUDGET_RECORD}: {e}"))


def write_budget_record(project_dir, matrix_arg, tests, tested_fp, tested_at=None, head=None):
    """After a Stop-style run that ended without a FAIL (a budget cut, an edited test waiting for review, a suite that cannot run here):
    the suites that passed their full command, for the next Stop-style run on the same inputs.
    tested_fp is the fingerprint taken BEFORE the suites ran (a Stop run takes none otherwise): code that changed while they ran was
    not the code tested, so then nothing is written; head is the HEAD taken at the same moment (none: nothing is written, the reader
    refuses a record without one). Written atomically; read through _state_fd by cached_full_pass."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import tree_fp  # noqa: PLC0415 - sibling module in bin/
    except ImportError:
        return
    path = budget_record_path(project_dir)
    untested = budget_untested_ids(tests)
    if not path or not tested_fp or not head or not any(t.get("command") and t.get("id") not in untested for t in tests):
        return
    if tree_fp.tree_fingerprint(project_dir) != tested_fp:
        log_warn(tr("Code đổi trong lúc chạy test — không ghi kết quả của lượt hết ngân sách (lần Stop sau chạy lại)",
                    "Code changed while the suites ran — the budget run's results are not recorded (the next Stop runs them again)"))
        return
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        # "exit" is only what cached_full_pass checks: 4 + a non-empty untested list, or 2 (every suite passed, the verdict was UNVERIFIED)
        data = {"time": time.time(), "exit": 4 if untested else 2, "project": str(Path(project_dir).resolve()), "fingerprint": tested_fp,
                "tested_at": tested_at or time.time(), "result_format": RESULT_FORMAT, "head": head, "env": _selection_env(),
                "gate_sha": _sha_file(__file__), "matrix_sha": _sha_file(find_matrix_path(matrix_arg)),
                "local_sha": local_state_sha(project_dir), "untested": untested,
                "tests": [{"id": t.get("id"), "status": t.get("status"), "log": t.get("log"),
                           "duration": t.get("duration"), "ran_at": SUITE_RAN_AT.get(t.get("id")),
                           "full_command": t.get("full_command") or t.get("command")}   # the matrix command, not the impacted one a run planned
                          for t in tests if t.get("command")]}
        fd, tmp = tempfile.mkstemp(prefix=".tmp_budget_pass.", dir=os.path.dirname(path))
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, path)
    except OSError as e:
        log_err(f"budget record not written: {e}")


# Third-party code (a minified lib dropped into vendor/) is not ours to lint; the secret scan still reads it.
THIRD_PARTY_DIRS = ("vendor",)


def has_dir(rel_file: str, *names) -> bool:
    parts = rel_file.replace("\\", "/").split("/")[:-1]
    return any(p in names for p in parts)


def log_ok(msg):
    print(f"  {GREEN}✔{RESET} {msg}")

def log_warn(msg):
    print(f"  {YELLOW}⚠{RESET} {msg}")

def log_err(msg):
    print(f"  {RED}✖{RESET} {msg}")

def get_devkit_dir() -> Path:
    return Path(__file__).resolve().parent.parent

_PROJECT_DIRS = {}


def get_project_dir() -> Path:
    """The audited project, resolved ONCE per process (per CLAUDE_PROJECT_DIR / TARGET_DIR value): a project folder removed while
    the gate runs (`worktree finish`/`remove`, W1 R5a) must stay the project — re-resolving it fell back to the cwd's repo (the main
    checkout) or crashed on the deleted cwd."""
    target_env = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("TARGET_DIR")
    if target_env in _PROJECT_DIRS:
        return _PROJECT_DIRS[target_env]
    if target_env and Path(target_env).exists():
        found = Path(target_env).resolve()
    else:
        found = None
        try:
            res = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
            if res.returncode == 0 and res.stdout.strip():
                found = Path(res.stdout.strip()).resolve()
        except Exception:
            pass
        found = found or Path.cwd().resolve()
    _PROJECT_DIRS[target_env] = found
    return found

def get_base_dir() -> Path:
    return get_project_dir()

def find_matrix_path(matrix_path: str = None):
    proj_dir = get_project_dir()
    devkit_dir = get_devkit_dir()
    candidates = []
    if matrix_path:
        candidates.append(Path(matrix_path))
    # Only the audited project's own matrix counts. The devkit's sample matrix is used
    # only when auditing the devkit itself — never silently for an unrelated project.
    candidates.extend([
        proj_dir / ".agents" / "regression_matrix.active.json",
        proj_dir / "templates" / "regression_matrix.active.json",
        proj_dir / ".agents" / "active-profile" / "regression_matrix.json",
        proj_dir / "templates" / "regression_matrix.json",
    ])
    if proj_dir == devkit_dir:
        candidates.append(devkit_dir / "templates" / "regression_matrix.json")
    for c in candidates:
        if c.exists():
            return c
    return None


def load_active_matrix(matrix_path: str = None, base_ref: str = "HEAD"):
    """Returns (matrix, trust_problem). The regression commands are what turns a change
    into PASS, so they are read from the base ref — never from a working copy the
    audited change could have edited (`exit 1` -> `true`)."""
    path = find_matrix_path(matrix_path)
    if path is None:
        return {}, None
    try:
        rel = path.resolve().relative_to(get_repo_root()).as_posix()
    except ValueError:
        rel = None
    if rel is None:
        # Outside the audited repo (e.g. the devkit's profile matrix): the change under
        # audit cannot have edited it, read as-is.
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f), None
        except (OSError, ValueError) as e:
            log_warn(tr(f"Không đọc được regression matrix {path}: {e}", f"Cannot read regression matrix {path}: {e}"))
            return {}, None
    res = subprocess.run(["git", "-C", str(get_repo_root()), "show", f"{base_ref}:{rel}"],
                         capture_output=True)
    if res.returncode != 0:
        # Not committed yet. A byte-identical copy of a DevKit profile matrix (what
        # `agent-kit profile` writes), or exactly what scripts/matrix_detect.py generates
        # from this project's own test runner right now, carries the DevKit's commands,
        # not the change's — an edited one (`exit 1` -> `true`) no longer matches.
        try:
            current = path.read_bytes()
        except OSError:
            current = None
        generated = None
        if current is not None and b'"generated_by"' in current:
            try:
                import matrix_detect  # noqa: PLC0415 - scripts/ is on sys.path
                generated = matrix_detect.generate(str(get_project_dir()))
            except Exception:
                generated = None
        if current is not None and (current in devkit_profile_matrices() or current == generated):
            try:
                return json.loads(current.decode("utf-8", errors="replace")), None
            except ValueError:
                pass
        return {}, tr(f"regression matrix `{rel}` chưa có trong {base_ref} — lệnh test chưa được commit nên không tin được",
                      f"regression matrix `{rel}` is not in {base_ref} — uncommitted test commands cannot be trusted")
    try:
        matrix = json.loads(res.stdout.decode("utf-8", errors="replace"))
    except ValueError as e:
        return {}, tr(f"regression matrix `{rel}` ở {base_ref} không parse được: {e}",
                      f"regression matrix `{rel}` at {base_ref} does not parse: {e}")
    try:
        current = path.read_bytes()
    except OSError:
        current = None
    if current != res.stdout:
        return matrix, tr(f"regression matrix `{rel}` bị sửa so với {base_ref} trong thay đổi đang audit — gate chạy lệnh của bản {base_ref}, cần người review",
                          f"regression matrix `{rel}` was modified relative to {base_ref} in the audited change — the gate runs the {base_ref} commands; needs human review")
    return matrix, None


def matrix_additions(base, current):
    """Id các test mà ma trận `current` THÊM so với `base`, hoặc None khi đó không phải thay đổi chỉ-thêm (GeelyEx2 PR #60, 18/10: một PR
    chỉ thêm REG-HOOK-01 bị exit 2 "cần người review", pre-push và merge gate dừng). Chỉ-thêm: khoá top-level ngoài "rules" giữ nguyên; rule
    cũ còn nguyên ở ĐẦU danh sách, bằng từng giá trị, rule mới chỉ nối ở đuôi (review 18/10: rule chèn đầu chạy trước suite base và tác
    dụng phụ của nó vô hiệu được suite base); mỗi rule mới có ít nhất một test, mỗi test mới có id chưa có ở base — kể cả đích covered_by
    của test base (id thêm "lấp" đích treo thì suite base bị đánh COVERED) —, không trùng nhau, có lệnh, và không covered_by (test mới
    phải tự chạy). Thứ khác: None.
    ponytail: gate không chấm chất lượng lệnh test mới — rule mới `watch_files: ["**"]` với lệnh `true` vẫn XANH và làm file chưa có test
    thành "được phủ" (như một file test rỗng dưới suite cũ đã làm được); thêm kiểm tra lệnh no-op khi thấy một ca như vậy trong PR thật."""
    if not isinstance(base, dict) or not isinstance(current, dict):
        return None
    if {k: v for k, v in base.items() if k != "rules"} != {k: v for k, v in current.items() if k != "rules"}:
        return None
    old, new = base.get("rules", []), current.get("rules", [])
    if not isinstance(old, list) or not isinstance(new, list):
        return None
    added_rules = new[len(old):]
    if new[:len(old)] != old or not added_rules:
        return None
    base_ids = {t[k] for r in old if isinstance(r, dict) for t in (r.get("mandatory_regression_tests") or [])
                if isinstance(t, dict) for k in ("id", "covered_by") if isinstance(t.get(k), str)}
    added = []
    for rule in added_rules:
        tests = rule.get("mandatory_regression_tests") if isinstance(rule, dict) else None
        if not isinstance(tests, list) or not tests:
            return None
        for t in tests:
            if not (isinstance(t, dict) and isinstance(t.get("id"), str) and t["id"].strip()
                    and isinstance(t.get("command"), str) and t["command"].strip() and "covered_by" not in t):
                return None
            if t["id"] in base_ids or t["id"] in added:
                return None
            added.append(t["id"])
    return added


def trust_additive_matrix(matrix, problem, matrix_path, base_ref: str):
    """(matrix, problem, added ids). Ma trận bị sửa so với base_ref mà chỉ THÊM rule (matrix_additions) thì gate chạy ma trận của thay đổi và
    không còn là việc của người review — với điều kiện mọi test thêm chạy XANH trong chính lượt này (main ép chạy chúng và kiểm lại trước
    kết luận). Mọi trường hợp khác giữ nguyên (matrix, problem) của load_active_matrix."""
    if not problem or not matrix:
        return matrix, problem, []
    path = find_matrix_path(matrix_path)
    try:
        rel = path.resolve().relative_to(get_repo_root()).as_posix()
        current = path.read_bytes()
    except (AttributeError, OSError, ValueError):
        return matrix, problem, []
    res = subprocess.run(["git", "-C", str(get_repo_root()), "show", f"{base_ref}:{rel}"], capture_output=True)
    if res.returncode != 0 or current == res.stdout:
        return matrix, problem, []
    try:
        base = json.loads(res.stdout.decode("utf-8", errors="replace"))
        cur = json.loads(current.decode("utf-8", errors="replace"))
    except ValueError:
        return matrix, problem, []
    added = matrix_additions(base, cur)
    if not added or base != matrix:
        return matrix, problem, []
    return cur, None, added


def matrix_id_conflicts(matrix) -> dict:
    """{suite id: [commands]} for an id the matrix gives two DIFFERENT commands (2026-10-10, GeelyEx2 REG-OPS-11): they share one status
    row, one evidence folder and one stale window, so a pass of one hides a failure of the other. One id under two rules with the same
    command is a shared suite, not a conflict."""
    seen = {}
    for rule in (matrix.get("rules") if isinstance(matrix, dict) else None) or []:
        for t in (rule.get("mandatory_regression_tests") if isinstance(rule, dict) else None) or []:
            if isinstance(t, dict) and t.get("id") and isinstance(t.get("command"), str):
                cmds = seen.setdefault(t["id"], [])
                if t["command"] not in cmds:
                    cmds.append(t["command"])
    return {i: c for i, c in seen.items() if len(c) > 1}


def _renamed_paths(base_ref: str, staged: bool = False) -> dict:
    """{old: new}, project-relative: what git itself records as RENAMED between base_ref and the working
    tree (the index with staged) and whose old path is gone. A copy keeps its old path and a path nobody
    removed is never re-pointed, so the map can follow a move but never redirect a command elsewhere."""
    root = get_project_dir()
    cmd = ["git", "-C", str(root), "diff", "--name-status", "-z", "-M", "--relative"] + (["--cached"] if staged else []) + [base_ref]
    res = subprocess.run(cmd, capture_output=True)
    if res.returncode != 0:
        return {}
    parts = res.stdout.decode("utf-8", errors="surrogateescape").split("\0")
    moved, i = {}, 0
    while i < len(parts):
        status = parts[i]
        i += 1
        if not status:
            continue
        if status[0] in "RC":   # R<score>\0old\0new   (C: a copy, never followed)
            if i + 1 >= len(parts):
                break
            old, new = parts[i], parts[i + 1]
            i += 2
            if status[0] == "R" and not (root / old).exists() and (root / new).exists():
                moved[old] = new
        elif i < len(parts):
            i += 1
    return moved


def _repoint(matrix: dict, renames: dict) -> dict:
    """matrix with every renamed path — as a whole path token of a test command or a watch_files entry — re-pointed."""
    if not renames:
        return matrix
    rx = re.compile(r"(?:(?<=\./)|(?<![\w./-]))(" + "|".join(re.escape(p) for p in sorted(renames, key=len, reverse=True))
                    + r")(?![\w./-])")
    sub = lambda v: rx.sub(lambda m: renames[m.group(1)], v) if isinstance(v, str) else v  # noqa: E731
    out = json.loads(json.dumps(matrix))
    for rule in out.get("rules") or []:
        if not isinstance(rule, dict):
            continue
        if isinstance(rule.get("watch_files"), list):
            rule["watch_files"] = [sub(w) for w in rule["watch_files"]]
        for t in rule.get("mandatory_regression_tests") or []:
            if isinstance(t, dict):
                for key in ("command", "impacted_command"):
                    if key in t:
                        t[key] = sub(t[key])
    return out


def follow_matrix_renames(matrix: dict, problem, matrix_path, base_ref: str, staged: bool = False):
    """(matrix, problem). The audited change cannot be trusted with its own matrix, so the commands are the
    base ref's. When the change MOVES a test file that command names a path the change removed (exit 127: a
    test moved into tests/<group>/ could not pass, 2026-10-02). Re-point exactly the renames git records.
    The matrix edit stops being the human-review problem only when the working matrix equals that
    re-pointing; any other edit stays the problem. A matrix that still names the old path is reported:
    it runs here, and would break once pushed.
    ponytail: a renamed test whose content also changed is judged by the edited-test rules, not here; move that
    check here if a weakened rename ever slips through."""
    if not matrix:
        return matrix, problem
    renames = _renamed_paths(base_ref, staged)
    moved = _repoint(matrix, renames)
    if moved == matrix:
        return matrix, problem
    if problem:
        path = find_matrix_path(matrix_path)
        try:
            current = json.loads(path.read_text(encoding="utf-8")) if path else None
        except (OSError, ValueError):
            current = None
        return moved, (None if current == moved else problem)
    named = sorted(o for o in renames if o in json.dumps(matrix))
    return moved, tr(f"regression matrix còn nêu file mà thay đổi này đổi tên ({', '.join(named[:5])}) — sửa lệnh/watch_files sang đường dẫn mới "
                     f"(sau khi push lệnh cũ sẽ thoát 127)",
                     f"the regression matrix still names file(s) this change renames ({', '.join(named[:5])}) — update its command/watch_files "
                     f"to the new path (the old command exits 127 once pushed)")


def devkit_profile_matrices() -> set:
    """Contents of every DevKit profile matrix (outside any audited project repo)."""
    out = set()
    if get_project_dir() == get_devkit_dir():
        return out  # auditing the DevKit itself: its own matrices are part of the change
    for f in (get_devkit_dir() / "profiles").glob("*/regression_matrix.json"):
        try:
            out.add(f.read_bytes())
        except OSError:
            pass
    return out


REPO_ROOT = None
PROJECT_PREFIX = None


def _git_static(project_dir, *args):
    """tree_fp.rev_parse_static: a `git rev-parse` whose answer cannot move during this run, spawned once per distinct question."""
    here = str(Path(__file__).resolve().parent)
    if here not in sys.path:
        sys.path.insert(0, here)
    import tree_fp  # noqa: PLC0415 - sibling module in bin/
    return tree_fp.rev_parse_static(project_dir, *args)


def get_repo_root() -> Path:
    global REPO_ROOT
    if REPO_ROOT is None:
        top = _git_static(get_project_dir(), "--show-toplevel")
        REPO_ROOT = Path(os.fsdecode(top)).resolve() if top else get_project_dir()
    return REPO_ROOT


def get_project_prefix() -> str:
    """Project dir relative to the repo root ("" unless the project is a monorepo subdir)."""
    global PROJECT_PREFIX
    if PROJECT_PREFIX is None:
        prefix = _git_static(get_project_dir(), "--show-prefix")
        PROJECT_PREFIX = os.fsdecode(prefix) if prefix is not None else ""
    return PROJECT_PREFIX


def resolve_path(rel_file: str) -> Path:
    """Changed-file paths are relative to the project dir (see get_modified_files)."""
    p = Path(rel_file)
    return p if p.is_absolute() else get_project_dir() / p


DELETED_FILES = set()
RENAME_SOURCES = {}
UNTRACKED_FILES = set()   # `??` in git status: a path the index does not hold (a `git rm --cached` file left on disk)


def _to_project_rel(repo_rel: str):
    prefix = get_project_prefix()
    if prefix and not repo_rel.startswith(prefix):
        return None  # outside the audited project (monorepo sibling)
    return repo_rel[len(prefix):]


STAGED = False       # --staged: audit the index — what `git commit` will record
STAGED_MODES = {}    # project-relative path -> index mode ("100644", "120000", "160000", …)
_CONTENT_CACHE = {}
BASE_REF = "HEAD"    # what "already there" means for a secret: HEAD, the --diff base, or the --since base
VACUITY_BASE = "HEAD"  # the code the vacuity revert puts back: BASE_REF, or the --since base
_BASE_CACHE = {}
_BASE_REF_FOR = {}   # project-relative path -> its own base ref (--since: a file only upstream commits touched keeps HEAD)
PREEXISTING_SECRETS = []   # (file:line, label) found in the base version too — warned, not blocked
# git objects read in batches (A12, audit 2026-10-09): 600 changed files cost ~1235 git processes (one `git show`,
# `cat-file -e` or `diff -U0` per file), ~4 s of fork/exec. Keyed by (ref, path from the repo root); ref "" = the index.
_BLOBS = {}          # -> bytes of the blob, or None when <ref>:<path> is no blob
_OBJ_INFO = {}       # -> (type, size) as `git cat-file --batch-check` printed it, or None when missing
_BATCH_MAX_BYTES = 2_000_000   # a larger blob is read only when asked (blob_at), never prefetched
_BATCH_TOTAL_BYTES = 256_000_000   # nor more than this in one prefetch: the rest is read when asked


def prefetch_blobs(ref: str, repo_paths) -> None:
    """Fill _OBJ_INFO / _BLOBS for many `<ref>:<path>` with two git processes (cat-file --batch-check, then --batch for
    the blobs up to _BATCH_MAX_BYTES). Any trouble leaves the entries out: object_info / blob_at then ask git per file,
    as before. A path with a newline cannot be named on one line: left to that fallback too."""
    todo = [p for p in dict.fromkeys(repo_paths) if p and "\n" not in p and (ref, p) not in _OBJ_INFO]
    if not todo:
        return
    root = str(get_repo_root())
    try:
        chk = subprocess.run(["git", "-C", root, "cat-file", "--batch-check"], capture_output=True,
                             input="".join(f"{ref}:{p}\n" for p in todo).encode("utf-8", "surrogateescape"))
    except OSError:
        return
    lines = chk.stdout.split(b"\n")
    if chk.returncode != 0 or len(lines) < len(todo):
        return
    want, total = [], 0
    for p, line in zip(todo, lines):
        parts = line.rsplit(b" ", 2)
        if line.endswith(b" missing"):
            _OBJ_INFO[(ref, p)] = None
            _BLOBS[(ref, p)] = None
        elif len(parts) == 3 and parts[2].isdigit() and len(parts[0]) in (40, 64) and b" " not in parts[0]:
            kind, size = parts[1].decode(), int(parts[2])
            _OBJ_INFO[(ref, p)] = (kind, size)
            if kind != "blob":
                _BLOBS[(ref, p)] = None
            elif size <= _BATCH_MAX_BYTES and total + size <= _BATCH_TOTAL_BYTES:
                want.append((p, parts[0].decode()))
                total += size
        # anything else ("ambiguous", …): not cached, the per-file fallback decides
    if not want:
        return
    try:
        out = subprocess.run(["git", "-C", root, "cat-file", "--batch"], capture_output=True,
                             input="".join(f"{sha}\n" for _p, sha in want).encode()).stdout
    except OSError:
        return
    pos = 0
    for p, sha in want:   # "<sha> blob <size>\n<content>\n" per object, in input order
        nl = out.find(b"\n", pos)
        head = out[pos:nl].split() if nl >= 0 else []
        if len(head) != 3 or head[0].decode() != sha or not head[2].isdigit():
            return
        size = int(head[2])
        _BLOBS[(ref, p)] = out[nl + 1:nl + 1 + size]
        pos = nl + 1 + size + 1


def object_info(ref: str, repo_path: str):
    """(type, size) of <ref>:<path>, or None when git has no such object (`git cat-file -e` failing)."""
    key = (ref, repo_path)
    if key not in _OBJ_INFO:
        res = subprocess.run(["git", "-C", str(get_repo_root()), "cat-file", "--batch-check"], capture_output=True,
                             input=f"{ref}:{repo_path}\n".encode("utf-8", "surrogateescape"))
        parts = res.stdout.strip().rsplit(b" ", 2)
        ok = res.returncode == 0 and len(parts) == 3 and parts[2].isdigit() and not res.stdout.strip().endswith(b" missing")
        _OBJ_INFO[key] = (parts[1].decode(), int(parts[2])) if ok else None
    return _OBJ_INFO[key]


def blob_at(ref: str, repo_path: str):
    """Bytes of the blob <ref>:<path> (ref "" = the index), or None (no such blob: new file, a tree, unreadable)."""
    key = (ref, repo_path)
    if key not in _BLOBS:
        res = subprocess.run(["git", "-C", str(get_repo_root()), "cat-file", "blob", f"{ref}:{repo_path}"],
                             capture_output=True)
        _BLOBS[key] = res.stdout if res.returncode == 0 else None
    return _BLOBS[key]


def worktree_bytes(repo_path: str):
    """The working-tree content git would diff for this path (a symlink: its target), or None: absent, or not a
    regular file (a FIFO is never opened: reading one would block the gate)."""
    full = os.path.join(str(get_repo_root()), repo_path)
    try:
        if os.path.islink(full):
            return os.fsencode(os.readlink(full))
        if not os.path.isfile(full):
            return None
        with open(full, "rb") as f:
            return f.read()
    except OSError:
        return None


def split_new(rel_file: str, pat: str, content: str):
    """(new, old): the matches of pat in content that this change introduced, and those
    already in the base version. Counted per matched text, so a second copy of an old
    anti-pattern added by the change is new. Findings that only exist because the file
    was touched must not block: fixing unrelated legacy lines to be allowed to commit
    would break the surgical-change rule, and the agent cannot bypass the gate."""
    matches = list(re.finditer(pat, content))
    base = base_text(rel_file)
    if base is None or not matches:
        return matches, []
    base_count = {}
    for bm in re.finditer(pat, base):
        base_count[bm.group(0)] = base_count.get(bm.group(0), 0) + 1
    new, old, seen = [], [], {}
    for m in matches:
        seen[m.group(0)] = seen.get(m.group(0), 0) + 1
        (old if seen[m.group(0)] <= base_count.get(m.group(0), 0) else new).append(m)
    return new, old


def note_preexisting(rel_file: str, content: str, m, label):
    PREEXISTING_SECRETS.append((f"{rel_file}:{content.count(chr(10), 0, m.start()) + 1}", _L(label)))


def base_text(rel_file: str):
    """The file at BASE_REF, or None (new file, not in git, unreadable)."""
    if rel_file not in _BASE_CACHE:
        src = RENAME_SOURCES.get(rel_file, rel_file)
        data = blob_at(_BASE_REF_FOR.get(rel_file, BASE_REF), f"{get_project_prefix()}{src}")   # prefetched in main()
        _BASE_CACHE[rel_file] = data.decode("utf-8", errors="replace") if data is not None else None
    return _BASE_CACHE[rel_file]


def read_changed_text(rel_file: str):
    """Content the static checks judge: the staged blob with --staged, else the working-
    tree file. None for symlinks (their content is a link target, not a change),
    submodules, deleted and unreadable files."""
    if rel_file in _CONTENT_CACHE:
        return _CONTENT_CACHE[rel_file]
    text = None
    if STAGED:
        if STAGED_MODES.get(rel_file, "").startswith("100"):
            data = blob_at("", f"{get_project_prefix()}{rel_file}")   # the index; prefetched in run_staged_audit
            if data is not None:
                text = data.decode("utf-8", errors="replace")
    else:
        full = resolve_path(rel_file)
        if full.is_file() and not full.is_symlink():
            try:
                with open(full, "r", encoding="utf-8", errors="replace") as f:
                    text = f.read()
            except OSError:
                pass
    _CONTENT_CACHE[rel_file] = text
    return text


def _parse_name_status(raw: bytes) -> set:
    """`git diff --name-status -z` output -> destination paths (deletions recorded)."""
    files = set()
    parts = raw.decode("utf-8", errors="surrogateescape").split("\0")
    j = 0
    while j < len(parts):
        status = parts[j]
        j += 1
        if not status:
            continue
        if status[0] in "RC":
            src = parts[j]
            j += 1  # skip source
            if j < len(parts) and parts[j]:
                RENAME_SOURCES[parts[j]] = src
        if j < len(parts) and parts[j]:
            if status[0] == "D":
                DELETED_FILES.add(parts[j])
            files.add(parts[j])
        j += 1
    return files


def get_staged_files() -> list:
    """Paths in the index that differ from HEAD (or every staged path before the first
    commit), relative to the project dir, plus their index modes."""
    proj = str(get_project_dir())
    res = subprocess.run(["git", "-C", proj, "diff", "--cached", "--relative", "--name-status", "-z",
                          "--", "."], capture_output=True)
    if res.returncode != 0:
        raise RuntimeError(tr("git diff --cached thất bại: ", "git diff --cached failed: ") + res.stderr.decode(errors='replace').strip())
    files = _parse_name_status(res.stdout)
    ls = subprocess.run(["git", "-C", proj, "ls-files", "-s", "-z", "--", "."], capture_output=True)
    for entry in ls.stdout.decode("utf-8", errors="surrogateescape").split("\0"):
        meta, sep, path = entry.partition("\t")
        if sep:
            STAGED_MODES[path] = meta.split(" ", 1)[0]
    return sorted(files)


def get_modified_files(diff_ref: str = None) -> list:
    """Working-tree changes (+ `git diff <ref>` when given), parsed from -z output so
    quoted names, renames and files inside untracked directories are all resolved.
    Limited to the project dir and returned relative to it, so a monorepo subproject's
    paths match its own regression matrix."""
    proj = str(get_project_dir())
    files = set()
    res = subprocess.run(["git", "-C", proj, "status", "--porcelain=v1", "-z", "-uall", "--", "."],
                         capture_output=True)
    if res.returncode != 0:
        raise RuntimeError(tr(f"git status thất bại trong {proj}: ", f"git status failed in {proj}: ") + res.stderr.decode(errors='replace').strip())
    entries = res.stdout.decode("utf-8", errors="surrogateescape").split("\0")
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        xy, path = entry[:2], _to_project_rel(entry[3:])
        if "R" in xy or "C" in xy:
            if i < len(entries):
                src = _to_project_rel(entries[i])
                if src and path:
                    RENAME_SOURCES[path] = src
            i += 1  # the next NUL field is the rename/copy SOURCE; keep the destination
        if path is None:
            continue
        if "D" in xy:
            DELETED_FILES.add(path)
        if xy == "??":
            UNTRACKED_FILES.add(path)
        files.add(path)
    if diff_ref:
        res_diff = subprocess.run(["git", "-C", proj, "diff", "--relative", "--name-status", "-z",
                                   diff_ref, "--", "."], capture_output=True)
        if res_diff.returncode != 0:
            raise RuntimeError(tr(f"git diff {diff_ref} thất bại: ", f"git diff {diff_ref} failed: ") + res_diff.stderr.decode(errors='replace').strip())
        files |= _parse_name_status(res_diff.stdout)
    return sorted(files)


# The bookkeeping this gate writes itself (regression checklist, inbox).
GATE_STATE_FILES = (".agents/regression_status.json", ".agents/regression_checklist.md", ".agents/CHECKLIST.md", ".agents/INBOX.md")


def is_devkit_artifact(rel_file: str) -> bool:
    """Links the devkit installer places (hooks, commands, skills, rules, AGENTS.md…) and
    hook state are not the user's change: they are not scanned and not "unreadable"."""
    clean = rel_file.replace("\\", "/")
    if clean.startswith(".claude/audit-gate/"):
        return True
    # The regression checklist is written by this gate itself — never audit our own output.
    if clean in GATE_STATE_FILES \
            or clean.startswith((".agents/evidence/", ".agents/archive/", ".agents/context/")):
        return True
    full = resolve_path(rel_file)
    if not full.is_symlink():
        return False
    if clean.startswith((".claude/", ".agents/")):
        return True
    try:
        full.resolve().relative_to(get_devkit_dir())
        return True
    except (OSError, ValueError):
        return False


def tree_unclean_reason(matrix_arg) -> str:
    """#307, `--tree`: "" when the working tree IS the commit HEAD and HEAD is already published, else why --tree must not vouch for it.
    The mode skips every static audit (nothing is "changed") and trusts the matrix of HEAD, so each way to make `git status` look clean
    while the suites run on something else is a fake exit 0 (principal review 23/10): a commit nobody pushed, a matrix symlinked out of
    the devkit, an edit hidden by skip-worktree / assume-unchanged, a dirty submodule, a `--matrix` from outside the tree."""
    proj = str(get_project_dir())
    git = lambda *a: subprocess.run(["git", "-C", proj, *a], capture_output=True)   # noqa: E731
    if matrix_arg:
        return tr("--matrix: --tree chỉ tin ma trận đã commit trong cây, không nhận ma trận chỉ định",
                  "--matrix: --tree trusts only the matrix committed in the tree, not a named one")
    try:
        files = get_modified_files()
    except RuntimeError as e:
        return str(e)
    # A devkit symlink under .agents/ or .claude/ is the installer's — unless git tracks it: then it replaced (or retargeted) a committed file.
    dirty = [f for f in files if not is_devkit_artifact(f) or (resolve_path(f).is_symlink() and git("ls-files", "--error-unmatch", "--", f).returncode == 0)]
    st = git("status", "--porcelain=v1", "-z", "--ignore-submodules=none")   # a local diff.ignoreSubmodules cannot hide a dirty submodule
    if st.returncode != 0:
        return tr("git status thất bại", "git status failed")
    for ent in st.stdout.decode("utf-8", errors="surrogateescape").split("\0"):
        if len(ent) > 3 and ent[2] == " " and not is_devkit_artifact(ent[3:]) and ent[3:] not in dirty:
            dirty.append(ent[3:])
    hidden = git("ls-files", "-v", "-z")   # tag S = skip-worktree, lower case = assume-unchanged: an edit git does not report
    if hidden.returncode != 0:
        return tr("git ls-files thất bại", "git ls-files failed")
    dirty += [e[2:] for e in hidden.stdout.decode("utf-8", errors="surrogateescape").split("\0") if len(e) > 2 and (e[0] == "S" or e[0].islower())]
    if dirty:
        return tr(f"cây làm việc còn {len(dirty)} thay đổi chưa commit hoặc bị giấu ({', '.join(dirty[:3])}) — commit rồi chạy lại, hoặc dùng --diff",
                  f"the working tree has {len(dirty)} uncommitted or hidden change(s) ({', '.join(dirty[:3])}) — commit them and re-run, or use --diff")
    mp = find_matrix_path(None)
    if mp is not None and mp.is_symlink():
        try:
            mp.resolve().relative_to(get_devkit_dir())
        except (OSError, ValueError):
            return tr(f"ma trận {mp.name} là symlink ra ngoài devkit — không phải ma trận đã commit",
                      f"the matrix {mp.name} is a symlink out of the devkit — not the committed matrix")
    # Published: the audits above would have judged these commits against HEAD itself. No upstream at all (a detached worktree) → origin's trunk.
    refs = [git("rev-parse", "--verify", "-q", "@{u}").stdout.decode().strip()] + [
        git("rev-parse", "--verify", "-q", f"refs/remotes/origin/{b}").stdout.decode().strip() for b in ("main", "master", "trunk")]
    ref = next((r for r in refs if r), "")
    ahead = git("rev-list", "--count", f"{ref}..HEAD").stdout.decode().strip() if ref else ""
    if not ahead.isdigit() or int(ahead) > 0:
        return tr("HEAD có commit chưa nằm trên origin (hoặc không có upstream để so) — --tree không kiểm được chúng; dùng --full (kiểm upstream..HEAD)",
                  "HEAD holds commits origin does not (or there is no upstream to compare with) — --tree cannot audit them; use --full (audits upstream..HEAD)")
    return ""


# DevKit state folders the other checks skip (is_devkit_artifact) but the secret scan does not: a runner's log can print a
# token, and a key force-added under .agents/archive/ was exit 3 — which the pre-commit hook lets through (A5, 2026-10-09).
SECRET_SCAN_STATE_DIRS = (".claude/audit-gate/", ".agents/evidence/", ".agents/archive/", ".agents/context/")


def secret_scan_state_files(devkit_artifacts: list) -> list:
    """The changed files of SECRET_SCAN_STATE_DIRS (not the links the installer places: their content is a link target)."""
    return [f for f in devkit_artifacts if f.replace("\\", "/").startswith(SECRET_SCAN_STATE_DIRS)
            and not resolve_path(f).is_symlink()]


def match_pattern(file_path: str, pattern: str) -> bool:
    clean_path = file_path.replace("\\", "/")
    clean_pat = pattern.replace("\\", "/")
    if fnmatch.fnmatch(clean_path, clean_pat):
        return True
    if clean_pat.startswith("**/") and fnmatch.fnmatch(clean_path, clean_pat[3:]):
        return True
    return False


def run_git_hygiene_audit(modified_files: list) -> tuple:
    secrets_found = []
    for rel_file in modified_files:
        clean_rel = rel_file.replace("\\", "/")
        name = clean_rel.rsplit("/", 1)[-1].lower()
        exempt_name = name.endswith(SAFE_TEMPLATE_SUFFIXES)
        # A deletion of a forbidden file is the remediation, never a finding: `git rm --cached .env` was REJECTed by
        # --staged and --full, blocking the very commit that removes it (A4, 2026-10-09). Still a finding while the
        # file stays in what the change holds: on disk and not ignored (`??` next to the deletion).
        removed = rel_file in DELETED_FILES and rel_file not in UNTRACKED_FILES
        # 1. Kiểm tra tên file nhạy cảm cấm commit (Keystore, JKS, Provisioning, Service Configs)
        if not exempt_name and not removed:
            for file_pat, label in FORBIDDEN_SECRET_FILES:
                if re.search(file_pat, clean_rel, re.IGNORECASE):
                    secrets_found.append((rel_file, tr("File cấm: ", "Forbidden file: ") + _L(label)))
                    _record("secrets", rel_file, label if isinstance(label, tuple) else ("File cấm: " + label, "Forbidden file: " + label))

        # 2. Kiểm tra nội dung file tìm secret / password / key
        # Bỏ qua quét nội dung binary hoặc ảnh
        if rel_file.endswith((".pyc", ".png", ".jpg", ".jpeg", ".webp", ".so", ".dylib", ".a", ".jar", ".aar", ".apk", ".idsig", ".dex")):
            continue
        content = read_changed_text(rel_file)
        if content is not None and "\x00" in content[:8192]:
            continue   # binary (a NUL in the first 8 KB): 21 regexes over a 13 MB .tflite cost 2.9 s per gate run; the NAME check above still applies
        if content is not None:
            patterns = list(SECRET_PATTERNS)
            if name.endswith(CONFIG_EXTENSIONS) or re.search(ENV_FILE_PATTERN, clean_rel):
                patterns.append(CONFIG_SECRET_PATTERN)
            for pat, label, group in patterns:
                for m in re.finditer(pat, content):
                    if group is not None and PLACEHOLDER_VALUE.match(m.group(group)):
                        continue
                    line = content.count("\n", 0, m.start()) + 1
                    # The very same secret text already in the base version was not
                    # introduced by this change (e.g. a public Supabase anon key committed
                    # long ago): blocking on it would block every stop and commit that
                    # touches the file, forever. It is reported to be rotated/removed.
                    base = base_text(rel_file)
                    if base is not None and m.group(0) in base:
                        PREEXISTING_SECRETS.append((f"{rel_file}:{line}", _L(label)))
                        continue
                    secrets_found.append((f"{rel_file}:{line}", _L(label)))
                    _record("secrets", rel_file, label, content, m.start(), snippet=False)
                    break
    return len(secrets_found) == 0, secrets_found

def run_anti_laziness_audit(modified_files: list) -> tuple:
    lazy_matches = []
    for rel_file in modified_files:
        if is_test_path(rel_file) or has_dir(rel_file, "scripts", *THIRD_PARTY_DIRS) or rel_file.endswith(("post-fix-gate.py", "gate.sh")):
            continue
        if any(rel_file.endswith(ext) for ext in CODE_EXTENSIONS):
            content = read_changed_text(rel_file)
            if content is None:
                continue
            for pat, label in LAZY_CODE_PATTERNS:
                new, old = split_new(rel_file, pat, content)
                if old and not new:
                    note_preexisting(rel_file, content, old[0], label)
                if new:
                    lazy_matches.append((rel_file, _L(label)))
                    _record("lazy", rel_file, label, content, new[0].start())
    return len(lazy_matches) == 0, lazy_matches


def run_dependency_audit(modified_files: list) -> tuple:
    """Floating versions and plain-http sources in dependency manifests — supply-chain
    and reproducible-build hygiene. Each finding quotes the offending declaration."""
    findings = []
    for rel_file in modified_files:
        kind = dependency_kind(rel_file)
        if kind is None or is_test_path(rel_file):
            continue
        content = read_changed_text(rel_file)
        if content is None:
            continue
        hits = []
        if kind == "package.json":
            try:
                pkg = json.loads(content)
            except ValueError:
                pkg = None  # a broken package.json fails the project's own tooling first
            if isinstance(pkg, dict):
                for section in NPM_ALL_SECTIONS:
                    deps = pkg.get(section)
                    if not isinstance(deps, dict):
                        continue
                    for dep, ver in deps.items():
                        if not isinstance(ver, str):
                            continue
                        quoted = f'{section}.{dep}: "{ver}"'
                        km = re.search(r'"' + re.escape(dep) + r'"\s*:', content)
                        pos = km.start() if km else None
                        if section in NPM_PINNED_SECTIONS and ver.strip() in NPM_FLOATING:
                            hits.append((FLOATING_DEP, quoted, pos))
                        elif re.search(r"(?:^|\+)" + _HTTP, ver.strip()):
                            hits.append((INSECURE_DEP, quoted, pos))
                publish = pkg.get("publishConfig")
                registry = publish.get("registry") if isinstance(publish, dict) else None
                if isinstance(registry, str) and re.match(_HTTP, registry.strip()):
                    km = re.search(r'"registry"\s*:', content)
                    hits.append((INSECURE_DEP, f'publishConfig.registry: "{registry}"', km.start() if km else None))
        else:
            for pat, label in DEPENDENCY_RULES[kind]:
                new, old = split_new(rel_file, pat, content)
                if old and not new:
                    note_preexisting(rel_file, content, old[0], label)
                for m in new:
                    hits.append((label, " ".join(m.group(0).split())[:100], m.start()))
        seen = set()
        for label, quoted, pos in hits:
            if (label, quoted) not in seen:
                seen.add((label, quoted))
                findings.append((rel_file, f"{_L(label)}: `{quoted}`"))
                _record("dependencies", rel_file, label, content, pos)
    return len(findings) == 0, findings


# Lazy-senior advisories (core-rules §4): warnings, never blocking. A new dependency can be
# the right call; only the answer can say why stdlib / native / an installed one fell short.
# ponytail: TOML manifests need Python 3.11+ (tomllib), none warn below it, add a regex fallback if an older host shows up
_DEP_COORD = r"[\"']([\w.\-]+:[\w.\-]+)(?::[^\"'\s]*)?[\"']"
_DEBT_MARKER = r"(?:#|//|/\*|--|<!--)[ \t]*ponytail:([^\n]*)"
_PEP508_NAME = re.compile(r"\s*([A-Za-z0-9][A-Za-z0-9._\-]*)")


def _req_name(req: str) -> str:
    """PEP 503-normalised package name of one requirement line, or "" (URL with no #egg=)."""
    req = req.strip()
    if req.startswith(("-e ", "--editable ")):
        req = req.split(None, 1)[1]
    egg = re.search(r"#egg=([A-Za-z0-9._\-]+)", req)
    if egg:
        name = egg.group(1)
    elif req.startswith("-") or re.match(r"[\w+.\-]+://", req):
        return ""
    else:
        m = _PEP508_NAME.match(req)
        name = m.group(1) if m else ""
    return re.sub(r"[-_.]+", "-", name).lower()


def _toml_names(text: str) -> set:
    try:
        import tomllib  # noqa: PLC0415
        data = tomllib.loads(text)
    except (ImportError, ValueError):
        return set()
    names = set()
    def tables(d):
        for k, v in d.items():
            if not isinstance(v, dict):
                continue
            if not k.endswith("dependencies"):
                tables(v)
                continue
            for name, spec in v.items():  # Cargo/Poetry: {pkg: spec}; PEP 621 / PDM groups: {group: [reqs]}
                if isinstance(spec, list):
                    names.update(_req_name(r) for r in spec if isinstance(r, str) and _req_name(r))
                else:
                    names.add(name)
    tables(data)
    reqs = (data.get("project") or {}).get("dependencies") or []
    names.update(_req_name(r) for r in reqs if isinstance(r, str) and _req_name(r))
    names.discard("python")  # Poetry's interpreter pin, not a package
    return names


def _pubspec_names(text: str) -> set:
    names, section = set(), None
    for line in text.splitlines():
        top = re.match(r"^(\w+):", line)
        if top:
            section = top.group(1)
            continue
        m = re.match(r"^  (\w+):", line)
        if m and section in ("dependencies", "dev_dependencies", "dependency_overrides"):
            names.add(m.group(1))
    return names


def dependency_names(kind, text: str) -> set:
    if kind == "package.json":
        try:
            pkg = json.loads(text)
        except ValueError:
            return set()
        if not isinstance(pkg, dict):
            return set()
        return {n for s in NPM_PINNED_SECTIONS if isinstance(pkg.get(s), dict) for n in pkg[s]}
    if kind in ("gradle", "version-catalog"):
        return set(re.findall(_DEP_COORD, text))
    if kind == "pip":
        return {n for line in text.splitlines() if not line.lstrip().startswith("#") and (n := _req_name(line))}
    if kind == "podfile":
        return set(re.findall(r"(?m)^\s*pod\s+['\"]([^'\"]+)['\"]", text))
    if kind == "swiftpm":
        names = set()
        for u in re.findall(r"\.package\s*\([^)]*?\burl\s*:\s*\"([^\"]+)\"", text):
            pkg_name = u.rstrip("/").rsplit("/", 1)[-1]
            names.add(pkg_name[:-4] if pkg_name.endswith(".git") else pkg_name)
        return names
    if kind == "pubspec":
        return _pubspec_names(text)
    if kind == "cargo":
        return _toml_names(text)
    if kind == "maven-pom":
        out = set()
        for block in re.findall(r"<dependency>(.*?)</dependency>", re.sub(r"<!--.*?-->", "", text, flags=re.S), re.S):
            g = re.search(r"<groupId>\s*([^<\s]+)\s*</groupId>", block)
            a = re.search(r"<artifactId>\s*([^<\s]+)\s*</artifactId>", block)
            if g and a:
                out.add(f"{g.group(1)}:{a.group(1)}")
        return out
    return set()


def run_lazy_senior_advisories(modified_files: list) -> list:
    notes = []
    for rel_file in modified_files:
        content = read_changed_text(rel_file)
        if content is None or rel_file.endswith(".md"):
            continue
        kind = dependency_kind(rel_file)
        if rel_file.replace("\\", "/").endswith("Packages/manifest.json"):
            kind = "package.json"  # Unity UPM: same {"dependencies": {name: version}} shape
        if kind and not is_test_path(rel_file):
            added = sorted(dependency_names(kind, content) - dependency_names(kind, base_text(rel_file) or ""))
            if added:
                shown = ", ".join(added[:5]) + (f" +{len(added) - 5}" if len(added) > 5 else "")
                notes.append(tr(f"{rel_file}: dependency mới {shown} — nói trong câu trả lời vì sao stdlib / native / dependency đã cài không đủ (core-rules §4, không chặn)",
                                f"{rel_file}: new dependency {shown} — say in the answer why stdlib / native / an installed dependency falls short (core-rules §4, not blocking)"))
        for m in split_new(rel_file, _DEBT_MARKER, content)[0]:
            if not re.search(r"[,;]|->|→", m.group(1)):
                line = content.count("\n", 0, m.start()) + 1
                notes.append(tr(f"{rel_file}:{line}: marker `ponytail:` thiếu 'khi nào nâng cấp' — viết `ponytail: <trần>, <khi nào nâng cấp>` (không chặn)",
                                f"{rel_file}:{line}: `ponytail:` marker names no upgrade trigger — write `ponytail: <ceiling>, <when to upgrade>` (not blocking)"))
    return notes

def run_performance_audit(modified_files: list) -> tuple:
    perf_findings = []
    base_dir = get_base_dir()
    devkit_dir = get_devkit_dir()

    # Load the AST linters this change needs, each on its own: a failed import is printed (the lint is OFF for the run), never swallowed,
    # and it does not take the other linter down (2026-10-10: one try/except-pass hid both).
    check_kotlin_stability = None
    check_unity_gc = None
    need_kt = any(f.endswith(".kt") for f in modified_files)
    need_cs = any(f.endswith(".cs") for f in modified_files)
    if need_kt or need_cs:
        sys.path.insert(0, str(devkit_dir / "scripts"))
        for _sub in ("audits", "context", "git", "governance", "linters", "testing"):
            _sub_path = str(devkit_dir / "scripts" / _sub)
            if _sub_path not in sys.path:
                sys.path.insert(0, _sub_path)
    if need_kt:
        try:
            from lint_compose_stability import check_kotlin_file as check_kotlin_stability
        except Exception as e:
            log_err(f"lint_compose_stability unavailable ({e}) — Compose stability lint is OFF for this run")
    if need_cs:
        try:
            from lint_unity_gc import check_csharp_file as check_unity_gc
        except Exception as e:
            log_err(f"lint_unity_gc unavailable ({e}) — Unity Zero-GC lint is OFF for this run")

    for rel_file in modified_files:
        # Exclude tests and build scripts from performance antipattern checks
        if (is_test_path(rel_file) or has_dir(rel_file, "scripts", "bin", *THIRD_PARTY_DIRS)
                or rel_file.endswith(("build.gradle", "build.gradle.kts", "pom.xml"))):
            continue
        if not any(rel_file.endswith(ext) for ext in CODE_EXTENSIONS):
            continue
        content = read_changed_text(rel_file)
        if content is None:
            continue
        for pat, label in PERF_ANTIPATTERN_PATTERNS:
            new, old = split_new(rel_file, pat, content)
            if old and not new:
                note_preexisting(rel_file, content, old[0], label)
            if new:
                perf_findings.append((rel_file, _L(label)))
                _record("perf", rel_file, label, content, new[0].start())

        linter = None
        if rel_file.endswith(".kt") and check_kotlin_stability:
            linter, tag = check_kotlin_stability, "Jetpack Compose"   # AST Compose Stability Check
        elif rel_file.endswith(".cs") and check_unity_gc:
            linter, tag = check_unity_gc, "Unity Hot-Loop GC"         # AST Unity Zero-GC Check
        if linter is None:
            continue
        # The linters read a path; with --staged they get a temp copy of the staged blob.
        lint_path, tmp = resolve_path(rel_file), None
        try:
            if STAGED:
                fd, tmp = tempfile.mkstemp(suffix=Path(rel_file).suffix)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(content)
                lint_path = Path(tmp)
            # Like split_new for the regex layers: a finding already in the base version of
            # the file is legacy — warned, not blocked (GeelyEx2 2026-09-26). Compared per
            # message without its "Line N", so lines moving up or down stay legacy.
            base_left = {}
            base = base_text(rel_file)
            if base is not None:
                fd, base_tmp = tempfile.mkstemp(suffix=Path(rel_file).suffix)
                try:
                    with os.fdopen(fd, "w", encoding="utf-8") as f:
                        f.write(base)
                    for v in linter(Path(base_tmp)):
                        k = re.sub(r"^Line \d+ ", "", v)
                        base_left[k] = base_left.get(k, 0) + 1
                finally:
                    os.unlink(base_tmp)
            for v in linter(lint_path):
                k = re.sub(r"^Line \d+ ", "", v)
                if base_left.get(k, 0) > 0:
                    base_left[k] -= 1
                    line = re.match(r"^Line (\d+)", v)
                    PREEXISTING_SECRETS.append((f"{rel_file}:{line.group(1) if line else '?'}", f"{tag}: {k}"))
                    continue
                perf_findings.append((rel_file, f"{tag}: {v}"))
                _record("perf", rel_file, f"{tag}: {v}")
        except Exception as e:
            log_err(f"{tag} linter failed on {rel_file}: {e}")
        finally:
            if tmp:
                os.unlink(tmp)

    return len(perf_findings) == 0, perf_findings

def run_resilience_audit(modified_files: list) -> tuple:
    findings = []
    for rel_file in modified_files:
        if is_test_path(rel_file) or has_dir(rel_file, "scripts", "bin", *THIRD_PARTY_DIRS):
            continue
        content = read_changed_text(rel_file) if any(rel_file.endswith(ext) for ext in CODE_EXTENSIONS) else None
        if content is None:
            continue
        for pat, label in RESILIENCE_ANTIPATTERN_PATTERNS:
            new, old = split_new(rel_file, pat, content)
            if old and not new:
                note_preexisting(rel_file, content, old[0], label)
            if new:
                findings.append((rel_file, _L(label)))
                _record("resilience", rel_file, label, content, new[0].start())
    return len(findings) == 0, findings

def run_logging_audit(modified_files: list) -> tuple:
    findings = []
    for rel_file in modified_files:
        # A command-line tool's output IS its console: scripts/, bin/, Go's cmd/, tools/.
        if is_test_path(rel_file) or has_dir(rel_file, "scripts", "bin", "cmd", "tools", *THIRD_PARTY_DIRS):
            continue
        content = read_changed_text(rel_file) if any(rel_file.endswith(ext) for ext in CODE_EXTENSIONS) else None
        if content is None:
            continue
        for pat, label in LOGGING_ANTIPATTERN_PATTERNS:
            new, old = split_new(rel_file, pat, content)
            if old and not new:
                note_preexisting(rel_file, content, old[0], label)
            if new:
                findings.append((rel_file, _L(label)))
                _record("logging", rel_file, label, content, new[0].start())
    return len(findings) == 0, findings

def check_design_and_accessibility(modified_files: list) -> tuple:
    base_dir = get_base_dir()
    ui_files = [f for f in modified_files if any(f.endswith(ext) for ext in UI_EXTENSIONS)]
    if not ui_files:
        return True, tr("Không có file giao diện UI nào thay đổi", "No UI files changed")
    
    design_files = [
        base_dir / "DESIGN.md",
        base_dir / "templates" / "DESIGN.md",
        base_dir / ".agents" / "active-profile" / "DESIGN.md"
    ]
    design_found = any(d.exists() for d in design_files)
    if not design_found:
        return False, tr("Thiếu file DESIGN.md trong dự án hoặc active profile", "No DESIGN.md in the project or the active profile")
    return True, tr(f"Có DESIGN.md cho {len(ui_files)} UI files — Touch Target >= 48dp / 8pt Grid cần rà thủ công (gate không đo layout)",
                    f"DESIGN.md present for {len(ui_files)} UI files — touch targets >= 48dp / 8pt grid need a manual review (the gate does not measure layout)")

def check_instincts_memory() -> tuple:
    base_dir = get_base_dir()
    candidates = [
        base_dir / ".agents" / "instincts.md",
        base_dir / "templates" / "instincts.template.md"
    ]
    for c in candidates:
        if c.exists():
            return True, tr(f"Sẵn sàng ({c.name})", f"ready ({c.name})")
    return False, tr("Chưa thiết lập instincts.md", "instincts.md not set up")

def brain_sessions_for_project(project_dir: Path) -> list:
    """Antigravity session dirs whose plan/walkthrough mentions this project's path.
    Sessions of other projects are never counted (their images are not evidence here),
    nor sessions untouched for POSTFIX_GATE_BRAIN_DAYS days (default 7): an old
    session's screenshots do not show today's change, and skipping them by mtime
    also spares reading every old plan on each run."""
    root = Path(os.environ.get("POSTFIX_GATE_BRAIN_DIR") or (Path.home() / ".gemini" / "antigravity" / "brain"))
    if not root.is_dir():
        return []
    try:
        max_days = float(os.environ.get("POSTFIX_GATE_BRAIN_DAYS") or 7)
    except ValueError:
        max_days = 7
    cutoff = time.time() - max_days * 86400
    needle = re.compile(re.escape(str(project_dir)) + r"(?=[/\s)\"'`]|$)")
    sessions = []
    for b_dir in root.iterdir():
        if not b_dir.is_dir():
            continue
        mds = list(b_dir.glob("*.md"))
        try:
            newest = max([b_dir.stat().st_mtime] + [m.stat().st_mtime for m in mds])
        except OSError:
            continue
        if newest < cutoff:
            continue
        for md in mds:
            try:
                if md.stat().st_size <= 1_000_000 and needle.search(md.read_text(encoding="utf-8", errors="replace")):
                    sessions.append(b_dir)
                    break
            except OSError:
                continue
    return sessions


def check_anti_false_green(is_hardware_project: bool = False) -> tuple:
    """
    Anti-False-Green Engine:
    1. Device Enumeration: Check 'adb devices -l' if hardware project.
       Returns device_state: None (not checked), "online", "none", or "unverified".
    2. Visual Evidence Deduplication: SHA-256 on proof images of THIS project only,
       rejecting 0-byte or duplicates.
    """
    findings = []
    base_dir = get_base_dir()
    device_state = None

    if is_hardware_project:
        try:
            res = subprocess.run(["adb", "devices", "-l"], capture_output=True, text=True, timeout=3)
            lines = [l.strip() for l in res.stdout.strip().splitlines() if l.strip()]
            devices = [l for l in lines[1:] if " device" in l and "offline" not in l]
            device_state = "online" if res.returncode == 0 and devices else "none"
            if device_state == "none":
                findings.append(tr(
                    "Thiết bị ngoại vi: không có máy online. Chạy python3 .agents/devkit/bin/proof-capture.py — lệnh mở AVD rồi chụp. Không screencap serial chết, không lấy máy denylist.",
                    "Devices: none online. Run python3 .agents/devkit/bin/proof-capture.py — it boots the AVD and captures. Do not screencap a dead serial or a denylisted phone."))
        except (OSError, subprocess.SubprocessError) as e:
            device_state = "unverified"
            findings.append(tr(f"Thiết bị ngoại vi: KHÔNG xác minh được — không chạy được 'adb devices -l' ({type(e).__name__})",
                               f"Devices: NOT verified — could not run 'adb devices -l' ({type(e).__name__})"))

    image_hashes = {}
    proof_dirs = [
        base_dir / ".claude" / "audit-gate",
        base_dir / "reports"
    ]
    brain_sessions = brain_sessions_for_project(base_dir)
    proof_dirs.extend(brain_sessions)
    total_images = 0
    duplicate_images = []
    zero_byte_images = []
    # Every run read and sha256-hashed every proof image again, for a warning (A14, 2026-10-09: 300 x 1 MB = 300 MB per
    # gate run). The digest is remembered per (path, size, mtime) next to run_proof_block's hash cache
    # (<git-common-dir>/postfix-gate/); a rewritten image has a new mtime and is read again. ponytail: an agent can
    # write a wrong digest into that file and hide this duplicate WARNING (never a block); key by inode+ctime if that is seen.
    sha_path = _proof_hash_cache_path(base_dir)
    sha_path = sha_path and os.path.join(os.path.dirname(sha_path), "proof-sha-cache.json")
    try:
        with os.fdopen(_state_fd(sha_path), encoding="utf-8") as f:
            known = json.load(f)
        known = known if isinstance(known, dict) else {}
    except (OSError, ValueError, TypeError):
        known = {}
    seen = {}

    for pdir in proof_dirs:
        if pdir.exists():
            for img_file in list(pdir.glob("*.jpg")) + list(pdir.glob("*.png")):
                total_images += 1
                try:
                    st = img_file.stat()
                except OSError:
                    continue
                if st.st_size == 0:
                    zero_byte_images.append(img_file.name)
                    continue
                try:
                    key = str(img_file.resolve())
                    entry = known.get(key)
                    if isinstance(entry, list) and len(entry) == 3 and entry[:2] == [st.st_size, st.st_mtime_ns] \
                            and isinstance(entry[2], str):
                        h = entry[2]
                    else:
                        with open(img_file, "rb") as f:
                            h = hashlib.sha256(f.read()).hexdigest()
                    seen[key] = [st.st_size, st.st_mtime_ns, h]
                    if h in image_hashes and image_hashes[h] != img_file.name:
                        duplicate_images.append((img_file.name, image_hashes[h]))
                    else:
                        image_hashes[h] = img_file.name
                except OSError:
                    pass
    if sha_path and seen != known:   # only the images seen now: the file never grows past them
        tmp = None
        try:
            os.makedirs(os.path.dirname(sha_path), exist_ok=True)
            fd, tmp = tempfile.mkstemp(prefix=".tmp_proof_sha.", dir=os.path.dirname(sha_path))
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(seen, f)
            os.replace(tmp, sha_path)
        except OSError:   # a cache that cannot be written only costs the next run a re-read
            if tmp:
                with contextlib.suppress(OSError):
                    os.unlink(tmp)

    if zero_byte_images:
        findings.append(tr(f"Phát hiện {len(zero_byte_images)} ảnh chụp minh chứng 0-byte (Corrupt/Blank)",
                           f"{len(zero_byte_images)} zero-byte proof images (corrupt/blank)"))
    if duplicate_images:
        findings.append(tr(f"Phát hiện {len(duplicate_images)} ảnh chụp trùng mã băm SHA-256 (Màn hình đơ / Duplicate proof)",
                           f"{len(duplicate_images)} proof images with identical SHA-256 (frozen screen / duplicate proof)"))

    return len(findings) == 0, findings, total_images, device_state, len(brain_sessions)


def record_lesson(base_dir: Path, lesson: str, cause: str, prevention: str):
    """Same writer as `agent-kit learn` (bin/instincts.py): next [INSTINCT-NNN] id,
    a title already recorded is not added twice."""
    instincts_file = base_dir / ".agents" / "instincts.md"
    try:
        status, inst_id, _ = append_lesson(instincts_file, lesson, cause=cause, rule=prevention,
                                           check="postfix-gate --run-tests")
    except (OSError, ValueError) as e:
        print(f"{YELLOW}⚠ {tr('Không thể ghi vào', 'Cannot write to')} {instincts_file}: {e}{RESET}")
        return
    if status == "duplicate":
        print(f"{YELLOW}⚠ {tr('Bài học đã có sẵn', 'Lesson already recorded')}: [{inst_id}] — {tr('không ghi trùng', 'not added again')}{RESET}")
    else:
        print(f"{GREEN}✔ {tr('Đã ghi bài học kinh nghiệm', 'Lesson recorded')} [{inst_id}] {tr('vào', 'in')} {instincts_file}{RESET}")


def checklist_covers() -> dict:
    """{test_id: [files]} linked via `regression_checklist.py link UNCOVERED:<file> <TEST>`."""
    path = get_project_dir() / ".agents" / "regression_status.json"
    try:
        items = json.loads(path.read_text(encoding="utf-8")).get("items", {})
    except (OSError, ValueError, AttributeError):
        return {}
    return {tid: list(it.get("covers", [])) for tid, it in items.items()
            if isinstance(it, dict) and it.get("kind") == "test" and it.get("covers")}


def overlay_bind(project_dir, matrix_arg) -> dict:
    """What a worktree's recorded results are bound to besides the suite's own files: the matrix and the local state (the same
    keys cached_full_pass gives a reused full PASS)."""
    return {"matrix_sha": _sha_file(find_matrix_path(matrix_arg)), "local_sha": local_state_sha(project_dir),
            "result_format": RESULT_FORMAT}


def stale_suite_ids(matrix_arg=None) -> set:
    """Checklist test suites whose PASS went STALE (code changed since the run): `--full` re-runs
    them, so a full PASS never stands next to rows that still need a re-run (GeelyEx2 2026-09-26)."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
        data = rc.load(get_project_dir())
        if rc.skip_bookkeeping(get_project_dir()):   # a LINKED worktree: what its own gate runs proved (never the tracked file)
            try:
                rc.apply_overlay(data, get_project_dir(), lambda: overlay_bind(get_project_dir(), matrix_arg))
            except Exception:  # noqa: BLE001 - an overlay that cannot be read counts as none: the STALE suites run, as before
                pass
        rc.mark_stale(data, get_project_dir())
    except (ImportError, OSError, ValueError, AttributeError) as e:
        log_warn(tr(f"Không đọc được checklist để tìm suite STALE ({e}) — --full chỉ chạy suite bị ảnh hưởng",
                    f"Cannot read the checklist for STALE suites ({e}) — --full runs the impacted suites only"))
        return set()
    return {tid for tid, it in data.get("items", {}).items()
            if isinstance(it, dict) and it.get("kind") == "test" and rc.effective_status(data, it) == "STALE"}


def rule_watch(rule, covers) -> list:
    """A rule's watch patterns + files linked to any of its tests in the checklist."""
    extra = [f for t in rule.get("mandatory_regression_tests", []) for f in covers.get(t.get("id"), [])]
    return list(rule.get("watch_files", [])) + extra


# Top-level folders that hold agent material or evidence, never the product's code:
# a moved JUnit XML under docs/ or a workflow script under .agents/local/ needs no test.
NOT_CODE_ROOTS = ("docs", ".agents", ".claude")


def profile_source_exts() -> set:
    """What counts as code needing a regression test: the active profile's
    source_extensions — the same list the hooks and matrix_detect use — so an .xml
    layout or a .js tool is not "uncovered code" in an Android project."""
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "hooks"))
        sys.dont_write_bytecode = True     # no __pycache__ inside the linked hooks/ folder
        from devkit_profile import source_exts
        return set(source_exts(str(get_project_dir())))
    except Exception:  # noqa: BLE001 — a missing/broken profile falls back to the fixed list
        return set(CODE_EXTENSIONS)


def active_profile_name() -> str:
    """The active profile's name (.agents/active-profile.json), for a matrix without "project"."""
    try:
        f = get_project_dir() / ".agents" / "active-profile.json"
        if not f.is_file():
            f = get_project_dir() / ".active-profile.json"      # before DevKit 1.3
        d = json.loads(f.read_text(encoding="utf-8"))
        return d.get("name") or d.get("profile") or tr("(không có profile)", "(no profile)")
    except (OSError, ValueError, AttributeError):
        return tr("(không có profile)", "(no profile)")


# Not .txt or images: requirements.txt, app assets and drawables are read by the program.
DOC_EXT = (".md", ".rst", ".adoc")
DOC_NAMES = {"LICENSE", "NOTICE", "AUTHORS", "CODEOWNERS"}
# What the agent's own tooling writes: proof screenshots, the Antigravity PM config, the device
# denylist, agent memory. No program reads them, so they need no regression test either
# (OfficeReader 2026-09-27: a roadmap edit next to them stayed UNVERIFIED for 12 Stops).
# The agents' own harness config (.claude/settings*.json) is read by no project program either
# (2026-09-29, Goods: a settings-only commit needed a full Unity gate to be pushed). A project that
# does test it (a matrix rule watching the file) keeps that test: coverage comes from the matrix.
AGENT_STATE_FILES = {".antigravity-pm.json", ".adb-denylist", ".claude/settings.json", ".claude/settings.local.json"}


def needs_no_test(rel_file: str) -> bool:
    """Documentation or agent state: nothing a regression test could catch."""
    clean = rel_file.replace("\\", "/")
    return (clean.lower().endswith(DOC_EXT) or Path(clean).name in DOC_NAMES
            # Chỉ git đọc `.gitignore` (17/10: PR K7 của 4 repo kẹt ở merge gate vì "không có test khớp"); rule nào theo dõi nó vẫn giữ test.
            or Path(clean).name == ".gitignore"
            # Bản chép script super-board của agent-workbench (test ở đó, tests/super-board/); 17/10: PR đưa merge gate vào 4 repo kẹt như trên.
            or clean.startswith(".claude/bin/super-board-")
            # 21/10 (#78): skill, schema and wave workflow chép từ agent-workbench cũng vậy; chỉ đúng các đường dẫn này, không theo tiền tố .claude/ rộng.
            or clean.startswith((".claude/skills/super-board/", ".claude/skills/super-review/"))
            or clean == ".claude/workflows/super-board-wave.js"
            or clean in AGENT_STATE_FILES or clean.startswith((".agents/local/memory/", ".agents/local/red-patches/"))   # red_proof's bug-back patches: data of the proof tool
            or re.fullmatch(r"reports/proof-[^/]+\.png", clean) is not None
            # What the project's tooling writes under reports/ (Goods: its PlayMode screen tour saves
            # reports/tour-<time>/…), like tree_fp. Never source: a Django app called reports/ keeps its code.
            # ponytail: a data file a program reads from reports/ also skips; narrow to a pattern when one does.
            or (clean.startswith("reports/") and Path(clean).suffix.lower() not in profile_source_exts())
            # A tool-written log (pre-push red-patch-gate, GeelyEx2 2026-09-28), like tree_fp's
            # off-screen *.log. ponytail: a .log fixture production code reads also skips.
            or clean.lower().endswith(".log"))


# Exempt from regression SUITES above, not from every check (25/10): 11 of 11 app repos have no matrix rule watching
# .claude/settings.json, so a commit that dropped the Stop hook wiring passed with none. run_settings_audit() checks it.
SETTINGS_FILES = (".claude/settings.json", ".claude/settings.local.json")
_AGENT_HEALTH = []


def _registered_hook_scripts(settings) -> list:
    """bin/agent-health.py's reader of the hook script paths (one copy, INSTINCT-015), loaded on first use."""
    if not _AGENT_HEALTH:
        import importlib.util  # noqa: PLC0415 - hyphenated sibling module in bin/
        spec = importlib.util.spec_from_file_location("agent_health", Path(__file__).resolve().parent / "agent-health.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _AGENT_HEALTH.append(mod)
    return _AGENT_HEALTH[0].registered_hook_scripts(settings)


def settings_problems(rel_file: str, text, root: Path) -> list:
    """(vi, en) labels of what breaks the hook wiring in this content of .claude/settings.json or settings.local.json;
    [] when sound. text None = the file is deleted. Shared with bin/push_gate.py, which passes the blob it pushes.
    settings.local.json usually holds permissions only, so it needs no hooks of its own (core-rules §3 must-allow).
    ponytail: settings.json must keep a non-empty "hooks" block, so a project that wires no Claude hook on purpose (the kit
    installed for other agents only) is refused any edit of it; key the rule on the base version having hooks when one shows up."""
    is_main = rel_file.replace("\\", "/") == ".claude/settings.json"
    if text is None:
        return [("đã xoá: mọi hook Claude Code của dự án thôi chạy", "deleted: every Claude Code hook of the project stops running")] if is_main else []
    try:
        settings = json.loads(text)
    except ValueError as e:
        return [(f"không phải JSON hợp lệ ({e})", f"not valid JSON ({e})")]
    if not isinstance(settings, dict):
        return [("không phải một object JSON", "not a JSON object")]
    if is_main and not (isinstance(settings.get("hooks"), dict) and settings["hooks"]):
        return [('"hooks" rỗng hoặc thiếu: không hook nào chạy (chạy lại agent-kit init)',
                 '"hooks" is empty or missing: no hook runs (re-run agent-kit init)')]
    try:
        scripts = _registered_hook_scripts(settings)
    except ValueError as e:
        return [(f"khối hooks sai dạng, Claude Code không đọc được: {e}", f"malformed hooks block Claude Code cannot read: {e}")]
    except Exception as e:   # noqa: BLE001 - agent-health.py not loadable: the wiring cannot be judged, never a silent pass
        return [(f"không kiểm được dây nối hook ({e!r})", f"cannot check the hook wiring ({e!r})")]
    kit_hooks = get_devkit_dir() / "hooks"
    missing = []
    for rel in dict.fromkeys(scripts):
        name = rel[len(".claude/hooks/"):] if rel.startswith(".claude/hooks/") else ""
        # .claude/hooks/ holds the git-ignored links `agent-kit init` makes: a hook the kit ships is wired once it is installed
        if (root / rel).exists() or (name and "/" not in name and (kit_hooks / name).is_file()):
            continue
        missing.append(rel)
    return [(f"hook chạy file không tồn tại: {rel}", f"hook runs a file that does not exist: {rel}") for rel in missing]


def run_settings_audit(modified_files: list) -> tuple:
    """The static check of a changed .claude/settings*.json: valid JSON, settings.json keeps a non-empty "hooks", every hook
    script it runs from the project or .agents/devkit exists. Content as the other checks read it (the staged blob with --staged)."""
    findings = []
    for rel_file in modified_files:
        if rel_file.replace("\\", "/") not in SETTINGS_FILES:
            continue
        text = read_changed_text(rel_file)
        if text is None and rel_file not in DELETED_FILES:
            continue   # a link or an unreadable file: the unreadable check names it
        for label in settings_problems(rel_file, text, get_project_dir()):
            findings.append((rel_file, _L(label)))
            _record("settings", rel_file, label)
    return len(findings) == 0, findings


# A document a test READS stays a test even as Markdown (OfficeReader: androidTest/assets/test_files/*.md).
FIXTURE_DIR_NAMES = {"assets", "resources", "fixtures", "testfixtures", "testdata", "test_files", "samples"}


def is_test_doc(rel_file: str) -> bool:
    """A README or a Markdown file under the top-level docs/ that merely sits in a test-named directory (GeelyEx2
    docs/specs/*.md, OfficeReader app/src/test/snapshots/README.md): not a test, so editing it is not "an
    existing test edited". Nothing else qualifies: a golden .md, a .log fixture or code under reports/ is still
    a test (review 2026-10-04: needs_no_test here switched the oracle guard off for them)."""
    clean = rel_file.replace("\\", "/")
    parts = clean.lower().split("/")
    if not clean.lower().endswith(DOC_EXT) or any(p in FIXTURE_DIR_NAMES for p in parts[:-1]):
        return False
    # readme.md, not readme_parser_test.md; the TOP-LEVEL docs/ only (tests/docs/test_parser.md is a test)
    return parts[-1].split(".")[0] == "readme" or parts[0] == "docs"


def new_orphan_tests(modified_files, matrix, base_ref) -> tuple:
    """(sure, possible) new test files — absent at base_ref and not a rename of a test that was there
    (a copy is a new test). sure: no rule watches the path and no suite command / script / task file
    names it (regression_checklist.sure_orphans) — the only thing --full blocks on. possible: the
    runner analysis sees no suite run it (a heuristic): a warning and a checklist row, never a block.
    GeelyEx2 tests/scripts/test-retrace-treo.py (28/09/2026) ran only by hand."""
    if not (matrix or {}).get("rules"):
        return [], []
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
    except ImportError:
        return [], []
    prefix = get_project_prefix()
    cands = [f for f in modified_files if f not in DELETED_FILES and rc.is_test_candidate(f)]
    prefetch_blobs(base_ref, [prefix + f for f in cands])   # one git process, not one `cat-file -e` per file (A12)
    new = [f for f in cands if object_info(base_ref, prefix + f) is None]
    if not new:
        return [], []
    # A renamed test keeps its history; a copy is one more test nothing may run.
    raw = subprocess.run(["git", "-C", str(get_project_dir()), "diff", "-M", "--name-status", "-z", "--relative",
                          base_ref, "--", "."], capture_output=True).stdout.decode("utf-8", "surrogateescape").split("\0")
    moved, j = set(), 0
    while j < len(raw):
        if raw[j][:1] in ("R", "C") and j + 2 < len(raw):
            if raw[j][0] == "R" and rc.is_test_candidate(raw[j + 1]):
                moved.add(raw[j + 2])
            j += 3
        else:
            j += 2 if raw[j] else 1
    new = [f for f in new if f not in moved]
    if not new:
        return [], []
    project = get_project_dir()
    index = rc.suite_index(project, matrix)
    sure = rc.sure_orphans(project, matrix, new, index=index)
    return sure, [f for f in rc.orphan_tests(project, matrix, candidates=new, index=index) if f not in sure]


def uncovered_code_files(modified_files, rules, covers=None) -> list:
    """Changed source files that no matrix rule watches — changes nothing will re-test later."""
    covers = checklist_covers() if covers is None else covers
    watch = [pat for rule in rules for pat in rule_watch(rule, covers)]
    exts = profile_source_exts()
    return [
        f for f in modified_files
        if f not in DELETED_FILES and Path(f).suffix in exts
        and f.replace("\\", "/").split("/")[0] not in NOT_CODE_ROOTS
        and not is_test_path(f) and not any(match_pattern(f, pat) for pat in watch)
    ]


_RUNNER_FOLLOW_EXT = (".sh", ".bash", ".zsh")
_INTERPRETER = re.compile(r"(?:ba|z|da|k)?sh|source|\.|python[\d.]*|node|ruby|perl|php|pwsh")
_PREFIX_WORDS = {"exec", "env", "command", "time", "nohup", "nice"}


def _run_words(seg: str) -> list:
    """The file a command segment RUNS: its first word when that is a path (`./gradlew`, `scripts/ci`), or the script an
    interpreter is given (`sh scripts/check.sh`, `python3 -u tools/run.py`). Never an argument the command only reads
    (`grep -q x src/core.py`), nor a module or inline code (`python3 -m pytest`, `bash -c '…'`)."""
    words = [w.strip("'\"") for w in seg.split()]
    i = 0
    while i < len(words) and ("=" in words[i] or os.path.basename(words[i]) in _PREFIX_WORDS):
        i += 1
    if i >= len(words):
        return []
    if _INTERPRETER.fullmatch(os.path.basename(words[i])):
        for w in words[i + 1:]:
            if w in ("-m", "-c", "-e"):
                return []
            if not w.startswith("-"):
                return [w]
        return []
    return [words[i]] if "/" in words[i] else []


def suite_runner_paths(matrix: dict, ref: str, candidates: set) -> set:
    """The candidates (project-relative paths) a suite command of the matrix runs (A2, 2026-10-09): the file a command
    segment runs (_run_words: `sh scripts/check.sh`, `./gradlew`, `python3 tools/run.py`), and what the shell scripts
    it runs run in turn, read at `ref` — two levels, as deep as regression_checklist.suite_index reads. Task files
    (Makefile, package.json, tox.ini) and build wrappers (gradlew) are not followed; a word with $VAR or `…` is not
    resolved."""
    if not candidates:
        return set()
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
    except ImportError:
        return set()
    prefix = get_project_prefix()
    found, seen = set(), set()
    level = [(t["command"], "", True) for rule in (matrix or {}).get("rules") or [] if isinstance(rule, dict)
             for t in rule.get("mandatory_regression_tests") or [] if isinstance(t, dict) and isinstance(t.get("command"), str)]
    for depth in range(3):   # the commands, the scripts they name, the scripts those name
        scripts = []
        for text, here, top in level:
            for line in ([text] if top else rc._command_lines(text)):
                for cwd, seg in rc._segments(line):
                    for tok in _run_words(seg):
                        if not tok or "$" in tok or "`" in tok:
                            continue
                        for cand in dict.fromkeys(os.path.normpath(os.path.join(d, tok)).replace("\\", "/") for d in (cwd, "", here)):
                            if cand in seen or cand in (".", "..") or cand.startswith(("../", "/")):
                                continue
                            seen.add(cand)
                            if cand in candidates:
                                found.add(cand)
                            suffix = Path(cand).suffix
                            if depth < 2 and Path(cand).name not in ("gradlew", "mvnw") and (
                                    suffix in _RUNNER_FOLLOW_EXT or (suffix == "" and "/" in tok)):
                                scripts.append(cand)
        if not scripts:
            break
        prefetch_blobs(ref, [prefix + s for s in scripts])
        level = []
        for s in scripts:
            data = blob_at(ref, prefix + s)
            if data and b"\0" not in data[:8000]:
                level.append((data.decode("utf-8", errors="replace"), os.path.dirname(s), False))
    return found


# ── Impacted-test selection ────────────────────────────────────────────────────────
# A matrix test may declare "impacted_command": the same runner limited to the tests the
# change can affect, through one placeholder:
#   {gradle_tests}               --tests 'pkg.FooTest' --tests …   (one Gradle module)
#   {gradle_module_tests:<task>} :mod:<task> --tests 'pkg.FooTest' … per module
#   {unity_filter}               --filter 'Ns.FooTests;Ns.BarTests' (unity-batch.sh; the
#                                platform is read from the template: editmode / playmode)
#   {pytest_nodes}               /abs/tests/test_foo.py …
#   {jest_paths}                 /abs/src/foo.test.ts …
# Changed files of the rule are mapped to tests by (a) a test named <Class>Test(s),
# (b) tests that name one of the changed file's declarations, (c) changed tests
# themselves. Anything the map cannot vouch for runs the full command: a file that is
# not source code (build files, resources, manifests), a deleted file, a changed class
# no test names, shared code named by more than POSTFIX_GATE_IMPACTED_REF_CAP tests,
# more than POSTFIX_GATE_IMPACTED_CAP selected tests, an identifier unsafe to put in a
# shell command. `--full`, POSTFIX_GATE_FULL=1, CI=true and --record-lesson always run
# the full command. Name matching cannot see a test that reaches the class only
# through another class: an impacted PASS is a fast check, never the handover run.

IMPACTED_CAP_DEFAULT = 40
IMPACTED_REF_CAP_DEFAULT = 15
_SAFE_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$")
_SAFE_PATH = re.compile(r"^[A-Za-z0-9_./@+\-]+$")
_SAFE_GRADLE_PATH = re.compile(r"^(:[A-Za-z0-9_.\-]+)*$")
_GRADLE_MODULE_TESTS = re.compile(r"\{gradle_module_tests:([A-Za-z0-9_]+)\}")
_SKIP_WALK = {"build", ".gradle", ".git", "node_modules", ".idea", ".cxx", ".kotlin", "out",
              "Library", "Temp", "Logs", "obj", ".venv", "venv", "__pycache__", "site-packages",
              "dist", "coverage", ".next"}
_JVM_TEST_MARK = re.compile(r"@(?:Test|ParameterizedTest|TestFactory|RepeatedTest|Theory)\b"
                            r"|\b(?:FunSpec|StringSpec|DescribeSpec|BehaviorSpec|ShouldSpec|WordSpec"
                            r"|FreeSpec|FeatureSpec|ExpectSpec|AnnotationSpec)\b|\bextends\s+TestCase\b")
_CS_TEST_MARK = re.compile(r"\[\s*(?:Test|UnityTest|TestCase|TestCaseSource|TestFixture)\b")
# Top-level declarations (column 0; `private` ones are invisible to tests). A generic or
# receiver we cannot parse yields a common word, which the reference cap turns into a full run.
_KT_DECL = re.compile(r"^(?!private\b)(?:@[\w.]+(?:\([^)\n]*\))?\s+)*(?:(?:public|internal|protected|open|final|abstract"
                      r"|sealed|data|enum|annotation|inline|value|inner|suspend|operator|infix|tailrec|external"
                      r"|const|lateinit|expect|actual|static|strictfp|synchronized)\s+)*"
                      r"(?:fun\s+interface|class|interface|object|typealias|fun|val|var|record|@interface)\s+"
                      r"(?:<[^>\n]*>\s*)?([A-Za-z_][\w.]*)", re.M)
_JVM_TEST_CLASS = re.compile(r"^(?:(?:public|internal|open|final|data)\s+)*class\s+([A-Za-z_]\w*)", re.M)
_CS_DECL = re.compile(r"\b(?:class|struct|interface|enum|record)\s+([A-Za-z_]\w*)")
_CS_TEST_CLASS = re.compile(r"^\s*(?:\[[^\]\n]*\]\s*)*(?:(?:public|internal|sealed|static|partial)\s+)*class\s+([A-Za-z_]\w*)", re.M)
_PY_DECL = re.compile(r"^(?:async\s+)?(?:def|class)\s+([A-Za-z]\w*)", re.M)
_JS_DECL = re.compile(r"\bexport\s+(?:default\s+)?(?:async\s+)?(?:function\*?|class|const|let|var|interface|type|enum)\s+([A-Za-z_$][\w$]*)")

_GLOBAL_TEST_FILES = re.compile(r"^(?:conftest\.py|__init__\.py|setup\.py|(?:jest|vitest)\.(?:config|setup)\.[cm]?[jt]s"
                                r"|setupTests\.[cm]?[jt]sx?|test[-_]?setup\.[cm]?[jt]sx?)$")

_IMPACTED_KINDS = {
    "gradle": {".kt", ".java"},
    "unity": {".cs"},
    "pytest": {".py"},
    "jest": {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"},
}


def _int_env(name, default):
    try:
        return max(1, int(os.environ.get(name) or default))
    except ValueError:
        return default


def force_full_reason(args):
    """Why this run must use the full commands, or None (selection allowed)."""
    if getattr(args, "full", False):
        return "--full"
    if getattr(args, "force_full", False):
        return "--force-full"
    if os.environ.get("POSTFIX_GATE_FORCE_FULL") == "1":
        return "POSTFIX_GATE_FORCE_FULL=1"
    if os.environ.get("POSTFIX_GATE_FULL") == "1":
        return "POSTFIX_GATE_FULL=1"
    if (os.environ.get("CI") or "").lower() in ("1", "true", "yes"):
        return "CI"
    if getattr(args, "record_lesson", None):
        return tr("--record-lesson (nghiệm thu)", "--record-lesson (acceptance)")
    return None


def _impacted_kind(template):
    kinds = []
    if "{gradle_tests}" in template or _GRADLE_MODULE_TESTS.search(template):
        kinds.append("gradle")
    for kind, ph in (("unity", "{unity_filter}"), ("pytest", "{pytest_nodes}"), ("jest", "{jest_paths}")):
        if ph in template:
            kinds.append(kind)
    return kinds[0] if len(kinds) == 1 else None


def _read_small(path):
    try:
        if path.stat().st_size > 2_000_000:
            return None
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def _walk_files(root, exts):
    """Project-relative-to-root file paths under root with one of exts, build output skipped."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in _SKIP_WALK and not d.startswith(".")]
        for name in filenames:
            if os.path.splitext(name)[1] in exts:
                yield Path(dirpath) / name


def _gradle_source_set(rel):
    """(module_root, source_set_kind) for a Gradle source path, kind in main / test /
    helper / instrumented; None when the path is not under <module>/src/<set>/."""
    parts = rel.split("/")
    if "src" not in parts[:-2]:
        return None
    i = parts.index("src")
    sset = parts[i + 1]
    low = sset.lower()
    if "androidtest" in low or "instrumented" in low:
        kind = "instrumented"
    elif low == "testfixtures":
        kind = "helper"
    elif low.startswith("test") or low.endswith("test"):
        kind = "test"
    else:
        kind = "main"
    return "/".join(parts[:i]), kind


def _gradle_root(project_dir, module_root):
    """Nearest ancestor of the module holding settings.gradle(.kts), inside the project."""
    cur = (project_dir / module_root) if module_root else project_dir
    while True:
        if (cur / "settings.gradle.kts").exists() or (cur / "settings.gradle").exists():
            return cur
        if cur == project_dir or project_dir not in cur.parents:
            return project_dir
        cur = cur.parent


_CD_PREFIX = re.compile(r"""^\s*\(?\s*cd\s+(["']?)([^"'&;|()]+?)\1\s*(?:&&|;)""")
_GRADLE_P = re.compile(r"""gradlew\b[^;&|]*?\s(?:-p|--project-dir)(?:\s+|=)(["']?)([^\s"';&|()]+)\1""")
_GRADLE_BARE = re.compile(r"""^\s*(?:\./)?gradlew\b|^\s*gradle\b""")


def _command_gradle_dir(project_dir, command):
    """Directory a matrix command runs Gradle in — `cd <dir> &&|;` (also in a subshell),
    `gradlew -p|--project-dir <dir>`, or a bare `./gradlew …` (the project) — or None when the
    command has another shape, and callers then skip the composite-build check."""
    command = command or ""
    m = _CD_PREFIX.match(command) or _GRADLE_P.search(command)
    if m:
        d = project_dir / m.group(2).strip()
    elif _GRADLE_BARE.match(command):
        d = project_dir
    else:
        return None
    # The command's own dir, not the build root above it: from `cd app && ../gradlew` a bare task
    # runs only :app, so narrowing to a sibling module would skip the tests the matrix asked for
    # (review 3). Such commands run in full — slower, never a false PASS.
    try:
        return d.resolve()
    except OSError:
        return d


class _TestIndex:
    """Test-side files of one scope: {path: text}, split into runnable tests and helpers."""

    def __init__(self, tests, helpers):
        self.tests, self.helpers = tests, helpers


def _gradle_index(project_dir, groot, cache):
    key = ("gradle", str(groot))
    if key not in cache:
        tests, helpers = {}, {}
        for p in _walk_files(groot, _IMPACTED_KINDS["gradle"]):
            rel = p.relative_to(project_dir).as_posix()
            info = _gradle_source_set(rel)
            if not info or info[1] not in ("test", "helper"):
                continue
            text = _read_small(p)
            if text is None:
                continue
            is_test = info[1] == "test" and _JVM_TEST_MARK.search(text) and _JVM_TEST_CLASS.search(text)
            (tests if is_test else helpers)[rel] = text
        cache[key] = _TestIndex(tests, helpers)
    return cache[key]


def _unity_index(project_dir, cache):
    key = ("unity",)
    if key not in cache:
        tests, helpers = {}, {}
        for top in ("Assets", "Packages"):
            if not (project_dir / top).is_dir():
                continue
            for p in _walk_files(project_dir / top, {".cs"}):
                text = _read_small(p)
                if text is None:
                    continue
                rel = p.relative_to(project_dir).as_posix()
                if _CS_TEST_MARK.search(text):
                    tests[rel] = text
                elif is_test_path(rel):
                    helpers[rel] = text
        cache[key] = _TestIndex(tests, helpers)
    return cache[key]


def _script_index(project_dir, kind, cache):
    key = (kind,)
    if key not in cache:
        tests, helpers = {}, {}
        for p in _walk_files(project_dir, _IMPACTED_KINDS[kind]):
            rel = p.relative_to(project_dir).as_posix()
            if not is_test_path(rel):
                continue
            text = _read_small(p)
            if text is None:
                continue
            name = p.name
            runnable = (re.match(r"^test_.*\.py$|^.*_test\.py$", name) if kind == "pytest"
                        else re.search(r"\.(test|spec)\.[cm]?[jt]sx?$", name) or "__tests__" in rel.split("/"))
            (tests if runnable else helpers)[rel] = text
        cache[key] = _TestIndex(tests, helpers)
    return cache[key]


def _declared_symbols(kind, rel, text):
    stem = Path(rel).stem
    if kind == "gradle":
        names = [m.group(1).rsplit(".", 1)[-1] for m in _KT_DECL.finditer(text)]
    elif kind == "unity":
        names = _CS_DECL.findall(text)
    elif kind == "pytest":
        names = [n for n in _PY_DECL.findall(text) if not n.startswith("_")]
    else:
        names = _JS_DECL.findall(text)
        stem = stem.split(".")[0]
    return sorted({n for n in names + [stem] if n and n != "Companion"})


def _unity_platform(project_dir, rel):
    """EditMode when the nearest .asmdef targets only the Editor (or, without one, the
    file sits in an Editor/ folder); PlayMode otherwise."""
    cur = (project_dir / rel).parent
    while cur != project_dir and project_dir in cur.parents:
        for asm in cur.glob("*.asmdef"):
            try:
                plats = json.loads(asm.read_text(encoding="utf-8", errors="replace")).get("includePlatforms") or []
            except (OSError, ValueError, AttributeError):
                plats = []
            return "EditMode" if plats == ["Editor"] else "PlayMode"
        cur = cur.parent
    return "EditMode" if "Editor" in rel.split("/")[:-1] else "PlayMode"


def _test_names(kind, rel, text):
    """What the runner filter needs for one test file (FQCNs, or the file itself)."""
    if kind in ("gradle", "unity"):
        if kind == "gradle":
            pkg = re.search(r"^\s*package\s+([\w.]+)", text, re.M)
            classes = _JVM_TEST_CLASS.findall(text)
        else:
            pkg = re.search(r"^\s*namespace\s+([\w.]+)", text, re.M)
            classes = [c for c in _CS_TEST_CLASS.findall(text)]
        prefix = (pkg.group(1).rstrip(".") + ".") if pkg else ""
        return [prefix + c for c in dict.fromkeys(classes)]
    return [rel]


def select_impacted_tests(project_dir, template, files, cap=None, ref_cap=None, cache=None, deleted=()):
    """Map the rule's changed files to the tests that can see them.

    Returns {"ok": bool, "reason": str, "tests": {test_file: [names]}, "why": {test_file:
    "name"|"reference"|"changed"}, "kind": str}. ok=False means: run the full command.
    """
    project_dir = Path(project_dir)
    cap = cap or _int_env("POSTFIX_GATE_IMPACTED_CAP", IMPACTED_CAP_DEFAULT)
    ref_cap = ref_cap or _int_env("POSTFIX_GATE_IMPACTED_REF_CAP", IMPACTED_REF_CAP_DEFAULT)
    cache = {} if cache is None else cache
    kind = _impacted_kind(template)
    out = {"ok": False, "reason": "", "tests": {}, "why": {}, "kind": kind}

    def full(reason):
        out.update(ok=False, reason=reason, tests={}, why={})
        return out

    if kind is None:
        return full(tr("impacted_command không có (hoặc có nhiều hơn một) placeholder đã biết",
                       "impacted_command has no (or more than one) known placeholder"))
    if not files:
        return full(tr("không có file nào của luật để chọn test", "no file of the rule to select tests from"))
    exts = _IMPACTED_KINDS[kind]
    for f in files:
        rel = f.replace("\\", "/")
        if f in deleted:
            return full(tr(f"{rel} bị xoá/đổi tên", f"{rel} was deleted/renamed"))
        if Path(rel).suffix.lower() not in exts:
            if kind == "unity" and Path(rel).suffix.lower() in _UNITY_ASSET_EXT:
                index = _unity_index(project_dir, cache)
                hits = unity_asset_tests(project_dir, rel, index)
                if not hits:
                    return full(tr(f"{rel}: không test nào giữ GUID/tên asset này",
                                   f"{rel}: no test holds this asset GUID or name"))
                for t in hits:
                    out["tests"].setdefault(t, _test_names(kind, t, index.tests[t]))
                    out["why"].setdefault(t, "guid")
                continue
            return full(tr(f"{rel} không phải mã nguồn bản đồ test hiểu được (build/resource/config)",
                           f"{rel} is not source code the test map understands (build/resource/config file)"))
        # Code every test sees without naming it: build logic, pytest's conftest (autouse
        # fixtures), package __init__, test-runner setup files.
        if (set(rel.split("/")[:-1]) & {"buildSrc", "build-logic"}
                or _GLOBAL_TEST_FILES.match(Path(rel).name)):
            return full(tr(f"{rel} tác động mọi test mà không cần gọi tên (build logic / conftest / setup)",
                           f"{rel} affects every test without being named (build logic / conftest / setup)"))
        text = _read_small(project_dir / rel)
        if text is None:
            return full(tr(f"{rel} không đọc được", f"{rel} cannot be read"))
        if kind == "gradle":
            info = _gradle_source_set(rel)
            if not info or info[1] == "instrumented":
                return full(tr(f"{rel} không nằm trong source set main/test của một module Gradle",
                               f"{rel} is not in a main/test source set of a Gradle module"))
            index = _gradle_index(project_dir, _gradle_root(project_dir, info[0]), cache)
        elif kind == "unity":
            index = _unity_index(project_dir, cache)
        else:
            index = _script_index(project_dir, kind, cache)

        if rel in index.tests:                                   # (c) a changed test
            out["tests"][rel] = _test_names(kind, rel, text)
            out["why"].setdefault(rel, "changed")
            continue
        # (a) + (b): a changed class (or a test helper) → the tests that name it; a helper
        # that names it passes the question on to the tests that name the helper.
        found, frontier, seen = {}, [(rel, text)], {rel}
        for _depth in range(3):
            nxt = []
            for src_rel, src_text in frontier:
                symbols = _declared_symbols(kind, src_rel, src_text)
                if not symbols:
                    return full(tr(f"{src_rel}: không tìm thấy khai báo nào để dò test",
                                   f"{src_rel}: no declaration found to look tests up by"))
                stem = Path(src_rel).stem.split(".")[0]
                word = re.compile(r"\b(?:" + "|".join(map(re.escape, symbols)) + r")\b")
                named = {t for t in index.tests
                         if re.match(re.escape(stem) + r"(Test|Tests|Spec|_test|\.test|\.spec)?$",
                                     Path(t).stem.split(".")[0] if kind == "jest" else Path(t).stem)
                         or Path(t).stem in ("test_" + stem, stem + "_test", stem + "Test", stem + "Tests")}
                refs = {t for t, body in index.tests.items() if t not in seen and word.search(body)}
                for t in named:
                    found.setdefault(t, "name")
                for t in refs:
                    found.setdefault(t, "reference")
                if len(found) > ref_cap:
                    # Same package and name-matches only. package.* would rerun
                    # every test in a large CarConnect package.
                    found = _trim_to_package(found, rel, cap)
                for h, body in index.helpers.items():
                    if h not in seen and word.search(body):
                        seen.add(h)
                        nxt.append((h, body))
                seen.update(found)
            frontier = nxt
            if not frontier:
                break
        else:
            return full(tr(f"{rel}: chuỗi helper test quá sâu", f"{rel}: test-helper chain too deep"))
        if not found:
            return full(tr(f"{rel}: không test nào gọi tên các khai báo của nó",
                           f"{rel}: no test names any of its declarations"))
        for t, why in found.items():
            out["tests"].setdefault(t, _test_names(kind, t, index.tests[t]))
            out["why"].setdefault(t, why)

    if not out["tests"]:
        return full(tr("không chọn được test nào", "no test selected"))
    for t, names in out["tests"].items():
        if not names:
            return full(tr(f"{t}: không đọc được tên lớp test", f"{t}: cannot read its test class name"))
    count = sum(len(n) for n in out["tests"].values())
    if count > cap:
        named = {t: w for t, w in out["why"].items() if w == "name" and t in out["tests"]}
        if named:
            out["tests"] = {t: out["tests"][t] for t in named}
            out["why"] = {t: "name" for t in named}
        else:
            keep = list(out["tests"])[:cap]
            out["tests"] = {t: out["tests"][t] for t in keep}
            out["why"] = {t: out["why"].get(t, "reference") for t in keep}
    out.update(ok=True, reason="")
    return out


def _trim_to_package(found: dict, rel: str, cap: int) -> dict:
    """Name-matches first, then tests in the same Java/Kotlin package, at most cap."""
    pkg = _code_package(rel)
    named = [(t, w) for t, w in found.items() if w == "name"]
    same = [(t, w) for t, w in found.items()
            if w != "name" and pkg and _code_package(t) == pkg]
    chosen = {}
    for t, w in named + same:
        chosen.setdefault(t, w)
        if len(chosen) >= cap:
            break
    return chosen or dict(named)


def expand_impacted_command(project_dir, template, full_command, selection):
    """(command, n_tests) with the placeholder filled, or (None, reason) when it cannot be
    filled safely — the caller then runs the full command."""
    project_dir = Path(project_dir)
    kind, tests = selection["kind"], selection["tests"]
    names = [n for t in sorted(tests) for n in tests[t]]
    if kind in ("gradle", "unity"):
        bad = [n for n in names if not _SAFE_IDENT.match(n)]
    else:
        names = [str((project_dir / n).resolve()) for n in names]
        bad = [n for n in names if not _SAFE_PATH.match(n)]
    if bad:
        return None, tr(f"tên không an toàn để đưa vào lệnh shell: {bad[0]!r}",
                        f"identifier unsafe for a shell command: {bad[0]!r}")
    names = list(dict.fromkeys(names))
    if kind == "gradle":
        by_module = {}
        run_dir = _command_gradle_dir(project_dir, template)
        for t in sorted(tests):
            info = _gradle_source_set(t)
            groot = _gradle_root(project_dir, info[0])
            if run_dir is not None and groot.resolve() != run_dir:
                continue  # another (composite) build: its tasks are not addressable from run_dir
            mod_dir = project_dir / info[0] if info[0] else project_dir
            rel_mod = mod_dir.relative_to(groot).as_posix() if mod_dir != groot else ""
            gpath = "" if not rel_mod else ":" + rel_mod.replace("/", ":")
            by_module.setdefault(gpath, []).extend(tests[t])
        if not by_module:
            return None, tr("test được chọn thuộc một build Gradle khác thư mục lệnh chạy",
                            "selected tests belong to a Gradle build other than the one the command runs")
        if not all(_SAFE_GRADLE_PATH.match(m) for m in by_module):
            return None, tr("đường dẫn module Gradle không an toàn", "unsafe Gradle module path")
        m = _GRADLE_MODULE_TESTS.search(template)
        if m and "" in by_module:
            selection["root_project"] = True   # plan_test_run: no narrowed fallback either
            # A test of the root project: ":<task>" is a task the root rarely has, and a bare
            # "<task> --tests X" fails every module without X — run the full command (GeelyEx2
            # 2026-09-24: ./gradlew :testDebugUnitTest failed with any code).
            return None, tr("test được chọn thuộc project gốc, không thuộc module nào — chạy lệnh đầy đủ",
                            "a selected test belongs to the root project, not a module — running the full command")
        if m:
            task = m.group(1)
            parts, kept = [], 0
            for gpath in sorted(by_module):
                task_path = f"{gpath}:{task}"
                # Only modules the full command runs: a test outside its scope is not this rule's.
                if task_path not in full_command and not re.search(r"(?<![:\w])" + re.escape(task) + r"(?!\w)", full_command):
                    continue
                cls = list(dict.fromkeys(by_module[gpath]))
                kept += len(cls)
                parts.append(task_path + " " + " ".join(f"--tests {shlex.quote(c)}" for c in cls))
            if not parts:
                return None, tr("không test nào được chọn nằm trong module mà lệnh đầy đủ chạy",
                                "no selected test is in a module the full command runs")
            return _GRADLE_MODULE_TESTS.sub(lambda _m: " ".join(parts), template, count=1), kept
        if len(by_module) > 1:
            return None, tr(f"test được chọn nằm ở {len(by_module)} module Gradle — {{gradle_tests}} chỉ nhắm một task (dùng {{gradle_module_tests:<task>}})",
                            f"selected tests span {len(by_module)} Gradle modules — {{gradle_tests}} targets one task (use {{gradle_module_tests:<task>}})")
        return template.replace("{gradle_tests}", " ".join(f"--tests {shlex.quote(c)}" for c in names)), len(names)
    if kind == "unity":
        low = template.lower()
        platform = "EditMode" if "editmode" in low else "PlayMode" if "playmode" in low else None
        if platform is None:
            return None, tr("không biết nền tảng test (editmode/playmode) từ impacted_command",
                            "cannot tell the test platform (editmode/playmode) from impacted_command")
        picked = list(dict.fromkeys(n for t in sorted(tests) if _unity_platform(project_dir, t) == platform
                                    for n in tests[t]))
        if not picked:
            return None, tr(f"không test {platform} nào được chọn", f"no {platform} test selected")
        return template.replace("{unity_filter}", "--filter " + shlex.quote(";".join(picked))), len(picked)
    placeholder = "{pytest_nodes}" if kind == "pytest" else "{jest_paths}"
    return template.replace(placeholder, " ".join(shlex.quote(n) for n in names)), len(names)


_RES_DIR = re.compile(
    r"/res/(?:values|layout|drawable|mipmap|menu|navigation|anim|animator|color|font|xml|raw)"
    r"(?:-[A-Za-z0-9_+-]+)?/"
)
_SRC_PKG = re.compile(r"/src/[^/]+/(?:java|kotlin)/(.+)/[^/]+\.(?:kt|java)$")


def _is_res_xml(rel: str) -> bool:
    """Layout/values/drawable XML. Manifest and proguard stay on the full suite."""
    rel = "/" + rel.replace("\\", "/")
    if not rel.endswith(".xml") or rel.endswith("/AndroidManifest.xml"):
        return False
    return _RES_DIR.search(rel) is not None


def _code_package(rel: str):
    m = _SRC_PKG.search("/" + rel.replace("\\", "/"))
    if not m:
        return None
    pkg = m.group(1).replace("/", ".")
    return pkg if _SAFE_IDENT.match(pkg) else None


_UNITY_ASSET_EXT = {".prefab", ".unity", ".asset"}
_META_GUID = re.compile(r"^guid:\s*([0-9a-f]{32})\s*$", re.M)


def unity_asset_tests(project_dir, rel: str, index) -> list:
    """Test files that name this prefab/scene/asset or a scene that embeds its GUID."""
    project_dir = Path(project_dir)
    meta = project_dir / (rel + ".meta")
    guid = None
    if meta.is_file():
        m = _META_GUID.search(meta.read_text(encoding="utf-8", errors="replace")[:4000])
        guid = m.group(1) if m else None
    stem = Path(rel).stem
    needles = [n for n in (guid, stem) if n and len(n) >= 4]
    hits = []
    for t, body in index.tests.items():
        if any(n in body for n in needles):
            hits.append(t)
    assets = project_dir / "Assets"
    if guid and assets.is_dir():
        try:
            proc = subprocess.run(
                ["grep", "-l", "-F", "-r", "--include=*.unity", "--include=*.prefab", guid, str(assets)],
                capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            proc = None
        if proc and proc.returncode in (0, 1):
            for line in (proc.stdout or "").splitlines():
                scene = Path(line.strip()).stem
                if len(scene) < 4:
                    continue
                for t, body in index.tests.items():
                    if scene in body and t not in hits:
                        hits.append(t)
    return hits


def narrow_fallback(project_dir, test):
    """A smaller Gradle command when class selection cannot vouch.

    Resource XML alone does not run the JVM suite. Kotlin/Java falls back to
    `--tests <package>.*` on the modules the full command already runs, or to
    that module's task when one package would still be the whole suite's width.
    Returns (command, mode, reason) or None (keep the full command).
    """
    template = test.get("impacted_command") or ""
    found = _GRADLE_MODULE_TESTS.search(template)
    if not found:
        return None
    task = found.group(1)
    files = [f.replace("\\", "/") for f in (test.get("files") or []) if f not in DELETED_FILES]
    if not files:
        return None
    res, code, other = [], [], []
    for f in files:
        if _is_res_xml(f):
            res.append(f)
        elif Path(f).suffix in (".kt", ".java"):
            code.append(f)
        else:
            other.append(f)
    if other:
        return None
    if not code:
        return ("", "resource", tr(
            "chỉ XML tài nguyên (layout/values/drawable) — không chạy suite JVM",
            "resource XML only (layout/values/drawable) — JVM suite not run"))
    by = {}
    run_dir = _command_gradle_dir(project_dir, template)
    for f in code:
        info = _gradle_source_set(f)
        if not info or info[1] == "instrumented":
            return None
        stem = Path(f).stem
        if not stem or not _SAFE_IDENT.match(stem):
            return None
        groot = _gradle_root(project_dir, info[0])
        if run_dir is not None and groot.resolve() != run_dir:
            return None  # a file of another (composite) build: only the full command covers it
        mod_dir = project_dir / info[0] if info[0] else project_dir
        try:
            rel_mod = mod_dir.relative_to(groot).as_posix()
        except ValueError:
            return None
        gpath = "" if rel_mod in ("", ".") else ":" + rel_mod.replace("/", ":")
        task_path = f"{gpath}:{task}"
        full = test["command"]
        if task_path not in full and not re.search(r"(?<![:\w])" + re.escape(task) + r"(?!\w)", full):
            return None
        by.setdefault(task_path, set()).add(f"*{stem}*")
    if len(by) > 4:
        return None
    parts = []
    for task_path, pats in sorted(by.items()):
        if len(pats) > 4:
            parts.append(task_path)
        else:
            parts.append(task_path + " " + " ".join("--tests " + shlex.quote(p) for p in sorted(pats)))
    replacement = " ".join(parts)
    cmd = _GRADLE_MODULE_TESTS.sub(replacement, template, count=1)
    if cmd.strip() == test["command"].strip():
        return None
    return (cmd, "package", tr(
        f"không chọn được từng lớp — chạy package/module ({replacement})",
        f"class selection failed — running package/module ({replacement})"))


def plan_test_run(project_dir, test, force_reason, cache):
    """Decide full vs impacted for one matrix test → (command, mode, reason, selection)."""
    template = test.get("impacted_command")
    if not template:
        return test["command"], "full", tr("matrix không khai báo impacted_command", "the matrix declares no impacted_command"), None
    if force_reason:
        return test["command"], "full", tr(f"bắt buộc chạy đủ ({force_reason})", f"full run forced ({force_reason})"), None
    sel = select_impacted_tests(project_dir, template, test.get("files") or [], cache=cache, deleted=DELETED_FILES)
    if not sel["ok"]:
        narrow = narrow_fallback(project_dir, test)
        if narrow:
            return narrow[0], narrow[1], narrow[2], sel
        return test["command"], "full", sel["reason"], sel
    cmd, n = expand_impacted_command(project_dir, template, test["command"], sel)
    if cmd is None and sel.get("root_project"):
        # a narrowed package/module run (":app:… --tests '*Foo*'") would skip the root project's test
        return test["command"], "full", n, sel
    if cmd is None:
        narrow = narrow_fallback(project_dir, test)
        if narrow:
            return narrow[0], narrow[1], narrow[2], sel
        return test["command"], "full", n, sel
    sel["count"] = n
    return cmd, "impacted", "", sel


_VACUITY_RED = re.compile(
    r"\bFAILED\b|failures=\"[1-9]|errors=\"[1-9]|AssertionError|"
    r"Assert\.(?:AreEqual|AreNotEqual|IsTrue|IsFalse|That)|"
    r"There (?:were|was) \d+ failure",
    re.IGNORECASE,
)
_PROOF_HINTS = ("proof", "audit-gate", "reports/", "screenshot", "evidence")
_VACUITY_EXT = {".kt", ".kts", ".java", ".cs", ".py", ".swift"}


def _scripts_on_path():
    scripts = get_devkit_dir() / "scripts"
    if str(scripts) not in sys.path:
        sys.path.insert(0, str(scripts))
    for _sub in ("audits", "context", "git", "governance", "linters", "testing"):
        _sub_path = str(scripts / _sub)
        if _sub_path not in sys.path:
            sys.path.insert(0, _sub_path)


# What a vacuity re-run has reverted in the LIVE tree right now (path -> original bytes, None = it did not exist) and the
# process group of that re-run. A SIGTERM / SIGHUP (the Stop hook's timeout, a closed terminal) killed python without the
# `finally` of vacuity_revert: the agent's uncommitted fix stayed reverted and the re-run ran on as an orphan (audit
# 2026-10-09, tests/verification/test_vacuity_signal.sh). The re-run may be in a suite worker thread, where no handler can
# be installed, so main() installs _vacuity_on_signal and it acts on this registry. ponytail: SIGKILL still loses the fix,
# back the files up on disk and restore them at the next start if that is ever seen.
# _VACUITY_PGIDS holds the process group of EVERY suite command the gate is running (run_in_group: the suites, their
# flaky re-run, the vacuity re-run, pre-commit suites), not only the vacuity re-run: each runs in its own session, so a
# SIGTERM / SIGHUP / SIGINT to the gate left them running as orphans (A9, 2026-10-09, tests/gates/test_gate_robustness.sh).
_VACUITY_LIVE: dict = {}
_VACUITY_PGIDS: set = set()
_VACUITY_LOCK = threading.RLock()
# Seconds a timed-out suite group gets between SIGTERM and SIGKILL to run its cleanup traps.
_SUITE_TERM_GRACE_S = 10


def _signal_group(proc, sig) -> None:
    """killpg của nhóm tiến trình suite. macOS từ chối (EPERM) khi nhóm còn một zombie: gửi cho chính shell của suite. 20/10: lỗi đó
    từng làm gate chết giữa chừng (traceback) nên biên nhận cũ của cùng nội dung không bị xoá — lượt --full sau dùng lại PASS cũ."""
    try:
        os.killpg(proc.pid, sig)
    except ProcessLookupError:
        pass
    except PermissionError:
        with contextlib.suppress(OSError):
            proc.send_signal(sig)


# #370: run_in_group appends this marker and a `ps` snapshot of the suite's process tree to the output of a suite it had to stop,
# taken BEFORE the TERM — afterwards the stuck process is gone and "where it hung" with it. _run_suite splits it off again.
HANG_SNAPSHOT_MARK = "\n# --- process snapshot at timeout (ps) ---\n"
# a line of the suite output that names a test (the last one is where it hung); with none, the last line of output
HANG_TEST_LINE = re.compile(r"(?i)test|✔|✖|▶|^ok\b|^not ok\b")
# #427 / hang giả 27/10: dòng cuối của ảnh ps — tuổi (giây) của tiến trình CÓ CON trẻ nhất trong cả cây suite (mọi tiến trình, không chỉ
# 12 dòng in ra). hang_report đọc dòng này: một cây con mới (một test mới) vừa bắt đầu thì suite vẫn đang tiến triển, chưa phải treo. Lá
# không tính: vòng poll của một suite kẹt (`sleep 5` của unity-batch.sh, `grep` chờ marker) sinh lá mới liên tục mà không tiến triển.
HANG_YOUNGEST_LINE = "# youngest process: {} s"
HANG_YOUNGEST_RE = re.compile(r"^# youngest process: (\d+) s$", re.M)
PS_ETIME_RE = re.compile(r"^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$")   # cột etime của ps: [[dd-]hh:]mm:ss


def _etime_seconds(text: str):
    """etime của ps ra giây; None khi không đúng dạng [[dd-]hh:]mm:ss."""
    m = PS_ETIME_RE.match(text)
    if not m:
        return None
    days, hours, mins, secs = (int(g or 0) for g in m.groups())
    return ((days * 24 + hours) * 60 + mins) * 60 + secs


def _timeout_snapshot(pgid: int) -> str:
    """`ps` lines (header + at most 12 processes) of the suite pgid: its process group AND every descendant of its leader by ppid,
    leaves first, deepest first; the failure itself when ps cannot run (nothing is hidden). 25/10: run_impacted.sh runs each test
    through tests/lib/run_bounded.py, whose command sits in a session of its own (setsid) — filtered by pgid alone the snapshot kept
    only the runner and the helper, never the stuck leaf (a gate under test blocked in open() of a FIFO) nor the test's name."""
    try:
        r = subprocess.run(["ps", "-axo", "pid,ppid,pgid,stat,etime,command"], capture_output=True, text=True, errors="replace", timeout=5)
    except (OSError, subprocess.SubprocessError) as exc:
        return f"(ps failed: {exc!r})"
    lines = r.stdout.splitlines()
    rows = [(f[0], f[1], f[2], ln) for ln in lines[1:] for f in [ln.split(None, 5)] if len(f) >= 3 and f[0].isdigit() and f[1].isdigit()]
    kids: dict = {}
    for pid, ppid, _, _ in rows:
        kids.setdefault(ppid, []).append(pid)
    depth, todo = {str(pgid): 0}, [str(pgid)]   # leader pid == pgid (start_new_session); visited = depth's keys
    while todo:
        p = todo.pop()
        for c in kids.get(p, ()):
            if c not in depth:
                depth[c] = depth[p] + 1
                todo.append(c)
    mine = [row for row in rows if row[0] in depth or row[2] == str(pgid)]
    parents = {ppid for _, ppid, _, _ in mine}
    mine.sort(key=lambda row: (row[0] in parents, -depth.get(row[0], 0)))   # stable: ps order on ties
    # #427: tuổi nhỏ nhất trên MỌI tiến trình có con trong cây (cột etime); đặt cuối ảnh, hang_report bỏ nó khỏi phần hiển thị. Không có
    # tiến trình có con (`exec sleep`: một tiến trình) hay không đọc được tuổi nào thì không có dòng này.
    fields = (row[3].split(None, 5) for row in mine if row[0] in parents)
    ages = [a for a in (_etime_seconds(f[4]) for f in fields if len(f) >= 5) if a is not None]
    youngest = [HANG_YOUNGEST_LINE.format(min(ages))] if ages else []
    return "\n".join(lines[:1] + [row[3] for row in mine[:12]] + youngest)


PTC_LINE = re.compile(r"^per_test_cache: reuse=(\d+) ran=(\d+)$", re.M)
PER_TEST_CACHE = {"mode": "0"}   # B2: DEVKIT_PER_TEST_CACHE cho run_impacted.sh của lượt này (đặt sau khi biết keyed_ok)


EXTEND_STEP_S = 60   # #616 A: step of the extension below; DEVKIT_GATE_EXTEND_STEP_S overrides it (tests)
EXTEND_CAP_FACTOR = 3   # #616 A: hard ceiling = this × timeout, load never lifts it
EXTEND_MIN_TIMEOUT_S = 60   # #616 A: a --timeout below this is a test's own short budget, never extended (DEVKIT_GATE_EXTEND_MIN_S overrides: tests)


def _extend_step_s() -> float:
    try:
        v = float(os.environ.get("DEVKIT_GATE_EXTEND_STEP_S", ""))
        return v if v > 0 else EXTEND_STEP_S
    except ValueError:
        return EXTEND_STEP_S


def _extend_min_s() -> float:
    try:
        v = float(os.environ.get("DEVKIT_GATE_EXTEND_MIN_S", ""))
        return v if v >= 0 else EXTEND_MIN_TIMEOUT_S
    except ValueError:
        return EXTEND_MIN_TIMEOUT_S


def _machine_busy() -> bool:
    """#616 A: the 1-minute load is at or above capacity.busy_load; unknown load (capacity.py broken, no getloadavg) is NOT busy."""
    try:
        import capacity as _capacity  # noqa: PLC0415 - sibling module in bin/
        load = _capacity.load()
        return load is not None and load >= _capacity.busy_load()
    except Exception as exc:   # noqa: BLE001 - không đọc được tải thì không gia hạn: giữ luật timeout cũ, nói rõ lý do
        log_warn(f"capacity: {exc!r}; timeout is not extended (load unknown)")
        return False


def run_in_group(cmd: str, cwd: str, env: dict, timeout, extend: dict = None) -> tuple:
    """(exit code, output, timed out) of a shell command in its own session/process group, so a timeout kills the
    whole tree (gradle daemons, test workers), not just the shell. The group is in _VACUITY_PGIDS while it runs: a
    signal handler (_vacuity_on_signal) can end it from any thread.
    #616 A: with `extend` (a dict), a run that outlives `timeout` while the machine is busy (load >= busy_load) is not killed: it
    gets EXTEND_STEP_S more at a time, up to EXTEND_CAP_FACTOR × timeout in all; the seconds added are put in extend["s"]. A machine
    that is not busy (or whose load is unknown) at the deadline keeps the old kill."""
    mod = suite_cache_mod() if PER_TEST_CACHE["mode"] != "0" else None
    if mod is not None and env is not None and mod.SELECTION_CMD.match(cmd or ""):
        # chỉ `bash <kit>/tests/run_impacted.sh [--all]` (suite_env bỏ biến này khỏi mọi suite khác: một test chạy run_impacted.sh
        # thật trong suite riêng không được thừa hưởng chế độ dùng lại của gate)
        env = dict(env, DEVKIT_PER_TEST_CACHE=PER_TEST_CACHE["mode"])
    with _VACUITY_LOCK:   # registered in the same step as the start: a signal in between still finds it
        proc = subprocess.Popen(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, errors="replace", start_new_session=True, env=env)
        _VACUITY_PGIDS.add(proc.pid)
    try:
        try:
            try:
                out, _ = proc.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                if extend is None or not timeout or timeout < _extend_min_s():
                    raise
                cap, step, added = EXTEND_CAP_FACTOR * timeout, _extend_step_s(), 0.0
                try:
                    while timeout + added < cap and _machine_busy():
                        wait = min(step, cap - timeout - added)
                        added += wait
                        extend["s"] = round(added, 1)
                        try:
                            out, _ = proc.communicate(timeout=wait)
                            return proc.returncode, out, False
                        except subprocess.TimeoutExpired:
                            continue
                except subprocess.TimeoutExpired:
                    pass
                raise subprocess.TimeoutExpired(cmd, timeout + added)
            return proc.returncode, out, False
        except subprocess.TimeoutExpired:
            snap = HANG_SNAPSHOT_MARK + _timeout_snapshot(proc.pid) + "\n"   # before any signal: the stuck process is still there
            # TERM first: the suite's EXIT traps remove their temp dirs and fixture worktrees (2026-10-19: a bare SIGKILL
            # skipped them and ~8 GiB of test dirs piled up in TMPDIR). KILL whatever is left after the grace.
            _signal_group(proc, signal.SIGTERM)
            try:
                out, _ = proc.communicate(timeout=_SUITE_TERM_GRACE_S)
            except subprocess.TimeoutExpired:
                out = None
            _signal_group(proc, signal.SIGKILL)
            if out is None:
                try:
                    out = proc.communicate(timeout=_SUITE_TERM_GRACE_S)[0]   # reaps the shell first, so returncode below is set
                except subprocess.TimeoutExpired:   # a grandchild the signal never reached still holds the pipe (review 20/10)
                    with contextlib.suppress(OSError):
                        proc.kill()
                    with contextlib.suppress(subprocess.TimeoutExpired):
                        proc.wait(timeout=1)
                    for pipe in (proc.stdout, proc.stderr):
                        with contextlib.suppress(OSError, AttributeError):
                            pipe.close()
                    out = "(output cut: a child process still held the output pipe after SIGKILL)"
            return proc.returncode, (out or "") + snap, True
    finally:
        with _VACUITY_LOCK:
            _VACUITY_PGIDS.discard(proc.pid)


def _vacuity_restore(items) -> None:
    for path, blob in items:
        try:
            if blob is None:
                if path.is_file():
                    path.unlink()
            elif get_project_dir().is_dir():   # a project removed meanwhile is not re-created (W1 R5a)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(blob)
        except OSError as e:
            log_err(tr(f"Không khôi phục được {path} sau revert vacuity: {e}",
                       f"Could not restore {path} after the vacuity revert: {e}"))


def _vacuity_on_signal(signum, _frame):
    """Put the reverted files back and end the re-run, then die by the same signal as before (same exit status)."""
    with _VACUITY_LOCK:
        items, pgids = list(_VACUITY_LIVE.items()), list(_VACUITY_PGIDS)
        _VACUITY_LIVE.clear()
        _VACUITY_PGIDS.clear()
    # Still a bare SIGKILL: a grace here races the suite worker threads (flaky re-run, vacuity re-run) that keep running
    # while the handler waits (review 2026-10-19). A suite killed here leaves its temp dir: scratch_cleanup sweeps the
    # named ones.
    for pgid in pgids:
        with contextlib.suppress(ProcessLookupError, PermissionError):
            os.killpg(pgid, signal.SIGKILL)
    _vacuity_restore(items)
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)


def vacuity_revert(project_dir, test: dict, timeout: int, env=None) -> str:
    """Re-run an impacted PASS with the production diff put back.

    'ok' — the test went RED (it can see the bug). 'vacuous' — it stayed green.
    'weak' — the rerun failed without an assertion failure. 'skip' — nothing to prove.
    The working tree is restored before this returns.

    Default VACUITY_REVERT=narrow: only a PASS whose command names tests
    (--tests / --filter), including a package fallback that names *Class*.
    VACUITY_REVERT=1 also covers those modes without a name filter.
    VACUITY_REVERT=0 skips. The re-run puts production files back to VACUITY_BASE (HEAD, the
    --diff base, or the --since base for committed work) in this tree and restores them
    afterwards. red_proof.py remains the sandbox path.
    env: môi trường của chính suite (run_suite: có SB_HEAVY_SLOT_HELD / DEVKIT_SLOT_ADVISORY_HELD); None thì suite_env().
    """
    flag = os.environ.get("VACUITY_REVERT", "narrow")
    cmd = test.get("command") or ""
    named = "--tests" in cmd or "--filter" in cmd
    if flag == "0" or test.get("status") != "PASS":
        return "skip"
    if flag == "1":
        if test.get("mode") not in ("impacted", "package"):
            return "skip"
    elif not (named and test.get("mode") in ("impacted", "package")):
        return "skip"
    files = [f for f in (test.get("files") or [])
             if f not in DELETED_FILES and not is_test_path(f) and Path(f).suffix.lower() in _VACUITY_EXT]
    if not files:
        return "skip"
    prefix = get_project_prefix()
    saved = []
    try:
        for rel in files:
            path = project_dir / rel
            res = subprocess.run(
                ["git", "-C", str(get_repo_root()), "show", f"{VACUITY_BASE}:{prefix}{rel}"],
                capture_output=True)
            with _VACUITY_LOCK:   # recorded before the write: a signal between the two still restores this file
                saved.append((rel, path.read_bytes() if path.is_file() else None))
                _VACUITY_LIVE[path] = saved[-1][1]
                if res.returncode != 0:
                    if path.is_file():
                        path.unlink()
                elif get_project_dir().is_dir():   # a project removed meanwhile is not re-created (W1 R5a)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(res.stdout)
        code, out, timed_out = run_in_group(test["command"], str(project_dir), suite_env() if env is None else env, timeout)
        if timed_out:
            return "weak"
        if code == 0:
            return "vacuous"
        if _VACUITY_RED.search(out or ""):
            return "ok"
        return "weak"
    finally:
        with _VACUITY_LOCK:
            for rel, _blob in saved:
                _VACUITY_LIVE.pop(project_dir / rel, None)
            _vacuity_restore([(project_dir / rel, blob) for rel, blob in saved])


def run_hardware_source_audit(modified_files: list) -> tuple:
    _scripts_on_path()
    try:
        import hardware_source_lint as hw  # noqa: PLC0415
    except ImportError:
        return True, []
    findings = []
    exts = {".kt", ".kts", ".java", ".py", ".cs"}
    for rel in modified_files:
        if is_test_path(rel) or Path(rel).suffix.lower() not in exts:
            continue
        content = read_changed_text(rel)
        if content is None:
            continue
        for pat, label in hw.PATTERNS:
            new, old = split_new(rel, pat.pattern, content)
            if old and not new:
                note_preexisting(rel, content, old[0], label)
            if new:
                findings.append((rel, _L(label)))
                _record("hardware", rel, label, content, new[0].start())
    return len(findings) == 0, findings


def run_assertion_audit(modified_files: list) -> tuple:
    _scripts_on_path()
    try:
        import assertion_lint as al  # noqa: PLC0415
    except ImportError:
        return True, []
    findings = []
    for rel in modified_files:
        # Only the languages assertion_lint knows (JVM @Test, C# [Test], pytest def test_): a
        # script under tests/ that printf's a Kotlin fixture is not a test source.
        if not is_test_path(rel) or not rel.endswith((".kt", ".kts", ".java", ".groovy", ".scala", ".cs", ".py")):
            continue
        content = read_changed_text(rel)
        if not content:
            continue
        if rel in RENAME_SOURCES and base_text(rel) == content:
            continue
        for line, name in al.findings(content):
            label = (f"Test rỗng ở dòng {line} ({name}): không có assertion phân biệt dữ liệu",
                     f"Vacuous test at line {line} ({name}): no assertion that distinguishes data")
            findings.append((rel, _L(label)))
            _record("vacuity", rel, label)
    return len(findings) == 0, findings


def _proof_hash_cache_path(base) -> "str | None":
    """<git-common-dir>/postfix-gate/proof-hash-cache.json, shared by the worktrees of one repo and outside the
    audited tree. None outside a git repo: nothing is cached there (the old behaviour)."""
    try:
        res = subprocess.run(["git", "-C", str(base), "rev-parse", "--git-common-dir"],
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    out = res.stdout.strip()
    if res.returncode != 0 or not out:
        return None
    return str(Path(str(base), out) / "postfix-gate" / "proof-hash-cache.json")


def run_proof_block(modified_files: list) -> tuple:
    """Hard-fail when a proof image made in this turn is empty or repeats another proof.
    Only fresh images are judged: on disk (changed, or in a proof folder even when ignored or
    committed) and modified since POSTFIX_PROOF_SINCE (epoch seconds; default the last 6 h).
    Older images are references only, so yesterday's duplicates never block a later turn, and a deleted image
    is not "0 byte". proof_gate.sh separately requires the cited PNG to be from this turn."""
    _scripts_on_path()
    try:
        import proof_phash as ph  # noqa: PLC0415
    except ImportError:
        return True, []
    try:
        since = float(os.environ.get("POSTFIX_PROOF_SINCE") or time.time() - 6 * 3600)
    except ValueError:
        since = time.time() - 6 * 3600
    base = get_project_dir()
    images = {}   # resolved path -> (label, fresh)
    for rel in modified_files:
        low = rel.replace("\\", "/").lower()
        if rel in DELETED_FILES or not low.endswith((".png", ".jpg", ".jpeg")) or not any(h in low for h in _PROOF_HINTS):
            continue
        path = resolve_path(rel)
        try:
            if path.is_file():
                images[path.resolve()] = (rel, path.stat().st_mtime >= since)
        except OSError:
            continue
    for folder in (base / ".claude" / "audit-gate", base / "reports", base / ".agents" / "evidence"):
        if folder.is_dir():
            for img in list(folder.glob("*.png")) + list(folder.glob("*.jpg")) + list(folder.glob("*.jpeg")):
                try:   # an ignored or committed proof made in this turn is judged too
                    rel = img.relative_to(base).as_posix() if base in img.parents else str(img)
                    images.setdefault(img.resolve(), (rel, img.stat().st_mtime >= since))
                except OSError:
                    continue

    sha_of, bits_of, findings = {}, {}, []
    fresh, refs = [], []
    for path, (label, is_fresh) in images.items():
        if not is_fresh:
            refs.append((label, path))   # read below, and only when a fresh image needs them
            continue
        try:
            with os.fdopen(_state_fd(path), "rb") as f:   # a FIFO in a proof folder must not hang the gate
                data = f.read()
        except OSError:
            continue
        fresh.append((path.stat().st_mtime, label, data))
    if not fresh:   # references are never judged: nothing fresh means nothing to find, so none is read or hashed
        return True, []
    fresh.sort()
    # dhash of an image is remembered by the sha256 of its bytes (never path or mtime): an old screenshot is hashed once
    cache = ph.HashCache(_proof_hash_cache_path(base))
    fresh_bits = [cache.get(data) if data else None for _mtime, _rel, data in fresh]
    need_ref_bits = any(bits is not None for bits in fresh_bits)   # a reference is compared only with a hashable fresh image
    for label, path in refs:
        try:
            with os.fdopen(_state_fd(path), "rb") as f:
                data = f.read()
        except OSError:
            continue
        if data:   # a reference: remembered, never judged
            digest = hashlib.sha256(data).hexdigest()
            sha_of.setdefault(digest, label)
            if need_ref_bits:
                bits = cache.get(data, digest)
                if bits is not None:
                    bits_of[label] = bits
    def found(rel, label):   # recorded too: the Stop hook shows the summary's findings (GeelyEx2 2026-09-26)
        findings.append((rel, _L(label)))
        _record("proof", rel, label)

    for (_mtime, rel, data), bits in zip(fresh, fresh_bits):
        if not data:
            found(rel, (f"{rel}: ảnh proof 0 byte", f"{rel}: zero-byte proof image"))
            continue
        digest = hashlib.sha256(data).hexdigest()
        if digest in sha_of:
            found(rel, (f"{rel}: trùng byte với {sha_of[digest]}", f"{rel}: identical bytes to {sha_of[digest]}"))
            continue
        sha_of[digest] = rel
        if bits is None:
            continue
        for other, prev in bits_of.items():
            if ph.too_similar(bits, prev):
                # A warning, not a block: a retake of the same success screen is legitimate, and
                # blocking it made agents delete older proofs to pass (OfficeReader 2026-09-26,
                # 8 times). A reused image is still caught: byte-identical above, and
                # proof_gate.sh wants a PNG made in this turn.
                log_warn(tr(f"{rel}: giống {other} ≥ 98% (cùng một màn) — nếu là trạng thái mới, chụp màn khác; không xoá ảnh cũ",
                            f"{rel}: ≥98% similar to {other} (same screen) — for a new state capture another screen; do not delete older proofs"))
                break
        bits_of[rel] = bits
    try:
        cache.save()
    except OSError as e:
        log_warn(tr(f"Không ghi được cache hash ảnh proof: {e}", f"proof hash cache not written: {e}"))
    return len(findings) == 0, findings


def hardware_boundary_notes(modified_files: list) -> list:
    _scripts_on_path()
    try:
        import hardware_boundaries as hb  # noqa: PLC0415
    except ImportError:
        return []
    rows = hb.load(get_project_dir())
    return [hb.warning(r) for r in hb.match_paths(rows, modified_files)]


def test_failure_reported(output):
    """Did the runner report a failing TEST (not just a broken build)? — regression_checklist's rule."""
    _bin = str(Path(__file__).resolve().parent)
    if _bin not in sys.path:   # called from the worker threads of a suite group: insert once, not on every call
        sys.path.insert(0, _bin)
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
        return rc.test_failure_reported(output)
    except (ImportError, AttributeError):
        return True     # cannot tell: keep the conservative reading (flaky, not a pass)


# The machine could not provision the tools the command needs — no test ran, and no change
# to the audited code can fix it. Only signatures of a missing toolchain/SDK/network, never
# a compile or test error of the change.
ENV_BLOCKED_RE = re.compile(
    r"Unable to download toolchain|No matching toolchains found|Cannot find a Java installation|"
    r"SDK location not found|ANDROID_HOME|ANDROID_SDK_ROOT|"
    r"Received status code (?:40[1378]|429|5\d\d) from server|"
    r"Could not GET 'https?://|Could not HEAD 'https?://|CONNECT tunnel failed|"
    r"Could not resolve (?:host|plugin artifact)|Plugin \[id: '[^']+'.*\] was not found")


def environment_blocked(exit_code, output):
    """True when a FAILED command never reached a test because this machine lacks what it
    needs (exit 127: the tool is not installed, or a toolchain/SDK/network signature)."""
    if exit_code == 127:
        return True
    return bool(ENV_BLOCKED_RE.search(output or "")) and not test_failure_reported(output)


def killed_from_outside(exit_code, output):
    """True when the run was killed by SIGKILL / SIGTERM (exit 137 / 143 through a shell, -9 / -15 direct) and printed no
    failing test: it reached no verdict, and no change to the audited code answers a kill (GeelyEx2 2026-10-11: REG-CAR-01
    "Killed: 9" twice, 7.2 min of Stop-hook wall and 2 blocks; OfficeReader 09:57:37: REG-OR-APP exit 143, 163.7 s). Still FAIL
    and still no receipt: this only tells the Stop hook it is not a code problem. The gate's own timeout is TIMEOUT, not this.
    REGRESSION_GATE_KILLED_IS_ENV=0 turns it off."""
    if os.environ.get("REGRESSION_GATE_KILLED_IS_ENV", "1") == "0":
        return False
    return exit_code in (137, 143, -9, -15) and not test_failure_reported(output)


# The test runner lost its own results store — Gradle's build/test-results/**/binary/*.bin
# truncated or deleted under it, what two Gradle runs in one project tree do to each other
# (OfficeReader, 2026-09-25: "> java.io.EOFException" next to the test failures the corrupted
# run printed, then green on the re-run → a false FLAKY bug row). Nothing that run printed can
# be trusted: an infrastructure failure, re-run, never FLAKY. Twin: scripts/stale_rerun.py.
INFRA_FAILURE_RE = re.compile(
    r"^\s*> java\.io\.EOFException\b|test-results[/\\]\S*binary[/\\]|\bresults(?:-generic)?\.bin\b|"
    r"in-progress-results[\w-]*\.bin|Could not write [^\n]*test-results", re.M)


def infra_failure(output) -> bool:
    return bool(INFRA_FAILURE_RE.search(output or ""))


# Bộ lọc `--tests '*<tên file>*'` của narrow_fallback không khớp test nào (file sửa không có test cùng tên):
# Gradle thoát khác 0 mà không test nào chạy — đó không phải test đỏ (GeelyEx2 17/10: một dòng KDoc ở ThemePrefs.kt
# thành REG-CAR-01 FAIL). Chỉ thông báo của bộ lọc include của Gradle, không phải mọi kiểu "0 test".
NARROW_NO_TESTS_RE = re.compile(r"No tests found for given includes")


# One suite run at a time per project tree, across every DevKit runner (this gate from the Stop
# hook or the CLI, scripts/stale_rerun.py, scripts/nightly.py through it). red_proof.py runs in
# its own temp worktrees and keeps its job slots (red_proof.lock). Twin: scripts/stale_rerun.py.
TEST_RUN_LOCK = "test_run.lock"


def _env_seconds(name, default):
    """The environment variable `name` as a number of seconds; `default` when it is unset, not a number or not finite. NaN is no wait at all (min(45, nan)
    is 45, the long wait, and a nan deadline never passes: the run waits for ever) and inf is the same for ever, so neither is read."""
    try:
        value = float(os.environ.get(name, default))
    except ValueError:
        return default
    return value if math.isfinite(value) else default


# Audit 2026-10-25 B5: 41 BUSY Stop runs in 54 h, each after the whole 45 s wait (1.47 h; six Stops in a row behind one gate). The gate that
# holds test_run.lock writes who it is into the lock file (pid + start time, under the flock; emptied before it lets go). A Stop run
# (TEST_RUN_LOCK_BUSY_FAST=1, set by hooks/regression_gate.sh) that finds a LIVE gate there — the pid still the process with that start time,
# the check session_lock makes of its own holder — waits only DEVKIT_REUSE_LOCK_WAIT_S (3 s) and says BUSY: that holder is a whole gate run,
# minutes long. A holder it cannot name (stale_rerun / testsourceset / worktree.py write no record, a dead or recycled pid, a record a
# killed gate left) keeps the long wait; a lock nobody holds is taken at once, as before. The CLI never sets the flag: it keeps its wait.
# ponytail: stale_rerun opens the file with "w" and empties a gate's record while it waits for the lock; the next Stop then waits 45 s again.
def _write_test_run_lock_holder(fh, clear=False):
    """Record this run as the holder of the test_run.lock `fh` it holds (clear=True: empty the record, still under the flock). Data only:
    a failure leaves the record empty or stale, which a waiter reads as an unknown holder (the long wait)."""
    try:
        os.ftruncate(fh.fileno(), 0)
        if not clear:
            sys.path.insert(0, str(Path(__file__).resolve().parent))
            import session_lock  # noqa: PLC0415 - sibling module in bin/
            fh.write(json.dumps({"pid": os.getpid(), "pid_start": session_lock.pid_start(os.getpid())}) + "\n")
        fh.flush()
        return True
    except (OSError, ImportError, AttributeError, ValueError) as e:
        print(f"    {DIM}test_run.lock holder record not written ({e!r}): a waiter sees an unknown holder{RESET}", flush=True)
        return False


def _test_run_lock_live_gate(path):
    """The record in test_run.lock names a gate run that is still alive: pid > 1 with a recorded start time, and that pid is still the process
    started then (session_lock.is_pid_alive). No record, another writer's bytes, an unknown start, a dead or recycled pid: False."""
    try:
        fd = _state_fd(path, "r")
        try:
            raw = os.read(fd, 4096)
        finally:
            os.close(fd)
        rec = json.loads(raw.decode("utf-8", "replace") or "null")
        pid, start = (rec.get("pid"), rec.get("pid_start")) if isinstance(rec, dict) else (None, None)
        if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1 or not isinstance(start, str) or not start:
            return False
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import session_lock  # noqa: PLC0415 - sibling module in bin/
        return pid != os.getpid() and session_lock.is_pid_alive(pid, start)
    except (OSError, ValueError, ImportError, AttributeError):
        return False


def acquire_test_run_lock(project_dir, cap=None):
    """(file handle, held) — the per-project test-run flock under .claude/audit-gate/. Waits at
    most TEST_RUN_LOCK_WAIT_S (default 900 from the CLI; hooks/regression_gate.sh passes 45 so
    the wait plus the suites stay inside the Stop hook's own 1800 s timeout) for another run, or
    `cap` seconds when that is less (a run with nothing left to run: see main);
    not held → the tests are BUSY (summary "busy"). (None, True) when the lock file cannot be
    made (never worse than no lock). TEST_RUN_LOCK_BUSY_FAST=1 (the Stop hook) and a live gate holds
    it: DEVKIT_REUSE_LOCK_WAIT_S (3 s) at most (B5 above). Held: this run's record is written into it."""
    import fcntl  # noqa: PLC0415
    state = Path(project_dir) / ".claude" / "audit-gate"
    try:
        state.mkdir(parents=True, exist_ok=True)
        if not (state / ".gitignore").exists():
            (state / ".gitignore").write_text("*\n", encoding="utf-8")
        fh = os.fdopen(_state_fd(state / TEST_RUN_LOCK, "a"), "a")
    except OSError as e:
        log_warn(tr(f"Không tạo được khoá chạy test ({e}) — chạy không khoá", f"Cannot create the test-run lock ({e}) — running unlocked"))
        return None, True
    wait = _env_seconds("TEST_RUN_LOCK_WAIT_S", 900.0)
    if cap is not None:
        wait = min(wait, cap)
    t0 = time.monotonic()
    deadline, said = t0 + wait, False
    while True:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
            _write_test_run_lock_holder(fh)
            return fh, True
        except OSError:
            if not said and os.environ.get("TEST_RUN_LOCK_BUSY_FAST") == "1" and _test_run_lock_live_gate(state / TEST_RUN_LOCK):
                deadline = min(deadline, t0 + _env_seconds("DEVKIT_REUSE_LOCK_WAIT_S", 3.0))
            if time.monotonic() >= deadline:
                fh.close()
                return None, False
            if not said:
                print(f"    {DIM}⏳ {tr('Một lượt chạy test khác đang dùng dự án này — chờ nó xong (tránh 2 Gradle ghi đè build/test-results)', 'Another test run is using this project — waiting for it (two Gradle runs corrupt build/test-results)')}{RESET}", flush=True)
                said = True
            time.sleep(0.5)


def flaky_retry(cmd, project_dir, timeout, elapsed, infra=False, env=None):
    """Re-run a failed suite once: (exit code, output) or None. Green on the second run is a
    flaky test — the run stays FAIL. Off with FLAKY_RETRY=0; only for a suite that ran under
    FLAKY_RETRY_MAX_S seconds (default 120), so a real failure of a long suite is not paid twice.
    infra (the run lost its results store): always re-run, whatever its length; off with INFRA_RETRY=0.
    env: môi trường của chính suite (run_suite: có SB_HEAVY_SLOT_HELD / DEVKIT_SLOT_ADVISORY_HELD — thiếu chúng thì gate lồng
    trong lần chạy lại chờ chính khoá Unity của gate cha rồi ra SLOT); None thì suite_env()."""
    if infra:
        if os.environ.get("INFRA_RETRY", "1") == "0":
            return None
    elif os.environ.get("FLAKY_RETRY", "1") == "0":
        return None
    try:
        cap = float(os.environ.get("FLAKY_RETRY_MAX_S", "120"))
    except ValueError:
        cap = 120.0
    if elapsed > cap and not infra:
        return None
    code, out, timed_out = run_in_group(cmd, str(project_dir), suite_env() if env is None else env, timeout)
    if timed_out:
        return None
    label = "INFRA_RETRY" if infra else "FLAKY_RETRY"
    return code, f"\n# --- chạy lại 1 lần ({label}) — exit {code} ---\n{out or ''}"


def keep_evidence(project_dir, t, cmd, out):
    """The run's full output as acceptance evidence (.agents/evidence/<test-id>/, the
    checklist row links it). A failure to write is a warning, never a gate result."""
    _bin = str(Path(__file__).resolve().parent)
    if _bin not in sys.path:   # called from the worker threads of a suite group: insert once, not on every call
        sys.path.insert(0, _bin)
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
        return rc.write_evidence(project_dir, t.get("id") or "test", out or "", {
            "command": cmd, "mode": t.get("mode"), "status": t.get("status"), "exit": t.get("exit_code"),
            "duration": t.get("duration")})
    except (ImportError, OSError) as e:
        log_warn(tr(f"Không lưu được log bằng chứng: {e}", f"Cannot keep the evidence log: {e}"))
        return None


def skip_bookkeeping(project_dir) -> bool:
    """True in a LINKED git worktree (regression_checklist.skip_bookkeeping: ONE definition for the gate and every hook).
    Any trouble reads as False: the gate then keeps its old behaviour and writes."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
        return rc.skip_bookkeeping(project_dir)
    except (ImportError, AttributeError):
        return False


def capture_overlay_pre(args, matrix, project_dir, regression_tests):
    """Before the suites run, in a linked worktree that will keep their results in its own state: the fingerprint of each suite's
    watched files and the overlay bind. A file edited WHILE a suite runs must not be vouched for by a PASS that never saw it, so
    these are taken first (a fingerprint taken afterwards would bind the result to the newer content). None: nothing to keep."""
    if args.checklist or args.no_checklist:
        return None
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
        if not rc.skip_bookkeeping(project_dir):
            return None
        data = rc.load(project_dir)
        rc.sync_from_matrix(data, matrix)
        ids = {t.get("id") for t in regression_tests if t.get("id")}
        fps = {tid: rc.watched_fingerprint(project_dir, list(it.get("watch_files", [])) + list(it.get("covers", [])))
               for tid, it in data["items"].items() if tid in ids and isinstance(it, dict) and it.get("kind") == "test"}
        return {"fps": fps, "bind": overlay_bind(project_dir, args.matrix)}
    except Exception:  # noqa: BLE001 - no snapshot, nothing is kept: the suites run again next time (as before)
        return None


def record_worktree_results(args, matrix, modified_files, regression_tests, run_tests, pre=None):
    """A LINKED worktree does not write the tracked checklist, so the next --full would re-run every STALE suite again. Keep
    what this run proved in the worktree's own state (<git dir>/postfix-gate/, never tracked); stale_suite_ids reads it back.
    mark_stale still judges it against the watched files, so the PASS of another tree is never this tree's. Never fails the gate."""
    if not run_tests or not pre:
        return
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
        project_dir = get_project_dir()
        data = rc.load(project_dir)
        rc.sync_from_matrix(data, matrix)
        head = subprocess.run(["git", "-C", str(project_dir), "rev-parse", "--short", "HEAD"],
                              capture_output=True, text=True).stdout.strip() or None
        commit = f"{head}+dirty" if head and modified_files else head
        recorded = [dict(t, status="PASS_IMPACTED") if t.get("mode") in PARTIAL_MODES and t.get("status") == "PASS" else t
                    for t in regression_tests]
        rc.record_results(data, recorded, task=args.task, commit=commit, project=project_dir)
        rc.overlay_save_tests(project_dir, data, [t["id"] for t in recorded if t.get("id") and t.get("status") in rc.RESULT_STATES],
                              pre["bind"], pre["fps"])
    except Exception as e:  # noqa: BLE001 - never fails the gate (its verdict is decided)
        log_warn(tr(f"Không ghi được kết quả vào state của worktree: {e}", f"Cannot keep the results in the worktree state: {e}"))


def update_regression_checklist(*args):
    """Under the checklist lock: the prompt hook and `agent-kit bugs` write the same file."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
        lock = rc.locked(get_project_dir())
    except (ImportError, AttributeError):
        return _update_regression_checklist(*args)
    with lock:
        return _update_regression_checklist(*args)


def _update_regression_checklist(args, matrix, rules, modified_files, regression_tests, run_tests, exit_code):
    """Living checklist (.agents/regression_status.json + regression_checklist.md).

    Results are recorded only for tests this run actually executed; changed source
    files no rule covers become UNCOVERED rows; a lesson recorded on a PASSING gate
    becomes a bug row linked to the tests that just passed. Never fails the gate.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import regression_checklist as rc  # noqa: PLC0415 - sibling module in bin/
    except ImportError as e:
        log_warn(tr(f"Regression checklist không nạp được: {e}", f"Cannot load the regression checklist module: {e}"))
        return
    project_dir = get_project_dir()
    try:
        data = rc.load(project_dir)
    except (OSError, ValueError) as e:
        log_warn(tr(f"Không đọc được regression checklist ({e}) — bỏ qua, KHÔNG ghi đè",
                    f"Cannot read the regression checklist ({e}) — skipped, NOT overwritten"))
        return
    head = subprocess.run(["git", "-C", str(project_dir), "rev-parse", "--short", "HEAD"],
                          capture_output=True, text=True).stdout.strip() or None
    commit = f"{head}+dirty" if head and modified_files else head
    rc.sync_from_matrix(data, matrix)
    try:
        tagged = rc.autolink_tags(project_dir, data)
    except (OSError, ValueError) as e:
        tagged = []
        log_warn(tr(f"Không gắn được tag bug trong test: {e}", f"Could not link bug tags in tests: {e}"))
    if tagged:
        log_ok(tr(f"Đã gắn {len(tagged)} tag [BUG]/[FIX]/[INSTINCT] trong test vào checklist (chưa đổi trạng thái đã sửa)",
                  f"Linked {len(tagged)} [BUG]/[FIX]/[INSTINCT] tags from tests into the checklist (fix state unchanged)"))
    if run_tests:
        # An impacted / package PASS ran a subset, a resource PASS ran nothing: it flags the row
        # as impacted but never records PASS (that needs the full command). A FAIL is real.
        recorded = [dict(t, status="PASS_IMPACTED") if t.get("mode") in PARTIAL_MODES and t.get("status") == "PASS"
                    else t for t in regression_tests]
        rc.record_results(data, recorded, task=args.task, commit=commit, project=get_project_dir())
    # After the results: a guard row linked now shows NOT_RUN until a run AFTER its link.
    try:
        synced = rc.sync_project(data, project_dir, matrix)   # + guards.json guards, orphan tests
    except Exception as e:  # noqa: BLE001 — a bad guards.json or script never fails the gate
        synced = {"guards": []}
        log_warn(tr(f"Không đồng bộ được guard/test mồ côi vào checklist: {e!r}",
                    f"Could not sync guards / orphan tests into the checklist: {e!r}"))
    if synced["guards"]:
        log_ok(tr(f"Đã thêm {len(synced['guards'])} guard của .agents/local/guards.json vào checklist "
                  "(chưa PASS tới khi chạy thật sau khi link + chứng minh ĐỎ): ",
                  f"Added {len(synced['guards'])} guards of .agents/local/guards.json to the checklist "
                  "(not PASS before a real run after the link + a RED proof): ") + ", ".join(synced["guards"][:10]))
    rc.prune_uncovered(data, lambda files: [f for f in uncovered_code_files(files, rules) if (project_dir / f).exists()])
    # No trusted rules (no matrix, or one the gate does not trust): every changed file
    # would look uncovered — rows that say nothing true. Record UNCOVERED only against
    # real rules.
    added = rc.add_uncovered(data, uncovered_code_files(modified_files, rules), task=args.task) if rules else []
    bug_id = None
    if args.record_lesson and exit_code == 0:
        passed = [t["id"] for t in regression_tests
                  if t.get("status") == "PASS" and t.get("id") and not t.get("stale_rerun") and not t.get("keyed_full")]
        bug_id = rc.add_bug(data, args.record_lesson, cause=args.cause, task=args.task, test_ids=passed)
    try:
        rc.save(project_dir, data)
    except (OSError, ValueError) as e:   # ValueError: a non-UTF-8 file name in a row cannot be written as UTF-8 (A8)
        log_warn(tr(f"Không ghi được regression checklist: {e}", f"Cannot write the regression checklist: {e}"))
        return
    c = rc.summary(data)
    print(f"  • Regression checklist: ✅ {c.get('PASS', 0)} · ❌ {c.get('FAIL', 0) + c.get('TIMEOUT', 0)}"
          f" · ⚠️ {c.get('UNCOVERED', 0) + c.get('NEEDS_TEST', 0)} · ⏳ {c.get('NOT_RUN', 0)}"
          + (f" · ⚠️ {c['ORPHAN_TEST']} {tr('test có thể không suite nào chạy', 'tests maybe run by no suite')}"
             if c.get("ORPHAN_TEST") else "")
          + f" → {project_dir / rc.VIEW_FILE}")
    if added:
        log_warn(tr(f"{len(added)} file thay đổi CHƯA có test hồi quy — gắn test bằng ",
                    f"{len(added)} changed files have NO regression test — link one with ")
                 + "`python3 bin/regression_checklist.py link <ID> <TEST-ID>`:")
        for item_id in added[:10]:
            print(f"      - {item_id}")
    if bug_id:
        print(f"  • {tr('Đã thêm bug', 'Added bug')} {bug_id} {tr('vào checklist', 'to the checklist')}"
              + ("" if data["items"][bug_id]["tests"] else tr(" (chưa link test)", " (no test linked yet)")))


# Large or media files are not source: a 14 MB bugs/bug.mp4 of another session rode into a
# commit (GeelyEx2 c4769097, 2026-09-26). Blocked in pre-commit; DEVKIT_ALLOW_LARGE=1 when asked.
def _max_staged_mb() -> float:
    raw = os.environ.get("DEVKIT_MAX_STAGED_MB") or "5"
    try:
        return float(raw)
    except ValueError:   # "5MB": warn and keep the default instead of crashing every gate run
        sys.stderr.write(f"⚠ DEVKIT_MAX_STAGED_MB={raw!r} is not a number — using 5\n")
        return 5.0


MAX_STAGED_MB = _max_staged_mb()
BINARY_EXTS = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm", ".3gp", ".zip", ".7z", ".rar", ".tar",
               ".gz", ".tgz", ".apk", ".aab", ".ipa", ".hprof", ".heapdump", ".mp3", ".wav"}


def run_large_file_audit(modified_files: list) -> tuple:
    if os.environ.get("DEVKIT_ALLOW_LARGE") == "1":
        return True, []
    root = str(get_repo_root())
    prefix = get_project_prefix()
    findings = []
    files = [f for f in modified_files if f not in DELETED_FILES and STAGED_MODES.get(f, "100").startswith("100")]
    # One `check-attr --stdin` and one `cat-file --batch-check` for all of them, not two git processes per file (A12).
    lfs = set()
    if files:
        res = subprocess.run(["git", "-C", root, "check-attr", "--stdin", "-z", "filter"], capture_output=True,
                             input=b"".join((prefix + f).encode("utf-8", "surrogateescape") + b"\0" for f in files))
        parts = res.stdout.decode("utf-8", errors="surrogateescape").split("\0")
        lfs = {parts[i] for i in range(0, len(parts) - 2, 3) if parts[i + 1] == "filter" and parts[i + 2] == "lfs"}
        prefetch_blobs("", [prefix + f for f in files])
    for f in files:
        if prefix + f in lfs:
            continue
        info = object_info("", prefix + f)
        mb = info[1] / 1e6 if info else 0
        if mb > MAX_STAGED_MB:
            findings.append((f, tr(f"file {mb:.1f} MB > {MAX_STAGED_MB:g} MB — không commit file lớn (DEVKIT_ALLOW_LARGE=1 nếu User yêu cầu)",
                                   f"file {mb:.1f} MB > {MAX_STAGED_MB:g} MB — large files are not committed (DEVKIT_ALLOW_LARGE=1 when the user asks)")))
        elif Path(f).suffix.lower() in BINARY_EXTS:
            findings.append((f, tr("video/âm thanh/gói nhị phân — không commit (DEVKIT_ALLOW_LARGE=1 nếu User yêu cầu)",
                                   "video/audio/binary package — not committed (DEVKIT_ALLOW_LARGE=1 when the user asks)")))
    return not findings, findings


# A fix commit that changes source code names the bug it fixes, or says why none applies
# (GeelyEx2 25-26/09: ~12 car bugs fixed, 0 guards added; the project rule lived only in AGENTS.md).
FIX_SUBJECT = re.compile(r"^(fix|hotfix|bugfix)(\([^)]*\))?!?:", re.I)
TRAILER = re.compile(r"^(Bug|No-Guard)[ \t]*:[ \t]*(\S.*)$", re.I | re.M)
# A code change says what it changed. Goods 2026-09-25: "fix." and "no message" committed
# half-done work that turned 33 checklist rows red. Blocked: a vague subject — "<type>: <1 word>",
# fewer than 3 words otherwise, or a filler ("update", "wip"). Any type passes (GeelyEx2 uses
# data(voice):, tools(vhal):; its release script commits "Release artifacts (dev): …").
CONVENTIONAL = re.compile(r"^([a-z]+)(\([^)]*\))?!?:\s*(.*)$", re.I)
GIT_MADE_SUBJECT = re.compile(r"^(Merge |Revert |fixup! |squash! |amend! |Initial commit$|Squashed commit of the following:)")
VAGUE_SUBJECTS = {"wip", "update", "updates", "fix", "fixes", "fixed", "change", "changes", "misc", "tmp", "test",
                  "tests", "no message", "done", "ok", "sửa", "sửa lỗi", "cập nhật"}
FIX_WORD = re.compile(r"^(fix|fixes|fixed|hotfix|bugfix|sửa)\b", re.I)
BUG_ID = re.compile(r"^(#\d+|[A-Za-z][\w.]*-[\w.-]+)$")


def known_bug_ids():
    """Guard ids (.agents/local/guards.json) and checklist bug ids; None when the project has neither."""
    ids, seen = set(), False
    proj = get_project_dir()
    try:
        g = json.loads((proj / ".agents" / "local" / "guards.json").read_text(encoding="utf-8"))
        seen = True
        for it in (g.get("guards", []) if isinstance(g, dict) else g):
            if isinstance(it, dict) and it.get("id"):
                ids.add(str(it["id"]))
    except (OSError, ValueError, AttributeError):
        pass
    try:
        items = json.loads((proj / ".agents" / "regression_status.json").read_text(encoding="utf-8")).get("items", {})
        seen = True
        ids.update(k for k, v in items.items() if isinstance(v, dict) and v.get("kind") == "bug")
    except (OSError, ValueError, AttributeError):
        pass
    return ids if seen else None


def run_commit_msg_check(msg_path, modified_files) -> int:
    try:
        text = Path(msg_path).read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        log_err(tr(f"commit-msg: không đọc được message ({e})", f"commit-msg: cannot read the message ({e})"))
        return 1
    text = "\n".join(line for line in text.splitlines() if not line.startswith("#"))
    subject = next((line for line in text.splitlines() if line.strip("\ufeff \t")), "").strip("\ufeff \t\r")
    if GIT_MADE_SUBJECT.match(subject):
        return 0
    exts = profile_source_exts()
    code = [f for f in modified_files if f not in DELETED_FILES and Path(f).suffix in exts
            and f.replace("\\", "/").split("/")[0] not in NOT_CODE_ROOTS and not is_test_path(f)]
    if not code:
        return 0
    conv = CONVENTIONAL.match(subject)
    desc = conv.group(3) if conv else subject
    if (len(re.findall(r"\w+", desc)) < (2 if conv else 3)
            or desc.lower().strip(" .!:") in VAGUE_SUBJECTS):
        shown = ", ".join(code[:3]) + (" …" if len(code) > 3 else "")
        log_err(tr(f"commit-msg: commit sửa code ({shown}) có subject mơ hồ `{subject}` — nói rõ đổi gì: "
                   "`<type>(scope): mô tả` (vd `fix(player): dừng phát lặp khi mở lại`) hoặc một câu ≥ 3 từ.",
                   f"commit-msg: a commit that changes code ({shown}) has a vague subject `{subject}` — say what changed: "
                   "`<type>(scope): description` (e.g. `fix(player): stop the double play on reopen`) or a sentence of 3+ words."))
        return 1
    if not (FIX_SUBJECT.match(subject) or (not conv and FIX_WORD.match(subject))):
        return 0
    trailers = TRAILER.findall(text)
    if any(k.lower() == "no-guard" for k, _ in trailers):
        return 0
    bugs = [b for k, v in trailers if k.lower() == "bug" for b in re.split(r"[,\s]+", v.strip()) if b]
    shown = ", ".join(code[:3]) + (" …" if len(code) > 3 else "")
    if not bugs:
        log_err(tr(f"commit-msg: commit fix sửa code ({shown}) phải có dòng `Bug: <id>` (bug/guard nó sửa) "
                   "hoặc `No-Guard: <lý do>`. Thêm guard/test cho bug đã đo rồi ghi id vào đây.",
                   f"commit-msg: a fix commit that changes code ({shown}) needs a `Bug: <id>` line (the bug/guard it fixes) "
                   "or `No-Guard: <reason>`. Add the guard/test for the measured bug, then name its id here."))
        return 1
    not_ids = [b for b in bugs if not BUG_ID.match(b)]
    if not_ids:
        log_err(tr(f"commit-msg: `Bug:` cần id (BUG-…, ABC-12, #123), không phải mô tả: {' '.join(not_ids[:6])}. "
                   "Mô tả lý do thì dùng `No-Guard: <lý do>`.",
                   f"commit-msg: `Bug:` needs an id (BUG-…, ABC-12, #123), not prose: {' '.join(not_ids[:6])}. "
                   "For a reason, use `No-Guard: <reason>`."))
        return 1
    known = known_bug_ids()
    unknown = [b for b in bugs if known is not None and b not in known]
    if unknown:
        log_err(tr(f"commit-msg: `Bug: {', '.join(unknown)}` không phải guard (.agents/local/guards.json) hay bug của checklist. "
                   "Thêm guard/bug đó trước, hoặc dùng `No-Guard: <lý do>`.",
                   f"commit-msg: `Bug: {', '.join(unknown)}` is no guard (.agents/local/guards.json) or checklist bug. "
                   "Add that guard/bug first, or use `No-Guard: <reason>`."))
        return 1
    return 0


# Heavy suites (a build tool, an engine) are left to the Stop gate and the nightly run; the
# same split as scripts/stale_rerun.py and scripts/red_proof.py.
PRECOMMIT_HEAVY = re.compile(r"gradlew|\bgradle\b|unity|-runTests|xcodebuild", re.I)
# Slot máy: mỗi suite lấy slot theo lớp tài nguyên của chính nó lúc chạy (bin/heavy_slot.py classify / acquire_for_suite).


def _env_float(name, default):
    try:
        return float(os.environ.get(name) or default)
    except ValueError:
        return float(default)


def _recorded_seconds(median=False) -> dict:
    """Suite id → seconds the pre-commit gate believes it takes (.agents/regression_status.json): the
    LONGEST PASS/FAIL run in its history, else its last run. The last run alone made the same commit run a
    suite or skip it depending on the previous gate run (REG-DK-ALL-01, whose length follows the diff:
    165 s, 164 s, 23 s, 17 s). A suite with only untested / busy / cached runs has no belief.
    ponytail: biased towards skipping, and the history window (5 runs) lets a suite that really got faster
    drift back in after five fast runs; declare the length in the matrix if that ever matters.
    median=True (lớp slot của heavy_slot, audit B7 25/10): trung vị median_high của các lần chạy — một lần chậm (máy tải cao) không
    còn biến suite nhẹ thành cpu và xếp hàng slot nặng của cả máy; `last` trùng history[0] (cùng lúc, kết quả, độ dài) chỉ tính một lần.
    Pre-commit vẫn đọc số dài nhất (tests/gates/test_precommit_duration.sh)."""
    try:
        items = json.loads((get_project_dir() / ".agents" / "regression_status.json").read_text(encoding="utf-8")).get("items", {})
    except (OSError, ValueError, AttributeError):
        return {}

    def seconds(run):
        m = re.match(r"^([\d.]+)s$", str((run or {}).get("duration") or ""))
        return float(m.group(1)) if m and (run or {}).get("status") in ("PASS", "FAIL") else None

    out = {}
    for sid, it in items.items():
        runs, seen = [], set()
        for r in [*((it or {}).get("history") or []), (it or {}).get("last")]:
            s = seconds(r)
            k = (r.get("ts") or r.get("at"), r.get("status"), r.get("duration")) if isinstance(r, dict) else None
            if s is None or k in seen:
                continue
            seen.add(k)
            runs.append(s)
        if runs:
            out[sid] = statistics.median_high(runs) if median else max(runs)
    return out


def estimated_suite_seconds(cmd):
    """Longest tests/lib/test_durations.txt path that is a substring of cmd, else None.
    Only for a suite with no recorded history. Unknown stays runnable (the caller does not skip).
    ponytail: a short path that is a substring of a longer one loses; the longest path wins."""
    try:
        text = (Path(__file__).resolve().parent.parent / "tests" / "lib" / "test_durations.txt").read_text(encoding="utf-8")
    except OSError:
        return None
    best, best_len = None, -1
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        try:
            secs = float(parts[0])
        except ValueError:
            continue
        path = parts[1].strip()
        if path and path in cmd and len(path) > best_len:
            best, best_len = secs, len(path)
    return best


def suite_env():
    """The environment a test suite runs in, without the variables git sets for a hook
    (GIT_INDEX_FILE, GIT_DIR, …): a suite that builds scratch repos otherwise writes into the
    commit's own index — "invalid object … Error building trees" (agent-workbench 2026-09-28).
    Nor the author / committer identity `git commit` exports to its hook (2026-10-03): every scratch
    repo's commit would carry it, and tests/gates/test_gate_friction.sh could not tell a teammate's
    commit from ours — it failed only inside `git commit`, and the pre-commit gate REJECTed."""
    drop = {"GIT_INDEX_FILE", "GIT_DIR", "GIT_WORK_TREE", "GIT_PREFIX", "GIT_COMMON_DIR",
            "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE",
            "GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_AUTHOR_DATE",
            "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL", "GIT_COMMITTER_DATE",
            "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",  # `git -c k=v commit` reaches the hook as GIT_CONFIG_PARAMETERS
            "DEVKIT_LEDGER_ROOT",  # regression_gate's hint for THIS run: a gate a suite starts on a scratch repo reads that repo's own ledger
            # CI=true của worker ép --full. Để lọt vào suite thì gate lồng (test_postfix_gate) chặn file test mới.
            "POSTFIX_GATE_FORCE_FULL", "POSTFIX_GATE_FULL", "WORKTREE_MERGE_GATE", "DEVKIT_ALLOW_BRANCH", "CI",
            # #484: tự duyệt test sửa là quyết định verdict của gate CHA (do nơi gọi đặt trong env); lọt xuống suite thì gate lồng
            # (tests/gates/test_postfix_gate.sh) cũng tự duyệt, các ca "existing test edited … -> UNVERIFIED" ra exit 0 và REG-DK-GATE-01 đỏ
            "DEVKIT_AUTO_APPROVE_TESTS",
            "DEVKIT_GATE_MERGE_CHECK",   # the merge gate of `worktree finish` (see the receipt write below), never a gate a suite starts
            "TEST_RUN_LOCK_BUSY_FAST",   # B5: the Stop hook's short BUSY wait is for ITS gate run; a gate a suite starts waits as the CLI does
            # T0052: móc test của bin/capacity.py (giả số lõi / tải) chỉ cho lần gọi này; DEVKIT_CAPACITY (nút người dùng) vẫn truyền xuống
            # T0056 (INSTINCT-046): DEVKIT_GATE_SLOT_HELD cố ý giữ lại để suite chạy gate lồng không xin thêm slot và không tự khoá cứng;
            # số slot và thời gian chờ là núm của MỘT lần gate (Stop hook đặt 45 s), không lọt xuống suite
            "DEVKIT_CAPACITY_CORES", "DEVKIT_CAPACITY_LOAD", "DEVKIT_GATE_SLOTS", "DEVKIT_GATE_SLOT_WAIT_S",
            "DEVKIT_PER_TEST_CACHE",   # B2: chỉ run_in_group đặt nó, cho lệnh run_impacted.sh chuẩn của lượt này
            "DEVKIT_IMPACTED_DIRS"}   # #616: shard do tiền tố của lệnh ma trận đặt; biến có sẵn trong môi trường không được thu hẹp suite không tiền tố
    return {k: v for k, v in os.environ.items()
            if k not in drop and not k.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_"))}


def run_precommit_tests(modified_files) -> tuple:
    """(ran, failed, skipped, untested): the matrix suites whose watch_files match the staged
    files, run at commit. A commit with a clear subject could still carry code that turns the
    checklist red (Goods 2026-09-25); tests only ran in agent sessions. Light suites only
    unless DEVKIT_PRECOMMIT_TESTS=all; =0 turns it off. Commands come from the matrix at HEAD.
    A commit must stay quick: a suite whose last recorded run took over DEVKIT_PRECOMMIT_MAX_S
    (30 s) is skipped, the run stops starting suites past DEVKIT_PRECOMMIT_BUDGET_S (120 s), and
    a suite past DEVKIT_PRECOMMIT_TEST_TIMEOUT (60 s) is a warning, not a block — the DevKit's own
    run_impacted.sh takes 165–740 s. A suite with no recorded length is estimated from
    tests/lib/test_durations.txt; an estimate over that kill timeout is skipped (not failed).
    The 30 s history threshold is not applied to the estimate. Unknown duration stays runnable.
    skipped = [(id, why)].
    ponytail: runs on the working tree (unstaged edits included), not the staged blobs alone;
    run from a `git stash --keep-index` copy if unstaged edits ever mask a failure."""
    mode = os.environ.get("DEVKIT_PRECOMMIT_TESTS", "light")
    if mode == "0" or not modified_files:
        return [], [], [], []
    matrix, _problem = load_active_matrix(None, "HEAD")
    matrix, _problem = follow_matrix_renames(matrix, _problem, None, "HEAD", staged=True)
    covers = checklist_covers()
    suites = {}
    for rule in matrix.get("rules", []):
        watch = rule_watch(rule, covers)
        if not any(match_pattern(f, pat) for f in modified_files for pat in watch):
            continue
        for t in rule.get("mandatory_regression_tests", []):
            if t.get("id") and t.get("command"):
                suites.setdefault(t["id"], t)
    timeout = _env_float("DEVKIT_PRECOMMIT_TEST_TIMEOUT", 60)
    max_s, budget = _env_float("DEVKIT_PRECOMMIT_MAX_S", 30), _env_float("DEVKIT_PRECOMMIT_BUDGET_S", 120)
    recorded = _recorded_seconds()
    ran, failed, skipped, untested = [], [], [], []
    spent = 0.0
    for sid, t in sorted(suites.items(), key=lambda kv: recorded.get(kv[0], 0.0)):
        cmd = t["command"]
        if mode != "all" and PRECOMMIT_HEAVY.search(cmd):
            skipped.append((sid, "Gradle/Unity/xcodebuild"))
            continue
        if mode != "all" and recorded.get(sid, 0.0) > max_s:
            skipped.append((sid, f"{recorded[sid]:.0f}s > {max_s:.0f}s"))
            continue
        if mode != "all" and recorded.get(sid) is None:
            est = estimated_suite_seconds(cmd)
            if est is not None and est > timeout:
                skipped.append((sid, tr(f"ước lượng {est:.0f}s > {timeout:.0f}s",
                                        f"estimate {est:.0f}s > {timeout:.0f}s")))
                continue
        if spent >= budget:
            skipped.append((sid, tr(f"hết ngân sách {budget:.0f}s", f"budget {budget:.0f}s used")))
            continue
        started = time.perf_counter()
        print(f"  {DIM}▶ {sid}: {cmd}{RESET}")
        rc, out, timed_out = run_in_group(cmd, str(get_project_dir()), suite_env(), timeout)
        if timed_out:
            out, rc = (out or "") + "\n(TIMEOUT)", "TIMEOUT"
        spent += time.perf_counter() - started
        if rc == "TIMEOUT":
            skipped.append((sid, tr(f"quá {timeout:.0f}s, đã dừng", f"over {timeout:.0f}s, stopped")))
            continue
        ran.append(sid)
        if rc != 0 and isinstance(t.get("untested_exit"), int) and rc == t["untested_exit"]:
            untested.append(sid)   # the command's own "cannot run here" code: not a failure, no pass
        elif rc != 0:
            failed.append((sid, rc, (out or "")[-1500:]))
    return ran, failed, skipped, untested


def run_staged_audit(args, modified_files, devkit_artifacts) -> int:
    """--staged (git pre-commit): the 6 blocking static checks on the staged blobs only.
    No regression run, adb probe, proof-image scan or report — a hook has to be fast
    and must not reach outside the repository. Clean is exit 2: tests were not run,
    so this is never a PASS."""
    print(f"\n{BOLD}{CYAN}🛡️  POST-FIX GATE — {tr('kiểm tĩnh nội dung đã stage (pre-commit)', 'static checks on the staged content (pre-commit)')}{RESET}")
    state_files = secret_scan_state_files(devkit_artifacts)   # the secret scan only (A5)
    prefix = get_project_prefix()
    prefetch_blobs("", [prefix + f for f in modified_files + state_files if STAGED_MODES.get(f, "").startswith("100")])
    prefetch_blobs(BASE_REF, [prefix + RENAME_SOURCES.get(f, f) for f in modified_files + state_files])
    state_ok, state_findings = run_git_hygiene_audit(state_files) if state_files and not modified_files else (True, [])
    if not state_ok:
        for f, lbl in state_findings:
            log_err(f"{f}: {lbl}")
        print(f"  {BOLD}{tr('KẾT LUẬN', 'VERDICT')}:{RESET} {RED}{BOLD}{tr('REJECT — sửa các điểm trên rồi commit lại', 'REJECT — fix the findings above, then commit again')}{RESET}\n")
        if args.json:
            print(json.dumps({"mode": "staged", "exit_code": 1, "static_ok": False, "files": [], "static": {"secrets": len(state_findings)},
                              "findings": FINDINGS}, ensure_ascii=False))
        return 1
    if not modified_files:
        log_warn(tr("Không có thay đổi nào được stage để kiểm.", "Nothing staged to check.")
                 + (f" {DIM}({tr('bỏ qua', 'skipped')} {len(devkit_artifacts)} {tr('link/state do devkit cài', 'DevKit-installed links/state')}){RESET}" if devkit_artifacts else ""))
        if args.json:
            print(json.dumps({"mode": "staged", "exit_code": 3, "static_ok": True, "files": []}))
        return 3
    print(f"  • {tr('File đã stage', 'Staged files')}: {BOLD}{len(modified_files)}{RESET}")
    checks = [
        ("secrets", tr("Bí mật / file cấm", "Secrets / forbidden files"), lambda files: run_git_hygiene_audit(files + state_files)),
        ("large", tr("File lớn / video / gói nhị phân", "Large files / video / binary packages"), run_large_file_audit),
        ("lazy", tr("Placeholder lười biếng", "Lazy placeholders"), run_anti_laziness_audit),
        ("dependencies", tr("Dependency (version thả nổi / http://)", "Dependencies (floating versions / http://)"), run_dependency_audit),
        ("perf", tr("Anti-pattern hiệu năng", "Performance anti-patterns"), run_performance_audit),
        ("resilience", tr("Nuốt lỗi", "Swallowed errors"), run_resilience_audit),
        ("logging", tr("Log thô", "Raw logging"), run_logging_audit),
        ("settings", tr("Dây nối hook trong .claude/settings*.json", "Hook wiring in .claude/settings*.json"), run_settings_audit),
    ]
    counts = {}
    for key, label, check in checks:
        ok, findings = check(modified_files)
        counts[key] = len(findings)
        if ok:
            log_ok(f"{label}: 0 {tr('phát hiện', 'findings')}")
        for f, lbl in findings:
            log_err(f"{f}: {lbl}")
    for f, lbl in PREEXISTING_SECRETS[:15]:   # already in HEAD: shown, never blocking the commit
        log_warn(tr(f"{f}: {lbl} — đã có sẵn trong {BASE_REF}, không do commit này (không chặn); nên sửa riêng",
                    f"{f}: {lbl} — already in {BASE_REF}, not introduced by this commit (not blocking); fix it separately"))
    advisories = run_lazy_senior_advisories(modified_files)
    for note in advisories:
        log_warn(note)
    unreadable = [f for f in modified_files if f not in DELETED_FILES
                  and STAGED_MODES.get(f, "").startswith("100") and read_changed_text(f) is None]
    static_ok = not any(counts.values())
    ran, failed, skipped, untested = run_precommit_tests(modified_files) if static_ok and not unreadable else ([], [], [], [])
    for sid, rc, tail in failed:
        log_err(tr(f"suite {sid} ĐỎ (exit {rc}) với code đang stage:", f"suite {sid} RED (exit {rc}) with the staged code:"))
        print("\n".join("      " + l for l in tail.splitlines()[-15:]))
    if ran and not failed:
        log_ok(tr(f"Suite nhẹ của file đã stage: {len(ran)} XANH ({', '.join(ran)})",
                  f"Light suites of the staged files: {len(ran)} green ({', '.join(ran)})"))
    if untested:
        log_warn(tr(f"Suite không chạy được ở máy này (untested_exit): {', '.join(untested)}",
                    f"Suites that cannot run on this machine (untested_exit): {', '.join(untested)}"))
    if skipped:
        shown = ", ".join(f"{sid} ({why})" for sid, why in skipped)
        log_warn(tr(f"Suite không chạy ở pre-commit (cổng Stop hoặc nightly chạy; DEVKIT_PRECOMMIT_TESTS=all để chạy): {shown}",
                    f"Suites not run at pre-commit (the Stop gate or nightly runs them; DEVKIT_PRECOMMIT_TESTS=all to run them): {shown}"))
    if not static_ok:
        verdict, color, exit_code = tr("REJECT — sửa các điểm trên rồi commit lại", "REJECT — fix the findings above, then commit again"), RED, 1
    elif failed:
        verdict, color, exit_code = tr(f"REJECT — {len(failed)} suite hồi quy ĐỎ với code đang stage",
                                       f"REJECT — {len(failed)} regression suites RED with the staged code"), RED, 1
    elif unreadable:
        verdict, color, exit_code = tr(f"CHƯA XÁC MINH — {len(unreadable)} file đã stage không đọc được", f"UNVERIFIED — {len(unreadable)} staged files could not be read"), YELLOW, 2
    else:
        verdict, color, exit_code = tr("TĨNH SẠCH — test hồi quy KHÔNG chạy ở pre-commit (postfix-gate --run-tests để nghiệm thu)",
                                       "STATIC CLEAN — regression tests are NOT run in pre-commit (postfix-gate --run-tests to accept)"), GREEN, 2
    print(f"  {BOLD}{tr('KẾT LUẬN', 'VERDICT')}:{RESET} {color}{BOLD}{verdict}{RESET}\n")
    if args.json:
        print(json.dumps({"mode": "staged", "exit_code": exit_code, "static_ok": static_ok,
                          "tests_ok": not failed, "tests_ran": ran, "tests_failed": [f[0] for f in failed],
                          "tests_skipped": [sid for sid, _ in skipped],
                          "files": modified_files, "unreadable": unreadable, "static": counts,
                          "findings": FINDINGS, "advisories": advisories},
                         ensure_ascii=False))
    return exit_code


# ── Run log (DATA ONLY) ────────────────────────────────────────────────────────────────────────────────────────
# One JSON line per `--run-tests` run (modes full | impacted; nothing for static runs, --dry-run, --commit-msg, --staged, a clean tree,
# an argument error, a run the hook timeout killed, or any run that ends before the verdict: the totals are a LOWER bound) appended to
# <git-common-dir>/postfix-gate/runs.jsonl, to measure how often a --full run is triggered by a documentation-only change and what it
# costs (scripts/governance/gate_runs_report.py). bin/push_gate.py cross-checks a receipt against its line (2026-10-09), so a record must stay as written.
# It can never change the gate's result and never waits for anything the gate has not already waited for: it reads no file, runs no git
# command and no process (it only uses values main() already holds, so a FIFO planted at a profile file cannot hang it), takes no lock,
# prints nothing, and drops every error (`except Exception` only, so Ctrl-C and SystemExit still pass). Its one write is < 3 KB to a file
# opened without following a link and without blocking (the directory is agent-writable: a FIFO, a link, a directory or a hard-linked
# file at the path is skipped); a short write is finished, a torn line is ended with a newline.
# No file name, absolute path, commit message or session id is recorded. Additive (19/10), readers of the old fields ignore them:
# `fp` is the tree fingerprint main() already took (24 hex, or "") and `exit_reason` is a short token (pass, fail, uncovered, …).
# Neither carries a path. push_gate still matches the old fields only. Rotation: above RUN_LOG_MAX_BYTES the newest lines are kept.
# `steps` (_lap, below): a fixed set of 12 phase names with seconds rounded to 0.1, ~200 bytes; the size cap below cuts `suites`, never them.
# B9 (audit 25/10): `suites` lists only the suites that really ran (seconds) or did not PASS; the PASS ones re-used without a run (receipt,
# content key, a shared command) are only counted (`suites_reused`). `slot_wait_s` {id: seconds}: heavy-slot waits (load / Unity lock),
# waits only. Over RUN_LOG_LINE_MAX the cut drops the SHORTEST PASS entries first (the old halving dropped the tail, where REG-DK-ALL-01
# runs since B1: 129 of 411 full lines of agent-workbench lost it), then the rest from the end, then all but the 5 longest waits.
# Retention, measured on agent-workbench's own log 25/10 (585 lines over 59 h, median 2219 B, p90 2799 B, 432 of them cut at 3 KB —
# every suite was listed, ~30 of them really ran): RUN_LOG_KEEP_BYTES 1 MiB held ~495 runs (~54 h of that repo). Re-measured on those
# lines with only the ran / non-PASS entries kept: ~616 runs per MiB (median ~1.9 KB: most listed suites really ran there, because its
# content keys are whole-tree keys). A repo whose suites are mostly re-used logs ~600 B lines (~1700 runs per MiB).
# ponytail: 1 MiB still holds ~2.5 days of agent-workbench; raise RUN_LOG_KEEP_BYTES (the gate's own reader scans the last 4 MiB) if a
# week of history is needed.
RUN_LOG_NAME = "runs.jsonl"
RUN_LOG_MAX_BYTES = 1280 * 1024   # rotate above this ...
RUN_LOG_KEEP_BYTES = 1024 * 1024  # ... keeping at most this much (always below RUN_LOG_MAX_BYTES, so the next run does not rotate again)
RUN_LOG_KEEP_LINES = 4000
RUN_LOG_LINE_MAX = 3000
RUN_LOG_STALE_TMP_S = 3600        # a rotation temp file older than this belongs to a dead run
_MAIN_T0 = None                   # time.monotonic() at the start of main()
_SHADOW_ON = False                # #476: DEVKIT_SHADOW_MAP=1 đọc ở đầu main() rồi gỡ khỏi env, để suite con (test_gate_run_log) không thấy
_SHADOW = None                   # #476: (shadow_skip, shadow_miss) của lượt này — map test→nguồn so với cách chọn cũ; chỉ log
_MAIN_LOAD1 = None                # #472 C: tải 1 phút lúc main() bắt đầu (runs.jsonl load1)
# #472: worktree scratch của điểm gộp (scripts/git/integrate.py, .claude/bin/super-board-merge-gate.sh, super-board-merge-train.sh);
# cùng tiền tố với scripts/governance/gate_speed_report.py MERGE_POINT_PREFIXES và bin/batch_canary.py
MERGE_POINT_PREFIXES = (".integrate-scratch-", ".merge-scratch-", ".train-scratch-")
RUN_LOG_CHANGED_MAX = 50          # đường dẫn tối đa trong changed_files của một dòng runs.jsonl (n_changed vẫn là số thật)


def at_merge_point(project_dir) -> bool:
    """True khi một thành phần của đường dẫn project bắt đầu bằng tiền tố scratch của điểm gộp. Chỉ xét chuỗi (không lstat/realpath):
    _log_gate_run không được chạm hệ thống file ngoài file của nó (tests/gates/test_gate_run_log.sh)."""
    return any(p.startswith(MERGE_POINT_PREFIXES) for p in os.path.normpath(str(project_dir)).split(os.sep))


def run_log_force_reason(args, force_reason):
    """Vì sao lượt này chạy full (#472 C), nhãn ổn định cho runs.jsonl: "--tree", "--full", "--force-full", "POSTFIX_GATE_FORCE_FULL",
    "POSTFIX_GATE_FULL", "CI", "--record-lesson"; "" khi lượt impacted. force_full_reason trả nhãn theo ngôn ngữ (--record-lesson)."""
    if not force_reason:
        return ""
    if getattr(args, "tree", None) is not None:
        return "--tree"
    if str(force_reason).startswith("--record-lesson"):
        return "--record-lesson"
    return str(force_reason).split("=", 1)[0][:32]
# Per-phase seconds of the run, written as `steps` in the record (2026-10-15: runs.jsonl said how long a run took and how long its suites
# ran, so the 28.6 % of OfficeReader's gate time outside the suites could not be attributed). _lap(name) charges the time since the previous
# lap (main()'s start for the first) to `name`; the laps tile main() from its first line to the log call, so the steps add up to total_wall_s.
# Phases: git (arguments, changed files), analysis (matrix, edited-test and author analysis), static (the static audits, layers 1-3 and
# 5-8), select (rules and the impacted-test plan), cache (the reuse check), lock (the wait for test_run.lock), suites (the whole suite loop),
# verdict, receipt, checklist, report. `vacuity` is NOT a phase: it is the seconds of the vacuity re-runs, which happen inside the suites
# phase and after the command's own duration was stamped, so suites_wall_s (the sum of the durations) leaves them out; a flaky re-run, by
# contrast, is inside the duration. With a parallel group the vacuity seconds of its members add up and can exceed the loop's wall time.
_STEPS = {}
_STEP_LAST = None
_STEP_LOCK = threading.Lock()


def _lap(name):
    """Charge the seconds since the previous lap to `name`. Data only: it can never raise into the gate."""
    global _STEP_LAST
    try:
        now = time.monotonic()
        base = _STEP_LAST if _STEP_LAST is not None else _MAIN_T0
        if base is not None:
            with _STEP_LOCK:
                _STEPS[name] = _STEPS.get(name, 0.0) + max(now - base, 0.0)
        _STEP_LAST = now
    except Exception:  # noqa: BLE001 - the numbers are data; the verdict never depends on them
        return


def _add_step(name, seconds):
    try:
        with _STEP_LOCK:
            _STEPS[name] = _STEPS.get(name, 0.0) + max(float(seconds), 0.0)
    except Exception:  # noqa: BLE001
        return


def _run_log_open_flags():
    return getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0)


def _run_log_dir(git_dir):
    """<git-common-dir>/postfix-gate for the absolute git dir main() already resolved. A linked worktree's git dir is
    <common>/worktrees/<id> (git's own layout): its common dir is two levels up, found by the path alone (no file is read, no git call).
    Anything else (the main checkout, a submodule's git dir) is its own common dir."""
    base = str(git_dir)
    parent = os.path.dirname(base)
    if os.path.basename(parent) == "worktrees":
        base = os.path.dirname(parent)
    return os.path.join(base, "postfix-gate")


def _run_log_suites(regression_tests, ran_cmds):
    """[[id, status, seconds]] per suite. seconds is the real duration of a command that RAN in this run (once: a suite that shared a
    command, a re-used PASS, a skipped or BUSY/BUDGET one has null). Their sum is what the run cost ONLY when it was
    sequential: suites of a parallel_safe group overlap, the run's own length is total_wall_s."""
    ran = {id(t) for t in ran_cmds.values()}
    out = []
    for t in regression_tests:
        secs = None
        if id(t) in ran:
            try:
                secs = round(float(str(t.get("duration")).rstrip("s")), 2)
            except ValueError:
                secs = None
        out.append([str(t.get("id") or "?")[:40], str(t.get("status") or "?")[:16], secs])
    return out


def _run_log_slot_waits(regression_tests, slot_waits):
    """{id: seconds} of the heavy-slot waits of this run (B9): waits of 0.1 s and more, in suite order. slot_waits: id(suite) → seconds
    (take_slots in main)."""
    out = {}
    for t in regression_tests:
        w = (slot_waits or {}).get(id(t))
        if isinstance(w, (int, float)) and w >= 0.1:
            out[str(t.get("id") or "?")[:40]] = round(float(w), 1)
    return out


def _run_log_fit(rec):
    """The line of rec under RUN_LOG_LINE_MAX, or None (B9). Cuts rec["suites"] in this order: PASS entries, shortest first (a re-used
    PASS has no entry here); then the other entries from the end; then slot_wait_s down to its 5 longest waits. The longest suites —
    REG-DK-ALL-01, which runs last since B1 — stay longest; `suites_cut` says the list is not whole."""
    def dump():
        return (json.dumps(rec, separators=(",", ":")) + "\n").encode("ascii")
    data = dump()
    # #472 C: cắt changed_files rồi ran_suites trước (n_changed giữ số thật; suites vẫn ghi giây của suite đã chạy), rồi tới suites như cũ
    for k in ("changed_files", "ran_suites"):
        while len(data) > RUN_LOG_LINE_MAX and rec.get(k):
            rec[k] = rec[k][:len(rec[k]) // 2]
            rec[k + "_cut"] = True
            data = dump()
    suites = rec["suites"]
    order = sorted(range(len(suites)), key=lambda i: (suites[i][1] != "PASS",
                                                      suites[i][2] if suites[i][1] == "PASS" and suites[i][2] is not None else -i))
    k = 0
    while len(data) > RUN_LOG_LINE_MAX and k < len(order):
        excess = len(data) - RUN_LOG_LINE_MAX
        while excess > 0 and k < len(order):   # drop about as many entries as the excess, then measure again
            excess -= len(json.dumps(suites[order[k]], separators=(",", ":"))) + 1
            k += 1
        keep = set(order[k:])
        rec["suites"] = [s for j, s in enumerate(suites) if j in keep]
        rec["suites_cut"] = True
        data = dump()
    if len(data) > RUN_LOG_LINE_MAX and rec.get("slot_wait_s"):
        rec["slot_wait_s"] = dict(sorted(rec["slot_wait_s"].items(), key=lambda kv: -kv[1])[:5])
        data = dump()
    return data if len(data) <= RUN_LOG_LINE_MAX else None


def _end_torn_line(fd):
    try:
        os.write(fd, b"\n")
    except OSError:
        return


def _write_whole(fd, data):
    """Write data to fd whole: a short write is finished (at most 8 tries). A line left torn is ended with a newline so that it cannot
    swallow the next run's line. (No `return` inside `finally`: Python 3.14 warns about it on stderr.)"""
    done = 0
    try:
        for _ in range(8):
            done += os.write(fd, data[done:])
            if done >= len(data):
                return
    finally:
        if 0 < done < len(data):
            _end_torn_line(fd)


def _append_run_log(directory, data):
    import stat as _stat  # noqa: PLC0415
    try:
        os.mkdir(directory)   # one level, no parents: the common dir has no postfix-gate/ yet when only linked worktrees ran the gate
    except FileExistsError:
        if not os.path.isdir(directory):
            raise             # a file / FIFO there: the line is dropped by the caller's guard
    fd = os.open(os.path.join(directory, RUN_LOG_NAME), os.O_WRONLY | os.O_APPEND | os.O_CREAT | _run_log_open_flags(), 0o600)
    try:
        st = os.fstat(fd)
        if not _stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
            return
        _write_whole(fd, data)
        size = st.st_size + len(data)
    finally:
        os.close(fd)
    if size > RUN_LOG_MAX_BYTES:
        _rotate_run_log(os.path.join(directory, RUN_LOG_NAME))


def _drop_stale_tmp(directory):
    """Remove runs.jsonl.<pid>.tmp files older than RUN_LOG_STALE_TMP_S (a rotation that died): not followed, bounded to 200 entries."""
    cutoff = time.time() - RUN_LOG_STALE_TMP_S
    with os.scandir(directory) as it:
        for n, entry in enumerate(it):
            if n >= 200:
                return
            if entry.name.startswith(RUN_LOG_NAME + ".") and entry.name.endswith(".tmp") and entry.stat(follow_symlinks=False).st_mtime < cutoff:
                os.unlink(entry.path)


def _rotate_run_log(path):
    """Keep the newest RUN_LOG_KEEP_LINES lines (and at most RUN_LOG_KEEP_BYTES): temp file + os.replace. Best effort: a line another
    run appends meanwhile may be lost, any failure leaves the file as it is."""
    import stat as _stat  # noqa: PLC0415
    tmp = "%s.%d.tmp" % (path, os.getpid())
    try:
        fd = os.open(path, os.O_RDONLY | _run_log_open_flags())
        try:
            st = os.fstat(fd)
            if not _stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
                return
            n = min(st.st_size, RUN_LOG_KEEP_BYTES)
            raw = os.pread(fd, n, st.st_size - n)
        finally:
            os.close(fd)
        lines = raw.split(b"\n")
        if raw[-1:] != b"\n":
            lines = lines[:-1]                      # a write in flight: not a whole line yet
        if n < st.st_size:
            lines = lines[1:]                       # the first line of a tail read starts mid-line
        keep = [l for l in lines if l][-RUN_LOG_KEEP_LINES:]
        if not keep:
            return
        body = b"\n".join(keep) + b"\n"
        tfd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | _run_log_open_flags(), 0o600)
        try:
            view = memoryview(body)
            while view:
                view = view[os.write(tfd, view):]
        finally:
            os.close(tfd)
        os.replace(tmp, path)
        _drop_stale_tmp(os.path.dirname(path))
    except Exception:  # noqa: BLE001 — best effort: the log is only data
        try:
            os.unlink(tmp)
        except OSError:
            return


def _gate_busy(run_tests, lock_held, read_only, regression_tests):
    """Tests not run because another run interfered: it held test_run.lock past the wait, or it replaced / dropped the file a re-used PASS came from
    (STALE). A read-only run (every suite re-used, no lock, nothing written) is no such case: its re-used PASS stands and it waited for nothing.
    One formula for the --json summary (the Stop hook says "run again later" and caches nothing) and for the run log (scripts/governance/stop_hook_times.py and
    scripts/governance/gate_runs_report.py count a busy run as a lock wait)."""
    return bool(run_tests and ((not lock_held and not read_only) or any(t.get("label") == "STALE" for t in regression_tests)))


def default_gate_parallel() -> int:
    """Cỡ nhóm suite parallel_safe khi DEVKIT_GATE_PARALLEL không đặt / rác: bin/capacity.py gate_parallel (T0052). capacity vắng, hỏng
    lúc nạp, thiếu hàm, ném lỗi hay trả không phải int ≥ 1 (None / chuỗi từng làm BoundedSemaphore ném TypeError sập gate, ≤ 0 tắt ngầm
    chạy song song — Antigravity audit 23/10) thì 6 như cũ, kèm cảnh báo."""
    try:
        _bin = str(Path(__file__).resolve().parent)
        if _bin not in sys.path:
            sys.path.insert(0, _bin)
        import capacity as _capacity  # noqa: PLC0415 - sibling module in bin/
        value = _capacity.gate_parallel()
        if type(value) is not int or value < 1:
            raise ValueError(f"gate_parallel trả {value!r}")
        return value
    except Exception as exc:   # noqa: BLE001 - capacity.py hỏng kiểu gì (cả lỗi runtime lúc nạp) cũng không làm chết gate
        log_warn(f"capacity: {exc!r}; DEVKIT_GATE_PARALLEL mặc định 6")
        return 6


def default_gate_slots() -> int:
    """Số lượt post-fix-gate tối đa chạy suite cùng lúc trên máy (T0056, pool 'gate'): DEVKIT_GATE_SLOTS nếu là số nguyên ≥ 0
    (0 = tắt hàng đợi), không đặt / âm / rác thì bin/capacity.py gate_max (12 lõi: 3), lỗi nạp capacity thì mặc định 3."""
    raw = os.environ.get("DEVKIT_GATE_SLOTS", "").strip()
    if raw:
        try:
            n = int(raw, 10)
            if n >= 0:
                return n
        except ValueError:
            pass
    try:
        _bin = str(Path(__file__).resolve().parent)
        if _bin not in sys.path:
            sys.path.insert(0, _bin)
        import capacity as _capacity  # noqa: PLC0415 - sibling module in bin/
        value = _capacity.gate_max()
        if type(value) is not int or value < 1:
            raise ValueError(f"gate_max trả {value!r}")
        return value
    except Exception as exc:   # noqa: BLE001 - capacity.py hỏng kiểu gì cũng không làm chết gate
        log_warn(f"capacity: {exc!r}; DEVKIT_GATE_SLOTS mặc định 3")
        return 3


def _log_gate_run(args, exit_code, modified_files, regression_tests, ran_cmds, impacted_run, deferred_by, lock_busy, lock_held,
                  cache, run_tests, force_reason, no_test_only, project_dir, git_dir, read_only=False, log_fp="", exit_reason="",
                  slot_waits=None):
    """Append the run log line (see above). Takes only values the gate already has and reads nothing; `no_test_only` is main()'s own
    `docs_only` (every changed file passes needs_no_test()), while the logged `docs_only` is stricter: every changed file, rename source
    included, is documentation by DOC_EXT / DOC_NAMES. `log_fp` and `exit_reason` are values main() already holds: this function does not
    fingerprint the tree and does not decide the gate. Any error is dropped: the verdict and exit code are decided before this runs."""
    try:
        if not (run_tests and git_dir):
            return
        fp = _run_log_fp(log_fp)   # 24 hex hoặc rỗng: không bao giờ là đường dẫn
        reason = exit_reason if isinstance(exit_reason, str) and re.fullmatch(r"[a-z_]{1,32}", exit_reason) else ""
        files = [str(f) for f in modified_files]
        # a rename's SOURCE is a changed file too (modified_files holds only the destination; a deleted file is already in it)
        sources = sorted({str(RENAME_SOURCES[f]) for f in files if f in RENAME_SOURCES} - set(files))
        files += sources
        docs = [f for f in files if f.replace("\\", "/").lower().endswith(DOC_EXT) or Path(f.replace("\\", "/")).name in DOC_NAMES]
        suites = _run_log_suites(regression_tests, ran_cmds)
        suites_wall = round(sum(s[2] for s in suites if s[2] is not None), 2)
        if lock_busy:
            verdict = "BUSY"
        elif exit_code == 1:
            verdict = "FAIL"
        elif deferred_by and exit_code in (0, 5):
            verdict = "DEFERRED"
        elif exit_code == 0 and cache and not any(s[2] is not None for s in suites):
            verdict = "REUSED"
            reason = "reused"   # nhánh này quyết trong logger: lý do main đưa vào không còn mô tả đúng lượt
        elif exit_code == 0:
            verdict = "PASS"
        else:
            verdict = "UNTESTED"   # exit 2 (UNVERIFIED), 3, 4 (untested_exit / BUDGET): the exit code says which
        # B9: the verdict and suites_wall above read every suite; the line lists only those that ran or did not PASS
        listed = [s for s in suites if s[2] is not None or s[1] != "PASS"]
        z = time.strftime("%z")
        ran = {id(t) for t in (ran_cmds or {}).values()}
        rec = {
            "v": 1,
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S") + (z[:3] + ":" + z[3:] if len(z) == 5 else ""),
            "epoch": int(time.time()),
            "project": os.path.basename(str(project_dir))[:64],
            "mode": "full" if (force_reason or deferred_by) else "impacted",
            "source": "hook" if (args.session or args.transcript) else "cli",
            "exit": int(exit_code),
            "verdict": verdict,
            "fp": fp,
            "exit_reason": reason,
            "deferred": bool(deferred_by),
            "busy": _gate_busy(run_tests, lock_held, read_only, regression_tests),
            "reused_full_pass": bool(cache),
            "n_changed": len(files),
            "n_docs": len(docs),
            "docs_only": bool(files) and len(docs) == len(files),
            # needs_no_test() is the gate's own flag over modified_files; it would read the profile for a reports/ source, so a
            # rename source counts only when it is documentation itself (never turns a False into a True)
            "no_test_only": bool(files) and bool(no_test_only) and all(f in docs for f in sources),
            "suites": listed,
            "suites_reused": len(suites) - len(listed),
            "suites_wall_s": suites_wall,
            "force_full": bool(getattr(args, "force_full", False)),
            "impacted_run": bool(impacted_run),
            # #472 C: đủ dữ liệu để đo theo task, theo tải máy và theo lý do chạy full (scripts/governance/gate_speed_report.py)
            "force_reason": run_log_force_reason(args, force_reason),
            "merge_point": at_merge_point(project_dir),
            "task": str(args.task)[:80] if getattr(args, "task", None) else None,
            "load1": _MAIN_LOAD1,
            "ncpu": os.cpu_count() or None,
            "changed_files": [f[:200] for f in files[:RUN_LOG_CHANGED_MAX]],
            "ran_suites": [str(t.get("id") or "?")[:40] for t in regression_tests if id(t) in ran],
        }
        if _SHADOW is not None:   # #476: chỉ dữ liệu so sánh; cách chọn suite không đổi
            rec["shadow_skip"], rec["shadow_miss"] = _SHADOW
        ptc = [t["ptc"] for t in regression_tests if t.get("ptc")]
        if ptc:   # #472 D: hit-rate của per_test_cache (chỉ lượt có suite run_impacted.sh chạy với sổ per-test bật)
            rec["ptc_reuse"], rec["ptc_ran"] = sum(p[0] for p in ptc), sum(p[1] for p in ptc)
        extended = sum(t.get("extended_s") or 0 for t in regression_tests)
        if extended:   # #616 A
            rec["extended_s"] = round(extended, 1)
        if len(files) > RUN_LOG_CHANGED_MAX:
            rec["changed_files_cut"] = True
        waits = _run_log_slot_waits(regression_tests, slot_waits)
        if waits:
            rec["slot_wait_s"] = waits
        if _MAIN_T0 is not None:
            rec["total_wall_s"] = round(time.monotonic() - _MAIN_T0, 2)
        with _STEP_LOCK:   # seconds per phase (see _lap); a copy, so the record never changes after this line
            steps = {k: round(v, 1) for k, v in _STEPS.items()}
        if steps:
            rec["steps"] = steps
        data = _run_log_fit(rec)
        if data is not None:
            _append_run_log(_run_log_dir(git_dir), data)
    except Exception:  # noqa: BLE001 — the log is only data: it must never change the gate's result, and prints nothing
        return


def _shadow_compare(project_dir, rules, matrix_path, covers, regression_tests, files):
    """#476: (ids suite cách chọn cũ chạy mà map test→nguồn bỏ, trong số đó ids FAIL) — hoặc None khi tắt / không dựng được.
    Chỉ so sánh để có dữ liệu trước khi bật cách chọn mới; không đổi suite nào chạy. Bật bằng DEVKIT_SHADOW_MAP=1 (mặc định tắt:
    dòng runs.jsonl giữ nguyên bộ trường cũ).
    ponytail: opt-in, cần đặt biến ở các lượt thật để có ≥5 lượt shadow; bật mặc định khi test_gate_run_log được duyệt thêm 2 trường."""
    if not _SHADOW_ON:
        return None
    try:
        sc = suite_cache_for(project_dir, rules, matrix_path, covers)
        if sc is None:
            return None
        _run, skip = sc.shadow_select(regression_tests, files)
        failed = {str(t.get("id")) for t in regression_tests if t.get("status") == "FAIL"}
        return [i[:40] for i in skip], [i[:40] for i in skip if i in failed]
    except Exception as e:  # noqa: BLE001 — chỉ là dữ liệu: không bao giờ đổi kết quả gate
        log_warn(f"shadow map: {e!r}")
        return None


def main():
    global _MAIN_T0, _STEP_LAST, _MAIN_LOAD1, _SHADOW_ON
    _MAIN_T0 = time.monotonic()
    _SHADOW_ON = os.environ.pop("DEVKIT_SHADOW_MAP", "") == "1"
    try:
        _MAIN_LOAD1 = round(os.getloadavg()[0], 2)
    except (OSError, AttributeError):
        _MAIN_LOAD1 = None
    _STEP_LAST = None
    _STEPS.clear()   # one run, one set of steps (a test may call main() again in the same process)
    if threading.current_thread() is threading.main_thread():
        # SIGINT too (A9, 2026-10-09): its KeyboardInterrupt left the suites running; the handler dies by SIGINT like an
        # uncaught KeyboardInterrupt does, so the exit status is unchanged. An ignored signal (nohup, a background job's
        # SIGINT) stays ignored.
        for _sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            if signal.getsignal(_sig) in (signal.SIG_DFL, signal.default_int_handler):
                signal.signal(_sig, _vacuity_on_signal)
    parser = argparse.ArgumentParser(description="Post-Fix Audit & TIA Regression Verification Gate")
    parser.add_argument("--diff", help="Git diff reference (e.g. HEAD~1, origin/main)")
    parser.add_argument("--staged", action="store_true",
                        help="Pre-commit mode: static checks only, on the staged content (clean = exit 2, never PASS)")
    parser.add_argument("--commit-msg", metavar="FILE",
                        help="git commit-msg mode: a fix commit that changes source code needs `Bug: <id>` or `No-Guard: <reason>`")
    parser.add_argument("--matrix", help="Path to regression_matrix.json")
    parser.add_argument("--run-tests", action="store_true", help="Run the matrix regression commands for real (required for PASS)")
    parser.add_argument("--full", action="store_true",
                        help="Run every matrix command in full, ignoring impacted_command (implies --run-tests). "
                             "Without it, --run-tests runs only the impacted tests where the matrix declares an "
                             "impacted_command. A task runs only the impacted tests; --full belongs to the merge point "
                             "(agent-kit integrate, merge gate or train). POSTFIX_GATE_FULL=1 and CI=true do the same")
    parser.add_argument("--force-full", action="store_true",
                        help="Force the full test commands (like --full; kept for callers that pass it: --full is no longer deferred for sibling sessions)")
    parser.add_argument("--dry-run", action="store_true", help="Only list impacted tests, do not run them (default without --run-tests; never PASS)")
    parser.add_argument("--brief", action="store_true",
                        help="Print only the verdict block, errors (✖) and failing suites with their output tail; "
                             "the full output goes to <git dir>/postfix-gate/last_output.log (O3: fewer tokens for agents)")
    parser.add_argument("--since", help="Also audit the files of the commits REF..HEAD (the regression Stop hook passes "
                                        "the last verified HEAD); the static checks compare with REF (without --diff), "
                                        "while unlike --diff the matrix and the edited-test check still read HEAD")
    parser.add_argument("--tree", metavar="HEAD",
                        help="Verify the CLEAN committed tree as it stands (#307): run every suite of the matrix committed in that tree and trust "
                             "that matrix; no diff, so a clean main is no longer exit 3 and a merge that edited the matrix is no exit 2. "
                             "Only HEAD, only with no uncommitted change (exit 2 otherwise); implies --full")
    parser.add_argument("--no-cache", action="store_true",
                        help="Run the tests even when the last full PASS holds for this exact content (DEVKIT_GATE_CACHE=0 does the same)")
    parser.add_argument("--timeout", type=int, default=900, help="Timeout (seconds) per regression command")
    parser.add_argument("--json", action="store_true", help="Also print the result as JSON (last stdout line)")
    parser.add_argument("--auto-approve-tests", action="store_true",
                        help="Refused since #605 (self-approval): kept so old command lines parse; an edited existing test needs a cross-review entry in .claude/audit-gate/approved_tests.json")
    parser.add_argument("--allow-no-tests", action="store_true",
                        help="Allow PASS when there is no matrix / no regression test matches the change")
    parser.add_argument("--allow-orphan-tests", action="store_true",
                        help="Do not block --full on a NEW test file no matrix suite runs (it is still listed)")
    parser.add_argument("--record-lesson", help="Lesson / new code trap to record in .agents/instincts.md (only on PASS)")
    parser.add_argument("--cause", help="Root cause of the bug just fixed")
    parser.add_argument("--prevention", help="Prevention rule / how the fix avoids a recurrence")
    parser.add_argument("--task", help="Task id / name being accepted (recorded in the regression checklist)")
    parser.add_argument("--no-checklist", action="store_true",
                        help="Do not update .agents/regression_checklist.md / regression_status.json")
    parser.add_argument("--checklist", action="store_true",
                        help="Update that checklist even in a LINKED git worktree (skipped there by default: two worktrees "
                             "that each rewrote the tracked files conflict when their work is brought back into main)")
    parser.add_argument("--session", help="Agent session id (the Stop hook passes it): an existing test "
                        "edited by another session or a person is warned about, not blocked")
    parser.add_argument("--transcript", help="That session's transcript (.jsonl) — its Edit/Write/Bash calls")
    parser.add_argument("-l", "--lang", choices=["en", "vi"],
                        help="Output language (default: $DEVKIT_LANG, then the project's saved language, then vi)")
    args = parser.parse_args()

    base_dir = get_base_dir()
    set_lang(resolve_lang(args.lang, base_dir))

    # Without git on PATH every git call raised FileNotFoundError: a traceback and exit 1, read as a REJECT (A10,
    # 2026-10-09). Nothing can be listed or audited without git: UNVERIFIED, said plainly.
    if shutil.which("git") is None:
        log_err(tr("Không tìm thấy `git` trong PATH — gate không liệt kê được thay đổi để kiểm: CHƯA XÁC MINH (cài git hoặc sửa PATH rồi chạy lại)",
                   "`git` not found on PATH — the gate cannot list the change it audits: UNVERIFIED (install git or fix PATH, then re-run)"))
        return 2

    # A ref that starts with "-" would be parsed by git as an option (`--output=<file>`).
    if args.diff is not None and (not args.diff or args.diff.startswith("-")):
        log_err(tr(f"--diff không hợp lệ: {args.diff!r} (phải là một git ref, không được bắt đầu bằng '-')",
                   f"invalid --diff: {args.diff!r} (must be a git ref and must not start with '-')"))
        return 2
    # --since reaches `git diff` and `git show <ref>:<file>` (vacuity revert) as a ref too.
    if args.since is not None and (not args.since or args.since.startswith("-")):
        log_err(tr(f"--since không hợp lệ: {args.since!r} (phải là một git ref, không được bắt đầu bằng '-')",
                   f"invalid --since: {args.since!r} (must be a git ref and must not start with '-')"))
        return 2
    if args.staged and (args.diff or args.run_tests or args.record_lesson or args.full):
        log_err(tr("--staged chỉ kiểm tĩnh nội dung đã stage — không dùng chung với --diff / --run-tests / --record-lesson",
                   "--staged only statically checks the staged content — it cannot be combined with --diff / --run-tests / --full / --record-lesson"))
        return 2
    if args.tree is not None:
        # #307: the suites run on the working tree, so the tree named must be HEAD's and the working tree must BE it — an uncommitted edit
        # would skip every static audit (nothing is "changed") and ride a matrix nobody committed.
        proj = str(get_project_dir())
        head = subprocess.run(["git", "-C", proj, "rev-parse", "--verify", "-q", "HEAD^{commit}"], capture_output=True, text=True).stdout.strip()
        named = subprocess.run(["git", "-C", proj, "rev-parse", "--verify", "-q", f"{args.tree}^{{commit}}"], capture_output=True, text=True).stdout.strip() \
            if args.tree and not args.tree.startswith("-") else ""
        if args.diff or args.since or args.staged or args.commit_msg:
            log_err(tr("--tree: không dùng chung với --diff / --since / --staged / --commit-msg (cây sạch không có diff)",
                       "--tree: cannot be combined with --diff / --since / --staged / --commit-msg (a clean tree has no diff)"))
            return 2
        if not head or named != head:
            log_err(tr(f"--tree: chỉ nhận HEAD (suite chạy trên cây làm việc), không phải {args.tree!r}",
                       f"--tree: only HEAD is accepted (the suites run on the working tree), not {args.tree!r}"))
            return 2
        unclean = tree_unclean_reason(args.matrix)
        if unclean:
            log_err(f"--tree: {unclean}")
            return 2
        args.full = args.force_full = True   # no "current case" to narrow to, and a deferral to a sibling session would write no receipt
    # T0061 Pha 1: phạm vi của biên nhận task. merge-base(<nhánh đích>, HEAD) và checkout có đứng trên nhánh đích không (HEAD tách rời = không).
    # Lượt CLI task (--run-tests, không --full/--diff/--since/--staged/--commit-msg/--tree, không phải hook, không phải merge check) ngoài nhánh
    # đích tự kiểm từ merge-base đó, cả cây sạch lẫn bẩn: một nhánh sạch đã push không còn là exit 3 "không có gì để kiểm".
    task_mb, task_off_trunk = None, False
    if args.run_tests and not (args.staged or args.commit_msg or args.tree is not None):
        proj = str(get_project_dir())
        trunk_ref, trunk_name = task_trunk(proj)
        if trunk_ref:
            branch = subprocess.run(["git", "-C", proj, "symbolic-ref", "-q", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
            task_off_trunk = branch != trunk_name
            task_mb = subprocess.run(["git", "-C", proj, "merge-base", trunk_ref, "HEAD"], capture_output=True, text=True).stdout.strip() or None
        if (task_off_trunk and task_mb and not (args.diff or args.since) and force_full_reason(args) is None
                and not (args.session or args.transcript) and os.environ.get("DEVKIT_GATE_MERGE_CHECK") != "1"):
            args.diff = task_mb
            print(f"    {CYAN}▶ {tr(f'Lượt task: kiểm merge-base({trunk_ref}, HEAD) = {task_mb[:12]} → cây hiện tại', f'Task run: auditing merge-base({trunk_ref}, HEAD) = {task_mb[:12]} → the current tree')}{RESET}")
    # 2026-09-29: after a commit, --full on the clean tree said "nothing to audit" (exit 3), so the
    # commits about to be pushed got no receipt unless the agent found `--diff <sha>` by hand. A clean
    # tree AHEAD of its upstream audits upstream..HEAD — exactly what a push sends. No upstream, or
    # level with it: unchanged (exit 3).
    if (args.run_tests or args.full) and not (args.diff or args.since or args.staged or args.commit_msg or args.tree is not None):
        try:
            clean = not [f for f in get_modified_files() if not is_devkit_artifact(f)]
        except RuntimeError:
            clean = False
        if clean:
            proj = str(get_project_dir())
            up = subprocess.run(["git", "-C", proj, "rev-parse", "--verify", "-q", "@{u}"],
                                capture_output=True, text=True).stdout.strip()
            ahead = subprocess.run(["git", "-C", proj, "rev-list", "--count", f"{up}..HEAD"],
                                   capture_output=True, text=True).stdout.strip() if up else ""
            if up and ahead.isdigit() and int(ahead) > 0:
                args.diff = up
                print(f"    {CYAN}▶ {tr(f'Working tree sạch, HEAD đi trước upstream {ahead} commit: kiểm {up[:12]}..HEAD (nội dung sẽ push)', f'Clean working tree, HEAD {ahead} commit(s) ahead of upstream: auditing {up[:12]}..HEAD (what a push sends)')}{RESET}")
    diff_ref = args.diff   # as typed or defaulted, before the merge-base rewrite below: the tree receipt needs to know it was origin/<base>
    base_ref = args.diff if args.diff and ".." not in args.diff else "HEAD"
    if args.diff and ".." in args.diff:   # A..B / A...B: the change is B against A (merge base for ...)
        left, right = args.diff.split("...", 1) if "..." in args.diff else args.diff.split("..", 1)
        left = left or "HEAD"
        if "..." in args.diff:
            mb = subprocess.run(["git", "-C", str(get_project_dir()), "merge-base", left, right or "HEAD"],
                                capture_output=True, text=True).stdout.strip()
            left = mb or left
        base_ref = left
    elif args.diff:
        # #300: a plain ref is the TIP of that branch; commits that landed on it after this branch was cut (another PR's test or
        # matrix edit) would read as this change's own edits. Audit against merge-base(ref, HEAD), as `A...B` does.
        mb = subprocess.run(["git", "-C", str(get_project_dir()), "merge-base", args.diff, "HEAD"],
                            capture_output=True, text=True).stdout.strip()
        if mb:
            args.diff = base_ref = mb

    global STAGED, BASE_REF, VACUITY_BASE
    STAGED = args.staged or bool(args.commit_msg)
    BASE_REF = base_ref
    # --since gates committed work (regression_gate.sh: unverified commits): HEAD already holds the
    # fix there, so the vacuity revert must put back the --since base or every test looks vacuous.
    VACUITY_BASE = args.since if args.since and not STAGED else base_ref
    try:
        all_changed = get_staged_files() if STAGED else get_modified_files(args.diff)
    except RuntimeError as e:
        log_err(str(e))
        return 2
    since_paths = []
    if args.since and not STAGED:
        # Commits since the last verified HEAD (regression_gate, T0003): their files join the
        # change for test selection; the matrix reads HEAD, the edited-test check HEAD and <since>.
        # -z (A11, 2026-10-09): --name-only quoted a non-ASCII name ("src/cfg_\303\251.py"), which never exists, so
        # the file was never audited. -M: a file renamed in the range is compared with its old path at <since>.
        r = subprocess.run(["git", "-C", str(get_project_dir()), "diff", "--name-status", "-z", "-M", "--relative",
                            args.since, "HEAD"], capture_output=True)
        if r.returncode != 0:
            log_err(tr(f"--since {args.since}: git diff thất bại", f"--since {args.since}: git diff failed"))
            return 2
        since_renames, parts, i = {}, r.stdout.decode("utf-8", errors="surrogateescape").split("\0"), 0
        while i < len(parts):
            status, i = parts[i], i + 1
            if status[:1] in ("R", "C") and i + 1 < len(parts):
                if status[0] == "R":
                    since_renames[parts[i + 1]] = parts[i]
                since_paths.append(parts[i + 1])
                i += 2
            elif status and i < len(parts):
                since_paths.append(parts[i])
                i += 1
        extra = [f for f in since_paths if os.path.exists(os.path.join(str(get_project_dir()), f))]
        all_changed = sorted(set(all_changed) | set(extra))
        # The static checks judge the committed work too (A1, 2026-10-09): against HEAD, an AWS key or a placeholder
        # committed in <since>..HEAD was "already there" — exit 0 and a receipt. Their base is <since>; a file renamed
        # in the range (or renamed again in the tree) is read at <since> under its old path. A file only commits already
        # on the upstream touched (a teammate's, pulled in) keeps HEAD: they passed their own gate (as since_test_weakened).
        if not args.diff:
            BASE_REF = args.since
            up = subprocess.run(["git", "-C", str(get_project_dir()), "rev-parse", "--verify", "-q", "@{u}"],
                                capture_output=True, text=True).stdout.strip()
            if up:
                lg = subprocess.run(["git", "-C", str(get_project_dir()), "log", "--format=", "--name-only", "-z", "--cc",
                                     "--relative", f"{args.since}..HEAD", "--not", up], capture_output=True)
                local = set(lg.stdout.decode("utf-8", errors="surrogateescape").split("\0")) if lg.returncode == 0 else None
                if local is not None:
                    _BASE_REF_FOR.update((f, "HEAD") for f in since_paths if f not in local)
            for dst, src in list(RENAME_SOURCES.items()):
                if dst not in _BASE_REF_FOR:
                    RENAME_SOURCES[dst] = since_renames.get(src, src)
            for dst, src in since_renames.items():
                if dst not in _BASE_REF_FOR:
                    RENAME_SOURCES.setdefault(dst, src)
    _lap("git")
    devkit_artifacts = [f for f in all_changed if is_devkit_artifact(f)]
    modified_files = [f for f in all_changed if f not in devkit_artifacts]
    # 17/10: một commit chỉ đổi sổ trạng thái của gate, kiểm bằng --diff tường minh (merge gate của super-board), từng là exit 3 "không có
    # gì để kiểm" nên PR không bao giờ gộp được. Có --diff thì sổ đó được kiểm như file thường (quét tĩnh kể cả secret, needs_no_test);
    # cây sạch không --diff vẫn exit 3.
    if args.diff and not modified_files and not STAGED:
        own = [f for f in devkit_artifacts if f.replace("\\", "/") in GATE_STATE_FILES and not resolve_path(f).is_symlink()]
        modified_files, devkit_artifacts = own, [f for f in devkit_artifacts if f not in own]
    state_files = secret_scan_state_files(devkit_artifacts)   # the secret scan only (A5)
    if args.commit_msg:
        return run_commit_msg_check(args.commit_msg, modified_files)
    if STAGED:
        return run_staged_audit(args, modified_files, devkit_artifacts)
    base_matrix, base_problem = load_active_matrix(args.matrix, base_ref)
    matrix, matrix_problem, matrix_added = trust_additive_matrix(base_matrix, base_problem, args.matrix, base_ref)
    matrix, matrix_problem = follow_matrix_renames(matrix, matrix_problem, args.matrix, base_ref)
    if args.tree is not None and not any(isinstance(t, dict) and t.get("command") for r in (matrix.get("rules") or [] if isinstance(matrix, dict) else [])
                                         if isinstance(r, dict) for t in (r.get("mandatory_regression_tests") or [])):
        # whatever --allow-no-tests says: a receipt of "the clean tree passed" with no suite run vouches for nothing
        log_err(tr("--tree: ma trận không có suite nào để chạy — không có gì để xác nhận cây",
                   "--tree: the matrix has no suite to run — nothing vouches for the tree"))
        return 2
    for _sid, _cmds in matrix_id_conflicts(matrix).items():
        # log_err, not log_warn: --brief keeps only ✖ lines, so a ⚠ here would never reach the agent that runs the standard command
        log_err(tr(f"Matrix: suite id {_sid} có {len(_cmds)} lệnh khác nhau — chung một dòng trạng thái và evidence, mỗi suite cần id riêng (không chặn)",
                   f"Matrix: suite id {_sid} has {len(_cmds)} different commands — they share one status row and evidence folder; give each suite its own id (not blocking)"))
    # Editing an existing test in the same change can weaken the very assertion the
    # regression run relies on. New test files are fine (that is the RED test), and so is a
    # test appended to an existing file: no old line changed and no skip marker added.
    # A test moved with `git mv` is judged against its OLD path: base:<new path> does not exist, so a weakened test hid behind
    # its rename (audit 2026-10-09, tests/gates/test_gate_renamed_test_edit.sh).
    prefix = get_project_prefix()
    renamed_from = {new: old for old, new in _renamed_paths(base_ref).items()}
    # Every base blob the checks below read, in two git processes instead of one or three per file (A12, 2026-10-09).
    prefetch_blobs(BASE_REF, [prefix + RENAME_SOURCES.get(f, f) for f in modified_files + state_files if f not in _BASE_REF_FOR])
    prefetch_blobs("HEAD", [prefix + RENAME_SOURCES.get(f, f) for f in modified_files if f in _BASE_REF_FOR])
    prefetch_blobs(base_ref, [prefix + renamed_from.get(f, f) for f in modified_files if is_test_path(f)])

    def _edited_existing_test(f):
        src = renamed_from.get(f, f)
        if object_info(base_ref, prefix + src) is None:
            return False
        return not test_change_is_append_only(base_ref, prefix + f, prefix + src if src != f else "")
    tests_touched = [f for f in modified_files if is_test_path(f) and not is_test_doc(f) and _edited_existing_test(f)]
    # --since: a test weakened (or deleted) and COMMITTED in <since>..HEAD equals HEAD, so the
    # check above never sees it (2026-09-28). Such a path is judged against <since> too — on top
    # of the HEAD check, never instead of it. A range commit touching it with `Test-approved-by:`
    # (an Antigravity audit, rules/essentials.md Git) covers the file as of the LATEST such commit.
    upstream = ""
    if since_paths:
        up = subprocess.run(["git", "-C", str(get_project_dir()), "rev-parse", "--verify", "-q", "@{u}"],
                            capture_output=True, text=True)
        upstream = up.stdout.strip() if up.returncode == 0 else ""
    since_touched = [f for f in since_paths if f not in tests_touched and is_test_path(f) and not is_test_doc(f)
                     and not is_devkit_artifact(f) and since_test_weakened(args.since, prefix + f, upstream)]
    # A script a base-ref suite command runs is a file of the change (A2, 2026-10-09: with scripts/check.sh set to
    # `exit 0`, `sh scripts/check.sh` passed whatever the code did). Its change counts like an edited existing test —
    # UNVERIFIED unless approved, same paths — and like a test, a pure append (a line running one more test) is no edit,
    # unless an appended line can force its status green (_STATUS_NEUTRALIZER). Test files keep the test rule.
    runner_paths = suite_runner_paths(matrix, base_ref, {f for f in set(modified_files) | set(since_paths)
                                                         if not is_test_path(f) and not is_devkit_artifact(f)})
    runners_touched = [f for f in sorted(runner_paths) if f in modified_files and object_info(base_ref, prefix + f) is not None
                       and not test_change_is_append_only(base_ref, prefix + f, runner=True)]
    since_runners = [f for f in sorted(runner_paths) if f in since_paths and f not in runners_touched
                     and since_test_weakened(args.since, prefix + f, upstream, runner=True)]
    tests_touched += runners_touched
    since_touched += since_runners
    runners_touched += since_runners
    tests_touched += since_touched
    # Only THIS session's edits block. On a shared tree another session's in-flight test edit
    # used to block every Stop of every session until it was committed (2026-09-25).
    # Unattributable edits stay blocking.
    tests_touched, tests_touched_other = split_tests_by_author(tests_touched, args.session, args.transcript)
    tests_touched, tests_approved = split_user_approved(tests_touched, args.transcript, auto_approve=args.auto_approve_tests)
    run_tests = (args.run_tests or args.full or getattr(args, "force_full", False)) and not args.dry_run
    _lap("analysis")

    print(f"\n{BOLD}{CYAN}══════════════════════════════════════════════════════════════════════════════════════{RESET}")
    print(f"{BOLD}{CYAN}      🛡️  POST-FIX AUDIT & TIA REGRESSION VERIFICATION GATE                          {RESET}")
    print(f"  {DIM}{tr('Chặn thật: 6 kiểm tra tĩnh (bí mật, placeholder, dependency, hiệu năng, nuốt lỗi, log) + test hồi quy với --run-tests.', 'Blocking: 6 static checks (secrets, placeholders, dependencies, performance, swallowed errors, logging) + regression tests with --run-tests.')}{RESET}")
    print(f"  {DIM}{tr('Gate không chụp ảnh. Trước khi trả lời XONG, agent phải có PNG của lượt này theo rules/essentials.md (Every prompt). Exit 0 không thay ảnh.', 'This gate does not capture a screenshot. Before answering XONG, the agent needs a PNG from this turn per rules/essentials.md (Every prompt). Exit 0 does not replace the image.')}{RESET}\n")
    print(f"{BOLD}{CYAN}══════════════════════════════════════════════════════════════════════════════════════{RESET}\n")

    # Không có thay đổi thì không có gì để nghiệm thu — tuyệt đối không bịa file mẫu để ra PASS.
    if not modified_files and args.tree is None:
        if devkit_artifacts:
            log_warn(tr(f"Chỉ có {len(devkit_artifacts)} link/state do devkit cài — không phải thay đổi của người dùng.",
                        f"Only {len(devkit_artifacts)} DevKit-installed links/state files — not a change of yours."))
        # Still a leak when it is only DevKit state (A5): a token in a tracked evidence log was exit 3.
        state_ok, state_findings = run_git_hygiene_audit(state_files) if state_files else (True, [])
        if not state_ok:
            for f, lbl in state_findings:
                log_err(f"{f}: {lbl}")
            print(f"  {BOLD}{tr('KẾT LUẬN CỔNG POST-FIX AUDIT:', 'POST-FIX AUDIT GATE VERDICT:')}{RESET} {RED}{BOLD}{tr('REJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT', 'REJECT — FIX THE FAILED CHECKS')}{RESET}")
            if args.json:
                print(json.dumps({"exit_code": 1, "accepted": False, "files": [], "static": {"secrets": len(state_findings)},
                                  "findings": FINDINGS}, ensure_ascii=False))
            return 1
        log_warn(tr("Working tree sạch và không có --diff khớp: KHÔNG có thay đổi nào để kiểm toán.",
                    "Clean working tree and no matching --diff: NOTHING to audit."))
        log_warn(tr("Gate không kết luận PASS khi không có gì để kiểm. Dùng --diff <ref> để kiểm một commit.",
                    "The gate never reports PASS for nothing. Use --diff <ref> to audit a commit."))
        return 3

    # A listed path that can't be read is NOT clean — it is unverified.
    # A symlink's content is its target, not a project change: it is not unreadable.
    unreadable = [f for f in modified_files
                  if f not in DELETED_FILES and not resolve_path(f).is_symlink()
                  and not resolve_path(f).is_file()]
    # A nested git repository (a submodule with uncommitted work, an untracked repo such as vendor/tool/) is a directory,
    # not a file the gate can or must read: it made every run "1 file could not be read", exit 2 for ever (A3, 2026-10-09).
    nested_repos = [f for f in unreadable if resolve_path(f).is_dir()]
    unreadable = [f for f in unreadable if f not in nested_repos]

    # Layer 1: Git Diff, Hygiene & Anti-Laziness Audit
    print(f"{BOLD}[1/8] {tr('(CHẶN) Quét bí mật, placeholder lười biếng & dependency:', '(BLOCKING) Secrets, lazy placeholders & dependencies:')}{RESET}")
    hygiene_ok, secrets = run_git_hygiene_audit(modified_files + state_files)
    anti_laziness_ok, lazy_findings = run_anti_laziness_audit(modified_files)
    deps_ok, dep_findings = run_dependency_audit(modified_files)
    settings_ok, settings_findings = run_settings_audit(modified_files)
    instincts_ok, instincts_msg = check_instincts_memory()

    print(f"  • {tr('Phạm vi thay đổi', 'Changed files')}: {BOLD}{len(modified_files)} files{RESET}"
          + (f" {DIM}({tr('bỏ qua', 'skipped')} {len(devkit_artifacts)} {tr('link/state do devkit cài', 'DevKit-installed links/state')}){RESET}" if devkit_artifacts else ""))
    for mf in modified_files[:5]:
        print(f"    - {DIM}{mf}{RESET}")
    if len(modified_files) > 5:
        print(f"    - {DIM}... {tr('và', 'and')} {len(modified_files) - 5} {tr('files khác', 'more files')}{RESET}")

    if hygiene_ok:
        log_ok(tr(f"Quét bí mật theo {len(SECRET_PATTERNS) + 1} mẫu regex + {len(FORBIDDEN_SECRET_FILES)} mẫu tên file: 0 phát hiện",
                  f"Secret scan with {len(SECRET_PATTERNS) + 1} regex patterns + {len(FORBIDDEN_SECRET_FILES)} file-name patterns: 0 findings"))
    else:
        for f, lbl in secrets:
            log_err(f"{f}: {lbl}")
    if anti_laziness_ok:
        log_ok(tr("Chống lười biếng (Anti-Laziness): 0 placeholder theo mẫu regex", "Anti-laziness: 0 placeholders matched"))
    else:
        for f, lbl in lazy_findings:
            log_err(f"{f}: {lbl}")

    if deps_ok:
        log_ok(tr("Dependency: 0 version thả nổi / nguồn http://", "Dependencies: 0 floating versions / http:// sources"))
    else:
        for f, lbl in dep_findings:
            log_err(f"{f}: {lbl}")
    for f, lbl in settings_findings:   # silent when no .claude/settings*.json changed
        log_err(f"{f}: {lbl}")

    if instincts_ok:
        log_ok(f"{tr('Bộ nhớ bài học kinh nghiệm (Instincts Memory)', 'Instincts memory')}: {instincts_msg}")
    else:
        log_warn(f"{tr('Bộ nhớ bài học kinh nghiệm', 'Instincts memory')}: {instincts_msg}")

    # Layer 2: UI/UX Design System & Accessibility Gate
    print(f"\n{BOLD}[2/8] {tr('(NHẮC) DESIGN.md & a11y — gate chỉ kiểm file tồn tại, không đo layout:', '(REMINDER) DESIGN.md & a11y — the gate only checks the file exists, it does not measure layout:')}{RESET}")
    ui_ok, ui_msg = check_design_and_accessibility(modified_files)
    if ui_ok:
        log_ok(ui_msg)
    else:
        log_warn(ui_msg)

    # Layer 3: Paired Executable Oracle & Anti-False-Green Engine
    print(f"\n{BOLD}[3/8] {tr('(NHẮC) RED/GREEN. Ảnh nghiệm thu là luật agent, gate không chụp và không tính vào exit:', '(REMINDER) RED/GREEN. The proof image is an agent law; this gate does not capture it and does not score it in the exit code:')}{RESET}")
    log_warn(tr("Bằng chứng RED/GREEN: gate này KHÔNG xác minh — dùng workflow engine (workflows/) để kiểm receipt RED -> GREEN",
                "RED/GREEN evidence: NOT verified by this gate — use the workflow engine (workflows/) to check RED -> GREEN receipts"))

    is_hw = any("automotive" in str(f).lower() or "android" in str(f).lower() for f in modified_files)
    afg_ok, afg_findings, img_count, device_state, brain_count = check_anti_false_green(is_hardware_project=is_hw)
    if afg_ok:
        log_ok(tr(f"Mã băm ảnh minh chứng (SHA-256 Deduplication): {img_count} ảnh, 0 ảnh 0-byte / trùng lặp",
                  f"Proof image hashes (SHA-256 dedup): {img_count} images, 0 zero-byte / duplicates"))
    else:
        for err in afg_findings:
            log_warn(err)
    if not brain_count:
        log_warn(tr("Ảnh phiên Antigravity: KHÔNG xác minh — không có phiên nào ghi đường dẫn dự án này",
                    "Antigravity session images: NOT verified — no session mentions this project's path"))
    if device_state == "online":
        log_ok(tr("Device Enumeration: có thiết bị online qua 'adb devices -l'", "Device enumeration: device online via 'adb devices -l'"))

    _lap("static")
    # Layer 4: TIA Regression Impact Analysis & Marked Checklist
    print(f"\n{BOLD}[4/8] {tr('(CHẶN với --run-tests) Test hồi quy TIA (Test Impact Analysis):', '(BLOCKING with --run-tests) TIA regression tests (Test Impact Analysis):')}{RESET}")
    rules = matrix.get("rules", [])
    impacted_components = []
    regression_tests = []
    immutable_guards_protected = []

    covers = checklist_covers()
    KEYS, KEYED_IDS = {}, set()   # P2: id(suite) → (khoá chính xác, khoá cả cây); suite PASS theo khoá

    def lookup_key(t):
        """Khoá được phép DÙNG LẠI cho suite này: suite mà luật chọn cũ vẫn chạy (theo file đổi, STALE) chỉ theo khoá CẢ CÂY — khoá
        chính xác có thể thiếu input build ngầm (Gradle includeBuild, project(":feature")) mà --full cũ vẫn chạy và FAIL (review 20/10,
        P0-2); suite cached-full thêm vào (keyed_full) theo khoá chính xác."""
        ks = KEYS.get(id(t))
        return (ks[0] if t.get("keyed_full") else ks[1]) if ks else None
    keyed_hits, really_ran, recorded, voided, tree_warned = [], set(), set(), set(), []

    def precise_hit(t):
        """PASS dùng lại theo khoá CHÍNH XÁC (suite cached-full thêm vào): không chứng minh gì về nội dung cả cây — không vào biên nhận
        như PASS thật, không vào DEVKIT_GATE_DONE (review 20/10, P0-A/P0-B)."""
        return bool(t.get("keyed_full")) and id(t) in KEYED_IDS
    MATRIX_TESTS = {}             # id → các mục ma trận (cờ "cache" không vào dict suite)
    for rule in rules:
        for test in rule.get("mandatory_regression_tests", []):
            if test.get("id"):
                MATRIX_TESTS.setdefault(test["id"], []).append(test)
    for rule in rules:
        comp_name = rule.get("component", "UnknownComponent")
        watch_files = rule_watch(rule, covers)
        rule_files = [f for f in modified_files if any(match_pattern(f, pat) for pat in watch_files)]
        if not rule_files and args.tree is None:   # --tree: every rule's suites run, whatever the files
            continue
        impacted_components.append(comp_name)
        for test in rule.get("mandatory_regression_tests", []):
            regression_tests.append({
                "component": comp_name,
                "id": test.get("id"),
                "name": test.get("name"),
                "command": test.get("command"),
                "impacted_command": test.get("impacted_command"),
                "files": rule_files,
                "untested_exit": test.get("untested_exit"),
                "parallel_safe": test.get("parallel_safe") is True,
                "covered_by": test.get("covered_by") if isinstance(test.get("covered_by"), str) else None,
                "status": "NOT_RUN",
                "duration": "-",
            })
        for guard in rule.get("immutable_guards", []):
            immutable_guards_protected.append((comp_name, guard))
    impacted_tests = list(regression_tests)   # what the change itself needs (coverage verdicts)
    project_dir = get_project_dir()
    run_start_tree = head_tree(project_dir)   # the tree this run tests; mark_merge_gate_receipt keys the receipt to THIS tree, not to whatever HEAD is after the run
    force_reason = force_full_reason(args)
    # Acceptance was asked for (--full), not a Stop-hook style check: if it is deferred
    # below, the exit code must say "not accepted" (5), because an agent reading only the code would call 0 a PASS.
    asked_full = bool(getattr(args, "full", False))   # the flag only: the Stop hook inherits the environment (POSTFIX_GATE_FULL)
    # T0061 Pha 1: khối "Multi-session optimization" (hoãn --full khi có phiên anh em: 1/551 lượt, session_lock chỉ đếm phiên cùng gitdir) đã
    # bỏ; task giờ dùng biên nhận task (lượt --run-tests). deferred_by luôn rỗng, giữ cho _log_gate_run và trường "deferred" của runs.jsonl.
    deferred_by = []
    if args.session:
        try:
            sys.path.insert(0, str(Path(__file__).resolve().parent))
            import session_lock
            session_lock.heartbeat_session(str(project_dir), args.session)
        except Exception:
            pass

    # P2 (20/10): khoá nội dung của từng suite cache được (bin/suite_cache.py). Dựng cả khi --no-cache: lượt chạy thật vẫn ghi kết quả.
    # Dựng TRƯỚC khối STALE: cached-full chỉ mở rộng khi cache dùng được (DEVKIT_SUITE_CACHE=0 hay sc hỏng ⇒ luật chọn cũ).
    # Chỉ lượt cưỡng bức (--full, --force-full, CI…): Stop hook và worktree finish giữ nguyên hành vi cũ (biên nhận cả cây, budget record).
    sc = None
    expanded = [False]   # cached-full đã mở rộng trong lượt này
    if run_tests and force_reason:
        try:
            sc = suite_cache_for(project_dir, rules, find_matrix_path(args.matrix), covers)
        except Exception as e:   # noqa: BLE001 - không dựng được: mọi suite chạy như chưa có cache, không bao giờ thành PASS
            log_warn(f"suite_cache: {e!r}")
            sc = None
    if run_tests and force_reason:
        stale = stale_suite_ids(args.matrix) - {t["id"] for t in regression_tests}
        for rule in rules:
            for test in rule.get("mandatory_regression_tests", []):
                if test.get("id") in stale:
                    stale.discard(test.get("id"))
                    regression_tests.append({
                        "component": rule.get("component", "UnknownComponent"), "id": test.get("id"),
                        "name": test.get("name"), "command": test.get("command"),
                        "impacted_command": test.get("impacted_command"), "files": [],
                        "untested_exit": test.get("untested_exit"), "status": "NOT_RUN", "duration": "-",
                        "parallel_safe": test.get("parallel_safe") is True, "stale_rerun": True,
                        "covered_by": test.get("covered_by") if isinstance(test.get("covered_by"), str) else None})
        reran = [t["id"] for t in regression_tests if t.get("stale_rerun")]
        if reran:
            print(f"  • {tr('Chạy lại suite STALE của checklist (--full)', 'Re-running the checklist STALE suites (--full)')}: "
                  f"{', '.join(reran[:10])}{' …' if len(reran) > 10 else ''}")
        # --no-cache / DEVKIT_GATE_CACHE=0: luật chọn cũ, không dùng lại gì — không mở rộng cached-full (test_worktree_writers.sh:
        # --full --no-cache chạy đúng suite được chọn và suite STALE). Lần chạy thật MỌI suite cache được là việc của sentinel.
        expand_ok = not args.no_cache and os.environ.get("DEVKIT_GATE_CACHE", "1") != "0"
        if sc is not None and expand_ok:
            expanded[0] = True   # lượt này xét mọi suite cache được của ma trận (điều kiện đóng mốc sentinel)
            # P2 (20/10) CACHED-FULL: mọi suite cache được theo khoá của ma trận đều được xét; suite nào đã có PASS cho đúng khoá nội
            # dung hiện tại thì dùng lại, còn lại chạy. Bịt điểm mù của watch_files viết tay (input đổi mà không file nào khớp). Suite
            # không cache được (thiết bị/Unity, run_impacted.sh, đọc mạng, "cache": false) giữ luật chọn cũ. Chỉ thêm suite lớp nhẹ/cpu
            # (không dựng lại cái chờ slot engine). Cờ keyed_full: FAIL của chúng vào kết luận; UNTESTED (slot, khoá, ngân sách, không
            # chạy được ở máy này) thì không — luật chọn cũ không chạy chúng (review 20/10, P1-6).
            have = {t["id"] for t in regression_tests}
            added_ids = set(matrix_added or ())
            extra = []
            try:
                sys.path.insert(0, str(Path(__file__).resolve().parent))
                import heavy_slot as _hs_x  # noqa: PLC0415 - sibling module in bin/
            except Exception as e:   # noqa: BLE001 - không phân lớp được: không thêm gì (luật chọn cũ)
                log_warn(f"heavy_slot: {e!r}")
                _hs_x = None
            rec_x = _recorded_seconds(median=True) if _hs_x is not None else {}
            for rule in rules:
                for test in rule.get("mandatory_regression_tests", []):
                    tid = test.get("id")
                    if not tid or tid in have or tid in added_ids or not test.get("command") or not suite_cacheable(test)[0]:
                        continue
                    if _hs_x is None or _hs_x.classify(test["command"], str(project_dir), rec_x.get(tid),
                                                       device=bool(HARD_DEVICE_SUITE.search(test["command"])))["cls"] not in ("light", "cpu"):
                        continue
                    have.add(tid)
                    extra.append(tid)
                    regression_tests.append({
                        "component": rule.get("component", "UnknownComponent"), "id": tid,
                        "name": test.get("name"), "command": test.get("command"),
                        "impacted_command": test.get("impacted_command"), "files": [],
                        "untested_exit": test.get("untested_exit"), "status": "NOT_RUN", "duration": "-",
                        "parallel_safe": test.get("parallel_safe") is True, "keyed_full": True,
                        "covered_by": test.get("covered_by") if isinstance(test.get("covered_by"), str) else None})
            if extra:
                print(f"  • {tr('Cached-full: xét thêm suite không bị chọn (chạy khi chưa có PASS cho khoá nội dung hiện tại)', 'Cached-full: also considering unselected suites (run unless their content key already passed)')}: "
                      f"{len(extra)}")

    # 25/10 (audit B1): run_impacted.sh (DIFF_DEPENDENT) chỉ bỏ script của suite chạy TRƯỚC nó (DEVKIT_GATE_DONE). Đứng giữa ma trận, hay
    # trước suite STALE / cached-full thêm vào cuối ở trên, nó chạy lại đúng các script đó lần hai (REG-DK-ALL-01: 44 % thời gian gate của
    # workbench trong 54 h). Chạy nó SAU mọi suite khác; đuôi chỉ-thêm (matrix_added) ngay dưới vẫn là cuối cùng.
    if run_tests and suite_cache_mod() is not None:
        _dd = suite_cache_mod().DIFF_DEPENDENT
        _late = [t for t in regression_tests if _dd.search(t.get("command") or "")]
        if _late:
            regression_tests[:] = [t for t in regression_tests if not _dd.search(t.get("command") or "")] + _late

    if run_tests and matrix_added:
        # Ma trận chỉ-thêm được tin với điều kiện test thêm chạy XANH ở đây: chạy cả khi không file nào khớp watch_files của rule mới, và
        # chạy SAU mọi suite base và STALE, tuần tự (review 18/10: tác dụng phụ của lệnh thêm không được đi vào suite base).
        added_set = set(matrix_added)
        tail = [t for t in regression_tests if t.get("id") in added_set]
        have = {t["id"] for t in tail}
        for rule in rules:
            for test in rule.get("mandatory_regression_tests", []):
                if test.get("id") in added_set and test["id"] not in have:
                    have.add(test["id"])
                    tail.append({
                        "component": rule.get("component", "UnknownComponent"), "id": test["id"],
                        "name": test.get("name"), "command": test.get("command"),
                        "impacted_command": test.get("impacted_command"), "files": [],
                        "untested_exit": test.get("untested_exit"), "status": "NOT_RUN", "duration": "-", "covered_by": None})
        for t in tail:
            t.update({"parallel_safe": False, "matrix_added": True})
        regression_tests[:] = [t for t in regression_tests if t.get("id") not in added_set] + tail
        print(f"  • {tr('Ma trận chỉ THÊM rule so với', 'The matrix only ADDS rules relative to')} {base_ref}: "
              f"{tr('chạy test mới sau cùng', 'running the new tests last')} {', '.join(matrix_added[:10])}{' …' if len(matrix_added) > 10 else ''}")

    print(f"  • {tr('Dự án kích hoạt', 'Project')}: {CYAN}{matrix.get('project') or active_profile_name()}{RESET}")
    if matrix_problem:
        log_warn(matrix_problem)
    if not rules:
        log_warn(tr("Không tìm thấy regression matrix (hoặc matrix rỗng) — không đánh giá được TIA",
                    "No regression matrix found (or it is empty) — TIA cannot be evaluated"))
    if impacted_components:
        print(f"  • {tr('Component liên đới', 'Impacted components')}: {BOLD}{', '.join(dict.fromkeys(impacted_components))}{RESET}\n")
    else:
        print(f"  • {tr('Component liên đới', 'Impacted components')}: {DIM}{tr('không có (không file nào khớp watch_files)', 'none (no file matches watch_files)')}{RESET}\n")

    _lap("select")
    selection_cache = {}
    if sc is not None:
        for t in regression_tests:
            src = next((m for m in MATRIX_TESTS.get(t.get("id"), ()) if m.get("command") == t.get("command")), t)   # "cache": false
            if t.get("command") and not t.get("matrix_added") and suite_keyable(src):
                try:
                    KEYS[id(t)] = sc.keys(t)
                except Exception as e:   # noqa: BLE001 - khoá không tính được: suite này chạy
                    log_warn(f"suite_cache key {t.get('id')}: {e!r}")
        _lap("keys")
    unity_will_test = any(unity_suite_compiles(t.get("command") or "") for t in regression_tests)
    # Held for every suite run, re-run and vacuity revert (which rewrites production files in
    # the tree) of this gate, and NOT closed after the suite loop: a run waiting for this lock
    # polls every 0.5 s and, if it won the lock before the full-pass receipt below was written
    # (the static audits and the receipt's own fingerprint sit in between: 0.1-20 s), found no
    # receipt to re-use and ran every suite again. Closed right after the receipt block below.
    cache = None
    tested_fp = tree_fp_of(project_dir) if run_tests and force_reason else None
    # T0061: cây mà một lượt task kiểm, lấy TRƯỚC khi suite chạy (biên nhận task chỉ ghi khi cây vẫn là nó; một FAIL bỏ biên nhận của cây đó)
    task_fp = tree_fp_of(project_dir) if (run_tests and not force_reason and not deferred_by and not args.since and task_off_trunk
                                          and task_mb and os.environ.get("DEVKIT_GATE_MERGE_CHECK") != "1") else None
    # #472 mục B: file TEST đã có bị sửa mà chưa duyệt thì kết luận chắc chắn là CHƯA XÁC MINH (edited_test): lượt không lấy khoá dự án và
    # không chạy suite nào (baseline 24-27/10: 29/55 lượt như vậy chạy suite trước, 20 lượt chờ khoá trước). Lớp tĩnh đã chạy ở trên nên
    # REJECT tĩnh vẫn exit 1; một FAIL của suite không thể xảy ra vì suite không chạy — thứ tự kết luận giữ nguyên, lượt sau khi duyệt chạy
    # suite và bắt FAIL đó (exit 2 không bao giờ là PASS). Không áp cho:
    #   - merge check của `worktree finish` (DEVKIT_GATE_MERGE_CHECK=1): exit 2 ở đó không chặn gộp, suite phải chạy để bắt hồi quy;
    #   - lượt kiểu Stop (--session, hay GATE_TOTAL_BUDGET_S đặt): hooks/regression_gate.sh chạy suite MỘT lần trên nội dung đang chờ duyệt,
    #     ghi budget record rồi chỉ nhắc, không chạy lại (tests/gates/test_gate_stop_run_record.sh A1-A14 B1-B6,
    #     test_regression_gate_repeat_cache.sh 5c);
    #   - lượt cưỡng bức (--full, CI, …): điểm gộp và các ca đo FLAKY/infra_retry trên script test đã sửa (test_gate_audit_holes.sh A7);
    #   - script lệnh suite bị sửa (runners_touched): FAIL của nó vẫn là REJECT như cũ (test_regression_checklist.sh ca 3).
    # ponytail: chỉ lượt CLI impacted được rút ngắn; mở rộng sang lượt Stop khi runs.jsonl (source, exit_reason edited_test) cho thấy chúng
    # chiếm phần lớn giờ máy phí — cần đổi thiết kế budget record của Stop hook cùng lúc.
    try:
        _stop_budget = float(os.environ.get("GATE_TOTAL_BUDGET_S") or 0) > 0
    except ValueError:
        _stop_budget = False
    edited_early = bool(run_tests and not args.session and not _stop_budget and not force_reason
                        and os.environ.get("DEVKIT_GATE_MERGE_CHECK") != "1"
                        and not runners_touched and tests_touched)
    if edited_early:
        for t in regression_tests:
            if t.get("command"):
                t.update({"status": "UNTESTED", "label": "EDITED", "mode": "edited", "duration": "0s", "output_tail": tr(
                    # cách chữa nằm ở dòng kết luận (khác nhau theo --since: commit hay `Test-approved-by:`), không lặp lại ở đây
                    "Không chạy: test đã có bị sửa chưa được duyệt — xem cách chữa ở dòng KẾT LUẬN rồi chạy lại gate",
                    "Not run: an existing test was edited and is not approved — see the verdict line for how to clear it, then re-run the gate")})
        print(f"    {YELLOW}▶ {tr('Test đã có bị sửa chưa duyệt: không lấy khoá, không chạy suite nào (kết luận: CHƯA XÁC MINH)', 'Edited existing test not approved: no lock taken, no suite runs (verdict: UNVERIFIED)')}{RESET}")
    use_cache = run_tests and not edited_early and not args.no_cache and os.environ.get("DEVKIT_GATE_CACHE", "1") != "0" \
        and any(t.get("command") for t in regression_tests)
    # P3 (20/10) sentinel: lượt cưỡng bức khi lần chạy THẬT đủ suite gần nhất của repo đã quá DEVKIT_SENTINEL_MAX_S (24 h) không dùng
    # lại gì (cả biên nhận lẫn khoá): nó kiểm chính cache. Suite FAIL trên khoá mà sổ nói PASS ⇒ học input thiếu hoặc cách ly (record_keyed).
    # merge gate / worktree finish (DEVKIT_SLOT_PRIORITY=merge) không gánh lần chạy thật hằng ngày: chúng có hạn giờ và chặn người khác
    sentinel_run = bool(force_reason and use_cache and sc is not None and sc.sentinel_due()
                        and (os.environ.get("DEVKIT_SLOT_PRIORITY") or "").strip().lower() != "merge")
    # sentinel chỉ tắt khoá nội dung (keyed_ok); biên nhận cả cây (đúng nội dung này, như --full trước P2) vẫn dùng lại được. Lượt dùng lại
    # biên nhận không đóng mốc sentinel (stamp_sentinel cần mọi suite cache được chạy thật), nên lượt cưỡng bức sau vẫn là sentinel.
    keyed_ok = use_cache and not sentinel_run
    # B2 (audit 25/10): sổ PASS theo từng test của run_impacted.sh (tests/lib/per_test_cache.py) theo đúng chế độ khoá của lượt này: "1" dùng
    # lại + ghi, "record" chỉ ghi (sentinel, --no-cache, DEVKIT_GATE_CACHE=0), "0" tắt (không có sc: DEVKIT_SUITE_CACHE=0, lượt không cưỡng bức;
    # hay người dùng đặt sẵn DEVKIT_PER_TEST_CACHE=0). run_in_group chỉ đưa nó cho lệnh run_impacted.sh chuẩn. tests/gates/test_gate_per_test_cache.sh.
    if os.environ.get("DEVKIT_PER_TEST_CACHE") != "0":
        PER_TEST_CACHE["mode"] = "0" if sc is None else ("1" if keyed_ok else "record")
    if sentinel_run:
        print(f"    {CYAN}▶ {tr('sentinel: lần chạy thật đủ suite gần nhất của repo đã quá hạn — lượt này không dùng khoá nội dung, chạy thật mọi suite cache được để kiểm cache', 'sentinel: the repo’s last real full run is too old — this run uses no content key and runs every cacheable suite for real to check the cache')}{RESET}")
    overlay_pre = capture_overlay_pre(args, matrix, project_dir, regression_tests) if run_tests else None   # BEFORE any suite runs
    # GATE_TOTAL_BUDGET_S: seconds after which no NEW suite starts (a Stop hook has a hard timeout; 2026-10-02: a run of
    # ~10 suites at 600 s each, no total cap, was cut silently at 27 min). Suites left are UNTESTED/BUDGET, never PASS.
    # ponytail: a suite already running is not cut (its own --timeout bounds it). What the suites that finished proved is kept for
    # the next Stop on the same content (BUDGET_RECORD, 2026-10-14, Goods: two Unity suites of 901-967 s ran again at every Stop).
    # A resumed run that then completes does not update the record: the hook's pass_fp ends the cycle there, and a later
    # non-forced run of this content runs the suites that were left once more; upgrade if that is ever seen to cost minutes.
    try:
        budget_s = float(os.environ.get("GATE_TOTAL_BUDGET_S") or 0)
    except ValueError:
        budget_s = 0.0
    # The content this run tests, taken BEFORE the first reuse, the lock wait and the suites (a forced run already has it; a Stop run
    # took none): a suite marked re-used below and a suite that runs both belong to it, and a budget record is written only when
    # the tree is still this one afterwards. A13: the same value feeds the reuse, so it is not taken twice.
    budget_fp = tested_fp or (tree_fp_of(project_dir) if budget_s > 0 and use_cache else None)
    budget_head = _head_sha(project_dir) if budget_fp and not force_reason else None   # the HEAD of the same moment: a Stop record names both

    def reuse_from(found, budget_run=False, partial=False):
        """Mark every reusable suite PASS from `found`, the receipt (or the budget record) of this exact content; it, or None.
        partial (biên nhận của worktree anh em): suite mà biên nhận KHÔNG có thì chạy thật, không huỷ cả lần dùng lại — merge gate #56
        (17/10): scratch không có overlay checklist của worktree nên chạy thêm một suite STALE nhẹ, và vì biên nhận thiếu đúng suite đó
        mà cả 4 suite nặng chạy lại. Suite biên nhận CÓ thì vẫn phải PASS, trừ UNTESTED: chạy lại đúng suite đó."""
        prev = {x.get("id"): x for x in (found or {}).get("tests") or []}
        # those run again: the "untested" ids of an exit-4 receipt, and any suite the receipt holds as UNTESTED — an exit-0 one keeps a STALE
        # suite that could not run on that machine (stale_skipped, outside the verdict): GeelyEx2 #64 (18/10), REG-WEB-01 UNTESTED cancelled
        # the whole reuse and REG-CAR-01 ran again. It vouches for nothing either way; the suites it holds as PASS still stand.
        untested = set((found or {}).get("untested") or []) | {i for i, x in prev.items() if x.get("status") == "UNTESTED"}
        try:
            unity_max_s = float(os.environ.get("DEVKIT_UNITY_REUSE_MAX_S", "3600"))
        except ValueError:
            unity_max_s = 3600.0

        def ran_at(t):   # when this suite really ran: its own stamp, else the receipt's (a receipt without ran_at)
            return float((prev.get(t.get("id")) or {}).get("ran_at") or (found or {}).get("tested_at") or 0)

        def reusable_suite(t):
            cmd = t["command"]
            if sc is not None and any(sc.blocked(k, t.get("id")) for k in (KEYS.get(id(t)) or (None,))):
                return False   # P2: khoá hiện tại từng FAIL hoặc suite bị cách ly (flaky): không có PASS nào được dùng lại cho nó
            if not DEVICE_SUITE.search(cmd):
                return True
            return bool(UNITY_SUITE.search(cmd) and not HARD_DEVICE_SUITE.search(cmd) and 0 < unity_max_s
                        and 0 <= time.time() - ran_at(t) <= unity_max_s)

        # suite cached-full thêm vào (keyed_full) mà biên nhận không có: --full trước P2 không chạy nó, nên nó không huỷ lần dùng lại;
        # nó được tra theo khoá của nó hoặc chạy thật
        reusable = [t for t in regression_tests if t.get("command") and reusable_suite(t)
                    and t.get("id") not in untested and (t.get("id") in prev or not (partial or t.get("keyed_full")))]
        # a suite is matched by id AND, for the record, by the matrix command it passed under (a byte-equal matrix file under another --diff or
        # --matrix can name another command for the same id); a record that names none is not read
        if not (found and reusable and all(prev.get(t["id"], {}).get("status") == "PASS"
                                           and (not budget_run or prev[t["id"]].get("full_command") == t["command"]) for t in reusable)):
            return None
        at = time.strftime("%H:%M", time.localtime(float(found.get("tested_at") or 0)))
        for t in reusable:
            SUITE_RAN_AT[t.get("id")] = ran_at(t)   # a re-use never renews the stamp
            # the real duration: pre-commit picks light suites by the recorded one
            t.update({"status": "PASS", "duration": prev[t["id"]].get("duration") or "0s", "mode": "cached",
                      "log": prev[t["id"]].get("log"), "exit_code": 0,
                      "tested_at": float(found.get("tested_at") or 0),
                      "label": tr(f"PASS (dùng lại kết quả lúc {at}, cùng nội dung)", f"PASS (reused from {at}, same content)")})
        if budget_run:
            print(f"    {CYAN}▶ {tr(f'dùng lại suite đã PASS trong lượt kiểu Stop trước lúc {at}: cùng nội dung, cùng HEAD, cùng cách đọc kết quả, cùng ma trận; suite chưa chạy thì chạy bây giờ (--no-cache để chạy lại hết)', f'reusing the suites that passed in the earlier Stop-style run of {at}: same content, HEAD, result format and matrix; the suites that did not run run now (--no-cache to re-run all)')}{RESET}")
        elif partial and len(reusable) < sum(1 for t in regression_tests if t.get("command")):
            n_run = sum(1 for t in regression_tests if t.get("command")) - len(reusable)
            print(f"    {CYAN}▶ {tr(f'dùng lại {len(reusable)} suite đã PASS lúc {at} (cùng nội dung, cùng ma trận); chạy thật {n_run} suite còn lại', f'reusing {len(reusable)} suite(s) that passed at {at} (same content, same matrix); running the other {n_run} suite(s)')}{RESET}")
        else:
            print(f"    {CYAN}▶ {tr(f'dùng lại PASS đầy đủ lúc {at}: cùng nội dung, cùng cách đọc kết quả, cùng ma trận (--no-cache để chạy lại)', f'reusing the full PASS of {at}: same content, result format and matrix (--no-cache to re-run)')}{RESET}")
        return found

    reuse_src = [None]   # (file, its stamp taken BEFORE it was read, its record name: None = the receipt, biên nhận của worktree anh em?) of the file that vouched for the suites this run re-used

    def reuse_full_pass(fp=None):
        """Mark every reusable suite PASS from the last full PASS of this exact content; its receipt, or None. A non-forced run
        (the Stop hook) also reads the record a budget-cut run left (BUDGET_RECORD) when the receipt gives it nothing. Cuối cùng: biên
        nhận full-pass của worktree anh em cùng repo (sibling_receipts), cùng các kiểm tra — scratch của merge gate có git dir mới.
        Chỉ cho lượt --full cưỡng bức trong một git dir CHƯA từng có biên nhận (scratch của merge gate, worktree mới): Stop hook, main
        checkout và worktree đã có biên nhận giữ đúng hành vi cũ; thư mục đã từng chạy gate (có dòng run-log) cũng không mượn."""
        for name in ((None,) if force_reason else (None, BUDGET_RECORD)):
            src = _result_file(project_dir, name)
            stamp = _file_stamp(src)   # before the read: a change after it shows as another stamp when the record is written
            found = reuse_from(cached_full_pass(project_dir, args.matrix, fp, name), name is not None)
            if found:
                reuse_src[0] = (src, stamp, name, False)
                return found
        if not force_reason:
            return None
        own = _result_file(project_dir, None)
        if not own or _file_stamp(own) is not None or _ever_gated(project_dir):
            return None
        # ponytail: biên nhận anh em được ghi/xoá dưới test_run.lock CỦA worktree kia, không phải khoá lượt này giữ (F1): anh em FAIL sau lần
        # stale_reused cuối mà trước khi lượt này ghi biên nhận thì lượt này vẫn exit 0 — cùng loại cửa sổ read-only đã ghi bên dưới; khoá
        # cả lock của worktree anh em (LOCK_NB) khi gặp một ca như vậy.
        siblings = sibling_receipts(project_dir)
        # #247: sau các biên nhận anh em còn một nguồn nữa — mục theo cây trong store, sống sau khi worktree ghi nó bị gỡ (Builder bước 9)
        fp = (fp or tree_fp_of(project_dir)) or None   # một lần cho mọi biên nhận (anh em và store), không phải mỗi file một lần
        for path in siblings + tree_store_receipts(project_dir, fp):
            from_store = os.path.basename(os.path.dirname(path)) == TREE_STORE_DIR
            stamp = _file_stamp(path)
            found = reuse_from(cached_full_pass(project_dir, args.matrix, fp, None, path), partial=True)
            if found:
                kind = (tr('biên nhận theo cây', 'tree receipt') if from_store else tr('biên nhận của worktree anh em', 'sibling worktree receipt'))
                print(f"    {DIM}({kind}: {path}){RESET}")
                regen = regen_allowed(found.get("local_regen") or [])   # what cached_full_pass left out, filtered the same way
                if regen:   # what the comparison of local state left out: the files its suites rewrote (local_regen)
                    print(f"    {DIM}{tr('không so (suite tự ghi lại)', 'not compared (rewritten by its suites)')}: {len(regen)}: {', '.join(regen[:3])}{RESET}")
                reuse_src[0] = (path, stamp, None, True)
                return found
        return None

    def recheck_keyed():
        """PASS dùng lại theo khoá phải còn đứng vững (sổ khoá có flock riêng; một FAIL vừa ghi ở lượt/worktree khác lật nó thành UNTESTED).
        Gọi sau các suite và một lần nữa ngay trước kết luận, có hay không có khoá dự án (review 20/10, P1-5)."""
        if sc is None:
            return
        gone_keyed = [t for t in keyed_hits if t.get("status") == "PASS" and not sc.hit(lookup_key(t), t)]
        for t in gone_keyed:
            KEYED_IDS.discard(id(t))
            t.update({"status": "UNTESTED", "label": "STALE", "output_tail": tr(
                "PASS theo khoá nội dung không còn đứng vững (khoá vừa FAIL ở lượt khác, bị cách ly hoặc hết tuổi) — chạy lại gate",
                "The content-key PASS no longer stands (the key just FAILED elsewhere, was quarantined or expired) — run the gate again")})
        if gone_keyed:
            log_warn(tr(f"{len(gone_keyed)} PASS theo khoá không còn đứng vững — thành UNTESTED",
                        f"{len(gone_keyed)} content-key PASS no longer stand — UNTESTED"))

    def reused_tested_at():
        """Lúc chạy cũ nhất của các suite PASS dùng lại (biên nhận cả cây hoặc khoá); None khi lượt này không dùng lại gì."""
        ts = [float(t.get("tested_at") or 0) for t in regression_tests if t.get("mode") == "cached" and t.get("status") == "PASS"]
        if cache:
            ts.append(float(cache.get("tested_at") or 0))
        return min(ts) if ts else None

    def reused_pass():
        return [t for t in regression_tests if t.get("mode") == "cached" and t.get("status") == "PASS" and id(t) not in KEYED_IDS]

    def mark_keyed(t, rec):
        """Suite dùng lại PASS theo khoá nội dung (P2)."""
        at = float(rec.get("last_pass_at") or 0)
        SUITE_RAN_AT[t.get("id")] = at
        t.update({"status": "PASS", "duration": rec.get("duration") or "0s", "mode": "cached", "log": rec.get("log"), "exit_code": 0,
                  "tested_at": at, "label": tr(f"PASS (khoá nội dung, lúc {time.strftime('%H:%M', time.localtime(at))})",
                                               f"PASS (content key, {time.strftime('%H:%M', time.localtime(at))})")})
        KEYED_IDS.add(id(t))
        keyed_hits.append(t)

    def stale_reused():
        """The re-used suites that no longer stand. The file that vouched for them is gone, or is another file than the one this run read (a forced
        run that FAILED a suite deletes it; another run that PASSED rewrites it: another inode and ctime) and what is on disk now does not say PASS
        for them under the same keys (cached_full_pass: content, matrix, local state, HEAD, format, age). A rewritten file that still vouches for a
        suite keeps it and becomes the file this run stands on. F1: a FAIL is never turned back into a PASS by a stale reader or writer. Asked
        under test_run.lock after the suites ran, and again right before the verdict; stat only while nothing moved."""
        if not reuse_src[0]:
            return []
        src, stamp, name, sibling = reuse_src[0]
        now = _file_stamp(src)   # before the read, as at the first one
        if now == stamp:
            return []
        # biên nhận của worktree anh em: đọc lại đúng file đó với luật của anh em; biên nhận của mình: như cũ (path None)
        found = cached_full_pass(project_dir, args.matrix, budget_fp, name, src if sibling else None) if now else None
        if found:
            reuse_src[0] = (src, now, name, sibling)
        prev = {x.get("id"): x for x in (found or {}).get("tests") or []}
        untested = set((found or {}).get("untested") or [])
        return [t for t in reused_pass() if not (found and t["id"] not in untested and prev.get(t["id"], {}).get("status") == "PASS"
                                                 and (name is None or prev[t["id"]].get("full_command") == t["command"]))]

    def stale_to_untested(label, gone):
        """A re-used PASS that cannot be stood on (its file moved and no longer vouches for it, or there is no lock to check it under) is UNTESTED,
        never PASS; the number turned. Every later reader (verdict, receipt, Stop record, checklist) reads the suites' status, so this is the one
        place that decides it."""
        for t in gone:
            t.update({"status": "UNTESTED", "label": label, "output_tail": tr(
                "PASS dùng lại không còn đứng vững: file đã xác nhận nó đã đổi/biến mất, hoặc không có khoá để kiểm tra lại — chạy lại gate",
                "The re-used PASS no longer stands: the file that vouched for it changed or is gone, or there was no lock to check it under — run the gate again")})
        return len(gone)

    def receipt_stamp():
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        try:
            import tree_fp  # noqa: PLC0415 - sibling module in bin/
            st = os.stat(tree_fp.receipt_path(project_dir))
            return (st.st_mtime_ns, st.st_size)
        except (ImportError, OSError, TypeError):
            return None

    stamp_before = receipt_stamp() if use_cache else None
    if use_cache:
        # budget_fp (= tested_fp for a forced run) was taken just above and nothing has run since: the same tree (A13). The
        # re-check after the lock wait below takes a fresh one: the tree may have changed while this run waited.
        cache = reuse_full_pass(budget_fp)
    if sc is not None and keyed_ok:
        for t in regression_tests:
            k = lookup_key(t)
            if k and t.get("mode") != "cached":
                rec = sc.hit(k, t)
                if rec:
                    mark_keyed(t, rec)
        if keyed_hits:
            print(f"    {CYAN}▶ {tr(f'dùng lại {len(keyed_hits)} suite theo khoá nội dung (cùng input, cùng môi trường; --no-cache để chạy lại)', f'reusing {len(keyed_hits)} suite(s) by content key (same inputs and environment; --no-cache to re-run)')}{RESET}")
    _lap("cache")
    to_run = [t for t in regression_tests if t.get("mode") not in ("cached", "edited")]
    # A run that re-used a suite takes the lock even when it has nothing left to run: the check that what it re-used still stands and the writes
    # that follow it are one step under the lock (a forced run that FAILS the suite deletes the file holding the PASS while it holds this lock).
    # But it waits only DEVKIT_REUSE_LOCK_WAIT_S (default 3 s), not TEST_RUN_LOCK_WAIT_S (45 s through the Stop hook): it has no suite to run, and
    # before this check it needed no lock at all. Past that short wait it is READ-ONLY (read_only below): it judges from a stamp check and writes nothing.
    nothing_to_run = not any(t.get("command") for t in to_run)
    reuse_wait_s = _env_seconds("DEVKIT_REUSE_LOCK_WAIT_S", 3.0)
    gate_slot = None
    gate_slot_busy = False
    gate_slot_hs = None
    prev_gate_slot_held = os.environ.get("DEVKIT_GATE_SLOT_HELD")
    lock_fh, lock_held = (acquire_test_run_lock(project_dir, cap=reuse_wait_s if nothing_to_run else None)
                          if run_tests and (reuse_src[0] or keyed_hits or not nothing_to_run) else (None, True))
    # Read-only: every suite was re-used and the lock was not obtained within the short wait. The verdict is the stamp check alone (the file that vouched
    # for the PASS still stands, or still says PASS: exit as before; moved and no longer vouching: UNTESTED, exit 4) and nothing is written: no receipt,
    # no Stop record, no PASS row in the checklist, and a receipt that this run's non-zero verdict contradicts is only DROPPED, never loaded and written
    # back (write_full_pass_receipt locked=False): this run cannot put back a PASS that a FAIL took away. Why an exit 0 here is no false PASS: it is
    # given only while the persisted file still says PASS (the only writers of that file hold the lock this run does not have), and a FAIL that no one has
    # persisted yet is known to no one: the same as this run having finished just before that run started. What the Stop hook stores for exit 0 (pass_fp)
    # is keyed on the content, as for any PASS.
    # ponytail: a suite that starts to fail on UNCHANGED content while another run holds the lock is seen by this run's reader only after that run
    # persists its FAIL; DEVKIT_REUSE_LOCK_WAIT_S as long as TEST_RUN_LOCK_WAIT_S waits for it instead.
    read_only = bool(run_tests and not lock_held and nothing_to_run)
    # Another run (a second session, or a gate still running in the background) may have recorded a
    # full PASS of this same content since the check above — while we waited for its lock, or just
    # before we reached the lock: re-use it instead of running every suite again (audit 2026-09-29).
    # Keyed on the receipt file changing, not on how long the lock took: under load the other run
    # can finish before this one reaches the lock (a timing threshold missed that; review 2026-09-29).
    if use_cache and cache is None and lock_held and receipt_stamp() not in (None, stamp_before):
        cache = reuse_full_pass()
        to_run = [t for t in regression_tests if t.get("mode") not in ("cached", "edited")]
        nothing_to_run = not any(t.get("command") for t in to_run)
    # T0056: hàng đợi gate toàn máy (pool 'gate', tối đa N lượt chạy suite cùng lúc). Chỉ xin slot khi đã giữ khoá dự án,
    # thực sự còn suite cần chạy và tiến trình cha chưa giữ slot (DEVKIT_GATE_SLOT_HELD != "1").
    if run_tests and lock_held and not nothing_to_run and prev_gate_slot_held != "1":
        gate_slots_n = default_gate_slots()
        if gate_slots_n > 0:
            try:
                _bin = str(Path(__file__).resolve().parent)
                if _bin not in sys.path:
                    sys.path.insert(0, _bin)
                import heavy_slot as _gate_hs  # noqa: PLC0415 - sibling module in bin/
                gate_slot_hs = _gate_hs
            except Exception as exc:   # noqa: BLE001 - thiếu heavy_slot thì chạy tiếp không khoá như take_slots()
                log_warn(f"heavy_slot: {exc}")
            if gate_slot_hs is not None:
                gate_wait_s = _env_seconds("DEVKIT_GATE_SLOT_WAIT_S", 1800.0)
                # ponytail: test_run.lock của dự án vẫn bị giữ trong lúc chờ slot, nên một Stop hook cùng checkout báo BUSY với
                # busy_reason=project_lock dù máy thực ra đang nghẽn hàng đợi gate; và dưới SB_HEAVY_SLOT_HELD=1 acquire_pool trả
                # prev_held mà vẫn đặt DEVKIT_GATE_SLOT_HELD. Ghi nhãn holder vào khoá khi người dùng thấy báo sai lý do.
                gate_slot = gate_slot_hs.acquire_pool(
                    "gate", gate_slot_hs.pool_paths("gate", gate_slots_n),
                    wait_s=gate_wait_s, label=os.path.basename(str(project_dir))[:64])
                if gate_slot.timed_out:
                    if lock_fh is not None:
                        _write_test_run_lock_holder(lock_fh, clear=True)
                        lock_fh.close()
                        lock_fh = None
                    lock_held = False
                    gate_slot_busy = True
                    gate_slot = None
                else:
                    os.environ["DEVKIT_GATE_SLOT_HELD"] = "1"
                    # Trong lúc chờ slot, lượt khác có thể đã ghi biên nhận, đóng mốc sentinel hoặc nạp suite_cache:
                    # kiểm tra lại ngay, nếu không còn suite nào cần chạy thì trả slot liền cho hàng đợi.
                    if use_cache and cache is None:
                        cache = reuse_full_pass()
                    if use_cache and sc is not None and not keyed_ok and not sc.sentinel_due():
                        sentinel_run = False
                        keyed_ok = True
                    if sc is not None and keyed_ok:
                        prev_keyed_n = len(keyed_hits)
                        for t in regression_tests:
                            k = lookup_key(t)
                            if k and t.get("mode") != "cached":
                                rec = sc.hit(k, t)
                                if rec:
                                    mark_keyed(t, rec)
                        if len(keyed_hits) > prev_keyed_n:
                            print(f"    {CYAN}▶ {tr(f'dùng lại {len(keyed_hits) - prev_keyed_n} suite theo khoá nội dung sau khi chờ slot', f'reusing {len(keyed_hits) - prev_keyed_n} suite(s) by content key after slot wait')}{RESET}")
                    to_run = [t for t in regression_tests if t.get("mode") not in ("cached", "edited")]
                    nothing_to_run = not any(t.get("command") for t in to_run)
                    if nothing_to_run:
                        gate_slot_hs.release_pool(gate_slot)
                        gate_slot = None
                        if prev_gate_slot_held is None:
                            os.environ.pop("DEVKIT_GATE_SLOT_HELD", None)
                        else:
                            os.environ["DEVKIT_GATE_SLOT_HELD"] = prev_gate_slot_held
    _lap("lock")
    # One run per distinct command (O2, 2026-09-28): two rules naming one command share its result,
    # and the test scripts run so far go to DEVKIT_GATE_DONE so run_impacted.sh skips them.
    ran_cmds, done_scripts = {}, []
    _config_snaps = snapshot_local_configs(project_dir)
    global LOCAL_STATE_BEFORE   # what the suites below rewrite is left out of the receipt's local_sha (local_regen)
    LOCAL_STATE_BEFORE = None   # never a snapshot of an earlier main() in this process
    # only a run that can write the full-pass receipt (the `partial` test at its call below): a Stop or impacted run never reads it (1.3-2.9 s, GeelyEx2)
    if run_tests and lock_held and force_reason and any(t.get("command") for t in to_run) \
            and not any(t.get("mode") in PARTIAL_MODES for t in regression_tests):
        try:
            LOCAL_STATE_BEFORE = local_state_files(project_dir)
        except Exception as e:   # no snapshot: local_sha covers every file, as before (the scratch runs the suites, never a wrong reuse)
            log_warn(f"local_state_files: {e}")
    budget_start = time.monotonic()   # budget_s: parsed above, with the fingerprint the budget record is bound to
    # Plan 1c (2026-10-07): suites the base-ref matrix marks "parallel_safe": true, next to each other in matrix order,
    # run side by side as one group: the DevKit's five independent suites took the SUM of their times. A suite without
    # the flag is a barrier: the group before it finishes first, so nothing runs next to it. Only mode "full" joins a
    # group, which keeps vacuity_revert (it rewrites production files in the tree) from ever running next to another
    # suite. DEVKIT_GATE_PARALLEL=0 turns it off; a number caps the group (default: capacity gate_parallel, 6 on 12 idle cores).
    # ponytail: a flaky re-run of a grouped suite sees os.environ's DEVKIT_GATE_DONE, the scripts of the suites run alone
    # before it, not its group mates' (it re-runs them: slower, never less checked); upgrade if grouped suites retry often.
    # run_impacted.sh không vào nhóm này (may_join): các job của nó (run_impacted.sh --jobs) cộng GATE/HOOK đẩy suite quá 900 s.
    # ponytail: a grouped suite's recorded duration is wall time under contention (GATE-02 20 s alone, 26 s in the group), so
    # pre-commit's "skip a suite that took > DEVKIT_PRECOMMIT_MAX_S" can fire earlier; the Stop and push gates still run it.
    # T0052: không đặt / rỗng / không phải số nguyên thì bin/capacity.py gate_parallel (lõi/2 × DEVKIT_CAPACITY × phần máy rảnh, sàn 2;
    # 12 lõi rảnh: 6), không nạp được capacity thì 6 như cũ. Số đã đặt dùng nguyên: 0 và 1 vẫn là công tắc chạy tuần tự.
    try:
        parallel_cap = int(os.environ.get("DEVKIT_GATE_PARALLEL", "").strip())
    except ValueError:
        parallel_cap = default_gate_parallel()
    slots = threading.BoundedSemaphore(max(parallel_cap, 1))
    group, group_ts, deferred = [], set(), []

    def budget_spent():
        return budget_s > 0 and time.monotonic() - budget_start >= budget_s

    def mark_budget(t):
        t.update({"status": "UNTESTED", "label": "BUDGET", "duration": "0s", "output_tail": tr(
            f"Hết ngân sách thời gian GATE_TOTAL_BUDGET_S ({budget_s:.0f}s) — suite này chưa chạy",
            f"Time budget GATE_TOTAL_BUDGET_S ({budget_s:.0f}s) spent — this suite did not run")})

    def may_join(t):
        # flagged, and not a suite that must run alone: Gradle/Unity/device runs share build state (build/test-results)
        c = t.get("command") or ""
        # run_impacted.sh tự mở nhiều job (run_impacted.sh --jobs). Nhét nó vào nhóm parallel_safe (cùng GATE/HOOK) đo được
        # ~330 s một mình thành TIMEOUT đúng 900 s (runs.jsonl 19/10, wall 15–20 phút).
        # ponytail: chỉ script này; suite fan-out khác vẫn phải bỏ cờ. Nâng cấp khi có script thứ hai.
        if re.search(r"(?:^|[\s;|&])(?:\S*/)?run_impacted\.sh(?:$|[\s;|&])", c):
            return False
        return bool(parallel_cap > 1 and t.get("parallel_safe") and not (PRECOMMIT_HEAVY.search(c) or DEVICE_SUITE.search(c)))

    def share_result(t, prev):
        if id(prev) in KEYED_IDS and prev.get("keyed_full"):
            # prev được dùng lại theo khoá CỦA NÓ; khoá của suite này có thể khác (rule, watch_files khác): tra khoá của chính nó,
            # không có PASS thì chạy thật (review 20/10, P0-1)
            k = lookup_key(t) if sc is not None else None
            rec = sc.hit(k, t) if k else None
            if rec:
                mark_keyed(t, rec)
            else:
                run_suite(t, t["command"], t.get("mode") or "full", suite_env())
            return
        for k in ("status", "exit_code", "output_tail", "log", "flaky", "infra", "infra_retry",
                  "env_blocked", "vacuity", "fail_lines"):
            if k in prev:
                t[k] = prev[k]
        t["duration"] = prev.get("duration") or "0s"   # its real cost, for pre-commit's light-suite pick
        t["label"] = f"{prev.get('label') or prev['status']} ({tr('cùng lệnh với', 'same command as')} {prev['id']})"
        if id(prev) in really_ran:
            really_ran.add(id(t))
        elif id(prev) in KEYED_IDS:   # prev dùng lại theo khoá cả cây: cùng lệnh, cùng nội dung — cũng là PASS dùng lại (không vào checklist)
            KEYED_IDS.add(id(t))

    def note_ran(cmd):
        # Only a script the command RUNS (`bash|sh|zsh <path>`, `./<path>` opening a segment):
        # `cat tests/x.sh` read it, it did not run it (Antigravity review).
        for m in RAN_SCRIPT.finditer(cmd):
            done_scripts.append(os.path.realpath(os.path.join(str(project_dir), m.group(1) or m.group(2))))

    def may_note(t):
        """Script của suite này được báo cho run_impacted.sh chạy sau (DEVKIT_GATE_DONE) không. Suite STALE / cached-full (keyed_full) chỉ
        khi CHẠY THẬT trong lượt này và PASS (audit B1, 25/10): giờ chúng đứng trước run_impacted.sh, mà FAIL / quá giờ / UNTESTED của chúng
        có thể ra ngoài kết luận (KNOWN-RED, untested_exit) — script đó phải còn được run_impacted.sh chạy. PASS theo khoá chính xác: không."""
        if t.get("matrix_added") or precise_hit(t):
            return False
        return not (t.get("keyed_full") or t.get("stale_rerun")) or (id(t) in really_ran and t.get("status") == "PASS")
    late_notes = []   # (suite, lệnh) trong nhóm song song mà may_note chỉ biết được sau khi nhóm xong

    slot_rec = _recorded_seconds(median=True) if run_tests and lock_held else {}   # lớp slot: trung vị, không phải lần dài nhất (B7)
    # Hạn marker gộp lượt (suite_cache.inflight: est×1.5+60 s) theo lần DÀI NHẤT: trung vị làm hạn ngắn hơn lần chạy thật (REG-DK-HEALTH-01:
    # 389 s → 163 s), một gate --full thứ hai cùng khoá xoá marker của chủ còn sống và chạy song song (review 25/10).
    inflight_rec = _recorded_seconds() if run_tests and lock_held else {}
    slot_waits = {}   # id(suite) → giây chờ slot (tải máy / khoá Unity) của lượt này: vào runs.jsonl (slot_wait_s, audit B9)
    slot_mod = []
    # #338: lượt đã có suite được cho chạy thì chạy cho xong. started_run: không chờ tải lại ở các suite sau; heavy_lease: slot nặng giữ nguyên
    # giữa hai suite nặng TUẦN TỰ liền nhau (gate khác không chen được; suite trong nhóm song song vẫn xin slot riêng, nên tổng suite nặng
    # chạy cùng lúc không vượt heavy_max). Nhả khi tới suite không nặng, trước một job song song (nó chờ chính slot này sẽ treo tới hạn chờ) và
    # hết vòng suite.
    started_run, heavy_lease = [], []

    def drop_lease():
        if heavy_lease and slot_mod and slot_mod[0] is not None:
            slot_mod[0].release_pool(heavy_lease.pop())
        heavy_lease.clear()

    def take_slots(t, cmd, sequential=False):
        """P1 (20/10): quyền chạy của CHÍNH suite này (heavy_slot.classify), giữ trong lúc nó chạy — kể cả lần chạy lại flaky và
        vacuity revert. --full không còn giữ slot cả lượt (đo 20/10: một lượt --full chỉ suite bash/python chờ 30+ phút mà không chạy
        suite nào); P1b (người dùng 20/10): không còn 2 slot — tải máy dưới DEVKIT_SLOT_LOAD_MAX (mặc định capacity hold_load,
        12 lõi: 96) thì chạy, chỉ Unity còn khoá độc quyền. None: không có heavy_slot."""
        if not slot_mod:
            try:
                sys.path.insert(0, str(Path(__file__).resolve().parent))
                import heavy_slot as _hs  # noqa: PLC0415 - sibling module in bin/
                slot_mod.append(_hs)
            except Exception as exc:   # không có module: chạy không khoá, như khi thiếu thư mục khoá
                log_warn(f"heavy_slot: {exc}")
                slot_mod.append(None)
        hs = slot_mod[0]
        if hs is None:
            return None
        rec = slot_rec.get(t.get("id"))
        # tập `run_impacted.sh --list` đọc lúc tính khoá của ĐÚNG lệnh này (cùng lượt): không sinh thêm một --list chỉ để phân lớp (review
        # 25/10); lệnh khác (thu hẹp) hay chưa có khoá thì classify tự hỏi. Lần kiểm lại trước khi ghi PASS (R3) vẫn hỏi mới.
        sel = sc.selections.get((t.get("id"), cmd)) if sc is not None else None
        info = hs.classify(cmd, str(project_dir), rec, device=bool(HARD_DEVICE_SUITE.search(cmd or "")), selection=sel)
        lease = heavy_lease[0] if (sequential and heavy_lease and info["cls"] in hs.HEAVY_CLASSES) else None
        if heavy_lease and lease is None:
            drop_lease()   # suite này không dùng slot nặng đang giữ (không nặng, hay chạy trong nhóm song song): không giữ chỗ của người khác
        # GATE_TOTAL_BUDGET_S (Stop hook: 900 s, hạn cứng 1800 s): lần chờ slot không được vượt ngân sách còn lại (review 20/10)
        left = budget_s - (time.monotonic() - budget_start) if budget_s > 0 else None
        wait0 = time.monotonic()
        slots = hs.acquire_for_suite(info, est_s=rec or estimated_suite_seconds(cmd), max_wait=left,
                                     label=f"{os.path.basename(str(project_dir))}:{t.get('id')} ({info['cls']})",
                                     started=bool(started_run), lease=lease)
        slot_waits[id(t)] = slot_waits.get(id(t), 0.0) + (time.monotonic() - wait0)
        if slots.admitted:
            started_run.append(1)
        for note in slots.notes:
            log_warn(f"{t.get('id')}: {note}")
        return slots

    def run_suite(t, cmd, mode, env, sequential=False):
        k = lookup_key(t) if (sc is not None and keyed_ok and mode == "full") else None
        if not k:
            return run_suite_slotted(t, cmd, mode, env, sequential)
        drop_lease()   # R1: chờ marker của gate khác không giữ slot nặng — chủ marker có thể đang xếp hàng đúng slot này (hai bên chờ nhau)
        with sc.inflight(k, inflight_rec.get(t.get("id"))) as state:
            if state == "recheck":
                rec = sc.hit(k, t)
                if rec:   # một gate khác vừa chạy đúng khoá này và PASS
                    mark_keyed(t, rec)
                    return None
            run_suite_slotted(t, cmd, mode, env, sequential)
            record_keyed(t, final=False)   # ngay, vẫn giữ marker: lượt đang chờ cùng khoá tra lại là thấy kết quả này (trừ PASS của suite phụ thuộc diff: ghi ở lượt cuối)
            return None


    def record_keyed(t, final=True):
        """Ghi kết quả một lượt chạy THẬT lệnh đầy đủ vào sổ khoá — chỉ khi input không đổi trong lúc chạy (khoá đọc lại bằng nhau).
        final=False (ngay sau khi chính suite chạy xong, các suite khác có thể chưa chạy): PASS của suite phụ thuộc diff chưa được ghi."""
        ks = KEYS.get(id(t))
        st = t.get("status")
        void_due = sc is not None and id(t) in really_ran and st != "PASS" and id(t) not in voided

        def void_suite():
            voided.add(id(t))   # PASS cũ của suite này (mọi khoá) hết dùng lại, trừ FAIL thật đã ghi dưới khoá của nó (suite_cache.void_needed)
            try:
                sc.void(t.get("id"))
            except Exception as e:   # noqa: BLE001 - sổ cache chỉ là dữ liệu
                log_warn(f"suite_cache void {t.get('id')}: {e!r}")
        if (sc is None or not ks or id(t) in recorded or id(t) not in really_ran or st not in ("PASS", "FAIL", "TIMEOUT")
                or (st in ("PASS", "TIMEOUT") and t.get("mode") != "full")
                or (st == "FAIL" and t.get("mode") not in ("full", "impacted", "package", "module"))
                or t.get("infra_retry") or t.get("env_blocked") or t.get("infra")):
            if void_due and id(t) not in recorded:
                void_suite()   # không ghi được khoá nào: không có gì giữ FAIL này lại (đã ghi ở lần gọi trước thì FAIL đó đang giữ nó)
            return
        if st == "PASS" and suite_cache_mod().DIFF_DEPENDENT.search(t.get("full_command") or t.get("command") or "") \
                and (not final or any(x is not t and x.get("status") not in ("PASS", "NOT_RUN") for x in regression_tests)):
            # run_impacted.sh bỏ qua script của suite đã chạy trước nó (DEVKIT_GATE_DONE): PASS của nó chỉ đáng ghi khi các suite đó cũng PASS.
            # Ngay sau khi nó chạy xong (final=False) các suite khác có thể CHƯA chạy (gate gộp, DEVKIT_SLOT_PRIORITY=merge, đổi thứ tự): phán
            # quyết chỉ ở lượt ghi cuối, khi mọi suite đã có kết quả (tests/gates/test_gate_suite_cache_selection.sh ca S5m).
            return
        if st == "PASS" and suite_cache_mod().selection_keyable(t):
            # R3: tập chọn nằm trong khoá, đọc lúc tính khoá; cửa sổ `git log --since` của run_impacted.sh trượt theo giờ (cây không đổi) nên
            # suite có thể đã chạy tập khác tập trong khoá: PASS ghi dưới khoá tập lớn hơn là PASS giả. Đọc lại, khác thì không ghi.
            cmd0 = t.get("full_command") or t.get("command")
            parts = sc.key_parts.get((t.get("id"), cmd0))
            if parts is not None and json.loads(parts[0]).get("selection") != suite_cache_mod().selection_list(project_dir, cmd0):
                log_warn(tr(f"{t.get('id')}: tập test chọn đổi trong lúc chạy — PASS không ghi vào cache",
                            f"{t.get('id')}: the selected test set changed while it ran — PASS not recorded in the cache"))
                return
        recorded.add(id(t))
        meta = {"duration": t.get("duration"), "log": t.get("log"), "project": os.path.basename(str(project_dir))[:64],
                "head": _head_sha(project_dir), "inputs_n": sc.inputs.get(t.get("id"))}
        rt = dict(t, command=t.get("full_command") or t.get("command"))   # bản ghi mang lệnh của ma trận (khoá tính từ lệnh đó)
        keys_now = list(ks)
        tree_same = True
        if st == "TIMEOUT":
            # #363: TIMEOUT của lệnh đầy đủ, thật, trên cây không đổi trong lúc chạy là bằng chứng base cho KNOWN-RED — CHỈ dưới khoá cả
            # cây (không có khoá chính xác: quá giờ không chứng minh gì về input của suite, và không bao giờ HIT)
            mod = suite_cache_mod()
            cmf = mod.content_map(project_dir) if mod is not None else None
            keys_now = [ks[1]] if (cmf is not None and mod.tree_digest(cmf) == sc.tree_digest and not t.get("flaky")) else []
        if st == "FAIL":
            # FAIL dưới khoá cả cây là bằng chứng lỗi có sẵn cho KNOWN-RED: chỉ khi FAIL là của lệnh đầy đủ, thật (không phải VACUOUS — lệnh
            # PASS mà không phát hiện thay đổi —, không chập chờn — chạy lại PASS, OCR 21/10), trên cây không đổi trong lúc chạy (audit #4
            # 21/10); còn lại chỉ khoá chính xác (hẹp lại),
            # bao đóng bị cắt (khoá chính xác LÀ khoá cả cây) thì không ghi — void ở dưới chặn PASS cũ
            mod = suite_cache_mod()
            cmf = mod.content_map(project_dir) if mod is not None else None
            tree_same = cmf is not None and mod.tree_digest(cmf) == sc.tree_digest
            if t.get("mode") != "full" or t.get("label") == "VACUOUS" or t.get("flaky") or not tree_same:
                keys_now = [ks[0]] if ks[0] != ks[1] else []
        if void_due and suite_cache_mod().void_needed(st, flaky=bool(t.get("flaky")), vacuous=t.get("label") == "VACUOUS",
                                                      tree_unchanged=tree_same, recorded=bool(keys_now)):
            void_suite()   # #344: FAIL thật ghi dưới khoá của nó thì thôi; TIMEOUT, hạ tầng, chập chờn, cây đổi: PASS cũ của id hết dùng lại
        cm = None
        if st == "PASS":   # một content_map cho cả hai phép kiểm (cây không đổi, input của suite không đổi)
            mod = suite_cache_mod()
            cm = mod.content_map(project_dir) if mod is not None else None
        if st == "PASS" and not (cm is not None and suite_cache_mod().tree_digest(cm) == sc.tree_digest):
            # cây đổi trong lúc chạy: PASS chỉ theo khoá chính xác (input riêng của suite được kiểm lại trong record_run)
            keys_now = [ks[0]] if ks[0] != ks[1] else []
            if not tree_warned:
                tree_warned.append(1)
                log_warn(tr("Cây đổi trong lúc chạy suite — PASS của lượt này chỉ ghi theo khoá chính xác, bỏ khoá cả cây",
                            "The tree changed while the suites ran — this run's PASS results go under precise keys only, whole-tree keys skipped"))
        try:
            # at = giờ suite chạy xong: một void (không-PASS ở nơi khác) giữa lúc đó và lúc ghi chặn PASS này
            msg = (sc.record_run(keys_now, rt, st, bool(t.get("flaky")), meta, at=SUITE_RAN_AT.get(t.get("id")), cmap=cm)
                   if keys_now else None)
            if msg:   # P3: cache từng nói PASS cho đúng khoá này mà chạy thật FAIL
                log_err(f"suite cache: {msg}")
        except Exception as e:   # noqa: BLE001 - sổ cache chỉ là dữ liệu: không bao giờ đổi kết luận của lượt này
            log_warn(f"suite_cache record {t.get('id')}: {e!r}")

    def run_suite_slotted(t, cmd, mode, env, sequential=False):
        slots = take_slots(t, cmd, sequential)
        if slots is not None and not slots.admitted:
            log_warn(tr(f"heavy-slot SLOT: {t.get('id')}: khoá độc quyền (Unity) bận hết thời gian chờ — không chạy suite",
                        f"heavy-slot SLOT: {t.get('id')}: its exclusive lock (Unity) stayed busy past the wait — suite not started"))
            t.update({"status": "UNTESTED", "label": "SLOT", "duration": "0s", "output_tail": tr(
                "khoá độc quyền (Unity) bận hết thời gian chờ — suite không chạy",
                "the exclusive lock (Unity) stayed busy past the wait — suite not started")})
            return
        if slots is not None and slots.held:   # giữ khoá Unity (hoặc cha giữ hộ): gate lồng trong suite không xin thêm khoá nào
            env = dict(env, SB_HEAVY_SLOT_HELD="1")
        elif slots is not None and slots.advisory:   # chỉ được chạy theo tải: gate lồng không chờ tải lại, vẫn xin khoá Unity
            env = dict(env, DEVKIT_SLOT_ADVISORY_HELD="1")
        try:
            really_ran.add(id(t))
            _run_suite(t, cmd, mode, env)
        finally:
            if slots is not None:
                kept = slot_mod[0].release_suite(slots, keep_heavy=sequential)
                if sequential:
                    heavy_lease[:] = [kept] if kept is not None else []

    def hang_report(t, out):
        """#370: a suite that timed out while the machine was NOT busy hung — it was not slow. Marks it (t["hang"], label HANG) and puts the
        last test line it printed plus the `ps` snapshot of its process group in output_tail; under load it stays a plain TIMEOUT, and so does
        a suite still making progress (#427: its youngest process that has a child is younger than min(timeout/2, 120) s)."""
        body, _, snap = (out or "").partition(HANG_SNAPSHOT_MARK)
        try:
            import capacity as _capacity  # noqa: PLC0415 - sibling module in bin/
            load, busy = _capacity.load(), _capacity.busy_load()
        except Exception as exc:   # noqa: BLE001 - capacity.py hỏng thì không biết tải: giữ TIMEOUT, nói rõ lý do
            log_warn(f"capacity: {exc!r}; {t.get('id')}: timeout stays TIMEOUT (load unknown)")
            return
        if load is None or load >= busy:
            return
        # #427 / hang giả 27/10: tải thấp chưa đủ. REG-DK-ALL-01 hết 900 s ở đuôi tuần tự (tải ~15 < 36) khi test đang chạy mới 6 s và
        # tiến trình lá mới sinh — vẫn bị gọi HANG. Chỉ gọi HANG khi tiến trình CÓ CON trẻ nhất của cây đã sống ≥ min(timeout/2, 120) s
        # (không cây con nào mới bắt đầu ngần ấy lâu; lá của vòng poll không tính, xem HANG_YOUNGEST_LINE). Ảnh của chính lượt này luôn nằm cuối out (rpartition: output của gate lồng không lẫn vào).
        # Không đọc được tuổi (ps hỏng, không dòng nào, thiếu dòng youngest): giữ cách cũ, chỉ xét tải.
        youngest = HANG_YOUNGEST_RE.search((out or "").rpartition(HANG_SNAPSHOT_MARK)[2])
        if youngest and int(youngest.group(1)) < min(args.timeout / 2, 120):
            return
        lines = [ln.strip() for ln in body.splitlines() if ln.strip()]
        last = next((ln for ln in reversed(lines) if HANG_TEST_LINE.search(ln)), lines[-1] if lines else "(no output)")
        t["hang"] = True
        shown = [ln for ln in snap.strip().splitlines() if not HANG_YOUNGEST_RE.match(ln)]   # dòng tuổi chỉ để quyết định, không chiếm chỗ
        t["output_tail"] = "\n".join(shown[:7] + [
            tr(f"HANG (tải {load:.1f} < {busy}): test cuối suite in ra: {last[:200]}",
               f"HANG (load {load:.1f} < {busy}): last test line the suite printed: {last[:200]}")])
        log_warn(tr(f"{t.get('id')}: quá giờ lúc máy rảnh (tải {load:.1f}) — TREO, không phải chậm; test cuối: {last[:120]}",
                    f"{t.get('id')}: timed out on an idle machine (load {load:.1f}) — a HANG, not slow; last test: {last[:120]}"))

    def _run_suite(t, cmd, mode, env):
        started = time.perf_counter()
        # Own session/process group (run_in_group) so a timeout or a signal to the gate kills the whole tree
        # (gradle daemons, test workers), not just the shell. Commands come from the matrix at the base
        # ref (load_active_matrix), so the audited change cannot rewrite them.
        ext = {}
        code, out, timed_out = run_in_group(cmd, str(project_dir), env, args.timeout, extend=ext)
        if ext.get("s"):
            t["extended_s"] = ext["s"]   # #616 A: seconds past --timeout the suite was left running because the machine was busy
        full_cmd = t.get("full_command") or ""
        if (not timed_out and code != 0 and mode in ("package", "module") and full_cmd
                and full_cmd.strip() != cmd.strip() and NARROW_NO_TESTS_RE.search(out or "")):
            # Bước narrow không chạy test nào: chạy lại lệnh FULL một lần và chấm theo nó (full đỏ thì vẫn FAIL).
            # ponytail: ran_cmds vẫn khoá theo lệnh narrow, một suite khác cùng lệnh full sẽ chạy lại (chậm hơn, không kém kiểm); gom khoá khi việc này hay xảy ra.
            reason = tr(f"bộ lọc narrow không khớp test nào ({cmd}) — chạy lại lệnh đầy đủ",
                        f"the narrow filter matched no test ({cmd}) — re-running the full command")
            print(f"    {CYAN}▶ {t['id']}: {tr('chế độ FULL', 'mode FULL')} — {reason}{RESET}")
            cmd, mode = full_cmd, "full"
            t.update({"command": cmd, "mode": mode, "mode_reason": reason})
            narrow_out = out or ""
            code, out, timed_out = run_in_group(cmd, str(project_dir), env, args.timeout)
            out = narrow_out + f"\n# --- narrow không khớp test nào, chạy lại lệnh đầy đủ — exit {code} ---\n" + (out or "")
        if not timed_out:
            t["status"] = "PASS" if code == 0 else "FAIL"
            # The command's own "cannot run here" code (unity-batch.sh: 2 = no Editor):
            # UNTESTED — not a failing test, and never a PASS.
            if code != 0 and isinstance(t.get("untested_exit"), int) \
                    and code == t["untested_exit"]:
                t["status"] = "UNTESTED"
            t["exit_code"] = code
            last_code = code    # exit code of the LAST run of this suite (the re-run's when there was one)
            first_is_kill = True    # with no re-run the only run is the last one
            if t["status"] == "FAIL":
                first = out or ""
                infra = infra_failure(first)
                retry = flaky_retry(cmd, project_dir, args.timeout, time.perf_counter() - started, infra=infra, env=env)
                if retry:
                    last_code = retry[0]
                    # a compile error followed by a re-run that is killed is still a code problem: the first run must be
                    # a kill itself, or a lost results store (infra), for the final kill to mean "no verdict"
                    first_is_kill = infra or killed_from_outside(code, first)
                    out = first + retry[1]
                    if retry[0] == 0 and (infra or not test_failure_reported(first)):
                        # the first run broke in the build (no test failed) or lost its results
                        # store; the re-run of the same code ran green: a real PASS, flagged —
                        # not a flaky test
                        t.update({"status": "PASS", "exit_code": 0, "infra_retry": True})
                    elif not infra:
                        t["flaky"] = retry[0] == 0  # a test failed, then passed on the same code: still FAIL
                if t["status"] == "FAIL" and infra:
                    t["infra"] = True   # still FAIL, never FLAKY: that run's output is not a test result
            if t["status"] == "FAIL" and (environment_blocked(code, out)
                                          or (first_is_kill and killed_from_outside(last_code, out))):
                t["env_blocked"] = True     # still FAIL: the verdict never turns into a PASS
            t["output_tail"] = (out or "")[-2000:]
            m = PTC_LINE.search(out or "")   # #472 D: run_impacted.sh "per_test_cache: reuse=N ran=M"
            if m:
                t["ptc"] = (int(m.group(1)), int(m.group(2)))
            # Which sub-test failed, from the WHOLE output: run_impacted's "✖ tests/x.sh" sits
            # mid-output, outside the last lines shown (2026-09-28, --brief showed five ✔).
            t["fail_lines"] = [l.rstrip()[:300] for l in (out or "").splitlines() if FAIL_LINE.search(l)][:8]
        else:
            t["status"] = "TIMEOUT"
            hang_report(t, out)
        t["duration"] = f"{time.perf_counter() - started:.2f}s"
        SUITE_RAN_AT[t.get("id")] = time.time()
        t["log"] = keep_evidence(project_dir, t, cmd, out)
        if t["status"] == "PASS" and mode == "impacted":
            t["label"] = f"PASS (impacted: {t['impacted_count']} tests)"
        elif t["status"] == "PASS" and mode in ("package", "module"):
            t["label"] = f"PASS ({mode})"
        else:
            t["label"] = "HANG" if t.get("hang") else t["status"]
        _v0 = time.monotonic()
        proved = vacuity_revert(project_dir, t, args.timeout, env=env)
        if proved != "skip":
            _add_step("vacuity", time.monotonic() - _v0)   # a re-run that happened: its seconds are outside the suite's duration
        if proved == "vacuous":
            t["status"] = "FAIL"
            t["label"] = "VACUOUS"
            t["output_tail"] = tr(
                "Test rỗng: revert mã nguồn sản xuất mà test vẫn XANH — không có năng lực phát hiện lỗi",
                "Vacuous test: production diff reverted and the test stayed GREEN — it cannot detect the bug")
        elif proved == "ok":
            t["vacuity"] = "red"
        elif proved == "weak":
            log_warn(tr(
                f"{t.get('id')}: revert không ra assertion failure (có thể chỉ lỗi biên dịch) — chưa chứng minh test bắt được lỗi",
                f"{t.get('id')}: revert did not show an assertion failure (possibly a compile error) — the test has not proved it catches the bug"))

    def start_job(t, cmd, mode, env):
        box = {}

        def work():
            try:
                with slots:
                    if budget_spent():   # it waited for a slot past the budget: not started, as in the sequential loop
                        mark_budget(t)
                        return
                    run_suite(t, cmd, mode, env)
            except BaseException as e:   # drain() re-raises it: a bug in a worker fails the gate, it is never hidden
                box["err"] = e
        # daemon: Ctrl-C ends the gate at once, as the sequential loop did; the suites' own process groups (start_new_session)
        # are killed by the signal handler in both cases (run_in_group registers them, A9 2026-10-09)
        th = threading.Thread(target=work, name=f"suite-{t['id']}", daemon=True)
        th.start()
        group.append((th, box))
        group_ts.add(id(t))

    def drain():
        """Wait for the running group, then give the suites that shared a command with a member its result."""
        errors = []
        for th, box in group:
            th.join()
            if "err" in box:
                errors.append(box["err"])
        group.clear()
        group_ts.clear()
        if errors:   # before sharing: a worker that died left its suite without a status
            raise errors[0]
        for t, c in late_notes:
            if may_note(t):
                note_ran(c)
        late_notes.clear()
        for t, prev in deferred:
            share_result(t, prev)
        deferred.clear()

    for t in regression_tests:
        if t.get("mode") == "cached" and t.get("status") == "PASS" and t.get("command") and not t.get("matrix_added") \
                and not precise_hit(t):
            note_ran(t["command"])
    for t in to_run:
        if group and not may_join(t):
            drain()
        if run_tests and t["command"] and not lock_held:
            t.update({"status": "UNTESTED", "label": "BUSY", "duration": "0s", "output_tail": (
                tr("Hàng đợi gate toàn máy đang đầy quá DEVKIT_GATE_SLOT_WAIT_S (pool gate) — chưa tới lượt chạy suite",
                   "The machine-wide gate queue stayed full past DEVKIT_GATE_SLOT_WAIT_S (pool gate) — suite did not start")
                if gate_slot_busy else
                tr("Một lượt chạy test khác giữ khoá dự án quá TEST_RUN_LOCK_WAIT_S — không chạy song song (Gradle ghi đè build/test-results)",
                   "Another test run held the project lock past TEST_RUN_LOCK_WAIT_S — not run side by side (Gradle corrupts build/test-results)"))})
            continue
        if run_tests and t["command"] and budget_spent():
            mark_budget(t)
            continue
        if (run_tests and t["command"] and t.get("covered_by") and t["covered_by"] != t.get("id")
                and (force_reason or not t.get("impacted_command"))):
            # "covered_by": the matrix says another suite already runs this suite's tests (GeelyEx2: REG-CAR-VOICE is a
            # --tests subset of REG-CAR-01's task, 30 of 30 runs repeated it, median 90 s). Skipped only when that suite ran its
            # FULL command earlier in this run and passed; any other state (it failed, is UNTESTED, ran impacted, comes later,
            # is unknown, is itself covered) runs this suite as before. The matrix that says so is the base-ref one. A suite
            # that would run IMPACTED here (an impacted_command and no --full) is not covered: that run is also where the
            # vacuity revert checks its tests.
            drain()   # the cover may still be running in the group
            cov = next((c for c in regression_tests if c.get("id") == t["covered_by"]), None)
            # lệnh đầy đủ của cover PASS trên ĐÚNG nội dung này: chạy thật, hoặc dùng lại theo biên nhận / khoá CẢ CÂY. Cover dùng lại theo
            # khoá CHÍNH XÁC (phần cached-full thêm) thì không: khoá đó không thấy input của suite được phủ (review 20/10, P0-1)
            if cov is not None and cov.get("status") == "PASS" and (
                    cov.get("mode") == "full" or (cov.get("mode") == "cached" and not cov.get("keyed_full"))):
                t.update({"status": "PASS", "label": "COVERED", "duration": "0s", "mode": "covered",
                          "exit_code": cov.get("exit_code"), "log": cov.get("log"),
                          "mode_reason": tr(f"{cov['id']} đã chạy lệnh đầy đủ và PASS trong lượt này",
                                            f"{cov['id']} ran its full command and passed in this run")})
                print(f"    {CYAN}▶ {t['id']}: {tr('ĐÃ ĐƯỢC PHỦ', 'COVERED')} — {t['mode_reason']}{RESET}")
                continue
        if run_tests and t["command"] and skip_separate_unity_compile(t["command"], unity_will_test):
            t["status"] = "PASS"
            t["label"] = "SKIP compile"
            t["duration"] = "0s"
            t["mode"] = "skip-compile"
            t["mode_reason"] = tr("EditMode/PlayMode biên dịch cùng script", "EditMode/PlayMode compiles the same scripts")
            print(f"    {CYAN}▶ {t['id']}: {tr('bỏ bước compile riêng', 'skipped separate compile')} — {t['mode_reason']}{RESET}")
            continue
        if run_tests and t["command"]:
            # Impacted selection (see select_impacted_tests): the full command unless the
            # base-ref matrix declares an impacted_command AND the map can vouch for every
            # changed file of the rule. The chosen mode and its reason are always printed.
            cmd, mode, reason, sel = plan_test_run(project_dir, t, force_reason, selection_cache)
            t["mode"] = mode
            t["full_command"] = t["command"]
            t["command"] = cmd
            if mode == "impacted":
                t["impacted_count"] = sel["count"]
                t["selected"] = [n for f in sorted(sel["tests"]) for n in sel["tests"][f]][:100]
                why = {}
                for f, w in sel["why"].items():
                    why[w] = why.get(w, 0) + 1
                t["mode_reason"] = ", ".join(f"{k}: {v}" for k, v in sorted(why.items()))
                print(f"    {CYAN}▶ {t['id']}: {tr('chế độ IMPACTED', 'mode IMPACTED')}{RESET} — "
                      + tr(f"{sel['count']} test chọn theo ({t['mode_reason']}); lệnh đầy đủ vẫn bắt buộc trước bàn giao (--full)",
                           f"{sel['count']} tests selected by ({t['mode_reason']}); the full run is still required before handover (--full)"))
            elif mode == "resource":
                t["status"] = "PASS"
                t["label"] = "RESOURCE"
                t["duration"] = "0s"
                t["mode_reason"] = reason
                print(f"    {CYAN}▶ {t['id']}: {tr('chế độ RESOURCE', 'mode RESOURCE')} — {reason}{RESET}")
                continue
            elif mode in ("package", "module"):
                t["mode_reason"] = reason
                print(f"    {CYAN}▶ {t['id']}: {tr('chế độ PACKAGE', 'mode PACKAGE')} — {reason}{RESET}")
            else:
                t["mode_reason"] = reason
                if t.get("impacted_command") or force_reason:
                    print(f"    {DIM}▶ {t['id']}: {tr('chế độ FULL', 'mode FULL')} — {reason}{RESET}")
            key = " ".join(cmd.split())
            prev = ran_cmds.get(key)
            if prev is not None:
                if id(prev) in group_ts:   # still running in the group: it takes the result when the group is drained
                    deferred.append((t, prev))
                else:
                    share_result(t, prev)
                continue
            if may_join(t) and mode == "full":
                # joins the group; its own DEVKIT_GATE_DONE (the scripts of the suites before it), never os.environ
                env = suite_env()
                if done_scripts:
                    env["DEVKIT_GATE_DONE"] = "\n".join(done_scripts)
                drop_lease()
                start_job(t, cmd, mode, env)
                ran_cmds[key] = t
                if t.get("keyed_full") or t.get("stale_rerun"):   # kết quả chưa có: may_note quyết sau khi nhóm xong (drain)
                    late_notes.append((t, cmd))
                else:
                    note_ran(cmd)
                continue
            drain()
            if done_scripts:
                os.environ["DEVKIT_GATE_DONE"] = "\n".join(done_scripts)
            run_suite(t, cmd, mode, suite_env(), sequential=True)
            ran_cmds[key] = t
            if may_note(t):   # chỉ-thêm / PASS theo khoá chính xác / STALE, cached-full chưa PASS thật: không bảo runner bỏ script
                note_ran(cmd)
        elif run_tests:
            t["status"] = "FAIL"
            t["output_tail"] = tr("Matrix không khai báo command cho test này", "The matrix declares no command for this test")
    drain()
    drop_lease()
    restore_local_configs(_config_snaps)
    _lap("suites")
    # Lượt không cưỡng bức (Stop hook) không tra khoá, nhưng FAIL thật của nó phải vào sổ khoá: không thì --full sau đó dùng lại PASS cũ
    # theo khoá, trong khi --full trước P2 chạy lại suite đó và FAIL (F1; review 20/10). Khoá tính lúc này và chỉ cho suite FAIL: Stop không
    # tốn thêm gì khi mọi suite PASS; cây đã đổi trong lúc chạy thì FAIL rơi vào khoá khác, chỉ làm thừa một lần chạy lại (an toàn).
    if sc is None and run_tests and not force_reason and os.environ.get("DEVKIT_SUITE_CACHE", "1") != "0":
        bad = [t for t in regression_tests if t.get("status") != "PASS" and id(t) in really_ran and t.get("command")
               and not t.get("matrix_added")]
        failed = [t for t in bad if t.get("status") == "FAIL"]
        if bad:
            try:
                sc = suite_cache_for(project_dir, rules, find_matrix_path(args.matrix), covers)
            except Exception as e:   # noqa: BLE001 - không dựng được: FAIL chỉ không vào sổ khoá, kết luận lượt này không đổi
                log_warn(f"suite_cache: {e!r}")
                sc = None
            for t in failed if sc is not None else ():
                full_t = dict(t, command=t.get("full_command") or t.get("command"))   # lệnh của ma trận, không phải lệnh thu hẹp
                src = next((m for m in MATRIX_TESTS.get(t.get("id"), ()) if m.get("command") == full_t["command"]), full_t)
                if suite_keyable(src):
                    try:
                        KEYS[id(t)] = sc.keys(full_t)
                    except Exception as e:   # noqa: BLE001 - khoá không tính được: FAIL này không vào sổ
                        log_warn(f"suite_cache key {t.get('id')}: {e!r}")
    # Kiểm lại cả khi không có khoá dự án (read-only): sổ khoá có flock riêng, một FAIL lượt khác vừa ghi phải lật PASS dùng lại
    # của lượt này thành UNTESTED trước kết luận. Chỉ suite chạy thật (cần khoá dự án) mới được ghi.
    if sc is not None and run_tests:
        try:
            recheck_keyed()
            for t in regression_tests:   # suite cùng lệnh với một suite chạy thật (share_result): ghi khoá của chính nó
                record_keyed(t)
            keyed_all = [t for t in regression_tests if KEYS.get(id(t))]
            # suite đã "được làm" trong lượt này: chạy thật, dùng chung lượt chạy (share_result), được suite chạy thật phủ (covered_by),
            # hay không cần chạy cho thay đổi này (resource / skip-compile) — như cách --full hôm nay tính
            done = lambda t: ((id(t) in really_ran and t.get("status") in ("PASS", "FAIL")
                               and not (t.get("infra") or t.get("infra_retry") or t.get("env_blocked")))
                              or t.get("mode") in ("covered", "resource", "skip-compile"))   # quá giờ không kiểm được gì (Antigravity 20/10)
            # mốc sentinel chỉ khi lượt này XÉT mọi suite cache được (cached-full mở rộng) và chạy thật hết, không dùng lại gì
            if force_reason and expanded[0] and not cache and not keyed_hits and keyed_all and all(done(t) for t in keyed_all):
                sc.stamp_sentinel()   # một lượt chạy THẬT mọi suite cache được (sentinel hay --no-cache): mốc mới cho sentinel
        except Exception as e:   # noqa: BLE001 - sổ cache chỉ là dữ liệu: không bao giờ đổi kết luận của lượt này
            log_warn(f"suite_cache record: {e!r}")
    # What this run RE-USED is judged here, under the lock and before anything is printed or decided from it. The file it read (BEFORE the lock) may
    # have been replaced or dropped while it waited, e.g. by a forced run that FAILED the suite (F1): its PASS is UNTESTED then, not a PASS. Without
    # the lock (BUSY: the wait ran out) there is no way to check it: UNTESTED the same.
    if not lock_held and not read_only:   # suites to run and no lock: they are BUSY, and so is every PASS that cannot be checked without it
        gone, why = reused_pass(), "BUSY"
    else:
        gone, why = stale_reused(), "STALE"
    if gone and stale_to_untested(why, gone):
        log_warn(tr("PASS dùng lại không kiểm tra lại được (file nguồn đã đổi/biến mất lúc chờ khoá, hoặc không có khoá) — thành UNTESTED",
                    "A re-used PASS could not be checked again (its source file changed or went away while the lock was awaited, or there was no lock) — it turns UNTESTED"))
    if read_only:
        log_warn(tr("Một lượt chạy khác giữ khoá: lượt này chỉ kiểm file kết quả dùng lại và không ghi gì (không biên nhận, không ghi nhận Stop, không PASS vào checklist)"
                    + (" — XONG cần biên nhận của lượt này: chạy lại --full khi khoá rảnh" if force_reason else ""),
                    "Another run holds the lock: this run only checked the file its re-used results came from and wrote nothing (no receipt, no Stop record, no checklist PASS)"
                    + (" — XONG needs a receipt from this turn: run --full again when the lock is free" if force_reason else "")))

    checklist_markdown = []
    for t in regression_tests:
        st = t["status"]
        label = t.get("label") or st
        if st == "PASS":
            status_icon = f"{GREEN}[x] {label}{RESET}"
        elif st == "NOT_RUN":
            status_icon = f"{YELLOW}[ ] NOT RUN{RESET}"
        else:
            status_icon = f"{RED}[ ] {st}{' (HANG)' if t.get('hang') else ''}{RESET}"
        print(f"    {status_icon} | {BOLD}{t['id']:<15}{RESET} : {t['name']}")
        extra = f", exit={t['exit_code']}" if "exit_code" in t else ""
        print(f"           {DIM}{tr('Lệnh chạy', 'Command')}: {t['command']} ({t['duration']}{extra}){RESET}")
        if st in ("FAIL", "TIMEOUT", "UNTESTED") and t.get("output_tail"):
            last = t["output_tail"].strip().splitlines()[-5:]
            for line in [l for l in t.get("fail_lines") or [] if l not in last] + last:
                print(f"           {DIM}| {line}{RESET}")
        mark = "x" if st == "PASS" else " "
        mode_note = ""
        if t.get("mode") == "impacted":
            mode_note = tr(f" — chỉ test bị ảnh hưởng: `{t['command']}`; lệnh đầy đủ `{t['full_command']}` chưa chạy",
                           f" — impacted tests only: `{t['command']}`; the full command `{t['full_command']}` was not run")
        elif t.get("mode") == "full" and t.get("impacted_command"):
            mode_note = tr(f" — chạy đủ: {t.get('mode_reason')}", f" — full run: {t.get('mode_reason')}")
        checklist_markdown.append(f"- [{mark}] **{t['id']}** ({t['component']}): {t['name']} -> `{label}` ({t['duration']}){mode_note}")
    if regression_tests and not run_tests:
        log_warn(tr("Chưa chạy test hồi quy (dry-run). Thêm --run-tests để chạy thật — dry-run KHÔNG bao giờ là PASS.",
                    "Regression tests not run (dry-run). Add --run-tests to run them — a dry-run is NEVER a PASS."))

    if immutable_guards_protected:
        print(f"\n  • {tr('Rào chắn Bất biến Lịch sử (Immutable Guards — cần rà thủ công, gate không tự kiểm):', 'Immutable guards (manual review — the gate does not check them):')}")
        for comp, g in immutable_guards_protected:
            print(f"    - {YELLOW}🔒 [GUARD PROTECTED — REVIEW]{RESET} {comp} :: {g}")
            checklist_markdown.append(f"- [ ] **{tr('Rào chắn bất biến', 'Immutable guard')}**: `🔒 {g}` ({comp}) — {tr('cần xác nhận thủ công', 'confirm manually')}")

    # Layer 5: Performance, Memory & Resource Optimization Audit Gate
    print(f"\n{BOLD}[5/8] {tr('(CHẶN) Anti-pattern hiệu năng (regex):', '(BLOCKING) Performance anti-patterns (regex):')}{RESET}")
    perf_ok, perf_findings = run_performance_audit(modified_files)
    if perf_ok:
        log_ok(tr(f"Anti-pattern hiệu năng theo {len(PERF_ANTIPATTERN_PATTERNS)} mẫu regex: 0 phát hiện",
                  f"Performance anti-patterns ({len(PERF_ANTIPATTERN_PATTERNS)} regex patterns): 0 findings"))
    else:
        for f, lbl in perf_findings:
            log_err(f"{f}: {lbl}")

    # Layer 6: Error Resilience & Anti-Swallowing Gate
    print(f"\n{BOLD}[6/8] {tr('(CHẶN) Nuốt lỗi (regex):', '(BLOCKING) Swallowed errors (regex):')}{RESET}")
    resilience_ok, resilience_findings = run_resilience_audit(modified_files)
    if resilience_ok:
        log_ok(tr(f"Chống nuốt lỗi theo {len(RESILIENCE_ANTIPATTERN_PATTERNS)} mẫu regex: 0 phát hiện",
                  f"Swallowed errors ({len(RESILIENCE_ANTIPATTERN_PATTERNS)} regex patterns): 0 findings"))
    else:
        for f, lbl in resilience_findings:
            log_err(f"{f}: {lbl}")

    # Layer 7: Structured Logging & PII Masking Gate
    print(f"\n{BOLD}[7/8] {tr('(CHẶN) Log thô (regex):', '(BLOCKING) Raw logging (regex):')}{RESET}")
    logging_ok, logging_findings = run_logging_audit(modified_files)
    if logging_ok:
        log_ok(tr(f"Log thô / PII theo {len(LOGGING_ANTIPATTERN_PATTERNS)} mẫu regex: 0 phát hiện",
                  f"Raw logging / PII ({len(LOGGING_ANTIPATTERN_PATTERNS)} regex patterns): 0 findings"))
    else:
        for f, lbl in logging_findings:
            log_err(f"{f}: {lbl}")

    hw_ok, hw_findings = run_hardware_source_audit(modified_files)
    if hw_ok:
        log_ok(tr("Hardware source: 0 lệnh exec/su/reboot/cổng 5555 mới",
                  "Hardware source: 0 new exec/su/reboot/port-5555 calls"))
    else:
        for f, lbl in hw_findings:
            log_err(f"{f}: {lbl}")
    assert_ok, assert_findings = run_assertion_audit(modified_files)
    assert_findings, assert_other = demote_other_session("vacuity", assert_findings, args.session, args.transcript)
    assert_ok = not assert_findings
    for f, lbl in assert_other:
        log_warn(tr(f"{f}: {lbl} — do phiên khác / người khác tạo (không chặn phiên này; cần sửa trước khi commit)",
                    f"{f}: {lbl} — made by another session or a person (not blocking this session; fix before commit)"))
    if assert_ok:
        log_ok(tr("Test đổi trong lượt này: 0 hàm test không có assertion phân biệt",
                  "Tests changed in this run: 0 test functions without a distinguishing assertion"))
    else:
        for f, lbl in assert_findings:
            log_err(f"{f}: {lbl}")
    proof_ok, proof_findings = run_proof_block(modified_files)
    proof_findings, proof_other = demote_other_session("proof", proof_findings, args.session, args.transcript)
    proof_ok = not proof_findings
    for _f, msg in proof_other:
        log_warn(tr(f"{msg} — ảnh của phiên khác (không chặn phiên này)", f"{msg} — another session's image (not blocking this session)"))
    if proof_ok:
        log_ok(tr("Thư mục proof: 0 ảnh trùng byte hoặc ≥ 98% cùng một màn",
                  "Proof folders: 0 byte-identical or ≥98% same-screen duplicates"))  # similar ones only warn
    else:
        for _f, msg in proof_findings:
            log_err(msg)
    for note in hardware_boundary_notes(modified_files):
        log_warn(note)
    advisories = run_lazy_senior_advisories(modified_files)
    for note in advisories:
        log_warn(note)

    # Findings already in the base version, from every static layer above: shown, never blocking.
    for f, lbl in PREEXISTING_SECRETS[:15]:
        log_warn(tr(f"{f}: {lbl} — đã có sẵn trong {BASE_REF}, không do thay đổi này (không chặn); nên sửa riêng (bí mật: xoay khoá, gỡ khỏi repo)",
                    f"{f}: {lbl} — already in {BASE_REF}, not introduced by this change (not blocking); fix it separately (a secret: rotate and remove it)"))

    # Layer 8: OpenCodeReview (Alibaba OCR) Audit Gate
    print(f"\n{BOLD}[8/8] {tr('(NHẮC) OpenCodeReview:', '(REMINDER) OpenCodeReview:')}{RESET}")
    ocr_available = shutil.which("ocr") is not None
    if ocr_available:
        log_warn(tr("OpenCodeReview CLI (`ocr`) có sẵn nhưng gate KHÔNG tự chạy — chạy review thủ công và đính kết quả",
                    "OpenCodeReview CLI (`ocr`) is installed but the gate does NOT run it — run the review yourself and attach the result"))
    else:
        log_warn(tr("OpenCodeReview CLI (`ocr`) chưa cài — lớp này bỏ qua", "OpenCodeReview CLI (`ocr`) not installed — skipped"))

    _lap("static")
    try:
        recheck_keyed()   # P2: lần nhìn cuối trước kết luận, cả cho PASS theo khoá
    except Exception as e:   # noqa: BLE001 - không đọc được sổ: PASS theo khoá không còn được tin
        for t in keyed_hits:
            if t.get("status") == "PASS":
                t.update({"status": "UNTESTED", "label": "STALE"})
        log_warn(f"suite_cache recheck: {e!r}")
    if stale_to_untested("STALE", stale_reused()):   # the last look before the verdict: a writer that holds no lock (the check above found the file as read)
        log_warn(tr("File kết quả dùng lại đã đổi/biến mất trước kết luận — PASS dùng lại thành UNTESTED",
                    "The file the re-used results came from changed or went away before the verdict — the re-used PASS turns UNTESTED"))
    # P2: suite cached-full thêm vào (keyed_full) FAIL là lỗi có sẵn (KNOWN-RED: nêu tên, ngoài kết luận; FAIL vẫn ở sổ khoá) CHỈ khi có bằng
    # chứng: sổ khoá có FAIL thật — và chưa từng PASS — của chính suite đó dưới khoá cả cây của nội dung BASE_REF (một lượt chạy trên checkout
    # sạch ở base). Audit 21/10 (Antigravity + principal): suy "thay đổi không chạm input" từ bao đóng tĩnh không bao giờ đủ (đường dẫn dựng
    # lúc chạy, import động), nên FAIL do chính thay đổi từng bị xếp KNOWN-RED. Không có bằng chứng (base chưa ai chạy, base từng PASS,
    # --since nhiều base) ⇒ FAIL vào kết luận. GeelyEx2 20/10: 2 suite FAIL sẵn — một lượt --full trên main sạch ghi bằng chứng cho mọi
    # thay đổi sau. tests/gates/test_gate_suite_cache.sh ca 28, 30; test_gate_sentinel.sh ca 2b'.
    # #363: TIMEOUT cũng được, nhưng chỉ khi base có TIMEOUT thật (timeout_n ≥ 1) và chưa từng PASS ở đó; FAIL cần FAIL của base như cũ.
    # TIMEOUT áp cho MỌI suite có khoá (kể cả suite do luật chọn cũ chọn — chỗ chặn thật REG-DK-ALL-01 quá 900 s, exit 1), FAIL chỉ cho
    # keyed_full: FAIL của suite luật cũ luôn là kết luận.
    known_red = [t for t in regression_tests if not precise_hit(t) and (
        (t.get("keyed_full") and t.get("status") == "FAIL")
        or (t.get("status") == "TIMEOUT" and KEYS.get(id(t)) and t.get("mode") == "full"))]
    if sc is not None and known_red and not getattr(args, "since", None) and not _BASE_REF_FOR:
        mod = suite_cache_mod()
        base_map = mod.content_map_at(project_dir, BASE_REF) if mod is not None else None
        digest = mod.tree_digest(base_map) if base_map is not None else None
        if digest == sc.tree_digest:
            # base trùng cây hiện tại (thay đổi chỉ chạm file EXCLUDE, hay chỉ index): khoá cả cây của base LÀ khoá của lượt này — FAIL/TIMEOUT
            # vừa ghi sẽ tự làm bằng chứng của chính nó (audit #4 21/10) ⇒ không có bằng chứng
            digest = None
        for t in known_red:
            timed_out = t.get("status") == "TIMEOUT"
            bk = sc.tree_key_at(t.get("id"), t.get("full_command") or t.get("command") or "", digest)
            rec = sc.read(bk) if bk else None
            evid_n, pass_n = (rec or {}).get("timeout_n" if timed_out else "fail_n"), (rec or {}).get("pass_n", 0)
            what_vi, what_en = ("quá giờ", "timed out") if timed_out else ("FAIL", "FAILED")
            if isinstance(evid_n, int) and evid_n >= 1 and pass_n in (0, None):
                t.update({"status": "UNTESTED", "label": "KNOWN-RED", "known_red": True})
                log_warn(tr(f"{t.get('id')}: suite {what_vi}, và cũng {what_vi} trên nội dung {BASE_REF} (sổ khoá) — lỗi có sẵn (KNOWN-RED), "
                            "ngoài kết luận; sửa riêng",
                            f"{t.get('id')}: suite {what_en}, and it also {what_en} on the {BASE_REF} content (key store) — a "
                            "pre-existing problem (KNOWN-RED), not part of the verdict; fix it separately"))
            elif not timed_out:
                log_warn(tr(f"{t.get('id')}: suite cached-full FAIL, chưa có bằng chứng nó cũng FAIL trên {BASE_REF} — vào kết luận. Lỗi có sẵn thì "
                            f"ghi bằng chứng: tạo worktree detached ở {BASE_REF} (agent-kit worktree add ../<repo>-baseline), chạy post-fix-gate.py "
                            "--run-tests --full --diff HEAD~1 trong đó (sổ khoá ở git common dir nên bằng chứng dùng chung), rồi agent-kit worktree remove",
                            f"{t.get('id')}: cached-full suite FAILED, no evidence it also FAILS on {BASE_REF} — part of the verdict. If it is "
                            f"pre-existing, record the evidence: create a detached worktree at {BASE_REF} (agent-kit worktree add ../<repo>-baseline), run "
                            "post-fix-gate.py --run-tests --full --diff HEAD~1 in it (the key store lives in the git common dir, so the evidence "
                            "is shared), then agent-kit worktree remove"))
            # TIMEOUT không có bằng chứng: keyed_full → vòng lặp bên dưới (UNTESTED như cũ); suite luật cũ → vào kết luận
    # P2: suite cached-full thêm vào (keyed_full) mà QUÁ GIỜ: --full trước P2 không chạy nó, và quá giờ dưới tải không chứng minh lỗi của thay
    # đổi (REG-DK-ALL-01 quá 900 s ở merge gate dưới tải, 19/10) — UNTESTED ngoài kết luận, được nêu tên, chạy lại lượt sau; FAIL thật của nó
    # vẫn vào kết luận. Không ghi vào sổ khoá (record_keyed chỉ ghi PASS/FAIL). tests/gates/test_gate_suite_cache.sh ca 15.
    for t in regression_tests:
        if t.get("keyed_full") and t.get("status") == "TIMEOUT":
            t.update({"status": "UNTESTED", "label": "HANG" if t.get("hang") else "TIMEOUT"})
            log_warn(tr(f"{t.get('id')}: suite cached-full quá giờ — UNTESTED, không tính vào kết luận (luật chọn cũ không chạy nó); chạy lại lượt sau",
                        f"{t.get('id')}: cached-full suite timed out — UNTESTED, not part of the verdict (the old selection does not run it); it runs again next time"))
    # Final Summary Verdict
    static_ok = (hygiene_ok and anti_laziness_ok and deps_ok and perf_ok and resilience_ok
                 and logging_ok and hw_ok and assert_ok and proof_ok and settings_ok)
    tests_passed = sum(1 for t in regression_tests if t["status"] == "PASS")
    # A STALE suite of another component that cannot run on this machine stays STALE and is
    # named; it is not the verdict of this change (only a failure of it is). Chỉ UNTESTED do chính suite báo "không chạy được ở
    # máy này" (untested_exit) mới đứng ngoài kết luận; nhãn SLOT / BUSY / BUDGET / STALE vào tests_untested (exit 4). P1 20/10: slot
    # theo từng suite khiến một suite STALE có thể bị SLOT trong khi suite khác PASS (tests/gates/test_gate_slot_classes.sh ca 8).
    _not_here = ("SLOT", "BUSY", "BUDGET", "STALE")
    # suite cached-full (keyed_full) cùng luật: STALE (recheck thấy FAIL mới trên khoá của nó) phải vào kết luận (Antigravity 20/10)
    stale_skipped = [t for t in regression_tests if t["status"] == "UNTESTED"
                     and (t.get("stale_rerun") or t.get("keyed_full") or t.get("known_red")) and t.get("label") not in _not_here]
    tests_untested = [t for t in regression_tests if t["status"] == "UNTESTED" and t not in stale_skipped]
    if stale_skipped:
        log_warn(tr("Suite STALE không chạy được trên máy này (vẫn STALE, không tính vào kết luận): ",
                    "STALE suites that cannot run on this machine (still STALE, not part of the verdict): ")
                 + ", ".join(t["id"] or "?" for t in stale_skipped))
    tests_ok = tests_passed + len(tests_untested) + len(stale_skipped) == len(regression_tests)
    unverified = bool(regression_tests) and not run_tests
    # PASS mà không chạy gì (RESOURCE, SKIP compile, COVERED) không phải XANH; BUSY/BUDGET là kết luận exit 4 của chính chúng
    added_not_green = [i for i in matrix_added if not any(
        t.get("id") == i and ((t["status"] == "PASS" and t.get("mode") not in ("resource", "skip-compile", "covered"))
                              or t.get("label") in ("BUSY", "BUDGET", "EDITED")) for t in regression_tests)]
    if added_not_green and not matrix_problem:
        matrix_problem = tr(f"regression matrix chỉ thêm rule so với {base_ref} nhưng test mới chưa chạy XANH trong lượt này "
                            f"({', '.join(added_not_green[:5])}) — gate chỉ tin ma trận chỉ-thêm khi mọi test mới PASS; chạy lại với --run-tests",
                            f"the regression matrix only adds rules relative to {base_ref} but the new tests did not pass in this run "
                            f"({', '.join(added_not_green[:5])}) — an add-only matrix is trusted only when every new test passes; re-run with --run-tests")
        log_err(matrix_problem)
    impacted_run = [t for t in regression_tests if t.get("mode") == "impacted"]
    impacted_n = sum(t.get("impacted_count", 0) for t in impacted_run)
    test_mode = ("none" if not run_tests or not regression_tests
                 else "impacted" if impacted_run else "full")
    # Documentation and agent state cannot break a test, so they need none (code without a test still does).
    # Sổ trạng thái của gate chỉ vào modified_files khi --diff chỉ có nó (xem trên): không cần test. Không đưa vào needs_no_test: push_gate
    # dùng hàm đó để bỏ qua gate, mà chính gate mới là nơi quét secret cho sổ này.
    # Config board super-board (.claude/super-board/configs/*.json, 18/10): chỉ script super-board đọc, như .claude/settings.json; đổi luật
    # gộp ở đó không có test hồi quy nào của dự án bắt được. Rule nào theo dõi nó vẫn chạy test.
    docs_only = bool(modified_files) and all(
        needs_no_test(f) or f.replace("\\", "/") in GATE_STATE_FILES
        or re.fullmatch(r"\.claude/super-board/configs/[^/]+\.json", f.replace("\\", "/")) is not None
        for f in modified_files)
    no_coverage = (not rules or not impacted_tests) and not args.allow_no_tests and not docs_only
    # Every changed source file must be re-testable later; one no rule watches would
    # silently fall out of the regression checklist.
    uncovered = [] if args.allow_no_tests else uncovered_code_files(modified_files, rules)
    # A NEW test file no suite executes runs only by hand: --full (the handover run) refuses it; the
    # Stop hook's impacted run warns. Orphans already committed are checklist rows, never a block.
    orphans_new, orphans_maybe = new_orphan_tests(modified_files, matrix, base_ref)
    orphan_fix = tr("gọi nó trong lệnh của một suite ma trận (hoặc trong script lệnh đó chạy), hoặc thêm thư mục của nó vào watch_files của suite chạy nó",
                    "call it from a matrix suite's command (or a script that command runs), or add its folder to the watch_files of the suite that runs it")
    orphan_block = bool(orphans_new) and bool(force_reason) and not args.allow_orphan_tests
    if orphans_maybe:
        log_warn(tr(f"{len(orphans_maybe)} file test MỚI có thể không được suite nào chạy (dò runner, không chặn — dòng ⚠️ checklist): ",
                    f"{len(orphans_maybe)} NEW test files may be run by no suite (runner analysis, not blocking — a checklist ⚠️ row): ")
                 + ", ".join(orphans_maybe[:5]))
    if orphans_new and not orphan_block:
        why = tr(" (--allow-orphan-tests)", " (--allow-orphan-tests)") if args.allow_orphan_tests else tr(" (--full sẽ chặn)", " (--full will block)")
        log_warn(tr(f"{len(orphans_new)} file test MỚI không rule nào watch và không suite nào nhắc tên: ",
                    f"{len(orphans_new)} NEW test files no rule watches and no suite names: ")
                 + ", ".join(orphans_new[:5]) + f"{why} — {orphan_fix}")
    print(f"\n{BOLD}{CYAN}──────────────────────────────────────────────────────────────────────────────────────{RESET}")
    receipt_untested = None
    lock_busy = False   # exit 4 because the lock was not held: no suite ran, so the receipt is neither written nor deleted
    budget_cut = False  # exit 4 because the time budget stopped a suite from starting: same, do not write or delete
    slot_busy = False   # exit 4 because the exclusive lock (Unity) stayed busy: same, do not write or delete
    project_gone = not Path(project_dir).is_dir()   # W1 R5a: `worktree finish`/`remove` took it while the suites ran
    exit_reason = "pass"
    if project_gone:
        exit_reason = "project_gone"
        verdict_text, verdict_color, exit_code = tr(
            "CHƯA XÁC MINH — thư mục project đã bị gỡ trong lúc gate chạy (worktree finish/remove): không ghi kết quả nào vào đó",
            "UNVERIFIED — the project folder was removed while the gate ran (worktree finish/remove): no result is recorded there"), YELLOW, 1
    elif not static_ok or (run_tests and not tests_ok):
        exit_reason = "fail"
        verdict_text, verdict_color, exit_code = tr("REJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT", "REJECT — FIX THE FAILED CHECKS"), RED, 1
    elif matrix_problem:
        exit_reason = "matrix"
        verdict_text, verdict_color, exit_code = tr("CHƯA XÁC MINH — regression matrix không tin được (xem mục 4): người review rồi commit file ma trận — gate chỉ tin ma trận đã commit, hoặc giống từng byte bản `agent-kit matrix`",
                                                    "UNVERIFIED — regression matrix is not trusted (see section 4): have a human review and commit the matrix file — the gate trusts only a committed matrix, or one byte-identical to `agent-kit matrix`"), YELLOW, 2
    elif tests_touched:
        exit_reason = "edited_test"
        # Kept UNVERIFIED (an edited test can weaken the very assertion the run relies on);
        # the verdict names the one cure: a person reads that diff, or it gets committed.
        in_range = bool(set(tests_touched) & set(since_touched))
        touched_diff = f"git diff {args.since if in_range else base_ref} -- " + " ".join(tests_touched[:3]) + (" …" if len(tests_touched) > 3 else "")
        # A range-flagged test is already committed: committing again cures nothing.
        cure_vi, cure_en = (("hoặc một commit có dòng `Test-approved-by:` (audit Antigravity)", "or a commit carrying a `Test-approved-by:` line (an Antigravity audit)")
                            if in_range else ("hoặc commit nó", "or commit it"))
        verdict_text, verdict_color, exit_code = tr(f"CHƯA XÁC MINH — {len(tests_touched)} file test đã có bị sửa/xoá trong thay đổi: cần duyệt chéo diff test (`{touched_diff}`): agent sửa test KHÔNG tự duyệt (--auto-approve-tests / `AUTO-APPROVE:` bị từ chối); agent khác (audit `/giao` Antigravity hoặc phiên reviewer) đọc diff, xác nhận không nới assertion rồi ghi mục {{path, sha256, reviewer, author, task_id, reason}} vào `.claude/audit-gate/approved_tests.json` (khoá `approvals`) — {cure_vi} — rồi chạy lại gate; mục duyệt và trailer chỉ tính khi task_id có audit Antigravity pass mà verdict của antigravity-pm ghi `auditedHead: <sha>` của cây chứa đúng nội dung test hiện tại",
                                                    f"UNVERIFIED — {len(tests_touched)} existing test files were edited/deleted in the change: needs a cross-review of the test diff (`{touched_diff}`): the agent that edited a test does NOT approve it (--auto-approve-tests / `AUTO-APPROVE:` are refused); another agent (an Antigravity `/giao` audit or a reviewer session) reads the diff, confirms no assertion was weakened and records {{path, sha256, reviewer, author, task_id, reason}} in `.claude/audit-gate/approved_tests.json` (key `approvals`) — {cure_en} — then re-run the gate; an entry or trailer counts only when its task_id has an Antigravity audit pass whose antigravity-pm verdict records `auditedHead: <sha>` of a tree holding the test's current content"), YELLOW, 2
    elif unverified:
        exit_reason = "dry_run"
        verdict_text, verdict_color, exit_code = tr("CHƯA XÁC MINH — test hồi quy chưa chạy (dry-run)", "UNVERIFIED — regression tests not run (dry-run)"), YELLOW, 2
    elif unreadable:
        exit_reason = "unreadable"
        verdict_text, verdict_color, exit_code = tr(f"CHƯA XÁC MINH — {len(unreadable)} file không đọc được để quét", f"UNVERIFIED — {len(unreadable)} files could not be read for scanning"), YELLOW, 2
    elif orphan_block:
        exit_reason = "orphan"
        shown = ", ".join(orphans_new[:5]) + (" …" if len(orphans_new) > 5 else "")
        verdict_text, verdict_color, exit_code = tr(f"CHƯA XÁC MINH — {len(orphans_new)} file test MỚI mà không suite nào của ma trận chạy ({shown}: không rule nào watch, không suite nào nhắc tên): gate sẽ không bao giờ chạy lại nó — {orphan_fix} (cố ý: --allow-orphan-tests)",
                                                    f"UNVERIFIED — {len(orphans_new)} NEW test files that no matrix suite runs ({shown}: no rule watches them, no suite names them): the gate would never run them again — {orphan_fix} (on purpose: --allow-orphan-tests)"), YELLOW, 2
    elif uncovered and not no_coverage:
        exit_reason = "uncovered"
        verdict_text, verdict_color, exit_code = f"CHƯA XÁC MINH — {len(uncovered)} file code thay đổi chưa có test hồi quy (thêm vào regression_matrix.json, hoặc --allow-no-tests)", YELLOW, 2
    elif no_coverage:
        exit_reason = "no_match"
        verdict_text, verdict_color, exit_code = tr("CHƯA XÁC MINH — không có test hồi quy nào khớp thay đổi (--allow-no-tests để chấp nhận)", "UNVERIFIED — no regression test matches the change (--allow-no-tests to accept)"), YELLOW, 2
    elif run_tests and tests_untested and all(t.get("label") == "BUSY" for t in tests_untested):
        exit_reason = "busy"
        verdict_text, verdict_color, exit_code = (
            tr("UNTESTED — hàng đợi gate toàn máy đang đầy (pool gate, DEVKIT_GATE_SLOT_WAIT_S) — chạy lại sau; KHÔNG phải PASS",
               "UNTESTED — the machine-wide gate queue is full (pool gate, DEVKIT_GATE_SLOT_WAIT_S) — run again later; NOT a PASS")
            if gate_slot_busy else
            tr("UNTESTED — một lượt chạy test khác đang giữ khoá dự án (TEST_RUN_LOCK_WAIT_S) — chạy lại sau; KHÔNG phải PASS",
               "UNTESTED — another test run holds the project lock (TEST_RUN_LOCK_WAIT_S) — run again later; NOT a PASS")), YELLOW, 4
        lock_busy = True
    elif run_tests and any(t.get("label") == "SLOT" for t in tests_untested):
        exit_reason = "slot"
        verdict_text, verdict_color, exit_code = tr(
            "UNTESTED — khoá độc quyền (Unity) bận hết thời gian chờ — chạy lại sau; KHÔNG phải PASS",
            "UNTESTED — the exclusive lock (Unity) stayed busy past the wait — run again later; NOT a PASS"), YELLOW, 4
        slot_busy = True
    elif run_tests and any(t.get("label") == "BUDGET" for t in tests_untested):
        exit_reason = "budget"
        left = ", ".join(t["id"] or "?" for t in tests_untested if t.get("label") == "BUDGET")
        verdict_text, verdict_color, exit_code = tr(
            f"UNTESTED — hết ngân sách thời gian ({budget_s:.0f}s, GATE_TOTAL_BUDGET_S): {left} chưa chạy — chạy `postfix-gate --run-tests --full`; KHÔNG phải PASS",
            f"UNTESTED — time budget spent ({budget_s:.0f}s, GATE_TOTAL_BUDGET_S): {left} not run — run `postfix-gate --run-tests --full`; NOT a PASS"), YELLOW, 4
        budget_cut = True
    elif run_tests and tests_untested:
        # UNTESTED by untested_exit (BUSY marks suites only when the lock was not held — the
        # summary "busy"): a full run records it in the receipt so its PASS suites are reused.
        receipt_untested = sorted({t["id"] or "?" for t in regression_tests if t["status"] == "UNTESTED"}) if lock_held else None
        names = ", ".join(t["id"] or "?" for t in tests_untested)
        stale_names = ", ".join(t["id"] or "?" for t in tests_untested if t.get("label") == "STALE")
        verdict_text, verdict_color, exit_code = (
            tr(f"UNTESTED — PASS dùng lại của {stale_names} không còn đứng vững (file đã xác nhận nó đã đổi/biến mất trong lúc gate chạy): chạy lại gate; KHÔNG phải PASS",
               f"UNTESTED — the re-used PASS of {stale_names} no longer stands (the file that vouched for it changed or went away while the gate ran): run the gate again; NOT a PASS")
            if stale_names else
            tr(f"UNTESTED — {names} không chạy được trên máy này (thiếu công cụ/thiết bị); KHÔNG phải PASS",
               f"UNTESTED — {names} cannot run on this machine (missing tool/device); NOT a PASS")), YELLOW, 4
        exit_reason = "stale" if stale_names else "missing_tool"
    elif impacted_run:
        exit_reason = "impacted"
        # Exit 0 like any PASS (the Stop hook lets the turn end), but never worded as the
        # handover verdict: tests outside the selection did not run.
        verdict_text, verdict_color, exit_code = tr(
            f"PASS (impacted: {impacted_n} tests) — kiểm nhanh các test bị ảnh hưởng; chạy `postfix-gate --run-tests --full` trước khi bàn giao",
            f"PASS (impacted: {impacted_n} tests) — fast check of the impacted tests; run `postfix-gate --run-tests --full` before handover"), GREEN, 0
    else:
        verdict_text, verdict_color, exit_code = tr("PASS — ĐỦ ĐIỀU KIỆN NGHIỆM THU & BÀN GIAO", "PASS — READY FOR ACCEPTANCE & HANDOVER"), GREEN, 0

    if deferred_by and exit_code == 0:
        exit_reason = "deferred"
        # --full was deferred for sibling sessions: a partial PASS, never the handover verdict.
        verdict_text = tr(
            f"PASS (hoãn --full: phiên {', '.join(deferred_by)} còn hoạt động) — CHƯA ĐỦ ĐIỀU KIỆN NGHIỆM THU: không ghi receipt; chạy lại ở phiên cuối hoặc thêm --force-full",
            f"PASS (--full deferred: session {', '.join(deferred_by)} still active) — NOT READY FOR ACCEPTANCE: no receipt written; re-run in the last session or add --force-full")
        if asked_full:
            # Exit 5 = "not accepted": the checks that ran passed, the acceptance that was asked for did not happen.
            # The Stop hook never passes --full, so a turn still ends on its impacted run (exit 0).
            exit_code, verdict_color = 5, YELLOW
            verdict_text = tr(
                f"CHƯA NGHIỆM THU (exit 5) — --full bị hoãn: phiên {', '.join(deferred_by)} còn hoạt động; CHƯA ĐỦ ĐIỀU KIỆN NGHIỆM THU, không ghi receipt: chạy lại ở phiên cuối hoặc thêm --force-full",
                f"NOT ACCEPTED (exit 5) — --full deferred: session {', '.join(deferred_by)} still active; NOT READY FOR ACCEPTANCE, no receipt written: re-run in the last session or add --force-full")
    if read_only and exit_code == 0 and force_reason and not impacted_run and not deferred_by:
        exit_reason = "read_only"
        # a forced run that only read what it re-used wrote no receipt: the checks passed, the acceptance asked for did not happen (as --full deferred,
        # but exit 0 as before: K6 pins it; the Stop hook never passes --full). XONG needs a receipt of this turn.
        verdict_text, verdict_color = tr(
            "PASS (chỉ đọc: một lượt chạy khác giữ khoá) — CHƯA ĐỦ ĐIỀU KIỆN NGHIỆM THU: không ghi receipt; chạy lại --full khi khoá rảnh",
            "PASS (read-only: another run holds the lock) — NOT READY FOR ACCEPTANCE: no receipt written; run --full again when the lock is free"), YELLOW
    print(f"  {BOLD}{tr('KẾT LUẬN CỔNG POST-FIX AUDIT:', 'POST-FIX AUDIT GATE VERDICT:')}{RESET} {verdict_color}{BOLD}{verdict_text}{RESET}")
    print(f"  • {tr('Test hồi quy đạt', 'Regression tests passed')}: {tests_passed}/{len(regression_tests)}" + (tr(" (chưa chạy)", " (not run)") if unverified else "")
          + (tr(f" — {len(impacted_run)} lệnh chỉ chạy test bị ảnh hưởng ({impacted_n} test), lệnh đầy đủ CHƯA chạy",
                f" — {len(impacted_run)} commands ran impacted tests only ({impacted_n} tests), the full commands were NOT run") if impacted_run else ""))
    print(f"  • {tr('Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log)', 'Static checks (secrets, laziness, dependencies, performance, swallowed errors, logging)')}: "
          f"{tr('đạt', 'passed') if static_ok else tr('CÓ PHÁT HIỆN', 'FINDINGS')}")
    for f in unreadable[:5]:
        print(f"  • {YELLOW}{tr('Không đọc được để quét:', 'Could not read for scanning:')}{RESET} {f}")
    for f in nested_repos[:5]:
        print(f"  • {DIM}{tr('Repo git lồng (submodule / repo con), không phải file — nội dung bên trong không quét ở đây:', 'Nested git repository (submodule / inner repo), not a file — its content is not scanned here:')}{RESET} {f}")
    for f in tests_touched[:5]:
        what = (tr("Script lệnh suite của ma trận chạy bị sửa/xoá:", "Suite runner script (run by a matrix command) edited/deleted:")
                if f in runners_touched else tr("Test đã có bị sửa/xoá:", "Existing test edited/deleted:"))
        print(f"  • {YELLOW}{what}{RESET} {f}")
    for f in tests_approved[:5]:
        if APPROVED_BY.get(f) == "user":
            print(f"  • {GREEN}{tr('Test đã có bị sửa — người dùng đã duyệt (AskUserQuestion), file không đổi sau đó:', 'Existing test edited — approved by the user (AskUserQuestion), unchanged since:')}{RESET} {f}")
        else:
            rv, tid = CROSS_REVIEW.get(f, ("?", "?"))
            print(f"  • {GREEN}{tr(f'Test đã có bị sửa — duyệt chéo bởi {rv} (task {tid}), sha256 khớp nội dung hiện tại:', f'Existing test edited — cross-reviewed by {rv} (task {tid}), sha256 matches the current content:')}{RESET} {f}")
    for f, sha, why in APPROVAL_REJECTS:
        if f in tests_touched:
            print(f"  • {YELLOW}{tr(f'Duyệt test bị từ chối — {why}: cần duyệt lại (duyệt chéo, mục path, sha256, reviewer, author, task_id, reason):', f'Test approval refused — {why}: needs re-approval (a cross-review entry):')}{RESET} {f} sha256={sha or '?'}")
    if SELF_APPROVAL_REFUSED:   # cờ có test sửa để duyệt: luôn nói cờ không còn tác dụng, kể cả khi lời duyệt khác đã nhận
        print(f"  • {YELLOW}{tr('tự duyệt bị từ chối (--auto-approve-tests / DEVKIT_AUTO_APPROVE_TESTS): test có sẵn bị sửa cần agent khác duyệt chéo (audit /giao ghi mục duyệt)', 'self-approval refused (--auto-approve-tests / DEVKIT_AUTO_APPROVE_TESTS): an edited existing test needs a cross-review by another agent (a /giao audit records the entry)')}{RESET}")
    for f in tests_touched_other[:5]:
        print(f"  • {YELLOW}{tr('Test đã có bị phiên khác / người khác sửa (không chặn phiên này, cần người review trước khi commit):', 'Existing test edited by another session or a person (not blocking this session; needs a human review before commit):')}{RESET} {f}")
    print(f"  • {tr('Gate không xác minh: DESIGN.md/a11y, RED/GREEN, Immutable Guards, OpenCodeReview. Ảnh nghiệm thu không nằm trong exit code; agent vẫn phải gắn PNG của lượt này trước khi nói XONG, trừ khi thay đổi chắc chắn không lên màn hình (essentials bước 4).', 'The gate does not verify: DESIGN.md/a11y, RED/GREEN, immutable guards, OpenCodeReview. The proof image is outside the exit code; the agent still attaches a PNG from this turn before saying XONG unless the change surely cannot show on a screen (essentials step 4).')}")
    print(f"{BOLD}{CYAN}══════════════════════════════════════════════════════════════════════════════════════{RESET}\n")

    _lap("verdict")
    partial = not force_reason or any(t.get("mode") in PARTIAL_MODES for t in regression_tests)
    # #154 (21/10): the merge gate of `worktree finish` (scripts/git/worktree.py _merge_gate sets DEVKIT_GATE_MERGE_CHECK=1) checks for
    # regressions only; its exit 2 (an edited test awaiting the session's approval, a suite that could not run) is the session's own
    # business and never refuses the merge — and used to turn the session's exit-0 receipt of the SAME content down to exit 2, so the push
    # from main was refused until the gate ran again. That exit 2 leaves an exit-0 receipt of the SAME content alone (keep_same); a
    # receipt of other content is still dropped (principal review 21/10: content gated, then changed, must not ride along), and its exit 1
    # (a FAIL) still drops it, as before.
    merge_check = os.environ.get("DEVKIT_GATE_MERGE_CHECK") == "1"
    pm_relax = run_tests and exit_code == 0 and pm_relaxed()
    if pm_relax:
        print(f"  • {YELLOW}{tr('Lời duyệt test dựa vào biên bản antigravity-pm ở ANTIGRAVITY_PM_STATE_HOME lạ (không phải ~/.antigravity-pm): kết luận giữ nguyên nhưng KHÔNG ghi biên nhận task / merge gate, full_pass.json không là exit 0', 'Test approval rests on an antigravity-pm record under a foreign ANTIGRAVITY_PM_STATE_HOME (not ~/.antigravity-pm): verdict kept, but NO task / merge-gate receipt, full_pass.json is not exit 0')}{RESET}")
    try:
        if run_tests and not impacted_run and not deferred_by and not lock_busy and not budget_cut and not slot_busy and not edited_early and (not partial or (exit_code != 0 and not receipt_untested)) \
                and (lock_held or partial or exit_code != 0):
            # only a full run writes the receipt; a partial PASS — or a partial UNTESTED, whose runnable
            # suites all passed (2026-09-29) — leaves the last full one as it is; a BUSY run (lock not held, nothing ran)
            # and a BUDGET run (a suite never started) leave it alone too: either used to delete even a valid one,
            # so a Stop whose lock wait or time budget ran out forced a new --full.
            # A READ-ONLY run (no lock, every suite re-used) writes nothing new, forced or not: with exit 0 it leaves the receipt it re-used alone;
            # with another exit code it is handed to the writer as PARTIAL and unlocked, which only ever DROPS an exit-0 receipt (never replaces
            # it: a lock-less replace that carries a re-used PASS could put back a PASS a FAIL took away), so a verdict that contradicts the
            # receipt never leaves it standing for XONG and push, whether the run was a Stop or --full.
            # PASS theo khoá CHÍNH XÁC (cached-full) vào biên nhận như UNTESTED: biên nhận nói về nội dung cả cây, và reuse_from chạy
            # lại mọi suite UNTESTED của biên nhận (review 20/10, P0-A; tests/gates/test_gate_suite_cache.sh ca 16)
            receipt_tests = [dict(t, status="UNTESTED", label="KEYED") if precise_hit(t) else t for t in regression_tests]
            # Refresh-only only when a PASS was COPIED from a receipt (own, sibling, store, budget record: reuse_src): a content-key hit (suite
            # cache) re-uses nothing from a receipt, and a FAIL on a key is permanent there, so it cannot put a PASS back (review 22/10, P2).
            # ponytail: a --full that re-used some suites of its own exit-2 receipt (the Stop hook dropped the tree entry) and ran the rest leaves no
            # tree entry for a removed worktree: safe, only slower; upgrade when a PASS carries its lineage (real-run time) so a copy of a real
            # run can be told from a copy of a copy.
            reuse_at = reused_tested_at()
            # pm home lạ (pm_relaxed): exit 0 vào biên nhận như exit 2 — suite vẫn dùng lại được, proof/push gate không nhận
            write_full_pass_receipt(project_dir, 2 if exit_code == 0 and pm_relax else exit_code, args.matrix, receipt_tests,
                                    tested_at=reuse_at, refresh_only=reuse_src[0] is not None,
                                    # a run WITHOUT the lock (read-only, or the project lock / gate queue timed out: audit T0056, an exit-2
                                    # branch ahead of BUSY wrote full_pass.json) is handed over as partial + unlocked: it may DROP an exit-0
                                    # receipt its verdict contradicts, it never writes one
                                    tested_fp=tested_fp, untested=receipt_untested, partial=partial or not lock_held,
                                    locked=lock_fh is not None,   # the handle itself: (None, True) is also "nothing to re-use or run, no lock asked for"
                                    keep_same=merge_check)
        if exit_code == 0 and run_tests and not partial and not impacted_run and not deferred_by and not lock_busy and not budget_cut and not slot_busy:
            mark_merge_gate_receipt(project_dir, diff_ref, run_start_tree, relaxing=[
                flag for flag, on in (("--allow-no-tests", args.allow_no_tests), ("--allow-orphan-tests", args.allow_orphan_tests),
                                      ("--auto-approve-tests", args.auto_approve_tests or os.environ.get("DEVKIT_AUTO_APPROVE_TESTS") == "1"),
                                      ("ANTIGRAVITY_PM_STATE_HOME", pm_relax)) if on])
        # T0061 Pha 1: biên nhận task (task_fp chỉ có ở lượt không cưỡng bức, ngoài nhánh đích, không --since, không merge check). Ghi khi
        # exit 0 có khoá, không read-only, không suite UNTESTED (BUSY / BUDGET / SLOT / KEYED…), và lượt đã kiểm trọn merge-base(<nhánh đích>,
        # HEAD) → cây: base của diff là merge-base đó hoặc tổ tiên của nó. Exit 1 (mọi chế độ) bỏ biên nhận task của cây đó; BUSY / BUDGET /
        # SLOT / exit 2 của merge check không đụng tới nó.
        if (task_fp and exit_code == 0 and run_tests and lock_held and not read_only and not pm_relax and not lock_busy and not budget_cut and not slot_busy
                and not project_gone and not any(t.get("status") == "UNTESTED" for t in regression_tests)
                and subprocess.run(["git", "-C", str(project_dir), "merge-base", "--is-ancestor", base_ref, task_mb],
                                   capture_output=True).returncode == 0):
            if write_task_receipt(project_dir, task_fp, task_mb, args.session or os.environ.get("DEVKIT_SESSION_ID")
                                  or os.environ.get("CLAUDE_CODE_SESSION_ID") or os.environ.get("CLAUDE_SESSION_ID")):
                print(f"  • {GREEN}{tr('Biên nhận task đã ghi (XONG của task trong lượt này; push nhánh đích vẫn cần --full)', 'Task receipt written (XONG for this task in this turn; a push to the trunk still needs --full)')}{RESET}")
        elif exit_code == 1 and run_tests and not project_gone:
            drop_task_receipt(project_dir, task_fp or tested_fp or budget_fp or tree_fp_of(project_dir))
        # The budget record (BUDGET_RECORD) is a file of its own, so the receipt above stays byte for byte whatever happens here:
        # a suite that FAILED or TIMED OUT drops it (never a FAIL item), a budget cut writes what finished (never on another tree).
        if run_tests and any(t.get("status") in ("FAIL", "TIMEOUT") for t in regression_tests):
            drop_budget_record(project_dir)
            # #247 (review P2): an impacted or deferred run that FAILS never reaches write_full_pass_receipt, so the tree store entry of the
            # tree it tested would stay lendable: a FAIL on a tree takes its store entry, whatever the run mode
            try:
                import tree_fp  # noqa: PLC0415 - sibling module in bin/
                _tree_store(tree_fp, project_dir, budget_fp)   # budget_fp = tested_fp or the fingerprint taken for the budget record
            except ImportError:
                pass
        elif run_tests and budget_fp and budget_head and not force_reason and not lock_busy and exit_code != 0 and ran_cmds:
            # a PASS is the hook's pass_fp; a run that started no suite has nothing of its own to record (and rewriting what it only read is how a
            # PASS that a concurrent run had just replaced came back). The suites it re-used stand on the file that vouched for them: when that
            # file changed or is gone (a forced run's FAIL drops it) they are UNTESTED by now (stale_to_untested, under the lock, right before the
            # verdict): they go in as untested and run again next time.
            write_budget_record(project_dir, args.matrix, regression_tests, budget_fp,
                                tested_at=float(cache.get("tested_at") or 0) if cache else None, head=budget_head)
    finally:
        # T0056: nhả slot hàng đợi gate toàn máy và khôi phục DEVKIT_GATE_SLOT_HELD trong khối finally sẵn có.
        if gate_slot_hs is not None:
            gate_slot_hs.release_pool(gate_slot)
            gate_slot = None
        if prev_gate_slot_held is None:
            os.environ.pop("DEVKIT_GATE_SLOT_HELD", None)
        else:
            os.environ["DEVKIT_GATE_SLOT_HELD"] = prev_gate_slot_held
        # Only now may another run take the test-run lock: it finds the receipt (or its settled absence), and the
        # checklist update below does not run under it. A BUSY run holds no lock (lock_fh is None); a kill before
        # this line frees the lock with the process.
        if lock_fh:
            _write_test_run_lock_holder(lock_fh, clear=True)   # B5: a later waiter must not take a finished run for a live holder
            lock_fh.close()
    _lap("receipt")

    # a run without the lock (read-only, or BUSY) holds no lock: a re-used PASS is not written into the checklist (it would overwrite
    # the FAIL of a run that finished meanwhile)
    checklist_tests = ([dict(t, status="UNTESTED") if t.get("mode") == "cached" else t for t in regression_tests]
                       if (read_only or not lock_held) else regression_tests)
    checklist_tests = [t for t in checklist_tests if id(t) not in KEYED_IDS]   # P2: PASS theo khoá không đóng dấu lại commit
    cl_matrix, cl_rules = matrix, rules
    if matrix_added and exit_code != 0:
        # ma trận chỉ-thêm chưa đứng vững trong lượt này: sổ checklist theo ma trận base, không đồng bộ rule chưa được tin
        cl_matrix = follow_matrix_renames(base_matrix, base_problem, args.matrix, base_ref)[0]
        cl_rules = cl_matrix.get("rules", [])
        checklist_tests = [t for t in checklist_tests if not t.get("matrix_added")]
    if not args.no_checklist and not project_gone:
        # A LINKED worktree leaves the tracked checklist files alone (--checklist asks for the write): the verdict and
        # exit code above are already decided and do not depend on it. A --record-lesson still writes its lesson
        # (instincts.md, which `worktree diff` carries) but not the bug row: that file is left out of the patch.
        if args.checklist or not skip_bookkeeping(project_dir):
            update_regression_checklist(
                args, cl_matrix, cl_rules, modified_files, checklist_tests, run_tests, exit_code)
        else:
            record_worktree_results(args, cl_matrix, modified_files, checklist_tests, run_tests, overlay_pre)
            print(f"  • {DIM}{tr('Regression checklist: không ghi trong worktree liên kết (thêm --checklist để ghi); kết quả chạy giữ trong state riêng của worktree', 'Regression checklist: not written in a linked worktree (add --checklist to write it); this run results are kept in the worktree own state')}{RESET}")
            if args.record_lesson and exit_code == 0:
                print(f"  • {DIM}{tr('Bài học vào instincts.md; dòng bug KHÔNG ghi ở đây — thêm ở main checkout: agent-kit bugs add ...', 'The lesson goes to instincts.md; its bug row is NOT written here — add it in the main checkout: agent-kit bugs add ...')}{RESET}")

    _lap("checklist")

    def box(ok):
        return "x" if ok else " "

    # Write Markdown summary artifact for user inspection — chỉ ghi những gì đã thực sự kiểm.
    # Written inside .git/ so the report never becomes a change in the audited tree.
    git_dir = os.fsdecode(_git_static(project_dir, "--absolute-git-dir") or b"")
    report_file = (Path(git_dir) if git_dir else Path(tempfile.gettempdir())) / "postfix-gate" / "last_report.md"
    try:
        report_file.parent.mkdir(parents=True, exist_ok=True)
        # backslashreplace: a non-UTF-8 file name (decoded with surrogateescape) crashed this write AFTER the verdict (A8)
        with os.fdopen(_state_fd(report_file, "w"), "w", encoding="utf-8", errors="backslashreplace") as f:
            f.write(tr("# 📋 Báo Cáo Kiểm Toán Post-Fix Gate\n\n", "# 📋 Post-Fix Gate Audit Report\n\n"))
            f.write(f"**{tr('Thời gian', 'Time')}:** {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"**{tr('Dự án', 'Project')}:** {matrix.get('project', 'Universal Platform')}\n")
            f.write(f"**{tr('Phán quyết', 'Verdict')}:** {verdict_text}\n\n")
            f.write("---\n\n")
            f.write(tr("### 1. 🎯 Thay đổi được kiểm toán\n", "### 1. 🎯 Audited change\n"))
            if args.record_lesson:
                f.write(f"- **{tr('Tên lỗi & Triệu chứng', 'Bug & symptom')}:** {md_escape(args.record_lesson)}\n")
            if args.cause:
                f.write(f"- **{tr('Nguyên nhân gốc rễ', 'Root cause')}:** {md_escape(args.cause)}\n")
            if args.prevention:
                f.write(f"- **{tr('Cách khắc phục & Phòng ngừa', 'Fix & prevention')}:** {md_escape(args.prevention)}\n")
            f.write(f"- **{tr('Phạm vi thay đổi', 'Changed files')}:** {len(modified_files)} {tr('tệp', 'files')}\n")
            for mf in modified_files:
                f.write(f"  - `{mf}`\n")
            f.write("\n---\n\n")
            f.write(tr("### 2. 🛡️ Checklist hồi quy (TIA)\n", "### 2. 🛡️ Regression checklist (TIA)\n"))
            f.write("\n".join(checklist_markdown) if checklist_markdown else tr("- Không có component nào khớp watch_files", "- No component matches watch_files"))
            f.write("\n\n---\n\n")
            f.write(tr("### 3. 🔒 Quét tĩnh (regex heuristic)\n", "### 3. 🔒 Static scan (regex heuristics)\n"))
            found = tr("phát hiện", "findings")
            f.write(f"- [{box(hygiene_ok)}] {tr('Rò rỉ bí mật', 'Secret leaks')}: {len(secrets)} {found}\n")
            f.write(f"- [{box(anti_laziness_ok)}] {tr('Placeholder lười biếng', 'Lazy placeholders')}: {len(lazy_findings)} {found}\n")
            f.write(f"- [{box(deps_ok)}] {tr('Dependency (version thả nổi / http://)', 'Dependencies (floating versions / http://)')}: {len(dep_findings)} {found}\n")
            f.write(f"- [{box(perf_ok)}] {tr('Anti-pattern hiệu năng', 'Performance anti-patterns')}: {len(perf_findings)} {found}\n")
            f.write(f"- [{box(resilience_ok)}] {tr('Nuốt lỗi', 'Swallowed errors')}: {len(resilience_findings)} {found}\n")
            f.write(f"- [{box(logging_ok)}] {tr('Log thô / PII', 'Raw logging / PII')}: {len(logging_findings)} {found}\n")
            f.write(f"- [{box(ui_ok)}] DESIGN.md: {ui_msg}\n")
            f.write(f"- [{box(afg_ok)}] {tr('Ảnh minh chứng', 'Proof images')}: {img_count} {tr('ảnh', 'images')}" + (f" — {'; '.join(afg_findings)}" if afg_findings else "") + "\n")
            f.write(tr("\n### 4. ⚠️ Chưa được gate này xác minh\n", "\n### 4. ⚠️ Not verified by this gate\n"))
            if matrix_problem:
                f.write(f"- [ ] Regression matrix: {md_escape(matrix_problem)}\n")
            for tf in tests_touched:
                f.write(f"- [ ] {tr('Test đã có bị sửa/xoá', 'Existing test edited/deleted')}: `{tf}`\n")
            for tf in tests_touched_other:
                f.write(f"- [ ] {tr('Test đã có bị phiên khác / người khác sửa (không chặn)', 'Existing test edited by another session / a person (not blocking)')}: `{tf}`\n")
            f.write(tr("- [ ] Bằng chứng RED -> GREEN (Paired Oracle)\n", "- [ ] RED -> GREEN evidence (paired oracle)\n"))
            f.write(tr("- [ ] Immutable Guards còn nguyên\n", "- [ ] Immutable guards intact\n"))
            f.write("- [ ] OpenCodeReview (`ocr`)\n")
    except OSError as e:
        log_warn(tr(f"Không ghi được báo cáo {report_file}: {e}", f"Cannot write the report {report_file}: {e}"))
    else:
        print(f"  {tr('Báo cáo', 'Report')}: {report_file}")

    if args.json:
        print(json.dumps({
            "verdict": verdict_text, "exit_code": exit_code,
            "accepted": exit_code == 0 and run_tests and not partial and not deferred_by and not impacted_run and not read_only,   # a full run that passed and wrote its receipt
            "files": modified_files,
            "unreadable": unreadable, "regression_tests": regression_tests,
            "matrix_problem": matrix_problem, "tests_touched": tests_touched,
            "tests_touched_other": tests_touched_other, "tests_approved": tests_approved,
            # tests not run because another run interfered (_gate_busy): the Stop hook says "run again later" and caches nothing, so the next Stop
            # runs the suite for real (not a sticky "untested here")
            "busy": _gate_busy(run_tests, lock_held, read_only, regression_tests),
            "busy_reason": (("gate_queue" if gate_slot_busy else "project_lock")
                            if (run_tests and not lock_held and not read_only) else None),
            "budget_exhausted": any(t.get("label") == "BUDGET" for t in regression_tests),   # GATE_TOTAL_BUDGET_S spent
            "test_mode": test_mode, "full_run_required": bool(impacted_run),
            "devkit_artifacts_skipped": len(devkit_artifacts), "device": device_state,
            "static": {"secrets": len(secrets), "lazy": len(lazy_findings), "dependencies": len(dep_findings),
                       "perf": len(perf_findings),
                       "resilience": len(resilience_findings), "logging": len(logging_findings),
                       "settings": len(settings_findings)},
            "findings": FINDINGS,
            "advisories": advisories,  # lazy-senior warnings, never blocking
            "report": str(report_file),
            "matrix_path": str(find_matrix_path(args.matrix) or ""),
            "uncovered": [] if args.allow_no_tests else uncovered_code_files(modified_files, rules),
            "orphan_tests": orphans_new,   # new test files no matrix suite runs (block with --full)
            "checklist": str(get_project_dir() / ".agents" / "regression_checklist.md"),
        }, ensure_ascii=False))

    # A lesson is recorded only for a change that actually passed the gate.
    if args.record_lesson:
        if exit_code == 0:
            record_lesson(base_dir, args.record_lesson, args.cause, args.prevention)
        else:
            log_warn(tr("Không ghi bài học vào instincts.md vì gate chưa PASS.", "Lesson not recorded in instincts.md: the gate did not PASS."))

    # Last: the run log (data only, see _log_gate_run). Plain names only: nothing here can fail before the function's own guard.
    # Fingerprint đã lấy trước suite thì dùng lại. Chỉ khi chưa có (Stop không --full, không ngân sách) mới lấy một lần ở đây.
    _lap("report")
    log_fp = tested_fp or budget_fp or ""
    if run_tests and not _run_log_fp(log_fp):
        log_fp = tree_fp_of(project_dir)
    global _SHADOW
    if run_tests and git_dir and regression_tests and not force_reason:   # lượt impacted: so map với cách chọn cũ
        _SHADOW = _shadow_compare(project_dir, rules, find_matrix_path(args.matrix), covers, regression_tests,
                                  [str(f) for f in modified_files])
    _log_gate_run(args, exit_code, modified_files, regression_tests, ran_cmds, impacted_run, deferred_by, lock_busy, lock_held,
                  cache or (keyed_hits or None), run_tests, force_reason, docs_only, project_dir, git_dir, read_only=read_only,
                  log_fp=log_fp, exit_reason=exit_reason, slot_waits=slot_waits)
    return exit_code


FAIL_LINE = re.compile(r"✖|✗|❌|\bFAILED\b|\bFAIL\b|\bERROR\b|Traceback|AssertionError|\bException\b")


def run_brief():
    """--brief (O3, 2026-09-28): an agent reads the verdict and what failed, not ~70 lines of ✔ —
    each run's output stays in its context and is re-read on every later call. The gate runs
    exactly as without it; the full output is saved to <git dir>/postfix-gate/last_output.log."""
    import contextlib, io  # noqa: E401, PLC0415
    buf = io.StringIO()
    crash = None
    with contextlib.redirect_stdout(buf):
        try:
            code = main()
        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else 1
        except BaseException as e:   # noqa: BLE001 - any other exception lost the whole output (A8, 2026-10-09): kept, then re-raised
            crash, code = e, 1
    text = buf.getvalue()
    try:
        gd = os.fsdecode(_git_static(get_project_dir(), "--absolute-git-dir") or b"")
    except (ImportError, OSError, subprocess.SubprocessError):   # no git on PATH (A10): the log goes to the temp dir
        gd = ""
    out = (Path(gd) if gd else Path(tempfile.gettempdir())) / "postfix-gate" / "last_output.log"
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        with os.fdopen(_state_fd(out, "w"), "w", encoding="utf-8", errors="backslashreplace") as f:
            f.write(text)
    except OSError as e:
        out = Path(f"(không ghi được: {e})")
    keep, tail, summary = [], 0, False
    for line in text.splitlines():
        plain = re.sub(r"\x1b\[[0-9;]*m", "", line)
        if "KẾT LUẬN" in plain or "VERDICT" in plain:
            summary = True
        if summary or (tail and plain.strip().startswith(("|", "Lệnh chạy", "Command"))):
            keep.append(line)
            tail = max(tail - 1, 0)
            continue
        tail = 0
        if "✖" in plain or re.search(r"\[ \] (?!PASS)", plain):
            keep.append(line)
            tail = 16   # up to 8 failing sub-test lines + the last 5 lines + the command line
    json_line = text.rstrip().splitlines()[-1] if "--json" in sys.argv and text.strip() else ""
    if crash is not None:   # the lines just before the crash say where it stopped
        keep += [line for line in text.splitlines()[-10:] if line not in keep]
    keep.append(tr(f"  (đầy đủ: {out} — last_output.log)", f"  (full output: {out} — last_output.log)"))
    if json_line.startswith("{") and (not keep or keep[-1] != json_line):
        keep.append(json_line)
    print("\n".join(keep))
    if crash is not None:
        raise crash   # the traceback and exit status of the crash, as without --brief
    return code


if __name__ == "__main__":
    sys.exit(run_brief() if "--brief" in sys.argv[1:] else main())
