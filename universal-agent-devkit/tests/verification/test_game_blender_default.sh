#!/usr/bin/env bash
# Regression test: in the game profile Blender 3D is the only source of every asset.
#
# User, 2026-10-15: "remove toàn bộ 2d, mặc định là sử dụng blender 3d cho tất cả assets".
# Before this change the profile forbade flat 2D for 4 props only; render_game_prop.py drew a
# silent sphere for any other --prop (trophy and potion were advertised but never built);
# capture_3d_proof.py DREW a 2D coin with PIL when Blender failed and reported success;
# validate-assets.sh let .blend files and hand-drawn 2D sources into Assets/.
#
# Sections: A real Blender (render_game_prop.py), B validate-assets.sh fixtures,
# C capture_3d_proof.py with a failing Blender, D the rule/profile/council text.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GAME="$DEVKIT_DIR/profiles/game"
PROP="$GAME/scripts/render_game_prop.py"
VALIDATE="$GAME/hooks/validate-assets.sh"
PROOF="$DEVKIT_DIR/scripts/testing/capture_3d_proof.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
skip() { echo "⚠ SKIP $1"; }

BLENDER="$(command -v blender || true)"
[ -z "$BLENDER" ] && [ -x /Applications/Blender.app/Contents/MacOS/Blender ] && BLENDER=/Applications/Blender.app/Contents/MacOS/Blender

frame_of() {  # $1 = PNG: "inside" when the opaque part keeps a margin to every edge, else "cropped (bbox)"
  python3 -I -c "
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGBA'); w, h = im.size
box = im.getchannel('A').getbbox()
print('inside' if box and box[0] > 0 and box[1] > 0 and box[2] < w and box[3] < h else 'cropped %s' % (box,))" "$1"
}

fill_of() {  # $1 = PNG: the fraction of opaque pixels, e.g. 0.29
  python3 -I -c "
import sys
from PIL import Image
a = Image.open(sys.argv[1]).convert('RGBA').getchannel('A')
print('%.2f' % (a.point(lambda v: 255 if v else 0).histogram()[255] / float(a.size[0] * a.size[1])))" "$1"
}
need_png() {  # need_png <label> <png>: 0 when PIL is there AND the fixture rendered; no PIL = SKIP, no PNG = FAIL (never a quiet skip)
  if ! python3 -I -c "import PIL" 2>/dev/null; then skip "$1 no PIL, the PNG is not measured"; return 1; fi
  if [ ! -s "$2" ]; then fail "$1 the fixture did not render (a regression of the render step would hide behind a skip)"; return 1; fi
  return 0
}

# ---------- A. render_game_prop.py (real Blender) ----------
if [ -z "$BLENDER" ]; then
  skip "A: no Blender on this machine, render_game_prop.py not exercised"
else
  OUT="$("$BLENDER" -b --python-expr "
import sys
sys.path.insert(0, r'$GAME/scripts')
import render_game_prop as r
names = []
for p in ('trophy', 'potion'):
    r.clean_scene()
    names.append(r.build_prop(p, 'gold').name)
print('PROPS', *names)
r.clean_scene()
try:
    r.build_prop('nonsense', 'gold')
    print('UNKNOWN_RETURNED')
except Exception as e:
    print('UNKNOWN_RAISED', type(e).__name__)
" 2>&1)"
  echo "$OUT" | grep -q "^PROPS GameProp_Trophy GameProp_Potion$" \
    && ok "A1 trophy and potion are built (not the default sphere)" \
    || fail "A1 trophy/potion fall back to a sphere: $(echo "$OUT" | grep -E '^PROPS' || echo 'no PROPS line')"
  echo "$OUT" | grep -q "^UNKNOWN_RAISED ValueError$" \
    && ok "A2 build_prop rejects an unknown prop" \
    || fail "A2 an unknown prop is built silently as a sphere"

  "$BLENDER" -b -P "$PROP" -- --output "$TMP/nonsense.png" --prop nonsense >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ] && [ ! -e "$TMP/nonsense.png" ]; then
    ok "A3 render of an unknown prop exits $RC and writes no PNG"
  else
    fail "A3 unknown prop: exit=$RC, PNG written=$([ -e "$TMP/nonsense.png" ] && echo yes || echo no)"
  fi
  # Blender exits 0 on an uncaught Python error: a bad option value or an unwritable output must still end non-zero.
  "$BLENDER" -b -P "$PROP" -- --output "$TMP/badres.png" --prop coin --resolution abc >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ] && [ ! -e "$TMP/badres.png" ]; then
    ok "A8 a non-numeric --resolution exits $RC and writes no PNG"
  else
    fail "A8 bad --resolution: exit=$RC, PNG written=$([ -e "$TMP/badres.png" ] && echo yes || echo no)"
  fi
  "$BLENDER" -b -P "$PROP" -- --output /dev/null/impossible/out.png --prop coin >/dev/null 2>&1
  RC=$?
  [ "$RC" -ne 0 ] && ok "A9 an unwritable --output exits $RC" || fail "A9 unwritable --output exits 0 (Blender hides the Python error)"
  OUT2="$("$BLENDER" -b --python-expr "
import sys
sys.path.insert(0, r'$GAME/scripts')
import bpy
import render_game_prop as r
r.clean_scene()
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.samples = 4096
bpy.context.view_layer.samples = 4096
r.cap_samples(32)
print('CAPPED', sc.cycles.samples, bpy.context.view_layer.samples)
" 2>&1)"
  echo "$OUT2" | grep -q "^CAPPED 32 32$" \
    && ok "A10 a source saved with 4096 Cycles samples, scene and view layer, is capped (SAMPLES = 32)" \
    || fail "A10 --blend keeps the source's own sample count: $(echo "$OUT2" | grep -E 'CAPPED|Error' | head -n 1)"
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
bpy.ops.mesh.primitive_cube_add(size=400)
bpy.context.active_object.hide_render = True
bpy.ops.mesh.primitive_cube_add(size=300)
big = bpy.context.active_object
hidden = bpy.data.collections.new('Colliders')
bpy.context.scene.collection.children.link(hidden)
for col in list(big.users_collection):
    col.objects.unlink(big)
hidden.objects.link(big)
hidden.hide_render = True
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/hidden.blend')
" >/dev/null 2>&1
  [ -s "$TMP/hidden.blend" ] || fail "A11 setup: hidden.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/hidden.blend" --output "$TMP/hidden.png" >/dev/null 2>&1
  if ! python3 -I -c "import PIL" 2>/dev/null; then
    skip "A11 no PIL, the visible fill is not measured"
  elif [ ! -s "$TMP/hidden.png" ]; then
    fail "A11 the hidden-mesh fixture did not render (frame_blend_scene broke on it?)"
  else
    FILL="$(python3 -I -c "
