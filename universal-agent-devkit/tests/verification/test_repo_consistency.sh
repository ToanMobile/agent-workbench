#!/usr/bin/env bash
# test_repo_consistency.sh — the repo agrees with itself and with what its docs claim.
#
#   R1  no absolute symlinks, no broken symlinks
#   R2  every *.json parses
#   R3  every *.sh passes `bash -n`; a shebang means the file is executable and an
#       executable .sh/.py has a shebang
#   R4  strict YAML frontmatter for skills/*/SKILL.md and agents/**/*.md: `name`
#       (= directory name for skills), `description` <= 1024 chars, no duplicate names
#   R5  every `/command` quoted in README.md, README.vi.md, AGENTS.md exists in commands/,
#       every commands/*.md is linked (relative) from .claude/commands/
#   R6  every profile's active_councils and essential_mcps exist; every profile
#       regression_matrix.json uses the rules/watch_files schema post-fix-gate reads
#   R7  counts written in the docs (skills, profiles, councils, hooks) equal the real
#       counts, and retired claims ("8-layer", "AST linter", "50 agents", fixed test
#       totals) are gone
#   R8  no references to files of another repo (.Codex/, rulebook/NN-…)
#   R9  the tests live in tests/<group>/test_*.sh and every glob that enumerates them agrees
#   R10 every hooks/, bin/, scripts/ path the docs name (AGENTS.md, READMEs, CLAUDE.md, rules/) exists
#
# Red means a doc, a file or a link is wrong: fix that, do not relax the check.
# Usage: bash tests/verification/test_repo_consistency.sh      (needs python3; uses ruby for YAML if present)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "test_repo_consistency.sh: python3 is required" >&2
  exit 1
fi

python3 - "$ROOT" <<'PY'
import glob, json, os, re, shutil, subprocess, sys

ROOT = sys.argv[1]
PASS = FAIL = 0
def check(ok, name, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"✔ {name}")
    else:
        FAIL += 1
        print(f"✘ {name}" + (f"\n    {detail}" if detail else ""))

SKIP_DIRS = {".git", "node_modules", "__pycache__"}
def walk():
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for n in dns + fns:
            yield os.path.join(dp, n)

def rel(p):
    return os.path.relpath(p, ROOT)

# ── R1 symlinks ────────────────────────────────────────────────────────────────
abs_links, broken = [], []
for p in walk():
    if os.path.islink(p):
        t = os.readlink(p)
        if t.startswith("/"):
            abs_links.append(f"{rel(p)} -> {t}")
        elif not os.path.exists(p):
            broken.append(f"{rel(p)} -> {t}")
check(not abs_links, "R1 no absolute symlinks", "; ".join(abs_links[:5]))
check(not broken, "R1 no broken symlinks", "; ".join(broken[:5]))

# ── R2 JSON ────────────────────────────────────────────────────────────────────
bad_json = []
for p in walk():
    if p.endswith(".json") and os.path.isfile(p):
        try:
            json.load(open(p, encoding="utf-8"))
        except Exception as e:
            bad_json.append(f"{rel(p)}: {e}")
check(not bad_json, "R2 every JSON file parses", "; ".join(bad_json[:5]))

# ── R3 shell syntax & executable bits ─────────────────────────────────────────
syntax, bits = [], []
for p in walk():
    if os.path.islink(p) or not os.path.isfile(p):
        continue
    if p.endswith(".sh"):
        r = subprocess.run(["bash", "-n", p], capture_output=True, text=True)
        if r.returncode != 0:
            syntax.append(f"{rel(p)}: {r.stderr.strip()[:120]}")
    if p.endswith((".sh", ".py")):
        with open(p, "rb") as fh:
            shebang = fh.read(2) == b"#!"
        exe = os.access(p, os.X_OK)
        if shebang and not exe:
            bits.append(f"{rel(p)}: shebang but not executable")
        elif exe and not shebang:
            bits.append(f"{rel(p)}: executable without shebang")
