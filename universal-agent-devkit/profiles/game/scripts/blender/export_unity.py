#!/usr/bin/env python3
"""Xuất asset Blender 5.2+ chuẩn Unity 6.3 (FBX static / FBX skeletal / glTF GLB) kèm kiểm chứng round-trip.

Chuyển thể có chọn lọc từ scenario-labs/skills (MIT License — bx_export.py).
Mọi preset Unity đã được đo kiểm trên Unity 6.3 LTS:
  - unity:          static mesh, scale 1, rotation 0 (bake_space_transform=True, FBX_SCALE_ALL)
  - unity_skeletal: mesh có xương, KHÔNG bật bake_space_transform (hỏng với armature) và giữ Bake Axis Conversion OFF trong Unity
  - gltf:           GLB 2.0 Y-up (dùng kèm glTFast nếu dự án chọn glTF)

Cách dùng:
  blender --disable-autoexec -b f.blend --python-exit-code 1 -P export_unity.py -- \
      --preset unity --out /abs/Crate.fbx [--objects SM_Crate] [--round-trip]
  python3 export_unity.py -- --glb-summary /abs/crate.glb
"""
import json
import os
import struct
import subprocess
import sys
import tempfile

try:
    import bpy
    from mathutils import Vector
except ImportError:  # glb_summary() và --help chạy được bằng Python thuần không cần Blender
    bpy = None
    Vector = None

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _bpyx as bx  # noqa: E402

_FBX = dict(
    use_selection=True,
    apply_unit_scale=True,
    use_mesh_modifiers=True,
    mesh_smooth_type="FACE",
    add_leaf_bones=False,
    path_mode="COPY",
    embed_textures=True,
    axis_forward="-Z",
    axis_up="Y",
)
_FBX_RIG = dict(
    object_types={"ARMATURE", "MESH"},
    use_armature_deform_only=True,
    bake_anim=True,
    bake_anim_use_all_actions=True,
    bake_anim_use_nla_strips=False,
)
_GLB = dict(export_format="GLB", use_selection=True, export_yup=True, export_apply=True)

# Bảng preset: tên -> (đuôi file, operator xuất, tham số)
PRESETS = {
    # Unity 6.3 static mesh: nhập vào với scale 1, rotation 0
    "unity": (
        ".fbx",
        "export_scene.fbx",
        dict(_FBX, apply_scale_options="FBX_SCALE_ALL", bake_space_transform=True,
             object_types={"MESH", "EMPTY"}, bake_anim=False),
    ),
    # Unity 6.3 skeletal: KHÔNG bật bake_space_transform (hỏng với armature) và tắt Bake Axis Conversion ở Unity
    "unity_skeletal": (
        ".fbx",
        "export_scene.fbx",
        dict(**_FBX, **_FBX_RIG, apply_scale_options="FBX_SCALE_ALL"),
    ),
    "gltf": (".glb", "export_scene.gltf", dict(_GLB)),
}

CARRIES = {
    "unity": {"maps"},
    "unity_skeletal": {"armature", "actions", "shape_keys", "maps"},
    "gltf": {"armature", "actions", "shape_keys", "maps"},
}
MAP_INPUTS = ("Base Color", "Metallic", "Roughness", "Normal", "Emission Color")
IMPORTERS = {
    ".glb": "import_scene.gltf",
    ".gltf": "import_scene.gltf",
    ".fbx": "import_scene.fbx",
}
IMAGE_EXT = {
    "JPEG": ".jpg", "PNG": ".png", "TARGA": ".tga", "TARGA_RAW": ".tga",
    "TIFF": ".tif", "WEBP": ".webp", "BMP": ".bmp", "OPEN_EXR": ".exr", "HDR": ".hdr",
}


def _op(op_path):
    module, name = op_path.split(".")
    return getattr(getattr(bpy.ops, module), name)


def _select_targets(objects):
    if objects is None:
        return [o for o in bpy.context.scene.objects if o.visible_get()]
    return [bpy.data.objects[o] if isinstance(o, str) else o for o in objects]


def _name_packed_images():
    """Đặt đuôi file cho ảnh đã pack không có extension để Unity Extract Textures không bỏ sót."""
    named = []
    for img in bpy.data.images:
        if img.packed_file is not None and not os.path.splitext(img.filepath or img.name)[1]:
            named.append((img, img.filepath_raw))
            img.filepath_raw = (
                "//textures/" + bpy.path.clean_name(img.name) + IMAGE_EXT.get(img.file_format, ".png")
            )
    return named


