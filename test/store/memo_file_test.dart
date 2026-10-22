import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/sync_memo.dart';
import 'package:pdfreader/shared/sync_store.dart';
import 'package:pdfreader/store/memo_file.dart';

void main() {
  late Directory dir;
  late MemoFile memoFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('memo-');
    memoFile = MemoFile(File('${dir.path}/sub/sync-memo.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('keeps the memo for the next run, and clears it', () async {
    final memo = SyncMemo()..own = {'3' * 64: const JournalDoc(manifest: 4)};
    await memoFile.save(memo);
    expect((await memoFile.load()).own['3' * 64], const JournalDoc(manifest: 4));
    await memoFile.clear();
    expect((await memoFile.load()).own, isEmpty);
  });

  test('reads a missing or damaged file as an empty memo', () async {
    expect((await memoFile.load()).own, isEmpty);
    memoFile.file.createSync(recursive: true);
    memoFile.file.writeAsStringSync('{ not json');
    expect((await memoFile.load()).own, isEmpty);
  });
}
