#!/usr/bin/env python3
"""render_game_prop.py — Headless Blender script: renders one game asset to a transparent PNG.

Blender 3D is the only source of a game asset. This script turns one into a PNG for the Unity places that need a
Texture2D (uGUI, SpriteAtlas), with 3-point studio lighting, either a built-in prop or any .blend source:

    --prop coin|gem|chest|trophy|potion   built-in props
    --blend <file.blend>                  render that source instead: its own lights and cameras are replaced by the studio rig,
                                          what renders (collection and geometry-node instances included) is measured and the
                                          studio rig is placed and sized to it (the source is not moved), its scripts never run (use_scripts=False), its render border and compositor are ignored; its world (HDRI, colour) stays, only its lights go
Every unknown or bad argument exits 2 and writes nothing (never a silent default).

Usage (--disable-autoexec: a source may come from the web):
    blender --disable-autoexec -b -P render_game_prop.py -- --output Assets/Art/Sprites/UI/coin_gold.png --prop coin --color gold
    blender --disable-autoexec -b -P render_game_prop.py -- --output Assets/Art/Sprites/UI/gem_ruby.png --prop gem --color ruby
    blender --disable-autoexec -b -P render_game_prop.py -- --output Assets/Art/Sprites/UI/hero.png --blend Art/Source/hero.blend
"""

import argparse
import sys
import os
import math
import traceback

try:
    import bpy
except ImportError:
    # If run outside blender, provide instructions
    print("Error: render_game_prop.py must be run inside Blender: blender -b -P render_game_prop.py -- [args]")
    sys.exit(1)


PROPS = ("coin", "gem", "chest", "trophy", "potion")
SAMPLES = 32   # the most samples a --blend source may render with (it may come with 4096)

COLORS = {   # RGBA
    "gold": (1.0, 0.78, 0.15, 1.0),
    "ruby": (0.95, 0.1, 0.2, 1.0),
    "emerald": (0.1, 0.85, 0.35, 1.0),
    "sapphire": (0.15, 0.45, 0.95, 1.0),
    "amethyst": (0.7, 0.2, 0.9, 1.0),
    "silver": (0.85, 0.88, 0.92, 1.0),
    "bronze": (0.75, 0.45, 0.2, 1.0),
}


def _positive_int(text):
    value = int(text)
    if value < 4:
        raise argparse.ArgumentTypeError("must be >= 4 (Blender rounds anything smaller up to 4)")
    return value


def parse_args():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="render_game_prop.py", allow_abbrev=False,
                                     description="Render one game asset (Blender 3D) to a transparent PNG.")
    parser.add_argument("--output", required=True)   # no default file: `-- ` with nothing after it must not write a coin next to the caller
    parser.add_argument("--prop", type=str.lower, choices=PROPS)
    parser.add_argument("--color", type=str.lower, choices=sorted(COLORS))
    parser.add_argument("--resolution", default=512, type=_positive_int)
    parser.add_argument("--angle", default="iso", type=str.lower, choices=("iso", "front", "side"))
    parser.add_argument("--blend")
    if "--" not in sys.argv:
        parser.error("arguments go after `--`: blender -b -P render_game_prop.py -- --output <png> [--prop <name> | --blend <file>]")
    ns = parser.parse_args(args)   # a bad option exits 2 through SystemExit, past main()'s except Exception
    if ns.blend is not None and (ns.prop or ns.color):
        parser.error("--prop and --color describe a built-in prop; they do not apply to --blend")
    ns.prop = ns.prop or "coin"
    ns.color = ns.color or "gold"
    return vars(ns)


def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def create_pbr_material(name, base_color, metallic=0.9, roughness=0.2):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        # Blender 4+ vs 3.x compatibility
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
    return mat


def _join(parts, name):
    bpy.ops.object.select_all(action='DESELECT')
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