check(not syntax, "R3 every .sh passes bash -n", "; ".join(syntax[:5]))
check(not bits, "R3 executable bit matches shebang", "; ".join(bits[:8]))

# ── R4 frontmatter ─────────────────────────────────────────────────────────────
RUBY = shutil.which("ruby")
def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None, "no frontmatter block"
    block = m.group(1)
    if RUBY:
        r = subprocess.run(
            [RUBY, "-ryaml", "-rjson", "-e",
             "d = YAML.safe_load(STDIN.read); puts JSON.generate(d.is_a?(Hash) ? d : {'__not_a_map__' => true})"],
            input=block, capture_output=True, text=True)
        if r.returncode != 0:
            return None, "YAML: " + r.stderr.strip().splitlines()[-1][:160]
        data = json.loads(r.stdout)
        if "__not_a_map__" in data:
            return None, "frontmatter is not a mapping"
        return data, None
    # Fallback (no ruby): one `key: value` per line; an unquoted plain value must not
    # contain ": " or " #" (YAML would reject or truncate it).
    data = {}
    for line in block.splitlines():
        if not line.strip() or line.startswith((" ", "\t", "-")):
            continue
        k, sep, v = line.partition(":")
        if not sep:
            return None, f"not a key/value line: {line[:60]}"
        v = v.strip()
        if v[:1] in "\"'":
            v = v[1:-1]
        elif ": " in v or " #" in v:
            return None, f"unquoted value of '{k}' contains ': ' or ' #'"
        data[k.strip()] = v
    return data, None

def check_frontmatter(files, label, name_must_match_dir):
    problems, names = [], {}
    for f in files:
        data, err = frontmatter(f)
        if err:
            problems.append(f"{rel(f)}: {err}")
            continue
        name, desc = data.get("name"), data.get("description")
        if not name:
            problems.append(f"{rel(f)}: missing name")
        if not desc:
            problems.append(f"{rel(f)}: missing description")
        elif len(str(desc)) > 1024:
            problems.append(f"{rel(f)}: description {len(str(desc))} > 1024 chars")
        if name_must_match_dir and name and name != os.path.basename(os.path.dirname(f)):
            problems.append(f"{rel(f)}: name '{name}' != directory")
        if name:
            names.setdefault(name, []).append(rel(f))
    dups = {n: fs for n, fs in names.items() if len(fs) > 1}
    check(not problems, f"R4 {label}: valid frontmatter", "; ".join(problems[:6]))
    check(not dups, f"R4 {label}: unique names", str(dups)[:300])

skill_files = sorted(glob.glob(os.path.join(ROOT, "skills/*/SKILL.md")))
agent_files = sorted(glob.glob(os.path.join(ROOT, "agents/**/*.md"), recursive=True))
check_frontmatter(skill_files, "skills", True)
check_frontmatter(agent_files, "agents", False)

# ── R5 slash commands ──────────────────────────────────────────────────────────
# Built-in agent commands the docs may mention; they are not DevKit commands.
BUILTINS = {"help", "clear", "compact", "config", "init", "model", "memory", "cost",
            "doctor", "login", "logout", "status", "hooks", "agents", "mcp", "permissions",
            "resume", "exit", "plugin", "code-review", "security-review"}
DOCS = ["README.md", "README.vi.md", "AGENTS.md"]
cmd_re = re.compile(r"`(/[a-z][a-z0-9-]*)(?=[`\s\[])")
missing = []
for d in DOCS:
    text = open(os.path.join(ROOT, d), encoding="utf-8").read()
    for m in cmd_re.finditer(text):
        name = m.group(1)[1:]
        if name in BUILTINS:
            continue
        if not os.path.exists(os.path.join(ROOT, "commands", name + ".md")):
            missing.append(f"{d}: /{name}")
