// Port of the desktop's src/main/sync/webdav.ts: Nextcloud, ownCloud and any other WebDAV server.
// Files live in one folder under the user's own (phone ADR 3, desktop ADR 8). Network code, so it
// is outside `shared/`; the pure parts are tested against a stand-in server.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../shared/sync_store.dart';

/// The folder in the user's files that holds everything this app syncs. It keeps the app's old name,
/// "PDF Reader", on both the phone and the desktop: renaming it would leave the synced documents behind.
const nextcloudFolder = 'PDF Reader';
const _timeout = Duration(minutes: 5);
const userAgent = 'Easy Reader';

String _withSlash(String url) => url.endsWith('/') ? url : '$url/';

/// Where a Nextcloud user's files can be reached by WebDAV.
String nextcloudDavBase(String server, String user) =>
    '${_withSlash(server)}remote.php/dav/files/${Uri.encodeComponent(user)}/';

String _decode(String text) {
  try {
    return Uri.decodeComponent(text);
  } on ArgumentError {
    return text;
  }
}

final _responseSplit = RegExp(r'<(?:\w+:)?response[\s>]');
final _hrefPattern = RegExp(r'<(?:\w+:)?href>([^<]*)<');
final _collectionPattern = RegExp(r'<(?:\w+:)?collection\s*/?>');
final _lengthPattern = RegExp(r'<(?:\w+:)?getcontentlength>(\d+)<');
final _etagPattern = RegExp(r'<(?:\w+:)?getetag>([^<]*)<');

/// The children in a PROPFIND answer. Servers differ in the namespace prefix they use, so the tags
/// are matched without one. `dir` is the folder that was asked about, which the answer lists first.
List<RemoteEntry> parsePropfind(String xml, Uri dir) {
  final own = _withSlash(_decode(dir.path));
  final entries = <RemoteEntry>[];
  for (final block in xml.split(_responseSplit).skip(1)) {
    final href = _hrefPattern.firstMatch(block)?.group(1);
    if (href == null || href.isEmpty) continue;
    var path = _decode(href);
    if (RegExp(r'^https?://').hasMatch(path)) path = Uri.parse(path).path;
    if (_withSlash(path) == own) continue;
    final name = path.replaceFirst(RegExp(r'/$'), '').split('/').last;
    final size = int.tryParse(_lengthPattern.firstMatch(block)?.group(1) ?? '') ?? 0;
    final etag = _etagPattern.firstMatch(block)?.group(1);
    if (name.isNotEmpty) {
      entries.add(
        RemoteEntry(
          name,
          folder: _collectionPattern.hasMatch(block),
          size: size,
          etag: etag == null || etag.isEmpty ? null : etag,
        ),
      );
    }
  }
  return entries;
}

class StoreException implements Exception {
  const StoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

Never _fail(int status, String reason, String what) =>
    throw StoreException('The server refused $what: $status $reason'.trim());

class WebDavStore implements SyncStore {
  WebDavStore(this.base, this.user, this.password, {this.folder = nextcloudFolder, HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 30));

  /// The WebDAV address of the user's files, ending in a slash.
  final String base;
  final String user;
  final String password;
  final String folder;
  final HttpClient _client;
  final _made = <String>{};

  Uri _url(String path) {
    final parts = [folder, ...path.split('/').where((p) => p.isNotEmpty)];
    return Uri.parse(base).resolve(parts.map(Uri.encodeComponent).join('/'));
  }

  Future<({int status, String reason, Uint8List body})> _request(
    Uri url,
    String method, {
    Uint8List? body,
    Map<String, String> headers = const {},
  }) async {
    final request = await _client.openUrl(method, url);
    request.headers.set('Authorization', 'Basic ${base64Encode(utf8.encode('$user:$password'))}');
    request.headers.set('User-Agent', userAgent);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close().timeout(_timeout);
    final out = BytesBuilder();
    await for (final chunk in response.timeout(_timeout)) {
      out.add(chunk);
    }
    return (status: response.statusCode, reason: response.reasonPhrase, body: out.toBytes());
  }

  /// Creates the folders on the way to a file. MKCOL answers 405 for one that already exists.
  Future<void> _ensureFolders(String path) async {
    final parts = [folder, ...path.split('/').take(path.split('/').length - 1)];
    for (var i = 1; i <= parts.length; i++) {
      final relative = parts.sublist(1, i).join('/');
      if (_made.contains(relative)) continue;
      final response = await _request(_url(relative), 'MKCOL');
      final ok = response.status >= 200 && response.status < 300;
      if (!ok && response.status != 405) {
        _fail(
          response.status,
          response.reason,
          'creating the folder ${relative.isEmpty ? folder : relative}',
        );
      }
      _made.add(relative);
    }
  }

  @override
  Future<List<RemoteEntry>> list(String dir) async {
    if (dir.isNotEmpty) assertPath(dir);
    final url = _url(dir);
    final response = await _request(url, 'PROPFIND', headers: {'Depth': '1'});
    if (response.status == 404) return const [];
    if (response.status != 207) {
      _fail(response.status, response.reason, 'listing ${dir.isEmpty ? 'the folder' : dir}');
    }
    return parsePropfind(utf8.decode(response.body), url);
  }

  @override
  Future<Uint8List?> get(String path) async {
    assertPath(path);
    final response = await _request(_url(path), 'GET');
    if (response.status == 404) return null;
    if (response.status < 200 || response.status >= 300) {
      _fail(response.status, response.reason, 'sending $path');
    }
    return response.body;
  }

  @override
  Future<void> put(String path, Uint8List bytes) async {
    assertPath(path);
    await _ensureFolders(path);
    final response = await _request(_url(path), 'PUT', body: bytes);
    if (response.status < 200 || response.status >= 300) {
      _fail(response.status, response.reason, 'saving $path');
    }
  }
}