from PIL import Image
a = Image.open('$TMP/hidden.png').convert('RGBA').getchannel('A')
print('%.2f' % (a.point(lambda v: 255 if v else 0).histogram()[255] / float(a.size[0] * a.size[1])))")"
    python3 -I -c "import sys; sys.exit(0 if float('$FILL') >= 0.10 else 1)" \
      && ok "A11 meshes that do not render (hide_render, hidden collection) do not shrink the visible one (fill $FILL)" \
      || fail "A11 a hidden 400-unit cube sized the frame, the visible cube fills only $FILL"
  fi
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.curve.primitive_bezier_circle_add(radius=1)
bpy.context.active_object.data.bevel_depth = 0.2
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/curve.blend')
" >/dev/null 2>&1
  [ -s "$TMP/curve.blend" ] || fail "A12 setup: curve.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/curve.blend" --output "$TMP/curve.png" >/dev/null 2>&1
  RC=$?
  [ "$RC" -eq 0 ] && [ -s "$TMP/curve.png" ] \
    && ok "A12 a curve-only source (no mesh object) renders" \
    || fail "A12 curve-only .blend: exit=$RC, PNG=$([ -s "$TMP/curve.png" ] && echo yes || echo no)"
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
parts = bpy.data.collections.new('Parts')   # library style: only its instance renders
bpy.ops.mesh.primitive_cube_add(size=2)
part = bpy.context.active_object
for col in list(part.users_collection):
    col.objects.unlink(part)
parts.objects.link(part)
bpy.ops.object.collection_instance_add(collection='Parts', location=(5, 0, 0))
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/inst.blend')
" >/dev/null 2>&1
  [ -s "$TMP/inst.blend" ] || fail "A13 setup: inst.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/inst.blend" --output "$TMP/inst.png" >/dev/null 2>&1
  RC=$?
  if ! python3 -I -c "import PIL" 2>/dev/null; then
    skip "A13 no PIL, the frame is not measured"
  elif [ "$RC" -ne 0 ] || [ ! -s "$TMP/inst.png" ]; then
    fail "A13 a source with a collection instance did not render: exit=$RC"
  else
    FRAME="$(frame_of "$TMP/inst.png")"
    [ "$FRAME" = "inside" ] \
      && ok "A13 a collection instance is measured: both cubes fit inside the frame" \
      || fail "A13 the instance was not measured, the frame crops it: $FRAME"
  fi
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
parts = bpy.data.collections.new('Parts')
bpy.ops.mesh.primitive_cube_add(size=2)
part = bpy.context.active_object
for col in list(part.users_collection):
    col.objects.unlink(part)
parts.objects.link(part)
bpy.ops.object.collection_instance_add(collection='Parts', location=(500, 0, 0))
ref = bpy.context.active_object
refs = bpy.data.collections.new('Refs')
bpy.context.scene.collection.children.link(refs)
for col in list(ref.users_collection):
    col.objects.unlink(ref)
refs.objects.link(ref)
refs.hide_render = True
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/hinst.blend')
" >/dev/null 2>&1
  [ -s "$TMP/hinst.blend" ] || fail "A14 setup: hinst.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/hinst.blend" --output "$TMP/hinst.png" >/dev/null 2>&1
  RC=$?
  if ! python3 -I -c "import PIL" 2>/dev/null; then
    skip "A14 no PIL, the frame is not measured"
  elif [ "$RC" -ne 0 ] || [ ! -s "$TMP/hinst.png" ]; then
    fail "A14 a source with a hidden instance did not render: exit=$RC"
  else
    FRAME="$(frame_of "$TMP/hinst.png")"; FILL="$(fill_of "$TMP/hinst.png")"
    [ "$FRAME" = "inside" ] && python3 -I -c "import sys; sys.exit(0 if float('$FILL') >= 0.10 else 1)" \
      && ok "A14 an instance hidden through its collection is not measured (a 500-unit-away instance does not shrink the cube, fill $FILL)" \
      || fail "A14 the hidden instance sized or cropped the frame: $FRAME, the visible cube fills $FILL"
  fi
  # an object linked into a visible AND a hidden collection still renders; a hidden PARENT collection hides its children
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=0.2)
bpy.ops.mesh.primitive_cube_add(size=10)
big = bpy.context.active_object
both = bpy.data.collections.new('HiddenToo')
bpy.context.scene.collection.children.link(both)
both.objects.link(big)
both.hide_render = True
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/twocol.blend')
" >/dev/null 2>&1
  [ -s "$TMP/twocol.blend" ] || fail "A18 setup: twocol.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/twocol.blend" --output "$TMP/twocol.png" >/dev/null 2>&1
  if need_png "A18" "$TMP/twocol.png"; then
    FRAME="$(frame_of "$TMP/twocol.png")"
    [ "$FRAME" = "inside" ] \
      && ok "A18 an object in a visible and a hidden collection still sizes the frame" \
      || fail "A18 the 10-unit cube (also in a hidden collection) was dropped from the measure: $FRAME"
  fi
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
parent = bpy.data.collections.new('HiddenParent')
child = bpy.data.collections.new('Child')
bpy.context.scene.collection.children.link(parent)
parent.children.link(child)
bpy.ops.mesh.primitive_cube_add(size=400)
big = bpy.context.active_object
for col in list(big.users_collection):
    col.objects.unlink(big)
child.objects.link(big)
parent.hide_render = True
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/nested.blend')
" >/dev/null 2>&1
  [ -s "$TMP/nested.blend" ] || fail "A19 setup: nested.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/nested.blend" --output "$TMP/nested.png" >/dev/null 2>&1
  if need_png "A19" "$TMP/nested.png"; then
    FILL="$(python3 -I -c "
from PIL import Image
a = Image.open('$TMP/nested.png').convert('RGBA').getchannel('A')
print('%.2f' % (a.point(lambda v: 255 if v else 0).histogram()[255] / float(a.size[0] * a.size[1])))")"
    python3 -I -c "import sys; sys.exit(0 if float('$FILL') >= 0.10 else 1)" \
      && ok "A19 a child of a hidden PARENT collection is not measured (fill $FILL)" \
      || fail "A19 a cube inside a hidden parent collection sized the frame, the visible cube fills only $FILL"
  fi
  # a collection instance takes its geometry from a scene collection that is excluded from the view layer: that source must not be scaled by the framing as well
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
src = bpy.data.collections.new('Src')
bpy.context.scene.collection.children.link(src)
bpy.ops.mesh.primitive_cube_add(size=2)
cube = bpy.context.active_object
for col in list(cube.users_collection):
    col.objects.unlink(cube)
