// Port of the desktop's src/shared/sync-state.ts: the four states of the sync icon, the same on both.
// What decides the state. Times are milliseconds since 1970, 0 for never.
class SyncFacts {
  const SyncFacts({
    required this.store,
    required this.busy,
    required this.changedAt,
    required this.syncedAt,
    required this.failed,
    this.phones = false,
    this.document = false,
    this.prepared = false,
  });

  /// Signed in to Nextcloud, with the sync key.
  final bool store;

  /// A computer is paired for Wi-Fi sync. The phone's icon does not use it yet (step 7.7).
  final bool phones;

  /// A sync is running.
  final bool busy;

  /// A document is open, and it is in the library.
  final bool document;
  final bool prepared;

  /// The last change the store should get: marks, or a place. Not a change that came from the store.
  final int changedAt;

  /// When the last successful store sync started.
  final int syncedAt;

  /// The last store sync failed.
  final bool failed;
}

/// off: nothing set up. pending: something is not on the devices yet. syncing. done.
enum SyncState { off, pending, syncing, done }

SyncState syncState(SyncFacts facts) {
  if (facts.busy) return SyncState.syncing;
  if (!facts.store && !facts.phones) return SyncState.off;
  if (facts.document && !facts.prepared) return SyncState.pending;
  if (facts.store && (facts.failed || facts.changedAt > facts.syncedAt)) return SyncState.pending;
  return SyncState.done;
}