def _image_nodes(tree, seen):
    for n in tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            yield n
        elif n.type == "GROUP" and n.node_tree and n.node_tree not in seen:
            seen.add(n.node_tree)
            yield from _image_nodes(n.node_tree, seen)


def _pack_unsaved_images(objs, tmp):
    """Đóng gói tạm các ảnh GENERATED/is_dirty để FBX exporter nhúng đủ texture mới nhất."""
    swaps, copies, seen = [], {}, set()
    mats = {s.material for o in objs if o.type == "MESH" for s in o.material_slots if s.material}
    for mat in mats:
        if not mat.node_tree:
            continue
        for n in _image_nodes(mat.node_tree, seen):
            img = n.image
            if img.packed_file is not None or not (img.source == "GENERATED" or img.is_dirty):
                continue
            if img not in copies:
                w, h = img.size
                px = [0.0] * (w * h * 4)
                img.pixels.foreach_get(px)
                name = img.name
                img.name = name + ".bx_original"
                cp = bpy.data.images.new(name, w, h, alpha=True)
                cp.pixels.foreach_set(px)
                cp.colorspace_settings.name = img.colorspace_settings.name
                cp.alpha_mode = img.alpha_mode
                cp.filepath_raw = os.path.join(tmp, bpy.path.clean_name(name) + ".png")
                cp.file_format = "PNG"
                cp.save()
                cp.pack()
                copies[img] = cp
            swaps.append((n, img))
            n.image = copies[img]
    return swaps, copies


def _fed_by_image(sock):
    stack, seen = [lk.from_node for lk in sock.links], set()
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        if n.type == "TEX_IMAGE" and n.image:
            return True
        if n.type == "GROUP" and n.node_tree and next(_image_nodes(n.node_tree, set()), None):
            return True
        stack.extend(lk.from_node for i in n.inputs for lk in i.links)
    return False


