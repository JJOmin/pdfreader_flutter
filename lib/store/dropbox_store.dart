// Port of the desktop's src/main/sync/dropbox.ts (phone ADR 3, desktop ADR 8): Dropbox in the app's
// own folder, signed in with the authorization-code flow and PKCE and a refresh token, no secret in
// the app. It differs from the desktop in how the browser returns: by the app's own URI scheme.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../platform_oauth.dart';
import '../platform_secrets.dart';
import '../shared/sync_store.dart';
import 'cancellation.dart';
import 'webdav_store.dart';

/// The key of the app registered at dropbox.com/developers, with the "App folder" access type, the
/// scopes files.content.read and files.content.write, and [oauthRedirect] as a redirect address.
/// It is public by design (PKCE needs no secret). Given at build time with
/// `--dart-define=DROPBOX_APP_KEY=...`; without one the Dropbox sign-in is off.
const dropboxAppKey = String.fromEnvironment('DROPBOX_APP_KEY');

class DropboxHosts {
  const DropboxHosts({required this.api, required this.content, required this.www});

  final String api;
  final String content;
  final String www;
}

const _defaultHosts = DropboxHosts(
  api: 'https://api.dropboxapi.com',
  content: 'https://content.dropboxapi.com',
  www: 'https://www.dropbox.com',
);

const _timeout = Duration(minutes: 5);

/// The upload call takes at most 150 MB. A PDF larger than that is not synced.
const _maxUpload = 150 * 1024 * 1024;
const _maxRetries = 4;
const _expiryMargin = Duration(seconds: 60);

Future<Map<String, Object?>> _tokenRequest(
  HttpClient client,
  DropboxHosts hosts,
  Map<String, String> form,
) async {
  final request = await client.postUrl(Uri.parse('${hosts.api}/oauth2/token'));
  request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
  request.write(Uri(queryParameters: form).query);
  final response = await request.close().timeout(const Duration(seconds: 30));
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StoreException('Dropbox refused the sign-in: ${response.statusCode} $body');
  }
  final answer = jsonDecode(body);
  return answer is Map<String, Object?> ? answer : const {};
}

