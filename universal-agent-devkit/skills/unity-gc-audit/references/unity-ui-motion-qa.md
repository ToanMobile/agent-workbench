# Gói UI, tween, motion và QA bot cho Unity — nguồn và điều kiện dùng

Phạm vi: chỉ profile `game`. Rule ngắn nằm ở `profiles/game/rules/game-rules.md` §3–§7, asset ở `profiles/game/DESIGN.md` §7. Mọi mục dưới đây đã được đối chiếu với README/docs ngày 2026-10-12; mục chưa xác minh được ghi rõ. Mỗi gói là dependency mới (core §4: nêu lý do bậc 3–5 không đủ).

## Kết quả đối chiếu các tuyên bố đã gặp
| Tuyên bố | Kết quả |
|:---|:---|
| UIEffect có shiny, dissolve/transition bằng shader URP | Có (README). |
| UIEffect làm mờ hậu cảnh khi mở popup | CHƯA XÁC MINH: README chỉ có blur của chính graphic (BlurFast/Medium/Detail). |
| ParticleEffectForUGUI sửa lỗi sorting của particle trong UI | Có: `UIParticle` bake vào mesh Canvas. |
| SoftMask cho viền mịn | Có, nhưng chế độ "Anti-Aliasing" chỉ là stencil bớt răng cưa; viền mờ thật cần Soft Masking (RenderTexture). |
| PrimeTween không cấp phát | Có (README), kèm ngoại lệ: lambda bắt `this`, `async/await`, coroutine. |
| LitMotion không cấp phát, dựa struct | Có (README); "nhanh hơn 2–20 lần" không nêu đối thủ, số liệu chỉ ở ảnh biểu đồ. |
| DOTween cũ nên cấp phát GC trong Update | KHÔNG được nguồn ủng hộ: tài liệu DOTween nói cache/tái dùng; con số cấp phát của PrimeTween là mỗi lần tạo tween, không phải mỗi frame. |
| Animation Rigging có Foot IK bám dốc | KHÔNG: chỉ có constraint IK, raycast mặt đất tự viết; URL GitHub `Unity-Technologies/Animation-Rigging` trả 404. Không thành rule vì chỉ hợp game 3D có xương, ngoài phạm vi casual/puzzle của profile. |
| `KenneyNL` là org chứa asset | KHÔNG: là tài khoản cá nhân với 14 repo (đa số starter kit Godot); asset ở kenney.nl. |
| Unity-UI-Extensions có "Smart Tooltip" | Một phần: tên thật là `BoundToolTip`. Scroll Snap và Radial Layout có. |
| GAS của sjai013 cần DOTS | KHÔNG: dùng MonoBehaviour và coroutine; nhưng repo đã archived từ 2022. |

## Cài đặt và giấy phép (đã đọc)
- `mob-sakai/UIEffect` v5.11.7, MIT: `openupm add com.coffee.ui-effect` hoặc git URL `…UIEffect.git?path=Packages/src`. ShaderGraph cần Unity 2023.2+/6000.0+.
- `mob-sakai/ParticleEffectForUGUI`, MIT: `com.coffee.ui-particle`. Lỗi đã biết: `RibbonCount > 1` thường gây out-of-bounds triangle index; scale chứa 0 thì không render.
- `mob-sakai/SoftMaskForUGUI` v3.6.5, MIT: `com.coffee.softmask-for-ugui`. README ghi Unity 2019.4+ còn `package.json` ghi 2017.1: nguồn mâu thuẫn, thử trên phiên bản dự án.
- `KyryloKuzyk/PrimeTween`: license tuỳ chỉnh (GitHub hiển thị "Other"), dùng trong game miễn phí/thương mại được nhưng cấm bán lại và cấm đóng gói source trong sản phẩm phái sinh; cài qua Asset Store hoặc scoped registry npm. Đặt `PrimeTweenConfig.SetTweensCapacity(n)` lúc khởi động để tránh cấp phát khi mở rộng.
- `AnnulusGames/LitMotion`, MIT: Unity 2021.3+, phụ thuộc Burst 1.6.0+, Collections 1.5.1+, Mathematics 1.0.0+; cài qua git URL.
- DOTween: miễn phí (có bản Pro trả phí); `SetRecyclable`/`recycleAllByDefault` để tái dùng; mặc định chứa 200 Tweener và 50 Sequence, tự mở rộng, `SetCapacity` lúc khởi động tránh khựng.
- `Unity-UI-Extensions/com.unity.uiextensions` v3.0.0, BSD-3-Clause, cần Unity 6: `openupm add com.unity.uiextensions`.
- Lucide: ISC, ~1600 SVG, giữ thông báo bản quyền. Kenney: CC0 theo kenney.nl/support; đọc file license từng pack.

## Kiểm tra trước khi nhận một gói vào dự án
1. Ghi lý do không dùng được tính năng gốc (Canvas, Mask, ParticleSystem, DOTween đang có).
2. Đo Profiler/GC.Alloc và DrawCalls UI (≤ 15) trên máy yếu nhất trước/sau; với UIParticle so sánh có/không Mesh Sharing.
3. Build thử: shader variant của UIEffect đã đăng ký, hiệu ứng còn trong bản build (không chỉ trong Editor).
4. Ghi nguồn và giấy phép vào `docs/third-party-licenses.md`.