check(not missing, "R5 every documented /command exists in commands/", "; ".join(sorted(set(missing))[:10]))

unlinked = []
for c in sorted(glob.glob(os.path.join(ROOT, "commands/*.md"))):
    link = os.path.join(ROOT, ".claude/commands", os.path.basename(c))
    if not os.path.islink(link) or os.readlink(link).startswith("/") or not os.path.exists(link):
        unlinked.append(os.path.basename(c))
check(not unlinked, "R5 every command is linked (relative) from .claude/commands/", ", ".join(unlinked[:10]))

_sync_path = os.path.join(ROOT, "scripts/governance/sync_commands.sh")
if not os.path.isfile(_sync_path):
    _sync_path = os.path.join(ROOT, "scripts/sync_commands.sh")
sync = open(_sync_path, encoding="utf-8").read()
alias_missing = [a for a in re.findall(r'^\s*"([a-z0-9-]+):[a-z0-9-]+"\s*$', sync, re.M)
                 if not os.path.exists(os.path.join(ROOT, "commands", a + ".md"))]
check(not alias_missing, "R5 every alias in sync_commands.sh has commands/<alias>.md", ", ".join(alias_missing))

# The 1.1.0 renames (/review /qa /test /bugs /crashlytics) were removed in 1.2.0 and stay gone:
# /review would shadow the agent's built-in /review, the others listed a second entry every session.
gone = [n for n in ("review", "qa", "test", "bugs", "crashlytics")
        if os.path.lexists(os.path.join(ROOT, "commands", n + ".md"))]
check(not gone and "DEPRECATED_ALIASES" not in sync,
      "R5 removed deprecated aliases stay removed (commands/review.md would shadow the built-in /review)",
      ", ".join(gone) or "DEPRECATED_ALIASES still in sync_commands.sh")

# An alias is a link to its skill: a hand-written file under the alias name drifts from the skill and
# lists a second entry (commands/sandbox.md, 2026-10-25: hard-coded universal-agent-devkit/ paths).
shadowed = [a for a in re.findall(r'^\s*"([a-z0-9-]+):[a-z0-9-]+"\s*$', sync, re.M)
            if os.path.lexists(os.path.join(ROOT, "commands", a + ".md"))
            and not os.path.islink(os.path.join(ROOT, "commands", a + ".md"))]
check(not shadowed, "R5 every alias in sync_commands.sh is a link, not a hand-written file", ", ".join(shadowed))

# `agent-kit commands --sync` on the repo must change nothing: a link it makes that is not committed shows up as an
# untracked file after every sync (2026-10-25: generate2dmedia, generate2dsprite, video2dsprite and parallel-lanes are
# command-less on purpose). Run on a copy, never on the real tree: other sessions share it. An
# older sync's link for a command-less skill (planted below) must be removed again.
import tempfile
def _cmd_map(d):
    if not os.path.isdir(d):
        return {}
    return {n: ("-> " + os.readlink(os.path.join(d, n))) if os.path.islink(os.path.join(d, n)) else "file"
            for n in os.listdir(d)}
