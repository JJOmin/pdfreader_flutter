package io.github.jjomin.pdfreader

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/**
 * The phone's own voice (ADR 5): the system's text-to-speech renders one sentence into a WAV file,
 * and Dart plays the file like the desktop's audio. Never live `speak()`: a file keeps one player,
 * one speed control and the media notification for both kinds of audio.
 *
 * Only voices that work without a network are used (the app's offline rule). Requests run one at a
 * time, in order, with the language set before each, so a German sentence queued behind an English
 * one is not spoken with the wrong voice.
 */
class PhoneVoice(private val context: Context) {
    private class Job(val text: String, val lang: String, val result: MethodChannel.Result)

    private val main = Handler(Looper.getMainLooper())
    private val dir = File(context.cacheDir, "tts")
    private var engine: TextToSpeech? = null
    /** Null while the engine starts, then whether it did. */
    private var started: Boolean? = null
    private val whenStarted = mutableListOf<(Boolean) -> Unit>()
    private val queue = ArrayDeque<Job>()
    private var running: Job? = null
    private var runningId: String? = null
    private var runningFile: File? = null
    private var counter = 0
    private val timeout = Runnable { finish(runningId, "The voice did not answer") }

    /** The languages ("de", "en") the system speaks offline; empty without an engine. */
    fun languages(result: MethodChannel.Result) = whenReady { ok ->
        val found = if (ok) listOf("de", "en").filter { available(it) } else emptyList<String>()
        if (ok) {
            val voices = try { engine?.voices } catch (e: Exception) { null }
            Log.i(TAG, "engine ${engine?.defaultEngine}, ${voices?.size} voices, offline languages $found")
            found.forEach { Log.i(TAG, "$it: ${voiceFor(it)?.name}") }
        }
        result.success(found)
    }

    fun synthesize(text: String, lang: String, result: MethodChannel.Result) {
        queue.addLast(Job(text, lang, result))
        whenReady { ok -> if (ok) pump() else failAll() }
    }

    fun shutdown() {
        main.removeCallbacks(timeout)
        engine?.shutdown()
        engine = null
        started = null
        queue.forEach { it.result.error("shutdown", "The voice was shut down", null) }
        queue.clear()
    }

    /** Runs `action` once the engine has started, with whether it did. */
    private fun whenReady(action: (Boolean) -> Unit) {
        when (val ok = started) {
            null -> {
                whenStarted.add(action)
                if (engine == null) start()
            }
            else -> action(ok)
        }
    }

    private fun start() {
        // Files of an earlier run are no use: nothing remembers them.
        dir.listFiles()?.forEach { it.delete() }
        engine = TextToSpeech(context) { status ->
            main.post {
                started = status == TextToSpeech.SUCCESS
                if (started == true) engine?.setOnUtteranceProgressListener(listener)
                val waiting = whenStarted.toList()
                whenStarted.clear()
                waiting.forEach { it(started == true) }
            }
        }
    }

    private fun failAll() {
        queue.forEach { it.result.error("no-engine", "No text-to-speech engine on this phone", null) }
        queue.clear()
    }

    /** Samsung's engine names its locales with ISO 639-2 codes ("eng_USA"), Google's with 639-1 ("en"). */
    private fun speaks(voice: Voice, lang: String) =
        voice.locale.language == lang || voice.locale.language == Locale(lang).isO3Language

    /** The best offline voice for a language, or null. */
    private fun voiceFor(lang: String): Voice? {
        val voices = try { engine?.voices } catch (e: Exception) { null } ?: return null
        val country = Locale.getDefault().isO3Country
        return voices
            .filter {
                speaks(it, lang) &&
                    !it.isNetworkConnectionRequired &&
                    it.features?.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) != true
            }
            // Better quality first, then the phone's own country, then by name so the choice is stable.
            .sortedWith(
                compareByDescending<Voice> { it.quality }
                    .thenByDescending { it.locale.isO3Country == country || it.locale.country == country }
                    .thenBy { it.name }
            )
            .firstOrNull()
    }

    /** Some engines list no voices at all; they are asked about the language instead. */
    private fun available(lang: String): Boolean {
        if (voiceFor(lang) != null) return true
        val e = engine ?: return false
        val listed = try { e.voices?.isNotEmpty() == true } catch (ex: Exception) { false }
        return !listed && e.isLanguageAvailable(Locale(lang)) >= TextToSpeech.LANG_AVAILABLE
    }

    private fun pump() {
        if (running != null) return
        val job = queue.removeFirstOrNull() ?: return
        val e = engine ?: return job.result.error("no-engine", "No text-to-speech engine on this phone", null)
        running = job
        val voice = voiceFor(job.lang)
        val ready = if (voice != null) e.setVoice(voice) == TextToSpeech.SUCCESS
        else e.setLanguage(Locale(job.lang)) >= TextToSpeech.LANG_AVAILABLE
        if (!ready) {
            running = null
            job.result.error("language", "No offline voice for ${job.lang}", null)
            return pump()
        }
        e.setSpeechRate(1f)
        dir.mkdirs()
        val file = File(dir, "${counter++}.wav")
        val id = file.name
        runningId = id
        runningFile = file
        // shortcut: a sentence longer than the engine's limit is cut at a space; none has been that long.
        val limit = TextToSpeech.getMaxSpeechInputLength()
        val text = if (job.text.length <= limit) job.text else job.text.take(limit).substringBeforeLast(' ')
        main.postDelayed(timeout, TIMEOUT_MS)
        if (e.synthesizeToFile(text, Bundle(), file, id) != TextToSpeech.SUCCESS) {
            finish(id, "The voice refused the sentence")
        }
    }

    /** Answers the running request: with the file, or with an error. Then starts the next. */
    private fun finish(id: String?, error: String?) {
        if (id == null || id != runningId) return
        main.removeCallbacks(timeout)
        val job = running ?: return
        val file = runningFile
        running = null
        runningId = null
        runningFile = null
        if (error == null && file != null && file.length() > 0) {
            job.result.success(file.path)
        } else {
            file?.delete()
            job.result.error("synthesis", error ?: "The voice made no audio", null)
        }
        pump()
    }

    private val listener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) {}
        override fun onDone(utteranceId: String) { main.post { finish(utteranceId, null) } }
        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String) { main.post { finish(utteranceId, "The voice failed") } }
        override fun onError(utteranceId: String, errorCode: Int) {
            main.post { finish(utteranceId, "The voice failed (error $errorCode)") }
        }
        override fun onStop(utteranceId: String, interrupted: Boolean) {
            main.post { finish(utteranceId, "The voice was stopped") }
        }
    }

    private companion object {
        const val TIMEOUT_MS = 30_000L
        const val TAG = "PhoneVoice"
    }
}
