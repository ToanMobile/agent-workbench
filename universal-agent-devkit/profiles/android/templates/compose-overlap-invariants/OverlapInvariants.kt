package your.app.testing

import android.app.Activity
import android.content.res.Configuration
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import org.robolectric.RuntimeEnvironment
import java.io.File

data class WindowConfig(
    val id: String,
    val isLandscape: Boolean,
    val isGestureNav: Boolean,
    val statusInset: Int,
    val navInset: Int,
    val cutoutInset: Int,
    val fontScale: Float = 1.0f,
    val isRtl: Boolean = false
)

object OverlapInvariants {

    val defaultConfigList = listOf(
        WindowConfig("portrait_gesture", false, true, 24, 16, 0),
        WindowConfig("portrait_3button", false, false, 24, 48, 0),
        WindowConfig("landscape_gesture", true, true, 24, 16, 0),
        WindowConfig("landscape_3button", true, false, 24, 48, 0),
        WindowConfig("portrait_cutout", false, true, 24, 16, 32),
        WindowConfig("portrait_font200", false, true, 24, 16, 0, 2.0f),
        WindowConfig("portrait_rtl", false, true, 24, 16, 0, 1.0f, true)
    )

    fun loadConfigFromCsv(file: File): List<WindowConfig> {
        if (!file.exists()) {
            val cwd = System.getProperty("user.dir")
            throw IllegalArgumentException("CSV file not found: ${file.absolutePath} (working dir: $cwd)")
        }
        return file.readLines().drop(1).map { line ->
            val parts = line.split(",")
            WindowConfig(
                id = parts[0].trim(),
                isLandscape = parts[1].trim().toBoolean(),
                isGestureNav = parts[2].trim().toBoolean(),
                statusInset = parts[3].trim().toInt(),
                navInset = parts[4].trim().toInt(),
                cutoutInset = parts[5].trim().toInt(),
                fontScale = parts.getOrNull(6)?.trim()?.toFloat() ?: 1.0f,
                isRtl = parts.getOrNull(7)?.trim()?.toBoolean() ?: false
            )
        }
    }

    @OptIn(ExperimentalTestApi::class)
    fun forEachConfig(configs: List<WindowConfig>, block: (WindowConfig, ComposeUiTest) -> Unit) {
        for (config in configs) {
            runComposeUiTest {
                block(config, this)
            }
        }
    }

