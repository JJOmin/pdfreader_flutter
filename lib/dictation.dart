// Speaking a comment (ADR 6): Android records the microphone, and the speech model runs on the phone
// (lib/speech/transcriber.dart). Nothing leaves the phone. Listening stops when the speaker pauses,
// or when asked; the words appear every moment or so while speaking, and once more at the end. The
// model works out the language (German or English) by itself.
import 'dart:async';

import 'package:flutter/services.dart';

import 'shared/endpoint.dart';
import 'speech/transcriber.dart';

/// What listening ended with: the text, nothing heard, or a reason it could not listen.
class Dictated {
  const Dictated({this.text, this.error});

  /// Null when nothing was said.
  final String? text;

  /// A sentence for the user when listening failed; null otherwise.
  final String? error;
}

abstract interface class Dictation {
  /// Whether this phone can record for spoken comments at all.
  Future<bool> available();

  /// Listens until the speaker pauses or `stop` is called. `onPartial` gets the words so far.
  Future<Dictated> listen({void Function(String text)? onPartial});

  /// Ends listening early and still transcribes what was said: `listen` then completes with it.
  Future<void> stop();

  /// Ends listening and throws away what was said.
  Future<void> cancel();
}

class PlatformDictation implements Dictation {
  PlatformDictation({Transcriber? transcriber, this.partialEvery = const Duration(milliseconds: 1500)})
    : _transcriber = transcriber ?? SherpaTranscriber() {
    _channel.setMethodCallHandler(_fromPlatform);
  }

  static const _channel = MethodChannel('pdfreader/dictation');
  final Transcriber _transcriber;

  /// How often the words so far are worked out while the speaker goes on.
  final Duration partialEvery;

  Endpointer? _heard;
  Completer<bool>? _ending;

  Future<void> _fromPlatform(MethodCall call) async {
    if (call.method != 'chunk') return;
    final heard = _heard;
    if (heard == null) return;
    heard.accept(pcm16ToFloat(call.arguments as Uint8List));
    if (heard.finished) _end(keep: true);
  }

  void _end({required bool keep}) {
    final ending = _ending;
    if (ending != null && !ending.isCompleted) ending.complete(keep);
  }

  @override
  Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Dictated> listen({void Function(String text)? onPartial}) async {
    if (_ending != null) return const Dictated(error: 'Already listening');
    final problem = await _transcriber.problem();
    if (problem != null) return Dictated(error: problem);
    final heard = _heard = Endpointer();
    final ending = _ending = Completer<bool>();
    unawaited(_transcriber.warmUp());
    try {
      await _channel.invokeMethod<void>('start');
    } on PlatformException catch (e) {
      _heard = _ending = null;
      return Dictated(error: e.message ?? 'The microphone could not be opened');
    } on MissingPluginException {
      _heard = _ending = null;
      return const Dictated(error: 'This phone cannot record for spoken comments');
    }
    var working = false;
    final partials = Timer.periodic(partialEvery, (_) async {
      if (working || !heard.heardSpeech || ending.isCompleted || onPartial == null) return;
      working = true;
      try {
        final words = await _transcriber.transcribe(heard.samples);
        if (!ending.isCompleted && words.isNotEmpty) onPartial(words);
      } catch (_) {
        // The last, whole transcription reports a failure; a partial one just does not show.
      } finally {
        working = false;
      }
    });
    final keep = await ending.future;
    partials.cancel();
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing was recording.
    }
    _heard = _ending = null;
    if (!keep || !heard.heardSpeech) return const Dictated();
    try {
      final text = await _transcriber.transcribe(heard.samples);
      return Dictated(text: text.isEmpty ? null : text);
    } catch (error) {
      return Dictated(error: 'The speech model failed: $error');
    }
  }

  @override
  Future<void> stop() async => _end(keep: true);

  @override
  Future<void> cancel() async => _end(keep: false);
}
