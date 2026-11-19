# Tham chiếu Unity 6.3 URP & Blender 5.x API Deltas

> Tổng hợp có chọn lọc từ `EL4CTEO/blender-skills` (MIT) và `scenario-labs/skills` (MIT), đối chiếu cho Blender 5.2+ và Unity 6.3 LTS (URP 17.3).

## 1. Thiết lập FBX & Unity 6.3 Model Importer

| Trường hợp | Preset `export_unity.py` | Quy tắc bắt buộc |
|---|---|---|
| Mesh tĩnh (prop, môi trường) | `unity` | `apply_scale_options="FBX_SCALE_ALL"`, `bake_space_transform=True`, Forward `-Z`, Up `Y`, Smoothing `FACE`, `add_leaf_bones=False`. Nhập vào Unity đạt `scale = 1`, `rotation = 0`. |
| Nhân vật có xương / animation | `unity_skeletal` | `apply_scale_options="FBX_SCALE_ALL"`, `use_armature_deform_only=True`, **KHÔNG** bật `bake_space_transform`. Trong Unity Model Importer **giữ tắt** `Bake Axis Conversion` (bật lên sẽ quay ngược nhân vật sang `-Z`). |
| glTF 2.0 nhị phân | `gltf` | Y-up, apply modifiers; Unity cần gói `com.unity.cloud.gltfast` (FBX vẫn là mặc định). |

- Unity Importer (Model tab): `Scale Factor = 1`, bật `Convert Units`, `Normals = Import`, `Tangents = Import` (hoặc `Calculate Mikktspace`).
- Đặt tên chuỗi LOD: `<Tên>_LOD0`, `<Tên>_LOD1`, `<Tên>_LOD2` để Unity tự nhận `LODGroup`.
- Animation tách file theo chuẩn `Hero@Run.fbx` để dùng chung Avatar.

## 2. Kênh Texture URP / HDRP & Humanoid Mecanim

- **URP Lit:**
  - `BaseMap` (sRGB)
  - `NormalMap` (OpenGL `+Y`, đánh dấu `Normal map` trong Unity, `Non-Color` trong Blender)
  - `MetallicGlossMap`: **`R = Metallic`, `A = Smoothness`** (`Smoothness = 1 - Roughness`)
  - `Occlusion`: tách riêng
- **HDRP Lit (`MaskMap`):** `R = Metallic`, `G = AO`, `B = Detail Mask`, `A = Smoothness`.
- **Humanoid (Mecanim) tối thiểu 15 xương (T-pose):** `Hips` (gốc deform, có thể có xương `root` phía trên cho root motion), `Spine`, `Head`, `UpperLeg/LowerLeg/Foot` (L/R), `UpperArm/LowerArm/Hand` (L/R). Mỗi đỉnh tối đa **4 xương ảnh hưởng** (`qa_check.py` tự kiểm).

## 3. Các thay đổi API Blender 4.x → 5.2/5.3 hay gây lỗi script `bpy`

| API cũ (hay bị viết nhầm) | API đúng trên Blender 5.2+ |
|---|---|
| `mesh.use_auto_smooth`, `auto_smooth_angle` | Đã xoá (4.1). Dùng `bpy.ops.object.shade_smooth_by_angle(angle=...)` hoặc modifier `Smooth by Angle`. |
| `mesh.calc_normals_split()`, `loop.normal` | Dùng `mesh.corner_normals` (read-only) và `mesh.normals_domain`. |
| `engine = "BLENDER_EEVEE_NEXT"` | Đổi lại thành `"BLENDER_EEVEE"` (5.0). Headless review dùng `"BLENDER_WORKBENCH"`. |
| `image_settings.file_format = "PNG"` đơn lẻ | Đặt `image_settings.media_type = "IMAGE"` **trước** `file_format` (5.0). |
| `material.use_nodes = True` | Deprecated (5.0); material mới luôn có sẵn `Principled BSDF` + `Material Output`. |
| Principled socket `Specular`, `Subsurface`, `Coat`, `Emission` | Đổi tên thành `Specular IOR Level`, `Subsurface Weight`, `Coat Weight`, `Emission Color`. |
| `action.fcurves` / `action.groups` trực tiếp | Slotted/layered actions (5.0+): lấy channelbag qua `anim_utils.action_ensure_channelbag_for_slot(action, slot)` và gán `animation_data.action_slot`. |
| `Boolean` solver `"FAST"` | Đổi thành `"FLOAT"` (`EXACT`, `FLOAT`, `MANIFOLD`). |
| `scene.node_tree`, `scene.use_nodes` | Dùng `scene.compositing_node_group` (5.0+). |
| `bgl`, `Image.bindcode` | Dùng module `gpu` (gọi `gpu.init()` nếu dùng trong `--background` từ 5.2). |
