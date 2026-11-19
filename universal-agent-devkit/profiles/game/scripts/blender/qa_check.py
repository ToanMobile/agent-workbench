#!/usr/bin/env python3
"""Kiểm định QA mesh/asset 3D: z-fighting, mảnh lơ lửng, normal ngược, topology, self-intersection,
valence >= 6, transform chưa apply, UV, trọng số xương và material/texture (map dữ liệu để sRGB).

Chuyển thể từ EL4CTEO/blender-skills (MIT License) và bổ sung chỉ số self_intersections,
valence_6plus từ scenario-labs/skills (MIT License).

Cách dùng:
  blender --disable-autoexec -b f.blend --python-exit-code 1 -P qa_check.py -- \
      [--objects A B] [--profile game|render|print|roblox] [--eps 0.001] [--tol 0.002]
"""
import math
import os
import sys
from collections import Counter, defaultdict

try:
    import bmesh
    import bpy
    import numpy as np
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    from mathutils.kdtree import KDTree
except ImportError:  # cho phép chạy --help hoặc unit test pure-Python ngoài Blender
    bmesh = bpy = np = Vector = BVHTree = KDTree = None

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _bpyx as bx  # noqa: E402

# Mức độ kiểm tra theo profile ("e" lỗi chặn, "w" cảnh báo, None bỏ qua)
PROFILES = {
    #               zfight floating inverted inconsist nonmanif boundary degen dupes ngons scale uv  weights materials
    "game":   dict(zf="e", fl="e", inv="e", inc="e", nm="w", bd=None, dg="e", dup="w", ng="w", sc="e", uv="e", wt="e", mt="e"),
    "render": dict(zf="e", fl="e", inv="w", inc="w", nm=None, bd=None, dg="w", dup="w", ng=None, sc="w", uv="w", wt="w", mt="e"),
    "print":  dict(zf="e", fl="e", inv="e", inc="e", nm="e", bd="e", dg="e", dup="e", ng=None, sc="w", uv=None, wt=None, mt=None),
    "roblox": dict(zf="e", fl="e", inv="e", inc="e", nm="w", bd="w", dg="e", dup="w", ng="e", sc="e", uv="e", wt="e", mt="e"),
}
TRI_LIMIT = {"roblox": 20000}

DATA_INPUTS = {
    "Roughness", "Metallic", "Normal", "Alpha", "Specular IOR Level", "Coat Weight",
    "Coat Roughness", "Transmission Weight", "Subsurface Weight", "Anisotropic", "Sheen Weight", "IOR",
}
DATA_NODES = {"NORMAL_MAP", "BUMP", "DISPLACEMENT", "VECTOR_DISPLACEMENT"}


def _feeds(sock, depth=4):
    """Trả về tập cặp (loại node, tên input) mà socket truyền tới trong tối đa `depth` bước."""
    out = set()
    for lk in sock.links:
        n = lk.to_node
        out.add((n.type, lk.to_socket.name))
        if depth and n.type not in DATA_NODES and n.type != "BSDF_PRINCIPLED":
            for o in n.outputs:
                out |= _feeds(o, depth - 1)
    return out


