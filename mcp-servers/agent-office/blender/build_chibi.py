"""Build five chibi people (round head, big sparkly eyes, soft hair, short limbs) with a skeleton and Idle/Walk clips.

One GLB per person in web/models/chibi1.glb ... chibi5.glb. The skeleton uses the bone names the page's
sit/typing pose code looks for (Hips, UpperLeg/LowerLeg/Foot, UpperArm/LowerArm, Head, Head_end; .L = +X),
the person faces +Z in glTF, is 1.0 tall (Head_end at y=1.0) and the shirt material is named "Shirt"
so the page can tint it with the lane colour. Flat Principled materials, no textures.

Run from mcp-servers/agent-office/:
    blender -b --factory-startup --python blender/build_chibi.py
Optional preview (front three-quarter row and back row of all five):
    blender -b --factory-startup --python blender/build_chibi.py -- --preview /path/out.png

Coordinates in the helpers are (x, front, z): front is the way the face looks, converted to Blender -Y.
"""
import bpy, bmesh, math, os, sys
from mathutils import Matrix, Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..", "web", "models")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else None

# shirt tint comes from the page; every person differs from the back too (hair shape or hat)
PEOPLE = [
    dict(name="chibi1", skin=(255, 226, 204), hair=(120, 78, 52), eye=(92, 58, 36), style="short", pants=(84, 104, 150), shoes=(244, 240, 232), acc=None),
    dict(name="chibi2", skin=(252, 218, 196), hair=(150, 92, 86), eye=(110, 64, 70), style="twin", pants=(232, 160, 176), shoes=(240, 128, 150), acc=(255, 132, 168)),
    dict(name="chibi3", skin=(240, 200, 168), hair=(58, 46, 50), eye=(60, 46, 52), style="bun", pants=(110, 140, 120), shoes=(250, 244, 230), acc=(255, 196, 92)),
    dict(name="chibi4", skin=(255, 230, 212), hair=(188, 132, 80), eye=(70, 100, 150), style="beanie", pants=(104, 112, 132), shoes=(236, 120, 92), acc=(196, 176, 236)),
    dict(name="chibi5", skin=(214, 160, 120), hair=(84, 56, 44), eye=(70, 46, 36), style="bob", pants=(88, 140, 150), shoes=(250, 236, 214), acc=(255, 214, 90)),
]

HC, HR = 0.765, 0.235  # head centre height and radius (the head is a bit under half the height)

# bone: (head, tail, parent), points are (x, front, z); .L is +X
BONES = {
    "Hips": ((0, 0, 0.27), (0, 0, 0.31), None),
    "Spine": ((0, 0, 0.31), (0, 0, 0.50), "Hips"),
    "Neck": ((0, 0, 0.50), (0, 0, 0.53), "Spine"),
    "Head": ((0, 0, 0.53), (0, 0, 1.0), "Neck"),
    "Head_end": ((0, 0, 1.0), (0, 0, 1.03), "Head"),
}
for sd, sx in (("L", 1), ("R", -1)):
    BONES.update({
        f"UpperArm.{sd}": ((sx * 0.14, 0, 0.47), (sx * 0.19, 0, 0.33), "Spine"),
        f"LowerArm.{sd}": ((sx * 0.19, 0, 0.33), (sx * 0.22, 0, 0.19), f"UpperArm.{sd}"),
        f"Hand.{sd}": ((sx * 0.22, 0, 0.19), (sx * 0.23, 0, 0.14), f"LowerArm.{sd}"),
        f"UpperLeg.{sd}": ((sx * 0.072, 0, 0.27), (sx * 0.072, 0, 0.14), "Hips"),
        f"LowerLeg.{sd}": ((sx * 0.072, 0, 0.14), (sx * 0.072, 0, 0.05), f"UpperLeg.{sd}"),
        f"Foot.{sd}": ((sx * 0.072, 0, 0.05), (sx * 0.072, 0.06, 0.02), f"LowerLeg.{sd}"),
    })


def B(x, f, z):
    return Vector((x, -f, z))


def lin(rgb):
    return [((c / 255) / 12.92 if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4) for c in rgb]


def on_head(x, z, out=0.0):
    """Point on the head sphere surface (front side) at x, z, pushed `out` further along the normal."""
    dz = z - HC
    f = math.sqrt(max(0.0, (HR * 1.0) ** 2 - x * x - dz * dz))
    n = Vector((x, f, dz)).normalized()
    return B(x, f, z) + Vector((n.x, -n.y, n.z)) * out


