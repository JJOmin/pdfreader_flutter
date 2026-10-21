// Port of the desktop's src/shared/phone-library.ts (desktop ADR 7): the library the desktop
// prepares and the phone reads. The phone reads a page with the desktop's sentences when both
// engines find the same words on it, so the words, not the sentences or raw offsets, are what the
// two sides compare. Inputs are whatever jsonDecode gives, so every reader checks types itself.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'types.dart';

const libraryVersion = 1;

final _key = RegExp(r'^[0-9a-f]{40}$');
final _sha256 = RegExp(r'^[0-9a-f]{64}$');
final _deviceId = RegExp(r'^[0-9a-f]{32}$');
final _space = RegExp(r'\s+', unicode: true);

String sha256Hex(String text) => sha256.convert(utf8.encode(text)).toString();

/// The page's words in reading order, each NFKC. Hashed, joined by single spaces, into `wordsHash`.
List<String> pageWords(List<Utterance> utterances) => [
  for (final u in utterances)
    for (final w in u.words) unorm.nfkc(w.text),
];

/// The hash the index carries for a page's words.
String wordsHash(List<String> words) => sha256Hex(words.join(' '));

/// Each sentence's first word, as an index into `pageWords`.
List<int> sentenceStarts(List<Utterance> utterances) {
  final starts = <int>[];
  var next = 0;
  for (final u in utterances) {
    starts.add(next);
    next += u.words.length;
  }
  return starts;
}

/// A sentence's text as the sync key hashes it: used on pages where the two engines' words differ.
String syncText(String text) => unorm.nfkc(text).replaceAll(_space, ' ').trim();

/// The first 40 hex digits of the SHA-256 of `syncText`. Also names the audio file.
String syncKey(String text) => sha256Hex(syncText(text)).substring(0, 40);

class LibrarySentence {
  const LibrarySentence({
    required this.key,
    required this.lang,
    required this.ms,
    required this.from,
    required this.words,
  });

  final String key;
  final Lang lang;

  /// Length of the audio.
  final int ms;

  /// The sentence's first word in the page's words.
  final int from;

  /// Start and end of each of its words, in milliseconds.
  final List<(int, int)> words;

  Map<String, Object?> toJson() => {
    'key': key,
    'lang': lang.name,
    'ms': ms,
    'from': from,
    'words': [
      for (final (start, end) in words) [start, end],
    ],
  };
}

class PageIndex {
  const PageIndex({required this.wordCount, required this.wordsHash, required this.sentences});

  final int wordCount;
  final String wordsHash;
  final List<LibrarySentence> sentences;

  Map<String, Object?> toJson() => {
    'wordCount': wordCount,
    'wordsHash': wordsHash,
    'sentences': [for (final s in sentences) s.toJson()],
  };
}

class Manifest {
  const Manifest({
    required this.docId,
    required this.name,
    required this.pages,
    required this.sentences,
    required this.bytes,
    required this.updated,
  });

  /// SHA-256 of the PDF's bytes.
  final String docId;
  final String name;
  final int pages;
  final int sentences;
  final int bytes;
  final num updated;

  Map<String, Object?> toJson() => {
    'version': libraryVersion,
    'docId': docId,
    'name': name,
    'pages': pages,
    'sentences': sentences,
    'bytes': bytes,
    'updated': updated,
  };
}

typedef SentencePlace = ({int page, int index, String key});

/// Where one device stopped reading. Each device writes only its own.
class DeviceState {
  const DeviceState({
    required this.device,
    required this.name,
    required this.updated,
    required this.page,
    required this.offset,
    required this.sentence,
  });

  final String device;
  final String name;
  final num updated;
  final int page;
  final double offset;
  final SentencePlace? sentence;

  Map<String, Object?> toJson() => {
    'device': device,
    'name': name,
    'updated': updated,
    'page': page,
    'offset': offset,
    'sentence': switch (sentence) {
      null => null,
      final s => {'page': s.page, 'index': s.index, 'key': s.key},
    },
  };
}

Map<String, Object?>? _record(Object? value) => value is Map<String, Object?> ? value : null;
bool _integer(Object? value, int min) =>
    value is num && value.isFinite && value == value.roundToDouble() && value >= min;
bool _finite(Object? value) => value is num && value.isFinite;
bool _name(Object? value, int max) => value is String && value.isNotEmpty && value.length <= max;

