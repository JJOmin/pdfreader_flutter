// The phone's own voice (ADR 5): the system's text-to-speech renders one sentence to an audio file,
// which plays like the desktop's. Only voices that work offline are used. Android implements the
// channel in Kotlin; iOS gets AVSpeechSynthesizer later, and until then reports no voice.
import 'package:flutter/services.dart';

import 'shared/types.dart';

abstract interface class PhoneVoice {
  /// The languages the system can speak without a network.
  Future<Set<Lang>> languages();

  /// Speaks `text` into a new audio file and returns its path. The caller deletes the file.
  Future<String> synthesize(String text, Lang lang);
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
  Future<String> synthesize(String text, Lang lang) async =>
      (await _channel.invokeMethod<String>('synthesize', {'text': text, 'lang': lang.name}))!;
}
