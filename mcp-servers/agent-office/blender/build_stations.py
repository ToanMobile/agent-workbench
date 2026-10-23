"""Build standing work stations for the QA and Review lanes (people do not type code there).

Roots in web/models/stations.glb, same "desk frame" as office.glb (floor y=0, the person stands at
x=-0.8 facing +X, Z is sideways). Stations fit a software product team, not a factory or a court:
  QA      QABench (phones on test stands), QACheckboard (checklist), QADeviceWall (phone grid),
          QABugBoard (sticky-note kanban), QAMonitorWall (test dashboards + high table with laptop)
  Review  ReviewWall (PR diffs pinned on a board), ReviewDiffScreen (code diff on a wall screen),
          ReviewHuddle (standing round table with laptops), ReviewFlowBoard (flow chart whiteboard)

Run from mcp-servers/agent-office/:
    blender -b --factory-startup --python blender/build_stations.py
    blender -b --factory-startup --python blender/build_stations.py -- --preview /path/out.png
"""
import bpy, sys, os, math
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_office as B  # noqa: E402
from build_office import G, cube, cyl, join, mat  # noqa: E402

B.OUT = os.path.join(B.HERE, "..", "web", "models", "stations.glb")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else None


def ball(r, loc, m, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=12, ring_count=8, location=G(*loc))
    o = bpy.context.object
    o.scale = (scale[0], scale[2], scale[1])
    return B._finish(o, m, smooth=True)


def phone(x, y, z, ok, rot=(0, 0, 0)):
    body = mat("PhoneBody", (34, 36, 42), 0.4)
    screen = mat("ScreenOK", (88, 196, 120), 0.3) if ok else mat("ScreenBad", (224, 82, 82), 0.3)
    return [cube((0.07, 0.012, 0.14), (x, y, z), body, bevel=0.004, rot=rot),
            cube((0.058, 0.014, 0.12), (x, y, z), screen, bevel=0, rot=rot)]


def magnifier(x, y, z):
    frame = mat("MagFrame", (58, 61, 68), 0.5)
    glass = mat("MagGlass", (150, 205, 230), 0.15)
    return [cyl(0.055, 0.012, (x, y, z), frame, rot=(math.pi / 2, 0, 0), verts=16),
            cyl(0.045, 0.014, (x, y, z), glass, rot=(math.pi / 2, 0, 0), verts=16),
            cyl(0.012, 0.13, (x, y - 0.1, z), frame, rot=(0, 0, 0), verts=8)]


def sheet(loc, dims, rot=(0, 0, 0)):
    """Paper with grey text lines and red/green diff lines along its length (glTF z)."""
    paper = mat("Paper", (246, 244, 238), 0.9)
    red, grn = mat("DiffRed", (226, 92, 92), 0.8), mat("DiffGreen", (96, 190, 120), 0.8)
    ink = mat("InkGrey", (170, 172, 178), 0.9)
    p = [cube(dims, loc, paper, bevel=0.0, rot=rot)]
    for i in range(6):
        off = -dims[2] / 2 + 0.07 + i * (dims[2] - 0.14) / 5
        p.append(cube((dims[0] * 0.72, dims[1] + 0.004, 0.018), (loc[0], loc[1], loc[2] + off),
                      red if i in (1, 4) else grn if i == 2 else ink, bevel=0, rot=rot))
    return p


def vsheet(x, y, z, w, h):
    """Upright paper (faces -x) with horizontal diff lines, for the pinboard."""
    paper = mat("Paper", (246, 244, 238), 0.9)
    red, grn = mat("DiffRed", (226, 92, 92), 0.8), mat("DiffGreen", (96, 190, 120), 0.8)
    ink = mat("InkGrey", (170, 172, 178), 0.9)
    p = [cube((0.01, h, w), (x, y, z), paper, bevel=0.0)]
    for i in range(6):
        p.append(cube((0.01, 0.02, w * (0.72 if i % 2 else 0.55)), (x - 0.006, y + h / 2 - 0.07 - i * (h - 0.14) / 5, z),
                      red if i in (1, 4) else grn if i == 2 else ink, bevel=0))
    return p


def build_qa_bench():
    top = mat("BenchTop", (150, 118, 86), 0.7)
    frame = mat("BenchFrame", (58, 61, 68), 0.6)
    glass = mat("JarGlass", (170, 222, 200), 0.2)
    bug = mat("Bug", (84, 168, 88), 0.6)
    clip = mat("Clipboard", (196, 150, 82), 0.7)
    p = [cube((0.9, 0.05, 1.6), (0.35, 0.95, 0), top, bevel=0.01, seg=2)]
    for z in (-0.7, 0.7):
        for x in (0.0, 0.7):
            p.append(cube((0.06, 0.93, 0.06), (x, 0.465, z), frame, bevel=0.004))
        p.append(cube((0.72, 0.04, 0.05), (0.35, 0.25, z), frame, bevel=0.004))
    for i, z in enumerate((-0.2, 0.05, 0.3)):  # phones on test stands, one of them failing
        p.append(cube((0.1, 0.012, 0.1), (0.3, 0.986, z), frame, bevel=0.003))
        p += phone(0.3, 1.04, z, ok=i != 1, rot=(0, math.radians(75), 0))
    p += phone(0.1, 0.982, 0.5, True) + phone(0.1, 0.982, 0.65, True)  # waiting flat on the bench
    p += magnifier(0.5, 1.2, 0.0)
    p += [cube((0.22, 0.012, 0.3), (0.2, 0.98, -0.55), clip, bevel=0.003, rot=(0, math.radians(8), 0))]
    p += sheet((0.2, 0.99, -0.55), (0.18, 0.004, 0.26), (0, math.radians(8), 0))
    p += [cyl(0.07, 0.14, (0.6, 1.045, -0.2 - 0.35), glass, verts=14), ball(0.04, (0.6, 1.03, -0.55), bug, (1, 0.7, 1.2))]
    for sx in (-1, 1):
        for k in range(3):
            p.append(cyl(0.004, 0.06, (0.6 + sx * 0.035, 1.0, -0.55 + (k - 1) * 0.03), bug,
                         rot=(0, 0, sx * 0.9), verts=6, bevel=0))
    p.append(cube((0.06, 0.5, 1.5), (0.8, 1.22, 0), frame, bevel=0.004))  # device rack behind the bench
    for k in range(4):
        p += phone(0.765, 1.05 + k * 0.11, 0.0, ok=k != 2, rot=(0, 0, math.pi / 2))
    return join(p, "QABench")