def _material_issues(ob):
    """Trả về danh sách (is_error, thông điệp) cho slot vật liệu và image texture."""
    me, slots, out = ob.data, ob.material_slots, []
    idx = [0] * len(me.polygons)
    me.polygons.foreach_get("material_index", idx)
    used = set(idx)
    bad = sorted(i for i in used if i >= len(slots) or slots[i].material is None)
    if bad or not slots:
        out.append((True, f"{ob.name}: faces use empty/missing material slot(s) {bad or [0]} (grey in engines)"))
    unused = [s.name or str(i) for i, s in enumerate(slots) if i not in used]
    if unused:
        out.append((False, f"{ob.name}: unused material slot(s) {unused} (extra draw calls in some exporters)"))
    for i in sorted(used):
        mat = slots[i].material if i < len(slots) else None
        if mat is None or not mat.node_tree:
            continue
        for n in mat.node_tree.nodes:
            if n.type != "TEX_IMAGE":
                continue
            img = n.image
            if img is None:
                if n.outputs["Color"].is_linked or n.outputs["Alpha"].is_linked:
                    out.append((False, f"{mat.name}: image node {n.name!r} has no image"))
                continue
            if img.source == "FILE" and not img.packed_file and not os.path.exists(bpy.path.abspath(img.filepath)):
                out.append((True, f"{mat.name}: missing texture file {img.filepath!r}"))
            reach = _feeds(n.outputs["Color"])
            data_use = sorted(
                {s for t, s in reach if t == "BSDF_PRINCIPLED" and s in DATA_INPUTS}
                | {t.lower() for t, _s in reach if t in DATA_NODES}
            )
            if data_use and not img.colorspace_settings.is_data:
                out.append((True, f"{mat.name}: {img.name} feeds {data_use} but is {img.colorspace_settings.name} "
                                  "(must be Non-Color)"))
            if img.colorspace_settings.is_data and ("BSDF_PRINCIPLED", "Base Color") in reach:
                out.append((False, f"{mat.name}: {img.name} is Non-Color but drives Base Color (looks washed out)"))
    return out


def _mesh_world(ob, use_mods):
    """Tạo bmesh ở toạ độ world-space (có hoặc không tính modifier)."""
    bm = bmesh.new()
    if use_mods:
        dg = bpy.context.evaluated_depsgraph_get()
        bm.from_object(ob, dg)
    else:
        bm.from_mesh(ob.data)
    bm.transform(ob.matrix_world)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    return bm


