#!/usr/bin/env bash
# #1127: enrich_context.mentions() compiled one regex per keyword at EVERY prompt (a fresh process = cold re cache, ~240
# compiles, ~25-45 ms CPU of the 110 ms prompt-hook budget on the macOS CI runner). It must (A) compile no regex and
# (B) answer exactly as the old regex form did.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 -I - "$DEVKIT_DIR/scripts/context" <<'PY'
import re, sys, random
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import enrich_context as E
import re._compiler as C

def old(text, keywords):
    for k in keywords:
        k = E.normalize(k)
        if re.search(r"(?<!\w)" + re.escape(k) + (r"s?(?!\w)" if len(k) <= 3 else ""), text):
            return True
    return False

fails = 0
kws = ["crash", "ui", "pr", "view", "api", "a.b", "tối ưu", "c++", "xml", "s", "ab"]
texts = ["app crashed", "build ui", "uis ok", "PlayerPrefs", "pr", "prs!", "a pr_x", "apis", "x a.b y", "a-b",
         "tối ưu nhất", "c++ code", "xmls", "xmlss", "ss", "s", "abs", "abss", "_ui", "ui_", "viewmodel", "", "ü ui"]
random.seed(1127)
alpha = "abcsiuprxml_ .+é"
texts += ["".join(random.choice(alpha) for _ in range(random.randint(0, 12))) for _ in range(500)]
for t in texts:
    t = E.normalize(t)
    for k in kws + ["pr s", "ui", ""]:
        if old(t, [k]) != E.mentions(t, [k]):
            fails += 1; print("✖ differs", repr(t), repr(k))

n = [0]; real = C.compile
def spy(*a, **k):
    n[0] += 1; return real(*a, **k)
C.compile = spy
re.purge()
E.mentions("app crashed khi mở ui", [f"kw{i}" for i in range(50)] + ["ui", "crash"])
if n[0]:
    fails += 1; print(f"✖ mentions compiled {n[0]} regexes")
else:
    print("✔ no regex compiled")
print("✔ equal to the regex form" if not fails else f"✖ {fails} failures")
sys.exit(1 if fails else 0)
PY