with tempfile.TemporaryDirectory() as td:
    for sub in ("commands", ".claude/commands"):
        if os.path.isdir(os.path.join(ROOT, sub)):
            shutil.copytree(os.path.join(ROOT, sub), os.path.join(td, sub), symlinks=True)
    for sk in glob.glob(os.path.join(ROOT, "skills/*/SKILL.md")):
        os.makedirs(os.path.join(td, os.path.dirname(os.path.relpath(sk, ROOT))), exist_ok=True)
        shutil.copy2(sk, os.path.join(td, os.path.relpath(sk, ROOT)))
    os.makedirs(os.path.join(td, "rules"))
    shutil.copy2(os.path.join(ROOT, "rules/essentials.md"), os.path.join(td, "rules/essentials.md"))
    os.makedirs(os.path.join(td, "scripts/governance"))
    shutil.copy2(_sync_path, os.path.join(td, "scripts/governance/sync_commands.sh"))
    _before = {s: _cmd_map(os.path.join(td, s)) for s in ("commands", ".claude/commands")}
    if os.path.isfile(os.path.join(td, "skills/generate2dmedia/SKILL.md")):
        os.symlink("../skills/generate2dmedia/SKILL.md", os.path.join(td, "commands/generate2dmedia.md"))
        if os.path.isdir(os.path.join(td, ".claude/commands")):
            os.symlink("../../commands/generate2dmedia.md", os.path.join(td, ".claude/commands/generate2dmedia.md"))
    _r = subprocess.run(["bash", os.path.join(td, "scripts/governance/sync_commands.sh")],
                        capture_output=True, text=True, timeout=120)
    _after = {s: _cmd_map(os.path.join(td, s)) for s in ("commands", ".claude/commands")}
_drift = [f"{s}/{n}: {_before[s].get(n, 'absent')} => {_after[s].get(n, 'absent')}"
          for s in _before for n in sorted(set(_before[s]) | set(_after[s])) if _before[s].get(n) != _after[s].get(n)]
check(_r.returncode == 0 and not _drift,
      "R5 sync_commands.sh changes nothing in commands/ or .claude/commands/ (every link it makes is committed)",
      (f"rc={_r.returncode} {_r.stderr.strip()[:160]} " if _r.returncode else "") + "; ".join(_drift[:8])
      + (f" (+{len(_drift) - 8})" if len(_drift) > 8 else ""))

# A script a skill or command tells the agent to run must run in an INSTALLED repo, where the kit is .agents/devkit/:
# universal-agent-devkit/<path> exists only in agent-workbench, and a pre-reorg flat path (scripts/X before the
# scripts/<group>/ split, 2026-10-02) nowhere (2026-10-25: /sandbox, /gen-prompt, /createTask, /unity-test, /check).
RUN = re.compile(r"(?:python3|bash|sh|node)\s+((?:universal-agent-devkit|\.agents/devkit)/[\w./-]+\.(?:py|sh|js|mjs))")
bad_run = []
for f in sorted(set(glob.glob(os.path.join(ROOT, "skills/*/SKILL.md")) +
                    [p for p in glob.glob(os.path.join(ROOT, "commands/*.md")) if not os.path.islink(p)])):
    for n, line in enumerate(open(f, encoding="utf-8"), 1):
        for m in RUN.finditer(line):
            p = m.group(1)
            rel = p.split("/", 2)[2] if p.startswith(".agents/devkit/") else p.split("/", 1)[1]
            if p.startswith("universal-agent-devkit/") or not os.path.exists(os.path.join(ROOT, rel)):
                bad_run.append(f"{os.path.relpath(f, ROOT)}:{n} {p}")
check(not bad_run, "R5 skills/commands run kit scripts by a path that exists in an installed repo (.agents/devkit/…)",
      "; ".join(bad_run[:8]) + (f" (+{len(bad_run) - 8})" if len(bad_run) > 8 else ""))

# The kit's own CLAUDE.md is a NESTED instruction file for every session of the repo that holds the kit: an @import in it
# loads the 60 KB master AGENTS.md + 32 KB core-rules the first time an agent reads any kit file (2026-10-25: 180 of
# ~1,156 agent-workbench transcripts in 7 days, 18.8 MB). Those files are on-demand (essentials: "Read on demand").
kit_claude = os.path.join(ROOT, "CLAUDE.md")
imports = [l.strip() for l in open(kit_claude, encoding="utf-8")
           if re.search(r"(^|\s)@[\w./-]+", l)] if os.path.isfile(kit_claude) else []
check(not imports, "R5 the kit CLAUDE.md imports nothing (its targets are read on demand)", "; ".join(imports))