class Person:
    """One mesh built in a single bmesh: every part is rigidly weighted to one bone."""

    def __init__(self, cfg):
        self.cfg = cfg
        self.bm = bmesh.new()
        self.dl = self.bm.verts.layers.deform.verify()
        self.groups, self.mats = [], []

    def _gi(self, name):
        if name not in self.groups:
            self.groups.append(name)
        return self.groups.index(name)

    def _mi(self, name, rgb, rough):
        for i, (n, _, _) in enumerate(self.mats):
            if n == name:
                return i
        self.mats.append((name, rgb, rough))
        return len(self.mats) - 1

    def _tag(self, verts, mat, bone):
        mi, gi = self._mi(*mat), self._gi(bone)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index, f.smooth = mi, True
        for v in verts:
            v[self.dl][gi] = 1.0

    def sphere(self, r, loc, mat, bone, sc=(1, 1, 1), rot=(0, 0, 0), u=16, v=10):
        """rot is (tilt forward, roll sideways, turn) in degrees, applied in the (x, front, z) frame."""
        R = Euler((math.radians(-rot[0]), math.radians(rot[1]), math.radians(rot[2])), 'XYZ').to_matrix().to_4x4()
        m = Matrix.Translation(loc) @ R @ Matrix.Diagonal((r * sc[0], r * sc[1], r * sc[2], 1))
        self._tag(bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=1.0, matrix=m)["verts"], mat, bone)

    def limb(self, p0, p1, r0, r1, mat, bone, seg=12):
        d = p1 - p0
        m = Matrix.Translation((p0 + p1) / 2) @ d.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
        self._tag(bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r0, radius2=r1,
                                        depth=d.length, matrix=m)["verts"], mat, bone)

    def shell(self, centre, r, sc, mat, bone, keep):
        """Sphere shell; keep(x, front, z) decides which faces stay (relative to centre)."""
        m = Matrix.Translation(centre) @ Matrix.Diagonal((r * sc[0], r * sc[1], r * sc[2], 1))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=48, v_segments=30, radius=1.0, matrix=m)["verts"]  # dense: the cut edge stays smooth
        dead = []
        for f in {f for v in res for f in v.link_faces}:
            c = f.calc_center_median() - centre
            if not keep(c.x, -c.y, c.z):
                dead.append(f)
        bmesh.ops.delete(self.bm, geom=dead, context='FACES')
        self._tag([v for v in res if v.is_valid and v.link_faces], mat, bone)

    def finish(self):
        me = bpy.data.meshes.new(self.cfg["name"])
        self.bm.to_mesh(me)
        self.bm.free()
        for n, rgb, rough in self.mats:
            mt = bpy.data.materials.new(n)
            mt.use_nodes = True
            b = mt.node_tree.nodes["Principled BSDF"]
            b.inputs["Base Color"].default_value = (*lin(rgb), 1)
            b.inputs["Roughness"].default_value = rough
            b.inputs["Metallic"].default_value = 0.0
            mt.diffuse_color = (*lin(rgb), 1)  # Workbench preview colour
            me.materials.append(mt)
        ob = bpy.data.objects.new(self.cfg["name"] + "_mesh", me)
        bpy.context.scene.collection.objects.link(ob)
        for g in self.groups:
            ob.vertex_groups.new(name=g)
        return ob


def face(P, skin):
    c = P.cfg
    iris, shine = ("Eye", c["eye"], 0.25), ("EyeShine", (255, 255, 255), 0.2)
    lash, blush, mouth = ("Lash", (52, 40, 44), 0.6), ("Blush", (255, 160, 168), 0.9), ("Mouth", (150, 66, 72), 0.6)
    for sx in (-1, 1):
        x, z = sx * 0.092, HC - 0.035
        e = on_head(x, z, -0.012)
        P.sphere(0.05, e, iris, "Head", sc=(0.9, 0.5, 1.28), rot=(0, 0, sx * -12))                       # tall oval eye
        P.sphere(0.019, on_head(x + 0.016, z + 0.03, 0.006), shine, "Head", u=10, v=6)                   # big sparkle
        P.sphere(0.009, on_head(x - 0.015, z - 0.028, 0.004), shine, "Head", u=8, v=6)                   # small sparkle
        P.limb(on_head(x - sx * 0.035, z + 0.06, 0.004), on_head(x + sx * 0.045, z + 0.052, 0.004), 0.0075, 0.005, lash, "Head", seg=6)  # lid line
        P.sphere(0.04, on_head(sx * 0.15, HC - 0.095, -0.004), blush, "Head", sc=(1.15, 0.35, 0.62), rot=(0, 0, sx * -30))
    for k in range(5):  # small smile: a curved row of tiny beads
        t = (k - 2) / 2
        P.sphere(0.0065, on_head(t * 0.022, HC - 0.112 - 0.008 * (1 - t * t), 0.001), mouth, "Head", u=8, v=5)
    for sx in (-1, 1):  # ears, half hidden by the hair
        P.sphere(0.04, B(sx * (HR - 0.01), 0.0, HC - 0.03), skin, "Head", sc=(0.55, 0.8, 1.0))


