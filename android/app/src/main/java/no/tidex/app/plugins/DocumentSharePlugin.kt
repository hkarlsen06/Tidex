package no.tidex.app.plugins

import android.content.Intent
import android.util.Base64
import androidx.core.content.FileProvider
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import java.io.File
import java.util.UUID

/**
 * Capacitor plugin for sharing documents (PDF, CSV) via the native Android Share Sheet.
 *
 * Mirrors iOS DocumentSharePlugin functionality:
 * - Receives base64-encoded file data
 * - Writes to a temp file with the original filename preserved
 * - Opens the Android ShareSheet via Intent.ACTION_SEND
 */
@CapacitorPlugin(name = "DocumentShare")
class DocumentSharePlugin : Plugin() {

    private var currentTempDir: File? = null

    @PluginMethod
    fun shareDocument(call: PluginCall) {
        val base64Data = call.getString("data") ?: run {
            call.reject("Missing 'data' parameter")
            return
        }

        val filename = call.getString("filename") ?: run {
            call.reject("Missing 'filename' parameter")
            return
        }

        val mimeType = call.getString("mimeType") ?: "application/octet-stream"

        // Decode base64 data
        val bytes: ByteArray
        try {
            bytes = Base64.decode(base64Data, Base64.DEFAULT)
        } catch (e: Exception) {
            call.reject("Invalid base64 data")
            return
        }

        // Write to a unique subdirectory to avoid conflicts while keeping original filename
        val uniqueDir = File(context.cacheDir, UUID.randomUUID().toString())
        uniqueDir.mkdirs()
        currentTempDir = uniqueDir

        val tempFile = File(uniqueDir, filename)
        try {
            tempFile.writeBytes(bytes)
        } catch (e: Exception) {
            call.reject("Failed to write file: ${e.message}")
            cleanup()
            return
        }

        // Get content URI via FileProvider
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            tempFile
        )

        // Create share intent
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        // Start chooser activity
        activity?.startActivity(Intent.createChooser(shareIntent, null))

        // Note: We can't easily detect when the share sheet is closed on Android
        // So we resolve immediately and clean up the temp file after a delay
        val result = JSObject()
        result.put("completed", true)
        result.put("activityType", "")
        call.resolve(result)

        // Clean up temp file after a delay (give time for share to complete)
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            cleanup()
        }, 60_000) // 1 minute
    }

    private fun cleanup() {
        currentTempDir?.let { dir ->
            try {
                dir.deleteRecursively()
            } catch (_: Exception) {
                // Ignore cleanup errors
            }
            currentTempDir = null
        }
    }
}
