#!/usr/bin/env bash
# Regression test (Dot 28): a profile's rules are split into an ALWAYS-LOADED part (.agents/context/profile-rules.md,
# imported by AGENTS.md) and an ON-DEMAND reference (.agents/context/profile-reference.md, never imported). Rubric dim 5
# caps the bytes a session loads (AGENTS.md + profile-rules.md + rules-index.md) at 40 KB; the game and android profiles
# alone were 21-23 KB. User decisions (12-13/10): no rule sentence is deleted, MUST/CẤM/BẮT BUỘC/bất biến lines stay
# always-loaded, essentials are not trimmed. This test is the oracle for those promises.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# The python half prints one "ok|fail <text>" line per check.
python3 - "$DEVKIT_DIR" "$TMP" <<'PY' > "$TMP/result.txt" 2>&1
import collections, glob, json, os, re, subprocess, sys

D, TMP = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(D, "scripts", "governance"))
import context_sync as cs

if not hasattr(cs, "split_rules"):
    print("fail context_sync.split_rules does not exist yet")
    sys.exit(0)

MUST =re.compile(r"BẮT BUỘC|[Bb]ắt buộc|MUST|CẤM|[Cc]ấm|bất biến|Bất biến|Nghiêm cấm|Tuyệt đối")
START = re.compile(r"^<!-- on-demand: (.+?) -->$")
END = "<!-- /on-demand -->"


def say(good, text):
    print(("ok " if good else "fail ") + text)


def source(p):
    return open(os.path.join(D, "profiles", p, "rules", p + "-rules.md"), encoding="utf-8").read()


def project(p, name=None):
    root = os.path.join(TMP, name or "proj-" + p)
    os.makedirs(os.path.join(root, ".agents"), exist_ok=True)
    link = os.path.join(root, ".agents", "active-profile")
    if os.path.islink(link):
        os.unlink(link)
    os.symlink(os.path.join(D, "profiles", p), link)
    return root


profiles = sorted(os.path.basename(os.path.dirname(os.path.dirname(f))) for f in glob.glob(os.path.join(D, "profiles", "*", "rules", "*-rules.md")))
split = {}
for p in profiles:
    src = source(p)
    always, blocks = cs.split_rules(src)
    split[p] = (src, always, blocks)

# C. markers are balanced in every profile (an unbalanced file is silently loaded whole, so count the blocks too)
for p, (src, always, blocks) in split.items():
    depth, titles, bad = 0, [], None
    for n, line in enumerate(src.split("\n"), 1):
        m = START.match(line)
        if m:
            depth += 1
            titles.append(m.group(1))
            if depth > 1:
                bad = "nested start at line %d" % n
        elif line == END:
            depth -= 1
            if depth < 0:
                bad = "stray end at line %d" % n
    if depth != 0:
        bad = bad or "unclosed block"
    if len(set(titles)) != len(titles):
        bad = bad or "duplicate block title"
    say(bad is None and len(blocks) == len(titles), "%s: markers balanced, %d block(s) split (%s)" % (p, len(titles), bad or "ok"))

# A. nothing is lost and nothing changes place: put every stub back as marker + body + END and the source returns
# byte for byte; the generated profile-reference.md holds each block, in order, exactly as `## title` + body.
for p, (src, always, blocks) in split.items():
    ref = cs.wanted(project(p))["profile-reference.md"]
    rebuilt, it, bad = [], iter(blocks), None
    for line in always.split("\n"):
        if not line.startswith("> ↪ "):
            rebuilt.append(line)
            continue
        t, body = next(it, (None, None))
        if t is None or line != "> ↪ " + t:
            bad = "stub %r does not match the next block" % line[:40]
            break
        rebuilt += ["<!-- on-demand: %s -->" % t] + body.split("\n") + [END]
    in_ref = all(("## %s\n%s\n" % (t, body)) in ref for t, body in blocks) and [ref.index("## " + t + "\n") for t, _b in blocks] == sorted(
        ref.index("## " + t + "\n") for t, _b in blocks)
    stubs = [l for l in always.split("\n") if l.startswith("> ↪ ")]
    say(bad is None and "\n".join(rebuilt) == src and in_ref and len(stubs) == len(blocks) and all(len(s.encode()) <= 200 for s in stubs),
        "%s: lossless and in order (%d block(s) rebuild the source exactly, each in profile-reference.md, stubs short) %s" % (p, len(blocks), bad or ""))

# B. no MUST/CẤM/BẮT BUỘC/bất biến line is moved out of the always-loaded file
for p, (src, always, blocks) in split.items():
    hit = [l[:70] for _t, body in blocks for l in body.split("\n") if MUST.search(l)]
    say(not hit, "%s: no MUST-pattern line inside an on-demand block %s" % (p, hit[:2] if hit else ""))