    @OptIn(ExperimentalTestApi::class)
    fun setContentUnder(ui: ComposeUiTest, config: WindowConfig, content: @Composable () -> Unit) {
        val qualifier = if (config.isLandscape) "+land" else "+port"
        RuntimeEnvironment.setQualifiers(qualifier)

        var view: View? = null
        ui.setContent {
            view = LocalView.current
            val configuration = Configuration(LocalConfiguration.current).apply {
                orientation = if (config.isLandscape) Configuration.ORIENTATION_LANDSCAPE else Configuration.ORIENTATION_PORTRAIT
                fontScale = config.fontScale
            }
            
            val density = Density(density = LocalDensity.current.density, fontScale = config.fontScale)
            val layoutDirection = if (config.isRtl) LayoutDirection.Rtl else LayoutDirection.Ltr
            
            CompositionLocalProvider(
                LocalConfiguration provides configuration,
                LocalDensity provides density,
                LocalLayoutDirection provides layoutDirection
            ) {
                content()
            }
        }
        
        ui.runOnUiThread {
            val v = view ?: return@runOnUiThread
            val activity = v.context as? Activity
            if (activity != null) {
                WindowCompat.setDecorFitsSystemWindows(activity.window, false)
            }
            
            val navLeft = if (config.isLandscape && !config.isGestureNav && config.isRtl) config.navInset else 0
            val navRight = if (config.isLandscape && !config.isGestureNav && !config.isRtl) config.navInset else 0
            val navBottom = if (!config.isLandscape || config.isGestureNav) config.navInset else 0
            
            val insetsBuilder = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(navLeft, 0, navRight, navBottom))
                .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, config.statusInset, 0, 0))
            
            if (config.cutoutInset > 0) {
                insetsBuilder.setInsets(WindowInsetsCompat.Type.displayCutout(), Insets.of(0, config.cutoutInset, 0, 0))
            }
            
            val insets = insetsBuilder.build()
            
            ViewCompat.setOnApplyWindowInsetsListener(v.rootView) { _, _ -> insets }
            v.rootView.requestApplyInsets()
            ViewCompat.dispatchApplyWindowInsets(v, insets)
        }
        ui.waitForIdle()
    }

    @OptIn(ExperimentalTestApi::class)
    fun verify(
        ui: ComposeUiTest,
        config: WindowConfig,
        tags: List<String>,
        interactiveTags: List<String> = emptyList(),
        bottomAnchoredTags: List<String> = emptyList(),
        allowedOverlaps: Set<Pair<String, String>> = emptySet(),
        maxGapFromBottomEdge: Float = 0f
    ) {
        val boundsMap = mutableMapOf<String, DpRect>()
        tags.forEach { tag ->
            val node = ui.onNodeWithTag(tag)
            node.assertExists("Node with tag $tag not found in config ${config.id}")
            boundsMap[tag] = node.getUnclippedBoundsInRoot()
        }
        
        val rootBounds = ui.onRoot().getUnclippedBoundsInRoot()
        val screenWidthDp = rootBounds.width.value
        val screenHeightDp = rootBounds.height.value
        val density = ui.density.density

        if (config.isLandscape && screenWidthDp <= screenHeightDp) {
            throw AssertionError("Config ${config.id} geometry is incorrect: expected landscape but got width=${screenWidthDp}dp, height=${screenHeightDp}dp")
        }
        if (!config.isLandscape && screenWidthDp >= screenHeightDp) {
            throw AssertionError("Config ${config.id} geometry is incorrect: expected portrait but got width=${screenWidthDp}dp, height=${screenHeightDp}dp")
        }

        // 1. No two overlays intersect except explicitly declared
        // so cặp trên vài tag khai báo (N <= ~10), không phải dữ liệu động
        for (i in tags.indices) {
            for (j in i + 1 until tags.size) {
                val tag1 = tags[i]
                val tag2 = tags[j]
                if (allowedOverlaps.contains(tag1 to tag2) || allowedOverlaps.contains(tag2 to tag1)) continue
                
                val r1 = boundsMap[tag1]!!
                val r2 = boundsMap[tag2]!!
                if (r1.left < r2.right && r1.right > r2.left && r1.top < r2.bottom && r1.bottom > r2.top) {
                    throw AssertionError("Overlap found in config ${config.id} between $tag1 ($r1) and $tag2 ($r2)")
                }
            }
        }

        // 2. All interactive nodes >= 48dp on both axes
        interactiveTags.forEach { tag ->
            val b = boundsMap[tag]!!
            if (b.width < 48.dp || b.height < 48.dp) {
                throw AssertionError("Interactive node $tag too small in config ${config.id}: ${b.width} x ${b.height}")
            }
        }

        // 3. No overlay intersects the system bar rects
        val statusDp = config.statusInset / density
        val navDp = config.navInset / density
        val cutoutDp = config.cutoutInset / density
        
        val navLeftDp = if (config.isLandscape && !config.isGestureNav && config.isRtl) navDp else 0f
        val navRightDp = if (config.isLandscape && !config.isGestureNav && !config.isRtl) navDp else 0f
        val navBottomDp = if (!config.isLandscape || config.isGestureNav) navDp else 0f

        val topInset = maxOf(statusDp, cutoutDp)

        tags.forEach { tag ->
            val b = boundsMap[tag]!!
            // Top inset intersection
            if (b.top.value < topInset && b.bottom.value > 0f) {
                throw AssertionError("Node $tag intersects top system bars in config ${config.id}: $b")
            }
            // Bottom nav bar intersection
            if (navBottomDp > 0 && b.bottom.value > screenHeightDp - navBottomDp && b.top.value < screenHeightDp) {
                throw AssertionError("Node $tag intersects bottom nav bar in config ${config.id}: $b")
            }
            // Side nav bar intersection (Left)
            if (navLeftDp > 0 && b.left.value < navLeftDp && b.right.value > 0f) {
                throw AssertionError("Node $tag intersects left nav bar in config ${config.id}: $b")
            }
            // Side nav bar intersection (Right)
            if (navRightDp > 0 && b.right.value > screenWidthDp - navRightDp && b.left.value < screenWidthDp) {
                throw AssertionError("Node $tag intersects right nav bar in config ${config.id}: $b")
            }
        }

        // 4. Bottom-anchored overlays lie within maxGapFromBottomEdge of the visible bottom edge
        val bottomEdge = screenHeightDp - navBottomDp
        bottomAnchoredTags.forEach { tag ->
            val b = boundsMap[tag]!!
            val gap = bottomEdge - b.bottom.value
            if (gap < 0f || gap > maxGapFromBottomEdge) {
                throw AssertionError("Bottom anchored node $tag is misplaced in config ${config.id}: gap is $gap, allowed 0..$maxGapFromBottomEdge")
            }
        }
    }
}
