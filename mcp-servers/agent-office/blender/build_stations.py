"""Build standing work stations for the QA and Review lanes (people do not type code there).

Roots in web/models/stations.glb, same "desk frame" as office.glb (floor y=0, the person stands at
x=-0.8 facing +X, Z is sideways):
  QABench       standing test bench: phones on test stands, magnifier, checklist, bug jar, device rack
  QACheckboard  checklist board on legs (green ticks, red crosses) with a device tray
  ReviewLectern lectern with a sloped top, an open diff sheet, magnifier and an APPROVED stamp
  ReviewWall    pinboard of diff sheets with a stamp stand in front
  QALab / QAConveyor / QADeviceWall / ReviewJudge / ReviewCheckpoint / ReviewEasel: more variants

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
SLOPE = math.radians(-22)  # Blender euler y: tilts a top so its person-side (-x) edge is lower


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


def build_review_lectern():
    wood = mat("LecternWood", (166, 120, 84), 0.7)
    frame = mat("BenchFrame", (58, 61, 68), 0.6)
    p = [cube((0.6, 0.05, 0.95), (0.4, 0.025, 0), frame, bevel=0.006),
         cube((0.4, 1.0, 0.7), (0.45, 0.55, 0), wood, bevel=0.01, seg=2),
         cube((0.62, 0.05, 0.95), (0.42, 1.1, 0), wood, bevel=0.01, seg=2, rot=(0, SLOPE, 0)),
         cube((0.05, 0.05, 0.95), (0.19, 1.045, 0), wood, bevel=0.004)]
    p += sheet((0.42, 1.14, 0.0), (0.46, 0.006, 0.8), (0, SLOPE, 0))
    p += magnifier(0.42, 1.28, 0.3)
    p += stamp(0.34, 1.16, -0.38)
    return join(p, "ReviewLectern")


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


def build_qa_lab():
    top = mat("LabTop", (236, 238, 240), 0.5)
    frame = mat("BenchFrame", (58, 61, 68), 0.6)
    metal = mat("Metal", (150, 156, 166), 0.35)
    glass = mat("JarGlass", (170, 222, 200), 0.2)
    bug = mat("Bug", (84, 168, 88), 0.6)
    p = [cube((0.9, 0.05, 1.7), (0.4, 0.95, 0), top, bevel=0.01, seg=2),
         cube((0.8, 0.5, 1.6), (0.4, 0.5, 0), mat("LabCab", (120, 168, 200), 0.7), bevel=0.01)]
    p += [cube((0.22, 0.03, 0.26), (0.5, 0.995, -0.45), frame, bevel=0.005),            # microscope
          cube((0.04, 0.34, 0.05), (0.57, 1.17, -0.45), metal, bevel=0.004),
          cyl(0.03, 0.26, (0.5, 1.2, -0.45), metal, rot=(0, math.radians(-18), 0), verts=12),
          cyl(0.02, 0.07, (0.46, 1.37, -0.45), frame, rot=(0, math.radians(-18), 0), verts=10),
          cube((0.12, 0.012, 0.12), (0.5, 1.04, -0.45), frame, bevel=0.002)]
    p += [cyl(0.07, 0.012, (0.3, 0.99, -0.1), glass, verts=18), ball(0.035, (0.3, 1.0, -0.1), bug, (1, 0.5, 1))]  # petri dish
    for k, col in enumerate(((84, 168, 88), (84, 168, 88), (224, 82, 82), (84, 168, 88))):  # test-tube rack
        tm = mat("Tube%d" % k, col, 0.3)
        p.append(cyl(0.022, 0.16, (0.55, 1.05, 0.15 + k * 0.1), glass, verts=10))
        p.append(cyl(0.018, 0.09, (0.55, 1.02, 0.15 + k * 0.1), tm, verts=10))
    p.append(cube((0.1, 0.02, 0.42), (0.55, 0.985, 0.25), frame, bevel=0.003))
    p += magnifier(0.2, 1.2, 0.55)
    return join(p, "QALab")


def build_qa_conveyor():
    frame = mat("BenchFrame", (58, 61, 68), 0.6)
    belt = mat("Belt", (44, 46, 52), 0.8)
    yel = mat("Safety", (240, 190, 50), 0.5)
    ok, bad = mat("ScreenOK", (88, 196, 120), 0.3), mat("ScreenBad", (224, 82, 82), 0.3)
    p = [cube((0.5, 0.12, 2.3), (0.4, 0.88, 0), belt, bevel=0.01), cube((0.56, 0.04, 2.34), (0.4, 0.82, 0), yel, bevel=0.004)]
    for z in (-1.0, 1.0):
        p.append(cube((0.06, 0.8, 0.06), (0.15, 0.4, z), frame, bevel=0.004))
        p.append(cube((0.06, 0.8, 0.06), (0.65, 0.4, z), frame, bevel=0.004))
        p.append(cyl(0.07, 0.5, (0.4, 0.94, z * 1.12), frame, rot=(math.pi / 2, 0, 0), verts=12))
    for i, z in enumerate((-0.8, -0.35, 0.05, 0.45)):
        p += phone(0.4, 0.953, z, ok=i != 2)
    p += [cube((0.06, 0.62, 0.06), (0.15, 1.25, -0.1), frame, bevel=0.004), cube((0.06, 0.62, 0.06), (0.65, 1.25, -0.1), frame, bevel=0.004),
          cube((0.6, 0.07, 0.1), (0.4, 1.58, -0.1), frame, bevel=0.004), cube((0.45, 0.012, 0.012), (0.4, 1.54, -0.1), mat("Laser", (255, 70, 70), 0.3), bevel=0)]  # scanner arch
    p += [cube((0.34, 0.3, 0.3), (0.4, 0.28, 1.35), ok, bevel=0.008), cube((0.34, 0.3, 0.3), (0.4, 0.28, 1.7), bad, bevel=0.008)]  # pass / fail bins
    return join(p, "QAConveyor")


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


def build_review_judge():
    wood = mat("LecternWood", (140, 98, 66), 0.7)
    light = mat("LecternLight", (176, 130, 90), 0.7)
    brass = mat("Brass", (212, 170, 84), 0.4)
    p = [cube((0.5, 0.95, 1.5), (0.5, 0.475, 0), wood, bevel=0.01, seg=2), cube((0.62, 0.06, 1.62), (0.45, 0.98, 0), light, bevel=0.01, seg=2),
         cube((0.1, 0.5, 1.5), (0.78, 1.25, 0), wood, bevel=0.01), cube((0.1, 0.5, 0.1), (0.78, 1.7, 0), wood, bevel=0.01)]
    p += [cube((0.2, 0.05, 0.2), (0.4, 1.035, 0.4), wood, bevel=0.005), cyl(0.035, 0.16, (0.4, 1.12, 0.4), light, rot=(math.pi / 2, 0, 0), verts=12),
          cyl(0.012, 0.22, (0.4, 1.12, 0.4 - 0.12), brass, rot=(0, math.radians(35), 0), verts=8)]  # gavel on its block
    p += [cyl(0.012, 0.5, (0.62, 1.28, -0.4), brass, verts=8), cube((0.02, 0.02, 0.5), (0.62, 1.53, -0.4), brass, bevel=0),     # scales
          cyl(0.07, 0.012, (0.62, 1.4, -0.65), brass, verts=14), cyl(0.07, 0.012, (0.62, 1.4, -0.15), brass, verts=14),
          cyl(0.1, 0.03, (0.62, 1.04, -0.4), brass, verts=14)]
    p += sheet((0.35, 1.03, -0.35), (0.3, 0.05, 0.22), (0, 0, 0))
    return join(p, "ReviewJudge")


def build_review_checkpoint():
    frame = mat("BenchFrame", (58, 61, 68), 0.6)
    booth = mat("Booth", (226, 222, 214), 0.8)
    red, grn, yel = mat("LampRed", (226, 70, 70), 0.4), mat("LampGreen", (70, 200, 110), 0.4), mat("LampYel", (240, 190, 50), 0.4)
    stripe = mat("StripeRed", (214, 64, 64), 0.6)
    p = [cube((0.55, 1.0, 0.9), (0.5, 0.5, -0.5), booth, bevel=0.01), cube((0.65, 0.05, 1.0), (0.5, 1.025, -0.5), frame, bevel=0.008)]
    p += sheet((0.4, 1.06, -0.5), (0.3, 0.012, 0.4), (0, 0, 0))
    p += stamp(0.45, 1.09, -0.15)
    p += [cube((0.12, 2.0, 0.12), (0.75, 1.0, -0.5), frame, bevel=0.006), cube((0.16, 0.7, 0.16), (0.75, 1.7, -0.5), frame, bevel=0.01),
          cyl(0.055, 0.04, (0.67, 1.9, -0.5), red, rot=(0, 0, math.pi / 2), verts=14), cyl(0.055, 0.04, (0.67, 1.7, -0.5), yel, rot=(0, 0, math.pi / 2), verts=14),
          cyl(0.055, 0.04, (0.67, 1.5, -0.5), grn, rot=(0, 0, math.pi / 2), verts=14)]
    p += [cube((0.14, 0.9, 0.14), (0.5, 0.45, 0.7), frame, bevel=0.006), cube((0.08, 0.08, 1.5), (0.5, 0.9, 1.45), booth, bevel=0.004)]
    for k in range(5):
        p.append(cube((0.082, 0.082, 0.15), (0.5, 0.9, 0.9 + k * 0.3), stripe, bevel=0))
    return join(p, "ReviewCheckpoint")


def build_review_easel():
    wood = mat("LecternWood", (176, 130, 90), 0.7)
    pencil = mat("PencilRed", (214, 64, 64), 0.6)
    p = [cube((0.05, 1.9, 0.06), (0.62, 0.95, -0.55), wood, bevel=0.004, rot=(0, math.radians(8), 0)),
         cube((0.05, 1.9, 0.06), (0.62, 0.95, 0.55), wood, bevel=0.004, rot=(0, math.radians(8), 0)),
         cube((0.05, 1.7, 0.06), (1.0, 0.85, 0.0), wood, bevel=0.004, rot=(0, math.radians(-14), 0)),
         cube((0.06, 0.06, 1.2), (0.58, 0.8, 0.0), wood, bevel=0.004), cube((0.06, 0.06, 1.2), (0.6, 1.9, 0.0), wood, bevel=0.004)]
    p += [cube((0.12, 0.04, 1.2), (0.52, 0.76, 0.0), wood, bevel=0.004)]
    p += vsheet(0.55, 1.4, 0.0, 0.95, 1.1)
    p += [cyl(0.008, 0.2, (0.5, 0.8, 0.2), pencil, rot=(0, math.radians(80), 0), verts=6)]
    p += stamp(0.5, 0.83, -0.35)
    return join(p, "ReviewEasel")


def preview(png):
    rows = [["QABench", "QACheckboard", "QALab", "QAConveyor", "QADeviceWall"],
            ["ReviewLectern", "ReviewWall", "ReviewJudge", "ReviewCheckpoint", "ReviewEasel"]]
    for r, names in enumerate(rows):
        for i, n in enumerate(names):
            bpy.data.objects[n].location = G(r * 3.6, 0, (i - 2) * 2.8)
    bpy.ops.mesh.primitive_plane_add(size=24, location=(0, 0, 0))
    bpy.context.object.data.materials.append(mat("PreviewFloor", (205, 201, 194)))
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = 15
    cam = bpy.data.objects.new("cam", cam_d)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(G(-6.0, 6.0, 4.5))
    cam.rotation_euler = (Vector(G(1.8, 0.8, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
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
    for build in (build_qa_bench, build_qa_checkboard, build_review_lectern, build_review_wall, build_qa_lab,
                  build_qa_conveyor, build_qa_devicewall, build_review_judge, build_review_checkpoint, build_review_easel):
        build()
    B.export()
    if PREVIEW:
        preview(PREVIEW)