# stubs resolve to a heading of the generated reference file
for p, (src, always, blocks) in split.items():
    if not blocks:
        continue
    ref = cs.wanted(project(p))["profile-reference.md"].split("\n")
    stubs = [l for l in always.split("\n") if l.startswith("> ↪ ")]
    heads = {l[3:] for l in ref if l.startswith("## ")}
    titles = [t for t, _b in blocks]
    say(stubs == ["> ↪ " + t for t in titles] and set(titles) == heads,
        "%s: every stub is '> ↪ <title>' and names a '## title' that exists in profile-reference.md (and nothing else does)" % p)
    loaded = cs.wanted(project(p))["profile-rules.md"]
    say(loaded.count(cs.PREAMBLE) == 1 and "profile-reference.md" in cs.PREAMBLE,
        "%s: profile-rules.md says once where the cut text went" % p)

# The cut text must not come back through an import: neither the preamble nor a stub may carry an `@path` token, and no
# line of any loaded profile file starts with `@` (the import syntax; `@Immutable` inside backticks is just text).
at_token = re.compile(r"(^|\s)@\S")
for p, (src, always, blocks) in split.items():
    loaded = cs.wanted(project(p))["profile-rules.md"]
    stub_lines = [l for l in always.split("\n") if l.startswith("> ↪ ")]
    say(not at_token.search(cs.PREAMBLE) and not any(at_token.search(s) for s in stub_lines)
        and not any(l.startswith("@") for l in loaded.split("\n")),
        "%s: no @import token in the preamble, the stubs or at the start of a loaded line" % p)

# The guardrails that apply to every edit stay in the LOADED text (tests/verification/test_profile_guardrails.sh only greps the source).
# (the last three of each list came from the Antigravity audit of Dot 28: obligations phrased without MUST/CẤM that a regex cannot see)
LOADED = {"game": ["Application.targetFrameRate", "OnApplicationPause", "Cấm tuyệt đối `new`", "Debounce", "transform.DOKill(true)"],
          "android": ["LazyColumn", "derivedStateOf", "PendingIntent.FLAG_IMMUTABLE", "fallbackToDestructiveMigration",
                      "Không gửi PII vào analytics/Crashlytics", "Đổi ranh giới = hỏi trước"]}
for p, needles in LOADED.items():
    loaded = cs.wanted(project(p))["profile-rules.md"]
    gone = [n for n in needles if n not in loaded]
    say(not gone, "%s: guardrails still loaded at session start %s" % (p, gone or ""))

# D. budgets of the always-loaded file, and profiles without markers unchanged
# Measured 13/10 after the split (bytes incl. header and preamble): android 13497, game 14906. A ratchet, not a goal:
# it fails when a profile grows back, so the next reference-style section is cut on purpose. automotive and the rest carry
# no markers (their rules are hardware-safety or small): they must stay byte for byte the source.
BUDGET = {"game": 15 * 1024, "android": 14 * 1024}
for p, (src, always, blocks) in split.items():
    w = cs.wanted(project(p))
    size = len(w["profile-rules.md"].encode())
    if p in BUDGET:
        say(blocks and size <= BUDGET[p], "%s: profile-rules.md is %d bytes (budget %d) with %d block(s)" % (p, size, BUDGET[p], len(blocks)))
    if not blocks:
        say(w["profile-rules.md"] == cs.HEADER.format(src="profiles/%s/RULES.md" % p) + src
            and "No on-demand" in w["profile-reference.md"] and "## " not in w["profile-reference.md"],
            "%s: no markers -> profile-rules.md is the source byte for byte, reference says so" % p)

# E. malformed markers never lose text: the whole file stays always-loaded
for label, text in (("unclosed", "a\n<!-- on-demand: T -->\nb\n"), ("stray end", "a\n" + END + "\nb\n"),
                    ("nested", "<!-- on-demand: A -->\n<!-- on-demand: B -->\nx\n" + END + "\n" + END + "\n"),
                    ("empty title", "<!-- on-demand:   -->\nx\n" + END + "\n"), ("empty block", "<!-- on-demand: T -->\n" + END + "\n"),
                    ("duplicate title", "<!-- on-demand: T -->\nx\n" + END + "\n<!-- on-demand: T -->\ny\n" + END + "\n"),
                    ("heading inside", "<!-- on-demand: T -->\nx\n## not a rule\ny\n" + END + "\n")):
    a, b = cs.split_rules(text)
    say(a == text and b == [], "malformed (%s): returned whole and unsplit" % label)
a, b = cs.split_rules("x\n<!-- on-demand: T -->\ny\nw\n" + END + "\nz\n")
say(a == "x\n> ↪ T\nz\n" and b == [("T", "y\nw")], "a well-formed block becomes one stub line and its body")

# sync end to end: the file is written, --check is clean, a profile switch rewrites it
root = project("android", "sw")
sync = os.path.join(D, "scripts", "governance", "context_sync.py")
subprocess.run([sys.executable, sync, root, "--quiet"], check=False)
ref_path = os.path.join(root, ".agents", "context", "profile-reference.md")
first = open(ref_path, encoding="utf-8").read() if os.path.exists(ref_path) else ""
say("## " in first and "Room" in first, "sync writes profile-reference.md with the android blocks")
say(subprocess.run([sys.executable, sync, root, "--check", "--quiet"]).returncode == 0, "--check is clean right after sync")
with open(ref_path, "a", encoding="utf-8") as f:
    f.write("hand edit\n")
