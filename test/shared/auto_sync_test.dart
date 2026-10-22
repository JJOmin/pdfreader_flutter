// The timing of the phone's automatic sync (PLAN 7.3), with a clock the test moves.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/auto_sync.dart';

import '../fake_timers.dart';

void main() {
  late FakeTimers timers;
  late AutoSync auto;
  late List<int> runs;
  Future<void>? slow;

  setUp(() {
    timers = FakeTimers();
    runs = [];
    slow = null;
    auto = AutoSync(
      timers: timers,
      run: () async {
        runs.add(timers.now());
        await slow;
      },
    );
  });

  test('syncs at once on start, then every 30 seconds', () async {
    auto.start();
    await timers.advance(0);
    expect(runs, hasLength(1));
    await timers.advance(29);
    expect(runs, hasLength(1));
    await timers.advance(1);
    expect(runs, hasLength(2));
    await timers.advance(30);
    expect(runs, hasLength(3));
  });

  test('sends 5 seconds after the last change, and a new change moves that back', () async {
    auto.start();
    await timers.advance(0);
    runs.clear();
    auto.changed();
    await timers.advance(3);
    auto.changed();
    await timers.advance(4);
    expect(runs, isEmpty);
    await timers.advance(1);
    expect(runs, hasLength(1));
  });

  test('never runs two syncs at once, and runs again after one that a change interrupted', () async {
    final release = Completer<void>();
    slow = release.future;
    auto.start();
    await timers.advance(0);
    auto.changed();
    await timers.advance(5);
    expect(runs, hasLength(1));
    release.complete();
    slow = null;
    await timers.advance(0);
    expect(runs, hasLength(2));
  });

  test('keeps going after a sync that failed', () async {
    var fail = true;
    final failing = AutoSync(
      timers: timers,
      run: () {
        runs.add(timers.now());
        return fail ? Future<void>.error(StateError('offline')) : Future<void>.value();
      },
    );
    failing.start();
    await timers.advance(0);
    fail = false;
    await timers.advance(30);
    expect(runs, hasLength(2));
  });

  test('does nothing while stopped or switched off, and syncs when started or switched on', () async {
    auto.setEnabled(false);
    auto.start();
    auto.changed();
    await timers.advance(300);
    expect(runs, isEmpty);
    auto.setEnabled(true);
    await timers.advance(0);
    expect(runs, hasLength(1));
    auto.stop();
    runs.clear();
    await timers.advance(300);
    expect(runs, isEmpty);
    // The app came to the front again.
    auto.start();
    await timers.advance(0);
    expect(runs, hasLength(1));
  });

  test('sends what waits when asked, and says whether there was anything', () async {
    auto.start();
    await timers.advance(0);
    runs.clear();
    expect(await auto.flush(), isFalse);
    auto.changed();
    expect(await auto.flush(), isTrue);
    expect(runs, hasLength(1));
    await timers.advance(4);
    expect(runs, hasLength(1));
  });
}
