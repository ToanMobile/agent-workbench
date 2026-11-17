#!/usr/bin/env bash
# #1243: profiles/android keeps every old rule and gains the common rules, performance, quality,
# UI/UX and toolkit sections (Android only). No merged `mobile` profile. Structural checks only.
# Every content check is scoped to the section that owns the value (an Android vitals number that
# only appears in the wrong section does not count). ANDROID_PROFILE_DIR overrides the profile
# directory (used to prove the test goes RED on an altered scratch copy).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
P="${ANDROID_PROFILE_DIR:-profiles/android}"
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }

[ ! -e profiles/mobile ] || fail "profiles/mobile must not exist (owner decision 17/11: android and ios stay separate)"
[ -f "$P/profile.json" ] || fail "$P/profile.json missing"
python3 -I - "$P/profile.json" <<'PY' || exit 1
import json, os, sys
d = json.load(open(sys.argv[1]))
assert d["id"] == "android", "id is %r" % d["id"]
for k in ("name", "description", "description_en"):
    assert d.get(k), "missing " + k
for k in ("rules_file", "regression_matrix"):
    assert os.path.isfile(d[k]), "%s -> %s does not exist" % (k, d[k])
assert d["rules_file"] == "profiles/android/rules/android-rules.md"
assert d["regression_matrix"] == "profiles/android/regression_matrix.json"
councils = d["active_councils"]
assert len(councils) == 9 and len(set(councils)) == 9, "expected 9 distinct councils, got %d" % len(councils)
for c in councils:
    assert os.path.isfile("agents/councils/" + c), "council %s does not resolve" % c
assert "06-game-unity-blender.md" not in councils, "game council does not belong to android"
assert len(d["essential_mcps"]) == len(set(d["essential_mcps"])), "duplicate mcp"
cfg = json.load(open("mcp_config.json"))
servers = cfg.get("mcpServers", cfg)
for m in ("codebase-memory-mcp", "context7", "android-code-search", "android-skills", "mobile-mcp"):
    assert m in d["essential_mcps"], m
for m in d["essential_mcps"]:
    assert m in servers, "mcp %s not in mcp_config.json" % m
for e in (".kt", ".kts", ".java"):
    assert e in d["source_extensions"], e
for e in (".swift", ".m", ".mm"):
    assert e not in d["source_extensions"], "android must not carry " + e
for s in ("android-real-device-qa", "compose-recomp-audit"):
    assert s not in d["exclude_skills"], s
assert "android-principal-architect" not in d["exclude_agents"]
m = json.load(open(d["regression_matrix"]))
assert m["rules"], "matrix empty"
PY
ok "profile.json parses, id android, 9 councils and paths resolve, no profiles/mobile"

R="$P/rules/android-rules.md"
D="$P/DESIGN.md"
[ -f "$R" ] || fail "$R missing"
[ -f "$D" ] || fail "$D missing"
[ "$(readlink "$P/RULES.md" 2>/dev/null)" = "rules/android-rules.md" ] || fail "RULES.md symlink wrong"
[ -f "$P/instincts.md" ] || fail "instincts.md missing"
grep -q 'INSTINCT-AND-14' "$P/instincts.md" || fail "android instincts lost"

python3 -I - "$R" "$D" "$P" <<'PY' || exit 1
import json, os, re, sys

R, D, P = sys.argv[1], sys.argv[2], sys.argv[3]
rules = open(R, encoding="utf-8").read()
design = open(D, encoding="utf-8").read()
LABEL = "mặc định đề xuất của dự án, cần đo trên máy thật"
CHECK = "kiểm lại tài liệu hiện hành"


def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    sys.exit(1)


def section(text, heading_re, where):
    """text of the section from its '## ' heading up to the next '## ' heading."""
    m = re.search(r"(?m)^## " + heading_re + r"(?!\w).*$", text)
    if not m:
        fail("%s: heading '## %s' missing" % (where, heading_re))
    nxt = re.search(r"(?m)^## ", text[m.end():])
    return text[m.start(): m.end() + (nxt.start() if nxt else len(text) - m.end())]


