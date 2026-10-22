import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/document_access.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/main.dart';
import 'package:pdfreader/notes_store.dart';
import 'package:pdfreader/store/cloud_accounts.dart';
import 'package:pdfreader/sync_controller.dart';

import 'fake_platform.dart';

class _CancelledPicker extends DocumentAccess {
  int calls = 0;

  @override
  Future<OpenedDocument?> pickPdf() async {
    calls++;
    return null;
  }
}

void main() {
  testWidgets('starts with an open button and stays empty when the picker is cancelled', (tester) async {
    final picker = _CancelledPicker();
    await tester.pumpWidget(PdfReaderApp(documents: picker));
    await tester.tap(find.widgetWithText(FilledButton, 'Open a PDF'));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('PDF Reader'), findsOneWidget);
  });

  testWidgets('shows the sync icon in its state, and a pull to refresh asks for a full sync', (tester) async {
    final dir = Directory.systemTemp.createTempSync('home-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sync = SyncController(
      accounts: CloudAccounts(
        file: File('${dir.path}/cloud.json'),
        box: FakeSecretBox(),
        browser: FakeBrowser(onOpen: (_) {}),
      ),
      library: Library(Directory('${dir.path}/library')),
      notes: NotesStore(Directory('${dir.path}/notes')),
      device: 'e0' * 16,
      name: () async => 'Test phone',
      metered: () async => false,
    );
    await tester.pumpWidget(PdfReaderApp(documents: _CancelledPicker(), sync: sync));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.byKey(const Key('sync-off')), findsOneWidget);
    expect(find.byTooltip('Sync: not set up'), findsOneWidget);
    // Nothing is signed in, so the pull ends at once and the screen stays usable.
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    // The file reads of the pull are real I/O, which the test's clock does not wait for.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Open a PDF'), findsOneWidget);
    // The poll's timer must be gone before the test ends.
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });
}