def _principled(mat):
    tree = mat.node_tree if mat else None
    return next((n for n in tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if tree else None


def _maps(obj):
    out = {}
    for s in obj.material_slots:
        bsdf = _principled(s.material)
        if bsdf:
            out[s.material.name] = [k for k in MAP_INPUTS if k in bsdf.inputs and _fed_by_image(bsdf.inputs[k])]
    return out


def export(out_path, preset="unity", objects=None, **overrides):
    """Xuất object (mặc định toàn bộ object hiển thị) theo preset Unity và khôi phục trạng thái scene."""
    bx.require_bpy()
    if preset not in PRESETS:
        raise ValueError(f"preset không hợp lệ: {preset!r} (hỗ trợ: {sorted(PRESETS)})")
    ext, op, kw = PRESETS[preset]
    if not out_path.lower().endswith(ext):
        raise ValueError(f"preset {preset!r} yêu cầu đuôi file {ext}")
    objs = _select_targets(objects)
    if not objs:
        raise ValueError("không có object nào để xuất")
    view = bpy.context.view_layer
    view.update()
    keep = ([o for o in view.objects if o.select_get()], view.objects.active)
    for o in view.objects:
        o.select_set(o in objs)
    view.objects.active = objs[0]
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    args = dict(kw, **overrides)
    embed = ext == ".fbx" and args.get("embed_textures")
    tmp = tempfile.TemporaryDirectory() if embed else None
    swaps, copies = _pack_unsaved_images(objs, tmp.name) if embed else ([], {})
    named = _name_packed_images() if embed else []
    try:
        _op(op)(filepath=out_path, **args)
    finally:
        for img, old in named:
            img.filepath_raw = old
        for n, img in swaps:
            n.image = img
        for img, cp in copies.items():
            name = cp.name
            bpy.data.images.remove(cp)
            img.name = name
        if tmp:
            tmp.cleanup()
        for o in view.objects:
            o.select_set(o in keep[0])
        view.objects.active = keep[1]
    return {
        "ok": True,
        "path": out_path,
        "preset": preset,
        "bytes": os.path.getsize(out_path),
        "objects": [o.name for o in objs],
        "packed_unsaved_images": sorted(img.name for img in copies),
        "blender": bpy.app.version_string,
    }


def inspect_scene(objects=None, all_actions=False):
    """Đo kích thước world, scale, tam giác, shape keys, image maps, xương và action của scene."""
    bx.require_bpy()
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    objs = _select_targets(objects)
    if objects is None:
        actions = {a.name for a in bpy.data.actions}
    else:
        actions = set()
        for o in objs:
            for ad in (o.animation_data, getattr(getattr(o.data, "shape_keys", None), "animation_data", None)):
                if ad:
                    actions |= {ad.action.name} if ad.action else set()
                    actions |= {s.action.name for t in ad.nla_tracks for s in t.strips if s.action}
        if all_actions:
            ids = {"OB" + o.name for o in objs}
            ids |= {"KE" + o.data.shape_keys.name for o in objs if o.type == "MESH" and o.data.shape_keys}
            actions |= {
                a.name for a in bpy.data.actions
                if any(s.identifier in ids for s in getattr(a, "slots", ()))
            }
    out = {"objects": {}, "actions": sorted(actions)}
    for o in objs:
        info = {"type": o.type, "scale": [round(s, 4) for s in o.matrix_world.to_scale()]}
        if o.type == "MESH":
            pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
            info["size"] = [round(max(p[k] for p in pts) - min(p[k] for p in pts), 4) for k in range(3)]
            me = o.evaluated_get(dg).to_mesh()
            try:
                info["tris"] = sum(len(p.vertices) - 2 for p in me.polygons)
            finally:
                o.evaluated_get(dg).to_mesh_clear()
            keys = o.data.shape_keys
            info["shape_keys"] = [k.name for k in keys.key_blocks[1:]] if keys else []
            info["maps"] = _maps(o)
        elif o.type == "ARMATURE":
            info["bones"] = len(o.data.bones)
            info["deform_bones"] = sum(b.use_deform for b in o.data.bones)
            info["roots"] = [b.name for b in o.data.bones if b.parent is None]
        out["objects"][o.name] = info
    return out


def inspect_file(path):
    """Nhập file FBX/GLB vào scene rỗng trong Blender và đo lại thông số thực tế."""
    bx.require_bpy()
    ext = os.path.splitext(path)[1].lower()
    if ext not in IMPORTERS:
        raise ValueError(f"định dạng không hỗ trợ inspect: {ext}")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _op(IMPORTERS[ext])(filepath=path)
    r = inspect_scene()
    r["ok"] = True
    r["file"], r["bytes"] = path, os.path.getsize(path)
    return r


def compare(before, after, carries=("armature", "actions", "shape_keys"), tol=0.001,
            deform_only=False, clip_names=True):
    """So sánh kết quả đo trước/sau khi xuất và nhập lại. Rỗng nghĩa là khớp hoàn toàn."""
    diffs = []
    ab = after["objects"]
    for name, b in before["objects"].items():
        if b["type"] not in ("MESH", "ARMATURE") or (b["type"] == "ARMATURE" and "armature" not in carries):
            continue
        a = ab.get(name) or next(
            (v for k, v in ab.items() if k.split(".")[0] == name and v["type"] == b["type"]), None
        )
        if a is None:
            diffs.append(f"{name}: missing after round trip")
            continue
        if b["type"] == "MESH":
            if any(abs(x - y) > tol for x, y in zip(sorted(b["size"]), sorted(a["size"]))):
                diffs.append(f"{name}: size {b['size']} became {a['size']}")
            if b["tris"] != a["tris"]:
                diffs.append(f"{name}: {b['tris']} triangles became {a['tris']}")
            if "shape_keys" in carries and set(b["shape_keys"]) - set(a["shape_keys"]):
                diffs.append(f"{name}: lost shape keys {sorted(set(b['shape_keys']) - set(a['shape_keys']))}")
            am = a.get("maps", {})
            for mat, socks in b.get("maps", {}).items() if "maps" in carries else ():
                got = am.get(mat) or next((v for k, v in am.items() if k.split(".")[0] == mat), [])
                lost = [k for k in socks if k not in got]
                if lost:
                    diffs.append(f"{name}: material {mat} lost maps {', '.join(lost)}")
        else:
            want = b.get("deform_bones", b["bones"]) if deform_only else b["bones"]
            if a["bones"] != want:
                diffs.append(f"{name}: {want} bones became {a['bones']}")
            if len(a.get("roots", ())) > 1:
                diffs.append(f"{name}: {len(a['roots'])} root bones {a['roots']}, Unity wants one")
            if any(abs(s - 1.0) > 1e-3 for s in a["scale"]):
                diffs.append(f"{name}: armature scale {a['scale']} after round trip")
    if "actions" in carries and clip_names:
        lost = [n for n in before["actions"] if not any(n in m for m in after["actions"])]
        if lost:
            diffs.append(f"actions lost: {lost}")
    elif "actions" in carries and len(after["actions"]) < len(before["actions"]):
        diffs.append(f"actions: {len(before['actions'])} became {len(after['actions'])}")
    return diffs


def round_trip(path, objects=None, preset="unity"):
    """Mở tiến trình Blender nền độc lập để nhập lại file vừa xuất và đối chiếu với scene gốc."""
    bx.require_bpy()
    carries = set(CARRIES.get(preset, ("armature", "actions", "shape_keys")))
    args = dict(PRESETS[preset][2]) if preset in PRESETS else {}
    all_actions = args.get("bake_anim_use_all_actions", True)
    before = inspect_scene(objects, all_actions=all_actions)
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "inspect.json")
        proc = subprocess.run(
            [
                bpy.app.binary_path, "--disable-autoexec", "-b", "--factory-startup",
                "--python-exit-code", "1", "-P", os.path.abspath(__file__),
                "--", "--inspect", path, "--json", out,
            ],
            capture_output=True, text=True, timeout=600,
        )
        if proc.returncode != 0:
            raise RuntimeError((proc.stdout[-1500:] + "\n" + proc.stderr[-1500:]).strip())
        with open(out, encoding="utf-8") as f:
            after = json.load(f)
    diffs = compare(
        before, after, carries,
        deform_only=args.get("use_armature_deform_only", False),
        clip_names=all_actions,
    )
    return {"pass": not diffs, "diffs": diffs, "before": before, "after": after}


def glb_summary(path):
    """Đọc chunk JSON của file .glb bằng Python thuần (không cần cài Blender)."""
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        raise ValueError("không phải file nhị phân glTF 2.0")
    size, kind = struct.unpack_from("<I4s", data, 12)
    if kind != b"JSON":
        raise ValueError("chunk đầu tiên của GLB không phải JSON")
    g = json.loads(data[20:20 + size])
    acc = g.get("accessors", [])
    tris, morphs = 0, {}
    for m in g.get("meshes", []):
        for p in m.get("primitives", []):
            if p.get("mode", 4) != 4:
                continue
            idx = p.get("indices")
            n = acc[idx]["count"] if idx is not None else acc[p["attributes"]["POSITION"]]["count"]
            tris += n // 3
        names = m.get("extras", {}).get("targetNames")
        if names:
            morphs[m.get("name", "")] = names
    return {
        "ok": True,
        "bytes": len(data),
        "extensions_used": g.get("extensionsUsed", []),
        "extensions_required": g.get("extensionsRequired", []),
        "nodes": len(g.get("nodes", [])),
        "meshes": len(g.get("meshes", [])),
        "triangles": tris,
        "morph_targets": morphs,
        "skins": [len(s.get("joints", [])) for s in g.get("skins", [])],
        "animations": [a.get("name", "") for a in g.get("animations", [])],
        "materials": len(g.get("materials", [])),
        "images": [i.get("mimeType", os.path.splitext(i.get("uri", ""))[1]) for i in g.get("images", [])],
    }


def run(preset="unity", out=None, objects=None, do_round_trip=False, inspect=None,
        glb_summary_path=None, json_out=None, **_):
    if glb_summary_path:
        res = glb_summary(glb_summary_path)
    elif inspect:
        res = inspect_file(inspect)
    else:
        if not out:
            raise ValueError("cần truyền --out <đường_dẫn> (hoặc --inspect / --glb-summary)")
        res = export(out, preset=preset, objects=objects)
        if do_round_trip:
            rt = round_trip(out, objects=objects, preset=preset)
            res["round_trip"] = rt
            if not rt["pass"]:
                res["ok"] = False
    if json_out:
        with open(json_out, "w", encoding="utf-8") as f:
            json.dump(res, f, indent=2)
    return res


def _build_parser():
    p = bx.add_common(bx.parser(__doc__), save=False)
    p.add_argument("--preset", default="unity", choices=sorted(PRESETS), help="preset xuất Unity")
    p.add_argument("--out", default=None, help="đường dẫn file .fbx/.glb đầu ra")
    p.add_argument("--round-trip", dest="do_round_trip", action="store_true",
                   help="nhập lại file vừa xuất trong Blender nền để kiểm sai lệch")
    p.add_argument("--inspect", default=None, help="nhập file FBX/GLB vào scene rỗng và đo")
    p.add_argument("--glb-summary", dest="glb_summary_path", default=None,
                   help="đọc tóm tắt file .glb bằng Python thuần (không cần Blender)")
    p.add_argument("--json", dest="json_out", default=None, help="ghi thêm kết quả JSON ra file này")
    return p


if __name__ == "__main__":
    args = _build_parser().parse_args(bx.argv())
    try:
        result = run(**vars(args))
        bx.emit(result)
        if not result.get("ok", True):
            sys.exit(1)
    except Exception as exc:
        bx.emit({"ok": False, "error": f"{type(exc).__name__}: {exc}"})
        sys.exit(1)
