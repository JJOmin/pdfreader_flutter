// PDFs opened from Files or another app (PLAN 18.10), copied into the app's own storage so that Home
// can open them again at their place. The list is `kept.json`, the copies `kept/<sha256>.pdf`.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'shared/kept_documents.dart';

class KeptStore extends ChangeNotifier {
  KeptStore._(this._dir, this._list);

  /// Kept nowhere: for widget tests.
  KeptStore.inMemory() : this._(null, const []);

  final Directory? _dir;
  List<KeptDocument> _list;
  final _memory = <String, Uint8List>{};

  List<KeptDocument> get list => _list;

  static Future<KeptStore> open(Directory support) async {
    try {
      return KeptStore._(
        support,
        parseKept(jsonDecode(await File('${support.path}/kept.json').readAsString())),
      );
    } on FileSystemException {
      return KeptStore._(support, const []);
    } on FormatException {
      return KeptStore._(support, const []);
    }
  }

  File _copy(String id) => File('${_dir!.path}/kept/$id.pdf');

  /// Keeps a PDF the user opened, newest first, and lets go of the copies that fell off the list.
  /// Returns its id, the hash of its bytes.
  Future<String> keep(String name, Uint8List data) async {
    final id = sha256.convert(data).toString();
    final result = keepOpened(_list, id, name, DateTime.now().millisecondsSinceEpoch);
    final dir = _dir;
    if (dir == null) {
      _memory[id] = data;
    } else {
      final copy = _copy(id);
      if (!await copy.exists()) {
        await copy.parent.create(recursive: true);
        final partial = File('${copy.path}.part');
        await partial.writeAsBytes(data, flush: true);
        await partial.rename(copy.path);
      }
      for (final gone in result.dropped) {
        await _delete(_copy(gone));
      }
    }
    for (final gone in result.dropped) {
      _memory.remove(gone);
    }
    _list = result.kept;
    await _write();
    notifyListeners();
    return id;
  }

  /// The kept copy's bytes, or null if it is gone.
  Future<Uint8List?> bytes(String id) async {
    if (_dir == null) return _memory[id];
    try {
      return await _copy(id).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Takes a PDF off the list and frees its copy.
  Future<void> remove(String id) async {
    _list = [
      for (final d in _list)
        if (d.id != id) d,
    ];
    _memory.remove(id);
    if (_dir != null) await _delete(_copy(id));
    await _write();
    notifyListeners();
  }

  Future<void> _write() async {
    final dir = _dir;
    if (dir == null) return;
    final file = File('${dir.path}/kept.json');
    final partial = File('${file.path}.part');
    await partial.writeAsString(jsonEncode(keptToJson(_list)), flush: true);
    await partial.rename(file.path);
  }

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