def build_qa_checkboard():
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    face = mat("BoardFace", (244, 242, 236), 0.85)
    grn, red = mat("TickGreen", (70, 176, 100), 0.6), mat("CrossRed", (222, 74, 74), 0.6)
    ink = mat("InkGrey", (170, 172, 178), 0.9)
    tray = mat("Tray", (226, 222, 214), 0.8)
    p = [cube((0.04, 1.0, 1.6), (0.5, 1.45, 0), face, bevel=0.004),
         cube((0.06, 0.06, 1.7), (0.5, 0.94, 0), frame, bevel=0.004),
         cube((0.06, 0.06, 1.7), (0.5, 1.96, 0), frame, bevel=0.004)]
    for z in (-0.8, 0.8):
        p.append(cube((0.05, 2.0, 0.06), (0.5, 1.0, z), frame, bevel=0.004))
        p.append(cube((0.5, 0.04, 0.06), (0.5, 0.02, z), frame, bevel=0.004))
    for row in range(5):
        y = 1.78 - row * 0.17
        if row != 2:  # tick = two bars
            p.append(cube((0.015, 0.05, 0.016), (0.47, y - 0.015, -0.62), grn, bevel=0, rot=(math.radians(-45), 0, 0)))
            p.append(cube((0.015, 0.1, 0.016), (0.47, y, -0.575), grn, bevel=0, rot=(math.radians(35), 0, 0)))
        else:  # cross
            p.append(cube((0.015, 0.1, 0.016), (0.47, y, -0.6), red, bevel=0, rot=(math.radians(45), 0, 0)))
            p.append(cube((0.015, 0.1, 0.016), (0.47, y, -0.6), red, bevel=0, rot=(math.radians(-45), 0, 0)))
        p.append(cube((0.012, 0.035, 0.85 - 0.12 * (row % 3)), (0.47, y, 0.1), ink, bevel=0))
    p += [cube((0.34, 0.03, 0.7), (0.25, 0.86, 0.0), tray, bevel=0.006),
          cube((0.34, 0.2, 0.03), (0.25, 0.95, -0.35), tray, bevel=0.004)]
    p += phone(0.25, 0.885, -0.15, True) + phone(0.25, 0.885, 0.1, False)
    return join(p, "QACheckboard")


def stamp(x, y, z):
    red, brass = mat("StampRed", (214, 64, 64), 0.5), mat("Brass", (212, 170, 84), 0.4)
    return [cyl(0.055, 0.02, (x, y, z), red, verts=18), cyl(0.018, 0.07, (x, y + 0.045, z), brass, verts=8),
            cyl(0.034, 0.03, (x, y + 0.09, z), brass, verts=10)]


def build_review_wall():
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    cork = mat("Cork", (196, 156, 108), 0.9)
    pin = mat("PinBlue", (70, 120, 220), 0.5)
    p = [cube((0.05, 1.3, 2.0), (0.9, 1.35, 0), cork, bevel=0.004),
         cube((0.07, 0.07, 2.1), (0.9, 0.68, 0), frame, bevel=0.004),
         cube((0.07, 0.07, 2.1), (0.9, 2.02, 0), frame, bevel=0.004)]
    for z in (-1.0, 1.0):
        p.append(cube((0.06, 2.05, 0.07), (0.9, 1.025, z), frame, bevel=0.004))
        p.append(cube((0.5, 0.05, 0.08), (0.9, 0.025, z), frame, bevel=0.004))
    for col in range(3):
        for row in range(2):
            z, y = -0.62 + col * 0.62, 1.1 + row * 0.55
            p += vsheet(0.87, y, z, 0.44, 0.4)
            p.append(ball(0.02, (0.85, y + 0.17, z), pin))
    p += [cube((0.34, 0.9, 0.34), (0.25, 0.45, 0.55), frame, bevel=0.008),  # stamp stand
          cube((0.36, 0.04, 0.36), (0.25, 0.92, 0.55), frame, bevel=0.006)]
    p += stamp(0.25, 0.96, 0.55)
    return join(p, "ReviewWall")


