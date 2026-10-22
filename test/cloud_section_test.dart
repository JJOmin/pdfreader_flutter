import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/cloud_section.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/notes_store.dart';
import 'package:pdfreader/store/cloud_accounts.dart';
import 'package:pdfreader/sync_controller.dart';

import 'fake_platform.dart';

void main() {
  late Directory dir;
  late CloudAccounts accounts;
  late SyncController controller;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('section-');
    accounts = CloudAccounts(
      file: File('${dir.path}/cloud.json'),
      box: FakeSecretBox(),
      browser: FakeBrowser(onOpen: (_) {}),
    );
    controller = SyncController(
      accounts: accounts,
      library: Library(Directory('${dir.path}/library')),
      notes: NotesStore(Directory('${dir.path}/notes')),
      device: 'e0' * 16,
      name: () async => 'Test phone',
      metered: () async => false,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [CloudSection(sync: controller)]),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }

  testWidgets('asks for the address and the key when nothing is set up', (tester) async {
    await show(tester);
    expect(find.byKey(const Key('cloud-server')), findsOneWidget);
    expect(find.byKey(const Key('sign-in-nextcloud')), findsOneWidget);
    expect(find.byKey(const Key('cloud-key')), findsOneWidget);
    expect(find.byKey(const Key('sync-now')), findsNothing);
    controller.dispose();
  });
}
