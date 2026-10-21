// Port of the desktop's tests/unit/dropbox.test.ts, against the stand-in of test/fake_servers.dart.
// The sign-in differs in one way: the browser returns to the app by a custom scheme (ADR 3 section
// 4), so the fake browser hands the redirect to the app as Android would.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/store/cancellation.dart';
import 'package:pdfreader/store/dropbox_store.dart';

import '../fake_platform.dart';
import '../fake_servers.dart';

late FakeDropbox dropbox;

Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));
DropboxStore store() => DropboxStore('app-key', 'refresh-1', hosts: dropbox.hosts, wait: (_) async {});

extension on FakeDropbox {
  DropboxHosts get hosts => DropboxHosts(api: host, content: host, www: host);
}

void main() {
  setUp(() async => dropbox = await FakeDropbox.start());
  tearDown(() => dropbox.close());

  group('DropboxStore', () {
    test('stores a file and reads it back, signing in once', () async {
      final files = store();
      await files.put('doc/pages/1.json', text('hello'));
      expect(await files.get('doc/pages/1.json'), text('hello'));
      expect(utf8.decode(dropbox.files['/doc/pages/1.json']!), 'hello');
      expect(dropbox.tokensIssued, 1);
    });

    test('answers null for a file that is not there', () async {
      expect(await store().get('doc/none.json'), isNull);
    });

    test('lists a folder across several pages, and an absent one as empty', () async {
      final files = store();
      for (final name in ['a.json', 'b.json', 'c.json', 'd/e.json']) {
        await files.put('doc/$name', text('xy'));
      }
      final listed = await files.list('doc');
      expect(listed.map((e) => e.name).toList()..sort(), ['a.json', 'b.json', 'c.json', 'd']);
      expect(listed.firstWhere((e) => e.name == 'd').folder, isTrue);
      final a = listed.firstWhere((e) => e.name == 'a.json');
      expect((a.folder, a.size), (false, 2));
      expect(await files.list('nothing'), isEmpty);
    });

    test('gets a new token when the old one is refused', () async {
      final files = store();
      await files.put('a.json', text('1'));
      dropbox.expireTokens();
      await files.put('b.json', text('2'));
      expect(dropbox.files.containsKey('/b.json'), isTrue);
      expect(dropbox.tokensIssued, 2);
    });

    test('tries again after a 429', () async {
      dropbox.throttleRemaining = 2;
      await store().put('a.json', text('1'));
      expect(dropbox.throttleRefused, 2);
      expect(dropbox.files.containsKey('/a.json'), isTrue);
    });

    test('gives up when it is throttled for good', () async {
      dropbox.throttleRemaining = 99;
      await expectLater(store().put('a.json', text('1')), throwsA(predicate((e) => '$e'.contains('429'))));
    });

    test('refuses a revoked refresh token', () async {
      final revoked = DropboxStore('app-key', 'revoked', hosts: dropbox.hosts);
      await expectLater(
        revoked.get('a.json'),
        throwsA(predicate((e) => '$e'.contains('Dropbox refused the sign-in'))),
      );
    });

    test('refuses paths that are not the library’s own', () async {
      await expectLater(store().put('../x', text('x')), throwsArgumentError);
    });

    test('carries a file the size of a page’s audio pack, byte for byte', () async {
      final big = Uint8List.fromList([for (var i = 0; i < 600000; i++) i % 251]);
      final files = store();
      await files.put('doc/audio/1.pack', big);
      expect(await files.get('doc/audio/1.pack'), big);
    });
  });

  group('dropboxAuthorize', () {
    /// The browser: opens the address, and the app is returned to at where Dropbox sends the user.
    FakeBrowser browser(FakeRedirects redirects, {bool deny = false, void Function(Uri)? also}) =>
        FakeBrowser(
          onOpen: (url) {
            also?.call(url);
            final back = Uri.parse(dropbox.approve(url.toString()));
            if (deny) {
              redirects.add(
                back.replace(
                  queryParameters: {'error': 'access_denied', 'state': back.queryParameters['state']!},
                ),
              );
            } else {
              redirects.add(back);
            }
          },
        );

    Future<String> sign(FakeRedirects redirects, FakeBrowser browser, {Cancellation? cancel}) =>
        dropboxAuthorize('app-key', browser, redirects, cancel ?? Cancellation(), hosts: dropbox.hosts);

    test('returns a refresh token after the user approves, and that token opens the store', () async {
      final redirects = FakeRedirects();
      final token = await sign(redirects, browser(redirects));
      expect(token, 'refresh-1');
      await DropboxStore('app-key', token, hosts: dropbox.hosts).put('a.json', text('ok'));
    });

    test(
      'asks for the app’s own folder access with PKCE, offline, and comes back by the custom scheme',
      () async {
        final redirects = FakeRedirects();
        late Uri asked;
        await sign(redirects, browser(redirects, also: (url) => asked = url));
        expect(asked.queryParameters['client_id'], 'app-key');
        expect(asked.queryParameters['code_challenge_method'], 'S256');
        expect(asked.queryParameters['token_access_type'], 'offline');
        expect(asked.queryParameters['redirect_uri'], 'io.github.jjomin.pdfreader:/oauth');
      },
    );

    test('fails when the user says no', () async {
      final redirects = FakeRedirects();
      await expectLater(
        sign(redirects, browser(redirects, deny: true)),
        throwsA(predicate((e) => '$e'.contains('access_denied'))),
      );
    });

    test('ignores a redirect that does not carry the state, then still finishes', () async {
      final redirects = FakeRedirects();
      final token = await sign(
        redirects,
        FakeBrowser(
          onOpen: (url) {
            final back = Uri.parse(dropbox.approve(url.toString()));
            redirects.add(back.replace(queryParameters: {'code': 'stolen', 'state': 'wrong'}));
            redirects.add(back);
          },
        ),
      );
      expect(token, 'refresh-1');
    });

    test('ignores a redirect to another address of the app', () async {
      final redirects = FakeRedirects();
      final token = await sign(
        redirects,
        FakeBrowser(
          onOpen: (url) {
            final back = Uri.parse(dropbox.approve(url.toString()));
            redirects.add(
              Uri.parse('io.github.jjomin.pdfreader:/other?code=x&state=${back.queryParameters['state']}'),
            );
            redirects.add(back);
          },
        ),
      );
      expect(token, 'refresh-1');
    });

    test('stops when cancelled', () async {
      final cancel = Cancellation();
      final redirects = FakeRedirects();
      await expectLater(
        sign(
          redirects,
          FakeBrowser(onOpen: (_) => Future<void>.delayed(const Duration(milliseconds: 20), cancel.cancel)),
          cancel: cancel,
        ),
        throwsA(isA<CancelledException>()),
      );
    });

    test('needs an app key', () async {
      await expectLater(
        dropboxAuthorize('', FakeBrowser(), FakeRedirects(), Cancellation(), hosts: dropbox.hosts),
        throwsA(predicate((e) => '$e'.contains('no Dropbox app key'))),
      );
    });
  });
}
