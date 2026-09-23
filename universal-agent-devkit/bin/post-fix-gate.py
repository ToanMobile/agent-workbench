#!/usr/bin/env python3
"""
Post-Fix Audit & Regression Verification Gate CLI Tool
Universal Agent DevKit — Automated Quality & TIA Regression Shield

Audits the working-tree changes after a bug fix:
  - Static checks: secrets, lazy placeholders, dependencies (floating versions,
    http:// sources), perf, swallowed errors, raw logging
  - TIA: maps changed files to regression tests from regression_matrix.json and,
    with --run-tests, executes them and records the real exit code and duration
  - Reports only what was actually checked. RED/GREEN oracle receipts, immutable
    guards and OpenCodeReview are listed as "not verified here".

Only the 6 static checks and the regression run (--run-tests) decide the verdict; the
other sections are reminders. Regression commands are read from the base ref, so the
audited change cannot rewrite them.

--staged (the git pre-commit hook): the 6 static checks only, on the STAGED content —
no regression run, device probe or report. A clean result is exit 2 (tests not run),
never PASS.

Exit codes: 0 PASS, 1 REJECT, 2 UNVERIFIED (tests not run, matrix untrusted, existing
test edited, unreadable file, no coverage, bad --diff), 3 nothing to audit,
4 UNTESTED (everything else passed, but a test exited with its matrix `untested_exit`
code: it cannot run on this machine — e.g. no Unity Editor).

100% Standard Library — Zero external dependencies.
"""

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from devkit_i18n import resolve_lang, set_lang, tr  # noqa: E402
from instincts import append_lesson, md_escape  # noqa: E402


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
    (r"(?i)\.printStackTrace\(\)", ("In stack trace trực tiếp ra console (Gây nghẽn I/O)", "printStackTrace() to the console (blocking I/O)"))
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

def get_project_dir() -> Path:
    target_env = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("TARGET_DIR")
    if target_env and Path(target_env).exists():
        return Path(target_env).resolve()
    try:
        res = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            return Path(res.stdout.strip()).resolve()
    except Exception:
        pass
    return Path.cwd().resolve()

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


