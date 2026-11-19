---
name: blender-game-pipeline
description: "Dùng khi kiểm định QA mesh 3D, tạo chuỗi LOD, xuất FBX/glTF chuẩn Unity 6.3 hoặc chụp contact sheet review headless từ Blender 5.2+ cho dự án profile game. Bỏ qua với dự án không phải game 3D/Unity."
---

# Blender 5.2+ → Unity 6.3 Asset Pipeline (Profile Game)

Quy trình headless chuẩn để đưa asset 3D từ `Art/Source/*.blend` sang Unity 6.3 URP không lỗi scale/rotation, z-fighting, normal ngược hay thiếu texture. Toàn bộ script nằm tại `.agents/active-profile/scripts/blender/` và chạy an toàn với cờ `--disable-autoexec`.

## 1. Thứ tự chạy tiêu chuẩn cho 1 asset 3D

```bash
# Bước 1: Kiểm định QA hình học, UV, material, normal, z-fighting, valence >= 6, self-intersection
blender --disable-autoexec -b Art/Source/Crate.blend --python-exit-code 1 \
  -P .agents/active-profile/scripts/blender/qa_check.py -- \
  --objects SM_Crate --profile game

# Bước 2 (nếu >= 5.000 tris): Tạo chuỗi LOD0/LOD1/LOD2 cho Unity LODGroup
blender --disable-autoexec -b Art/Source/Crate.blend --python-exit-code 1 \
  -P .agents/active-profile/scripts/blender/make_lods.py -- \
  --objects SM_Crate --ratios 0.5 0.25 0.125 --cleanup --rename --save Art/Source/Crate_lods.blend

# Bước 3: Chụp contact sheet 4 góc (Workbench headless) để kiểm thị giác / wireframe
blender --disable-autoexec -b Art/Source/Crate.blend --python-exit-code 1 \
  -P .agents/active-profile/scripts/blender/review_shots.py -- \
  --objects SM_Crate --mode solid --out /tmp/crate_review.png

# Bước 4: Xuất FBX/GLB chuẩn Unity 6.3 và tự động nhập lại kiểm chứng round-trip
blender --disable-autoexec -b Art/Source/Crate.blend --python-exit-code 1 \
  -P .agents/active-profile/scripts/blender/export_unity.py -- \
  --preset unity --objects SM_Crate --out Assets/Art/Models/SM_Crate.fbx --round-trip
```

## 2. Quy tắc bắt buộc (chặn lỗi phổ biến)

- **Chặn QA đỏ trước khi export:** `qa_check.py` trả dòng `@@JSON@@{...}`; chỉ xuất khi `"pass": true`. Lỗi hay gặp: `unapplied scale`, `negative scale`, `inside_out_islands`, `z-fighting`, `missing texture`, hoặc map dữ liệu (`Roughness`/`Metallic`/`Normal`) để nhầm `sRGB` thay vì `Non-Color`.
- **Static vs Skeletal FBX:**
  - `--preset unity` bật `bake_space_transform=True` và `FBX_SCALE_ALL` → nhập vào Unity ở `scale = 1, rotation = 0`.
  - `--preset unity_skeletal` **KHÔNG** bật `bake_space_transform` (làm hỏng armature) và **tắt** `Bake Axis Conversion` trong Unity Model Importer (bật lên sẽ làm nhân vật quay lưng `-Z`).
- **Đọc nhanh file `.glb` không cần mở Blender:** `python3 .agents/active-profile/scripts/blender/export_unity.py -- --glb-summary path/to/asset.glb`.
- **Nguồn `.blend` luôn nằm ngoài `Assets/`** (đặt ở `Art/Source/`), tuân thủ `profiles/game/rules/game-rules.md` §2.

## 3. Tài liệu tham chiếu theo nhu cầu

Đọc `references/unity-blender-5x.md` khi cần tra cứu:
- Đóng gói kênh texture URP Lit (`R = Metallic, A = Smoothness`) và HDRP MaskMap.
- Danh sách 15 xương tối thiểu cho Humanoid (Mecanim) T-pose.
- Bảng thay đổi API Blender 4.x → 5.2/5.3 (tránh viết code `bpy` cũ bị lỗi như `use_auto_smooth`, `BLENDER_EEVEE_NEXT`, `material.use_nodes`).
