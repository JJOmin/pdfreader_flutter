// Port of the desktop's tests/unit/align.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/align.dart';
import 'package:pdfreader/shared/types.dart';

List<double> starts(List<WordTiming> timings) => [
  for (final t in timings) double.parse(t.start.toStringAsFixed(2)),
];

void main() {
  phoneVoiceTimings();
  engineMarks();

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

// Phone only (PLAN 18.3): the phone's voice, timed by the engine's own marks where it gives them, else
// by an estimate that knows about pauses and numbers.
void phoneVoiceTimings() {
  group('timingsFromMarks', () {
    test('takes each word start from the engine mark that starts in it', () {
      final timings = timingsFromMarks(
        ['Hello', 'there', 'world'],
        'Hello there, world.',
        [(0, 0.05), (6, 0.4), (13, 0.9)],
        1.4,
      );
      expect(starts(timings), [0.05, 0.4, 0.9]);
      expect(timings.last.end, 1.4);
    });

    test('a mark on the space before a word belongs to that word, and the first mark wins', () {
      final timings = timingsFromMarks(['a', 'b'], 'a b', [(0, 0.0), (1, 0.3), (2, 0.5)], 1);
      expect(starts(timings), [0.0, 0.3]);
    });

    test('words without a mark are spread between their neighbours', () {
      final timings = timingsFromMarks(['one', 'two', 'three'], 'one two three', [(0, 0.0), (8, 1.0)], 1.5);
      expect(timings[1].start, greaterThan(0));
      expect(timings[1].start, lessThan(1.0));
      expect(starts(timings)[2], 1.0);
    });

    test('without marks it is the estimate', () {
      expect(
        starts(timingsFromMarks(['a', 'bb'], 'a, bb', const [], 2)),
        starts(estimateSpokenTimings(['a', 'bb'], 'a, bb', 2)),
      );
    });
  });

  group('estimateSpokenTimings', () {
    test('covers the whole duration in order', () {
      final timings = estimateSpokenTimings(['A', 'short', 'one.'], 'A short one.', 2);
      expect(timings.first.start, 0);
      expect(timings.last.end, 2);
      expect(starts(timings), orderedEquals(starts(timings)..sort()));
    });

    test('a pause after a comma or a full stop moves the next word later', () {
      final plain = estimateSpokenTimings(['one', 'two', 'six'], 'one two six', 3);
      final comma = estimateSpokenTimings(['one', 'two', 'six'], 'one, two six', 3);
      final stop = estimateSpokenTimings(['one', 'two', 'six'], 'one. two six', 3);
      expect(comma[1].start, greaterThan(plain[1].start));
      expect(stop[1].start, greaterThan(comma[1].start));
    });

    test('a number takes longer than its digits suggest', () {
      final timings = estimateSpokenTimings(['in', '1990', 'it'], 'in 1990 it', 3);
      final letters = estimateSpokenTimings(['in', 'abcd', 'it'], 'in abcd it', 3);
      expect(timings[1].end - timings[1].start, greaterThan(letters[1].end - letters[1].start));
    });
  });
}

// Phone only (PLAN 18.3): engines report a word as (start, end, frame), Samsung's as (frame, start,
// end); which it is shows in the numbers, as text offsets never pass the text's length.
void engineMarks() {
  group('marksFromRanges', () {
    test('reads the order Android documents: the text’s start and end, then the frame', () {
      expect(marksFromRanges([(0, 3, 0), (4, 7, 12000)], textLength: 10, rate: 24000), [(0, 0.0), (4, 0.5)]);
    });

    test('reads the order Samsung’s engine uses: the frame first', () {
      // Measured on the S20 FE: "Das ist ein …" at 24 kHz.
      expect(marksFromRanges([(0, 0, 3), (5280, 4, 7), (9600, 8, 11)], textLength: 30, rate: 24000), [
        (0, 0.0),
        (4, 0.22),
        (8, 0.4),
      ]);
    });

    test('gives nothing for numbers that fit neither order, or without the rate', () {
      expect(marksFromRanges([(50, 3, 70), (4, 90, 1)], textLength: 10, rate: 24000), isEmpty);
      expect(marksFromRanges([(0, 3, 0)], textLength: 10, rate: 0), isEmpty);
      expect(marksFromRanges(const [], textLength: 10, rate: 24000), isEmpty);
    });
  });
}