def get_repo_root() -> Path:
    global REPO_ROOT
    if REPO_ROOT is None:
        res = subprocess.run(["git", "-C", str(get_project_dir()), "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True)
        REPO_ROOT = Path(res.stdout.strip()).resolve() if res.returncode == 0 and res.stdout.strip() else get_project_dir()
    return REPO_ROOT


def get_project_prefix() -> str:
    """Project dir relative to the repo root ("" unless the project is a monorepo subdir)."""
    global PROJECT_PREFIX
    if PROJECT_PREFIX is None:
        res = subprocess.run(["git", "-C", str(get_project_dir()), "rev-parse", "--show-prefix"],
                             capture_output=True, text=True)
        PROJECT_PREFIX = res.stdout.strip() if res.returncode == 0 else ""
    return PROJECT_PREFIX


def resolve_path(rel_file: str) -> Path:
    """Changed-file paths are relative to the project dir (see get_modified_files)."""
    p = Path(rel_file)
    return p if p.is_absolute() else get_project_dir() / p


DELETED_FILES = set()


def _to_project_rel(repo_rel: str):
    prefix = get_project_prefix()
    if prefix and not repo_rel.startswith(prefix):
        return None  # outside the audited project (monorepo sibling)
    return repo_rel[len(prefix):]


STAGED = False       # --staged: audit the index — what `git commit` will record
STAGED_MODES = {}    # project-relative path -> index mode ("100644", "120000", "160000", …)
_CONTENT_CACHE = {}
BASE_REF = "HEAD"    # what "already there" means for a secret: HEAD, or the --diff base
_BASE_CACHE = {}
PREEXISTING_SECRETS = []   # (file:line, label) found in the base version too — warned, not blocked


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
        res = subprocess.run(["git", "-C", str(get_repo_root()), "show", f"{BASE_REF}:{get_project_prefix()}{rel_file}"],
                             capture_output=True)
        _BASE_CACHE[rel_file] = res.stdout.decode("utf-8", errors="replace") if res.returncode == 0 else None
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
            res = subprocess.run(["git", "-C", str(get_repo_root()), "cat-file", "blob",
                                  f":{get_project_prefix()}{rel_file}"], capture_output=True)
            if res.returncode == 0:
                text = res.stdout.decode("utf-8", errors="replace")
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
            j += 1  # skip source
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
            i += 1  # the next NUL field is the rename/copy SOURCE; keep the destination
        if path is None:
            continue
        if "D" in xy:
            DELETED_FILES.add(path)
        files.add(path)
    if diff_ref:
        res_diff = subprocess.run(["git", "-C", proj, "diff", "--relative", "--name-status", "-z",
                                   diff_ref, "--", "."], capture_output=True)
        if res_diff.returncode != 0:
            raise RuntimeError(tr(f"git diff {diff_ref} thất bại: ", f"git diff {diff_ref} failed: ") + res_diff.stderr.decode(errors='replace').strip())
        files |= _parse_name_status(res_diff.stdout)
    return sorted(files)


def is_devkit_artifact(rel_file: str) -> bool:
    """Links the devkit installer places (hooks, commands, skills, rules, AGENTS.md…) and
    hook state are not the user's change: they are not scanned and not "unreadable"."""
    clean = rel_file.replace("\\", "/")
    if clean.startswith(".claude/audit-gate/"):
        return True
    # The regression checklist is written by this gate itself — never audit our own output.
    if clean in (".agents/regression_status.json", ".agents/regression_checklist.md"):
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
        # 1. Kiểm tra tên file nhạy cảm cấm commit (Keystore, JKS, Provisioning, Service Configs)
        if not exempt_name:
            for file_pat, label in FORBIDDEN_SECRET_FILES:
                if re.search(file_pat, clean_rel, re.IGNORECASE):
                    secrets_found.append((rel_file, tr("File cấm: ", "Forbidden file: ") + _L(label)))
                    _record("secrets", rel_file, label if isinstance(label, tuple) else ("File cấm: " + label, "Forbidden file: " + label))

        # 2. Kiểm tra nội dung file tìm secret / password / key
        # Bỏ qua quét nội dung binary hoặc ảnh
        if rel_file.endswith((".pyc", ".png", ".jpg", ".jpeg", ".webp", ".so", ".dylib", ".a", ".jar", ".aar")):
            continue
        content = read_changed_text(rel_file)
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
        if is_test_path(rel_file) or has_dir(rel_file, "scripts") or rel_file.endswith(("post-fix-gate.py", "gate.sh")):
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

def run_performance_audit(modified_files: list) -> tuple:
    perf_findings = []
    base_dir = get_base_dir()
    devkit_dir = get_devkit_dir()

    # Load AST linters dynamically if available
    check_kotlin_stability = None
    check_unity_gc = None
    try:
        sys.path.insert(0, str(devkit_dir / "scripts"))
        from lint_compose_stability import check_kotlin_file as check_kotlin_stability
        from lint_unity_gc import check_csharp_file as check_unity_gc
    except Exception:
        pass

    for rel_file in modified_files:
        # Exclude tests and build scripts from performance antipattern checks
        if (is_test_path(rel_file) or has_dir(rel_file, "scripts", "bin")
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
            for v in linter(lint_path):
                perf_findings.append((rel_file, f"{tag}: {v}"))
                _record("perf", rel_file, f"{tag}: {v}")
        except Exception:
            pass
        finally:
            if tmp:
                os.unlink(tmp)

    return len(perf_findings) == 0, perf_findings

def run_resilience_audit(modified_files: list) -> tuple:
    findings = []
    for rel_file in modified_files:
        if is_test_path(rel_file) or has_dir(rel_file, "scripts", "bin"):
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
        if is_test_path(rel_file) or has_dir(rel_file, "scripts", "bin", "cmd", "tools"):
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
                findings.append(tr("Thiết bị ngoại vi: Không phát hiện máy thật online qua 'adb devices -l' -> Ghi cờ UNTESTED",
                                   "Devices: no online device found via 'adb devices -l' -> flagged UNTESTED"))
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

    for pdir in proof_dirs:
        if pdir.exists():
            for img_file in list(pdir.glob("*.jpg")) + list(pdir.glob("*.png")):
                total_images += 1
                sz = img_file.stat().st_size
                if sz == 0:
                    zero_byte_images.append(img_file.name)
                    continue
                try:
                    with open(img_file, "rb") as f:
                        h = hashlib.sha256(f.read()).hexdigest()
                    if h in image_hashes and image_hashes[h] != img_file.name:
                        duplicate_images.append((img_file.name, image_hashes[h]))
                    else:
                        image_hashes[h] = img_file.name
                except OSError:
                    pass

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
    """The active profile's name (.active-profile.json), for a matrix without "project"."""
    try:
        d = json.loads((get_project_dir() / ".active-profile.json").read_text(encoding="utf-8"))
        return d.get("name") or d.get("profile") or tr("(không có profile)", "(no profile)")
    except (OSError, ValueError, AttributeError):
        return tr("(không có profile)", "(no profile)")


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


def update_regression_checklist(args, matrix, rules, modified_files, regression_tests, run_tests, exit_code):
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
    if run_tests:
        rc.record_results(data, regression_tests, task=args.task, commit=commit)
    rc.prune_uncovered(data, lambda files: [f for f in uncovered_code_files(files, rules) if (project_dir / f).exists()])
    # No trusted rules (no matrix, or one the gate does not trust): every changed file
    # would look uncovered — rows that say nothing true. Record UNCOVERED only against
    # real rules.
    added = rc.add_uncovered(data, uncovered_code_files(modified_files, rules), task=args.task) if rules else []
    bug_id = None
    if args.record_lesson and exit_code == 0:
        passed = [t["id"] for t in regression_tests if t.get("status") == "PASS" and t.get("id")]
        bug_id = rc.add_bug(data, args.record_lesson, cause=args.cause, task=args.task, test_ids=passed)
    try:
        rc.save(project_dir, data)
    except OSError as e:
        log_warn(tr(f"Không ghi được regression checklist: {e}", f"Cannot write the regression checklist: {e}"))
        return
    c = rc.summary(data)
    print(f"  • Regression checklist: ✅ {c.get('PASS', 0)} · ❌ {c.get('FAIL', 0) + c.get('TIMEOUT', 0)}"
          f" · ⚠️ {c.get('UNCOVERED', 0) + c.get('NEEDS_TEST', 0)} · ⏳ {c.get('NOT_RUN', 0)}"
          f" → {project_dir / rc.VIEW_FILE}")
    if added:
        log_warn(tr(f"{len(added)} file thay đổi CHƯA có test hồi quy — gắn test bằng ",
                    f"{len(added)} changed files have NO regression test — link one with ")
                 + "`python3 bin/regression_checklist.py link <ID> <TEST-ID>`:")
        for item_id in added[:10]:
            print(f"      - {item_id}")
    if bug_id:
        print(f"  • {tr('Đã thêm bug', 'Added bug')} {bug_id} {tr('vào checklist', 'to the checklist')}"
              + ("" if data["items"][bug_id]["tests"] else tr(" (chưa link test)", " (no test linked yet)")))


def run_staged_audit(args, modified_files, devkit_artifacts) -> int:
    """--staged (git pre-commit): the 6 blocking static checks on the staged blobs only.
    No regression run, adb probe, proof-image scan or report — a hook has to be fast
    and must not reach outside the repository. Clean is exit 2: tests were not run,
    so this is never a PASS."""
    print(f"\n{BOLD}{CYAN}🛡️  POST-FIX GATE — {tr('kiểm tĩnh nội dung đã stage (pre-commit)', 'static checks on the staged content (pre-commit)')}{RESET}")
    if not modified_files:
        log_warn(tr("Không có thay đổi nào được stage để kiểm.", "Nothing staged to check.")
                 + (f" {DIM}({tr('bỏ qua', 'skipped')} {len(devkit_artifacts)} {tr('link/state do devkit cài', 'DevKit-installed links/state')}){RESET}" if devkit_artifacts else ""))
        if args.json:
            print(json.dumps({"mode": "staged", "exit_code": 3, "static_ok": True, "files": []}))
        return 3
    print(f"  • {tr('File đã stage', 'Staged files')}: {BOLD}{len(modified_files)}{RESET}")
    checks = [
        ("secrets", tr("Bí mật / file cấm", "Secrets / forbidden files"), run_git_hygiene_audit),
        ("lazy", tr("Placeholder lười biếng", "Lazy placeholders"), run_anti_laziness_audit),
        ("dependencies", tr("Dependency (version thả nổi / http://)", "Dependencies (floating versions / http://)"), run_dependency_audit),
        ("perf", tr("Anti-pattern hiệu năng", "Performance anti-patterns"), run_performance_audit),
        ("resilience", tr("Nuốt lỗi", "Swallowed errors"), run_resilience_audit),
        ("logging", tr("Log thô", "Raw logging"), run_logging_audit),
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
    unreadable = [f for f in modified_files if f not in DELETED_FILES
                  and STAGED_MODES.get(f, "").startswith("100") and read_changed_text(f) is None]
    static_ok = not any(counts.values())
    if not static_ok:
        verdict, color, exit_code = tr("REJECT — sửa các điểm trên rồi commit lại", "REJECT — fix the findings above, then commit again"), RED, 1
    elif unreadable:
        verdict, color, exit_code = tr(f"CHƯA XÁC MINH — {len(unreadable)} file đã stage không đọc được", f"UNVERIFIED — {len(unreadable)} staged files could not be read"), YELLOW, 2
    else:
        verdict, color, exit_code = tr("TĨNH SẠCH — test hồi quy KHÔNG chạy ở pre-commit (postfix-gate --run-tests để nghiệm thu)",
                                       "STATIC CLEAN — regression tests are NOT run in pre-commit (postfix-gate --run-tests to accept)"), GREEN, 2
    print(f"  {BOLD}{tr('KẾT LUẬN', 'VERDICT')}:{RESET} {color}{BOLD}{verdict}{RESET}\n")
    if args.json:
        print(json.dumps({"mode": "staged", "exit_code": exit_code, "static_ok": static_ok,
                          "files": modified_files, "unreadable": unreadable, "static": counts,
                          "findings": FINDINGS},
                         ensure_ascii=False))
    return exit_code


def main():
    parser = argparse.ArgumentParser(description="Post-Fix Audit & TIA Regression Verification Gate")
    parser.add_argument("--diff", help="Git diff reference (e.g. HEAD~1, origin/main)")
    parser.add_argument("--staged", action="store_true",
                        help="Pre-commit mode: static checks only, on the staged content (clean = exit 2, never PASS)")
    parser.add_argument("--matrix", help="Path to regression_matrix.json")
    parser.add_argument("--run-tests", action="store_true", help="Run the matrix regression commands for real (required for PASS)")
    parser.add_argument("--dry-run", action="store_true", help="Only list impacted tests, do not run them (default without --run-tests; never PASS)")
    parser.add_argument("--timeout", type=int, default=900, help="Timeout (seconds) per regression command")
    parser.add_argument("--json", action="store_true", help="Also print the result as JSON (last stdout line)")
    parser.add_argument("--allow-no-tests", action="store_true",
                        help="Allow PASS when there is no matrix / no regression test matches the change")
    parser.add_argument("--record-lesson", help="Lesson / new code trap to record in .agents/instincts.md (only on PASS)")
    parser.add_argument("--cause", help="Root cause of the bug just fixed")
    parser.add_argument("--prevention", help="Prevention rule / how the fix avoids a recurrence")
    parser.add_argument("--task", help="Task id / name being accepted (recorded in the regression checklist)")
    parser.add_argument("--no-checklist", action="store_true",
                        help="Do not update .agents/regression_checklist.md / regression_status.json")
    parser.add_argument("-l", "--lang", choices=["en", "vi"],
                        help="Output language (default: $DEVKIT_LANG, then the project's saved language, then vi)")
    args = parser.parse_args()

    base_dir = get_base_dir()
    set_lang(resolve_lang(args.lang, base_dir))

    # A ref that starts with "-" would be parsed by git as an option (`--output=<file>`).
    if args.diff is not None and (not args.diff or args.diff.startswith("-")):
        log_err(tr(f"--diff không hợp lệ: {args.diff!r} (phải là một git ref, không được bắt đầu bằng '-')",
                   f"invalid --diff: {args.diff!r} (must be a git ref and must not start with '-')"))
        return 2
    if args.staged and (args.diff or args.run_tests or args.record_lesson):
        log_err(tr("--staged chỉ kiểm tĩnh nội dung đã stage — không dùng chung với --diff / --run-tests / --record-lesson",
                   "--staged only statically checks the staged content — it cannot be combined with --diff / --run-tests / --record-lesson"))
        return 2
    base_ref = args.diff if args.diff and ".." not in args.diff else "HEAD"

    global STAGED, BASE_REF
    STAGED = args.staged
    BASE_REF = base_ref
    try:
        all_changed = get_staged_files() if STAGED else get_modified_files(args.diff)
    except RuntimeError as e:
        log_err(str(e))
        return 2
    devkit_artifacts = [f for f in all_changed if is_devkit_artifact(f)]
    modified_files = [f for f in all_changed if f not in devkit_artifacts]
    if STAGED:
        return run_staged_audit(args, modified_files, devkit_artifacts)
    matrix, matrix_problem = load_active_matrix(args.matrix, base_ref)
    # Editing an existing test in the same change can weaken the very assertion the
    # regression run relies on. New test files are fine (that is the RED test).
    prefix = get_project_prefix()
    tests_touched = [f for f in modified_files if is_test_path(f) and subprocess.run(
        ["git", "-C", str(get_repo_root()), "cat-file", "-e", f"{base_ref}:{prefix}{f}"],
        capture_output=True).returncode == 0]
    run_tests = args.run_tests and not args.dry_run

    print(f"\n{BOLD}{CYAN}══════════════════════════════════════════════════════════════════════════════════════{RESET}")
    print(f"{BOLD}{CYAN}      🛡️  POST-FIX AUDIT & TIA REGRESSION VERIFICATION GATE                          {RESET}")
    print(f"  {DIM}{tr('Chặn thật: 6 kiểm tra tĩnh (bí mật, placeholder, dependency, hiệu năng, nuốt lỗi, log) + test hồi quy với --run-tests.', 'Blocking: 6 static checks (secrets, placeholders, dependencies, performance, swallowed errors, logging) + regression tests with --run-tests.')}{RESET}")
    print(f"  {DIM}{tr('Chỉ nhắc (không chặn): DESIGN.md, RED/GREEN, ảnh minh chứng, thiết bị, Immutable Guards, OpenCodeReview.', 'Reminders only (not blocking): DESIGN.md, RED/GREEN, proof images, devices, immutable guards, OpenCodeReview.')}{RESET}\n")
    print(f"{BOLD}{CYAN}══════════════════════════════════════════════════════════════════════════════════════{RESET}\n")

    # Không có thay đổi thì không có gì để nghiệm thu — tuyệt đối không bịa file mẫu để ra PASS.
    if not modified_files:
        if devkit_artifacts:
            log_warn(tr(f"Chỉ có {len(devkit_artifacts)} link/state do devkit cài — không phải thay đổi của người dùng.",
                        f"Only {len(devkit_artifacts)} DevKit-installed links/state files — not a change of yours."))
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

    # Layer 1: Git Diff, Hygiene & Anti-Laziness Audit
    print(f"{BOLD}[1/8] {tr('(CHẶN) Quét bí mật, placeholder lười biếng & dependency:', '(BLOCKING) Secrets, lazy placeholders & dependencies:')}{RESET}")
    hygiene_ok, secrets = run_git_hygiene_audit(modified_files)
    anti_laziness_ok, lazy_findings = run_anti_laziness_audit(modified_files)
    deps_ok, dep_findings = run_dependency_audit(modified_files)
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
    print(f"\n{BOLD}[3/8] {tr('(NHẮC) RED/GREEN, ảnh minh chứng & thiết bị:', '(REMINDER) RED/GREEN, proof images & devices:')}{RESET}")
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

    # Layer 4: TIA Regression Impact Analysis & Marked Checklist
    print(f"\n{BOLD}[4/8] {tr('(CHẶN với --run-tests) Test hồi quy TIA (Test Impact Analysis):', '(BLOCKING with --run-tests) TIA regression tests (Test Impact Analysis):')}{RESET}")
    rules = matrix.get("rules", [])
    impacted_components = []
    regression_tests = []
    immutable_guards_protected = []

    covers = checklist_covers()
    for rule in rules:
        comp_name = rule.get("component", "UnknownComponent")
        watch_files = rule_watch(rule, covers)
        matched = any(match_pattern(f, pat) for f in modified_files for pat in watch_files)
        if not matched:
            continue
        impacted_components.append(comp_name)
        for test in rule.get("mandatory_regression_tests", []):
            regression_tests.append({
                "component": comp_name,
                "id": test.get("id"),
                "name": test.get("name"),
                "command": test.get("command"),
                "untested_exit": test.get("untested_exit"),
                "status": "NOT_RUN",
                "duration": "-",
            })
        for guard in rule.get("immutable_guards", []):
            immutable_guards_protected.append((comp_name, guard))

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

    project_dir = get_project_dir()
    for t in regression_tests:
        if run_tests and t["command"]:
            started = time.perf_counter()
            # Own session/process group so a timeout kills the whole tree (gradle daemons,
            # test workers), not just the shell. Commands come from the matrix at the base
            # ref (load_active_matrix), so the audited change cannot rewrite them.
            proc = subprocess.Popen(t["command"], shell=True, cwd=str(project_dir),
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, errors="replace", start_new_session=True)
            try:
                out, _ = proc.communicate(timeout=args.timeout)
                t["status"] = "PASS" if proc.returncode == 0 else "FAIL"
                # The command's own "cannot run here" code (unity-batch.sh: 2 = no Editor):
                # UNTESTED — not a failing test, and never a PASS.
                if proc.returncode != 0 and isinstance(t.get("untested_exit"), int) \
                        and proc.returncode == t["untested_exit"]:
                    t["status"] = "UNTESTED"
                t["exit_code"] = proc.returncode
                t["output_tail"] = (out or "")[-2000:]
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.communicate()
                t["status"] = "TIMEOUT"
            t["duration"] = f"{time.perf_counter() - started:.2f}s"
        elif run_tests:
            t["status"] = "FAIL"
            t["output_tail"] = tr("Matrix không khai báo command cho test này", "The matrix declares no command for this test")

    checklist_markdown = []
    for t in regression_tests:
        st = t["status"]
        if st == "PASS":
            status_icon = f"{GREEN}[x] PASS{RESET}"
        elif st == "NOT_RUN":
            status_icon = f"{YELLOW}[ ] NOT RUN{RESET}"
        else:
            status_icon = f"{RED}[ ] {st}{RESET}"
        print(f"    {status_icon} | {BOLD}{t['id']:<15}{RESET} : {t['name']}")
        extra = f", exit={t['exit_code']}" if "exit_code" in t else ""
        print(f"           {DIM}{tr('Lệnh chạy', 'Command')}: {t['command']} ({t['duration']}{extra}){RESET}")
        if st in ("FAIL", "TIMEOUT", "UNTESTED") and t.get("output_tail"):
            for line in t["output_tail"].strip().splitlines()[-5:]:
                print(f"           {DIM}| {line}{RESET}")
        mark = "x" if st == "PASS" else " "
        checklist_markdown.append(f"- [{mark}] **{t['id']}** ({t['component']}): {t['name']} -> `{st}` ({t['duration']})")
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

    # Final Summary Verdict
    static_ok = hygiene_ok and anti_laziness_ok and deps_ok and perf_ok and resilience_ok and logging_ok
    tests_passed = sum(1 for t in regression_tests if t["status"] == "PASS")
    tests_untested = [t for t in regression_tests if t["status"] == "UNTESTED"]
    tests_ok = tests_passed + len(tests_untested) == len(regression_tests)
    unverified = bool(regression_tests) and not run_tests
    no_coverage = (not rules or not regression_tests) and not args.allow_no_tests
    # Every changed source file must be re-testable later; one no rule watches would
    # silently fall out of the regression checklist.
    uncovered = [] if args.allow_no_tests else uncovered_code_files(modified_files, rules)

    print(f"\n{BOLD}{CYAN}──────────────────────────────────────────────────────────────────────────────────────{RESET}")
    if not static_ok or (run_tests and not tests_ok):
        verdict_text, verdict_color, exit_code = tr("REJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT", "REJECT — FIX THE FAILED CHECKS"), RED, 1
    elif matrix_problem:
        verdict_text, verdict_color, exit_code = tr("CHƯA XÁC MINH — regression matrix không tin được (xem mục 4): người review rồi commit file ma trận — gate chỉ tin ma trận đã commit, hoặc giống từng byte bản `agent-kit matrix`",
                                                    "UNVERIFIED — regression matrix is not trusted (see section 4): have a human review and commit the matrix file — the gate trusts only a committed matrix, or one byte-identical to `agent-kit matrix`"), YELLOW, 2
    elif tests_touched:
        # Kept UNVERIFIED (an edited test can weaken the very assertion the run relies on);
        # the verdict names the one cure: a person reads that diff, or it gets committed.
        touched_diff = f"git diff {base_ref} -- " + " ".join(tests_touched[:3]) + (" …" if len(tests_touched) > 3 else "")
        verdict_text, verdict_color, exit_code = tr(f"CHƯA XÁC MINH — {len(tests_touched)} file test đã có bị sửa/xoá trong thay đổi: cần người review diff test (`{touched_diff}`), hoặc commit nó, rồi chạy lại gate",
                                                    f"UNVERIFIED — {len(tests_touched)} existing test files were edited/deleted in the change: have a human review the test diff (`{touched_diff}`), or commit it, then re-run the gate"), YELLOW, 2
    elif unverified:
        verdict_text, verdict_color, exit_code = tr("CHƯA XÁC MINH — test hồi quy chưa chạy (dry-run)", "UNVERIFIED — regression tests not run (dry-run)"), YELLOW, 2
    elif unreadable:
        verdict_text, verdict_color, exit_code = tr(f"CHƯA XÁC MINH — {len(unreadable)} file không đọc được để quét", f"UNVERIFIED — {len(unreadable)} files could not be read for scanning"), YELLOW, 2
    elif uncovered and not no_coverage:
        verdict_text, verdict_color, exit_code = f"CHƯA XÁC MINH — {len(uncovered)} file code thay đổi chưa có test hồi quy (thêm vào regression_matrix.json, hoặc --allow-no-tests)", YELLOW, 2
    elif no_coverage:
        verdict_text, verdict_color, exit_code = tr("CHƯA XÁC MINH — không có test hồi quy nào khớp thay đổi (--allow-no-tests để chấp nhận)", "UNVERIFIED — no regression test matches the change (--allow-no-tests to accept)"), YELLOW, 2
    elif run_tests and tests_untested:
        names = ", ".join(t["id"] or "?" for t in tests_untested)
        verdict_text, verdict_color, exit_code = tr(f"UNTESTED — {names} không chạy được trên máy này (thiếu công cụ/thiết bị); KHÔNG phải PASS",
                                                    f"UNTESTED — {names} cannot run on this machine (missing tool/device); NOT a PASS"), YELLOW, 4
    else:
        verdict_text, verdict_color, exit_code = tr("PASS — ĐỦ ĐIỀU KIỆN NGHIỆM THU & BÀN GIAO", "PASS — READY FOR ACCEPTANCE & HANDOVER"), GREEN, 0

    print(f"  {BOLD}{tr('KẾT LUẬN CỔNG POST-FIX AUDIT:', 'POST-FIX AUDIT GATE VERDICT:')}{RESET} {verdict_color}{BOLD}{verdict_text}{RESET}")
    print(f"  • {tr('Test hồi quy đạt', 'Regression tests passed')}: {tests_passed}/{len(regression_tests)}" + (tr(" (chưa chạy)", " (not run)") if unverified else ""))
    print(f"  • {tr('Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log)', 'Static checks (secrets, laziness, dependencies, performance, swallowed errors, logging)')}: "
          f"{tr('đạt', 'passed') if static_ok else tr('CÓ PHÁT HIỆN', 'FINDINGS')}")
    for f in unreadable[:5]:
        print(f"  • {YELLOW}{tr('Không đọc được để quét:', 'Could not read for scanning:')}{RESET} {f}")
    for f in tests_touched[:5]:
        print(f"  • {YELLOW}{tr('Test đã có bị sửa/xoá:', 'Existing test edited/deleted:')}{RESET} {f}")
    print(f"  • {tr('Chỉ nhắc, gate không xác minh: DESIGN.md/a11y, RED/GREEN oracle, ảnh minh chứng, thiết bị, Immutable Guards, OpenCodeReview.', 'Reminders the gate does not verify: DESIGN.md/a11y, RED/GREEN oracle, proof images, devices, immutable guards, OpenCodeReview.')}")
    print(f"{BOLD}{CYAN}══════════════════════════════════════════════════════════════════════════════════════{RESET}\n")

    if not args.no_checklist:
        update_regression_checklist(
            args, matrix, rules, modified_files, regression_tests, run_tests, exit_code)

    def box(ok):
        return "x" if ok else " "

    # Write Markdown summary artifact for user inspection — chỉ ghi những gì đã thực sự kiểm.
    # Written inside .git/ so the report never becomes a change in the audited tree.
    git_dir = subprocess.run(["git", "-C", str(project_dir), "rev-parse", "--absolute-git-dir"],
                             capture_output=True, text=True).stdout.strip()
    report_file = (Path(git_dir) if git_dir else Path(tempfile.gettempdir())) / "postfix-gate" / "last_report.md"
    try:
        report_file.parent.mkdir(parents=True, exist_ok=True)
        with open(report_file, "w", encoding="utf-8") as f:
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
            f.write(tr("- [ ] Bằng chứng RED -> GREEN (Paired Oracle)\n", "- [ ] RED -> GREEN evidence (paired oracle)\n"))
            f.write(tr("- [ ] Immutable Guards còn nguyên\n", "- [ ] Immutable guards intact\n"))
            f.write("- [ ] OpenCodeReview (`ocr`)\n")
    except OSError as e:
        log_warn(tr(f"Không ghi được báo cáo {report_file}: {e}", f"Cannot write the report {report_file}: {e}"))
    else:
        print(f"  {tr('Báo cáo', 'Report')}: {report_file}")

    if args.json:
        print(json.dumps({
            "verdict": verdict_text, "exit_code": exit_code, "files": modified_files,
            "unreadable": unreadable, "regression_tests": regression_tests,
            "matrix_problem": matrix_problem, "tests_touched": tests_touched,
            "devkit_artifacts_skipped": len(devkit_artifacts), "device": device_state,
            "static": {"secrets": len(secrets), "lazy": len(lazy_findings), "dependencies": len(dep_findings),
                       "perf": len(perf_findings),
                       "resilience": len(resilience_findings), "logging": len(logging_findings)},
            "findings": FINDINGS,
            "report": str(report_file),
            "matrix_path": str(find_matrix_path(args.matrix) or ""),
            "uncovered": [] if args.allow_no_tests else uncovered_code_files(modified_files, rules),
            "checklist": str(get_project_dir() / ".agents" / "regression_checklist.md"),
        }, ensure_ascii=False))

    # A lesson is recorded only for a change that actually passed the gate.
    if args.record_lesson:
        if exit_code == 0:
            record_lesson(base_dir, args.record_lesson, args.cause, args.prevention)
        else:
            log_warn(tr("Không ghi bài học vào instincts.md vì gate chưa PASS.", "Lesson not recorded in instincts.md: the gate did not PASS."))

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