List<(int, int)>? _parseTimings(Object? value, num ms) {
  if (value is! List || value.isEmpty) return null;
  final out = <(int, int)>[];
  num previous = 0;
  for (final pair in value) {
    if (pair is! List || pair.length != 2) return null;
    final [start, end] = pair;
    if (!_finite(start) || !_finite(end)) return null;
    if ((start as num) < previous || (end as num) < start || end > ms) return null;
    previous = end;
    out.add((start.round(), end.round()));
  }
  return out;
}

LibrarySentence? _parseSentence(Object? value) {
  final input = _record(value);
  if (input == null) return null;
  final key = input['key'];
  final lang = Lang.values.where((l) => l.name == input['lang']).firstOrNull;
  final ms = input['ms'];
  final from = input['from'];
  if (key is! String || !_key.hasMatch(key)) return null;
  if (lang == null || !_finite(ms) || (ms as num) < 0 || !_integer(from, 0)) return null;
  final words = _parseTimings(input['words'], ms);
  if (words == null) return null;
  return LibrarySentence(key: key, lang: lang, ms: ms.round(), from: (from as num).toInt(), words: words);
}

/// Reads a page index, or null when it is not valid. The sentences must cover the page's words
/// exactly, in order, because the phone maps them onto its own words by index.
PageIndex? parsePageIndex(Object? value) {
  final input = _record(value);
  if (input == null || !_integer(input['wordCount'], 0)) return null;
  final hash = input['wordsHash'];
  final list = input['sentences'];
  if (hash is! String || !_sha256.hasMatch(hash) || list is! List) return null;
  final sentences = <LibrarySentence>[];
  var next = 0;
  for (final entry in list) {
    final sentence = _parseSentence(entry);
    if (sentence == null || sentence.from != next) return null;
    next += sentence.words.length;
    sentences.add(sentence);
  }
  final wordCount = (input['wordCount']! as num).toInt();
  if (next != wordCount) return null;
  return PageIndex(wordCount: wordCount, wordsHash: hash, sentences: sentences);
}

Manifest? parseManifest(Object? value) {
  final input = _record(value);
  if (input == null || input['version'] != libraryVersion) return null;
  final Object? docId = input['docId'], name = input['name'], updated = input['updated'];
  final Object? pages = input['pages'], sentences = input['sentences'], bytes = input['bytes'];
  if (docId is! String || !_sha256.hasMatch(docId) || !_name(name, 255)) return null;
  if (!_integer(pages, 1) || !_integer(sentences, 0) || !_integer(bytes, 0) || !_finite(updated)) return null;
  return Manifest(
    docId: docId,
    name: name! as String,
    pages: (pages! as num).toInt(),
    sentences: (sentences! as num).toInt(),
    bytes: (bytes! as num).toInt(),
    updated: updated! as num,
  );
}

/// Reads a device's state, as sent by the desktop or read from disk, or null when it is not valid.
DeviceState? parseDeviceState(Object? value) {
  final input = _record(value);
  if (input == null) return null;
  final Object? device = input['device'], name = input['name'], updated = input['updated'];
  final Object? page = input['page'], offset = input['offset'];
  if (device is! String || !_deviceId.hasMatch(device) || !_name(name, 64)) return null;
  if (!_finite(updated) || !_integer(page, 1)) return null;
  final sentence = _record(input['sentence']);
  final key = sentence?['key'];
  final valid =
      sentence != null &&
      _integer(sentence['page'], 1) &&
      _integer(sentence['index'], 0) &&
      key is String &&
      _key.hasMatch(key);
  return DeviceState(
    device: device,
    name: name! as String,
    updated: updated! as num,
    page: (page! as num).toInt(),
    offset: _finite(offset) ? (offset! as num).toDouble().clamp(0, 0.999) : 0,
    sentence: valid
        ? (page: (sentence['page']! as num).toInt(), index: (sentence['index']! as num).toInt(), key: key)
        : null,
  );
}

/// The state to offer when a document opens: the newest, whichever device wrote it.
// shortcut: compares the devices' clocks, upgrade if a wrong pick is ever seen.
DeviceState? newestState(List<DeviceState> states) {
  DeviceState? best;
  for (final s in states) {
    if (best == null || s.updated > best.updated) best = s;
  }
  return best;
}

/// The place to offer when a document opens: the newest state, if another device wrote it after
/// this device last moved in the document. `ownUpdated` is when this device last did.
DeviceState? placeOffer(List<DeviceState> states, String device, num? ownUpdated) {
  final newest = newestState(states);
  if (newest == null || newest.device == device) return null;
  return ownUpdated == null || newest.updated > ownUpdated ? newest : null;
}
