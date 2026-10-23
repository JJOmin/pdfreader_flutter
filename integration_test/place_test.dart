// PLAN steps 4.1 and 5.6 on the phone, against a running desktop that this phone is paired with
// (run desktop_sync_test.dart first) and that prepared sample.pdf.
//   PHASE=place: read into page 2, close, reopen (the same page and sentence), then sync.
//   PHASE=offer: sync, then reopen and expect the desktop's newer place to be offered.
//   flutter test integration_test/place_test.dart --no-uninstall \
//     --dart-define=PHASE=place --dart-define=DESKTOP=<computer name>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'finders.dart';

import 'package:pdfreader/main.dart' as app;
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/reader_page.dart';

const phase = String.fromEnvironment('PHASE');
const desktop = String.fromEnvironment('DESKTOP');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('place $phase', (tester) async {
    Future<void> waitFor(bool Function() done, {int seconds = 30, String? reason}) async {
      for (var i = 0; i < seconds * 10 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue, reason: reason);
    }

    final play = find.byKey(const Key('play'));
    Future<ReaderPageState> openSample() async {
      await waitFor(() => find.text('sample.pdf').evaluate().isNotEmpty);
      await tester.tap(sampleTile);
      await waitFor(() => play.evaluate().isNotEmpty && tester.widget<IconButton>(play).onPressed != null);
      // The saved place is shown after the first layout.
      await tester.pump(const Duration(seconds: 1));
      return tester.state<ReaderPageState>(find.byType(ReaderPage));
    }

    Future<void> back() => closeDocument(tester);

    Future<void> sync() async {
      await waitFor(() => syncButton.evaluate().isNotEmpty);
      await tester.tap(syncButton);
      final button = find.byKey(const Key('sync-$desktop'));
      await waitFor(() => button.evaluate().isNotEmpty);
      await tester.tap(button);
      await waitFor(
        () => find.textContaining(RegExp('documents from|is here already')).evaluate().isNotEmpty,
        seconds: 60,
        reason: 'sync',
      );
      await tester.tap(homeTab);
      await tester.pump(const Duration(seconds: 1));
    }

    await app.main();

    if (phase == 'place') {
      var page = await openSample();
      await tester.tap(play);
      await waitFor(() => page.sentence != null);
      // To the second sentence of page 2.
      for (var i = 0; i < 20 && !(page.sentence!.page == 2); i++) {
        await tester.tap(find.byTooltip('Next sentence'));
        await waitFor(() => page.sentence != null && page.word >= 0, seconds: 10);
      }
      await tester.tap(find.byTooltip('Next sentence'));
      await tester.pump(const Duration(seconds: 2));
      final key = page.sentence!.key;
      // Paused: Stop is gone from the reader (PLAN 9.4).
      await tester.tap(play);
      await tester.pump(const Duration(milliseconds: 600));
      await back();

      page = await openSample();
      expect(page.currentPage, 2, reason: 'the place is kept');
      await tester.tap(play);
      await waitFor(() => page.sentence != null);
      expect(page.sentence!.key, key, reason: 'Play continues at the sentence read last');
      // Paused: Stop is gone from the reader (PLAN 9.4).
      await tester.tap(play);
      await tester.pump(const Duration(milliseconds: 600));
      await back();
      await sync();
      // ignore: avoid_print
      print('PHONE-SENTENCE $key');
    } else {
      await sync();
      final page = await openSample();
      final offer = find.byKey(const Key('place-offer'));
      await waitFor(() => offer.evaluate().isNotEmpty, seconds: 10, reason: 'the desktop’s place is offered');
      expect(find.textContaining('Continue where you stopped on $desktop, page 1?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('place-continue')));
      await waitFor(() => page.currentPage == 1, seconds: 10);
      expect(page.state, ReaderState.idle);
    }
  });
}
