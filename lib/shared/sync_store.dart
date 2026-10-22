// Port of the desktop's src/shared/sync-store.ts (desktop ADR 8, phone ADR 3): what every sync
// backend shares. The store interface, the names of the files in it, the audio pack, and the
// encryption that keeps the provider from reading anything. The formats are the desktop's, byte for
// byte; its golden files are in test/golden/store.json.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class RemoteEntry {
  const RemoteEntry(this.name, {required this.folder, required this.size, this.etag});

  final String name;
  final bool folder;
  final int size;

  /// Changes whenever the file does, when the store says so (WebDAV's ETag).
  final String? etag;
}

/// A place that keeps files and knows nothing else: no logic runs on the other side. Paths are
/// relative to the app's own folder in the store and pass [assertPath].
abstract interface class SyncStore {
  /// The direct children of a folder, or none when the folder does not exist.
  Future<List<RemoteEntry>> list(String dir);

  /// The file's bytes, or null when there is no such file.
  Future<Uint8List?> get(String path);

  /// Writes the file, with its folders, replacing what was there.
  Future<void> put(String path, Uint8List bytes);
}

final _segment = RegExp(r'^[A-Za-z0-9._-]+$');
final _dots = RegExp(r'^\.+$');

/// Paths are built from hashes and numbers; this stops anything else reaching a provider's API.
void assertPath(String path) {
  final ok = path.split('/').every((s) => _segment.hasMatch(s) && !_dots.hasMatch(s));
  if (!ok) throw ArgumentError.value(path, 'path', 'Invalid path');
}

/// Where a document's files lie in the store. They mirror the library of desktop ADR 7 section 2.
abstract final class RemotePath {
  static String manifest(String docId) => '$docId/manifest.json';
  static String pdf(String docId) => '$docId/document.pdf';
  static String page(String docId, int page) => '$docId/pages/$page.json';

  /// A page's audio, packed: a store should not be asked for a file per sentence.
  static String pack(String docId, int page) => '$docId/audio/$page.pack';
  static String states(String docId) => '$docId/state';
  static String state(String docId, String device) => '$docId/state/$device.json';

  /// The document's marks and comments, merged per mark (desktop ADR 7 section 1).
  static String notes(String docId) => '$docId/notes.json';

  /// Where every device's change journal lies (desktop ADR 10 section 2).
  static const journals = 'devices';
  static String journal(String device) => 'devices/$device.json';
}

enum JournalPart { manifest, notes, state }

/// When each part of a document last changed on the device that wrote the journal.
class JournalDoc {
  const JournalDoc({this.manifest = 0, this.notes = 0, this.state = 0});

  final int manifest;
  final int notes;
  final int state;

  int at(JournalPart part) => switch (part) {
    JournalPart.manifest => manifest,
    JournalPart.notes => notes,
    JournalPart.state => state,
  };

  JournalDoc withPart(JournalPart part, int t) => JournalDoc(
    manifest: part == JournalPart.manifest ? t : manifest,
    notes: part == JournalPart.notes ? t : notes,
    state: part == JournalPart.state ? t : state,
  );

  Map<String, Object?> toJson() => {'manifest': manifest, 'notes': notes, 'state': state};

  @override
  bool operator ==(Object other) =>
      other is JournalDoc && other.manifest == manifest && other.notes == notes && other.state == state;

  @override
  int get hashCode => Object.hash(manifest, notes, state);
}

/// One device's list of its latest changes, sealed in `devices/<device>.json`. Another device that
/// has read it before can tell from the difference which documents and parts to fetch. It is a
/// hint: a full walk of the store repairs whatever a lost journal missed.
class Journal {
  const Journal({required this.device, required this.name, required this.updated, required this.docs});

  final String device;
  final String name;
  final int updated;
  final Map<String, JournalDoc> docs;

  /// The desktop's bytes for the same journal: the keys in this order.
  Map<String, Object?> toJson() => {
    'device': device,
    'name': name,
    'updated': updated,
    'docs': {for (final MapEntry(:key, :value) in docs.entries) key: value.toJson()},
  };
}

final _journalDevice = RegExp(r'^[0-9a-f]{32}$');
final _journalDoc = RegExp(r'^[0-9a-f]{64}$');

int? _time(Object? value) => value is num && value.isFinite && value >= 0 ? value.toInt() : null;

/// Reads a journal; documents with a bad id or time are dropped, a bad device id makes it null.
Journal? parseJournal(Object? value) {
  if (value is! Map<String, Object?>) return null;
  final updated = _time(value['updated']);
  final device = value['device'];
  if (device is! String || !_journalDevice.hasMatch(device) || updated == null) return null;
  final docs = <String, JournalDoc>{};
  final raw = value['docs'];
  if (raw is Map<String, Object?>) {
    for (final MapEntry(:key, :value) in raw.entries) {
      if (!_journalDoc.hasMatch(key) || value is! Map<String, Object?>) continue;
      final manifest = _time(value['manifest']), notes = _time(value['notes']), state = _time(value['state']);
      if (manifest != null && notes != null && state != null) {
        docs[key] = JournalDoc(manifest: manifest, notes: notes, state: state);
      }
    }
  }
  final name = value['name'];
  return Journal(
    device: device,
    name: name is String && name.length <= 256 ? name : '',
    updated: updated,
    docs: docs,
  );
}

/// The documents, and which of their parts, that differ between the journal as it was last read
/// and now. Times are compared for difference, not order, so a device with a wrong clock still
/// gets its changes noticed. Without an earlier journal everything in it is new.
Map<String, List<JournalPart>> changedParts(Journal? seen, Journal now) {
  final changed = <String, List<JournalPart>>{};
  for (final MapEntry(key: docId, value: doc) in now.docs.entries) {
    final before = seen?.docs[docId];
    final parts = [
      for (final part in JournalPart.values)
        if (before == null || before.at(part) != doc.at(part)) part,
    ];
    if (parts.isNotEmpty) changed[docId] = parts;
  }
  return changed;
}

