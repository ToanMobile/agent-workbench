"""Build five chibi people (big head, big sparkly eyes, short limbs) with a skeleton and Idle/Walk clips.

One GLB per person in web/models/chibi1.glb ... chibi5.glb. The skeleton uses the bone names the page's
sit/typing pose code looks for (Hips, UpperLeg/LowerLeg/Foot, UpperArm/LowerArm, Head, Head_end; .L = +X),
the person faces +Z in glTF, is 1.0 tall (Head_end at y=1.0) and the shirt material is named "Shirt"
so the page can tint it with the lane colour. Flat Principled materials, no textures.

Run from mcp-servers/agent-office/:
    blender -b --factory-startup --python blender/build_chibi.py
Optional preview (all five walking, plus a seated-style front view):
    blender -b --factory-startup --python blender/build_chibi.py -- --preview /path/out.png

Coordinates in the helpers are (x, front, z): front is the way the face looks, converted to Blender -Y.
"""
import bpy, bmesh, math, os, sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..", "web", "models")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else None

PEOPLE = [  # shirt tint comes from the page; the rest is fixed per person
    dict(name="chibi1", skin=(255, 224, 196), hair=(92, 62, 44), style="short", pants=(52, 66, 110), shoes=(48, 44, 52), tie=None),
    dict(name="chibi2", skin=(244, 208, 176), hair=(74, 48, 62), style="twin", pants=(120, 76, 120), shoes=(214, 90, 120), tie=(255, 130, 170)),
    dict(name="chibi3", skin=(230, 186, 150), hair=(34, 32, 42), style="bun", pants=(60, 70, 62), shoes=(60, 56, 64), tie=(240, 190, 70)),
    dict(name="chibi4", skin=(255, 228, 206), hair=(246, 208, 88), style="spiky", pants=(80, 84, 96), shoes=(214, 100, 60), tie=None),
    dict(name="chibi5", skin=(198, 146, 106), hair=(166, 92, 66), style="bob", pants=(48, 90, 96), shoes=(235, 235, 235), tie=None),
]

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
        f"UpperArm.{sd}": ((sx * 0.15, 0, 0.46), (sx * 0.2, 0, 0.31), "Spine"),
        f"LowerArm.{sd}": ((sx * 0.2, 0, 0.31), (sx * 0.23, 0, 0.17), f"UpperArm.{sd}"),
        f"Hand.{sd}": ((sx * 0.23, 0, 0.17), (sx * 0.24, 0, 0.12), f"LowerArm.{sd}"),
        f"UpperLeg.{sd}": ((sx * 0.075, 0, 0.27), (sx * 0.075, 0, 0.14), "Hips"),
        f"LowerLeg.{sd}": ((sx * 0.075, 0, 0.14), (sx * 0.075, 0, 0.05), f"UpperLeg.{sd}"),
        f"Foot.{sd}": ((sx * 0.075, 0, 0.05), (sx * 0.075, 0.06, 0.02), f"LowerLeg.{sd}"),
    })


def B(x, f, z):
    return Vector((x, -f, z))


def lin(rgb):
    return [((c / 255) / 12.92 if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4) for c in rgb]


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
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index, f.smooth = mi, True
        for v in verts:
            v[self.dl][gi] = 1.0

    def sphere(self, r, loc, mat, bone, sc=(1, 1, 1), u=16, v=10):
        m = Matrix.Translation(loc) @ Matrix.Diagonal((r * sc[0], r * sc[1], r * sc[2], 1))
        self._tag(bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=1.0, matrix=m)["verts"], mat, bone)

    def limb(self, p0, p1, r0, r1, mat, bone, seg=10):
        d = p1 - p0
        rot = d.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
        m = Matrix.Translation((p0 + p1) / 2) @ rot
        self._tag(bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r0, radius2=r1,
                                        depth=d.length, matrix=m)["verts"], mat, bone)

    def cone_up(self, base, tip, r, mat, bone):
        self.limb(base, tip, r, 0.004, mat, bone, seg=8)

    def hair_cap(self, centre, r, sc, mat):
        """Sphere shell for the top and back of the head: the front/lower faces are cut away so the face stays visible."""
        m = Matrix.Translation(centre) @ Matrix.Diagonal((r * sc[0], r * sc[1], r * sc[2], 1))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=20, v_segments=12, radius=1.0, matrix=m)["verts"]
        dead = [f for f in {f for v in res for f in v.link_faces}
                if (f.calc_center_median().y < centre.y - 0.02 and f.calc_center_median().z < centre.z + 0.075)  # front, below the fringe
                or f.calc_center_median().z < centre.z - 0.02]                                                 # below the ears
        bmesh.ops.delete(self.bm, geom=dead, context='FACES')
        keep = [v for v in res if v.is_valid and v.link_faces]
        self._tag(keep, mat, "Head")

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


