// PLAN step 5.7 on the phone, against a running test desktop (a second app on its own profile,
// named "Test desktop") that has sample.pdf prepared and open. The phases are separated by what the
// desktop does in between; run by hand, in order. Nothing on the phone is deleted: the test adds
// two marks of its own, and `forget` removes the test desktop again, leaving other pairings alone.
//   PHASE=pair    pair with the test desktop, typing CODE from its Phone dialog.
//   PHASE=a       mark two words, comment on one, then sync: the desktop must show both.
//   PHASE=b       sync, expect the desktop's new mark and its edit of the comment, then delete the
//                 desktop's mark on the phone and sync again: the desktop must lose it.
//   PHASE=forget  forget the test desktop.
//   flutter test integration_test/notes_sync_test.dart --no-uninstall \
//     --dart-define=PHASE=a --dart-define=CODE=XXXX-XXXX-XXXX
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfreader/main.dart' as app;
import 'package:pdfreader/reader_page.dart';
import 'package:pdfreader/shared/notes.dart';

const phase = String.fromEnvironment('PHASE');
const code = String.fromEnvironment('CODE');
const desktop = 'Test desktop';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notes sync, phase $phase', (tester) async {
    Future<void> waitFor(bool Function() done, {int seconds = 30, String? reason}) async {
      for (var i = 0; i < seconds * 10 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue, reason: reason);
    }

    Future<ReaderPageState> openSample() async {
      await waitFor(() => find.text('sample.pdf').evaluate().isNotEmpty);
      await tester.tap(find.text('sample.pdf'));
      await waitFor(() => find.byType(ReaderPage).evaluate().isNotEmpty);
      await tester.pump(const Duration(seconds: 3));
      return tester.state<ReaderPageState>(find.byType(ReaderPage));
    }

    Future<void> back() async {
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 2));
    }

    Future<String> sync() async {
      await waitFor(() => find.byTooltip('Desktops').evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('Desktops'));
      final button = find.byKey(const Key('sync-$desktop'));
      await waitFor(() => button.evaluate().isNotEmpty);
      await tester.tap(button);
      bool synced() => find.textContaining(RegExp('documents from|is here already')).evaluate().isNotEmpty;
      for (var i = 0; i < 600 && !synced(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (i % 50 == 49) {
          // ignore: avoid_print
          print('STATUS ${tester.widget<Text>(find.byKey(const Key('desktop-status'))).data}');
        }
      }
      expect(synced(), isTrue, reason: 'sync');
      final status = tester.widget<Text>(find.byKey(const Key('desktop-status'))).data!;
      await back();
      return status;
    }

    await app.main();

    if (phase == 'pair') {
      await waitFor(() => find.byTooltip('Desktops').evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('Desktops'));
      await waitFor(() => find.byKey(const Key('found-$desktop')).evaluate().isNotEmpty);
      await tester.tap(find.byKey(const Key('found-$desktop')));
      await waitFor(() => find.byKey(const Key('code')).evaluate().isNotEmpty);
      await tester.enterText(find.byKey(const Key('code')), code);
      await tester.pump();
      await tester.tap(find.byKey(const Key('pair')));
      await waitFor(() => find.textContaining('Paired with').evaluate().isNotEmpty, reason: 'paired');
    } else if (phase == 'forget') {
      await waitFor(() => find.byTooltip('Desktops').evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('Desktops'));
      await waitFor(() => find.byTooltip('Forget $desktop').evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('Forget $desktop'));
      await waitFor(() => find.byTooltip('Forget $desktop').evaluate().isEmpty);
    } else if (phase == 'a') {
      final page = await openSample();
      final words = (await tester.runAsync(() => page.utterancesOf(1)))!
          .firstWhere((u) => u.text.startsWith('Dieser Text'))
          .words;
      await tester.runAsync(
        () => page.addMarkFor(1, words[0].ranges.first, MarkKind.highlight, HighlightColor.green),
      );
      await tester.runAsync(
        () => page.addMarkFor(1, words[2].ranges.first, MarkKind.underline, HighlightColor.red),
      );
      // A mark holds the word without its punctuation: "prüft", not "prüft,".
      final mine = page.marks.where((a) => a.text == words[0].text || a.text == words[2].text).toList();
      expect(mine, hasLength(2));
      page.setCommentFor(page.marks.firstWhere((a) => a.text == 'Dieser').id, 'comment from the phone');
      await tester.pump(const Duration(seconds: 1));
      await back();
      // ignore: avoid_print
      print('SYNC ${await sync()}');
    } else if (phase == 'b') {
      // ignore: avoid_print
      print('SYNC ${await sync()}');
      final page = await openSample();
      // ignore: avoid_print
      print('MARKS ${[for (final a in page.marks) '${a.text}|${a.comment}']}');
      expect(
        page.marks.firstWhere((a) => a.text == 'Dieser').comment,
        'edited on the desktop',
        reason: 'the desktop’s edit reached the phone',
      );
      final fromDesktop = page.marks.where((a) => a.text == 'Programm').toList();
      expect(fromDesktop, isNotEmpty, reason: 'the desktop’s own mark reached the phone');
      // Deleted here: the desktop must lose it, and not bring it back on its next sync.
      page.deleteMarkFor(fromDesktop.first.id);
      await tester.pump(const Duration(seconds: 1));
      await back();
      // ignore: avoid_print
      print('SYNC ${await sync()}');
    }
  });
}
