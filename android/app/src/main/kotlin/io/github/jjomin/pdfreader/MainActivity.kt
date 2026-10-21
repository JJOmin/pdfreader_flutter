package io.github.jjomin.pdfreader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
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
    private var oauthChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfreader/documents")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickPdf" -> pickPdf(result)
                    else -> result.notImplemented()
                }
            }
        // SecretBox (ADR 3 section 5): the sign-in secrets and the sync key are encrypted with a key
        // in the Android Keystore, which never leaves the chip, as the desktop's safeStorage does.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfreader/secrets")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "encrypt" -> result.success(encrypt(call.arguments as String))
                        "decrypt" -> result.success(decrypt(call.arguments as String))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("secret", e.message, null)
                }
            }
        // Browser (ADR 3 section 4): the sign-in pages of Nextcloud and Dropbox open in the user's
        // own browser, never in the app, so the app never sees a password.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfreader/browser")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uri = Uri.parse(call.arguments as String)
                // Only web pages: nothing the sign-in code builds is anything else.
                if (uri.scheme != "https" && uri.scheme != "http") {
                    result.error("scheme", "Only web addresses are opened", null)
                } else {
                    startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
            }
        oauthChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfreader/oauth")
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

    /** The browser sent the user back with an address of the app's own scheme: on to the sign-in code. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uri = intent.data
        if (intent.action == Intent.ACTION_VIEW && uri != null && uri.scheme == "io.github.jjomin.pdfreader") {
            oauthChannel?.invokeMethod("redirect", uri.toString())
        }
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    /** Base64 of the IV followed by the ciphertext. */
    private fun encrypt(text: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, secretKey()) }
        return Base64.encodeToString(cipher.iv + cipher.doFinal(text.toByteArray()), Base64.NO_WRAP)
    }

    private fun decrypt(text: String): String {
        val bytes = Base64.decode(text, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            .apply { init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, bytes, 0, IV_BYTES)) }
        return String(cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES))
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
        const val KEY_ALIAS = "pdfreader-secrets"
        const val IV_BYTES = 12
    }
}
