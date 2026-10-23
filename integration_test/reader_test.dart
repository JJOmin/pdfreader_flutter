// PLAN step 1.13: the real app on the phone reads the fixture the desktop prepared. Push it first:
//   powershell -ExecutionPolicy Bypass -File tool/push_library.ps1
//   flutter test integration_test/reader_test.dart --no-uninstall
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfreader/main.dart' as app;
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/reader_page.dart';
import 'package:pdfreader/shared/types.dart';
import 'package:path_provider/path_provider.dart';

import 'finders.dart';

bool inside(List<RawRange> inner, List<RawRange> outer) =>
    inner.every((r) => outer.any((o) => o.$1 <= r.$1 && r.$2 <= o.$2));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reads the prepared fixture with the word mark inside the spoken sentence', (tester) async {
    // From the top: the place a previous run left must not decide where Play starts.
    final saved = File('${(await getApplicationSupportDirectory()).path}/progress.json');
    if (await saved.exists()) await saved.delete();
    await app.main();
    for (var i = 0; i < 100 && find.text('sample.pdf').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(sampleTile);
    final play = find.byKey(const Key('play'));
    bool ready() => play.evaluate().isNotEmpty && tester.widget<IconButton>(play).onPressed != null;
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final page = tester.state<ReaderPageState>(find.byType(ReaderPage));
    expect(find.byKey(const Key('status')), findsNothing, reason: 'every sentence has audio');

    await tester.tap(play);
    final watch = Stopwatch()..start();
    final started = <String, int>{};
    final words = <String, List<int>>{};
    while (watch.elapsed < const Duration(seconds: 25)) {
      await tester.pump(const Duration(milliseconds: 20));
      final sentence = page.sentence;
      if (sentence == null) continue;
      started.putIfAbsent(sentence.key, () => watch.elapsedMilliseconds);
      if (page.word < 0) continue;
      final seen = words.putIfAbsent(sentence.key, () => []);
      if (seen.isEmpty || seen.last != page.word) seen.add(page.word);
      expect(inside(sentence.words[page.word].ranges, sentence.ranges), isTrue, reason: sentence.key);
    }
    expect(page.state, ReaderState.playing);

    // ignore: avoid_print
    print('sentences started at ms: ${started.values.toList()}');
    // ignore: avoid_print
    print('words seen per sentence: ${[for (final w in words.values) w.length]}');
    expect(started.length, greaterThanOrEqualTo(3), reason: 'the spoken sentence advances');
    for (final seen in words.values) {
      // The word mark only moves forward within a sentence.
      expect(seen, orderedEquals([...seen]..sort()));
    }
    // Step 1.10: the controls.
    Future<void> wait(int ms) => tester.pump(Duration(milliseconds: ms));
    final before = page.sentence!.key;
    await tester.tap(find.byTooltip('Next sentence'));
    await wait(600);
    final next = page.sentence!.key;
    expect(next, isNot(before));
    // Previous is in the full-screen player, which a tap on the bar opens (PLAN 11).
    await tester.tap(find.byKey(const Key('reader-bar')));
    await wait(600);
    await tester.tap(find.byKey(const Key('player-previous')));
    await wait(600);
    expect(page.sentence!.key, before);
    await tester.tap(find.byKey(const Key('player-minimize')));
    await wait(600);
    await tester.tap(play);
    await wait(300);
    expect(page.state, ReaderState.paused);
    final pausedAt = (page.sentence!.key, page.word);
    await wait(1500);
    expect((page.sentence!.key, page.word), pausedAt, reason: 'nothing moves while paused');
    await tester.tap(play);
    await wait(300);
    expect(page.state, ReaderState.playing);

    // Step 1.12, only with --dart-define=SCREEN_OFF=true: the shell turns the screen off at the
    // marker and on again 20 s later. Reading must have gone on in between.
    if (const bool.fromEnvironment('SCREEN_OFF')) {
      final from = page.sentence!.key;
      final cursor = (page.sentence!.page, started.length);
      // ignore: avoid_print
      print('SCREEN-OFF-NOW at sentence $from, page ${cursor.$1}');
      final screenOff = Stopwatch()..start();
      final keys = <String>{from};
      while (screenOff.elapsed < const Duration(seconds: 30)) {
        await wait(200);
        if (page.sentence != null) keys.add(page.sentence!.key);
      }
      // ignore: avoid_print
      print('sentences while the screen was off: ${keys.length}, state ${page.state}');
      expect(keys.length, greaterThanOrEqualTo(3));
    }

    // Paused: Stop is gone from the reader (PLAN 9.4).
    await tester.tap(find.byKey(const Key('play')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(page.state, ReaderState.paused);
  });
}
