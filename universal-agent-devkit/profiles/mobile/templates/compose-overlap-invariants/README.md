# Compose Overlap Invariants Template

Template này chứa công cụ test cấu trúc hình học và UI overlap cho dự án Android dùng Jetpack Compose.
Giới hạn: Kit này chỉ chứa template, Kotlin code ở đây KHÔNG được biên dịch bên trong DevKit. Helper này bơm cấu hình và Insets thông qua Compose `CompositionLocalProvider` và `ViewCompat.dispatchApplyWindowInsets` tới view gốc (root view) để các composable có thể đọc `WindowInsets.navigationBars` và các inset khác bình thường.

## Các file trong thư mục
- `README.md`: Hướng dẫn sử dụng này.
- `OverlapInvariants.kt`: Helper script để load config và verify invariants.
- `config.csv`: File bảng cấu hình mẫu chứa ma trận trạng thái (cấu hình màn hình, insets, ...).
- `ExampleOverlapTest.kt`: Ví dụ tham khảo cách viết test dùng helper này (thất bại vs thành công).

Lưu ý: Helper hiện tại CHƯA kiểm tra lỗi inset kép ở CẠNH BÊN (như thanh điều hướng 3 nút khi xoay ngang `landscape_3button`). Lỗi này chỉ được kiểm tra ở ĐÁY màn hình thông qua `bottomAnchoredTags`. Người dùng cần tự cài đặt thêm kiểm tra khoảng cách cạnh nếu muốn bắt chặt chẽ.

## Phụ thuộc
Để sử dụng helper này, dự án Android của bạn cần các thư viện sau:
- `androidx.compose.material3:material3`
- `androidx.compose.ui:ui-test-junit4` (compose-ui-test) - version tương ứng với Compose BOM `2024.02.00` (hoặc tương tự).
- `androidx.compose.ui:ui-test-manifest` (debugImplementation)
- `org.robolectric:robolectric` (Robolectric) - khuyên dùng version `4.11` trở lên và nhớ dùng `@RunWith(RobolectricTestRunner::class)`.

## Cách copy
Copy các file `.kt` và `config.csv` vào thư mục `src/test/java/...` của dự án của bạn và **đổi package** ở đầu file cho phù hợp với dự án.
Bạn có thể tuỳ chỉnh `config.csv` để thêm các trạng thái test (dùng dấu phẩy `,` để phân cách các cột). Đảm bảo đường dẫn đến file `config.csv` tính từ working dir của module Gradle. Đơn vị của `statusInset`, `navInset`, và `cutoutInset` là **PX** (trong môi trường test Robolectric với density mặc định 1.0 thì px = dp). Khoảng cách tính bằng px, và check khoảng cách mép dưới `maxGapFromBottomEdge` mặc định là `0f` (bắt buộc sát đáy), nên hãy cung cấp giá trị nếu layout của bạn có khoảng hở. Chú ý: cạnh thanh điều hướng 3 nút khi xoay ngang được mô phỏng theo LTR/RTL, không theo rotation 90/270.

## Ví dụ sử dụng
```kotlin
@RunWith(RobolectricTestRunner::class)
class MyScreenTest {
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun testOverlap() {
        val configs = OverlapInvariants.defaultConfigList
        
        OverlapInvariants.forEachConfig(configs) { config, ui ->
            OverlapInvariants.setContentUnder(ui, config) {
                MyScreen()
            }
            
            OverlapInvariants.verify(
                ui = ui,
                config = config,
                tags = listOf("topBar", "fab", "bottomSheet"),
                interactiveTags = listOf("fab"),
                bottomAnchoredTags = listOf("bottomSheet"),
                maxGapFromBottomEdge = 16f
            )
        }
    }
}
```