def build_body(P):
    c = P.cfg
    skin, hair = ("Skin", c["skin"], 0.7), ("Hair", c["hair"], 0.8)
    shirt, pants, shoes = ("Shirt", (240, 240, 240), 0.85), ("Pants", c["pants"], 0.85), ("Shoes", c["shoes"], 0.6)
    dark, white = ("EyeDark", (36, 30, 44), 0.25), ("EyeShine", (255, 255, 255), 0.2)
    pink, mouth = ("Blush", (255, 150, 160), 0.8), ("Mouth", (176, 70, 82), 0.5)
    # head: wide and round, the face sits on the front
    hc = B(0, 0, 0.745)
    P.sphere(0.25, hc, skin, "Head", sc=(1.06, 0.98, 0.96), u=24, v=16)
    for sx in (-1, 1):
        P.sphere(0.058, B(sx * 0.098, 0.208, 0.725), dark, "Head", sc=(1.0, 0.55, 1.4))                    # big eyes
        P.sphere(0.02, B(sx * 0.098 + 0.02, 0.236, 0.765), white, "Head", u=10, v=6)                      # main sparkle
        P.sphere(0.011, B(sx * 0.098 - 0.02, 0.236, 0.69), white, "Head", u=8, v=6)                       # small sparkle
        P.sphere(0.046, B(sx * 0.16, 0.17, 0.665), pink, "Head", sc=(1.0, 0.3, 0.6))                      # blush
        P.limb(B(sx * 0.12, 0.226, 0.795), B(sx * 0.07, 0.232, 0.806), 0.008, 0.008, dark, "Head", seg=6)  # tiny brows
    P.sphere(0.022, B(0, 0.244, 0.655), mouth, "Head", sc=(1.0, 0.4, 0.55), u=10, v=6)
    # hair
    P.hair_cap(hc + Vector((0, 0.012, 0.015)), 0.268, (1.04, 1.02, 1.0), hair)
    st = c["style"]
    bang_z = 0.85
    for x, f, z, s in ((-0.1, 0.19, bang_z - 0.015, 0.075), (0.0, 0.205, bang_z, 0.085), (0.1, 0.19, bang_z - 0.015, 0.075)):
        P.sphere(s, B(x, f, z), hair, "Head", sc=(1.0, 0.5, 0.62))
    if st == "twin":
        for sx in (-1, 1):
            P.sphere(0.07, B(sx * 0.27, -0.02, 0.64), hair, "Head", sc=(0.9, 0.9, 2.1))
            P.sphere(0.034, B(sx * 0.255, -0.02, 0.76), ("HairTie", c["tie"], 0.5), "Head", u=10, v=6)
    elif st == "bun":
        P.sphere(0.095, B(0, -0.08, 1.015), hair, "Head")
        P.sphere(0.04, B(0, -0.08, 0.955), ("HairTie", c["tie"], 0.5), "Head", sc=(1.5, 1.5, 0.6), u=10, v=6)
    elif st == "spiky":
        for k, (x, f, h) in enumerate(((-0.14, 0.02, 0.1), (-0.07, 0.06, 0.13), (0.0, 0.09, 0.14), (0.07, 0.06, 0.13), (0.14, 0.02, 0.1))):
            P.cone_up(B(x, f - 0.03, 0.97), B(x * 1.25, f, 0.97 + h), 0.05, hair, "Head")
    elif st == "bob":
        P.sphere(0.27, B(0, -0.06, 0.69), hair, "Head", sc=(1.0, 0.82, 0.62))
    else:  # short: a little tuft
        P.cone_up(B(0.02, 0.1, 0.995), B(0.07, 0.14, 1.07), 0.04, hair, "Head")
    # body
    P.sphere(0.135, B(0, 0, 0.405), shirt, "Spine", sc=(1.0, 0.85, 1.0))
    P.sphere(0.125, B(0, 0, 0.29), pants, "Hips", sc=(1.0, 0.85, 0.8))
    for sd, sx in (("L", 1), ("R", -1)):
        sh, el, wr = (B(sx * 0.15, 0, 0.46), B(sx * 0.2, 0, 0.31), B(sx * 0.23, 0, 0.17))
        P.sphere(0.055, sh, shirt, f"UpperArm.{sd}")
        P.limb(sh, el, 0.046, 0.04, shirt, f"UpperArm.{sd}")
        P.sphere(0.04, el, skin, f"LowerArm.{sd}")
        P.limb(el, wr, 0.038, 0.034, skin, f"LowerArm.{sd}")
        P.sphere(0.052, wr, skin, f"Hand.{sd}")
        hp, kn, an = (B(sx * 0.075, 0, 0.27), B(sx * 0.075, 0, 0.14), B(sx * 0.075, 0, 0.05))
        P.limb(hp, kn, 0.06, 0.052, pants, f"UpperLeg.{sd}")
        P.limb(kn, an, 0.048, 0.044, skin, f"LowerLeg.{sd}")
        P.sphere(0.07, B(sx * 0.075, 0.025, 0.038), shoes, f"Foot.{sd}", sc=(0.95, 1.5, 0.75))