def build_qa_devicewall():
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    face = mat("WallFace", (52, 58, 70), 0.8)
    ok, bad = mat("ScreenOK", (88, 196, 120), 0.3), mat("ScreenBad", (224, 82, 82), 0.3)
    p = [cube((0.05, 1.45, 2.0), (0.9, 1.3, 0), face, bevel=0.004),
         cube((0.07, 0.07, 2.1), (0.9, 0.55, 0), frame, bevel=0.004), cube((0.07, 0.07, 2.1), (0.9, 2.05, 0), frame, bevel=0.004)]
    for z in (-1.0, 1.0):
        p.append(cube((0.06, 2.1, 0.07), (0.9, 1.05, z), frame, bevel=0.004))
        p.append(cube((0.5, 0.05, 0.08), (0.9, 0.025, z), frame, bevel=0.004))
    for r in range(4):
        for c in range(6):
            p += phone(0.86, 0.88 + r * 0.3, -0.75 + c * 0.3, ok=(r * 6 + c) not in (4, 13, 20), rot=(0, 0, math.pi / 2))
    p += [cube((0.08, 0.14, 0.9), (0.9, 2.2, -0.5), ok, bevel=0.006), cube((0.08, 0.14, 0.9), (0.9, 2.2, 0.55), bad, bevel=0.006)]
    return join(p, "QADeviceWall")


def code_screen(x, y, z, w, h, rows=9, seed=0, mode='mixed'):
    """Dark editor panel facing -x with a diff: grey context lines, red removed, green added, line-number gutter."""
    bg = mat("EditorBg", (30, 34, 44), 0.5)
    red, grn = mat("DiffRed", (226, 92, 92), 0.6), mat("DiffGreen", (96, 190, 120), 0.6)
    ink, blue = mat("CodeGrey", (150, 156, 170), 0.6), mat("CodeBlue", (96, 150, 230), 0.6)
    p = [cube((0.014, h, w), (x, y, z), bg, bevel=0.0)]
    step = (h - 0.14) / (rows - 1)
    for i in range(rows):
        yy = y + h / 2 - 0.07 - i * step
        kind = (i + seed) % 5
        m = red if kind == 1 else grn if kind in (2, 3) else blue if kind == 4 else ink
        if mode != 'mixed':  # split diff: the left pane only shows removals, the right one only additions
            m = (red if mode == 'del' else grn) if kind in (1, 2, 3) else ink
        ln = w * (0.25 + 0.09 * ((i * 7 + seed * 3) % 6))
        ind = 0.06 * ((i + seed) % 3)
        p.append(cube((0.016, 0.022, 0.03), (x - 0.002, yy, z - w / 2 + 0.06), ink, bevel=0))  # gutter number
        p.append(cube((0.016, 0.022, ln), (x - 0.002, yy, z - w / 2 + 0.14 + ind + ln / 2), m, bevel=0))
    return p


def laptop(x, z, yaw=0.0):
    body, glow = mat("LaptopBody", (176, 180, 188), 0.4), mat("EditorBg", (30, 34, 44), 0.5)
    return [cube((0.3, 0.015, 0.22), (x, 1.0, z), body, bevel=0.004, rot=(0, yaw, 0)),
            cube((0.012, 0.2, 0.28), (x + 0.12, 1.1, z), body, bevel=0.004, rot=(0, yaw, 0)),
            cube((0.008, 0.17, 0.25), (x + 0.112, 1.1, z), glow, bevel=0, rot=(0, yaw, 0))]


def mug(x, y, z, col=(240, 240, 236)):
    m = mat("MugW%d" % col[0], col, 0.5)
    return [cyl(0.035, 0.08, (x, y + 0.04, z), m, verts=12), cube((0.012, 0.04, 0.012), (x, y + 0.045, z + 0.045), m, bevel=0)]


def sticky(x, y, z, col, s=0.12):
    return cube((0.006, s, s), (x, y, z), mat("Sticky%d%d" % (col[0], col[1]), col, 0.9), bevel=0)


def board_legs(x, z0, z1, top, w=0.07):
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    p = []
    for z in (z0, z1):
        p.append(cube((0.06, top, w), (x, top / 2, z), frame, bevel=0.004))
        p.append(cube((0.5, 0.04, 0.08), (x, 0.02, z), frame, bevel=0.004))
    return p


def build_qa_bugboard():
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    face = mat("BoardFace", (244, 242, 236), 0.85)
    heads = [mat("HeadTodo", (222, 74, 74), 0.6), mat("HeadDoing", (240, 190, 50), 0.6), mat("HeadDone", (70, 176, 100), 0.6)]
    bug = mat("Bug", (60, 60, 66), 0.6)
    p = [cube((0.05, 1.3, 2.0), (0.9, 1.35, 0), face, bevel=0.004),
         cube((0.07, 0.07, 2.1), (0.9, 0.68, 0), frame, bevel=0.004), cube((0.07, 0.07, 2.1), (0.9, 2.02, 0), frame, bevel=0.004)]
    p += board_legs(0.9, -1.0, 1.0, 2.05)
    cols = [((255, 220, 120), (255, 160, 160), (255, 200, 120)), ((255, 220, 120), (170, 210, 255)),
            ((200, 235, 170), (200, 235, 170), (255, 220, 120), (200, 235, 170))]
    for c in range(3):
        z = -0.62 + c * 0.62
        p.append(cube((0.01, 0.08, 0.5), (0.87, 1.89, z), heads[c], bevel=0))
        p.append(cube((0.006, 1.1, 0.012), (0.872, 1.3, z + 0.31), mat("InkGrey", (170, 172, 178), 0.9), bevel=0))
        for k, col in enumerate(cols[c]):
            yy = 1.7 - k * 0.27
            p.append(sticky(0.87, yy, z + ((k * 37) % 5 - 2) * 0.02, col, 0.2))
            if c == 0 and k in (0, 1):  # a little bug on the open tickets
                p.append(ball(0.03, (0.86, yy, z), bug, (1, 0.7, 1.2)))
                for s in (-1, 1):
                    p.append(cyl(0.004, 0.07, (0.86, yy, z), bug, rot=(0, 0, s * 1.2), verts=6, bevel=0))
    return join(p, "QABugBoard")


