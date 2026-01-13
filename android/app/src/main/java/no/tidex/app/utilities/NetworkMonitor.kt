package no.tidex.app.utilities

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper

/**
 * Centralized network connectivity monitoring using ConnectivityManager.NetworkCallback.
 *
 * Mirrors iOS NetworkMonitor functionality:
 * - Provides reliable network state detection
 * - Debounces rapid state changes
 * - Notifies listener on connectivity changes
 */
class NetworkMonitor(private val context: Context) {

    private val connectivityManager = context.getSystemService(ConnectivityManager::class.java)
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val handler = Handler(Looper.getMainLooper())
    private var pendingUpdate: Runnable? = null

    // Debounce delay in milliseconds
    private val debounceDelay = 500L

    // Current connectivity state
    var isConnected: Boolean = true
        private set

    // Whether monitoring has been started
    private var isMonitoring = false

    // Listener for connectivity changes
    var listener: ((Boolean) -> Unit)? = null

    /**
     * Start monitoring network connectivity.
     * Safe to call multiple times - will only start once.
     */
    fun startMonitoring() {
        if (isMonitoring) return

        // Check initial state
        isConnected = checkInitialConnectivity()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                handleConnectivityChange(true)
            }

            override fun onLost(network: Network) {
                handleConnectivityChange(false)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities
            ) {
                val hasInternet = networkCapabilities.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_INTERNET
                )
                handleConnectivityChange(hasInternet)
            }
        }

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        connectivityManager?.registerNetworkCallback(request, networkCallback!!)
        isMonitoring = true

        android.util.Log.d("NetworkMonitor", "Started monitoring")
    }

    /**
     * Stop monitoring network connectivity.
     */
    fun stopMonitoring() {
        if (!isMonitoring) return

        networkCallback?.let {
            connectivityManager?.unregisterNetworkCallback(it)
        }
        networkCallback = null

        pendingUpdate?.let { handler.removeCallbacks(it) }
        pendingUpdate = null

        isMonitoring = false

        android.util.Log.d("NetworkMonitor", "Stopped monitoring")
    }

    /**
     * Check initial network connectivity state.
     */
    private fun checkInitialConnectivity(): Boolean {
        val activeNetwork = connectivityManager?.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    /**
     * Handle network connectivity changes with debouncing.
     */
    private fun handleConnectivityChange(newConnected: Boolean) {
        // Cancel any pending update
        pendingUpdate?.let { handler.removeCallbacks(it) }

        // Create new debounced update
        val runnable = Runnable {
            // Only notify if state actually changed
            if (isConnected != newConnected) {
                isConnected = newConnected

                android.util.Log.d(
                    "NetworkMonitor",
                    "Connection state changed: ${if (newConnected) "connected" else "disconnected"}"
                )

                // Notify listener on main thread
                handler.post {
                    listener?.invoke(newConnected)
                }
            }
        }

        pendingUpdate = runnable

        // Execute after debounce delay
        handler.postDelayed(runnable, debounceDelay)
    }
}
