"""Build the chibi girl and boy of the agent office (toon look: the page shades them with MeshToonMaterial + outline).

Design reference: a QC girl with twin tails, a curly ahoge, a star hair clip, big blue eyes with two highlights,
a mint puff-sleeve shirt with a white collar tab, a pink skirt, white socks and pink sneakers; the boy shares the
face and body language with short hair and shorts.

Outputs web/models/chibi_girl.glb and chibi_boy.glb. Each has the bone names the page's sit/typing pose code looks
for (Hips, UpperLeg/LowerLeg/Foot, UpperArm/LowerArm, Head, Head_end; .L = +X), faces +Z in glTF, is 1.0 tall
(Head_end at y=1.0), and names its materials "Shirt" (tinted with the lane colour) and "Hair" (tinted per agent).

Run from mcp-servers/agent-office/:
    blender -b --factory-startup --python blender/build_chibi.py
    blender -b --factory-startup --python blender/build_chibi.py -- --preview /path/out.png

Helper coordinates are (x, front, z): front is the way the face looks, converted to Blender -Y.
"""
import bpy, bmesh, math, os, sys
from mathutils import Matrix, Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..", "web", "models")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else None

SKIN, HAIR = (246, 198, 168), (116, 74, 58)
PEOPLE = [
    dict(name="chibi_girl", girl=True, eye=(70, 104, 196), tie=(238, 104, 138), bottom=(238, 128, 160), shoes=(236, 92, 120)),
    dict(name="chibi_boy", girl=False, eye=(70, 104, 196), tie=None, bottom=(92, 112, 168), shoes=(84, 140, 220)),
]

HC, HR = 0.725, 0.265  # head centre height and radius: the head is a bit over half the height

BONES = {  # bone: (head, tail, parent), points are (x, front, z); .L is +X
    "Hips": ((0, 0, 0.2), (0, 0, 0.25), None),
    "Spine": ((0, 0, 0.25), (0, 0, 0.44), "Hips"),
    "Neck": ((0, 0, 0.44), (0, 0, 0.47), "Spine"),
    "Head": ((0, 0, 0.47), (0, 0, 1.0), "Neck"),
    "Head_end": ((0, 0, 1.0), (0, 0, 1.03), "Head"),
}
for sd, sx in (("L", 1), ("R", -1)):
    BONES.update({
        f"UpperArm.{sd}": ((sx * 0.125, 0, 0.415), (sx * 0.165, 0, 0.33), "Spine"),
        f"LowerArm.{sd}": ((sx * 0.165, 0, 0.33), (sx * 0.19, 0, 0.225), f"UpperArm.{sd}"),
        f"Hand.{sd}": ((sx * 0.19, 0, 0.225), (sx * 0.2, 0, 0.18), f"LowerArm.{sd}"),
        f"UpperLeg.{sd}": ((sx * 0.06, 0, 0.2), (sx * 0.06, 0, 0.12), "Hips"),
        f"LowerLeg.{sd}": ((sx * 0.06, 0, 0.12), (sx * 0.06, 0, 0.05), f"UpperLeg.{sd}"),
        f"Foot.{sd}": ((sx * 0.06, 0, 0.05), (sx * 0.06, 0.06, 0.02), f"LowerLeg.{sd}"),
    })


def B(x, f, z):
    return Vector((x, -f, z))


def lin(rgb):
    return [((c / 255) / 12.92 if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4) for c in rgb]