def build_qa_monitorwall():
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    wall = mat("WallFace", (52, 58, 70), 0.8)
    ok, bad = mat("ScreenOK", (88, 196, 120), 0.3), mat("ScreenBad", (224, 82, 82), 0.3)
    bg = mat("EditorBg", (30, 34, 44), 0.5)
    p = [cube((0.05, 1.1, 2.3), (0.9, 1.5, 0), wall, bevel=0.004),
         cube((0.07, 0.07, 2.4), (0.9, 0.93, 0), frame, bevel=0.004), cube((0.07, 0.07, 2.4), (0.9, 2.07, 0), frame, bevel=0.004)]
    p += board_legs(0.9, -1.15, 1.15, 2.1)
    for i, z in enumerate((-0.75, 0.0, 0.75)):  # three dashboards
        p.append(cube((0.04, 0.82, 0.66), (0.87, 1.5, z), frame, bevel=0.006))
        p.append(cube((0.02, 0.74, 0.58), (0.85, 1.5, z), bg, bevel=0))
        if i == 0:  # test-run bars: mostly green, one red
            for b in range(5):
                hgt = 0.15 + 0.1 * ((b * 3) % 4)
                p.append(cube((0.02, hgt, 0.07), (0.84, 1.2 + hgt / 2, z - 0.2 + b * 0.1), bad if b == 3 else ok, bevel=0))
        elif i == 1:  # pass rate: big green ring with a red sliver
            p.append(cyl(0.22, 0.02, (0.84, 1.52, z), ok, rot=(0, 0, math.pi / 2), verts=24))
            p.append(cyl(0.14, 0.024, (0.838, 1.52, z), bg, rot=(0, 0, math.pi / 2), verts=24))
            p.append(cube((0.022, 0.06, 0.1), (0.835, 1.7, z + 0.12), bad, bevel=0, rot=(math.radians(30), 0, 0)))
        else:  # list of runs with status dots
            for r in range(5):
                yy = 1.76 - r * 0.13
                p.append(cyl(0.025, 0.02, (0.84, yy, z - 0.22), bad if r == 2 else ok, rot=(0, 0, math.pi / 2), verts=10))
                p.append(cube((0.02, 0.025, 0.3 - 0.03 * r), (0.84, yy, z + 0.03), mat("CodeGrey", (150, 156, 170), 0.6), bevel=0))
    p += [cube((0.5, 0.04, 1.0), (0.3, 0.98, 0), mat("BenchTop", (150, 118, 86), 0.7), bevel=0.008)]
    for z in (-0.4, 0.4):
        p.append(cube((0.05, 0.96, 0.05), (0.3, 0.48, z), frame, bevel=0.004))
    p += laptop(0.3, 0.0)
    p += mug(0.25, 1.0, 0.35)
    return join(p, "QAMonitorWall")


def build_review_diffscreen():
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    p = [cube((0.07, 1.15, 2.0), (0.9, 1.45, 0), frame, bevel=0.01)]
    p += code_screen(0.86, 1.45, 0, 1.9, 1.05, rows=11, seed=1)
    p += board_legs(0.9, -0.9, 0.9, 0.88)
    p += [cube((0.05, 0.05, 1.8), (0.9, 0.9, 0.0), frame, bevel=0.004)]
    top = mat("BenchTop", (226, 222, 214), 0.7)
    p += [cyl(0.32, 0.04, (0.3, 0.98, 0), top, verts=24), cyl(0.04, 0.96, (0.3, 0.49, 0), frame, verts=10), cyl(0.2, 0.03, (0.3, 0.015, 0), frame, verts=16)]
    p += laptop(0.3, -0.05)
    p += mug(0.25, 1.0, 0.18, (222, 74, 74))
    return join(p, "ReviewDiffScreen")


def build_review_huddle():
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    top = mat("BenchTop", (226, 222, 214), 0.7)
    wood = mat("LecternWood", (176, 130, 90), 0.7)
    p = [cyl(0.95, 0.05, (0.5, 1.0, 0), top, verts=32, bevel=0.01), cyl(0.07, 1.0, (0.5, 0.5, 0), frame, verts=12),
         cyl(0.5, 0.04, (0.5, 0.02, 0), frame, verts=24), cyl(0.9, 0.012, (0.5, 1.03, 0), wood, verts=32, bevel=0)]
    for dx, dz, yaw in ((0.5, 0.0, math.pi), (-0.25, 0.45, math.radians(-60)), (-0.25, -0.45, math.radians(60))):
        p += laptop(0.5 + dx, dz, yaw=yaw)
    p += sheet((0.6, 1.04, 0.0), (0.28, 0.006, 0.2), (0, math.radians(20), 0))
    p += sheet((0.5, 1.042, -0.25), (0.26, 0.006, 0.2), (0, math.radians(-15), 0))
    p += mug(0.35, 1.05, 0.1) + mug(0.65, 1.05, -0.45, (96, 190, 120)) + stamp(0.7, 1.06, 0.4)
    return join(p, "ReviewHuddle")


