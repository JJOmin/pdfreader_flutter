// PLAN M18 on the phone, as screenshots in build/screens/: a PDF handed over by another app, the
// speed reader with a paragraph over a page break, the mode switch, the selection menu, the comment
// sheet, the notes sheet's search, the player in a full, a short and a wide window, and Home with the
// kept PDF. Uses the app's real stores; nothing needs to be pushed to the phone first.
//   flutter drive --driver=test_driver/screens.dart --target=integration_test/screens_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfreader/document_access.dart';
import 'package:pdfreader/favourites_store.dart';
import 'package:pdfreader/kept_store.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/main.dart';
import 'package:pdfreader/notes_store.dart';
import 'package:pdfreader/phone_voice.dart';
import 'package:pdfreader/places.dart';
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/reader_page.dart';
import 'package:pdfreader/app_settings_store.dart';

import 'pdfs.dart';

/// Hands the app one PDF, as "Open with" in another app does.
class HandedOver extends DocumentAccess {
  HandedOver(this.document);

  OpenedDocument? document;

  @override
  Future<OpenedDocument?> takeIncoming() async {
    final out = document;
    document = null;
    return out;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the screens of improvement round 2', (tester) async {
    Future<void> wait(int ms) => tester.pump(Duration(milliseconds: ms));
    Future<void> waitFor(bool Function() done, {int seconds = 30, String? reason}) async {
      for (var i = 0; i < seconds * 10 && !done(); i++) {
        await wait(100);
      }
      expect(done(), isTrue, reason: reason);
    }

    var converted = false;
    Future<void> shot(String name) async {
      await wait(800);
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await binding.takeScreenshot(name);
    }

    await pdfrxFlutterInitialize();
    final support = await getApplicationSupportDirectory();
    final voice = PlatformPhoneVoice();
    await tester.pumpWidget(
      PdfReaderApp(
        documents: HandedOver(
          OpenedDocument(
            uri: 'content://test/study.pdf',
            name: 'Reading study.pdf',
            data: longPdf(12, runOn: true),
          ),
        ),
        library: await Library.open(),
        phoneVoice: voice,
        places: await Places.open(null),
        notesStore: await NotesStore.open(),
        favourites: FavouritesStore.inMemory(),
        appSettings: AppSettingsStore.inMemory(),
        kept: await KeptStore.open(Directory(support.path)),
      ),
    );
    final play = find.byKey(const Key('play'));
    await waitFor(() => play.evaluate().isNotEmpty && tester.widget<IconButton>(play).onPressed != null);
    final page = tester.state<ReaderPageState>(find.byType(ReaderPage));
    expect(page.reading, isTrue, reason: 'a PDF from another app opens in the speed reader');

    // The speed reader: page 5's last sentence runs over the break, page 6's number in the margin.
    await page.showPageForTest(5, 0.85);
    await shot('speed-reader-page-break');

    // The selection menu: Comment in the comment colour, the two favourites, More.
    final words = (await page.utterancesOf(5)).first.words;
    await page.showPageForTest(5, 0);
    await wait(500);
    await tester.longPressAt(page.globalCenterOf(5, words[1].ranges)!);
    await waitFor(() => find.byKey(const Key('more-looks')).evaluate().isNotEmpty, reason: 'the menu');
    await shot('menu');
    await tester.tap(find.byKey(const Key('more-looks')));
    await shot('menu-more');
    await tester.tapAt(const Offset(180, 120));
    await wait(500);

    // The comment sheet: the keyboard up at once, and the looks to choose from.
    await tester.longPressAt(page.globalCenterOf(5, words[3].ranges)!);
    await waitFor(() => find.byKey(const Key('comment-selection')).evaluate().isNotEmpty);
    await tester.tap(find.byKey(const Key('comment-selection')));
    await waitFor(() => find.byKey(const Key('quick-comment')).evaluate().isNotEmpty);
    await wait(1200);
    await shot('comment-sheet');
    await tester.enterText(find.byKey(const Key('quick-comment')), 'Ask about the sample size');
    await wait(800);
    await tester.tap(find.byKey(const Key('save-comment')));
    await waitFor(() => page.marks.isNotEmpty, reason: 'the comment is saved');

    // The notes sheet, searching the comments.
    await tester.tap(find.byKey(const Key('notes')));
    await waitFor(() => find.byKey(const Key('comment-search')).evaluate().isNotEmpty);
    await tester.enterText(find.byKey(const Key('comment-search')), 'sample');
    await shot('notes-search');
    await tester.pageBack();
    await wait(800);

    // The player, from the mode switch, reading; then in split screen, and in a wide window.
    await tester.tap(find.byKey(const Key('mode-player')));
    await wait(800);
    await tester.tap(find.byKey(const Key('player-play')));
    await waitFor(() => page.state == ReaderState.playing && page.word >= 1);
    await shot('player');
    tester.view.physicalSize = const Size(1080, 1170);
    await shot('player-split-screen');
    tester.view.physicalSize = const Size(2400, 1080);
    await shot('player-wide');
    tester.view.resetPhysicalSize();
    await wait(500);

    // From the player into the pages, the voice going on.
    await tester.tap(find.byKey(const Key('player-mode-pages')));
    await wait(1500);
    expect(page.reading, isFalse);
    expect(page.state, ReaderState.playing);
    await shot('pages-reading');
    await tester.tap(find.byKey(const Key('play')));

    // Home keeps the PDF that came from outside, under Continue reading.
    await tester.pageBack();
    await wait(1500);
    expect(find.text('Reading study.pdf'), findsWidgets);
    await shot('home-kept');
    await tester.tap(find.text('Settings'));
    await wait(800);
    await tester.tap(find.byKey(const Key('settings-marks')));
    await shot('settings-marks');
  });
}