# ── R6 profiles ────────────────────────────────────────────────────────────────
mcp_names = set()
for f in ("mcp/.mcp.json", "mcp/mcp_config.json"):
    mcp_names |= set(json.load(open(os.path.join(ROOT, f)))["mcpServers"])
# agentmemory: removed (dead InMemoryKV fallback with 0 tool_use calls across 8900+ sessions).
am_bad = []
for f in ("mcp_config.json", "mcp/.mcp.json", "mcp/mcp_config.json"):
    if "agentmemory" in (json.load(open(os.path.join(ROOT, f))).get("mcpServers") or {}):
        am_bad.append(f)
check(not am_bad, "R6 dead agentmemory MCP is absent from DevKit + install sources", "; ".join(am_bad))
prof_problems = []
profiles = sorted(d for d in os.listdir(os.path.join(ROOT, "profiles"))
                  if os.path.isfile(os.path.join(ROOT, "profiles", d, "profile.json")))
for pid in profiles:
    meta = json.load(open(os.path.join(ROOT, "profiles", pid, "profile.json")))
    for c in meta.get("active_councils", []):
        if not (os.path.isfile(os.path.join(ROOT, "agents/councils", c))
                or os.path.isfile(os.path.join(ROOT, "profiles", pid, "councils", c))):
            prof_problems.append(f"{pid}: council {c} missing")
    for m in meta.get("essential_mcps", []):
        if m not in mcp_names:
            prof_problems.append(f"{pid}: MCP '{m}' not defined in mcp/")
    for k in ("rules_file", "regression_matrix"):
        if meta.get(k) and not os.path.isfile(os.path.join(ROOT, meta[k])):
            prof_problems.append(f"{pid}: {k} {meta[k]} missing")
check(not prof_problems, "R6 profile councils, MCPs, rules and matrices exist", "; ".join(prof_problems[:6]))

# Every profile matrix uses the schema post-fix-gate reads (bin/post-fix-gate.py TIA
# layer: matrix["rules"][*].component / watch_files / mandatory_regression_tests[*].id,
# .command). Any other shape (e.g. a "checklist" list) is silently ignored by the gate.
matrix_problems = []
for mf in sorted(glob.glob(os.path.join(ROOT, "profiles", "*", "regression_matrix.json"))):
    rel = os.path.relpath(mf, ROOT)
    try:
        m = json.load(open(mf))
    except Exception as e:
        matrix_problems.append(f"{rel}: {e}"); continue
    rules = m.get("rules")
    if not isinstance(rules, list) or not rules:
        matrix_problems.append(f"{rel}: no non-empty 'rules' list (keys: {sorted(m)})"); continue
    for i, r in enumerate(rules):
        if not r.get("component"):
            matrix_problems.append(f"{rel}: rules[{i}] has no component")
        if not (isinstance(r.get("watch_files"), list) and r["watch_files"]):
            matrix_problems.append(f"{rel}: rules[{i}] has no watch_files")
        tests_ = r.get("mandatory_regression_tests")
        if not (isinstance(tests_, list) and tests_):
            matrix_problems.append(f"{rel}: rules[{i}] has no mandatory_regression_tests"); continue
        for t in tests_:
            if not (t.get("id") and t.get("command")):
                matrix_problems.append(f"{rel}: rules[{i}] test without id/command")
            elif re.search(r"\|\|\s*true\s*$", t["command"]):
                matrix_problems.append(f"{rel}: {t['id']} ends in '|| true' (can never fail)")
check(not matrix_problems, "R6 every profile regression_matrix.json has the schema the gate reads",
      "; ".join(matrix_problems[:6]))

# ── R7 documented counts ───────────────────────────────────────────────────────
n_skills = len(skill_files)
n_profiles = len(profiles)
n_councils = len(glob.glob(os.path.join(ROOT, "agents/councils/*.md")))
n_hook_files = len(glob.glob(os.path.join(ROOT, "hooks/*.sh")))
wired = set()
for ev in json.load(open(os.path.join(ROOT, "hooks/hooks.json")))["hooks"].values():
    for matcher in ev:
        for h in matcher["hooks"]:
            wired.add(re.findall(r"([\w.-]+\.sh)", h["command"])[-1])