def hairline(x):
    """Height (relative to the head centre) of the hair edge on the face: high on the forehead, low by the cheeks."""
    q = min(1.0, abs(x) / HR)
    return 0.115 - 0.24 * q ** 1.7


def hair(P, hairm, acc):
    c = P.cfg
    st = c["style"]
    cen = B(0, -0.008, HC + 0.01)
    # cap: top and back of the head, cut along a soft hairline that frames the face
    P.shell(cen, HR + 0.018, (1.03, 1.04, 1.02), hairm, "Head",
            keep=lambda x, f, z: (f < -0.03 or z > 0.075) and z > -0.17)
    # fringe: overlapping soft strands that hang over the forehead, tilted outward
    for k in (-1, 0, 1):  # three soft scallops of fringe hugging the forehead, ending above the eyes
        x = k * 0.085
        z = HC + 0.075 - 0.01 * abs(k)
        P.sphere(0.075, on_head(x, z, 0.002), hairm, "Head", sc=(1.05, 0.3, 0.62), rot=(14, k * 12, 0), u=24, v=14)
    for sx in (-1, 1):  # side locks down to the cheeks
        P.sphere(0.066, on_head(sx * 0.205, HC - 0.02, -0.016), hairm, "Head", sc=(0.45, 0.9, 1.5), rot=(0, sx * 4, sx * 40), u=20, v=12)
    if st == "short":
        P.limb(B(0.0, 0.03, HC + HR + 0.005), B(0.035, 0.07, HC + HR + 0.06), 0.022, 0.006, hairm, "Head", seg=8)  # little ahoge
        P.sphere(0.03, B(0.04, 0.075, HC + HR + 0.06), hairm, "Head")
    elif st == "twin":
        for sx in (-1, 1):
            P.sphere(0.075, B(sx * 0.255, -0.06, HC - 0.07), hairm, "Head", sc=(0.85, 0.85, 1.9), rot=(0, sx * -14, 0))
            P.sphere(0.03, B(sx * 0.215, -0.04, HC + 0.06), ("Ribbon", acc, 0.5), "Head", sc=(1.6, 0.8, 1.0))
            P.sphere(0.03, B(sx * 0.215, -0.04, HC + 0.06), ("Ribbon", acc, 0.5), "Head", sc=(0.6, 1.0, 1.6), rot=(0, 0, 90))
    elif st == "bun":
        P.sphere(0.09, B(0, -0.06, HC + HR + 0.03), hairm, "Head")
        P.sphere(0.06, B(0, -0.05, HC + HR - 0.03), ("HairTie", acc, 0.5), "Head", sc=(1.2, 1.2, 0.35), rot=(-15, 0, 0))
    elif st == "beanie":  # knitted cat-ear beanie over the hair
        hat = ("Beanie", acc, 0.9)
        P.shell(B(0, -0.01, HC + 0.01), HR + 0.026, (1.03, 1.04, 1.04), hat, "Head", keep=lambda x, f, z: z > 0.08)
        P.sphere(HR + 0.014, B(0, -0.008, HC + 0.1), ("BeanieRim", acc, 0.95), "Head", sc=(1.04, 1.05, 0.15))  # snug rolled brim
        P.sphere(0.035, B(0, -0.02, HC + HR + 0.035), hat, "Head")  # pompom
        pink = ("EarInner", (255, 176, 186), 0.9)
        for sx in (-1, 1):
            P.limb(B(sx * 0.14, -0.01, HC + 0.15), B(sx * 0.18, -0.01, HC + 0.3), 0.085, 0.02, hat, "Head", seg=12)    # rounded cat ears
            P.sphere(0.02, B(sx * 0.18, -0.01, HC + 0.3), hat, "Head")
            P.limb(B(sx * 0.14, 0.05, HC + 0.17), B(sx * 0.172, 0.04, HC + 0.27), 0.05, 0.012, pink, "Head", seg=10)
    elif st == "bob":
        P.shell(cen, HR + 0.03, (1.08, 1.07, 1.0), hairm, "Head", keep=lambda x, f, z: f < 0.03 and -0.25 < z < 0.0)  # rounded bob flaring at the nape
        P.sphere(0.024, on_head(0.13, HC + 0.075, 0.03), ("Clip", acc, 0.4), "Head", sc=(1.6, 0.6, 0.8), rot=(0, 0, 25))


