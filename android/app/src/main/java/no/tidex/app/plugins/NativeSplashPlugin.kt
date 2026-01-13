package no.tidex.app.plugins

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import no.tidex.app.MainActivity

/**
 * Capacitor plugin for controlling the native Android splash screen.
 *
 * Mirrors iOS NativeSplashPlugin functionality:
 * - hide: Dismiss the splash screen with optional fade animation
 * - show: Re-show the splash screen (rarely needed)
 * - isVisible: Check if splash screen is currently visible
 *
 * On Android 12+, this works with the SplashScreen API.
 * The splash screen is held visible until the web layer signals ready by calling hide().
 */
@CapacitorPlugin(name = "NativeSplash")
class NativeSplashPlugin : Plugin() {

    @PluginMethod
    fun hide(call: PluginCall) {
        val fadeOutDuration = call.getDouble("fadeOutDuration") ?: 200.0

        activity?.runOnUiThread {
            MainActivity.instance?.hideSplash(fadeOutDuration.toLong()) {
                call.resolve()
            }
        }
    }

    @PluginMethod
    fun show(call: PluginCall) {
        activity?.runOnUiThread {
            MainActivity.instance?.showSplash()
            call.resolve()
        }
    }

    @PluginMethod
    fun isVisible(call: PluginCall) {
        val visible = MainActivity.instance?.isSplashVisible ?: false
        val result = JSObject()
        result.put("visible", visible)
        call.resolve(result)
    }
}
