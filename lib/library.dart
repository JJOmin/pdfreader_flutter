// The documents the desktop prepared, in the app's own storage, in the layout of desktop ADR 7
// section 2. For now they arrive over USB (tool/push_library.ps1); later by sync, step 5.4.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'shared/sync.dart';

class LibraryDocument {
  LibraryDocument(this.dir, this.manifest);

  final Directory dir;
  final Manifest manifest;
  final _indexes = <int, Future<PageIndex?>>{};

  File get pdf => File('${dir.path}/document.pdf');

  String audioPath(String key) => '${dir.path}/audio/$key.opus';

  /// The page's index, or null when the page has none or it is not valid.
  Future<PageIndex?> index(int page) => _indexes[page] ??= () async {
    try {
      return parsePageIndex(jsonDecode(await File('${dir.path}/pages/$page.json').readAsString()));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }();
}

class Library {
  Library(this.root);

  final Directory root;

  /// Android's app-specific external storage, which adb can write without root.
  static Future<Library> open() async {
    final base = await getExternalStorageDirectory() ?? await getApplicationSupportDirectory();
    return Library(Directory('${base.path}/library'));
  }

  /// Every complete document: the desktop writes the manifest last.
  Future<List<LibraryDocument>> documents() async {
    if (!await root.exists()) return const [];
    final out = <LibraryDocument>[];
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final document = await _read(entry);
      if (document != null) out.add(document);
    }
    out.sort((a, b) => a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));
    return out;
  }

  /// The library's copy of a PDF opened from elsewhere, found by the hash of its bytes.
  Future<LibraryDocument?> find(List<int> pdf) => _read(Directory('${root.path}/${sha256.convert(pdf)}'));

  Future<LibraryDocument?> _read(Directory dir) async {
    try {
      final manifest = parseManifest(jsonDecode(await File('${dir.path}/manifest.json').readAsString()));
      // A folder renamed by hand must not pass for another document.
      if (manifest == null || !dir.path.endsWith(manifest.docId)) return null;
      return LibraryDocument(dir, manifest);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
