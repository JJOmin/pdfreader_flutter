// The marks and comments of each document, in the app's own storage, one file per PDF named by the
// hash of its bytes (the id the library uses), in the desktop's notes format (PLAN step 2.1,
// decided by the owner on 2026-10-21). Sync will send these files as they are.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'shared/notes.dart';

final _docId = RegExp(r'^[0-9a-f]{64}$');

class NotesStore {
  NotesStore(this.dir);

  final Directory dir;

  static Future<NotesStore> open() async {
    final support = await getApplicationSupportDirectory();
    return NotesStore(Directory('${support.path}/notes'));
  }

  File _file(String docId) {
    if (!_docId.hasMatch(docId)) throw ArgumentError.value(docId, 'docId', 'not a document hash');
    return File('${dir.path}/$docId.json');
  }

  /// The document's notes, empty when there are none or the file is not a notes file.
  Future<NotesFile> load(String docId) async {
    try {
      return parseNotes(jsonDecode(await _file(docId).readAsString())) ?? emptyNotes();
    } on FileSystemException {
      return emptyNotes();
    } on FormatException {
      // Left where it is: the next save replaces it, and the user can still look at it before.
      return emptyNotes();
    }
  }

  Future<void> save(String docId, NotesFile file) async {
    final target = _file(docId);
    await dir.create(recursive: true);
    // Written beside the file and renamed over it, so a stop in the middle loses nothing.
    final partial = File('${target.path}.part');
    await partial.writeAsString(encodeNotes(file), flush: true);
    await partial.rename(target.path);
  }
}
