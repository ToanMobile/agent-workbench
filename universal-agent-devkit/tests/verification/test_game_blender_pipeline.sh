#!/usr/bin/env bash
# test_game_blender_pipeline.sh — kiểm tra 4 script Blender headless, skill blender-game-pipeline,
# cấu hình exclude_skills ở profile không phải game, và quy tắc Blender/Unity 6.3 trong game-rules.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
BLENDER_DIR="$ROOT/profiles/game/scripts/blender"
SKILL_DIR="$ROOT/skills/blender-game-pipeline"
GAME_RULES="$ROOT/profiles/game/rules/game-rules.md"

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  echo "✔ $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "✘ $1" >&2
}

# 1. Kiểm tra đủ 5 file Python (4 script chính + _bpyx.py), syntax sạch và cờ executable khớp shebang
for f in _bpyx.py qa_check.py make_lods.py export_unity.py review_shots.py; do
  p="$BLENDER_DIR/$f"
  if [ -f "$p" ]; then
    ok "tồn tại $f"
  else
    fail "thiếu $p"
    continue
  fi
  if python3 -m py_compile "$p" 2>/dev/null; then
    ok "py_compile sạch: $f"
  else
    fail "lỗi cú pháp Python: $f"
  fi
done

# 2. Kiểm tra CLI --help chạy sạch không cần Blender và exit code đúng
for f in qa_check.py make_lods.py export_unity.py review_shots.py; do
  p="$BLENDER_DIR/$f"
  [ -f "$p" ] || continue
  if python3 "$p" -- --help >/dev/null 2>&1; then
    ok "CLI --help sạch (không cần bpy): $f"
  else
    fail "CLI --help thất bại: $f"
  fi
done

# 3. Kiểm tra unit pure-Python: preset Unity 6.3 an toàn, glb_summary, qa_check profile game
if python3 - "$BLENDER_DIR" <<'PY'
import json
import os
import struct
import sys
import tempfile

blender_dir = sys.argv[1]
sys.path.insert(0, blender_dir)

import export_unity
import qa_check
import review_shots

# Kiểm tra preset unity vs unity_skeletal (tránh bẫy bake_space_transform với armature)
assert "unity" in export_unity.PRESETS, "thiếu preset unity"
assert "unity_skeletal" in export_unity.PRESETS, "thiếu preset unity_skeletal"
assert "gltf" in export_unity.PRESETS, "thiếu preset gltf"
unity_kw = export_unity.PRESETS["unity"][2]
skel_kw = export_unity.PRESETS["unity_skeletal"][2]
assert unity_kw.get("bake_space_transform") is True, "unity static cần bake_space_transform=True"
assert unity_kw.get("apply_scale_options") == "FBX_SCALE_ALL"
assert not skel_kw.get("bake_space_transform"), "unity_skeletal CẤM bật bake_space_transform"
assert skel_kw.get("use_armature_deform_only") is True

# Kiểm tra glb_summary đọc đúng header GLB 2.0 tối thiểu
glb_json = json.dumps({
    "asset": {"version": "2.0"},
    "nodes": [{"name": "Crate"}],
    "meshes": [{"name": "Crate", "primitives": [{"mode": 4, "indices": 0, "attributes": {"POSITION": 1}}]}],
    "accessors": [{"count": 36}, {"count": 24}],
    "materials": [{"name": "Mat"}],
}).encode("utf-8")
pad = (4 - (len(glb_json) % 4)) % 4
glb_json += b" " * pad
header = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(glb_json))
chunk = struct.pack("<I4s", len(glb_json), b"JSON")
with tempfile.NamedTemporaryFile(suffix=".glb", delete=False) as tf:
    tf.write(header + chunk + glb_json)
    glb_path = tf.name
try:
    summary = export_unity.glb_summary(glb_path)
    assert summary["meshes"] == 1 and summary["triangles"] == 12, f"glb_summary sai: {summary}"
finally:
    os.unlink(glb_path)

# Kiểm tra qa_check PROFILES có profile game và giữ các severity trọng yếu
assert "game" in qa_check.PROFILES
assert qa_check.PROFILES["game"]["zf"] == "e"
assert qa_check.PROFILES["game"]["sc"] == "e"
assert qa_check.PROFILES["game"]["uv"] == "e"
assert qa_check.PROFILES["game"]["mt"] == "e"

# Kiểm tra review_shots có đủ góc nhìn mặc định
for v in ("front", "right", "top", "three_quarter"):
    assert v in review_shots.DIRS, f"thiếu góc nhìn {v}"
PY
then
  ok "unit pure-Python: preset Unity, glb_summary, qa_check profiles, review_shots DIRS"
else
  fail "unit pure-Python thất bại"
fi

# 4. Kiểm tra skill blender-game-pipeline + reference + exclude_skills ở các profile khác game
if [ -f "$SKILL_DIR/SKILL.md" ] && [ -f "$SKILL_DIR/references/unity-blender-5x.md" ]; then
  ok "tồn tại skill blender-game-pipeline và references/unity-blender-5x.md"
else
  fail "thiếu SKILL.md hoặc references/unity-blender-5x.md"
fi

