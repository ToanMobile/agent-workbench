#!/usr/bin/env bash
# Every model-visible skill/command description is listed in the system prompt of every session and subagent
# (measured 02/11/2026 over 107+136 transcripts: the skill listing was ~8.5 % of context). A description says
# WHEN to use the skill; how it works belongs in the body, which loads only on invoke. Cap per description,
# in UTF-8 bytes (Vietnamese is multi-byte). Covers the kit's skills/*/SKILL.md and commands/*.md and the
# project's .claude/skills/*/SKILL.md; symlinks are skipped (their target is checked), as are entries with
# disable-model-invocation: true (not listed). A ratchet: lower MAX_BYTES when every description fits.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(cd "$DK/.." && pwd)"
MAX_BYTES=300

python3 -I - "$MAX_BYTES" "$DK" "$ROOT" <<'PY'
import glob, os, re, sys

cap, dk, root = int(sys.argv[1]), sys.argv[2], sys.argv[3]
files = sorted(glob.glob(os.path.join(dk, "skills", "*", "SKILL.md")) + glob.glob(os.path.join(dk, "commands", "*.md"))
               + glob.glob(os.path.join(root, ".claude", "skills", "*", "SKILL.md")))
files = [p for p in files if not os.path.islink(p)]
if not files:
    print("✖ no SKILL.md / command found")
    sys.exit(1)


def scalar(raw):
    """The value the model sees: a plain, quoted or block (> / |) YAML scalar, not its raw YAML spelling."""
    lines = raw.strip().split("\n")
    head = lines[0].strip()
    if head[:1] in (">", "|"):
        return " ".join(l.strip() for l in lines[1:] if l.strip())
    v = " ".join(l.strip() for l in lines if l.strip())
    if len(v) >= 2 and v[0] == v[-1] == '"':
        return v[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    if len(v) >= 2 and v[0] == v[-1] == "'":
        return v[1:-1].replace("''", "'")
    return v


bad, empty, checked = [], [], 0
for p in files:
    with open(p, encoding="utf-8") as f:
        text = f.read().replace("\r", "")
    m = re.match(r"---\n(.*?)\n---", text, re.S)
    if not m:
        continue   # no frontmatter (commands/unity-test.md): nothing is listed
    fm = m.group(1)
    if re.search(r"^disable-model-invocation:\s*true\b", fm, re.M):
        continue
    d = re.search(r"^description:[ \t]*(.*?)(?=^[\w-]+:|\Z)", fm, re.S | re.M)
    desc = scalar(d.group(1)) if d else ""
    rel = os.path.relpath(p, root)
    if not desc:
        empty.append(rel)
        continue
    checked += 1
    n = len(desc.encode("utf-8"))
    if n > cap:
        bad.append((n, rel))
for p in empty:
    print(f"✖ {p}: frontmatter without a description (the listing shows nothing to choose it by)")
for n, p in sorted(bad, reverse=True):
    print(f"✖ {p}: description {n} bytes (budget {cap})")
bad += empty
print(f"{checked} descriptions checked, {len(bad)} over {cap} bytes")
sys.exit(1 if bad else 0)
PY
