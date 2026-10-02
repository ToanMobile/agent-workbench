#!/usr/bin/env python3
"""render_game_prop.py — Headless Blender Script for Juicy 3D Game UI Assets & Baked Sprites.

Generates polished, high-resolution transparent 3D sprites (coins, gems, chests, trophies)
using 3-point studio lighting and PBR materials, exported directly into Unity Assets/ folder.

Usage:
    blender -b -P render_game_prop.py -- --output Assets/Art/Sprites/UI/coin_gold.png --prop coin --color gold
    blender -b -P render_game_prop.py -- --output Assets/Art/Sprites/UI/gem_ruby.png --prop gem --color ruby
"""

import sys
import os
import math

try:
    import bpy
except ImportError:
    # If run outside blender, provide instructions
    print("Error: render_game_prop.py must be run inside Blender: blender -b -P render_game_prop.py -- [args]")
    sys.exit(1)


def parse_args():
    raw_args = sys.argv
    if "--" in raw_args:
        args = raw_args[raw_args.index("--") + 1:]
    else:
        args = []

    params = {
        "output": "rendered_prop.png",
        "prop": "coin",
        "color": "gold",
        "resolution": 512,
        "angle": "iso",
        "samples": 32,
    }

    i = 0
    while i < len(args):
        if args[i] == "--output" and i + 1 < len(args):
            params["output"] = args[i + 1]
            i += 2
        elif args[i] == "--prop" and i + 1 < len(args):
            params["prop"] = args[i + 1].lower()
            i += 2
        elif args[i] == "--color" and i + 1 < len(args):
            params["color"] = args[i + 1].lower()
            i += 2
        elif args[i] == "--resolution" and i + 1 < len(args):
            params["resolution"] = int(args[i + 1])
            i += 2
        elif args[i] == "--angle" and i + 1 < len(args):
            params["angle"] = args[i + 1].lower()
            i += 2
        else:
            i += 1
    return params


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


def build_prop(prop_type, color_name):
    # Colors (RGBA)
    color_map = {
        "gold": (1.0, 0.78, 0.15, 1.0),
        "ruby": (0.95, 0.1, 0.2, 1.0),
        "emerald": (0.1, 0.85, 0.35, 1.0),
        "sapphire": (0.15, 0.45, 0.95, 1.0),
        "amethyst": (0.7, 0.2, 0.9, 1.0),
        "silver": (0.85, 0.88, 0.92, 1.0),
        "bronze": (0.75, 0.45, 0.2, 1.0),
    }
    base_color = color_map.get(color_name, (1.0, 0.78, 0.15, 1.0))

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

    else:
        # Default sphere token
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=32, ring_count=24)
        token = bpy.context.active_object
        mat = create_pbr_material("Mat_Token", base_color, metallic=0.8, roughness=0.2)
        token.data.materials.append(mat)
        bpy.ops.object.shade_smooth()
        return token


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


def configure_render(output_path, resolution, samples):
    scene = bpy.context.scene
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100

    # Transparent background for UI sprite
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'

    # Output directory
    abs_out = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(abs_out), exist_ok=True)
    scene.render.filepath = abs_out


def main():
    params = parse_args()
    clean_scene()
    build_prop(params["prop"], params["color"])
    setup_lighting()
    setup_camera(params["angle"])
    configure_render(params["output"], params["resolution"], params["samples"])

    # Render
    bpy.ops.render.render(write_still=True)
    abs_path = os.path.abspath(params["output"])
    print(f"[BLENDER_RENDER_SUCCESS] Exported 3D Asset Sprite: {abs_path} ({params['resolution']}x{params['resolution']})")


if __name__ == "__main__":
    main()
