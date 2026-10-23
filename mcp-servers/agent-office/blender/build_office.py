"""Build a low-poly office furniture set for the Agent Office page and export ONE GLB.

Builds separate named roots: Desk, Chair, Monitor (with child Screen), Keyboard, Mouse,
Plant, Mug (all placed in the "desk frame": floor at y=0, the person sits at x=-0.95
facing +X, Z is sideways) and Shelf (a low cabinet, origin at its floor centre).
Output: web/models/office.glb (flat-colour Principled materials, no textures, +Y up).

Run from mcp-servers/agent-office/:
    blender -b --factory-startup --python blender/build_office.py
Optional preview render (moves Shelf aside after the export, adds floor + camera):
    blender -b --factory-startup --python blender/build_office.py -- --preview /path/out.png

Helpers adapted from https://github.com/tinhthanh/vetgo-3d-demo/blob/main/blender/build_characters.py

Coordinates below are written in glTF terms with G(x, y_up, z); G() converts them to
Blender's Z-up frame (Blender x = x, Blender y = -z, Blender z = y_up), which the exporter
turns back with export_yup=True.
"""
import bpy, bmesh, sys, math, os
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "web", "models", "office.glb")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else None

MATS = {}


def G(x, y, z):
    """glTF (x, y-up, z) -> Blender location."""
    return (x, -z, y)


def GD(sx, sy, sz):
    """glTF box size -> Blender dimensions."""
    return (sx, sz, sy)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def mat(name, rgb, rough=0.75):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    lin = [((c / 255) / 12.92 if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4) for c in rgb]
    b.inputs["Base Color"].default_value = (*lin, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Emission Strength"].default_value = 0.0
    m.diffuse_color = (*lin, 1)          # Workbench preview colour
    m.roughness = rough
    MATS[name] = m
    return m


def _ctx(obj):
    return bpy.context.temp_override(object=obj, active_object=obj,
                                     selected_objects=[obj], selected_editable_objects=[obj])


def _finish(obj, m, smooth=False, bevel=None, seg=2):
    obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.use_smooth = smooth
    if bevel:
        bv = obj.modifiers.new("bevel", "BEVEL")
        bv.width = bevel
        bv.segments = seg
        bv.limit_method = 'ANGLE'
    obj.modifiers.new("tri", "TRIANGULATE")
    with _ctx(obj):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        for md in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=md.name)
    return obj


def cube(dims, loc, m, bevel=0.008, rot=(0, 0, 0), seg=1):
    """dims/loc in glTF terms; rot is a Blender euler."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=G(*loc), rotation=rot)
    o = bpy.context.object
    o.scale = GD(*dims)
    return _finish(o, m, bevel=bevel, seg=seg)


def cyl(r, depth, loc, m, rot=(0, 0, 0), r2=None, verts=12, bevel=0.004, seg=1, smooth=False):
    """Vertical (glTF +Y) cylinder/cone by default; loc is its centre in glTF terms."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=G(*loc), rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, vertices=verts,
                                        location=G(*loc), rotation=rot)
    return _finish(bpy.context.object, m, bevel=bevel, seg=seg, smooth=smooth)


