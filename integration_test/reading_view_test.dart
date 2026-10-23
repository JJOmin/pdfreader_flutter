// PLAN M3 on the phone: the reading view reads aloud with the word mark, search finds a word
// across a hyphenated line break in both views, the text settings apply and are kept, and
// switching views keeps the place while the voice goes on. Needs the prepared sample.pdf.
// Prints SHOT lines at moments worth a screenshot.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfreader/main.dart' as app;
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/reader_page.dart';
import 'package:pdfreader/views/reading_view.dart';

import 'finders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the reading view reads, searches and keeps its settings', (tester) async {
    final support = (await getApplicationSupportDirectory()).path;
    for (final name in ['progress.json', 'settings.json']) {
      final file = File('$support/$name');
      if (await file.exists()) await file.delete();
    }

    Future<void> waitFor(bool Function() done, {int seconds = 30, String? reason}) async {
      for (var i = 0; i < seconds * 10 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue, reason: reason);
    }

    Future<void> shot(String name) async {
      // ignore: avoid_print
      print('SHOT $name');
      await tester.pump(const Duration(seconds: 3));
    }

    String count() => tester.widget<Text>(find.byKey(const Key('search-count'))).data!;

    await app.main();
    await waitFor(() => find.text('sample.pdf').evaluate().isNotEmpty);
    await tester.tap(sampleTile);
    final play = find.byKey(const Key('play'));
    await waitFor(() => play.evaluate().isNotEmpty && tester.widget<IconButton>(play).onPressed != null);
    final page = tester.state<ReaderPageState>(find.byType(ReaderPage));

    await tester.tap(find.byKey(const Key('toggle-reading')));
    await waitFor(() => find.byType(ReadingView).evaluate().isNotEmpty);
    await waitFor(() => find.textContaining('Zweispaltiger', findRichText: true).evaluate().isNotEmpty);

    // Reads aloud in the reading view, the word mark moving forward.
    await tester.tap(play);
    await waitFor(() => page.word >= 2, reason: 'the word mark moves');
    final key = page.sentence!.key;
    await shot('reading-view-speaking');

    // Switching to the pages keeps the voice going and the place.
    await tester.tap(find.byKey(const Key('toggle-reading')));
    await tester.pump(const Duration(seconds: 1));
    expect(page.reading, isFalse);
    expect(page.state, ReaderState.playing);
    expect(page.currentPage, page.sentence!.page);
    await tester.tap(find.byKey(const Key('toggle-reading')));
    await tester.pump(const Duration(seconds: 1));
    expect(page.state, ReaderState.playing);
    await tester.tap(find.byKey(const Key('play')));
    await tester.pump(const Duration(milliseconds: 500));
    // ignore: avoid_print
    print('spoke $key, then ${page.state}');

    // Search finds a word across a hyphenated line break, in the reading view and on the pages.
    // Search and the text settings are in the menu (PLAN 9.7).
    await tester.tap(find.byKey(const Key('reader-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('search')), 'Silbentrennung');
    await waitFor(() => count() == '1 / 1', seconds: 10, reason: 'one match across the line break');
    await waitFor(() => page.currentPage == 2, seconds: 5, reason: 'the match on page 2 is shown');
    await shot('reading-view-search');
    await tester.enterText(find.byKey(const Key('search')), 'Spalte');
    await waitFor(() => count().endsWith(' / 4'), seconds: 10, reason: 'four matches of Spalte: ${count()}');
    await tester.tap(find.byTooltip('Next match'));
    await tester.pump();
    expect(count(), startsWith('2 / '));
    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();

    // Text settings: OpenDyslexic on dark, kept for the next document.
    await tester.tap(find.byKey(const Key('reader-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenDyslexic').last);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 150));
    await tester.pumpAndSettle();
    await shot('reading-view-opendyslexic-dark');
    await closeDocument(tester);

    final settings = File('$support/settings.json').readAsStringSync();
    expect(settings, contains('"font":"OpenDyslexic"'));
    expect(settings, contains('"theme":"dark"'));
    // The reading view is remembered with the place.
    await tester.tap(sampleTile);
    await waitFor(
      () => find.byType(ReadingView).evaluate().isNotEmpty,
      reason: 'reopens in the reading view',
    );
  });
}
