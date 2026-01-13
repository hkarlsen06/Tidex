package no.tidex.app.plugins

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import no.tidex.app.MainActivity

/**
 * Capacitor plugin for controlling the native Android BottomNavigationView.
 *
 * Mirrors iOS NativeTabBarPlugin functionality:
 * - setSelectedTab: Highlight a specific tab
 * - clearSelection: Deselect all tabs
 * - setTabBadge: Show badge on tab
 * - setTabTitles: Update tab labels
 * - hide/show: Toggle visibility
 * - isAvailable: Check if native tab bar is present
 * - getTabBarHeight: Get height in pixels
 *
 * Events:
 * - tabSelected: Fired when a different tab is tapped
 * - tabReselected: Fired when the same tab is tapped (for scroll-to-top)
 */
@CapacitorPlugin(name = "NativeTabBar")
class NativeTabBarPlugin : Plugin() {

    var mainActivity: MainActivity? = null

    @PluginMethod
    fun setSelectedTab(call: PluginCall) {
        val index = call.getInt("index") ?: run {
            call.reject("Missing index")
            return
        }

        activity?.runOnUiThread {
            MainActivity.instance?.setSelectedTabIndex(index)
            call.resolve()
        }
    }

    @PluginMethod
    fun clearSelection(call: PluginCall) {
        activity?.runOnUiThread {
            MainActivity.instance?.clearTabSelection()
            call.resolve()
        }
    }

    @PluginMethod
    fun setTabBadge(call: PluginCall) {
        val index = call.getInt("index") ?: run {
            call.reject("Missing index")
            return
        }
        val value = call.getString("value")

        activity?.runOnUiThread {
            MainActivity.instance?.setTabBadge(index, value)
            call.resolve()
        }
    }

    @PluginMethod
    fun setTabTitles(call: PluginCall) {
        val titlesArray = call.getArray("titles") ?: run {
            call.reject("Missing titles array")
            return
        }

        val titles = mutableListOf<String>()
        for (i in 0 until titlesArray.length()) {
            titles.add(titlesArray.getString(i))
        }

        activity?.runOnUiThread {
            MainActivity.instance?.setTabTitles(titles)
            call.resolve()
        }
    }

    @PluginMethod
    fun hide(call: PluginCall) {
        activity?.runOnUiThread {
            MainActivity.instance?.hideTabBar()
            call.resolve()
        }
    }

    @PluginMethod
    fun show(call: PluginCall) {
        activity?.runOnUiThread {
            MainActivity.instance?.showTabBar()
            call.resolve()
        }
    }

    @PluginMethod
    fun isAvailable(call: PluginCall) {
        val result = JSObject()
        result.put("available", MainActivity.instance != null)
        call.resolve(result)
    }

    @PluginMethod
    fun getTabBarHeight(call: PluginCall) {
        activity?.runOnUiThread {
            val height = MainActivity.instance?.getTabBarHeight() ?: 0
            val result = JSObject()
            result.put("height", height)
            call.resolve(result)
        }
    }

    // Called from MainActivity when tab is tapped
    fun handleTabSelection(index: Int, route: String) {
        val data = JSObject()
        data.put("index", index)
        data.put("route", route)
        notifyListeners("tabSelected", data)
    }

    // Called from MainActivity when same tab is re-tapped
    fun handleTabReselection(index: Int, route: String) {
        val data = JSObject()
        data.put("index", index)
        data.put("route", route)
        notifyListeners("tabReselected", data)
    }
}