src.objects.link(cube)
bpy.ops.object.collection_instance_add(collection='Src', location=(5, 0, 0))
bpy.context.view_layer.layer_collection.children['Src'].exclude = True
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/srcinst.blend')
" >/dev/null 2>&1
  [ -s "$TMP/srcinst.blend" ] || fail "A24 setup: srcinst.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/srcinst.blend" --output "$TMP/srcinst.png" >/dev/null 2>&1
  if need_png "A24" "$TMP/srcinst.png"; then
    FILL="$(python3 -I -c "
from PIL import Image
a = Image.open('$TMP/srcinst.png').convert('RGBA').getchannel('A')
print('%.2f' % (a.point(lambda v: 255 if v else 0).histogram()[255] / float(a.size[0] * a.size[1])))")"
    python3 -I -c "import sys; sys.exit(0 if float('$FILL') >= 0.20 else 1)" \
      && ok "A24 an instance of an excluded scene collection is framed once (fill $FILL)" \
      || fail "A24 the instance's source collection was scaled by the framing too, the cube fills only $FILL"
  fi
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
vis = bpy.data.collections.new('Vis')
bpy.context.scene.collection.children.link(vis)
bpy.ops.mesh.primitive_cube_add(size=2)
cube = bpy.context.active_object
for col in list(cube.users_collection):
    col.objects.unlink(cube)
vis.objects.link(cube)
bpy.ops.object.collection_instance_add(collection='Vis', location=(6, 0, 0))
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/visinst.blend')
" >/dev/null 2>&1
  [ -s "$TMP/visinst.blend" ] || fail "A28 setup: visinst.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/visinst.blend" --output "$TMP/visinst.png" >/dev/null 2>&1
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 0))
bpy.ops.mesh.primitive_cube_add(size=2, location=(6, 0, 0))
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/realtwo.blend')
" >/dev/null 2>&1
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/realtwo.blend" --output "$TMP/realtwo.png" >/dev/null 2>&1
  if need_png "A28" "$TMP/visinst.png" && need_png "A28" "$TMP/realtwo.png"; then
    DIFF="$(python3 -I -c "
from PIL import Image, ImageChops
a = Image.open('$TMP/visinst.png').convert('RGBA').getchannel('A')
b = Image.open('$TMP/realtwo.png').convert('RGBA').getchannel('A')
d = ImageChops.difference(a, b).point(lambda v: 255 if v > 16 else 0).histogram()[255]
print('%.3f' % (d / float(a.size[0] * a.size[1])))")"
    python3 -I -c "import sys; sys.exit(0 if float('$DIFF') <= 0.01 else 1)" \
      && ok "A28 an instance of a visible collection renders like the same layout built from real cubes (mask difference $DIFF)" \
      || fail "A28 the instance of a visible collection is framed differently from real cubes (mask difference $DIFF)"
  fi
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=0.01)
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/tiny.blend')
" >/dev/null 2>&1
  [ -s "$TMP/tiny.blend" ] || fail "A29 setup: tiny.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/tiny.blend" --output "$TMP/tiny.png" >/dev/null 2>&1
  if need_png "A29" "$TMP/tiny.png"; then
    FILL="$(python3 -I -c "
from PIL import Image
a = Image.open('$TMP/tiny.png').convert('RGBA').getchannel('A')
print('%.2f' % (a.point(lambda v: 255 if v else 0).histogram()[255] / float(a.size[0] * a.size[1])))")"
    python3 -I -c "import sys; sys.exit(0 if float('$FILL') >= 0.10 else 1)" \
      && ok "A29 a 0.01-unit source is not clipped by the camera (fill $FILL)" \
      || fail "A29 a tiny source renders empty or clipped (fill $FILL): the camera sits inside its clip_start"
  fi
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
bpy.context.active_object.name = 'Key_Light'
bpy.ops.mesh.primitive_cube_add(size=2, location=(3, 0, 0))
bpy.context.active_object.name = 'RenderCamera'
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/names.blend')
" >/dev/null 2>&1
  [ -s "$TMP/names.blend" ] || fail "A30 setup: names.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/names.blend" --output "$TMP/names.png" >/dev/null 2>&1
  RC=$?
  if ! python3 -I -c "import PIL" 2>/dev/null; then
    skip "A30 no PIL, the frame is not measured"
  elif [ "$RC" -ne 0 ] || [ ! -s "$TMP/names.png" ]; then
    fail "A30 a source with meshes named Key_Light and RenderCamera did not render: exit=$RC"
  else
    FRAME="$(frame_of "$TMP/names.png")"
    [ "$FRAME" = "inside" ] && ok "A30 source objects named like the studio rig are left alone and framed" || fail "A30 the rig was fitted to the wrong objects: $FRAME"
  fi
  # F1: the source's active view layer is the one measured; Blender used to write the FIRST one: a transparent PNG, exit 0, "blender-3d"
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.mesh.primitive_cube_add(size=2)
second = scene.view_layers.new('Second')
scene.view_layers[0].layer_collection.exclude = True
bpy.context.window_manager.windows[0].view_layer = second
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/twolayers.blend')
" >/dev/null 2>&1
  [ -s "$TMP/twolayers.blend" ] || fail "A31 setup: twolayers.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/twolayers.blend" --output "$TMP/twolayers.png" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -eq 0 ] && need_png "A31" "$TMP/twolayers.png"; then
    FILL="$(fill_of "$TMP/twolayers.png")"
    python3 -I -c "import sys; sys.exit(0 if float('$FILL') >= 0.10 else 1)" \
      && ok "A31 a source saved on its second view layer renders that layer (fill $FILL)" \
      || fail "A31 a source on its second view layer rendered a blank frame (fill $FILL) and said SUCCESS"
  elif [ "$RC" -ne 0 ]; then
    fail "A31 two-view-layer source: exit=$RC"
  fi
  # F1 sink: something is measured but nothing reaches the camera: a blank PNG is no result and no proof
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
bpy.context.active_object.visible_camera = False
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/nocam.blend')
" >/dev/null 2>&1
  [ -s "$TMP/nocam.blend" ] || fail "A32 setup: nocam.blend was not built"
  rm -f "$TMP/nocam.png"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/nocam.blend" --output "$TMP/nocam.png" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -eq 2 ] && [ ! -e "$TMP/nocam.png" ]; then
    ok "A32 a render that comes out fully transparent exits 2 and leaves no PNG"
  else
    fail "A32 blank render: exit=$RC, PNG=$([ -e "$TMP/nocam.png" ] && echo kept || echo none)"
  fi
  # F2 F4 F6: the source's own output settings (stereo, video, stamp, pixel aspect) must not decide what --output gets
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
r = bpy.context.scene.render
r.use_multiview = True
r.views_format = 'STEREO_3D'
if hasattr(r.image_settings, 'media_type'):
    r.image_settings.media_type = 'VIDEO'
