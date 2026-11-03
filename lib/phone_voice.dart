// The phone's own voice (ADR 5): the system's text-to-speech renders one sentence to an audio file,
// which plays like the desktop's. Only voices that work offline are used. Android implements the
// channel in Kotlin; iOS gets AVSpeechSynthesizer later, and until then reports no voice.
import 'package:flutter/services.dart';

import 'shared/align.dart' show marksFromRanges;
import 'shared/types.dart';

/// A sentence spoken into a file, and where the engine said each stretch of the text starts in it: a
/// UTF-16 offset in the text and seconds into the audio (PLAN 18.3). Empty where the engine says nothing.
typedef SpokenAudio = ({String path, List<(int, double)> marks});

abstract interface class PhoneVoice {
  /// The languages the system can speak without a network.
  Future<Set<Lang>> languages();

  /// Speaks `text` into a new audio file. The caller deletes the file.
  Future<SpokenAudio> synthesize(String text, Lang lang);
}

class PlatformPhoneVoice implements PhoneVoice {
  static const _channel = MethodChannel('pdfreader/tts');

  @override
  Future<Set<Lang>> languages() async {
    try {
      final codes = await _channel.invokeListMethod<String>('languages') ?? const [];
      return {
        for (final lang in Lang.values)
          if (codes.contains(lang.name)) lang,
      };
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  @override
  Future<SpokenAudio> synthesize(String text, Lang lang) async {
    final answer = await _channel.invokeMethod<Object>('synthesize', {'text': text, 'lang': lang.name});
    if (answer is String) return (path: answer, marks: const <(int, double)>[]);
    final map = answer! as Map<Object?, Object?>;
    final rate = map['rate'];
    final flat = map['marks'];
    // Each mark is three numbers, in an order that differs between engines; `marksFromRanges` tells.
    final ranges = <(int, int, int)>[
      if (flat is List<Object?>)
        for (var i = 0; i + 2 < flat.length; i += 3)
          (flat[i]! as int, flat[i + 1]! as int, flat[i + 2]! as int),
    ];
    return (
      path: map['path']! as String,
      marks: marksFromRanges(ranges, textLength: text.length, rate: rate is int ? rate : 0),
    );
  }
}
