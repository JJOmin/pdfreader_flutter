// Port of the desktop's tests/unit/sync-state.test.ts: the two icons must agree.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/sync_state.dart';

SyncFacts facts({
  bool store = true,
  bool phones = false,
  bool busy = false,
  bool document = true,
  bool prepared = true,
  int changedAt = 100,
  bool failed = false,
}) => SyncFacts(
  store: store,
  phones: phones,
  busy: busy,
  document: document,
  prepared: prepared,
  changedAt: changedAt,
  syncedAt: 200,
  failed: failed,
);

void main() {
  test('is off with neither a store nor a paired phone', () {
    expect(syncState(facts(store: false)), SyncState.off);
  });

  test('is syncing while a document is prepared or sent, even before anything is set up', () {
    expect(syncState(facts(busy: true)), SyncState.syncing);
    expect(syncState(facts(store: false, busy: true)), SyncState.syncing);
  });

  test('is pending while the open document is not on the devices', () {
    expect(syncState(facts(prepared: false)), SyncState.pending);
    expect(syncState(facts(store: false, phones: true, prepared: false)), SyncState.pending);
  });

  test('is pending after a change the store has not had, or a failed sync', () {
    expect(syncState(facts(changedAt: 300)), SyncState.pending);
    expect(syncState(facts(failed: true)), SyncState.pending);
  });

  test('is done when everything was sent, and for phones once the document is prepared', () {
    expect(syncState(facts()), SyncState.done);
    expect(syncState(facts(store: false, phones: true, changedAt: 300)), SyncState.done);
    expect(syncState(facts(document: false, prepared: false)), SyncState.done);
  });
}
