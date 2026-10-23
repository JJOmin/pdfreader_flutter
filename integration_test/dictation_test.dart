// ADR 6 on the phone: the speech model understands speech, in German and English, offline, and the
// microphone opens. The speech is the phone's own voice, so nobody has to talk to the test.
//   flutter test integration_test/dictation_test.dart --no-uninstall
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pdfreader/dictation.dart';
import 'package:pdfreader/phone_voice.dart';
import 'package:pdfreader/shared/types.dart';
import 'package:pdfreader/speech/transcriber.dart';

/// The samples of a 16-bit mono WAV file, at 16 kHz.
Float32List wavAt16k(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final rate = data.getUint32(24, Endian.little);
  final channels = data.getUint16(22, Endian.little);
  expect(data.getUint16(34, Endian.little), 16, reason: '16-bit samples');
  // The data chunk, after whatever chunks the engine wrote before it.
  var at = 12;
  while (String.fromCharCodes(bytes.sublist(at, at + 4)) != 'data') {
    at += 8 + data.getUint32(at + 4, Endian.little);
  }
  final count = data.getUint32(at + 4, Endian.little) ~/ (2 * channels);
  final source = [
    for (var i = 0; i < count; i++) data.getInt16(at + 8 + i * 2 * channels, Endian.little) / 32768,
  ];
  final out = Float32List(source.length * 16000 ~/ rate);
  for (var i = 0; i < out.length; i++) {
    final at = i * rate / 16000;
    final i0 = at.floor();
    final i1 = i0 + 1 < source.length ? i0 + 1 : i0;
    out[i] = source[i0] + (source[i1] - source[i0]) * (at - i0);
  }
  return out;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the model writes out German and English speech', (tester) async {
    final voice = PlatformPhoneVoice();
    final langs = await voice.languages();
    final transcriber = SherpaTranscriber();
    expect(await transcriber.problem(), isNull, reason: 'the model is installed (tool/push_models)');
    final sentences = {
      Lang.de: 'Das ist ein Kommentar zu diesem Absatz und er ist wirklich sehr wichtig.',
      Lang.en: 'This is a comment on this paragraph and it is really very important.',
    };
    for (final MapEntry(key: lang, value: text) in sentences.entries) {
      if (!langs.contains(lang)) continue;
      final path = await voice.synthesize(text, lang);
      final samples = wavAt16k(path);
      File(path).deleteSync();
      final watch = Stopwatch()..start();
      final heard = await transcriber.transcribe(samples);
      final first = watch.elapsedMilliseconds;
      watch.reset();
      await transcriber.transcribe(samples);
      // ignore: avoid_print
      print(
        '${lang.name}: ${samples.length / 16000} s of speech, first $first ms (with loading), '
        'then ${watch.elapsedMilliseconds} ms\n  said:  $text\n  heard: $heard',
      );
      expect(heard, isNotEmpty);
      final said = text.toLowerCase().replaceAll(RegExp(r'[^\p{L} ]', unicode: true), '').split(' ');
      final got = heard.toLowerCase().replaceAll(RegExp(r'[^\p{L} ]', unicode: true), '').split(' ');
      final shared = said.where(got.contains).length;
      expect(shared / said.length, greaterThan(0.7), reason: 'most words are recognised');
    }
  });

  testWidgets('the microphone opens, and a room with nobody speaking gives no text', (tester) async {
    final dictation = PlatformDictation();
    expect(await dictation.available(), isTrue);
    final watch = Stopwatch()..start();
    final result = await dictation.listen();
    // ignore: avoid_print
    print('listened for ${watch.elapsed.inSeconds} s: text ${result.text}, error ${result.error}');
    expect(result.error, isNull, reason: 'permission given, microphone opened');
    expect(watch.elapsed, greaterThan(const Duration(seconds: 5)), reason: 'it waited for a first word');
  });

  testWidgets('what the phone says aloud is heard by its microphone and written out', (tester) async {
    final voice = PlatformPhoneVoice();
    if (!(await voice.languages()).contains(Lang.de)) {
      markTestSkipped('no offline German voice on this phone');
      return;
    }
    const text = 'Hier ist mein Kommentar zu diesem Absatz, er enthält eine wichtige Idee.';
    final path = await voice.synthesize(text, Lang.de);
    final player = AudioPlayer();
    await player.setFilePath(path);
    await player.setVolume(1);
    final dictation = PlatformDictation();
    final partials = <String>[];
    final heard = dictation.listen(onPartial: partials.add);
    // A moment of quiet first, as when a person starts to speak.
    await Future<void>.delayed(const Duration(seconds: 1));
    final watch = Stopwatch()..start();
    unawaited(player.play());
    final result = await heard;
    // ignore: avoid_print
    print(
      'ended ${watch.elapsedMilliseconds} ms after the speech began\n  said:     $text\n'
      '  partials: $partials\n  heard:    ${result.text} (error ${result.error})',
    );
    await player.dispose();
    File(path).deleteSync();
    expect(result.error, isNull);
    expect(result.text, isNotNull, reason: 'the microphone picked up the speaker');
    final got = result.text!.toLowerCase();
    expect(['kommentar', 'absatz', 'wichtige', 'idee'].where(got.contains).length, greaterThanOrEqualTo(2));
  });
}