# --- 1. old android rules survive (old phrases, whole file) ----------------------------------------
for ph in ("Disable ngay lập tức", "PendingIntent.FLAG_IMMUTABLE", "SAXNotRecognizedException",
           "Không `runBlocking` trên main", "fallbackToDestructiveMigration", "consumerProguardFiles",
           "takePersistableUriPermission", "collectAsStateWithLifecycle", "Mandatory 4 trạng thái",
           "wiring_pin.py scan"):
    if ph not in rules:
        fail("android rules lost: " + ph)
if "chi tiết ở §13" not in rules or "chi tiết ở §11" in rules:
    fail("§3 Bitmap cross-reference must point to §13")
print("ok: 10 old android rule phrases survive, §3 points to §13")

# --- 2. rules sections 17..21 ------------------------------------------------------------------------
S = {}
for n, title in ((17, "17\\. Bằng chứng"), (18, "18\\. Hiệu năng"), (19, "19\\. Chất lượng"),
                 (20, "20\\. UI/UX"), (21, "21\\. Bộ công cụ")):
    S[n] = section(rules, title, "rules")

# 2a. always-loaded line: outside every on-demand block, no must-word (so it stays loaded)
loaded = re.sub(r"(?s)<!-- on-demand:.*?<!-- /on-demand -->", "", rules)
need_loaded = "Hiệu năng: chỉ máy thật"
line = [l for l in loaded.split("\n") if need_loaded in l]
if not line:
    fail("always-loaded evidence-scope line missing from the loaded part of the rules")
for w in ("AVD chỉ cho ảnh nghiệm thu", "không nới assertion", "không số đo thì không tuyên bố", "§18"):
    if w not in line[0]:
        fail("always-loaded line lacks: " + w)
if re.search(r"BẮT BUỘC|[Bb]ắt buộc|MUST|CẤM|[Cc]ấm|bất biến|Tuyệt đối", line[0]):
    fail("always-loaded line must not carry a must/cấm word")
# the §4 AVD rule and the real-device scope must be reconciled in the loaded text
if "AVD" not in S.get(4, "") and "AVD" not in loaded:
    fail("AVD scope missing")
print("ok: always-loaded evidence-scope line present (AVD for proof only, real device for performance)")

# 2b. §17 is only the always-loaded evidence line; the universal pointers and the Dependency Rule live in §16
s16 = section(rules, "16\\.", "rules")
for w in ("The Dependency Rule", "§1", "§2", "§4", "§19.1", "Domain", "Repository interface"):
    if w not in s16:
        fail("§16 pointer/Dependency Rule block lacks " + w)
for dup in ("Chống Spam & Quản trị Bất đồng bộ", "Bằng chứng Nghiệm thu (Acceptance Gate)", "Soát kỹ `git diff`",
            "Web/Desktop", "Controllers, Presenters", "Separation of Concerns", "Zero-Defect TDD"):
    if dup in rules:
        fail("rules still repeat generic/duplicated universal text: " + dup)

# 2c. §18 budget table: values inside §18, a source or label on every row
s18 = S[18]
rows = [l for l in s18.split("\n") if l.startswith("| ") and not l.startswith("| Chỉ số") and not l.startswith("|---")]
if len(rows) < 15:
    fail("§18 budget table has only %d rows" % len(rows))
SRC = ("Android vitals", "Android developers", "Phép tính", "Nguồn kit", "nguồn kit", "Luật DevKit essentials", LABEL)
for r in rows:
    cells = [c.strip() for c in r.strip().strip("|").split("|")]
    if len(cells) != 4:
        fail("§18 row has %d cells: %s" % (len(cells), r[:60]))
    if not any(s in cells[2] for s in SRC):
        fail("§18 row has no source/label: " + cells[0])


def row(name):
    hit = [r for r in rows if r.split("|")[1].strip().startswith(name)]
    if len(hit) != 1:
        fail("§18 row '%s' expected once, found %d" % (name, len(hit)))
    return hit[0]


def has(r, name, *vals):
    for v in vals:
        if v not in r:
            fail("§18 row '%s' lacks %r" % (name, v))


