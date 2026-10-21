// PLAN steps 5.3 and 5.4 on the phone, against a running desktop with phone sync switched on,
// its Phone dialog open, and a prepared library. The code comes from that dialog:
//   flutter test integration_test/desktop_sync_test.dart --no-uninstall \
//     --dart-define=CODE=XXXX-XXXX-XXXX --dart-define=DESKTOP=<computer name>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/main.dart' as app;

const code = String.fromEnvironment('CODE');
const desktop = String.fromEnvironment('DESKTOP');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('finds the desktop, pairs with its code and fetches only what is missing', (tester) async {
    expect(code, isNotEmpty, reason: 'pass --dart-define=CODE=…');
    // Start from nothing on the phone, so what is read was downloaded, not pushed.
    final library = await Library.open();
    if (await library.root.exists()) await library.root.delete(recursive: true);

    Future<void> waitFor(Finder finder, {int seconds = 30}) async {
      for (var i = 0; i < seconds * 10 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }

    Future<String> status() async => tester.widget<Text>(find.byKey(const Key('desktop-status'))).data!;

    await app.main();
    await waitFor(find.byTooltip('Desktops'));
    await tester.tap(find.byTooltip('Desktops'));
    final heard = Stopwatch()..start();
    await waitFor(find.byKey(const Key('found-$desktop')));
    // ignore: avoid_print
    print('heard the desktop after ${heard.elapsedMilliseconds} ms');

    // A wrong code is refused before anything is sent.
    await tester.tap(find.byKey(const Key('found-$desktop')));
    await waitFor(find.byKey(const Key('code')));
    final wrong = code.replaceFirstMapped(RegExp('^.'), (m) => m[0] == 'A' ? 'B' : 'A');
    await tester.enterText(find.byKey(const Key('code')), wrong);
    await tester.pump();
    await tester.tap(find.byKey(const Key('pair')));
    await waitFor(find.textContaining('not the code'));

    await tester.tap(find.byKey(const Key('found-$desktop')));
    await waitFor(find.byKey(const Key('code')));
    await tester.enterText(find.byKey(const Key('code')), code);
    await tester.pump();
    await tester.tap(find.byKey(const Key('pair')));
    await waitFor(find.textContaining('Paired with'));

    final sync = find.byKey(const Key('sync-$desktop'));
    await tester.tap(sync);
    await waitFor(find.textContaining('documents from'), seconds: 120);
    // ignore: avoid_print
    print('first sync: ${await status()}');

    // Every file is here at the desktop's size: their total is the manifest's.
    final documents = await library.documents();
    expect(documents, isNotEmpty);
    for (final document in documents) {
      final files = document.dir.listSync(recursive: true).whereType<File>();
      final total = files
          .where((f) => !f.path.contains('${Platform.pathSeparator}state'))
          .fold<int>(0, (n, f) => n + (f.path.endsWith('manifest.json') ? 0 : f.lengthSync()));
      expect(total, document.manifest.bytes, reason: document.manifest.name);
    }

    await tester.tap(sync);
    await waitFor(find.textContaining('is here already'), seconds: 60);
  });
}
