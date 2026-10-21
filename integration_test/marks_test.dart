// PLAN M2 on the phone: select text, choose a kind and a colour, tap a mark to comment on it, and
// see all twelve kinds and colours on the right letters, also where marks overlap. Needs the
// prepared sample.pdf. Prints SHOT lines at moments worth a screenshot.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfreader/main.dart' as app;
import 'package:pdfreader/reader_page.dart';
import 'package:pdfreader/shared/notes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('selects, marks, comments, and paints every kind and colour', (tester) async {
    final support = (await getApplicationSupportDirectory()).path;
    for (final name in ['progress.json', 'settings.json']) {
      final file = File('$support/$name');
      if (await file.exists()) await file.delete();
    }
    final notesDir = Directory('$support/notes');
    if (await notesDir.exists()) await notesDir.delete(recursive: true);

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

    await app.main();
    await waitFor(() => find.text('sample.pdf').evaluate().isNotEmpty);
    await tester.tap(find.text('sample.pdf'));
    await waitFor(() => find.byType(ReaderPage).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 3));
    final page = tester.state<ReaderPageState>(find.byType(ReaderPage));
    final utterances = await tester.runAsync(() => page.utterancesOf(1)) ?? [];
    // The body paragraph's words, to press on: "Dieser Text prüft, ob das Programm ..."
    final words = utterances.firstWhere((u) => u.text.startsWith('Dieser Text')).words;
    Offset at(int word) => page.globalCenterOf(1, words[word].ranges)!;
    // The page's glyph boxes load on first use; asking once starts it.
    await waitFor(
      () => page.globalCenterOf(1, words[0].ranges) != null,
      reason: 'the first word is on screen',
    );

    // 1. A long press selects a word and shows the menu; one tap on a colour marks it.
    await tester.longPressAt(at(0));
    await tester.pump(const Duration(milliseconds: 500));
    await waitFor(
      () => find.byKey(const Key('color-green')).evaluate().isNotEmpty,
      reason: 'the menu appears',
    );
    await shot('menu');
    await tester.tap(find.byKey(const Key('color-green')));
    await waitFor(() => page.marks.length == 1, seconds: 10, reason: 'one mark');
    expect(page.marks.single.text, 'Dieser');
    expect((page.marks.single.kind, page.marks.single.color), (MarkKind.highlight, HighlightColor.green));

    // 2. The kind stays selected: choose underline once, and the next mark is one too.
    await tester.longPressAt(at(1));
    await waitFor(() => find.byKey(const Key('kind-underline')).evaluate().isNotEmpty);
    await tester.tap(find.byKey(const Key('kind-underline')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('color-red')));
    await waitFor(() => page.marks.length == 2, seconds: 10);
    expect(page.marks.last.kind, MarkKind.underline);
    await tester.longPressAt(at(2));
    await waitFor(() => find.byKey(const Key('color-blue')).evaluate().isNotEmpty);
    await tester.tap(find.byKey(const Key('color-blue')));
    await waitFor(() => page.marks.length == 3, seconds: 10);
    expect(page.marks.last.kind, MarkKind.underline, reason: 'the kind is kept for the next mark');

    // 3. A tap on a mark opens its comment, which is saved.
    await tester.tapAt(at(0));
    final comment = find.byKey(Key('comment-${page.marks.first.id}'));
    await waitFor(() => comment.evaluate().isNotEmpty, reason: 'a tap on a mark opens its card');
    await tester.enterText(comment, 'A comment, ä ö ü');
    await tester.pump(const Duration(seconds: 1));
    expect(page.marks.first.comment, 'A comment, ä ö ü');
    await tester.tapAt(const Offset(200, 80));
    await tester.pumpAndSettle();

    // 4. All twelve kinds and colours, and overlaps: marks over words 3 to 14, then one over several.
    // Words of the first paragraph's sentences, which are on screen at the top of the page.
    final more = [for (final u in utterances.where((u) => u.role.name == 'main').take(3)) ...u.words];
    var n = 3;
    for (final kind in MarkKind.values) {
      for (final color in HighlightColor.values) {
        await tester.runAsync(() => page.addMarkFor(1, more[n].ranges.first, kind, color));
        n++;
      }
    }
    // A strike-through over the first words that already have a highlight, underline and fill.
    await tester.runAsync(
      () => page.addMarkFor(
        1,
        (words[0].ranges.first.$1, words[3].ranges.last.$2),
        MarkKind.strike,
        HighlightColor.yellow,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await shot('twelve');

    // 5. Written in the desktop's format: parsed and written again, byte for byte.
    await tester.pump(const Duration(seconds: 1));
    final files = notesDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    expect(files, hasLength(1));
    final written = files.single.readAsStringSync();
    expect(encodeNotes(parseNotes(jsonDecode(written))!), written);
    expect(parseNotes(jsonDecode(written))!.annotations, hasLength(16));
    // ignore: avoid_print
    print('NOTES ${files.single.path} ${written.length} bytes');

    // 6. In the reading view: the same marks, and a selection there makes a mark too.
    await tester.tap(find.byKey(const Key('toggle-reading')));
    await tester.pump(const Duration(seconds: 2));
    await shot('reading-marks');
    final before = page.marks.length;
    final target = utterances.firstWhere((u) => u.text.startsWith('Die Verarbeitung')).words;
    await tester.longPressAt(page.globalCenterOf(1, target[1].ranges)!);
    await waitFor(
      () => find.byKey(const Key('color-yellow')).evaluate().isNotEmpty,
      reason: 'the menu in the reading view',
    );
    await tester.tap(find.byKey(const Key('color-yellow')));
    await waitFor(() => page.marks.length == before + 1, seconds: 10, reason: 'a mark from the reading view');
    expect(page.marks.last.text, 'Verarbeitung');
    await shot('reading-marked');

    // 7. Come back later: the marks are still there.
    await tester.pump(const Duration(seconds: 1));
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('sample.pdf'));
    await waitFor(() => find.byType(ReaderPage).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 3));
    final again = tester.state<ReaderPageState>(find.byType(ReaderPage));
    expect(again.marks, hasLength(17));
    expect(again.marks.first.comment, 'A comment, ä ö ü');
  });
}
