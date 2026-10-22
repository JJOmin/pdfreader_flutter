// The phone's automatic sync as the app sees it (PLAN 7.3): the icon's state, one sync at a time, and
// the timing of the automatic ones with a clock the test moves, against a stand-in Nextcloud.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/notes_store.dart';
import 'package:pdfreader/shared/sync_state.dart';
import 'package:pdfreader/shared/sync_store.dart';
import 'package:pdfreader/store/cancellation.dart';
import 'package:pdfreader/store/cloud_accounts.dart';
import 'package:pdfreader/store/memo_file.dart';
import 'package:pdfreader/sync_controller.dart';

import 'fake_platform.dart';
import 'fake_servers.dart';
import 'fake_timers.dart';

void main() {
  late Directory dir;
  late FakeNextcloud nextcloud;
  late FakeTimers timers;
  late CloudAccounts accounts;
  late SyncController controller;

  Future<void> waitFor(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
  }

  Future<void> signIn() async {
    await accounts.connectNextcloud(nextcloud.url, Cancellation());
    await accounts.setKey(formatSyncKey(newSyncKey()));
    await controller.forget();
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('controller-');
    nextcloud = await FakeNextcloud.start();
    timers = FakeTimers();
    accounts = CloudAccounts(
      file: File('${dir.path}/cloud.json'),
      box: FakeSecretBox(),
      browser: FakeBrowser(onOpen: (url) => nextcloud.approve()),
    );
    controller = SyncController(
      accounts: accounts,
      library: Library(Directory('${dir.path}/library')),
      notes: NotesStore(Directory('${dir.path}/notes')),
      device: 'e0' * 16,
      memoFile: MemoFile(File('${dir.path}/sync-memo.json')),
      timers: timers,
      name: () async => 'Test phone',
    );
  });
  tearDown(() async {
    controller.dispose();
    await nextcloud.close();
    dir.deleteSync(recursive: true);
  });

  test('is off until an account and a key are set, and syncs nothing', () async {
    await controller.refreshStatus();
    expect(controller.state, SyncState.off);
    expect(await controller.sync(), isNull);
  });

  test(
    'is done after a sync, pending after the phone changed something, done again after the next',
    () async {
      await signIn();
      expect(controller.state, SyncState.done);
      await timers.advance(1);
      controller.ownChanged(place: true);
      expect(controller.state, SyncState.pending);
      expect(await controller.sync(), isNotNull);
      expect(controller.state, SyncState.done);
      expect(controller.syncs, 1);
    },
  );

  test('says syncing while it runs', () async {
    await signIn();
    final states = <SyncState>[];
    controller.addListener(() => states.add(controller.state));
    await controller.sync();
    expect(states, contains(SyncState.syncing));
    expect(states.last, SyncState.done);
  });

  test('is pending after a sync that failed, and keeps the reason', () async {
    await signIn();
    await nextcloud.close();
    await expectLater(controller.sync(), throwsA(anything));
    expect(controller.state, SyncState.pending);
    expect(controller.lastError, isNotNull);
  });

  test('syncs when the app comes to the front and every 30 seconds, and stops in the background', () async {
    await signIn();
    controller.resume();
    await timers.advance(0);
    await waitFor(() => controller.syncs == 1);
    await timers.advance(30);
    await waitFor(() => controller.syncs == 2);
    await controller.pause();
    final before = controller.syncs;
    await timers.advance(120);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(controller.syncs, before);
  });

  test('sends a mark 5 seconds after it was made', () async {
    await signIn();
    controller.resume();
    await waitFor(() => controller.syncs == 1);
    controller.ownChanged();
    await timers.advance(4);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(controller.syncs, 1);
    await timers.advance(1);
    await waitFor(() => controller.syncs == 2);
  });

  test('runs one thing at a time', () async {
    final order = <String>[];
    final first = controller.exclusive(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      order.add('first');
    });
    final second = controller.exclusive(() async => order.add('second'));
    await Future.wait([first, second]);
    expect(order, ['first', 'second']);
  });
}
