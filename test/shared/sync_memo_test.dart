import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/sync_memo.dart';
import 'package:pdfreader/shared/sync_store.dart';

void main() {
  final docId = '3' * 64;

  test('goes round trip through JSON', () {
    final memo = SyncMemo()
      ..own = {docId: const JournalDoc(manifest: 1, notes: 2, state: 3)}
      ..synced = {docId: const SyncedHashes(notes: 'aa', state: 'bb')};
    memo.seen['d' * 32] = SeenJournal(
      '"e1"',
      Journal(device: 'd' * 32, name: 'Mac', updated: 4, docs: {docId: const JournalDoc(notes: 9)}),
    );
    final back = parseMemo(jsonDecode(jsonEncode(memo.toJson())));
    expect(jsonEncode(back.toJson()), jsonEncode(memo.toJson()));
    expect(back.seen['d' * 32]!.etag, '"e1"');
    expect(back.own[docId], const JournalDoc(manifest: 1, notes: 2, state: 3));
  });

  test('forgets what is damaged, which only means the next sync walks everything', () {
    for (final bad in [
      null,
      5,
      <String, Object?>{'seen': 5, 'own': [], 'synced': 'x'},
    ]) {
      final memo = parseMemo(bad);
      expect(memo.seen, isEmpty);
      expect(memo.own, isEmpty);
      expect(memo.synced, isEmpty);
    }
    // A journal filed under another device's name is not kept.
    final liar = SyncMemo()
      ..seen['e' * 32] = SeenJournal('', Journal(device: 'd' * 32, name: '', updated: 0, docs: const {}));
    expect(parseMemo(jsonDecode(jsonEncode(liar.toJson()))).seen, isEmpty);
  });
}