/// Dropbox, in the app's own folder. The user's other files are out of its reach.
class DropboxStore implements SyncStore {
  DropboxStore(
    this.appKey,
    this.refreshToken, {
    this.hosts = _defaultHosts,
    Future<void> Function(Duration)? wait,
    HttpClient? client,
  }) : _wait = wait ?? ((d) => Future<void>.delayed(d)),
       _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 30));

  final String appKey;
  final String refreshToken;
  final DropboxHosts hosts;
  final Future<void> Function(Duration) _wait;
  final HttpClient _client;
  String _access = '';
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  Future<String> _token({required bool force}) async {
    if (force || DateTime.now().isAfter(_expires.subtract(_expiryMargin))) {
      final answer = await _tokenRequest(_client, hosts, {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': appKey,
      });
      final access = answer['access_token'];
      final expires = answer['expires_in'];
      if (access is! String || expires is! num) {
        throw const StoreException('Dropbox returned no access token');
      }
      _access = access;
      _expires = DateTime.now().add(Duration(seconds: expires.toInt()));
    }
    return _access;
  }

  /// One call, with a fresh token after a 401 and a pause after a 429, as Dropbox asks.
  Future<({int status, Uint8List body})> _call(
    String url, {
    Map<String, String> headers = const {},
    Uint8List? body,
  }) async {
    var refreshed = false;
    for (var attempt = 0; ; attempt++) {
      final request = await _client.postUrl(Uri.parse(url));
      headers.forEach(request.headers.set);
      request.headers.set('Authorization', 'Bearer ${await _token(force: refreshed)}');
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(_timeout);
      final out = BytesBuilder();
      await for (final chunk in response.timeout(_timeout)) {
        out.add(chunk);
      }
      if (response.statusCode == 401 && !refreshed) {
        refreshed = true;
        continue;
      }
      if (response.statusCode == 429 && attempt < _maxRetries) {
        final retry = int.tryParse(response.headers.value('retry-after') ?? '') ?? 1;
        await _wait(Duration(seconds: retry));
        continue;
      }
      return (status: response.statusCode, body: out.toBytes());
    }
  }

  Never _fail(int status, Uint8List body, String what) {
    final text = utf8.decode(body, allowMalformed: true);
    throw StoreException(
      'Dropbox refused $what: $status ${text.length > 300 ? text.substring(0, 300) : text}',
    );
  }

  bool _ok(int status) => status >= 200 && status < 300;

  @override
  Future<List<RemoteEntry>> list(String dir) async {
    if (dir.isNotEmpty) assertPath(dir);
    final entries = <RemoteEntry>[];
    var route = '/2/files/list_folder';
    Map<String, Object?> body = {'path': dir.isEmpty ? '' : '/$dir', 'recursive': false};
    for (;;) {
      final response = await _call(
        hosts.api + route,
        headers: {'Content-Type': 'application/json'},
        body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
      );
      if (response.status == 409) {
        final text = utf8.decode(response.body, allowMalformed: true);
        if (text.contains('not_found')) return const [];
        throw StoreException(
          'Dropbox refused listing $dir: ${text.length > 300 ? text.substring(0, 300) : text}',
        );
      }
      if (!_ok(response.status)) {
        _fail(response.status, response.body, 'listing ${dir.isEmpty ? 'the folder' : dir}');
      }
      final page = jsonDecode(utf8.decode(response.body)) as Map<String, Object?>;
      for (final e in page['entries']! as List) {
        final entry = e as Map<String, Object?>;
        entries.add(
          RemoteEntry(
            entry['name']! as String,
            folder: entry['.tag'] == 'folder',
            size: (entry['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      if (page['has_more'] != true) return entries;
      route = '/2/files/list_folder/continue';
      body = {'cursor': page['cursor']};
    }
  }

  @override
  Future<Uint8List?> get(String path) async {
    assertPath(path);
    final response = await _call(
      '${hosts.content}/2/files/download',
      headers: {
        'Dropbox-API-Arg': jsonEncode({'path': '/$path'}),
      },
    );
    if (response.status == 409) {
      final text = utf8.decode(response.body, allowMalformed: true);
      if (text.contains('not_found')) return null;
      throw StoreException(
        'Dropbox refused sending $path: ${text.length > 300 ? text.substring(0, 300) : text}',
      );
    }
    if (!_ok(response.status)) _fail(response.status, response.body, 'sending $path');
    return response.body;
  }

  @override
  Future<void> put(String path, Uint8List bytes) async {
    assertPath(path);
    if (bytes.length > _maxUpload) throw StoreException('$path is too large for Dropbox (150 MB at most)');
    final response = await _call(
      '${hosts.content}/2/files/upload',
      headers: {
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': jsonEncode({'path': '/$path', 'mode': 'overwrite', 'mute': true}),
      },
      body: bytes,
    );
    if (!_ok(response.status)) _fail(response.status, response.body, 'saving $path');
  }
}

String _base64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _random(int n) {
  final random = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < n; i++) random.nextInt(256)]);
}

/// Signs in to Dropbox with the authorization-code flow and PKCE: the browser sends the user back to
/// the app's own URI scheme, and no secret is built into the app. Resolves to a refresh token.
Future<String> dropboxAuthorize(
  String appKey,
  Browser browser,
  OAuthRedirects redirects,
  Cancellation cancel, {
  DropboxHosts hosts = _defaultHosts,
  String redirect = oauthRedirect,
  HttpClient? client,
}) async {
  if (appKey.isEmpty) throw const StoreException('This build has no Dropbox app key');
  final verifier = _base64Url(_random(32));
  final state = _base64Url(_random(16));
  final challenge = _base64Url(sha256.convert(utf8.encode(verifier)).bytes);
  final back = Uri.parse(redirect);

  final codeResult = Completer<String>();
  // Listening starts before the browser opens, so a quick return is not missed.
  final listening = redirects.uris.listen((uri) {
    if (uri.scheme != back.scheme || uri.path != back.path) return;
    // Anything that does not carry this sign-in's state is not part of it.
    if (uri.queryParameters['state'] != state) return;
    final code = uri.queryParameters['code'];
    if (code != null && !codeResult.isCompleted) {
      codeResult.complete(code);
    } else if (!codeResult.isCompleted) {
      codeResult.completeError(
        StoreException('Dropbox sign-in failed: ${uri.queryParameters['error'] ?? 'no access given'}'),
      );
    }
  });
  final timer = Timer(const Duration(minutes: 5), () {
    if (!codeResult.isCompleted) codeResult.completeError(const StoreException('Sign-in timed out'));
  });
  try {
    final query = {
      'client_id': appKey,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
      'redirect_uri': redirect,
      'state': state,
    };
    await browser.open(Uri.parse('${hosts.www}/oauth2/authorize').replace(queryParameters: query));
    final code = await Future.any([
      codeResult.future,
      cancel.whenCancelled.then<String>((_) => throw const CancelledException()),
    ]);
    final answer = await _tokenRequest(client ?? HttpClient(), hosts, {
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': verifier,
      'client_id': appKey,
      'redirect_uri': redirect,
    });
    final refresh = answer['refresh_token'];
    if (refresh is! String) throw const StoreException('Dropbox returned no refresh token');
    return refresh;
  } finally {
    timer.cancel();
    await listening.cancel();
  }
}
