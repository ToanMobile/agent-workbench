#!/usr/bin/env python3
"""_bpyx — tiện ích dùng chung gọn nhẹ cho các script Blender 5.2+ headless của DevKit profile game.

Chuyển thể từ EL4CTEO/blender-skills (MIT License).
Quy ước chung của mọi script:
  run(**kwargs) -> dict                      # gọi trực tiếp trong Python/MCP
  blender --disable-autoexec -b f.blend -P x.py -- --arg v   # CLI: in 1 dòng "@@JSON@@{...}"
"""
import argparse
import json
import sys

try:
    import bpy
except ImportError:  # cho phép chạy --help hoặc unit test pure-Python ngoài Blender
    bpy = None

MARK = "@@JSON@@"


def require_bpy():
    """Bảo đảm đang chạy bên trong môi trường Python của Blender."""
    if bpy is None:
        raise RuntimeError("Script này cần chạy trong Blender (ví dụ: blender --disable-autoexec -b f.blend -P ...)")
    return bpy


def argv():
    """Lấy danh sách đối số đứng sau dấu '--' (Blender bỏ qua phần này)."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def _default(o):
    if hasattr(o, "__len__") and not isinstance(o, str):
        try:
            return [round(v, 5) if isinstance(v, float) else v for v in o]
        except TypeError:
            pass
    if isinstance(o, (set, frozenset)):
        return sorted(o)
    return str(o)


def emit(data):
    """In JSON gọn trên một dòng có tiền tố MARK để agent/CI parse ổn định."""
    print(MARK + json.dumps(data, separators=(",", ":"), default=_default), flush=True)
    return data


def parser(doc):
    """Tạo ArgumentParser lấy dòng đầu của docstring làm mô tả."""
    return argparse.ArgumentParser(description=(doc or "").strip().splitlines()[0])


def cli(run, p):
    """Điểm vào CLI: parse đối số sau '--', chạy `run`, xuất JSON. Lỗi thì exit 1."""
    args = p.parse_args(argv())
    try:
        result = run(**vars(args))
        save = getattr(args, "save", None)
        if save:
            require_bpy()
            bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath(save))
            result["saved"] = save
        emit(result)
    except Exception as e:  # báo lỗi JSON gọn, không đổ traceback dài vào context agent
        emit({"ok": False, "error": f"{type(e).__name__}: {e}"})
        if bpy is None or bpy.app.background:
            sys.exit(1)


def add_common(p, save=True):
    """Gắn cờ --objects và (tuỳ chọn) --save dùng chung cho hầu hết script."""
    p.add_argument("--objects", nargs="*", default=None,
                   help="tên object cần xử lý (mặc định: đang chọn, nếu không thì mọi mesh hiển thị)")
    if save:
        p.add_argument("--save", default=None, help="lưu file .blend ra đường dẫn này sau khi chạy")
    return p


def objects(names=None, types=("MESH",)):
    """Phân giải danh sách tên thành object Blender. Không truyền tên: lấy đang chọn hoặc đang hiện."""
    require_bpy()
    if names:
        missing = [n for n in names if n not in bpy.data.objects]
        if missing:
            raise KeyError(f"không tìm thấy object: {missing}")
        return [bpy.data.objects[n] for n in names]
    pool = [o for o in bpy.context.scene.objects if not types or o.type in types]
    sel = [o for o in pool if o.select_get()]
    return sel or [o for o in pool if o.visible_get()]


def object_mode():
    """Thoát khỏi Edit/Sculpt/Pose mode về OBJECT mode trước khi thao tác Data API."""
    require_bpy()
    ob = bpy.context.view_layer.objects.active
    if ob and ob.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def select_only(objs, active=None):
    """Chỉ chọn đúng tập `objs` và đặt `active` (mặc định phần tử đầu) làm active object."""
    require_bpy()
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def mesh_tris(ob, evaluated=True):
    """Đếm số tam giác (evaluated=True tính cả modifier đang bật)."""
    require_bpy()
    if evaluated:
        eo = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = eo.to_mesh()
        try:
            me.calc_loop_triangles()
            return len(me.loop_triangles)
        finally:
            eo.to_mesh_clear()
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def r(v, n=4):
    """Làm tròn số thực hoặc vector để JSON gọn."""
    if isinstance(v, float):
        return round(v, n)
    return [round(x, n) for x in v]
