// PLAN steps 6.3 and 6.5 on the phone, through the Cloud screen, against a stand-in Nextcloud that
// the desktop's own engine filled and that runs on the PC (see the desktop's repo, a throwaway test
// serving it). Real: the phone's network stack, the Keystore, the screen, the files. The browser is
// a stand-in, since the stand-in "user" approves by itself. Everything is in temporary folders, so
// the phone's own documents, marks and sign-ins are not touched.
//   flutter test integration_test/cloud_test.dart --no-uninstall \
//     --dart-define=SERVER=http://192.168.1.198:8099 --dart-define=KEY=xxxxxxxx-xxxxxxxx-...
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfreader/cloud_section.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/notes_store.dart';
import 'package:pdfreader/platform_secrets.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfreader/store/cloud_accounts.dart';
import 'package:pdfreader/store/cloud_catalog.dart';
import 'package:pdfreader/sync_controller.dart';

const server = String.fromEnvironment('SERVER');
const key = String.fromEnvironment('KEY');

/// The user's browser: nothing opens, the stand-in server approves after a moment.
class _NoBrowser implements Browser {
  final opened = <Uri>[];

  @override
  Future<void> open(Uri url) async => opened.add(url);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signs in, downloads a document the desktop sent, and exchanges marks', (tester) async {
    expect(server, isNotEmpty, reason: 'pass --dart-define=SERVER=…');
    final temp = Directory.systemTemp.createTempSync('cloud-test-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final browser = _NoBrowser();
    final accounts = CloudAccounts(
      file: File('${temp.path}/cloud.json'),
      box: KeystoreSecretBox(),
      browser: browser,
    );
    final library = Library(Directory('${temp.path}/library'));
    final notes = NotesStore(Directory('${temp.path}/notes'));

    Future<void> waitFor(bool Function() done, {int seconds = 60, String? reason}) async {
      for (var i = 0; i < seconds * 10 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue, reason: reason);
    }

    // The line is gone while something runs, and comes back with its result.
    String status() {
      final line = find.byKey(const Key('cloud-status'));
      return line.evaluate().isEmpty ? '' : tester.widget<Text>(line).data!;
    }

    final controller = SyncController(
      accounts: accounts,
      library: library,
      notes: notes,
      device: 'e0' * 16,
      catalogFile: CloudCatalog(File('${temp.path}/cloud-catalog.json')),
    );
    // The Nextcloud part of the Sync screen on its own: the screen's other part listens for desktops,
    // and the documents are listed on the home screen (tested in test/library_list_test.dart).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [CloudSection(sync: controller)]),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Sign in: the address, then the browser that the stand-in user approves.
    await tester.enterText(find.byKey(const Key('cloud-server')), server);
    await tester.tap(find.byKey(const Key('sign-in-nextcloud')));
    await waitFor(() => find.textContaining('Signed in as alice').evaluate().isNotEmpty, reason: 'signed in');
    expect(browser.opened.single.toString(), startsWith('$server/login/v2/flow/'));
    // The app password is only on the phone, sealed by the Keystore.
    final saved = File('${temp.path}/cloud.json').readAsStringSync();
    expect(saved, isNot(contains('app-pass')));

    // The key the desktop shows.
    await tester.enterText(find.byKey(const Key('cloud-key')), key);
    await tester.tap(find.byKey(const Key('save-key')));
    await waitFor(() => controller.cloud.isNotEmpty, reason: 'the document is listed: ${status()}');
    expect(controller.cloud.single.name, 'sample.pdf');
    expect(controller.cloud.single.pages, 2);

    // Download it, as a tap on it in the library does.
    final watch = Stopwatch()..start();
    await tester.runAsync(() => controller.download(controller.cloud.single));
    // ignore: avoid_print
    print('DOWNLOAD took ${watch.elapsedMilliseconds} ms');
    final docs = await tester.runAsync(library.documents) ?? [];
    expect(docs, hasLength(1));
    final doc = docs.single;
    expect(sha256.convert(await tester.runAsync(doc.pdf.readAsBytes) ?? []).toString(), doc.manifest.docId);
    final audio = Directory('${doc.dir.path}/audio').listSync().whereType<File>().toList();
    expect(audio, hasLength(17));
    expect(String.fromCharCodes(audio.first.readAsBytesSync().take(4)), 'OggS');

    // First sync: the desktop's place and notes come down.
    await tester.tap(find.byKey(const Key('sync-now')));
    await waitFor(
      () => find.byKey(const Key('cloud-status')).evaluate().isNotEmpty && status().contains('marks changed'),
      reason: status(),
    );
    final got = await tester.runAsync(() => notes.load(doc.manifest.docId));
    expect(got!.notes, 'Notes from the desktop');
    expect(got.annotations.firstWhere((a) => a.id == 'd1').comment, 'desktop comment');
    expect(File('${doc.dir.path}/state/${'d' * 32}.json').existsSync(), isTrue);

    // A mark made on the phone goes up with the next sync.
    final mark = Annotation(
      id: 'phone-${DateTime.now().millisecondsSinceEpoch}',
      page: 1,
      start: 45,
      end: 50,
      text: 'prüft',
      quote: 'prüft',
      kind: MarkKind.underline,
      color: HighlightColor.red,
      comment: 'from the phone',
      created: '2026-10-21T00:00:00.000Z',
      updated: DateTime.now().millisecondsSinceEpoch,
    );
    await tester.runAsync(
      () => notes.save(
        doc.manifest.docId,
        NotesFile(
          notes: got.notes,
          annotations: [...got.annotations, mark],
          notesUpdated: got.notesUpdated,
          removed: got.removed,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('sync-now')));
    // The first sync said "marks changed"; this one only sends, so it ends as up to date.
    // The bar shows while it runs; a moment for it to appear, then until it is gone.
    await tester.pump(const Duration(milliseconds: 300));
    await waitFor(
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      reason: 'the second sync ends',
    );
    // ignore: avoid_print
    print('SYNC2 ${status()}');
    expect(status(), 'Everything is up to date.');
    // Let the stand-in's reporter see the upload.
    await tester.pump(const Duration(seconds: 3));
    // ignore: avoid_print
    print(
      'PHONE-MARK-SENT ${jsonEncode([for (final a in (await notes.load(doc.manifest.docId)).annotations) a.id])}',
    );

    // Signed out, the secrets are gone but the files are kept; the key stays.
    await tester.tap(find.byKey(const Key('sign-out')));
    await waitFor(() => find.byKey(const Key('sign-in-nextcloud')).evaluate().isNotEmpty);
    expect(File('${doc.dir.path}/manifest.json').existsSync(), isTrue);
    expect((await accounts.status()).hasKey, isTrue);
  });
}