n_wired = len(wired)
print(f"  (real counts: {n_skills} skills, {n_profiles} profiles, {n_councils} councils, "
      f"{n_hook_files} hook scripts, {n_wired} wired hooks)")

COUNT_DOCS = ["README.md", "README.vi.md", "AGENTS.md", "CLAUDE.md", ".claude-plugin/plugin.json",
              "rules/core-rules.md", "bin/agent-kit", "Makefile"]
N = r"(\d+)\s*"
RULES = [
    ("skills",   re.compile(N + r"(?:curated\s+|canonical\s+|engineering\s+)*(?:skills?|kỹ năng)\b", re.I), {n_skills}),
    ("skills",   re.compile(r"Skills-(\d+)"), {n_skills}),
    ("profiles", re.compile(N + r"(?:dynamic\s+|domain\s+)*(?:profiles?)\b", re.I), {n_profiles}),
    ("profiles", re.compile(r"Profiles-(\d+)"), {n_profiles}),
    ("councils", re.compile(N + r"(?:quality\s+|audit\s+)*(?:councils?|hội đồng)", re.I), {n_councils}),
    ("hooks",    re.compile(N + r"(?:lifecycle\s+|safety\s+)*(?:hook scripts|hooks?|safety gates)\b", re.I), {n_hook_files, n_wired}),
    ("hooks",    re.compile(N + r"(?:wired|registered)\b", re.I), {n_wired}),
]
RETIRED = [r"8[- ]layer", r"8 tầng", r"8 lớp", r"5[- ]layer", r"5 tầng", r"AST (?:machine )?linter",
           r"50[- ](?:specialized |audit )?agents?", r"50 agent", r"\b302\b", r"\b294\b",
           r"168 (?:contract|hook)", r"160 / 160", r"44 curated", r"file://", r"Windsurf", r"Copilot",
           r"100/100 HEALTHY", r"cryptographically signed"]
wrong, retired = [], []
for d in COUNT_DOCS:
    path = os.path.join(ROOT, d)
    if not os.path.isfile(path):
        continue
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        for label, rx, allowed in RULES:
            for m in rx.finditer(line):
                if int(m.group(1)) not in allowed:
                    wrong.append(f"{d}:{i} '{m.group(0).strip()}' ({label}: real {sorted(allowed)})")
        for pat in RETIRED:
            if re.search(pat, line, re.I):
                retired.append(f"{d}:{i} /{pat}/")
check(not wrong, "R7 documented counts match the repo", "; ".join(wrong[:8]))
check(not retired, "R7 retired claims are gone", "; ".join(retired[:8]))

# ── R8 foreign-repo references ────────────────────────────────────────────────
foreign = []
scan = DOCS + ["CLAUDE.md"] + glob.glob(os.path.join(ROOT, "skills/*/SKILL.md")) \
    + glob.glob(os.path.join(ROOT, "agents/**/*.md"), recursive=True) \
    + glob.glob(os.path.join(ROOT, "rules/*.md")) + glob.glob(os.path.join(ROOT, "commands/*.md"))
for f in scan:
    path = f if os.path.isabs(f) else os.path.join(ROOT, f)
    if not os.path.isfile(path):
        continue
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        if re.search(r"\.Codex/|rulebook/\d", line):
            foreign.append(f"{rel(path)}:{i}")
check(not foreign, "R8 no .Codex/ or rulebook/NN references", "; ".join(sorted(set(foreign))[:8]))