def build_body(P):
    c = P.cfg
    skin, hairm = ("Skin", c["skin"], 0.75), ("Hair", c["hair"], 0.7)
    shirt, pants, shoes = ("Shirt", (240, 240, 240), 0.85), ("Pants", c["pants"], 0.85), ("Shoes", c["shoes"], 0.6)
    white = ("Collar", (250, 250, 248), 0.8)
    P.sphere(HR, B(0, 0, HC), skin, "Head", sc=(1.05, 0.98, 0.97), u=28, v=18)
    face(P, skin)
    hair(P, hairm, c["acc"])
    # body: small and soft, a little wider at the bottom
    P.sphere(0.13, B(0, 0, 0.405), shirt, "Spine", sc=(1.0, 0.86, 1.02))
    P.sphere(0.07, B(0, 0.02, 0.505), white, "Spine", sc=(1.35, 1.15, 0.35))  # round collar
    P.sphere(0.128, B(0, 0, 0.3), pants, "Hips", sc=(1.02, 0.86, 0.72))
    for sd, sx in (("L", 1), ("R", -1)):
        sh, el, wr = (B(sx * 0.14, 0, 0.47), B(sx * 0.19, 0, 0.33), B(sx * 0.22, 0, 0.19))
        P.sphere(0.052, sh, shirt, f"UpperArm.{sd}")
        P.limb(sh, el, 0.047, 0.042, shirt, f"UpperArm.{sd}")
        P.limb(el, wr, 0.04, 0.036, skin, f"LowerArm.{sd}")
        P.sphere(0.047, wr, skin, f"Hand.{sd}", sc=(1.0, 0.9, 1.05))  # mitten hand
        hp, kn, an = (B(sx * 0.072, 0, 0.27), B(sx * 0.072, 0, 0.14), B(sx * 0.072, 0, 0.05))
        P.limb(hp, kn, 0.058, 0.05, pants, f"UpperLeg.{sd}")
        P.limb(kn, an, 0.045, 0.042, skin, f"LowerLeg.{sd}")
        P.sphere(0.066, B(sx * 0.074, 0.03, 0.038), shoes, f"Foot.{sd}", sc=(0.95, 1.45, 0.72))


