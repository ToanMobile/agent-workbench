#!/usr/bin/env bash
# #1247: profile game has the 3D performance section and the toolkit section,
# every named skill/agent/council exists, the evidence rule is in the LOADED text,
# the on-demand blocks are well formed, every number is labelled, old key rules are untouched.
# The greps run on sections 8 and 9 only (awk from the "## 8." heading to EOF).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
R=profiles/game/rules/game-rules.md
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }
hasall() { grep -qF -- "$1" "$R" || fail "game-rules.md missing: $1"; }

SEC="$(awk '/^## 8\. Hiệu năng 3D/{f=1} f' "$R")"
[ -n "$SEC" ] || fail "missing section '## 8. Hiệu năng 3D'"
has() { printf '%s\n' "$SEC" | grep -qF -- "$1" || fail "sections 8/9 missing: $1"; }

# --- structure: loaded part vs on-demand blocks
LOADED="$(printf '%s\n' "$SEC" | awk '/^<!-- on-demand: /{b=1;next} /^<!-- \/on-demand -->/{b=0;next} !b')"
BLOCKS="$(printf '%s\n' "$SEC" | awk '/^<!-- on-demand: /{b=1;next} /^<!-- \/on-demand -->/{b=0;next} b')"
open=$(printf '%s\n' "$SEC" | grep -c '^<!-- on-demand: ')
close=$(printf '%s\n' "$SEC" | grep -c '^<!-- /on-demand -->')
[ "$open" -ge 1 ] && [ "$open" -eq "$close" ] || fail "on-demand blocks not well formed ($open open, $close close)"
printf '%s\n' "$BLOCKS" | grep -q '^## ' && fail "a '## ' heading sits inside an on-demand block"
printf '%s\n' "$LOADED" | grep -qF 'CHƯA ĐO TRÊN MÁY THẬT' || fail "evidence rule (CHƯA ĐO TRÊN MÁY THẬT) is not in the always-loaded text"
printf '%s\n' "$LOADED" | grep -qF 'máy thật' || fail "loaded one-liner does not mention real device"
has 'Bộ công cụ'
has 'Cách nghiệm thu'

# --- every numbered item 1..12 of section 8 exists
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
  printf '%s\n' "$BLOCKS" | grep -q "^$n\. \*\*" || fail "section 8 item $n missing"
done

# --- topics
for t in '16,7 ms' '33,3 ms' 'SetPass' 'SRP Batcher' 'GPU Instancing' 'Static Batching' \
  'LOD' 'ASTC' 'ETC2' 'mipmap' 'Overdraw' 'transparency' 'shader variants' \
  'Zero-GC' 'pool' 'baked' 'shadow' 'thermal' 'pin' 'Addressables' \
  'Unity Profiler' 'Frame Debugger' 'Memory Profiler' 'Android GPU Inspector' 'Xcode Instruments' \
  'mặc định đề xuất của dự án, cần đo trên máy thật' \
  'early-Z' 'bội số' 'GLES 3.1' 'FPS Regression' '≥ 58' 'iOS' 'Screen.sleepTimeout'; do
  has "$t"
done
printf '%s\n' "$SEC" | grep -qF '16,6 ms' && fail "stale 16,6 ms pin (must be 16,7 to match section 4)"
# batching paths are exclusive and checked in Frame Debugger
printf '%s\n' "$SEC" | grep -F 'loại trừ nhau' | grep -qF 'MaterialPropertyBlock' || fail "item 3 must state the exclusive batching paths and MPB"
# alpha test must not be recommended over alpha blend
printf '%s\n' "$SEC" | grep -qF 'Ưu tiên Opaque hoặc Alpha Test' && fail "stale 'Alpha Test over Alpha Blend' advice"

# --- named skills / agents / councils are in the section and exist
for n in unity-gc-audit game-gc-rendering-auditor 06-game-unity-blender 07-performance-anr ui-ux-pro-max principal-code-reviewer \
  real-device-ui-auditor test-architect-seti tdd-workflow qc verification-before-completion; do
  has "$n"
done
for f in skills/unity-gc-audit/SKILL.md skills/ui-ux-pro-max/SKILL.md skills/qc/SKILL.md skills/tdd-workflow/SKILL.md \
  skills/verification-before-completion/SKILL.md agents/game-gc-rendering-auditor.md agents/principal-code-reviewer.md \
  agents/real-device-ui-auditor.md agents/test-architect-seti.md agents/councils/06-game-unity-blender.md \
  agents/councils/07-performance-anr.md; do
  [ -f "$f" ] || fail "$f missing"
done

# --- every number in section 8 is arithmetic or sits in an item that carries the proposal label or a source tag
python3 -I - "$R" <<'PY' || exit 1
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
sec = text[text.index("## 8. Hiệu năng 3D"):]
ref = re.compile(r"(mục|khoản|§|council|agent|item)\s*\d+(\.\d+)?|\b0[67]-[a-z-]+|\b\d+\.\s\*\*|SRP|URP|IL2CPP|GLES 3\.1|Unity 6|\b[A-Z]\d+\b")
num = re.compile(r"\d+([.,]\d+)?\s*(ms|fps|FPS|bpp|%|B\b|phút|cặp|x\d|dp)|\b\d+x\d+\b|\b\d+\s*(đến|/)\s*\d+")
ok = ("mặc định đề xuất của dự án", "[đặc tả", "[council", "tính toán", "verification-before-completion", "khớp", "mục 4", "mục 6", "council 07")
bad = []
for i, line in enumerate(sec.split("\n"), 1):
    body = ref.sub("", line)
    if num.search(body) and not any(k in line for k in ok):
        bad.append((i, line[:90]))
if bad:
    print("FAIL: numbers without source or proposal label:", bad, file=sys.stderr)
    sys.exit(1)
PY

# --- old key rules must stay (whole file)
for t in 'Application.targetFrameRate' 'OnApplicationPause' 'Cấm tuyệt đối `new`' 'Canvas_Static' \
  'Canvas_Dynamic' 'Hot Path Zero-GC' 'Ngân Sách Khung Hình & DrawCalls' 'MaterialPropertyBlock' \
  'Object Pooling Toàn Diện' 'LoadAssetAsync' 'p95 $\le 16.7\text{ms}$' 'Cổng FPS Regression' 'Visual Proof Gate'; do
  hasall "$t"
done
ok "game 3D performance rules, loaded evidence rule, toolkit section and references present"
