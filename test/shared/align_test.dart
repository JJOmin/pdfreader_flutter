// Port of the desktop's tests/unit/align.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/align.dart';
import 'package:pdfreader/shared/types.dart';

List<double> starts(List<WordTiming> timings) => [
  for (final t in timings) double.parse(t.start.toStringAsFixed(2)),
];

void main() {
  group('estimateTimings', () {
    test('covers the whole duration in order, longer words taking longer', () {
      final timings = estimateTimings(['a', 'considerably', 'b'], 3);
      expect(timings[0].start, 0);
      expect(timings.last.end, 3);
      expect(timings[1].end - timings[1].start, greaterThan(timings[0].end - timings[0].start));
    });
  });

  group('alignWords', () {
    test('takes word starts from the recogniser tokens', () {
      final timings = alignWords(['The', 'proposed', 'method'], [' The', ' pro', 'posed', ' me', 'thod'], [
        0.1,
        0.3,
        0.5,
        0.9,
        1.1,
      ], 1.5);
      expect(starts(timings), [0.1, 0.3, 0.9]);
      expect(timings.last.end, 1.5);
    });

    test('tolerates a word the recogniser split in two', () {
      final timings = alignWords(
        ['benchmark', 'datasets', 'while'],
        [' benchmark', ' data', ' sets', ' while'],
        [0, 0.5, 0.8, 1.2],
        1.6,
      );
      expect(starts(timings), [0, 0.5, 1.2]);
    });

    test('interpolates words the recogniser heard differently', () {
      final timings = alignWords(
        ['in', '2020', 'we', 'found'],
        [' in', ' twenty', ' twenty', ' we', ' found'],
        [0, 0.2, 0.5, 1.0, 1.2],
        1.6,
      );
      expect(timings[0].start, 0);
      expect(timings[1].start, greaterThan(0));
      expect(timings[1].start, lessThan(1.0));
      expect(starts(timings).sublist(2), [1.0, 1.2]);
    });

    test('never goes backwards and survives empty recogniser output', () {
      final timings = alignWords(['one', 'two', 'three'], [], [], 2);
      expect(timings, hasLength(3));
      var prev = 0.0;
      for (final t in timings) {
        expect(t.start, greaterThanOrEqualTo(prev));
        prev = t.start;
      }
    });
  });
}