def build_prop(prop_type, color_name="gold"):
    if color_name not in COLORS:
        raise ValueError("unknown color %r (known: %s)" % (color_name, ", ".join(sorted(COLORS))))
    base_color = COLORS[color_name]

    if prop_type == "coin":
        # Beveled cylinder coin with star/star relief
        bpy.ops.mesh.primitive_cylinder_add(radius=1.0, depth=0.22, vertices=48)
        coin = bpy.context.active_object
        coin.name = "GameProp_Coin"
        mat = create_pbr_material("Mat_GoldCoin", base_color, metallic=0.95, roughness=0.18)
        coin.data.materials.append(mat)
        # Add bevel modifier for juicy specular highlight on edges
        bev = coin.modifiers.new(name="Bevel", type='BEVEL')
        bev.width = 0.05
        bev.segments = 3
        bpy.ops.object.shade_smooth()
        return coin

    elif prop_type == "gem":
        # Low-poly faceted diamond / gem
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=1.0, radius2=0.5, depth=0.8)
        top = bpy.context.active_object
        top.location.z = 0.4
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=1.0, radius2=0.0, depth=1.2)
        bottom = bpy.context.active_object
        bottom.rotation_euler.x = math.pi
        bottom.location.z = -0.6
        # Join
        top.select_set(True)
        bottom.select_set(True)
        bpy.context.view_layer.objects.active = top
        bpy.ops.object.join()
        gem = bpy.context.active_object
        gem.name = "GameProp_Gem"
        mat = create_pbr_material("Mat_Gem", base_color, metallic=0.1, roughness=0.05)
        gem.data.materials.append(mat)
        bpy.ops.object.shade_flat()
        return gem

    elif prop_type == "chest":
        # Stylized Treasure Chest
        bpy.ops.mesh.primitive_cube_add(size=1.2)
        chest = bpy.context.active_object
        chest.scale = (1.2, 0.8, 0.7)
        chest.name = "GameProp_Chest"
        mat = create_pbr_material("Mat_Chest", (0.35, 0.2, 0.1, 1.0), metallic=0.1, roughness=0.6)
        chest.data.materials.append(mat)
        bev = chest.modifiers.new(name="Bevel", type='BEVEL')
        bev.width = 0.04
        bev.segments = 2
        return chest

    elif prop_type == "trophy":
        # Cup on a stem and a foot
        mat = create_pbr_material("Mat_Trophy", base_color, metallic=0.95, roughness=0.2)
        parts = []
        for add, kw in (
            (bpy.ops.mesh.primitive_cone_add, dict(vertices=32, radius1=0.35, radius2=0.75, depth=0.9, location=(0, 0, 0.45))),
            (bpy.ops.mesh.primitive_cylinder_add, dict(vertices=24, radius=0.12, depth=0.5, location=(0, 0, -0.25))),
            (bpy.ops.mesh.primitive_cylinder_add, dict(vertices=32, radius=0.5, depth=0.14, location=(0, 0, -0.57))),
        ):
            add(**kw)
            part = bpy.context.active_object
            part.data.materials.append(mat)
            parts.append(part)
        trophy = _join(parts, "GameProp_Trophy")
        bev = trophy.modifiers.new(name="Bevel", type='BEVEL')
        bev.width = 0.03
        bev.segments = 2
        bpy.ops.object.shade_smooth()
        return trophy

    elif prop_type == "potion":
        # Round flask, neck and cork
        glass = create_pbr_material("Mat_Potion", base_color, metallic=0.1, roughness=0.05)
        cork = create_pbr_material("Mat_Cork", (0.45, 0.28, 0.12, 1.0), metallic=0.0, roughness=0.8)
        parts = []
        for add, kw, mat in (
            (bpy.ops.mesh.primitive_uv_sphere_add, dict(radius=0.7, segments=32, ring_count=24, location=(0, 0, -0.2)), glass),
            (bpy.ops.mesh.primitive_cylinder_add, dict(vertices=24, radius=0.2, depth=0.6, location=(0, 0, 0.55)), glass),
            (bpy.ops.mesh.primitive_cylinder_add, dict(vertices=24, radius=0.26, depth=0.18, location=(0, 0, 0.94)), cork),
        ):
            add(**kw)
            part = bpy.context.active_object
            part.data.materials.append(mat)
            parts.append(part)
        potion = _join(parts, "GameProp_Potion")
        bpy.ops.object.shade_smooth()
        return potion

    raise ValueError("unknown prop %r (known: %s; or --blend <file>)" % (prop_type, ", ".join(PROPS)))


def setup_lighting():
    # 1. Key Light (Warm, 45 deg front-right)
    bpy.ops.object.light_add(type='AREA', location=(3.0, -3.0, 3.5))
    key = bpy.context.active_object
    key.name = "Key_Light"
    key.data.energy = 250.0
    key.data.size = 2.0
    key.data.color = (1.0, 0.95, 0.88)
    key.rotation_euler = (math.radians(45), math.radians(15), math.radians(45))

    # 2. Fill Light (Cool, front-left, soft)
    bpy.ops.object.light_add(type='AREA', location=(-3.0, -2.5, 1.5))
    fill = bpy.context.active_object
    fill.name = "Fill_Light"
    fill.data.energy = 80.0
    fill.data.size = 3.0
    fill.data.color = (0.75, 0.85, 1.0)
    fill.rotation_euler = (math.radians(60), math.radians(-10), math.radians(-45))

    # 3. Rim Light (Back sharp backlight creating juicy contour)
    bpy.ops.object.light_add(type='SPOT', location=(0.0, 3.5, 2.5))
    rim = bpy.context.active_object
    rim.name = "Rim_Light"
    rim.data.energy = 350.0
    rim.data.spot_size = math.radians(60)
    rim.data.color = (1.0, 1.0, 1.0)
    rim.rotation_euler = (math.radians(-120), 0, 0)
    return [key, fill, rim]


