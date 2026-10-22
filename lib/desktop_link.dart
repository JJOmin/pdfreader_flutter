// The phone's half of desktop ADR 7 (PLAN steps 5.3 and 5.4): finding the desktop, pairing with
// its code, and fetching the library it prepared. The phone always asks; the desktop never calls.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'notes_store.dart';
import 'shared/download_plan.dart';
import 'shared/notes.dart';
import 'shared/pairing.dart';
import 'shared/sync.dart';

const _channel = MethodChannel('pdfreader/discovery');

/// A desktop this phone paired with. The fingerprint is pinned: no other certificate is accepted.
class PairedDesktop {
  const PairedDesktop({
    required this.name,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.token,
  });

  final String name;
  final String host;
  final int port;
  final String fingerprint;
  final String token;

  PairedDesktop at(String host, int port) =>
      PairedDesktop(name: name, host: host, port: port, fingerprint: fingerprint, token: token);

  Map<String, Object> toJson() => {
    'name': name,
    'host': host,
    'port': port,
    'fingerprint': fingerprint,
    'token': token,
  };

  static PairedDesktop? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final Object? name = value['name'], host = value['host'], port = value['port'];
    final Object? fingerprint = value['fingerprint'], token = value['token'];
    if (name is! String || host is! String || port is! int || fingerprint is! String || token is! String) {
      return null;
    }
    return PairedDesktop(name: name, host: host, port: port, fingerprint: fingerprint, token: token);
  }
}

/// This phone's id and its paired desktops, in the app's own storage (ADR 2 section 4).
class DesktopStore {
  DesktopStore._(this._file, this.device, this.desktops);

  final File _file;

  /// Names this phone's state file on every desktop.
  final String device;
  final List<PairedDesktop> desktops;

  static Future<DesktopStore> open() async {
    final file = File('${(await getApplicationSupportDirectory()).path}/desktops.json');
    String? device;
    final desktops = <PairedDesktop>[];
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is Map<String, Object?>) {
        final id = value['device'];
        if (id is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) device = id;
        for (final entry in value['desktops'] is List ? value['desktops']! as List : const []) {
          final desktop = PairedDesktop.fromJson(entry);
          if (desktop != null) desktops.add(desktop);
        }
      }
    } on FileSystemException {
      // First start: no desktops yet.
    } on FormatException {
      // A file that is not ours: start again.
    }
    final random = Random.secure();
    device ??= [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    final store = DesktopStore._(file, device, desktops);
    await store.save();
    return store;
  }

  Future<void> save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'device': device,
        'desktops': [for (final d in desktops) d.toJson()],
      }),
    );
  }

  Future<void> remember(PairedDesktop desktop) async {
    desktops
      ..removeWhere((d) => d.fingerprint == desktop.fingerprint)
      ..add(desktop);
    await save();
  }

  Future<void> forget(PairedDesktop desktop) async {
    desktops.removeWhere((d) => d.fingerprint == desktop.fingerprint);
    await save();
  }
}

class DesktopException implements Exception {
  const DesktopException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// HTTPS to one desktop. Its certificate is self-signed, so no root is trusted and every
/// certificate goes through `trust`, which checks its SHA-256 before anything is sent.
class DesktopClient {
  DesktopClient(this.host, this.port, this.trust)
    : _http = HttpClient(context: SecurityContext(withTrustedRoots: false))
        ..connectionTimeout = const Duration(seconds: 5)
        ..idleTimeout = const Duration(seconds: 15) {
    _http.badCertificateCallback = (certificate, _, _) {
      final fingerprint = sha256.convert(certificate.der).toString();
      seenFingerprint = fingerprint;
      return trust(fingerprint);
    };
  }

  final String host;
  final int port;
  final bool Function(String fingerprint) trust;
  final HttpClient _http;

  /// The certificate the desktop showed, once a request has been made.
  String? seenFingerprint;

  Future<HttpClientResponse> _send(String method, String path, {String? token, Object? body}) async {
    final request = await _http.openUrl(method, Uri(scheme: 'https', host: host, port: port, path: path));
    if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    return request.close();
  }

  Future<Object?> json(
    String method,
    String path, {
    String? token,
    Object? body,
    bool missingIsNull = false,
  }) async {
    final response = await _send(method, path, token: token, body: body);
    final text = await response.transform(utf8.decoder).join();
    if (missingIsNull && response.statusCode == 404) return null;
    _check(response.statusCode);
    return text.isEmpty ? null : jsonDecode(text);
  }

