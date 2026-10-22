import 'package:pdfreader/shared/auto_sync.dart';

class _FakeTimer {
  _FakeTimer(this.at, this.action, {this.period});

  int at;
  final void Function() action;
  final Duration? period;
  var cancelled = false;
}

/// A clock and timers that only move when the test says so.
class FakeTimers implements Timers {
  var _now = 1000000;
  final _timers = <_FakeTimer>[];

  @override
  int now() => _now;

  @override
  Cancel after(Duration delay, void Function() action) {
    final timer = _FakeTimer(_now + delay.inMilliseconds, action);
    _timers.add(timer);
    return () => timer.cancelled = true;
  }

  @override
  Cancel every(Duration interval, void Function() action) {
    final timer = _FakeTimer(_now + interval.inMilliseconds, action, period: interval);
    _timers.add(timer);
    return () => timer.cancelled = true;
  }

  Future<void> advance(int seconds) async {
    final end = _now + seconds * 1000;
    while (true) {
      _timers.removeWhere((t) => t.cancelled);
      final due = _timers.where((t) => t.at <= end).toList()..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final timer = due.first;
      _now = timer.at;
      if (timer.period == null) {
        _timers.remove(timer);
      } else {
        timer.at += timer.period!.inMilliseconds;
      }
      timer.action();
      await Future<void>.delayed(Duration.zero);
    }
    _now = end;
    await Future<void>.delayed(Duration.zero);
  }
}
