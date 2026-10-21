// Small in-memory stand-ins for the two services, enough to run the real adapters against: the
// phone's counterpart of the desktop's tests/unit/fake-servers.ts, written from the services'
// documentation, so they prove agreement with that reading and not with the services (ADR 3).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Future<Uint8List> _body(HttpRequest request) async {
  final out = BytesBuilder();
  await for (final chunk in request) {
    out.add(chunk);
  }
  return out.toBytes();
}

Future<HttpServer> _listen(Future<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    handler(request).catchError((Object error) async {
      request.response.statusCode = 500;
      request.response.write('$error');
      await request.response.close();
    });
  });
  return server;
}

String _origin(HttpServer server) => 'http://127.0.0.1:${server.port}';

Future<void> _reply(
  HttpRequest request,
  int status, {
  Object? json,
  List<int>? bytes,
  Map<String, String>? headers,
}) async {
  request.response.statusCode = status;
  headers?.forEach(request.response.headers.set);
  if (json != null) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(json));
  }
  if (bytes != null) request.response.add(bytes);
  await request.response.close();
}

class FakeNextcloud {
  FakeNextcloud._(this._server);

  final HttpServer _server;

  /// Path under the user's files, with the folder prefix, to bytes.
  final files = <String, Uint8List>{};
  final folders = <String>{''};
  bool _approved = false;

  String get url => _origin(_server);

  /// The user opens the sign-in page and approves.
  void approve() => _approved = true;

  Future<void> close() => _server.close(force: true);

  static Future<FakeNextcloud> start() async {
    late final FakeNextcloud fake;
    const prefix = '/remote.php/dav/files/alice/';
    final server = await _listen((req) async {
      final path = req.uri.path;
      final base = _origin(fake._server);
      if (path == '/index.php/login/v2' && req.method == 'POST') {
        return _reply(
          req,
          200,
          json: {
            'poll': {'token': 'poll-token', 'endpoint': '$base/login/v2/poll'},
            'login': '$base/login/v2/flow/poll-token',
          },
        );
      }
      if (path == '/login/v2/poll' && req.method == 'POST') {
        final form = Uri.splitQueryString(utf8.decode(await _body(req)));
        if (form['token'] != 'poll-token' || !fake._approved) return _reply(req, 404);
        return _reply(req, 200, json: {'server': base, 'loginName': 'alice', 'appPassword': 'app-pass'});
      }
      if (!path.startsWith(prefix)) return _reply(req, 404);
      if (req.headers.value('authorization') != 'Basic ${base64Encode(utf8.encode('alice:app-pass'))}') {
        return _reply(req, 401);
      }
      final rel = Uri.decodeComponent(path.substring(prefix.length)).replaceFirst(RegExp(r'/$'), '');
      final parent = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
      switch (req.method) {
        case 'MKCOL':
          if (fake.folders.contains(rel) || fake.files.containsKey(rel)) return _reply(req, 405);
          if (!fake.folders.contains(parent)) return _reply(req, 409);
          fake.folders.add(rel);
          return _reply(req, 201);
        case 'PUT':
          if (!fake.folders.contains(parent)) return _reply(req, 409);
          fake.files[rel] = await _body(req);
          return _reply(req, 201);
        case 'GET':
          final file = fake.files[rel];
          return file == null ? _reply(req, 404) : _reply(req, 200, bytes: file);
        case 'PROPFIND':
          if (!fake.folders.contains(rel)) return _reply(req, 404);
          String entry(String p, bool folder, [int size = 0]) =>
              '<d:response><d:href>$prefix${p.split('/').map(Uri.encodeComponent).join('/')}${folder ? '/' : ''}</d:href>'
              '<d:propstat><d:prop>${folder ? '<d:resourcetype><d:collection/></d:resourcetype>' : '<d:resourcetype/><d:getcontentlength>$size</d:getcontentlength>'}</d:prop></d:propstat></d:response>';
          bool inside(String p) =>
              p != rel && p.isNotEmpty && (p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : '') == rel;
          final children = [...fake.folders.where(inside), ...fake.files.keys.where(inside)];
          final xml =
              '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">${entry(rel, true)}'
              '${children.map((c) => entry(c, fake.folders.contains(c), fake.files[c]?.length ?? 0)).join()}</d:multistatus>';
          return _reply(req, 207, bytes: utf8.encode(xml), headers: {'content-type': 'application/xml'});
        default:
          return _reply(req, 405);
      }
    });
    fake = FakeNextcloud._(server);
    return fake;
  }
}

class FakeDropbox {
  FakeDropbox._(this._server);