  /// Writes a file next to `target` first, so a broken transfer never leaves half a file.
  Future<int> download(String path, File target, {required String token}) async {
    final response = await _send('GET', path, token: token);
    if (response.statusCode != 200) {
      await response.drain<void>();
      _check(response.statusCode);
    }
    await target.parent.create(recursive: true);
    final partial = File('${target.path}.part');
    final sink = partial.openWrite();
    var bytes = 0;
    await for (final chunk in response) {
      bytes += chunk.length;
      sink.add(chunk);
    }
    await sink.close();
    await partial.rename(target.path);
    return bytes;
  }

  void _check(int status) {
    if (status >= 200 && status < 300) return;
    throw DesktopException(switch (status) {
      401 => 'The desktop no longer knows this phone. Pair again.',
      403 => 'The desktop declined.',
      404 => 'The desktop is not accepting phones. Open its Phone dialog.',
      409 => 'Another phone is pairing. Try again in a moment.',
      _ => 'The desktop answered $status.',
    });
  }

  void close() => _http.close(force: true);
}

/// A desktop heard on the network.
typedef FoundDesktop = ({String name, String host, int port});

/// Listens for the desktops' announcements while the stream is listened to.
Stream<FoundDesktop> discoverDesktops() {
  RawDatagramSocket? socket;
  late final StreamController<FoundDesktop> controller;
  controller = StreamController(
    onListen: () async {
      try {
        await _channel.invokeMethod<void>('acquire');
        final s = socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          desktopPort,
          reuseAddress: true,
        );
        // Joined on each interface by address: a membership on the default one may hear nothing.
        for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
          try {
            s.joinMulticast(InternetAddress(announceGroup), interface);
          } on SocketException {
            // An interface without multicast, such as mobile data.
          }
        }
        s.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = s.receive();
          final heard = datagram == null ? null : parseAnnouncement(datagram.data);
          if (heard != null) {
            controller.add((name: heard.name, host: datagram!.address.address, port: heard.port));
          }
        });
      } catch (error) {
        controller.addError(error);
      }
    },
    onCancel: () async {
      socket?.close();
      await _channel.invokeMethod<void>('release');
    },
  );
  return controller.stream;
}

/// The name the desktop shows in "Pair with …?".
Future<String> phoneName() async => await _channel.invokeMethod<String>('deviceName') ?? 'Phone';

/// Whether the network in use is metered (mobile data, or a Wi-Fi the user marked so). Downloads the
/// phone starts on its own wait for one that is not. False where the platform cannot say.
Future<bool> isMetered() async {
  try {
    return await _channel.invokeMethod<bool>('isMetered') ?? false;
  } on MissingPluginException {
    return false;
  }
}

/// Pairs with the desktop at `host`. The certificate must match the typed code before anything is
/// sent; then the desktop asks its user, and the phone waits for the answer.
Future<PairedDesktop> pair(DesktopStore store, String host, int port, String code) async {
  if (normalizeCode(code) == null) throw const DesktopException('The code has 12 letters and digits.');
  final client = DesktopClient(host, port, (fingerprint) => codeMatches(fingerprint, code));
  try {
    final hello = await client.json('GET', '/v1/hello').catchError((Object error) {
      if (client.seenFingerprint != null && !codeMatches(client.seenFingerprint!, code)) {
        throw const DesktopException('That is not the code this desktop shows.');
      }
      throw error;
    });
    final name = (hello as Map<String, Object?>)['name'];
    final answer = await client.json(
      'POST',
      '/v1/pair',
      body: {'device': store.device, 'name': await phoneName()},
    );
    final token = (answer as Map<String, Object?>)['token'];
    if (token is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const DesktopException('The desktop gave no token.');
    }
    final desktop = PairedDesktop(
      name: name is String ? name : host,
      host: host,
      port: port,
      fingerprint: client.seenFingerprint!,
      token: token,
    );
    await store.remember(desktop);
    return desktop;
  } finally {
    client.close();
  }
}

class SyncProgress {
  const SyncProgress(this.document, this.done, this.total);

  final String document;
  final int done;
  final int total;
}

class SyncResult {
  const SyncResult(this.documents, this.files, this.bytes, {this.notes = 0});

  final int documents;

  /// Documents whose marks or comments changed on this phone because of the sync.
  final int notes;

  /// Files fetched; zero when everything was current.
  final int files;
  final int bytes;
}