def build_review_flowboard():
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    face = mat("BoardFace", (244, 242, 236), 0.85)
    blue, grn, red = mat("CodeBlue", (96, 150, 230), 0.6), mat("TickGreen", (70, 176, 100), 0.6), mat("CrossRed", (222, 74, 74), 0.6)
    ink = mat("InkGrey", (120, 124, 134), 0.9)
    p = [cube((0.05, 1.3, 2.0), (0.9, 1.35, 0), face, bevel=0.004),
         cube((0.07, 0.07, 2.1), (0.9, 0.68, 0), frame, bevel=0.004), cube((0.07, 0.07, 2.1), (0.9, 2.02, 0), frame, bevel=0.004)]
    p += board_legs(0.9, -1.0, 1.0, 2.05)
    X = 0.87
    p += [cube((0.01, 0.2, 0.42), (X, 1.75, -0.6), blue, bevel=0), cube((0.01, 0.2, 0.42), (X, 1.75, 0.6), blue, bevel=0),
          cube((0.01, 0.2, 0.42), (X, 1.0, -0.6), grn, bevel=0), cube((0.01, 0.2, 0.42), (X, 1.0, 0.6), red, bevel=0),
          cube((0.01, 0.26, 0.26), (X, 1.38, 0.0), mat("Sticky25522", (255, 220, 120), 0.9), bevel=0, rot=(math.radians(45), 0, 0))]  # decision diamond
    p += [cube((0.008, 0.02, 0.8), (X, 1.75, 0.0), ink, bevel=0),                                   # arrows between boxes
          cube((0.008, 0.18, 0.02), (X, 1.56, -0.6), ink, bevel=0), cube((0.008, 0.18, 0.02), (X, 1.56, 0.6), ink, bevel=0),
          cube((0.008, 0.02, 0.4), (X, 1.38, -0.4), ink, bevel=0), cube((0.008, 0.02, 0.4), (X, 1.38, 0.4), ink, bevel=0),
          cube((0.008, 0.2, 0.02), (X, 1.2, -0.6), ink, bevel=0), cube((0.008, 0.2, 0.02), (X, 1.2, 0.6), ink, bevel=0)]
    p += [cube((0.1, 0.03, 1.2), (0.84, 0.74, 0.0), mat("Tray", (226, 222, 214), 0.8), bevel=0.004)]
    for k, m in enumerate((blue, red, grn)):
        p.append(cyl(0.012, 0.14, (0.82, 0.77, -0.2 + k * 0.1), m, rot=(math.pi / 2, 0, 0), verts=8))
    return join(p, "ReviewFlowBoard")


def plant(x, z, h=0.28):
    pot, leaf = mat("PotWhite", (236, 232, 224), 0.7), mat("Leaf", (74, 150, 92), 0.7)
    p = [cyl(0.05, 0.1, (x, 1.0 + 0.05, z), pot, r2=0.04, verts=12)]
    for dx, dz, s in ((0, 0, 0.07), (0.04, 0.03, 0.055), (-0.04, 0.02, 0.055), (0.0, -0.04, 0.05)):
        p.append(ball(s, (x + dx, 1.0 + 0.1 + h * s * 5, z + dz), leaf, (1, 1.5, 1)))
    return p


def window_dots(x, y, z):
    return [cyl(0.013, 0.012, (x, y, z + k * 0.04), mat("Dot%d" % k, c, 0.4), rot=(0, 0, math.pi / 2), verts=10)
            for k, c in enumerate(((226, 92, 92), (240, 190, 50), (96, 190, 120)))]


def build_review_diffsplit():
    dark = mat("Bezel", (36, 40, 50), 0.4)
    metal = mat("Metal", (150, 156, 166), 0.35)
    ok, bad = mat("ScreenOK", (88, 196, 120), 0.3), mat("ScreenBad", (224, 82, 82), 0.3)
    bg = mat("EditorBg", (30, 34, 44), 0.5)
    chrome = mat("Chrome", (52, 58, 72), 0.5)
    p = []
    for side, z, mode in ((-1, -0.74, 'del'), (1, 0.74, 'add')):  # two panes: before / after
        p.append(cube((0.07, 1.2, 1.4), (0.96, 1.5, z), dark, bevel=0.02, seg=2))
        p += code_screen(0.915, 1.5, z, 1.28, 1.08, rows=11, seed=side + 3, mode=mode)
    p += [cube((0.07, 0.07, 2.9), (0.96, 2.16, 0), chrome, bevel=0.01)]                                   # title strip
    p += window_dots(0.915, 2.16, -1.35)
    p += [cube((0.02, 0.1, 0.36), (0.9, 1.0, -0.2), mat("Btn", (70, 176, 100), 0.5), bevel=0.01),       # Approve
          cube((0.02, 0.1, 0.5), (0.9, 1.0, 0.25), mat("Btn2", (222, 74, 74), 0.5), bevel=0.01)]       # Request changes
    p += [cyl(0.07, 0.65, (1.0, 0.7, 0), metal, verts=12), cyl(0.38, 0.04, (1.0, 0.02, 0), metal, verts=24)]
    wood = mat("BenchTop", (176, 130, 90), 0.7)
    p += [cube((0.5, 0.05, 1.5), (0.35, 0.97, 0), wood, bevel=0.01, seg=2), cube((0.46, 0.9, 1.4), (0.35, 0.45, 0), mat("Booth", (226, 222, 214), 0.8), bevel=0.01)]
    p += laptop(0.35, 0.05)
    p += mug(0.3, 1.0, 0.5, (222, 74, 74)) + plant(0.35, -0.55)
    return join(p, "ReviewDiffSplit")


