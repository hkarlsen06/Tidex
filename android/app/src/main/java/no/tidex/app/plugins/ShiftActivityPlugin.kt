package no.tidex.app.plugins

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import no.tidex.app.MainActivity
import no.tidex.app.R
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.UUID

/**
 * Capacitor plugin for managing shift activity notifications.
 *
 * Android equivalent of iOS Live Activities:
 * - Uses ongoing notifications to show real-time shift progress
 * - Updates earnings and progress bar every 60 seconds
 * - Displays on lock screen and notification shade
 *
 * Also handles saving shifts to SharedPreferences for potential widget use.
 */
@CapacitorPlugin(name = "ShiftActivity")
class ShiftActivityPlugin : Plugin() {

    companion object {
        private const val CHANNEL_ID = "shift_activity"
        private const val NOTIFICATION_ID = 1001
        private const val PREFS_NAME = "tidex_shifts"
        private const val SHIFTS_KEY = "upcoming_shifts"
        private const val UPDATE_INTERVAL_MS = 60_000L // 60 seconds
    }

    // Current activity state
    private var currentActivityId: String? = null
    private var updateHandler: Handler? = null
    private var updateRunnable: Runnable? = null

    // Shift data for updates
    private var shiftStartTime: Long = 0
    private var shiftEndTime: Long = 0
    private var totalRate: Double = 0.0
    private var currencySymbol: String = "kr"
    private var locale: String = "no"
    private var shiftTimeDisplay: String = ""

    override fun load() {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Active Shift",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress during your work shift"
                setShowBadge(false)
            }