def on_head(x, z, out=0.0, r=HR):
    """Point on the front of the head sphere at x, z, pushed `out` along the surface normal."""
    dz = z - HC
    f = math.sqrt(max(0.0, r * r - x * x - dz * dz))
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

    def _mi(self, name, rgb):
        for i, (n, _) in enumerate(self.mats):
            if n == name:
                return i
        self.mats.append((name, rgb))
        return len(self.mats) - 1

    def _tag(self, verts, mat, bone, smooth=True):
        mi, gi = self._mi(*mat), self._gi(bone)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index, f.smooth = mi, smooth
        for v in verts:
            v[self.dl][gi] = 1.0

    def sphere(self, r, loc, mat, bone, sc=(1, 1, 1), rot=(0, 0, 0), u=20, v=12):
        """rot: (tilt forward, roll sideways, turn) in degrees in the (x, front, z) frame."""
        R = Euler((math.radians(-rot[0]), math.radians(rot[1]), math.radians(rot[2])), 'XYZ').to_matrix().to_4x4()
        m = Matrix.Translation(loc) @ R @ Matrix.Diagonal((r * sc[0], r * sc[1], r * sc[2], 1))
        self._tag(bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=1.0, matrix=m)["verts"], mat, bone)

    def limb(self, p0, p1, r0, r1, mat, bone, seg=12, caps=True):
        d = p1 - p0
        m = Matrix.Translation((p0 + p1) / 2) @ d.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
        self._tag(bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r0, radius2=r1,
                                        depth=d.length, matrix=m)["verts"], mat, bone)
        if caps:  # round joints so bends never show a cut end
            self.sphere(r0, p0, mat, bone, u=12, v=8)
            self.sphere(r1, p1, mat, bone, u=12, v=8)

    def tube(self, pts, r, mat, bone):
        """A drawn stroke: chain of rounded segments through pts (used for the mouth, lashes and ahoge)."""
        for a, b in zip(pts, pts[1:]):
            self.limb(a, b, r, r, mat, bone, seg=8)

    def shell(self, centre, r, sc, mat, bone, keep, u=48, v=30):
        m = Matrix.Translation(centre) @ Matrix.Diagonal((r * sc[0], r * sc[1], r * sc[2], 1))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=1.0, matrix=m)["verts"]
        dead = []
        for f in {f for v in res for f in v.link_faces}:
            c = f.calc_center_median() - centre
            if not keep(c.x, -c.y, c.z):
                dead.append(f)
        bmesh.ops.delete(self.bm, geom=dead, context='FACES')
        self._tag([v for v in res if v.is_valid and v.link_faces], mat, bone)

    def star(self, centre, normal, r, mat, bone, depth=0.012):
        """Five-point star plate facing `normal`."""
        n = normal.normalized()
        q = n.to_track_quat('Z', 'Y')
        pts = []
        for k in range(10):
            a = math.pi / 2 + k * math.pi / 5
            rr = r if k % 2 == 0 else r * 0.45
            pts.append(q @ Vector((rr * math.cos(a), rr * math.sin(a), 0)))
        front = [self.bm.verts.new(centre + p + n * depth / 2) for p in pts]
        back = [self.bm.verts.new(centre + p - n * depth / 2) for p in pts]
        self.bm.faces.new(front)
        self.bm.faces.new(list(reversed(back)))
        for k in range(10):
            self.bm.faces.new([front[k], back[k], back[(k + 1) % 10], front[(k + 1) % 10]])
        self._tag(front + back, mat, bone, smooth=False)

    def finish(self):
        me = bpy.data.meshes.new(self.cfg["name"])
        self.bm.to_mesh(me)
        self.bm.free()
        for n, rgb in self.mats:
            mt = bpy.data.materials.new(n)
            mt.use_nodes = True
            b = mt.node_tree.nodes["Principled BSDF"]
            b.inputs["Base Color"].default_value = (*lin(rgb), 1)
            b.inputs["Roughness"].default_value = 0.9
            b.inputs["Metallic"].default_value = 0.0
            mt.diffuse_color = (*lin(rgb), 1)
            me.materials.append(mt)
        ob = bpy.data.objects.new(self.cfg["name"] + "_mesh", me)
        bpy.context.scene.collection.objects.link(ob)
        for g in self.groups:
            ob.vertex_groups.new(name=g)
        return ob