has(row("Khởi động nguội"), "cold", "Dưới 5 s", "Android vitals", LABEL)
has(row("Khởi động ấm"), "warm", "Dưới 2 s", "Android vitals")
has(row("Khởi động nóng"), "hot", "Dưới 1,5 s", "Android vitals")
has(row("Khung hình 60 Hz"), "60Hz", "16,6 ms", "16 ms")
has(row("Khung hình 120 Hz"), "120Hz", "8,3 ms")
has(row("Khung đóng băng"), "frozen", "700 ms", "Android vitals")
has(row("FPS trung bình"), "fps", "58 FPS", "115 FPS", "5%", "Nguồn kit")
has(row("Jank màn Compose"), "compose jank", "2%", "115 FPS", "Nguồn kit")
has(row("Jank kịch bản cuộn"), "scroll jank", "1%", LABEL)
has(row("ANR — input"), "anr input", "5 s", "Android developers")
has(row("ANR — broadcast"), "anr bcast", "10 s", "Android developers")
has(row("Tỷ lệ ANR"), "anr rate", "0,47%", "1,09%", "8%", CHECK, LABEL)
has(row("Bộ nhớ"), "memory", LABEL)
has(row("Binder"), "binder", "1 MB", "500 KB", "nguồn kit")
has(row("Số method DEX"), "dex", "60.000", "65.536", "Nguồn kit")
has(row("Độ sâu View"), "view depth", "10 tầng", "Nguồn kit")
for w in ("A/B/B/A", "5 cặp", "20%", "inconclusive", "Macrobenchmark", "Perfetto", "StrictMode", "Baseline Profile",
          "adb-safe-exec.sh", "UNTESTED", "máy thật", LABEL):
    if w not in s18:
        fail("§18 lacks " + w)
print("ok: §18 values (vitals, ANR, jank, DEX, view depth, Binder) sit in §18, every row has a source or label")

# 2d. §19 quality
s19 = S[19]
for w in ("Surviving Mutant", "ktlintCheck", "detekt", "lintDebug", "Metalava", "70/20/10", "99,5%", "1,09%", "8%", CHECK,
          "tests > 0", "StandardTestDispatcher", "RED", "GREEN", LABEL):
    if w not in s19:
        fail("§19 lacks " + w)
if re.search(r"cần đo trên dữ liệu", rules) or "cần đo trên máy thật/CI" in rules:
    fail("variant of the proposal label found; use the exact label")

# 2e. §20 UI/UX
s20 = S[20]
for w in ("48×48 dp", "4,5:1", "1.4.11", "200%", "TalkBack", "ANIMATOR_DURATION_SCALE", "80–150 ms", "1000 ms",
          "compact dùng navigation bar", "medium dùng navigation rail", "expanded dùng rail hoặc drawer", CHECK,
          "Material 3", "Zero-Slop", "Dynamic Color", LABEL):
    if w not in s20:
        fail("§20 lacks " + w)

# 2f. §21 toolkit + Cách nghiệm thu
s21 = S[21]
if "Cách nghiệm thu" not in s21:
    fail("§21 lacks 'Cách nghiệm thu'")
acc = s21.split("Cách nghiệm thu", 1)[1]
for w in ("Hiệu năng", "Chất lượng", "UI/UX", "compose-recomp-audit", "tdd-workflow", "real-device-ui-auditor"):
    if w not in acc:
        fail("Cách nghiệm thu lacks " + w)
print("ok: §17 pointers, §19, §20, §21 key values present in the right section")

# --- 3. DESIGN sections 6..16 and the type scale ---------------------------------------------------------
D2 = section(design, "2\\.", "DESIGN")
for w in ("Body Large / Medium / Small", "16sp / 14sp / 12sp", "24sp", "Label Large / Medium / Small", "11sp", "Material 3", CHECK):
    if w not in D2:
        fail("DESIGN §2 lacks " + w)
for old in ("$14\\text{sp} / 16\\text{px}$", "Caption / Label", "Display / Hero"):
    if old in design:
        fail("DESIGN still has the old non-Material type table: " + old)
DS = {}
for n, title in ((6, "6\\. Vùng Chạm"), (7, "7\\. Typography"), (8, "8\\. Chuyển Động"), (9, "9\\. Trạng Thái"),
                 (10, "10\\. Dark Mode"), (11, "11\\. Accessibility"), (12, "12\\. Haptic"), (13, "13\\. Nguyên Tắc UI/UX"),
                 (14, "14\\. Zero-Slop"), (15, "15\\. Hiệu Năng"), (16, "16\\. Chống Spam")):
    DS[n] = section(design, title, "DESIGN")
