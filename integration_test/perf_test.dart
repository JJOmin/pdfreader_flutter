// PLAN 18.1 and 18.2 on the phone: frame times while the voice reads, in the pages and in the speed
// reader, while flinging through the speed reader, and how long a switch of mode takes, in a long
// document made here (40 pages of about 3,000 characters each, read by the phone's voice). In profile
// mode, as debug frame times say nothing:
//   flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/perf_test.dart
// Prints PERF lines. Written to run on older code too, so it finds the mode switch by either name.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfreader/phone_voice.dart';
import 'package:pdfreader/reader_page.dart';

import 'pdfs.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('frame times while reading a long document', (tester) async {
    Future<void> wait(int ms) => tester.pump(Duration(milliseconds: ms));
    Future<void> waitFor(bool Function() done, {int seconds = 30}) async {
      for (var i = 0; i < seconds * 10 && !done(); i++) {
        await wait(100);
      }
      expect(done(), isTrue);
    }

    /// Frame times over `run`, as a line: frames, mean and 90th percentile build and raster, and the
    /// frames that missed the 16.7 ms of a 60 Hz screen.
    Future<void> measure(String name, Future<void> Function() run) async {
      final timings = <FrameTiming>[];
      void collect(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(collect);
      await run();
      await wait(500);
      SchedulerBinding.instance.removeTimingsCallback(collect);
      double ms(Duration d) => d.inMicroseconds / 1000;
      List<double> sorted(Iterable<double> v) => v.toList()..sort();
      final build = sorted(timings.map((t) => ms(t.buildDuration)));
      final raster = sorted(timings.map((t) => ms(t.rasterDuration)));
      String stats(List<double> v) => v.isEmpty
          ? '-'
          : 'mean ${(v.reduce((a, b) => a + b) / v.length).toStringAsFixed(1)} '
                'p90 ${v[(v.length * 0.9).floor().clamp(0, v.length - 1)].toStringAsFixed(1)} '
                'max ${v.last.toStringAsFixed(1)}';
      final missed = timings.where((t) => ms(t.buildDuration) > 16.7 || ms(t.rasterDuration) > 16.7).length;
      // ignore: avoid_print
      print(
        'PERF $name: ${timings.length} frames, build ${stats(build)}, raster ${stats(raster)}, missed $missed',
      );
    }

    Finder mode(String now) => find.byKey(Key(now)).evaluate().isNotEmpty
        ? find.byKey(Key(now))
        : find.byKey(const Key('toggle-reading'));

    await pdfrxFlutterInitialize();
    final voice = PlatformPhoneVoice();
    final langs = await voice.languages();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          name: 'long.pdf',
          data: longPdf(40),
          placeKey: 'test:perf',
          phoneVoice: voice,
          phoneLangs: langs,
        ),
      ),
    );
    final play = find.byKey(const Key('play'));
    await waitFor(() => play.evaluate().isNotEmpty && tester.widget<IconButton>(play).onPressed != null);
    final page = tester.state<ReaderPageState>(find.byType(ReaderPage));
    await wait(2000);

    await tester.tap(play);
    await waitFor(() => page.word >= 1);
    await measure('pages, reading aloud', () => wait(8000));

    final switchTimes = <int>[];
    Future<void> switchTo(String now) async {
      final watch = Stopwatch()..start();
      await tester.tap(mode(now));
      await tester.pump();
      await SchedulerBinding.instance.endOfFrame;
      switchTimes.add(watch.elapsedMilliseconds);
    }

    await switchTo('mode-reading');
    await wait(4000);
    await measure('speed reader, reading aloud', () => wait(8000));
    await tester.tap(play);
    await wait(500);

    await measure('speed reader, flinging', () async {
      for (var i = 0; i < 4; i++) {
        await tester.flingFrom(const Offset(180, 600), const Offset(0, -1500), 4000);
        await wait(1200);
        await tester.flingFrom(const Offset(180, 300), const Offset(0, 1000), 3000);
        await wait(1200);
      }
    });

    for (var i = 0; i < 3; i++) {
      await switchTo('mode-pages');
      await wait(800);
      await switchTo('mode-reading');
      await wait(800);
    }
    // ignore: avoid_print
    print('PERF mode switches, ms to the next frame: $switchTimes');
  });
}
