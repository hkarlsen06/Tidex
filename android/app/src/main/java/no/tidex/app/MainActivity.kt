package no.tidex.app

import android.annotation.SuppressLint
import android.content.Context
import android.os.Bundle
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.ui.platform.ComposeView
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.getcapacitor.BridgeActivity
import com.google.android.material.bottomnavigation.BottomNavigationView
import no.tidex.app.features.OfflineScreen
import no.tidex.app.plugins.DocumentSharePlugin
import no.tidex.app.plugins.NativeSplashPlugin
import no.tidex.app.plugins.NativeTabBarPlugin
import no.tidex.app.plugins.ShiftActivityPlugin
import no.tidex.app.utilities.NetworkMonitor

/**
 * Main activity that hosts the WebView and native components.
 *
 * Architecture (matching iOS TidexContainerViewController):
 * - WebView is edge-to-edge (extends under status bar and nav bar)
 * - BottomNavigationView overlays at the bottom
 * - Tab bar height injected into WebView as CSS custom property
 * - Splash screen shown until JS signals ready
 * - Offline screen shown when network unavailable
 */
class MainActivity : BridgeActivity() {

    companion object {
        @SuppressLint("StaticFieldLeak")
        var instance: MainActivity? = null
            private set
    }

    // Native UI components
    private lateinit var bottomNavigation: BottomNavigationView
    private var offlineScreenView: ComposeView? = null
    private var splashView: View? = null

    // State
    var isSplashVisible = true
        private set
    var isShowingOfflineScreen = false
        private set
    private var selectedTabIndex = 0

    // Network monitoring
    private lateinit var networkMonitor: NetworkMonitor

    // Plugin references
    var nativeTabBarPlugin: NativeTabBarPlugin? = null
        private set

    // Tab definitions (must match iOS and TypeScript)
    data class TabItem(val iconRes: Int, val route: String, val titleEn: String, val titleNb: String)

    private val tabDefinitions = listOf(
        TabItem(R.drawable.ic_home, "/dashboard", "Home", "Hjem"),
        TabItem(R.drawable.ic_event, "/shifts", "Shifts", "Vakter"),
        TabItem(R.drawable.ic_add_circle, "/shifts/add", "", ""),  // No title for center tab
        TabItem(R.drawable.ic_bar_chart, "/stats", "Stats", "Statistikk"),
        TabItem(R.drawable.ic_group, "/sharing", "Friends", "Venner")
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        // Register custom plugins BEFORE calling super.onCreate()
        // This is required for Capacitor to properly instantiate and load plugins
        registerPlugin(NativeTabBarPlugin::class.java)
        registerPlugin(NativeSplashPlugin::class.java)
        registerPlugin(ShiftActivityPlugin::class.java)
        registerPlugin(DocumentSharePlugin::class.java)

        // Install splash screen (Android 12+)
        val splashScreen = installSplashScreen()
        splashScreen.setKeepOnScreenCondition { isSplashVisible }

        super.onCreate(savedInstanceState)
        instance = this

        // Enable edge-to-edge display
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // Setup network monitoring
        networkMonitor = NetworkMonitor(this)
        networkMonitor.listener = { isConnected ->
            runOnUiThread {
                if (isConnected && isShowingOfflineScreen) {
                    hideOfflineScreen()
                    reloadWebView()
                }
            }
        }
        networkMonitor.startMonitoring()

        // Setup UI after Capacitor bridge is ready
        bridge?.webView?.post {
            setupBottomNavigation()
            setupSplashOverlay()
            setupSwipeBackGesture()
            setupPlugins()

            // Auto-hide splash after 2 seconds as fallback
            // (in case JS plugin call fails)
            android.os.Handler(mainLooper).postDelayed({
                if (isSplashVisible) {
                    hideSplash()
                }
            }, 2000)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        networkMonitor.stopMonitoring()
        instance = null
    }

    // MARK: - Plugin Setup

    private fun setupPlugins() {
        // Get the NativeTabBarPlugin instance that Capacitor created
        // (plugins are registered in onCreate before super.onCreate)
        nativeTabBarPlugin = bridge?.getPlugin("NativeTabBar")?.instance as? NativeTabBarPlugin
        nativeTabBarPlugin?.mainActivity = this

        // Inject initial tab bar height
        injectTabBarHeightToCSS()
    }

    // MARK: - Bottom Navigation Setup

    private fun setupBottomNavigation() {
        val rootView = findViewById<ViewGroup>(android.R.id.content)
        val existingLayout = rootView.getChildAt(0) as? ViewGroup ?: return

        // Create bottom navigation
        bottomNavigation = BottomNavigationView(this).apply {
            id = View.generateViewId()
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = android.view.Gravity.BOTTOM
            }

            // Inflate menu
            inflateMenu(R.menu.bottom_navigation)

            // Set item selected listener
            setOnItemSelectedListener { item ->
                val index = when (item.itemId) {
                    R.id.nav_home -> 0
                    R.id.nav_shifts -> 1
                    R.id.nav_add -> 2
                    R.id.nav_stats -> 3
                    R.id.nav_friends -> 4
                    else -> -1
                }

                if (index >= 0 && index < tabDefinitions.count()) {
                    val route = tabDefinitions[index].route
                    if (index == selectedTabIndex) {
                        // Re-tapping same tab
                        nativeTabBarPlugin?.handleTabReselection(index, route)
                    } else {
                        selectedTabIndex = index
                        nativeTabBarPlugin?.handleTabSelection(index, route)
                    }
                }
                true
            }

            // Start hidden - will be shown by web layer when entering (app) routes
            visibility = View.GONE
        }

        // Add to layout
        (existingLayout as? FrameLayout)?.addView(bottomNavigation)
            ?: run {
                // Wrap in FrameLayout if needed
                val wrapper = FrameLayout(this).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                }
                rootView.removeView(existingLayout)
                wrapper.addView(existingLayout)
                wrapper.addView(bottomNavigation)
                rootView.addView(wrapper)
            }

