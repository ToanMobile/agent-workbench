#!/usr/bin/env bash

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$DEVKIT_DIR" <<'PY'
import os, sys, json, re

ROOT = sys.argv[1]
FAILS = 0
PASSES = 0

def ok(msg):
    global PASSES
    print(f"✔ {msg}")
    PASSES += 1

def fail(msg):
    global FAILS
    print(f"✖ {msg}")
    FAILS += 1

skill_path = os.path.join(ROOT, "skills", "taste-mobile-app", "SKILL.md")
if not os.path.isfile(skill_path):
    fail(f"Missing {skill_path}")
else:
    content = open(skill_path, encoding="utf-8").read()
    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            fm = parts[1]
            body = parts[2]
            if "name: taste-mobile-app" not in fm:
                fail("SKILL.md frontmatter missing name")
            else:
                ok("SKILL.md frontmatter name")
            if "disable-model-invocation" in fm:
                fail("SKILL.md frontmatter has disable-model-invocation")
            else:
                ok("SKILL.md frontmatter has no disable-model-invocation")
            
            desc_match = re.search(r"description:\s*(.+)", fm)
            if not desc_match:
                fail("SKILL.md frontmatter missing description")
            else:
                desc = desc_match.group(1)
                if len(desc) > 1024:
                    fail("SKILL.md description > 1024 chars")
                elif "Dùng khi" not in desc or "Bỏ qua khi" not in desc:
                    fail("SKILL.md description missing Dùng khi/Bỏ qua khi")
                else:
                    ok("SKILL.md description valid")
            
            words = len(body.split())
            if words >= 500:
                fail(f"SKILL.md body >= 500 words ({words})")
            else:
                ok("SKILL.md body < 500 words")
            
            phases = [f"Pha {i}" for i in range(1, 8)]
            missing_phases = [p for p in phases if p not in body]
            if missing_phases:
                fail(f"SKILL.md missing phases: {missing_phases}")
            else:
                ok("SKILL.md has 7 phases")
            
            
            import re
            visual_block = body.split("Pha 7:")[-1] if "Pha 7:" in body else body.split("Pha 7")[1] if "Pha 7" in body else ""
            numbered = re.findall(r"(?m)^\s*\d+\.\s", visual_block)
            if len(numbered) < 10:
                fail(f"Pha 7 missing 10 numbered questions (found {len(numbered)})")
            else:
                ok("Pha 7 has 10 numbered questions")
            
            links = re.findall(r"(rules/[a-zA-Z0-9_.-]+|skills/[a-zA-Z0-9_.-]+|profiles/[a-zA-Z0-9_.-]+)", body)
            missing_links = [l for l in links if not os.path.exists(os.path.join(ROOT, l.strip(" .,")))]
            if missing_links:
                fail(f"SKILL.md has broken links: {missing_links}")
            else:
                ok("SKILL.md links valid")
                
            if "orbitextechlab/taste-mobile-app-skill" not in body or "MIT" not in body:
                fail("SKILL.md missing source attribution")
            else:
                ok("SKILL.md source valid")
        else:
            fail("SKILL.md frontmatter malformed")
    else:
        fail("SKILL.md has no frontmatter")

android_rules_path = os.path.join(ROOT, "profiles", "android", "rules", "android-rules.md")
if not os.path.isfile(android_rules_path):
    fail(f"Missing {android_rules_path}")
else:
    android_rules = open(android_rules_path, encoding="utf-8").read()
    required = ["enableEdgeToEdge", "imePadding", "Welcome back", "taste-mobile-app"]
    missing = [r for r in required if r not in android_rules]
    if "4 trạng thái" not in android_rules and "Loading" not in android_rules:
        missing.append("4 trạng thái")
    if missing:
        fail(f"android-rules.md missing: {missing}")
    else:
        ok("android-rules.md valid")

ios_rules_path = os.path.join(ROOT, "profiles", "ios", "rules", "ios-rules.md")
if not os.path.isfile(ios_rules_path):
    fail(f"Missing {ios_rules_path}")
else:
    ios_rules = open(ios_rules_path, encoding="utf-8").read()
    required = ["presentationDetents", "safeAreaInset", "44", "Welcome back", "taste-mobile-app"]
    missing = [r for r in required if r not in ios_rules]
    if missing:
        fail(f"ios-rules.md missing: {missing}")
    else:
        ok("ios-rules.md valid")

cmd_path = os.path.join(ROOT, "commands", "taste-mobile-app.md")
if not os.path.islink(cmd_path):
    fail(f"commands/taste-mobile-app.md is not a symlink")
else:
    target = os.readlink(cmd_path)
    if target != "../skills/taste-mobile-app/SKILL.md":
        fail(f"commands/taste-mobile-app.md points to {target}")
    else:
        ok("commands symlink valid")

import subprocess
script = os.path.join(ROOT, "scripts", "governance", "profile_skills.py")
for prof in ["android", "ios", "automotive", "universal", "backend"]:
    out = subprocess.check_output(["python3", script, prof], text=True)
    if "taste-mobile-app" not in out:
        fail(f"profile_skills.py missing taste-mobile-app for {prof}")
        break
else:
    # game (Unity UI) and web (the skill's own description skips web; 2026-10-09 host install) never get it
    leaked = [p for p in ("game", "web") if "taste-mobile-app" in subprocess.check_output(["python3", script, p], text=True).split()]
    if leaked:
        fail(f"profile_skills.py returned taste-mobile-app for {leaked}")
    else:
        ok("profile_skills.py output valid")

game_prof = os.path.join(ROOT, "profiles", "game", "profile.json")
if not os.path.isfile(game_prof):
    fail(f"Missing {game_prof}")
else:
    try:
        j = json.load(open(game_prof, encoding="utf-8"))
        if "taste-mobile-app" not in j.get("exclude_skills", []):
            fail("game profile.json exclude_skills missing taste-mobile-app")
        else:
            ok("game profile.json exclude_skills valid")
    except Exception as e:
        fail(f"game profile.json invalid JSON: {e}")

agents_path = os.path.join(ROOT, "AGENTS.md")
if not os.path.isfile(agents_path):
    fail(f"Missing {agents_path}")
else:
    agents = open(agents_path, encoding="utf-8").read()
    if "taste-mobile-app" not in agents:
        fail("AGENTS.md missing taste-mobile-app")
    else:
        ok("AGENTS.md valid")

sys.exit(1 if FAILS > 0 else 0)
PY
