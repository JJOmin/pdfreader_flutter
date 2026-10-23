// Where the user was in each document, and the reading speed (PLAN step 4.1), kept in the app's
// own storage in the desktop's formats. For a prepared document the place is also written as
// this phone's state file in the library, which sync sends to the desktop (step 5.6).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'shared/home_lists.dart';
import 'shared/settings.dart';
import 'shared/sync.dart';

/// Changes come in runs while the user scrolls; one write a second is enough.
const _writeDelay = Duration(seconds: 1);

/// The phone as its state files name it.
typedef PhoneIdentity = ({String device, String name});

class Places {
  Places._(this._dir, this._store, this._settings, this.identity);

  final Directory _dir;
  final ProgressStore _store;
  Settings _settings;

  /// Null in widget tests, where there is no platform to name the phone.
  final PhoneIdentity? identity;
  Timer? _timer;

  /// Told after this phone's place in a prepared document was written, so that the sync can send it.
  void Function()? onStateWritten;
  final _pendingStates = <String, String>{};

  static Future<Places> open(PhoneIdentity? identity) async {
    final dir = await getApplicationSupportDirectory();
    Object? read(String name) {
      try {
        return jsonDecode(File('${dir.path}/$name').readAsStringSync());
      } on FileSystemException {
        return null;
      } on FormatException {
        return null;
      }
    }

    return Places._(
      dir,
      parseProgressStore(read('progress.json')),
      normalizeSettings(read('settings.json')),
      identity,
    );
  }

  double get speed => _settings.speed;

  set speed(double value) {
    _settings = normalizeSettings({..._settings.toJson(), 'speed': value});
    _schedule();
  }

  bool get stopAtReferences => _settings.stopAtReferences;

  set stopAtReferences(bool value) {
    _settings = normalizeSettings({..._settings.toJson(), 'stopAtReferences': value});
    _schedule();
  }

  ReadingSettings get reading => _settings.reading;

  set reading(ReadingSettings value) {
    _settings = normalizeSettings({..._settings.toJson(), 'reading': value.toJson()});
    _schedule();
  }

  ({Progress progress, num updated})? progress(String key) => _store.documents[key];

  /// When the place in each library document was last saved, by the document's id.
  Map<String, num> get lastRead => {
    for (final MapEntry(:key, :value) in _store.documents.entries) ?docIdOfPlace(key): value.updated,
  };

  /// Remembers the place in a document. `state` is this phone's state for a prepared document.
  void remember(String key, Progress progress, {LibraryDocument? prepared, String? sentenceKey}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    rememberProgress(_store, key, progress, now);
    final identity = this.identity;
    if (prepared != null && identity != null) {
      final sentence = progress.sentence;
      final state = DeviceState(
        device: identity.device,
        name: identity.name,
        updated: now,
        page: progress.page,
        offset: progress.offset,
        sentence: sentence != null && sentenceKey != null
            ? (page: sentence.page, index: sentence.index, key: sentenceKey)
            : null,
      );
      _pendingStates['${prepared.dir.path}/state/${identity.device}.json'] = jsonEncode(state.toJson());
    }
    _schedule();
  }

  void _schedule() => _timer ??= Timer(_writeDelay, () => unawaited(flush()));

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    await File('${_dir.path}/progress.json').writeAsString(jsonEncode(_store.toJson()));
    await File('${_dir.path}/settings.json').writeAsString(jsonEncode(_settings.toJson()));
    for (final MapEntry(key: path, value: json) in _pendingStates.entries.toList()) {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(json);
    }
    final wrote = _pendingStates.isNotEmpty;
    _pendingStates.clear();
    if (wrote) onStateWritten?.call();
  }
}

/// Every device's place in a prepared document, each from the file named after it.
Future<List<DeviceState>> libraryStates(LibraryDocument document) async {
  final dir = Directory('${document.dir.path}/state');
  if (!await dir.exists()) return const [];
  final states = <DeviceState>[];
  await for (final file in dir.list()) {
    if (file is! File) continue;
    try {
      final state = parseDeviceState(jsonDecode(await file.readAsString()));
      if (state != null && file.uri.pathSegments.last == '${state.device}.json') states.add(state);
    } on FormatException {
      // A file that is not ours is left out.
    }
  }
  return states;
}
