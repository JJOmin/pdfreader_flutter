package io.github.jjomin.pdfreader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * DocumentAccess (ADR 1): opens documents through the system picker and keeps their content URI,
 * so that later steps can write notes next to the PDF. A file picker package would copy the file
 * into the cache and lose where it came from. It extends audio_service's activity, which shares
 * the Flutter engine with the playback service, so reading goes on with the screen off.
 */
class MainActivity : AudioServiceActivity() {
    private var pending: MethodChannel.Result? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfreader/documents")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickPdf" -> pickPdf(result)
                    else -> result.notImplemented()
                }
            }
        // Discovery (ADR 2 section 4): Android drops multicast unless the app holds this lock, so
        // it is held only while the Desktops screen listens for announcements.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfreader/discovery")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        if (multicastLock == null) {
                            val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("pdfreader-discovery").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(null)
                    }
                    "release" -> {
                        multicastLock?.release()
                        multicastLock = null
                        result.success(null)
                    }
                    // The name the user gave the phone, shown in "Pair with …?" on the desktop.
                    "deviceName" -> result.success(
                        Settings.Global.getString(contentResolver, "device_name") ?: Build.MODEL
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickPdf(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "The document picker is already open", null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("application/pdf")
        @Suppress("DEPRECATION") // FlutterActivity, which this extends, is not a ComponentActivity, so no ActivityResult API.
        startActivityForResult(intent, PICK_PDF)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_PDF) return
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // A large PDF takes a moment to read; keep it off the UI thread.
        Thread {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw IllegalStateException("The document could not be opened")
                val document = mapOf("uri" to uri.toString(), "name" to displayName(uri), "data" to bytes)
                runOnUiThread { result.success(document) }
            } catch (e: Exception) {
                runOnUiThread { result.error("read", e.message, null) }
            }
        }.start()
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0)
        }
        return uri.lastPathSegment ?: "document.pdf"
    }

    private companion object {
        const val PICK_PDF = 1
    }
}