def build_review_cockpit():
    slat = mat("Slat", (176, 130, 90), 0.7)
    slat2 = mat("Slat2", (150, 108, 74), 0.7)
    dark = mat("Bezel", (36, 40, 50), 0.4)
    bg = mat("EditorBg", (30, 34, 44), 0.5)
    glow = mat("Led", (255, 214, 140), 0.3)
    grey, blue = mat("CodeGrey", (150, 156, 170), 0.6), mat("CodeBlue", (96, 150, 230), 0.6)
    red, grn = mat("DiffRed", (226, 92, 92), 0.6), mat("DiffGreen", (96, 190, 120), 0.6)
    p = [cube((0.06, 1.7, 2.7), (1.05, 1.35, 0), mat("Backdrop", (60, 52, 46), 0.9), bevel=0.004)]
    for k in range(18):                                                                                   # wood slats
        p.append(cube((0.04, 1.6, 0.1), (1.0, 1.35, -1.28 + k * 0.15), slat if k % 2 else slat2, bevel=0.004))
    p += board_legs(1.05, -1.3, 1.3, 2.2, w=0.08)
    for z, w in ((-0.95, 0.62), (0.0, 1.1), (0.95, 0.62)):
        p.append(cube((0.05, 0.98, w + 0.06), (0.95, 1.5, z), dark, bevel=0.012, seg=2))
    p += code_screen(0.91, 1.5, 0.0, 1.04, 0.9, rows=10, seed=2)                                           # center diff
    p.append(cube((0.02, 0.88, 0.56), (0.92, 1.5, -0.95), bg, bevel=0))                                    # left file tree
    for r in range(8):
        sel = r == 3
        if sel:
            p.append(cube((0.02, 0.08, 0.5), (0.915, 1.85 - r * 0.1, -0.95), mat("Sel", (60, 96, 160), 0.5), bevel=0))
        p.append(cube((0.022, 0.03, 0.03), (0.912, 1.85 - r * 0.1, -1.18 + 0.05 * (r % 3)), blue if r % 3 == 0 else grey, bevel=0))
        p.append(cube((0.022, 0.025, 0.22 + 0.04 * (r % 4)), (0.912, 1.85 - r * 0.1, -0.98 + 0.05 * (r % 3) + 0.1), grey, bevel=0))
    p.append(cube((0.02, 0.88, 0.56), (0.92, 1.5, 0.95), bg, bevel=0))                                      # right: review comments
    for k, (col, ln) in enumerate(((red, 0.4), (grn, 0.3), (red, 0.46))):
        yy = 1.8 - k * 0.27
        p.append(cube((0.022, 0.2, 0.46), (0.912, yy, 0.95), mat("Bubble", (52, 58, 72), 0.5), bevel=0))
        p.append(cube((0.024, 0.2, 0.012), (0.91, yy, 0.72), col, bevel=0))
        p.append(cube((0.024, 0.025, ln), (0.908, yy + 0.04, 0.93), grey, bevel=0))
        p.append(cube((0.024, 0.025, ln * 0.7), (0.908, yy - 0.03, 0.9), grey, bevel=0))
    p.append(cube((0.03, 0.025, 2.4), (0.95, 0.96, 0), glow, bevel=0))                                       # warm LED strip
    wood = mat("BenchTop", (176, 130, 90), 0.7)
    p += [cube((0.45, 0.05, 1.6), (0.35, 0.97, 0), wood, bevel=0.01, seg=2)]
    for z in (-0.7, 0.7):
        p.append(cube((0.06, 0.95, 0.06), (0.35, 0.475, z), mat("BoardFrame", (58, 61, 68), 0.6), bevel=0.004))
    p += laptop(0.35, -0.3) + mug(0.3, 1.0, 0.3, (96, 190, 120)) + plant(0.4, 0.62) + stamp(0.3, 1.0, 0.0)
    return join(p, "ReviewCockpit")


