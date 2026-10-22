// When the phone syncs with the store on its own (desktop ADR 10 section 3, the phone's half of the
// desktop's src/shared/auto-sync.ts): at once when the app starts or comes to the front, every 30
// seconds while it is open, and 5 seconds after its own change. A place in a document is not such a
// change: it goes with the next poll, so that turning pages does not send a request each time. The
// clock and the timers are handed in, so a test can move them.
import 'dart:async';

const pollInterval = Duration(seconds: 30);
const changeDelay = Duration(seconds: 5);

typedef Cancel = void Function();

abstract interface class Timers {
  int now();
  Cancel after(Duration delay, void Function() action);
  Cancel every(Duration interval, void Function() action);
}

class AutoSync {
  AutoSync({required this.run, required this.timers});

  /// One sync. Errors are the caller's to report; this keeps going after them.
  final Future<void> Function() run;
  final Timers timers;

  var _enabled = true;
  var _started = false;
  Cancel? _poll;
  Cancel? _timer;
  Future<void>? _running;

  /// A change came while a sync was running, so that one cannot have carried it.
  var _again = false;

  /// Syncs now and then on the poll interval. Also what the app does when it comes to the front.
  void start() {
    _started = true;
    if (_enabled) _arm();
  }

  /// The app went to the background: nothing runs by itself, and what waits is sent by [flush].
  void stop() {
    _started = false;
    _disarm();
  }

  /// The user's setting: while off nothing runs by itself, and switching on syncs at once.
  void setEnabled(bool on) {
    _enabled = on;
    if (!_started) return;
    if (on) {
      _arm();
    } else {
      _disarm();
    }
  }

  /// A mark or a comment the store should get: it goes after 5 s, and a new one moves that back.
  void changed() {
    if (!_started || !_enabled) return;
    _timer?.call();
    _schedule(changeDelay);
  }

  /// Sends what waits. Resolves to whether there was anything.
  Future<bool> flush() async {
    if (_timer == null && !_again) return false;
    _timer?.call();
    _timer = null;
    await sync();
    return true;
  }

  /// A sync now, by itself or on request (pull to refresh asks the controller, which calls [run]).
  Future<void> sync() async {
    final running = _running;
    if (running != null) {
      _again = true;
      await running;
      return;
    }
    final done = _running = run()
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _running = null);
    await done;
    if (_again) {
      _again = false;
      await sync();
    }
  }

  void _arm() {
    _poll?.call();
    _poll = timers.every(pollInterval, () => unawaited(sync()));
    unawaited(sync());
  }

  void _disarm() {
    _poll?.call();
    _timer?.call();
    _poll = _timer = null;
  }

  void _schedule(Duration delay) {
    _timer = timers.after(delay, () {
      _timer = null;
      unawaited(sync());
    });
  }
}
