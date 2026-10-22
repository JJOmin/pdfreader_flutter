// Wi-Fi sync that works like the cloud (desktop ADR 10 section 6, PLAN 7.7): while the app is open it
// listens for the paired computers' announcements, syncs with one as soon as it is heard, then asks it
// every 5 seconds what changed and syncs when something did, or when this phone changed something. A
// computer of protocol 1 has no changes request: it is synced when heard, at most every 30 seconds.
import 'dart:async';

import 'desktop_link.dart';
import 'shared/inbox.dart';
import 'shared/auto_sync.dart' show Cancel, Timers;

const wifiPoll = Duration(seconds: 5);
const _oldDesktopEvery = Duration(seconds: 30);

typedef Changes = ({int now, Set<String> docs});

class WifiSync {
  WifiSync({
    required this.desktops,
    required this.timers,
    required this.discover,
    required this.changes,
    required this.sync,
    this.onSynced,
    this.inbox,
    this.onOffers,
  });

  /// The paired computers, read each time one is heard: pairing can happen while this runs.
  final List<PairedDesktop> Function() desktops;
  final Timers timers;
  final Stream<FoundDesktop> Function() discover;
  final Future<Changes?> Function(PairedDesktop desktop, int since) changes;

  /// One sync with a computer, which keeps up to date only what is on the phone.
  final Future<SyncResult> Function(PairedDesktop desktop) sync;

  /// Told after each sync, so that the library can show what came.
  final void Function(PairedDesktop desktop, SyncResult result)? onSynced;

  /// "Send to phone": what a computer offers, asked at each poll, and who is told of it.
  final Future<List<Offer>> Function(PairedDesktop desktop)? inbox;
  final void Function(PairedDesktop desktop, List<Offer> offers)? onOffers;

  StreamSubscription<FoundDesktop>? _listening;
  final _connected = <String, _Link>{};
  final _lastOldSync = <String, int>{};

  /// When a computer was heard but could not be reached: it is tried again after 30 s, not at each
  /// announcement, as behind a VPN, where every attempt waits for its timeout.
  final _failedAt = <String, int>{};

  /// The computers being polled now, by name.
  Iterable<String> get connected => _connected.keys;

  void start() {
    _listening ??= discover().listen(_heard, onError: (Object _) {});
  }

  /// The app went to the background: no listening, no polling. The next start syncs again.
  void stop() {
    unawaited(_listening?.cancel());
    _listening = null;
    for (final link in _connected.values) {
      link.poll?.call();
    }
    _connected.clear();
  }

  /// This phone changed something: every connected computer gets it at the next poll.
  void ownChanged() {
    for (final link in _connected.values) {
      link.dirty = true;
    }
  }

  void _heard(FoundDesktop found) {
    PairedDesktop? paired;
    for (final d in desktops()) {
      if (d.name == found.name) paired = d.at(found.host, found.port);
    }
    if (paired == null) return;
    final failed = _failedAt[found.name];
    if (failed != null && timers.now() - failed < _oldDesktopEvery.inMilliseconds) return;
    final link = _connected[found.name];
    if (link != null) {
      // A home router may have given it a new address.
      link.desktop = paired;
      return;
    }
    unawaited(_connect(paired));
  }

  Future<void> _connect(PairedDesktop desktop) async {
    final link = _connected[desktop.name] = _Link(desktop);
    try {
      final first = await changes(desktop, 0);
      _failedAt.remove(desktop.name);
      if (first == null) {
        // Protocol 1: no polling, but each announcement could sync; once every 30 s is enough.
        _connected.remove(desktop.name);
        final last = _lastOldSync[desktop.name] ?? -_oldDesktopEvery.inMilliseconds;
        if (timers.now() - last < _oldDesktopEvery.inMilliseconds) return;
        _lastOldSync[desktop.name] = timers.now();
        await _sync(link);
        return;
      }
      await _sync(link);
      await _askInbox(link);
      link.since = first.now;
      if (_connected[desktop.name] != link) return;
      link.poll = timers.every(wifiPoll, () => unawaited(_poll(link)));
    } catch (_) {
      _failedAt[desktop.name] = timers.now();
      _drop(link);
    }
  }

  Future<void> _poll(_Link link) async {
    if (link.busy) return;
    link.busy = true;
    try {
      final answer = await changes(link.desktop, link.since);
      if (answer == null) return _drop(link);
      if (answer.docs.isNotEmpty || link.dirty) {
        link.dirty = false;
        await _sync(link);
      }
      link.since = answer.now;
      await _askInbox(link);
    } catch (_) {
      // Gone, or asleep: listen again, and sync at once when it is heard.
      _drop(link);
    } finally {
      link.busy = false;
    }
  }

  Future<void> _sync(_Link link) async {
    final result = await sync(link.desktop);
    onSynced?.call(link.desktop, result);
  }

  Future<void> _askInbox(_Link link) async {
    final ask = inbox;
    if (ask != null) onOffers?.call(link.desktop, await ask(link.desktop));
  }

  void _drop(_Link link) {
    link.poll?.call();
    if (_connected[link.desktop.name] == link) _connected.remove(link.desktop.name);
  }
}

class _Link {
  _Link(this.desktop);

  PairedDesktop desktop;
  int since = 0;
  bool dirty = false;
  bool busy = false;
  Cancel? poll;
}