  final HttpServer _server;
  final files = <String, Uint8List>{};
  final _codes = <String, ({String challenge, String redirect})>{};
  Set<String> _valid = {};
  int tokensIssued = 0;

  /// How many calls are still to be refused with 429, and how many were.
  int throttleRemaining = 0;
  int throttleRefused = 0;

  String get host => _origin(_server);

  /// Makes every token issued so far invalid, as an expiry would.
  void expireTokens() => _valid = {};

  /// What the browser does at the authorize address: approves, and returns where Dropbox sends the user.
  String approve(String authorizeUrl) {
    final url = Uri.parse(authorizeUrl);
    final code = 'code-${_codes.length + 1}';
    _codes[code] = (
      challenge: url.queryParameters['code_challenge']!,
      redirect: url.queryParameters['redirect_uri']!,
    );
    return Uri.parse(url.queryParameters['redirect_uri']!)
        .replace(queryParameters: {'code': code, 'state': url.queryParameters['state']!})
        .toString();
  }

  Future<void> close() => _server.close(force: true);

  static Future<FakeDropbox> start() async {
    late final FakeDropbox fake;
    final server = await _listen((req) async {
      final path = req.uri.path;
      final raw = await _body(req);
      if (path == '/oauth2/token') {
        final form = Uri.splitQueryString(utf8.decode(raw));
        if (form['grant_type'] == 'authorization_code') {
          final granted = fake._codes[form['code'] ?? ''];
          final challenge = base64Url
              .encode(sha256.convert(utf8.encode(form['code_verifier'] ?? '')).bytes)
              .replaceAll('=', '');
          if (granted == null || granted.challenge != challenge || granted.redirect != form['redirect_uri']) {
            return _reply(req, 400, json: {'error': 'invalid_grant'});
          }
        } else if (form['refresh_token'] != 'refresh-1') {
          return _reply(req, 400, json: {'error': 'invalid_grant'});
        }
        final access = 'access-${++fake.tokensIssued}';
        fake._valid.add(access);
        return _reply(
          req,
          200,
          json: {'access_token': access, 'expires_in': 14400, 'refresh_token': 'refresh-1'},
        );
      }
      if (!fake._valid.contains((req.headers.value('authorization') ?? '').replaceFirst('Bearer ', ''))) {
        return _reply(req, 401, json: {'error_summary': 'expired_access_token/'});
      }
      if (fake.throttleRemaining > 0) {
        fake.throttleRemaining--;
        fake.throttleRefused++;
        return _reply(req, 429, bytes: utf8.encode('too_many_requests'), headers: {'retry-after': '0'});
      }
      final argHeader = req.headers.value('dropbox-api-arg');
      final arg = argHeader == null ? null : jsonDecode(argHeader) as Map<String, Object?>;
      if (path == '/2/files/upload') {
        fake.files[arg!['path']! as String] = raw;
        return _reply(req, 200, json: {'name': arg['path']});
      }
      if (path == '/2/files/download') {
        final file = fake.files[arg!['path']! as String];
        if (file == null) return _reply(req, 409, json: {'error_summary': 'path/not_found/..'});
        return _reply(req, 200, bytes: file);
      }
      if (path == '/2/files/list_folder' || path == '/2/files/list_folder/continue') {
        final request = jsonDecode(utf8.decode(raw)) as Map<String, Object?>;
        // Two entries a page, so the continuation is exercised.
        final cursor = request['cursor'] as String?;
        final dir = cursor != null ? cursor.split('|')[0] : (request['path'] as String? ?? '');
        final from = cursor != null ? int.parse(cursor.split('|')[1]) : 0;
        final names = <String, ({bool folder, int size})>{};
        for (final MapEntry(key: file, value: bytes) in fake.files.entries) {
          if (!file.startsWith('$dir/')) continue;
          final rest = file.substring(dir.length + 1).split('/');
          names[rest.first] = rest.length > 1 ? (folder: true, size: 0) : (folder: false, size: bytes.length);
        }
        if (names.isEmpty && dir != '') return _reply(req, 409, json: {'error_summary': 'path/not_found/'});
        final all = names.entries.toList();
        final slice = all.skip(from).take(2);
        return _reply(
          req,
          200,
          json: {
            'entries': [
              for (final e in slice)
                {'.tag': e.value.folder ? 'folder' : 'file', 'name': e.key, 'size': e.value.size},
            ],
            'cursor': '$dir|${from + 2}',
            'has_more': from + 2 < all.length,
          },
        );
      }
      return _reply(req, 404);
    });
    fake = FakeDropbox._(server);
    return fake;
  }
}