r.image_settings.file_format = 'FFMPEG'
r.pixel_aspect_x = 2.0
r.use_stamp = True
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/outsettings.blend')
" >/dev/null 2>&1
  [ -s "$TMP/outsettings.blend" ] || fail "A33 setup: outsettings.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/outsettings.blend" --output "$TMP/outsettings.png" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -eq 0 ] && need_png "A33" "$TMP/outsettings.png"; then
    FRAME="$(frame_of "$TMP/outsettings.png")"
    LEAK="$(python3 -I -c "import sys; print('leak' if b'.blend' in open(sys.argv[1], 'rb').read() else 'clean')" "$TMP/outsettings.png")"
    [ "$FRAME" = "inside" ] && [ "$LEAK" = "clean" ] \
      && ok "A33 stereo + video output + pixel aspect 2 + stamp in the source: a plain PNG at --output, framed, no source path inside" \
      || fail "A33 the source's output settings leaked: frame=$FRAME, source path in the PNG=$LEAK"
  else
    fail "A33 source with stereo/video/stamp output: exit=$RC, PNG=$([ -s "$TMP/outsettings.png" ] && echo yes || echo no) (one stereo_L.png/stereo_R.png pair, or a TypeError on 'PNG')"
  fi
  # F5: geometry that renders as nothing (a curve without bevel, a mesh of edges) must not size the frame
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
bpy.ops.curve.primitive_bezier_curve_add(location=(50, 0, 0))
mesh = bpy.data.meshes.new('edges')
mesh.from_pydata([(0, 0, 0), (60, 0, 0)], [(0, 1)], [])
bpy.context.scene.collection.objects.link(bpy.data.objects.new('edges', mesh))
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/nosurface.blend')
" >/dev/null 2>&1
  [ -s "$TMP/nosurface.blend" ] || fail "A34 setup: nosurface.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/nosurface.blend" --output "$TMP/nosurface.png" >/dev/null 2>&1
  if need_png "A34" "$TMP/nosurface.png"; then
    FILL="$(fill_of "$TMP/nosurface.png")"
    python3 -I -c "import sys; sys.exit(0 if float('$FILL') >= 0.10 else 1)" \
      && ok "A34 a bevel-less curve and an edges-only mesh do not size the frame (fill $FILL)" \
      || fail "A34 geometry that renders as nothing shrank the cube to fill $FILL"
  fi
  # OCR round 20: two objects share ONE curve datablock, one with a Screw modifier (it renders faces), one plain (renders nothing). frame_blend_scene caches
  # "renders a surface" per evaluated MESH only (instances of one mesh share it); a curve's answer belongs to its object, because each evaluated curve object
  # owns its own Curve, so neither answer may decide the other's, whichever is visited first (a key shared by both, e.g. the original data, would)
  OUT="$("$BLENDER" -b --python-expr "