def build_review_glasswall():
    glass = mat("Glass", (176, 214, 232), 0.1)
    metal = mat("Metal", (110, 118, 130), 0.35)
    red, grn, blue = mat("MarkerRed", (214, 64, 64), 0.5), mat("MarkerGreen", (60, 170, 96), 0.5), mat("MarkerBlue", (70, 120, 220), 0.5)
    pink = (255, 170, 190)
    p = [cube((0.03, 1.5, 2.3), (0.95, 1.35, 0), glass, bevel=0.004),
         cube((0.05, 0.05, 2.36), (0.95, 0.58, 0), metal, bevel=0.003), cube((0.05, 0.05, 2.36), (0.95, 2.12, 0), metal, bevel=0.003)]
    p += board_legs(0.95, -1.15, 1.15, 2.14, w=0.05)
    for i in range(8):                                  # marker-drawn diff lines, some struck through
        yy = 1.95 - i * 0.16
        m = red if i in (1, 5) else grn if i in (2, 6) else blue
        p.append(cube((0.012, 0.02, 0.5 + 0.12 * ((i * 5) % 5)), (0.925, yy, -0.75 + (0.5 + 0.12 * ((i * 5) % 5)) / 2), m, bevel=0))
        if i in (1, 5):
            p.append(cube((0.014, 0.012, 0.7), (0.922, yy, -0.45), red, bevel=0, rot=(math.radians(8), 0, 0)))
    p += [cube((0.012, 0.5, 0.012), (0.925, 1.5, 0.28), metal, bevel=0)]
    for k, (yy, zz) in enumerate(((1.85, 0.62), (1.45, 0.8), (1.05, 0.55))):                                # review comments as notes
        p.append(sticky(0.925, yy, zz, pink if k != 1 else (255, 220, 120), 0.22))
        p.append(cube((0.008, 0.03, 0.12), (0.92, yy, zz), red if k != 1 else grn, bevel=0))
    ring = mat("Ring", (214, 64, 64), 0.5)
    bpy.ops.mesh.primitive_torus_add(location=G(0.92, 1.1, -0.55), major_radius=0.17, minor_radius=0.008, major_segments=24, minor_segments=6,
                                     rotation=(0, math.pi / 2, 0))
    p.append(B._finish(bpy.context.object, ring))
    p += magnifier(0.9, 0.78, 0.9)
    wood = mat("BenchTop", (176, 130, 90), 0.7)
    p += [cube((0.34, 0.04, 0.8), (0.4, 0.9, 0.6), wood, bevel=0.008), cube((0.05, 0.88, 0.05), (0.4, 0.44, 0.95), metal, bevel=0.004),
          cube((0.05, 0.88, 0.05), (0.4, 0.44, 0.25), metal, bevel=0.004)]
    p += mug(0.4, 0.92, 0.45, (222, 74, 74)) + stamp(0.4, 0.93, 0.8)
    return join(p, "ReviewGlassWall")


def checkbox(x, y, z, state, s=0.07):
    """Square box; state 'ok' = green fill + white tick, 'bad' = red fill + white cross, 'todo' = empty frame."""
    white = mat("White", (250, 250, 248), 0.5)
    if state == 'todo':
        return [cube((0.012, s, s), (x, y, z), mat("BoxFrame", (170, 172, 178), 0.6), bevel=0),
                cube((0.014, s - 0.02, s - 0.02), (x - 0.001, y, z), white, bevel=0)]
    col = mat("TickGreen", (70, 176, 100), 0.5) if state == 'ok' else mat("CrossRed", (222, 74, 74), 0.5)
    p = [cube((0.012, s, s), (x, y, z), col, bevel=0.002)]
    if state == 'ok':
        p += [cube((0.014, 0.022, 0.008), (x - 0.002, y - 0.012, z - 0.012), white, bevel=0, rot=(math.radians(-45), 0, 0)),
              cube((0.014, 0.04, 0.008), (x - 0.002, y + 0.004, z + 0.008), white, bevel=0, rot=(math.radians(40), 0, 0))]
    else:
        p += [cube((0.014, 0.045, 0.008), (x - 0.002, y, z), white, bevel=0, rot=(math.radians(45), 0, 0)),
              cube((0.014, 0.045, 0.008), (x - 0.002, y, z), white, bevel=0, rot=(math.radians(-45), 0, 0))]
    return p


def build_qa_kiosk():
    dark = mat("Bezel", (36, 40, 50), 0.4)
    bg = mat("EditorBg", (30, 34, 44), 0.5)
    metal = mat("Metal", (150, 156, 166), 0.35)
    ink = mat("CodeGrey", (150, 156, 170), 0.6)
    blue, ok = mat("CodeBlue", (96, 150, 230), 0.6), mat("ScreenOK", (88, 196, 120), 0.4)
    p = [cube((0.07, 1.0, 1.5), (0.95, 1.55, 0), dark, bevel=0.025, seg=2), cube((0.02, 0.9, 1.4), (0.91, 1.55, 0), bg, bevel=0),
         cyl(0.07, 1.1, (0.97, 0.55, 0), metal, verts=12), cyl(0.4, 0.04, (0.97, 0.02, 0), metal, verts=24)]
    p.append(cube((0.022, 0.1, 1.4), (0.9, 1.95, 0), mat("HeadBlue", (60, 96, 160), 0.5), bevel=0))
    p += window_dots(0.89, 1.95, -0.6) if 'window_dots' in globals() else []
    for r, st in enumerate(('ok', 'ok', 'ok', 'bad', 'ok', 'todo')):
        yy = 1.78 - r * 0.11
        p += checkbox(0.9, yy, -0.58, st, 0.06)
        p.append(cube((0.022, 0.03, 0.55 + 0.1 * (r % 3)), (0.9, yy, -0.08 + 0.05 * (r % 3)), ink, bevel=0))
    p += [cube((0.022, 0.05, 1.1), (0.9, 1.15, -0.12), mat("Track", (60, 66, 80), 0.5), bevel=0),               # progress bar 4 of 6
          cube((0.024, 0.05, 0.74), (0.9, 1.15, -0.3), ok, bevel=0),
          cube((0.022, 0.1, 0.3), (0.9, 1.15, 0.55), blue, bevel=0.004)]                                     # Run button
    top = mat("BenchTop", (226, 222, 214), 0.7)
    p += [cyl(0.28, 0.04, (0.3, 0.98, 0), top, verts=24), cyl(0.04, 0.96, (0.3, 0.49, 0), metal, verts=10), cyl(0.18, 0.03, (0.3, 0.015, 0), metal, verts=16)]
    p += phone(0.3, 1.0, -0.08, True) + phone(0.3, 1.0, 0.1, False)
    return join(p, "QAKiosk")


