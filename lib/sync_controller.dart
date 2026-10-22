// The phone's sync with the user's Nextcloud as the rest of the app sees it (PLAN 7.3): one place that
// owns the store engine and the memo, runs the syncs one at a time, schedules the automatic ones
// (`shared/auto_sync.dart`) and tells the sync icon its state.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'desktop_link.dart' show isMetered, phoneName;
import 'library.dart';
import 'notes_store.dart';
import 'shared/auto_sync.dart';
import 'shared/sync.dart' show Manifest;
import 'shared/sync_memo.dart';
import 'shared/sync_state.dart';
import 'store/cloud_accounts.dart';
import 'store/cloud_catalog.dart';
import 'store/memo_file.dart';
import 'store/store_sync.dart';

class RealTimers implements Timers {
  const RealTimers();

  @override
  int now() => DateTime.now().millisecondsSinceEpoch;

  @override
  Cancel after(Duration delay, void Function() action) {
    final timer = Timer(delay, action);
    return timer.cancel;
  }

  @override
  Cancel every(Duration interval, void Function() action) {
    final timer = Timer.periodic(interval, (_) => action());
    return timer.cancel;
  }
}

class SyncController extends ChangeNotifier {
  SyncController({
    required this.accounts,
    required this.library,
    required this.notes,
    required this.device,
    this.memoFile,
    this.catalogFile,
    this.timers = const RealTimers(),
    Future<String> Function()? name,
    Future<bool> Function()? metered,
  }) : _name = name ?? phoneName,
       _metered = metered ?? isMetered {
    _auto = AutoSync(timers: timers, run: () async => _runAutomatic());
  }

  final CloudAccounts accounts;
  final Library library;
  final NotesStore notes;

  /// This phone's id, which names its place in the store.
  final String device;

  /// What a sync remembers for the next one; without it the controller remembers only while it lives.
  final MemoFile? memoFile;

  /// The cloud's documents as the syncs learned them; without it only while the controller lives.
  final CloudCatalog? catalogFile;
  final Timers timers;
  final Future<bool> Function() _metered;
  final Future<String> Function() _name;
  late final AutoSync _auto;

  StoreSync? _engine;
  SyncMemo? _memo;
  Future<void> _queue = Future.value();

  var _signedIn = false;
  var _busy = false;
  var _failed = false;
  var _changedAt = 0;
  var _syncedAt = 0;

  /// How the last sync ended, for the Sync screen; null until one has.
  String? lastError;
  SyncSummary? lastSummary;

  /// The documents the cloud holds, as far as the syncs know.
  List<Manifest> cloud = const [];

  /// Downloads the user started, by document id, with how far each is (null when not known yet).
  final downloading = <String, double?>{};

  /// Counts the syncs that finished, so that a screen can reload when one did.
  int syncs = 0;

  SyncState get state => syncState(
    SyncFacts(store: _signedIn, busy: _busy, changedAt: _changedAt, syncedAt: _syncedAt, failed: _failed),
  );

  /// The store engine, made once for the account and key that are set.
  Future<StoreSync> engine() async {
    final memo = _memo ??= await memoFile?.load() ?? SyncMemo();
    return _engine ??= StoreSync(
      await accounts.store(),
      await accounts.key(),
      library,
      notes,
      device,
      memo: memo,
      name: await _name(),
    );
  }

  /// A new account or key: the memo describes another store, so the next sync walks everything.
  Future<void> forget() async {
    _engine = null;
    _memo = null;
    cloud = const [];
    await memoFile?.clear();
    await catalogFile?.clear();
    await refreshStatus();
    notifyListeners();
  }

  /// Reads the catalog the last run left, so the library lists the cloud before the first sync ends.
  Future<void> loadCatalog() async {
    final loaded = await catalogFile?.load();
    if (loaded != null && loaded.isNotEmpty && cloud.isEmpty) {
      cloud = loaded;
      notifyListeners();
    }
  }

  /// Downloads a document on the user's tap: always, whatever the network.
  Future<void> download(Manifest manifest) => exclusive(() async {
    downloading[manifest.docId] = null;
    notifyListeners();
    try {
      final engine = await this.engine();
      await engine.download(CloudDocument(manifest), (p) {
        downloading[manifest.docId] = p.total == 0 ? null : p.done / p.total;
        notifyListeners();
      });
      syncs++;
      lastSummary = null;
    } finally {
      downloading.remove(manifest.docId);
      notifyListeners();
    }
  });

  /// Takes a document off the phone. It stays in the cloud, and the library lists it as such.
  Future<void> removeFromPhone(LibraryDocument document) async {
    await exclusive(() => library.remove(document));
    syncs++;
    notifyListeners();
  }

  /// Runs something that uses the engine after whatever runs now: two syncs, or a download and a
  /// sync, must not write the same document at once.
  Future<T> exclusive<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> refreshStatus() async {
    final status = await accounts.status();
    final signedIn = status.backend != CloudBackend.none && status.hasKey;
    if (signedIn != _signedIn) {
      _signedIn = signedIn;
      notifyListeners();
    }
  }

  /// A sync now. [full] walks the whole store (pull to refresh); otherwise the journals say what to
  /// fetch. Null when nothing is signed in. Throws what failed, after the icon has said so.
  Future<SyncSummary?> sync({
    bool full = false,
    bool allowDownloads = true,
    void Function(DownloadProgress)? progress,
  }) => exclusive(() async {
    await refreshStatus();
    if (!_signedIn) return null;
    final started = timers.now();
    _busy = true;
    notifyListeners();
    try {
      final engine = await this.engine();
      final summary = await engine.sync(progress ?? (_) {}, full: full, allowDownloads: allowDownloads);
      cloud = await _catalog(summary);
      // Only after it finished, so a failed one is repeated from the same journals.
      await memoFile?.save(_memo!);
      _syncedAt = started;
      _failed = false;
      lastError = null;
      lastSummary = summary;
      syncs++;
      return summary;
    } catch (error) {
      _failed = true;
      lastError = '$error';
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  });

  /// Remembers what the sync learned of the cloud, and returns the whole list.
  Future<List<Manifest>> _catalog(SyncSummary summary) async {
    final file = catalogFile;
    if (file != null) return file.update(summary.cloud, complete: summary.cloudComplete);
    return [
      if (!summary.cloudComplete)
        for (final m in cloud)
          if (!summary.cloud.any((n) => n.docId == m.docId)) m,
      ...summary.cloud,
    ];
  }

  Future<void> _runAutomatic() async {
    try {
      // What the phone starts on its own waits for a network that is not metered.
      await sync(allowDownloads: !await _metered());
    } catch (_) {
      // The icon shows it, and the Sync screen says why.
    }
  }

  /// This phone changed something the store should get. A mark or comment goes after 5 seconds; a
  /// place [place] goes with the next poll.
  void ownChanged({bool place = false}) {
    _changedAt = timers.now();
    notifyListeners();
    if (!place) _auto.changed();
  }

  /// The app is in front: sync now and every 30 seconds.
  void resume() {
    unawaited(refreshStatus());
    _auto.start();
  }

  /// The app went to the background: nothing runs by itself. A change that waits is sent first.
  Future<void> pause() async {
    await _auto.flush();
    _auto.stop();
  }

  @override
  void dispose() {
    _auto.stop();
    super.dispose();
  }
}