def _islands(bm):
    """Phân nhóm các thành phần liên thông (islands) của mesh bằng Union-Find."""
    parent = list(range(len(bm.verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for e in bm.edges:
        a, b = find(e.verts[0].index), find(e.verts[1].index)
        if a != b:
            parent[a] = b
    roots = [find(i) for i in range(len(bm.verts))]
    remap = {r: n for n, r in enumerate(dict.fromkeys(roots))}
    return [remap[r] for r in roots]


def _self_intersections(bm, limit=200000):
    """Đếm số cặp mặt không chung đỉnh nhưng cắt xuyên nhau (từ scenario-labs/skills)."""
    if len(bm.faces) > limit:
        return None
    tree = BVHTree.FromBMesh(bm)
    faces = bm.faces
    n = 0
    for a, b in tree.overlap(tree):
        if a >= b:
            continue
        va = {v.index for v in faces[a].verts}
        if va & {v.index for v in faces[b].verts}:
            continue
        n += 1
    return n


def _point_in_tri(p, a, b, c, n):
    for u, v in ((a, b), (b, c), (c, a)):
        if (v - u).cross(p - u).dot(n) < -1e-9:
            return False
    return True


def _uv_stats(ob, bm_local):
    """Đo thống kê UV: ngoài vùng 0-1, diện tích 0, chồng lấn và độ phủ."""
    me = ob.data
    if not me.uv_layers:
        return {"uv_maps": 0}
    uv = bm_local.loops.layers.uv.active
    oob = total = zero = 0
    n = 128
    # Lưới raster thô cố định kích thước để tránh tốn RAM khi nhiều mặt chồng nhau
    owner = np.full((n, n), -1, dtype=np.int64)
    over = np.zeros((n, n), dtype=bool)
    step = max(1, len(bm_local.faces) // 30000)
    for f in list(bm_local.faces)[::step]:
        pts = [l[uv].uv.copy() for l in f.loops]
        for p in pts:
            total += 1
            if p.x < -1e-4 or p.y < -1e-4 or p.x > 1.0001 or p.y > 1.0001:
                oob += 1
        a2 = sum(
            pts[i].x * pts[(i + 1) % len(pts)].y - pts[(i + 1) % len(pts)].x * pts[i].y
            for i in range(len(pts))
        )
        if abs(a2) < 1e-12:
            zero += 1
            continue
        xs, ys = [p.x for p in pts], [p.y for p in pts]
        x0, x1 = max(0, int(min(xs) * n)), min(n, int(max(xs) * n) + 1)
        y0, y1 = max(0, int(min(ys) * n)), min(n, int(max(ys) * n) + 1)
        if x0 >= x1 or y0 >= y1:
            continue
        cx, cy = np.meshgrid((np.arange(x0, x1) + 0.5) / n, (np.arange(y0, y1) + 0.5) / n, indexing="ij")
        inside = np.zeros(cx.shape, dtype=bool)
        for i in range(1, len(pts) - 1):
            t = (pts[0], pts[i], pts[i + 1])
            d = [
                (t[(k + 1) % 3].x - t[k].x) * (cy - t[k].y) - (t[(k + 1) % 3].y - t[k].y) * (cx - t[k].x)
                for k in range(3)
            ]
            inside |= ((d[0] >= 0) & (d[1] >= 0) & (d[2] >= 0)) | ((d[0] <= 0) & (d[1] <= 0) & (d[2] <= 0))
        win, ov = owner[x0:x1, y0:y1], over[x0:x1, y0:y1]
        ov |= inside & (win >= 0) & (win != f.index)
        win[inside & (win < 0)] = f.index
    used = int((owner >= 0).sum())
    overlap = int(over.sum())
    return {
        "uv_maps": len(me.uv_layers),
        "uv_oob_pct": round(100 * oob / max(total, 1), 2),
        "uv_zero_area_faces": zero,
        "uv_overlap_pct": round(100 * overlap / max(used, 1), 2),
        "uv_coverage_pct": round(100 * used / n / n, 1),
    }


def run(objects=None, profile="game", eps=0.001, tol=0.002, no_modifiers=False, max_tris=300000,
        uv=True, **_):
    bx.object_mode()
    sev = PROFILES[profile]
    obs = [o for o in bx.objects(objects) if o.type == "MESH"]
    if not obs:
        raise ValueError("không có mesh object nào để kiểm tra")
    errors, warnings, per = [], [], {}

    def flag(key, msg):
        s = sev.get(key)
        if s == "e":
            errors.append(msg)
        elif s == "w":
            warnings.append(msg)

    # ---- Gom toàn bộ tam giác world-space của các object trong asset ----
    verts, tris, tri_meta = [], [], []  # tri_meta: (obj_i, island_gid, normal)
    island_info = {}                    # gid -> dict(ob, verts, tris, bbox)
    gid_base = 0
    min_z = math.inf
    for oi, ob in enumerate(obs):
        bm = _mesh_world(ob, not no_modifiers)
        m = {}
        isl = _islands(bm)
        n_isl = max(isl) + 1 if isl else 0
        base_v = len(verts)
        verts.extend(v.co.copy() for v in bm.verts)
        if bm.verts:
            min_z = min(min_z, min(v.co.z for v in bm.verts))
        # Chỉ số topology cơ bản + valence >= 6 + self-intersections
        ecount = Counter(len(e.link_faces) for e in bm.edges)
        m["verts"], m["faces"] = len(bm.verts), len(bm.faces)
        m["tris"] = sum(len(f.verts) - 2 for f in bm.faces)
        m["ngons"] = sum(1 for f in bm.faces if len(f.verts) > 4)
        m["boundary_edges"] = ecount.get(1, 0)
        m["nonmanifold_edges"] = sum(c for k, c in ecount.items() if k > 2)
        m["wire_edges"] = ecount.get(0, 0)
        m["loose_verts"] = sum(1 for v in bm.verts if not v.link_edges)
        m["degenerate_faces"] = sum(1 for f in bm.faces if f.calc_area() < 1e-10)
        m["zero_length_edges"] = sum(1 for e in bm.edges if e.calc_length() < 1e-7)
        m["valence_6plus"] = sum(
            1 for v in bm.verts if not v.is_boundary and len(v.link_edges) >= 6
        )
        m["self_intersections"] = _self_intersections(bm)
        directed = Counter((l.vert.index, l.link_loop_next.vert.index) for f in bm.faces for l in f.loops)
        m["inconsistent_normals_edges"] = sum(1 for _k, c in directed.items() if c > 1)
        kd = KDTree(len(bm.verts))
        for v in bm.verts:
            kd.insert(v.co, v.index)
        kd.balance()
        m["duplicate_verts"] = sum(1 for v in bm.verts if len(kd.find_range(v.co, 1e-5)) > 1) // 2
        m["islands"] = n_isl

        # Thể tích có dấu theo từng island khép kín để phát hiện normal bị lộn vào trong
        vol, closed = defaultdict(float), defaultdict(lambda: True)
        for e in bm.edges:
            if len(e.link_faces) != 2:
                closed[isl[e.verts[0].index]] = False
        bm_t = bm.copy()
        bmesh.ops.triangulate(bm_t, faces=bm_t.faces[:])
        bm_t.verts.ensure_lookup_table()
        # Tính thể tích quanh một đỉnh ngay trên island để tránh sai số float32 khi ở xa gốc toạ độ
        ref = {}
        for v in bm.verts:
            ref.setdefault(isl[v.index], v.co.copy())
        for f in bm_t.faces:
            g = isl[f.verts[0].index]
            o = ref[g]
            a, b, c = (v.co - o for v in f.verts)
            vol[g] += a.dot(b.cross(c)) / 6.0
            tris.append(tuple(base_v + v.index for v in f.verts))
            tri_meta.append((oi, gid_base + g, f.normal.copy()))
        bm_t.free()
        m["inside_out_islands"] = sum(1 for g in range(n_isl) if closed[g] and vol[g] < -1e-9)

        groups = defaultdict(list)
        for i, g in enumerate(isl):
            groups[g].append(i)
        for g, idx in groups.items():
            pts = [bm.verts[i].co for i in idx]
            lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
            hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
            island_info[gid_base + g] = {
                "ob": ob.name, "verts": [base_v + i for i in idx],
                "center": (lo + hi) / 2, "size": (hi - lo).length,
                "closed": closed[g], "tris": [],
            }
        gid_base += n_isl

        # Transform: scale chưa apply hoặc scale âm
        s = ob.scale
        m["scale"] = bx.r(tuple(s), 3)
        if any(abs(x - 1) > 1e-4 for x in s):
            flag("sc", f"{ob.name}: unapplied scale {m['scale']}")
        if s.x * s.y * s.z < 0:
            errors.append(f"{ob.name}: negative scale (flips normals on export)")

        # Material & texture
        m["materials"] = len(ob.material_slots)
        for is_err, msg in _material_issues(ob):
            if is_err:
                flag("mt", msg)
            else:
                warnings.append(msg)

        # Trọng số skinning (Unity chuẩn tối đa 4 xương/đỉnh)
        arm_mod = next((md for md in ob.modifiers if md.type == "ARMATURE" and md.object), None)
        if arm_mod and ob.vertex_groups:
            deform = {b.name for b in arm_mod.object.data.bones if b.use_deform}
            gidx = {g.index for g in ob.vertex_groups if g.name in deform}
            unweighted = over4 = 0
            for v in ob.data.vertices:
                ws = [g for g in v.groups if g.group in gidx and g.weight > 1e-4]
                unweighted += not ws
                over4 += len(ws) > 4
            m["unweighted_verts"], m["verts_over_4_influences"] = unweighted, over4
            if unweighted:
                flag("wt", f"{ob.name}: {unweighted} verts with no deform weights")
            if over4:
                flag("wt", f"{ob.name}: {over4} verts with >4 bone influences")

        # UV map
        if uv:
            bm_l = bmesh.new()
            bm_l.from_mesh(ob.data)
            m.update(_uv_stats(ob, bm_l))
            bm_l.free()
            if m["uv_maps"] == 0:
                flag("uv", f"{ob.name}: no UV map")
            else:
                if m["uv_zero_area_faces"]:
                    flag("uv", f"{ob.name}: {m['uv_zero_area_faces']} zero-area UV faces")
                if m["uv_oob_pct"] > 0 and profile in ("roblox",):
                    flag("uv", f"{ob.name}: {m['uv_oob_pct']}% UVs outside 0-1")
                if m["uv_overlap_pct"] > 5:
                    warnings.append(
                        f"{ob.name}: ~{m['uv_overlap_pct']}% UV overlap "
                        "(ok only if mirrored/stacked on purpose; bakes break)"
                    )
        bm.free()

        # Gắn cờ lỗi/cảnh báo theo bảng severity
        if m["inside_out_islands"]:
            flag("inv", f"{ob.name}: {m['inside_out_islands']} closed parts with normals pointing inward")
        if m["inconsistent_normals_edges"]:
            flag("inc", f"{ob.name}: {m['inconsistent_normals_edges']} edges with inconsistent face winding")
        if m["nonmanifold_edges"] or m["wire_edges"]:
            flag("nm", f"{ob.name}: non-manifold edges={m['nonmanifold_edges']} wire={m['wire_edges']}")
        if m["boundary_edges"]:
            flag("bd", f"{ob.name}: {m['boundary_edges']} open boundary edges (not watertight)")
        if m["degenerate_faces"] or m["zero_length_edges"]:
            flag("dg", f"{ob.name}: degenerate faces={m['degenerate_faces']} zero-len edges={m['zero_length_edges']}")
        if m["duplicate_verts"] or m["loose_verts"]:
            flag("dup", f"{ob.name}: duplicate verts={m['duplicate_verts']} loose verts={m['loose_verts']}")
        if m["ngons"]:
            flag("ng", f"{ob.name}: {m['ngons']} n-gons")
        if m["valence_6plus"]:
            warnings.append(f"{ob.name}: {m['valence_6plus']} interior pole(s) with valence >= 6 (shading/pinching risk)")
        if m["self_intersections"]:
            warnings.append(f"{ob.name}: {m['self_intersections']} self-intersecting face pair(s)")
        lim = TRI_LIMIT.get(profile)
        if lim and m["tris"] > lim:
            errors.append(f"{ob.name}: {m['tris']} tris > {profile} limit {lim}")
        per[ob.name] = m

    if len(tris) > max_tris:
        warnings.append(f"{len(tris)} tris > max_tris {max_tris}: z-fighting/floating checks skipped")
        return _result(errors, warnings, per, min_z, tol, [], [], [])

    bvh = BVHTree.FromPolygons(verts, tris, epsilon=0.0)
    tri_sets = [set(t) for t in tris]
    for ti, (_, g, _) in enumerate(tri_meta):
        island_info[g]["tris"].append(ti)

    # ---- Kiểm tra z-fighting: mặt song song trong khoảng eps và chồng diện tích ----
    zf_pairs, contact_pairs = set(), set()
    for ti, t in enumerate(tris):
        a, b, c = (verts[i] for i in t)
        n = tri_meta[ti][2]
        if n.length < 0.5:
            continue
        cen = (a + b + c) / 3
        for p in (cen, cen.lerp(a, 0.6), cen.lerp(b, 0.6), cen.lerp(c, 0.6)):
            for _, _, tj, _ in bvh.find_nearest_range(p, eps):
                if tj is None or tj == ti or (tri_sets[ti] & tri_sets[tj]):
                    continue
                n2 = tri_meta[tj][2]
                d = n.dot(n2)
                if abs(d) < 0.999:
                    continue
                a2, b2, c2 = (verts[i] for i in tris[tj])
                q = p - n2 * n2.dot(p - a2)
                if _point_in_tri(q, a2, b2, c2, n2):
                    (zf_pairs if d > 0 else contact_pairs).add((min(ti, tj), max(ti, tj)))

    def _describe(pairs):
        out = Counter()
        for i, j in pairs:
            oa, ob_ = obs[tri_meta[i][0]].name, obs[tri_meta[j][0]].name
            out[f"{oa}<->{ob_}" if oa != ob_ else oa] += 1
        return [{"where": k, "tri_pairs": v} for k, v in out.most_common(20)]

    zf = _describe(zf_pairs)
    for z in zf:
        flag("zf", f"z-fighting: {z['where']} ({z['tri_pairs']} overlapping coplanar tri pairs)")
    contact = _describe(contact_pairs)
    for z in contact:
        warnings.append(f"hidden back-to-back faces: {z['where']} ({z['tri_pairs']} pairs) - delete to save tris")

    # ---- Kiểm tra mảnh rời / lơ lửng (floating islands) ----
    floating, enclosed = [], []
    if len(island_info) > 1:
        tri_island = [m_[1] for m_ in tri_meta]
        biggest = max(island_info, key=lambda g: island_info[g]["size"])
        for g, info in island_info.items():
            if g == biggest:
                continue
            touching = False
            vs = info["verts"]
            step = max(1, len(vs) // 400)
            for vi in vs[::step]:
                for _, _, tj, _ in bvh.find_nearest_range(verts[vi], tol):
                    if tj is not None and tri_island[tj] != g:
                        touching = True
                        break
                if touching:
                    break
            if not touching and info["tris"]:
                sub = BVHTree.FromPolygons(verts, [tris[t] for t in info["tris"]], epsilon=0.0)
                touching = any(tri_island[j] != g for _, j in sub.overlap(bvh))
            if touching:
                continue
            # Kiểm tra bằng tia ray-cast xem mảnh có nằm lọt hẳn bên trong khối khác không
            org, hits, d = info["center"], 0, Vector((0.137, 0.271, 0.953)).normalized()
            p = org.copy()
            for _ in range(64):
                loc, _, tj, _ = bvh.ray_cast(p, d)
                if loc is None:
                    break
                if tri_island[tj] != g:
                    hits += 1
                p = loc + d * 1e-5
            rec = {"object": info["ob"], "island_verts": len(vs), "center": bx.r(tuple(info["center"]), 3)}
            (enclosed if hits % 2 == 1 else floating).append(rec)
    for f in floating:
        flag("fl", f"floating/detached part in {f['object']} ({f['island_verts']} verts at {f['center']})")
    if enclosed:
        warnings.append(
            f"{len(enclosed)} parts fully enclosed, not touching (eyes/internals?): "
            f"{[e['object'] for e in enclosed][:5]}"
        )
    return _result(errors, warnings, per, min_z, tol, zf, floating, contact, enclosed)


def _result(errors, warnings, per, min_z, tol, zf, floating, contact, enclosed=()):
    ground = None if min_z == math.inf else round(min_z, 4)
    if ground is not None and abs(ground) > max(tol, 1e-3):
        warnings.append(f"asset lowest point z={ground} (not resting on ground plane z=0)")
    return {
        "ok": True,
        "pass": not errors,
        "errors": errors,
        "warnings": warnings,
        "ground_z": ground,
        "zfighting": zf,
        "floating": floating,
        "back_to_back": contact,
        "enclosed": list(enclosed),
        "objects": per,
    }


def _build_parser():
    p = bx.add_common(bx.parser(__doc__), save=False)
    p.add_argument("--profile", default="game", choices=list(PROFILES))
    p.add_argument("--eps", type=float, default=0.001, help="khoảng cách mặt song song để bắt z-fighting (m)")
    p.add_argument("--tol", type=float, default=0.002, help="ngưỡng tiếp xúc cho mảnh rời (m)")
    p.add_argument("--no-modifiers", action="store_true")
    p.add_argument("--max-tris", type=int, default=300000)
    p.add_argument("--no-uv", dest="uv", action="store_false")
    return p


if __name__ == "__main__":
    bx.cli(run, _build_parser())
