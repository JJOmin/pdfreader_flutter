package io.github.jjomin.pdfreader

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
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
import android.os.Bundle
import android.provider.Settings
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * DocumentAccess (ADR 1): opens documents through the system picker and keeps their content URI,
 * so that later steps can write notes next to the PDF. A file picker package would copy the file
 * into the cache and lose where it came from. It extends audio_service's activity, which shares
 * the Flutter engine with the playback service, so reading goes on with the screen off. A PDF that
 * another app opens this one with ("Open with", "Share") is handed to Flutter the same way.
 */
class MainActivity : AudioServiceActivity() {
    private var pending: MethodChannel.Result? = null
    /** A file the user is choosing a place for, with the answer to give once it is written. */
    private var saving: Pair<ByteArray, MethodChannel.Result>? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    /** The PDF another app opened this one with, until Flutter has taken it. */
    private var incoming: Uri? = null
    private var documents: MethodChannel? = null
    private val phoneVoice by lazy { PhoneVoice(applicationContext) }
    private var dictation: Dictation? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Not after a restart of the activity: that would open the same PDF again.
        if (savedInstanceState == null) incoming = incomingUri(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uri = incomingUri(intent) ?: return
        incoming = uri
        documents?.invokeMethod("incoming", null)
    }

    private fun incomingUri(intent: Intent?): Uri? = when (intent?.action) {
        Intent.ACTION_VIEW -> intent.data
        @Suppress("DEPRECATION")
        Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        else -> null
    }?.takeUnless { isOwnPrivateFile(it) }

    /**
     * A `file:` address that points into this app's own storage. Any app, or a web page, can send
     * an intent with one, and the app would read its own private files for it; the system's pickers
     * and other apps' shares use `content:` addresses, which name only what the sender may give.
     */
    private fun isOwnPrivateFile(uri: Uri): Boolean {
        if (uri.scheme != "file") return false
        val path = try { java.io.File(uri.path ?: return true).canonicalPath } catch (e: Exception) { return true }
        return listOf(applicationInfo.dataDir, applicationInfo.deviceProtectedDataDir).any {
            path == java.io.File(it).canonicalPath || path.startsWith(java.io.File(it).canonicalPath + "/")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        documents = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfreader/documents")
        documents!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickPdf" -> pickPdf(result)
                "takeIncoming" -> takeIncoming(result)
                "saveAs" -> saveAs(
                    call.argument<String>("name")!!,
                    call.argument<String>("mime")!!,
                    call.argument<ByteArray>("data")!!,
                    result,
                )
                else -> result.notImplemented()
            }
        }
        // The phone's own voice (ADR 5): the system's text-to-speech, offline voices only.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfreader/tts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "languages" -> phoneVoice.languages(result)
                    "synthesize" -> phoneVoice.synthesize(
                        call.argument<String>("text")!!,
                        call.argument<String>("lang")!!,
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
        // Speaking a comment (ADR 6): the microphone only; the speech model runs in Dart.
        val dictationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfreader/dictation")
        val dictation = Dictation(this, dictationChannel).also { this.dictation = it }
        dictationChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(true)
                "start" -> dictation.start(result)
                "stop" -> { dictation.stop(); result.success(null) }
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
        // Browser (ADR 3 section 4): Nextcloud's sign-in page opens in the user's
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
                    // Downloads the phone starts on its own wait for a network that is not metered
                    // (desktop ADR 10 section 4); a tap on a document always downloads.
                    "isMetered" -> {
                        val connectivity = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                        result.success(connectivity.isActiveNetworkMetered)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        dictation?.onPermission(requestCode, grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        dictation?.stop()
        phoneVoice.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
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

    private fun takeIncoming(result: MethodChannel.Result) {
        val uri = incoming
        incoming = null
        if (uri == null) {
            result.success(null)
            return
        }
        readDocument(uri, result)
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

    /**
     * The system's "save as": the user picks the folder and the name, and only that one file can be
     * written (Markdown export and "Save PDF", PLAN 4.2 and 4.4). Answers true once written, false
     * when the user cancelled.
     */
    private fun saveAs(name: String, mime: String, data: ByteArray, result: MethodChannel.Result) {
        if (saving != null) {
            result.error("busy", "A file is already being saved", null)
            return
        }
        saving = data to result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mime)
            .putExtra(Intent.EXTRA_TITLE, name)
        @Suppress("DEPRECATION")
        startActivityForResult(intent, SAVE_AS)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAVE_AS) {
            val (bytes, answer) = saving ?: return
            saving = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                answer.success(false)
                return
            }
            Thread {
                try {
                    contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                        ?: throw IllegalStateException("The file could not be written")
                    runOnUiThread { answer.success(true) }
                } catch (e: Exception) {
                    runOnUiThread { answer.error("write", e.message, null) }
                }
            }.start()
            return
        }
        if (requestCode != PICK_PDF) return
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        readDocument(uri, result)
    }

    /** A large PDF takes a moment to read; keep it off the UI thread. */
    private fun readDocument(uri: Uri, result: MethodChannel.Result) {
        Thread {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { readCapped(it) }
                    ?: throw IllegalStateException("The document could not be opened")
                val document = mapOf("uri" to uri.toString(), "name" to displayName(uri), "data" to bytes)
                runOnUiThread { result.success(document) }
            } catch (e: Exception) {
                runOnUiThread { result.error("read", e.message, null) }
            }
        }.start()
    }

    /** The whole document is held in memory, so one that is far larger than any PDF is refused. */
    private fun readCapped(stream: java.io.InputStream): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val chunk = ByteArray(64 * 1024)
        while (true) {
            val n = stream.read(chunk)
            if (n < 0) break
            out.write(chunk, 0, n)
            if (out.size() > MAX_DOCUMENT_BYTES) throw IllegalStateException("The document is larger than 300 MB")
        }
        return out.toByteArray()
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0)
        }
        return uri.lastPathSegment ?: "document.pdf"
    }

    private companion object {
        const val PICK_PDF = 1
        const val SAVE_AS = 2
        const val KEY_ALIAS = "pdfreader-secrets"
        const val IV_BYTES = 12
        const val MAX_DOCUMENT_BYTES = 300 * 1024 * 1024
    }
}