def face(P):
    c = P.cfg
    iris, pupil, shine = ("Eye", c["eye"]), ("Pupil", (30, 28, 62)), ("EyeShine", (255, 255, 255))
    ink, blush = ("Ink", (52, 36, 40)), ("Blush", (246, 160, 172))
    for sx in (-1, 1):
        x, z = sx * 0.105, HC - 0.045
        P.sphere(0.064, on_head(x, z, -0.02), iris, "Head", sc=(0.82, 0.42, 1.12))                      # big blue iris
        P.sphere(0.04, on_head(x + sx * 0.004, z - 0.006, -0.006), pupil, "Head", sc=(0.8, 0.4, 1.12))  # dark pupil
        P.sphere(0.019, on_head(x - sx * 0.012, z + 0.03, 0.006), shine, "Head", u=10, v=6)             # big highlight
        P.sphere(0.009, on_head(x + sx * 0.022, z - 0.034, 0.004), shine, "Head", u=8, v=6)             # small highlight
        P.tube([on_head(x + sx * dx, z + dz, 0.004) for dx, dz in ((-0.045, 0.05), (-0.015, 0.072), (0.02, 0.074), (0.05, 0.06))],
               0.0065, ink, "Head")                                                                      # upper lash line
        P.sphere(0.042, on_head(sx * 0.165, HC - 0.11, -0.006), blush, "Head", sc=(1.2, 0.3, 0.6))
    P.tube([on_head(dx, HC - 0.145 - 0.022 * (1 - (dx / 0.045) ** 2), 0.004) for dx in (-0.045, -0.025, 0.0, 0.025, 0.045)],
           0.0065, ink, "Head")                                                                          # smile stroke


def hair(P):
    c, hairm = P.cfg, ("Hair", HAIR)
    cen = B(0, -0.01, HC + 0.012)
    P.shell(cen, HR + 0.02, (1.03, 1.04, 1.02), hairm, "Head", keep=lambda x, f, z: (f < -0.04 or z > 0.07) and z > -0.17)
    for x in (-0.16, -0.055, 0.055, 0.16):  # four big round scallops of fringe down to the eyelids
        P.sphere(0.088, on_head(x, HC + 0.075 - 0.25 * x * x, 0.0), hairm, "Head", sc=(1.0, 0.42, 0.78), rot=(10, x * 60, 0))
    for sx in (-1, 1):  # side locks framing the face down to the chin line
        P.sphere(0.06, B(sx * 0.252, 0.03, HC - 0.06), hairm, "Head", sc=(0.5, 0.9, 1.75), rot=(0, sx * 6, sx * 20))
    P.tube([B(0.0, 0.02, HC + HR + 0.005), B(0.01, 0.03, HC + HR + 0.06), B(-0.015, 0.035, HC + HR + 0.1),
            B(0.01, 0.03, HC + HR + 0.135), B(0.045, 0.02, HC + HR + 0.14)], 0.012, hairm, "Head")    # curly ahoge
    if c["girl"]:
        tie = ("HairTie", c["tie"])
        for sx in (-1, 1):  # big drooping twin tails with pink ties
            P.sphere(0.1, B(sx * 0.34, -0.03, HC - 0.03), hairm, "Head", sc=(0.75, 0.8, 1.75), rot=(0, sx * -38, 0), u=22, v=14)
            P.sphere(0.045, B(sx * 0.255, -0.02, HC + 0.09), tie, "Head")
        P.star(on_head(0.14, HC + 0.16, 0.03, HR + 0.02), Vector((0.45, -0.75, 0.5)), 0.05, ("Star", (250, 210, 80)), "Head")
    else:
        for sx in (-1, 1):  # short side hair over the ears, a little tuft at the back
            P.sphere(0.075, B(sx * 0.235, -0.04, HC - 0.02), hairm, "Head", sc=(0.55, 0.95, 1.2))
        P.sphere(0.09, B(0, -0.2, HC - 0.1), hairm, "Head", sc=(1.6, 0.7, 0.8))


