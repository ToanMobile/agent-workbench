#!/usr/bin/env python3
"""Tạo chuỗi LOD (<tên>_LOD1..N) bằng Decimate, giữ UV seam/normal/silhouette cho Unity LODGroup.

Chuyển thể từ EL4CTEO/blender-skills (MIT License), kết hợp hàn đỉnh biên hở trước Decimate
(từ scenario-labs/skills, MIT License) để tránh nứt seam trên mesh nhập từ glTF.

Cách dùng:
  blender --disable-autoexec -b f.blend --python-exit-code 1 -P make_lods.py -- \
      --objects SM_Crate [--ratios 0.5 0.25 0.125] [--symmetry] [--cleanup] [--rename] [--save out.blend]
"""
import os
import sys

try:
    import bmesh
    import bpy
    from mathutils import Vector
except ImportError:  # cho phép chạy --help hoặc unit test pure-Python ngoài Blender
    bmesh = bpy = Vector = None

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _bpyx as bx  # noqa: E402


def cleanup(ob, dist=1e-4):
    """Gộp đỉnh trùng theo khoảng cách, triệt cạnh suy biến, xoá đỉnh rời. Trả về số đỉnh đã bỏ."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    n0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=dist)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    return n0 - len(ob.data.vertices)


def _weld_open_borders(me, ob):
    """Hàn các đỉnh biên hở cực sát nhau (ví dụ UV seam bị tách từ glTF) trước khi Decimate."""
    bm = bmesh.new()
    bm.from_mesh(me)
    diag = (Vector(ob.bound_box[6]) - Vector(ob.bound_box[0])).length or 1.0
    border = [v for v in bm.verts if v.is_boundary]
    if border:
        bmesh.ops.remove_doubles(bm, verts=border, dist=diag * 1e-6)
    bm.to_mesh(me)
    bm.free()


def run(objects=None, ratios=None, symmetry=False, do_cleanup=False, rename=False,
        collection=None, **_):
    bx.object_mode()
    ratios = ratios or [0.5, 0.25, 0.125]
    out = {}
    for src in bx.objects(objects):
        base = src.name.split("_LOD")[0]
        rec = {}
        if do_cleanup:
            rec["cleanup_removed_verts"] = cleanup(src)
        if rename and not src.name.endswith("_LOD0"):
            src.name = f"{base}_LOD0"
        col = None
        if collection:
            col = bpy.data.collections.get(collection) or bpy.data.collections.new(collection)
            if col.name not in bpy.context.scene.collection.children:
                bpy.context.scene.collection.children.link(col)
        tris0 = bx.mesh_tris(src)
        rec["LOD0"] = tris0
        for i, ratio in enumerate(ratios, start=1):
            name = f"{base}_LOD{i}"
            old = bpy.data.objects.get(name)
            if old:
                bpy.data.objects.remove(old)
            lod = src.copy()
            lod.data = src.data.copy()
            lod.name = lod.data.name = name
            for c in [col] if col else src.users_collection:
                c.objects.link(lod)
            # Apply modifier hiện có vào bản sao, hàn đỉnh biên hở rồi mới chạy Decimate
            dg = bpy.context.evaluated_depsgraph_get()
            me = bpy.data.meshes.new_from_object(src.evaluated_get(dg))
            _weld_open_borders(me, src)
            old_me, lod.data = lod.data, me
            bpy.data.meshes.remove(old_me)
            me.name = name
            lod.modifiers.clear()
            d = lod.modifiers.new("Decimate", "DECIMATE")
            d.decimate_type = "COLLAPSE"
            d.ratio = ratio
            d.use_symmetry = symmetry
            d.use_collapse_triangulate = True
            with bpy.context.temp_override(
                object=lod, active_object=lod, selected_objects=[lod],
                selected_editable_objects=[lod],
            ):
                bpy.ops.object.modifier_apply(modifier=d.name)
            lod.hide_set(True)
            lod.hide_render = True
            rec[f"LOD{i}"] = bx.mesh_tris(lod, evaluated=False)
        out[src.name] = rec
    return {
        "ok": True,
        "lods": out,
        "screen_size_hint": {"LOD1": 0.5, "LOD2": 0.25, "LOD3": 0.125},
        "note": "kiểm silhouette và UV seam từng LOD bằng review_shots.py; LOD3+ cân nhắc billboard/culled",
    }


def _build_parser():
    p = bx.add_common(bx.parser(__doc__))
    p.add_argument("--ratios", nargs="*", type=float, default=None, help="tỉ lệ decimate (mặc định 0.5 0.25 0.125)")
    p.add_argument("--symmetry", action="store_true", help="giữ đối xứng khi decimate")
    p.add_argument("--cleanup", dest="do_cleanup", action="store_true", help="dọn mesh nguồn trước khi sinh LOD")
    p.add_argument("--rename", action="store_true", help="đổi tên nguồn thành <base>_LOD0 cho Unity LODGroup")
    p.add_argument("--collection", default=None, help="đưa các bản LOD vào collection riêng")
    return p


if __name__ == "__main__":
    bx.cli(run, _build_parser())
