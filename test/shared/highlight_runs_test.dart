import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/highlight_runs.dart';

/// Runs as (from, to, ids): records that hold a list would compare by identity.
List<(int, int, String)> shape(List<HighlightRun> runs) => [
  for (final r in runs) (r.from, r.to, r.ids.join(',')),
];

void main() {
  group('highlightRuns', () {
    test('is one plain run without highlights', () {
      expect(shape(highlightRuns(10, const [])), [(0, 10, '')]);
      expect(highlightRuns(0, const []), isEmpty);
    });

    test('cuts the text where highlights start and end', () {
      expect(shape(highlightRuns(10, const [(from: 2, to: 5, id: 0)])), [
        (0, 2, ''),
        (2, 5, '0'),
        (5, 10, ''),
      ]);
    });

    test('lists every highlight covering a run, in order, so the caller can layer them', () {
      expect(
        shape(
          highlightRuns(10, const [
            (from: 0, to: 10, id: 0),
            (from: 3, to: 6, id: 2),
            (from: 5, to: 8, id: 1),
          ]),
        ),
        [(0, 3, '0'), (3, 5, '0,2'), (5, 6, '0,1,2'), (6, 8, '0,1'), (8, 10, '0')],
      );
    });

    test('joins neighbours that look the same, such as two highlights that touch', () {
      expect(shape(highlightRuns(6, const [(from: 0, to: 3, id: 4), (from: 3, to: 6, id: 4)])), [
        (0, 6, '4'),
      ]);
    });

    test('clips highlights to the text and ignores empty ones', () {
      expect(
        shape(
          highlightRuns(4, const [
            (from: -2, to: 2, id: 1),
            (from: 3, to: 3, id: 2),
            (from: 3, to: 9, id: 0),
          ]),
        ),
        [(0, 2, '1'), (2, 3, ''), (3, 4, '0')],
      );
    });
  });
}
