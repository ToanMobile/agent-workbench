#!/usr/bin/env bash
# Kiểm thử xác minh tích hợp skill `impeccable` (v4.7.1, Apache-2.0 + MIT NOTICE)
# vào Universal Agent DevKit:
# 1. SKILL.md hợp lệ (YAML frontmatter <= 1024 ký tự, Dùng khi / Bỏ qua khi), kèm LICENSE + NOTICE.md
# 2. Launcher scripts/impeccable thực thi được, qua `sh -n`, tắt telemetry mặc định, fail-closed khi probe
# 3. Đầy đủ file reference/*.md liên kết từ SKILL.md, command-metadata.json (24 lệnh) và antipatterns.json (>= 60 rule)
# 4. Bản vá bảo mật & quản trị DevKit: Paid calls (billing), cấm đè hook DevKit / cấm .grok/, bảo vệ .adb-denylist Android
# 5. Symlink lệnh slash commands/impeccable.md và .claude/commands/impeccable.md
# 6. Lọc profile (profile_skills.py): bật cho web/android/ios/automotive/universal/voice-assistant, loại khỏi backend/game
# 7. Quy tắc web-rules.md / android-rules.md / ios-rules.md và tài liệu AGENTS.md / README / plugin.json đồng bộ (35 skills)

. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -uo pipefail

DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$DEVKIT_ROOT/skills/impeccable"
SKILL_MD="$SKILL_DIR/SKILL.md"
LAUNCHER="$SKILL_DIR/scripts/impeccable"
PROFILE_SKILLS_PY="$DEVKIT_ROOT/scripts/governance/profile_skills.py"
TMP_OUT="$(mktemp -t test_impeccable.XXXXXX)"
trap 'rm -f "$TMP_OUT"' EXIT

FAILS=0
PASSES=0

pass() {
  echo "  ✔ $1"
  PASSES=$((PASSES + 1))
}

fail() {
  echo "  ✖ FAIL: $1"
  FAILS=$((FAILS + 1))
}

echo "=== Verification: impeccable skill integration ==="

# ---------------------------------------------------------------------------
# 1. SKILL.md frontmatter + bản quyền Apache-2.0 / MIT NOTICE
# ---------------------------------------------------------------------------
if [[ -f "$SKILL_MD" ]]; then
  pass "skills/impeccable/SKILL.md tồn tại"
else
  fail "Thiếu skills/impeccable/SKILL.md"
fi

if [[ -f "$SKILL_DIR/LICENSE" ]] && grep -q "Apache License" "$SKILL_DIR/LICENSE"; then
  pass "skills/impeccable/LICENSE (Apache-2.0) tồn tại"
else
  fail "Thiếu skills/impeccable/LICENSE chuẩn Apache-2.0"
fi

if [[ -f "$SKILL_DIR/NOTICE.md" ]] && grep -q "platform-design-skills" "$SKILL_DIR/NOTICE.md"; then
  pass "skills/impeccable/NOTICE.md (ghi nhận MIT platform-design-skills) tồn tại"
else
  fail "Thiếu skills/impeccable/NOTICE.md"
fi

if [[ -f "$SKILL_MD" ]]; then
  python3 - "$SKILL_MD" >"$TMP_OUT" <<'PY'
import re, sys