def setup_camera(angle):
    bpy.ops.object.camera_add()
    cam = bpy.context.active_object
    cam.name = "RenderCamera"
    bpy.context.scene.camera = cam

    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 3.2

    if angle == "iso":
        # Isometric angle (35.264° X, 0° Y, 45° Z)
        cam.location = (3.5, -3.5, 3.0)
        cam.rotation_euler = (math.radians(55), 0, math.radians(45))
    elif angle == "front":
        cam.location = (0, -4.5, 0)
        cam.rotation_euler = (math.radians(90), 0, 0)
    else:
        cam.location = (3.0, -3.0, 3.0)
        cam.rotation_euler = (math.radians(50), 0, math.radians(45))
    return cam


def configure_render(output_path, resolution):
    scene = bpy.context.scene
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100

    # The output is this scene's 3D only: a source's own render border, compositor and sequencer must not crop or replace it,
    # and the file is written exactly where --output says (Blender would append .png to a name without an extension)
    scene.render.use_border = False
    scene.render.use_compositing = False
    scene.render.use_sequencer = False
    scene.render.use_file_extension = False
    scene.render.use_multiview = False   # a stereo source would write stereo_L.png and stereo_R.png and never --output
    scene.render.pixel_aspect_x = scene.render.pixel_aspect_y = 1.0   # a pixel aspect of 2 crops the sprite
    for name in dir(scene.render):   # a stamp prints the source's absolute path (a user name) over the sprite and into the PNG
        if name.startswith("use_stamp") and isinstance(getattr(scene.render, name), bool):
            setattr(scene.render, name, False)
    if hasattr(scene.render.image_settings, "media_type"):   # Blender 5: a source whose output is video or multilayer EXR rejects 'PNG'
        scene.render.image_settings.media_type = 'IMAGE'

    # Transparent background for UI sprite
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'

    # Output directory
    abs_out = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(abs_out), exist_ok=True)
    scene.render.filepath = abs_out


def cap_samples(limit):
    """A source saved with 4096 samples would outlast any caller's timeout: never render with more than `limit`."""
    scene = bpy.context.scene
    for view_layer in scene.view_layers:   # Cycles lets a view layer override the scene's sample count
        if view_layer.samples:
            view_layer.samples = min(view_layer.samples, limit)
    if scene.render.engine == 'CYCLES':
        scene.cycles.samples = min(scene.cycles.samples, limit)
    elif hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = min(scene.eevee.taa_render_samples, limit)


GEOMETRY = ('MESH', 'CURVE', 'SURFACE', 'FONT', 'META', 'GPENCIL', 'GREASEPENCIL', 'CURVES', 'POINTCLOUD', 'VOLUME')


def _render_visible():
    """The scene objects that render: not hidden themselves, in a collection that is neither excluded from the view layer nor
    hidden for render through itself or a parent (an object linked into several collections renders when ONE of them does)."""
    seen = set()

    def walk(layer_collection):
        if layer_collection.exclude or layer_collection.collection.hide_render:
            return
        seen.update(obj for obj in layer_collection.collection.objects if not obj.hide_render)
        for child in layer_collection.children:
            walk(child)

    walk(bpy.context.view_layer.layer_collection)
    return seen


def _has_faces(evaluated):
    mesh = evaluated.to_mesh()
    try:
        return mesh is not None and len(mesh.polygons) > 0
    finally:
        evaluated.to_mesh_clear()


def _renders_surface(evaluated, cache):
    """False for geometry that renders as nothing: a curve without bevel or extrude, a mesh of edges only (it would still size the frame).
    `cache` is keyed by the evaluated mesh: a scatter of 10^5 instances shares a few, and to_mesh() builds a temporary mesh each time.
    Only meshes are cached: the answer for a curve, font or metaball belongs to its object (a metaball family polygonizes on its basis
    object only, and linked duplicates share one datablock)."""
    if evaluated.type not in ('MESH', 'CURVE', 'SURFACE', 'FONT', 'META'):
        return True
    if evaluated.type != 'MESH':
        return _has_faces(evaluated)
    if evaluated.data not in cache:
        cache[evaluated.data] = _has_faces(evaluated)
    return cache[evaluated.data]


