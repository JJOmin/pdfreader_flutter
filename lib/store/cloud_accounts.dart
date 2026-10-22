// The sign-in and the secrets (phone ADR 3 sections 4 and 5), and the one place that turns "the user
// chose Nextcloud" into a store. The secrets, the app password and the sync key, are sealed with the
// Android Keystore; the file beside them says only which service and which user. Dropbox was removed
// for now (desktop ADR 10): a file that still names it reads as signed out.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../platform_secrets.dart';
import '../shared/sync_store.dart';
import 'cancellation.dart';
import 'nextcloud_login.dart';
import 'webdav_store.dart';

enum CloudBackend { none, nextcloud }

class CloudStatus {
  const CloudStatus({required this.backend, required this.account, required this.hasKey});

  final CloudBackend backend;

  /// Who is signed in: `user at server`, or empty when nothing is connected.
  final String account;

  /// Whether a sync key is set. It is never shown back.
  final bool hasKey;
}

class _Config {
  _Config({this.backend = CloudBackend.none, this.server = '', this.user = '', this.secrets = ''});

  CloudBackend backend;
  String server;
  String user;

  /// JSON of [_Secrets], sealed by the Keystore.
  String secrets;
}

class _Secrets {
  _Secrets({this.key, this.password});

  String? key;
  String? password;

  Map<String, Object?> toJson() => {if (key != null) 'key': key, if (password != null) 'password': password};

  static _Secrets from(Object? value) {
    final map = value is Map<String, Object?> ? value : const <String, Object?>{};
    String? text(String name) =>
        map[name] is String && (map[name]! as String).length <= 4096 ? map[name]! as String : null;
    return _Secrets(key: text('key'), password: text('password'));
  }
}

class CloudAccounts {
  CloudAccounts({required this.file, required this.box, required this.browser});

  final File file;
  final SecretBox box;
  final Browser browser;

  Future<({_Config config, _Secrets secrets})> _load() async {
    var config = _Config();
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is Map<String, Object?>) {
        config = _Config(
          backend:
              CloudBackend.values.where((b) => b.name == value['backend']).firstOrNull ?? CloudBackend.none,
          server: value['server'] is String && (value['server']! as String).length <= 2048
              ? value['server']! as String
              : '',
          user: value['user'] is String && (value['user']! as String).length <= 256
              ? value['user']! as String
              : '',
          secrets: value['secrets'] is String ? value['secrets']! as String : '',
        );
      }
    } on FileSystemException {
      // First start: nothing is connected.
    } on FormatException {
      // A file that is not ours: nothing is connected.
    }
    var secrets = _Secrets();
    if (config.secrets.isNotEmpty) {
      try {
        secrets = _Secrets.from(jsonDecode(await box.decrypt(config.secrets)));
      } catch (_) {
        // Secrets written for another install cannot be opened: sign in again.
      }
    }
    return (config: config, secrets: secrets);
  }

  Future<void> _save(_Config config, _Secrets secrets) async {
    await file.parent.create(recursive: true);
    config.secrets = await box.encrypt(jsonEncode(secrets.toJson()));
    await file.writeAsString(
      jsonEncode({
        'backend': config.backend.name,
        'server': config.server,
        'user': config.user,
        'secrets': config.secrets,
      }),
    );
  }

  CloudStatus _status(_Config config, _Secrets secrets) => CloudStatus(
    backend: config.backend,
    account: switch (config.backend) {
      CloudBackend.nextcloud =>
        '${config.user} at ${Uri.tryParse(config.server)?.authority ?? config.server}',
      CloudBackend.none => '',
    },
    hasKey: secrets.key != null,
  );

  Future<CloudStatus> status() async {
    final (:config, :secrets) = await _load();
    return _status(config, secrets);
  }

  /// Signs in to Nextcloud in the user's browser. Resolves when they approved; throws when they
  /// cancel or it times out.
  Future<CloudStatus> connectNextcloud(String server, Cancellation cancel) async {
    final url = parseServerUrl(server);
    if (url == null) {
      throw const StoreException(
        'Enter the address of your Nextcloud, for example https://cloud.example.com',
      );
    }
    final login = await nextcloudLogin(url, browser, cancel);
    final (:config, :secrets) = await _load();
    config
      ..backend = CloudBackend.nextcloud
      ..server = url.toString().replaceFirst(RegExp(r'/$'), '')
      ..user = login.user;
    secrets.password = login.password;
    await _save(config, secrets);
    return _status(config, secrets);
  }

  /// Forgets the sign-in and keeps the key, so signing in again finds the same files. The files in
  /// the store are not deleted.
  Future<CloudStatus> disconnect() async {
    final (:config, :secrets) = await _load();
    config
      ..backend = CloudBackend.none
      ..server = ''
      ..user = '';
    secrets.password = null;
    await _save(config, secrets);
    return _status(config, secrets);
  }

  /// Sets the key the desktop shows. Throws a [FormatException] for text that is not one.
  Future<CloudStatus> setKey(String text) async {
    final key = parseSyncKey(text);
    if (key == null) throw const FormatException('A sync key is 64 digits, 0 to 9 and a to f');
    final (:config, :secrets) = await _load();
    secrets.key = formatSyncKey(key);
    await _save(config, secrets);
    return _status(config, secrets);
  }

  Future<Uint8List> key() async {
    final key = parseSyncKey((await _load()).secrets.key ?? '');
    if (key == null) throw const StoreException('There is no sync key. Enter the one the desktop shows.');
    return key;
  }

  /// The store of whoever is signed in.
  Future<SyncStore> store() async {
    final (:config, :secrets) = await _load();
    switch (config.backend) {
      case CloudBackend.nextcloud when secrets.password != null:
        return WebDavStore(nextcloudDavBase(config.server, config.user), config.user, secrets.password!);
      default:
        throw const StoreException('Sign in to Nextcloud first.');
    }
  }
}