/// One audio file of a pack: the sentence's key and its Ogg Opus bytes.
class PackedFile {
  const PackedFile(this.key, this.bytes);

  final String key;
  final Uint8List bytes;
}

final _audioKey = RegExp(r'^[0-9a-f]{40}$');

/// A page's audio files in one: a 4-byte big-endian length, that many bytes of JSON
/// `[[key, byteLength], ...]`, then the files in that order.
Uint8List packAudio(List<PackedFile> files) {
  final header = utf8.encode(
    jsonEncode([
      for (final f in files) [f.key, f.bytes.length],
    ]),
  );
  final out = Uint8List(4 + header.length + files.fold<int>(0, (n, f) => n + f.bytes.length));
  ByteData.sublistView(out).setUint32(0, header.length);
  out.setRange(4, 4 + header.length, header);
  var at = 4 + header.length;
  for (final f in files) {
    out.setRange(at, at + f.bytes.length, f.bytes);
    at += f.bytes.length;
  }
  return out;
}

/// The files of a pack, or null when it is not one.
List<PackedFile>? unpackAudio(Uint8List pack) {
  if (pack.length < 4) return null;
  final headerLength = ByteData.sublistView(pack).getUint32(0);
  if (4 + headerLength > pack.length) return null;
  final Object? entries;
  try {
    entries = jsonDecode(utf8.decode(Uint8List.sublistView(pack, 4, 4 + headerLength)));
  } on FormatException {
    return null;
  }
  if (entries is! List) return null;
  final files = <PackedFile>[];
  var at = 4 + headerLength;
  for (final entry in entries) {
    if (entry is! List || entry.length != 2) return null;
    final [key, length] = entry;
    if (key is! String || !_audioKey.hasMatch(key)) return null;
    if (length is! int || length < 0 || at + length > pack.length) return null;
    files.add(PackedFile(key, Uint8List.sublistView(pack, at, at + length)));
    at += length;
  }
  return at == pack.length ? files : null;
}

final _magic = utf8.encode('PRS1');
const _ivBytes = 12;
const _keyBytes = 32;
const _tagBytes = 16;

final _random = Random.secure();

Uint8List _randomBytes(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) _random.nextInt(256)]);

Uint8List newSyncKey() => _randomBytes(_keyBytes);

/// Thrown when a file from the store cannot be opened.
class SealException implements Exception {
  const SealException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _aes = AesGcm.with256bits();

/// Encrypts a file for the store: `PRS1`, a random IV, then AES-256-GCM. The path is signed into
/// the file, so the provider cannot hand one file back under another's name. `iv` is for tests
/// that compare with the desktop's bytes; it is random otherwise.
Future<Uint8List> seal(Uint8List key, String path, Uint8List data, {Uint8List? iv}) async {
  final nonce = iv ?? _randomBytes(_ivBytes);
  final box = await _aes.encrypt(data, secretKey: SecretKey(key), nonce: nonce, aad: utf8.encode(path));
  // Web Crypto, which the desktop uses, writes the tag after the ciphertext.
  return Uint8List.fromList([..._magic, ...nonce, ...box.cipherText, ...box.mac.bytes]);
}

/// Decrypts a file from the store. Throws a [SealException] when the key is wrong, the path is
/// another's or the file was changed.
Future<Uint8List> unseal(Uint8List key, String path, Uint8List sealed) async {
  final header = _magic.length + _ivBytes;
  if (sealed.length < header + _tagBytes ||
      !List.generate(_magic.length, (i) => sealed[i] == _magic[i]).every((b) => b)) {
    throw SealException('$path is not a file of this app');
  }
  final nonce = sealed.sublist(_magic.length, header);
  final cipherText = sealed.sublist(header, sealed.length - _tagBytes);
  final mac = Mac(sealed.sublist(sealed.length - _tagBytes));
  try {
    final plain = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: SecretKey(key),
      aad: utf8.encode(path),
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    throw SealException('$path cannot be read: the sync key is wrong or the file was changed');
  }
}

final _groups = RegExp(r'(.{8})(?=.)');

/// A key as the user sees it: 64 hex digits in groups of 8.
String formatSyncKey(Uint8List key) =>
    key.map((b) => b.toRadixString(16).padLeft(2, '0')).join().replaceAllMapped(_groups, (m) => '${m[1]}-');

final _separators = RegExp(r'[\s-]');
final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Reads a key the user typed or pasted, or null when it is not one.
Uint8List? parseSyncKey(String text) {
  final hex = text.replaceAll(_separators, '').toLowerCase();
  if (!_hex64.hasMatch(hex)) return null;
  return Uint8List.fromList([for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
}

final _privateHost = RegExp(
  r'^(localhost|127\.\d+\.\d+\.\d+|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|[^.]+\.local)$',
);
final _scheme = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);

/// Reads a server address the user typed. Passwords go over https; plain http is accepted only for
/// a machine on the user's own network, which is where a home server lives.
Uri? parseServerUrl(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final Uri url;
  try {
    url = Uri.parse(_scheme.hasMatch(trimmed) ? trimmed : 'https://$trimmed');
  } on FormatException {
    return null;
  }
  if (url.userInfo.isNotEmpty || url.hasQuery || url.hasFragment || url.host.isEmpty) return null;
  if (url.scheme == 'https') return url.path.isEmpty ? url.replace(path: '/') : url;
  return url.scheme == 'http' && _privateHost.hasMatch(url.host) ? url : null;
}