def frame_blend_scene():
    """Replace the source's own lights and cameras and measure what renders. Returns (centre, factor) for fit_rig: the rig is built
    for content of 1.3 units, so a source `factor` times larger gets the rig `factor` times larger. The source itself is never moved,
    scaled or re-parented (instances, hidden parents, constraints and animation then need no special care)."""
    from mathutils import Vector
    scene = bpy.context.scene
    for obj in list(scene.objects):
        if obj.type in ('LIGHT', 'CAMERA'):
            bpy.data.objects.remove(obj, do_unlink=True)
    visible = _render_visible()
    points, surfaces = [], {}
    # ponytail: the viewport depsgraph skips an object that is disabled in viewports but enabled for render; add a render depsgraph when a source needs it
    for inst in bpy.context.evaluated_depsgraph_get().object_instances:   # real objects AND instances (collections, geometry nodes, particles)
        evaluated = inst.object
        if evaluated.type not in GEOMETRY or not _renders_surface(evaluated, surfaces):
            continue
        owner = inst.parent.original if inst.is_instance and inst.parent else evaluated.original   # an instance renders when its instancer does
        if owner in visible:
            points.extend(inst.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    if not points:
        raise ValueError("--blend file has nothing that renders (no mesh, curve, text or instance with geometry)")
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    # The iso camera looks 0.385 above the rig's origin: content of 1.3 units keeps the top of even a cube inside the ortho 3.2 frame.
    return (low + high) * 0.5, (max(high.x - low.x, high.y - low.y, high.z - low.z) or 1.0) / 1.3


def fit_rig(rig, centre, factor):
    """Put the studio rig (the lights and camera just created, never found by name: a source may own an object called Key_Light)
    at the content's centre, `factor` times larger."""
    for obj in rig:
        obj.location = centre + obj.location * factor
        if obj.type == 'LIGHT':
            obj.data.energy *= factor ** 2   # the same exposure at `factor` times the distance
            if obj.data.type == 'AREA':
                obj.data.size *= factor
        else:
            obj.data.ortho_scale *= factor
            obj.data.clip_start *= factor
            obj.data.clip_end *= factor


def _refuse_blank(path):
    """A fully transparent PNG is a render of nothing (everything hidden from the camera, the wrong layer): never a result, never a proof."""
    image = bpy.data.images.load(path)
    try:
        blank = max(image.pixels[3::4], default=0.0) <= 0.0
    finally:
        bpy.data.images.remove(image)
    if blank:
        os.remove(path)
        raise RuntimeError("the render is fully transparent (nothing reached the camera): %s removed" % path)


def _run():
    params = parse_args()
    fit = None
    if params["blend"] is not None:
        if not os.path.isfile(params["blend"]):
            raise ValueError("--blend file not found: %s" % params["blend"])
        bpy.ops.wm.open_mainfile(filepath=os.path.abspath(params["blend"]), use_scripts=False)   # a source may come from the web
        fit = frame_blend_scene()
        cap_samples(SAMPLES)
        view_layer = bpy.context.view_layer   # the studio rig goes into the scene's own collection, never a hidden or excluded one
        view_layer.active_layer_collection = view_layer.layer_collection
    else:
        clean_scene()
        build_prop(params["prop"], params["color"])
    rig = setup_lighting() + [setup_camera(params["angle"])]
    if fit:
        fit_rig(rig, *fit)
    configure_render(params["output"], params["resolution"])

    # Render
    bpy.ops.render.render(write_still=True)
    abs_path = os.path.abspath(params["output"])
    if not os.path.isfile(abs_path):   # Blender can finish without writing the file it was asked for (a stereo or video source did)
        raise RuntimeError("the render finished but %s was not written" % abs_path)
    _refuse_blank(abs_path)
    print(f"[BLENDER_RENDER_SUCCESS] Exported 3D Asset Sprite: {abs_path} ({params['resolution']}x{params['resolution']})")


def main():
    try:
        _run()
    except Exception as err:   # Blender exits 0 on an uncaught Python error, and capture_3d_proof.py reads the exit code
        print("[BLENDER_RENDER_ERROR] %s: %s" % (type(err).__name__, err), file=sys.stderr)
        traceback.print_exc()
        sys.exit(2)


if __name__ == "__main__":
    main()
