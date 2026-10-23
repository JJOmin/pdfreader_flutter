// ADR 5 on the phone: the system's text-to-speech makes audio for a PDF the desktop never prepared,
// and the reader plays it with the word mark and the "phone" badge.
//   flutter test integration_test/phone_voice_test.dart --no-uninstall
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfreader/phone_voice.dart';
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/reader_page.dart';
import 'package:pdfreader/shared/read_plan.dart';
import 'package:pdfreader/shared/types.dart';

/// A one-page PDF with two English sentences, written by hand so the test needs no fixture.
Uint8List tinyPdf() {
  const text = 'Hello there. This is a short test of the phone voice.';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${'BT /F1 14 Tf 72 700 Td ($text) Tj ET'.length} >>\nstream\nBT /F1 14 Tf 72 700 Td ($text) Tj ET\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(utf8.encode(out.toString()));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the system voice speaks German and English into audio files, offline', (tester) async {
    final voice = PlatformPhoneVoice();
    final langs = await voice.languages();
    // ignore: avoid_print
    print('phone voice languages: $langs');
    expect(langs, isNotEmpty, reason: 'this phone has an offline voice');
    for (final lang in langs) {
      final watch = Stopwatch()..start();
      final path = await voice.synthesize(
        lang == Lang.de ? 'Das ist ein kurzer Satz.' : 'This is a short sentence.',
        lang,
      );
      // ignore: avoid_print
      print('${lang.name}: ${watch.elapsedMilliseconds} ms, ${File(path).lengthSync()} bytes');
      expect(File(path).lengthSync(), greaterThan(2000));
      File(path).deleteSync();
    }
  });

  testWidgets('reads a PDF the desktop did not prepare, with the phone voice', (tester) async {
    await pdfrxFlutterInitialize();
    final voice = PlatformPhoneVoice();
    final langs = await voice.languages();
    if (!langs.contains(Lang.en)) {
      markTestSkipped('no offline English voice on this phone');
      return;
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          name: 'tiny.pdf',
          data: tinyPdf(),
          placeKey: 'test:tiny',
          phoneVoice: voice,
          phoneLangs: langs,
        ),
      ),
    );
    final play = find.byKey(const Key('play'));
    bool ready() => play.evaluate().isNotEmpty && tester.widget<IconButton>(play).onPressed != null;
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue, reason: 'a document with a phone voice can be played');
    final page = tester.state<ReaderPageState>(find.byType(ReaderPage));
    expect(find.byKey(const Key('status')), findsOneWidget);

    await tester.tap(play);
    final sentences = <String>{};
    final words = <int>[];
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 20) && sentences.length < 2) {
      await tester.pump(const Duration(milliseconds: 30));
      final sentence = page.sentence;
      if (sentence == null) continue;
      expect(sentence.source, SpeechSource.phone);
      expect(find.byKey(const Key('source-phone')), findsOneWidget);
      sentences.add(sentence.key);
      if (page.word >= 0 && (words.isEmpty || words.last != page.word)) words.add(page.word);
    }
    // ignore: avoid_print
    print('sentences read: ${sentences.length}, words marked: $words');
    expect(sentences.length, 2, reason: 'both sentences were read');
    expect(words, isNotEmpty, reason: 'the word mark moved');
    expect(words, orderedEquals([...words]..sort()));
    expect(page.state, ReaderState.playing);
    await tester.tap(play);
    await tester.pump(const Duration(milliseconds: 300));
    expect(page.state, ReaderState.paused);
  });
}