            val notificationManager = context.getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }

    @PluginMethod
    fun isAvailable(call: PluginCall) {
        val result = JSObject()
        result.put("available", true) // Always available on Android
        result.put("frequentUpdatesEnabled", true)
        call.resolve(result)
    }

    @PluginMethod
    fun startActivity(call: PluginCall) {
        // Extract shift data
        val shiftId = call.getString("shiftId") ?: run {
            call.reject("Missing shiftId")
            return
        }
        val shiftDate = call.getString("shiftDate") ?: run {
            call.reject("Missing shiftDate")
            return
        }
        val startTime = call.getString("startTime") ?: run {
            call.reject("Missing startTime")
            return
        }
        val endTime = call.getString("endTime") ?: run {
            call.reject("Missing endTime")
            return
        }
        val hourlyWage = call.getDouble("hourlyWage") ?: 0.0
        val supplementRate = call.getDouble("supplementRatePerHour") ?: 0.0

        locale = call.getString("locale") ?: "no"
        currencySymbol = call.getString("currencySymbol") ?: "kr"
        val initialProgress = call.getDouble("initialProgress") ?: 0.0
        val initialEarnings = call.getDouble("initialEarnings") ?: 0.0

        // End any existing activity
        endAllActivitiesInternal()

        // Parse times
        shiftStartTime = parseShiftTime(shiftDate, startTime)
        shiftEndTime = parseShiftTime(shiftDate, endTime, endTime < startTime)
        totalRate = hourlyWage + supplementRate
        shiftTimeDisplay = "$startTime - $endTime"

        // Generate activity ID
        currentActivityId = UUID.randomUUID().toString()

        // Check notification permission (Android 13+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                val result = JSObject()
                result.put("activityId", currentActivityId)
                result.put("success", false)
                result.put("error", "Notification permission not granted")
                call.resolve(result)
                return
            }
        }

        // Show initial notification
        showNotification(initialEarnings, initialProgress.toInt())

        // Start update timer
        startUpdateTimer()

        val result = JSObject()
        result.put("activityId", currentActivityId)
        result.put("success", true)
        call.resolve(result)
    }

    @PluginMethod
    fun updateActivity(call: PluginCall) {
        if (currentActivityId == null) {
            call.reject("No active activity to update")
            return
        }

        val earnings = call.getDouble("earnings") ?: 0.0
        val progress = call.getInt("progress") ?: 0

        showNotification(earnings, progress)

        val result = JSObject()
        result.put("success", true)
        call.resolve(result)
    }

    @PluginMethod
    fun endActivity(call: PluginCall) {
        endAllActivitiesInternal()

        val result = JSObject()
        result.put("success", true)
        call.resolve(result)
    }

    @PluginMethod
    fun endAllActivities(call: PluginCall) {
        endAllActivitiesInternal()

        val result = JSObject()
        result.put("success", true)
        call.resolve(result)
    }

    @PluginMethod
    fun getActiveActivity(call: PluginCall) {
        val result = JSObject()
        if (currentActivityId != null) {
            result.put("hasActivity", true)
            result.put("activityId", currentActivityId)
        } else {
            result.put("hasActivity", false)
        }
        call.resolve(result)
    }

    @PluginMethod
    fun saveShiftsToSharedStorage(call: PluginCall) {
        val shiftsJson = call.getString("shifts") ?: run {
            call.reject("Missing shifts parameter")
            return
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(SHIFTS_KEY, shiftsJson).apply()

        val result = JSObject()
        result.put("success", true)
        call.resolve(result)
    }

    // MARK: - Private Helpers

    private fun showNotification(earnings: Double, progress: Int) {
        val notificationManager = NotificationManagerCompat.from(context)

        // Create intent to open app
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Format earnings
        val formattedEarnings = formatCurrency(earnings)

        // Calculate remaining time
        val now = System.currentTimeMillis()
        val remaining = (shiftEndTime - now).coerceAtLeast(0)
        val remainingMinutes = (remaining / 60_000).toInt()
        val remainingText = if (locale == "no") {
            "$remainingMinutes min igjen"
        } else {
            "$remainingMinutes min left"
        }

        // Build notification
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_work)
            .setContentTitle(shiftTimeDisplay)
            .setContentText("$formattedEarnings • $remainingText")
            .setProgress(100, progress.coerceIn(0, 100), false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU
        ) {
            notificationManager.notify(NOTIFICATION_ID, notification)
        }
    }

    private fun startUpdateTimer() {
        updateHandler = Handler(Looper.getMainLooper())
        updateRunnable = object : Runnable {
            override fun run() {
                val now = System.currentTimeMillis()

                // Check if shift has ended
                if (now >= shiftEndTime) {
                    endAllActivitiesInternal()
                    return
                }

                // Calculate current state
                val elapsed = (now - shiftStartTime).coerceAtLeast(0)
                val total = (shiftEndTime - shiftStartTime).coerceAtLeast(1)
                val progress = ((elapsed.toDouble() / total) * 100).toInt()
                val hoursWorked = elapsed.toDouble() / 3_600_000
                val earnings = hoursWorked * totalRate

                // Update notification
                showNotification(earnings, progress)

                // Schedule next update
                updateHandler?.postDelayed(this, UPDATE_INTERVAL_MS)
            }
        }

        // Fire immediately
        updateRunnable?.let { updateHandler?.post(it) }
    }

    private fun endAllActivitiesInternal() {
        // Stop update timer
        updateRunnable?.let { updateHandler?.removeCallbacks(it) }
        updateHandler = null
        updateRunnable = null

        // Dismiss notification
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)

        currentActivityId = null
    }

    private fun parseShiftTime(date: String, time: String, crossMidnight: Boolean = false): Long {
        val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
        val dateTime = formatter.parse("$date $time")?.time ?: System.currentTimeMillis()

        return if (crossMidnight) {
            dateTime + 24 * 60 * 60 * 1000 // Add one day
        } else {
            dateTime
        }
    }

    private fun formatCurrency(amount: Double): String {
        val formatter = NumberFormat.getInstance(if (locale == "no") Locale("nb", "NO") else Locale.US)
        formatter.maximumFractionDigits = 0
        val formatted = formatter.format(amount)
        return "$formatted $currencySymbol"
    }
}
