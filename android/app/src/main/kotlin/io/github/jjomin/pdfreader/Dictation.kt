package io.github.jjomin.pdfreader

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * The microphone for spoken comments (ADR 6). It only records: 16 kHz mono 16-bit samples go to
 * Dart in pieces of about 100 ms (`chunk`), and the speech model that turns them into text runs
 * there, on the phone. Android's own recogniser is not used: on the owner's phone it cannot be
 * bound, and it may use the network. One recording at a time.
 */
class Dictation(private val activity: Activity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private var recorder: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var recording = false
    private var waiting: MethodChannel.Result? = null

    /** Starts recording; answers once it runs, or with why it cannot. */
    fun start(result: MethodChannel.Result) {
        if (recording || waiting != null) return result.error("busy", "Already recording", null)
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            waiting = result
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST)
            return
        }
        begin(result)
    }

    /** The answer to the microphone permission prompt. */
    fun onPermission(requestCode: Int, granted: Boolean) {
        if (requestCode != REQUEST) return
        val result = waiting ?: return
        waiting = null
        if (granted) begin(result) else result.error("permission", "The microphone is not allowed", null)
    }

    fun stop() {
        recording = false
        thread?.join(500)
        thread = null
        recorder?.release()
        recorder = null
    }

    private fun begin(result: MethodChannel.Result) {
        val minimum = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val chunkBytes = RATE / 10 * 2
        val engine = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum, chunkBytes * 4),
            )
        } catch (e: Exception) {
            return result.error("microphone", e.message ?: "The microphone could not be opened", null)
        }
        if (engine.state != AudioRecord.STATE_INITIALIZED) {
            engine.release()
            return result.error("microphone", "The microphone could not be opened", null)
        }
        recorder = engine
        recording = true
        engine.startRecording()
        thread = Thread {
            val buffer = ByteArray(chunkBytes)
            while (recording) {
                val read = engine.read(buffer, 0, buffer.size)
                if (read <= 0) break
                val piece = buffer.copyOf(read)
                main.post { if (recording) channel.invokeMethod("chunk", piece) }
            }
        }.also { it.start() }
        result.success(null)
    }

    private companion object {
        const val REQUEST = 4711
        const val RATE = 16000
    }
}
