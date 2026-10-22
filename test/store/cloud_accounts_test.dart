import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/sync_store.dart';
import 'package:pdfreader/store/cancellation.dart';
import 'package:pdfreader/store/cloud_accounts.dart';
import 'package:pdfreader/store/webdav_store.dart';

import '../fake_platform.dart';
import '../fake_servers.dart';

Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  late Directory dir;
  late File file;
  late FakeNextcloud nextcloud;

  CloudAccounts accounts({FakeBrowser? browser}) => CloudAccounts(
    file: file,
    box: FakeSecretBox(),
    browser: browser ?? FakeBrowser(onOpen: (url) => nextcloud.approve()),
  );

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('cloud-');
    file = File('${dir.path}/cloud.json');
    nextcloud = await FakeNextcloud.start();
  });
  tearDown(() async {
    await nextcloud.close();
    dir.deleteSync(recursive: true);
  });

  test('starts signed out and without a key', () async {
    final status = await accounts().status();
    expect((status.backend, status.account, status.hasKey), (CloudBackend.none, '', false));
  });

  test('reads a file written while Dropbox was chosen as signed out (desktop ADR 10)', () async {
    file.writeAsStringSync('{"backend":"dropbox","server":"","user":"","secrets":""}');
    expect((await accounts().status()).backend, CloudBackend.none);
    await expectLater(accounts().store(), throwsA(isA<StoreException>()));
  });

  group('Nextcloud', () {
    test('signs in through the browser, keeps the app password only sealed, and opens the store', () async {
      final cloud = accounts();
      final status = await cloud.connectNextcloud(nextcloud.url, Cancellation());
      expect(status.backend, CloudBackend.nextcloud);
      expect(status.account, startsWith('alice at '));
      final onDisk = file.readAsStringSync();
      expect(onDisk, isNot(contains('app-pass')));
      expect(onDisk, isNot(contains('"password"')));
      final store = await cloud.store();
      await store.put('a/b.json', text('hello'));
      expect(await store.get('a/b.json'), text('hello'));
    });

    test('is still signed in after the app is started again', () async {
      await accounts().connectNextcloud(nextcloud.url, Cancellation());
      final again = accounts();
      expect((await again.status()).backend, CloudBackend.nextcloud);
      await (await again.store()).put('x.json', text('1'));
    });

    test('refuses an address that is not https, or not the user’s own network', () async {
      await expectLater(
        accounts().connectNextcloud('http://cloud.example.com', Cancellation()),
        throwsA(predicate((e) => '$e'.contains('address of your Nextcloud'))),
      );
    });

    test('stops when cancelled, and stays signed out', () async {
      final cancel = Cancellation();
      final cloud = accounts(
        browser: FakeBrowser(
          onOpen: (_) => Future<void>.delayed(const Duration(milliseconds: 30), cancel.cancel),
        ),
      );
      await expectLater(cloud.connectNextcloud(nextcloud.url, cancel), throwsA(isA<CancelledException>()));
      expect((await cloud.status()).backend, CloudBackend.none);
    });
  });

  group('the sync key', () {
    test('is kept, sealed, across starts, and never shown back', () async {
      final key = formatSyncKey(newSyncKey());
      final status = await accounts().setKey(key);
      expect(status.hasKey, isTrue);
      expect(file.readAsStringSync(), isNot(contains(key.substring(0, 17))));
      expect(formatSyncKey(await accounts().key()), key);
    });

    test('is checked: text that is not a key is refused and nothing changes', () async {
      final cloud = accounts();
      await expectLater(cloud.setKey('not a key'), throwsA(isA<FormatException>()));
      expect((await cloud.status()).hasKey, isFalse);
    });

    test('is asked for when syncing without one', () async {
      final cloud = accounts();
      await cloud.connectNextcloud(nextcloud.url, Cancellation());
      await expectLater(cloud.key(), throwsA(predicate((e) => '$e'.contains('sync key'))));
    });
  });

  group('signing out', () {
    test('forgets the sign-in and keeps the key, so signing in again finds the same files', () async {
      final cloud = accounts();
      final key = formatSyncKey(newSyncKey());
      await cloud.setKey(key);
      await cloud.connectNextcloud(nextcloud.url, Cancellation());
      final status = await cloud.disconnect();
      expect((status.backend, status.hasKey), (CloudBackend.none, true));
      expect(formatSyncKey(await cloud.key()), key);
      await expectLater(cloud.store(), throwsA(predicate((e) => '$e'.contains('Sign in'))));
    });
  });

  group('damaged or foreign files', () {
    test('a file that is not ours means nothing is connected', () async {
      file.writeAsStringSync('{ nonsense');
      expect((await accounts().status()).backend, CloudBackend.none);
      file.writeAsStringSync(jsonEncode({'backend': 'onedrive', 'secrets': 5}));
      expect((await accounts().status()).backend, CloudBackend.none);
    });

    test('secrets that cannot be opened mean signing in again, not a crash', () async {
      await accounts().connectNextcloud(nextcloud.url, Cancellation());
      final broken = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      broken['secrets'] = 'garbage';
      file.writeAsStringSync(jsonEncode(broken));
      final cloud = accounts();
      expect((await cloud.status()).backend, CloudBackend.nextcloud);
      await expectLater(cloud.store(), throwsA(predicate((e) => '$e'.contains('Sign in'))));
    });
  });
}