def build_body(P):
    c = P.cfg
    skin, shirt, white = ("Skin", SKIN), ("Shirt", (148, 214, 196)), ("Collar", (255, 255, 255))
    bottom, sock, shoe = ("Bottom", c["bottom"]), ("Sock", (255, 255, 255)), ("Shoes", c["shoes"])
    P.sphere(HR, B(0, 0, HC), skin, "Head", sc=(1.04, 0.98, 0.97), u=32, v=20)
    for sx in (-1, 1):
        P.sphere(0.04, B(sx * (HR - 0.005), -0.01, HC - 0.04), skin, "Head", sc=(0.5, 0.8, 1.0))
    face(P)
    hair(P)
    P.limb(B(0, 0, 0.44), B(0, 0, 0.48), 0.04, 0.04, skin, "Neck", caps=False)
    P.sphere(0.115, B(0, 0, 0.36), shirt, "Spine", sc=(1.0, 0.85, 1.0))
    P.sphere(0.04, B(0, 0.095, 0.37), white, "Spine", sc=(0.75, 0.4, 1.4))                              # white collar tab
    P.sphere(0.024, B(0.06, 0.09, 0.31), ("Badge", (255, 255, 255)), "Spine", sc=(1.4, 0.4, 1.0))       # little name badge
    if c["girl"]:
        P.limb(B(0, 0, 0.27), B(0, 0, 0.15), 0.1, 0.165, bottom, "Hips", seg=16, caps=False)             # flared skirt
    else:
        P.sphere(0.11, B(0, 0, 0.24), bottom, "Hips", sc=(1.0, 0.85, 0.6))                              # shorts
    for sd, sx in (("L", 1), ("R", -1)):
        sh, el, wr = B(sx * 0.125, 0, 0.415), B(sx * 0.165, 0, 0.33), B(sx * 0.19, 0, 0.225)
        P.sphere(0.06, sh, shirt, f"UpperArm.{sd}", sc=(1.0, 1.0, 0.95))                                # puff sleeve
        P.limb(sh, el, 0.042, 0.038, skin, f"UpperArm.{sd}")
        P.limb(el, wr, 0.038, 0.035, skin, f"LowerArm.{sd}")
        P.sphere(0.048, wr, skin, f"Hand.{sd}")
        hp, kn, an = B(sx * 0.06, 0, 0.2), B(sx * 0.06, 0, 0.12), B(sx * 0.06, 0, 0.05)
        P.limb(hp, kn, 0.042 if c["girl"] else 0.048, 0.04, sock if c["girl"] else bottom, f"UpperLeg.{sd}")
        P.limb(kn, an, 0.04, 0.04, sock, f"LowerLeg.{sd}")
        P.sphere(0.062, B(sx * 0.062, 0.025, 0.045), shoe, f"Foot.{sd}", sc=(0.95, 1.4, 0.72))
        P.sphere(0.06, B(sx * 0.062, 0.03, 0.02), ("Sole", (255, 255, 255)), f"Foot.{sd}", sc=(1.0, 1.45, 0.3))


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
    """Flat-lit, outlined preview (close to the page's toon look): front, three-quarter and back of each person."""
    sc = bpy.context.scene
    k = 0
    for arm in arms:
        mesh = next(o for o in bpy.data.objects if o.parent == arm)
        for j, yaw in enumerate((0, -30, 180)):
            a2, m2 = (arm, mesh) if j == 0 else (arm.copy(), mesh.copy())
            if j:
                sc.collection.objects.link(a2)
                sc.collection.objects.link(m2)
                m2.parent = a2
                m2.modifiers["Armature"].object = a2
            a2.location = ((k - 2.5) * 0.75, 0, 0)
            a2.rotation_euler = (0, 0, math.radians(yaw))
            k += 1
    cd = bpy.data.cameras.new("cam")
    cd.type = 'ORTHO'
    cd.ortho_scale = 4.6
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    cam.location = Vector((0.0, -6.0, 0.55))
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light, sh.color_type, sh.show_object_outline = 'FLAT', 'MATERIAL', True
    sh.object_outline_color = (0.16, 0.11, 0.13)
    sh.background_type, sh.background_color = 'VIEWPORT', (0.99, 0.95, 0.96)
    sc.render.resolution_x, sc.render.resolution_y = 1500, 380
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
