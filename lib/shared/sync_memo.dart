// What the phone remembers between syncs (the phone's side of desktop ADR 10 section 2): the
// journals of the other devices as last processed, its own journal so that a lost one can be written
// again, and the hash of what it last exchanged for each document, so that a local change is known
// without asking the store. Local to the phone; the desktop keeps the same in `sync-memo.json`.
import 'sync_store.dart';

class SeenJournal {
  const SeenJournal(this.etag, this.journal);

  final String etag;
  final Journal journal;
}

/// The hashes of the notes and of the place as last exchanged with the store.
class SyncedHashes {
  const SyncedHashes({this.notes, this.state});

  final String? notes;
  final String? state;
}

class SyncMemo {
  SyncMemo({Map<String, SeenJournal>? seen, Map<String, JournalDoc>? own, Map<String, SyncedHashes>? synced})
    : seen = seen ?? {},
      own = own ?? {},
      synced = synced ?? {};

  final Map<String, SeenJournal> seen;
  Map<String, JournalDoc> own;
  Map<String, SyncedHashes> synced;

  Map<String, Object?> toJson() => {
    'seen': {
      for (final MapEntry(:key, :value) in seen.entries)
        key: {'etag': value.etag, 'journal': value.journal.toJson()},
    },
    'own': {for (final MapEntry(:key, :value) in own.entries) key: value.toJson()},
    'synced': {
      for (final MapEntry(:key, :value) in synced.entries)
        key: {if (value.notes != null) 'notes': value.notes, if (value.state != null) 'state': value.state},
    },
  };
}

/// Reads the memo; anything damaged is forgotten, which only means the next sync walks everything.
SyncMemo parseMemo(Object? value) {
  final memo = SyncMemo();
  if (value is! Map<String, Object?>) return memo;
  final seen = value['seen'];
  if (seen is Map<String, Object?>) {
    for (final MapEntry(key: device, value: raw) in seen.entries) {
      if (raw is! Map<String, Object?>) continue;
      final journal = parseJournal(raw['journal']);
      if (journal != null && journal.device == device) {
        final etag = raw['etag'];
        memo.seen[device] = SeenJournal(etag is String ? etag : '', journal);
      }
    }
  }
  final own = parseJournal({'device': 'f' * 32, 'updated': 0, 'docs': value['own']});
  memo.own = own?.docs ?? {};
  final synced = value['synced'];
  if (synced is Map<String, Object?>) {
    for (final MapEntry(key: docId, value: raw) in synced.entries) {
      if (raw is! Map<String, Object?>) continue;
      final notes = raw['notes'], state = raw['state'];
      memo.synced[docId] = SyncedHashes(
        notes: notes is String ? notes : null,
        state: state is String ? state : null,
      );
    }
  }
  return memo;
}