text = open(sys.argv[1], encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    print("ERR:missing YAML frontmatter")
    sys.exit(0)
fm = m.group(1)
if "disable-model-invocation: true" in fm:
    print("ERR:disable-model-invocation must not be true")
    sys.exit(0)
name_m = re.search(r"^name:\s*(\S+)\s*$", fm, re.M)
if not name_m or name_m.group(1).strip("\"'") != "impeccable":
    print("ERR:name must be impeccable")
    sys.exit(0)
desc_m = re.search(r"^description:\s*(.+)$", fm, re.M)
if not desc_m:
    print("ERR:missing description")
    sys.exit(0)
desc = desc_m.group(1).strip().strip("\"'")
if len(desc) > 1024:
    print(f"ERR:description too long ({len(desc)} > 1024)")
    sys.exit(0)
if "Dùng khi" not in desc or "Bỏ qua khi" not in desc:
    print("ERR:description must include Dung khi and Bo qua khi")
    sys.exit(0)
print(f"OK:{len(desc)}")
PY
  FM_CHECK="$(cat "$TMP_OUT")"
  if [[ "$FM_CHECK" == OK:* ]]; then
    pass "SKILL.md YAML frontmatter hợp lệ (${FM_CHECK#OK:} ký tự <= 1024)"
  else
    fail "SKILL.md frontmatter lỗi: $FM_CHECK"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Launcher scripts/impeccable: quyền thực thi, sh -n, tắt telemetry, probe
# ---------------------------------------------------------------------------
if [[ -f "$LAUNCHER" && -x "$LAUNCHER" ]]; then
  pass "scripts/impeccable tồn tại và có quyền thực thi (+x)"
else
  fail "scripts/impeccable thiếu hoặc chưa có quyền +x"
fi

if [[ -f "$LAUNCHER" ]] && sh -n "$LAUNCHER" 2>/dev/null; then
  pass "scripts/impeccable đạt kiểm tra cú pháp POSIX sh -n"
else
  fail "scripts/impeccable lỗi cú pháp sh -n"
fi

if [[ -x "$LAUNCHER" ]]; then
  ENV_DUMP="$(env -u IMPECCABLE_NO_TELEMETRY -u DO_NOT_TRACK -u IMPECCABLE_SKILL_DIR IMPECCABLE_BIN="$(command -v env)" "$LAUNCHER" 2>/dev/null || true)"
  # Dùng here-string `<<<` và `-Fqx` thay cho `printf | grep -qx` để không dính SIGPIPE (Broken pipe) dưới `set -uo pipefail` (#780)
  if grep -Fqx 'IMPECCABLE_NO_TELEMETRY=1' <<<"$ENV_DUMP" \
    && grep -Fqx 'DO_NOT_TRACK=1' <<<"$ENV_DUMP" \
    && grep -Fqx -- "IMPECCABLE_SKILL_DIR=$SKILL_DIR" <<<"$ENV_DUMP"; then
    pass "scripts/impeccable thực sự export IMPECCABLE_NO_TELEMETRY=1, DO_NOT_TRACK=1 và IMPECCABLE_SKILL_DIR khi exec"
  else
    fail "scripts/impeccable không export đủ biến môi trường bảo mật khi chạy thực tế"
  fi
fi

if [[ -f "$LAUNCHER" ]] && grep -q -- '--connect-timeout 10' "$LAUNCHER" && grep -q -- '-T 15' "$LAUNCHER"; then
  pass "scripts/impeccable có giới hạn network timeout tường minh cho curl và wget"
else
  fail "scripts/impeccable thiếu giới hạn network timeout tường minh"
fi

if [[ -x "$LAUNCHER" ]]; then
  set +e
  HOME=/nonexistent IMPECCABLE_HOME=/nonexistent IMPECCABLE_LAUNCHER_PROBE=1 IMPECCABLE_BIN=/nonexistent "$LAUNCHER" engine-probe >/dev/null 2>&1
  PROBE_RC=$?
  set -u
  if [[ "$PROBE_RC" -eq 127 ]]; then
    pass "scripts/impeccable thoát an toàn (exit 127, không tải mạng) khi chạy probe cô lập"
  else
    fail "scripts/impeccable trả mã $PROBE_RC thay vì 127 khi chạy probe cô lập"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Tính toàn vẹn reference/*.md và dữ liệu JSON (command-metadata + antipatterns)
# ---------------------------------------------------------------------------
python3 - "$SKILL_DIR" >"$TMP_OUT" <<'PY'
import json, pathlib, re, sys

skill_dir = pathlib.Path(sys.argv[1])
skill_md = skill_dir / "SKILL.md"
if not skill_md.is_file():
    print("ERR:no SKILL.md")
    sys.exit(0)

body = skill_md.read_text(encoding="utf-8")
links = sorted(set(re.findall(r"\((reference/[A-Za-z0-9._-]+)(?:#[^)]+)?\)", body)))
if len(links) < 20:
    print(f"ERR:expected >= 20 reference links in SKILL.md, got {len(links)}")
    sys.exit(0)
missing = [rel for rel in links if not (skill_dir / rel).is_file() or (skill_dir / rel).stat().st_size == 0]
if missing:
    print("ERR:missing reference files: " + ", ".join(missing))
    sys.exit(0)

cmd_meta = skill_dir / "scripts" / "command-metadata.json"
if not cmd_meta.is_file():
    print("ERR:missing scripts/command-metadata.json")
    sys.exit(0)
cmds = json.loads(cmd_meta.read_text(encoding="utf-8"))
if len(cmds) < 24:
    print(f"ERR:expected >= 24 commands in command-metadata.json, got {len(cmds)}")
    sys.exit(0)

ap_json = skill_dir / "scripts" / "data" / "antipatterns.json"
if not ap_json.is_file():
    print("ERR:missing scripts/data/antipatterns.json")
    sys.exit(0)
ap = json.loads(ap_json.read_text(encoding="utf-8"))
if not isinstance(ap, list):
    print("ERR:antipatterns.json must be a JSON array")
    sys.exit(0)
slop_count = sum(1 for r in ap if isinstance(r, dict) and r.get("category") == "slop")
quality_count = sum(1 for r in ap if isinstance(r, dict) and r.get("category") == "quality")
rules_count = len(ap)
if rules_count < 60 or slop_count == 0 or quality_count == 0:
    print(f"ERR:expected >= 60 detector rules (slop+quality), got total={rules_count}, slop={slop_count}, quality={quality_count}")
    sys.exit(0)

print(f"OK:refs={len(links)},cmds={len(cmds)},rules={rules_count}(slop={slop_count},quality={quality_count})")
PY
REF_CHECK="$(cat "$TMP_OUT")"
if [[ "$REF_CHECK" == OK:* ]]; then
  pass "Liên kết reference/*.md và kho rule JSON đầy đủ (${REF_CHECK#OK:})"
else
  fail "Kiểm tra reference/JSON thất bại: $REF_CHECK"
fi

# ---------------------------------------------------------------------------
# 4. Bản vá bảo mật & quản trị DevKit (Billing, Hooks/.grok, Android .adb-denylist)
# ---------------------------------------------------------------------------
python3 - "$SKILL_DIR" >"$TMP_OUT" <<'PY'
import pathlib, re, sys

skill_dir = pathlib.Path(sys.argv[1])
if not skill_dir.is_dir():
    print("ERR:missing skill_dir")
    sys.exit(0)

bad_billing = re.compile(r"owner's consent|key is consent|no per-call question", re.I)
for p in skill_dir.rglob("*.md"):
    txt = p.read_text(encoding="utf-8")
    if bad_billing.search(txt):
        print(f"ERR:forbidden auto-spend phrase in {p.relative_to(skill_dir)}")
        sys.exit(0)

for rel in ("SKILL.md", "reference/visualize.md", "agents/impeccable-asset-producer.md"):
    f = skill_dir / rel
    if not f.is_file() or "Paid calls (DevKit" not in f.read_text(encoding="utf-8"):
        print(f"ERR:missing Paid calls (DevKit billing guard in {rel}")
        sys.exit(0)

for rel in ("SKILL.md", "reference/hooks.md"):
    f = skill_dir / rel
    txt = f.read_text(encoding="utf-8") if f.is_file() else ""
    if "DevKit hook" not in txt or ".grok" not in txt:
        print(f"ERR:missing DevKit hook coexistence / .grok guard in {rel}")
        sys.exit(0)

android_ref = skill_dir / "reference" / "android.md"
android_txt = android_ref.read_text(encoding="utf-8") if android_ref.is_file() else ""
if ".adb-denylist" not in android_txt or "proof-capture.py" not in android_txt or "adb-safe-exec.sh" not in android_txt:
    print("ERR:reference/android.md missing .adb-denylist / proof-capture.py / adb-safe-exec.sh guard")
    sys.exit(0)

print("OK")
PY
GOV_CHECK="$(cat "$TMP_OUT")"
if [[ "$GOV_CHECK" == "OK" ]]; then
  pass "Đủ 3 lớp bảo vệ quản trị DevKit (Paid API consent, Hook/.grok guard, Android .adb-denylist)"
else
  fail "Thiếu lớp bảo vệ quản trị DevKit: $GOV_CHECK"
fi

# ---------------------------------------------------------------------------
# 5. Symlink commands/impeccable.md và .claude/commands/impeccable.md
# ---------------------------------------------------------------------------
CMD_LINK="$DEVKIT_ROOT/commands/impeccable.md"
CLAUDE_CMD_LINK="$DEVKIT_ROOT/.claude/commands/impeccable.md"

if [[ -L "$CMD_LINK" && "$(readlink "$CMD_LINK")" == "../skills/impeccable/SKILL.md" ]]; then
  pass "commands/impeccable.md trỏ tương đối tới ../skills/impeccable/SKILL.md"
else
  fail "commands/impeccable.md thiếu hoặc sai đích symlink"
fi

if [[ -L "$CLAUDE_CMD_LINK" && "$(readlink "$CLAUDE_CMD_LINK")" == "../../commands/impeccable.md" ]]; then
  pass ".claude/commands/impeccable.md trỏ tương đối tới ../../commands/impeccable.md"
else
  fail ".claude/commands/impeccable.md thiếu hoặc sai đích symlink"
fi

# ---------------------------------------------------------------------------
# 6. Lọc skill theo profile (profile_skills.py)
# ---------------------------------------------------------------------------
# Dùng here-string `<<<` thay cho `printf | grep -qx` để tránh SIGPIPE làm đỏ oan ở vòng kiểm profile UI hoặc lọt lỗi giả ở nhánh elif loại trừ (#780)
for prof in web android ios automotive universal voice-assistant; do
  if PROF_OUT="$(python3 "$PROFILE_SKILLS_PY" "$prof" 2>&1)" && grep -Fqx "impeccable" <<<"$PROF_OUT"; then
    pass "profile_skills.py bao gồm impeccable cho profile '$prof'"
  else
    fail "profile_skills.py thiếu impeccable cho profile '$prof'"
  fi
done

for prof in backend game; do
  if ! PROF_OUT="$(python3 "$PROFILE_SKILLS_PY" "$prof" 2>&1)"; then
    fail "profile_skills.py lỗi khi chạy với profile '$prof': $PROF_OUT"
  elif grep -Fqx "impeccable" <<<"$PROF_OUT"; then
    fail "profile_skills.py KHÔNG ĐƯỢC bao gồm impeccable cho profile '$prof'"
  else
    pass "profile_skills.py loại trừ đúng impeccable khỏi profile '$prof'"
  fi
done

# ---------------------------------------------------------------------------
# 7. Luật domain (web-rules, android-rules, ios-rules) & tài liệu (35 skills)
# ---------------------------------------------------------------------------
WEB_RULES="$DEVKIT_ROOT/profiles/web/rules/web-rules.md"
if grep -q "impeccable" "$WEB_RULES" && grep -q "65–75ch" "$WEB_RULES" && grep -q "\.impeccable/" "$WEB_RULES"; then
  pass "profiles/web/rules/web-rules.md bổ sung chuẩn Craft Floor & Anti-Slop của impeccable"
else
  fail "profiles/web/rules/web-rules.md thiếu chuẩn Craft Floor & Anti-Slop của impeccable"
fi

for rule_doc in \
  "$DEVKIT_ROOT/profiles/android/rules/android-rules.md" \
  "$DEVKIT_ROOT/profiles/ios/rules/ios-rules.md" \
  "$DEVKIT_ROOT/AGENTS.md" \
  "$DEVKIT_ROOT/README.md" \
  "$DEVKIT_ROOT/README.vi.md" \
  "$DEVKIT_ROOT/.claude-plugin/plugin.json"
do
  rel="${rule_doc#$DEVKIT_ROOT/}"
  if grep -q "impeccable" "$rule_doc"; then
    pass "$rel có tham chiếu tới impeccable"
  else
    fail "$rel chưa tham chiếu tới impeccable"
  fi
done

# ---------------------------------------------------------------------------
# 8. Smart On-Demand Routing trong enrich_context.py (chỉ bật khi làm đẹp/thiết kế UI)
# ---------------------------------------------------------------------------
ENRICH_PY="$DEVKIT_ROOT/scripts/context/enrich_context.py"
python3 - "$ENRICH_PY" "$DEVKIT_ROOT" >"$TMP_OUT" <<'PY'
import importlib.util, os, sys, tempfile

spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ec)
devkit_root = sys.argv[2]

with tempfile.TemporaryDirectory() as tmp:
    def skills_for(profile, prompt):
        pdir = os.path.join(tmp, profile)
        os.makedirs(os.path.join(pdir, ".agents"), exist_ok=True)
        with open(os.path.join(pdir, ".agents", "active-profile.json"), "w", encoding="utf-8") as fh:
            fh.write(f'{{"profile": "{profile}"}}\n')
        d = ec.enrich_prompt(prompt, devkit_root, pdir)
        return d["recommended_skills"], ec.compact(d, pdir)

    for prof in ("web", "android", "ios"):
        sk, out = skills_for(prof, "thiết kế lại giao diện màn hình đăng nhập, chống AI slop")
        if "impeccable" not in sk or "impeccable" not in out:
            print(f"ERR:{prof} UI craft prompt missing impeccable: {sk}")
            sys.exit(0)

    sk_polish, out_polish = skills_for("web", "polish và typeset lại trang dashboard cho đẹp")
    if "impeccable" not in sk_polish or "impeccable" not in out_polish:
        print(f"ERR:web polish/typeset prompt missing impeccable: {sk_polish}")
        sys.exit(0)

    sk_ux, out_ux = skills_for("ios", "cải thiện ui/ux và bảng màu cho màn hình thanh toán")
    if "impeccable" not in sk_ux or "impeccable" not in out_ux:
        print(f"ERR:ios ui/ux prompt missing impeccable: {sk_ux}")
        sys.exit(0)

    for prof in ("backend", "game"):
        sk_ex, _ = skills_for(prof, "thiết kế lại giao diện màn hình đăng nhập, polish UI")
        if "impeccable" in sk_ex:
            print(f"ERR:{prof} profile should exclude impeccable: {sk_ex}")
            sys.exit(0)

    sk_bug, _ = skills_for("web", "sửa lỗi bấm nút ký không gọi API")
    if "impeccable" in sk_bug:
        print(f"ERR:plain bug fix prompt should NOT trigger impeccable: {sk_bug}")
        sys.exit(0)

print("OK")
PY
ROUTE_CHECK="$(cat "$TMP_OUT")"
if [[ "$ROUTE_CHECK" == "OK" ]]; then
  pass "enrich_context.py tự động gợi ý impeccable đúng ngữ cảnh thiết kế/polish UI (Smart On-Demand)"
else
  fail "enrich_context.py định tuyến Smart On-Demand lỗi: $ROUTE_CHECK"
fi

echo ""
if [[ "$FAILS" -gt 0 ]]; then
  echo "FAILED: $FAILS lỗi ($PASSES kiểm tra đạt)"
  exit 1
fi
echo "ALL $PASSES CHECKS PASSED"
exit 0
