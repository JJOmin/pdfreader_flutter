// Port of the desktop's tests/unit/webdav.test.ts, against the stand-in of test/fake_servers.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/sync_store.dart';
import 'package:pdfreader/store/cancellation.dart';
import 'package:pdfreader/store/nextcloud_login.dart';
import 'package:pdfreader/store/webdav_store.dart';

import '../fake_servers.dart';
import '../fake_platform.dart';

late FakeNextcloud server;

Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));
WebDavStore store([String password = 'app-pass']) =>
    WebDavStore(nextcloudDavBase(server.url, 'alice'), 'alice', password);

void main() {
  setUp(() async => server = await FakeNextcloud.start());
  tearDown(() => server.close());

  group('parsePropfind', () {
    final dir = Uri.parse('https://cloud.example.com/remote.php/dav/files/alice/PDF%20Reader/');
    String xml(String prefix) {
      final ns = prefix.replaceAll(':', '');
      return '<${prefix}multistatus xmlns${ns.isEmpty ? '' : ':$ns'}="DAV:">'
          '<${prefix}response><${prefix}href>/remote.php/dav/files/alice/PDF%20Reader/</${prefix}href></${prefix}response>'
          '<${prefix}response><${prefix}href>/remote.php/dav/files/alice/PDF%20Reader/abc/</${prefix}href>'
          '<${prefix}propstat><${prefix}prop><${prefix}resourcetype><${prefix}collection/></${prefix}resourcetype></${prefix}prop></${prefix}propstat></${prefix}response>'
          '<${prefix}response><${prefix}href>/remote.php/dav/files/alice/PDF%20Reader/1.json</${prefix}href>'
          '<${prefix}propstat><${prefix}prop><${prefix}getcontentlength>42</${prefix}getcontentlength><${prefix}resourcetype/></${prefix}prop></${prefix}propstat></${prefix}response>'
          '</${prefix}multistatus>';
    }

    List<String> shape(List<RemoteEntry> entries) => [
      for (final e in entries) '${e.name} ${e.folder} ${e.size}',
    ];

    for (final prefix in ['d:', 'D:', '']) {
      test('lists the children and not the folder itself, with prefix "$prefix"', () {
        expect(shape(parsePropfind(xml(prefix), dir)), ['abc true 0', '1.json false 42']);
      });
    }

    test('reads the ETag a server gives, which a journal poll compares', () {
      const xml =
          '<d:multistatus><d:response><d:href>/remote.php/dav/files/alice/PDF%20Reader/devices/x.json</d:href><d:propstat><d:prop><d:getetag>&quot;5f3a&quot;</d:getetag></d:prop></d:propstat></d:response></d:multistatus>';
      expect(parsePropfind(xml, dir).single.etag, '&quot;5f3a&quot;');
      expect(parsePropfind(xml.replaceAll('getetag', 'getlastmodified'), dir).single.etag, isNull);
    });

    test('reads a full address in the href', () {
      const full =
          '<d:multistatus><d:response><d:href>https://cloud.example.com/remote.php/dav/files/alice/PDF%20Reader/x.pack</d:href><d:getcontentlength>7</d:getcontentlength></d:response></d:multistatus>';
      expect(shape(parsePropfind(full, dir)), ['x.pack false 7']);
    });
  });

  group('WebDavStore', () {
    test('stores a file, creating its folders, and reads it back', () async {
      final webdav = store();
      await webdav.put('doc/pages/1.json', text('hello'));
      expect(await webdav.get('doc/pages/1.json'), text('hello'));
      expect(server.folders.toList()..sort(), ['', 'PDF Reader', 'PDF Reader/doc', 'PDF Reader/doc/pages']);
      expect(utf8.decode(server.files['PDF Reader/doc/pages/1.json']!), 'hello');
    });

    test('replaces a file and works with folders that already exist', () async {
      await store().put('doc/a.json', text('one'));
      final second = store();
      await second.put('doc/a.json', text('two'));
      await second.put('doc/b.json', text('three'));
      expect(await second.get('doc/a.json'), text('two'));
    });

    test('answers null for a file that is not there', () async {
      expect(await store().get('doc/none.json'), isNull);
    });

    test('lists folders and files, and nothing for a folder that does not exist', () async {
      final webdav = store();
      await webdav.put('doc/manifest.json', text('12345'));
      await webdav.put('doc/state/ab.json', text('x'));
      final listed = [for (final e in await webdav.list('doc')) '${e.name} ${e.folder} ${e.size}'];
      expect(listed, containsAll(['manifest.json false 5', 'state true 0']));
      expect(
        [for (final e in await webdav.list('doc/state')) '${e.name} ${e.folder} ${e.size}'],
        ['ab.json false 1'],
      );
      expect(await webdav.list('nothing'), isEmpty);
    });

    test('reports a refused password', () async {
      await expectLater(
        store('wrong').put('a.json', text('x')),
        throwsA(predicate((e) => '$e'.contains('401'))),
      );
    });

    test('refuses paths that are not the library’s own', () async {
      final webdav = store();
      await expectLater(webdav.put('../x', text('x')), throwsArgumentError);
      await expectLater(webdav.get('a/../../x'), throwsArgumentError);
      await expectLater(webdav.list('..'), throwsArgumentError);
    });

    test('carries a file the size of a page’s audio pack, byte for byte', () async {
      final big = Uint8List.fromList([for (var i = 0; i < 600000; i++) i % 251]);
      final webdav = store();
      await webdav.put('doc/audio/1.pack', big);
      expect(await webdav.get('doc/audio/1.pack'), big);
    });
  });

  group('nextcloudLogin', () {
    test('opens the sign-in page and returns the app password once it is approved', () async {
      final browser = FakeBrowser(onOpen: (_) => server.approve());
      final login = await nextcloudLogin(Uri.parse(server.url), browser, Cancellation(), pollMs: 10);
      expect((login.user, login.password), ('alice', 'app-pass'));
      expect(browser.opened.map((u) => u.toString()), ['${server.url}/login/v2/flow/poll-token']);
    });

    test('keeps asking while the user has not approved, and stops when cancelled', () async {
      final cancel = Cancellation();
      final browser = FakeBrowser(
        onOpen: (_) => Future<void>.delayed(const Duration(milliseconds: 60), cancel.cancel),
      );
      await expectLater(
        nextcloudLogin(Uri.parse(server.url), browser, cancel, pollMs: 10),
        throwsA(isA<CancelledException>()),
      );
    });

    test('refuses a server that is not Nextcloud', () async {
      await expectLater(
        nextcloudLogin(Uri.parse('${server.url}/elsewhere'), FakeBrowser(), Cancellation(), pollMs: 10),
        throwsA(predicate((e) => '$e'.contains('does not look like a Nextcloud'))),
      );
    });
  });
}