def mesh_obj(name, verts, faces, m, uvs=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([G(*v) for v in verts], [], faces)
    if uvs:
        layer = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for li in poly.loop_indices:
                layer.data[li].uv = uvs[me.loops[li].vertex_index]
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(m)
    return o


def join(parts, name):
    """Join parts into one object with its origin at the world origin (desk frame)."""
    main = parts[0]
    with bpy.context.temp_override(object=main, active_object=main,
                                   selected_objects=parts, selected_editable_objects=parts):
        if len(parts) > 1:
            bpy.ops.object.join()
    main.name = name
    main.data.name = name
    main.data.transform(Matrix.Translation(main.location))
    main.location = (0, 0, 0)
    # primitives carry UVs; only the screen needs them
    while main.data.uv_layers:
        main.data.uv_layers.remove(main.data.uv_layers[0])
    return main


# ---------------------------------------------------------------- pieces
def build_desk():
    top = mat("DeskTop", (214, 178, 132), rough=0.7)
    frame = mat("DeskFrame", (58, 61, 68), rough=0.6)
    p = [cube((1.80, 0.05, 0.90), (0, 0.775, 0), top, bevel=0.012, seg=2)]
    for z in (-0.40, 0.40):
        p.append(cube((0.72, 0.03, 0.06), (0.05, 0.015, z), frame, bevel=0.008))   # foot
        p.append(cube((0.08, 0.69, 0.05), (0.05, 0.375, z), frame, bevel=0.006))   # post
        p.append(cube((0.72, 0.03, 0.06), (0.05, 0.735, z), frame, bevel=0.006))   # top rail
        for x in (-0.29, 0.39):
            p.append(cube((0.05, 0.012, 0.05), (x, 0.006, z), frame, bevel=0))  # glides
    p.append(cube((0.05, 0.04, 0.75), (0.30, 0.73, 0), frame, bevel=0.005))        # cross beam
    p.append(cube((0.015, 0.32, 0.74), (0.78, 0.56, 0), frame, bevel=0.004))       # modesty panel
    return join(p, "Desk")


def build_chair():
    fab = mat("ChairFabric", (98, 112, 132), rough=0.9)
    fr = mat("ChairFrame", (40, 42, 47), rough=0.6)
    cx = -0.95
    p = [cyl(0.055, 0.06, (cx, 0.09, 0), fr, verts=10),                 # hub
         cyl(0.026, 0.36, (cx, 0.30, 0), fr, verts=10, smooth=True),     # gas column
         cyl(0.034, 0.10, (cx, 0.17, 0), fr, verts=10, smooth=True),     # column sleeve
         cube((0.20, 0.04, 0.20), (cx, 0.48, 0), fr, bevel=0.006),       # mechanism
         cube((0.48, 0.07, 0.48), (cx, 0.525, 0), fab, bevel=0.025, seg=2)]  # seat (top 0.56)
    for i in range(5):
        a = 2 * math.pi * i / 5
        dx, dz = math.cos(a), math.sin(a)
        # star arm (pivoted around the glTF Y axis == Blender Z)
        p.append(cube((0.30, 0.035, 0.045), (cx + dx * 0.15, 0.085, dz * 0.15), fr,
                      bevel=0.008, rot=(0, 0, math.atan2(-dz, dx))))
        ex, ez = cx + dx * 0.29, dz * 0.29
        p.append(cyl(0.012, 0.03, (ex, 0.06, ez), fr, verts=8, bevel=0))           # caster stem
        p.append(cyl(0.026, 0.024, (ex, 0.026, ez), fr, verts=8, bevel=0,       # wheel
                     rot=(0, math.pi / 2, math.atan2(-dz, dx))))
    # backrest support: under-seat bar + upright, then the tilted pad
    p.append(cube((0.20, 0.03, 0.06), (cx - 0.19, 0.475, 0), fr, bevel=0.005))
    p.append(cube((0.03, 0.26, 0.06), (-1.245, 0.59, 0), fr, bevel=0.005))
    p.append(cube((0.06, 0.45, 0.46), (-1.22, 0.83, 0), fab, bevel=0.025, seg=2,
                  rot=(0, math.radians(-7), 0)))
    for z in (-0.265, 0.265):     # armrests
        s = 1 if z > 0 else -1
        p.append(cube((0.05, 0.025, 0.08), (cx, 0.475, z - s * 0.04), fr, bevel=0.004))
        p.append(cube((0.04, 0.20, 0.03), (cx, 0.585, z), fr, bevel=0.005))
        p.append(cube((0.26, 0.03, 0.07), (cx - 0.02, 0.70, z), fr, bevel=0.012))
    return join(p, "Chair")


def build_monitor():
    body = mat("Monitor", (34, 36, 41), rough=0.6)
    scr = mat("Screen", (18, 20, 26), rough=0.6)
    p = [cube((0.24, 0.014, 0.28), (0.56, 0.807, 0), body, bevel=0.006),     # base on desk
         cube((0.04, 0.42, 0.08), (0.575, 1.02, 0), body, bevel=0.006),      # neck
         cube((0.06, 0.62, 1.00), (0.50, 1.30, 0), body, bevel=0.010, seg=2),       # bezel body
         cube((0.04, 0.34, 0.56), (0.545, 1.29, 0), body, bevel=0.012)]      # back bulge
    mon = join(p, "Monitor")
    x, y0, y1, z0, z1 = 0.4685, 1.01, 1.59, -0.48, 0.48
    # CCW seen from -X (viewer's right is +Z): normal points -X toward the person.
    screen = mesh_obj("Screen", [(x, y0, z0), (x, y0, z1), (x, y1, z1), (x, y1, z0)],
                      [(0, 1, 2, 3)], scr, uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
    screen.data.name = "Screen"
    screen.parent = mon
    return mon


def build_keyboard():
    kb = mat("Keyboard", (44, 46, 52), rough=0.65)
    keys = mat("Keys", (150, 154, 162), rough=0.7)
    p = [cube((0.20, 0.016, 0.50), (-0.33, 0.808, 0), kb, bevel=0.005)]
    rows = [[1, 1, 1, 6, 1, 1, 1], [1.5] + [1] * 9 + [1.5], [1.3] + [1] * 10 + [1.3],
            [1] * 12, [1] * 12]
    span, gap = 0.47, 0.005
    for i, row in enumerate(rows):                  # row 0 is nearest the person (-X)
        x = -0.405 + i * 0.038
        unit = (span - gap * (len(row) - 1)) / sum(row)
        z = -span / 2
        for w in row:
            wz = w * unit
            p.append(cube((0.03, 0.009, wz), (x, 0.8205, z + wz / 2), keys, bevel=0))
            z += wz + gap
    return join(p, "Keyboard")


def build_mouse():
    kb = mat("Keyboard", (44, 46, 52))
    keys = mat("Keys", (150, 154, 162))
    p = [cube((0.10, 0.032, 0.06), (-0.30, 0.816, 0.38), kb, bevel=0.014, seg=2),
         cube((0.012, 0.004, 0.008), (-0.33, 0.833, 0.38), keys, bevel=0)]       # wheel
    return join(p, "Mouse")


def build_plant():
    pot = mat("Pot", (196, 106, 74), rough=0.85)
    soil = mat("Soil", (74, 54, 40), rough=0.9)
    leaf = mat("Leaf", (78, 150, 88), rough=0.8)
    px, pz = 0.55, -0.62
    p = [cyl(0.062, 0.13, (px, 0.865, pz), pot, r2=0.078, verts=10, bevel=0.003),
         cyl(0.086, 0.022, (px, 0.94, pz), pot, verts=10, bevel=0.004),
         cyl(0.074, 0.006, (px, 0.951, pz), soil, verts=10, bevel=0)]
    # faceted blades: yaw (deg), tilt from vertical (deg), length
    blades = [(0, 18, 0.24), (52, 38, 0.20), (110, 30, 0.22), (170, 42, 0.19),
              (215, 24, 0.23), (265, 40, 0.20), (320, 32, 0.21), (140, 12, 0.18)]
    for k, (yaw, tilt, L) in enumerate(blades):
        w, th, mid = 0.035, 0.008, 0.45
        v = [(0, 0, 0), (0, L, 0), (-w, L * mid, 0), (w, L * mid, 0), (0, L * mid, th), (0, L * mid, -th)]
        f = [(0, 3, 4), (0, 4, 2), (0, 2, 5), (0, 5, 3), (1, 4, 3), (1, 2, 4), (1, 5, 2), (1, 3, 5)]
        o = mesh_obj("leaf%d" % k, v, f, leaf)
        # tilt around the blade's flat axis, then yaw around the vertical, then move to the pot
        o.rotation_euler = (math.radians(tilt), 0, math.radians(yaw))
        o.location = G(px, 0.95, pz)
        with _ctx(o):
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        o.data.validate()
        p.append(o)
    return join(p, "Plant")


def build_mug():
    mug = mat("Mug", (232, 228, 220), rough=0.6)
    coffee = mat("Coffee", (70, 44, 30), rough=0.6)
    mx, mz = -0.15, -0.42
    o = cyl(0.042, 0.10, (mx, 0.85, mz), mug, verts=14, bevel=0)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.dissolve_limit(bm, angle_limit=0.01, verts=bm.verts, edges=bm.edges)   # undo the triangle fan
    top = max(bm.faces, key=lambda f: f.calc_center_median().z)
    bmesh.ops.inset_individual(bm, faces=[top], thickness=0.005)
    bmesh.ops.translate(bm, vec=(0, 0, -0.012), verts=top.verts)                       # coffee level
    o.data.materials.append(coffee)
    top.material_index = 1
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(o.data); bm.free()
    p = [o]
    # handle: half torus on the -Z side, ends on the wall
    hv, hf, segs, ring = [], [], 7, 6
    R, rr = 0.026, 0.0065
    for i in range(segs + 1):
        a = -math.pi / 2 + math.pi * i / segs
        for j in range(ring):
            b = 2 * math.pi * j / ring
            d = R + rr * math.cos(b)
            hv.append((mx + rr * math.sin(b), 0.85 + d * math.sin(a), mz - 0.038 - d * math.cos(a)))
    for i in range(segs):
        for j in range(ring):
            a0, a1 = i * ring + j, i * ring + (j + 1) % ring
            hf.append((a0, a1, a1 + ring, a0 + ring))
    h = mesh_obj("handle", hv, hf, mug)
    bm = bmesh.new(); bm.from_mesh(h.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(h.data); bm.free()
    p.append(h)
    return join(p, "Mug")


def build_shelf():
    sh = mat("Shelf", (226, 222, 214), rough=0.8)
    W, D, H = 1.0, 2.35, 0.46
    p = [cube((W - 0.06, 0.05, D - 0.06), (0, 0.025, 0), sh, bevel=0.004),     # recessed plinth
         cube((W - 0.02, H - 0.08, D - 0.02), (0, 0.05 + (H - 0.08) / 2, 0), sh, bevel=0.004),
         cube((W, 0.03, D), (0, H - 0.015, 0), sh, bevel=0.006)]              # top slab
    # three shallow door panels on each long (+-X) face; plain boxes survive x scaling
    pw = (D - 0.10) / 3
    for s in (-1, 1):
        for k in range(3):
            z = -D / 2 + 0.05 + pw * (k + 0.5)
            p.append(cube((0.008, H - 0.14, pw - 0.03), (s * (W / 2 - 0.006), 0.05 + (H - 0.08) / 2, z), sh,
                          bevel=0.002, seg=1))
    return join(p, "Shelf")


def export():
    bpy.ops.object.select_all(action='SELECT')
    path = os.path.abspath(OUT)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_apply=True, export_yup=True,
                              use_selection=True, export_animations=False, export_lights=False,
                              export_cameras=False, export_materials='EXPORT', export_texcoords=True,
                              export_normals=True)
    print("EXPORTED", path, os.path.getsize(path))


def preview(png):
    bpy.data.objects["Shelf"].location = G(1.45, 0, 0)
    floor_m = mat("PreviewFloor", (200, 196, 188))
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0.3, 0, 0))
    bpy.context.object.data.materials.append(floor_m)
    cam_d = bpy.data.cameras.new("cam"); cam_d.lens = 40
    cam = bpy.data.objects.new("cam", cam_d); bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(G(-2.7, 2.2, 2.7))
    cam.rotation_euler = (Vector(G(0.25, 0.65, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_shadows = True; sh.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 900, 600
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", png)


if __name__ == "__main__":  # build_stations.py imports the helpers above without rebuilding the office
    reset()
    for build in (build_desk, build_chair, build_monitor, build_keyboard, build_mouse,
                  build_plant, build_mug, build_shelf):
        build()
    export()
    if PREVIEW:
        preview(PREVIEW)