import sys
sys.path.insert(0, r'$GAME/scripts')
import bpy
import render_game_prop as r
for order in ('plain_first', 'screw_first'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_cube_add(size=2)
    bpy.ops.curve.primitive_nurbs_path_add()
    first = bpy.context.active_object
    second = bpy.data.objects.new('second', first.data)
    bpy.context.scene.collection.objects.link(second)
    plain, screw = (first, second) if order == 'plain_first' else (second, first)
    plain.location = (200, 0, 0)
    mod = screw.modifiers.new('S', 'SCREW')
    mod.angle = 6.283
    mod.steps = 8
    centre, factor = r.frame_blend_scene()
    print('SHARED_CURVE', order, round(factor, 2))
" 2>&1)"
  if [ "$(echo "$OUT" | grep -c '^SHARED_CURVE')" = 2 ] && [ -z "$(echo "$OUT" | grep '^SHARED_CURVE' | awk '$3 > 10 || $3 < 3')" ]; then   # the swept screw is ~6 units wide = 4.6; the cube alone would be 1.54 (screw dropped), the plain curve at x=200 would be 158
    ok "A37 a plain curve and a Screw-modified one sharing a datablock do not decide each other's framing ($(echo "$OUT" | grep '^SHARED_CURVE' | tr '\n' ' '))"
  else
    fail "A37 shared curve datablock: the plain object (x=200) sized the frame or the case did not run: $(echo "$OUT" | grep -E '^SHARED_CURVE|Error' | tr '\n' ' ')"
  fi
  # F7: no `--` at all is a refusal, not a gold coin written next to the caller; a resolution Blender would round up is refused too
  mkdir -p "$TMP/nodash" && (cd "$TMP/nodash" && "$BLENDER" -b -P "$PROP" >/dev/null 2>&1; echo $? > "$TMP/nodash.rc")
  if [ "$(cat "$TMP/nodash.rc")" = "2" ] && [ ! -e "$TMP/nodash/rendered_prop.png" ]; then
    ok "A35 no -- separator: exit 2 and nothing written next to the caller"
  else
    fail "A35 no --: exit=$(cat "$TMP/nodash.rc"), rendered_prop.png=$([ -e "$TMP/nodash/rendered_prop.png" ] && echo WRITTEN || echo none)"
  fi
  "$BLENDER" -b -P "$PROP" -- --output "$TMP/tiny-res.png" --resolution 2 >/dev/null 2>&1
  RC=$?
  [ "$RC" -eq 2 ] && [ ! -e "$TMP/tiny-res.png" ] && ok "A36 --resolution 2 (Blender would make a 4x4) is refused" || fail "A36 --resolution 2: exit=$RC, PNG=$([ -e "$TMP/tiny-res.png" ] && echo yes || echo no)"
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.object.empty_add(location=(4, 0, 0))
rig = bpy.context.active_object
rig.hide_render = True
bpy.ops.mesh.primitive_cube_add(size=2)
cube = bpy.context.active_object
cube.parent = rig
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/hidparent.blend')
" >/dev/null 2>&1
  [ -s "$TMP/hidparent.blend" ] || fail "A25 setup: hidparent.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/hidparent.blend" --output "$TMP/hidparent.png" >/dev/null 2>&1
  if need_png "A25" "$TMP/hidparent.png"; then
    FILL="$(python3 -I -c "
from PIL import Image
a = Image.open('$TMP/hidparent.png').convert('RGBA').getchannel('A')
print('%.2f' % (a.point(lambda v: 255 if v else 0).histogram()[255] / float(a.size[0] * a.size[1])))")"
    python3 -I -c "import sys; sys.exit(0 if float('$FILL') >= 0.20 else 1)" \
      && ok "A25 a visible cube under a render-hidden parent is centred with the rest (fill $FILL)" \
      || fail "A25 the cube under a hidden parent kept its place outside the frame (fill $FILL)"
  fi
  # the source's own render settings must not leak into the output: border/crop, and a file name without extension
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
sc = bpy.context.scene
sc.render.use_border = True
sc.render.use_crop_to_border = True
sc.render.border_min_x, sc.render.border_max_x = 0.4, 0.5
sc.render.border_min_y, sc.render.border_max_y = 0.4, 0.5
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/border.blend')
" >/dev/null 2>&1
  [ -s "$TMP/border.blend" ] || fail "A21 setup: border.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/border.blend" --output "$TMP/border.png" >/dev/null 2>&1
  if ! python3 -I -c "import PIL" 2>/dev/null; then
    skip "A21 no PIL, the output size is not measured"
  elif [ ! -s "$TMP/border.png" ]; then
    fail "A21 the border fixture did not render"
  else
    SIZE="$(python3 -I -c "from PIL import Image; print('%dx%d' % Image.open('$TMP/border.png').size)")"
    [ "$SIZE" = "512x512" ] && ok "A21 a render border saved in the source does not crop the output ($SIZE)" || fail "A21 the source's render border cropped the output to $SIZE"
  fi
  "$BLENDER" -b -P "$PROP" -- --output "$TMP/noext" --prop coin >/dev/null 2>&1
  [ -s "$TMP/noext" ] && ok "A22 --output without an extension is written exactly there" || fail "A22 --output $TMP/noext: no file at that path (Blender appended an extension)"
  # Blender logs a failed save and still returns FINISHED: no PNG on disk must never print SUCCESS
  mkdir -p "$TMP/ro" && chmod 555 "$TMP/ro"
  if [ -w "$TMP/ro" ]; then
    skip "A26 this user can write into a 555 folder (root), the read-only case cannot be built"
  else
    "$BLENDER" -b -P "$PROP" -- --output "$TMP/ro/out.png" --prop coin >"$TMP/ro.log" 2>&1
    RC=$?
    if [ "$RC" -ne 0 ] && ! grep -q "BLENDER_RENDER_SUCCESS" "$TMP/ro.log"; then
      ok "A26 a read-only output folder exits $RC and never prints SUCCESS"
    else
      fail "A26 read-only output folder: exit=$RC, SUCCESS printed=$(grep -q BLENDER_RENDER_SUCCESS "$TMP/ro.log" && echo YES || echo no)"
    fi
  fi
  chmod 755 "$TMP/ro"
  # strict arguments: nothing is ignored or defaulted silently
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
mat = bpy.data.materials.new('Red'); mat.use_nodes = True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (1, 0, 0, 1)
mat.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value = 0.0
bpy.context.active_object.data.materials.append(mat)
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/eqsrc.blend')
" >/dev/null 2>&1
  [ -s "$TMP/eqsrc.blend" ] || fail "A23 setup: eqsrc.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend="$TMP/eqsrc.blend" --output "$TMP/eq.png" >"$TMP/eq.log" 2>&1
  RC=$?
  if [ "$RC" -eq 0 ] && [ -s "$TMP/eq.png" ] && python3 -I -c "import PIL" 2>/dev/null; then
    EQ="$(python3 -I -c "
from PIL import Image
im = Image.open('$TMP/eq.png').convert('RGBA'); w, h = im.size
r, g, b, a = im.getpixel((w // 2, h // 2))
print('red-source' if a > 0 and r > 50 and g < r / 2 and b < r / 2 else 'default-coin %s' % ((r, g, b, a),))")"
    [ "$EQ" = "red-source" ] && ok "A23 --blend=<file> (equals form) renders the source" || fail "A23 --blend=<file> was ignored and the default coin rendered: $EQ"
  else
    fail "A23 --blend=<file>: exit=$RC, PNG=$([ -s "$TMP/eq.png" ] && echo yes || echo no) $(grep -E 'usage|error|Error' "$TMP/eq.log" | head -n 3 | tr '\n' ' ')"
  fi
  # an empty value (an unset shell variable in --blend "$SRC") is a refusal too, not the default coin
  rm -f "$TMP/emptyblend.png"
  "$BLENDER" -b -P "$PROP" -- --output "$TMP/emptyblend.png" --blend "" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -eq 2 ] && [ ! -e "$TMP/emptyblend.png" ]; then
    ok "A27 an empty --blend exits 2 and writes nothing"
  else
    fail "A27 empty --blend: exit=$RC, PNG=$([ -e "$TMP/emptyblend.png" ] && echo yes || echo no) (the default coin rendered instead)"
  fi
  for bad in "--blnd $TMP/eqsrc.blend" "--blend" "--color red" "--angle isometric" "--prop token" "--resolution 0" "--samples 8" "--blend $TMP/eqsrc.blend --prop token" "--blend $TMP/eqsrc.blend --prop chest" "--blend $TMP/eqsrc.blend --color ruby"; do
    rm -f "$TMP/bad.png"
    # shellcheck disable=SC2086  # the option words are split on purpose
    "$BLENDER" -b -P "$PROP" -- --output "$TMP/bad.png" $bad >/dev/null 2>&1
    RC=$?
    if [ "$RC" -eq 2 ] && [ ! -e "$TMP/bad.png" ]; then
      ok "A23 '$bad' exits 2 and writes nothing"
    else
      fail "A23 '$bad' is not refused: exit=$RC, PNG=$([ -e "$TMP/bad.png" ] && echo yes || echo no)"
    fi
  done
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
mat = bpy.data.materials.new('Red'); mat.use_nodes = True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (1, 0, 0, 1)
mat.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value = 0.0
bpy.context.active_object.data.materials.append(mat)
helpers = bpy.data.collections.new('Helpers')
bpy.context.scene.collection.children.link(helpers)
helpers.hide_render = True
bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children['Helpers']
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/hhelp.blend')
" >/dev/null 2>&1
  [ -s "$TMP/hhelp.blend" ] || fail "A15 setup: hhelp.blend was not built"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/hhelp.blend" --output "$TMP/hhelp.png" >/dev/null 2>&1
  if ! python3 -I -c "import PIL" 2>/dev/null; then
    skip "A15 no PIL, the lit colour is not measured"
  elif [ ! -s "$TMP/hhelp.png" ]; then
    fail "A15 the source whose active collection is hidden did not render"
  else
    LIT="$(python3 -I -c "
from PIL import Image
im = Image.open('$TMP/hhelp.png').convert('RGBA'); w, h = im.size
r, g, b, a = im.getpixel((w // 2, h // 2))
print('lit' if a > 0 and r > 50 and g < r / 2 else 'dark %s' % ((r, g, b, a),))")"
    [ "$LIT" = "lit" ] \
      && ok "A15 the studio rig is created in the scene collection, not in the source's hidden active collection" \
      || fail "A15 the studio lights landed in a hidden collection, the cube renders $LIT"
  fi
  # A source may come from the web: its embedded script must not run even when the user's Blender has auto-exec enabled.
  TRAP="$TMP/trap"; mkdir -p "$TRAP"
  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
t = bpy.data.texts.new('boot.py')
t.write(\"open(r'$TRAP/marker', 'w').write('ran')\")
t.use_module = True
bpy.ops.wm.save_as_mainfile(filepath=r'$TRAP/trap.blend')
" >/dev/null 2>&1
  [ -s "$TRAP/trap.blend" ] || fail "A16 setup: trap.blend was not built"
  "$BLENDER" --enable-autoexec -b -P "$PROP" -- --blend "$TRAP/trap.blend" --output "$TRAP/trap.png" >/dev/null 2>&1
  RC=$?
  [ "$RC" -eq 0 ] && [ -s "$TRAP/trap.png" ] && [ ! -e "$TRAP/marker" ] \
    && ok "A16 an embedded run-on-load script of a source does not run, even with auto-exec enabled" \
    || fail "A16 a .blend source ran its own script (marker=$([ -e "$TRAP/marker" ] && echo CREATED || echo no), exit=$RC)"

  "$BLENDER" -b --python-expr "
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=40)
mat = bpy.data.materials.new('Red'); mat.diffuse_color = (1, 0, 0, 1); mat.use_nodes = True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (1, 0, 0, 1)
mat.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value = 0.0
bpy.context.active_object.data.materials.append(mat)
bpy.ops.wm.save_as_mainfile(filepath=r'$TMP/src.blend')
" >/dev/null 2>&1
  [ -s "$TMP/src.blend" ] || fail "A setup: the red-cube fixture .blend was not built, A4-A7 prove nothing"
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/missing.blend" --output "$TMP/missing.png" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ] && [ ! -e "$TMP/missing.png" ]; then
    ok "A6 a missing --blend file exits $RC and writes no PNG"
  else
    fail "A6 missing --blend: exit=$RC, PNG written=$([ -e "$TMP/missing.png" ] && echo yes || echo no)"
  fi
  "$BLENDER" -b -P "$PROP" -- --blend "$TMP/src.blend" --output "$TMP/blend.png" >"$TMP/blend.log" 2>&1
  RC=$?
  if [ "$RC" -eq 0 ] && [ -s "$TMP/blend.png" ]; then
    CT="$(python3 -I -c "import sys; b=open(sys.argv[1],'rb').read(); print(b[25] if b[:8]==b'\x89PNG\r\n\x1a\n' else -1, len(b))" "$TMP/blend.png")"
    case "$CT" in
      "6 "*) ok "A4 --blend renders an RGBA PNG ($CT)" ;;
      *) fail "A4 --blend output is not an RGBA PNG: $CT" ;;
    esac
    if python3 -I -c "import PIL" 2>/dev/null; then
      FRAME="$(frame_of "$TMP/blend.png")"
      [ "$FRAME" = "inside" ] \
        && ok "A5 a 40-unit source is auto-framed (the opaque part keeps a margin to every edge)" \
        || fail "A5 --blend crops the source: $FRAME"
      TINT="$(python3 -I -c "
from PIL import Image
im = Image.open('$TMP/blend.png').convert('RGBA'); w, h = im.size
r, g, b, a = im.getpixel((w // 2, h // 2))
print('red-source' if a > 0 and r > 50 and g < r / 2 and b < r / 2 else 'not-from-source %s' % ((r, g, b, a),))")"
      [ "$TINT" = "red-source" ] \
        && ok "A7 the PNG comes from the .blend (red cube, not the default gold coin)" \
        || fail "A7 --blend output ignores the source file: $TINT"
    else
      skip "A5/A7 no PIL: framing and 'the PNG comes from the .blend' are not checked"
    fi
  else
    fail "A4 --blend render failed: exit=$RC $(tail -n 2 "$TMP/blend.log" | tr '\n' ' ')"
  fi
fi

# ---------- B. validate-assets.sh ----------
ROOT="$TMP/unity"
mkdir -p "$ROOT/Assets/Art" "$ROOT/ProjectSettings"
git -C "$ROOT" init -q 2>/dev/null || fail "B setup: git init failed, the scan cases below prove nothing"
hook_rc() {  # $1 = repo-relative path the agent just wrote
  printf '{"tool_input":{"file_path":"%s/%s"}}' "$ROOT" "$1" | CLAUDE_PROJECT_DIR="$ROOT" bash "$VALIDATE" >/dev/null 2>&1
  echo $?
}
for f in Assets/Art/coin.blend Assets/Art/coin.blend1 Assets/Art/coin.blend2 Assets/Art/coin.blend12 Assets/Art/coin.blend@ Assets/Art/coin.blend.meta Assets/UI/icon.svg Assets/UI/frame.psd Assets/UI/Frame.PSD Assets/UI/hero.aseprite; do
  RCV="$(hook_rc "$f")"
  [ "$RCV" = "2" ] && ok "B hook blocks $f" || fail "B hook lets $f into Assets/ (exit $RCV)"
done
for f in Art/Source/coin.blend Assets/Art/Sprites/coin.png Assets/Plugins/Vendor/logo.psd "Assets/TextMesh Pro/Examples/x.psd" Assets/Samples/Pkg/logo.psd; do
  RCV="$(hook_rc "$f")"
  [ "$RCV" = "0" ] && ok "B hook allows $f" || fail "B hook wrongly blocks $f (exit $RCV)"
done
touch "$ROOT/Assets/Art/new.blend"
CLAUDE_PROJECT_DIR="$ROOT" bash "$VALIDATE" </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && ok "B scan flags a new .blend in Assets/" || fail "B scan lets a new .blend through (exit $RC)"
rm -f "$ROOT/Assets/Art/new.blend"
touch "$ROOT/Assets/Art/coin.png"
CLAUDE_PROJECT_DIR="$ROOT" bash "$VALIDATE" </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" = "0" ] && ok "B scan accepts a new Blender-rendered PNG" || fail "B scan rejects a plain PNG (exit $RC)"
# the move the rule forbids, as git reports it: the pathspec is applied before rename pairing, so a move from outside Assets/ is a NEW file there
mkdir -p "$ROOT/Art/Source"; printf 'BLENDER hero source, long enough for git to pair it as a rename (git never pairs empty files)\n' > "$ROOT/Art/Source/hero.blend"
git -C "$ROOT" add Art/Source/hero.blend
git -C "$ROOT" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm base 2>/dev/null || fail "B setup: could not commit the rename fixture"
git -C "$ROOT" mv Art/Source/hero.blend Assets/Art/hero.blend
CLAUDE_PROJECT_DIR="$ROOT" bash "$VALIDATE" </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && ok "B scan flags git mv Art/Source/hero.blend into Assets/ (reported as a new file)" || fail "B scan lets a rename into Assets/ through (exit $RC)"
GIT_ID="-c user.email=t@example.com -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null"
# shellcheck disable=SC2086  # the two -c options are split on purpose
git -C "$ROOT" $GIT_ID commit -qm renamed 2>/dev/null || fail "B setup: could not commit the renamed fixture"
printf 'FBX model bytes, long enough for git to pair a rename later on and on\n' > "$ROOT/Assets/Art/hero.fbx"
git -C "$ROOT" add Assets/Art/hero.fbx
# shellcheck disable=SC2086
git -C "$ROOT" $GIT_ID commit -qm fbx 2>/dev/null || fail "B setup: could not commit the fbx fixture"
git -C "$ROOT" mv Assets/Art/hero.fbx Assets/Art/hero2.blend
CLAUDE_PROJECT_DIR="$ROOT" bash "$VALIDATE" </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && ok "B scan flags a rename inside Assets/ to a .blend (git mv hero.fbx hero2.blend)" || fail "B scan lets hero.fbx -> hero2.blend through (exit $RC)"
# shellcheck disable=SC2086
git -C "$ROOT" $GIT_ID commit -qm blendrename 2>/dev/null || fail "B setup: could not commit the second rename"
mkdir -p "$ROOT/Assets/Docs"; printf 'PSD bytes, already tracked before the rule existed, long enough to pair\n' > "$ROOT/Assets/Docs/old.psd"
git -C "$ROOT" add Assets/Docs/old.psd
# shellcheck disable=SC2086
git -C "$ROOT" $GIT_ID commit -qm psd 2>/dev/null || fail "B setup: could not commit the psd fixture"
git -C "$ROOT" mv Assets/Docs/old.psd Assets/Docs/new.psd
CLAUDE_PROJECT_DIR="$ROOT" bash "$VALIDATE" </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" = "0" ] && ok "B scan leaves a rename of an already tracked rogue file alone (grandfathered)" || fail "B scan flags the rename of a grandfathered .psd (exit $RC)"
# shellcheck disable=SC2086
git -C "$ROOT" $GIT_ID commit -qm psdrename 2>/dev/null || fail "B setup: could not commit the psd rename"
printf 'Notes that were tracked before the rule existed, long enough to pair as a rename\n' > "$ROOT/Assets/Docs/notes.md"
git -C "$ROOT" add Assets/Docs/notes.md
# shellcheck disable=SC2086
git -C "$ROOT" $GIT_ID commit -qm md 2>/dev/null || fail "B setup: could not commit the md fixture"
git -C "$ROOT" mv Assets/Docs/notes.md Assets/Art/hero3.blend
CLAUDE_PROJECT_DIR="$ROOT" bash "$VALIDATE" </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && ok "B scan flags notes.md -> hero3.blend (grandfathering covers the same kind of file only)" || fail "B scan lets a tracked .md become a .blend (exit $RC)"
# shellcheck disable=SC2086
git -C "$ROOT" $GIT_ID commit -qm mdrename 2>/dev/null || fail "B setup: could not commit the md rename"
printf 'meta of a tracked note, long enough for git to pair a rename of it later\n' > "$ROOT/Assets/Docs/n.md.meta"
git -C "$ROOT" add Assets/Docs/n.md.meta
# shellcheck disable=SC2086
git -C "$ROOT" $GIT_ID commit -qm mdmeta 2>/dev/null || fail "B setup: could not commit the .meta fixture"
git -C "$ROOT" mv Assets/Docs/n.md.meta Assets/Art/h.blend.meta
CLAUDE_PROJECT_DIR="$ROOT" bash "$VALIDATE" </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && ok "B scan flags n.md.meta -> h.blend.meta (the kind is compared without the .meta)" || fail "B scan grandfathers a .md.meta that becomes .blend.meta (exit $RC)"
# shellcheck disable=SC2086
git -C "$ROOT" $GIT_ID commit -qm metarename 2>/dev/null || fail "B setup: could not commit the .meta rename"
printf 'An upper-case PSD tracked before the rule existed, long enough to pair as a rename\n' > "$ROOT/Assets/Docs/Old.PSD"
git -C "$ROOT" add Assets/Docs/Old.PSD
# shellcheck disable=SC2086
git -C "$ROOT" $GIT_ID commit -qm upperpsd 2>/dev/null || fail "B setup: could not commit the upper-case fixture"
git -C "$ROOT" mv Assets/Docs/Old.PSD Assets/Docs/new2.psd
CLAUDE_PROJECT_DIR="$ROOT" bash "$VALIDATE" </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" = "0" ] && ok "B scan treats Old.PSD -> new2.psd as the same kind (extension case ignored)" || fail "B scan flags a grandfathered rename because of the extension case (exit $RC)"

# a Unity project one level down (Neighbours-From-Hell keeps it in unity/): the same rules, the paths seen from the repo root
UR="$TMP/unitysub"; mkdir -p "$UR/unity/Assets/Art" "$UR/unity/ProjectSettings" "$UR/Art/Source"
git -C "$UR" init -q 2>/dev/null
for f in unity/Assets/Art/hero.blend unity/Assets/UI/icon.svg unity/Assets/Art/coin.blend2; do
  RCV="$(printf '{"tool_input":{"file_path":"%s/%s"}}' "$UR" "$f" | CLAUDE_PROJECT_DIR="$UR" bash "$VALIDATE" >/dev/null 2>&1; echo $?)"
  [ "$RCV" = "2" ] && ok "B unity/ hook blocks $f" || fail "B unity/ hook lets $f into the Unity project (exit $RCV)"
done
for f in Art/Source/hero.blend unity/Assets/Plugins/Vendor/logo.psd unity/Assets/Art/Sprites/coin.png; do
  RCV="$(printf '{"tool_input":{"file_path":"%s/%s"}}' "$UR" "$f" | CLAUDE_PROJECT_DIR="$UR" bash "$VALIDATE" >/dev/null 2>&1; echo $?)"
  [ "$RCV" = "0" ] && ok "B unity/ hook allows $f" || fail "B unity/ hook wrongly blocks $f (exit $RCV)"
done
touch "$UR/unity/Assets/Art/new.blend"
CLAUDE_PROJECT_DIR="$UR" bash "$VALIDATE" </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && ok "B unity/ scan flags a new .blend in unity/Assets" || fail "B unity/ scan lets a new .blend through (exit $RC)"

# ---------- C. capture_3d_proof.py never draws a 2D proof ----------
mkdir -p "$TMP/fakebin" "$TMP/proj"
for stub_exit in 1 0; do
  rm -f "$TMP/fake.ran" "$TMP/proj/proof.png"
  if [ "$stub_exit" = "0" ]; then   # a stale, valid-looking PNG from an earlier run already sits at --output
    python3 -I -c "open('$TMP/proj/proof.png', 'wb').write(b'\x89PNG\r\n\x1a\n' + bytes(9000))"
  fi
  printf '#!/bin/sh\necho "$*" > "%s/fake.ran"\nexit %s\n' "$TMP" "$stub_exit" > "$TMP/fakebin/blender"; chmod +x "$TMP/fakebin/blender"
  PATH="$TMP/fakebin:$PATH" python3 -I "$PROOF" --project "$TMP/proj" --output "$TMP/proj/proof.png" --prop coin >/dev/null 2>&1
  RC=$?
  if [ -e "$TMP/fake.ran" ] && grep -q -- '--disable-autoexec' "$TMP/fake.ran" && [ "$RC" -ne 0 ] && [ ! -e "$TMP/proj/proof.png" ]; then   # a stale PNG is removed, not reported
    ok "C a Blender that exits $stub_exit and draws nothing gives exit $RC and no proof (run with --disable-autoexec)"
  else
    fail "C Blender stub exit $stub_exit: ran=$([ -e "$TMP/fake.ran" ] && echo yes || echo NO), autoexec flag=$(grep -q -- '--disable-autoexec' "$TMP/fake.ran" 2>/dev/null && echo yes || echo NO), proof exit=$RC, PNG=$([ -e "$TMP/proj/proof.png" ] && echo drawn || echo none)"
  fi
done

rm -f "$TMP/fake.ran"
printf '#!/bin/sh\necho "$*" > "%s/fake.ran"\nexit 1\n' "$TMP" > "$TMP/fakebin/blender"; chmod +x "$TMP/fakebin/blender"
PATH="$TMP/fakebin:$PATH" python3 -I "$PROOF" --project "$TMP/proj" --output "$TMP/proj/b.png" --blend Art/Source/hero.blend >/dev/null 2>&1
if grep -q -E -- '--blend /.*/proj/Art/Source/hero\.blend' "$TMP/fake.ran" 2>/dev/null && ! grep -q -E -- '--prop|--color' "$TMP/fake.ran"; then
  ok "C --blend is resolved against --project and forwarded without --prop/--color"
else
  fail "C --blend forwarding: $(cat "$TMP/fake.ran" 2>/dev/null || echo 'the stub never ran')"
fi
rm -f "$TMP/fake.ran"
PATH="$TMP/fakebin:$PATH" python3 -I "$PROOF" --project "$TMP/proj" --output "$TMP/proj/c.png" --blend Art/Source/hero.blend --prop chest >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 2 ] && [ ! -e "$TMP/fake.ran" ]; then
  ok "C --blend together with --prop is refused (exit 2) before Blender runs"
else
  fail "C --blend --prop chest: exit=$RC, Blender ran=$([ -e "$TMP/fake.ran" ] && echo YES || echo no) (the prop would be dropped silently)"
fi
for empty in --blend --image; do
  rm -f "$TMP/fake.ran" "$TMP/proj/e.png"
  PATH="$TMP/fakebin:$PATH" python3 -I "$PROOF" --project "$TMP/proj" --output "$TMP/proj/e.png" $empty "" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ] && [ ! -e "$TMP/fake.ran" ] && [ ! -e "$TMP/proj/e.png" ]; then
    ok "C an empty $empty is refused (exit $RC) and no stand-in is rendered"
  else
    fail "C empty $empty: exit=$RC, Blender ran=$([ -e "$TMP/fake.ran" ] && echo YES || echo no), PNG=$([ -e "$TMP/proj/e.png" ] && echo yes || echo no)"
  fi
done
rm -f "$TMP/fake.ran" "$TMP/proj/ec.png"
PATH="$TMP/fakebin:$PATH" python3 -I "$PROOF" --project "$TMP/proj" --output "$TMP/proj/ec.png" --color "" >/dev/null 2>&1
RC=$?
if [ "$RC" -ne 0 ] && [ ! -e "$TMP/fake.ran" ] && [ ! -e "$TMP/proj/ec.png" ]; then
  ok "C an empty --color is refused (exit $RC), not turned into gold"
else
  fail "C empty --color: exit=$RC, Blender ran=$([ -e "$TMP/fake.ran" ] && echo YES || echo no), proof=$([ -e "$TMP/proj/ec.png" ] && echo written || echo none)"
fi
for combo in "--image $TMP/proj/x.png --blend Art/Source/hero.blend" "--image $TMP/proj/x.png --prop chest"; do
  rm -f "$TMP/fake.ran" "$TMP/proj/amb.png"; python3 -I -c "open('$TMP/proj/x.png', 'wb').write(b'\x89PNG\r\n\x1a\n' + bytes(9000))"   # a valid-looking proof image
  # shellcheck disable=SC2086
  PATH="$TMP/fakebin:$PATH" python3 -I "$PROOF" --project "$TMP/proj" --output "$TMP/proj/amb.png" $combo >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ] && [ ! -e "$TMP/fake.ran" ] && [ ! -e "$TMP/proj/amb.png" ]; then
    ok "C '$combo' is refused (exit $RC), nothing rendered or copied"
  else
    fail "C '$combo': exit=$RC, Blender ran=$([ -e "$TMP/fake.ran" ] && echo YES || echo no), proof=$([ -e "$TMP/proj/amb.png" ] && echo written || echo none)"
  fi
done
rm -f "$TMP/proj/img.png"
python3 -I "$PROOF" --project "$TMP/proj" --output "$TMP/proj/img.png" --image "$TMP/proj/missing.png" >/dev/null 2>&1
RC=$?
if [ "$RC" -ne 0 ] && [ ! -e "$TMP/proj/img.png" ]; then
  ok "C --image with a missing file exits $RC and renders no stand-in"
else
  fail "C --image <missing>: exit=$RC, PNG=$([ -e "$TMP/proj/img.png" ] && echo rendered-anyway || echo none)"
fi

# ---------- D. the written rule ----------
grep -q 'Art/Source' "$GAME/rules/game-rules.md" \
  && ok "D game-rules.md keeps Blender sources in Art/Source" || fail "D game-rules.md has no Art/Source rule"
if [ -f "$GAME/DESIGN.md" ] && ! grep -q -E 'Vector SVG \(Web\)|Lucide: giấy phép ISC' "$GAME/DESIGN.md"; then
  ok "D DESIGN.md has no 2D icon source"
else
  fail "D DESIGN.md is missing or still names Lucide or Vector SVG as an icon source"
fi
grep -q 'execute_blender_code' "$DEVKIT_DIR/agents/councils/06-game-unity-blender.md" \
  && ok "D council 6.4 audits through read-only MCP tools" || fail "D council 6.4 does not restrict execute_blender_code"
python3 -I - "$GAME/profile.json" <<'PY' && ok "D profile.json: MCP safety note and 2D skills excluded" || fail "D profile.json lacks the MCP safety note or still enables 2D skills"
import json, sys
p = json.load(open(sys.argv[1]))
need = {"generate2dmedia", "generate2dsprite", "video2dsprite"}
sys.exit(0 if "DISABLE_TELEMETRY" in p.get("external_mcps_note", "") and need <= set(p.get("exclude_skills", [])) else 1)
PY

echo "failures: $FAILS"
[ "$FAILS" -eq 0 ]
