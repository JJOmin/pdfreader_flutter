// Finds where a spoken comment ends (PLAN 11): the microphone gives 16 kHz samples, and listening
// stops once a pause follows speech. A plain level detector: the recogniser model decides what was
// said, this only decides when to stop recording.
import 'dart:math' as math;
import 'dart:typed_data';

/// Little-endian 16-bit mono samples, as Android's AudioRecord gives them, as floats in -1 to 1.
Float32List pcm16ToFloat(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final out = Float32List(bytes.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = data.getInt16(i * 2, Endian.little) / 32768;
  }
  return out;
}

enum EndReason { none, pause, nothingSaid, tooLong }

class Endpointer {
  Endpointer({
    this.sampleRate = 16000,
    this.pause = const Duration(milliseconds: 1800),
    this.nothingSaid = const Duration(seconds: 6),
    this.maxLength = const Duration(seconds: 60),
  });

  final int sampleRate;

  /// Silence after speech that ends the recording: long enough for a breath, short enough to not wait.
  final Duration pause;

  /// How long to wait for the first word.
  final Duration nothingSaid;
  final Duration maxLength;

  /// Speech needs at least this much loud audio before it counts, so a click does not start it.
  static const _minSpeech = Duration(milliseconds: 200);

  /// The quietest level that can be speech, how far above the background it has to be, and the
  /// loudest a background can be taken to be: speaking from the very first moment is not a hum.
  static const _minLevel = 0.012;
  static const _aboveBackground = 3.0;
  static const _maxBackground = 0.02;

  final _chunks = <Float32List>[];
  int _count = 0;
  int _speechSamples = 0;
  int _silentRun = 0;
  double _background = _maxBackground;
  EndReason _reason = EndReason.none;

  /// Everything heard so far.
  Float32List get samples {
    final out = Float32List(_count);
    var at = 0;
    for (final chunk in _chunks) {
      out.setAll(at, chunk);
      at += chunk.length;
    }
    return out;
  }

  Duration get length => Duration(microseconds: _count * 1000000 ~/ sampleRate);
  bool get heardSpeech => _speechSamples >= _minSpeech.inMicroseconds * sampleRate ~/ 1000000;
  bool get finished => _reason != EndReason.none;
  EndReason get reason => _reason;

  /// Takes the next piece of audio; once finished, further audio is ignored.
  void accept(Float32List chunk) {
    if (finished || chunk.isEmpty) return;
    _chunks.add(chunk);
    _count += chunk.length;
    var sum = 0.0;
    for (final s in chunk) {
      sum += s * s;
    }
    final level = math.sqrt(sum / chunk.length);
    // The background is the quietest the room has been, creeping up so a changed room is followed.
    _background = math.min(_maxBackground, math.min(level, _background * 1.02 + 1e-5));
    final loud = level > math.max(_minLevel, _background * _aboveBackground);
    if (loud) {
      _speechSamples += chunk.length;
      _silentRun = 0;
    } else {
      _silentRun += chunk.length;
    }
    final elapsed = length;
    if (heardSpeech && !loud && _silentRun >= pause.inMicroseconds * sampleRate ~/ 1000000) {
      _reason = EndReason.pause;
    } else if (!heardSpeech && elapsed >= nothingSaid) {
      _reason = EndReason.nothingSaid;
    } else if (elapsed >= maxLength) {
      _reason = EndReason.tooLong;
    }
  }
}