def build_qa_matrix():
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    bg = mat("EditorBg", (30, 34, 44), 0.5)
    ink = mat("CodeGrey", (150, 156, 170), 0.6)
    ok, bad, skip = mat("ScreenOK", (88, 196, 120), 0.4), mat("ScreenBad", (224, 82, 82), 0.4), mat("Skip", (240, 190, 50), 0.4)
    p = [cube((0.06, 1.5, 2.3), (0.95, 1.4, 0), frame, bevel=0.012), cube((0.02, 1.4, 2.2), (0.915, 1.4, 0), bg, bevel=0)]
    p += board_legs(0.95, -1.1, 1.1, 2.15)
    bad_cells, skip_cells = {(1, 3), (3, 1), (4, 4)}, {(2, 5), (5, 2)}
    for c in range(6):  # device columns (phone silhouettes)
        p.append(cube((0.022, 0.07, 0.1), (0.9, 2.0, -0.7 + c * 0.28), mat("Chip", (96, 150, 230), 0.5), bevel=0.004))
    for r in range(6):
        yy = 1.8 - r * 0.22
        p.append(cube((0.022, 0.035, 0.28 - 0.03 * (r % 3)), (0.9, yy, -1.0 + 0.14 - 0.015 * (r % 3)), ink, bevel=0))  # test-case label
        for c in range(6):
            m = bad if (r, c) in bad_cells else skip if (r, c) in skip_cells else ok
            p.append(cube((0.022, 0.15, 0.22), (0.9, yy, -0.7 + c * 0.28), m, bevel=0.006))
    return join(p, "QAMatrix")


def build_qa_clipboard():
    wood = mat("LecternWood", (176, 130, 90), 0.7)
    paper = mat("Paper", (246, 244, 238), 0.9)
    metal = mat("Metal", (150, 156, 166), 0.35)
    ink = mat("CodeGrey", (150, 156, 170), 0.6)
    p = [cube((0.04, 1.6, 1.15), (0.85, 1.4, 0), wood, bevel=0.015, seg=2), cube((0.01, 1.42, 0.95), (0.825, 1.36, 0), paper, bevel=0),
         cube((0.05, 0.14, 0.36), (0.83, 2.14, 0), metal, bevel=0.01), cyl(0.03, 0.06, (0.83, 2.2, 0), metal, rot=(0, 0, math.pi / 2), verts=10)]
    for z in (-0.5, 0.5):  # A-frame legs
        p.append(cube((0.05, 2.0, 0.06), (0.92, 1.0, z), wood, bevel=0.004, rot=(0, math.radians(6), 0)))
    p.append(cube((0.5, 0.05, 0.06), (0.8, 0.02, -0.5), wood, bevel=0.004))
    p.append(cube((0.5, 0.05, 0.06), (0.8, 0.02, 0.5), wood, bevel=0.004))
    p.append(cube((0.1, 0.04, 1.1), (0.78, 0.7, 0), wood, bevel=0.004))
    for r, st in enumerate(('ok', 'ok', 'bad', 'ok', 'ok', 'todo', 'todo')):
        yy = 1.92 - r * 0.19
        p += checkbox(0.818, yy, -0.32, st, 0.09)
        p.append(cube((0.008, 0.03, 0.42 + 0.06 * (r % 3)), (0.82, yy, 0.0 + 0.04 * (r % 3)), ink, bevel=0))
    p += [cyl(0.008, 0.2, (0.75, 0.75, 0.3), mat("PenBlue", (70, 120, 220), 0.5), rot=(math.pi / 2, 0, 0), verts=6)]
    p += stamp(0.75, 0.73, -0.3)
    return join(p, "QAClipboard")


def preview(png):
    rows = [["QABench", "QACheckboard", "QADeviceWall", "QABugBoard", "QAMonitorWall"],
            ["ReviewWall", "ReviewDiffScreen", "ReviewHuddle", "ReviewFlowBoard"],
            ["ReviewDiffSplit", "ReviewCockpit", "ReviewGlassWall"],
            ["QAKiosk", "QAMatrix", "QAClipboard"]]
    for r, names in enumerate(rows):
        for i, n in enumerate(names):
            bpy.data.objects[n].location = G(r * 3.6, 0, (i - 2) * 2.8)
    bpy.ops.mesh.primitive_plane_add(size=24, location=(0, 0, 0))
    bpy.context.object.data.materials.append(mat("PreviewFloor", (205, 201, 194)))
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = 22
    cam = bpy.data.objects.new("cam", cam_d)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(G(-6.0, 6.0, 4.5))
    cam.rotation_euler = (Vector(G(4.5, 0.8, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_shadows = True
    sh.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 1700, 900
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", png)


if __name__ == "__main__":
    B.reset()
    for build in (build_qa_bench, build_qa_checkboard, build_qa_devicewall, build_qa_bugboard, build_qa_monitorwall,
                  build_review_wall, build_review_diffscreen, build_review_huddle, build_review_flowboard,
                  build_review_diffsplit, build_review_cockpit, build_review_glasswall,
                  build_qa_kiosk, build_qa_matrix, build_qa_clipboard):
        build()
    B.export()
    if PREVIEW:
        preview(PREVIEW)