/// Sends this phone's place in a document and keeps the other devices' (step 5.6). Each device
/// writes only its own file, so nothing is merged.
Future<void> _exchangeStates(
  DesktopClient client,
  String token,
  String device,
  Directory dir,
  String docId,
) async {
  final own = File('${dir.path}/state/$device.json');
  if (await own.exists()) {
    await client.json(
      'PUT',
      '/v1/doc/$docId/state/$device',
      token: token,
      body: jsonDecode(await own.readAsString()),
    );
  }
  final listed = await client.json('GET', '/v1/doc/$docId/state', token: token);
  for (final entry in listed is List ? listed : const []) {
    final state = parseDeviceState(entry);
    if (state == null || state.device == device) continue;
    final file = File('${dir.path}/state/${state.device}.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(state.toJson()));
  }
}

bool _blank(NotesFile f) => f.annotations.isEmpty && f.notes.isEmpty && f.removed.isEmpty;

/// Sends this phone's marks and comments for a document and keeps what the desktop merged them
/// with (step 5.7). Per mark: a mark new on either side is kept, the later edit wins, and a deleted
/// mark stays deleted (desktop ADR 7 section 1). Returns whether this phone's copy changed.
Future<bool> _exchangeNotes(DesktopClient client, String token, NotesStore store, String docId) async {
  final local = await store.load(docId);
  final path = '/v1/doc/$docId/notes';
  // Nothing here to send: ask whether the desktop has some. It answers 404 when it has none.
  final answer = _blank(local)
      ? await client.json('GET', path, token: token, missingIsNull: true)
      : await client.json('PUT', path, token: token, body: local.toJson());
  final merged = parseNotes(answer);
  if (merged == null) return false;
  if (encodeNotes(merged) == encodeNotes(local)) return false;
  await store.save(docId, merged);
  return true;
}

/// Fetches every document the desktop prepared, and of each only what the phone lacks (step 5.4),
/// then exchanges the places in them (step 5.6). `device` is this phone's id.
Future<SyncResult> syncFrom(
  PairedDesktop desktop,
  Library library,
  String device,
  void Function(SyncProgress) progress, {
  NotesStore? notes,
}) async {
  final client = DesktopClient(
    desktop.host,
    desktop.port,
    (fingerprint) => fingerprint == desktop.fingerprint,
  );
  final token = desktop.token;
  var files = 0;
  var bytes = 0;
  try {
    final listed = await client.json('GET', '/v1/library', token: token);
    final manifests = [for (final entry in listed is List ? listed : const []) ?parseManifest(entry)];
    for (final remote in manifests) {
      final dir = Directory('${library.root.path}/${remote.docId}');
      final local = await library.read(dir);
      if (isCurrent(remote, local?.manifest)) continue;
      final base = '/v1/doc/${remote.docId}';
      Future<void> fetch(String file) async {
        bytes += await client.download('$base/$file', File('${dir.path}/$file'), token: token);
        files++;
      }

      progress(SyncProgress(remote.name, 0, 1));
      // Until the new manifest arrives the folder is not a whole document, so it is not listed.
      if (local != null) await File('${dir.path}/manifest.json').delete();
      // Its id is its hash, so a PDF already here is the same PDF.
      if (!await File('${dir.path}/document.pdf').exists()) await fetch('document.pdf');
      final pages = <PageIndex>[];
      for (var page = 1; page <= remote.pages; page++) {
        await fetch('pages/$page.json');
        final index = parsePageIndex(jsonDecode(await File('${dir.path}/pages/$page.json').readAsString()));
        if (index == null) throw DesktopException('Page $page of ${remote.name} is not valid');
        pages.add(index);
      }
      final audio = Directory('${dir.path}/audio');
      final have = <String>{
        if (await audio.exists())
          for (final f in audio.listSync().whereType<File>())
            if (f.path.endsWith('.opus')) f.uri.pathSegments.last.replaceAll('.opus', ''),
      };
      final missing = audioToFetch(pages, have);
      for (var i = 0; i < missing.length; i++) {
        progress(SyncProgress(remote.name, i, missing.length));
        await fetch('audio/${missing[i]}.opus');
      }
      for (final key in audioToRemove(pages, have)) {
        await File('${audio.path}/$key.opus').delete();
      }
      // Last, as on the desktop: a folder with a manifest is a whole document.
      await fetch('manifest.json');
    }
    for (final remote in manifests) {
      await _exchangeStates(
        client,
        token,
        device,
        Directory('${library.root.path}/${remote.docId}'),
        remote.docId,
      );
    }
    var changed = 0;
    if (notes != null) {
      for (final remote in manifests) {
        if (await _exchangeNotes(client, token, notes, remote.docId)) changed++;
      }
    }
    return SyncResult(manifests.length, files, bytes, notes: changed);
  } finally {
    client.close();
  }
}
