// The timing of Wi-Fi sync (PLAN 7.7) with a clock the test moves, a stand-in for the announcements,
// and stand-ins for the desktop's answers.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/desktop_link.dart';
import 'package:pdfreader/wifi_sync.dart';

import 'fake_timers.dart';

const mac = PairedDesktop(name: 'Mac', host: '10.0.0.5', port: 47613, fingerprint: 'f', token: 't');

void main() {
  late FakeTimers timers;
  late StreamController<FoundDesktop> heard;
  late WifiSync wifi;
  late List<String> calls;
  late Changes? Function(int since) answer;
  late bool reachable;

  Future<void> settle() => timers.advance(0);
  void announce({String host = '10.0.0.5'}) => heard.add((name: 'Mac', host: host, port: 47613));

  setUp(() {
    timers = FakeTimers();
    heard = StreamController.broadcast();
    calls = [];
    reachable = true;
    var clock = 100;
    answer = (since) => (now: ++clock, docs: since == 0 ? {'a'} : <String>{});
    wifi = WifiSync(
      desktops: () => [mac],
      timers: timers,
      discover: () => heard.stream,
      changes: (desktop, since) async {
        calls.add('changes $since ${desktop.host}');
        if (!reachable) throw const DesktopException('unreachable');
        return answer(since);
      },
      sync: (desktop) async {
        calls.add('sync');
        return const SyncResult(1, 0, 0);
      },
    );
    wifi.start();
  });
  tearDown(() async {
    wifi.stop();
    await heard.close();
  });

  test('syncs as soon as a paired computer is heard, then asks every 5 seconds', () async {
    announce();
    await settle();
    expect(calls, ['changes 0 10.0.0.5', 'sync']);
    expect(wifi.connected, ['Mac']);
    calls.clear();
    await timers.advance(4);
    expect(calls, isEmpty);
    await timers.advance(1);
    expect(calls, ['changes 101 10.0.0.5']);
    await timers.advance(5);
    expect(calls, ['changes 101 10.0.0.5', 'changes 102 10.0.0.5']);
  });

  test('syncs when the computer says something changed, and asks from its own time', () async {
    announce();
    await settle();
    calls.clear();
    answer = (since) => (now: 500, docs: {'b'});
    await timers.advance(5);
    expect(calls, ['changes 101 10.0.0.5', 'sync']);
    answer = (since) => (now: 600, docs: <String>{});
    calls.clear();
    await timers.advance(5);
    expect(calls, ['changes 500 10.0.0.5']);
  });

  test('sends this phone’s change at the next poll', () async {
    announce();
    await settle();
    calls.clear();
    wifi.ownChanged();
    await timers.advance(5);
    expect(calls, ['changes 101 10.0.0.5', 'sync']);
  });

  test('ignores a computer it is not paired with, and announcements while connected', () async {
    heard.add((name: 'Stranger', host: '10.0.0.9', port: 47613));
    await settle();
    expect(calls, isEmpty);
    announce();
    await settle();
    announce(host: '10.0.0.6');
    await settle();
    expect(calls, ['changes 0 10.0.0.5', 'sync']);
    calls.clear();
    // The new address is used from then on.
    await timers.advance(5);
    expect(calls, ['changes 101 10.0.0.6']);
  });

  test('lets a computer that went away go, and syncs again at once when it is heard', () async {
    announce();
    await settle();
    reachable = false;
    await timers.advance(5);
    expect(wifi.connected, isEmpty);
    reachable = true;
    calls.clear();
    announce();
    await settle();
    expect(calls, ['changes 0 10.0.0.5', 'sync']);
  });

  test('tries a computer it cannot reach again after 30 seconds, not at each announcement', () async {
    reachable = false;
    announce();
    await settle();
    calls.clear();
    for (var i = 0; i < 10; i++) {
      await timers.advance(2);
      announce();
      await settle();
    }
    expect(calls, isEmpty);
    await timers.advance(10);
    announce();
    await settle();
    expect(calls, ['changes 0 10.0.0.5']);
  });

  test('syncs a computer of protocol 1 when heard, at most every 30 seconds, without polling', () async {
    answer = (since) => null;
    announce();
    await settle();
    expect(calls, ['changes 0 10.0.0.5', 'sync']);
    calls.clear();
    await timers.advance(10);
    announce();
    await settle();
    expect(calls, ['changes 0 10.0.0.5']);
    await timers.advance(30);
    calls.clear();
    announce();
    await settle();
    expect(calls, ['changes 0 10.0.0.5', 'sync']);
  });

  test('stops listening and polling in the background', () async {
    announce();
    await settle();
    wifi.stop();
    calls.clear();
    await timers.advance(60);
    expect(calls, isEmpty);
    expect(wifi.connected, isEmpty);
  });
}