want = {6: ("48", "minimumInteractiveComponentSize", "8\\text{dp}", LABEL, "WindowInsets"),
        7: ("200\\%", "sp", "Typography", "1.5", LABEL, "stringResource"),
        8: ("80", "300", "ANIMATOR_DURATION_SCALE", LABEL),
        9: ("Loading", "Empty", "Error", "Populated", "0.38", "1000"),
        10: ("MaterialTheme.colorScheme", "isSystemInDarkTheme", "scrim"),
        11: ("4.5:1", "1.4.11", "TalkBack", "contentDescription", "Switch Access"),
        12: ("HapticFeedback", "LocalHapticFeedback"),
        13: ("medium dùng navigation rail", "compact dùng navigation bar", "expanded dùng rail hoặc drawer", CHECK, "FAB", "predictive back"),
        14: ("Card { Card", "#808080", "3", "24"),
        15: ("16.6", "8.3", "700", "58", "115", "LazyColumn", "compose-recomp-audit"),
        16: ("1000", "40")}
for n, vals in want.items():
    for v in vals:
        if v not in DS[n]:
            fail("DESIGN §%d lacks %r" % (n, v))
if re.search(r"\bWeb\b|Hover|SVG", design):
    fail("DESIGN still mentions Web/Hover/SVG")
print("ok: DESIGN §2 Material 3 type scale and §6-§16 values present in their own section")

# --- 4. skill/agent/council names in ALL new sections and DESIGN exist, none excluded -----------------------
prof = json.load(open(os.path.join(P, "profile.json")))
excl = set(prof["exclude_skills"]) | set(prof["exclude_agents"])
path = {"skill": "skills/%s/SKILL.md", "agent": "agents/%s.md", "council": "agents/councils/%s.md"}
tagged = []
for text in (S[17], S[18], S[19], S[20], S[21], design):
    tagged += re.findall(r"`(skill|agent|council):([A-Za-z0-9_-]+)`", text)
prose = re.findall(r"skill `([A-Za-z0-9_-]+)`", design) + re.findall(r"`(?:skill|agent):[A-Za-z0-9_-]+`\s", "")
tagged += [("skill", n) for n in prose]
if not tagged:
    fail("no skill/agent/council reference found")
for k, n in tagged:
    if not os.path.isfile(path[k] % n):
        fail("%s:%s named but not in the kit" % (k, n))
    if n in excl:
        fail("%s excluded by the profile but recommended" % n)
names = {n for _, n in tagged}
for n in ("compose-recomp-audit", "android-real-device-qa", "taste-mobile-app", "ui-ux-pro-max", "impeccable", "qa-visual",
          "tdd-workflow", "qc", "verification-before-completion", "real-device-ui-auditor", "test-architect-seti",
          "mobile-release-auditor", "principal-code-reviewer", "security-checklist", "07-performance-anr"):
    if n not in names:
        fail("toolkit does not mention " + n)
print("ok: %d skill/agent/council references in §17-§21 and DESIGN all exist" % len(tagged))

# --- 5. no other-platform wording anywhere in the android profile ---------------------------------------------
GENERIC = re.compile(r"flutter|\breact\b|react-native|tailwind|unity|swift|xcode|\bapple\b|uikit|voiceover|metrickit|xctest|"
                     r"dynamic type|instruments|\bios\b|\bhover\b|\bsvg\b|\bweb\b|\b44 ?(px|pt)\b|desktop|\bhtml\b", re.I)
IOSJS = re.compile(r"flutter|\breact\b|react-native|tailwind|unity|swift|xcode|\bapple\b|uikit|voiceover|metrickit|xctest|"
                   r"dynamic type|instruments|\bios\b", re.I)
for name, text, rx in (("rules", rules, GENERIC), ("DESIGN", design, GENERIC),
                       ("instincts", open(os.path.join(P, "instincts.md"), encoding="utf-8").read(), IOSJS),
                       ("profile.json descriptions", " ".join(prof[k] for k in ("name", "description", "description_en")), GENERIC)):
    for i, l in enumerate(text.split("\n"), 1):
        if rx.search(l):
            fail("%s:%d has other-platform wording: %s" % (name, i, l[:100]))
for n in (17, 18, 19, 20, 21):
    if re.search(r"\bDOM\b", S[n]):
        fail("§%d mentions DOM" % n)
print("ok: no Flutter/React/Unity/Web/iOS wording in the android profile")
PY
echo "ok: sections, scoped values, labels, names and platform purity checked"
echo "PASS"
