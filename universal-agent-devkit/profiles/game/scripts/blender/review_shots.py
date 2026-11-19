#!/usr/bin/env python3
"""Render contact sheet nhiều góc (Workbench headless) để kiểm tra thị giác asset 3D.

Chuyển thể từ EL4CTEO/blender-skills (MIT License).
Các chế độ:
  - solid:    ánh sáng studio + cavity (kiểm khối và bóng đổ)
  - random:   màu ngẫu nhiên theo từng object (soi nhanh phần rời)
  - wire:     khung dây đen phủ trên nền solid (soi topology)
  - material: màu vật liệu/texture cơ bản

Cách dùng:
  blender --disable-autoexec -b f.blend --python-exit-code 1 -P review_shots.py -- \
      [--objects A B] [--out /abs/review.png] [--views front right top three_quarter] \
      [--mode solid|random|wire|material] [--res 512]
"""
import math
import os
import sys
import tempfile

try:
    import bpy
    import numpy as np
    from mathutils import Vector
except ImportError:  # cho phép chạy --help hoặc unit test pure-Python ngoài Blender
    bpy = np = Vector = None

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _bpyx as bx  # noqa: E402

DIRS = {
    "front": (0, -1, 0.15),
    "back": (0, 1, 0.15),
    "right": (1, 0, 0.15),
    "left": (-1, 0, 0.15),
    "top": (0, -0.001, 1),
    "bottom": (0, 0.001, -1),
    "three_quarter": (1, -1, 0.6),
}


def _bounds(obs):
    """Tính tâm và bán kính bao của tập object sau khi cập nhật view_layer."""
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in obs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return (lo + hi) / 2, max((hi - lo).length / 2, 1e-3)


def run(objects=None, out="", views=None, mode="solid", res=512, **_):
    bx.object_mode()
    obs = bx.objects(objects, types=("MESH", "CURVE", "FONT", "SURFACE", "CURVES", "VOLUME"))
    if not obs:
        raise ValueError("không có object nào để render")
    views = views or ["front", "right", "top", "three_quarter"]
    sc = bpy.context.scene
    out = bpy.path.abspath(out) if out else os.path.join(
        os.path.dirname(bpy.data.filepath) or tempfile.gettempdir(), "review_sheet.png"
    )
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)

    # Lưu cấu hình hiện tại để khôi phục nguyên trạng trong finally
    r, sh = sc.render, sc.display.shading
    saved = dict(
        engine=r.engine, rx=r.resolution_x, ry=r.resolution_y, pct=r.resolution_percentage,
        fp=r.filepath, cam=sc.camera, light=sh.light, color=sh.color_type,
        cavity=sh.show_cavity, outline=sh.show_object_outline, transp=r.film_transparent,
    )
    hidden = {o: o.hide_render for o in sc.objects}
    temp = []
    try:
        for o in sc.objects:
            o.hide_render = o not in obs
        r.engine = "BLENDER_WORKBENCH"
        r.resolution_x = r.resolution_y = res
        r.resolution_percentage = 100
        r.film_transparent = False
        # Blender 5.0+ yêu cầu đặt media_type trước file_format
        if hasattr(r.image_settings, "media_type"):
            r.image_settings.media_type = "IMAGE"
        r.image_settings.file_format = "PNG"
        sh.light = "STUDIO"
        sh.show_cavity = mode in ("solid", "wire")
        sh.show_object_outline = True
        sh.color_type = {"random": "RANDOM", "material": "MATERIAL", "wire": "OBJECT"}.get(mode, "SINGLE")
        if mode == "wire":
            wire_t = _bounds(obs)[1] * 0.006
            for o in obs:
                if o.type != "MESH":
                    continue
                w = o.copy()
                w.data = o.data
                w.modifiers.new("QA_Wire", "WIREFRAME").thickness = wire_t
                w.color = (0, 0, 0, 1)
                sc.collection.objects.link(w)
                temp.append(w)
                o.color = (0.8, 0.8, 0.8, 1)

        cam_data = bpy.data.cameras.new("QA_Cam")
        cam_data.lens = 50
        cam = bpy.data.objects.new("QA_Cam", cam_data)
        sc.collection.objects.link(cam)
        temp.append(cam)
        sc.camera = cam
        center, radius = _bounds(obs)
        fov = 2 * math.atan(cam_data.sensor_width / (2 * cam_data.lens))
        dist = radius / math.sin(fov / 2) * 1.05
        cam_data.clip_end = dist * 4
        cam_data.clip_start = dist / 1000
        paths = []
        for v in views:
            d = Vector(DIRS[v] if isinstance(v, str) else v).normalized()
            cam.location = center + d * dist
            cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
            p = os.path.splitext(out)[0] + f"_{v}.png"
            r.filepath = p
            bpy.ops.render.render(write_still=True)
            paths.append(p)

        # Ghép các góc render thành một ảnh contact sheet duy nhất
        imgs = []
        for p in paths:
            im = bpy.data.images.load(p, check_existing=False)
            a = np.empty(res * res * 4, dtype=np.float32)
            im.pixels.foreach_get(a)
            imgs.append(a.reshape(res, res, 4))
            bpy.data.images.remove(im)
        n = len(imgs)
        cols = n if n <= 3 else 2 if n == 4 else 3
        rows = math.ceil(n / cols)
        sheet = np.empty((rows * res, cols * res, 4), dtype=np.float32)
        sheet[:] = imgs[0][0, 0]  # ô trống dùng màu nền render thay vì trắng gắt
        for i, a in enumerate(imgs):
            rr, cc = rows - 1 - i // cols, i % cols  # hàng pixel trong Blender đi từ dưới lên
            sheet[rr * res:(rr + 1) * res, cc * res:(cc + 1) * res] = a
        im = bpy.data.images.new("QA_Sheet", cols * res, rows * res, alpha=True)
        im.pixels.foreach_set(sheet.ravel())
        im.filepath_raw = out
        im.file_format = "PNG"
        im.save()
        bpy.data.images.remove(im)
    finally:
        for o in temp:
            data = o.data if o.type == "CAMERA" else None
            bpy.data.objects.remove(o)
            if data:
                bpy.data.cameras.remove(data)
        for o, h in hidden.items():
            o.hide_render = h
        r.engine, r.resolution_x, r.resolution_y = saved["engine"], saved["rx"], saved["ry"]
        r.resolution_percentage, r.filepath, sc.camera = saved["pct"], saved["fp"], saved["cam"]
        r.film_transparent = saved["transp"]
        sh.light, sh.color_type, sh.show_cavity = saved["light"], saved["color"], saved["cavity"]
        sh.show_object_outline = saved["outline"]
    return {"ok": True, "sheet": out, "views": paths, "layout": f"{cols}x{rows}", "order": views}


def _build_parser():
    p = bx.add_common(bx.parser(__doc__), save=False)
    p.add_argument("--out", default="", help="đường dẫn ảnh contact sheet đầu ra (.png)")
    p.add_argument("--views", nargs="*", default=None, choices=list(DIRS), help="các góc chụp")
    p.add_argument("--mode", default="solid", choices=["solid", "random", "wire", "material"])
    p.add_argument("--res", type=int, default=512, help="độ phân giải mỗi ô góc (px)")
    return p


if __name__ == "__main__":
    bx.cli(run, _build_parser())
