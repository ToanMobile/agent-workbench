"""Build the two standing work stations of the QA and Review lanes (people do not type code there).

Roots in web/models/stations.glb, same "desk frame" as office.glb (floor y=0, the person stands at
x=-0.45 facing +X, Z is sideways, hands rest on the counter at y=1.0):
  QAMatrix       test case x device grid (green pass, red fail, yellow skipped) + standing counter
  ReviewCockpit  wood slat wall with three screens (file tree, code diff, review comments) + counter

Run from mcp-servers/agent-office/:
    blender -b --factory-startup --python blender/build_stations.py
    blender -b --factory-startup --python blender/build_stations.py -- --preview /path/out.png
"""
import bpy, sys, os
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


def stamp(x, y, z):
    red, brass = mat("StampRed", (214, 64, 64), 0.5), mat("Brass", (212, 170, 84), 0.4)
    return [cyl(0.055, 0.02, (x, y, z), red, verts=18), cyl(0.018, 0.07, (x, y + 0.045, z), brass, verts=8),
            cyl(0.034, 0.03, (x, y + 0.09, z), brass, verts=10)]


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


def board_legs(x, z0, z1, top, w=0.07):
    frame = mat("BoardFrame", (58, 61, 68), 0.6)
    p = []
    for z in (z0, z1):
        p.append(cube((0.06, top, w), (x, top / 2, z), frame, bevel=0.004))
        p.append(cube((0.5, 0.04, 0.08), (x, 0.02, z), frame, bevel=0.004))
    return p


def plant(x, z, h=0.28):
    pot, leaf = mat("PotWhite", (236, 232, 224), 0.7), mat("Leaf", (74, 150, 92), 0.7)
    p = [cyl(0.05, 0.1, (x, 1.0 + 0.05, z), pot, r2=0.04, verts=12)]
    for dx, dz, s in ((0, 0, 0.07), (0.04, 0.03, 0.055), (-0.04, 0.02, 0.055), (0.0, -0.04, 0.05)):
        p.append(ball(s, (x + dx, 1.0 + 0.1 + h * s * 5, z + dz), leaf, (1, 1.5, 1)))
    return p


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
    wood = mat("BenchTop", (176, 130, 90), 0.7)
    p += [cube((0.45, 0.05, 1.6), (0.35, 0.97, 0), wood, bevel=0.01, seg=2)]
    for z in (-0.7, 0.7):
        p.append(cube((0.06, 0.95, 0.06), (0.35, 0.475, z), frame, bevel=0.004))
    p += laptop(0.35, -0.3) + mug(0.3, 1.0, 0.3, (222, 74, 74)) + plant(0.4, 0.62)
    return join(p, "QAMatrix")


def preview(png):
    rows = [["QAMatrix", "ReviewCockpit"]]
    for r, names in enumerate(rows):
        for i, n in enumerate(names):
            bpy.data.objects[n].location = G(r * 3.6, 0, (i - 0.5) * 3.2)
    bpy.ops.mesh.primitive_plane_add(size=24, location=(0, 0, 0))
    bpy.context.object.data.materials.append(mat("PreviewFloor", (205, 201, 194)))
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = 6.5
    cam = bpy.data.objects.new("cam", cam_d)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(G(-6.0, 3.6, 0.0))
    cam.rotation_euler = (Vector(G(0.9, 1.0, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_shadows = True
    sh.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 1500, 620
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", png)


if __name__ == "__main__":
    B.reset()
    for build in (build_qa_matrix, build_review_cockpit):
        build()
    B.export()
    if PREVIEW:
        preview(PREVIEW)