def build_armature(name):
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {}
    for n, (h, t, parent) in BONES.items():
        b = arm.edit_bones.new(n)
        b.head, b.tail = B(*h), B(*t)
        eb[n] = b
    for n, (_, _, parent) in BONES.items():
        if parent:
            eb[n].parent = eb[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob


def key_clip(arm_ob, name, frames, fn):
    """fn(t01) -> {bone: (rot_euler_xyz_degrees, loc_xyz)}; keyed on every frame, linear loop (first == last)."""
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
    s = math.sin(2 * math.pi * t)
    c2 = math.sin(4 * math.pi * t)
    p = {"Hips": ((0, 0, 0), (0, 0.006 * c2, 0)), "Head": ((2.0 * s, 0, 3.0 * s), (0, 0, 0))}
    for sd, k in (("L", 1), ("R", -1)):
        p[f"UpperArm.{sd}"] = ((2.5 * s * k, 0, 0), (0, 0, 0))
    return p


def walk(t):
    a = 2 * math.pi * t
    s = math.sin(a)
    p = {"Hips": ((0, 0, 0), (0, 0.018 * abs(math.cos(a)), 0)), "Head": ((0, 0, 4 * s), (0, 0, 0)), "Spine": ((0, 0, -5 * s), (0, 0, 0))}
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
    mod = mesh.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
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


def preview(png, people):
    sc = bpy.context.scene
    for i, (arm, _) in enumerate(people):
        arm.location = (0, 0, 0)
        arm.location.x = (i - 2) * 0.9
        act = bpy.data.actions.get("Walk." + arm.name)
        arm.animation_data_create()
        arm.animation_data.nla_tracks.clear() if arm.animation_data.nla_tracks else None
        arm.animation_data.action = act
    sc.frame_set(7)
    floor = bpy.data.materials.new("PreviewFloor")
    floor.diffuse_color = (0.8, 0.78, 0.74, 1)
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    bpy.context.object.data.materials.append(floor)
    cd = bpy.data.cameras.new("cam")
    cd.type = 'ORTHO'
    cd.ortho_scale = 4.6
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    cam.location = Vector((0.0, -5.0, 0.9))
    cam.rotation_euler = (math.radians(88), 0, 0)
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light, sh.color_type, sh.show_shadows = 'STUDIO', 'MATERIAL', True
    sc.render.resolution_x, sc.render.resolution_y = 1500, 520
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
        preview(PREVIEW, [(a, m) for a, m, _, _ in built])
    else:
        for arm, mesh, ai, aw in built:
            to_nla(arm, [("Idle", ai), ("Walk", aw)])
            export(arm, mesh, os.path.abspath(os.path.join(OUTDIR, arm.name + ".glb")))
