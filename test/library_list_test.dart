import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/library_list.dart';
import 'package:pdfreader/shared/inbox.dart';
import 'package:pdfreader/shared/library_view.dart';
import 'package:pdfreader/shared/sync.dart';

Manifest doc(String id, String name, {num updated = 1, int bytes = 2 * 1024 * 1024}) =>
    Manifest.allVoiced(docId: id * 64, name: name, pages: 2, sentences: 10, bytes: bytes, updated: updated);

void main() {
  final onPhone = doc('a', 'On.pdf');
  final stale = doc('b', 'Stale.pdf');
  final cloudOnly = doc('c', 'Cloud.pdf');
  final loading = doc('d', 'Loading.pdf');

  final opened = <String>[];
  final downloaded = <String>[];
  final removed = <String>[];
  final offered = <String>[];

  Future<void> show(WidgetTester tester, {Map<String, double?> downloading = const {}}) async {
    opened.clear();
    downloaded.clear();
    removed.clear();
    offered.clear();
    final entries = libraryEntries(
      local: [onPhone, stale],
      cloud: [onPhone, doc('b', 'Stale.pdf', updated: 2), cloudOnly, loading],
      downloading: downloading,
      offers: [PendingOffer(Offer(docId: 'e' * 64, name: 'Sent.pdf', bytes: 1024 * 1024, sent: 2), 'Mac')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LibraryList(
              entries: entries,
              onOpen: (e) => opened.add(e.manifest.name),
              onDownload: (e) => downloaded.add(e.manifest.name),
              onRemove: (e) => removed.add(e.manifest.name),
              onOffer: (e) => offered.add(e.manifest.name),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows each document with its state and the space used', (tester) async {
    await show(tester, downloading: {loading.docId: 0.4});
    expect(find.text('On this phone · 2 MB'), findsOneWidget);
    expect(find.text('Update available · 2 MB'), findsOneWidget);
    expect(find.text('In the cloud · 2 MB'), findsOneWidget);
    expect(find.text('Downloading 40 %'), findsOneWidget);
    // Two documents are on the phone; the cloud's are not counted.
    expect(find.text('4 MB on this phone'), findsOneWidget);
  });

  testWidgets('filters to what is on the phone, or only in the cloud', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('filter-onPhone')));
    await tester.pump();
    expect(find.text('On.pdf'), findsOneWidget);
    expect(find.text('Stale.pdf'), findsOneWidget);
    expect(find.text('Cloud.pdf'), findsNothing);
    await tester.tap(find.byKey(const Key('filter-cloudOnly')));
    await tester.pump();
    expect(find.text('On.pdf'), findsNothing);
    expect(find.text('Cloud.pdf'), findsOneWidget);
    expect(find.text('Loading.pdf'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter-all')));
    await tester.pump();
    expect(find.text('On.pdf'), findsOneWidget);
    expect(find.text('Cloud.pdf'), findsOneWidget);
  });

  testWidgets('a tap opens a document that is here and downloads one that is only in the cloud', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('On.pdf'));
    await tester.tap(find.text('Cloud.pdf'));
    expect(opened, ['On.pdf']);
    expect(downloaded, ['Cloud.pdf']);
  });

  testWidgets('the menu offers Open, Remove from this phone and, for an update, Download update', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(Key('menu-${stale.docId}')));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Download update'), findsOneWidget);
    await tester.tap(find.text('Remove from this phone'));
    await tester.pumpAndSettle();
    expect(removed, ['Stale.pdf']);
    // A document in the cloud can only be downloaded.
    await tester.tap(find.byKey(Key('menu-${cloudOnly.docId}')));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsNothing);
    expect(find.text('Remove from this phone'), findsNothing);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(downloaded, ['Cloud.pdf']);
  });

  testWidgets('has no menu and no tap while a document downloads', (tester) async {
    await show(tester, downloading: {loading.docId: null});
    expect(find.text('Downloading…'), findsOneWidget);
    expect(find.byKey(Key('menu-${loading.docId}')), findsNothing);
    await tester.tap(find.text('Loading.pdf'));
    expect(downloaded, isEmpty);
  });

  testWidgets('shows an offered document with who sent it, and a tap asks about it', (tester) async {
    await show(tester);
    expect(find.text('Offered by Mac · 1 MB'), findsOneWidget);
    expect(find.byKey(Key('menu-${'e' * 64}')), findsNothing);
    await tester.tap(find.text('Sent.pdf'));
    expect(offered, ['Sent.pdf']);
    expect(downloaded, isEmpty);
  });

  testWidgets('says how many pages have audio while the computer is still making it', (tester) async {
    Manifest partial(List<int> voiced) => Manifest(
      docId: 'p' * 64,
      name: 'Part.pdf',
      pages: 4,
      sentences: 1,
      bytes: 1024,
      updated: 1,
      voiced: voiced,
    );
    for (final (voiced, text) in [
      (<int>[1], 'On this phone · 1 KB · audio 1 of 4 pages'),
      (<int>[], 'On this phone · 1 KB · no audio yet'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryList(
              entries: libraryEntries(local: [partial(voiced)], cloud: []),
              onOpen: (_) {},
              onDownload: (_) {},
              onRemove: (_) {},
              onOffer: (_) {},
            ),
          ),
        ),
      );
      expect(find.text(text), findsOneWidget);
    }
  });
}