def build_armature(name):
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {}
    for n, (h, t, _) in BONES.items():
        b = arm.edit_bones.new(n)
        b.head, b.tail = B(*h), B(*t)
        eb[n] = b
    for n, (_, _, parent) in BONES.items():
        if parent:
            eb[n].parent = eb[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob


def key_clip(arm_ob, name, frames, fn):
    """fn(t01) -> {bone: (rot_euler_xyz_degrees, loc_xyz)}; keyed on every frame, the loop closes on itself."""
    ad = arm_ob.animation_data_create()
    act = bpy.data.actions.new(name)
    ad.action = act
    bpy.context.view_layer.objects.active = arm_ob
    bpy.ops.object.mode_set(mode='POSE')
    for pb in arm_ob.pose.bones:
        pb.rotation_mode = 'XYZ'
    for f in range(frames + 1):
        pose = fn((f % frames) / frames)
        for pb in arm_ob.pose.bones:
            rot, loc = pose.get(pb.name, ((0, 0, 0), (0, 0, 0)))
            pb.rotation_euler = [math.radians(a) for a in rot]
            pb.location = loc
            pb.keyframe_insert("rotation_euler", frame=f + 1)
            pb.keyframe_insert("location", frame=f + 1)
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in arm_ob.pose.bones:
        pb.rotation_euler, pb.location = (0, 0, 0), (0, 0, 0)
    return act


def idle(t):
    s, c2 = math.sin(2 * math.pi * t), math.sin(4 * math.pi * t)
    p = {"Hips": ((0, 0, 0), (0, 0.006 * c2, 0)), "Head": ((2.0 * s, 0, 4.0 * s), (0, 0, 0))}
    for sd, k in (("L", 1), ("R", -1)):
        p[f"UpperArm.{sd}"] = ((2.5 * s * k, 0, 0), (0, 0, 0))
    return p


def walk(t):
    a = 2 * math.pi * t
    s = math.sin(a)
    p = {"Hips": ((0, 0, 0), (0, 0.02 * abs(math.cos(a)), 0)), "Head": ((0, 0, 4 * s), (0, 0, 0)), "Spine": ((0, 0, -5 * s), (0, 0, 0))}
    for sd, ph in (("L", 0.0), ("R", math.pi)):
        sw = math.sin(a + ph)
        p[f"UpperLeg.{sd}"] = ((38 * sw, 0, 0), (0, 0, 0))
        p[f"LowerLeg.{sd}"] = ((max(0.0, -math.cos(a + ph)) * 45, 0, 0), (0, 0, 0))
        p[f"UpperArm.{sd}"] = ((-34 * sw, 0, 0), (0, 0, 0))
        p[f"LowerArm.{sd}"] = ((-max(0.0, -sw) * 25, 0, 0), (0, 0, 0))
    return p


def build_person(cfg):
    P = Person(cfg)
    build_body(P)
    mesh = P.finish()
    arm = build_armature(cfg["name"])
    mesh.parent = arm
    mesh.modifiers.new("Armature", 'ARMATURE').object = arm
    return arm, mesh


def to_nla(arm, clips):
    ad = arm.animation_data
    for nm, act in clips:
        tr = ad.nla_tracks.new()
        tr.name = nm
        tr.strips.new(nm, 1, act)
    ad.action = None


def export(arm, mesh, path):
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    mesh.select_set(True)
    kw = dict(filepath=path, export_format='GLB', export_yup=True, use_selection=True, export_animations=True,
              export_materials='EXPORT', export_skins=True, export_lights=False, export_cameras=False)
    try:
        bpy.ops.export_scene.gltf(export_animation_mode='NLA_TRACKS', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(export_nla_strips=True, **kw)
    print("EXPORTED", path, os.path.getsize(path))


def preview(png, arms):
    """Two rows: front three-quarter (idle) and back view, to judge both sides."""
    sc = bpy.context.scene
    for i, arm in enumerate(arms):
        arm.location = ((i - 2) * 0.75, 0, 0)
        arm.rotation_euler = (0, 0, math.radians(-25))
        twin = arm.copy()
        twin.data = arm.data
        sc.collection.objects.link(twin)
        twin.location = ((i - 2) * 0.75, 3.0, 0)
        twin.rotation_euler = (0, 0, math.radians(180))
        mesh = next(o for o in bpy.data.objects if o.parent == arm)
        m2 = mesh.copy()
        sc.collection.objects.link(m2)
        m2.parent = twin
        m2.modifiers["Armature"].object = twin
    floor = bpy.data.materials.new("PreviewFloor")
    floor.diffuse_color = (0.86, 0.84, 0.8, 1)
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 1.5, 0))
    bpy.context.object.data.materials.append(floor)
    cd = bpy.data.cameras.new("cam")
    cd.type = 'ORTHO'
    cd.ortho_scale = 3.9
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    cam.location = Vector((0.0, -6.0, 1.9))
    cam.rotation_euler = (math.radians(78), 0, 0)
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light, sh.color_type, sh.show_shadows, sh.show_cavity = 'STUDIO', 'MATERIAL', True, True
    sc.world = bpy.data.worlds.new("w")
    sc.render.resolution_x, sc.render.resolution_y = 1500, 900
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", png)


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    built = []
    for cfg in PEOPLE:
        arm, mesh = build_person(cfg)
        ai = key_clip(arm, "Idle." + cfg["name"], 60, idle)
        aw = key_clip(arm, "Walk." + cfg["name"], 24, walk)
        built.append((arm, mesh, ai, aw))
    if PREVIEW:
        preview(PREVIEW, [a for a, _, _, _ in built])
    else:
        for arm, mesh, ai, aw in built:
            to_nla(arm, [("Idle", ai), ("Walk", aw)])
            export(arm, mesh, os.path.abspath(os.path.join(OUTDIR, arm.name + ".glb")))