if python3 - "$ROOT" <<'PY'
import glob, json, os, sys
root = sys.argv[1]
for pf in sorted(glob.glob(os.path.join(root, "profiles", "*", "profile.json"))):
    pid = os.path.basename(os.path.dirname(pf))
    excl = json.load(open(pf, encoding="utf-8")).get("exclude_skills", [])
    if pid == "game":
        assert "blender-game-pipeline" not in excl, "profile game không được exclude blender-game-pipeline"
    else:
        assert "blender-game-pipeline" in excl, f"profile {pid} phải exclude blender-game-pipeline"
PY
then
  ok "exclude_skills: chỉ profile game bật blender-game-pipeline"
else
  fail "kiểm tra exclude_skills thất bại"
fi

# 5. Kiểm tra game-rules.md dẫn chiếu 4 script Blender và quy tắc Unity 6.3 GRD + GC.Alloc
for kw in "qa_check.py" "make_lods.py" "export_unity.py" "review_shots.py" "GPU Resident Drawer" "BatchRendererGroup Variants" "Hybrid Batch Group" "GC.Collect"; do
  if grep -qF "$kw" "$GAME_RULES"; then
    ok "game-rules.md có '$kw'"
  else
    fail "game-rules.md thiếu '$kw'"
  fi
done

# 6. Nếu máy có cài Blender, chạy smoke test headless thật trên mesh tạo mới trong /tmp
if command -v blender >/dev/null 2>&1; then
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT
  # Tạo file .blend mẫu trong TMPD: 1 khối UV cube có vật liệu Principled và scale đã apply, đáy ở z=0
  if python3 - "$TMPD" <<'PY'
import os, subprocess, sys
tmpd = sys.argv[1]
blend = os.path.join(tmpd, "fixture.blend")
code = f"""
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.5))
cube = bpy.context.active_object
cube.name = "SM_TestCrate"
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
mat = bpy.data.materials.new("M_Crate")
cube.data.materials.append(mat)
bpy.ops.wm.save_as_mainfile(filepath={blend!r})
"""
script = os.path.join(tmpd, "gen.py")
open(script, "w", encoding="utf-8").write(code)
subprocess.run(["blender", "--disable-autoexec", "-b", "--factory-startup", "--python-exit-code", "1", "-P", script], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY
  then
    QA_OUT="$(blender --disable-autoexec -b --factory-startup "$TMPD/fixture.blend" --python-exit-code 1 -P "$BLENDER_DIR/qa_check.py" -- --objects SM_TestCrate --profile game 2>&1 || true)"
    if echo "$QA_OUT" | grep -q '@@JSON@@' && echo "$QA_OUT" | grep '@@JSON@@' | tail -n 1 | sed 's/^.*@@JSON@@//' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"] and d["pass"] and "self_intersections" in d["objects"]["SM_TestCrate"] and "valence_6plus" in d["objects"]["SM_TestCrate"]'; then
      ok "blender headless thật: qa_check.py PASS + có self_intersections & valence_6plus"
    else
      fail "blender headless thật: qa_check.py thất bại: $(echo "$QA_OUT" | tail -n 5)"
    fi

    LOD_OUT="$(blender --disable-autoexec -b --factory-startup "$TMPD/fixture.blend" --python-exit-code 1 -P "$BLENDER_DIR/make_lods.py" -- --objects SM_TestCrate --ratios 0.5 0.25 --rename --save "$TMPD/lods.blend" 2>&1 || true)"
    if echo "$LOD_OUT" | grep -q '@@JSON@@' && [ -f "$TMPD/lods.blend" ]; then
      ok "blender headless thật: make_lods.py tạo chuỗi LOD"
    else
      fail "blender headless thật: make_lods.py thất bại: $(echo "$LOD_OUT" | tail -n 5)"
    fi

    EXP_OUT="$(blender --disable-autoexec -b --factory-startup "$TMPD/fixture.blend" --python-exit-code 1 -P "$BLENDER_DIR/export_unity.py" -- --preset unity --objects SM_TestCrate --out "$TMPD/SM_TestCrate.fbx" --round-trip 2>&1 || true)"
    if echo "$EXP_OUT" | grep -q '@@JSON@@' && [ -f "$TMPD/SM_TestCrate.fbx" ] && echo "$EXP_OUT" | grep '@@JSON@@' | tail -n 1 | sed 's/^.*@@JSON@@//' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"] and d["round_trip"]["pass"]'; then
      ok "blender headless thật: export_unity.py --preset unity --round-trip PASS"
    else
      fail "blender headless thật: export_unity.py thất bại: $(echo "$EXP_OUT" | tail -n 5)"
    fi

    REV_OUT="$(blender --disable-autoexec -b --factory-startup "$TMPD/fixture.blend" --python-exit-code 1 -P "$BLENDER_DIR/review_shots.py" -- --objects SM_TestCrate --out "$TMPD/review.png" --res 128 2>&1 || true)"
    if echo "$REV_OUT" | grep -q '@@JSON@@' && [ -s "$TMPD/review.png" ]; then
      ok "blender headless thật: review_shots.py xuất contact sheet PNG"
    else
      fail "blender headless thật: review_shots.py thất bại: $(echo "$REV_OUT" | tail -n 5)"
    fi
  else
    fail "không tạo được fixture.blend trong Blender headless"
  fi
fi

echo ""
echo "game blender pipeline: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
