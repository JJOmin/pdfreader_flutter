// ADR 5 on the phone: the system's text-to-speech makes audio for a PDF the desktop never prepared,
// and the reader plays it with the word mark and the "phone" badge.
//   flutter test integration_test/phone_voice_test.dart --no-uninstall
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfreader/dictation.dart';
import 'package:pdfreader/notes_store.dart';
import 'package:pdfreader/phone_voice.dart';
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/reader_page.dart';
import 'package:pdfreader/shared/notes.dart';
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

/// A recogniser that always hears the same words, so a spoken comment can be made without anyone speaking.
class HeardDictation implements Dictation {
  @override
  Future<bool> available() async => true;

  @override
  Future<Dictated> listen({void Function(String text)? onPartial}) async =>
      const Dictated(text: 'Said out loud');

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
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
    expect(find.byKey(const Key('status')), findsNothing, reason: 'no box about where the audio comes from');

    await tester.tap(play);
    final sentences = <String>{};
    final words = <int>[];
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 20) && sentences.length < 2) {
      await tester.pump(const Duration(milliseconds: 30));
      final sentence = page.sentence;
      if (sentence == null) continue;
      expect(sentence.source, SpeechSource.phone);
      expect(page.session.source, SpeechSource.phone);
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

  testWidgets('a comment on the sentence being read pauses, saves a mark with the comment and goes on', (
    tester,
  ) async {
    await pdfrxFlutterInitialize();
    final voice = PlatformPhoneVoice();
    final langs = await voice.languages();
    if (!langs.contains(Lang.en)) {
      markTestSkipped('no offline English voice on this phone');
      return;
    }
    final dictation = PlatformDictation();
    final dir = Directory.systemTemp.createTempSync('comment-');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          name: 'tiny.pdf',
          data: tinyPdf(),
          placeKey: 'test:comment',
          phoneVoice: voice,
          phoneLangs: langs,
          dictation: dictation,
          notesStore: NotesStore(dir),
        ),
      ),
    );
    final play = find.byKey(const Key('play'));
    for (
      var i = 0;
      i < 100 && (play.evaluate().isEmpty || tester.widget<IconButton>(play).onPressed == null);
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final page = tester.state<ReaderPageState>(find.byType(ReaderPage));
    await tester.tap(play);
    for (var i = 0; i < 100 && page.sentence == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final spoken = page.sentence!;

    // What the player's Comment button does: pause, ask, save on the sentence, resume.
    final session = page.session;
    unawaited(session.comment!(speak: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(page.state, ReaderState.paused, reason: 'asking for a comment pauses the voice');
    expect(find.byKey(const Key('quick-comment')), findsOneWidget);
    expect(find.byKey(const Key('dictate')), findsNWidgets(await dictation.available() ? 1 : 0));
    await tester.enterText(find.byKey(const Key('quick-comment')), 'Check this claim');
    await tester.tap(find.byKey(const Key('save-comment')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(page.marks, hasLength(1));
    expect(page.marks.single.comment, 'Check this claim');
    expect(page.marks.single.page, spoken.page);
    expect(page.marks.single.start, spoken.ranges.first.$1);
    expect(page.marks.single.end, spoken.ranges.last.$2);
    expect(page.marks.single.via, isNull, reason: 'typed, so not marked as spoken');
    expect(page.state, ReaderState.playing, reason: 'it was reading, so it reads on');
    await tester.tap(play);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a spoken comment gets a microphone mark and a typed one a note, in both views', (
    tester,
  ) async {
    await pdfrxFlutterInitialize();
    final voice = PlatformPhoneVoice();
    final langs = await voice.languages();
    if (!langs.contains(Lang.en)) {
      markTestSkipped('no offline English voice on this phone');
      return;
    }
    final dir = Directory.systemTemp.createTempSync('badges-');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          name: 'tiny.pdf',
          data: tinyPdf(),
          placeKey: 'test:badges',
          phoneVoice: voice,
          phoneLangs: langs,
          dictation: HeardDictation(),
          notesStore: NotesStore(dir),
        ),
      ),
    );
    final play = find.byKey(const Key('play'));
    for (
      var i = 0;
      i < 100 && (play.evaluate().isEmpty || tester.widget<IconButton>(play).onPressed == null);
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final page = tester.state<ReaderPageState>(find.byType(ReaderPage));
    await tester.tap(play);
    for (var i = 0; i < 100 && page.sentence == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // The first sentence, spoken to the recogniser.
    unawaited(page.session.comment!(speak: true));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('save-comment')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // The second, typed.
    page.session.skip!(1);
    await tester.pump(const Duration(seconds: 1));
    unawaited(page.session.comment!(speak: false));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byKey(const Key('quick-comment')), 'Typed remark');
    await tester.tap(find.byKey(const Key('save-comment')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(play);
    await tester.pump(const Duration(milliseconds: 300));

    expect(page.marks, hasLength(2));
    expect(
      [for (final m in page.marks) (m.comment, m.via)],
      [('Said out loud', 'speech'), ('Typed remark', null)],
    );
    expect([for (final m in page.marks) markBadge(m)], [NoteBadge.speech, NoteBadge.note]);

    // Time to look at it: the pages first, then the reading view.
    // ignore: avoid_print
    print('SHOT pages');
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.byKey(const Key('toggle-reading')));
    await tester.pump(const Duration(seconds: 1));
    // ignore: avoid_print
    print('SHOT reading');
    await tester.pump(const Duration(seconds: 6));
  });

  for (final reading in [true, false]) {
    testWidgets(
      'the Comment button in the selection menu opens the sheet in the ${reading ? 'reading view' : 'pages'}',
      (tester) async {
        await pdfrxFlutterInitialize();
        final voice = PlatformPhoneVoice();
        final langs = await voice.languages();
        final dir = Directory.systemTemp.createTempSync('menu-');
        addTearDown(() => dir.deleteSync(recursive: true));
        await tester.pumpWidget(
          MaterialApp(
            home: ReaderPage(
              name: 'tiny.pdf',
              data: tinyPdf(),
              placeKey: 'test:menu-$reading',
              phoneVoice: voice,
              phoneLangs: langs,
              dictation: HeardDictation(),
              notesStore: NotesStore(dir),
              startInReading: reading,
            ),
          ),
        );
        final page = tester.state<ReaderPageState>(find.byType(ReaderPage));
        List<Utterance> utterances = const [];
        for (var i = 0; i < 100 && utterances.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          try {
            utterances = await page.utterancesOf(1);
          } catch (_) {}
        }
        final word = utterances.first.words.first;
        for (var i = 0; i < 100 && page.globalCenterOf(1, word.ranges) == null; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.longPressAt(page.globalCenterOf(1, word.ranges)!);
        for (var i = 0; i < 50 && find.byKey(const Key('comment-selection')).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const Key('comment-selection')), findsOneWidget, reason: 'the menu has the button');
        expect(find.byKey(const Key('speak-comment')), findsNothing);
        await tester.tap(find.byKey(const Key('comment-selection')));
        for (var i = 0; i < 50 && find.byKey(const Key('quick-comment')).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const Key('quick-comment')), findsOneWidget, reason: 'the comment sheet opens');
        // Typed, with the keyboard; the microphone is in the sheet, for whoever wants it.
        expect(find.byKey(const Key('dictate')), findsOneWidget);
        await tester.enterText(find.byKey(const Key('quick-comment')), 'Typed on a selection');
        await tester.tap(find.byKey(const Key('save-comment')));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(page.marks, hasLength(1));
        expect(page.marks.single.comment, 'Typed on a selection');
        expect(page.marks.single.via, isNull);
      },
    );
  }
}
