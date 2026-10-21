import 'dart:io';
import 'dart:typed_data';

import 'package:pdfreader/shared/sync_store.dart';

/// A store in memory, as the desktop's tests use, that can start with a folder written by the
/// desktop's own engine (test/golden/store-folder).
class MemoryStore implements SyncStore {
  MemoryStore([Map<String, Uint8List>? files]) : files = {...?files};

  final Map<String, Uint8List> files;
  final gets = <String>[];
  final puts = <String>[];

  /// Every file under `dir`, by its path relative to it, except the plain helper files of the fixture.
  static MemoryStore fromFolder(String dir) {
    final root = Directory(dir);
    final files = <String, Uint8List>{};
    for (final entity in root.listSync(recursive: true).whereType<File>()) {
      final path = entity.path.substring(root.path.length + 1).replaceAll(r'\', '/');
      if (path == 'key.txt' || path == 'doc.txt') continue;
      files[path] = entity.readAsBytesSync();
    }
    return MemoryStore(files);
  }

  @override
  Future<List<RemoteEntry>> list(String dir) async {
    final names = <String, RemoteEntry>{};
    final prefix = dir.isEmpty ? '' : '$dir/';
    for (final MapEntry(key: path, value: bytes) in files.entries) {
      if (!path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length).split('/');
      names[rest.first] = RemoteEntry(rest.first, folder: rest.length > 1, size: bytes.length);
    }
    return names.values.toList();
  }

  @override
  Future<Uint8List?> get(String path) async {
    gets.add(path);
    return files[path];
  }

  @override
  Future<void> put(String path, Uint8List bytes) async {
    puts.add(path);
    files[path] = bytes;
  }
}
