#!/usr/bin/env bash
# #1247: profile game has the 3D performance section and the toolkit section,
# every named skill/agent/council exists, and the old key rules are untouched.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DK" || exit 2
R=profiles/game/rules/game-rules.md
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }
has() { grep -qF -- "$1" "$R" || fail "game-rules.md missing: $1"; }

grep -q '^## [0-9]*\. Hiệu năng 3D' "$R" || fail "missing section 'Hiệu năng 3D'"
grep -q '^## [0-9]*\. Bộ công cụ' "$R" || fail "missing section 'Bộ công cụ'"
for t in '16,6 ms' '33,3 ms' 'SetPass' 'SRP Batcher' 'GPU Instancing' 'Static Batching' \
  'LOD' 'ASTC' 'ETC2' 'mipmap' 'Overdraw' 'transparency' 'shader variants' \
  'Zero-GC' 'pool' 'baked' 'shadow' 'thermal' 'pin' 'Addressables' \
  'Unity Profiler' 'Frame Debugger' 'Memory Profiler' 'Android GPU Inspector' 'Xcode Instruments' \
  'CHƯA ĐO TRÊN MÁY THẬT' 'mặc định đề xuất của dự án, cần đo trên máy thật'; do
  has "$t"
done
has 'Cách nghiệm thu'
for n in unity-gc-audit game-gc-rendering-auditor 06-game-unity-blender 07-performance-anr ui-ux-pro-max principal-code-reviewer \
  real-device-ui-auditor test-architect-seti tdd-workflow qc verification-before-completion; do
  has "$n"
done
[ -f skills/unity-gc-audit/SKILL.md ] || fail "skill unity-gc-audit missing"
[ -f skills/ui-ux-pro-max/SKILL.md ] || fail "skill ui-ux-pro-max missing"
[ -f agents/game-gc-rendering-auditor.md ] || fail "agent game-gc-rendering-auditor missing"
[ -f agents/principal-code-reviewer.md ] || fail "agent principal-code-reviewer missing"
for f in skills/qc/SKILL.md skills/tdd-workflow/SKILL.md skills/verification-before-completion/SKILL.md \
  agents/real-device-ui-auditor.md agents/test-architect-seti.md; do
  [ -f "$f" ] || fail "$f missing"
done
[ -f agents/councils/06-game-unity-blender.md ] || fail "council 06 missing"
[ -f agents/councils/07-performance-anr.md ] || fail "council 07 missing"
for t in 'Application.targetFrameRate' 'OnApplicationPause' 'Cấm tuyệt đối `new`' 'Canvas_Static' \
  'Canvas_Dynamic' 'Hot Path Zero-GC' 'Ngân Sách Khung Hình & DrawCalls' 'MaterialPropertyBlock' \
  'Object Pooling Toàn Diện' 'LoadAssetAsync'; do
  has "$t"
done
ok "game 3D performance rules, toolkit section and references present"