r = subprocess.run([sys.executable, sync, root, "--check"], capture_output=True, text=True)
say(r.returncode == 1 and "profile-reference.md" in r.stdout, "--check names a hand-edited profile-reference.md")
subprocess.run([sys.executable, sync, root, "--quiet"], check=False)
project("ios", "sw")
subprocess.run([sys.executable, sync, root, "--quiet"], check=False)
after = open(ref_path, encoding="utf-8").read()
say("Room" not in after and "No on-demand" in after, "after the switch to ios the android blocks are gone from profile-reference.md")

# F. the prompt hook (rule_context.py) names the matching reference section with a working sed range. It is driven off the
# REAL generated profile-reference.md of the android and game profiles: a prompt made of the first three title words of each
# block must name that block, and the printed range must open exactly that section. rules-index.md is absent on purpose
# (rule_context reads each file on its own; hooks/prompt_context.sh still starts it only when rules-index.md exists, which sync always writes).
sys.path.insert(0, os.path.join(D, "scripts", "context"))
import rule_context as rcx

rc = os.path.join(D, "scripts", "context", "rule_context.py")


def hook(root, prompt):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=root)
    env.pop("RULE_CONTEXT", None)
    return subprocess.run([sys.executable, rc], input=json.dumps({"prompt": prompt}), capture_output=True, text=True, env=env).stdout


for p in ("android", "game"):
    hook_root = os.path.join(TMP, "hook-" + p)
    os.makedirs(os.path.join(hook_root, ".agents", "context"), exist_ok=True)
    ref_file = os.path.join(hook_root, ".agents", "context", "profile-reference.md")
    with open(ref_file, "w", encoding="utf-8") as f:
        f.write(cs.wanted(project(p))["profile-reference.md"])
    ref_lines = open(ref_file, encoding="utf-8").read().split("\n")
    bad = []
    for title, _b in split[p][2]:
        toks, seen = [], set()
        for w in re.findall(r"[^\W_]{3,}", title):
            if rcx.words(w) and rcx.fold(w) not in seen:
                seen.add(rcx.fold(w))
                toks.append(w)
        out = hook(hook_root, "sửa " + " ".join(toks[:3]) + " cho tính năng mới")
        got = None
        for m in re.finditer(r"  - (.+?) — `sed -n '(\d+),(\d+)p' (\S+)`", out):
            first = ref_lines[int(m.group(2)) - 1]
            if first == "## " + title and m.group(4) == ".agents/context/profile-reference.md" \
                    and not any(l.startswith("## ") for l in ref_lines[int(m.group(2)):int(m.group(3))]) \
                    and ref_lines[int(m.group(3)) - 1].strip():
                got = True
        if not got:
            bad.append(title[:40])
    say(not bad, "%s: rule_context names every block from three of its title words, range opens that section %s" % (p, bad))

# the body path of profile_hits, on a small file: one EXACT title word plus two body words matches; one body word, or a
# 4-letter prefix of a title word, does not
tiny = ["intro", "## Alpha beta", "gamma delta epsilon", "", "## Crashlytics note", "gamma delta"]
hits = lambda prompt: [t for _s, _l, t, _c in rcx.profile_hits(tiny, rcx.words(prompt))]
say(hits("alpha gamma delta fixing") == ["Alpha beta"], "profile_hits: one exact title word + two body words matches")
say(hits("alpha gamma fixing") == [], "profile_hits: one exact title word + one body word does not match")
say(hits("crash gamma delta") == [], "profile_hits: a title prefix + two body words does not match")
say(hits("crashlytics gamma") != [] and rcx.profile_hits(tiny, rcx.words("alpha gamma delta"))[0][3].endswith("p' .agents/context/profile-reference.md`")
    and "sed -n '2,3p'" in rcx.profile_hits(tiny, rcx.words("alpha gamma delta"))[0][3], "profile_hits: the range stops before the blank line that ends the section")

android_root = os.path.join(TMP, "hook-android")
out = hook(android_root, "fix SAF crash khi mở file từ content uri")
say("§9 SAF" in out and "Analytics" not in out, "rule_context: a SAF prompt gets §9 and not the Crashlytics section (one title word + a crash prefix is not enough)")
say(hook(android_root, "rename the button label on the home screen please") == "", "rule_context is silent when no reference section matches")
say(hook(os.path.join(TMP, "no-such-project"), "fix the Room migration crash after the schema export change") == "",
    "rule_context is silent without profile-reference.md and rules-index.md")
PY

while IFS= read -r line; do
  case "$line" in
    ok\ *)   ok "${line#ok }" ;;
    fail\ *) fail "${line#fail }" ;;
    *)       fail "test script output: $line" ;;
  esac
done < "$TMP/result.txt"
[ -s "$TMP/result.txt" ] || fail "the python half printed nothing"

if [ "$FAILS" -ne 0 ]; then echo "profile_split: $FAILS FAILED"; exit 1; fi
echo "profile_split: all checks passed"