# R9 the tests live one level down, tests/<group>/test_*.sh, and every place that enumerates them agrees:
# a glob left on tests/test_*.sh matches nothing and passes silently. (2026-10-02: the scripts/ regrouping had already
# broken 13 tests through stale paths that the gate's impacted selection never ran.)
flat = sorted(glob.glob(os.path.join(ROOT, "tests", "test_*.sh")))
grouped = sorted(glob.glob(os.path.join(ROOT, "tests", "*", "test_*.sh")))
anywhere = sorted(glob.glob(os.path.join(ROOT, "tests", "**", "test_*.sh"), recursive=True))
check(not flat, "R9 no test_*.sh directly under tests/ (they live in tests/<group>/)", "; ".join(rel(p) for p in flat[:6]))
check(len(grouped) > 0 and len(grouped) == len(anywhere),
      "R9 every test sits exactly one level down (what `agent-kit test` and run_impacted.sh glob)",
      "%d at tests/<group>/, %d anywhere under tests/" % (len(grouped), len(anywhere)))
_ak = open(os.path.join(ROOT, "bin", "agent-kit"), encoding="utf-8").read()
_ri = open(os.path.join(ROOT, "tests", "run_impacted.sh"), encoding="utf-8").read()
check('run_impacted.sh" --all' in _ak and "tests/*/test_*.sh" in _ri   # (hooks/tests/test_*.sh is another folder, 14/10)
      and "tests/test_*.sh" not in (_ak + _ri).replace("tests/*/test_*.sh", "").replace("hooks/tests/test_*.sh", ""),
      "R9 agent-kit test runs the suite through run_impacted.sh --all, which enumerates tests/*/test_*.sh; nothing still globs tests/test_*.sh")
_ev = re.findall(r'DEVKIT_SUITE_RX = re\.compile\(r"([^"]+)"\)', open(os.path.join(ROOT, "hooks", "test_evidence_gate.sh"), encoding="utf-8").read())
check(bool(_ev) and re.search(_ev[0], "bash tests/gate/test_x.sh") is not None and re.search(_ev[0], "bash tests/test_x.sh") is not None,
      "R9 test_evidence_gate counts tests/<group>/test_*.sh (and a flat one) as a DevKit suite")

# R10 a kit script the docs name exists: after the scripts/<group>/ split (2026-10-02) AGENTS.md and the READMEs kept 13
# flat paths (scripts/nightly.py, scripts/lint_*.py, …) until the 2026-10-25 audit. A path that resolves inside a skill
# folder (ui-ux-pro-max's scripts/search.py) is that skill's own script.
DOC_PATH = re.compile(r"(?<![\w./-])((?:hooks|bin|scripts)/[\w./*-]*(?:\.py|\.sh|\*))")
skill_dirs = sorted(glob.glob(os.path.join(ROOT, "skills", "*")))
def _resolves(p):
    hit = (lambda q: bool(glob.glob(q))) if "*" in p else os.path.exists
    return hit(os.path.join(ROOT, p)) or any(hit(os.path.join(d, p)) for d in skill_dirs)
dead_paths = []
for d in ["AGENTS.md", "README.md", "README.vi.md", "CLAUDE.md"] + sorted(glob.glob(os.path.join(ROOT, "rules", "*.md"))):
    path = d if os.path.isabs(d) else os.path.join(ROOT, d)
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        for m in DOC_PATH.finditer(line):
            if not _resolves(m.group(1)):
                dead_paths.append(f"{os.path.relpath(path, ROOT)}:{i} {m.group(1)}")   # `rel` is rebound by R5/R6
check(not dead_paths, "R10 every hooks/ bin/ scripts/ path the docs name exists",
      "; ".join(dead_paths[:8]) + (f" (+{len(dead_paths) - 8})" if len(dead_paths) > 8 else ""))

print()
print(f"repo consistency: {PASS} passed, {FAIL} failed")
if FAIL == 0:
    print("repo consistency: all checks passed")
sys.exit(0 if FAIL == 0 else 1)
PY
