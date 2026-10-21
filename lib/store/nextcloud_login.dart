// Nextcloud's Login Flow v2, as on the desktop (src/main/sync/webdav.ts): the user signs in in the
// browser and approves this app, and the server hands back an app password that can be revoked on
// its own. Nothing the user types reaches this program.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform_secrets.dart';
import 'cancellation.dart';
import 'webdav_store.dart';

const _loginTimeout = Duration(minutes: 5);

class NextcloudLogin {
  const NextcloudLogin(this.user, this.password);

  final String user;
  final String password;
}

bool _sameOrigin(Uri a, String b) {
  try {
    final other = Uri.parse(b);
    return other.scheme == a.scheme && other.host == a.host && other.port == a.port;
  } on FormatException {
    return false;
  }
}

Future<NextcloudLogin> nextcloudLogin(
  Uri server,
  Browser browser,
  Cancellation cancel, {
  int pollMs = 2000,
  HttpClient? client,
}) async {
  final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 30));
  Future<({int status, String reason, String body})> post(Uri url, {Map<String, String>? form}) async {
    final request = await http.postUrl(url);
    request.headers.set('User-Agent', userAgent);
    if (form != null) {
      request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      request.write(Uri(queryParameters: form).query);
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, reason: response.reasonPhrase, body: body);
  }

  final base = server.toString().endsWith('/') ? server : server.replace(path: '${server.path}/');
  final start = await post(base.resolve('index.php/login/v2'));
  if (start.status < 200 || start.status >= 300) {
    throw StoreException('This does not look like a Nextcloud server (${start.status})');
  }
  final Object? flow;
  try {
    flow = jsonDecode(start.body);
  } on FormatException {
    throw const StoreException('This does not look like a Nextcloud server');
  }
  final poll = flow is Map<String, Object?> ? flow['poll'] : null;
  final token = poll is Map<String, Object?> ? poll['token'] : null;
  final endpoint = poll is Map<String, Object?> ? poll['endpoint'] : null;
  final login = flow is Map<String, Object?> ? flow['login'] : null;
  // The server names the addresses to visit and poll; they must stay on the server the user typed.
  if (token is! String || endpoint is! String || login is! String) {
    throw const StoreException('The server answered the sign-in request in a way this app does not know');
  }
  if (!_sameOrigin(server, endpoint) || !_sameOrigin(server, login)) {
    throw const StoreException('The server sent the sign-in to another address');
  }
  await browser.open(Uri.parse(login));

  final deadline = DateTime.now().add(_loginTimeout);
  while (DateTime.now().isBefore(deadline)) {
    cancel.throwIfCancelled();
    final answer = await post(Uri.parse(endpoint), form: {'token': token});
    if (answer.status >= 200 && answer.status < 300) {
      final done = jsonDecode(answer.body);
      final user = done is Map<String, Object?> ? done['loginName'] : null;
      final password = done is Map<String, Object?> ? done['appPassword'] : null;
      if (user is! String || password is! String) {
        throw const StoreException('The server did not return an app password');
      }
      return NextcloudLogin(user, password);
    }
    // 404 means the user has not approved yet.
    if (answer.status != 404) {
      throw StoreException('Sign-in failed: ${answer.status} ${answer.reason}'.trim());
    }
    await cancel.delay(Duration(milliseconds: pollMs));
  }
  throw const StoreException('Sign-in timed out');
}
