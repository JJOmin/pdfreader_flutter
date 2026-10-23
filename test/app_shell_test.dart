import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/document_access.dart';
import 'package:pdfreader/favourites_store.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/main.dart';
import 'package:pdfreader/now_playing.dart';
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/shared/sync.dart';

final docId = 'a' * 64;

void main() {
  testWidgets('the three tabs switch, and a document is put in a new folder and found by its name', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('shell-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final doc = Directory('${dir.path}/library/$docId')..createSync(recursive: true);
    File('${doc.path}/document.pdf').writeAsStringSync('%PDF');
    File('${doc.path}/manifest.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'docId': docId,
        'name': 'Arbeitsvertrag.pdf',
        'pages': 2,
        'sentences': 10,
        'bytes': 1000,
        'updated': 1,
      }),
    );
    final favourites = FavouritesStore.inMemory();
    await tester.pumpWidget(
      PdfReaderApp(
        documents: DocumentAccess(),
        library: Library(Directory('${dir.path}/library')),
        favourites: favourites,
      ),
    );
    // The library is read from disk, which the test's clock does not wait for.
    for (var i = 0; i < 20 && find.text('Arbeitsvertrag.pdf').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    // Never opened: it is new on this phone, and in the whole list.
    expect(find.text('New on this phone'), findsOneWidget);
    expect(find.text('Arbeitsvertrag.pdf'), findsNWidgets(2));

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    // Each topic has a page of its own.
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-reading')));
    await tester.pumpAndSettle();
    expect(find.text('Stop reading at the reference list'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.system);
    await tester.tap(find.byKey(const Key('settings-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(Scaffold).last)).brightness, Brightness.dark);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget, reason: 'the list names the choice');

    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Like a document'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-folder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('folder-name')), 'Verträge');
    await tester.enterText(find.byKey(const Key('folder-notes')), 'Arbeit und Wohnung');
    await tester.tap(find.byKey(const Key('save-folder')));
    await tester.pumpAndSettle();
    expect(favourites.value.folders.single.name, 'Verträge');
    expect(find.byKey(const Key('filter-folder-Verträge')), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('menu-$docId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Folders…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('in-folder-Verträge')));
    await tester.pumpAndSettle();
    expect(favourites.value.foldersOf(docId).single.name, 'Verträge');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('favourites-search')), 'verträge');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Arbeitsvertrag.pdf'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('favourites-search')), 'Miete');
    await tester.pumpAndSettle();
    expect(find.text('Nothing found.'), findsOneWidget);
  });

  testWidgets('the Now Playing bar plays, skips, likes, opens the reader and is swiped away', (tester) async {
    final session = ReadingSession(
      name: 'A very long title of a paper that does not fit on one line of a phone.pdf',
      data: Uint8List(0),
      placeKey: 'library:$docId',
      prepared: LibraryDocument(
        Directory('unused'),
        Manifest.allVoiced(docId: docId, name: 'x.pdf', pages: 1, sentences: 1, bytes: 1, updated: 1),
      ),
    );
    final favourites = FavouritesStore.inMemory();
    var toggled = 0, skipped = 0, opened = 0, closed = 0;
    session
      ..toggle = (() => toggled++)
      ..skip = ((direction) => skipped += direction);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: NowPlayingBar(
            session: session,
            favourites: favourites,
            onOpen: () => opened++,
            onClose: () => closed++,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byKey(const Key('mini-play')));
    expect(toggled, 1);
    session.update(ReaderState.playing);
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byKey(const Key('mini-next')));
    expect(skipped, 1);
    await tester.tap(find.byKey(const Key('mini-like')));
    await tester.pump();
    expect(favourites.value.isLiked(docId), isTrue);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    // One line, shortened.
    expect(tester.widget<Text>(find.textContaining('A very long')).maxLines, 1);
    await tester.tap(find.textContaining('A very long'));
    expect(opened, 1);
    await tester.drag(find.byKey(const Key('now-playing')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  test('a document has audio only when the desktop prepared it and voiced a page', () {
    ReadingSession session([LibraryDocument? prepared]) =>
        ReadingSession(name: 'x.pdf', data: Uint8List(0), placeKey: 'k', prepared: prepared);
    LibraryDocument doc(List<int> voiced) => LibraryDocument(
      Directory('unused'),
      Manifest(docId: docId, name: 'x.pdf', pages: 3, sentences: 1, bytes: 1, updated: 1, voiced: voiced),
    );
    expect(session().hasAudio, isFalse, reason: 'opened from elsewhere, not prepared');
    expect(session(doc(const [])).hasAudio, isFalse, reason: 'the audio is still being made');
    expect(session(doc(const [2])).hasAudio, isTrue);
  });
}