        // Handle window insets for proper padding
        ViewCompat.setOnApplyWindowInsetsListener(bottomNavigation) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(0, 0, 0, systemBars.bottom)
            insets
        }
    }

    // MARK: - Splash Screen

    private fun setupSplashOverlay() {
        // For pre-Android 12 or additional splash control, we could add a custom overlay here
        // The Android 12+ SplashScreen API handles the actual splash screen
        // This method is kept for parity with iOS where we manually manage splash state
    }

    fun hideSplash(fadeOutDuration: Long = 200, completion: (() -> Unit)? = null) {
        if (!isSplashVisible) {
            completion?.invoke()
            return
        }

        isSplashVisible = false

        // The Android SplashScreen API will automatically dismiss
        // Any custom overlay would be animated here
        splashView?.animate()
            ?.alpha(0f)
            ?.setDuration(fadeOutDuration)
            ?.withEndAction {
                splashView?.visibility = View.GONE
                completion?.invoke()
            }
            ?.start()
            ?: completion?.invoke()
    }

    fun showSplash() {
        isSplashVisible = true
        splashView?.visibility = View.VISIBLE
        splashView?.alpha = 1f
    }

    // MARK: - Offline Screen

    fun showOfflineScreen() {
        if (isShowingOfflineScreen) return

        val rootView = findViewById<ViewGroup>(android.R.id.content)
        val wrapper = rootView.getChildAt(0) as? ViewGroup ?: return

        // Determine locale
        val locale = if (resources.configuration.locales[0].language == "nb" ||
            resources.configuration.locales[0].language == "no") "no" else "en"

        offlineScreenView = ComposeView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setContent {
                OfflineScreen(
                    locale = locale,
                    onRetry = {
                        handleOfflineRetry()
                    }
                )
            }
            alpha = 0f
        }

        wrapper.addView(offlineScreenView)
        offlineScreenView?.animate()?.alpha(1f)?.setDuration(200)?.start()

        isShowingOfflineScreen = true
    }

    fun hideOfflineScreen() {
        if (!isShowingOfflineScreen) return

        offlineScreenView?.animate()
            ?.alpha(0f)
            ?.setDuration(200)
            ?.withEndAction {
                (offlineScreenView?.parent as? ViewGroup)?.removeView(offlineScreenView)
                offlineScreenView = null
                isShowingOfflineScreen = false
            }
            ?.start()
    }

    private fun handleOfflineRetry() {
        hideOfflineScreen()
        showSplash()
        reloadWebView()
    }

    private fun reloadWebView() {
        bridge?.webView?.let { webView ->
            // Get server URL from Capacitor config or use default
            val serverUrl = bridge?.config?.serverUrl ?: "https://app.tidex.no"
            webView.loadUrl(serverUrl)
        }
    }

    // MARK: - Tab Bar Control (called from plugin)

    fun setSelectedTabIndex(index: Int) {
        if (index < 0 || index >= tabDefinitions.count()) return
        selectedTabIndex = index

        val itemId = when (index) {
            0 -> R.id.nav_home
            1 -> R.id.nav_shifts
            2 -> R.id.nav_add
            3 -> R.id.nav_stats
            4 -> R.id.nav_friends
            else -> return
        }
        bottomNavigation.selectedItemId = itemId
    }

    fun clearTabSelection() {
        selectedTabIndex = -1
        bottomNavigation.menu.setGroupCheckable(0, true, false)
        for (i in 0 until bottomNavigation.menu.size()) {
            bottomNavigation.menu.getItem(i).isChecked = false
        }
        bottomNavigation.menu.setGroupCheckable(0, true, true)
    }

    fun setTabBadge(index: Int, value: String?) {
        val itemId = when (index) {
            0 -> R.id.nav_home
            1 -> R.id.nav_shifts
            2 -> R.id.nav_add
            3 -> R.id.nav_stats
            4 -> R.id.nav_friends
            else -> return
        }

        val badge = bottomNavigation.getOrCreateBadge(itemId)
        if (value.isNullOrEmpty()) {
            bottomNavigation.removeBadge(itemId)
        } else {
            badge.isVisible = true
            badge.text = value
        }
    }

    fun setTabTitles(titles: List<String>) {
        val menu = bottomNavigation.menu
        titles.forEachIndexed { index, title ->
            if (index < menu.size()) {
                menu.getItem(index).title = title
            }
        }
    }

    fun hideTabBar() {
        if (bottomNavigation.visibility == View.GONE) return
        bottomNavigation.visibility = View.GONE
        injectTabBarHiddenState(true)
    }

    fun showTabBar() {
        if (bottomNavigation.visibility == View.VISIBLE) return
        bottomNavigation.visibility = View.VISIBLE
        injectTabBarHiddenState(false)
        injectTabBarHeightToCSS()
    }

    fun getTabBarHeight(): Int {
        return bottomNavigation.height
    }

    // MARK: - CSS Injection

    private fun injectTabBarHeightToCSS() {
        bottomNavigation.post {
            val height = bottomNavigation.height
            if (height > 0) {
                val js = "document.documentElement.style.setProperty('--native-tab-bar-height', '${height}px');"
                bridge?.webView?.evaluateJavascript(js, null)
            }
        }
    }

    private fun injectTabBarHiddenState(hidden: Boolean) {
        val heightValue = if (hidden) "0px" else "${bottomNavigation.height}px"
        val classAction = if (hidden) "add" else "remove"

        val js = """
            document.documentElement.style.setProperty('--native-tab-bar-height', '$heightValue');
            document.documentElement.classList.$classAction('native-tab-bar-hidden');
        """.trimIndent()
        bridge?.webView?.evaluateJavascript(js, null)
    }

    // MARK: - Swipe Back Gesture

    @SuppressLint("ClickableViewAccessibility")
    private fun setupSwipeBackGesture() {
        val gestureDetector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onFling(
                e1: MotionEvent?,
                e2: MotionEvent,
                velocityX: Float,
                velocityY: Float
            ): Boolean {
                val startX = e1?.x ?: return false
                val endX = e2.x
                val diffX = endX - startX

                // Swipe from left edge to right = back
                if (startX < 50 && diffX > 100 && kotlin.math.abs(velocityX) > kotlin.math.abs(velocityY)) {
                    bridge?.webView?.evaluateJavascript("window.history.back();", null)
                    return true
                }
                return false
            }
        })

        bridge?.webView?.setOnTouchListener { _, event ->
            gestureDetector.onTouchEvent(event)
            false // Don't consume the event
        }
    }
}
