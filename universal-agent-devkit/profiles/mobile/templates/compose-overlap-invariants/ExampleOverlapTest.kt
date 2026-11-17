package your.app.testing

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Ví dụ test tham khảo chạy trên Robolectric >= 4.11 và compose-ui-test (BOM 2024.02.00).
 * Yêu cầu: `androidx.compose.material3:material3`, `androidx.compose.ui:ui-test-junit4`,
 * `androidx.compose.ui:ui-test-manifest` (debugImplementation), và Robolectric.
 * Thay `your.app.testing` thành package của dự án thực tế.
 */
@RunWith(RobolectricTestRunner::class)
class ExampleOverlapTest {

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun testOverlap_failsOnDoublePadding() {
        val configs = OverlapInvariants.defaultConfigList
        
        OverlapInvariants.forEachConfig(configs) { config, ui ->
            OverlapInvariants.setContentUnder(ui, config) {
                // Lỗi: Scaffold đã pad navigation bar ở dưới rồi, lại pad thêm lần nữa
                Scaffold { innerPadding ->
                    Box(modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                        .windowInsetsPadding(WindowInsets.navigationBars)
                        .testTag("content")
                    ) {
                        Text("Hello")
                    }
                }
            }
            
            // Nếu có navBottom > 0 (navInset > 0 và nằm ở đáy), khoảng hở dưới đáy sẽ bị nhân đôi gây ra lỗi
            val navBottom = if (!config.isLandscape || config.isGestureNav) config.navInset else 0
            if (navBottom > 0) {
                var caught = false
                try {
                    OverlapInvariants.verify(
                        ui = ui,
                        config = config,
                        tags = listOf("content"),
                        bottomAnchoredTags = listOf("content"),
                        maxGapFromBottomEdge = 0f
                    )
                } catch (e: AssertionError) {
                    caught = true
                    assertTrue("Lỗi phải báo về gap", e.message?.contains("gap") == true)
                }
                assertTrue("Phải bắt được AssertionError cho config ${config.id}", caught)
            } else {
                OverlapInvariants.verify(
                    ui = ui,
                    config = config,
                    tags = listOf("content"),
                    bottomAnchoredTags = listOf("content"),
                    maxGapFromBottomEdge = 0f
                )
            }
        }
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun testOverlap_passesOnCorrectPadding() {
        val configs = OverlapInvariants.defaultConfigList
        
        OverlapInvariants.forEachConfig(configs) { config, ui ->
            OverlapInvariants.setContentUnder(ui, config) {
                // Đúng: Scaffold quản lý innerPadding, box content bám sát mép vùng được phép
                Scaffold { innerPadding ->
                    Box(modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                        .testTag("content")
                    ) {
                        Text("Hello")
                    }
                }
            }
            
            OverlapInvariants.verify(
                ui = ui,
                config = config,
                tags = listOf("content"),
                bottomAnchoredTags = listOf("content"),
                maxGapFromBottomEdge = 0f
            )
        }
    }
}
