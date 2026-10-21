import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/highlight_runs.dart';

void main() {
  group('highlightRuns', () {
    test('is one plain run without highlights', () {
      expect(highlightRuns(10, const []), [(from: 0, to: 10, layer: null)]);
      expect(highlightRuns(0, const []), isEmpty);
    });

    test('cuts the text where highlights start and end', () {
      expect(highlightRuns(10, const [(from: 2, to: 5, layer: 0)]), [
        (from: 0, to: 2, layer: null),
        (from: 2, to: 5, layer: 0),
        (from: 5, to: 10, layer: null),
      ]);
    });

    test('lets the higher layer win where highlights overlap, as the word mark over the sentence', () {
      expect(
        highlightRuns(10, const [
          (from: 0, to: 10, layer: 0),
          (from: 3, to: 6, layer: 2),
          (from: 5, to: 8, layer: 1),
        ]),
        [
          (from: 0, to: 3, layer: 0),
          (from: 3, to: 6, layer: 2),
          (from: 6, to: 8, layer: 1),
          (from: 8, to: 10, layer: 0),
        ],
      );
    });

    test('clips highlights to the text and ignores empty ones', () {
      expect(
        highlightRuns(4, const [
          (from: -2, to: 2, layer: 1),
          (from: 3, to: 3, layer: 2),
          (from: 3, to: 9, layer: 0),
        ]),
        [(from: 0, to: 2, layer: 1), (from: 2, to: 3, layer: null), (from: 3, to: 4, layer: 0)],
      );
    });
  });
}
