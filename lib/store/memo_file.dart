import 'dart:convert';
import 'dart:io';

import '../shared/sync_memo.dart';

/// Where the phone keeps its [SyncMemo] between runs of the app. A missing or damaged file reads as
/// an empty memo, which only means the next sync walks the whole store.
class MemoFile {
  MemoFile(this.file);

  final File file;

  Future<SyncMemo> load() async {
    try {
      return parseMemo(jsonDecode(await file.readAsString()));
    } on FileSystemException {
      return SyncMemo();
    } on FormatException {
      return SyncMemo();
    }
  }

  /// Written only after a sync finished, so a failed one is repeated from the same journals.
  Future<void> save(SyncMemo memo) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(memo.toJson()));
  }

  /// After a new account or key the memo describes another store.
  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }
}
